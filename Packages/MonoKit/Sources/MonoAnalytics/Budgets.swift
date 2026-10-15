import Foundation
import MonoCore

extension AnalyticsEngine {
    /// Потрачено по бюджету за месяц: общий бюджет — все расходы и комиссии, бюджет категории — её расходы за вычетом возвратов.
    public func spent(for budget: Budget, in month: MonthKey) -> Money {
        let range = periods.monthRange(month)
        if let categoryID = budget.categoryID {
            return spendingByCategory(range).first { $0.categoryID == categoryID }?.amount ?? zero
        }
        let total = summary(range).outflow
        return total.isNegative ? zero : total
    }

    /// Состояние бюджетов на месяц с учётом переноса неиспользованного остатка.
    public func budgetStatuses(_ budgets: [Budget], month: MonthKey, now: Date) -> [BudgetStatus] {
        budgets.filter { !$0.isArchived && $0.startMonth <= month }.compactMap { budget in
            guard let limit = converter.toBase(budget.limit) else { return nil }
            var carried = zero
            if budget.rolloverEnabled {
                var key = budget.startMonth
                var carry = zero
                while key < month {
                    let effective = limit + carry
                    let left = effective - spent(for: budget, in: key)
                    carry = left.isPositive ? left : zero
                    key = key.next
                }
                carried = carry
            }
            let spent = spent(for: budget, in: month)
            let range = periods.monthRange(month)
            let isCurrent = range.contains(now)
            let daysLeft: Int
            var projected: Money?
            if isCurrent {
                let today = periods.startOfDay(now)
                daysLeft = max(0, periods.numberOfDays(in: DateRange(start: today, end: range.end)))
                let elapsed = elapsedDays(range, now: now)
                if elapsed >= 3 {
                    projected = Money(minorUnits: spent.minorUnits * Int64(periods.dayCount(of: month)) / Int64(elapsed), currency: base)
                }
            } else {
                daysLeft = range.end <= now ? 0 : periods.dayCount(of: month)
            }
            return BudgetStatus(budget: budget, month: month, baseLimit: limit, carriedOver: carried, spent: spent,
                                projectedSpend: projected, daysLeft: daysLeft)
        }
        .sorted { lhs, rhs in
            if lhs.budget.isOverall != rhs.budget.isOverall { return lhs.budget.isOverall }
            return lhs.progress > rhs.progress
        }
    }

    /// Прогресс целей: баланс привязанного счёта или сумма взносов.
    public func goalStatuses(_ goals: [Goal], contributions: [GoalContribution], balances: [UUID: Money], now: Date) -> [GoalStatus] {
        goals.filter { !$0.isArchived }.map { goal in
            var saved = Money.zero(goal.target.currency)
            if let accountID = goal.linkedAccountID, let balance = balances[accountID] {
                saved = converter.convert(balance, to: goal.target.currency) ?? saved
            } else {
                for contribution in contributions where contribution.goalID == goal.id {
                    if let value = saved.adding(contribution.amount) { saved = value }
                }
            }
            var monthly: Money?
            var monthsLeft: Int?
            if let deadline = goal.deadline, deadline > now {
                let months = max(1, periods.monthKey(now).distance(to: periods.monthKey(deadline)))
                monthsLeft = months
                let remaining = goal.target - saved
                if remaining.isPositive {
                    let perMonth = (remaining.minorUnits + Int64(months) - 1) / Int64(months)
                    monthly = Money(minorUnits: perMonth, currency: goal.target.currency)
                }
            }
            return GoalStatus(goal: goal, saved: saved, monthlyNeeded: monthly, monthsLeft: monthsLeft)
        }
    }
}
