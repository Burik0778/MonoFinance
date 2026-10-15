import SwiftUI
import Charts
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

// MARK: - График движения денег

struct FlowChartCard: View {
    let analytics: AnalyticsEngine
    @Binding var period: PeriodPreset
    let now: Date

    @State private var selectedDate: Date?
    @Environment(\.appLanguage) private var language

    var body: some View {
        let points = analytics.balanceHistory(analytics.periods.range(for: period, now: now))
        let selected = nearest(to: selectedDate, in: points)
        let values = points.map(\.balance.chartValue)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.18, max(abs(high) * 0.01, 1))
        let domain = (low - pad)...(high + pad)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Движение денег")
                    if let selected {
                        MoneyText(money: selected.balance, token: .title2)
                        Text(verbatim: DateFormatting.weekdayDay(selected.date, calendar: analytics.periods.calendar, language: language))
                            .monoFont(.footnote)
                            .foregroundStyle(Color.mono.textSecondary)
                    } else {
                        Text("Баланс на конец дня")
                            .monoFont(.title2)
                            .foregroundStyle(Color.mono.textPrimary)
                        Text("Проведите по графику, чтобы увидеть сумму")
                            .monoFont(.footnote)
                            .foregroundStyle(Color.mono.textTertiary)
                    }
                }
                Spacer()
            }
            .frame(minHeight: 56, alignment: .top)

            if points.count > 1 {
                Chart(points) { point in
                    AreaMark(
                        x: .value("Дата", point.date),
                        yStart: .value("Основание", domain.lowerBound),
                        yEnd: .value("Баланс", point.balance.chartValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(colors: [Color.mono.electric.opacity(0.42), Color.mono.violet.opacity(0.0)], startPoint: .top, endPoint: .bottom)
                    )
                    LineMark(x: .value("Дата", point.date), y: .value("Баланс", point.balance.chartValue))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(LinearGradient(colors: [Color.mono.cyan, Color.mono.electric, Color.mono.violet], startPoint: .leading, endPoint: .trailing))
                    if let selected, selected.date == point.date {
                        RuleMark(x: .value("Дата", point.date))
                            .foregroundStyle(Color.mono.strokeStrong)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        PointMark(x: .value("Дата", point.date), y: .value("Баланс", point.balance.chartValue))
                            .symbolSize(90)
                            .foregroundStyle(Color.white)
                    }
                }
                .chartYScale(domain: domain)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(Color.mono.textTertiary)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: 170)
                .sensoryFeedback(.selection, trigger: selected?.date)
                .accessibilityLabel(Text("График баланса"))
            } else {
                Text("График появится после первых операций")
                    .monoFont(.callout)
                    .foregroundStyle(Color.mono.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            SegmentedPills(options: [.last7Days, .last30Days, .last90Days, .last365Days], selection: $period,
                           title: { $0.shortTitle(language) }, stretch: true)
        }
        .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
        .onChange(of: period) { _, _ in selectedDate = nil }
    }

    private func nearest(to date: Date?, in points: [BalancePoint]) -> BalancePoint? {
        guard let date else { return nil }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
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
                Kicker("Ожидают подтверждения", color: Color.mono.tangerine)
                ForEach(due) { rule in
                    HStack(spacing: 12) {
                        CategoryGlyph(category: rule.categoryID.flatMap { store.categoryMap[$0] }, kind: rule.kind, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: rule.title).monoFont(.body).foregroundStyle(Color.mono.textPrimary)
                            MoneyText(money: rule.amount, token: .footnote, color: Color.mono.textSecondary)
                        }
                        Spacer()
                        Button("Пропустить") {
                            do { try store.skipRecurring(rule) } catch { toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.coral)) }
                        }
                        .buttonStyle(ChipStyle())
                        Button("Записать") {
                            do {
                                try store.confirmRecurring(rule)
                                Haptics.success()
                                toasts.show(ToastMessage(text: String(localized: "Платёж записан")))
                            } catch {
                                toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.coral))
                            }
                        }
                        .buttonStyle(ChipStyle(isSelected: true))
                    }
                }
            }
            .monoSurface(radius: MonoTokens.Radius.xl, padding: 16)
        }
    }
}

// MARK: - Счета

