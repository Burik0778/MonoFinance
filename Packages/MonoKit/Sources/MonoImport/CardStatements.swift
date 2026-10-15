import Foundation
import MonoCore

/// Маскированный номер карты из выписки: «414084******7058», «414084*******058», «8600 •• 1234».
/// Сравнение — по BIN (первые цифры) и видимому хвосту: разные выписки маскируют разное число цифр.
public struct CardKey: Hashable, Codable, Sendable {
    public let bin: String
    public let tail: String

    public init?(_ text: String) {
        let characters = Array(text)
        var groups: [(digits: String, maskAfter: Int)] = []
        var index = 0
        while index < characters.count {
            guard characters[index].isASCII && characters[index].isNumber else { index += 1; continue }
            var digits = ""
            while index < characters.count, characters[index].isASCII, characters[index].isNumber {
                digits.append(characters[index])
                index += 1
            }
            var mask = 0
            var probe = index
            while probe < characters.count, "*•xX·. ".contains(characters[probe]) {
                if characters[probe] != " " { mask += 1 }
                probe += 1
            }
            groups.append((digits, mask))
            index = probe
        }
        // Полный номер (16–19 цифр подряд).
        if let full = groups.first(where: { (16...19).contains($0.digits.count) }) {
            bin = String(full.digits.prefix(6))
            tail = String(full.digits.suffix(4))
            return
        }
        // BIN, маска, хвост.
        for (offset, group) in groups.enumerated() where group.maskAfter >= 2 && (4...6).contains(group.digits.count) {
            guard offset + 1 < groups.count else { break }
            let next = groups[offset + 1].digits
            guard (2...4).contains(next.count) else { continue }
            bin = group.digits
            tail = next
            return
        }
        return nil
    }

    /// Устойчивый ключ для группировки строк и сохранения сопоставления.
    public var id: String { "\(bin)*\(tail)" }

    public var lastFour: String? { tail.count >= 4 ? String(tail.suffix(4)) : nil }

    /// Та же карта: совпадает BIN (если указан у обоих) и не меньше трёх последних цифр.
    public func matches(_ other: CardKey) -> Bool {
        let shortest = min(tail.count, other.tail.count)
        guard shortest >= 3, tail.suffix(shortest) == other.tail.suffix(shortest) else { return false }
        let binLength = min(bin.count, other.bin.count)
        return binLength >= 4 && bin.prefix(binLength) == other.bin.prefix(binLength)
    }
}

/// Карта, встретившаяся в выписке сразу по нескольким картам.
public struct StatementCard: Identifiable, Equatable, Sendable {
    /// Ключ группировки (`CardKey.id` или текст ячейки).
    public var id: String
    /// Номер в том виде, как он записан в файле.
    public var number: String
    /// Название карты из выписки («KapitalVisa», «Work»).
    public var name: String?
    public var rowCount: Int
    public var lastFour: String?

    public init(id: String, number: String, name: String?, rowCount: Int, lastFour: String?) {
        self.id = id
        self.number = number
        self.name = name
        self.rowCount = rowCount
        self.lastFour = lastFour
    }

    /// Ключ строки по тексту ячейки с номером карты.
    public static func key(for text: String) -> String {
        CardKey(text)?.id ?? TextNormalizer.fold(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Карты в таблице в порядке частоты.
    public static func cards(in table: ImportTable, mapping: ColumnMapping) -> [StatementCard] {
        guard let cardColumn = mapping.column(.card) else { return [] }
        let nameColumn = mapping.column(.cardName)
        var order: [String] = []
        var cards: [String: StatementCard] = [:]
        for row in mapping.firstDataRow..<table.rows.count {
            let text = table.cell(row, cardColumn).text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let key = key(for: text)
            if cards[key] == nil {
                order.append(key)
                let name = nameColumn.map { table.cell(row, $0).text.trimmingCharacters(in: .whitespacesAndNewlines) }
                cards[key] = StatementCard(id: key, number: text, name: (name?.isEmpty ?? true) ? nil : name,
                                           rowCount: 0, lastFour: CardKey(text)?.lastFour)
            }
            cards[key]?.rowCount += 1
        }
        return order.compactMap { cards[$0] }.sorted { $0.rowCount > $1.rowCount }
    }

    /// Подходящий счёт: по последним 4 цифрам, затем по названию банка в имени карты. Неоднозначно — `nil`.
    public func suggestedAccount(in accounts: [Account]) -> Account? {
        let active = accounts.filter { !$0.isArchived }
        if let lastFour {
            let byDigits = active.filter { $0.lastFour == lastFour }
            if byDigits.count == 1 { return byDigits[0] }
        }
        guard let name else { return nil }
        let folded = TextNormalizer.fold(name)
        let banks = Bank.allCases.filter { bank in bank.isBank && bank.mentionStems.contains { folded.contains($0) } }
        guard banks.count == 1 else { return nil }
        let candidates = active.filter { $0.bank == banks[0] && $0.kind != .cash }
        return candidates.count == 1 ? candidates[0] : nil
    }
}

/// Выписка Payme («Платежи» → экспорт): все карты в одном файле, сумма без знака, направление — в «Тип операции».
/// Формат проверен на реальной выписке (2 444 строки по трём картам, январь–октябрь 2026).
public struct PaymeStatementAdapter: StatementAdapter {
    public let id = "payme"
    public let bank: Bank? = nil
    public let isVerified = true
    public let displayName: String? = "Payme"

    public init() {}

    private static let roles: [String: ColumnRole] = [
        "дата платежа": .date,
        "время платежа": .time,
        "тип операции": .direction,
        "имя поставщика": .merchant,
        "сумма платежа": .amount,
        "категория": .category,
        "реквизиты платежа": .details,
        "номер карты": .card,
        "название карты": .cardName,
        "комментарий к платежу": .description,
        "состояние чека": .status
    ]

    private static let required: Set<String> = ["дата платежа", "тип операции", "сумма платежа", "номер карты", "состояние чека"]

    private func headerRow(in table: ImportTable) -> Int? {
        (0..<min(5, table.rows.count)).first { row in
            let headers = Set(table.rows[row].map { Self.normalize($0.text) })
            return Self.required.isSubset(of: headers)
        }
    }

    private static func normalize(_ text: String) -> String {
        TextNormalizer.fold(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func matches(_ table: ImportTable) -> Bool { headerRow(in: table) != nil }

    public func mapping(for table: ImportTable, calendar: Calendar) -> ColumnMapping {
        guard let header = headerRow(in: table) else { return ColumnDetector.suggestMapping(for: table, calendar: calendar) }
        var roles: [Int: ColumnRole] = [:]
        for (column, cell) in table.rows[header].enumerated() {
            if let role = Self.roles[Self.normalize(cell.text)] { roles[column] = role }
        }
        // Суммы положительные, направление задаёт «Тип операции» (Списание / Поступление).
        return ColumnMapping(headerRow: header, roles: roles, signConvention: .negativeIsOutflow)
    }
}
