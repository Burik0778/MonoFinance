import Foundation
import MonoCore

/// Разбор значений из выписок: даты, суммы, валюты, направление операции.
public enum ValueParsers {
    // MARK: - Даты

    /// Дата из ячейки. Текст: «14.10.2026», «14.10.2026 18:45», «2026-10-14T18:45:00», «14/10/26», серийные числа Excel.
    /// Даты XLSX «плавающие» (записаны в UTC) — переводим их в календарь пользователя без сдвига дня.
    public static func date(_ cell: CellValue, time: CellValue? = nil, calendar: Calendar) -> Date? {
        var components: DateComponents?
        switch cell {
        case .date(let date):
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            components = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        case .number(let number):
            if number > 20_000, number < 80_000, let date = XLSXReader.excelDate(number) {
                return ValueParsers.date(.date(date), time: time, calendar: calendar)
            }
            return nil
        case .text(let text):
            components = dateComponents(from: text)
        default:
            return nil
        }
        guard var result = components else { return nil }
        if let time, let timeComponents = timeComponents(time) {
            result.hour = timeComponents.hour
            result.minute = timeComponents.minute
            result.second = timeComponents.second
        }
        if result.hour == nil || (result.hour == 0 && result.minute == 0 && (result.second ?? 0) == 0) {
            result.hour = 12
            result.minute = 0
            result.second = 0
        }
        guard let year = result.year, let month = result.month, let day = result.day,
              (1...12).contains(month), (1...31).contains(day), (1990...2100).contains(year) else { return nil }
        var normalized = DateComponents()
        normalized.year = year
        normalized.month = month
        normalized.day = day
        normalized.hour = result.hour
        normalized.minute = result.minute
        normalized.second = result.second
        guard let date = calendar.date(from: normalized), calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    static func dateComponents(from raw: String) -> DateComponents? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var groups: [String] = []
        var separators: [Character] = []
        var current = ""
        for char in text {
            if char.isASCII && char.isNumber {
                current.append(char)
            } else {
                if !current.isEmpty { groups.append(current); current = "" }
                separators.append(char)
            }
        }
        if !current.isEmpty { groups.append(current) }
        guard groups.count >= 3 else { return nil }
        let numbers = groups.compactMap { Int($0) }
        guard numbers.count == groups.count else { return nil }

        var components = DateComponents()
        if groups[0].count == 4 {
            components.year = numbers[0]
            components.month = numbers[1]
            components.day = numbers[2]
        } else {
            guard groups[2].count == 4 || groups[2].count == 2 else { return nil }
            var day = numbers[0]
            var month = numbers[1]
            // «10/14/2026» — американский порядок распознаём, только если иначе дата невозможна.
            if month > 12 && day <= 12 { swap(&day, &month) }
            components.day = day
            components.month = month
            components.year = groups[2].count == 2 ? 2000 + numbers[2] : numbers[2]
        }
        if numbers.count >= 5 {
            components.hour = numbers[3]
            components.minute = numbers[4]
            components.second = numbers.count >= 6 ? numbers[5] : 0
            guard (0...23).contains(numbers[3]), (0...59).contains(numbers[4]) else { return nil }
        }
        _ = separators
        return components
    }

    static func timeComponents(_ cell: CellValue) -> DateComponents? {
        switch cell {
        case .text(let text):
            let parts = text.split(whereSeparator: { !($0.isASCII && $0.isNumber) }).compactMap { Int($0) }
            guard parts.count >= 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
            return DateComponents(hour: parts[0], minute: parts[1], second: parts.count > 2 ? parts[2] : 0)
        case .number(let fraction):
            // Время в Excel — доля суток.
            let seconds = Int((NSDecimalNumber(decimal: fraction).doubleValue * 86_400).rounded())
            guard seconds >= 0, seconds < 86_400 else { return nil }
            return DateComponents(hour: seconds / 3600, minute: (seconds % 3600) / 60, second: seconds % 60)
        case .date(let date):
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            return utc.dateComponents([.hour, .minute, .second], from: date)
        default:
            return nil
        }
    }

    // MARK: - Суммы

