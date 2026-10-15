import SwiftUI
import MonoCore
import MonoAnalytics
import MonoIntelligence

extension Money {
    /// Значение для графиков (основные единицы). Только для отображения — расчёты остаются в `Money`.
    var chartValue: Double { NSDecimalNumber(decimal: majorValue).doubleValue }
}

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// Пространство имён для zoom-перехода «карта → экран счёта».
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

/// Источник zoom-перехода, если пространство имён доступно.
struct ZoomSource: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

struct ZoomDestination: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

/// Заголовок модуля на главных экранах: крупное название и ссылка справа.
struct ModuleHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let trailing: Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .monoFont(.title)
                .foregroundStyle(Color.mono.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension ModuleHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title) { EmptyView() }
    }
}

// MARK: - Регулярные платежи к подтверждению

struct DueRecurringSection: View {
    let now: Date
    @Environment(FinanceStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        let due = store.dueRecurring(now: now)
        if !due.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(Color.mono.warning).frame(width: 6, height: 6)
                    Kicker("Ожидают подтверждения")
                }
                VStack(spacing: 0) {
                    ForEach(due) { rule in
                        HStack(spacing: 12) {
                            CategoryGlyph(category: rule.categoryID.flatMap { store.categoryMap[$0] }, kind: rule.kind, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: rule.title).monoFont(.body).foregroundStyle(Color.mono.textPrimary).lineLimit(1)
                                MoneyText(money: rule.amount, token: .footnote, color: Color.mono.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Button("Пропустить") {
                                do { try store.skipRecurring(rule) } catch { toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.negative)) }
                            }
                            .buttonStyle(ChipStyle())
                            Button("Записать") {
                                do {
                                    try store.confirmRecurring(rule)
                                    Haptics.success()
                                    toasts.show(ToastMessage(text: String(localized: "Платёж записан")))
                                } catch {
                                    toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.negative))
                                }
                            }
                            .buttonStyle(ChipStyle(isSelected: true))
                        }
                        .padding(.vertical, 8)
                        if rule.id != due.last?.id { Hairline(inset: 50) }
                    }
                }
            }
            .monoSurface(radius: MonoTokens.Radius.xl, padding: 16)
        }
    }
}

// MARK: - Счета

/// Счета списком: миниатюра карты, название, банк и последние цифры, остаток и доля в общем балансе.
/// Список вместо карусели — все остатки видны сразу, без прокрутки вбок.
struct AccountsSection: View {
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.appLanguage) private var language

    var body: some View {
        let accounts = store.activeAccounts
        let converter = store.converter
        let baseValues: [UUID: Int64] = Dictionary(uniqueKeysWithValues: accounts.compactMap { account -> (UUID, Int64)? in
            guard account.includeInTotal, let base = converter.toBase(store.balance(of: account)) else { return nil }
            return (account.id, max(0, base.minorUnits))
        })
        let totalBase = baseValues.values.reduce(0, +)

        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader("Счета") {
                SectionLink(title: "Карты") { router.open(.accounts) }
            }
            VStack(spacing: 0) {
                ForEach(accounts) { account in
                    NavigationLink(value: Route.account(account.id)) {
                        row(account, share: totalBase > 0 ? baseValues[account.id].map { Double($0) / Double(totalBase) } : nil)
                    }
                    .buttonStyle(.plain)
                    .modifier(ZoomSource(id: account.id, namespace: zoomNamespace))
                    .contextMenu {
                        Button { router.newTransaction(.expense, accountID: account.id) } label: { Label("Новая операция", systemImage: "plus") }
                        Button { router.present(.setBalance(account)) } label: { Label("Корректировка баланса", systemImage: "slider.horizontal.3") }
                        Button { router.present(.account(account)) } label: { Label("Изменить", systemImage: "pencil") }
                    }
                    Hairline(inset: 72)
                }
                Button {
                    Haptics.tap()
                    router.present(.account(nil))
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.mono.accentText)
                            .frame(width: 44, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.mono.strokeStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        Text("Добавить счёт")
                            .monoFont(.callout)
                            .foregroundStyle(Color.mono.accentText)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
            .monoSurface(radius: MonoTokens.Radius.xl, padding: 0)
        }
    }

    private func row(_ account: Account, share: Double?) -> some View {
        HStack(spacing: 14) {
            CardThumbnail(skin: account.skin, width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: account.displayName)
                    .monoFont(.body)
                    .foregroundStyle(Color.mono.textPrimary)
                    .lineLimit(1)
                Text(verbatim: subtitle(account))
                    .monoFont(.footnote)
                    .foregroundStyle(Color.mono.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                MoneyText(money: store.balance(of: account), token: .amountRow)
                if let share, store.activeAccounts.count > 1 {
                    Text(verbatim: PercentFormatting.string(share, language: language))
                        .monoFont(.caption, digits: true)
                        .foregroundStyle(Color.mono.textTertiary)
                } else if account.currency != store.baseCurrency {
                    Text(verbatim: account.currency.code)
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.textTertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func subtitle(_ account: Account) -> String {
        var parts = [account.bank.displayName]
        if let masked = account.maskedNumber { parts.append(masked) }
        if !account.includeInTotal { parts.append(Phrase(ru: "не в итоге", uz: "jamida emas", en: "not in total")(language)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Инсайты

struct InsightsSection: View {
    let insights: [Insight]
    @State private var page: Int? = 0

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Kicker("Наблюдения")
                    Spacer()
                    if insights.count > 1 {
                        HStack(spacing: 5) {
                            ForEach(0..<insights.count, id: \.self) { index in
                                Capsule()
                                    .fill(index == (page ?? 0) ? Color.mono.textPrimary : Color.mono.strokeStrong)
                                    .frame(width: index == (page ?? 0) ? 14 : 5, height: 5)
                            }
                        }
                        .monoAnimation(.quick, value: page)
                        .accessibilityHidden(true)
                    }
                }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                            InsightQuoteView(insight: insight)
                                .containerRelativeFrame(.horizontal)
                                .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)
            }
        }
    }
}

// MARK: - Последние операции

struct RecentTransactionsSection: View {
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let recent = Array(store.transactions.filter { !$0.isOpeningBalance }.prefix(5))
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader("Операции") {
                SectionLink(title: "Все") { withMonoAnimation(.quick) { router.tab = .transactions } }
            }
            Group {
                if recent.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "mic")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.mono.accentText)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.mono.surface2))
                        Text("Операций пока нет. Нажмите на микрофон и скажите, например: «Потратил 85 тысяч на обед».")
                            .monoFont(.callout)
                            .foregroundStyle(Color.mono.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(recent) { transaction in
                            NavigationLink(value: Route.transaction(transaction.id)) {
                                TransactionRow(
                                    transaction: transaction,
                                    category: transaction.categoryID.flatMap { store.categoryMap[$0] },
                                    account: store.accountMap[transaction.accountID],
                                    counterAccount: transaction.counterAccountID.flatMap { store.accountMap[$0] },
                                    calendar: store.periods.calendar
                                )
                                .padding(.horizontal, 14)
                            }
                            .buttonStyle(.plain)
                            if transaction.id != recent.last?.id {
                                Hairline(inset: 66)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .monoSurface(radius: MonoTokens.Radius.xl, padding: 0)
        }
    }
}
