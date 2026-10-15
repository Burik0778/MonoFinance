import Foundation

/// Правило округления денежных значений.
public enum RoundingRule: String, Codable, Sendable, CaseIterable {
    /// Банковское округление (к ближайшему чётному) — по умолчанию для конвертаций.
    case halfEven
    /// Классическое округление «половина вверх» (от нуля).
    case halfUp
    /// Отбрасывание дробной части (к нулю).
    case down
    /// От нуля.
    case up

    var nsMode: NSDecimalNumber.RoundingMode {
        switch self {
        case .halfEven: return .bankers
        case .halfUp: return .plain
        case .down: return .down
        case .up: return .up
        }
    }
}

/// Точная арифметика на `Decimal` без промежуточных `Double`.
public enum DecimalMath {
    public static func pow10(_ exponent: Int) -> Decimal {
        Decimal(sign: .plus, exponent: exponent, significand: 1)
    }

    /// Округляет до `scale` знаков после запятой.
    ///
    /// `NSDecimalRound` в режимах `.down`/`.up` работает в сторону -∞/+∞,
    /// поэтому для отрицательных чисел округляем модуль — так `.down` означает «к нулю».
    public static func round(_ value: Decimal, scale: Int, rule: RoundingRule) -> Decimal {
        let negative = value < 0
        var input = negative ? -value : value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, rule.nsMode)
        return negative ? -result : result
    }

    /// Точное преобразование целого `Decimal` в `Int64`. Возвращает `nil`, если число дробное или не помещается.
    public static func exactInt64(_ value: Decimal) -> Int64? {
        guard value.isFinite else { return nil }
        let text = value.description
        if let dot = text.firstIndex(of: ".") {
            let fraction = text[text.index(after: dot)...]
            guard fraction.allSatisfy({ $0 == "0" }) else { return nil }
            return Int64(text[..<dot])
        }
        return Int64(text)
    }

    /// Переводит сумму в основных единицах в минимальные (тийины, центы) с округлением.
    public static func minorUnits(fromMajor major: Decimal, digits: Int, rule: RoundingRule) -> Int64? {
        let scaled = major * pow10(digits)
        let rounded = round(scaled, scale: 0, rule: rule)
        return exactInt64(rounded)
    }

    /// Разбирает число в «машинном» формате ("12650.37", "-5", "1e3" не поддерживается).
    public static func parse(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var sawDigit = false
        var sawDot = false
        for (index, char) in trimmed.enumerated() {
            if char.isASCII, char.isNumber { sawDigit = true; continue }
            if char == "." { if sawDot { return nil }; sawDot = true; continue }
            if (char == "-" || char == "+") && index == 0 { continue }
            return nil
        }
        guard sawDigit else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// Денежная сумма: целое число минимальных единиц и валюта. Никаких `Double`.
public struct Money: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public var minorUnits: Int64
    public var currency: Currency

    /// Верхняя граница модуля суммы (10^15 минимальных единиц). Защищает от переполнения при суммировании.
    public static let maxMagnitude: Int64 = 1_000_000_000_000_000

    public init(minorUnits: Int64, currency: Currency) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    /// Создаёт сумму из значения в основных единицах (например, 85000 сум или 12.5 USD).
    public init?(major: Decimal, currency: Currency, rounding: RoundingRule = .halfEven) {
        guard let minor = DecimalMath.minorUnits(fromMajor: major, digits: currency.minorUnitDigits, rule: rounding),
              minor.magnitude <= UInt64(Money.maxMagnitude) else { return nil }
        self.init(minorUnits: minor, currency: currency)
    }

    public static func zero(_ currency: Currency) -> Money { Money(minorUnits: 0, currency: currency) }

    /// Значение в основных единицах (точное).
    public var majorValue: Decimal {
        Decimal(minorUnits) * DecimalMath.pow10(-currency.minorUnitDigits)
    }

    public var isZero: Bool { minorUnits == 0 }
    public var isPositive: Bool { minorUnits > 0 }
    public var isNegative: Bool { minorUnits < 0 }
    public var isWithinLimits: Bool { minorUnits.magnitude <= UInt64(Money.maxMagnitude) }

    public var magnitude: Money { Money(minorUnits: minorUnits < 0 ? -minorUnits : minorUnits, currency: currency) }
    public var negated: Money { Money(minorUnits: -minorUnits, currency: currency) }

    public func isSameCurrency(as other: Money) -> Bool { currency == other.currency }

    public var description: String { "\(majorValue) \(currency.code)" }

    // MARK: Арифметика (только в одной валюте)

    public static prefix func - (value: Money) -> Money { value.negated }

    public static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Сложение сумм в разных валютах: \(lhs.currency) и \(rhs.currency)")
        return Money(minorUnits: lhs.minorUnits + rhs.minorUnits, currency: lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Вычитание сумм в разных валютах: \(lhs.currency) и \(rhs.currency)")
        return Money(minorUnits: lhs.minorUnits - rhs.minorUnits, currency: lhs.currency)
    }

    public static func += (lhs: inout Money, rhs: Money) { lhs = lhs + rhs }
    public static func -= (lhs: inout Money, rhs: Money) { lhs = lhs - rhs }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency, "Сравнение сумм в разных валютах: \(lhs.currency) и \(rhs.currency)")
        return lhs.minorUnits < rhs.minorUnits
    }

    /// Безопасное сложение: `nil`, если валюты различаются.
    public func adding(_ other: Money) -> Money? {
        guard currency == other.currency else { return nil }
        return Money(minorUnits: minorUnits + other.minorUnits, currency: currency)
    }

    /// Умножение на коэффициент с округлением до минимальных единиц.
    public func multiplied(by factor: Decimal, rounding: RoundingRule = .halfEven) -> Money? {
        let product = Decimal(minorUnits) * factor
        guard let minor = DecimalMath.exactInt64(DecimalMath.round(product, scale: 0, rule: rounding)) else { return nil }
        return Money(minorUnits: minor, currency: currency)
    }

    /// Доля от другой суммы той же валюты (0…∞). `nil`, если делитель нулевой.
    public func ratio(to other: Money) -> Double? {
        guard currency == other.currency, other.minorUnits != 0 else { return nil }
        return Double(minorUnits) / Double(other.minorUnits)
    }

    /// Сумма массива в одной валюте.
    public static func sum(_ values: [Money], currency: Currency) -> Money {
        values.reduce(Money.zero(currency)) { $0 + $1 }
    }
}
