import Foundation
import MonoCore

extension LedgerDatabase {
    // MARK: - Бюджеты

    public func budgets(includeArchived: Bool = false) throws -> [Budget] {
        let filter = includeArchived ? "" : "WHERE is_archived = 0"
        return try connection.query(
            "SELECT id, category_id, limit_minor, currency, rollover, start_month, is_archived, created_at FROM budgets \(filter) ORDER BY category_id IS NOT NULL, created_at"
        ) { row in
            guard let id = row.uuid(0), let month = MonthKey(string: row.text(5)) else { return nil }
            return Budget(
                id: id,
                categoryID: row.optionalUUID(1),
                limit: Money(minorUnits: row.int64(2), currency: Currency(row.text(3))),
                rolloverEnabled: row.bool(4),
                startMonth: month,
                isArchived: row.bool(6),
                createdAt: row.date(7)
            )
        }
    }

    /// Создаёт или обновляет бюджет. На категорию допускается один активный бюджет.
    public func saveBudget(_ budget: Budget) throws {
        guard budget.limit.isPositive else { throw LedgerError.amountMustBePositive }
        try connection.run(
            """
            INSERT INTO budgets (id, category_id, limit_minor, currency, rollover, start_month, is_archived, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET category_id = excluded.category_id, limit_minor = excluded.limit_minor,
            currency = excluded.currency, rollover = excluded.rollover, start_month = excluded.start_month, is_archived = excluded.is_archived
            """,
            [
                .uuid(budget.id), .uuid(budget.categoryID), .integer(budget.limit.minorUnits), .text(budget.limit.currency.code),
                .bool(budget.rolloverEnabled), .text(budget.startMonth.description), .bool(budget.isArchived), .date(budget.createdAt)
            ]
        )
    }

    public func deleteBudget(id: UUID) throws {
        try connection.run("DELETE FROM budgets WHERE id = ?", [.uuid(id)])
    }

    // MARK: - Цели

    public func goals(includeArchived: Bool = true) throws -> [Goal] {
        let filter = includeArchived ? "" : "WHERE is_archived = 0"
        return try connection.query(
            "SELECT id, name, target_minor, currency, deadline, icon, color, linked_account_id, is_archived, created_at FROM goals \(filter) ORDER BY is_archived, created_at"
        ) { row in
            guard let id = row.uuid(0) else { return nil }
            return Goal(
                id: id,
                name: row.text(1),
                target: Money(minorUnits: row.int64(2), currency: Currency(row.text(3))),
                deadline: row.optionalDate(4),
                icon: row.text(5),
                color: CategoryColor(rawValue: row.text(6)) ?? .violet,
                linkedAccountID: row.optionalUUID(7),
                isArchived: row.bool(8),
                createdAt: row.date(9)
            )
        }
    }

    public func saveGoal(_ goal: Goal) throws {
        guard goal.target.isPositive else { throw LedgerError.amountMustBePositive }
        try connection.run(
            """
            INSERT INTO goals (id, name, target_minor, currency, deadline, icon, color, linked_account_id, is_archived, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name, target_minor = excluded.target_minor, currency = excluded.currency,
            deadline = excluded.deadline, icon = excluded.icon, color = excluded.color, linked_account_id = excluded.linked_account_id,
            is_archived = excluded.is_archived
            """,
            [
                .uuid(goal.id), .text(goal.name), .integer(goal.target.minorUnits), .text(goal.target.currency.code),
                .date(goal.deadline), .text(goal.icon), .text(goal.color.rawValue), .uuid(goal.linkedAccountID),
                .bool(goal.isArchived), .date(goal.createdAt)
            ]
        )
    }

    public func deleteGoal(id: UUID) throws {
        try connection.run("DELETE FROM goals WHERE id = ?", [.uuid(id)])
    }

