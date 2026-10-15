import Foundation

/// Банк счёта. Список намеренно короткий: банки пользователя + наличные + «другой».
public enum Bank: String, Codable, Sendable, CaseIterable, Identifiable {
    case kapitalbank
    case uzum
    case orientFinans
    case trastbank
    case cash
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .kapitalbank: return "Kapitalbank"
        case .uzum: return "Uzum Bank"
        case .orientFinans: return "Orient Finans Bank"
        case .trastbank: return "Trastbank"
        case .cash: return "Наличные"
        case .other: return "Другой банк"
        }
    }

    public var shortName: String {
        switch self {
        case .kapitalbank: return "Kapital"
        case .uzum: return "Uzum"
        case .orientFinans: return "OFB"
        case .trastbank: return "Trast"
        case .cash: return "Cash"
        case .other: return "Bank"
        }
    }

    /// Основы слов для распознавания упоминаний банка в речи и выписках (после `TextNormalizer.fold`).
    /// Проверяются как префиксы слов, поэтому ловят падежи: «капиталбанка», «узуме», «трастбанком».
    public var mentionStems: [String] {
        switch self {
        case .kapitalbank: return ["капиталбанк", "капитал", "kapitalbank", "kapital", "capital"]
        case .uzum: return ["узум", "uzum"]
        case .orientFinans: return ["ориент", "orient", "офб", "ofb"]
        case .trastbank: return ["трастбанк", "траст", "trastbank", "trast", "trust"]
        case .cash: return ["наличн", "налом", "налик", "кэш", "кеш", "cash", "naqd"]
        case .other: return []
        }
    }

    /// Банки, к которым в будущем можно подключить официальную синхронизацию.
    public var isBank: Bool { self != .cash && self != .other }
}

/// Тип счёта.
public enum AccountKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case card
    case current
    case savings
    case deposit
    case cash
    case credit

    public var id: String { rawValue }

    public var title: Phrase {
        switch self {
        case .card: return Phrase(ru: "Карта", uz: "Karta", en: "Card")
        case .current: return Phrase(ru: "Текущий счёт", uz: "Joriy hisob", en: "Current account")
        case .savings: return Phrase(ru: "Накопительный", uz: "Jamg‘arma", en: "Savings")
        case .deposit: return Phrase(ru: "Вклад", uz: "Omonat", en: "Deposit")
        case .cash: return Phrase(ru: "Наличные", uz: "Naqd pul", en: "Cash")
        case .credit: return Phrase(ru: "Кредитная карта", uz: "Kredit karta", en: "Credit card")
        }
    }
}

/// Платёжная система карты (только как текстовая метка, без логотипов).
public enum PaymentSystem: String, Codable, Sendable, CaseIterable, Identifiable {
    case humo
    case uzcard
    case visa
    case mastercard
    case unionPay
    case mir

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .humo: return "HUMO"
        case .uzcard: return "UZCARD"
        case .visa: return "VISA"
        case .mastercard: return "MASTERCARD"
        case .unionPay: return "UNIONPAY"
        case .mir: return "МИР"
        }
    }

    public var mentionStems: [String] {
        switch self {
        case .humo: return ["хумо", "humo"]
        case .uzcard: return ["узкарт", "uzcard", "uzkart"]
        case .visa: return ["виза", "визы", "визой", "визу", "visa"]
        case .mastercard: return ["мастеркард", "мастер", "mastercard", "master"]
        case .unionPay: return ["юнионпей", "unionpay", "union"]
        // «мир» — слишком частое слово в речи; карту МИР выбирают вручную.
        case .mir: return []
        }
    }
}

/// Абстрактный «скин» виртуальной карты. Не копирует дизайн реальных банковских продуктов.
public enum CardSkin: String, Codable, Sendable, CaseIterable, Identifiable {
    case aurora
    case nebula
    case glacier
    case lagoon
    case graphite
    case ultraviolet

    public var id: String { rawValue }

    public static func `default`(for bank: Bank) -> CardSkin {
        switch bank {
        case .kapitalbank: return .aurora
        case .uzum: return .ultraviolet
        case .orientFinans: return .lagoon
        case .trastbank: return .glacier
        case .cash: return .graphite
        case .other: return .nebula
        }
    }
}

/// Счёт или карта пользователя. Баланс не хранится: он всегда вычисляется из проводок.
public struct Account: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var bank: Bank
    public var name: String
    public var kind: AccountKind
    public var paymentSystem: PaymentSystem?
    public var currency: Currency
    /// Последние 4 цифры карты — только для узнавания, полный номер не хранится никогда.
    public var lastFour: String?
    public var skin: CardSkin
    public var includeInTotal: Bool
    public var isArchived: Bool
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        bank: Bank,
        name: String,
        kind: AccountKind = .card,
        paymentSystem: PaymentSystem? = nil,
        currency: Currency = .uzs,
        lastFour: String? = nil,
        skin: CardSkin? = nil,
        includeInTotal: Bool = true,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.bank = bank
        self.name = name
        self.kind = kind
        self.paymentSystem = paymentSystem
        self.currency = currency
        self.lastFour = Account.sanitizeLastFour(lastFour)
        self.skin = skin ?? CardSkin.default(for: bank)
        self.includeInTotal = includeInTotal
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// Оставляет ровно 4 последние цифры или `nil`.
    public static func sanitizeLastFour(_ value: String?) -> String? {
        guard let value else { return nil }
        let digits = value.filter { $0.isASCII && $0.isNumber }
        guard digits.count >= 4 else { return nil }
        return String(digits.suffix(4))
    }

    /// Отображаемое имя: пользовательское название или банк.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? bank.displayName : trimmed
    }

    public var maskedNumber: String? {
        guard let lastFour else { return nil }
        return "•• " + lastFour
    }
}
