import SwiftUI
import MonoCore

private struct HideAmountsKey: EnvironmentKey {
    static let defaultValue = false
}

private struct MoneyFormatterKey: EnvironmentKey {
    static let defaultValue = MoneyFormatter(language: .ru)
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .ru
}

extension EnvironmentValues {
    /// Режим конфиденциальности: суммы скрыты.
    var hideAmounts: Bool {
        get { self[HideAmountsKey.self] }
        set { self[HideAmountsKey.self] = newValue }
    }

    var moneyFormatter: MoneyFormatter {
        get { self[MoneyFormatterKey.self] }
        set { self[MoneyFormatterKey.self] = newValue }
    }

    /// Язык строк, которые формирует ядро (инсайты, ответы ассистента).
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

extension AppLanguage {
    /// Язык интерфейса по фактической локализации приложения (учитывает «Язык приложения» в Настройках iOS).
    static var current: AppLanguage {
        AppLanguage(localeIdentifier: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier)
    }

    var locale: Locale {
        switch self {
        case .ru: return Locale(identifier: "ru_RU")
        case .uz: return Locale(identifier: "uz_Latn_UZ")
        case .en: return Locale(identifier: "en_US")
        }
    }
}
