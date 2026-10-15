import SwiftUI
import UIKit
import Speech
import AVFoundation
import MonoCore
import MonoBankSync
import MonoImport

// MARK: - Приватность и защита

struct SecuritySettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppLock.self) private var lock
    @State private var lockEnabled = false
    @State private var working = false

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                Toggle(isOn: Binding(get: { lockEnabled }, set: { value in Task { await setLock(value) } })) {
                    FormRow(icon: lockSymbol, tint: Color.mono.accent, title: "Блокировка приложения",
                            subtitle: Text(lock.canProtect ? "Face ID, Touch ID или код-пароль устройства" : "На устройстве не задан код-пароль"))
                }
                .tint(Color.mono.accent)
                .disabled(working || !lock.canProtect)
                if settings.appLockEnabled {
                    Picker(selection: $settings.lockTimeout) {
                        Text("Сразу").tag(LockTimeout.immediately)
                        Text("Через 1 минуту").tag(LockTimeout.oneMinute)
                        Text("Через 5 минут").tag(LockTimeout.fiveMinutes)
                        Text("Через 15 минут").tag(LockTimeout.fifteenMinutes)
                    } label: {
                        FormRow(icon: "timer", tint: Color.mono.neutral, title: "Блокировать в фоне")
                    }
                }
                if let error = lock.lastError {
                    Text(verbatim: error)
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.negative)
                }
            } header: {
                Kicker("Вход")
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                Toggle(isOn: $settings.privacyShield) {
                    FormRow(icon: "eye.slash.circle.fill", tint: Color.mono.accent, title: "Скрывать в переключателе",
                            subtitle: Text("Суммы не попадают в снимок экрана при сворачивании"))
                }
                .tint(Color.mono.accent)
                Toggle(isOn: $settings.hideAmountsOnLaunch) {
                    FormRow(icon: "eye.trianglebadge.exclamationmark", tint: Color.mono.accent, title: "Скрывать суммы при запуске",
                            subtitle: Text("Показать — касанием глаза на главном экране"))
                }
                .tint(Color.mono.accent)
            } header: {
                Kicker("Приватность")
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    privacyLine("internaldrive.fill", "Данные хранятся только на этом iPhone, в защищённом хранилище iOS (Data Protection).")
                    privacyLine("icloud.slash.fill", "Нет аккаунта и облака MONO: операции никуда не отправляются.")
                    privacyLine("waveform.badge.mic", "Голос распознаётся на устройстве. Серверы Apple используются только с вашего разрешения, если язык не поддерживается локально.")
                    privacyLine("network", "Из сети загружаются только курсы ЦБ РУз — запрос без ваших данных.")
                    privacyLine("key.fill", "Пароли от банков приложение не запрашивает и не хранит.")
                }
                .padding(.vertical, 6)
            } header: {
                Kicker("Как защищены данные")
            }
            .listRowBackground(Color.mono.surface1)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MonoBackdrop())
        .navigationTitle(Text("Приватность и защита"))
        .onAppear { lockEnabled = settings.appLockEnabled }
    }

    private var lockSymbol: String {
        switch lock.biometry {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.fill"
        }
    }

    private func privacyLine(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.mono.accentText)
                .frame(width: 22)
            Text(text)
                .monoFont(.footnote)
                .foregroundStyle(Color.mono.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setLock(_ enabled: Bool) async {
        working = true
        defer { working = false }
        if enabled {
            lockEnabled = await lock.enable(reason: String(localized: "Подтвердите, чтобы включить блокировку MONO"))
        } else {
            lock.disable()
            lockEnabled = false
        }
    }
}

// MARK: - Голосовой ввод

