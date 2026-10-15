import SwiftUI
import UniformTypeIdentifiers
import MonoCore
import MonoStorage

/// Резервные копии (AES-256-GCM, ключ из пароля), восстановление, экспорт CSV, проверка целостности.
struct BackupView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.appLanguage) private var language

    @State private var password = ""
    @State private var confirmation = ""
    @State private var creating = false
    @State private var backupURL: URL?
    @State private var csvURL: URL?
    @State private var showsImporter = false
    @State private var restoreData: Data?
    @State private var restorePassword = ""
    @State private var pendingSnapshot: LedgerSnapshot?
    @State private var restoring = false
    @State private var integrity: [String]?
    @State private var error: String?

    private var passwordProblem: String? {
        if password.isEmpty { return nil }
        if password.count < 8 { return String(localized: "Не короче 8 символов.") }
        if !confirmation.isEmpty && confirmation != password { return String(localized: "Пароли не совпадают.") }
        return nil
    }

    var body: some View {
        List {
            if store.isDemo {
                Section {
                    Label("Сейчас открыт демо-режим: копия будет содержать демонстрационные данные.", systemImage: "theatermasks.fill")
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.magenta)
                }
                .listRowBackground(Color.mono.surface1)
            }

            Section {
                SecureField("Пароль копии", text: $password)
                    .textContentType(.newPassword)
                    .monoFont(.body)
                SecureField("Повторите пароль", text: $confirmation)
                    .textContentType(.newPassword)
                    .monoFont(.body)
                if let problem = passwordProblem {
                    Text(verbatim: problem)
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.coral)
                }
                Button {
                    Task { await createBackup() }
                } label: {
                    HStack {
                        if creating { ProgressView().controlSize(.small) }
                        Text(creating ? "Шифрование…" : "Создать зашифрованную копию")
                    }
                }
                .disabled(creating || password.count < 8 || password != confirmation)
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label("Сохранить или отправить копию", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Kicker("Резервная копия")
            } footer: {
                Text("Копия шифруется AES-256-GCM ключом из вашего пароля (PBKDF2, 310 000 итераций). Без пароля восстановить её невозможно — запишите его.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                Button("Выбрать файл копии") { showsImporter = true }
                if restoreData != nil {
                    SecureField("Пароль копии", text: $restorePassword)
                        .monoFont(.body)
                    Button {
                        Task { await decryptBackup() }
                    } label: {
                        HStack {
                            if restoring { ProgressView().controlSize(.small) }
                            Text("Расшифровать")
                        }
                    }
                    .disabled(restorePassword.isEmpty || restoring)
                }
            } header: {
                Kicker("Восстановление")
            } footer: {
                Text("Восстановление заменяет все текущие данные содержимым копии. Перед заменой копия проверяется.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                Button("Экспорт операций в CSV") { exportCSV() }
                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("Отправить CSV", systemImage: "tablecells")
                    }
                }
            } header: {
                Kicker("Экспорт")
            } footer: {
                Text("UTF-8, разделитель «;» — открывается в Excel и Numbers. Файл не шифруется.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                Button("Проверить целостность данных") {
                    integrity = store.integrityIssues()
                }
                if let integrity {
                    if integrity.isEmpty {
                        Label("Ошибок не найдено", systemImage: "checkmark.seal.fill")
                            .monoFont(.footnote)
                            .foregroundStyle(Color.mono.emerald)
                    } else {
                        ForEach(integrity, id: \.self) { issue in
                            Label { Text(verbatim: issue) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                                .monoFont(.footnote)
                                .foregroundStyle(Color.mono.tangerine)
                        }
                    }
                }
            } header: {
                Kicker("Проверка")
            }
            .listRowBackground(Color.mono.surface1)

            if let error {
                Section {
                    Text(verbatim: error)
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.coral)
                }
                .listRowBackground(Color.mono.surface1)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.mono.background.ignoresSafeArea())
        .navigationTitle(Text("Резервные копии"))
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [UTType(filenameExtension: BackupService.fileExtension) ?? .data, .data]) { result in
            guard case .success(let url) = result else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                restoreData = try Data(contentsOf: url)
                restorePassword = ""
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
        .confirmationDialog("Заменить все данные копией?", isPresented: Binding(get: { pendingSnapshot != nil }, set: { if !$0 { pendingSnapshot = nil } }),
                            titleVisibility: .visible) {
            Button("Заменить", role: .destructive) { applyRestore() }
        } message: {
            if let snapshot = pendingSnapshot {
                Text("В копии: счетов — \(snapshot.accounts.count), операций — \(snapshot.transactions.count). Текущие данные будут заменены.")
            }
        }
    }

    private func createBackup() async {
        creating = true
        error = nil
        defer { creating = false }
        do {
            let snapshot = try store.snapshot()
            let secret = password
            let data = try await Task.detached(priority: .userInitiated) {
                try BackupService.encrypt(snapshot, password: secret)
            }.value
            backupURL = try ExportService.temporaryFile(named: BackupService.fileName(), data: data)
            password = ""
            confirmation = ""
            Haptics.success()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? AppError(error).message
        }
    }

    private func decryptBackup() async {
        guard let data = restoreData else { return }
        restoring = true
        error = nil
        defer { restoring = false }
        let secret = restorePassword
        do {
            pendingSnapshot = try await Task.detached(priority: .userInitiated) {
                try BackupService.decrypt(data, password: secret)
            }.value
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? AppError(error).message
            Haptics.error()
        }
    }

    private func applyRestore() {
        guard let snapshot = pendingSnapshot else { return }
        do {
            try store.restore(snapshot: snapshot)
            restoreData = nil
            restorePassword = ""
            Haptics.success()
            toasts.show(ToastMessage(text: String(localized: "Данные восстановлены из копии"), symbol: "externaldrive.fill.badge.checkmark"))
        } catch {
            self.error = AppError(error).message
        }
        pendingSnapshot = nil
    }

    private func exportCSV() {
        let data = ExportService.csv(transactions: store.transactions, accounts: store.accountMap, categories: store.categoryMap,
                                     calendar: store.periods.calendar)
        do {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            csvURL = try ExportService.temporaryFile(named: "MONO-\(formatter.string(from: Date())).csv", data: data)
            Haptics.success()
        } catch {
            self.error = AppError(error).message
        }
    }
}
