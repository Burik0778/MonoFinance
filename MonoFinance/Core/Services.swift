import Foundation
import MonoCore
import MonoStorage
import MonoIntelligence

/// Официальные курсы ЦБ Республики Узбекистан. Запрос не содержит никаких данных пользователя.
struct ExchangeRateService {
    static let endpoint = URL(string: "https://cbu.uz/ru/arkhiv-kursov-valyut/json/")!

    var session: URLSession = .shared

    func fetchLatest(calendar: Calendar) async throws -> [ExchangeRate] {
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try CBURateParser.parse(data, calendar: calendar)
    }
}

/// Экспорт истории операций в CSV (UTF-8 с BOM и «;» — корректно открывается в Excel с русской локалью).
enum ExportService {
    static func csv(transactions: [FinanceTransaction], accounts: [UUID: Account], categories: [UUID: FinanceCategory], calendar: Calendar) -> Data {
        let header = ["Дата", "Тип", "Сумма", "Валюта", "Счёт", "Счёт получателя", "Сумма зачисления", "Валюта зачисления",
                      "Категория", "Получатель/магазин", "Описание", "Теги", "Источник"]
        var lines = [header.map(escape).joined(separator: ";")]
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withSpaceBetweenDateAndTime]
        for transaction in transactions.sorted(by: { $0.date < $1.date }) {
            let signed: Money
            switch transaction.kind {
            case .expense, .fee, .transfer: signed = transaction.amount.magnitude.negated
            case .income, .refund: signed = transaction.amount.magnitude
            case .adjustment: signed = transaction.amount
            }
            let fields: [String] = [
                formatter.string(from: transaction.date),
                transaction.kind.title(.ru),
                plainNumber(signed),
                transaction.amount.currency.code,
                accounts[transaction.accountID]?.displayName ?? "",
                transaction.counterAccountID.flatMap { accounts[$0]?.displayName } ?? "",
                transaction.counterAmount.map(plainNumber) ?? "",
                transaction.counterAmount?.currency.code ?? "",
                transaction.categoryID.flatMap { categories[$0]?.name } ?? "",
                transaction.merchant ?? "",
                transaction.note ?? "",
                transaction.tags.joined(separator: ", "),
                transaction.source.rawValue
            ]
            lines.append(fields.map(escape).joined(separator: ";"))
        }
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(lines.joined(separator: "\r\n").utf8))
        return data
    }

    /// Число с запятой и без разделителей разрядов: «-85000,50».
    static func plainNumber(_ money: Money) -> String {
        let text = "\(money.majorValue)"
        return text.replacingOccurrences(of: ".", with: ",")
    }

    static func escape(_ field: String) -> String {
        guard field.contains(";") || field.contains("\"") || field.contains("\n") || field.contains("\r") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func temporaryFile(named name: String, data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

/// Хранение фотографий чеков в защищённом каталоге приложения.
enum ReceiptStore {
    static var directory: URL {
        AppEnvironmentPaths.receipts
    }

    static func save(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return name
    }

    static func url(for name: String) -> URL { directory.appendingPathComponent(name) }

    static func load(_ name: String) -> Data? { try? Data(contentsOf: url(for: name)) }

    static func delete(_ name: String) { try? FileManager.default.removeItem(at: url(for: name)) }
}

enum AppEnvironmentPaths {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MONO", isDirectory: true)
    }

    static var receipts: URL { root.appendingPathComponent("Receipts", isDirectory: true) }
}

/// Ключи сервисов нейросети: только Keychain на этом устройстве, отдельная запись на каждый сервис.
enum LLMKeychain {
    static func key(for provider: LLMProvider) -> String? {
        guard let value = KeychainStore.get(provider.keychainAccount)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    static func hasKey(_ provider: LLMProvider) -> Bool { key(for: provider) != nil }

    static func set(_ key: String?, for provider: LLMProvider) {
        KeychainStore.set(key?.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.keychainAccount)
    }
}

/// Запросы к нейросети через OpenAI-совместимый `POST {baseURL}/chat/completions`.
///
/// Наружу уходят только сообщения, собранные `LLMPrompt` (сводка + вопрос после `PrivacySanitizer`).
/// Ключи и тела ответов не логируются; таймаут — 30 секунд.
struct LLMClient {
    static let timeout: TimeInterval = 30

    var session: URLSession = LLMClient.makeSession()

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 5
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// Один запрос к одному сервису.
    func complete(provider: LLMProvider, key: String, messages: [LLMMessage], maxTokens: Int = 800) async throws -> String {
        guard let url = provider.chatURL else { throw LLMError.insecureURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        for (field, value) in provider.extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONEncoder().encode(LLMChatRequest(model: provider.model, messages: messages, maxTokens: maxTokens))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? LLMError.timeout : LLMError.noNetwork
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LLMError.noNetwork
        }
        guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse }
        if let error = LLMError.from(status: http.statusCode) { throw error }
        return try LLMResponseParser.text(from: data)
    }

    /// Вопрос с перебором: если активный сервис не ответил (сеть, 429, 5xx) — следующий с ключом.
    func ask(messages: [LLMMessage], candidates: [LLMProvider]) async -> Result<LLMFallback.Outcome<String>, LLMError> {
        await LLMFallback.run(candidates) { provider in
            guard let key = LLMKeychain.key(for: provider) else { throw LLMError.notConfigured }
            return try await complete(provider: provider, key: key, messages: messages)
        }
    }

    /// «Проверить»: короткий тестовый запрос без данных пользователя.
    func check(provider: LLMProvider, key: String) async throws -> String {
        let messages = [
            LLMMessage(role: .system, content: "Это проверка подключения. Ответь одним словом."),
            LLMMessage(role: .user, content: "Скажи «готово».")
        ]
        return try await complete(provider: provider, key: key, messages: messages, maxTokens: 16)
    }
}
