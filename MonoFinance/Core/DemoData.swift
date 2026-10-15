import Foundation
import MonoCore
import MonoStorage

/// Демонстрационные данные. Пишутся только в отдельную базу demo.sqlite и показываются с плашкой «Демо-режим».
enum DemoData {
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    static func populate(_ db: LedgerDatabase, now: Date, calendar: Calendar) throws {
        var rng = SeededGenerator(state: 20_261_015)
        func uzs(_ value: Int) -> Money { Money(minorUnits: Int64(value) * 100, currency: .uzs) }
        func usd(_ value: Int) -> Money { Money(minorUnits: Int64(value) * 100, currency: .usd) }
        func cat(_ key: String) -> UUID { DefaultCategories.id(for: key) }
        func roundedAmount(_ range: ClosedRange<Int>) -> Int {
            Int.random(in: range, using: &rng) / 1_000 * 1_000
        }
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, hour: Int = 12, minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
            return min(date, now)
        }

        let kapital = Account(bank: .kapitalbank, name: "Kapital Humo", kind: .card, paymentSystem: .humo, currency: .uzs, lastFour: "4417", skin: .aurora, sortOrder: 0)
        let uzum = Account(bank: .uzum, name: "Uzum Visa", kind: .card, paymentSystem: .visa, currency: .uzs, lastFour: "2093", skin: .ultraviolet, sortOrder: 1)
        let ofb = Account(bank: .orientFinans, name: "OFB долларовая", kind: .card, paymentSystem: .visa, currency: .usd, lastFour: "7710", skin: .lagoon, sortOrder: 2)
        let trast = Account(bank: .trastbank, name: "Накопительный", kind: .savings, currency: .uzs, skin: .glacier, sortOrder: 3)
        let cash = Account(bank: .cash, name: "Наличные", kind: .cash, currency: .uzs, skin: .graphite, sortOrder: 4)

        let start = 124
        try db.createAccount(kapital, openingBalance: uzs(6_200_000), openingDate: day(start, hour: 9))
        try db.createAccount(uzum, openingBalance: uzs(1_450_000), openingDate: day(start, hour: 9))
        try db.createAccount(ofb, openingBalance: usd(1_840), openingDate: day(start, hour: 9))
        try db.createAccount(trast, openingBalance: uzs(12_000_000), openingDate: day(start, hour: 9))
        try db.createAccount(cash, openingBalance: uzs(650_000), openingDate: day(start, hour: 9))
        try db.setSetting(FinanceStore.StoreKeys.defaultAccount, kapital.id.uuidString)
        try db.setSetting(FinanceStore.StoreKeys.baseCurrency, "UZS")
        try db.saveExchangeRates([
            ExchangeRate(currency: .usd, baseCurrency: .uzs, rate: Decimal(string: "11913.35")!, date: now, source: .manual),
            ExchangeRate(currency: .eur, baseCurrency: .uzs, rate: Decimal(string: "13328.66")!, date: now, source: .manual)
        ], keepManual: false)

        var batch: [FinanceTransaction] = []
        func add(_ kind: TransactionKind, _ amount: Money, _ account: Account, _ category: String?, merchant: String? = nil, at date: Date, source: TransactionSource = .demo) {
            batch.append(FinanceTransaction(kind: kind, amount: amount, accountID: account.id, categoryID: category.map(cat), merchant: merchant,
                                            date: date, createdAt: date, source: source))
        }

