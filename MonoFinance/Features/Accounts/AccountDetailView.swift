import SwiftUI
import Charts
import MonoCore
import MonoAnalytics
import MonoBankSync

/// Экран счёта: карта, расчётный баланс, аналитика по счёту, история операций, действия.
struct AccountDetailView: View {
    let account: Account

    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @State private var confirmsDelete = false

    private var current: Account { store.accountMap[account.id] ?? account }

    var body: some View {
        let analytics = store.analytics()
        let now = Date()
        let monthRange = store.periods.range(for: .thisMonth, now: now)
        let flow = analytics.flowsByAccount(monthRange).first { $0.accountID == account.id }
        let history = analytics.balanceHistory(store.periods.range(for: .last90Days, now: now), accountIDs: [account.id])
        let transactions = store.transactions(for: current)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VirtualCardView(account: current, balance: store.balance(of: current))
                    .aspectRatio(1.586, contentMode: .fit)
                    .padding(.top, 8)

                HStack(spacing: 10) {
                    actionButton("Операция", symbol: "plus") { router.newTransaction(.expense, accountID: account.id) }
                    actionButton("Перевод", symbol: "arrow.left.arrow.right") { router.newTransaction(.transfer, accountID: account.id) }
                    actionButton("Баланс", symbol: "slider.horizontal.3") { router.present(.setBalance(current)) }
                    actionButton("Импорт", symbol: "tray.and.arrow.down") { router.present(.importStatement(current)) }
                }

                syncStatus

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Kicker("Этот месяц по счёту")
                        Spacer()
                        Text("90 дней")
                            .monoFont(.caption)
                            .foregroundStyle(Color.mono.textTertiary)
                    }
                    HStack(spacing: 12) {
                        stat("Пришло", value: (flow?.income ?? .zero(store.baseCurrency)) + (flow?.transfersIn ?? .zero(store.baseCurrency)), tint: Color.mono.positive)
                        stat("Ушло", value: (flow?.spending ?? .zero(store.baseCurrency)) + (flow?.fees ?? .zero(store.baseCurrency)) + (flow?.transfersOut ?? .zero(store.baseCurrency)), tint: Color.mono.textPrimary)
                    }
                    if history.count > 1 {
                        let values = history.map(\.balance.chartValue)
                        let low = values.min() ?? 0
                        let high = values.max() ?? 1
                        let pad = max((high - low) * 0.15, 1)
                        Chart(history) { point in
                            AreaMark(x: .value("Дата", point.date),
                                     yStart: .value("Основание", low - pad),
                                     yEnd: .value("Баланс", point.balance.chartValue))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(LinearGradient(colors: [Color.mono.accent.opacity(0.22), Color.mono.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("Дата", point.date), y: .value("Баланс", point.balance.chartValue))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(Color.mono.accentText)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        }
                        .chartYScale(domain: (low - pad)...(high + pad))
                        .chartYAxis(.hidden)
                        .chartXAxis(.hidden)
                        .frame(height: 80)
                        .accessibilityLabel(Text("Баланс счёта за 90 дней"))
                    }
                    if current.currency != store.baseCurrency {
                        Text("Суммы месяца пересчитаны в базовую валюту по текущему курсу.")
                            .monoFont(.caption)
                            .foregroundStyle(Color.mono.textTertiary)
                    }
                }
                .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)

