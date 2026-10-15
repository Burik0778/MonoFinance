import Foundation
import MonoCore

/// Сервис нейросети с OpenAI-совместимым API: `POST {baseURL}/chat/completions`.
/// Хранится в UserDefaults; ключ — только в Keychain (отдельно для каждого сервиса, по `id`).
public struct LLMProvider: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var model: String
    public var isEnabled: Bool

    public init(id: String = UUID().uuidString, name: String, baseURL: String, model: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.isEnabled = isEnabled
    }

    public static let groq = LLMProvider(id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1", model: "llama-3.3-70b-versatile")
    public static let cerebras = LLMProvider(id: "cerebras", name: "Cerebras", baseURL: "https://api.cerebras.ai/v1", model: "llama-3.3-70b")
    public static let openRouter = LLMProvider(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1",
                                               model: "meta-llama/llama-3.3-70b-instruct:free")
    public static let gemini = LLMProvider(id: "gemini", name: "Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
                                           model: "gemini-2.5-flash")

    /// Готовые сервисы в порядке по умолчанию.
    public static let presets: [LLMProvider] = [groq, cerebras, openRouter, gemini]

    public var isBuiltIn: Bool { Self.presets.contains { $0.id == id } }

    /// Готовый сервис в исходном виде (для «Сбросить»).
    public var preset: LLMProvider? { Self.presets.first { $0.id == id } }

    /// Адрес запроса; `nil`, если адрес не https или без хоста.
    public var chatURL: URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/chat/completions"),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// Дополнительные заголовки: OpenRouter просит указать сайт и название приложения.
    public var extraHeaders: [String: String] {
        guard let host = chatURL?.host?.lowercased(), host == "openrouter.ai" || host.hasSuffix(".openrouter.ai") else { return [:] }
        return ["HTTP-Referer": "https://github.com/Burik0778/MonoFinance", "X-Title": "MONO Finance"]
    }

    /// Ошибка заполнения по-русски; `nil` — всё верно.
    public var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Укажите название" }
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Укажите модель" }
        if chatURL == nil { return "Адрес должен начинаться с https://" }
        return nil
    }

    /// Имя записи в Keychain для ключа этого сервиса.
    public var keychainAccount: String { "llmKey.\(id)" }

    /// Порядок попыток: сначала активный, затем остальные включённые с ключом — в порядке списка.
    public static func fallbackOrder(_ providers: [LLMProvider], activeID: String?, hasKey: (LLMProvider) -> Bool) -> [LLMProvider] {
        let usable = providers.filter { $0.isEnabled && $0.chatURL != nil && hasKey($0) }
        guard let activeID, let active = usable.first(where: { $0.id == activeID }) else { return usable }
        return [active] + usable.filter { $0.id != activeID }
    }

    /// Восстанавливает готовые сервисы, которых нет в списке (свои сервисы и правки готовых сохраняются).
    public static func mergingPresets(into providers: [LLMProvider]) -> [LLMProvider] {
        var result = providers
        for preset in presets where !result.contains(where: { $0.id == preset.id }) {
            result.append(preset)
        }
        return result
    }
}

/// Сообщение чата в формате OpenAI.
public struct LLMMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// Тело запроса `chat/completions`.
public struct LLMChatRequest: Encodable, Equatable, Sendable {
    public var model: String
    public var messages: [LLMMessage]
    public var temperature: Double
    public var maxTokens: Int
    public var stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }

    public init(model: String, messages: [LLMMessage], temperature: Double = 0.3, maxTokens: Int = 800) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.stream = false
    }
}

/// Ошибки нейросети. Тексты — для пользователя, без ключей и тел ответов.
public enum LLMError: Error, Equatable, Sendable {
    case invalidKey
    case rateLimited
    case serverUnavailable(Int)
    case noNetwork
    case timeout
    case badResponse
    case insecureURL
    case notConfigured

    /// Код ответа HTTP → ошибка; `nil` для успешных кодов.
    public static func from(status: Int) -> LLMError? {
        switch status {
        case 200..<300: return nil
        case 401, 403: return .invalidKey
        case 429: return .rateLimited
        case 500..<600: return .serverUnavailable(status)
        default: return .badResponse
        }
    }

