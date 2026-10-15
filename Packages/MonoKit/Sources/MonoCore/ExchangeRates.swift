import Foundation

public enum RateSource: String, Codable, Sendable {
    /// Официальный курс Центрального банка Республики Узбекистан.
    case cbu
    /// Введён пользователем вручную.
    case manual
}

/// Курс валюты: сколько единиц базовой валюты стоит одна единица `currency`.
public struct ExchangeRate: Hashable, Codable, Sendable, Identifiable {
    public var currency: Currency
    public var baseCurrency: Currency
    public var rate: Decimal
    public var date: Date
    public var source: RateSource

    public var id: String { currency.code }

    public init(currency: Currency, baseCurrency: Currency, rate: Decimal, date: Date, source: RateSource) {
        self.currency = currency
        self.baseCurrency = baseCurrency
        self.rate = rate
        self.date = date
        self.source = source
    }
}

/// Конвертация через базовую валюту. Если курса нет — возвращает `nil`, ничего не придумывая.
public struct CurrencyConverter: Sendable {
    public let base: Currency
    private let rates: [Currency: Decimal]

    public init(base: Currency, rates: [ExchangeRate]) {
        self.base = base
        var map: [Currency: Decimal] = [base: 1]
        for rate in rates where rate.baseCurrency == base && rate.rate > 0 {
            map[rate.currency] = rate.rate
        }
        self.rates = map
    }

    public init(base: Currency, rateTable: [Currency: Decimal]) {
        self.base = base
        var map = rateTable.filter { $0.value > 0 }
        map[base] = 1
        self.rates = map
    }

    public func hasRate(for currency: Currency) -> Bool { rates[currency] != nil }

    public func rate(for currency: Currency) -> Decimal? { rates[currency] }

    public var knownCurrencies: Set<Currency> { Set(rates.keys) }

    public func convert(_ money: Money, to target: Currency, rounding: RoundingRule = .halfEven) -> Money? {
        if money.currency == target { return money }
        guard let fromRate = rates[money.currency], let toRate = rates[target] else { return nil }
        let inBase = money.majorValue * fromRate
        let inTarget = inBase / toRate
        return Money(major: inTarget, currency: target, rounding: rounding)
    }

    public func toBase(_ money: Money) -> Money? { convert(money, to: base) }
}

/// Разбор официального JSON ЦБ РУз (https://cbu.uz/ru/arkhiv-kursov-valyut/json/).
/// Формат: массив объектов с полями `Ccy` ("USD"), `Rate` ("11913.35", строка), `Nominal` ("1"), `Date` ("14.10.2026").
public enum CBURateParser {
    private struct Row: Decodable {
        let Ccy: String
        let Rate: String
        let Nominal: String?
        let Date: String
    }

    public enum ParseError: Error, Equatable {
        case invalidJSON
        case empty
    }

    public static func parse(_ data: Data, calendar: Calendar) throws -> [ExchangeRate] {
        let rows: [Row]
        do {
            rows = try JSONDecoder().decode([Row].self, from: data)
        } catch {
            throw ParseError.invalidJSON
        }
        var result: [ExchangeRate] = []
        for row in rows {
            let currency = Currency(row.Ccy)
            guard currency.isWellFormed, currency != .uzs,
                  let rawRate = DecimalMath.parse(row.Rate), rawRate > 0 else { continue }
            let nominal = row.Nominal.flatMap { DecimalMath.parse($0) } ?? 1
            guard nominal > 0 else { continue }
            let date = parseDate(row.Date, calendar: calendar) ?? Date()
            result.append(ExchangeRate(currency: currency, baseCurrency: .uzs, rate: rawRate / nominal, date: date, source: .cbu))
        }
        guard !result.isEmpty else { throw ParseError.empty }
        return result
    }

    static func parseDate(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.day = parts[0]
        components.month = parts[1]
        components.year = parts[2]
        components.hour = 12
        return calendar.date(from: components)
    }
}
