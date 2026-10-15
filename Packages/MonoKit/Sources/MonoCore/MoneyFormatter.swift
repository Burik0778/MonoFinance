import Foundation

/// Составные части отформатированной суммы — для типографики, где целая часть,
/// дробная часть и символ валюты набираются разными стилями.
public struct MoneyParts: Equatable, Sendable {
    public var sign: String
    public var integerPart: String
    public var fractionPart: String?
    public var decimalSeparator: String
    public var symbol: String
    public var symbolLeading: Bool

    /// Полная строка: «−85 000 сум», «$1 250,50».
    public var formatted: String {
        var number = integerPart
        if let fractionPart { number += decimalSeparator + fractionPart }
        if symbolLeading {
            return sign + symbol + number
        }
        return sign + number + MoneyFormatter.nbsp + symbol
    }
}

/// Форматирование денег без зависимости от системной локали — результат одинаков на iOS и в тестах.
public struct MoneyFormatter: Sendable {
    public enum SignDisplay: Sendable {
        /// Минус только для отрицательных.
        case automatic
        /// «+» для положительных, «−» для отрицательных.
        case always
        /// Без знака (модуль).
        case never
    }

    public enum FractionDisplay: Sendable {
        /// Для UZS дробная часть показывается только если она не нулевая; для остальных — всегда.
        case automatic
        case always
        case never
    }

    /// Узкий неразрывный пробел — разделитель разрядов (ru/uz).
    public static let groupSeparatorNarrow = "\u{202F}"
    public static let nbsp = "\u{00A0}"
    /// Типографский минус.
    public static let minus = "\u{2212}"

    public var language: AppLanguage

    public init(language: AppLanguage = .ru) {
        self.language = language
    }

    public var groupSeparator: String { language == .en ? "," : Self.groupSeparatorNarrow }
    public var decimalSeparator: String { language == .en ? "." : "," }

    // MARK: Символы валют

    public func symbol(for currency: Currency) -> (text: String, leading: Bool) {
        switch currency.code {
        case "UZS":
            switch language {
            case .ru: return ("сум", false)
            case .uz: return ("so‘m", false)
            case .en: return ("UZS", false)
            }
        case "USD": return ("$", true)
        case "EUR": return ("€", language == .en)
        case "GBP": return ("£", true)
        case "RUB": return ("₽", false)
        case "KZT": return ("₸", false)
        case "TRY": return ("₺", language == .en)
        case "KRW": return ("₩", true)
        case "JPY": return ("¥", true)
        default: return (currency.code, false)
        }
    }

    // MARK: Полный формат

    public func parts(_ money: Money, sign: SignDisplay = .automatic, fraction: FractionDisplay = .automatic) -> MoneyParts {
        let digits = money.currency.minorUnitDigits
        let scale = UInt64(money.currency.minorUnitScale)
        let absolute = money.minorUnits.magnitude
        let integer = absolute / scale
        let remainder = absolute % scale

        var fractionText: String?
        if digits > 0 {
            let showFraction: Bool
            switch fraction {
            case .always: showFraction = true
            case .never: showFraction = false
            case .automatic: showFraction = money.currency == .uzs ? remainder != 0 : true
            }
            if showFraction {
                var text = String(remainder)
                while text.count < digits { text = "0" + text }
                fractionText = text
            }
        }

        let symbolInfo = symbol(for: money.currency)
        return MoneyParts(
            sign: signText(for: money.minorUnits, display: sign),
            integerPart: group(String(integer)),
            fractionPart: fractionText,
            decimalSeparator: decimalSeparator,
            symbol: symbolInfo.text,
            symbolLeading: symbolInfo.leading
        )
    }

    public func string(_ money: Money, sign: SignDisplay = .automatic, fraction: FractionDisplay = .automatic) -> String {
        parts(money, sign: sign, fraction: fraction).formatted
    }

    /// Число без символа валюты: «85 000», «1 250,50».
    public func number(_ money: Money, sign: SignDisplay = .automatic, fraction: FractionDisplay = .automatic) -> String {
        let p = parts(money, sign: sign, fraction: fraction)
        var text = p.sign + p.integerPart
        if let f = p.fractionPart { text += p.decimalSeparator + f }
        return text
    }

    // MARK: Компактный формат

    /// «1,25 млн сум», «850 тыс. сум», «$12,4 тыс.»; en: «1.25M UZS».
    public func compact(_ money: Money, sign: SignDisplay = .automatic) -> String {
        let value = money.majorValue
        let magnitude = value < 0 ? -value : value
        let symbolInfo = symbol(for: money.currency)
        guard let body = compactBody(magnitude) else {
            return string(money, sign: sign, fraction: money.currency == .uzs ? .automatic : .automatic)
        }
        let signText = signText(for: money.minorUnits, display: sign)
        if symbolInfo.leading {
            return signText + symbolInfo.text + body
        }
        return signText + body + Self.nbsp + symbolInfo.text
    }

