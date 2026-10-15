import Foundation
import Observation
import MonoCore
import MonoStorage
import MonoAnalytics
import MonoIntelligence

/// Главное хранилище состояния. Читает SQLite, держит снимок данных в памяти и пересчитывает производные значения.
/// Все записи проходят через `LedgerDatabase` (валидация + атомарность), после чего снимок перезагружается.
@MainActor
@Observable
final class FinanceStore {
    private(set) var accounts: [Account] = []
    private(set) var categories: [FinanceCategory] = []
    /// Операции, новые сверху.
    private(set) var transactions: [FinanceTransaction] = []
    private(set) var balances: [UUID: Money] = [:]
    private(set) var budgets: [Budget] = []
    private(set) var goals: [Goal] = []
    private(set) var contributions: [GoalContribution] = []
    private(set) var planned: [PlannedExpense] = []
    private(set) var recurring: [RecurringRule] = []
    private(set) var rates: [ExchangeRate] = []
    private(set) var merchantRules: [MerchantRule] = []
    private(set) var baseCurrency: Currency = .uzs
    private(set) var defaultAccountID: UUID?
    /// Увеличивается при каждом изменении данных — удобно для `.task(id:)`.
    private(set) var revision = 0
    private(set) var loadError: AppError?

    let database: LedgerDatabase
    let isDemo: Bool
    let periods: PeriodCalendar

    init(database: LedgerDatabase, isDemo: Bool, periods: PeriodCalendar = PeriodCalendar()) {
        self.database = database
        self.isDemo = isDemo
        self.periods = periods
        reload()
    }

    // MARK: - Загрузка

    func reload() {
        do {
            accounts = try database.accounts()
            categories = try database.categories()
            transactions = try database.transactions()
            balances = try database.balances()
            budgets = try database.budgets(includeArchived: true)
            goals = try database.goals()
            contributions = try database.goalContributions()
            planned = try database.plannedExpenses()
            recurring = try database.recurringRules()
            rates = try database.exchangeRates()
            merchantRules = try database.merchantRules()
            baseCurrency = (try database.setting(StoreKeys.baseCurrency)).map { Currency($0) } ?? .uzs
            defaultAccountID = (try database.setting(StoreKeys.defaultAccount)).flatMap { UUID(uuidString: $0) }
            loadError = nil
        } catch {
            loadError = AppError(error)
        }
        revision &+= 1
    }

    enum StoreKeys {
        static let baseCurrency = "baseCurrency"
        static let defaultAccount = "defaultAccountID"
    }

    // MARK: - Производные значения