    public func goalContributions(goalID: UUID? = nil) throws -> [GoalContribution] {
        let filter = goalID == nil ? "" : "WHERE goal_id = ?"
        let parameters: [SQLValue] = goalID.map { [.uuid($0)] } ?? []
        return try connection.query(
            "SELECT id, goal_id, amount_minor, currency, occurred_at, note FROM goal_contributions \(filter) ORDER BY occurred_at DESC",
            parameters
        ) { row in
            guard let id = row.uuid(0), let goal = row.uuid(1) else { return nil }
            return GoalContribution(
                id: id,
                goalID: goal,
                amount: Money(minorUnits: row.int64(2), currency: Currency(row.text(3))),
                date: row.date(4),
                note: row.optionalText(5)
            )
        }
    }

    public func addContribution(_ contribution: GoalContribution) throws {
        guard !contribution.amount.isZero else { throw LedgerError.adjustmentMustBeNonZero }
        try connection.transaction {
            guard let goal = try goals().first(where: { $0.id == contribution.goalID }) else { throw StorageError.notFound }
            guard goal.target.currency == contribution.amount.currency else {
                throw LedgerError.currencyMismatch(expected: goal.target.currency, actual: contribution.amount.currency)
            }
            try connection.run(
                "INSERT INTO goal_contributions (id, goal_id, amount_minor, currency, occurred_at, note) VALUES (?, ?, ?, ?, ?, ?)",
                [.uuid(contribution.id), .uuid(contribution.goalID), .integer(contribution.amount.minorUnits),
                 .text(contribution.amount.currency.code), .date(contribution.date), .optionalText(contribution.note)]
            )
        }
    }

    public func deleteContribution(id: UUID) throws {
        try connection.run("DELETE FROM goal_contributions WHERE id = ?", [.uuid(id)])
    }

    // MARK: - Запланированные расходы

    public func plannedExpenses() throws -> [PlannedExpense] {
        try connection.query(
            "SELECT id, title, amount_minor, currency, planned_at, category_id, note, is_completed, created_at FROM planned_expenses ORDER BY is_completed, planned_at"
        ) { row in
            guard let id = row.uuid(0) else { return nil }
            return PlannedExpense(
                id: id,
                title: row.text(1),
                amount: Money(minorUnits: row.int64(2), currency: Currency(row.text(3))),
                date: row.date(4),
                categoryID: row.optionalUUID(5),
                note: row.optionalText(6),
                isCompleted: row.bool(7),
                createdAt: row.date(8)
            )
        }
    }

    public func savePlannedExpense(_ item: PlannedExpense) throws {
        guard item.amount.isPositive else { throw LedgerError.amountMustBePositive }
        try connection.run(
            """
            INSERT INTO planned_expenses (id, title, amount_minor, currency, planned_at, category_id, note, is_completed, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET title = excluded.title, amount_minor = excluded.amount_minor, currency = excluded.currency,
            planned_at = excluded.planned_at, category_id = excluded.category_id, note = excluded.note, is_completed = excluded.is_completed
            """,
            [
                .uuid(item.id), .text(item.title), .integer(item.amount.minorUnits), .text(item.amount.currency.code),
                .date(item.date), .uuid(item.categoryID), .optionalText(item.note), .bool(item.isCompleted), .date(item.createdAt)
            ]
        )
    }

    public func deletePlannedExpense(id: UUID) throws {
        try connection.run("DELETE FROM planned_expenses WHERE id = ?", [.uuid(id)])
    }

    // MARK: - Регулярные платежи

    public func recurringRules() throws -> [RecurringRule] {
        try connection.query(
            """
            SELECT id, title, kind, amount_minor, currency, account_id, category_id, merchant, frequency, repeat_interval,
                   anchor_at, next_due_at, reminder, is_active, created_at
            FROM recurring_rules ORDER BY is_active DESC, next_due_at
            """
        ) { row in
            guard let id = row.uuid(0),
                  let kind = TransactionKind(rawValue: row.text(2)),
                  let account = row.uuid(5),
                  let frequency = RecurrenceFrequency(rawValue: row.text(8)) else { return nil }
            return RecurringRule(
                id: id,
                title: row.text(1),
                kind: kind,
                amount: Money(minorUnits: row.int64(3), currency: Currency(row.text(4))),
                accountID: account,
                categoryID: row.optionalUUID(6),
                merchant: row.optionalText(7),
                frequency: frequency,
                interval: row.int(9),
                anchorDate: row.date(10),
                nextDueDate: row.date(11),
                reminderEnabled: row.bool(12),
                isActive: row.bool(13),
                createdAt: row.date(14)
            )
        }
    }

