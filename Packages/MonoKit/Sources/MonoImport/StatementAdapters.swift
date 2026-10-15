import Foundation
import MonoCore

/// Адаптер формата выписки конкретного банка.
///
/// Сейчас зарегистрирован только универсальный адаптер. Адаптеры Kapitalbank, Uzum Bank, Orient Finans Bank
/// и Trastbank добавляются по реальным образцам выписок: без образца формат считается непроверенным и
/// приложение не заявляет его поддержку. До этого используется универсальный разбор + сохранённые профили
/// сопоставления (после первого ручного сопоставления файл того же формата импортируется автоматически).
public protocol StatementAdapter: Sendable {
    var id: String { get }
    var bank: Bank? { get }
    /// Проверен ли формат на реальном образце.
    var isVerified: Bool { get }
    /// Подходит ли адаптер к таблице (обычно по заголовкам).
    func matches(_ table: ImportTable) -> Bool
    func mapping(for table: ImportTable, calendar: Calendar) -> ColumnMapping
}

/// Универсальный адаптер: поиск заголовков и ролей колонок по словарю и содержимому.
public struct GenericStatementAdapter: StatementAdapter {
    public let id = "generic"
    public let bank: Bank? = nil
    public let isVerified = false

    public init() {}

    public func matches(_ table: ImportTable) -> Bool { true }

    public func mapping(for table: ImportTable, calendar: Calendar) -> ColumnMapping {
        ColumnDetector.suggestMapping(for: table, calendar: calendar)
    }
}

public enum StatementAdapterRegistry {
    /// Порядок важен: специализированные адаптеры раньше универсального.
    public static let adapters: [any StatementAdapter] = [GenericStatementAdapter()]

    public static func adapter(for table: ImportTable) -> any StatementAdapter {
        adapters.first { $0.matches(table) } ?? GenericStatementAdapter()
    }

    /// Банки, для которых формат выписки проверен на реальных файлах.
    public static var verifiedBanks: [Bank] {
        adapters.filter(\.isVerified).compactMap(\.bank)
    }
}
