import Foundation

public enum CategoryKind: String, Codable, Sendable, CaseIterable {
    case expense
    case income
}

/// Цветовой токен категории. Конкретные цвета задаёт дизайн-система приложения.
public enum CategoryColor: String, Codable, Sendable, CaseIterable, Identifiable {
    case electric
    case violet
    case cyan
    case emerald
    case coral
    case magenta
    case indigo
    case sky
    case mint
    case tangerine
    case rose
    case steel

    public var id: String { rawValue }
}

/// Категория операций. Встроенные категории имеют стабильный `systemKey`,
/// на который опираются правила категоризации — даже если пользователь переименовал категорию.
public struct FinanceCategory: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: CategoryKind
    /// Имя SF Symbol.
    public var icon: String
    public var color: CategoryColor
    /// Обязательный расход (жильё, связь, кредиты…) — для доли обязательных трат.
    public var isMandatory: Bool
    public var systemKey: String?
    public var isArchived: Bool
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        name: String,
        kind: CategoryKind,
        icon: String,
        color: CategoryColor,
        isMandatory: Bool = false,
        systemKey: String? = nil,
        isArchived: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.icon = icon
        self.color = color
        self.isMandatory = isMandatory
        self.systemKey = systemKey
        self.isArchived = isArchived
        self.sortOrder = sortOrder
    }
}

/// Ключи встроенных категорий.
public enum SystemCategoryKey {
    // Расходы
    public static let groceries = "groceries"
    public static let cafe = "cafe"
    public static let delivery = "delivery"
    public static let taxi = "taxi"
    public static let transport = "transport"
    public static let fuel = "fuel"
    public static let car = "car"
    public static let housing = "housing"
    public static let utilities = "utilities"
    public static let mobile = "mobile"
    public static let subscriptions = "subscriptions"
    public static let health = "health"
    public static let beauty = "beauty"
    public static let clothes = "clothes"
    public static let shopping = "shopping"
    public static let electronics = "electronics"
    public static let home = "home"
    public static let entertainment = "entertainment"
    public static let sport = "sport"
    public static let education = "education"
    public static let travel = "travel"
    public static let gifts = "gifts"
    public static let family = "family"
    public static let pets = "pets"
    public static let transfersOut = "transfers_out"
    public static let loans = "loans"
    public static let taxes = "taxes"
    public static let charity = "charity"
    public static let otherExpense = "other_expense"
    // Доходы
    public static let salary = "salary"
    public static let freelance = "freelance"
    public static let business = "business"
    public static let cashback = "cashback"
    public static let interest = "interest"
    public static let giftsIncome = "gifts_income"
    public static let debtReturn = "debt_return"
    public static let sale = "sale"
    public static let otherIncome = "other_income"
}

/// Набор категорий по умолчанию. Идентификаторы детерминированы, чтобы демо-данные и тесты были воспроизводимы.
public enum DefaultCategories {
    struct Spec {
        let key: String
        let kind: CategoryKind
        let name: Phrase
        let icon: String
        let color: CategoryColor
        let mandatory: Bool
    }