    public func saveRecurringRule(_ rule: RecurringRule) throws {
        guard rule.kind == .expense || rule.kind == .income else { throw LedgerError.categoryKindMismatch }
        guard rule.amount.isPositive else { throw LedgerError.amountMustBePositive }
        guard let account = try account(id: rule.accountID) else { throw LedgerError.unknownAccount(rule.accountID) }
        guard account.currency == rule.amount.currency else {
            throw LedgerError.currencyMismatch(expected: account.currency, actual: rule.amount.currency)
        }
        try connection.run(
            """
            INSERT INTO recurring_rules (id, title, kind, amount_minor, currency, account_id, category_id, merchant, frequency,
                repeat_interval, anchor_at, next_due_at, reminder, is_active, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET title = excluded.title, kind = excluded.kind, amount_minor = excluded.amount_minor,
            currency = excluded.currency, account_id = excluded.account_id, category_id = excluded.category_id,
            merchant = excluded.merchant, frequency = excluded.frequency, repeat_interval = excluded.repeat_interval,
            anchor_at = excluded.anchor_at, next_due_at = excluded.next_due_at, reminder = excluded.reminder,
            is_active = excluded.is_active
            """,
            [
                .uuid(rule.id), .text(rule.title), .text(rule.kind.rawValue), .integer(rule.amount.minorUnits),
                .text(rule.amount.currency.code), .uuid(rule.accountID), .uuid(rule.categoryID), .optionalText(rule.merchant),
                .text(rule.frequency.rawValue), .integer(Int64(rule.interval)), .date(rule.anchorDate), .date(rule.nextDueDate),
                .bool(rule.reminderEnabled), .bool(rule.isActive), .date(rule.createdAt)
            ]
        )
    }

    public func deleteRecurringRule(id: UUID) throws {
        try connection.run("DELETE FROM recurring_rules WHERE id = ?", [.uuid(id)])
    }

    /// Подтверждает ближайший платёж: создаёт операцию и переносит дату на следующее повторение — атомарно.
    @discardableResult
    public func confirmRecurring(ruleID: UUID, amount: Money? = nil, date: Date? = nil, calendar: Calendar) throws -> FinanceTransaction {
        try connection.transaction {
            guard let rule = try recurringRules().first(where: { $0.id == ruleID }) else { throw StorageError.notFound }
            let transaction = FinanceTransaction(
                kind: rule.kind,
                amount: amount ?? rule.amount,
                accountID: rule.accountID,
                categoryID: rule.categoryID,
                merchant: rule.merchant,
                note: rule.title,
                date: date ?? rule.nextDueDate,
                source: .recurring,
                recurringRuleID: rule.id
            )
            try insert(transaction)
            try advanceRecurring(rule, calendar: calendar)
            return transaction
        }
    }

    /// Пропускает ближайшее повторение без создания операции.
    public func skipRecurring(ruleID: UUID, calendar: Calendar) throws {
        try connection.transaction {
            guard let rule = try recurringRules().first(where: { $0.id == ruleID }) else { throw StorageError.notFound }
            try advanceRecurring(rule, calendar: calendar)
        }
    }

    private func advanceRecurring(_ rule: RecurringRule, calendar: Calendar) throws {
        let next = RecurrenceMath.nextOccurrence(
            after: rule.nextDueDate,
            anchor: rule.anchorDate,
            frequency: rule.frequency,
            interval: rule.interval,
            calendar: calendar
        )
        try connection.run("UPDATE recurring_rules SET next_due_at = ? WHERE id = ?", [.date(next), .uuid(rule.id)])
    }
}