struct SpeechSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var support: [AppLanguage: SpeechSupportInfo] = [:]
    @State private var micStatus = SpeechPermissions.microphoneStatus
    @State private var speechStatus = SpeechPermissions.speechStatus

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Button {
                        Haptics.selection()
                        settings.speechLanguage = language
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: settings.speechLanguage == language ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(settings.speechLanguage == language ? Color.mono.accent : Color.mono.textTertiary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: language.nativeName)
                                    .monoFont(.body)
                                    .foregroundStyle(Color.mono.textPrimary)
                                supportLabel(support[language])
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Kicker("Язык распознавания")
            } footer: {
                Text("Поддержка проверяется на этом iPhone прямо сейчас. Если язык не поддерживается, фразу можно ввести текстом — разбор работает так же.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                Toggle(isOn: $settings.speechServerConsent) {
                    FormRow(icon: "icloud.and.arrow.up", tint: Color.mono.textSecondary, title: "Разрешить серверы Apple",
                            subtitle: Text("Только если язык не распознаётся на устройстве. Аудио отправляется Apple для расшифровки; финансовые данные — нет."))
                }
                .tint(Color.mono.accent)
                Toggle(isOn: $settings.autoStopOnSilence) {
                    FormRow(icon: "waveform.path.badge.minus", tint: Color.mono.accent, title: "Останавливать по паузе",
                            subtitle: Text("Запись завершится, когда вы замолчите"))
                }
                .tint(Color.mono.accent)
            } header: {
                Kicker("Обработка")
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                permissionRow(title: "Микрофон", granted: micStatus == .granted, undetermined: micStatus == .undetermined)
                permissionRow(title: "Распознавание речи", granted: speechStatus == .authorized, undetermined: speechStatus == .notDetermined)
                Button("Открыть настройки iOS") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .monoFont(.body)
            } header: {
                Kicker("Разрешения")
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Примеры фраз")
                        .monoFont(.headline)
                        .foregroundStyle(Color.mono.textPrimary)
                    ForEach(examples, id: \.self) { example in
                        Text(verbatim: "«\(example)»")
                            .monoFont(.quote)
                            .foregroundStyle(Color.mono.textSecondary)
                    }
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.mono.surface1)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MonoBackdrop())
        .navigationTitle(Text("Голосовой ввод"))
        .task { refresh() }
    }

    private let examples = [
        "Потратил 85 тысяч сум на обед сегодня",
        "Вчера купил продукты в Корзинке на 245 тысяч с карты Капиталбанка",
        "Перевёл миллион сум с Капиталбанка на Узум",
        "Получил 500 долларов",
        "Сегодня потратил 120 тысяч на такси и 75 тысяч на кофе"
    ]

    private func refresh() {
        var map: [AppLanguage: SpeechSupportInfo] = [:]
        for language in AppLanguage.allCases { map[language] = SpeechSupport.info(for: language) }
        support = map
        micStatus = SpeechPermissions.microphoneStatus
        speechStatus = SpeechPermissions.speechStatus
    }

    @ViewBuilder
    private func supportLabel(_ info: SpeechSupportInfo?) -> some View {
        if let info {
            if info.supportsOnDevice {
                Label("На устройстве, без интернета", systemImage: "lock.iphone")
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.positive)
            } else if info.isSupported {
                Label("Только через серверы Apple", systemImage: "icloud")
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.warning)
            } else {
                Label("Не поддерживается системой — ввод текстом", systemImage: "keyboard")
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.textTertiary)
            }
        } else {
            ProgressView().controlSize(.mini)
        }
    }

    private func permissionRow(title: LocalizedStringKey, granted: Bool, undetermined: Bool) -> some View {
        HStack {
            Text(title)
                .monoFont(.body)
                .foregroundStyle(Color.mono.textPrimary)
            Spacer()
            if granted {
                Label("Разрешено", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.mono.positive)
            } else if undetermined {
                Label("Спросим при первой записи", systemImage: "questionmark.circle")
                    .foregroundStyle(Color.mono.textTertiary)
            } else {
                Label("Запрещено", systemImage: "xmark.circle.fill")
                    .foregroundStyle(Color.mono.negative)
            }
        }
        .monoFont(.caption)
    }
}

// MARK: - Ассистент и ИИ

struct AISettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var token = ""
    @State private var tokenSaved = false

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ассистент работает на устройстве")
                        .monoFont(.headline)
                        .foregroundStyle(Color.mono.textPrimary)
                    Text("Ответы на вопросы о расходах, сравнения, прогнозы и поиск необычных трат считаются локально по вашим операциям. Если данных нет — ассистент так и говорит.")
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textSecondary)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                Toggle(isOn: $settings.llmEnabled) {
                    FormRow(icon: "server.rack", tint: Color.mono.accent, title: "Пояснения внешней модели",
                            subtitle: Text("Через ваш собственный сервер (HTTPS)"))
                }
                .tint(Color.mono.accent)
                if settings.llmEnabled {
                    TextField("https://…", text: $settings.llmEndpoint)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .monoFont(.body)
                    if !settings.llmEndpoint.isEmpty && URL(string: settings.llmEndpoint)?.scheme != "https" {
                        Text("Адрес должен начинаться с https://")
                            .monoFont(.caption)
                            .foregroundStyle(Color.mono.negative)
                    }
                    HStack {
                        SecureField("Токен доступа (необязательно)", text: $token)
                            .monoFont(.body)
                            .textInputAutocapitalization(.never)
                        Button(tokenSaved ? "Сохранено" : "Сохранить") {
                            KeychainStore.set(token, for: KeychainStore.Keys.llmToken)
                            token = ""
                            tokenSaved = true
                            Haptics.success()
                        }
                        .disabled(token.isEmpty)
                    }
                    Toggle(isOn: $settings.llmConsent) {
                        Text("Я согласен отправлять на этот сервер текст вопроса и посчитанные приложением итоги (без списка операций, выписок и аудио).")
                            .monoFont(.footnote)
                            .foregroundStyle(Color.mono.textSecondary)
                    }
                    .tint(Color.mono.accent)
                }
            } header: {
                Kicker("Внешняя модель")
            } footer: {
                Text("Модель не считает цифры — она только пересказывает ответ, который уже посчитало приложение. Токен хранится в Keychain только на этом устройстве.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)

            if KeychainStore.get(KeychainStore.Keys.llmToken) != nil || tokenSaved {
                Section {
                    Button("Удалить сохранённый токен", role: .destructive) {
                        KeychainStore.set(nil, for: KeychainStore.Keys.llmToken)
                        tokenSaved = false
                    }
                }
                .listRowBackground(Color.mono.surface1)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MonoBackdrop())
        .navigationTitle(Text("Ассистент и ИИ"))
    }
}

