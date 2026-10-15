import XCTest
@testable import MonoCore

final class LedgerTests: XCTestCase {
    let kapital = Account(bank: .kapitalbank, name: "Kapital Humo", currency: .uzs)
    let uzum = Account(bank: .uzum, name: "Uzum", currency: .uzs)
    let dollar = Account(bank: .orientFinans, name: "OFB Visa", currency: .usd)
    lazy var accounts: [UUID: Account] = [kapital.id: kapital, uzum.id: uzum, dollar.id: dollar]
    let categories: [UUID: FinanceCategory] = Dictionary(uniqueKeysWithValues: DefaultCategories.make(language: .ru).map { ($0.id, $0) })

    func uzs(_ value: Int64) -> Money { Money(major: Decimal(value), currency: .uzs)! }
    func usd(_ value: Int64) -> Money { Money(major: Decimal(value), currency: .usd)! }
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testEffectsPerKind() {
        let expense = FinanceTransaction(kind: .expense, amount: uzs(85_000), accountID: kapital.id, date: now)
        XCTAssertEqual(Ledger.effects(of: expense), [BalanceEffect(accountID: kapital.id, delta: uzs(-85_000))])

        let income = FinanceTransaction(kind: .income, amount: uzs(1_000_000), accountID: kapital.id, date: now)
        XCTAssertEqual(Ledger.effects(of: income).first?.delta, uzs(1_000_000))

        let fee = FinanceTransaction(kind: .fee, amount: uzs(5_000), accountID: kapital.id, date: now)
        XCTAssertEqual(Ledger.effects(of: fee).first?.delta, uzs(-5_000))

        let refund = FinanceTransaction(kind: .refund, amount: uzs(40_000), accountID: kapital.id, date: now)
        XCTAssertEqual(Ledger.effects(of: refund).first?.delta, uzs(40_000))

        let adjustment = FinanceTransaction(kind: .adjustment, amount: uzs(-12_000), accountID: kapital.id, date: now)
        XCTAssertEqual(Ledger.effects(of: adjustment).first?.delta, uzs(-12_000))

        let transfer = FinanceTransaction(kind: .transfer, amount: uzs(1_000_000), accountID: kapital.id,
                                   counterAccountID: uzum.id, counterAmount: uzs(1_000_000), date: now)
        XCTAssertEqual(Ledger.effects(of: transfer), [
            BalanceEffect(accountID: kapital.id, delta: uzs(-1_000_000)),
            BalanceEffect(accountID: uzum.id, delta: uzs(1_000_000))
        ])
    }

    func testSameCurrencyTransferPreservesTotal() {
        let opening = FinanceTransaction(kind: .adjustment, amount: uzs(5_000_000), accountID: kapital.id, date: now, isOpeningBalance: true)
        let transfer = FinanceTransaction(kind: .transfer, amount: uzs(1_000_000), accountID: kapital.id,
                                   counterAccountID: uzum.id, counterAmount: uzs(1_000_000), date: now)
        let before = Ledger.totalsByCurrency(Ledger.balances(accounts: [kapital, uzum], transactions: [opening]))
        let after = Ledger.totalsByCurrency(Ledger.balances(accounts: [kapital, uzum], transactions: [opening, transfer]))
        XCTAssertEqual(before[.uzs], after[.uzs], "Перевод между своими счетами не меняет общий баланс")
        let balances = Ledger.balances(accounts: [kapital, uzum], transactions: [opening, transfer])
        XCTAssertEqual(balances[kapital.id], uzs(4_000_000))
        XCTAssertEqual(balances[uzum.id], uzs(1_000_000))
    }

