import SwiftUI
import Observation
import MonoCore

enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case overview
    case transactions
    case analytics
    case plans

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: return "Обзор"
        case .transactions: return "Операции"
        case .analytics: return "Аналитика"
        case .plans: return "Планы"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "circle.hexagongrid.fill"
        case .transactions: return "list.bullet.rectangle.portrait.fill"
        case .analytics: return "chart.xyaxis.line"
        case .plans: return "target"
        }
    }
}

/// Контекст редактора операции.
struct TransactionEditorContext: Hashable {
    var existingID: UUID?
    var kind: TransactionKind = .expense
    var accountID: UUID?
    var categoryID: UUID?
    var prefill: FinanceTransaction?
}

/// Модальные экраны.
enum AppSheet: Identifiable {
    case voice(prefill: String?)
    case transaction(TransactionEditorContext)
    case account(Account?)
    case setBalance(Account)
    case importStatement(Account?)
    case assistant
    case settings
    case budget(Budget?)
    case goal(Goal?)
    case contribution(Goal)
    case planned(PlannedExpense?)
    case recurring(RecurringRule?)
    case category(FinanceCategory?, CategoryKind)

    var id: String {
        switch self {
        case .voice: return "voice"
        case .transaction(let context): return "transaction-\(context.existingID?.uuidString ?? "new")-\(context.kind.rawValue)"
        case .account(let account): return "account-\(account?.id.uuidString ?? "new")"
        case .setBalance(let account): return "balance-\(account.id)"
        case .importStatement: return "import"
        case .assistant: return "assistant"
        case .settings: return "settings"
        case .budget(let budget): return "budget-\(budget?.id.uuidString ?? "new")"
        case .goal(let goal): return "goal-\(goal?.id.uuidString ?? "new")"
        case .contribution(let goal): return "contribution-\(goal.id)"
        case .planned(let item): return "planned-\(item?.id.uuidString ?? "new")"
        case .recurring(let rule): return "recurring-\(rule?.id.uuidString ?? "new")"
        case .category(let category, let kind): return "category-\(category?.id.uuidString ?? "new")-\(kind.rawValue)"
        }
    }
}

/// Экраны в стеке навигации.
enum Route: Hashable {
    case accounts
    case account(UUID)
    case transaction(UUID)
    case filteredTransactions(TransactionFilter)
    case categories
    case recurringList
    case goal(UUID)
    case merchantRules
    case bankSync
    case exchangeRates
    case backup
    case speechSettings
    case aiSettings
    case securitySettings
    case about
    case settings
}

@MainActor
@Observable
final class Router {
    var tab: AppTab = .overview
    var sheet: AppSheet?
    var overviewPath = NavigationPath()
    var transactionsPath = NavigationPath()
    var analyticsPath = NavigationPath()
    var plansPath = NavigationPath()

    func present(_ sheet: AppSheet) {
        if self.sheet != nil {
            // Сначала закрываем текущий лист, затем открываем новый — иначе SwiftUI проигнорирует смену.
            self.sheet = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                self.sheet = sheet
            }
        } else {
            self.sheet = sheet
        }
    }

    func open(_ route: Route) {
        switch tab {
        case .overview: overviewPath.append(route)
        case .transactions: transactionsPath.append(route)
        case .analytics: analyticsPath.append(route)
        case .plans: plansPath.append(route)
        }
    }

    func newTransaction(_ kind: TransactionKind = .expense, accountID: UUID? = nil) {
        present(.transaction(TransactionEditorContext(kind: kind, accountID: accountID)))
    }
}
