import Foundation

/// Валюта ISO 4217. Хранится и кодируется как трёхбуквенный код.
public struct Currency: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let code: String

    public init(_ code: String) {
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }

    public var description: String { code }

    public static func < (lhs: Currency, rhs: Currency) -> Bool { lhs.code < rhs.code }

    // MARK: Известные валюты

    public static let uzs = Currency("UZS")
    public static let usd = Currency("USD")
    public static let eur = Currency("EUR")
    public static let rub = Currency("RUB")
    public static let kzt = Currency("KZT")
    public static let gbp = Currency("GBP")
    public static let cny = Currency("CNY")
    public static let tryLira = Currency("TRY")
    public static let aed = Currency("AED")
    public static let krw = Currency("KRW")
    public static let jpy = Currency("JPY")
    public static let chf = Currency("CHF")
    public static let kgs = Currency("KGS")

    /// Валюты для выбора в интерфейсе, в порядке показа.
    public static let common: [Currency] = [.uzs, .usd, .eur, .rub, .kzt, .gbp, .cny, .tryLira, .aed, .krw, .jpy, .chf, .kgs]

    private static let zeroDigitCodes: Set<String> = ["JPY", "KRW", "VND", "CLP", "ISK", "UGX", "XAF", "XOF", "PYG", "KMF", "RWF"]
    private static let threeDigitCodes: Set<String> = ["BHD", "KWD", "OMR", "JOD", "TND", "LYD", "IQD"]

    /// Количество знаков после запятой (minor unit по ISO 4217). Для UZS — 2 (тийины).
    public var minorUnitDigits: Int {
        if Self.zeroDigitCodes.contains(code) { return 0 }
        if Self.threeDigitCodes.contains(code) { return 3 }
        return 2
    }

    /// 10^minorUnitDigits.
    public var minorUnitScale: Int64 {
        var scale: Int64 = 1
        for _ in 0..<minorUnitDigits { scale *= 10 }
        return scale
    }

    /// Корректный ли трёхбуквенный код.
    public var isWellFormed: Bool {
        code.count == 3 && code.unicodeScalars.allSatisfy { $0.value >= 65 && $0.value <= 90 }
    }
}