        let groceries = ["Korzinka", "Makro", "Havas", "Korzinka", "Carrefour"]
        let cafes = ["EVOS", "Max Way", "Safia", "Les Ailes", "Bon!"]
        for offset in stride(from: start - 1, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let dayOfMonth = calendar.component(.day, from: date)
            let weekday = calendar.component(.weekday, from: date)

            if dayOfMonth == 1 { add(.expense, uzs(4_000_000), kapital, SystemCategoryKey.housing, merchant: "Аренда квартиры", at: day(offset, hour: 10)) }
            if dayOfMonth == 3 {
                add(.expense, uzs(150_000), kapital, SystemCategoryKey.mobile, merchant: "Uztelecom", at: day(offset, hour: 9, minute: 12))
                add(.expense, uzs(45_000), uzum, SystemCategoryKey.mobile, merchant: "Beeline", at: day(offset, hour: 9, minute: 40))
            }
            if dayOfMonth == 5 { add(.income, uzs(14_500_000), kapital, SystemCategoryKey.salary, merchant: "ООО «Медиа Студия»", at: day(offset, hour: 11)) }
            if dayOfMonth == 6 {
                let transfer = FinanceTransaction(kind: .transfer, amount: uzs(2_000_000), accountID: kapital.id, counterAccountID: trast.id,
                                                  counterAmount: uzs(2_000_000), date: day(offset, hour: 13), createdAt: day(offset, hour: 13), source: .demo)
                try db.insertTransfer(transfer, fee: nil)
                let toUzum = FinanceTransaction(kind: .transfer, amount: uzs(1_000_000), accountID: kapital.id, counterAccountID: uzum.id,
                                                counterAmount: uzs(1_000_000), date: day(offset, hour: 13, minute: 5), createdAt: day(offset, hour: 13, minute: 5), source: .demo)
                try db.insertTransfer(toUzum, fee: uzs(5_000))
            }
            if dayOfMonth == 9 || dayOfMonth == 23 { add(.income, usd(Int.random(in: 320...880, using: &rng)), ofb, SystemCategoryKey.freelance, merchant: "Upwork", at: day(offset, hour: 18)) }
            if dayOfMonth == 14 { add(.expense, usd(11), ofb, SystemCategoryKey.subscriptions, merchant: "Netflix", at: day(offset, hour: 8)) }
            if dayOfMonth == 15 {
                let withdrawal = FinanceTransaction(kind: .transfer, amount: uzs(600_000), accountID: kapital.id, counterAccountID: cash.id,
                                                    counterAmount: uzs(600_000), date: day(offset, hour: 17), createdAt: day(offset, hour: 17), source: .demo)
                try db.insertTransfer(withdrawal, fee: uzs(3_000))
            }
            if weekday == 7 || (weekday == 4 && Int.random(in: 0...2, using: &rng) == 0) {
                add(.expense, uzs(roundedAmount(240_000...560_000)), kapital, SystemCategoryKey.groceries,
                    merchant: groceries[Int.random(in: 0..<groceries.count, using: &rng)], at: day(offset, hour: 18, minute: 20))
            }
            if weekday == 1 && Int.random(in: 0...1, using: &rng) == 0 {
                add(.expense, uzs(roundedAmount(60_000...180_000)), cash, SystemCategoryKey.groceries, merchant: "Чорсу базар", at: day(offset, hour: 11))
            }
            if Int.random(in: 0...9, using: &rng) < 3 {
                let account = Int.random(in: 0...1, using: &rng) == 0 ? kapital : uzum
                add(.expense, uzs(roundedAmount(42_000...135_000)), account, SystemCategoryKey.cafe,
                    merchant: cafes[Int.random(in: 0..<cafes.count, using: &rng)], at: day(offset, hour: 13, minute: 30))
            }
            if weekday >= 2 && weekday <= 6 && Int.random(in: 0...9, using: &rng) < 4 {
                add(.expense, uzs(roundedAmount(16_000...58_000)), uzum, SystemCategoryKey.taxi, merchant: "Yandex Go", at: day(offset, hour: 9, minute: 5))
            }
            if dayOfMonth % 9 == 2 { add(.expense, uzs(roundedAmount(70_000...95_000)), kapital, SystemCategoryKey.fuel, merchant: "АГЗС Метан", at: day(offset, hour: 19)) }
            if dayOfMonth == 20 && Int.random(in: 0...1, using: &rng) == 0 {
                add(.expense, uzs(roundedAmount(150_000...420_000)), uzum, SystemCategoryKey.entertainment, merchant: "Magic City", at: day(offset, hour: 20))
            }
            if dayOfMonth == 27 { add(.expense, uzs(roundedAmount(180_000...320_000)), kapital, SystemCategoryKey.health, merchant: "Аптека 999", at: day(offset, hour: 16)) }
        }

