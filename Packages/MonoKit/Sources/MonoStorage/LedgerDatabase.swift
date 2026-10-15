import Foundation
import MonoCore

/// Ошибки хранилища (помимо нарушений правил `LedgerError`).
public enum StorageError: Error, Equatable, Sendable {
    case notFound
    case currencyLocked
    case categoryInUse(count: Int)
    case invalidSnapshot(String)
    case integrity(String)

    public func message(_ language: AppLanguage) -> String {
        switch self {
        case .notFound:
            return Phrase(ru: "Запись не найдена.", uz: "Yozuv topilmadi.", en: "Record not found.")(language)
        case .currencyLocked:
            return Phrase(ru: "Валюту счёта нельзя менять, пока на нём есть операции.", uz: "Operatsiyalari bor hisob valyutasini o‘zgartirib bo‘lmaydi.", en: "Can't change the currency of an account with transactions.")(language)
        case .categoryInUse(let count):
            return Phrase(ru: "Категория используется в \(count) операциях. Перенесите их или отправьте категорию в архив.",
                          uz: "Kategoriya \(count) ta operatsiyada ishlatilgan.",
                          en: "FinanceCategory is used by \(count) transactions. Move them or archive the category.")(language)
        case .invalidSnapshot(let reason):
            return Phrase(ru: "Резервная копия повреждена: \(reason)", uz: "Zaxira nusxa buzilgan: \(reason)", en: "Backup is invalid: \(reason)")(language)
        case .integrity(let reason):
            return Phrase(ru: "Нарушена целостность данных: \(reason)", uz: "Ma’lumotlar yaxlitligi buzilgan: \(reason)", en: "Data integrity issue: \(reason)")(language)
        }
    }
}

/// Запись истории изменений операции.
public struct AuditEntry: Identifiable, Hashable, Sendable {
    public enum Change: String, Sendable {
        case created
        case updated
        case deleted
    }

    public let id: Int64
    public let entityID: UUID
    public let change: Change
    public let date: Date
    public let before: FinanceTransaction?
    public let after: FinanceTransaction?
}

/// Итог записи импортированных операций.
public struct ImportWriteResult: Equatable, Sendable {
    public var inserted: Int
    public var skippedDuplicates: Int
}

/// Сохранённый профиль сопоставления колонок (формат задаёт модуль импорта).
public struct StoredImportProfile: Hashable, Sendable {
    public var signature: String
    public var name: String
    public var payload: String
    public var updatedAt: Date

