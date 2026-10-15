import AppIntents
import Foundation

/// Siri и Быстрые команды открывают нужный экран MONO. Операции не создаются в фоне:
/// пользователь всегда видит черновик и подтверждает его в приложении.
struct RecordByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Записать операцию голосом"
    static let description = IntentDescription("Открывает голосовой ввод MONO. Операция сохранится только после вашего подтверждения.")
    static let openAppWhenRun = true

    @Parameter(title: "Фраза", description: "Например: «потратил 85 тысяч на обед»")
    var phrase: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        AppEnvironment.shared.handle(command: .voice(phrase))
        return .result()
    }
}

struct NewExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Новый расход"
    static let description = IntentDescription("Открывает форму нового расхода в MONO.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppEnvironment.shared.handle(command: .newExpense)
        return .result()
    }
}

struct NewTransferIntent: AppIntent {
    static let title: LocalizedStringResource = "Перевод между счетами"
    static let description = IntentDescription("Открывает форму перевода между своими счетами в MONO.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppEnvironment.shared.handle(command: .transfer)
        return .result()
    }
}

struct AskAssistantIntent: AppIntent {
    static let title: LocalizedStringResource = "Спросить MONO"
    static let description = IntentDescription("Открывает финансового ассистента MONO.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppEnvironment.shared.handle(command: .assistant)
        return .result()
    }
}

struct MonoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordByVoiceIntent(),
            phrases: [
                "Записать расход в \(.applicationName)",
                "Добавить операцию в \(.applicationName)",
                "Record an expense in \(.applicationName)"
            ],
            shortTitle: "Голосом",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: NewExpenseIntent(),
            phrases: ["Новый расход в \(.applicationName)", "New expense in \(.applicationName)"],
            shortTitle: "Расход",
            systemImageName: "arrow.up.right"
        )
        AppShortcut(
            intent: NewTransferIntent(),
            phrases: ["Перевод в \(.applicationName)", "Transfer in \(.applicationName)"],
            shortTitle: "Перевод",
            systemImageName: "arrow.left.arrow.right"
        )
        AppShortcut(
            intent: AskAssistantIntent(),
            phrases: ["Спросить \(.applicationName)", "Ask \(.applicationName)"],
            shortTitle: "Ассистент",
            systemImageName: "sparkles"
        )
    }
}
