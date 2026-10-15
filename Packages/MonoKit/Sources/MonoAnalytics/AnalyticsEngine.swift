import Foundation
import MonoCore

/// Детерминированная аналитика по сохранённым операциям. Все суммы — в базовой валюте конвертера.
/// Операции в валютах без курса не подменяются догадками: они исключаются и перечисляются в `excludedCurrencies`.
public struct AnalyticsEngine: Sendable {
    public let transactions: [FinanceTransaction]
    public let accounts: [UUID: Account]
    public let categories: [UUID: FinanceCategory]
    public let converter: CurrencyConverter
    public let periods: PeriodCalendar

    public init(
        transactions: [FinanceTransaction],
        accounts: [Account],
        categories: [FinanceCategory],
        converter: CurrencyConverter,
        periods: PeriodCalendar
    ) {
        self.transactions = transactions.sorted { $0.date < $1.date }
        self.accounts = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.categories = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.converter = converter
        self.periods = periods
    }

    public var base: Currency { converter.base }
    var zero: Money { .zero(base) }

    /// Сумма операции в базовой валюте (модуль). `nil`, если нет курса.
    func baseAmount(_ transaction: FinanceTransaction) -> Money? {
        converter.toBase(transaction.amount.magnitude)
    }

    func inRange(_ range: DateRange) -> [FinanceTransaction] {
        transactions.filter { range.contains($0.date) }
    }

    // MARK: - Итоги периода

    public func summary(_ range: DateRange) -> PeriodSummary {
        var result = PeriodSummary(range: range, income: zero, spending: zero, grossExpenses: zero, refunds: zero, fees: zero,
                                   transactionCount: 0, excludedCurrencies: [])
        for transaction in inRange(range) {
            guard transaction.kind != .transfer, transaction.kind != .adjustment else { continue }
            guard let amount = baseAmount(transaction) else {
                result.excludedCurrencies.insert(transaction.amount.currency)
                continue
            }
            result.transactionCount += 1
            switch transaction.kind {
            case .income: result.income += amount
            case .expense:
                result.grossExpenses += amount
                result.spending += amount
            case .refund:
                result.refunds += amount
                result.spending -= amount
            case .fee: result.fees += amount
            case .transfer, .adjustment: break
            }
        }
        return result
    }

    // MARK: - Категории

    /// Расходы по категориям (возвраты уменьшают свою категорию). Без комиссий.
    public func spendingByCategory(_ range: DateRange) -> [CategoryAmount] {
        var totals: [UUID?: (Money, Int)] = [:]
        for transaction in inRange(range) where transaction.kind == .expense || transaction.kind == .refund {
            guard let amount = baseAmount(transaction) else { continue }
            let signed = transaction.kind == .refund ? amount.negated : amount
            let current = totals[transaction.categoryID] ?? (zero, 0)
            totals[transaction.categoryID] = (current.0 + signed, current.1 + (transaction.kind == .expense ? 1 : 0))
        }
        return rank(totals)
    }

    public func incomeByCategory(_ range: DateRange) -> [CategoryAmount] {
        var totals: [UUID?: (Money, Int)] = [:]
        for transaction in inRange(range) where transaction.kind == .income {
            guard let amount = baseAmount(transaction) else { continue }
            let current = totals[transaction.categoryID] ?? (zero, 0)
            totals[transaction.categoryID] = (current.0 + amount, current.1 + 1)
        }
        return rank(totals)
    }

    private func rank(_ totals: [UUID?: (Money, Int)]) -> [CategoryAmount] {
        let positive = totals.filter { $0.value.0.minorUnits > 0 }
        let sum = positive.values.reduce(Int64(0)) { $0 + $1.0.minorUnits }
        return positive.map { key, value in
            CategoryAmount(categoryID: key, amount: value.0, share: sum > 0 ? Double(value.0.minorUnits) / Double(sum) : 0, count: value.1)
        }
        .sorted { lhs, rhs in
            lhs.amount.minorUnits != rhs.amount.minorUnits ? lhs.amount.minorUnits > rhs.amount.minorUnits : lhs.id < rhs.id
        }
    }

    // MARK: - Ряды

    public func bucketStart(_ date: Date, granularity: Granularity) -> Date {
        switch granularity {
        case .day: return periods.startOfDay(date)
        case .week: return periods.weekStart(date)
        case .month: return periods.monthRange(periods.monthKey(date)).start
        }
    }

