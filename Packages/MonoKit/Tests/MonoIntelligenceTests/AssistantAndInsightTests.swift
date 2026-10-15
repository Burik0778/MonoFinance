import XCTest
import MonoCore
import MonoAnalytics
@testable import MonoIntelligence

/// Детерминированный набор данных: июль–октябрь 2026.
struct Fixture {
    let periods = PeriodCalendar(timeZone: TimeZone(identifier: "Asia/Tashkent")!)
    let kapital = Account(bank: .kapitalbank, name: "Kapital", currency: .uzs)
    let uzum = Account(bank: .uzum, name: "Uzum", currency: .uzs)
    let categories = DefaultCategories.make(language: .ru)

    func cat(_ key: String) -> UUID { DefaultCategories.id(for: key) }
    func uzs(_ value: Int64) -> Money { Money(major: Decimal(value), currency: .uzs)! }
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h
        return periods.calendar.date(from: c)!
    }

    var now: Date { date(2026, 10, 15, 14) }

    var transactions: [FinanceTransaction] {
        var list: [FinanceTransaction] = [
            FinanceTransaction(kind: .adjustment, amount: uzs(3_000_000), accountID: kapital.id, date: date(2026, 7, 1), isOpeningBalance: true)
        ]
        for month in 7...10 {
            list.append(FinanceTransaction(kind: .income, amount: uzs(12_000_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.salary), date: date(2026, month, 5)))
            list.append(FinanceTransaction(kind: .expense, amount: uzs(3_500_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.housing), date: date(2026, month, 1)))
            list.append(FinanceTransaction(kind: .expense, amount: uzs(150_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.mobile), merchant: "Uztelecom", date: date(2026, month, 3)))
            for week in 0..<4 {
                let day = 2 + week * 7
                guard month < 10 || day <= 14 else { continue }
                list.append(FinanceTransaction(kind: .expense, amount: uzs(Int64(400_000 + week * 20_000)), accountID: kapital.id,
                                               categoryID: cat(SystemCategoryKey.groceries), merchant: "Korzinka", date: date(2026, month, day)))
            }
            // Кафе резко выросли в октябре.
            let cafeCount = month == 10 ? 9 : 3
            for index in 0..<cafeCount {
                list.append(FinanceTransaction(kind: .expense, amount: uzs(85_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.cafe),
                                               merchant: "EVOS", date: date(2026, month, 4 + index)))
            }
            list.append(FinanceTransaction(kind: .fee, amount: uzs(12_000), accountID: kapital.id, date: date(2026, month, 6)))
        }
        // Крупная разовая покупка.
        list.append(FinanceTransaction(kind: .expense, amount: uzs(4_200_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.electronics),
                                       merchant: "Mediapark", date: date(2026, 10, 12)))
        list.append(FinanceTransaction(kind: .transfer, amount: uzs(2_000_000), accountID: kapital.id, counterAccountID: uzum.id,
                                       counterAmount: uzs(2_000_000), date: date(2026, 9, 20)))
        return list
    }

    var analytics: AnalyticsEngine {
        AnalyticsEngine(transactions: transactions, accounts: [kapital, uzum], categories: categories,
                        converter: CurrencyConverter(base: .uzs, rateTable: [:]), periods: periods)
    }
}

final class AssistantTests: XCTestCase {
    let fixture = Fixture()

    func assistant(_ budgets: [Budget] = [], planned: [PlannedExpense] = []) -> AssistantEngine {
        AssistantEngine(analytics: fixture.analytics, budgets: budgets, planned: planned, language: .ru, now: fixture.now)
    }

    func testIntentRecognitionForAllExamplesFromSpec() {
        let a = assistant()
        let food = [SystemCategoryKey.groceries, SystemCategoryKey.cafe, SystemCategoryKey.delivery].map(fixture.cat)
        XCTAssertEqual(a.interpret("Сколько я потратил на еду за этот месяц?"), .spending(categoryIDs: food, merchant: nil, period: .thisMonth))
        XCTAssertEqual(a.interpret("На что я трачу больше всего денег?"), .topCategories(period: .thisMonth))
        XCTAssertEqual(a.interpret("Сравни мои расходы за август и сентябрь"),
                       .compare(.month(MonthKey(year: 2026, month: 9)), .month(MonthKey(year: 2026, month: 8))))
        XCTAssertEqual(a.interpret("Какие категории выросли сильнее всего?"), .categoryGrowth(current: .lastDays(30), previous: .lastDays(30)))
        XCTAssertEqual(a.interpret("Сколько я смогу накопить за три месяца при текущем темпе расходов?"), .savingsForecast(months: 3))
        XCTAssertEqual(a.interpret("Найди необычно крупные расходы"), .unusualExpenses(period: .lastDays(90)))
    }