    static let specs: [Spec] = [
        Spec(key: SystemCategoryKey.groceries, kind: .expense, name: Phrase(ru: "Продукты", uz: "Oziq-ovqat", en: "Groceries"), icon: "cart.fill", color: .emerald, mandatory: true),
        Spec(key: SystemCategoryKey.cafe, kind: .expense, name: Phrase(ru: "Кафе и рестораны", uz: "Kafe va restoranlar", en: "Cafes & restaurants"), icon: "cup.and.saucer.fill", color: .coral, mandatory: false),
        Spec(key: SystemCategoryKey.delivery, kind: .expense, name: Phrase(ru: "Доставка еды", uz: "Ovqat yetkazish", en: "Food delivery"), icon: "takeoutbag.and.cup.and.straw.fill", color: .rose, mandatory: false),
        Spec(key: SystemCategoryKey.taxi, kind: .expense, name: Phrase(ru: "Такси", uz: "Taksi", en: "Taxi"), icon: "car.fill", color: .tangerine, mandatory: false),
        Spec(key: SystemCategoryKey.transport, kind: .expense, name: Phrase(ru: "Общественный транспорт", uz: "Jamoat transporti", en: "Public transport"), icon: "tram.fill", color: .sky, mandatory: true),
        Spec(key: SystemCategoryKey.fuel, kind: .expense, name: Phrase(ru: "Топливо", uz: "Yoqilg‘i", en: "Fuel"), icon: "fuelpump.fill", color: .indigo, mandatory: false),
        Spec(key: SystemCategoryKey.car, kind: .expense, name: Phrase(ru: "Автомобиль", uz: "Avtomobil", en: "Car"), icon: "wrench.and.screwdriver.fill", color: .steel, mandatory: false),
        Spec(key: SystemCategoryKey.housing, kind: .expense, name: Phrase(ru: "Жильё и аренда", uz: "Uy-joy va ijara", en: "Housing & rent"), icon: "house.fill", color: .violet, mandatory: true),
        Spec(key: SystemCategoryKey.utilities, kind: .expense, name: Phrase(ru: "Коммунальные услуги", uz: "Kommunal xizmatlar", en: "Utilities"), icon: "bolt.fill", color: .cyan, mandatory: true),
        Spec(key: SystemCategoryKey.mobile, kind: .expense, name: Phrase(ru: "Связь и интернет", uz: "Aloqa va internet", en: "Mobile & internet"), icon: "antenna.radiowaves.left.and.right", color: .electric, mandatory: true),
        Spec(key: SystemCategoryKey.subscriptions, kind: .expense, name: Phrase(ru: "Подписки", uz: "Obunalar", en: "Subscriptions"), icon: "repeat.circle.fill", color: .magenta, mandatory: false),
        Spec(key: SystemCategoryKey.health, kind: .expense, name: Phrase(ru: "Здоровье и аптека", uz: "Salomatlik va dorixona", en: "Health & pharmacy"), icon: "cross.case.fill", color: .mint, mandatory: true),
        Spec(key: SystemCategoryKey.beauty, kind: .expense, name: Phrase(ru: "Красота и уход", uz: "Go‘zallik", en: "Beauty"), icon: "sparkles", color: .rose, mandatory: false),
        Spec(key: SystemCategoryKey.clothes, kind: .expense, name: Phrase(ru: "Одежда и обувь", uz: "Kiyim-kechak", en: "Clothing"), icon: "tshirt.fill", color: .violet, mandatory: false),
        Spec(key: SystemCategoryKey.shopping, kind: .expense, name: Phrase(ru: "Покупки и маркетплейсы", uz: "Xaridlar", en: "Shopping"), icon: "bag.fill", color: .magenta, mandatory: false),
        Spec(key: SystemCategoryKey.electronics, kind: .expense, name: Phrase(ru: "Техника", uz: "Texnika", en: "Electronics"), icon: "laptopcomputer", color: .electric, mandatory: false),
        Spec(key: SystemCategoryKey.home, kind: .expense, name: Phrase(ru: "Дом и быт", uz: "Uy-ro‘zg‘or", en: "Home"), icon: "sofa.fill", color: .sky, mandatory: false),
        Spec(key: SystemCategoryKey.entertainment, kind: .expense, name: Phrase(ru: "Развлечения", uz: "Ko‘ngilochar", en: "Entertainment"), icon: "ticket.fill", color: .coral, mandatory: false),
        Spec(key: SystemCategoryKey.sport, kind: .expense, name: Phrase(ru: "Спорт", uz: "Sport", en: "Sport"), icon: "dumbbell.fill", color: .emerald, mandatory: false),
        Spec(key: SystemCategoryKey.education, kind: .expense, name: Phrase(ru: "Образование", uz: "Ta’lim", en: "Education"), icon: "book.fill", color: .indigo, mandatory: true),
        Spec(key: SystemCategoryKey.travel, kind: .expense, name: Phrase(ru: "Путешествия", uz: "Sayohat", en: "Travel"), icon: "airplane", color: .cyan, mandatory: false),
        Spec(key: SystemCategoryKey.gifts, kind: .expense, name: Phrase(ru: "Подарки", uz: "Sovg‘alar", en: "Gifts"), icon: "gift.fill", color: .magenta, mandatory: false),
        Spec(key: SystemCategoryKey.family, kind: .expense, name: Phrase(ru: "Семья и дети", uz: "Oila va bolalar", en: "Family & kids"), icon: "person.2.fill", color: .mint, mandatory: false),
        Spec(key: SystemCategoryKey.pets, kind: .expense, name: Phrase(ru: "Питомцы", uz: "Uy hayvonlari", en: "Pets"), icon: "pawprint.fill", color: .tangerine, mandatory: false),
        Spec(key: SystemCategoryKey.transfersOut, kind: .expense, name: Phrase(ru: "Переводы людям", uz: "Odamlarga o‘tkazmalar", en: "Transfers to people"), icon: "paperplane.fill", color: .sky, mandatory: false),
        Spec(key: SystemCategoryKey.loans, kind: .expense, name: Phrase(ru: "Кредиты и рассрочка", uz: "Kreditlar", en: "Loans"), icon: "creditcard.fill", color: .steel, mandatory: true),
        Spec(key: SystemCategoryKey.taxes, kind: .expense, name: Phrase(ru: "Налоги и штрафы", uz: "Soliqlar", en: "Taxes & fines"), icon: "building.columns.fill", color: .steel, mandatory: true),
        Spec(key: SystemCategoryKey.charity, kind: .expense, name: Phrase(ru: "Благотворительность", uz: "Xayriya", en: "Charity"), icon: "heart.circle.fill", color: .rose, mandatory: false),
        Spec(key: SystemCategoryKey.otherExpense, kind: .expense, name: Phrase(ru: "Прочие расходы", uz: "Boshqa xarajatlar", en: "Other"), icon: "square.grid.2x2.fill", color: .steel, mandatory: false),

        Spec(key: SystemCategoryKey.salary, kind: .income, name: Phrase(ru: "Зарплата", uz: "Maosh", en: "Salary"), icon: "briefcase.fill", color: .emerald, mandatory: false),
        Spec(key: SystemCategoryKey.freelance, kind: .income, name: Phrase(ru: "Фриланс", uz: "Frilans", en: "Freelance"), icon: "wand.and.stars", color: .violet, mandatory: false),
        Spec(key: SystemCategoryKey.business, kind: .income, name: Phrase(ru: "Бизнес", uz: "Biznes", en: "Business"), icon: "chart.line.uptrend.xyaxis", color: .electric, mandatory: false),
        Spec(key: SystemCategoryKey.cashback, kind: .income, name: Phrase(ru: "Кэшбэк", uz: "Keshbek", en: "Cashback"), icon: "arrow.uturn.backward.circle.fill", color: .cyan, mandatory: false),
        Spec(key: SystemCategoryKey.interest, kind: .income, name: Phrase(ru: "Проценты", uz: "Foizlar", en: "Interest"), icon: "percent", color: .mint, mandatory: false),
        Spec(key: SystemCategoryKey.giftsIncome, kind: .income, name: Phrase(ru: "Подарки", uz: "Sovg‘alar", en: "Gifts received"), icon: "gift.fill", color: .magenta, mandatory: false),
        Spec(key: SystemCategoryKey.debtReturn, kind: .income, name: Phrase(ru: "Возврат долга", uz: "Qarz qaytarildi", en: "Debt repaid"), icon: "arrow.down.left.circle.fill", color: .sky, mandatory: false),
        Spec(key: SystemCategoryKey.sale, kind: .income, name: Phrase(ru: "Продажа вещей", uz: "Sotuv", en: "Sales"), icon: "tag.fill", color: .tangerine, mandatory: false),
        Spec(key: SystemCategoryKey.otherIncome, kind: .income, name: Phrase(ru: "Прочие доходы", uz: "Boshqa daromadlar", en: "Other income"), icon: "plus.circle.fill", color: .steel, mandatory: false)
    ]