    func testBalanceFormula() {
        let txs: [FinanceTransaction] = [
            FinanceTransaction(kind: .adjustment, amount: uzs(2_000_000), accountID: kapital.id, date: now, isOpeningBalance: true),
            FinanceTransaction(kind: .income, amount: uzs(3_000_000), accountID: kapital.id, date: now),
            FinanceTransaction(kind: .expense, amount: uzs(245_000), accountID: kapital.id, date: now),
            FinanceTransaction(kind: .fee, amount: uzs(10_000), accountID: kapital.id, date: now),
            FinanceTransaction(kind: .refund, amount: uzs(45_000), accountID: kapital.id, date: now),
            FinanceTransaction(kind: .transfer, amount: uzs(500_000), accountID: kapital.id, counterAccountID: uzum.id, counterAmount: uzs(500_000), date: now),
            FinanceTransaction(kind: .adjustment, amount: uzs(-1_000), accountID: kapital.id, date: now)
        ]
        let balances = Ledger.balances(accounts: [kapital, uzum], transactions: txs)
        // 2 000 000 + 3 000 000 − 245 000 − 10 000 + 45 000 − 500 000 − 1 000
        XCTAssertEqual(balances[kapital.id], uzs(4_289_000))
        XCTAssertEqual(balances[uzum.id], uzs(500_000))
    }

    func testCrossCurrencyTransfer() throws {
        let transfer = FinanceTransaction(kind: .transfer, amount: usd(100), accountID: dollar.id,
                                   counterAccountID: kapital.id, counterAmount: uzs(1_191_335), date: now)
        try Ledger.validate(transfer, accounts: accounts, categories: categories, isNew: true)
        let balances = Ledger.balances(accounts: [dollar, kapital], transactions: [transfer])
        XCTAssertEqual(balances[dollar.id], usd(-100))
        XCTAssertEqual(balances[kapital.id], uzs(1_191_335))
    }

    func testValidationRules() {
        func check(_ tx: FinanceTransaction, _ expected: LedgerError, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertThrowsError(try Ledger.validate(tx, accounts: accounts, categories: categories, isNew: true), file: file, line: line) { error in
                XCTAssertEqual(error as? LedgerError, expected, file: file, line: line)
            }
        }
        check(FinanceTransaction(kind: .expense, amount: uzs(0), accountID: kapital.id, date: now), .amountMustBePositive)
        check(FinanceTransaction(kind: .expense, amount: uzs(-5), accountID: kapital.id, date: now), .amountMustBePositive)
        check(FinanceTransaction(kind: .adjustment, amount: uzs(0), accountID: kapital.id, date: now), .adjustmentMustBeNonZero)
        check(FinanceTransaction(kind: .expense, amount: usd(5), accountID: kapital.id, date: now), .currencyMismatch(expected: .uzs, actual: .usd))
        check(FinanceTransaction(kind: .transfer, amount: uzs(5), accountID: kapital.id, date: now), .transferNeedsDestination)
        check(FinanceTransaction(kind: .transfer, amount: uzs(5), accountID: kapital.id, counterAccountID: kapital.id, counterAmount: uzs(5), date: now), .transferToSameAccount)
        check(FinanceTransaction(kind: .transfer, amount: uzs(5), accountID: kapital.id, counterAccountID: uzum.id, counterAmount: uzs(4), date: now), .sameCurrencyTransferAmountsDiffer)
        check(FinanceTransaction(kind: .transfer, amount: uzs(5), accountID: kapital.id, counterAccountID: dollar.id, counterAmount: uzs(5), date: now), .counterCurrencyMismatch(expected: .usd, actual: .uzs))
        check(FinanceTransaction(kind: .income, amount: uzs(5), accountID: kapital.id, counterAccountID: uzum.id, date: now), .unexpectedCounterAccount)

        let salary = categories.values.first { $0.systemKey == SystemCategoryKey.salary }!
        let cafe = categories.values.first { $0.systemKey == SystemCategoryKey.cafe }!
        check(FinanceTransaction(kind: .expense, amount: uzs(5), accountID: kapital.id, categoryID: salary.id, date: now), .categoryKindMismatch)
        check(FinanceTransaction(kind: .transfer, amount: uzs(5), accountID: kapital.id, counterAccountID: uzum.id, counterAmount: uzs(5), categoryID: cafe.id, date: now), .categoryNotAllowed)
        XCTAssertNoThrow(try Ledger.validate(FinanceTransaction(kind: .refund, amount: uzs(5), accountID: kapital.id, categoryID: cafe.id, date: now), accounts: accounts, categories: categories, isNew: true))

        var archived = uzum
        archived.isArchived = true
        var withArchived = accounts
        withArchived[archived.id] = archived
        XCTAssertThrowsError(try Ledger.validate(FinanceTransaction(kind: .expense, amount: uzs(5), accountID: archived.id, date: now), accounts: withArchived, categories: categories, isNew: true))
        XCTAssertNoThrow(try Ledger.validate(FinanceTransaction(kind: .expense, amount: uzs(5), accountID: archived.id, date: now), accounts: withArchived, categories: categories, isNew: false),
                         "Старые операции архивного счёта можно редактировать")
    }