struct AccountsStrip: View {
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.zoomNamespace) private var zoomNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(kicker: "Счета и карты", title: "Кошелёк") {
                NavigationLink(value: Route.accounts) {
                    Text("Все")
                        .monoFont(.subhead)
                        .foregroundStyle(Color.mono.electric)
                }
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(store.activeAccounts) { account in
                        NavigationLink(value: Route.account(account.id)) {
                            VirtualCardView(account: account, balance: store.balance(of: account), style: .compact)
                                .frame(width: 236, height: 148)
                        }
                        .buttonStyle(PressableStyle(scale: 0.97))
                        .modifier(ZoomSource(id: account.id, namespace: zoomNamespace))
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.92)
                                .rotation3DEffect(.degrees(phase.value * -10), axis: (x: 0, y: 1, z: 0))
                                .opacity(phase.isIdentity ? 1 : 0.75)
                        }
                    }
                    Button { router.present(.account(nil)) } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color.mono.electric)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(Color.mono.electric.opacity(0.14)))
                            Text("Новый счёт")
                                .monoFont(.subhead)
                                .foregroundStyle(Color.mono.textSecondary)
                        }
                        .frame(width: 140, height: 148)
                        .background(
                            RoundedRectangle(cornerRadius: MonoTokens.Radius.lg, style: .continuous)
                                .strokeBorder(Color.mono.strokeStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                        )
                    }
                    .buttonStyle(PressableStyle())
                }
                .scrollTargetLayout()
                .padding(.vertical, 18)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .padding(.horizontal, -20)
            .padding(.vertical, -18)
        }
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

// MARK: - Категории

struct TopCategoriesSection: View {
    let items: [CategoryAmount]
    let total: Money

    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(kicker: "Куда уходят деньги", title: "Этот месяц") {
                Button {
                    Haptics.selection()
                    withMonoAnimation(.quick) { router.tab = .analytics }
                } label: {
                    Text("Аналитика").monoFont(.subhead).foregroundStyle(Color.mono.electric)
                }
            }
            if items.isEmpty {
                Text("Расходов в этом месяце пока нет")
                    .monoFont(.callout)
                    .foregroundStyle(Color.mono.textTertiary)
            } else {
                LiquidityBar(segments: items.prefix(6).map { item in
                    LiquidityBar.Segment(id: item.categoryID ?? UUID(), color: color(for: item), value: item.share)
                }, height: 10)
                VStack(spacing: 4) {
                    ForEach(items.prefix(4)) { item in
                        NavigationLink(value: Route.filteredTransactions(TransactionFilter(categoryID: item.categoryID, range: store.periods.range(for: .thisMonth, now: Date())))) {
                            HStack(spacing: 12) {
                                CategoryGlyph(category: item.categoryID.flatMap { store.categoryMap[$0] }, kind: .expense, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: name(for: item))
                                        .monoFont(.body)
                                        .foregroundStyle(Color.mono.textPrimary)
                                        .lineLimit(1)
                                    Text(verbatim: "\(Int((item.share * 100).rounded()))%")
                                        .monoFont(.caption, digits: true)
                                        .foregroundStyle(Color.mono.textTertiary)
                                }
                                Spacer()
                                MoneyText(money: item.amount, token: .amountRow)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
    }

    private func color(for item: CategoryAmount) -> Color {
        item.categoryID.flatMap { store.categoryMap[$0]?.color.color } ?? Color.mono.steel
    }

    private func name(for item: CategoryAmount) -> String {
        item.categoryID.flatMap { store.categoryMap[$0]?.name } ?? String(localized: "Без категории")
    }
}

// MARK: - Инсайты

struct InsightsSection: View {
    let insights: [Insight]
    @State private var page: Int? = 0

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Kicker("Наблюдения")
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
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
                if insights.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<insights.count, id: \.self) { index in
                            Capsule()
                                .fill(index == (page ?? 0) ? Color.mono.textPrimary : Color.mono.strokeStrong)
                                .frame(width: index == (page ?? 0) ? 18 : 6, height: 6)
                        }
                    }
                    .monoAnimation(.quick, value: page)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                }
            }
        }
    }
}

// MARK: - Последние операции

struct RecentTransactionsSection: View {
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(kicker: "Последние операции") {
                Button {
                    Haptics.selection()
                    withMonoAnimation(.quick) { router.tab = .transactions }
                } label: {
                    Text("Все").monoFont(.subhead).foregroundStyle(Color.mono.electric)
                }
            }
            let recent = Array(store.transactions.filter { !$0.isOpeningBalance }.prefix(6))
            if recent.isEmpty {
                Text("Операций пока нет. Нажмите на микрофон и скажите, например: «Потратил 85 тысяч на обед».")
                    .monoFont(.callout)
                    .foregroundStyle(Color.mono.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
                        }
                        .buttonStyle(.plain)
                        if transaction.id != recent.last?.id {
                            Rectangle().fill(Color.mono.strokeSubtle).frame(height: 1).padding(.leading, 54)
                        }
                    }
                }
            }
        }
        .monoSurface(radius: MonoTokens.Radius.xl, padding: 16)
    }
}