    public init(signature: String, name: String, payload: String, updatedAt: Date = Date()) {
        self.signature = signature
        self.name = name
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

/// Локальная база MONO Finance поверх SQLite.
///
/// Балансы нигде не хранятся — вычисляются из проводок. Каждая операция записи атомарна:
/// перевод + комиссия, импорт пакета, восстановление копии выполняются в одной транзакции SQLite.
public final class LedgerDatabase {
    let connection: SQLiteConnection
    public let path: String

    public init(path: String) throws {
        self.path = path
        connection = try SQLiteConnection(path: path)
        try Schema.migrate(connection)
    }

    /// База в памяти — для тестов и превью.
    public static func inMemory() throws -> LedgerDatabase {
        try LedgerDatabase(path: ":memory:")
    }

    public var schemaVersion: Int { (try? connection.userVersion) ?? 0 }
    public static var sqliteVersion: String { SQLiteConnection.libraryVersion }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    // MARK: - Счета

    static let accountColumns = "id, bank, name, kind, payment_system, currency, last_four, skin, include_in_total, is_archived, sort_order, created_at, updated_at"

    static func account(from row: SQLRow) -> Account? {
        guard let id = row.uuid(0),
              let bank = Bank(rawValue: row.text(1)),
              let kind = AccountKind(rawValue: row.text(3)) else { return nil }
        return Account(
            id: id,
            bank: bank,
            name: row.text(2),
            kind: kind,
            paymentSystem: row.optionalText(4).flatMap(PaymentSystem.init(rawValue:)),
            currency: Currency(row.text(5)),
            lastFour: row.optionalText(6),
            skin: CardSkin(rawValue: row.text(7)) ?? CardSkin.default(for: bank),
            includeInTotal: row.bool(8),
            isArchived: row.bool(9),
            sortOrder: row.int(10),
            createdAt: row.date(11),
            updatedAt: row.date(12)
        )
    }

    public func accounts(includeArchived: Bool = true) throws -> [Account] {
        let filter = includeArchived ? "" : "WHERE is_archived = 0"
        return try connection.query("SELECT \(Self.accountColumns) FROM accounts \(filter) ORDER BY is_archived, sort_order, created_at") { Self.account(from: $0) }
    }

    public func account(id: UUID) throws -> Account? {
        try connection.query("SELECT \(Self.accountColumns) FROM accounts WHERE id = ?", [.uuid(id)]) { Self.account(from: $0) }.first
    }

    private func accountValues(_ account: Account) -> [SQLValue] {
        [
            .uuid(account.id), .text(account.bank.rawValue), .text(account.name), .text(account.kind.rawValue),
            .optionalText(account.paymentSystem?.rawValue), .text(account.currency.code), .optionalText(account.lastFour),
            .text(account.skin.rawValue), .bool(account.includeInTotal), .bool(account.isArchived),
            .integer(Int64(account.sortOrder)), .date(account.createdAt), .date(account.updatedAt)
        ]
    }

    /// Создаёт счёт и, если указан, начальный остаток (корректировка с флагом `isOpeningBalance`) — атомарно.
    @discardableResult
    public func createAccount(_ account: Account, openingBalance: Money? = nil, openingDate: Date = Date()) throws -> FinanceTransaction? {
        try connection.transaction {
            guard account.currency.isWellFormed else { throw LedgerError.currencyMismatch(expected: .uzs, actual: account.currency) }
            try connection.run("INSERT INTO accounts (\(Self.accountColumns)) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", accountValues(account))
            guard let opening = openingBalance, !opening.isZero else { return nil }
            let transaction = FinanceTransaction(
                kind: .adjustment,
                amount: opening,
                accountID: account.id,
                note: Phrase(ru: "Начальный остаток", uz: "Boshlang‘ich qoldiq", en: "Opening balance")(.ru),
                date: openingDate,
                source: .manual,
                isOpeningBalance: true
            )
            try insertValidated(transaction, isNew: true)
            return transaction
        }
    }

    public func updateAccount(_ account: Account) throws {
        try connection.transaction {
            guard let existing = try self.account(id: account.id) else { throw StorageError.notFound }
            if existing.currency != account.currency {
                let count = try connection.scalarInt(
                    "SELECT COUNT(*) FROM transactions WHERE account_id = ? OR counter_account_id = ?",
                    [.uuid(account.id), .uuid(account.id)]
                ) ?? 0
                if count > 0 { throw StorageError.currencyLocked }
            }
            var updated = account
            updated.updatedAt = Date()
            try connection.run(
                """
                UPDATE accounts SET bank = ?, name = ?, kind = ?, payment_system = ?, currency = ?, last_four = ?, skin = ?,
                include_in_total = ?, is_archived = ?, sort_order = ?, updated_at = ? WHERE id = ?
                """,
                [
                    .text(updated.bank.rawValue), .text(updated.name), .text(updated.kind.rawValue),
                    .optionalText(updated.paymentSystem?.rawValue), .text(updated.currency.code), .optionalText(updated.lastFour),
                    .text(updated.skin.rawValue), .bool(updated.includeInTotal), .bool(updated.isArchived),
                    .integer(Int64(updated.sortOrder)), .date(updated.updatedAt), .uuid(updated.id)
                ]
            )
        }
    }

    public func setAccountArchived(_ id: UUID, archived: Bool) throws {
        let changed = try connection.run("UPDATE accounts SET is_archived = ?, updated_at = ? WHERE id = ?", [.bool(archived), .date(Date()), .uuid(id)])
        if changed == 0 { throw StorageError.notFound }
    }

    public func reorderAccounts(_ ids: [UUID]) throws {
        try connection.transaction {
            for (index, id) in ids.enumerated() {
                try connection.run("UPDATE accounts SET sort_order = ? WHERE id = ?", [.integer(Int64(index)), .uuid(id)])
            }
        }
    }

    /// Удаляет счёт вместе со всеми операциями, где он участвует (включая переводы), одной транзакцией.
    public func deleteAccount(_ id: UUID) throws {
        try connection.transaction {
            guard let existing = try account(id: id) else { throw StorageError.notFound }
            let involved = try connection.query(
                "SELECT \(Self.transactionColumns) FROM transactions WHERE account_id = ? OR counter_account_id = ?",
                [.uuid(id), .uuid(id)]
            ) { Self.transaction(from: $0) }
            for transaction in involved {
                try audit(.deleted, before: transaction, after: nil)
            }
            try connection.run("DELETE FROM transactions WHERE account_id = ? OR counter_account_id = ?", [.uuid(id), .uuid(id)])
            try connection.run("DELETE FROM accounts WHERE id = ?", [.uuid(existing.id)])
        }
    }

    // MARK: - Категории

    static let categoryColumns = "id, name, kind, icon, color, is_mandatory, system_key, is_archived, sort_order"

    static func category(from row: SQLRow) -> FinanceCategory? {
        guard let id = row.uuid(0), let kind = CategoryKind(rawValue: row.text(2)) else { return nil }
        return FinanceCategory(
            id: id,
            name: row.text(1),
            kind: kind,
            icon: row.text(3),
            color: CategoryColor(rawValue: row.text(4)) ?? .steel,
            isMandatory: row.bool(5),
            systemKey: row.optionalText(6),
            isArchived: row.bool(7),
            sortOrder: row.int(8)
        )
    }

    public func categories() throws -> [FinanceCategory] {
        try connection.query("SELECT \(Self.categoryColumns) FROM categories ORDER BY kind, sort_order, name") { Self.category(from: $0) }
    }

    /// Добавляет встроенные категории, которых ещё нет (по `system_key`). Пользовательские правки не трогает.
    @discardableResult
    public func seedDefaultCategories(language: AppLanguage) throws -> Int {
        try connection.transaction {
            var inserted = 0
            for category in DefaultCategories.make(language: language) {
                inserted += try connection.run(
                    "INSERT OR IGNORE INTO categories (\(Self.categoryColumns)) VALUES (?,?,?,?,?,?,?,?,?)",
                    categoryValues(category)
                )
            }
            return inserted
        }
    }

    private func categoryValues(_ category: FinanceCategory) -> [SQLValue] {
        [
            .uuid(category.id), .text(category.name), .text(category.kind.rawValue), .text(category.icon),
            .text(category.color.rawValue), .bool(category.isMandatory), .optionalText(category.systemKey),
            .bool(category.isArchived), .integer(Int64(category.sortOrder))
        ]
    }

    public func saveCategory(_ category: FinanceCategory) throws {
        try connection.run(
            """
            INSERT INTO categories (\(Self.categoryColumns)) VALUES (?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name, kind = excluded.kind, icon = excluded.icon, color = excluded.color,
            is_mandatory = excluded.is_mandatory, is_archived = excluded.is_archived, sort_order = excluded.sort_order
            """,
            categoryValues(category)
        )
    }

    public func setCategoryArchived(_ id: UUID, archived: Bool) throws {
        let changed = try connection.run("UPDATE categories SET is_archived = ? WHERE id = ?", [.bool(archived), .uuid(id)])
        if changed == 0 { throw StorageError.notFound }
    }

    /// Переносит операции в другую категорию того же типа.
    public func reassignTransactions(fromCategory source: UUID, to target: UUID) throws {
        try connection.transaction {
            let all = try categories()
            guard let from = all.first(where: { $0.id == source }), let to = all.first(where: { $0.id == target }) else {
                throw StorageError.notFound
            }
            guard from.kind == to.kind else { throw LedgerError.categoryKindMismatch }
            try connection.run("UPDATE transactions SET category_id = ?, updated_at = ? WHERE category_id = ?", [.uuid(target), .date(Date()), .uuid(source)])
            try connection.run("UPDATE budgets SET category_id = ? WHERE category_id = ? AND is_archived = 0 AND NOT EXISTS (SELECT 1 FROM budgets b WHERE b.category_id = ? AND b.is_archived = 0)", [.uuid(target), .uuid(source), .uuid(target)])
        }
    }

    /// Удаляет неиспользуемую категорию.
    public func deleteCategory(_ id: UUID) throws {
        try connection.transaction {
            let used = try connection.scalarInt("SELECT COUNT(*) FROM transactions WHERE category_id = ?", [.uuid(id)]) ?? 0
            if used > 0 { throw StorageError.categoryInUse(count: Int(used)) }
            let changed = try connection.run("DELETE FROM categories WHERE id = ?", [.uuid(id)])
            if changed == 0 { throw StorageError.notFound }
        }
    }

    // MARK: - Операции

    static let transactionColumns = """
    id, kind, amount_minor, currency, account_id, counter_account_id, counter_amount_minor, counter_currency, category_id, \
    merchant, note, tags, occurred_at, created_at, updated_at, source, import_fingerprint, receipt_file, \
    linked_transaction_id, recurring_rule_id, is_opening
    """

    static func transaction(from row: SQLRow) -> FinanceTransaction? {
        guard let id = row.uuid(0),
              let kind = TransactionKind(rawValue: row.text(1)),
              let accountID = row.uuid(4) else { return nil }
        let counterAmount: Money?
        if let minor = row.optionalInt64(6), let code = row.optionalText(7) {
            counterAmount = Money(minorUnits: minor, currency: Currency(code))
        } else {
            counterAmount = nil
        }
        let tags = (try? JSONDecoder().decode([String].self, from: Data(row.text(11).utf8))) ?? []
        return FinanceTransaction(
            id: id,
            kind: kind,
            amount: Money(minorUnits: row.int64(2), currency: Currency(row.text(3))),
            accountID: accountID,
            counterAccountID: row.optionalUUID(5),
            counterAmount: counterAmount,
            categoryID: row.optionalUUID(8),
            merchant: row.optionalText(9),
            note: row.optionalText(10),
            tags: tags,
            date: row.date(12),
            createdAt: row.date(13),
            updatedAt: row.date(14),
            source: TransactionSource(rawValue: row.text(15)) ?? .manual,
            importFingerprint: row.optionalText(16),
            receiptFileName: row.optionalText(17),
            linkedTransactionID: row.optionalUUID(18),
            recurringRuleID: row.optionalUUID(19),
            isOpeningBalance: row.bool(20)
        )
    }

    private func transactionValues(_ t: FinanceTransaction) -> [SQLValue] {
        let tagsJSON = (try? JSONEncoder().encode(t.tags)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        return [
            .uuid(t.id), .text(t.kind.rawValue), .integer(t.amount.minorUnits), .text(t.amount.currency.code),
            .uuid(t.accountID), .uuid(t.counterAccountID), .optionalInteger(t.counterAmount?.minorUnits),
            .optionalText(t.counterAmount?.currency.code), .uuid(t.categoryID), .optionalText(Self.clean(t.merchant)),
            .optionalText(Self.clean(t.note)), .text(tagsJSON), .date(t.date), .date(t.createdAt), .date(t.updatedAt),
            .text(t.source.rawValue), .optionalText(t.importFingerprint), .optionalText(t.receiptFileName),
            .uuid(t.linkedTransactionID), .uuid(t.recurringRuleID), .bool(t.isOpeningBalance)
        ]
    }

    static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Все операции, новые сверху.
    public func transactions() throws -> [FinanceTransaction] {
        try connection.query("SELECT \(Self.transactionColumns) FROM transactions ORDER BY occurred_at DESC, created_at DESC, id") { Self.transaction(from: $0) }
    }

    public func transactions(accountID: UUID) throws -> [FinanceTransaction] {
        try connection.query(
            "SELECT \(Self.transactionColumns) FROM transactions WHERE account_id = ? OR counter_account_id = ? ORDER BY occurred_at DESC, created_at DESC, id",
            [.uuid(accountID), .uuid(accountID)]
        ) { Self.transaction(from: $0) }
    }

    public func transaction(id: UUID) throws -> FinanceTransaction? {
        try connection.query("SELECT \(Self.transactionColumns) FROM transactions WHERE id = ?", [.uuid(id)]) { Self.transaction(from: $0) }.first
    }

    public func transactionCount() throws -> Int {
        Int(try connection.scalarInt("SELECT COUNT(*) FROM transactions") ?? 0)
    }

    func accountMap() throws -> [UUID: Account] {
        Dictionary(uniqueKeysWithValues: try accounts().map { ($0.id, $0) })
    }

    func categoryMap() throws -> [UUID: FinanceCategory] {
        Dictionary(uniqueKeysWithValues: try categories().map { ($0.id, $0) })
    }

    private func insertValidated(_ transaction: FinanceTransaction, isNew: Bool) throws {
        try Ledger.validate(transaction, accounts: try accountMap(), categories: try categoryMap(), isNew: isNew)
        try connection.run("INSERT INTO transactions (\(Self.transactionColumns)) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", transactionValues(transaction))
        try audit(.created, before: nil, after: transaction)
    }

    /// Проверяет и записывает операцию.
    @discardableResult
    public func insert(_ transaction: FinanceTransaction) throws -> FinanceTransaction {
        try connection.transaction { try insertValidated(transaction, isNew: true) }
        return transaction
    }

    /// Записывает несколько операций одной транзакцией (например, голосовые черновики). Либо все, либо ни одной.
    public func insert(batch: [FinanceTransaction]) throws {
        try connection.transaction {
            for transaction in batch { try insertValidated(transaction, isNew: true) }
        }
    }

    /// Перевод между своими счетами и (опционально) комиссия со счёта-источника — атомарно.
    @discardableResult
    public func insertTransfer(_ transfer: FinanceTransaction, fee: Money?) throws -> (transfer: FinanceTransaction, fee: FinanceTransaction?) {
        precondition(transfer.kind == .transfer, "insertTransfer ожидает операцию перевода")
        return try connection.transaction {
            try insertValidated(transfer, isNew: true)
            guard let fee, !fee.isZero else { return (transfer, nil) }
            let feeTransaction = FinanceTransaction(
                kind: .fee,
                amount: fee.magnitude,
                accountID: transfer.accountID,
                note: Phrase(ru: "Комиссия за перевод", uz: "O‘tkazma komissiyasi", en: "Transfer fee")(.ru),
                date: transfer.date,
                source: transfer.source,
                linkedTransactionID: transfer.id
            )
            try insertValidated(feeTransaction, isNew: true)
            return (transfer, feeTransaction)
        }
    }

    /// Изменяет операцию, сохраняя состояние «до» и «после» в истории.
    public func update(_ transaction: FinanceTransaction) throws {
        try connection.transaction {
            guard let before = try self.transaction(id: transaction.id) else { throw StorageError.notFound }
            var updated = transaction
            updated.createdAt = before.createdAt
            updated.updatedAt = Date()
            try Ledger.validate(updated, accounts: try accountMap(), categories: try categoryMap(), isNew: false)
            var values = transactionValues(updated)
            let id = values.removeFirst()
            values.append(id)
            try connection.run(
                """
                UPDATE transactions SET kind = ?, amount_minor = ?, currency = ?, account_id = ?, counter_account_id = ?,
                counter_amount_minor = ?, counter_currency = ?, category_id = ?, merchant = ?, note = ?, tags = ?, occurred_at = ?,
                created_at = ?, updated_at = ?, source = ?, import_fingerprint = ?, receipt_file = ?, linked_transaction_id = ?,
                recurring_rule_id = ?, is_opening = ? WHERE id = ?
                """,
                values
            )
            try audit(.updated, before: before, after: updated)
        }
    }

    /// Удаляет операцию. По умолчанию вместе со связанными комиссиями.
    public func deleteTransaction(id: UUID, deleteLinkedFees: Bool = true) throws {
        try connection.transaction {
            guard let before = try transaction(id: id) else { throw StorageError.notFound }
            if deleteLinkedFees {
                let fees = try connection.query(
                    "SELECT \(Self.transactionColumns) FROM transactions WHERE linked_transaction_id = ? AND kind = 'fee'",
                    [.uuid(id)]
                ) { Self.transaction(from: $0) }
                for fee in fees {
                    try connection.run("DELETE FROM transactions WHERE id = ?", [.uuid(fee.id)])
                    try audit(.deleted, before: fee, after: nil)
                }
            }
            try connection.run("DELETE FROM transactions WHERE id = ?", [.uuid(id)])
            try audit(.deleted, before: before, after: nil)
        }
    }

    /// Устанавливает фактический баланс счёта: создаёт корректировку на разницу. `nil`, если разницы нет.
    @discardableResult
    public func setBalance(accountID: UUID, to target: Money, date: Date = Date()) throws -> FinanceTransaction? {
        try connection.transaction {
            guard let account = try account(id: accountID) else { throw StorageError.notFound }
            guard target.currency == account.currency else {
                throw LedgerError.currencyMismatch(expected: account.currency, actual: target.currency)
            }
            let current = try balances()[accountID] ?? .zero(account.currency)
            let delta = target - current
            guard !delta.isZero else { return nil }
            let adjustment = FinanceTransaction(
                kind: .adjustment,
                amount: delta,
                accountID: accountID,
                note: Phrase(ru: "Корректировка баланса", uz: "Balans tuzatildi", en: "Balance adjustment")(.ru),
                date: date,
                source: .manual
            )
            try insertValidated(adjustment, isNew: false)
            return adjustment
        }
    }

    /// Балансы всех счетов, посчитанные агрегатным SQL-запросом.
    public func balances() throws -> [UUID: Money] {
        let accounts = try self.accounts()
        var result: [UUID: Money] = [:]
        for account in accounts { result[account.id] = .zero(account.currency) }
        struct Row { let account: UUID; let currency: Currency; let sum: Int64 }
        let rows = try connection.query(
            """
            SELECT account_id, currency,
                   SUM(CASE WHEN kind IN ('expense', 'fee', 'transfer') THEN -amount_minor ELSE amount_minor END)
            FROM transactions GROUP BY account_id, currency
            UNION ALL
            SELECT counter_account_id, counter_currency, SUM(counter_amount_minor)
            FROM transactions WHERE kind = 'transfer' GROUP BY counter_account_id, counter_currency
            """
        ) { row -> Row? in
            guard let id = row.uuid(0) else { return nil }
            return Row(account: id, currency: Currency(row.text(1)), sum: row.int64(2))
        }
        for row in rows {
            guard let current = result[row.account], current.currency == row.currency else { continue }
            result[row.account] = current + Money(minorUnits: row.sum, currency: row.currency)
        }
        return result
    }

    // MARK: - История изменений

    private func audit(_ change: AuditEntry.Change, before: FinanceTransaction?, after: FinanceTransaction?) throws {
        let encoder = Self.makeEncoder()
        let beforeJSON = try before.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        let afterJSON = try after.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        guard let id = (after ?? before)?.id else { return }
        try connection.run(
            "INSERT INTO audit_log (entity, entity_id, change_type, changed_at, before_json, after_json) VALUES ('transaction', ?, ?, ?, ?, ?)",
            [.uuid(id), .text(change.rawValue), .date(Date()), .optionalText(beforeJSON), .optionalText(afterJSON)]
        )
    }

    public func auditTrail(transactionID: UUID) throws -> [AuditEntry] {
        let decoder = Self.makeDecoder()
        return try connection.query(
            "SELECT id, entity_id, change_type, changed_at, before_json, after_json FROM audit_log WHERE entity = 'transaction' AND entity_id = ? ORDER BY id",
            [.uuid(transactionID)]
        ) { row in
            guard let entityID = row.uuid(1), let change = AuditEntry.Change(rawValue: row.text(2)) else { return nil }
            let before = row.optionalText(4).flatMap { try? decoder.decode(FinanceTransaction.self, from: Data($0.utf8)) }
            let after = row.optionalText(5).flatMap { try? decoder.decode(FinanceTransaction.self, from: Data($0.utf8)) }
            return AuditEntry(id: row.int64(0), entityID: entityID, change: change, date: row.date(3), before: before, after: after)
        }
    }

    // MARK: - Импорт

    public func existingFingerprints() throws -> Set<String> {
        Set(try connection.query("SELECT import_fingerprint FROM transactions WHERE import_fingerprint IS NOT NULL") { $0.optionalText(0) })
    }

    /// Записывает импортированные операции одной транзакцией. Повторы по отпечатку пропускаются.
    public func importTransactions(_ transactions: [FinanceTransaction]) throws -> ImportWriteResult {
        try connection.transaction {
            var result = ImportWriteResult(inserted: 0, skippedDuplicates: 0)
            var seen = Set<String>()
            for transaction in transactions {
                if let fingerprint = transaction.importFingerprint {
                    let exists = (try connection.scalarInt("SELECT 1 FROM transactions WHERE import_fingerprint = ?", [.text(fingerprint)])) != nil
                    if exists || seen.contains(fingerprint) {
                        result.skippedDuplicates += 1
                        continue
                    }
                    seen.insert(fingerprint)
                }
                try insertValidated(transaction, isNew: true)
                result.inserted += 1
            }
            return result
        }
    }

    // MARK: - Правила категоризации

    public func merchantRules() throws -> [MerchantRule] {
        try connection.query("SELECT rule_key, category_id, hits, updated_at FROM merchant_rules ORDER BY rule_key") { row in
            guard let categoryID = row.uuid(1) else { return nil }
            return MerchantRule(key: row.text(0), categoryID: categoryID, hits: row.int(2), updatedAt: row.date(3))
        }
    }

    /// Запоминает выбор категории для продавца.
    public func learnMerchant(key: String, categoryID: UUID) throws {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try connection.run(
            """
            INSERT INTO merchant_rules (rule_key, category_id, hits, updated_at) VALUES (?, ?, 1, ?)
            ON CONFLICT(rule_key) DO UPDATE SET
                hits = CASE WHEN merchant_rules.category_id = excluded.category_id THEN merchant_rules.hits + 1 ELSE 1 END,
                category_id = excluded.category_id,
                updated_at = excluded.updated_at
            """,
            [.text(trimmed), .uuid(categoryID), .date(Date())]
        )
    }

    public func forgetMerchant(key: String) throws {
        try connection.run("DELETE FROM merchant_rules WHERE rule_key = ?", [.text(key)])
    }

    // MARK: - Настройки

    public func setting(_ key: String) throws -> String? {
        try connection.query("SELECT value FROM settings WHERE setting_key = ?", [.text(key)]) { $0.text(0) }.first
    }

    public func setSetting(_ key: String, _ value: String?) throws {
        if let value {
            try connection.run("INSERT INTO settings (setting_key, value) VALUES (?, ?) ON CONFLICT(setting_key) DO UPDATE SET value = excluded.value", [.text(key), .text(value)])
        } else {
            try connection.run("DELETE FROM settings WHERE setting_key = ?", [.text(key)])
        }
    }

    public func allSettings() throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try connection.query("SELECT setting_key, value FROM settings") { ($0.text(0), $0.text(1)) })
    }

    // MARK: - Курсы валют

    public func exchangeRates() throws -> [ExchangeRate] {
        try connection.query("SELECT currency, base_currency, rate, rate_date, source FROM exchange_rates ORDER BY currency") { row in
            guard let rate = DecimalMath.parse(row.text(2)) else { return nil }
            return ExchangeRate(
                currency: Currency(row.text(0)),
                baseCurrency: Currency(row.text(1)),
                rate: rate,
                date: row.date(3),
                source: RateSource(rawValue: row.text(4)) ?? .manual
            )
        }
    }

    /// Сохраняет курсы. Ручной курс не перезаписывается курсом ЦБ, если `keepManual == true`.
    public func saveExchangeRates(_ rates: [ExchangeRate], keepManual: Bool = true) throws {
        try connection.transaction {
            let manual = Set(try exchangeRates().filter { $0.source == .manual }.map(\.currency))
            for rate in rates {
                if keepManual && rate.source == .cbu && manual.contains(rate.currency) { continue }
                try connection.run(
                    """
                    INSERT INTO exchange_rates (currency, base_currency, rate, rate_date, source) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(currency) DO UPDATE SET base_currency = excluded.base_currency, rate = excluded.rate,
                    rate_date = excluded.rate_date, source = excluded.source
                    """,
                    [.text(rate.currency.code), .text(rate.baseCurrency.code), .text("\(rate.rate)"), .date(rate.date), .text(rate.source.rawValue)]
                )
            }
        }
    }

    public func deleteExchangeRate(_ currency: Currency) throws {
        try connection.run("DELETE FROM exchange_rates WHERE currency = ?", [.text(currency.code)])
    }

    // MARK: - Профили импорта

    public func importProfiles() throws -> [StoredImportProfile] {
        try connection.query("SELECT signature, name, payload, updated_at FROM import_profiles ORDER BY updated_at DESC") {
            StoredImportProfile(signature: $0.text(0), name: $0.text(1), payload: $0.text(2), updatedAt: $0.date(3))
        }
    }

    public func saveImportProfile(_ profile: StoredImportProfile) throws {
        try connection.run(
            """
            INSERT INTO import_profiles (signature, name, payload, updated_at) VALUES (?, ?, ?, ?)
            ON CONFLICT(signature) DO UPDATE SET name = excluded.name, payload = excluded.payload, updated_at = excluded.updated_at
            """,
            [.text(profile.signature), .text(profile.name), .text(profile.payload), .date(profile.updatedAt)]
        )
    }

    public func deleteImportProfile(signature: String) throws {
        try connection.run("DELETE FROM import_profiles WHERE signature = ?", [.text(signature)])
    }
}
