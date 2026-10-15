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

    /// Автоопределение колонок; если такие заголовки уже встречались — применяем сохранённый профиль.
    private func prepareMapping(store: FinanceStore) {
        guard let table else { return }
        let suggested = ColumnDetector.suggestMapping(for: table, calendar: store.periods.calendar)
        mapping = suggested
        appliedProfileName = nil
        let signature = ColumnDetector.signature(for: table, mapping: suggested)
        if let stored = store.importProfiles().first(where: { $0.signature == signature }),
           let profile = ImportProfile.decode(payload: stored.payload) {
            mapping = profile.mapping
            appliedProfileName = stored.name
            if accountID == nil, let saved = profile.accountID, store.accountMap[saved] != nil { accountID = saved }
        }
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

    func setHeaderRow(_ row: Int?) {
        mapping.headerRow = row
        preview = nil
    }

    // MARK: - Предпросмотр

    func buildPreview(store: FinanceStore) {
        error = nil
        guard let table else { return }
        guard let accountID, let account = store.accountMap[accountID] else {
            error = String(localized: "Выберите счёт, к которому относится выписка.")
            return
        }
        do {
            let fingerprints = (try? store.database.existingFingerprints()) ?? []
            let pipeline = ImportPipeline(account: account, existing: store.transactions, existingFingerprints: fingerprints,
                                          categorizer: store.categorizer(), calendar: store.periods.calendar)
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

    func setAll(included: Bool) {
        guard var preview else { return }
        for index in preview.candidates.indices where preview.candidates[index].duplicate == ImportCandidate.DuplicateStatus.none {
            preview.candidates[index].include = included
        }
        self.preview = preview
    }

    // MARK: - Запись

    func commit(store: FinanceStore) {
        guard let preview, let table, let accountID, let account = store.accountMap[accountID] else { return }
        error = nil
        let pipeline = ImportPipeline(account: account, existing: store.transactions, existingFingerprints: [],
                                      categorizer: store.categorizer(), calendar: store.periods.calendar)
        let transactions = pipeline.transactions(from: preview.candidates)
        guard !transactions.isEmpty else {
            error = String(localized: "Не выбрано ни одной операции.")
            return
        }
        do {
            result = try store.importTransactions(transactions)
            if rememberMapping {
                let signature = ColumnDetector.signature(for: table, mapping: mapping)
                let profile = ImportProfile(signature: signature, name: profileName(account: account), mapping: mapping, accountID: accountID)
                store.saveImportProfile(StoredImportProfile(signature: signature, name: profile.name, payload: profile.encodedPayload()))
            }
            // Исправленные категории — в обучение.
            let categorizer = store.categorizer()
            for candidate in preview.candidates where candidate.include {
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
        "\(account.bank.displayName) · \(fileName ?? "")"
    }
}
