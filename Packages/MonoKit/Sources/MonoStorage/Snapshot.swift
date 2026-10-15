import Foundation
import MonoCore

/// Полный снимок данных для резервной копии и экспорта. Шифрование выполняет приложение.
public struct LedgerSnapshot: Codable, Sendable, Equatable {
    public static let currentFormat = 1

    public var format: Int
    public var exportedAt: Date
    public var accounts: [Account]
    public var categories: [FinanceCategory]
    public var transactions: [FinanceTransaction]
    public var budgets: [Budget]
    public var goals: [Goal]
    public var contributions: [GoalContribution]
    public var plannedExpenses: [PlannedExpense]
    public var recurringRules: [RecurringRule]
    public var exchangeRates: [ExchangeRate]
    public var merchantRules: [MerchantRule]
    public var settings: [String: String]
    public var importProfiles: [ImportProfileRecord]

    public struct ImportProfileRecord: Codable, Sendable, Equatable {
        public var signature: String
        public var name: String
        public var payload: String
        public var updatedAt: Date
    }

    public func encoded() throws -> Data {
        try LedgerDatabase.makeEncoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> LedgerSnapshot {
        do {
            return try LedgerDatabase.makeDecoder().decode(LedgerSnapshot.self, from: data)
        } catch {
            throw StorageError.invalidSnapshot("не удалось прочитать данные")
        }
    }
}

extension LedgerDatabase {
    public func exportSnapshot(now: Date = Date()) throws -> LedgerSnapshot {
        LedgerSnapshot(
            format: LedgerSnapshot.currentFormat,
            exportedAt: now,
            accounts: try accounts(),
            categories: try categories(),
            transactions: try transactions(),
            budgets: try budgets(includeArchived: true),
            goals: try goals(),
            contributions: try goalContributions(),
            plannedExpenses: try plannedExpenses(),
            recurringRules: try recurringRules(),
            exchangeRates: try exchangeRates(),
            merchantRules: try merchantRules(),
            settings: try allSettings(),
            importProfiles: try importProfiles().map {
                LedgerSnapshot.ImportProfileRecord(signature: $0.signature, name: $0.name, payload: $0.payload, updatedAt: $0.updatedAt)
            }
        )
    }

