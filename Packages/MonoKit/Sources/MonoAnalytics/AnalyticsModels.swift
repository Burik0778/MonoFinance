import Foundation
import MonoCore

/// Итоги периода в базовой валюте.
public struct PeriodSummary: Equatable, Sendable {
    public var range: DateRange
    public var income: Money
    /// Расходы за вычетом возвратов.
    public var spending: Money
    /// Расходы без учёта возвратов.
    public var grossExpenses: Money
    public var refunds: Money
    public var fees: Money
    public var transactionCount: Int
    /// Валюты, по которым нет курса: такие операции не вошли в итоги.
    public var excludedCurrencies: Set<Currency>

    /// Всё, что ушло: расходы + комиссии.
    public var outflow: Money { spending + fees }
    /// Чистый поток: доходы − расходы − комиссии.
    public var net: Money { income - spending - fees }
    public var isEmpty: Bool { transactionCount == 0 }
}

/// Сумма по категории.
public struct CategoryAmount: Identifiable, Equatable, Sendable {
    public var categoryID: UUID?
    public var amount: Money
    public var share: Double
    public var count: Int

    public var id: String { categoryID?.uuidString ?? "uncategorized" }
}

public enum Granularity: String, Sendable, CaseIterable, Identifiable {
    case day
    case week
    case month

    public var id: String { rawValue }
}

/// Точка ряда доходов/расходов.
public struct SeriesPoint: Identifiable, Equatable, Sendable {
    public var date: Date
    public var income: Money
    public var spending: Money
    public var fees: Money

    public var net: Money { income - spending - fees }
    public var outflow: Money { spending + fees }
    public var id: Date { date }
}

/// Баланс на конец дня.
public struct BalancePoint: Identifiable, Equatable, Sendable {
    public var date: Date
    public var balance: Money
    public var id: Date { date }
}

/// Изменение категории между периодами.
public struct CategoryDelta: Identifiable, Equatable, Sendable {
    public var categoryID: UUID?
    public var current: Money
    public var previous: Money

    public var change: Money { current - previous }
    /// Относительное изменение; `nil`, если в прошлом периоде трат не было.
    public var changeRatio: Double? {
        guard previous.minorUnits != 0 else { return nil }
        return Double(current.minorUnits - previous.minorUnits) / Double(previous.minorUnits)
    }
    public var id: String { categoryID?.uuidString ?? "uncategorized" }
}

public struct PeriodComparison: Equatable, Sendable {
    public var current: PeriodSummary
    public var previous: PeriodSummary
    public var categories: [CategoryDelta]

    public var spendingChangeRatio: Double? {
        guard previous.spending.minorUnits != 0 else { return nil }
        return Double(current.spending.minorUnits - previous.spending.minorUnits) / Double(previous.spending.minorUnits)
    }
}

/// Статистика по продавцу.
public struct MerchantStat: Identifiable, Equatable, Sendable {
    public var key: String
    public var name: String
    public var count: Int
    public var total: Money
    public var lastDate: Date
    public var categoryID: UUID?
    public var id: String { key }
}

/// Найденный регулярный платёж.
public struct RecurringCandidate: Identifiable, Equatable, Sendable {
    public var key: String
    public var name: String
    public var typicalAmount: Money
    public var frequency: RecurrenceFrequency
    public var occurrences: Int
    public var lastDate: Date
    public var nextExpectedDate: Date
    public var categoryID: UUID?
    public var accountID: UUID
    public var id: String { key }
}

/// Потоки по счёту (в базовой валюте).
public struct AccountFlow: Identifiable, Equatable, Sendable {
    public var accountID: UUID
    public var income: Money
    public var spending: Money
    public var fees: Money
    public var transfersIn: Money
    public var transfersOut: Money
    public var count: Int
    public var id: UUID { accountID }
}

/// Обязательные и необязательные расходы.
public struct MandatorySplit: Equatable, Sendable {
    public var mandatory: Money
    public var optional: Money
    public var uncategorized: Money

    public var total: Money { mandatory + optional + uncategorized }
    public var mandatoryShare: Double {
        guard total.minorUnits > 0 else { return 0 }
        return Double(mandatory.minorUnits) / Double(total.minorUnits)
    }
}

/// Необычно крупная трата.
public struct UnusualExpense: Identifiable, Equatable, Sendable {
    public var transaction: FinanceTransaction
    public var amount: Money
    public var typical: Money
    public var ratio: Double
    public var id: UUID { transaction.id }
}

/// Прогноз накоплений при текущем темпе.
public struct SavingsForecast: Equatable, Sendable {
    public var months: Int
    public var basisDescription: Basis
    public var averageIncome: Money
    public var averageOutflow: Money
    public var plannedExpenses: Money
    public var projectedSavings: Money

    public enum Basis: Equatable, Sendable {
        /// Полные календарные месяцы.
        case fullMonths([MonthKey])
        /// Последние N дней, пересчитанные на месяц (мало данных).
        case recentDays(Int)
        /// Данных нет.
        case none
    }

    public var averageNet: Money { averageIncome - averageOutflow }
    public var isReliable: Bool {
        if case .fullMonths(let months) = basisDescription { return months.count >= 2 }
        return false
    }
}

/// Состояние бюджета за месяц.
public struct BudgetStatus: Identifiable, Equatable, Sendable {
    public enum State: String, Sendable {
        case ok
        case warning
        case exceeded
    }

    public var budget: Budget
    public var month: MonthKey
    public var baseLimit: Money
    public var carriedOver: Money
    public var spent: Money
    public var projectedSpend: Money?
    public var daysLeft: Int

    public var effectiveLimit: Money { baseLimit + carriedOver }
    public var remaining: Money { effectiveLimit - spent }
    public var progress: Double {
        guard effectiveLimit.minorUnits > 0 else { return 0 }
        return Double(spent.minorUnits) / Double(effectiveLimit.minorUnits)
    }
    public var state: State {
        if progress > 1.0 { return .exceeded }
        if progress >= 0.8 { return .warning }
        return .ok
    }
    /// Сколько можно тратить в день до конца месяца, чтобы уложиться.
    public var dailyAllowance: Money? {
        guard daysLeft > 0, remaining.minorUnits > 0 else { return nil }
        return Money(minorUnits: remaining.minorUnits / Int64(daysLeft), currency: remaining.currency)
    }
    public var id: UUID { budget.id }
}

/// Прогресс цели.
public struct GoalStatus: Identifiable, Equatable, Sendable {
    public var goal: Goal
    public var saved: Money
    /// Сколько откладывать в месяц, чтобы успеть к сроку.
    public var monthlyNeeded: Money?
    public var monthsLeft: Int?

    public var remaining: Money {
        let value = goal.target - saved
        return value.isNegative ? .zero(value.currency) : value
    }
    public var progress: Double {
        guard goal.target.minorUnits > 0 else { return 0 }
        return min(max(Double(saved.minorUnits) / Double(goal.target.minorUnits), 0), 1)
    }
    public var isCompleted: Bool { saved.minorUnits >= goal.target.minorUnits }
    public var id: UUID { goal.id }
}
