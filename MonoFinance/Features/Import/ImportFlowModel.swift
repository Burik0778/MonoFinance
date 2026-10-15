import Foundation
import Observation
import MonoCore
import MonoStorage
import MonoImport

/// Состояние импорта выписки: файл → лист → сопоставление колонок → предпросмотр → запись.
/// Ничего не пишется в базу до явного подтверждения на шаге предпросмотра.
@MainActor
@Observable
final class ImportFlowModel {
    enum Step: Int, Comparable {
        case source
        case mapping
        case preview
        case done

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var step: Step = .source
    var accountID: UUID?
    private(set) var fileName: String?
    private(set) var document: ImportDocument?
    var tableIndex = 0
    var mapping = ColumnMapping(headerRow: nil, roles: [:])
    private(set) var appliedProfileName: String?
    /// Распознанный формат выписки («Payme»).
    private(set) var formatName: String?
    /// Карты в выписке сразу по нескольким картам и выбранные для них счета (нет записи — карта не импортируется).
    private(set) var cards: [StatementCard] = []
    var cardAccounts: [String: UUID] = [:]
    /// В выписке есть переводы со своим вкладом («Перевод с DEPOSIT на VISA»).
    private(set) var hasDepositRows = false
    /// Счёт вклада для таких строк; `nil` — останутся доходами и расходами.
    var depositAccountID: UUID?
    /// Банк распознанного формата.
    private(set) var formatBank: Bank?
    var preview: ImportPreview?
    var rememberMapping = true
    private(set) var isWorking = false
    var error: String?
    private(set) var result: ImportWriteResult?

    var table: ImportTable? {
        guard let document, document.tables.indices.contains(tableIndex) else { return nil }
        return document.tables[tableIndex]
    }

    // MARK: - Файл

    func load(url: URL, store: FinanceStore) async {
        error = nil
        isWorking = true
        defer { isWorking = false }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent
            // Разбор XLSX может занять заметное время — уводим с главного потока.
            let document = try await Task.detached(priority: .userInitiated) {
                try ImportReader.read(data: data, fileName: name)
            }.value
            self.fileName = name
            self.document = document
            self.tableIndex = Self.bestTableIndex(in: document)
            prepareMapping(store: store)
            step = .mapping
        } catch {
            self.error = AppError(error).message
        }
    }

    /// Лист с наибольшим числом непустых строк.
    private static func bestTableIndex(in document: ImportDocument) -> Int {
        let counts = document.tables.map { table in table.rows.filter { !$0.allSatisfy(\.isEmpty) }.count }
        return counts.indices.max { counts[$0] < counts[$1] } ?? 0
    }

    func selectTable(_ index: Int, store: FinanceStore) {
        guard let document, document.tables.indices.contains(index) else { return }
        tableIndex = index
        prepareMapping(store: store)
    }

    /// Автоопределение колонок (известный формат — по адаптеру); если такие заголовки уже встречались — применяем сохранённый профиль.
    private func prepareMapping(store: FinanceStore) {
        guard let table else { return }
        let adapter = StatementAdapterRegistry.adapter(for: table)
        let suggested = adapter.mapping(for: table, calendar: store.periods.calendar)
        mapping = suggested
        formatName = adapter.displayName
        formatBank = adapter.bank
        appliedProfileName = nil
        cardAccounts = [:]
        var savedCards: [String: UUID] = [:]
        let signature = ColumnDetector.signature(for: table, mapping: suggested)
        if let stored = store.importProfiles().first(where: { $0.signature == signature }),
           let profile = ImportProfile.decode(payload: stored.payload) {
            mapping = profile.mapping
            appliedProfileName = stored.name
            if accountID == nil, let saved = profile.accountID, store.accountMap[saved] != nil { accountID = saved }
            savedCards = profile.cardAccounts ?? [:]
        }
        refreshCards(store: store, saved: savedCards)
        refreshDeposit(store: store)
    }

