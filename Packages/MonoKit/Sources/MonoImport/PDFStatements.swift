import Foundation
import MonoCore

/// Слово на странице PDF. Координаты страницы, ось y направлена вниз.
public struct PDFWord: Equatable, Sendable {
    public var text: String
    public var minX: Double
    public var maxX: Double
    public var minY: Double
    public var maxY: Double

    public init(text: String, minX: Double, maxX: Double, minY: Double, maxY: Double) {
        self.text = text
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
    }

    public var midY: Double { (minY + maxY) / 2 }
    public var height: Double { maxY - minY }
}

/// Текст страницы PDF словами с положением.
public struct PDFPageText: Equatable, Sendable {
    public var words: [PDFWord]

    public init(words: [PDFWord]) {
        self.words = words
    }

    /// Весь текст страницы одной строкой сверху вниз — для распознавания формата.
    public var plainText: String {
        PDFTableLayout.lines(words).map { $0.words.map(\.text).joined(separator: " ") }.joined(separator: " ")
    }
}

/// Восстановление таблицы выписки по положению слов на странице.
///
/// Порядок текста внутри PDF не гарантирован (iText пишет ячейки вперемешку, на стыке страниц описание операции
/// может оказаться после чужой суммы), поэтому строки собираются по координатам:
/// колонки — по заголовкам, записи — по вертикальным промежуткам в колонке с многострочным текстом.
public enum PDFTableLayout {
    public struct Line: Equatable, Sendable {
        public var y: Double
        public var words: [PDFWord]
    }

    /// Слова, сгруппированные в строки (по вертикали), внутри строки — слева направо.
    public static func lines(_ words: [PDFWord]) -> [Line] {
        guard !words.isEmpty else { return [] }
        let tolerance = max(0.3 * median(words.map(\.height)), 1)
        var result: [Line] = []
        for word in words.sorted(by: { ($0.midY, $0.minX) < ($1.midY, $1.minX) }) {
            if let last = result.last, abs(last.y - word.midY) < tolerance {
                result[result.count - 1].words.append(word)
            } else {
                result.append(Line(y: word.midY, words: [word]))
            }
        }
        return result.map { Line(y: $0.y, words: $0.words.sorted { $0.minX < $1.minX }) }
    }

    /// Строки таблицы.
    /// - Parameters:
    ///   - titles: первое слово заголовка каждой колонки слева направо (без учёта регистра).
    ///   - spine: колонка с многострочным текстом (детали операции), по ней видны границы записей.
    ///   - anchor: колонка, непустая только в первой части записи (дата): записи без неё — продолжение предыдущей с прошлой страницы.
    ///   - isAnchor: похоже ли содержимое колонки `anchor` на начало записи.
    public static func rows(pages: [PDFPageText], titles: [String], spine: Int, anchor: Int,
                            isAnchor: (String) -> Bool) -> [[String]] {
        let titles = titles.map(fold)
        var columns: [Double]?
        var result: [[String]] = []
        for page in pages {
            let lines = Self.lines(page.words)
            var top = -Double.infinity
            if let header = headerColumns(lines: lines, titles: titles, spine: spine, isAnchor: isAnchor) {
                columns = header.columns
                top = header.bottom
            }
            guard let columns else { continue }
            let column = { (x: Double) -> Int? in
                guard x >= columns[0] - 4 else { return nil }
                return columns.lastIndex { x >= $0 - 4 }
            }
            // Слова тела таблицы с колонкой и строкой.
            var body: [(word: PDFWord, y: Double, column: Int)] = []
            for line in lines where line.y > top {
                for word in line.words {
                    if let index = column(word.minX) { body.append((word, line.y, index)) }
                }
            }
            let spineLines = Array(Set(body.filter { $0.column == spine }.map(\.y))).sorted()
            guard let firstSpine = spineLines.first else { continue }
            let gaps = zip(spineLines, spineLines.dropFirst()).map { $1 - $0 }
            let limit = blockGap(gaps, height: median(body.map(\.word.height)))
            // Записи — группы строк колонки `spine` без больших промежутков.
            var blocks: [(top: Double, bottom: Double)] = [(firstSpine, firstSpine)]
            for y in spineLines.dropFirst() {
                if y - blocks[blocks.count - 1].bottom > limit {
                    blocks.append((y, y))
                } else {
                    blocks[blocks.count - 1].bottom = y
                }
            }
            var cells = Array(repeating: Array(repeating: [String](), count: columns.count), count: blocks.count)
            for item in body.sorted(by: { ($0.y, $0.word.minX) < ($1.y, $1.word.minX) }) {
                // Ближайшая запись: дата и сумма стоят по центру многострочной ячейки.
                var best: (index: Int, distance: Double)?
                for (index, block) in blocks.enumerated() {
                    let distance = item.y < block.top ? block.top - item.y : (item.y > block.bottom ? item.y - block.bottom : 0)
                    if best == nil || distance < best!.distance { best = (index, distance) }
                }
                guard let best, best.distance <= limit else { continue }
                cells[best.index][item.column].append(item.word.text)
            }
            var seenAnchor = false
            for blockCells in cells {
                let texts = blockCells.map { $0.joined(separator: " ") }
                if isAnchor(texts[anchor]) {
                    result.append(texts)
                    seenAnchor = true
                } else if !seenAnchor, !result.isEmpty {
                    // Начало страницы: окончание записи с предыдущей страницы.
                    let previous = result[result.count - 1]
                    result[result.count - 1] = zip(previous, texts).map { [$0, $1].filter { !$0.isEmpty }.joined(separator: " ") }
                }
                // Текст после последней записи страницы — подписи и колонтитулы.
            }
        }
        return result
    }

