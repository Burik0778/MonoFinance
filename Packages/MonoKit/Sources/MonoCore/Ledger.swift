import Foundation

/// Изменение баланса одного счёта.
public struct BalanceEffect: Hashable, Sendable {
    public let accountID: UUID
    public let delta: Money

    public init(accountID: UUID, delta: Money) {
        self.accountID = accountID
        self.delta = delta
    }
}

/// Нарушение финансовых правил при создании или изменении операции.
public enum LedgerError: Error, Equatable, Sendable {
    case amountMustBePositive
    case adjustmentMustBeNonZero
    case amountOutOfRange
    case unknownAccount(UUID)
    case archivedAccount(UUID)
    case currencyMismatch(expected: Currency, actual: Currency)
    case transferNeedsDestination
    case transferToSameAccount
    case transferNeedsCounterAmount
    case counterCurrencyMismatch(expected: Currency, actual: Currency)
    case sameCurrencyTransferAmountsDiffer
    case unexpectedCounterAccount
    case unknownCategory(UUID)
    case categoryKindMismatch
    case categoryNotAllowed

    public func message(_ language: AppLanguage) -> String {
        switch self {
        case .amountMustBePositive:
            return Phrase(ru: "Сумма должна быть больше нуля.", uz: "Summa noldan katta bo‘lishi kerak.", en: "Amount must be greater than zero.")(language)
        case .adjustmentMustBeNonZero:
            return Phrase(ru: "Корректировка не может быть нулевой.", uz: "Tuzatish nol bo‘lishi mumkin emas.", en: "Adjustment can't be zero.")(language)
        case .amountOutOfRange:
            return Phrase(ru: "Сумма слишком велика.", uz: "Summa juda katta.", en: "Amount is too large.")(language)
        case .unknownAccount:
            return Phrase(ru: "Счёт не найден.", uz: "Hisob topilmadi.", en: "Account not found.")(language)
        case .archivedAccount:
            return Phrase(ru: "Счёт в архиве — новые операции на нём недоступны.", uz: "Hisob arxivda.", en: "The account is archived.")(language)
        case .currencyMismatch(let expected, let actual):
            return Phrase(ru: "Валюта операции (\(actual.code)) не совпадает с валютой счёта (\(expected.code)).",
                          uz: "Operatsiya valyutasi (\(actual.code)) hisob valyutasiga (\(expected.code)) mos emas.",
                          en: "FinanceTransaction currency (\(actual.code)) doesn't match the account (\(expected.code)).")(language)
        case .transferNeedsDestination:
            return Phrase(ru: "Укажите счёт получателя.", uz: "Qabul qiluvchi hisobni tanlang.", en: "Choose the destination account.")(language)
        case .transferToSameAccount:
            return Phrase(ru: "Нельзя перевести на тот же счёт.", uz: "Xuddi shu hisobga o‘tkazib bo‘lmaydi.", en: "Can't transfer to the same account.")(language)
        case .transferNeedsCounterAmount:
            return Phrase(ru: "Укажите сумму зачисления.", uz: "Kiritiladigan summani ko‘rsating.", en: "Enter the received amount.")(language)
        case .counterCurrencyMismatch(let expected, let actual):
            return Phrase(ru: "Сумма зачисления должна быть в \(expected.code), а не в \(actual.code).",
                          uz: "Kiritiladigan summa \(expected.code) da bo‘lishi kerak.",
                          en: "Received amount must be in \(expected.code), not \(actual.code).")(language)
        case .sameCurrencyTransferAmountsDiffer:
            return Phrase(ru: "При переводе в одной валюте суммы списания и зачисления совпадают. Разницу оформите комиссией.",
                          uz: "Bir valyutadagi o‘tkazmada summalar teng bo‘lishi kerak. Farqni komissiya sifatida kiriting.",
                          en: "Same-currency transfer amounts must match. Record the difference as a fee.")(language)
        case .unexpectedCounterAccount:
            return Phrase(ru: "Счёт получателя указывается только для перевода.", uz: "Qabul qiluvchi faqat o‘tkazma uchun.", en: "Destination applies only to transfers.")(language)
        case .unknownCategory:
            return Phrase(ru: "Категория не найдена.", uz: "Kategoriya topilmadi.", en: "FinanceCategory not found.")(language)
        case .categoryKindMismatch:
            return Phrase(ru: "Категория не подходит для этого типа операции.", uz: "Kategoriya mos emas.", en: "FinanceCategory doesn't fit this transaction type.")(language)
        case .categoryNotAllowed:
            return Phrase(ru: "Для переводов, комиссий и корректировок категория не используется.", uz: "Bu turdagi operatsiya uchun kategoriya ishlatilmaydi.", en: "This transaction type has no category.")(language)
        }
    }
}