        // Разовые операции: крупная покупка, возврат, кэшбэк, доход наличными.
        add(.expense, uzs(6_900_000), kapital, SystemCategoryKey.electronics, merchant: "Mediapark", at: day(38, hour: 15))
        add(.expense, uzs(690_000), uzum, SystemCategoryKey.clothes, merchant: "Uzum Market", at: day(17, hour: 21))
        add(.refund, uzs(690_000), uzum, SystemCategoryKey.clothes, merchant: "Uzum Market", at: day(12, hour: 10))
        add(.income, uzs(87_000), kapital, SystemCategoryKey.cashback, merchant: "Kapitalbank", at: day(10, hour: 9))
        add(.income, uzs(1_200_000), cash, SystemCategoryKey.sale, merchant: "Продажа велосипеда", at: day(45, hour: 12))
        add(.expense, uzs(85_000), kapital, SystemCategoryKey.cafe, merchant: "EVOS", at: day(0, hour: max(0, calendar.component(.hour, from: now) - 1)), source: .voice)

        try db.insert(batch: batch.filter { $0.date <= now })

        // Бюджеты, цели, планы, регулярные платежи.
        let month = MonthKey(date: now, calendar: calendar)
        try db.saveBudget(Budget(categoryID: nil, limit: uzs(11_000_000), startMonth: month.previous))
        try db.saveBudget(Budget(categoryID: cat(SystemCategoryKey.groceries), limit: uzs(2_400_000), rolloverEnabled: true, startMonth: month.adding(months: -2)))
        try db.saveBudget(Budget(categoryID: cat(SystemCategoryKey.cafe), limit: uzs(900_000), startMonth: month.previous))
        try db.saveBudget(Budget(categoryID: cat(SystemCategoryKey.taxi), limit: uzs(650_000), startMonth: month))

        let laptop = Goal(name: "MacBook для монтажа", target: uzs(24_000_000), deadline: calendar.date(byAdding: .month, value: 5, to: now),
                          icon: "laptopcomputer", color: .electric)
        try db.saveGoal(laptop)
        try db.addContribution(GoalContribution(goalID: laptop.id, amount: uzs(4_000_000), date: day(70)))
        try db.addContribution(GoalContribution(goalID: laptop.id, amount: uzs(3_500_000), date: day(40)))
        try db.addContribution(GoalContribution(goalID: laptop.id, amount: uzs(2_000_000), date: day(9)))
        try db.saveGoal(Goal(name: "Подушка безопасности", target: uzs(30_000_000), icon: "shield.lefthalf.filled", color: .emerald, linkedAccountID: trast.id))

        try db.savePlannedExpense(PlannedExpense(title: "Страховка автомобиля", amount: uzs(2_400_000),
                                                 date: calendar.date(byAdding: .day, value: 19, to: now) ?? now, categoryID: cat(SystemCategoryKey.car)))
        try db.savePlannedExpense(PlannedExpense(title: "Поездка в Самарканд", amount: uzs(5_000_000),
                                                 date: calendar.date(byAdding: .day, value: 52, to: now) ?? now, categoryID: cat(SystemCategoryKey.travel)))

        func nextDate(day dayOfMonth: Int) -> Date {
            var components = calendar.dateComponents([.year, .month], from: now)
            components.day = dayOfMonth
            components.hour = 10
            let candidate = calendar.date(from: components) ?? now
            return candidate > now ? candidate : (calendar.date(byAdding: .month, value: 1, to: candidate) ?? candidate)
        }
        try db.saveRecurringRule(RecurringRule(title: "Аренда квартиры", amount: uzs(4_000_000), accountID: kapital.id,
                                               categoryID: cat(SystemCategoryKey.housing), merchant: "Аренда квартиры",
                                               anchorDate: nextDate(day: 1), nextDueDate: nextDate(day: 1)))
        try db.saveRecurringRule(RecurringRule(title: "Интернет Uztelecom", amount: uzs(150_000), accountID: kapital.id,
                                               categoryID: cat(SystemCategoryKey.mobile), merchant: "Uztelecom",
                                               anchorDate: nextDate(day: 3), nextDueDate: nextDate(day: 3)))
        try db.saveRecurringRule(RecurringRule(title: "Netflix", amount: usd(11), accountID: ofb.id,
                                               categoryID: cat(SystemCategoryKey.subscriptions), merchant: "Netflix",
                                               anchorDate: nextDate(day: 14), nextDueDate: nextDate(day: 14)))
        try db.learnMerchant(key: "chorsu bazar", categoryID: cat(SystemCategoryKey.groceries))
    }
}
