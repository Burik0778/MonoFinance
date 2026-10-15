import XCTest
import MonoCore
@testable import MonoStorage

final class LedgerDatabaseTests: XCTestCase {
    var db: LedgerDatabase!
    var kapital: Account!
    var uzum: Account!
    var dollar: Account!
    let now = Date(timeIntervalSince1970: 1_791_000_000)

    func uzs(_ value: Int64) -> Money { Money(major: Decimal(value), currency: .uzs)! }
    func usd(_ value: Int64) -> Money { Money(major: Decimal(value), currency: .usd)! }
    func category(_ key: String) -> UUID { DefaultCategories.id(for: key) }

    override func setUpWithError() throws {
        db = try LedgerDatabase.inMemory()
        try db.seedDefaultCategories(language: .ru)
        kapital = Account(bank: .kapitalbank, name: "Kapital Humo", currency: .uzs, lastFour: "4417")
        uzum = Account(bank: .uzum, name: "Uzum", currency: .uzs)
        dollar = Account(bank: .orientFinans, name: "OFB Visa", kind: .card, paymentSystem: .visa, currency: .usd)
        try db.createAccount(kapital, openingBalance: uzs(5_000_000), openingDate: now)
        try db.createAccount(uzum, openingBalance: nil)
        try db.createAccount(dollar, openingBalance: usd(500), openingDate: now)
    }

    func testMigrationAndSeed() throws {
        XCTAssertEqual(db.schemaVersion, 1)
        XCTAssertEqual(try db.categories().count, DefaultCategories.make(language: .ru).count)
        XCTAssertEqual(try db.seedDefaultCategories(language: .ru), 0, "Повторный сид ничего не дублирует")
        XCTAssertEqual(try db.accounts().count, 3)
        XCTAssertEqual(try db.account(id: kapital.id)?.lastFour, "4417")
    }

    func testOpeningBalancesAndExpense() throws {
        try db.insert(FinanceTransaction(kind: .expense, amount: uzs(85_000), accountID: kapital.id,
                                         categoryID: category(SystemCategoryKey.cafe), merchant: "EVOS", date: now))
        let balances = try db.balances()
        XCTAssertEqual(balances[kapital.id], uzs(4_915_000))
        XCTAssertEqual(balances[uzum.id], uzs(0))
        XCTAssertEqual(balances[dollar.id], usd(500))
        XCTAssertTrue(try db.integrityIssues().isEmpty)
    }

    func testTransferWithFeeIsAtomicAndPreservesInvariants() throws {
        let transfer = FinanceTransaction(kind: .transfer, amount: uzs(1_000_000), accountID: kapital.id,
                                          counterAccountID: uzum.id, counterAmount: uzs(1_000_000), date: now)
        let result = try db.insertTransfer(transfer, fee: uzs(5_000))
        XCTAssertNotNil(result.fee)
        XCTAssertEqual(result.fee?.linkedTransactionID, transfer.id)

        let balances = try db.balances()
        XCTAssertEqual(balances[kapital.id], uzs(3_995_000))
        XCTAssertEqual(balances[uzum.id], uzs(1_000_000))
        // Общий баланс уменьшился ровно на комиссию — перевод сам по себе нейтрален.
        XCTAssertEqual(balances[kapital.id]! + balances[uzum.id]!, uzs(5_000_000 - 5_000))

        // Удаление перевода удаляет связанную комиссию и восстанавливает балансы.
        try db.deleteTransaction(id: transfer.id)
        let restored = try db.balances()
        XCTAssertEqual(restored[kapital.id], uzs(5_000_000))
        XCTAssertEqual(restored[uzum.id], uzs(0))
        XCTAssertEqual(try db.transactionCount(), 2, "Остались только два начальных остатка")
    }

    func testFailedFeeRollsBackTransfer() throws {
        let transfer = FinanceTransaction(kind: .transfer, amount: uzs(1_000_000), accountID: kapital.id,
                                          counterAccountID: uzum.id, counterAmount: uzs(1_000_000), date: now)
        // Комиссия в USD на сумовом счёте нарушает правила — вся операция должна откатиться.
        XCTAssertThrowsError(try db.insertTransfer(transfer, fee: usd(1)))
        XCTAssertNil(try db.transaction(id: transfer.id), "Перевод не должен остаться без комиссии")
        XCTAssertEqual(try db.balances()[kapital.id], uzs(5_000_000))
    }

    func testBatchInsertIsAllOrNothing() throws {
        let good = FinanceTransaction(kind: .expense, amount: uzs(120_000), accountID: kapital.id, categoryID: category(SystemCategoryKey.taxi), date: now)
        let bad = FinanceTransaction(kind: .expense, amount: uzs(75_000), accountID: UUID(), categoryID: category(SystemCategoryKey.cafe), date: now)
        XCTAssertThrowsError(try db.insert(batch: [good, bad]))
        XCTAssertNil(try db.transaction(id: good.id))
        try db.insert(batch: [good])
        XCTAssertNotNil(try db.transaction(id: good.id))
    }