/// Правила двойной записи MONO: как операции меняют балансы и что считается корректной операцией.
public enum Ledger {
    /// Влияние операции на балансы счетов.
    public static func effects(of transaction: FinanceTransaction) -> [BalanceEffect] {
        switch transaction.kind {
        case .expense, .fee:
            return [BalanceEffect(accountID: transaction.accountID, delta: transaction.amount.magnitude.negated)]
        case .income, .refund:
            return [BalanceEffect(accountID: transaction.accountID, delta: transaction.amount.magnitude)]
        case .adjustment:
            return [BalanceEffect(accountID: transaction.accountID, delta: transaction.amount)]
        case .transfer:
            var result = [BalanceEffect(accountID: transaction.accountID, delta: transaction.amount.magnitude.negated)]
            if let destination = transaction.counterAccountID {
                let received = transaction.counterAmount ?? transaction.amount
                result.append(BalanceEffect(accountID: destination, delta: received.magnitude))
            }
            return result
        }
    }

    /// Балансы всех счетов: сумма эффектов всех операций. Счета без операций получают ноль.
    public static func balances(accounts: [Account], transactions: [FinanceTransaction]) -> [UUID: Money] {
        var result: [UUID: Money] = [:]
        for account in accounts {
            result[account.id] = .zero(account.currency)
        }
        for transaction in transactions {
            for effect in effects(of: transaction) {
                if let current = result[effect.accountID] {
                    if let sum = current.adding(effect.delta) {
                        result[effect.accountID] = sum
                    }
                } else {
                    result[effect.accountID] = effect.delta
                }
            }
        }
        return result
    }

    /// Баланс счёта на конец указанного момента (включительно).
    public static func balance(of account: Account, transactions: [FinanceTransaction], asOf date: Date) -> Money {
        var total = Money.zero(account.currency)
        for transaction in transactions where transaction.date <= date {
            for effect in effects(of: transaction) where effect.accountID == account.id {
                if let sum = total.adding(effect.delta) { total = sum }
            }
        }
        return total
    }

    /// Проверка операции перед записью.
    /// - Parameter isNew: для новых операций запрещены архивные счета.
    public static func validate(
        _ transaction: FinanceTransaction,
        accounts: [UUID: Account],
        categories: [UUID: FinanceCategory],
        isNew: Bool
    ) throws {
        guard let account = accounts[transaction.accountID] else {
            throw LedgerError.unknownAccount(transaction.accountID)
        }
        if isNew && account.isArchived { throw LedgerError.archivedAccount(account.id) }
        guard transaction.amount.isWithinLimits else { throw LedgerError.amountOutOfRange }
        guard transaction.amount.currency == account.currency else {
            throw LedgerError.currencyMismatch(expected: account.currency, actual: transaction.amount.currency)
        }

        switch transaction.kind {
        case .adjustment:
            guard !transaction.amount.isZero else { throw LedgerError.adjustmentMustBeNonZero }
        default:
            guard transaction.amount.isPositive else { throw LedgerError.amountMustBePositive }
        }

        if transaction.kind == .transfer {
            guard let destinationID = transaction.counterAccountID else { throw LedgerError.transferNeedsDestination }
            guard destinationID != account.id else { throw LedgerError.transferToSameAccount }
            guard let destination = accounts[destinationID] else { throw LedgerError.unknownAccount(destinationID) }
            if isNew && destination.isArchived { throw LedgerError.archivedAccount(destinationID) }
            guard let received = transaction.counterAmount else { throw LedgerError.transferNeedsCounterAmount }
            guard received.currency == destination.currency else {
                throw LedgerError.counterCurrencyMismatch(expected: destination.currency, actual: received.currency)
            }
            guard received.isPositive else { throw LedgerError.amountMustBePositive }
            guard received.isWithinLimits else { throw LedgerError.amountOutOfRange }
            if received.currency == transaction.amount.currency && received != transaction.amount {
                throw LedgerError.sameCurrencyTransferAmountsDiffer
            }
        } else if transaction.counterAccountID != nil || transaction.counterAmount != nil {
            throw LedgerError.unexpectedCounterAccount
        }

        if let categoryID = transaction.categoryID {
            guard transaction.kind.usesCategory else { throw LedgerError.categoryNotAllowed }
            guard let category = categories[categoryID] else { throw LedgerError.unknownCategory(categoryID) }
            if let expected = transaction.kind.categoryKind, category.kind != expected {
                throw LedgerError.categoryKindMismatch
            }
        }
    }

    /// Сумма всех балансов по валютам. Переводы в одной валюте сохраняют её неизменной.
    public static func totalsByCurrency(_ balances: [UUID: Money]) -> [Currency: Money] {
        var totals: [Currency: Money] = [:]
        for money in balances.values {
            totals[money.currency] = (totals[money.currency] ?? .zero(money.currency)) + money
        }
        return totals
    }
}
