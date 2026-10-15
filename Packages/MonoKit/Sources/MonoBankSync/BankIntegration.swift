import Foundation
import MonoCore

/// Доступность автоматической синхронизации.
public enum SyncAvailability: Equatable, Sendable {
    /// Официальный канал доступа подключён и работает.
    case available
    /// Официального доступа для личного использования нет — используйте импорт выписки.
    case unavailable(reason: Phrase)

    public static func == (lhs: SyncAvailability, rhs: SyncAvailability) -> Bool {
        switch (lhs, rhs) {
        case (.available, .available): return true
        case (.unavailable(let a), .unavailable(let b)): return a.ru == b.ru
        default: return false
        }
    }
}

/// Состояние последней синхронизации.
public enum SyncStatus: Equatable, Sendable {
    case never
    case syncing
    case succeeded(at: Date, imported: Int)
    case failed(at: Date, error: BankSyncError)
}

public enum BankSyncError: Error, Equatable, Sendable {
    case notAvailable
    case authorizationRequired
    case authorizationExpired
    case rateLimited(retryAfter: TimeInterval?)
    case network
    case invalidResponse
    case bankError(code: String)
}

/// Данные счёта, полученные от банка.
public struct RemoteAccount: Equatable, Sendable {
    public var remoteID: String
    public var name: String
    public var currency: Currency
    public var maskedNumber: String?
}

/// Операция, полученная от банка. `remoteID` используется как отпечаток против повторного импорта.
public struct RemoteTransaction: Equatable, Sendable {
    public var remoteID: String
    public var accountRemoteID: String
    public var date: Date
    /// Знаковая сумма: отрицательная — списание.
    public var amount: Money
    public var description: String
    public var merchant: String?

    /// Отпечаток для `FinanceTransaction.importFingerprint`.
    public func fingerprint(bank: Bank) -> String { "\(bank.rawValue)|remote|\(remoteID)" }
}

/// Интерфейс адаптера банка. Каждый банк — отдельный адаптер.
///
/// Правила: только официальные каналы (Open Banking/API банка с согласия клиента). Никакого обхода авторизации,
/// перехвата токенов или хранения банковских паролей. Если официального доступа нет — `availability` честно
/// возвращает `.unavailable`, а приложение предлагает импорт выписки.
public protocol BankIntegration: Sendable {
    var bank: Bank { get }
    var availability: SyncAvailability { get }
    func fetchAccounts() async throws -> [RemoteAccount]
    func fetchBalances() async throws -> [String: Money]
    func fetchTransactions(accountRemoteID: String, since: Date) async throws -> [RemoteTransaction]
}

/// Адаптер без официального канала доступа. Не имитирует подключение: все запросы завершаются ошибкой `.notAvailable`.
public struct UnavailableBankIntegration: BankIntegration {
    public let bank: Bank

    public init(bank: Bank) {
        self.bank = bank
    }

    public var availability: SyncAvailability {
        .unavailable(reason: Phrase(
            ru: "Автоматическая синхронизация недоступна: официальный доступ к данным \(bank.displayName) для личного использования не подключён. Используйте импорт выписки CSV или XLSX.",
            uz: "Avtomatik sinxronlash mavjud emas: \(bank.displayName) ma’lumotlariga rasmiy kirish ulanmagan. Ko‘chirmani CSV yoki XLSX orqali import qiling.",
            en: "Automatic sync is unavailable: official data access for \(bank.displayName) isn't connected. Import a CSV or XLSX statement instead."
        ))
    }

    public func fetchAccounts() async throws -> [RemoteAccount] { throw BankSyncError.notAvailable }
    public func fetchBalances() async throws -> [String: Money] { throw BankSyncError.notAvailable }
    public func fetchTransactions(accountRemoteID: String, since: Date) async throws -> [RemoteTransaction] { throw BankSyncError.notAvailable }
}

/// Реестр адаптеров. Когда у банка появится официальный API, его адаптер заменит `UnavailableBankIntegration`.
public enum BankIntegrationRegistry {
    public static func integration(for bank: Bank) -> any BankIntegration {
        UnavailableBankIntegration(bank: bank)
    }

    public static var supportedBanks: [Bank] { [.kapitalbank, .uzum, .orientFinans, .trastbank] }
}

/// Превращает операции банка в черновики с отпечатками; повторно полученные операции отсекаются.
public enum RemoteTransactionMapper {
    public static func transactions(
        from remote: [RemoteTransaction],
        bank: Bank,
        account: Account,
        existingFingerprints: Set<String>
    ) -> [FinanceTransaction] {
        remote.compactMap { item in
            let fingerprint = item.fingerprint(bank: bank)
            guard !existingFingerprints.contains(fingerprint), item.amount.currency == account.currency, !item.amount.isZero else { return nil }
            return FinanceTransaction(
                kind: item.amount.isNegative ? .expense : .income,
                amount: item.amount.magnitude,
                accountID: account.id,
                merchant: item.merchant,
                note: item.description,
                date: item.date,
                source: .importFile,
                importFingerprint: fingerprint
            )
        }
    }
}