    var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }
    var archivedAccounts: [Account] { accounts.filter(\.isArchived) }
    var accountMap: [UUID: Account] { Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) }) }
    var categoryMap: [UUID: FinanceCategory] { Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) }) }
    var activeCategories: [FinanceCategory] { categories.filter { !$0.isArchived } }
    var hasData: Bool { !accounts.isEmpty }

    func categories(for kind: TransactionKind) -> [FinanceCategory] {
        guard let categoryKind = kind.categoryKind else { return [] }
        return activeCategories.filter { $0.kind == categoryKind }
    }

    var converter: CurrencyConverter { CurrencyConverter(base: baseCurrency, rates: rates) }

    func balance(of account: Account) -> Money { balances[account.id] ?? .zero(account.currency) }

    var defaultAccount: Account? {
        if let id = defaultAccountID, let account = activeAccounts.first(where: { $0.id == id }) { return account }
        return activeAccounts.first
    }

    /// Общий баланс счетов, включённых в итог, в базовой валюте.
    var totalBalance: (total: Money, excluded: Set<Currency>) { analytics().totalBalance() }

    func analytics() -> AnalyticsEngine {
        AnalyticsEngine(transactions: transactions, accounts: accounts, categories: categories, converter: converter, periods: periods)
    }

    func categorizer() -> CategorizationEngine {
        CategorizationEngine(categories: categories, rules: merchantRules)
    }

    func voiceParser(now: Date = Date()) -> VoiceCommandParser {
        VoiceCommandParser(context: VoiceParserContext(
            accounts: activeAccounts,
            categories: categories,
            merchantRules: merchantRules,
            defaultAccountID: defaultAccount?.id,
            baseCurrency: baseCurrency,
            converter: converter,
            now: now,
            periods: periods
        ))
    }

    func transactions(for account: Account) -> [FinanceTransaction] {
        transactions.filter { $0.involves(account: account.id) }
    }

    func transaction(id: UUID) -> FinanceTransaction? { transactions.first { $0.id == id } }

    /// Регулярные платежи, ожидающие подтверждения (дата наступила).
    func dueRecurring(now: Date = Date()) -> [RecurringRule] {
        let endOfToday = periods.addingDays(1, to: periods.startOfDay(now))
        return recurring.filter { $0.isActive && $0.nextDueDate < endOfToday }
    }

    // MARK: - Запись (каждый метод атомарен на уровне базы)

    private func perform(_ work: () throws -> Void) throws {
        do {
            try work()
            reload()
        } catch {
            reload()
            throw AppError(error)
        }
    }

    func createAccount(_ account: Account, openingBalance: Money?) throws {
        try perform {
            var account = account
            account.sortOrder = (accounts.map(\.sortOrder).max() ?? -1) + 1
            try database.createAccount(account, openingBalance: openingBalance, openingDate: Date())
            if defaultAccountID == nil { try database.setSetting(StoreKeys.defaultAccount, account.id.uuidString) }
        }
    }

    func updateAccount(_ account: Account) throws { try perform { try database.updateAccount(account) } }
    func setArchived(_ account: Account, archived: Bool) throws { try perform { try database.setAccountArchived(account.id, archived: archived) } }
    func deleteAccount(_ account: Account) throws {
        try perform {
            try database.deleteAccount(account.id)
            if defaultAccountID == account.id { try database.setSetting(StoreKeys.defaultAccount, nil) }
        }
    }
    func reorderAccounts(_ ids: [UUID]) throws { try perform { try database.reorderAccounts(ids) } }
    func setDefaultAccount(_ account: Account?) throws { try perform { try database.setSetting(StoreKeys.defaultAccount, account?.id.uuidString) } }
    func setBaseCurrency(_ currency: Currency) throws { try perform { try database.setSetting(StoreKeys.baseCurrency, currency.code) } }

    @discardableResult
    func setBalance(of account: Account, to target: Money) throws -> FinanceTransaction? {
        var result: FinanceTransaction?
        try perform { result = try database.setBalance(accountID: account.id, to: target) }
        return result
    }

    /// Создаёт или обновляет операцию. Для перевода с комиссией используйте `saveTransfer`.
    func save(_ transaction: FinanceTransaction, isNew: Bool) throws {
        try perform {
            if isNew { try database.insert(transaction) } else { try database.update(transaction) }
        }
    }

    func saveTransfer(_ transfer: FinanceTransaction, fee: Money?) throws {
        try perform { try database.insertTransfer(transfer, fee: fee) }
    }

    /// Пакетная запись (голосовые черновики): либо все, либо ни одной.
    func insert(batch: [FinanceTransaction]) throws {
        try perform { try database.insert(batch: batch) }
    }

    func delete(_ transaction: FinanceTransaction) throws {
        try perform { try database.deleteTransaction(id: transaction.id) }
    }

    /// Восстановление удалённой операции (кнопка «Вернуть» в уведомлении).
    func restore(_ transactions: [FinanceTransaction]) throws {
        try perform { try database.insert(batch: transactions.filter { self.accountMap[$0.accountID] != nil }) }
    }

    func linkedFees(of transaction: FinanceTransaction) -> [FinanceTransaction] {
        transactions.filter { $0.linkedTransactionID == transaction.id && $0.kind == .fee }
    }

    func auditTrail(for transaction: FinanceTransaction) -> [AuditEntry] {
        (try? database.auditTrail(transactionID: transaction.id)) ?? []
    }

    /// Запоминает выбор категории для продавца (умная категоризация учится на исправлениях).
    func learnCategory(merchant: String?, categoryID: UUID?) {
        guard let merchant, !merchant.trimmingCharacters(in: .whitespaces).isEmpty, let categoryID else { return }
        let key = CategorizationEngine.learningKey(for: merchant)
        guard !key.isEmpty else { return }
        try? database.learnMerchant(key: key, categoryID: categoryID)
        merchantRules = (try? database.merchantRules()) ?? merchantRules
    }

    func forgetRule(_ rule: MerchantRule) throws { try perform { try database.forgetMerchant(key: rule.key) } }

    // Категории
    func saveCategory(_ category: FinanceCategory) throws { try perform { try database.saveCategory(category) } }
    func setArchived(_ category: FinanceCategory, archived: Bool) throws { try perform { try database.setCategoryArchived(category.id, archived: archived) } }
    func deleteCategory(_ category: FinanceCategory) throws { try perform { try database.deleteCategory(category.id) } }
    func reassign(from source: FinanceCategory, to target: FinanceCategory) throws {
        try perform { try database.reassignTransactions(fromCategory: source.id, to: target.id) }
    }

    // Планы
    func saveBudget(_ budget: Budget) throws { try perform { try database.saveBudget(budget) } }
    func deleteBudget(_ budget: Budget) throws { try perform { try database.deleteBudget(id: budget.id) } }
    func saveGoal(_ goal: Goal) throws { try perform { try database.saveGoal(goal) } }
    func deleteGoal(_ goal: Goal) throws { try perform { try database.deleteGoal(id: goal.id) } }
    func addContribution(_ contribution: GoalContribution) throws { try perform { try database.addContribution(contribution) } }
    func deleteContribution(_ contribution: GoalContribution) throws { try perform { try database.deleteContribution(id: contribution.id) } }
    func savePlanned(_ item: PlannedExpense) throws { try perform { try database.savePlannedExpense(item) } }
    func deletePlanned(_ item: PlannedExpense) throws { try perform { try database.deletePlannedExpense(id: item.id) } }
    func saveRecurring(_ rule: RecurringRule) throws { try perform { try database.saveRecurringRule(rule) } }
    func deleteRecurring(_ rule: RecurringRule) throws { try perform { try database.deleteRecurringRule(id: rule.id) } }

    @discardableResult
    func confirmRecurring(_ rule: RecurringRule, amount: Money? = nil) throws -> FinanceTransaction? {
        var created: FinanceTransaction?
        try perform { created = try database.confirmRecurring(ruleID: rule.id, amount: amount, calendar: periods.calendar) }
        return created
    }

    func skipRecurring(_ rule: RecurringRule) throws {
        try perform { try database.skipRecurring(ruleID: rule.id, calendar: periods.calendar) }
    }

    // Курсы и импорт
    func saveRates(_ rates: [ExchangeRate], keepManual: Bool = true) throws {
        try perform { try database.saveExchangeRates(rates, keepManual: keepManual) }
    }

    func deleteRate(_ currency: Currency) throws { try perform { try database.deleteExchangeRate(currency) } }

    func importTransactions(_ transactions: [FinanceTransaction], replacing: [UUID] = []) throws -> ImportWriteResult {
        var result = ImportWriteResult(inserted: 0, skippedDuplicates: 0)
        try perform { result = try database.importTransactions(transactions, replacing: replacing) }
        return result
    }

    func importProfiles() -> [StoredImportProfile] { (try? database.importProfiles()) ?? [] }
    func saveImportProfile(_ profile: StoredImportProfile) { try? database.saveImportProfile(profile) }

    // Резервные копии
    func snapshot() throws -> LedgerSnapshot { try database.exportSnapshot() }
    func restore(snapshot: LedgerSnapshot) throws { try perform { try database.restore(from: snapshot) } }
    func integrityIssues() -> [String] { (try? database.integrityIssues()) ?? ["integrity check failed"] }
}