    func testBalanceAsOf() {
        let day = TimeInterval(86_400)
        let txs = [
            FinanceTransaction(kind: .income, amount: uzs(100), accountID: kapital.id, date: now),
            FinanceTransaction(kind: .expense, amount: uzs(30), accountID: kapital.id, date: now.addingTimeInterval(day)),
            FinanceTransaction(kind: .expense, amount: uzs(20), accountID: kapital.id, date: now.addingTimeInterval(2 * day))
        ]
        XCTAssertEqual(Ledger.balance(of: kapital, transactions: txs, asOf: now.addingTimeInterval(day)), uzs(70))
        XCTAssertEqual(Ledger.balance(of: kapital, transactions: txs, asOf: now.addingTimeInterval(-1)), uzs(0))
    }

    func testValidationMessagesAreLocalized() {
        XCTAssertEqual(LedgerError.amountMustBePositive.message(.ru), "Сумма должна быть больше нуля.")
        XCTAssertEqual(LedgerError.amountMustBePositive.message(.en), "Amount must be greater than zero.")
    }
}

final class ConverterTests: XCTestCase {
    func testConversionViaBase() {
        let converter = CurrencyConverter(base: .uzs, rateTable: [.usd: Decimal(string: "11913.35")!, .eur: Decimal(string: "13328.66")!])
        XCTAssertEqual(converter.convert(Money(minorUnits: 10_000, currency: .usd), to: .uzs)?.minorUnits, 119_133_500)
        // 100 EUR → USD через сум: 1 332 866 / 11 913.35 = 111.880… → 111.88
        XCTAssertEqual(converter.convert(Money(minorUnits: 10_000, currency: .eur), to: .usd)?.minorUnits, 11_188)
        XCTAssertNil(converter.convert(Money(minorUnits: 100, currency: .gbp), to: .uzs), "Нет курса — нет выдуманного значения")
        XCTAssertEqual(converter.toBase(Money(minorUnits: 500, currency: .uzs))?.minorUnits, 500)
    }

    func testCBUParser() throws {
        let json = """
        [{"id":68,"Code":"840","Ccy":"USD","CcyNm_RU":"Доллар США","Nominal":"1","Rate":"11913.35","Diff":"14.26","Date":"14.10.2026"},
         {"id":20,"Code":"978","Ccy":"EUR","CcyNm_RU":"Евро","Nominal":"1","Rate":"13328.66","Diff":"30.24","Date":"14.10.2026"},
         {"id":38,"Code":"392","Ccy":"JPY","CcyNm_RU":"Иена","Nominal":"10","Rate":"793.10","Diff":"0.1","Date":"14.10.2026"},
         {"id":99,"Code":"000","Ccy":"XX","Nominal":"1","Rate":"abc","Date":"14.10.2026"}]
        """
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        let rates = try CBURateParser.parse(Data(json.utf8), calendar: calendar)
        XCTAssertEqual(rates.count, 3)
        XCTAssertEqual(rates.first { $0.currency == .usd }?.rate, Decimal(string: "11913.35"))
        XCTAssertEqual(rates.first { $0.currency == .jpy }?.rate, Decimal(string: "79.31"), "Номинал 10 делится")
        let components = calendar.dateComponents([.year, .month, .day], from: rates[0].date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 10)
        XCTAssertEqual(components.day, 14)
        XCTAssertThrowsError(try CBURateParser.parse(Data("{}".utf8), calendar: calendar))
    }
}

