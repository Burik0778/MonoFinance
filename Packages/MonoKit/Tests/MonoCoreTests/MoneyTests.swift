import XCTest
@testable import MonoCore

final class MoneyTests: XCTestCase {
    func testMinorUnitDigits() {
        XCTAssertEqual(Currency.uzs.minorUnitDigits, 2)
        XCTAssertEqual(Currency.usd.minorUnitDigits, 2)
        XCTAssertEqual(Currency.jpy.minorUnitDigits, 0)
        XCTAssertEqual(Currency("kwd").minorUnitDigits, 3)
        XCTAssertEqual(Currency.uzs.minorUnitScale, 100)
        XCTAssertTrue(Currency("usd").isWellFormed)
        XCTAssertFalse(Currency("US").isWellFormed)
    }

    func testMajorConversionIsExact() {
        let money = Money(major: Decimal(string: "85000")!, currency: .uzs)!
        XCTAssertEqual(money.minorUnits, 8_500_000)
        XCTAssertEqual(money.majorValue, Decimal(85000))

        let usd = Money(major: Decimal(string: "0.1")!, currency: .usd)!
        let usd2 = Money(major: Decimal(string: "0.2")!, currency: .usd)!
        XCTAssertEqual((usd + usd2).minorUnits, 30, "0.1 + 0.2 обязано быть ровно 0.30")
    }

    func testBankersRoundingOnHalf() {
        XCTAssertEqual(Money(major: Decimal(string: "1.005")!, currency: .usd)!.minorUnits, 100)
        XCTAssertEqual(Money(major: Decimal(string: "1.015")!, currency: .usd)!.minorUnits, 102)
        XCTAssertEqual(Money(major: Decimal(string: "-1.015")!, currency: .usd)!.minorUnits, -102)
        XCTAssertEqual(Money(major: Decimal(string: "1.005")!, currency: .usd, rounding: .halfUp)!.minorUnits, 101)
        XCTAssertEqual(Money(major: Decimal(string: "-2.5")!, currency: .jpy, rounding: .halfUp)!.minorUnits, -3)
        XCTAssertEqual(Money(major: Decimal(string: "-2.9")!, currency: .jpy, rounding: .down)!.minorUnits, -2)
    }

    func testLargeValuesStayExact() {
        let big = Money(major: Decimal(string: "9999999999999.99")!, currency: .uzs)!
        XCTAssertEqual(big.minorUnits, 999_999_999_999_999)
        XCTAssertNil(Money(major: Decimal(string: "99999999999999999")!, currency: .uzs), "Выше лимита — отказ, а не переполнение")
        XCTAssertEqual(DecimalMath.exactInt64(Decimal(string: "123456789012345678")!), 123_456_789_012_345_678)
        XCTAssertNil(DecimalMath.exactInt64(Decimal(string: "1.5")!))
    }

    func testArithmeticAndHelpers() {
        let a = Money(minorUnits: 12_000_000, currency: .uzs)
        let b = Money(minorUnits: 7_500_000, currency: .uzs)
        XCTAssertEqual((a - b).minorUnits, 4_500_000)
        XCTAssertEqual((-a).minorUnits, -12_000_000)
        XCTAssertEqual(a.magnitude, a)
        XCTAssertEqual((-a).magnitude, a)
        XCTAssertNil(a.adding(Money(minorUnits: 1, currency: .usd)))
        XCTAssertEqual(Money.sum([a, b], currency: .uzs).minorUnits, 19_500_000)
        XCTAssertEqual(a.multiplied(by: Decimal(string: "0.015")!)?.minorUnits, 180_000)
        XCTAssertEqual(b.ratio(to: a)!, 0.625, accuracy: 1e-9)
        XCTAssertTrue(b < a)
    }

    func testDecimalParsing() {
        XCTAssertEqual(DecimalMath.parse("12650.37"), Decimal(string: "12650.37"))
        XCTAssertEqual(DecimalMath.parse("-5"), Decimal(-5))
        XCTAssertNil(DecimalMath.parse("12,5"))
        XCTAssertNil(DecimalMath.parse("1.2.3"))
        XCTAssertNil(DecimalMath.parse(""))
        XCTAssertNil(DecimalMath.parse("abc"))
    }

    func testCodableRoundTrip() throws {
        let money = Money(minorUnits: -123_456, currency: .usd)
        let data = try JSONEncoder().encode(money)
        let decoded = try JSONDecoder().decode(Money.self, from: data)
        XCTAssertEqual(decoded, money)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"USD\""))
    }
}

final class MoneyFormatterTests: XCTestCase {
    let nn = "\u{202F}"   // разделитель разрядов
    let nb = "\u{00A0}"   // перед символом валюты
    let minus = "\u{2212}"

