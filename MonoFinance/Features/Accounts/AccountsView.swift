import SwiftUI
import MonoCore

/// Все счета: полноразмерные виртуальные карты, итог по валютам, архив.
struct AccountsView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var showsArchived = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                totals
                if store.activeAccounts.isEmpty {
                    EmptyStateView(symbol: "creditcard", title: "Счетов пока нет", message: "Добавьте карты Kapitalbank, Uzum Bank, Orient Finans Bank, Trastbank или наличные.") {
                        Button("Добавить счёт") { router.present(.account(nil)) }
                            .buttonStyle(PrimaryButtonStyle())
                            .frame(maxWidth: 240)
                    }
                }
                ForEach(store.activeAccounts) { account in
                    NavigationLink(value: Route.account(account.id)) {
                        VirtualCardView(account: account, balance: store.balance(of: account))
                            .aspectRatio(1.586, contentMode: .fit)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .modifier(ZoomSource(id: account.id, namespace: zoomNamespace))
                    .contextMenu {
                        Button { router.present(.account(account)) } label: { Label("Изменить", systemImage: "pencil") }
                        Button { router.present(.setBalance(account)) } label: { Label("Корректировка баланса", systemImage: "slider.horizontal.3") }
                        Button { router.newTransaction(.expense, accountID: account.id) } label: { Label("Новая операция", systemImage: "plus") }
                        Button { try? store.setDefaultAccount(account) } label: { Label("Сделать основным", systemImage: "star") }
                    }
                }
                if !store.archivedAccounts.isEmpty {
                    DisclosureGroup(isExpanded: $showsArchived) {
                        VStack(spacing: 10) {
                            ForEach(store.archivedAccounts) { account in
                                NavigationLink(value: Route.account(account.id)) {
                                    HStack {
                                        Circle().fill(account.tint).frame(width: 10, height: 10)
                                        Text(verbatim: account.displayName).monoFont(.body).foregroundStyle(Color.mono.textSecondary)
                                        Spacer()
                                        MoneyText(money: store.balance(of: account), token: .amountRow, color: Color.mono.textSecondary)
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Kicker("Архив")
                    }
                    .tint(Color.mono.textSecondary)
                    .monoSurface(padding: 16)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color.mono.background.ignoresSafeArea())
        .navigationTitle("Счета")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.present(.account(nil)) } label: { Image(systemName: "plus") }
                    .accessibilityLabel(Text("Добавить счёт"))
            }
        }
    }

    /// Итоги по валютам — без пересчёта, как есть на счетах.
    private var totals: some View {
        let totals = Ledger.totalsByCurrency(Dictionary(uniqueKeysWithValues: store.activeAccounts.filter(\.includeInTotal).map { ($0.id, store.balance(of: $0)) }))
        return VStack(alignment: .leading, spacing: 8) {
            Kicker("Остатки по валютам")
            FlowLayout(spacing: 8) {
                ForEach(totals.keys.sorted(), id: \.self) { currency in
                    if let money = totals[currency] {
                        MoneyText(money: money, token: .headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.mono.surface2))
                    }
                }
            }
        }
    }
}
