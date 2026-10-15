import Foundation
import MonoCore

extension AnalyticsEngine {
    // MARK: - Повторяющиеся платежи

    /// Ищет платежи, которые повторяются примерно раз в неделю или раз в месяц с похожей суммой.
    public func recurringCandidates(now: Date, lookbackDays: Int = 200) -> [RecurringCandidate] {
        let start = periods.addingDays(-lookbackDays, to: now)
        var groups: [String: [(FinanceTransaction, Money)]] = [:]
        for transaction in transactions where transaction.kind == .expense && transaction.date >= start && transaction.date <= now {
            guard let amount = baseAmount(transaction) else { continue }
            let key: String
            if let merchant = transaction.merchant, !MerchantNormalizer.key(merchant).isEmpty {
                key = MerchantNormalizer.key(merchant)
            } else if let category = transaction.categoryID {
                // Без продавца группируем по категории и сумме, округлённой до двух значащих цифр:
                // «Аренда 3 500 000» и «Интернет 150 000» в одной категории не смешиваются.
                key = "cat:\(category.uuidString)|\(Self.twoSignificantDigits(amount.minorUnits))"
            } else {
                continue
            }
            groups[key, default: []].append((transaction, amount))
        }

        var result: [RecurringCandidate] = []
        for (key, items) in groups where items.count >= 3 {
            let sorted = items.sorted { $0.0.date < $1.0.date }
            let intervals = zip(sorted, sorted.dropFirst()).map { $1.0.date.timeIntervalSince($0.0.date) / 86_400 }
            let medianInterval = Statistics.median(intervals)
            let frequency: RecurrenceFrequency
            let tolerance: Double
            if (25...36).contains(medianInterval) {
                frequency = .monthly
                tolerance = 6
            } else if (6...8).contains(medianInterval) {
                frequency = .weekly
                tolerance = 2
            } else {
                continue
            }
            let regular = intervals.filter { abs($0 - medianInterval) <= tolerance }.count
            guard Double(regular) >= Double(intervals.count) * 0.66 else { continue }

            let amounts = sorted.map { Double($0.1.minorUnits) }
            let medianAmount = Statistics.median(amounts)
            guard medianAmount > 0 else { continue }
            let similar = amounts.filter { abs($0 - medianAmount) / medianAmount <= 0.2 }.count
            guard Double(similar) >= Double(amounts.count) * 0.66 else { continue }

            let last = sorted[sorted.count - 1].0
            let next: Date
            switch frequency {
            case .monthly: next = periods.calendar.date(byAdding: .month, value: 1, to: last.date) ?? last.date
            case .weekly: next = periods.addingDays(7, to: last.date)
            case .yearly: next = periods.calendar.date(byAdding: .year, value: 1, to: last.date) ?? last.date
            }
            let name = last.merchant.map(MerchantNormalizer.displayName)
                ?? last.categoryID.flatMap { categories[$0]?.name }
                ?? "—"
            result.append(RecurringCandidate(
                key: key,
                name: name,
                typicalAmount: Money(minorUnits: Int64(medianAmount.rounded()), currency: base),
                frequency: frequency,
                occurrences: sorted.count,
                lastDate: last.date,
                nextExpectedDate: next,
                categoryID: last.categoryID,
                accountID: last.accountID
            ))
        }
        return result.sorted { $0.nextExpectedDate < $1.nextExpectedDate }
    }

    static func twoSignificantDigits(_ value: Int64) -> Int64 {
        var magnitude = value.magnitude
        var factor: UInt64 = 1
        while magnitude >= 100 {
            magnitude /= 10
            factor *= 10
        }
        let rounded = (value.magnitude + factor / 2) / factor * factor
        return Int64(rounded)
    }

    // MARK: - Необычные траты

    /// Траты, заметно превышающие обычный уровень своей категории (медиана и MAD за полгода).
    public func unusualExpenses(_ range: DateRange, limit: Int = 5) -> [UnusualExpense] {
        let historyStart = periods.addingDays(-180, to: range.start)
        var byCategory: [UUID?: [Double]] = [:]
        var all: [Double] = []
        for transaction in transactions where transaction.kind == .expense && transaction.date >= historyStart && transaction.date < range.end {
            guard let amount = baseAmount(transaction) else { continue }
            byCategory[transaction.categoryID, default: []].append(Double(amount.minorUnits))
            all.append(Double(amount.minorUnits))
        }
        guard all.count >= 5 else { return [] }
        let overallMedian = Statistics.median(all)

        var result: [UnusualExpense] = []
        for transaction in inRange(range) where transaction.kind == .expense {
            guard let amount = baseAmount(transaction) else { continue }
            let value = Double(amount.minorUnits)
            let sample = byCategory[transaction.categoryID] ?? []
            let typical: Double
            let threshold: Double
            if sample.count >= 4 {
                typical = Statistics.median(sample)
                let mad = Statistics.medianAbsoluteDeviation(sample)
                threshold = max(typical * 3, typical + 5 * mad * 1.4826)
            } else {
                typical = overallMedian
                threshold = overallMedian * 6
            }
            guard typical > 0, value > threshold, value >= overallMedian * 2 else { continue }
            result.append(UnusualExpense(
                transaction: transaction,
                amount: amount,
                typical: Money(minorUnits: Int64(typical.rounded()), currency: base),
                ratio: value / typical
            ))
        }
        return result.sorted { $0.ratio > $1.ratio }.prefix(limit).map { $0 }
    }