    /// Детерминированный UUID для встроенной категории.
    public static func id(for key: String) -> UUID {
        StableID.make(namespace: "category", key: key)
    }

    public static func make(language: AppLanguage) -> [FinanceCategory] {
        specs.enumerated().map { index, spec in
            FinanceCategory(
                id: id(for: spec.key),
                name: spec.name(language),
                kind: spec.kind,
                icon: spec.icon,
                color: spec.color,
                isMandatory: spec.mandatory,
                systemKey: spec.key,
                sortOrder: index
            )
        }
    }
}

/// Детерминированные UUID (FNV-1a → формат UUID v8-подобный). Только для встроенных сущностей.
public enum StableID {
    public static func make(namespace: String, key: String) -> UUID {
        let bytes = Array((namespace + ":" + key).utf8)
        var h1: UInt64 = 0xcbf29ce484222325
        var h2: UInt64 = 0x84222325cbf29ce4
        for byte in bytes {
            h1 = (h1 ^ UInt64(byte)) &* 0x100000001b3
            h2 = (h2 ^ UInt64(byte)) &* 0x100000001b3 &+ 0x9e3779b97f4a7c15
        }
        var raw = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            raw[i] = UInt8(truncatingIfNeeded: h1 >> (UInt64(i) * 8))
            raw[8 + i] = UInt8(truncatingIfNeeded: h2 >> (UInt64(i) * 8))
        }
        raw[6] = (raw[6] & 0x0F) | 0x80   // версия 8 (кастомная)
        raw[8] = (raw[8] & 0x3F) | 0x80   // вариант RFC 4122
        let tuple = (raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
                     raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15])
        return UUID(uuid: tuple)
    }
}