    /// Положение колонок по строке заголовка и нижняя граница заголовка.
    static func headerColumns(lines: [Line], titles: [String], spine: Int,
                              isAnchor: (String) -> Bool) -> (columns: [Double], bottom: Double)? {
        // Слова заголовка могут прийти слитно («Деталиоперации»), поэтому сравнение — по началу слова.
        let isTitle = { (word: PDFWord, title: String) -> Bool in fold(word.text).hasPrefix(title) }
        guard let headerLine = lines.first(where: { line in line.words.contains { isTitle($0, titles[spine]) } }),
              let spineX = headerLine.words.first(where: { isTitle($0, titles[spine]) })?.minX else { return nil }
        // Заголовок может занимать несколько строк («Дата и / время / операции»).
        var region: [Line] = []
        for line in lines where line.y >= headerLine.y - 30 {
            if line.y > headerLine.y + 30 || line.words.contains(where: { isAnchor($0.text) }) { break }
            // Текст в колонке деталей ниже строки заголовка — уже первая запись.
            if line.y > headerLine.y + 1, line.words.contains(where: { $0.minX >= spineX - 4 }) { break }
            region.append(line)
        }
        var columns: [Double] = []
        var used: [PDFWord] = []
        for title in titles {
            let candidates = region.flatMap(\.words)
                .filter { isTitle($0, title) && !used.contains($0) && $0.minX > (columns.last ?? -.infinity) + 5 }
                .sorted { $0.minX < $1.minX }
            guard let match = candidates.first else { return nil }
            columns.append(match.minX)
            used.append(match)
        }
        return (columns, (region.map(\.y).max() ?? headerLine.y) + 3)
    }

