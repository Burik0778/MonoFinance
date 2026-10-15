import Foundation
import SwiftUI
import Observation
import MonoCore
import MonoStorage

/// Корень зависимостей приложения.
@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let settings: SettingsStore
    let router = Router()
    let toasts = ToastCenter()
    let lock: AppLock
    private(set) var store: FinanceStore
    /// Критическая ошибка открытия базы (показывается вместо приложения, данные не трогаются).
    private(set) var startupError: String?
    /// Голосовая фраза, пришедшая из Siri/Быстрых команд до открытия экрана.
    var pendingVoicePhrase: String?

    init() {
        let settings = SettingsStore()
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let screenshots = arguments.contains("-monoScreenshots")
        if screenshots {
            // Снимки экрана в симуляторе (CI): только демо-база, без блокировки.
            settings.demoMode = true
            settings.onboardingCompleted = !arguments.contains("-monoOnboarding")
            settings.appLockEnabled = false
            settings.hideAmounts = false
            settings.appearance = arguments.contains("-monoLight") ? .light : .dark
        }
        #endif
        self.settings = settings
        self.lock = AppLock(settings: settings)
        do {
            self.store = try Self.makeStore(demo: settings.demoMode)
        } catch {
            self.startupError = AppError(error).message
            // Временная база в памяти, чтобы интерфейс мог показать ошибку; настоящие данные не изменяются.
            self.store = FinanceStore(database: try! LedgerDatabase.inMemory(), isDemo: false)
        }
        #if DEBUG
        if screenshots { applyScreenshotRoute(arguments) }
        #endif
    }

    #if DEBUG
    /// Открывает нужный экран по аргументам запуска: `-monoTab analytics`, `-monoRoute account`, `-monoSheet import`, `-monoVoice "фраза"`.
    private func applyScreenshotRoute(_ arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let tab = value(after: "-monoTab").flatMap(AppTab.init(rawValue:)) { router.tab = tab }
        switch value(after: "-monoRoute") {
        case "account":
            if let account = store.activeAccounts.first { router.overviewPath.append(Route.account(account.id)) }
        case "settings":
            router.overviewPath.append(Route.settings)
        case "accounts":
            router.overviewPath.append(Route.accounts)
        case "transaction":
            if let transaction = store.transactions.first(where: { $0.kind == .expense && $0.merchant != nil }) {
                router.tab = .transactions
                router.transactionsPath.append(Route.transaction(transaction.id))
            }
        case "categories":
            router.overviewPath.append(Route.categories)
        case "goal":
            if let goal = store.goals.first {
                router.tab = .plans
                router.plansPath.append(Route.goal(goal.id))
            }
        default:
            break
        }
        if let phrase = value(after: "-monoVoice") {
            router.sheet = .voice(prefill: phrase)
        }
        switch value(after: "-monoSheet") {
        case "import": router.sheet = .importStatement(nil)
        case "assistant": router.sheet = .assistant
        case "expense": router.sheet = .transaction(TransactionEditorContext(kind: .expense))
        case "transfer": router.sheet = .transaction(TransactionEditorContext(kind: .transfer))
        case "account": router.sheet = .account(nil)
        case "voice": router.sheet = .voice(prefill: nil)
        default: break
        }
    }
    #endif

    static var dataDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MONO", isDirectory: true)
    }

    static func databaseURL(demo: Bool) -> URL {
        dataDirectory.appendingPathComponent(demo ? "demo.sqlite" : "ledger.sqlite")
    }

    static func makeStore(demo: Bool) throws -> FinanceStore {
        let directory = dataDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ])
        let url = databaseURL(demo: demo)
        if demo {
            // Демо-база всегда создаётся заново и никогда не смешивается с реальными данными.
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let database = try LedgerDatabase(path: url.path)
        try database.seedDefaultCategories(language: .current)
        if demo {
            try DemoData.populate(database, now: Date(), calendar: PeriodCalendar().calendar)
        }
        return FinanceStore(database: database, isDemo: demo)
    }

    /// Переключение демо-режима: открывает другую базу. Реальные данные не затрагиваются.
    func setDemoMode(_ enabled: Bool) {
        do {
            store = try Self.makeStore(demo: enabled)
            settings.demoMode = enabled
            router.overviewPath = NavigationPath()
            router.transactionsPath = NavigationPath()
            router.analyticsPath = NavigationPath()
            router.plansPath = NavigationPath()
        } catch {
            toasts.show(ToastMessage(text: AppError(error).message, symbol: "exclamationmark.triangle.fill", tint: Color.mono.warning))
        }
    }

    /// Обработка команды из Быстрых действий или App Intents.
    func handle(command: AppCommand) {
        // До завершения онбординга счетов ещё нет — команды игнорируем.
        guard settings.onboardingCompleted, startupError == nil else { return }
        switch command {
        case .voice(let phrase):
            router.present(.voice(prefill: phrase))
        case .newExpense:
            router.newTransaction(.expense)
        case .newIncome:
            router.newTransaction(.income)
        case .transfer:
            router.newTransaction(.transfer)
        case .assistant:
            router.present(.assistant)
        }
    }
}

/// Внешние команды (Быстрые действия, Siri, ссылки monofinance://).
enum AppCommand: Equatable {
    case voice(String?)
    case newExpense
    case newIncome
    case transfer
    case assistant

    init?(shortcutType: String) {
        switch shortcutType {
        case "uz.mono.finance.voice": self = .voice(nil)
        case "uz.mono.finance.expense": self = .newExpense
        case "uz.mono.finance.transfer": self = .transfer
        case "uz.mono.finance.assistant": self = .assistant
        default: return nil
        }
    }

    init?(url: URL) {
        guard url.scheme == "monofinance" else { return nil }
        switch url.host {
        case "voice":
            let phrase = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "text" }?.value
            self = .voice(phrase)
        case "expense": self = .newExpense
        case "income": self = .newIncome
        case "transfer": self = .transfer
        case "assistant": self = .assistant
        default: return nil
        }
    }
}

/// Флаги для снимков экрана в симуляторе (только в отладочной сборке).
enum DebugFlags {
    /// `-monoVoiceIdle` — голосовой экран открывается без автозапуска записи (в симуляторе нет микрофона).
    static let voiceIdle: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-monoVoiceIdle")
        #else
        return false
        #endif
    }()

    /// `-monoScroll top|center|bottom` — начальная позиция прокрутки длинных экранов.
    static let scrollAnchor: UnitPoint = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-monoScroll"), arguments.indices.contains(index + 1) {
            switch arguments[index + 1] {
            case "center": return .center
            case "bottom": return .bottom
            default: return .top
            }
        }
        #endif
        return .top
    }()
}
