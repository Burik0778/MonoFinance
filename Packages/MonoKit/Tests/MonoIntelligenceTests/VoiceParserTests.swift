import XCTest
import MonoCore
@testable import MonoIntelligence

final class VoiceParserTests: XCTestCase {
    let periods = PeriodCalendar(timeZone: TimeZone(identifier: "Asia/Tashkent")!)
    let kapital = Account(bank: .kapitalbank, name: "Kapital Humo", kind: .card, paymentSystem: .humo, currency: .uzs, lastFour: "4417")
    let uzum = Account(bank: .uzum, name: "Uzum Visa", kind: .card, paymentSystem: .visa, currency: .uzs)
    let ofb = Account(bank: .orientFinans, name: "OFB долларовая", kind: .card, paymentSystem: .visa, currency: .usd)
    let trast = Account(bank: .trastbank, name: "Накопительная", kind: .savings, currency: .uzs)
    let cash = Account(bank: .cash, name: "Кошелёк", kind: .cash, currency: .uzs)
    let categories = DefaultCategories.make(language: .ru)

    /// Четверг, 15 октября 2026, 14:00 по Ташкенту.
    var now: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 15; c.hour = 14
        return periods.calendar.date(from: c)!
    }

    func parser(accounts: [Account]? = nil, defaultAccount: UUID? = nil, rules: [MerchantRule] = []) -> VoiceCommandParser {
        VoiceCommandParser(context: VoiceParserContext(
            accounts: accounts ?? [kapital, uzum, ofb, trast, cash],
            categories: categories,
            merchantRules: rules,
            defaultAccountID: defaultAccount ?? kapital.id,
            converter: CurrencyConverter(base: .uzs, rateTable: [.usd: Decimal(string: "11913.35")!]),
            now: now,
            periods: periods
        ))
    }

    func cat(_ key: String) -> UUID { DefaultCategories.id(for: key) }
    func day(_ date: Date) -> DateComponents { periods.calendar.dateComponents([.year, .month, .day], from: date) }

    // MARK: Примеры из ТЗ

    func testLunchToday() {
        let result = parser().parse("Потратил 85 тысяч сум на обед сегодня")
        XCTAssertEqual(result.drafts.count, 1)
        let draft = result.drafts[0]
        XCTAssertEqual(draft.kind, .expense)
        XCTAssertEqual(draft.amount, 85_000)
        XCTAssertEqual(draft.currency, .uzs)
        XCTAssertEqual(draft.categoryID, cat(SystemCategoryKey.cafe))
        XCTAssertEqual(draft.accountID, kapital.id)
        XCTAssertEqual(draft.issues, [.usedDefaultAccount], "Счёт по умолчанию показывается явно")
        XCTAssertTrue(draft.isReady)
        XCTAssertEqual(day(draft.date), day(now))
    }

    /// Фразы ровно в той формулировке, в какой их дал владелец приложения.
    func testOwnerExamplesVerbatim() {
        let lunch = parser().parse("Потратил 85 тысяч на обед").drafts
        XCTAssertEqual(lunch.count, 1)
        XCTAssertEqual(lunch.first?.kind, .expense)
        XCTAssertEqual(lunch.first?.amount, 85_000)
        XCTAssertEqual(lunch.first?.categoryID, cat(SystemCategoryKey.cafe))
        XCTAssertEqual(lunch.first.map { day($0.date) }, day(now))

        let groceries = parser(defaultAccount: uzum.id).parse("Вчера купил продукты на 230 тысяч с Капиталбанка").drafts
        XCTAssertEqual(groceries.count, 1)
        XCTAssertEqual(groceries.first?.amount, 230_000)
        XCTAssertEqual(groceries.first?.categoryID, cat(SystemCategoryKey.groceries))
        XCTAssertEqual(groceries.first?.accountID, kapital.id)
        XCTAssertEqual(groceries.first.map { day($0.date) }, day(periods.addingDays(-1, to: now)))

        let transfer = parser().parse("Перевёл миллион сум с Капиталбанка на Узум").drafts
        XCTAssertEqual(transfer.count, 1)
        XCTAssertEqual(transfer.first?.kind, .transfer, "Перевод между своими счетами — не расход")
        XCTAssertEqual(transfer.first?.amount, 1_000_000)
        XCTAssertEqual(transfer.first?.accountID, kapital.id)
        XCTAssertEqual(transfer.first?.counterAccountID, uzum.id)

        let two = parser().parse("Сегодня потратил 120 тысяч на такси и 50 тысяч на кофе").drafts
        XCTAssertEqual(two.count, 2)
        XCTAssertEqual(two.map(\.amount), [120_000, 50_000])
        XCTAssertEqual(two.first?.categoryID, cat(SystemCategoryKey.taxi))
        XCTAssertEqual(two.last?.categoryID, cat(SystemCategoryKey.cafe))
        XCTAssertTrue(two.allSatisfy { $0.kind == .expense && $0.isReady })
    }

    func testFuel() {
        let draft = parser().parse("Заправился на 300 тысяч").drafts[0]
        XCTAssertEqual(draft.kind, .expense)
        XCTAssertEqual(draft.amount, 300_000)
        XCTAssertEqual(draft.categoryID, cat(SystemCategoryKey.fuel))
        XCTAssertTrue(draft.isReady)
    }

    func testGroceriesYesterdayWithMerchantAndAccount() {
        let draft = parser(defaultAccount: uzum.id).parse("Вчера купил продукты в Корзинке на 245 тысяч с карты Капиталбанка").drafts[0]
        XCTAssertEqual(draft.kind, .expense)
        XCTAssertEqual(draft.amount, 245_000)
        XCTAssertEqual(draft.merchant, "Korzinka")
        XCTAssertEqual(draft.categoryID, cat(SystemCategoryKey.groceries))
        XCTAssertEqual(draft.accountID, kapital.id, "Счёт из фразы важнее счёта по умолчанию")
        XCTAssertEqual(day(draft.date), DateComponents(year: 2026, month: 10, day: 14))
        XCTAssertTrue(draft.issues.isEmpty)
    }

    func testTransferBetweenOwnAccounts() {
        let draft = parser().parse("Перевёл миллион сум с Капиталбанка на Узум").drafts[0]
        XCTAssertEqual(draft.kind, .transfer)
        XCTAssertEqual(draft.amount, 1_000_000)
        XCTAssertEqual(draft.accountID, kapital.id)
        XCTAssertEqual(draft.counterAccountID, uzum.id)
        XCTAssertNil(draft.categoryID)
        XCTAssertTrue(draft.isReady)
        let transaction = draft.makeTransaction(accounts: accountMap)
        XCTAssertEqual(transaction?.counterAmount, Money(major: 1_000_000, currency: .uzs))
    }

    func testIncomeInDollarsPicksDollarAccount() {
        let draft = parser().parse("Получил 500 долларов").drafts[0]
        XCTAssertEqual(draft.kind, .income)
        XCTAssertEqual(draft.amount, 500)
        XCTAssertEqual(draft.currency, .usd)
        XCTAssertEqual(draft.accountID, ofb.id, "Единственный долларовый счёт")
        XCTAssertTrue(draft.issues.contains(.accountInferredFromCurrency))
        XCTAssertTrue(draft.isReady)
    }

    func testIncomeInDollarsWithoutDollarAccountAsksForClarification() {
        let draft = parser(accounts: [kapital, uzum]).parse("Получил 500 долларов").drafts[0]
        XCTAssertEqual(draft.currency, .usd)
        XCTAssertTrue(draft.issues.contains(.currencyMismatch(spoken: .usd, account: .uzs)))
        XCTAssertFalse(draft.isReady)
    }

    func testTwoExpensesInOnePhrase() {
        let drafts = parser().parse("Сегодня потратил 120 тысяч на такси и 75 тысяч на кофе").drafts
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts.map(\.amount), [120_000, 75_000])
        XCTAssertEqual(drafts.map(\.categoryID), [cat(SystemCategoryKey.taxi), cat(SystemCategoryKey.cafe)])
        XCTAssertEqual(drafts.map(\.kind), [.expense, .expense])
        XCTAssertTrue(drafts.allSatisfy { day($0.date) == day(now) })
    }

    // MARK: Числа

    func testSpokenNumbers() {
        let cases: [(String, Decimal)] = [
            ("потратил двести сорок пять тысяч на продукты", 245_000),
            ("заплатил полтора миллиона за аренду", 1_500_000),
            ("перевёл полмиллиона маме", 500_000),
            ("потратил миллион двести на ремонт", 1_200_000),
            ("купил куртку за 1 200 000", 1_200_000),
            ("потратил 85к на обед", 85_000),
            ("заплатил 2,5 млн за ноутбук", 2_500_000),
            ("потратил лям на подарки", 1_000_000),
            ("отдал тысячу за парковку", 1_000),
            ("заплатил сто двадцать тысяч за интернет", 120_000),
            ("потратил два миллиона пятьсот тысяч на телефон", 2_500_000),
            ("заплатил 245,000 за свет", 245_000)
        ]
        for (phrase, expected) in cases {
            let draft = parser().parse(phrase).drafts.first
            XCTAssertEqual(draft?.amount, expected, phrase)
        }
    }

    func testAmbiguousSmallAmountAsksForThousands() {
        let draft = parser().parse("кофе за 25").drafts[0]
        XCTAssertEqual(draft.amount, 25)
        XCTAssertEqual(draft.categoryID, cat(SystemCategoryKey.cafe))
        XCTAssertTrue(draft.issues.contains(.amountMayNeedThousands(suggested: 25_000)))
        XCTAssertFalse(draft.isReady)
        var fixed = draft
        fixed.setAmount(25_000, accounts: accountMap, converter: nil)
        XCTAssertTrue(fixed.isReady)
    }

    func testQuantitiesDatesAndCardDigitsAreNotAmounts() {
        let draft = parser().parse("3 октября купил 2 кг мяса за 180 тысяч с карты 4417").drafts
        XCTAssertEqual(draft.count, 1)
        XCTAssertEqual(draft[0].amount, 180_000)
        XCTAssertEqual(draft[0].accountID, kapital.id, "Карта по последним цифрам")
        XCTAssertEqual(day(draft[0].date), DateComponents(year: 2026, month: 10, day: 3))
        XCTAssertEqual(draft[0].categoryID, cat(SystemCategoryKey.groceries))
    }

    func testOrdinalDateAndFutureDateGoesToPreviousYear() {
        let october = parser().parse("двадцать первого сентября заплатил 50 тысяч в аптеке").drafts[0]
        XCTAssertEqual(day(october.date), DateComponents(year: 2026, month: 9, day: 21))
        XCTAssertEqual(october.categoryID, cat(SystemCategoryKey.health))
        let december = parser().parse("25 декабря потратил 300 тысяч на подарки").drafts[0]
        XCTAssertEqual(day(december.date), DateComponents(year: 2025, month: 12, day: 25))
    }

    func testWeekdays() {
        // 15.10.2026 — четверг. «В понедельник» — 12.10, «в прошлую пятницу» — 9.10.
        let monday = parser().parse("в понедельник потратил 40 тысяч на такси").drafts[0]
        XCTAssertEqual(day(monday.date), DateComponents(year: 2026, month: 10, day: 12))
        let friday = parser().parse("в прошлую пятницу заплатил 90 тысяч за кино").drafts[0]
        XCTAssertEqual(day(friday.date), DateComponents(year: 2026, month: 10, day: 9))
        XCTAssertEqual(friday.categoryID, cat(SystemCategoryKey.entertainment))
    }

    // MARK: Типы операций

    func testTransferToPersonIsExpense() {
        let draft = parser().parse("перевёл маме 500 тысяч").drafts[0]
        XCTAssertEqual(draft.kind, .expense)
        XCTAssertEqual(draft.categoryID, cat(SystemCategoryKey.transfersOut))
    }

    func testRefundFeeAndDebt() {
        let refund = parser().parse("вернули 450 тысяч за кроссовки").drafts[0]
        XCTAssertEqual(refund.kind, .refund)
        XCTAssertEqual(refund.categoryID, cat(SystemCategoryKey.clothes))

        let fee = parser().parse("комиссия 5 тысяч за перевод").drafts[0]
        XCTAssertEqual(fee.kind, .fee)
        XCTAssertNil(fee.categoryID)

        let debt = parser().parse("друг вернул долг, мне вернули 300 тысяч долг").drafts[0]
        XCTAssertEqual(debt.kind, .income)
        XCTAssertEqual(debt.categoryID, cat(SystemCategoryKey.debtReturn))

        let salary = parser().parse("пришла зарплата 12 миллионов на узум").drafts[0]
        XCTAssertEqual(salary.kind, .income)
        XCTAssertEqual(salary.categoryID, cat(SystemCategoryKey.salary))
        XCTAssertEqual(salary.accountID, uzum.id, "Доход зачисляется на названный счёт")
    }

    func testTopUpPhoneIsExpenseButTopUpCardIsTransfer() {
        let phone = parser().parse("пополнил телефон на 50 тысяч").drafts[0]
        XCTAssertEqual(phone.kind, .expense)
        XCTAssertEqual(phone.categoryID, cat(SystemCategoryKey.mobile))

        let card = parser().parse("пополнил накопительную на 2 миллиона с узума").drafts[0]
        XCTAssertEqual(card.kind, .transfer)
        XCTAssertEqual(card.accountID, uzum.id)
        XCTAssertEqual(card.counterAccountID, trast.id)
    }

    func testTransferWithoutSourceUsesDefaultAndShowsIt() {
        let draft = parser().parse("перекинул 300 тысяч на Траст").drafts[0]
        XCTAssertEqual(draft.kind, .transfer)
        XCTAssertEqual(draft.accountID, kapital.id)
        XCTAssertEqual(draft.counterAccountID, trast.id)
        XCTAssertTrue(draft.issues.contains(.usedDefaultAccount))
        XCTAssertTrue(draft.isReady)
    }

    func testCrossCurrencyTransferNeedsReceivedAmount() {
        let draft = parser().parse("перевёл 100 долларов с ОФБ на Капиталбанк").drafts[0]
        XCTAssertEqual(draft.kind, .transfer)
        XCTAssertEqual(draft.accountID, ofb.id)
        XCTAssertEqual(draft.counterAccountID, kapital.id)
        guard case .needsCounterAmount(let suggested)? = draft.issues.first(where: { if case .needsCounterAmount = $0 { return true } else { return false } }) else {
            return XCTFail("Нужна сумма зачисления")
        }
        XCTAssertEqual(suggested, Decimal(string: "1191335"), "Подсказка по курсу ЦБ")
        var fixed = draft
        fixed.counterAmount = 1_190_000
        fixed.revalidate(accounts: accountMap, converter: nil)
        XCTAssertTrue(fixed.isReady)
        XCTAssertEqual(fixed.makeTransaction(accounts: accountMap)?.counterAmount, Money(major: 1_190_000, currency: .uzs))
    }

    func testUnknownBankIsReportedNotGuessed() {
        let draft = parser(accounts: [kapital, uzum]).parse("потратил 100 тысяч на такси с Трастбанка").drafts[0]
        XCTAssertNil(draft.accountID)
        XCTAssertTrue(draft.issues.contains(.accountNotFound(mention: "Trastbank")))
        XCTAssertFalse(draft.isReady)
    }

    func testCashAndPaymentSystem() {
        let cashDraft = parser().parse("потратил наличными 30 тысяч на самсу").drafts[0]
        XCTAssertEqual(cashDraft.accountID, cash.id)
        XCTAssertEqual(cashDraft.categoryID, cat(SystemCategoryKey.cafe))

        let humo = parser(defaultAccount: uzum.id).parse("оплатил хумо 60 тысяч за интернет").drafts[0]
        XCTAssertEqual(humo.accountID, kapital.id)
        XCTAssertEqual(humo.categoryID, cat(SystemCategoryKey.mobile))
    }

    func testAmbiguousAccountWithinSameBank() {
        let second = Account(bank: .kapitalbank, name: "Kapital Visa", kind: .card, paymentSystem: .visa, currency: .uzs)
        let draft = parser(accounts: [kapital, second, uzum], defaultAccount: uzum.id).parse("купил кроссовки за 900 тысяч с капиталбанка").drafts[0]
        XCTAssertTrue(draft.issues.contains(.ambiguousAccount(candidates: [kapital.id, second.id])))
        XCTAssertFalse(draft.isReady)
        var fixed = draft
        fixed.selectAccount(second.id, accounts: [kapital.id: kapital, second.id: second, uzum.id: uzum], converter: nil)
        XCTAssertTrue(fixed.isReady)
        XCTAssertEqual(fixed.accountID, second.id)
    }

    // MARK: Продавцы и обучение

    func testLearnedRuleWins() {
        let rule = MerchantRule(key: "korzinka", categoryID: cat(SystemCategoryKey.home))
        let draft = parser(rules: [rule]).parse("купил в корзинке на 300 тысяч").drafts[0]
        XCTAssertEqual(draft.merchant, "Korzinka")
        XCTAssertEqual(draft.categoryID, cat(SystemCategoryKey.home), "Выбор пользователя важнее справочника")
    }

    func testCapitalizedUnknownMerchant() {
        let draft = parser().parse("купил кроссовки в Адидасе за 800 тысяч").drafts[0]
        XCTAssertEqual(draft.merchant, "Адидас")
        XCTAssertEqual(draft.categoryID, cat(SystemCategoryKey.clothes))
        let city = parser().parse("пообедал в Ташкенте за 90 тысяч").drafts[0]
        XCTAssertNil(city.merchant, "Город — не продавец")
    }

    func testMerchantsFromDirectory() {
        XCTAssertEqual(parser().parse("Яндекс Го 32 тысячи").drafts.first?.categoryID, cat(SystemCategoryKey.taxi))
        XCTAssertEqual(parser().parse("заказал на узум маркете на 400 тысяч").drafts.first?.merchant, "Uzum Market")
        let evos = parser().parse("эвос 65 тысяч").drafts.first
        XCTAssertEqual(evos?.merchant, "EVOS")
        XCTAssertEqual(evos?.accountID, kapital.id, "«узум маркет» не считается счётом Uzum")
    }

    // MARK: Узбекский и английский

    func testUzbekPhrase() {
        let draft = parser().parse("Bugun tushlikka sakson besh ming so'm sarfladim").drafts[0]
        XCTAssertEqual(draft.kind, .expense)
        XCTAssertEqual(draft.amount, 85_000)
        XCTAssertEqual(draft.currency, .uzs)
        XCTAssertEqual(draft.categoryID, cat(SystemCategoryKey.cafe))

        let transfer = parser().parse("Kapitalbankdan Uzumga bir yarim million o'tkazdim").drafts[0]
        XCTAssertEqual(transfer.kind, .transfer)
        XCTAssertEqual(transfer.amount, 1_500_000)
        XCTAssertEqual(transfer.accountID, kapital.id)
        XCTAssertEqual(transfer.counterAccountID, uzum.id)

        let kecha = parser().parse("kecha taksi uchun 40 ming to'ladim").drafts[0]
        XCTAssertEqual(day(kecha.date), DateComponents(year: 2026, month: 10, day: 14))
        XCTAssertEqual(kecha.categoryID, cat(SystemCategoryKey.taxi))
    }

    func testEnglishPhrase() {
        let draft = parser().parse("Spent $20 on coffee yesterday").drafts[0]
        XCTAssertEqual(draft.amount, 20)
        XCTAssertEqual(draft.currency, .usd)
        XCTAssertEqual(draft.accountID, ofb.id)
        XCTAssertEqual(draft.categoryID, cat(SystemCategoryKey.cafe))
        XCTAssertEqual(day(draft.date), DateComponents(year: 2026, month: 10, day: 14))
    }

    // MARK: Граничные случаи

    func testNoAmountGivesDraftToFill() {
        let result = parser().parse("купил продукты в корзинке")
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertNil(result.drafts[0].amount)
        XCTAssertTrue(result.drafts[0].issues.contains(.missingAmount))
        XCTAssertEqual(result.drafts[0].merchant, "Korzinka")
    }

    func testIrrelevantPhraseGivesNothing() {
        XCTAssertTrue(parser().parse("какая сегодня погода").drafts.isEmpty)
        XCTAssertTrue(parser().parse("").drafts.isEmpty)
    }

    func testPurposeBeforeAmountSegmentation() {
        let drafts = parser().parse("на такси 120 тысяч на кофе 75 тысяч").drafts
        XCTAssertEqual(drafts.map(\.categoryID), [cat(SystemCategoryKey.taxi), cat(SystemCategoryKey.cafe)])
        let commas = parser().parse("такси 40 тысяч, обед 90 тысяч, продукты 210 тысяч").drafts
        XCTAssertEqual(commas.map(\.amount), [40_000, 90_000, 210_000])
        XCTAssertEqual(commas.map(\.categoryID), [cat(SystemCategoryKey.taxi), cat(SystemCategoryKey.cafe), cat(SystemCategoryKey.groceries)])
    }

    func testSharedAccountAndDateAcrossSegments() {
        let drafts = parser(defaultAccount: uzum.id).parse("вчера потратил 120 тысяч на такси и 75 тысяч на кофе с карты Капиталбанка").drafts
        XCTAssertEqual(drafts.count, 2)
        XCTAssertTrue(drafts.allSatisfy { $0.accountID == kapital.id })
        XCTAssertTrue(drafts.allSatisfy { day($0.date) == DateComponents(year: 2026, month: 10, day: 14) })
    }

    func testMixedIncomeAndExpense() {
        let drafts = parser().parse("получил зарплату 10 миллионов и потратил 200 тысяч на продукты").drafts
        XCTAssertEqual(drafts.map(\.kind), [.income, .expense])
        XCTAssertEqual(drafts.map(\.categoryID), [cat(SystemCategoryKey.salary), cat(SystemCategoryKey.groceries)])
    }

    func testTokenizerNumberFormats() {
        XCTAssertEqual(VoiceTokenizer.parseNumber("1,5")?.value, Decimal(string: "1.5"))
        XCTAssertEqual(VoiceTokenizer.parseNumber("12.500")?.value, 12_500)
        XCTAssertEqual(VoiceTokenizer.parseNumber("1.200.000")?.value, 1_200_000)
        XCTAssertEqual(VoiceTokenizer.parseNumber("1,234.56")?.value, Decimal(string: "1234.56"))
        let merged = VoiceTokenizer.tokenize("1 200 000 сум")
        XCTAssertEqual(merged.first?.value, 1_200_000)
        XCTAssertEqual(merged.count, 2)
        let separate = VoiceTokenizer.tokenize("2026 000")
        XCTAssertEqual(separate.count, 2, "Четырёхзначное число не склеивается с группой")
    }

    var accountMap: [UUID: Account] {
        Dictionary(uniqueKeysWithValues: [kapital, uzum, ofb, trast, cash].map { ($0.id, $0) })
    }
}
