import Foundation
import Observation
import MonoCore
import MonoIntelligence

/// Ключи пользовательских настроек интерфейса и безопасности (UserDefaults).
/// Финансовые настройки (базовая валюта, счёт по умолчанию) хранятся в базе и попадают в резервную копию.
enum SettingsKeys {
    static let onboardingCompleted = "onboardingCompleted"
    static let hideAmounts = "hideAmounts"
    static let hideAmountsOnLaunch = "hideAmountsOnLaunch"
    static let appLockEnabled = "appLockEnabled"
    static let lockTimeout = "lockTimeout"
    static let privacyShield = "privacyShield"
    static let haptics = "haptics"
    static let appearance = "appearance"
    static let speechLanguage = "speechLanguage"
    static let speechServerConsent = "speechServerConsent"
    static let autoStopOnSilence = "autoStopOnSilence"
    static let cbuRatesEnabled = "cbuRatesEnabled"
    static let lastRatesUpdate = "lastRatesUpdate"
    static let remindersEnabled = "remindersEnabled"
    static let llmEnabled = "llmEnabled"
    static let llmProviders = "llmProviders"
    static let llmActiveProvider = "llmActiveProvider"
    static let llmConsent = "llmConsent"
    static let demoMode = "demoMode"
}

enum Appearance: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }
}

/// Тайм-аут автоблокировки после ухода в фон.
enum LockTimeout: Int, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var id: Int { rawValue }
}

@MainActor
@Observable
final class SettingsStore {
    private let defaults: UserDefaults

    var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: SettingsKeys.onboardingCompleted) } }
    var hideAmounts: Bool { didSet { defaults.set(hideAmounts, forKey: SettingsKeys.hideAmounts) } }
    var hideAmountsOnLaunch: Bool { didSet { defaults.set(hideAmountsOnLaunch, forKey: SettingsKeys.hideAmountsOnLaunch) } }
    var appLockEnabled: Bool { didSet { defaults.set(appLockEnabled, forKey: SettingsKeys.appLockEnabled) } }
    var lockTimeout: LockTimeout { didSet { defaults.set(lockTimeout.rawValue, forKey: SettingsKeys.lockTimeout) } }
    var privacyShield: Bool { didSet { defaults.set(privacyShield, forKey: SettingsKeys.privacyShield) } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: SettingsKeys.haptics) } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: SettingsKeys.appearance) } }
    var speechLanguage: AppLanguage { didSet { defaults.set(speechLanguage.rawValue, forKey: SettingsKeys.speechLanguage) } }
    /// Согласие на распознавание речи серверами Apple, если локальное распознавание недоступно.
    var speechServerConsent: Bool { didSet { defaults.set(speechServerConsent, forKey: SettingsKeys.speechServerConsent) } }
    var autoStopOnSilence: Bool { didSet { defaults.set(autoStopOnSilence, forKey: SettingsKeys.autoStopOnSilence) } }
    /// Загружать официальные курсы ЦБ РУз (запрос без персональных данных).
    var cbuRatesEnabled: Bool { didSet { defaults.set(cbuRatesEnabled, forKey: SettingsKeys.cbuRatesEnabled) } }
    var lastRatesUpdate: Date? { didSet { defaults.set(lastRatesUpdate, forKey: SettingsKeys.lastRatesUpdate) } }
    var remindersEnabled: Bool { didSet { defaults.set(remindersEnabled, forKey: SettingsKeys.remindersEnabled) } }
    /// Нейросеть (Groq, Cerebras, OpenRouter, Gemini или свой сервис) — выключено по умолчанию.
    var llmEnabled: Bool { didSet { defaults.set(llmEnabled, forKey: SettingsKeys.llmEnabled) } }
    /// Сервисы нейросети. Ключи хранятся отдельно, в Keychain (`LLMKeychain`).
    var llmProviders: [LLMProvider] {
        didSet { defaults.set(try? JSONEncoder().encode(llmProviders), forKey: SettingsKeys.llmProviders) }
    }
    var llmActiveProviderID: String { didSet { defaults.set(llmActiveProviderID, forKey: SettingsKeys.llmActiveProvider) } }
    /// Согласие на отправку сводки (без операций, карт и имён) выбранному сервису.
    var llmConsent: Bool { didSet { defaults.set(llmConsent, forKey: SettingsKeys.llmConsent) } }
    var demoMode: Bool { didSet { defaults.set(demoMode, forKey: SettingsKeys.demoMode) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingCompleted = defaults.bool(forKey: SettingsKeys.onboardingCompleted)
        hideAmountsOnLaunch = defaults.bool(forKey: SettingsKeys.hideAmountsOnLaunch)
        hideAmounts = defaults.bool(forKey: SettingsKeys.hideAmountsOnLaunch) ? true : defaults.bool(forKey: SettingsKeys.hideAmounts)
        appLockEnabled = defaults.bool(forKey: SettingsKeys.appLockEnabled)
        lockTimeout = LockTimeout(rawValue: defaults.integer(forKey: SettingsKeys.lockTimeout)) ?? .immediately
        privacyShield = defaults.object(forKey: SettingsKeys.privacyShield) as? Bool ?? true
        haptics = defaults.object(forKey: SettingsKeys.haptics) as? Bool ?? true
        appearance = Appearance(rawValue: defaults.string(forKey: SettingsKeys.appearance) ?? "") ?? .dark
        speechLanguage = AppLanguage(rawValue: defaults.string(forKey: SettingsKeys.speechLanguage) ?? "") ?? AppLanguage.current
        speechServerConsent = defaults.bool(forKey: SettingsKeys.speechServerConsent)
        autoStopOnSilence = defaults.object(forKey: SettingsKeys.autoStopOnSilence) as? Bool ?? true
        cbuRatesEnabled = defaults.object(forKey: SettingsKeys.cbuRatesEnabled) as? Bool ?? true
        lastRatesUpdate = defaults.object(forKey: SettingsKeys.lastRatesUpdate) as? Date
        remindersEnabled = defaults.bool(forKey: SettingsKeys.remindersEnabled)
        llmEnabled = defaults.bool(forKey: SettingsKeys.llmEnabled)
        let savedProviders = defaults.data(forKey: SettingsKeys.llmProviders).flatMap { try? JSONDecoder().decode([LLMProvider].self, from: $0) }
        llmProviders = LLMProvider.upgradingRetiredModels(LLMProvider.mergingPresets(into: savedProviders ?? []))
        llmActiveProviderID = defaults.string(forKey: SettingsKeys.llmActiveProvider) ?? LLMProvider.groq.id
        llmConsent = defaults.bool(forKey: SettingsKeys.llmConsent)
        demoMode = defaults.bool(forKey: SettingsKeys.demoMode)
    }

    /// Активный сервис нейросети (или первый, если активный удалён).
    var llmActiveProvider: LLMProvider? {
        llmProviders.first { $0.id == llmActiveProviderID } ?? llmProviders.first
    }

    /// Сервисы в порядке попыток: активный, затем остальные включённые с ключом.
    var llmCandidates: [LLMProvider] {
        LLMProvider.fallbackOrder(llmProviders, activeID: llmActiveProviderID) { LLMKeychain.hasKey($0) }
    }

    /// Можно ли спрашивать нейросеть: включено, есть согласие и хотя бы один сервис с ключом.
    var llmReady: Bool { llmEnabled && llmConsent && !llmCandidates.isEmpty }
}