// MARK: - Банки

/// Честный статус подключений: официального доступа для личного использования сейчас нет — предлагаем импорт.
struct BankSyncView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language

    var body: some View {
        List {
            Section {
                ForEach(BankIntegrationRegistry.supportedBanks, id: \.self) { bank in
                    let integration = BankIntegrationRegistry.integration(for: bank)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(CardSkin.default(for: bank).linearGradient)
                                .frame(width: 44, height: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: bank.displayName)
                                    .monoFont(.body)
                                    .foregroundStyle(Color.mono.textPrimary)
                                Text(verbatim: accountsText(bank))
                                    .monoFont(.caption)
                                    .foregroundStyle(Color.mono.textTertiary)
                            }
                            Spacer()
                            statusBadge(integration.availability)
                        }
                        if case .unavailable(let reason) = integration.availability {
                            Text(verbatim: reason(language))
                                .monoFont(.footnote)
                                .foregroundStyle(Color.mono.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                router.present(.importStatement(store.activeAccounts.first { $0.bank == bank }))
                            } label: {
                                Label("Импортировать выписку", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(ChipStyle(isSelected: true, tint: Color.mono.textSecondary))
                        }
                    }
                    .padding(.vertical, 6)
                }
            } footer: {
                Text("MONO не просит пароли от интернет-банка, не перехватывает коды и не имитирует подключение. Автоматическая синхронизация появится только через официальный канал банка с вашего согласия.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                ForEach(BankIntegrationRegistry.supportedBanks, id: \.self) { bank in
                    HStack {
                        Text(verbatim: bank.displayName)
                            .monoFont(.body)
                            .foregroundStyle(Color.mono.textPrimary)
                        Spacer()
                        Text(StatementAdapterRegistry.verifiedBanks.contains(bank) ? "Шаблон проверен" : "Автоопределение колонок")
                            .monoFont(.caption)
                            .foregroundStyle(StatementAdapterRegistry.verifiedBanks.contains(bank) ? Color.mono.positive : Color.mono.textTertiary)
                    }
                }
            } header: {
                Kicker("Формат выписки")
            } footer: {
                Text("Шаблон банка считается проверенным только после теста на реальной выписке. Пока таких нет — колонки определяются автоматически и подтверждаются вами.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MonoBackdrop())
        .navigationTitle(Text("Банки"))
    }

    private func accountsText(_ bank: Bank) -> String {
        let count = store.activeAccounts.filter { $0.bank == bank }.count
        return count == 0
            ? Phrase(ru: "Нет счетов", uz: "Hisoblar yo‘q", en: "No accounts")(language)
            : Phrase(ru: "Счетов: \(count)", uz: "Hisoblar: \(count)", en: "Accounts: \(count)")(language)
    }

    @ViewBuilder
    private func statusBadge(_ availability: SyncAvailability) -> some View {
        switch availability {
        case .available:
            Label("Подключено", systemImage: "checkmark.circle.fill")
                .monoFont(.caption)
                .foregroundStyle(Color.mono.positive)
        case .unavailable:
            Text("Синхронизация недоступна")
                .monoFont(.caption)
                .foregroundStyle(Color.mono.warning)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120, alignment: .trailing)
        }
    }
}

// MARK: - О приложении

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "MONO")
                        .font(.system(size: 44, weight: .heavy).width(.expanded))
                        .foregroundStyle(Color.mono.textPrimary)
                    Text("Личные финансы без шума")
                        .monoFont(.title2)
                        .foregroundStyle(Color.mono.textPrimary)
                    Text(verbatim: Bundle.main.shortVersion)
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.textTertiary)
                }
                aboutBlock("Точные деньги", "Суммы хранятся в минимальных единицах валюты (тийины, центы), без ошибок округления. Переводы между своими счетами не считаются ни доходом, ни расходом.")
                aboutBlock("Ничего выдуманного", "Балансы считаются только из ваших операций и начальных остатков. Демо-данные живут в отдельной базе и всегда помечены.")
                aboutBlock("Подтверждение — за вами", "Голос, импорт и регулярные платежи предлагают черновики. Операция появляется только после вашего подтверждения.")
                aboutBlock("Виртуальные карты", "Карты в приложении — оформление ваших счетов, а не банковские продукты. Логотипы банков не используются.")
                aboutBlock("Курсы валют", "Официальные курсы Центрального банка Республики Узбекистан (cbu.uz) или введённые вами вручную.")
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(MonoBackdrop(haze: true))
        .navigationTitle(Text("О приложении"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutBlock(_ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Capsule(style: .continuous)
                .fill(Color.mono.accent)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .textCase(.uppercase)
                    .monoFont(.kicker)
                    .foregroundStyle(Color.mono.accentText)
                Text(text)
                    .monoFont(.quote)
                    .foregroundStyle(Color.mono.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
