import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Чтение XLSX (Office Open XML): листы, общие строки, inline-строки, числа, булевы значения и даты по формату ячейки.
enum XLSXReader {
    static func read(_ data: Data) throws -> [ImportTable] {
        let archive: ZipArchive
        do {
            archive = try ZipArchive(data: data)
        } catch {
            throw ImportError.corruptArchive
        }
        guard archive.contains("xl/workbook.xml") else { throw ImportError.corruptArchive }

        let workbook = try parse(archive.data(for: "xl/workbook.xml"), WorkbookHandler())
        let relations = archive.contains("xl/_rels/workbook.xml.rels")
            ? try parse(archive.data(for: "xl/_rels/workbook.xml.rels"), RelationshipsHandler()).targets
            : [:]
        let sharedStrings = archive.contains("xl/sharedStrings.xml")
            ? try parse(archive.data(for: "xl/sharedStrings.xml"), SharedStringsHandler()).strings
            : []
        let dateStyles = archive.contains("xl/styles.xml")
            ? try parse(archive.data(for: "xl/styles.xml"), StylesHandler()).dateStyleIndexes
            : []

        var tables: [ImportTable] = []
        for sheet in workbook.sheets {
            guard let target = relations[sheet.relationID] else { continue }
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            guard archive.contains(path) else { continue }
            let handler = SheetHandler(sharedStrings: sharedStrings, dateStyles: dateStyles)
            let rows = try parse(archive.data(for: path), handler).rows
            let nonEmpty = rows.filter { row in row.contains { !$0.isEmpty } }
            if !nonEmpty.isEmpty {
                tables.append(ImportTable(name: sheet.name, rows: nonEmpty))
            }
        }
        guard !tables.isEmpty else { throw ImportError.noSheets }
        return tables
    }

    private static func parse<H: XMLParserDelegate>(_ data: Data, _ handler: H) throws -> H {
        let parser = XMLParser(data: data)
        parser.delegate = handler
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { throw ImportError.invalidXML }
        return handler
    }

    /// Номер колонки по ссылке ячейки: «C12» → 2.
    static func columnIndex(_ reference: String) -> Int? {
        var value = 0
        var seenLetter = false
        for scalar in reference.unicodeScalars {
            if scalar.value >= 65 && scalar.value <= 90 {
                value = value * 26 + Int(scalar.value - 64)
                seenLetter = true
            } else if scalar.value >= 97 && scalar.value <= 122 {
                value = value * 26 + Int(scalar.value - 96)
                seenLetter = true
            } else {
                break
            }
        }
        return seenLetter ? value - 1 : nil
    }

    /// Дата Excel (система 1900, с учётом несуществующего 29.02.1900) → «плавающая» дата, записанная в UTC.
    /// Часовой пояс пользователя применяется позже, при разборе значений.
    static func excelDate(_ serial: Decimal) -> Date? {
        let value = NSDecimalNumber(decimal: serial).doubleValue
        guard value > 0, value < 2_958_466 else { return nil }
        let days = value < 61 ? value + 1 : value
        // 30.12.1899 00:00 UTC + days
        let base = Date(timeIntervalSince1970: -2_209_161_600)
        return base.addingTimeInterval((days * 86_400).rounded())
    }
}

// MARK: - Обработчики XML

private final class WorkbookHandler: NSObject, XMLParserDelegate {
    struct Sheet {
        let name: String
        let relationID: String
    }

    var sheets: [Sheet] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        guard elementName == "sheet" || elementName.hasSuffix(":sheet") else { return }
        let relation = attributes["r:id"] ?? attributes.first { $0.key.hasSuffix(":id") }?.value ?? ""
        sheets.append(Sheet(name: attributes["name"] ?? "Sheet", relationID: relation))
    }
}

private final class RelationshipsHandler: NSObject, XMLParserDelegate {
    var targets: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        guard elementName == "Relationship", let id = attributes["Id"], let target = attributes["Target"] else { return }
        targets[id] = target
    }
}

private final class SharedStringsHandler: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var inItem = false
    private var inText = false
    private var inPhonetic = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "si":
            inItem = true
            current = ""
        case "t" where inItem && !inPhonetic:
            inText = true
        case "rPh":
            inPhonetic = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "t": inText = false
        case "rPh": inPhonetic = false
        case "si":
            strings.append(current)
            inItem = false
        default: break
        }
    }
}

