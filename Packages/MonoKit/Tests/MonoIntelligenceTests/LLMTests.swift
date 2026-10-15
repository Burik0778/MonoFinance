import XCTest
import MonoCore
import MonoAnalytics
@testable import MonoIntelligence

final class FinancialSummaryTests: XCTestCase {
    let fixture = Fixture()

    /// Данные фикстуры плюс операции с личными данными в продавце, заметке и тегах.
    private func summaryText() -> String {
        var transactions = fixture.transactions
        transactions.append(FinanceTransaction(
            kind: .expense, amount: fixture.uzs(300_000), accountID: fixture.kapital.id,
            categoryID: fixture.cat(SystemCategoryKey.transfersOut), merchant: "Перевод Алишеру Каримову",
            note: "долг за обед", tags: ["секретный тег"], date: fixture.date(2026, 10, 10)
        ))
        transactions.append(FinanceTransaction(
            kind: .expense, amount: fixture.uzs(45_000), accountID: fixture.kapital.id,
            categoryID: fixture.cat(SystemCategoryKey.subscriptions), merchant: "NETFLIX 414084******7058",
            note: "моя заметка", date: fixture.date(2026, 10, 11)
        ))
        let analytics = AnalyticsEngine(transactions: transactions, accounts: [fixture.kapital, fixture.uzum], categories: fixture.categories,
                                        converter: CurrencyConverter(base: .uzs, rateTable: [:]), periods: fixture.periods)
        let budget = Budget(categoryID: fixture.cat(SystemCategoryKey.cafe), limit: fixture.uzs(800_000), startMonth: MonthKey(year: 2026, month: 10))
        return FinancialSummaryBuilder(analytics: analytics, budgets: [budget], now: fixture.now).text()
    }

    func testSummaryContainsAggregates() {
        let text = summaryText()
        XCTAssertTrue(text.contains("Итоги по месяцам"), text)
        XCTAssertTrue(text.contains("октябрь 2026 (текущий, неполный)"), text)
        XCTAssertTrue(text.contains("сентябрь 2026"), text)
        XCTAssertTrue(text.contains("Кафе и рестораны"), text)
        XCTAssertTrue(text.contains("Korzinka"), text)
        XCTAssertTrue(text.contains("Сравнение"), text)
        XCTAssertTrue(text.contains("Средние"), text)
        XCTAssertTrue(text.contains("Регулярные траты"), text)
        XCTAssertTrue(text.contains("Бюджеты на текущий месяц"), text)
        XCTAssertTrue(text.contains("12 000 000 сум"), text)
    }

    func testSummaryHasNoPersonalData() {
        let text = summaryText()
        for secret in ["Алишер", "Каримов", "7058", "414084", "долг за обед", "секретный тег", "моя заметка", "Kapital", "Uzum"] {
            XCTAssertFalse(text.contains(secret), "«\(secret)» попало в сводку:\n\(text)")
        }
        XCTAssertTrue(text.contains(PrivacySanitizer.personTransfer), text)
    }

    func testEmptyLedger() {
        let analytics = AnalyticsEngine(transactions: [], accounts: [], categories: fixture.categories,
                                        converter: CurrencyConverter(base: .uzs, rateTable: [:]), periods: fixture.periods)
        let text = FinancialSummaryBuilder(analytics: analytics, now: fixture.now).text()
        XCTAssertTrue(text.contains("Операций пока нет"), text)
        XCTAssertFalse(text.contains("Итоги по месяцам"), text)
    }
}