    /// Пробовать ли следующий сервис: сеть, таймаут, лимит запросов, ошибка сервера.
    public var allowsFallback: Bool {
        switch self {
        case .noNetwork, .timeout, .rateLimited, .serverUnavailable: return true
        case .invalidKey, .badResponse, .insecureURL, .notConfigured: return false
        }
    }

    public var message: String {
        switch self {
        case .invalidKey: return "Неверный ключ API. Проверьте его в настройках → Нейросеть."
        case .rateLimited: return "Лимит запросов исчерпан. Подождите немного или выберите другой сервис."
        case .serverUnavailable(let status): return "Сервис нейросети временно недоступен (код \(status))."
        case .noNetwork: return "Нет сети. Показываю ответ, посчитанный на телефоне."
        case .timeout: return "Нейросеть не ответила за 30 секунд."
        case .badResponse: return "Нейросеть вернула непонятный ответ. Проверьте адрес и модель."
        case .insecureURL: return "Адрес сервиса должен начинаться с https://"
        case .notConfigured: return "Нет сервиса с ключом. Добавьте ключ в настройках → Нейросеть."
        }
    }
}

/// Разбор ответа `chat/completions`.
public enum LLMResponseParser {
    struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message?
            let text: String?
        }
        let choices: [Choice]?
    }

    public static func text(from data: Data) throws -> String {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let choice = response.choices?.first,
              let content = choice.message?.content ?? choice.text else {
            throw LLMError.badResponse
        }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LLMError.badResponse }
        return text
    }
}

/// Перебор сервисов: если активный не ответил (сеть, 429, 5xx) — следующий по списку.
public enum LLMFallback {
    public struct Outcome<Value: Sendable>: Sendable {
        public let value: Value
        public let provider: LLMProvider
        /// Сервисы, которые не ответили до этого.
        public let skipped: [LLMProvider]
    }

    public static func run<Value: Sendable>(
        _ candidates: [LLMProvider],
        attempt: (LLMProvider) async throws -> Value
    ) async -> Result<Outcome<Value>, LLMError> {
        guard !candidates.isEmpty else { return .failure(.notConfigured) }
        var firstError: LLMError?
        var skipped: [LLMProvider] = []
        for provider in candidates {
            do {
                let value = try await attempt(provider)
                return .success(Outcome(value: value, provider: provider, skipped: skipped))
            } catch {
                let llmError = error as? LLMError ?? .badResponse
                if firstError == nil { firstError = llmError }
                guard llmError.allowsFallback else { return .failure(llmError) }
                skipped.append(provider)
            }
        }
        return .failure(firstError ?? .notConfigured)
    }
}

/// Системный промпт и сборка сообщений. Всё, что пишет пользователь, проходит через `PrivacySanitizer`.
public enum LLMPrompt {
    public static let instructions = """
    Ты — личный финансовый помощник в приложении MONO. Отвечай по-русски, кратко: 3–6 предложений или короткий список.
    Опирайся только на данные из сводки ниже — не придумывай суммы, категории и продавцов. Если данных не хватает, так и скажи.
    Давай конкретные советы по экономии: какая категория или подписка съедает больше всего, сколько можно сберечь в месяц, что изменилось по сравнению с прошлым месяцем.
    Суммы пиши так же, как в сводке. Не проси номера карт, телефоны и другие личные данные.
    """

    /// Текст системного сообщения — ровно то, что показывается на экране «Что будет отправлено».
    public static func systemMessage(summary: String) -> String {
        instructions + "\n\nСводка:\n" + summary
    }

    /// Сообщения для запроса: системное, последние реплики чата и новый вопрос.
    public static func messages(summary: String, history: [LLMMessage], question: String, historyLimit: Int = 10) -> [LLMMessage] {
        var result = [LLMMessage(role: .system, content: systemMessage(summary: summary))]
        for message in history.suffix(historyLimit) where message.role != .system {
            result.append(LLMMessage(role: message.role, content: PrivacySanitizer.clean(message.content)))
        }
        result.append(LLMMessage(role: .user, content: PrivacySanitizer.clean(question)))
        return result
    }

    /// Подсказки для пустого чата.
    public static let suggestions = [
        "На что я трачу больше всего?",
        "Где можно сэкономить?",
        "Сравни этот месяц с прошлым",
        "Какие подписки и регулярные траты?"
    ]
}