    /// Подписи осей графиков: «1,2 млн», «850 тыс.», «12 000».
    public func axisLabel(_ value: Decimal) -> String {
        let magnitude = value < 0 ? -value : value
        let signText = value < 0 ? Self.minus : ""
        if let body = compactBody(magnitude) { return signText + body }
        let rounded = DecimalMath.round(magnitude, scale: 0, rule: .halfUp)
        return signText + group(DecimalMath.exactInt64(rounded).map { String($0) } ?? "0")
    }

    /// Строка для редактирования: без разделителей разрядов, с десятичным разделителем языка.
    public func editableString(_ money: Money) -> String {
        let scale = UInt64(money.currency.minorUnitScale)
        let absolute = money.minorUnits.magnitude
        var text = String(absolute / scale)
        let remainder = absolute % scale
        if remainder != 0 {
            var fraction = String(remainder)
            while fraction.count < money.currency.minorUnitDigits { fraction = "0" + fraction }
            while fraction.hasSuffix("0") { fraction.removeLast() }
            text += decimalSeparator + fraction
        }
        return (money.minorUnits < 0 ? "-" : "") + text
    }

    /// Разбор ввода пользователя: «85000», «85 000», «12,5», «12.50». Пустая строка → nil.
    public static func parseUserInput(_ text: String, currency: Currency) -> Money? {
        var cleaned = ""
        var separatorSeen = false
        for char in text {
            if char.isASCII, char.isNumber {
                cleaned.append(char)
            } else if (char == "," || char == ".") && !separatorSeen {
                separatorSeen = true
                cleaned.append(".")
            } else if char == " " || char == "\u{00A0}" || char == "\u{202F}" || char == "\u{2009}" {
                continue
            } else if char == "-" || char == "\u{2212}" {
                if cleaned.isEmpty { cleaned.append("-") } else { return nil }
            } else {
                return nil
            }
        }
        if cleaned.hasSuffix(".") { cleaned.removeLast() }
        guard let value = DecimalMath.parse(cleaned) else { return nil }
        return Money(major: value, currency: currency)
    }

    // MARK: Вспомогательное

    private func signText(for minorUnits: Int64, display: SignDisplay) -> String {
        switch display {
        case .never: return ""
        case .automatic: return minorUnits < 0 ? Self.minus : ""
        case .always:
            if minorUnits < 0 { return Self.minus }
            if minorUnits > 0 { return "+" }
            return ""
        }
    }

    func group(_ digits: String) -> String {
        guard digits.count > 3 else { return digits }
        var result = ""
        for (index, char) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { result += groupSeparator }
            result.append(char)
        }
        return result
    }

    private struct CompactUnit {
        let threshold: Decimal
        let ru: String
        let uz: String
        let en: String
    }

    private static let compactUnits: [CompactUnit] = [
        CompactUnit(threshold: 1_000_000_000, ru: "млрд", uz: "mlrd", en: "B"),
        CompactUnit(threshold: 1_000_000, ru: "млн", uz: "mln", en: "M"),
        CompactUnit(threshold: 1_000, ru: "тыс.", uz: "ming", en: "K")
    ]

    private func compactBody(_ magnitude: Decimal) -> String? {
        for unit in Self.compactUnits where magnitude >= unit.threshold {
            let scaled = magnitude / unit.threshold
            let fractionDigits: Int
            if scaled < 10 { fractionDigits = 2 } else if scaled < 100 { fractionDigits = 1 } else { fractionDigits = 0 }
            let rounded = DecimalMath.round(scaled, scale: fractionDigits, rule: .halfUp)
            let suffix: String
            switch language {
            case .ru: suffix = unit.ru
            case .uz: suffix = unit.uz
            case .en: suffix = unit.en
            }
            let numberText = trimmedDecimal(rounded, maxFractionDigits: fractionDigits)
            return language == .en ? numberText + suffix : numberText + Self.nbsp + suffix
        }
        return nil
    }

    private func trimmedDecimal(_ value: Decimal, maxFractionDigits: Int) -> String {
        let scaledInt = DecimalMath.exactInt64(DecimalMath.round(value * DecimalMath.pow10(maxFractionDigits), scale: 0, rule: .halfUp)) ?? 0
        var divisor: Int64 = 1
        for _ in 0..<maxFractionDigits { divisor *= 10 }
        let integer = scaledInt / divisor
        var fraction = maxFractionDigits > 0 ? String(scaledInt % divisor) : ""
        while fraction.count < maxFractionDigits { fraction = "0" + fraction }
        while fraction.hasSuffix("0") { fraction.removeLast() }
        let integerText = group(String(integer))
        return fraction.isEmpty ? integerText : integerText + decimalSeparator + fraction
    }
}
