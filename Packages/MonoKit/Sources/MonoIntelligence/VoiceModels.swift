import Foundation
import MonoCore

/// Что нужно проверить или уточнить в голосовом черновике.
public enum VoiceIssue: Hashable, Sendable {
    /// Сумма не распознана.
    case missingAmount
    /// «на 300» без «тысяч»: скорее всего имелось в виду 300 000.
    case amountMayNeedThousands(suggested: Decimal)
    /// Названная валюта не совпадает с валютой счёта.
    case currencyMismatch(spoken: Currency, account: Currency)
    /// Счёт не назван — подставлен счёт по умолчанию (показывается явно).
    case usedDefaultAccount
    /// Счёт выбран по названной валюте (единственный счёт в этой валюте).
    case accountInferredFromCurrency
    /// Упоминание подходит нескольким счетам.
    case ambiguousAccount(candidates: [UUID])
    /// Названный банк/счёт не найден среди счетов.
    case accountNotFound(mention: String)
    /// Нет ни названного счёта, ни счёта по умолчанию.
    case missingAccount
    /// Перевод без счёта-получателя.
    case missingDestination
    /// Перевод на тот же счёт.
    case sameAccount
    /// Перевод между валютами: нужна сумма зачисления (есть подсказка по курсу ЦБ, если курс известен).
    case needsCounterAmount(suggested: Decimal?)
    /// Категорию определить не удалось.
    case categoryUncertain

    /// Блокирует сохранение, пока пользователь не уточнит.
    public var isBlocking: Bool {
        switch self {
        case .usedDefaultAccount, .accountInferredFromCurrency, .categoryUncertain: return false
        default: return true
        }
    }

    public func message(_ language: AppLanguage, formatter: MoneyFormatter? = nil, currency: Currency = .uzs) -> String {
        let f = formatter ?? MoneyFormatter(language: language)
        switch self {
        case .missingAmount:
            return Phrase(ru: "Не расслышал сумму — введите её.", uz: "Summa aniqlanmadi.", en: "Couldn't catch the amount.")(language)
        case .amountMayNeedThousands(let suggested):
            let text = Money(major: suggested, currency: currency).map { f.string($0) } ?? "\(suggested)"
            return Phrase(ru: "Возможно, имелось в виду \(text)?", uz: "Balki \(text)?", en: "Did you mean \(text)?")(language)
        case .currencyMismatch(let spoken, let account):
            return Phrase(ru: "Названа валюта \(spoken.code), а счёт в \(account.code). Выберите счёт в \(spoken.code).",
                          uz: "\(spoken.code) valyutasi aytildi, hisob esa \(account.code) da.",
                          en: "You said \(spoken.code), but the account is in \(account.code).")(language)
        case .usedDefaultAccount:
            return Phrase(ru: "Счёт не назван — выбран счёт по умолчанию.", uz: "Hisob aytilmadi — asosiy hisob tanlandi.", en: "No account mentioned — default account used.")(language)
        case .accountInferredFromCurrency:
            return Phrase(ru: "Счёт выбран по валюте.", uz: "Hisob valyuta bo‘yicha tanlandi.", en: "Account chosen by currency.")(language)
        case .ambiguousAccount:
            return Phrase(ru: "Подходит несколько счетов — уточните.", uz: "Bir nechta hisob mos keladi.", en: "Several accounts match — pick one.")(language)
        case .accountNotFound(let mention):
            return Phrase(ru: "Счёт «\(mention)» не найден.", uz: "«\(mention)» hisobi topilmadi.", en: "Account “\(mention)” not found.")(language)
        case .missingAccount:
            return Phrase(ru: "Выберите счёт.", uz: "Hisobni tanlang.", en: "Choose an account.")(language)
        case .missingDestination:
            return Phrase(ru: "Куда перевести? Выберите счёт получателя.", uz: "Qaysi hisobga?", en: "Where to? Choose the destination.")(language)
        case .sameAccount:
            return Phrase(ru: "Счета списания и зачисления совпадают.", uz: "Hisoblar bir xil.", en: "Source and destination are the same.")(language)
        case .needsCounterAmount:
            return Phrase(ru: "Перевод между валютами — укажите сумму зачисления.", uz: "Kiritiladigan summani ko‘rsating.", en: "Cross-currency transfer — enter the received amount.")(language)
        case .categoryUncertain:
            return Phrase(ru: "Категория не определена.", uz: "Kategoriya aniqlanmadi.", en: "Category not detected.")(language)
        }
    }
}