    func testMoreIntents() {
        let a = assistant()
        XCTAssertEqual(a.interpret("Сколько ушло на такси на прошлой неделе?"),
                       .spending(categoryIDs: [fixture.cat(SystemCategoryKey.taxi)], merchant: nil, period: .lastWeek))
        XCTAssertEqual(a.interpret("Сколько я потратил в Корзинке в сентябре"),
                       .spending(categoryIDs: [], merchant: "Korzinka", period: .month(MonthKey(year: 2026, month: 9))))
        XCTAssertEqual(a.interpret("Сколько я заработал в августе?"), .income(period: .month(MonthKey(year: 2026, month: 8))))
        XCTAssertEqual(a.interpret("Какой у меня баланс?"), .balance)
        XCTAssertEqual(a.interpret("Средние расходы в день"), .averageDaily(period: .thisMonth))
        XCTAssertEqual(a.interpret("Покажи самые крупные покупки за месяц"), .largestExpenses(period: .thisMonth))
        XCTAssertEqual(a.interpret("Как дела с бюджетом?"), .budgets)
        XCTAssertEqual(a.interpret("Сколько отложу за полгода"), .savingsForecast(months: 6))
        XCTAssertEqual(a.interpret("расходы за последние 14 дней"), .spending(categoryIDs: [], merchant: nil, period: .lastDays(14)))
        XCTAssertEqual(a.interpret("Расскажи анекдот"), .unknown)
        XCTAssertEqual(a.interpret("Декабрь"), .unknown, "Один месяц без вопроса — не запрос")
    }

    func testFoodAnswerUsesRealNumbers() {
        let answer = assistant().ask("Сколько я потратил на еду за этот месяц?")
        // Октябрь: продукты 400+420 тыс. (2 и 9 числа), кафе 9 × 85 000.
        let expected = fixture.uzs(400_000 + 420_000 + 9 * 85_000)
        XCTAssertTrue(answer.hasData)
        XCTAssertEqual(answer.headline, MoneyFormatter(language: .ru).string(expected))
        XCTAssertTrue(answer.text.hasPrefix("В октябре на "), answer.text)
        XCTAssertEqual(answer.rows.count, 2)
    }

    func testCompareAnswer() {
        let answer = assistant().ask("Сравни мои расходы за август и сентябрь")
        XCTAssertTrue(answer.hasData)
        XCTAssertTrue(answer.text.contains("В сентябре"), answer.text)
        XCTAssertTrue(answer.text.contains("в августе"), answer.text)
        XCTAssertEqual(answer.headline, "0%", "Расходы в августе и сентябре совпадают")
    }

    func testGrowthFindsCafe() {
        let answer = assistant().ask("Какие категории выросли сильнее всего?")
        XCTAssertTrue(answer.hasData)
        XCTAssertEqual(answer.headline, "Техника", "Покупка в Mediapark — новая статья, самый большой рост")
        XCTAssertTrue(answer.rows.contains { $0.categoryID == fixture.cat(SystemCategoryKey.cafe) })
    }

    func testForecastAnswer() {
        let planned = [PlannedExpense(title: "Билеты", amount: fixture.uzs(3_000_000), date: fixture.date(2026, 11, 10))]
        let answer = assistant(planned: planned).ask("Сколько я смогу накопить за три месяца при текущем темпе расходов?")
        XCTAssertTrue(answer.hasData)
        XCTAssertNotNil(answer.note)
        XCTAssertTrue(answer.note!.contains("июль"), answer.note!)
        XCTAssertTrue(answer.text.contains("запланированные"), answer.text)
    }

    func testUnusualFindsMediapark() {
        let answer = assistant().ask("Найди необычно крупные расходы")
        XCTAssertTrue(answer.hasData)
        XCTAssertEqual(answer.rows.first?.title, "Mediapark")
    }

    func testEmptyDataIsHonest() {
        let empty = AssistantEngine(analytics: AnalyticsEngine(transactions: [], accounts: [], categories: fixture.categories,
                                                               converter: CurrencyConverter(base: .uzs, rateTable: [:]), periods: fixture.periods),
                                    language: .ru, now: fixture.now)
        let answer = empty.ask("Сколько я потратил на еду за этот месяц?")
        XCTAssertFalse(answer.hasData)
        XCTAssertTrue(answer.text.contains("не найдено"), answer.text)
        XCTAssertFalse(empty.ask("Сколько я смогу накопить за три месяца?").hasData)
    }

    func testEnglishAnswer() {
        let engine = AssistantEngine(analytics: fixture.analytics, language: .en, now: fixture.now)
        let answer = engine.ask("What do I spend the most on?")
        XCTAssertEqual(answer.intent, .topCategories(period: .thisMonth))
        XCTAssertTrue(answer.text.contains("most went to"), answer.text)
    }
}

final class InsightTests: XCTestCase {
    let fixture = Fixture()