private final class StylesHandler: NSObject, XMLParserDelegate {
    /// Индексы стилей ячеек (cellXfs), форматирующих дату.
    var dateStyleIndexes: Set<Int> = []
    private var customDateFormats: Set<Int> = []
    private var inCellXfs = false
    private var xfIndex = 0

    private static let builtInDateFormats: Set<Int> = Set(14...22).union(45...47)

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "numFmt":
            if let id = attributes["numFmtId"].flatMap(Int.init), let code = attributes["formatCode"], Self.looksLikeDate(code) {
                customDateFormats.insert(id)
            }
        case "cellXfs":
            inCellXfs = true
            xfIndex = 0
        case "xf" where inCellXfs:
            if let id = attributes["numFmtId"].flatMap(Int.init), Self.builtInDateFormats.contains(id) || customDateFormats.contains(id) {
                dateStyleIndexes.insert(xfIndex)
            }
            xfIndex += 1
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "cellXfs" { inCellXfs = false }
    }

    static func looksLikeDate(_ code: String) -> Bool {
        // Убираем текст в кавычках и в квадратных скобках ([Red], [$-419]).
        var cleaned = ""
        var inQuote = false
        var inBracket = false
        for char in code.lowercased() {
            if char == "\"" { inQuote.toggle(); continue }
            if char == "[" { inBracket = true; continue }
            if char == "]" { inBracket = false; continue }
            if !inQuote && !inBracket { cleaned.append(char) }
        }
        return cleaned.contains("y") || cleaned.contains("d") || (cleaned.contains("m") && cleaned.contains("h"))
    }
}

private final class SheetHandler: NSObject, XMLParserDelegate {
    var rows: [[CellValue]] = []
    private let sharedStrings: [String]
    private let dateStyles: Set<Int>

    private var currentRow: [Int: CellValue] = [:]
    private var rowIndex = -1
    private var cellColumn = 0
    private var nextColumn = 0
    private var cellType = ""
    private var cellStyle = 0
    private var buffer = ""
    private var capturing = false

    init(sharedStrings: [String], dateStyles: Set<Int>) {
        self.sharedStrings = sharedStrings
        self.dateStyles = dateStyles
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "row":
            currentRow = [:]
            nextColumn = 0
            if let r = attributes["r"].flatMap(Int.init) {
                // Пропущенные пустые строки сохраняем, чтобы номера строк совпадали с Excel.
                while rows.count < r - 1 { rows.append([]) }
                rowIndex = r - 1
            } else {
                rowIndex = rows.count
            }
        case "c":
            cellColumn = attributes["r"].flatMap(XLSXReader.columnIndex) ?? nextColumn
            nextColumn = cellColumn + 1
            cellType = attributes["t"] ?? "n"
            cellStyle = attributes["s"].flatMap(Int.init) ?? 0
            buffer = ""
        case "v", "t":
            capturing = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "v", "t":
            capturing = false
        case "c":
            currentRow[cellColumn] = value()
        case "row":
            let width = (currentRow.keys.max() ?? -1) + 1
            var row = [CellValue](repeating: .empty, count: width)
            for (column, value) in currentRow { row[column] = value }
            if rowIndex < rows.count {
                rows[rowIndex] = row
            } else {
                rows.append(row)
            }
        default:
            break
        }
    }

    private func value() -> CellValue {
        let raw = buffer
        switch cellType {
        case "s":
            guard let index = Int(raw.trimmingCharacters(in: .whitespaces)), index >= 0, index < sharedStrings.count else { return .empty }
            let text = sharedStrings[index]
            return text.isEmpty ? .empty : .text(text)
        case "inlineStr", "str":
            return raw.isEmpty ? .empty : .text(raw)
        case "b":
            return .bool(raw == "1")
        case "e":
            return .empty
        case "d":
            if let date = ISO8601DateFormatter().date(from: raw) { return .date(date) }
            return raw.isEmpty ? .empty : .text(raw)
        default:
            guard !raw.isEmpty, let number = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return .empty }
            if dateStyles.contains(cellStyle), let date = XLSXReader.excelDate(number) { return .date(date) }
            return .number(number)
        }
    }
}