    private func nextBucket(_ date: Date, granularity: Granularity) -> Date {
        switch granularity {
        case .day: return periods.addingDays(1, to: date)
        case .week: return periods.addingDays(7, to: date)
        case .month: return periods.monthRange(periods.monthKey(date)).end
        }
    }

    /// Доходы/расходы/комиссии по корзинам, включая пустые корзины — для непрерывных графиков.
    public func series(_ range: DateRange, granularity: Granularity) -> [SeriesPoint] {
        var buckets: [Date: SeriesPoint] = [:]
        var cursor = bucketStart(range.start, granularity: granularity)
        var order: [Date] = []
        while cursor < range.end {
            buckets[cursor] = SeriesPoint(date: cursor, income: zero, spending: zero, fees: zero)
            order.append(cursor)
            cursor = nextBucket(cursor, granularity: granularity)
        }
        for transaction in inRange(range) {
            guard let amount = baseAmount(transaction) else { continue }
            let key = bucketStart(transaction.date, granularity: granularity)
            guard var point = buckets[key] else { continue }
            switch transaction.kind {
            case .income: point.income += amount
            case .expense: point.spending += amount
            case .refund: point.spending -= amount
            case .fee: point.fees += amount
            case .transfer, .adjustment: continue
            }
            buckets[key] = point
        }
        return order.compactMap { buckets[$0] }
    }

    // MARK: - Балансы

    /// Счета, входящие в общий баланс.
    public var totalAccounts: [Account] {
        accounts.values.filter { $0.includeInTotal && !$0.isArchived }
    }

    /// Общий баланс на момент `date` (или по всем операциям) в базовой валюте.
    public func totalBalance(at date: Date? = nil) -> (total: Money, excluded: Set<Currency>) {
        let relevant = date.map { cutoff in transactions.filter { $0.date <= cutoff } } ?? transactions
        let balances = Ledger.balances(accounts: totalAccounts, transactions: relevant)
        var total = zero
        var excluded = Set<Currency>()
        for account in totalAccounts {
            guard let balance = balances[account.id] else { continue }
            if let converted = converter.toBase(balance) {
                total += converted
            } else if !balance.isZero {
                excluded.insert(balance.currency)
            }
        }
        return (total, excluded)
    }

