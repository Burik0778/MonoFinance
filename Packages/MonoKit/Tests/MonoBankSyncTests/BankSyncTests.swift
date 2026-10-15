import XCTest
import MonoCore
@testable import MonoBankSync

final class BankSyncTests: XCTestCase {
    func testNoBankPretendsToBeConnected() async {
        for bank in BankIntegrationRegistry.supportedBanks {
            let integration = BankIntegrationRegistry.integration(for: bank)
            guard case .unavailable(let reason) = integration.availability else {
                return XCTFail("\(bank) не должен заявлять подключение без официального доступа")
            }
            XCTAssertTrue(reason.ru.contains("импорт выписки"))
            do {
                _ = try await integration.fetchTransactions(accountRemoteID: "x", since: Date())
                XCTFail("Запрос к недоступному банку не может «успешно» вернуть данные")
            } catch {
                XCTAssertEqual(error as? BankSyncError, .notAvailable)
            }
        }
    }

    func testRemoteMappingSkipsAlreadyImported() {
        let account = Account(bank: .uzum, name: "Uzum", currency: .uzs)
        let remote = [
            RemoteTransaction(remoteID: "1", accountRemoteID: "a", date: Date(), amount: Money(minorUnits: -8_500_000, currency: .uzs), description: "EVOS", merchant: "EVOS"),
            RemoteTransaction(remoteID: "2", accountRemoteID: "a", date: Date(), amount: Money(minorUnits: 50_000_000, currency: .uzs), description: "Salary", merchant: nil),
            RemoteTransaction(remoteID: "3", accountRemoteID: "a", date: Date(), amount: Money(minorUnits: -100, currency: .usd), description: "USD", merchant: nil)
        ]
        let mapped = RemoteTransactionMapper.transactions(from: remote, bank: .uzum, account: account, existingFingerprints: ["uzum|remote|2"])
        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped[0].kind, .expense)
        XCTAssertEqual(mapped[0].amount.minorUnits, 8_500_000)
        XCTAssertEqual(mapped[0].importFingerprint, "uzum|remote|1")
    }
}