    /// «1 234 567,89», «1,234,567.89», «1.234.567,89», «-85 000.00», «(1 000)», «−5 000 UZS», «+12.5».
    public static func amount(_ cell: CellValue) -> Decimal? {
        switch cell {
        case .number(let value): return value
        case .text(let text): return amount(text)
        default: return nil
        }
    }

    public static func amount(_ raw: String) -> Decimal? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var negative = false
        if text.hasPrefix("(") && text.hasSuffix(")") {
            negative = true
            text = String(text.dropFirst().dropLast())
        }
        var digits = ""
        var sawDigit = false
        var trailingMinus = false
        for char in text {
            if char.isASCII && char.isNumber {
                // Минус между цифрами — это не сумма («12-34»).
                if trailingMinus { return nil }
                digits.append(char)
                sawDigit = true
            } else if char == "," || char == "." {
                digits.append(char)
            } else if char == "-" || char == "\u{2212}" || char == "\u{2013}" {
                if sawDigit { trailingMinus = true } else { negative = true }
            } else if char == "+" || char.isWhitespace || char == "\u{00A0}" || char == "\u{202F}" || char == "'" {
                continue
            } else if char.isLetter || "$€₽£₸".contains(char) {
                continue
            } else {
                return nil
            }
        }
        guard sawDigit else { return nil }
        if trailingMinus { negative = true }
        let normalized = normalizeSeparators(digits)
        guard let value = DecimalMath.parse(normalized) else { return nil }
        return negative ? -value : value
    }

    static func normalizeSeparators(_ text: String) -> String {
        let dots = text.filter { $0 == "." }.count
        let commas = text.filter { $0 == "," }.count
        guard dots + commas > 0 else { return text }
        if dots > 0 && commas > 0 {
            // Последний разделитель — дробный.
            let lastIndex = text.lastIndex { $0 == "." || $0 == "," }!
            let integer = text[..<lastIndex].filter(\.isNumber)
            return integer + "." + text[text.index(after: lastIndex)...]
        }
        let separator: Character = dots > 0 ? "." : ","
        let parts = text.split(separator: separator, omittingEmptySubsequences: false)
        if parts.count > 2 {
            return text.filter(\.isNumber)
        }
        // Один разделитель: ровно три цифры после — разряды («1,234»), иначе дробь («85000,50», «12.5»).
        if parts.count == 2 && parts[1].count == 3 && parts[0].count <= 3 && !parts[0].isEmpty {
            return String(parts[0] + parts[1])
        }
        return parts[0] + "." + (parts.count > 1 ? parts[1] : "")
    }

    // MARK: - Валюта

    private static let numericCodes: [String: Currency] = ["860": .uzs, "840": .usd, "978": .eur, "643": .rub, "398": .kzt, "826": .gbp, "156": .cny]

    public static func currency(_ cell: CellValue) -> Currency? {
        let text = TextNormalizer.fold(cell.text).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if let code = numericCodes[text] { return code }
        if text.hasPrefix("сум") || text == "so'm" || text == "som" || text == "sum" || text == "uzs" { return .uzs }
        if text.hasPrefix("долл") || text == "usd" || text == "$" { return .usd }
        if text == "евро" || text == "eur" || text == "€" { return .eur }
        if text.hasPrefix("руб") || text == "rub" || text == "rur" { return .rub }
        let upper = Currency(text)
        return upper.isWellFormed ? upper : nil
    }

    // MARK: - Направление

    public enum Direction: String, Sendable, Codable {
        case outflow
        case inflow
    }

    public static func direction(_ cell: CellValue) -> Direction? {
        let text = TextNormalizer.fold(cell.text)
        guard !text.isEmpty else { return nil }
        let outflow = ["спис", "расход", "дебет", "debit", "chiqim", "покупк", "оплат", "withdraw", "payment", "purchase", "снятие", "-"]
        let inflow = ["зачисл", "приход", "кредит", "credit", "kirim", "пополн", "поступ", "deposit", "income", "возврат", "refund", "+"]
        if inflow.contains(where: { text.hasPrefix($0) }) { return .inflow }
        if outflow.contains(where: { text.hasPrefix($0) }) { return .outflow }
        return nil
    }
}