    /// Граница между записями: первый заметный скачок промежутков между строками (межстрочный интервал → отступ между записями).
    /// Если все промежутки одинаковые — по высоте шрифта.
    static func blockGap(_ gaps: [Double], height: Double) -> Double {
        let values = Array(Set(gaps.filter { $0 > 0.3 * height }.map { ($0 * 10).rounded() / 10 })).sorted()
        for (low, high) in zip(values, values.dropFirst()) {
            if low > 1.4 * height { break }
            if high / low > 1.2 { return (low * high).squareRoot() }
        }
        return 1.45 * height
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    static func fold(_ text: String) -> String {
        TextNormalizer.fold(text).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

/// Разбор PDF-выписки конкретного банка в таблицу единого вида (`BankPDFStatementAdapter`).
public protocol PDFStatementParser: Sendable {
    var bank: Bank { get }
    var displayName: String { get }
    /// Подходит ли разбор к выписке (по тексту первой страницы, приведённому к нижнему регистру).
    func matches(_ firstPage: String) -> Bool
    func rows(from pages: [PDFPageText]) -> [BankPDFRow]
}

/// Операция из PDF-выписки.
public struct BankPDFRow: Equatable, Sendable {
    /// Дата совершения операции (если указана в деталях), иначе дата проведения.
    public var date: String
    public var time: String
    /// Сумма со знаком: списание — отрицательная.
    public var amount: Decimal
    public var merchant: String
    public var description: String
    public var card: String
    public var details: String
}

/// Таблица единого вида для PDF-выписок банков.
public enum BankPDFTable {
    static let headers = ["Дата", "Время", "Сумма", "Продавец", "Описание", "Номер карты", "Название карты", "Детали операции", "Банк"]
    static let roles: [ColumnRole?] = [.date, .time, .amount, .merchant, .description, .card, .cardName, nil, nil]

    public static func table(rows: [BankPDFRow], parser: any PDFStatementParser) -> ImportTable {
        var result: [[CellValue]] = [headers.map { .text($0) }]
        for row in rows {
            let card = CardKey(row.card)
            let cardName = [parser.bank.displayName, card.flatMap { cardNetwork(bin: $0.bin) }].compactMap { $0 }.joined(separator: " ")
            result.append([
                .text(row.date), row.time.isEmpty ? .empty : .text(row.time), .number(row.amount),
                row.merchant.isEmpty ? .empty : .text(row.merchant), .text(row.description),
                row.card.isEmpty ? .empty : .text(row.card), .text(cardName), .text(row.details), .text(parser.displayName)
            ])
        }
        return ImportTable(name: parser.displayName, rows: result)
    }

    static func cardNetwork(bin: String) -> String? {
        if bin.hasPrefix("8600") || bin.hasPrefix("5614") { return "Uzcard" }
        if bin.hasPrefix("9860") { return "Humo" }
        if bin.hasPrefix("4") { return "Visa" }
        if bin.hasPrefix("5") || bin.hasPrefix("2") { return "Mastercard" }
        return nil
    }
}

/// Адаптер для таблиц, собранных из PDF-выписок (`BankPDFTable`): роли колонок известны заранее.
public struct BankPDFStatementAdapter: StatementAdapter {
    public let id: String
    public let bank: Bank?
    public let isVerified = true
    public let displayName: String?

    public init(parser: any PDFStatementParser) {
        id = "pdf-" + parser.bank.rawValue
        bank = parser.bank
        displayName = parser.displayName
    }

    public func matches(_ table: ImportTable) -> Bool {
        guard let header = table.rows.first, header.count == BankPDFTable.headers.count else { return false }
        return zip(header, BankPDFTable.headers).allSatisfy { $0.text == $1 }
            && table.cell(1, BankPDFTable.headers.count - 1).text == displayName
    }

    public func mapping(for table: ImportTable, calendar: Calendar) -> ColumnMapping {
        var roles: [Int: ColumnRole] = [:]
        for (index, role) in BankPDFTable.roles.enumerated() { if let role { roles[index] = role } }
        // Номер карты не найден ни в одной строке — счёт выбирается для всего файла.
        let cardColumn = BankPDFTable.roles.firstIndex(of: .card) ?? 0
        if !table.rows.dropFirst().contains(where: { !$0[safe: cardColumn].isEmpty }) {
            roles = roles.filter { $0.value != .card && $0.value != .cardName }
        }
        return ColumnMapping(headerRow: 0, roles: roles, signConvention: .negativeIsOutflow)
    }
}

/// Общие правила разбора текста PDF-выписок.
enum PDFStatementText {
    static let date = try! NSRegularExpression(pattern: #"^\d{2}\.\d{2}\.\d{4}"#)
    static let operationDate = try! NSRegularExpression(pattern: #"(?:^|[\s;])за (\d{2}\.\d{2}\.\d{4})"#)
    static let maskedCard = try! NSRegularExpression(pattern: #"\b\d{4,6}[*•xX]{2,}\d{2,4}\b;?"#)
    /// С этих слов в деталях начинаются служебные реквизиты: дальше в описании они не нужны.
    static let serviceTail = try! NSRegularExpression(
        pattern: #"(Номер карты|RRN|\bTID\b|\bMID\b|[TТ][EЕ]R\.ID|SLIP No|сог-но|UBCL|\bза \d{2}\.\d{2}\.\d{4}|\bза период|Host2Host|по сделке|\bDN \d)"#,
        options: [.caseInsensitive]
    )

    static func startsWithDate(_ text: String) -> Bool {
        date.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func firstGroup(_ regex: NSRegularExpression, in text: String) -> String? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// «-1 178 589,06» → −1178589.06.
    static func amount(_ text: String) -> Decimal? {
        let compact = text.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
        guard !compact.isEmpty, compact.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return Decimal(string: compact, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Первый номер карты в деталях в исходном виде.
    static func card(in text: String) -> String? {
        guard let match = maskedCard.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ";"))
    }

    /// Описание без номеров карт, RRN, терминалов и имён файлов процессинга.
    static func clean(_ text: String) -> String {
        var value = maskedCard.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        if let match = serviceTail.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           match.range.location > 0, let range = Range(match.range, in: value) {
            value = String(value[..<range.lowerBound])
        }
        value = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: " ;,.:"))
        for suffix in [" по", " в", " через МП"] where value.hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count))
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " ;,.:"))
    }

    /// Самая частая карта в выписке — карта счёта.
    static func mainCard(in details: [String]) -> String? {
        var counts: [String: (count: Int, text: String)] = [:]
        for text in details {
            guard let card = card(in: text), let key = CardKey(card)?.id else { continue }
            counts[key] = ((counts[key]?.count ?? 0) + 1, counts[key]?.text ?? card)
        }
        return counts.values.max { $0.count < $1.count }?.text
    }
}

/// Выписка АКБ «Капиталбанк» «по истории операций» (PDF из интернет-банка / приложения).
///
/// Колонки: «Дата проведения операции | Сумма (со знаком) | Детали операции». Настоящая дата операции — «за ДД.ММ.ГГГГ»
/// в деталях: дата проведения бывает на 1–3 дня позже. Формат проверен на реальной выписке (921 операция, 46 страниц).
public struct KapitalbankPDFParser: PDFStatementParser {
    public let bank = Bank.kapitalbank
    public let displayName = "Kapitalbank"

