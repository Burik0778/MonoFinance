import Foundation

/// Выученное правило: нормализованный ключ продавца → категория.
/// Появляется, когда пользователь исправляет категорию, и имеет приоритет над встроенными правилами.
public struct MerchantRule: Hashable, Codable, Sendable, Identifiable {
    public var key: String
    public var categoryID: UUID
    public var hits: Int
    public var updatedAt: Date

    public var id: String { key }

    public init(key: String, categoryID: UUID, hits: Int = 1, updatedAt: Date = Date()) {
        self.key = key
        self.categoryID = categoryID
        self.hits = hits
        self.updatedAt = updatedAt
    }
}
