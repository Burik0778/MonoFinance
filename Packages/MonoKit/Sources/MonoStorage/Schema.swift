import Foundation

/// Миграции схемы. Номер версии хранится в `PRAGMA user_version`.
/// Каждая миграция выполняется в одной транзакции; новые миграции только добавляются в конец.
enum Schema {
    static let migrations: [String] = [
        // v1 — исходная схема
        """
        CREATE TABLE accounts (
            id TEXT PRIMARY KEY NOT NULL,
            bank TEXT NOT NULL,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            payment_system TEXT,
            currency TEXT NOT NULL CHECK (length(currency) = 3),
            last_four TEXT CHECK (last_four IS NULL OR length(last_four) = 4),
            skin TEXT NOT NULL,
            include_in_total INTEGER NOT NULL DEFAULT 1,
            is_archived INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE categories (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('expense', 'income')),
            icon TEXT NOT NULL,
            color TEXT NOT NULL,
            is_mandatory INTEGER NOT NULL DEFAULT 0,
            system_key TEXT UNIQUE,
            is_archived INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE transactions (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('expense', 'income', 'transfer', 'fee', 'refund', 'adjustment')),
            amount_minor INTEGER NOT NULL CHECK (amount_minor <> 0),
            currency TEXT NOT NULL,
            account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
            counter_account_id TEXT REFERENCES accounts(id) ON DELETE RESTRICT,
            counter_amount_minor INTEGER,
            counter_currency TEXT,
            category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
            merchant TEXT,
            note TEXT,
            tags TEXT NOT NULL DEFAULT '[]',
            occurred_at REAL NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            source TEXT NOT NULL,
            import_fingerprint TEXT UNIQUE,
            receipt_file TEXT,
            linked_transaction_id TEXT REFERENCES transactions(id) ON DELETE SET NULL,
            recurring_rule_id TEXT,
            is_opening INTEGER NOT NULL DEFAULT 0,
            CHECK ((kind = 'transfer') = (counter_account_id IS NOT NULL)),
            CHECK (kind = 'adjustment' OR amount_minor > 0),
            CHECK (counter_account_id IS NULL OR counter_account_id <> account_id),
            CHECK (kind <> 'transfer' OR (counter_amount_minor > 0 AND counter_currency IS NOT NULL))
        );
        CREATE INDEX idx_transactions_account ON transactions(account_id, occurred_at);
        CREATE INDEX idx_transactions_counter ON transactions(counter_account_id);
        CREATE INDEX idx_transactions_date ON transactions(occurred_at);
        CREATE INDEX idx_transactions_category ON transactions(category_id);
        CREATE INDEX idx_transactions_linked ON transactions(linked_transaction_id);

        CREATE TABLE audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            change_type TEXT NOT NULL,
            changed_at REAL NOT NULL,
            before_json TEXT,
            after_json TEXT
        );
        CREATE INDEX idx_audit_entity ON audit_log(entity, entity_id);

        CREATE TABLE merchant_rules (
            rule_key TEXT PRIMARY KEY NOT NULL,
            category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
            hits INTEGER NOT NULL DEFAULT 1,
            updated_at REAL NOT NULL
        );

        CREATE TABLE budgets (
            id TEXT PRIMARY KEY NOT NULL,
            category_id TEXT REFERENCES categories(id) ON DELETE CASCADE,
            limit_minor INTEGER NOT NULL CHECK (limit_minor > 0),
            currency TEXT NOT NULL,
            rollover INTEGER NOT NULL DEFAULT 0,
            start_month TEXT NOT NULL,
            is_archived INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );
        CREATE UNIQUE INDEX idx_budgets_active_category ON budgets(IFNULL(category_id, 'overall')) WHERE is_archived = 0;

        CREATE TABLE goals (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            target_minor INTEGER NOT NULL CHECK (target_minor > 0),
            currency TEXT NOT NULL,
            deadline REAL,
            icon TEXT NOT NULL,
            color TEXT NOT NULL,
            linked_account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
            is_archived INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );

        CREATE TABLE goal_contributions (
            id TEXT PRIMARY KEY NOT NULL,
            goal_id TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
            amount_minor INTEGER NOT NULL CHECK (amount_minor <> 0),
            currency TEXT NOT NULL,
            occurred_at REAL NOT NULL,
            note TEXT
        );

        CREATE TABLE planned_expenses (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
            currency TEXT NOT NULL,
            planned_at REAL NOT NULL,
            category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
            note TEXT,
            is_completed INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );

        CREATE TABLE recurring_rules (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('expense', 'income')),
            amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
            currency TEXT NOT NULL,
            account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
            merchant TEXT,
            frequency TEXT NOT NULL,
            repeat_interval INTEGER NOT NULL DEFAULT 1 CHECK (repeat_interval >= 1),
            anchor_at REAL NOT NULL,
            next_due_at REAL NOT NULL,
            reminder INTEGER NOT NULL DEFAULT 1,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL
        );

        CREATE TABLE exchange_rates (
            currency TEXT PRIMARY KEY NOT NULL,
            base_currency TEXT NOT NULL,
            rate TEXT NOT NULL,
            rate_date REAL NOT NULL,
            source TEXT NOT NULL
        );

        CREATE TABLE settings (
            setting_key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        );

        CREATE TABLE import_profiles (
            signature TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            payload TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        """
    ]

    static var currentVersion: Int { migrations.count }

    static func migrate(_ connection: SQLiteConnection) throws {
        let version = try connection.userVersion
        guard version <= currentVersion else {
            throw SQLiteError.migration("База создана более новой версией приложения (\(version) > \(currentVersion)).")
        }
        guard version < currentVersion else { return }
        for index in version..<currentVersion {
            try connection.transaction {
                try connection.execute(migrations[index])
                try connection.setUserVersion(index + 1)
            }
        }
    }
}
