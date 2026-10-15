import Foundation
import MonoCore

/// Предложение категории с объяснением, откуда оно взялось.
public struct CategorySuggestion: Equatable, Sendable {
    public enum Reason: String, Sendable {
        /// Пользователь раньше выбирал эту категорию для продавца.
        case learned
        /// Известный продавец из справочника.
        case merchantDirectory
        /// Ключевые слова в описании или речи.
        case keyword
    }

    public var categoryID: UUID
    public var reason: Reason
    public var confidence: Double
}

/// Локальная категоризация без обращения к сети:
/// 1) выученные правила пользователя, 2) справочник продавцов, 3) ключевые слова.
public struct CategorizationEngine: Sendable {
    public let categories: [FinanceCategory]
    private let learned: [String: UUID]
    private let bySystemKey: [String: FinanceCategory]

    public init(categories: [FinanceCategory], rules: [MerchantRule]) {
        self.categories = categories
        var learned: [String: UUID] = [:]
        let active = Set(categories.filter { !$0.isArchived }.map(\.id))
        for rule in rules where active.contains(rule.categoryID) {
            learned[rule.key] = rule.categoryID
        }
        self.learned = learned
        var map: [String: FinanceCategory] = [:]
        for category in categories where !category.isArchived {
            if let key = category.systemKey { map[key] = category }
        }
        self.bySystemKey = map
    }

    /// Ключ для обучения: каноническое имя известного продавца или нормализованное название.
    public static func learningKey(for merchant: String) -> String {
        if let match = MerchantDirectory.firstMatch(in: merchant) {
            return MerchantNormalizer.key(match.entry.name)
        }
        return MerchantNormalizer.key(merchant)
    }

    /// Каноническое имя продавца, если он известен справочнику: «в корзинке» → «Korzinka».
    public static func canonicalMerchantName(_ text: String) -> String? {
        MerchantDirectory.firstMatch(in: text)?.entry.name
    }

    public func category(forSystemKey key: String) -> FinanceCategory? { bySystemKey[key] }

    public func suggest(merchant: String?, text: String?, kind: TransactionKind) -> CategorySuggestion? {
        guard let categoryKind = kind.categoryKind else { return nil }

        if let merchant, !merchant.isEmpty {
            let key = Self.learningKey(for: merchant)
            if let id = learned[key], categories.first(where: { $0.id == id })?.kind == categoryKind {
                return CategorySuggestion(categoryID: id, reason: .learned, confidence: 0.95)
            }
        }

        let combined = [merchant ?? "", text ?? ""].joined(separator: " ")
        let words = TextNormalizer.words(combined)

        // Выученные правила срабатывают и по тексту: «в Корзинке» → ключ «korzinka».
        if let match = MerchantDirectory.firstMatch(in: words) {
            let key = MerchantNormalizer.key(match.entry.name)
            if let id = learned[key], categories.first(where: { $0.id == id })?.kind == categoryKind {
                return CategorySuggestion(categoryID: id, reason: .learned, confidence: 0.95)
            }
            if categoryKind == .expense, let category = bySystemKey[match.entry.categoryKey], category.kind == .expense {
                return CategorySuggestion(categoryID: category.id, reason: .merchantDirectory, confidence: 0.85)
            }
        }

        if let best = CategoryKeywords.bestKey(words: words, kind: categoryKind), let category = bySystemKey[best.key] {
            return CategorySuggestion(categoryID: category.id, reason: .keyword, confidence: best.hits >= 2 ? 0.8 : 0.65)
        }

        // Совпадение по названию пользовательской категории: «на хобби» → «Хобби».
        for category in categories where !category.isArchived && category.kind == categoryKind && category.systemKey == nil {
            let nameWords = TextNormalizer.words(category.name).filter { $0.count >= 4 }
            for nameWord in nameWords {
                let stem = String(nameWord.prefix(max(4, nameWord.count - 2)))
                if words.contains(where: { $0.hasPrefix(stem) }) {
                    return CategorySuggestion(categoryID: category.id, reason: .keyword, confidence: 0.6)
                }
            }
        }
        return nil
    }
}
