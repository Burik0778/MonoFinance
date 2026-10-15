import Foundation

/// Языки интерфейса. Основной — русский; узбекский (латиница) и английский поддержаны архитектурно.
public enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case ru
    case uz
    case en

    public var id: String { rawValue }

    public init(localeIdentifier: String) {
        let lowered = localeIdentifier.lowercased()
        if lowered.hasPrefix("uz") {
            self = .uz
        } else if lowered.hasPrefix("en") {
            self = .en
        } else {
            self = .ru
        }
    }

    /// Локаль для распознавания речи.
    public var speechLocaleIdentifier: String {
        switch self {
        case .ru: return "ru-RU"
        case .uz: return "uz-UZ"
        case .en: return "en-US"
        }
    }

    public var nativeName: String {
        switch self {
        case .ru: return "Русский"
        case .uz: return "O‘zbekcha"
        case .en: return "English"
        }
    }
}

/// Мини-словарь для строк, которые формирует само ядро (инсайты, ответы ассистента, названия по умолчанию).
/// UI-строки локализуются в приложении через String Catalog.
public struct Phrase: Sendable {
    public let ru: String
    public let uz: String
    public let en: String

    public init(ru: String, uz: String, en: String) {
        self.ru = ru
        self.uz = uz
        self.en = en
    }

    public func callAsFunction(_ language: AppLanguage) -> String {
        switch language {
        case .ru: return ru
        case .uz: return uz
        case .en: return en
        }
    }
}