                VStack(alignment: .leading, spacing: 8) {
                    Kicker("История операций")
                    if transactions.isEmpty {
                        Text("Операций по счёту пока нет")
                            .monoFont(.callout)
                            .foregroundStyle(Color.mono.textTertiary)
                            .padding(.vertical, 8)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(transactions.prefix(60)) { transaction in
                                NavigationLink(value: Route.transaction(transaction.id)) {
                                    TransactionRow(transaction: transaction,
                                                   category: transaction.categoryID.flatMap { store.categoryMap[$0] },
                                                   account: store.accountMap[transaction.accountID],
                                                   counterAccount: transaction.counterAccountID.flatMap { store.accountMap[$0] },
                                                   calendar: store.periods.calendar)
                                }
                                .buttonStyle(.plain)
                                if transaction.id != transactions.prefix(60).last?.id { Hairline(inset: 52) }
                            }
                        }
                        if transactions.count > 60 {
                            NavigationLink(value: Route.filteredTransactions(TransactionFilter(accountID: account.id))) {
                                Text("Показать все \(transactions.count)")
                                    .monoFont(.subhead)
                                    .foregroundStyle(Color.mono.accentText)
                            }
                        }
                    }
                }
                .monoSurface(radius: MonoTokens.Radius.xl, padding: 16)

                VStack(spacing: 10) {
                    Button(current.isArchived ? "Вернуть из архива" : "Отправить в архив") {
                        do {
                            try store.setArchived(current, archived: !current.isArchived)
                            Haptics.success()
                        } catch {
                            toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.negative))
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Удалить счёт", role: .destructive) { confirmsDelete = true }
                        .buttonStyle(SecondaryButtonStyle(tint: Color.mono.negative))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(MonoBackdrop())
        .navigationTitle(Text(verbatim: current.displayName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Изменить") { router.present(.account(current)) }
            }
        }
        .confirmationDialog("Удалить счёт «\(current.displayName)»?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Удалить счёт и \(transactions.count) операций", role: .destructive) {
                do {
                    try store.deleteAccount(current)
                    Haptics.warning()
                    dismiss()
                } catch {
                    toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.negative))
                }
            }
        } message: {
            Text("Будут удалены все операции счёта, включая переводы с другими счетами. Если счёт больше не нужен, но история важна — отправьте его в архив.")
        }
    }

    private var syncStatus: some View {
        let integration = BankIntegrationRegistry.integration(for: current.bank)
        return Group {
            if current.bank.isBank, case .unavailable(let reason) = integration.availability {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(Color.mono.textTertiary)
                    Text(verbatim: reason(language))
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func actionButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.mono.textPrimary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.mono.surface1))
                    .overlay(Circle().strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
                Text(title)
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableStyle())
    }

    private func stat(_ title: LocalizedStringKey, value: Money, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).monoFont(.subhead).foregroundStyle(Color.mono.textSecondary)
            MoneyText(money: value, token: .title2, color: tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Корректировка: пользователь вводит фактический остаток, приложение создаёт корректировку на разницу.
struct SetBalanceView: View {
    let account: Account

    @Environment(FinanceStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyFormatter) private var formatter
    @State private var entry = AmountEntry()
    @State private var isNegative = false
    @State private var error: String?

    var body: some View {
        let current = store.balance(of: account)
        VStack(spacing: 18) {
            Capsule().fill(Color.mono.strokeStrong).frame(width: 40, height: 5).padding(.top, 8)
            Kicker("Фактический остаток")
            Text(verbatim: account.displayName).monoFont(.title).foregroundStyle(Color.mono.textPrimary)
            HStack(spacing: 6) {
                Text("Сейчас в MONO:").monoFont(.footnote).foregroundStyle(Color.mono.textSecondary)
                MoneyText(money: current, token: .footnote, color: Color.mono.textSecondary)
            }
            Text(verbatim: (isNegative ? MoneyFormatter.minus : "") + display)
                .font(.system(size: 44, weight: .semibold, design: .default).monospacedDigit())
                .tracking(-1.2)
                .foregroundStyle(entry.isEmpty ? Color.mono.textTertiary : Color.mono.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            if account.kind == .credit || current.isNegative {
                Toggle("Отрицательный остаток (долг)", isOn: $isNegative)
                    .monoFont(.callout)
                    .tint(Color.mono.negative)
                    .padding(.horizontal, 24)
            }
            if let error {
                Text(verbatim: error).monoFont(.footnote).foregroundStyle(Color.mono.negative)
            }
            Spacer(minLength: 0)
            NumberPad(allowsSeparator: account.currency.minorUnitDigits > 0, decimalSeparator: formatter.decimalSeparator) { key in
                entry.apply(key, fractionDigits: account.currency.minorUnitDigits)
            }
            .padding(.horizontal, 16)
            Button("Сохранить остаток") { save() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(entry.isEmpty)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .presentationDetents([.large])
    }

    private var display: String {
        guard let money = entry.money(currency: account.currency) else { return "0" }
        return formatter.number(money, fraction: entry.text.contains(".") ? .always : .automatic) + " " + formatter.symbol(for: account.currency).text
    }

    private func save() {
        guard var target = entry.money(currency: account.currency) else { return }
        if isNegative { target = target.negated }
        do {
            let adjustment = try store.setBalance(of: account, to: target)
            Haptics.success()
            toasts.show(ToastMessage(text: adjustment == nil ? String(localized: "Остаток совпадает — корректировка не нужна") : String(localized: "Остаток обновлён")))
            dismiss()
        } catch {
            self.error = AppError(error).message
            Haptics.error()
        }
    }
}
