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
                    .scrollTransition(.animated, axis: .vertical) { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1 : 0.96)
                            .opacity(phase.isIdentity ? 1 : 0.6)
                    }
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
                                    HStack(spacing: 12) {
                                        CardThumbnail(skin: account.skin, width: 36)
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
        .background(MonoBackdrop())
        .navigationTitle("Счета")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.present(.account(nil)) } label: { Image(systemName: "plus") }
                    .accessibilityLabel(Text("Добавить счёт"))
            }
        }
    }

    /// Итог в базовой валюте и остатки по валютам — без пересчёта, как есть на счетах.
    private var totals: some View {
        let totals = Ledger.totalsByCurrency(Dictionary(uniqueKeysWithValues: store.activeAccounts.filter(\.includeInTotal).map { ($0.id, store.balance(of: $0)) }))
        let total = store.totalBalance
        return VStack(alignment: .leading, spacing: 10) {
            Kicker("Всего на счетах")
            HeroAmount(money: total.total, token: .display, secondaryToken: .title2)
            if totals.count > 1 {
                HStack(spacing: 16) {
                    ForEach(totals.keys.sorted(), id: \.self) { currency in
                        if let money = totals[currency] {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: currency.code)
                                    .monoFont(.caption)
                                    .foregroundStyle(Color.mono.textTertiary)
                                MoneyText(money: money, token: .subhead, color: Color.mono.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom, 6)
    }
}