    /// Есть ли строки со вкладом и какой счёт вклада предложить: единственный вклад или накопительный счёт (того же банка, если их несколько).
    private func refreshDeposit(store: FinanceStore) {
        guard let table else { return }
        hasDepositRows = table.rows.dropFirst(mapping.firstDataRow).contains { row in
            ImportPipeline.isDepositTransfer(row.map(\.text).joined(separator: " "))
        }
        guard hasDepositRows else { depositAccountID = nil; return }
        if let id = depositAccountID, store.accountMap[id]?.isArchived == false { return }
        let deposits = store.activeAccounts.filter { $0.kind == .deposit || $0.kind == .savings }
        let bank = formatBank ?? cardAccounts.values.compactMap { store.accountMap[$0]?.bank }.first ?? accountID.flatMap { store.accountMap[$0]?.bank }
        let sameBank = deposits.filter { $0.bank == bank }
        if sameBank.count == 1 {
            depositAccountID = sameBank[0].id
        } else if deposits.count == 1 {
            depositAccountID = deposits[0].id
        }
    }

    /// «Создать счёт «Вклад»» — пустой вклад в банке выписки; остаток можно указать позже.
    func createDepositAccount(store: FinanceStore) {
        let statementAccount = cardAccounts.values.compactMap { store.accountMap[$0] }.first ?? accountID.flatMap { store.accountMap[$0] }
        let bank = formatBank ?? statementAccount?.bank ?? .other
        let account = Account(bank: bank, name: String(localized: "Вклад"), kind: .deposit, currency: statementAccount?.currency ?? .uzs)
        do {
            try store.createAccount(account, openingBalance: nil)
            depositAccountID = account.id
            preview = nil
        } catch {
            self.error = AppError(error).message
        }
    }

    /// Карты из колонки «Номер карты» и счета для них: сохранённые → по последним цифрам или банку → единственная карта на выбранный счёт.
    private func refreshCards(store: FinanceStore, saved: [String: UUID] = [:]) {
        guard let table else { return }
        cards = StatementCard.cards(in: table, mapping: mapping)
        var assignments: [String: UUID] = [:]
        for card in cards {
            if let id = cardAccounts[card.id] ?? saved[card.id], store.accountMap[id]?.isArchived == false {
                assignments[card.id] = id
            } else if let suggested = card.suggestedAccount(in: store.activeAccounts) {
                assignments[card.id] = suggested.id
            }
        }
        if cards.count == 1, assignments.isEmpty, let accountID { assignments[cards[0].id] = accountID }
        cardAccounts = assignments
    }

    func assign(_ accountID: UUID?, to card: StatementCard) {
        cardAccounts[card.id] = accountID
        preview = nil
    }

    /// Выписка по нескольким картам: строки распределяются по счетам.
    var isMultiCard: Bool { !cards.isEmpty }

    private func pipeline(store: FinanceStore, fingerprints: Set<String>) -> ImportPipeline? {
        let accounts = cardAccounts.compactMapValues { store.accountMap[$0] }
        let deposit = hasDepositRows ? depositAccountID.flatMap { store.accountMap[$0] } : nil
        if isMultiCard {
            guard let first = cards.compactMap({ accounts[$0.id] }).first else { return nil }
            return ImportPipeline(account: first, cardAccounts: accounts, existing: store.transactions, existingFingerprints: fingerprints,
                                  depositAccount: deposit, categorizer: store.categorizer(), calendar: store.periods.calendar)
        }
        guard let accountID, let account = store.accountMap[accountID] else { return nil }
        return ImportPipeline(account: account, existing: store.transactions, existingFingerprints: fingerprints,
                              depositAccount: deposit, categorizer: store.categorizer(), calendar: store.periods.calendar)
    }

    var canBuildPreview: Bool {
        mapping.isComplete && (isMultiCard ? !cardAccounts.isEmpty : accountID != nil)
    }

    // MARK: - Сопоставление