    /// Общий баланс на конец каждого дня интервала (по текущим курсам).
    public func balanceHistory(_ range: DateRange, accountIDs: Set<UUID>? = nil) -> [BalancePoint] {
        let selected = totalAccounts.filter { accountIDs?.contains($0.id) ?? true }
        let selectedIDs = Set(selected.map(\.id))
        var running: [UUID: Money] = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, Money.zero($0.currency)) })
        let days = periods.days(in: range)
        guard !days.isEmpty else { return [] }

        var dayEffects: [Date: [BalanceEffect]] = [:]
        for transaction in transactions {
            let effects = Ledger.effects(of: transaction).filter { selectedIDs.contains($0.accountID) }
            guard !effects.isEmpty else { continue }
            if transaction.date < days[0] {
                for effect in effects {
                    if let value = running[effect.accountID]?.adding(effect.delta) { running[effect.accountID] = value }
                }
            } else if transaction.date < range.end {
                dayEffects[periods.startOfDay(transaction.date), default: []].append(contentsOf: effects)
            }
        }

        var points: [BalancePoint] = []
        points.reserveCapacity(days.count)
        for day in days {
            for effect in dayEffects[day] ?? [] {
                if let value = running[effect.accountID]?.adding(effect.delta) { running[effect.accountID] = value }
            }
            var total = zero
            for money in running.values {
                if let converted = converter.toBase(money) { total += converted }
            }
            points.append(BalancePoint(date: day, balance: total))
        }
        return points
    }

    // MARK: - Сравнения и средние

    public func compare(_ current: DateRange, with previous: DateRange) -> PeriodComparison {
        let now = spendingByCategory(current)
        let before = spendingByCategory(previous)
        var keys: [UUID?] = []
        var seen = Set<String>()
        for item in now + before where !seen.contains(item.id) {
            seen.insert(item.id)
            keys.append(item.categoryID)
        }
        let deltas = keys.map { key in
            CategoryDelta(
                categoryID: key,
                current: now.first { $0.categoryID == key }?.amount ?? zero,
                previous: before.first { $0.categoryID == key }?.amount ?? zero
            )
        }
        .sorted { abs($0.change.minorUnits) > abs($1.change.minorUnits) }
        return PeriodComparison(current: summary(current), previous: summary(previous), categories: deltas)
    }

    /// Количество прошедших дней интервала на момент `now` (минимум 1).
    public func elapsedDays(_ range: DateRange, now: Date) -> Int {
        let end = min(range.end, periods.addingDays(1, to: periods.startOfDay(now)))
        guard end > range.start else { return 1 }
        return max(1, periods.numberOfDays(in: DateRange(start: range.start, end: end)))
    }

    /// Средние расходы в день за прошедшую часть интервала.
    public func averageDailySpending(_ range: DateRange, now: Date) -> Money {
        let days = elapsedDays(range, now: now)
        let spending = summary(range).spending
        return Money(minorUnits: spending.minorUnits / Int64(days), currency: base)
    }

    /// Траты с начала месяца и за тот же отрезок прошлого месяца — честное сравнение незаконченного месяца.
    public func monthToDate(now: Date) -> (current: Money, previous: Money, day: Int) {
        let monthRange = periods.monthRange(periods.monthKey(now))
        let current = summary(DateRange(start: monthRange.start, end: now)).outflow
        let elapsed = now.timeIntervalSince(monthRange.start)
        let previousRange = periods.monthRange(periods.monthKey(now).previous)
        let previousEnd = min(previousRange.start.addingTimeInterval(elapsed), previousRange.end)
        let previous = summary(DateRange(start: previousRange.start, end: previousEnd)).outflow
        let day = periods.calendar.component(.day, from: now)
        return (current, previous, day)
    }

    /// Крупнейшие расходы периода.
    public func largestExpenses(_ range: DateRange, limit: Int = 5) -> [FinanceTransaction] {
        inRange(range)
            .filter { $0.kind == .expense }
            .compactMap { transaction in baseAmount(transaction).map { (transaction, $0) } }
            .sorted { $0.1.minorUnits > $1.1.minorUnits }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: - Продавцы, счета, обязательные расходы

    public func topMerchants(_ range: DateRange, limit: Int = 8) -> [MerchantStat] {
        var stats: [String: MerchantStat] = [:]
        for transaction in inRange(range) where transaction.kind == .expense {
            guard let merchant = transaction.merchant, let amount = baseAmount(transaction) else { continue }
            let key = MerchantNormalizer.key(merchant)
            guard !key.isEmpty else { continue }
            if var stat = stats[key] {
                stat.count += 1
                stat.total += amount
                if transaction.date > stat.lastDate {
                    stat.lastDate = transaction.date
                    stat.name = MerchantNormalizer.displayName(merchant)
                    stat.categoryID = transaction.categoryID ?? stat.categoryID
                }
                stats[key] = stat
            } else {
                stats[key] = MerchantStat(key: key, name: MerchantNormalizer.displayName(merchant), count: 1, total: amount,
                                          lastDate: transaction.date, categoryID: transaction.categoryID)
            }
        }
        return stats.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.total.minorUnits > $1.total.minorUnits }
            .prefix(limit)
            .map { $0 }
    }

    public func flowsByAccount(_ range: DateRange) -> [AccountFlow] {
        var flows: [UUID: AccountFlow] = [:]
        func flow(_ id: UUID) -> AccountFlow {
            flows[id] ?? AccountFlow(accountID: id, income: zero, spending: zero, fees: zero, transfersIn: zero, transfersOut: zero, count: 0)
        }
        for transaction in inRange(range) {
            guard let amount = baseAmount(transaction) else { continue }
            var item = flow(transaction.accountID)
            item.count += 1
            switch transaction.kind {
            case .income: item.income += amount
            case .expense: item.spending += amount
            case .refund: item.spending -= amount
            case .fee: item.fees += amount
            case .transfer:
                item.transfersOut += amount
                if let destination = transaction.counterAccountID,
                   let received = transaction.counterAmount.flatMap({ converter.toBase($0) }) {
                    var target = flow(destination)
                    target.transfersIn += received
                    flows[destination] = target
                }
            case .adjustment: break
            }
            flows[transaction.accountID] = item
        }
        return flows.values.sorted { ($0.spending + $0.fees).minorUnits > ($1.spending + $1.fees).minorUnits }
    }

    public func mandatorySplit(_ range: DateRange) -> MandatorySplit {
        var result = MandatorySplit(mandatory: zero, optional: zero, uncategorized: zero)
        for item in spendingByCategory(range) {
            guard let id = item.categoryID, let category = categories[id] else {
                result.uncategorized += item.amount
                continue
            }
            if category.isMandatory { result.mandatory += item.amount } else { result.optional += item.amount }
        }
        return result
    }
}