    func testRussianUZS() {
        let f = MoneyFormatter(language: .ru)
        XCTAssertEqual(f.string(Money(minorUnits: 8_500_000, currency: .uzs)), "85\(nn)000\(nb)сум")
        XCTAssertEqual(f.string(Money(minorUnits: 1_245_030_000, currency: .uzs)), "12\(nn)450\(nn)300\(nb)сум")
        XCTAssertEqual(f.string(Money(minorUnits: -8_500_000, currency: .uzs)), "\(minus)85\(nn)000\(nb)сум")
        XCTAssertEqual(f.string(Money(minorUnits: 8_500_050, currency: .uzs)), "85\(nn)000,50\(nb)сум", "Тийины показываются, только если не нулевые")
        XCTAssertEqual(f.string(Money(minorUnits: 8_500_000, currency: .uzs), sign: .always), "+85\(nn)000\(nb)сум")
        XCTAssertEqual(f.string(Money(minorUnits: 999, currency: .uzs), fraction: .never), "9\(nb)сум")
    }

    func testUSDAndOthers() {
        let ru = MoneyFormatter(language: .ru)
        XCTAssertEqual(ru.string(Money(minorUnits: 125_050, currency: .usd)), "$1\(nn)250,50")
        XCTAssertEqual(ru.string(Money(minorUnits: -125_050, currency: .usd)), "\(minus)$1\(nn)250,50")
        XCTAssertEqual(ru.string(Money(minorUnits: 150_000, currency: .rub)), "1\(nn)500,00\(nb)₽")
        XCTAssertEqual(ru.string(Money(minorUnits: 1500, currency: .jpy)), "¥1\(nn)500")

        let en = MoneyFormatter(language: .en)
        XCTAssertEqual(en.string(Money(minorUnits: 125_050, currency: .usd)), "$1,250.50")
        XCTAssertEqual(en.string(Money(minorUnits: 8_500_000, currency: .uzs)), "85,000\(nb)UZS")

        let uz = MoneyFormatter(language: .uz)
        XCTAssertEqual(uz.string(Money(minorUnits: 8_500_000, currency: .uzs)), "85\(nn)000\(nb)so‘m")
    }

    func testParts() {
        let parts = MoneyFormatter(language: .ru).parts(Money(minorUnits: 125_050, currency: .usd))
        XCTAssertEqual(parts.integerPart, "1\(nn)250")
        XCTAssertEqual(parts.fractionPart, "50")
        XCTAssertEqual(parts.symbol, "$")
        XCTAssertTrue(parts.symbolLeading)
    }

    func testCompact() {
        let ru = MoneyFormatter(language: .ru)
        XCTAssertEqual(ru.compact(Money(major: 1_250_000, currency: .uzs)!), "1,25\(nb)млн\(nb)сум")
        XCTAssertEqual(ru.compact(Money(major: 12_400_000, currency: .uzs)!), "12,4\(nb)млн\(nb)сум")
        XCTAssertEqual(ru.compact(Money(major: 850_000, currency: .uzs)!), "850\(nb)тыс.\(nb)сум")
        XCTAssertEqual(ru.compact(Money(major: 2_000_000_000, currency: .uzs)!), "2\(nb)млрд\(nb)сум")
        XCTAssertEqual(ru.compact(Money(major: 500, currency: .uzs)!), "500\(nb)сум")
        XCTAssertEqual(ru.axisLabel(Decimal(1_200_000)), "1,2\(nb)млн")
        let en = MoneyFormatter(language: .en)
        XCTAssertEqual(en.compact(Money(major: 1_250_000, currency: .uzs)!), "1.25M\(nb)UZS")
        XCTAssertEqual(en.compact(Money(major: 12_500, currency: .usd)!), "$12.5K")
    }

    func testEditableAndParsing() {
        let ru = MoneyFormatter(language: .ru)
        XCTAssertEqual(ru.editableString(Money(minorUnits: 8_500_000, currency: .uzs)), "85000")
        XCTAssertEqual(ru.editableString(Money(minorUnits: 1250, currency: .usd)), "12,5")
        XCTAssertEqual(MoneyFormatter.parseUserInput("85 000", currency: .uzs)?.minorUnits, 8_500_000)
        XCTAssertEqual(MoneyFormatter.parseUserInput("12,5", currency: .usd)?.minorUnits, 1250)
        XCTAssertEqual(MoneyFormatter.parseUserInput("12.50", currency: .usd)?.minorUnits, 1250)
        XCTAssertNil(MoneyFormatter.parseUserInput("12,5,0", currency: .usd))
        XCTAssertNil(MoneyFormatter.parseUserInput("", currency: .usd))
        XCTAssertNil(MoneyFormatter.parseUserInput("abc", currency: .usd))
    }
}
