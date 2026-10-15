import XCTest
@testable import MonoCore

final class CurrencyConverterTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func cbu(_ currency: Currency, _ rate: Decimal) -> ExchangeRate {
        ExchangeRate(currency: currency, baseCurrency: .uzs, rate: rate, date: date, source: .cbu)
    }

    private func money(_ value: Decimal, _ currency: Currency) -> Money { Money(major: value, currency: currency)! }

    func testDirectRatesToUZS() {
        let converter = CurrencyConverter(base: .uzs, rates: [cbu(.usd, 12_000), cbu(.rub, 150)])
        XCTAssertEqual(converter.toBase(money(100, .usd)), money(1_200_000, .uzs))
        XCTAssertEqual(converter.toBase(money(1_000, .rub)), money(150_000, .uzs))
    }

    func testCBURatesWorkWithDollarBase() {
        let converter = CurrencyConverter(base: .usd, rates: [cbu(.usd, 12_000), cbu(.rub, 150), cbu(.eur, 13_200)])
        XCTAssertEqual(converter.toBase(money(1_200_000, .uzs)), money(100, .usd))
        XCTAssertEqual(converter.toBase(money(800, .rub)), money(10, .usd))
        XCTAssertEqual(converter.toBase(money(100, .eur)), money(110, .usd))
        XCTAssertTrue(converter.hasRate(for: .uzs))
    }

    func testRubleBase() {
        let converter = CurrencyConverter(base: .rub, rates: [cbu(.usd, 12_000), cbu(.rub, 150)])
        XCTAssertEqual(converter.toBase(money(150_000, .uzs)), money(1_000, .rub))
        XCTAssertEqual(converter.toBase(money(1, .usd)), money(80, .rub))
    }

    func testManualRateWinsOverCrossRate() {
        let manual = ExchangeRate(currency: .eur, baseCurrency: .usd, rate: Decimal(string: "1.2")!, date: date, source: .manual)
        let converter = CurrencyConverter(base: .usd, rates: [cbu(.usd, 12_000), cbu(.eur, 13_200), manual])
        XCTAssertEqual(converter.toBase(money(100, .eur)), money(120, .usd))
    }

    func testManualRateQuotedInSum() {
        // Основная валюта — доллар, пользователь ввёл «1 USD = 12 500 сум».
        let manual = ExchangeRate(currency: .usd, baseCurrency: .uzs, rate: 12_500, date: date, source: .manual)
        let converter = CurrencyConverter(base: .usd, rates: [manual])
        XCTAssertEqual(converter.toBase(money(2_500_000, .uzs)), money(200, .usd))
    }

    func testMissingRateStaysNil() {
        let converter = CurrencyConverter(base: .usd, rates: [cbu(.rub, 150)])
        XCTAssertNil(converter.toBase(money(100, .uzs)), "без курса доллара к суму пересчитать нельзя")
        XCTAssertNil(converter.toBase(money(100, .rub)))
    }
}