    public init() {}

    public func matches(_ firstPage: String) -> Bool {
        // Заголовок таблицы переносится по-разному, поэтому проверяем отдельные слова.
        (firstPage.contains("капиталбанк") || firstPage.contains("kapitalbank"))
            && firstPage.contains("детали") && firstPage.contains("проведения")
    }

    public func rows(from pages: [PDFPageText]) -> [BankPDFRow] {
        let table = PDFTableLayout.rows(pages: pages, titles: ["Дата", "Сумма", "Детали"], spine: 2, anchor: 0,
                                        isAnchor: PDFStatementText.startsWithDate)
        let mainCard = PDFStatementText.mainCard(in: table.map { $0[2] }) ?? ""
        return table.compactMap { (cells: [String]) -> BankPDFRow? in
            guard let amount = PDFStatementText.amount(cells[1]) else { return nil }
            let details = cells[2]
            let posted = String(cells[0].prefix(10))
            var description = details
            if description.hasPrefix("KBPC:") { description = String(description.dropFirst(5)) }
            description = PDFStatementText.clean(description)
            return BankPDFRow(
                date: PDFStatementText.firstGroup(PDFStatementText.operationDate, in: details) ?? posted,
                time: "",
                amount: amount,
                merchant: Self.merchant(in: description),
                description: description,
                card: PDFStatementText.card(in: details) ?? mainCard,
                details: details
            )
        }
    }