    /// Полностью заменяет данные содержимым снимка — атомарно. Снимок предварительно проверяется.
    public func restore(from snapshot: LedgerSnapshot) throws {
        guard snapshot.format <= LedgerSnapshot.currentFormat else {
            throw StorageError.invalidSnapshot("формат \(snapshot.format) новее поддерживаемого")
        }
        let accountMap = Dictionary(snapshot.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let categoryMap = Dictionary(snapshot.categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard accountMap.count == snapshot.accounts.count else { throw StorageError.invalidSnapshot("повторяющиеся счета") }
        for transaction in snapshot.transactions {
            do {
                try Ledger.validate(transaction, accounts: accountMap, categories: categoryMap, isNew: false)
            } catch {
                throw StorageError.invalidSnapshot("операция \(transaction.id.uuidString.prefix(8)) не проходит проверку")
            }
        }

        try connection.transaction {
            try connection.execute("PRAGMA defer_foreign_keys = ON;")
            for table in ["audit_log", "goal_contributions", "goals", "budgets", "planned_expenses", "recurring_rules",
                          "merchant_rules", "transactions", "categories", "accounts", "exchange_rates", "settings", "import_profiles"] {
                try connection.execute("DELETE FROM \(table);")
            }
            for account in snapshot.accounts {
                try connection.run("INSERT INTO accounts (\(Self.accountColumns)) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", [
                    .uuid(account.id), .text(account.bank.rawValue), .text(account.name), .text(account.kind.rawValue),
                    .optionalText(account.paymentSystem?.rawValue), .text(account.currency.code), .optionalText(account.lastFour),
                    .text(account.skin.rawValue), .bool(account.includeInTotal), .bool(account.isArchived),
                    .integer(Int64(account.sortOrder)), .date(account.createdAt), .date(account.updatedAt)
                ])
            }
            for category in snapshot.categories { try saveCategory(category) }
            for transaction in snapshot.transactions {
                let tagsJSON = String(decoding: try JSONEncoder().encode(transaction.tags), as: UTF8.self)
                try connection.run("INSERT INTO transactions (\(Self.transactionColumns)) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", [
                    .uuid(transaction.id), .text(transaction.kind.rawValue), .integer(transaction.amount.minorUnits),
                    .text(transaction.amount.currency.code), .uuid(transaction.accountID), .uuid(transaction.counterAccountID),
                    .optionalInteger(transaction.counterAmount?.minorUnits), .optionalText(transaction.counterAmount?.currency.code),
                    .uuid(transaction.categoryID), .optionalText(transaction.merchant), .optionalText(transaction.note),
                    .text(tagsJSON), .date(transaction.date), .date(transaction.createdAt), .date(transaction.updatedAt),
                    .text(transaction.source.rawValue), .optionalText(transaction.importFingerprint),
                    .optionalText(transaction.receiptFileName), .uuid(transaction.linkedTransactionID),
                    .uuid(transaction.recurringRuleID), .bool(transaction.isOpeningBalance)
                ])
            }
            for budget in snapshot.budgets { try saveBudget(budget) }
            for goal in snapshot.goals { try saveGoal(goal) }
            for contribution in snapshot.contributions {
                try connection.run(
                    "INSERT INTO goal_contributions (id, goal_id, amount_minor, currency, occurred_at, note) VALUES (?, ?, ?, ?, ?, ?)",
                    [.uuid(contribution.id), .uuid(contribution.goalID), .integer(contribution.amount.minorUnits),
                     .text(contribution.amount.currency.code), .date(contribution.date), .optionalText(contribution.note)]
                )
            }
            for item in snapshot.plannedExpenses { try savePlannedExpense(item) }
            for rule in snapshot.recurringRules { try saveRecurringRule(rule) }
            try saveExchangeRates(snapshot.exchangeRates, keepManual: false)
            for rule in snapshot.merchantRules {
                try connection.run(
                    "INSERT INTO merchant_rules (rule_key, category_id, hits, updated_at) VALUES (?, ?, ?, ?)",
                    [.text(rule.key), .uuid(rule.categoryID), .integer(Int64(rule.hits)), .date(rule.updatedAt)]
                )
            }
            for (key, value) in snapshot.settings { try setSetting(key, value) }
            for profile in snapshot.importProfiles {
                try saveImportProfile(StoredImportProfile(signature: profile.signature, name: profile.name, payload: profile.payload, updatedAt: profile.updatedAt))
            }
        }
    }

    /// Проверка целостности: SQLite + финансовые инварианты. Пустой массив — всё в порядке.
    public func integrityIssues() throws -> [String] {
        var issues: [String] = []
        let sqliteCheck = try connection.query("PRAGMA integrity_check;") { $0.text(0) }
        if sqliteCheck != ["ok"] { issues.append(contentsOf: sqliteCheck) }
        let foreignKeys = try connection.query("PRAGMA foreign_key_check;") { $0.text(0) }
        if !foreignKeys.isEmpty { issues.append("foreign_key_check: \(foreignKeys.count)") }

        let accounts = try accountMap()
        let categories = try categoryMap()
        let all = try transactions()
        for transaction in all {
            do {
                try Ledger.validate(transaction, accounts: accounts, categories: categories, isNew: false)
            } catch {
                issues.append("transaction \(transaction.id): \(error)")
            }
        }
        let sqlBalances = try balances()
        let swiftBalances = Ledger.balances(accounts: Array(accounts.values), transactions: all)
        for (id, balance) in swiftBalances where sqlBalances[id] != balance {
            issues.append("balance mismatch for \(id)")
        }
        return issues
    }
}