final class PeriodTests: XCTestCase {
    let periods = PeriodCalendar(timeZone: TimeZone(identifier: "Asia/Tashkent")!)

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h
        return periods.calendar.date(from: c)!
    }

    func testMonthRangesAndKeys() {
        let range = periods.monthRange(MonthKey(year: 2026, month: 2))
        XCTAssertEqual(periods.numberOfDays(in: range), 28)
        XCTAssertEqual(periods.dayCount(of: MonthKey(year: 2028, month: 2)), 29)
        XCTAssertEqual(MonthKey(year: 2026, month: 13), MonthKey(year: 2027, month: 1))
        XCTAssertEqual(MonthKey(year: 2026, month: 1).previous, MonthKey(year: 2025, month: 12))
        XCTAssertEqual(MonthKey(year: 2025, month: 11).distance(to: MonthKey(year: 2026, month: 2)), 3)
        XCTAssertEqual(MonthKey(string: "2026-10"), MonthKey(year: 2026, month: 10))
        XCTAssertEqual(MonthKey(year: 2026, month: 3).description, "2026-03")
    }

    func testPresets() {
        let now = date(2026, 10, 15, 1)
        let last7 = periods.range(for: .last7Days, now: now)
        XCTAssertEqual(periods.numberOfDays(in: last7), 7)
        XCTAssertTrue(last7.contains(now))
        XCTAssertEqual(last7.start, periods.startOfDay(date(2026, 10, 9)))

        let week = periods.range(for: .thisWeek, now: now)   // 15.10.2026 — четверг
        XCTAssertEqual(periods.calendar.component(.weekday, from: week.start), 2, "Неделя начинается с понедельника")
        XCTAssertEqual(week.start, periods.startOfDay(date(2026, 10, 12)))

        let previous = periods.previousRange(of: periods.range(for: .thisMonth, now: now))
        XCTAssertEqual(previous, periods.monthRange(MonthKey(year: 2026, month: 9)))
        XCTAssertEqual(periods.months(in: periods.range(for: .last90Days, now: now)).count, 4)
    }

    func testRecurrenceKeepsAnchorDay() {
        let anchor = date(2026, 1, 31)
        let cal = periods.calendar
        let feb = RecurrenceMath.occurrence(1, anchor: anchor, frequency: .monthly, interval: 1, calendar: cal)
        let mar = RecurrenceMath.occurrence(2, anchor: anchor, frequency: .monthly, interval: 1, calendar: cal)
        XCTAssertEqual(cal.component(.day, from: feb), 28)
        XCTAssertEqual(cal.component(.day, from: mar), 31, "31-е число не сползает на 28-е")

        let next = RecurrenceMath.nextOccurrence(after: date(2026, 6, 1), anchor: anchor, frequency: .monthly, interval: 1, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.month, .day], from: next), DateComponents(month: 6, day: 30))

        let weekly = RecurrenceMath.occurrences(from: date(2026, 10, 1), through: date(2026, 10, 31), anchor: date(2026, 9, 3), frequency: .weekly, interval: 2, calendar: cal)
        XCTAssertEqual(weekly.map { cal.component(.day, from: $0) }, [1, 15, 29])
    }
}

final class TextAndIDTests: XCTestCase {
    func testFoldAndWords() {
        XCTAssertEqual(TextNormalizer.fold("  Перевёл\u{00A0}МИЛЛИОН  сум "), "перевел миллион сум")
        XCTAssertEqual(TextNormalizer.words("Sakson besh ming so‘m!"), ["sakson", "besh", "ming", "so'm"])
        XCTAssertEqual(TextNormalizer.matchKey("Корзинка"), "korzinka")
        XCTAssertEqual(TextNormalizer.matchKey("KORZINKA"), "korzinka")
    }

    func testStableIDsAreDeterministicAndDistinct() {
        let a1 = DefaultCategories.id(for: SystemCategoryKey.cafe)
        let a2 = DefaultCategories.id(for: SystemCategoryKey.cafe)
        let b = DefaultCategories.id(for: SystemCategoryKey.groceries)
        XCTAssertEqual(a1, a2)
        XCTAssertNotEqual(a1, b)
        let ids = Set(DefaultCategories.make(language: .ru).map(\.id))
        XCTAssertEqual(ids.count, DefaultCategories.specs.count)
    }

    func testLastFourSanitizing() {
        XCTAssertEqual(Account.sanitizeLastFour("8600 1234 5678 4417"), "4417")
        XCTAssertNil(Account.sanitizeLastFour("44"))
        XCTAssertEqual(Account(bank: .uzum, name: " ", currency: .uzs).displayName, "Uzum Bank")
    }
}