    func testCrossCurrencyTransfer() throws {
        let transfer = FinanceTransaction(kind: .transfer, amount: usd(100), accountID: dollar.id,
                                          counterAccountID: kapital.id, counterAmount: uzs(1_191_335), date: now)
        try db.insertTransfer(transfer, fee: nil)
        let balances = try db.balances()
        XCTAssertEqual(balances[dollar.id], usd(400))
        XCTAssertEqual(balances[kapital.id], uzs(6_191_335))
        XCTAssertTrue(try db.integrityIssues().isEmpty)
    }

    func testRefundAndAdjustments() throws {
        let purchase = FinanceTransaction(kind: .expense, amount: uzs(450_000), accountID: kapital.id, categoryID: category(SystemCategoryKey.clothes), date: now)
        try db.insert(purchase)
        let refund = FinanceTransaction(kind: .refund, amount: uzs(450_000), accountID: kapital.id, categoryID: category(SystemCategoryKey.clothes),
                                        date: now, linkedTransactionID: purchase.id)
        try db.insert(refund)
        XCTAssertEqual(try db.balances()[kapital.id], uzs(5_000_000))

        let adjustment = try db.setBalance(accountID: kapital.id, to: uzs(4_990_500), date: now)
        XCTAssertEqual(adjustment?.amount, uzs(-9_500))
        XCTAssertEqual(try db.balances()[kapital.id], uzs(4_990_500))
        XCTAssertNil(try db.setBalance(accountID: kapital.id, to: uzs(4_990_500)), "Без разницы — без корректировки")

        // Удаление покупки не удаляет возврат, а только разрывает связь.
        try db.deleteTransaction(id: purchase.id)
        XCTAssertNil(try db.transaction(id: refund.id)?.linkedTransactionID)
    }

    func testUpdateWritesAuditTrail() throws {
        var expense = FinanceTransaction(kind: .expense, amount: uzs(85_000), accountID: kapital.id, categoryID: category(SystemCategoryKey.cafe), date: now)
        try db.insert(expense)
        expense.amount = uzs(95_000)
        expense.categoryID = category(SystemCategoryKey.delivery)
        try db.update(expense)
        try db.deleteTransaction(id: expense.id)

        let trail = try db.auditTrail(transactionID: expense.id)
        XCTAssertEqual(trail.map(\.change), [.created, .updated, .deleted])
        XCTAssertEqual(trail[1].before?.amount, uzs(85_000))
        XCTAssertEqual(trail[1].after?.amount, uzs(95_000))
        XCTAssertEqual(trail[2].before?.categoryID, category(SystemCategoryKey.delivery))
    }

    func testValidationIsEnforcedOnUpdate() throws {
        var expense = FinanceTransaction(kind: .expense, amount: uzs(85_000), accountID: kapital.id, date: now)
        try db.insert(expense)
        expense.amount = usd(5)
        XCTAssertThrowsError(try db.update(expense)) { error in
            XCTAssertEqual(error as? LedgerError, .currencyMismatch(expected: .uzs, actual: .usd))
        }
        XCTAssertEqual(try db.transaction(id: expense.id)?.amount, uzs(85_000))
    }

    func testDatabaseConstraintsAreASecondLineOfDefense() throws {
        // Обходим Swift-валидацию и пишем напрямую: CHECK в схеме не должен пропустить нулевую сумму.
        XCTAssertThrowsError(try db.connection.run(
            "INSERT INTO transactions (id, kind, amount_minor, currency, account_id, occurred_at, created_at, updated_at, source) VALUES (?, 'expense', 0, 'UZS', ?, 0, 0, 0, 'manual')",
            [.text(UUID().uuidString), .text(kapital.id.uuidString)]
        ))
        XCTAssertThrowsError(try db.connection.run(
            "INSERT INTO transactions (id, kind, amount_minor, currency, account_id, occurred_at, created_at, updated_at, source) VALUES (?, 'transfer', 100, 'UZS', ?, 0, 0, 0, 'manual')",
            [.text(UUID().uuidString), .text(kapital.id.uuidString)]
        ), "Перевод без счёта-получателя запрещён схемой")
    }

    func testImportDeduplication() throws {
        let rows = (0..<3).map { index in
            FinanceTransaction(kind: .expense, amount: uzs(Int64(10_000 * (index + 1))), accountID: kapital.id, date: now,
                               source: .importFile, importFingerprint: "kapital|2026-10-01|\(index)")
        }
        let first = try db.importTransactions(rows)
        XCTAssertEqual(first, ImportWriteResult(inserted: 3, skippedDuplicates: 0))
        let second = try db.importTransactions(rows.map { var copy = $0; copy.id = UUID(); return copy })
        XCTAssertEqual(second, ImportWriteResult(inserted: 0, skippedDuplicates: 3), "Повторный импорт той же выписки ничего не добавляет")
        XCTAssertEqual(try db.existingFingerprints().count, 3)
    }