    func setRole(_ role: ColumnRole?, for column: Int) {
        var roles = mapping.roles
        if let role, role != .ignore {
            // Однозначные роли — не больше одной колонки (описаний может быть несколько).
            if role != .description {
                for (key, value) in roles where value == role { roles[key] = nil }
            }
            roles[column] = role
        } else {
            roles[column] = nil
        }
        mapping.roles = roles
        preview = nil
    }

    func setRole(_ role: ColumnRole?, for column: Int, store: FinanceStore) {
        setRole(role, for: column)
        refreshCards(store: store)
    }

    func setHeaderRow(_ row: Int?, store: FinanceStore) {
        mapping.headerRow = row
        preview = nil
        refreshCards(store: store)
    }

    // MARK: - Предпросмотр

    func buildPreview(store: FinanceStore) {
        error = nil
        guard let table else { return }
        let fingerprints = (try? store.database.existingFingerprints()) ?? []
        guard let pipeline = pipeline(store: store, fingerprints: fingerprints) else {
            error = isMultiCard ? String(localized: "Выберите счёт хотя бы для одной карты.") : String(localized: "Выберите счёт, к которому относится выписка.")
            return
        }
        do {
            preview = try pipeline.preview(table: table, mapping: mapping)
            step = .preview
        } catch {
            self.error = AppError(error).message
        }
    }

    func toggle(_ candidate: ImportCandidate) {
        guard var preview, let index = preview.candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
        guard preview.candidates[index].duplicate != .alreadyImported else { return }
        preview.candidates[index].include.toggle()
        self.preview = preview
    }

    func setCategory(_ categoryID: UUID?, for candidate: ImportCandidate) {
        guard var preview, let index = preview.candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
        preview.candidates[index].categoryID = categoryID
        self.preview = preview
    }

    /// «Это не перевод» — пара снова становится отдельными списанием и зачислением.
    func splitTransfer(_ candidate: ImportCandidate) {
        guard var preview else { return }
        preview.splitTransfer(candidate.id)
        self.preview = preview
    }

    func setAll(included: Bool) {
        guard var preview else { return }
        for index in preview.candidates.indices where preview.candidates[index].duplicate == ImportCandidate.DuplicateStatus.none {
            preview.candidates[index].include = included
        }
        self.preview = preview
    }

    // MARK: - Запись

    func commit(store: FinanceStore) {
        guard let preview, let table, let pipeline = pipeline(store: store, fingerprints: []) else { return }
        error = nil
        let account = pipeline.account
        let transactions = pipeline.transactions(from: preview.candidates)
        guard !transactions.isEmpty else {
            error = String(localized: "Не выбрано ни одной операции.")
            return
        }
        do {
            result = try store.importTransactions(transactions, replacing: preview.replacedTransactionIDs)
            if rememberMapping {
                let signature = ColumnDetector.signature(for: table, mapping: mapping)
                let profile = ImportProfile(signature: signature, name: profileName(account: account), mapping: mapping,
                                            accountID: isMultiCard ? nil : accountID, cardAccounts: isMultiCard ? cardAccounts : nil)
                store.saveImportProfile(StoredImportProfile(signature: signature, name: profile.name, payload: profile.encodedPayload()))
            }
            // Исправленные категории — в обучение.
            let categorizer = store.categorizer()
            for candidate in preview.candidates where candidate.include && candidate.isVisible && !candidate.isTransfer {
                if let merchant = candidate.merchant, let categoryID = candidate.categoryID {
                    let suggested = categorizer.suggest(merchant: merchant, text: candidate.description, kind: candidate.kind)?.categoryID
                    if suggested != categoryID { store.learnCategory(merchant: merchant, categoryID: categoryID) }
                }
            }
            step = .done
        } catch {
            self.error = AppError(error).message
        }
    }

    private func profileName(account: Account) -> String {
        "\(formatName ?? account.bank.displayName) · \(fileName ?? "")"
    }
}