    func testInsightsFromRealData() {
        let budget = Budget(categoryID: fixture.cat(SystemCategoryKey.cafe), limit: fixture.uzs(800_000), startMonth: MonthKey(year: 2026, month: 10))
        let rule = RecurringRule(title: "Интернет", amount: fixture.uzs(150_000), accountID: fixture.kapital.id,
                                 categoryID: fixture.cat(SystemCategoryKey.mobile), anchorDate: fixture.date(2026, 7, 3),
                                 nextDueDate: fixture.date(2026, 10, 18))
        let engine = InsightEngine(analytics: fixture.analytics, budgets: [budget], recurring: [rule], language: .ru, now: fixture.now)
        let insights = engine.insights(limit: 8)
        let kinds = insights.map(\.kind)
        XCTAssertEqual(kinds.first, .budget, "Превышенный бюджет — самый важный вывод")
        XCTAssertEqual(insights.first?.tone, .warning)
        XCTAssertTrue(kinds.contains(.monthToDate))
        XCTAssertTrue(kinds.contains(.categoryGrowth))
        XCTAssertTrue(kinds.contains(.upcoming))
        XCTAssertTrue(kinds.contains(.largestPurchase))
        XCTAssertTrue(kinds.contains(.fees))
        let upcoming = insights.first { $0.kind == .upcoming }!
        XCTAssertTrue(upcoming.text.hasPrefix("Через 3 дн."), upcoming.text)
        let growth = insights.first { $0.kind == .categoryGrowth }!
        XCTAssertEqual(growth.categoryID, fixture.cat(SystemCategoryKey.cafe))
    }

    func testNoDataNoInsights() {
        let engine = InsightEngine(analytics: AnalyticsEngine(transactions: [], accounts: [], categories: fixture.categories,
                                                              converter: CurrencyConverter(base: .uzs, rateTable: [:]), periods: fixture.periods),
                                   now: fixture.now)
        XCTAssertTrue(engine.insights().isEmpty, "Без данных — никаких выдуманных выводов")
    }
}

final class CategorizationTests: XCTestCase {
    let categories = DefaultCategories.make(language: .ru)
    func cat(_ key: String) -> UUID { DefaultCategories.id(for: key) }

    func testDirectoryKeywordsAndLearning() {
        let engine = CategorizationEngine(categories: categories, rules: [])
        XCTAssertEqual(engine.suggest(merchant: "KORZINKA CHILANZAR 12 TASHKENT UZ", text: nil, kind: .expense)?.categoryID, cat(SystemCategoryKey.groceries))
        XCTAssertEqual(engine.suggest(merchant: "YANDEX GO", text: nil, kind: .expense)?.categoryID, cat(SystemCategoryKey.taxi))
        XCTAssertEqual(engine.suggest(merchant: nil, text: "Кофейня у дома", kind: .expense)?.categoryID, cat(SystemCategoryKey.cafe))
        XCTAssertEqual(engine.suggest(merchant: nil, text: "оплата за свет", kind: .expense)?.categoryID, cat(SystemCategoryKey.utilities))
        XCTAssertEqual(engine.suggest(merchant: nil, text: "купил телефон", kind: .expense)?.categoryID, cat(SystemCategoryKey.electronics))
        XCTAssertEqual(engine.suggest(merchant: nil, text: "заплатил за телефон", kind: .expense)?.categoryID, cat(SystemCategoryKey.mobile))
        XCTAssertEqual(engine.suggest(merchant: nil, text: "зарплата за октябрь", kind: .income)?.categoryID, cat(SystemCategoryKey.salary))
        XCTAssertNil(engine.suggest(merchant: nil, text: "что-то непонятное", kind: .expense))
        XCTAssertNil(engine.suggest(merchant: "Korzinka", text: nil, kind: .transfer))

        let learned = CategorizationEngine(categories: categories, rules: [MerchantRule(key: CategorizationEngine.learningKey(for: "Корзинке"), categoryID: cat(SystemCategoryKey.home))])
        let suggestion = learned.suggest(merchant: "KORZINKA SERGELI", text: nil, kind: .expense)
        XCTAssertEqual(suggestion?.categoryID, cat(SystemCategoryKey.home))
        XCTAssertEqual(suggestion?.reason, .learned)
        XCTAssertEqual(CategorizationEngine.learningKey(for: "Корзинке"), "korzinka")
        XCTAssertEqual(CategorizationEngine.learningKey(for: "OOO ARTEL ELECTRONICS 123"), "artel electronics")
    }

    func testCustomCategoryByName() {
        let hobby = FinanceCategory(name: "Фотография", kind: .expense, icon: "camera.fill", color: .violet)
        let engine = CategorizationEngine(categories: categories + [hobby], rules: [])
        XCTAssertEqual(engine.suggest(merchant: nil, text: "объектив для фотографии", kind: .expense)?.categoryID, hobby.id)
    }

    func testMerchantNormalizer() {
        XCTAssertEqual(MerchantNormalizer.key("KORZINKA CHILANZAR 12 TASHKENT UZ"), "korzinka chilanzar")
        XCTAssertEqual(MerchantNormalizer.displayName("UZTELECOM INTERNET"), "Uztelecom Internet")
        XCTAssertEqual(MerchantNormalizer.displayName("Max Way"), "Max Way")
    }
}
