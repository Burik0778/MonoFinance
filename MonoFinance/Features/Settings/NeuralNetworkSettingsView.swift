import SwiftUI
import MonoCore
import MonoIntelligence

// MARK: - Нейросеть

/// Экран «Нейросеть»: включение, согласие, список сервисов, выбор активного, добавление своих.
struct NeuralNetworkSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var newProvider: LLMProvider?
    @State private var confirmReset = false

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ассистент работает и без нейросети")
                        .monoFont(.headline)
                        .foregroundStyle(Color.mono.textPrimary)
                    Text("Без сети и без вашего согласия ответы считаются на телефоне. С нейросетью ассистент отвечает свободнее и подсказывает, где сэкономить — по сводке, посчитанной на телефоне.")
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textSecondary)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                Toggle(isOn: $settings.llmEnabled) {
                    FormRow(icon: "sparkles", tint: Color.mono.accent, title: "Нейросеть",
                            subtitle: Text(statusText))
                }
                .tint(Color.mono.positive)
                if settings.llmEnabled {
                    Toggle(isOn: $settings.llmConsent) {
                        Text("Разрешаю отправлять выбранному сервису вопрос и сводку: итоги по месяцам и категориям, частых продавцов, подписки и бюджеты. Без списка операций, номеров карт, счетов, телефонов и имён.")
                            .monoFont(.footnote)
                            .foregroundStyle(Color.mono.textSecondary)
                    }
                    .tint(Color.mono.positive)
                    NavigationLink {
                        LLMPayloadPreviewView()
                    } label: {
                        FormRow(icon: "doc.text.magnifyingglass", tint: Color.mono.textSecondary, title: "Что будет отправлено",
                                subtitle: Text("Точный текст сводки"))
                    }
                }
            } header: {
                Kicker("Подключение")
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                ForEach(settings.llmProviders) { provider in
                    providerRow(provider)
                }
                Button {
                    newProvider = LLMProvider(name: "", baseURL: "https://", model: "")
                } label: {
                    Label("Добавить сервис", systemImage: "plus.circle.fill")
                        .monoFont(.body)
                }
            } header: {
                Kicker("Сервисы")
            } footer: {
                Text("Кружок слева — активный сервис. Если он не ответил (нет сети, лимит запросов, сбой сервера), ассистент попробует следующий включённый сервис с ключом. Ключи хранятся в Keychain только на этом iPhone.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                Button("Сбросить готовые сервисы", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Groq, Cerebras, OpenRouter и Gemini вернутся к исходным адресам и моделям. Свои сервисы и ключи сохранятся.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MonoBackdrop())
        .navigationTitle(Text("Нейросеть"))
        .sheet(item: $newProvider) { provider in
            NavigationStack {
                LLMProviderEditorView(provider: provider, isNew: true)
            }
        }
        .confirmationDialog("Сбросить готовые сервисы?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Сбросить", role: .destructive) { resetPresets() }
        }
    }

    private var statusText: String {
        guard settings.llmEnabled else { return String(localized: "Выключено — только ответы на телефоне") }
        guard settings.llmConsent else { return String(localized: "Нужно ваше согласие") }
        guard let active = settings.llmCandidates.first else { return String(localized: "Добавьте ключ хотя бы одному сервису") }
        return String(localized: "Отвечает \(active.name)")
    }

    private func providerRow(_ provider: LLMProvider) -> some View {
        let isActive = settings.llmActiveProvider?.id == provider.id
        return HStack(spacing: 12) {
            Button {
                Haptics.selection()
                settings.llmActiveProviderID = provider.id
            } label: {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isActive ? Color.mono.accent : Color.mono.textTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Сделать активным: \(provider.name)"))

            NavigationLink {
                LLMProviderEditorView(provider: provider, isNew: false)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: provider.name)
                        .monoFont(.body)
                        .foregroundStyle(provider.isEnabled ? Color.mono.textPrimary : Color.mono.textTertiary)
                    Text(verbatim: provider.model)
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.textTertiary)
                        .lineLimit(1)
                    Text(providerStatus(provider))
                        .monoFont(.caption)
                        .foregroundStyle(LLMKeychain.hasKey(provider) && provider.isEnabled ? Color.mono.positive : Color.mono.textSecondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func providerStatus(_ provider: LLMProvider) -> LocalizedStringKey {
        if !provider.isEnabled { return "Выключен" }
        if provider.chatURL == nil { return "Неверный адрес" }
        return LLMKeychain.hasKey(provider) ? "Ключ сохранён" : "Нет ключа"
    }

    private func resetPresets() {
        settings.llmProviders = settings.llmProviders.map { $0.preset ?? $0 }
        Haptics.success()
    }
}

// MARK: - Редактор сервиса

/// Название, адрес, модель, ключ (SecureField), «Проверить», удаление своих и сброс готовых.
struct LLMProviderEditorView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let isNew: Bool
    @State private var draft: LLMProvider
    @State private var key = ""
    @State private var hasStoredKey: Bool
    @State private var checking = false
    @State private var checkResult: CheckResult?
    @State private var confirmDelete = false
    @State private var availableModels: [String]?
    @State private var loadingModels = false
    @State private var modelsError: String?

    enum CheckResult: Equatable {
        case success(String)
        case failure(String)
    }

    init(provider: LLMProvider, isNew: Bool) {
        self.isNew = isNew
        _draft = State(initialValue: provider)
        _hasStoredKey = State(initialValue: LLMKeychain.hasKey(provider))
    }

    /// Ключ для проверки и сохранения: введённый сейчас или сохранённый ранее.
    private var effectiveKey: String? {
        let typed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? LLMKeychain.key(for: draft) : typed
    }

    var body: some View {
        List {
            Section {
                TextField("Название", text: $draft.name)
                    .monoFont(.body)
                TextField("https://…/v1", text: $draft.baseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .monoFont(.body)
                TextField("Модель", text: $draft.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .monoFont(.body)
                Button {
                    Task { await loadModels() }
                } label: {
                    HStack(spacing: 8) {
                        if loadingModels {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "list.bullet")
                        }
                        Text("Выбрать модель")
                    }
                }
                .disabled(loadingModels || draft.modelsURL == nil || effectiveKey == nil)
                if let modelsError {
                    Text(verbatim: modelsError)
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.negative)
                }
                Toggle("Включён", isOn: $draft.isEnabled)
                    .tint(Color.mono.positive)
                if let error = draft.validationError, !draft.baseURL.isEmpty {
                    Text(verbatim: error)
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.negative)
                }
            } header: {
                Kicker("Сервис")
            } footer: {
                Text("Запросы идут на адрес + /chat/completions (формат OpenAI). Только https.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                SecureField(hasStoredKey ? String(localized: "Ключ сохранён — введите новый, чтобы заменить") : String(localized: "Ключ API"), text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .monoFont(.body)
                if let link = keyPage {
                    Link(destination: link) {
                        Label("Где взять ключ", systemImage: "arrow.up.right.square")
                            .monoFont(.footnote)
                    }
                }
                if hasStoredKey {
                    Button("Удалить ключ", role: .destructive) {
                        LLMKeychain.set(nil, for: draft)
                        hasStoredKey = false
                        key = ""
                        touchProviders()
                    }
                }
            } header: {
                Kicker("Ключ")
            } footer: {
                Text("Ключ хранится в Keychain только на этом iPhone и отправляется только этому сервису.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                Button {
                    Task { await check() }
                } label: {
                    HStack(spacing: 8) {
                        if checking {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.seal")
                        }
                        Text("Проверить")
                    }
                }
                .disabled(checking || draft.chatURL == nil || effectiveKey == nil)
                if let checkResult {
                    switch checkResult {
                    case .success(let text):
                        Label { Text(verbatim: text) } icon: { Image(systemName: "checkmark.circle.fill") }
                            .monoFont(.footnote)
                            .foregroundStyle(Color.mono.positive)
                    case .failure(let text):
                        Label { Text(verbatim: text) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                            .monoFont(.footnote)
                            .foregroundStyle(Color.mono.negative)
                    }
                }
            } footer: {
                Text("Короткий тестовый запрос без ваших данных.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)

            if !isNew {
                Section {
                    if settings.llmActiveProvider?.id != draft.id {
                        Button("Сделать активным") {
                            save()
                            settings.llmActiveProviderID = draft.id
                            Haptics.success()
                        }
                    }
                    if let preset = draft.preset {
                        Button("Сбросить к исходным") {
                            draft.name = preset.name
                            draft.baseURL = preset.baseURL
                            draft.model = preset.model
                            checkResult = nil
                        }
                    } else {
                        Button("Удалить сервис", role: .destructive) { confirmDelete = true }
                    }
                }
                .listRowBackground(Color.mono.surface1)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MonoBackdrop())
        .navigationTitle(Text(isNew ? "Новый сервис" : "Сервис"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    save()
                    Haptics.success()
                    dismiss()
                }
                .disabled(draft.validationError != nil)
            }
        }
        .sheet(isPresented: Binding(get: { availableModels != nil }, set: { if !$0 { availableModels = nil } })) {
            NavigationStack {
                LLMModelPickerView(models: availableModels ?? [], current: draft.model) { model in
                    draft.model = model
                    checkResult = nil
                    availableModels = nil
                }
            }
        }
        .confirmationDialog("Удалить сервис «\(draft.name)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { delete() }
        }
    }

    /// Страницы, где получить ключ к готовым сервисам.
    private var keyPage: URL? {
        switch draft.id {
        case LLMProvider.groq.id: return URL(string: "https://console.groq.com/keys")
        case LLMProvider.cerebras.id: return URL(string: "https://cloud.cerebras.ai")
        case LLMProvider.openRouter.id: return URL(string: "https://openrouter.ai/keys")
        case LLMProvider.gemini.id: return URL(string: "https://aistudio.google.com/apikey")
        default: return nil
        }
    }

    /// Список моделей сервиса по ключу (введённому сейчас или сохранённому).
    private func loadModels() async {
        guard let key = effectiveKey else { return }
        loadingModels = true
        modelsError = nil
        do {
            availableModels = try await LLMClient().models(provider: draft, key: key)
        } catch let error as LLMError {
            modelsError = error.message
        } catch {
            modelsError = nil
        }
        loadingModels = false
    }

    private func check() async {
        guard let key = effectiveKey else { return }
        checking = true
        checkResult = nil
        do {
            _ = try await LLMClient().check(provider: draft, key: key)
            checkResult = .success(String(localized: "Сервис отвечает, модель \(draft.model) доступна"))
            Haptics.success()
        } catch let error as LLMError {
            checkResult = .failure(error.message)
            Haptics.error()
        } catch {
            checkResult = nil
        }
        checking = false
    }

    private func save() {
        guard draft.validationError == nil else { return }
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.baseURL = draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.model = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let typed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            LLMKeychain.set(typed, for: draft)
            hasStoredKey = true
            key = ""
        }
        if let index = settings.llmProviders.firstIndex(where: { $0.id == draft.id }) {
            settings.llmProviders[index] = draft
        } else {
            settings.llmProviders.append(draft)
        }
    }

    private func delete() {
        LLMKeychain.set(nil, for: draft)
        settings.llmProviders.removeAll { $0.id == draft.id }
        if settings.llmActiveProviderID == draft.id, let first = settings.llmProviders.first {
            settings.llmActiveProviderID = first.id
        }
        dismiss()
    }

    /// Ключи в Keychain не наблюдаются — переприсваиваем список, чтобы экраны обновили статусы.
    private func touchProviders() {
        let providers = settings.llmProviders
        settings.llmProviders = providers
    }
}

// MARK: - Выбор модели

/// Модели, которые сервис отдаёт по ключу. Бесплатные (OpenRouter, «:free») — первыми.
struct LLMModelPickerView: View {
    let models: [String]
    let current: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [String] {
        let free = models.filter { $0.hasSuffix(":free") }
        let rest = models.filter { !$0.hasSuffix(":free") }
        let ordered = free + rest
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.isEmpty ? ordered : ordered.filter { $0.lowercased().contains(trimmed) }
    }

    var body: some View {
        List(filtered, id: \.self) { model in
            Button {
                onPick(model)
                dismiss()
            } label: {
                HStack {
                    Text(verbatim: model)
                        .monoFont(.body)
                        .foregroundStyle(Color.mono.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if model == current {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.mono.accent)
                    }
                }
            }
            .listRowBackground(Color.mono.surface1)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MonoBackdrop())
        .searchable(text: $query, prompt: Text("Поиск модели"))
        .navigationTitle(Text("Модели сервиса"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
        }
    }
}

// MARK: - Что будет отправлено

/// Точный текст, который уходит в нейросеть вместе с вопросом, и явное согласие на отправку.
struct LLMPayloadPreviewView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @State private var payload = ""

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    previewLine("checkmark.shield", "Сводку считает телефон: итоги по месяцам, топ категорий и продавцов, средние, подписки, бюджеты, сравнение с прошлым месяцем.")
                    previewLine("xmark.shield", "Не отправляются: список операций, остатки и названия счетов, номера карт и счетов, RRN/TID, телефоны, e-mail, паспорт, имена из переводов, заметки и теги.")
                    previewLine("text.bubble", "К сводке добавляются ваш вопрос и предыдущие реплики чата — тоже после очистки.")
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                Text(verbatim: payload.isEmpty ? "…" : payload)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.mono.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } header: {
                Kicker("Текст запроса")
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                Toggle(isOn: $settings.llmConsent) {
                    Text("Согласен отправлять этот текст и мои вопросы выбранному сервису нейросети")
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textPrimary)
                }
                .tint(Color.mono.positive)
            } footer: {
                Text("Согласие можно отозвать в любой момент — ассистент вернётся к ответам на телефоне.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MonoBackdrop())
        .navigationTitle(Text("Что будет отправлено"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let summary = FinancialSummaryBuilder(analytics: store.analytics(), budgets: store.budgets, now: Date()).text()
            payload = LLMPrompt.systemMessage(summary: summary)
        }
    }

    private func previewLine(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.mono.textSecondary)
                .frame(width: 20)
            Text(text)
                .monoFont(.footnote)
                .foregroundStyle(Color.mono.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