    // MARK: - Прогноз накоплений

    /// Сколько получится отложить за `months` месяцев при текущем темпе: средний чистый поток
    /// последних полных месяцев (до трёх) минус запланированные крупные расходы на горизонте.
    public func savingsForecast(months: Int, now: Date, planned: [PlannedExpense] = []) -> SavingsForecast {
        let horizon = max(1, months)
        let currentMonth = periods.monthKey(now)
        let firstDate = transactions.first { $0.kind != .adjustment && $0.kind != .transfer }?.date

        var basis: [MonthKey] = []
        if let firstDate {
            let firstMonth = periods.monthKey(firstDate)
            var key = currentMonth.previous
            while basis.count < 3 && key >= firstMonth {
                // Первый месяц учитываем, только если данные начались в его первые дни.
                if key == firstMonth {
                    let start = periods.monthRange(key).start
                    if firstDate.timeIntervalSince(start) > 5 * 86_400 { break }
                }
                basis.append(key)
                key = key.previous
            }
        }

        var averageIncome = zero
        var averageOutflow = zero
        let description: SavingsForecast.Basis
        if !basis.isEmpty {
            var income: Int64 = 0
            var outflow: Int64 = 0
            for key in basis {
                let summary = summary(periods.monthRange(key))
                income += summary.income.minorUnits
                outflow += summary.outflow.minorUnits
            }
            averageIncome = Money(minorUnits: income / Int64(basis.count), currency: base)
            averageOutflow = Money(minorUnits: outflow / Int64(basis.count), currency: base)
            description = .fullMonths(basis)
        } else if let firstDate {
            let range = DateRange(start: max(firstDate, periods.addingDays(-30, to: now)), end: now)
            let days = max(1, periods.numberOfDays(in: range))
            let summary = summary(range)
            let scale = Decimal(30) / Decimal(days)
            averageIncome = summary.income.multiplied(by: scale) ?? zero
            averageOutflow = summary.outflow.multiplied(by: scale) ?? zero
            description = .recentDays(days)
        } else {
            description = .none
        }

        let horizonEnd = periods.monthRange(currentMonth.adding(months: horizon)).start
        var plannedTotal = zero
        for item in planned where !item.isCompleted && item.date >= periods.startOfDay(now) && item.date < horizonEnd {
            if let converted = converter.toBase(item.amount) { plannedTotal += converted }
        }
        let net = averageIncome - averageOutflow
        let projected = Money(minorUnits: net.minorUnits * Int64(horizon), currency: base) - plannedTotal
        return SavingsForecast(
            months: horizon,
            basisDescription: description,
            averageIncome: averageIncome,
            averageOutflow: averageOutflow,
            plannedExpenses: plannedTotal,
            projectedSavings: projected
        )
    }

    /// Линейный прогноз расходов текущего месяца.
    public func projectedMonthSpending(now: Date) -> Money? {
        let key = periods.monthKey(now)
        let range = periods.monthRange(key)
        let elapsed = elapsedDays(range, now: now)
        let total = periods.dayCount(of: key)
        guard elapsed >= 5 else { return nil }
        let spent = summary(DateRange(start: range.start, end: now)).outflow
        return Money(minorUnits: spent.minorUnits * Int64(total) / Int64(elapsed), currency: base)
    }
}

/// Небольшие статистические функции.
public enum Statistics {
    public static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    public static func medianAbsoluteDeviation(_ values: [Double]) -> Double {
        let m = median(values)
        return median(values.map { abs($0 - m) })
    }
}

// MARK: - Крупные траты

extension AnalyticsEngine {
    /// Та же аналитика, но из расходов и комиссий остаются только суммы от `minimum` (в базовой валюте).
    /// Доходы, возвраты, переводы и корректировки не трогаются. Операции без курса отбрасываются,
    /// как и в итогах. Нужна для отчётов «только крупные расходы».
    public func filteringExpenses(atLeast minimum: Money) -> AnalyticsEngine {
        let filtered = transactions.filter { transaction in
            guard transaction.kind == .expense || transaction.kind == .fee else { return true }
            guard let amount = baseAmount(transaction) else { return false }
            return amount.minorUnits >= minimum.magnitude.minorUnits
        }
        return AnalyticsEngine(transactions: filtered, accounts: Array(accounts.values), categories: Array(categories.values),
                               converter: converter, periods: periods)
    }

    /// Пороги «крупных» трат для быстрых фильтров — в основных единицах базовой валюты.
    public static func largeExpenseThresholds(for currency: Currency) -> [Int] {
        switch currency.code {
        case "UZS": return [100_000, 500_000, 1_000_000, 5_000_000]
        case "KZT", "KRW": return [10_000, 50_000, 100_000, 500_000]
        case "RUB", "JPY": return [1_000, 5_000, 10_000, 50_000]
        default: return [50, 100, 500, 1_000]
        }
    }
}
