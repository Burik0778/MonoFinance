import Foundation
import MonoCore
import MonoStorage

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

/// Внешняя языковая модель через собственный защищённый бэкенд пользователя. Выключено по умолчанию.
///
/// Модели передаются только вопрос и уже посчитанный ответ (агрегаты), без списка операций и аудио.
/// Задача модели — переформулировать объяснение; числа считаются локально и не могут быть изменены.
struct AssistantRemoteClient {
    struct Payload: Encodable {
        let question: String
        let answerHeadline: String
        let answerText: String
        let facts: [String]
        let language: String
        let instruction: String
    }

    struct Response: Decodable {
        let text: String
    }

    let endpoint: URL
    let token: String?
    var session: URLSession = .shared

    func explain(question: String, headline: String, text: String, facts: [String], language: AppLanguage) async throws -> String {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let payload = Payload(
            question: question,
            answerHeadline: headline,
            answerText: text,
            facts: facts,
            language: language.rawValue,
            instruction: "Explain the computed answer in 2-3 sentences. Use only the numbers provided in answerHeadline, answerText and facts. Never invent new figures."
        )
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: data).text
    }
}
