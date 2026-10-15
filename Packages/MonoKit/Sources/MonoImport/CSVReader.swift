import Foundation

/// Определение кодировки текстовых выписок: UTF-8 (с BOM и без), UTF-16, Windows-1251.
enum TextDecoder {
    static func decode(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(decoding: bytes.dropFirst(3), as: UTF8.self)
        }
        if bytes.starts(with: [0xFF, 0xFE]) { return String(data: Data(bytes.dropFirst(2)), encoding: .utf16LittleEndian) }
        if bytes.starts(with: [0xFE, 0xFF]) { return String(data: Data(bytes.dropFirst(2)), encoding: .utf16BigEndian) }
        if let utf8 = String(bytes: bytes, encoding: .utf8) { return utf8 }
        return decodeWindows1251(bytes)
    }

    /// Windows-1251 вручную: таблица верхней половины. Не зависит от поддержки кодировок в Foundation.
    static func decodeWindows1251(_ bytes: [UInt8]) -> String {
        var scalars = String.UnicodeScalarView()
        for byte in bytes {
            if byte < 0x80 {
                scalars.append(Unicode.Scalar(byte))
            } else if byte >= 0xC0 {
                scalars.append(Unicode.Scalar(UInt32(byte) - 0xC0 + 0x0410)!)
            } else if let mapped = cp1251High[byte], let scalar = Unicode.Scalar(mapped) {
                scalars.append(scalar)
            } else {
                scalars.append("\u{FFFD}")
            }
        }
        return String(scalars)
    }

    private static let cp1251High: [UInt8: UInt32] = [
        0x80: 0x0402, 0x81: 0x0403, 0x82: 0x201A, 0x83: 0x0453, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021,
        0x88: 0x20AC, 0x89: 0x2030, 0x8A: 0x0409, 0x8B: 0x2039, 0x8C: 0x040A, 0x8D: 0x040C, 0x8E: 0x040B, 0x8F: 0x040F,
        0x90: 0x0452, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
        0x99: 0x2122, 0x9A: 0x0459, 0x9B: 0x203A, 0x9C: 0x045A, 0x9D: 0x045C, 0x9E: 0x045B, 0x9F: 0x045F,
        0xA0: 0x00A0, 0xA1: 0x040E, 0xA2: 0x045E, 0xA3: 0x0408, 0xA4: 0x00A4, 0xA5: 0x0490, 0xA6: 0x00A6, 0xA7: 0x00A7,
        0xA8: 0x0401, 0xA9: 0x00A9, 0xAA: 0x0404, 0xAB: 0x00AB, 0xAC: 0x00AC, 0xAD: 0x00AD, 0xAE: 0x00AE, 0xAF: 0x0407,
        0xB0: 0x00B0, 0xB1: 0x00B1, 0xB2: 0x0406, 0xB3: 0x0456, 0xB4: 0x0491, 0xB5: 0x00B5, 0xB6: 0x00B6, 0xB7: 0x00B7,
        0xB8: 0x0451, 0xB9: 0x2116, 0xBA: 0x0454, 0xBB: 0x00BB, 0xBC: 0x0458, 0xBD: 0x0405, 0xBE: 0x0455, 0xBF: 0x0457
    ]
}

/// CSV по RFC 4180 с автоопределением разделителя.
enum CSVReader {
    static let candidates: [Character] = [";", ",", "\t", "|"]

    static func read(_ data: Data) throws -> ImportTable {
        guard !data.isEmpty else { throw ImportError.emptyFile }
        guard let text = TextDecoder.decode(data) else { throw ImportError.unreadableText }
        let delimiter = detectDelimiter(text)
        let rows = parse(text, delimiter: delimiter)
            .filter { row in row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
            .map { row in row.map { field -> CellValue in
                let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? .empty : .text(trimmed)
            } }
        guard !rows.isEmpty else { throw ImportError.emptyFile }
        return ImportTable(name: "CSV", rows: rows)
    }

    /// Разделитель, дающий наибольшее и самое стабильное число колонок в первых строках.
    static func detectDelimiter(_ text: String) -> Character {
        let sample = String(text.prefix(20_000))
        var best: (Character, Int, Int) = (",", 0, 0)
        for candidate in candidates {
            let rows = parse(sample, delimiter: candidate).prefix(30).filter { $0.count > 1 || !($0.first ?? "").isEmpty }
            let counts = rows.map(\.count).filter { $0 > 1 }
            guard !counts.isEmpty else { continue }
            var frequency: [Int: Int] = [:]
            for count in counts { frequency[count, default: 0] += 1 }
            guard let mode = frequency.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }) else { continue }
            if mode.value > best.1 || (mode.value == best.1 && mode.key > best.2) {
                best = (candidate, mode.value, mode.key)
            }
        }
        return best.0
    }

    static func parse(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = iterator.next()

        while let char = pending {
            pending = iterator.next()
            if inQuotes {
                if char == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
                continue
            }
            switch char {
            case "\"" where field.isEmpty:
                inQuotes = true
            case delimiter:
                row.append(field)
                field = ""
            case "\r\n", "\n", "\r":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            default:
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