final class LLMProviderTests: XCTestCase {
    func testPresets() {
        XCTAssertEqual(LLMProvider.presets.map(\.id), ["groq", "cerebras", "openrouter", "gemini"])
        XCTAssertEqual(LLMProvider.groq.chatURL?.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(LLMProvider.cerebras.chatURL?.absoluteString, "https://api.cerebras.ai/v1/chat/completions")
        XCTAssertEqual(LLMProvider.gemini.chatURL?.absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        XCTAssertEqual(LLMProvider.openRouter.model, "meta-llama/llama-3.3-70b-instruct:free")
        XCTAssertTrue(LLMProvider.presets.allSatisfy { $0.isBuiltIn && $0.validationError == nil })
    }

    func testOpenRouterHeaders() {
        XCTAssertEqual(LLMProvider.openRouter.extraHeaders["X-Title"], "MONO Finance")
        XCTAssertNotNil(LLMProvider.openRouter.extraHeaders["HTTP-Referer"])
        XCTAssertTrue(LLMProvider.groq.extraHeaders.isEmpty)
    }

    func testOnlyHTTPS() {
        var provider = LLMProvider(name: "Свой", baseURL: "http://example.com/v1", model: "m")
        XCTAssertNil(provider.chatURL)
        XCTAssertNotNil(provider.validationError)
        provider.baseURL = "https://example.com/v1/"
        XCTAssertEqual(provider.chatURL?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertNil(provider.validationError)
        XCTAssertFalse(provider.isBuiltIn)
    }

    func testFallbackOrder() {
        var cerebras = LLMProvider.cerebras
        cerebras.isEnabled = false
        let providers = [LLMProvider.groq, cerebras, LLMProvider.openRouter, LLMProvider.gemini]
        let withKeys: Set<String> = ["groq", "cerebras", "gemini"]
        let order = LLMProvider.fallbackOrder(providers, activeID: "gemini") { withKeys.contains($0.id) }
        XCTAssertEqual(order.map(\.id), ["gemini", "groq"])
        let noActive = LLMProvider.fallbackOrder(providers, activeID: "openrouter") { withKeys.contains($0.id) }
        XCTAssertEqual(noActive.map(\.id), ["groq", "gemini"])
    }

    func testMergingPresetsKeepsEdits() {
        var groq = LLMProvider.groq
        groq.model = "llama-3.1-8b-instant"
        let custom = LLMProvider(name: "Свой", baseURL: "https://example.com/v1", model: "m")
        let merged = LLMProvider.mergingPresets(into: [custom, groq])
        XCTAssertEqual(merged.count, 5)
        XCTAssertEqual(merged.first { $0.id == "groq" }?.model, "llama-3.1-8b-instant")
        XCTAssertEqual(merged.first?.id, custom.id)
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(LLMProvider.presets)
        XCTAssertEqual(try JSONDecoder().decode([LLMProvider].self, from: data), LLMProvider.presets)
    }
}

final class LLMRequestTests: XCTestCase {
    func testRequestBody() throws {
        let request = LLMChatRequest(model: "llama-3.3-70b-versatile", messages: [LLMMessage(role: .user, content: "Привет")])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "llama-3.3-70b-versatile")
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertNotNil(json["max_tokens"])
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "user", "content": "Привет"]])
    }

    func testParseResponse() throws {
        let data = Data(#"{"id":"x","choices":[{"index":0,"message":{"role":"assistant","content":"  Больше всего — кафе.  "}}]}"#.utf8)
        XCTAssertEqual(try LLMResponseParser.text(from: data), "Больше всего — кафе.")
        XCTAssertThrowsError(try LLMResponseParser.text(from: Data(#"{"error":{"message":"bad"}}"#.utf8)))
        XCTAssertThrowsError(try LLMResponseParser.text(from: Data(#"{"choices":[{"message":{"content":""}}]}"#.utf8)))
    }

    func testStatusMapping() {
        XCTAssertNil(LLMError.from(status: 200))
        XCTAssertEqual(LLMError.from(status: 401), .invalidKey)
        XCTAssertEqual(LLMError.from(status: 429), .rateLimited)
        XCTAssertEqual(LLMError.from(status: 503), .serverUnavailable(503))
        XCTAssertTrue(LLMError.rateLimited.allowsFallback)
        XCTAssertTrue(LLMError.serverUnavailable(502).allowsFallback)
        XCTAssertTrue(LLMError.noNetwork.allowsFallback)
        XCTAssertFalse(LLMError.invalidKey.allowsFallback)
    }

    func testMessagesAreSanitized() {
        let history = [LLMMessage(role: .user, content: "Мой номер +998 90 123 45 67"), LLMMessage(role: .assistant, content: "Понял.")]
        let messages = LLMPrompt.messages(summary: "Сводка: итоги", history: history, question: "Сколько я перевёл Алишеру Каримову с карты 414084******7058?")
        XCTAssertEqual(messages.first?.role, .system)
        XCTAssertTrue(messages[0].content.contains("Сводка: итоги"))
        XCTAssertEqual(messages.count, 4)
        let joined = messages.map(\.content).joined(separator: "\n")
        for secret in ["123 45 67", "Алишер", "Каримов", "7058"] {
            XCTAssertFalse(joined.contains(secret), "«\(secret)» ушло в запрос")
        }
        XCTAssertEqual(messages.last?.role, .user)
    }

    func testSuggestions() {
        XCTAssertEqual(LLMPrompt.suggestions.count, 4)
        XCTAssertTrue(LLMPrompt.suggestions.contains("Где можно сэкономить?"))
    }
}

final class LLMFallbackTests: XCTestCase {
    private let providers = [LLMProvider.groq, LLMProvider.cerebras, LLMProvider.gemini]

    func testFallsBackOnRateLimitAndServerErrors() async {
        let result = await LLMFallback.run(providers) { provider -> String in
            switch provider.id {
            case "groq": throw LLMError.rateLimited
            case "cerebras": throw LLMError.serverUnavailable(503)
            default: return "ответ \(provider.name)"
            }
        }
        guard case .success(let outcome) = result else { return XCTFail("ожидался ответ") }
        XCTAssertEqual(outcome.value, "ответ Gemini")
        XCTAssertEqual(outcome.provider.id, "gemini")
        XCTAssertEqual(outcome.skipped.map(\.id), ["groq", "cerebras"])
    }

    func testStopsOnInvalidKey() async {
        let result = await LLMFallback.run(providers) { provider -> String in
            if provider.id == "groq" { throw LLMError.invalidKey }
            return "ответ"
        }
        guard case .failure(let error) = result else { return XCTFail("ожидалась ошибка") }
        XCTAssertEqual(error, .invalidKey)
    }

    func testAllOfflineReportsNoNetwork() async {
        let result = await LLMFallback.run(providers) { _ -> String in throw LLMError.noNetwork }
        guard case .failure(let error) = result else { return XCTFail("ожидалась ошибка") }
        XCTAssertEqual(error, .noNetwork)
    }

    func testNoProviders() async {
        let result = await LLMFallback.run([]) { _ -> String in "ответ" }
        guard case .failure(let error) = result else { return XCTFail("ожидалась ошибка") }
        XCTAssertEqual(error, .notConfigured)
    }
}