    func testAccountCurrencyLockAndDeletion() throws {
        var changed = kapital!
        changed.currency = .usd
        XCTAssertThrowsError(try db.updateAccount(changed)) { XCTAssertEqual($0 as? StorageError, .currencyLocked) }

        var renamed = kapital!
        renamed.name = "Основная"
        try db.updateAccount(renamed)
        XCTAssertEqual(try db.account(id: kapital.id)?.name, "Основная")

        try db.insertTransfer(FinanceTransaction(kind: .transfer, amount: uzs(100_000), accountID: kapital.id, counterAccountID: uzum.id,
                                                 counterAmount: uzs(100_000), date: now), fee: nil)
        try db.deleteAccount(uzum.id)
        XCTAssertNil(try db.account(id: uzum.id))
        XCTAssertEqual(try db.balances()[kapital.id], uzs(5_000_000), "Перевод на удалённый счёт удалён вместе с ним")
        XCTAssertTrue(try db.integrityIssues().isEmpty)

        try db.setAccountArchived(dollar.id, archived: true)
        XCTAssertThrowsError(try db.insert(FinanceTransaction(kind: .expense, amount: usd(1), accountID: dollar.id, date: now)))
        XCTAssertEqual(try db.accounts(includeArchived: false).count, 1)
    }

    func testCategoryDeletionRules() throws {
        let custom = FinanceCategory(name: "Хобби", kind: .expense, icon: "paintpalette.fill", color: .violet)
        try db.saveCategory(custom)
        try db.insert(FinanceTransaction(kind: .expense, amount: uzs(1_000), accountID: kapital.id, categoryID: custom.id, date: now))
        XCTAssertThrowsError(try db.deleteCategory(custom.id)) { XCTAssertEqual($0 as? StorageError, .categoryInUse(count: 1)) }
        XCTAssertThrowsError(try db.reassignTransactions(fromCategory: custom.id, to: category(SystemCategoryKey.salary)))
        try db.reassignTransactions(fromCategory: custom.id, to: category(SystemCategoryKey.otherExpense))
        try db.deleteCategory(custom.id)
        XCTAssertFalse(try db.categories().contains { $0.id == custom.id })
    }

    func testMerchantLearning() throws {
        try db.learnMerchant(key: "korzinka", categoryID: category(SystemCategoryKey.groceries))
        try db.learnMerchant(key: "korzinka", categoryID: category(SystemCategoryKey.groceries))
        XCTAssertEqual(try db.merchantRules().first?.hits, 2)
        try db.learnMerchant(key: "korzinka", categoryID: category(SystemCategoryKey.home))
        let rule = try db.merchantRules().first
        XCTAssertEqual(rule?.categoryID, category(SystemCategoryKey.home))
        XCTAssertEqual(rule?.hits, 1, "Смена категории сбрасывает счётчик")
    }

    func testBudgetsGoalsPlannedRecurring() throws {
        let budget = Budget(categoryID: category(SystemCategoryKey.groceries), limit: uzs(2_000_000), rolloverEnabled: true, startMonth: MonthKey(year: 2026, month: 9))
        try db.saveBudget(budget)
        XCTAssertThrowsError(try db.saveBudget(Budget(categoryID: category(SystemCategoryKey.groceries), limit: uzs(1), startMonth: MonthKey(year: 2026, month: 10))),
                             "Второй активный бюджет на ту же категорию запрещён")
        try db.saveBudget(Budget(categoryID: nil, limit: uzs(10_000_000), startMonth: MonthKey(year: 2026, month: 10)))
        XCTAssertEqual(try db.budgets().count, 2)

        let goal = Goal(name: "Ноутбук", target: uzs(15_000_000))
        try db.saveGoal(goal)
        try db.addContribution(GoalContribution(goalID: goal.id, amount: uzs(2_500_000), date: now))
        XCTAssertThrowsError(try db.addContribution(GoalContribution(goalID: goal.id, amount: usd(10), date: now)))
        XCTAssertEqual(try db.goalContributions(goalID: goal.id).count, 1)

        try db.savePlannedExpense(PlannedExpense(title: "Страховка авто", amount: uzs(1_800_000), date: now.addingTimeInterval(86_400 * 20)))
        XCTAssertEqual(try db.plannedExpenses().count, 1)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        let rule = RecurringRule(title: "Интернет", amount: uzs(150_000), accountID: kapital.id,
                                 categoryID: category(SystemCategoryKey.mobile), anchorDate: now)
        try db.saveRecurringRule(rule)
        let created = try db.confirmRecurring(ruleID: rule.id, calendar: calendar)
        XCTAssertEqual(created.source, .recurring)
        XCTAssertEqual(created.recurringRuleID, rule.id)
        let advanced = try db.recurringRules().first!
        XCTAssertGreaterThan(advanced.nextDueDate, now)
        XCTAssertEqual(calendar.component(.day, from: advanced.nextDueDate), calendar.component(.day, from: now))
        try db.skipRecurring(ruleID: rule.id, calendar: calendar)
        XCTAssertGreaterThan(try db.recurringRules().first!.nextDueDate, advanced.nextDueDate)
        XCTAssertEqual(try db.balances()[kapital.id], uzs(4_850_000))

        XCTAssertThrowsError(try db.saveRecurringRule(RecurringRule(title: "x", amount: usd(1), accountID: kapital.id, anchorDate: now)))
    }

