import Foundation
import MonoCore

/// Фильтр истории операций.
struct TransactionFilter: Hashable {
    var query = ""
    var kinds: Set<TransactionKind> = []
    var accountID: UUID?
    var categoryID: UUID?
    var range: DateRange?
    var source: TransactionSource?
    var minAmount: Decimal?
    var maxAmount: Decimal?

    init(query: String = "", kinds: Set<TransactionKind> = [], accountID: UUID? = nil, categoryID: UUID? = nil,
         range: DateRange? = nil, source: TransactionSource? = nil, minAmount: Decimal? = nil, maxAmount: Decimal? = nil) {
        self.query = query
        self.kinds = kinds
        self.accountID = accountID
        self.categoryID = categoryID
        self.range = range
        self.source = source
        self.minAmount = minAmount
        self.maxAmount = maxAmount
    }

    var isActive: Bool {
        !kinds.isEmpty || accountID != nil || categoryID != nil || range != nil || source != nil || minAmount != nil || maxAmount != nil
    }

    var activeCount: Int {
        [!kinds.isEmpty, accountID != nil, categoryID != nil, range != nil, source != nil, minAmount != nil || maxAmount != nil].filter { $0 }.count
    }

    /// Проверка операции. Поиск идёт по продавцу, заметке, тегам, категории, счёту и сумме.
    func matches(_ transaction: FinanceTransaction, categories: [UUID: FinanceCategory], accounts: [UUID: Account]) -> Bool {
        if !kinds.isEmpty && !kinds.contains(transaction.kind) { return false }
        if let accountID, !transaction.involves(account: accountID) { return false }
        if let categoryID, transaction.categoryID != categoryID { return false }
        if let range, !range.contains(transaction.date) { return false }
        if let source, transaction.source != source { return false }
        let magnitude = transaction.amount.magnitude.majorValue
        if let minAmount, magnitude < minAmount { return false }
        if let maxAmount, magnitude > maxAmount { return false }
        let needle = TextNormalizer.fold(query)
        guard !needle.isEmpty else { return true }
        var haystack = transaction.searchableText
        if let id = transaction.categoryID, let category = categories[id] { haystack += " " + TextNormalizer.fold(category.name) }
        if let account = accounts[transaction.accountID] { haystack += " " + TextNormalizer.fold(account.displayName + " " + account.bank.displayName) }
        haystack += " " + "\(transaction.amount.magnitude.majorValue)"
        let latinNeedle = TextNormalizer.transliterate(needle)
        return haystack.contains(needle) || TextNormalizer.transliterate(haystack).contains(latinNeedle)
    }
}
