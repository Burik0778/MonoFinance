import Foundation

/// Тип операции. Влияние на балансы задаёт `Ledger.effects(of:)`.
public enum TransactionKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Расход: счёт −сумма.
    case expense
    /// Доход: счёт +сумма.
    case income
    /// Перевод между своими счетами: источник −сумма, получатель +встречная сумма. Не доход и не расход.
    case transfer
    /// Комиссия банка: счёт −сумма. Учитывается отдельно от расходов по категориям.
    case fee
    /// Возврат покупки: счёт +сумма, уменьшает расходы своей категории.
    case refund
    /// Корректировка баланса (в т.ч. начальный остаток): знаковая сумма, не доход и не расход.
    case adjustment

    public var id: String { rawValue }

    public var title: Phrase {
        switch self {
        case .expense: return Phrase(ru: "Расход", uz: "Xarajat", en: "Expense")
        case .income: return Phrase(ru: "Доход", uz: "Daromad", en: "Income")
        case .transfer: return Phrase(ru: "Перевод", uz: "O‘tkazma", en: "Transfer")
        case .fee: return Phrase(ru: "Комиссия", uz: "Komissiya", en: "Fee")
        case .refund: return Phrase(ru: "Возврат", uz: "Qaytarish", en: "Refund")
        case .adjustment: return Phrase(ru: "Корректировка", uz: "Tuzatish", en: "Adjustment")
        }
    }

    /// Нужна ли категория для этого типа.
    public var usesCategory: Bool {
        switch self {
        case .expense, .income, .refund: return true
        case .transfer, .fee, .adjustment: return false
        }
    }

    /// Ожидаемый тип категории.
    public var categoryKind: CategoryKind? {
        switch self {
        case .expense, .refund: return .expense
        case .income: return .income
        default: return nil
        }
    }
}

/// Откуда появилась запись.
public enum TransactionSource: String, Codable, Sendable, CaseIterable {
    case manual
    case voice
    case importFile
    case recurring
    case shortcut
    case demo
}

/// Финансовая операция.
public struct FinanceTransaction: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: TransactionKind
    /// Сумма в валюте счёта. Положительная для всех типов, кроме `adjustment` (знаковая, ненулевая).
    public var amount: Money
    public var accountID: UUID
    /// Счёт-получатель (только для перевода).
    public var counterAccountID: UUID?
    /// Сумма, зачисленная на счёт-получатель (в его валюте). Для перевода в одной валюте равна `amount`.
    public var counterAmount: Money?
    public var categoryID: UUID?
    public var merchant: String?
    public var note: String?
    public var tags: [String]
    public var date: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var source: TransactionSource
    /// Отпечаток импортированной строки — защита от повторного импорта (уникален в базе).
    public var importFingerprint: String?
    /// Имя файла чека в каталоге вложений.
    public var receiptFileName: String?
    /// Связанная операция: комиссия → перевод/покупка, возврат → исходная покупка.
    public var linkedTransactionID: UUID?
    public var recurringRuleID: UUID?
    /// Начальный остаток счёта (особый вид корректировки).
    public var isOpeningBalance: Bool

    public init(
        id: UUID = UUID(),
        kind: TransactionKind,
        amount: Money,
        accountID: UUID,
        counterAccountID: UUID? = nil,
        counterAmount: Money? = nil,
        categoryID: UUID? = nil,
        merchant: String? = nil,
        note: String? = nil,
        tags: [String] = [],
        date: Date,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        source: TransactionSource = .manual,
        importFingerprint: String? = nil,
        receiptFileName: String? = nil,
        linkedTransactionID: UUID? = nil,
        recurringRuleID: UUID? = nil,
        isOpeningBalance: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.accountID = accountID
        self.counterAccountID = counterAccountID
        self.counterAmount = counterAmount
        self.categoryID = categoryID
        self.merchant = merchant
        self.note = note
        self.tags = tags
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.source = source
        self.importFingerprint = importFingerprint
        self.receiptFileName = receiptFileName
        self.linkedTransactionID = linkedTransactionID
        self.recurringRuleID = recurringRuleID
        self.isOpeningBalance = isOpeningBalance
    }

    /// Затрагивает ли операция счёт.
    public func involves(account id: UUID) -> Bool {
        accountID == id || counterAccountID == id
    }

    /// Текст для поиска: продавец, заметка, теги.
    public var searchableText: String {
        TextNormalizer.fold([merchant ?? "", note ?? "", tags.joined(separator: " ")].joined(separator: " "))
    }
}