/// Черновик операции из голосовой фразы. Сохраняется только после подтверждения пользователем.
public struct VoiceDraft: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: TransactionKind
    /// Сумма в основных единицах.
    public var amount: Decimal?
    public var currency: Currency
    public var accountID: UUID?
    public var counterAccountID: UUID?
    /// Сумма зачисления для перевода между валютами.
    public var counterAmount: Decimal?
    public var categoryID: UUID?
    public var merchant: String?
    public var date: Date
    public var note: String?
    /// Фрагмент фразы, из которого получен черновик.
    public var sourceText: String
    public var issues: [VoiceIssue]

    public init(
        id: UUID = UUID(),
        kind: TransactionKind,
        amount: Decimal?,
        currency: Currency,
        accountID: UUID?,
        counterAccountID: UUID? = nil,
        counterAmount: Decimal? = nil,
        categoryID: UUID?,
        merchant: String?,
        date: Date,
        note: String? = nil,
        sourceText: String,
        issues: [VoiceIssue]
    ) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.accountID = accountID
        self.counterAccountID = counterAccountID
        self.counterAmount = counterAmount
        self.categoryID = categoryID
        self.merchant = merchant
        self.date = date
        self.note = note
        self.sourceText = sourceText
        self.issues = issues
    }

    public var blockingIssues: [VoiceIssue] { issues.filter(\.isBlocking) }

    /// Пользователь выбрал счёт списания (или зачисления для дохода): снимаем вопросы по счёту.
    public mutating func selectAccount(_ id: UUID, accounts: [UUID: Account], converter: CurrencyConverter?) {
        accountID = id
        if let account = accounts[id] { currency = account.currency }
        issues.removeAll {
            switch $0 {
            case .ambiguousAccount, .accountNotFound, .usedDefaultAccount, .accountInferredFromCurrency: return true
            default: return false
            }
        }
        revalidate(accounts: accounts, converter: converter)
    }

    /// Пользователь выбрал счёт получателя перевода.
    public mutating func selectDestination(_ id: UUID, accounts: [UUID: Account], converter: CurrencyConverter?) {
        counterAccountID = id
        counterAmount = nil
        issues.removeAll {
            if case .accountNotFound = $0 { return true }
            if case .ambiguousAccount = $0 { return true }
            return false
        }
        revalidate(accounts: accounts, converter: converter)
    }

    /// Пользователь подтвердил или ввёл сумму.
    public mutating func setAmount(_ value: Decimal, accounts: [UUID: Account], converter: CurrencyConverter?) {
        amount = value
        issues.removeAll {
            if case .amountMayNeedThousands = $0 { return true }
            return false
        }
        revalidate(accounts: accounts, converter: converter)
    }

    public mutating func setCategory(_ id: UUID?) {
        categoryID = id
        if id != nil { issues.removeAll { $0 == .categoryUncertain } }
    }

    /// Пересчитывает проблемы, зависящие от выбранных счетов (после правок пользователя).
    public mutating func revalidate(accounts: [UUID: Account], converter: CurrencyConverter?) {
        var kept = issues.filter {
            switch $0 {
            case .categoryUncertain, .usedDefaultAccount, .accountInferredFromCurrency, .amountMayNeedThousands,
                 .ambiguousAccount, .accountNotFound:
                return true
            default:
                return false
            }
        }
        if categoryID != nil { kept.removeAll { $0 == .categoryUncertain } }
        if amount == nil || amount! <= 0 { kept.append(.missingAmount) }
        guard let accountID, let account = accounts[accountID] else {
            let explained = kept.contains {
                if case .accountNotFound = $0 { return true }
                return false
            }
            if !explained { kept.append(.missingAccount) }
            issues = kept
            return
        }
        if account.currency != currency {
            kept.append(.currencyMismatch(spoken: currency, account: account.currency))
        }
        if kind == .transfer {
            if let destinationID = counterAccountID, let destination = accounts[destinationID] {
                if destinationID == accountID {
                    kept.append(.sameAccount)
                } else if destination.currency != account.currency && (counterAmount ?? 0) <= 0 {
                    let suggestion = amount.flatMap { value in
                        Money(major: value, currency: account.currency).flatMap { converter?.convert($0, to: destination.currency) }?.majorValue
                    }
                    kept.append(.needsCounterAmount(suggested: suggestion))
                }
            } else {
                kept.append(.missingDestination)
            }
        }
        issues = kept
    }

    /// Готов ли черновик к сохранению.
    public var isReady: Bool { blockingIssues.isEmpty && amount != nil && accountID != nil }

    /// Превращает готовый черновик в операцию.
    public func makeTransaction(accounts: [UUID: Account], now: Date = Date()) -> FinanceTransaction? {
        guard isReady, let amount, let accountID, let account = accounts[accountID],
              let money = Money(major: amount, currency: account.currency), money.isPositive else { return nil }
        var counterMoney: Money?
        if kind == .transfer {
            guard let destinationID = counterAccountID, let destination = accounts[destinationID] else { return nil }
            if destination.currency == account.currency {
                counterMoney = money
            } else {
                guard let counter = counterAmount, let value = Money(major: counter, currency: destination.currency) else { return nil }
                counterMoney = value
            }
        }
        return FinanceTransaction(
            id: id,
            kind: kind,
            amount: money,
            accountID: accountID,
            counterAccountID: kind == .transfer ? counterAccountID : nil,
            counterAmount: counterMoney,
            categoryID: kind.usesCategory ? categoryID : nil,
            merchant: kind == .transfer ? nil : merchant,
            note: note,
            date: date,
            createdAt: now,
            source: .voice
        )
    }
}

/// Результат разбора фразы.
public struct VoiceParseResult: Sendable, Equatable {
    public var transcript: String
    public var drafts: [VoiceDraft]

    public var isEmpty: Bool { drafts.isEmpty }
}
