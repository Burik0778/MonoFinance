import SwiftUI
import MonoCore

struct MainTabView: View {
    @Environment(Router.self) private var router
    @Environment(AppEnvironment.self) private var environment
    @Namespace private var zoomNamespace

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.overviewPath) {
                OverviewView().withRoutes()
            }
            .toolbar(.hidden, for: .tabBar)
            .tag(AppTab.overview)

            NavigationStack(path: $router.transactionsPath) {
                TransactionsView().withRoutes()
            }
            .toolbar(.hidden, for: .tabBar)
            .tag(AppTab.transactions)

            NavigationStack(path: $router.analyticsPath) {
                AnalyticsView().withRoutes()
            }
            .toolbar(.hidden, for: .tabBar)
            .tag(AppTab.analytics)

            NavigationStack(path: $router.plansPath) {
                PlansView().withRoutes()
            }
            .toolbar(.hidden, for: .tabBar)
            .tag(AppTab.plans)
        }
        .environment(\.zoomNamespace, zoomNamespace)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingDock(
                selection: $router.tab,
                onVoice: { router.present(.voice(prefill: nil)) },
                onManualEntry: { router.newTransaction(.expense) },
                onTransfer: { router.newTransaction(.transfer) }
            )
            .padding(.bottom, 4)
        }
        .onAppear {
            if let phrase = environment.pendingVoicePhrase {
                environment.pendingVoicePhrase = nil
                router.present(.voice(prefill: phrase))
            }
        }
    }
}

extension View {
    /// Подключает все экраны навигационного стека.
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            RouteDestination(route: route)
        }
    }
}

struct RouteDestination: View {
    let route: Route
    @Environment(FinanceStore.self) private var store
    @Environment(\.zoomNamespace) private var zoomNamespace

    var body: some View {
        switch route {
        case .accounts:
            AccountsView()
        case .account(let id):
            if let account = store.accountMap[id] {
                AccountDetailView(account: account)
                    .modifier(ZoomDestination(id: id, namespace: zoomNamespace))
            } else {
                MissingItemView()
            }
        case .transaction(let id):
            if let transaction = store.transaction(id: id) {
                TransactionDetailView(transaction: transaction)
            } else {
                MissingItemView()
            }
        case .filteredTransactions(let filter):
            TransactionsView(initialFilter: filter, isRoot: false)
        case .categories:
            CategoriesView()
        case .recurringList:
            RecurringListView()
        case .goal(let id):
            if let goal = store.goals.first(where: { $0.id == id }) {
                GoalDetailView(goal: goal)
            } else {
                MissingItemView()
            }
        case .merchantRules:
            MerchantRulesView()
        case .bankSync:
            BankSyncView()
        case .exchangeRates:
            ExchangeRatesView()
        case .backup:
            BackupView()
        case .speechSettings:
            SpeechSettingsView()
        case .aiSettings:
            AISettingsView()
        case .securitySettings:
            SecuritySettingsView()
        case .about:
            AboutView()
        case .settings:
            SettingsView()
        }
    }
}

/// «Готово» для экранов, открытых модально.
struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Готово") { dismiss() }
    }
}

struct MissingItemView: View {
    var body: some View {
        EmptyStateView(symbol: "questionmark.folder", title: "Запись не найдена", message: "Возможно, она была удалена.")
    }
}

/// Модальные экраны по `AppSheet`.
struct SheetContainer: View {
    let sheet: AppSheet
    @Environment(FinanceStore.self) private var store

    var body: some View {
        Group {
            switch sheet {
            case .voice(let prefill):
                VoiceCaptureView(prefill: prefill)
            case .transaction(let context):
                TransactionEditorView(context: context)
            case .account(let account):
                AccountEditorView(account: account)
            case .setBalance(let account):
                SetBalanceView(account: account)
            case .importStatement(let account):
                ImportFlowView(preselectedAccount: account)
            case .assistant:
                AssistantView()
            case .settings:
                NavigationStack {
                    SettingsView()
                        .withRoutes()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                DismissButton()
                            }
                        }
                }
            case .budget(let budget):
                BudgetEditorView(budget: budget)
            case .goal(let goal):
                GoalEditorView(goal: goal)
            case .contribution(let goal):
                ContributionEditorView(goal: goal)
            case .planned(let item):
                PlannedEditorView(item: item)
            case .recurring(let rule):
                RecurringEditorView(rule: rule)
            case .category(let category, let kind):
                CategoryEditorView(category: category, kind: kind)
            }
        }
        .presentationBackground(Color.mono.backgroundRaised)
        .presentationCornerRadius(MonoTokens.Radius.xxl)
    }
}