    /// Продавец: «Списание по операциям покупке OOO UZUM MARKET» → «OOO UZUM MARKET».
    static func merchant(in description: String) -> String {
        let prefixes = ["Списание по операциям покупке ", "Оплата за покупку товара в ", "Зачисление по опер переводам ",
                        "Списание по операциям ", "Списание по выд нал в "]
        for prefix in prefixes where description.hasPrefix(prefix) {
            return String(description.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }
}

/// Справка АО «Uzum Bank» об истории операций по счёту (PDF).
///
/// Колонки: «Дата и время операции | Дата документа | Номер документа | Сумма (без знака) | Детали операции».
/// Направление — по началу деталей («Оплата по карте», «Зачисление на VISA»). Время совершения операции указано
/// в конце деталей («2026-01-19 10.38.55»). Формат проверен на реальной выписке (126 операций, 15 страниц).
public struct UzumPDFParser: PDFStatementParser {
    public let bank = Bank.uzum
    public let displayName = "Uzum Bank"

    public init() {}

    public func matches(_ firstPage: String) -> Bool {
        firstPage.contains("uzum bank") && firstPage.contains("детали") && firstPage.contains("номер")
            && firstPage.contains("документа")
    }

    static let operationMoment = try! NSRegularExpression(
        pattern: #"(\d{4})-(\d{2})-\s*(\d{2})\s+(\d{2})\.(\d{2})\.(\d{2})"#
    )

    public func rows(from pages: [PDFPageText]) -> [BankPDFRow] {
        let table = PDFTableLayout.rows(pages: pages, titles: ["Дата", "Дата", "Номер", "Сумма", "Детали"], spine: 4, anchor: 0,
                                        isAnchor: PDFStatementText.startsWithDate)
        let mainCard = PDFStatementText.mainCard(in: table.map { $0[4] }) ?? ""
        return table.compactMap { (cells: [String]) -> BankPDFRow? in
            guard let magnitude = PDFStatementText.amount(cells[3]) else { return nil }
            let details = cells[4]
            var date = String(cells[0].prefix(10))
            var time = cells[0].split(separator: " ").dropFirst().first.map(String.init) ?? ""
            if let match = Self.operationMoment.firstMatch(in: details, range: NSRange(details.startIndex..., in: details)) {
                let part = { (index: Int) -> String in
                    Range(match.range(at: index), in: details).map { String(details[$0]) } ?? ""
                }
                date = "\(part(3)).\(part(2)).\(part(1))"
                let moment = "\(part(4)):\(part(5)):\(part(6))"
                // «00.00.00» — время не указано: оставляем время проведения.
                if moment != "00:00:00" { time = moment }
            }
            let description = PDFStatementText.clean(details)
            let signed = Self.isInflow(description) ? magnitude : -magnitude
            return BankPDFRow(date: date, time: time, amount: signed, merchant: "", description: description,
                              card: PDFStatementText.card(in: details) ?? mainCard, details: details)
        }
    }

    /// «Зачисление», «Поступление», «Возврат оплаты», «Кешбек» — поступления; остальное — списания.
    static func isInflow(_ description: String) -> Bool {
        let text = TextNormalizer.fold(description)
        return ["зачислен", "поступлен", "возврат", "кешбек", "кэшбек", "cashback"].contains { text.contains($0) }
    }
}

/// Распознавание PDF-выписок.
public enum PDFStatementReader {
    public static let parsers: [any PDFStatementParser] = [KapitalbankPDFParser(), UzumPDFParser()]

    /// Таблица выписки из текста страниц; `nil` — формат не распознан.
    public static func table(from pages: [PDFPageText]) -> ImportTable? {
        guard let first = pages.first else { return nil }
        let text = TextNormalizer.fold(first.plainText)
        guard let parser = parsers.first(where: { $0.matches(text) }) else { return nil }
        let rows = parser.rows(from: pages)
        guard !rows.isEmpty else { return nil }
        return BankPDFTable.table(rows: rows, parser: parser)
    }
}

private extension Array where Element == CellValue {
    subscript(safe index: Int) -> CellValue { indices.contains(index) ? self[index] : .empty }
}