    func testRatesAndSettings() throws {
        try db.saveExchangeRates([ExchangeRate(currency: .usd, baseCurrency: .uzs, rate: Decimal(string: "12000")!, date: now, source: .manual)])
        try db.saveExchangeRates([ExchangeRate(currency: .usd, baseCurrency: .uzs, rate: Decimal(string: "11913.35")!, date: now, source: .cbu),
                                  ExchangeRate(currency: .eur, baseCurrency: .uzs, rate: Decimal(string: "13328.66")!, date: now, source: .cbu)])
        let rates = try db.exchangeRates()
        XCTAssertEqual(rates.first { $0.currency == .usd }?.rate, Decimal(12000), "Ручной курс не перезаписывается курсом ЦБ")
        XCTAssertEqual(rates.first { $0.currency == .eur }?.rate, Decimal(string: "13328.66"))

        try db.setSetting("baseCurrency", "UZS")
        XCTAssertEqual(try db.setting("baseCurrency"), "UZS")
        try db.setSetting("baseCurrency", nil)
        XCTAssertNil(try db.setting("baseCurrency"))
    }

    func testSnapshotRoundTrip() throws {
        try db.insertTransfer(FinanceTransaction(kind: .transfer, amount: uzs(250_000), accountID: kapital.id, counterAccountID: uzum.id,
                                                 counterAmount: uzs(250_000), date: now), fee: uzs(1_250))
        try db.insert(FinanceTransaction(kind: .expense, amount: uzs(245_000), accountID: kapital.id, categoryID: category(SystemCategoryKey.groceries),
                                         merchant: "Korzinka", tags: ["дом", "еженедельно"], date: now))
        try db.learnMerchant(key: "korzinka", categoryID: category(SystemCategoryKey.groceries))
        try db.setSetting("defaultAccountID", kapital.id.uuidString)
        try db.saveImportProfile(StoredImportProfile(signature: "date|amount|description", name: "Kapitalbank CSV", payload: "{}"))

        let snapshot = try db.exportSnapshot(now: now)
        let data = try snapshot.encoded()
        let decoded = try LedgerSnapshot.decode(data)
        XCTAssertEqual(decoded, snapshot)

        let restoredDB = try LedgerDatabase.inMemory()
        try restoredDB.restore(from: decoded)
        XCTAssertEqual(try restoredDB.balances(), try db.balances())
        XCTAssertEqual(try restoredDB.transactions(), try db.transactions())
        XCTAssertEqual(try restoredDB.setting("defaultAccountID"), kapital.id.uuidString)
        XCTAssertEqual(try restoredDB.importProfiles().count, 1)
        XCTAssertTrue(try restoredDB.integrityIssues().isEmpty)

        var corrupted = snapshot
        let index = corrupted.transactions.firstIndex { $0.accountID == kapital.id }!
        corrupted.transactions[index].amount = usd(1)
        XCTAssertThrowsError(try restoredDB.restore(from: corrupted))
        XCTAssertEqual(try restoredDB.transactions().count, snapshot.transactions.count, "Неудачное восстановление ничего не меняет")
        XCTAssertThrowsError(try LedgerSnapshot.decode(Data("garbage".utf8)))
    }

    func testFileDatabasePersistsAcrossReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mono-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("ledger.sqlite").path
        let account = Account(bank: .trastbank, name: "Trast", currency: .uzs)
        do {
            let fileDB = try LedgerDatabase(path: path)
            try fileDB.seedDefaultCategories(language: .ru)
            try fileDB.createAccount(account, openingBalance: uzs(777_000), openingDate: now)
        }
        let reopened = try LedgerDatabase(path: path)
        XCTAssertEqual(try reopened.balances()[account.id], uzs(777_000), "Данные переживают закрытие и повторное открытие")
        XCTAssertEqual(reopened.schemaVersion, 1)
    }
}
