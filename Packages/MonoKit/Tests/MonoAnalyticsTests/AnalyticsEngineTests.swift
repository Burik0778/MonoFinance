import XCTest
import MonoCore
@testable import MonoAnalytics

final class AnalyticsEngineTests: XCTestCase {
    let periods = PeriodCalendar(timeZone: TimeZone(identifier: "Asia/Tashkent")!)
    let kapital = Account(bank: .kapitalbank, name: "Kapital", currency: .uzs)
    let uzum = Account(bank: .uzum, name: "Uzum", currency: .uzs)
    let dollar = Account(bank: .orientFinans, name: "OFB", currency: .usd)
    let euro = Account(bank: .other, name: "EUR wallet", currency: .eur)
    let categories = DefaultCategories.make(language: .ru)
    let converter = CurrencyConverter(base: .uzs, rateTable: [.usd: Decimal(12_000)])

    func uzs(_ v: Int64) -> Money { Money(major: Decimal(v), currency: .uzs)! }
    func usd(_ v: Int64) -> Money { Money(major: Decimal(v), currency: .usd)! }
    func cat(_ key: String) -> UUID { DefaultCategories.id(for: key) }
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h
        return periods.calendar.date(from: c)!
    }

    func engine(_ transactions: [FinanceTransaction]) -> AnalyticsEngine {
        AnalyticsEngine(transactions: transactions, accounts: [kapital, uzum, dollar, euro], categories: categories,
                        converter: converter, periods: periods)
    }

    var sample: [FinanceTransaction] {
        [
            FinanceTransaction(kind: .adjustment, amount: uzs(10_000_000), accountID: kapital.id, date: date(2026, 9, 1), isOpeningBalance: true),
            FinanceTransaction(kind: .adjustment, amount: usd(1_000), accountID: dollar.id, date: date(2026, 9, 1), isOpeningBalance: true),
            FinanceTransaction(kind: .income, amount: uzs(12_000_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.salary), date: date(2026, 10, 5)),
            FinanceTransaction(kind: .income, amount: usd(500), accountID: dollar.id, categoryID: cat(SystemCategoryKey.freelance), date: date(2026, 10, 7)),
            FinanceTransaction(kind: .expense, amount: uzs(245_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.groceries), merchant: "Korzinka", date: date(2026, 10, 8)),
            FinanceTransaction(kind: .expense, amount: uzs(85_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.cafe), merchant: "EVOS", date: date(2026, 10, 9)),
            FinanceTransaction(kind: .expense, amount: uzs(400_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.clothes), date: date(2026, 10, 10)),
            FinanceTransaction(kind: .refund, amount: uzs(100_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.clothes), date: date(2026, 10, 11)),
            FinanceTransaction(kind: .fee, amount: uzs(5_000), accountID: kapital.id, date: date(2026, 10, 11)),
            FinanceTransaction(kind: .transfer, amount: uzs(1_000_000), accountID: kapital.id, counterAccountID: uzum.id, counterAmount: uzs(1_000_000), date: date(2026, 10, 12)),
            FinanceTransaction(kind: .expense, amount: Money(minorUnits: 5_000, currency: .eur), accountID: euro.id, date: date(2026, 10, 12)),
            FinanceTransaction(kind: .expense, amount: uzs(300_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.groceries), merchant: "Korzinka", date: date(2026, 9, 20))
        ]
    }

    func testSummaryExcludesTransfersAndAdjustments() {
        let summary = engine(sample).summary(periods.monthRange(MonthKey(year: 2026, month: 10)))
        XCTAssertEqual(summary.income, uzs(12_000_000 + 6_000_000), "500 USD × 12 000")
        XCTAssertEqual(summary.grossExpenses, uzs(245_000 + 85_000 + 400_000))
        XCTAssertEqual(summary.refunds, uzs(100_000))
        XCTAssertEqual(summary.spending, uzs(630_000))
        XCTAssertEqual(summary.fees, uzs(5_000))
        XCTAssertEqual(summary.outflow, uzs(635_000))
        XCTAssertEqual(summary.net, uzs(18_000_000 - 635_000))
        XCTAssertEqual(summary.excludedCurrencies, [.eur], "EUR без курса не придумывается")
        XCTAssertEqual(summary.transactionCount, 7)
    }

    func testCategoryBreakdownAppliesRefunds() {
        let items = engine(sample).spendingByCategory(periods.monthRange(MonthKey(year: 2026, month: 10)))
        XCTAssertEqual(items.map(\.categoryID), [cat(SystemCategoryKey.clothes), cat(SystemCategoryKey.groceries), cat(SystemCategoryKey.cafe)])
        XCTAssertEqual(items[0].amount, uzs(300_000))
        XCTAssertEqual(items.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-9)
        let income = engine(sample).incomeByCategory(periods.monthRange(MonthKey(year: 2026, month: 10)))
        XCTAssertEqual(income.first?.categoryID, cat(SystemCategoryKey.salary))
    }

    func testSeriesIncludesEmptyBuckets() {
        let range = DateRange(start: date(2026, 10, 8, 0), end: date(2026, 10, 13, 0))
        let points = engine(sample).series(range, granularity: .day)
        XCTAssertEqual(points.count, 5)
        XCTAssertEqual(points[0].spending, uzs(245_000))
        XCTAssertEqual(points[3].spending, uzs(-100_000), "Возврат 11-го уменьшает расходы дня")
        XCTAssertEqual(points[3].fees, uzs(5_000))
        XCTAssertEqual(points[4].spending, uzs(0), "Перевод 12-го — не расход")
        let monthly = engine(sample).series(DateRange(start: date(2026, 9, 1, 0), end: date(2026, 11, 1, 0)), granularity: .month)
        XCTAssertEqual(monthly.count, 2)
        XCTAssertEqual(monthly[0].spending, uzs(300_000))
    }

    func testTotalBalanceAndHistory() {
        let analytics = engine(sample)
        let total = analytics.totalBalance()
        // UZS: 10 000 000 + 12 000 000 − 245 000 − 85 000 − 400 000 + 100 000 − 5 000 − 300 000 = 21 065 000 (перевод внутри)
        // USD: 1 500 × 12 000 = 18 000 000
        XCTAssertEqual(total.total, uzs(21_065_000 + 18_000_000))
        XCTAssertEqual(total.excluded, [.eur], "Счёт в EUR с ненулевым балансом без курса")

        let history = analytics.balanceHistory(DateRange(start: date(2026, 10, 10, 0), end: date(2026, 10, 13, 0)))
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.last?.balance, total.total, "Последняя точка совпадает с текущим балансом")
        XCTAssertEqual(history[1].balance - history[0].balance, uzs(100_000 - 5_000), "11-го: возврат минус комиссия")
    }

    func testComparisonAndAverages() {
        let analytics = engine(sample)
        let october = periods.monthRange(MonthKey(year: 2026, month: 10))
        let comparison = analytics.compare(october, with: periods.previousRange(of: october))
        XCTAssertEqual(comparison.previous.spending, uzs(300_000))
        let groceries = comparison.categories.first { $0.categoryID == cat(SystemCategoryKey.groceries) }!
        XCTAssertEqual(groceries.change, uzs(-55_000))
        XCTAssertEqual(groceries.changeRatio!, -55.0 / 300.0, accuracy: 1e-9)
        XCTAssertNil(comparison.categories.first { $0.categoryID == cat(SystemCategoryKey.cafe) }?.changeRatio)

        let average = analytics.averageDailySpending(october, now: date(2026, 10, 15, 9))
        XCTAssertEqual(average, uzs(42_000), "630 000 / 15 дней")
        XCTAssertEqual(analytics.largestExpenses(october, limit: 1).first?.categoryID, cat(SystemCategoryKey.clothes))
    }

    func testMerchantsAccountsAndMandatory() {
        let analytics = engine(sample)
        let range = DateRange(start: date(2026, 9, 1, 0), end: date(2026, 11, 1, 0))
        let merchants = analytics.topMerchants(range)
        XCTAssertEqual(merchants.first?.key, "korzinka")
        XCTAssertEqual(merchants.first?.count, 2)
        XCTAssertEqual(merchants.first?.total, uzs(545_000))

        let flows = analytics.flowsByAccount(periods.monthRange(MonthKey(year: 2026, month: 10)))
        let kapitalFlow = flows.first { $0.accountID == kapital.id }!
        XCTAssertEqual(kapitalFlow.transfersOut, uzs(1_000_000))
        XCTAssertEqual(flows.first { $0.accountID == uzum.id }?.transfersIn, uzs(1_000_000))

        let split = analytics.mandatorySplit(periods.monthRange(MonthKey(year: 2026, month: 10)))
        XCTAssertEqual(split.mandatory, uzs(245_000), "Продукты — обязательные")
        XCTAssertEqual(split.optional, uzs(385_000))
    }

    func testMonthToDateIsFair() {
        let analytics = engine(sample)
        let mtd = analytics.monthToDate(now: date(2026, 10, 10, 23))
        XCTAssertEqual(mtd.current, uzs(730_000))
        XCTAssertEqual(mtd.previous, uzs(0), "До 10 сентября трат не было — покупка 20-го не учитывается")
        XCTAssertEqual(mtd.day, 10)
    }

    func testRecurringDetection() {
        var txs: [FinanceTransaction] = []
        for month in 4...9 {
            txs.append(FinanceTransaction(kind: .expense, amount: uzs(150_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.mobile),
                                          merchant: "UZTELECOM INTERNET", date: date(2026, month, 3)))
        }
        for week in 0..<6 {
            txs.append(FinanceTransaction(kind: .expense, amount: uzs(60_000 + Int64(week) * 1_000), accountID: kapital.id,
                                          merchant: "Fitness Club", date: periods.addingDays(7 * week, to: date(2026, 8, 20))))
        }
        for day in [1, 2, 4, 9, 10, 21] {
            txs.append(FinanceTransaction(kind: .expense, amount: uzs(Int64(day) * 13_000), accountID: kapital.id, merchant: "Random Cafe", date: date(2026, 9, day)))
        }
        for month in 6...9 {
            txs.append(FinanceTransaction(kind: .expense, amount: uzs(3_500_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.housing), date: date(2026, month, 1)))
        }
        let candidates = engine(txs).recurringCandidates(now: date(2026, 10, 1, 9))
        let names = Set(candidates.map(\.name))
        XCTAssertTrue(names.contains("Uztelecom Internet"))
        XCTAssertTrue(names.contains("Fitness Club"))
        XCTAssertTrue(names.contains("Жильё и аренда"), "Без продавца — по категории и сумме")
        XCTAssertFalse(names.contains("Random Cafe"))
        let internet = candidates.first { $0.name == "Uztelecom Internet" }!
        XCTAssertEqual(internet.frequency, .monthly)
        XCTAssertEqual(internet.typicalAmount, uzs(150_000))
        XCTAssertEqual(periods.calendar.dateComponents([.month, .day], from: internet.nextExpectedDate), DateComponents(month: 10, day: 3))
        XCTAssertEqual(candidates.first { $0.name == "Fitness Club" }?.frequency, .weekly)
    }

    func testUnusualExpenses() {
        var txs: [FinanceTransaction] = []
        for day in 1...10 {
            txs.append(FinanceTransaction(kind: .expense, amount: uzs(40_000 + Int64(day) * 1_000), accountID: kapital.id,
                                          categoryID: cat(SystemCategoryKey.cafe), date: date(2026, 9, day)))
        }
        let big = FinanceTransaction(kind: .expense, amount: uzs(600_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.cafe), date: date(2026, 10, 3))
        let normal = FinanceTransaction(kind: .expense, amount: uzs(52_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.cafe), date: date(2026, 10, 4))
        txs += [big, normal]
        let result = engine(txs).unusualExpenses(periods.monthRange(MonthKey(year: 2026, month: 10)))
        XCTAssertEqual(result.map(\.transaction.id), [big.id])
        XCTAssertEqual(result.first?.typical, uzs(46_500))
        XCTAssertTrue(engine(Array(txs.prefix(3))).unusualExpenses(periods.monthRange(MonthKey(year: 2026, month: 10))).isEmpty, "Мало данных — нет выводов")
    }

    func testSavingsForecast() {
        var txs: [FinanceTransaction] = []
        for month in 7...9 {
            txs.append(FinanceTransaction(kind: .income, amount: uzs(10_000_000), accountID: kapital.id, date: date(2026, month, 2)))
            txs.append(FinanceTransaction(kind: .expense, amount: uzs(Int64(6_000_000 + month * 100_000)), accountID: kapital.id, date: date(2026, month, 15)))
            txs.append(FinanceTransaction(kind: .fee, amount: uzs(10_000), accountID: kapital.id, date: date(2026, month, 16)))
        }
        let planned = [PlannedExpense(title: "Отпуск", amount: uzs(2_000_000), date: date(2026, 11, 20)),
                       PlannedExpense(title: "Далеко", amount: uzs(9_000_000), date: date(2027, 3, 1))]
        let forecast = engine(txs).savingsForecast(months: 3, now: date(2026, 10, 15), planned: planned)
        XCTAssertEqual(forecast.basisDescription, .fullMonths([MonthKey(year: 2026, month: 9), MonthKey(year: 2026, month: 8), MonthKey(year: 2026, month: 7)]))
        XCTAssertEqual(forecast.averageIncome, uzs(10_000_000))
        XCTAssertEqual(forecast.averageOutflow, uzs(6_810_000))
        XCTAssertEqual(forecast.plannedExpenses, uzs(2_000_000), "Учитываются только планы в горизонте")
        XCTAssertEqual(forecast.projectedSavings, uzs(3_190_000 * 3 - 2_000_000))
        XCTAssertTrue(forecast.isReliable)

        let empty = engine([]).savingsForecast(months: 3, now: date(2026, 10, 15))
        XCTAssertEqual(empty.basisDescription, .none)
        XCTAssertFalse(empty.isReliable)

        let young = [FinanceTransaction(kind: .expense, amount: uzs(300_000), accountID: kapital.id, date: date(2026, 10, 5))]
        if case .recentDays = engine(young).savingsForecast(months: 3, now: date(2026, 10, 15)).basisDescription {} else {
            XCTFail("Меньше месяца данных — расчёт по последним дням")
        }
    }

    func testBudgetsWithRollover() {
        var txs: [FinanceTransaction] = []
        txs.append(FinanceTransaction(kind: .expense, amount: uzs(1_500_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.groceries), date: date(2026, 8, 10)))
        txs.append(FinanceTransaction(kind: .expense, amount: uzs(2_400_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.groceries), date: date(2026, 9, 10)))
        txs.append(FinanceTransaction(kind: .expense, amount: uzs(1_800_000), accountID: kapital.id, categoryID: cat(SystemCategoryKey.groceries), date: date(2026, 10, 5)))
        txs.append(FinanceTransaction(kind: .fee, amount: uzs(20_000), accountID: kapital.id, date: date(2026, 10, 5)))

        let rolling = Budget(categoryID: cat(SystemCategoryKey.groceries), limit: uzs(2_000_000), rolloverEnabled: true, startMonth: MonthKey(year: 2026, month: 8))
        let plain = Budget(categoryID: nil, limit: uzs(1_500_000), rolloverEnabled: false, startMonth: MonthKey(year: 2026, month: 8))
        let future = Budget(categoryID: cat(SystemCategoryKey.cafe), limit: uzs(1), startMonth: MonthKey(year: 2026, month: 12))
        let statuses = engine(txs).budgetStatuses([rolling, plain, future], month: MonthKey(year: 2026, month: 10), now: date(2026, 10, 15))
        XCTAssertEqual(statuses.count, 2, "Бюджет из будущего не показывается")

        let overall = statuses[0]
        XCTAssertTrue(overall.budget.isOverall)
        XCTAssertEqual(overall.spent, uzs(1_820_000), "Общий бюджет включает комиссии")
        XCTAssertEqual(overall.state, .exceeded)
        XCTAssertEqual(overall.carriedOver, uzs(0))

        let groceries = statuses[1]
        // Август: лимит 2 000 000, потрачено 1 500 000 → перенос 500 000.
        // Сентябрь: 2 500 000, потрачено 2 400 000 → перенос 100 000.
        XCTAssertEqual(groceries.carriedOver, uzs(100_000))
        XCTAssertEqual(groceries.effectiveLimit, uzs(2_100_000))
        XCTAssertEqual(groceries.remaining, uzs(300_000))
        XCTAssertEqual(groceries.state, .warning)
        XCTAssertEqual(groceries.daysLeft, 17)
        XCTAssertEqual(groceries.dailyAllowance, Money(minorUnits: 30_000_000 / 17, currency: .uzs))
        XCTAssertEqual(groceries.projectedSpend, uzs(3_720_000), "1 800 000 / 15 дней × 31")
    }

    func testGoalStatuses() {
        let goal = Goal(name: "Ноутбук", target: uzs(15_000_000), deadline: date(2027, 1, 15))
        let linked = Goal(name: "Подушка", target: usd(5_000), linkedAccountID: dollar.id)
        let contributions = [GoalContribution(goalID: goal.id, amount: uzs(6_000_000), date: date(2026, 9, 1)),
                             GoalContribution(goalID: goal.id, amount: uzs(1_500_000), date: date(2026, 10, 1))]
        let statuses = engine([]).goalStatuses([goal, linked], contributions: contributions, balances: [dollar.id: usd(1_250)], now: date(2026, 10, 15))
        XCTAssertEqual(statuses[0].saved, uzs(7_500_000))
        XCTAssertEqual(statuses[0].progress, 0.5, accuracy: 1e-9)
        XCTAssertEqual(statuses[0].monthsLeft, 3)
        XCTAssertEqual(statuses[0].monthlyNeeded, uzs(2_500_000))
        XCTAssertEqual(statuses[1].saved, usd(1_250))
        XCTAssertEqual(statuses[1].progress, 0.25, accuracy: 1e-9)
    }

    func testStatisticsHelpers() {
        XCTAssertEqual(Statistics.median([3, 1, 2]), 2)
        XCTAssertEqual(Statistics.median([4, 1, 2, 3]), 2.5)
        XCTAssertEqual(Statistics.medianAbsoluteDeviation([1, 2, 3, 4, 100]), 1)
        XCTAssertEqual(AnalyticsEngine.twoSignificantDigits(349_000_000), 350_000_000)
        XCTAssertEqual(AnalyticsEngine.twoSignificantDigits(15_000_000), 15_000_000)
    }
}

extension AnalyticsEngineTests {
    func testFilteringLargeExpenses() {
        let october = periods.monthRange(MonthKey(year: 2026, month: 10))
        let large = engine(sample).filteringExpenses(atLeast: uzs(200_000))
        let summary = large.summary(october)
        XCTAssertEqual(summary.income, uzs(18_000_000), "доходы не фильтруются")
        XCTAssertEqual(summary.grossExpenses, uzs(245_000 + 400_000), "85 000 и расход без курса отброшены")
        XCTAssertEqual(summary.spending, uzs(245_000 + 400_000 - 100_000), "возврат остаётся")
        XCTAssertEqual(summary.fees, uzs(0))
        XCTAssertEqual(large.largestExpenses(october, limit: 10).map(\.amount), [uzs(400_000), uzs(245_000)])
        XCTAssertEqual(large.summary(periods.monthRange(MonthKey(year: 2026, month: 9))).spending, uzs(300_000))
    }

    func testLargeExpenseThresholds() {
        XCTAssertEqual(AnalyticsEngine.largeExpenseThresholds(for: .uzs).first, 100_000)
        XCTAssertEqual(AnalyticsEngine.largeExpenseThresholds(for: .usd), [50, 100, 500, 1_000])
    }
}
