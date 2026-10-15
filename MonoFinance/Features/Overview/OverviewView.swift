import SwiftUI
import Charts
import MonoCore
import MonoAnalytics
import MonoIntelligence

/// Главный экран. Иерархия: сколько у меня денег → как это меняется → что с месяцем → где лежат деньги → что произошло.
/// Карточек немного: герой и график лежат прямо на фоне, поверхности — только у модулей со строками.
struct OverviewView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language
    @State private var period: PeriodPreset = .last30Days

    var body: some View {
        let now = Date()
        let analytics = store.analytics()
        let monthRange = store.periods.range(for: .thisMonth, now: now)
        let month = analytics.summary(monthRange)
        let total = analytics.totalBalance()

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                OverviewHeader(now: now)
                if store.activeAccounts.isEmpty {
                    EmptyStateView(symbol: "creditcard", title: "Добавьте первый счёт",
                                   message: "Карта, вклад или наличные. Укажите реальный остаток — дальше MONO посчитает всё сам.") {
                        Button("Добавить счёт") { router.present(.account(nil)) }
                            .buttonStyle(PrimaryButtonStyle())
                            .frame(maxWidth: 260)
                    }
                    .monoSurface(radius: MonoTokens.Radius.xl, padding: 8)
                } else {
                    BalanceHero(total: total.total, excluded: total.excluded, analytics: analytics, period: $period, now: now)
                        .riseIn()
                    VStack(spacing: 14) {
                        VoiceCommandBar()
                        QuickActionsRow()
                    }
                    .riseIn(delay: 0.05)
                    MonthModule(summary: month, categories: analytics.spendingByCategory(monthRange),
                                mtd: analytics.monthToDate(now: now), now: now)
                        .riseIn(delay: 0.1)
                    DueRecurringSection(now: now)
                    AccountsSection()
                    InsightsSection(insights: InsightEngine(analytics: analytics, budgets: store.budgets, recurring: store.recurring, language: language, now: now).insights())
                    RecentTransactionsSection()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(DebugFlags.scrollAnchor)
        .background(MonoBackdrop(haze: true))
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { store.reload() }
    }
}

private struct OverviewHeader: View {
    let now: Date
    @Environment(Router.self) private var router
    @Environment(FinanceStore.self) private var store
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: DateFormatting.weekdayDay(now, calendar: store.periods.calendar, language: language))
                    .textCase(.uppercase)
                    .monoFont(.kicker)
                    .foregroundStyle(Color.mono.textTertiary)
                Text(verbatim: "MONO")
                    .font(.system(size: 21, weight: .heavy).width(.expanded))
                    .tracking(1)
                    .foregroundStyle(Color.mono.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            IconButton(systemName: "sparkles", label: "Спросить MONO", tint: Color.mono.accentText) {
                router.present(.assistant)
            }
            IconButton(systemName: "gearshape", label: "Настройки") {
                router.open(.settings)
            }
        }
    }
}

// MARK: - Герой: баланс и его движение

/// Общий баланс и график. Проведите по графику — сумма в герое покажет баланс на выбранный день.
private struct BalanceHero: View {
    let total: Money
    let excluded: Set<Currency>
    let analytics: AnalyticsEngine
    @Binding var period: PeriodPreset
    let now: Date

    @State private var selectedDate: Date?
    @Environment(SettingsStore.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language
    @Environment(\.hideAmounts) private var hideAmounts

    var body: some View {
        let points = analytics.balanceHistory(analytics.periods.range(for: period, now: now))
        let selected = nearest(to: selectedDate, in: points)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Group {
                    if let selected {
                        Text(verbatim: DateFormatting.weekdayDay(selected.date, calendar: analytics.periods.calendar, language: language))
                    } else {
                        Text("Всего на счетах")
                    }
                }
                .textCase(.uppercase)
                .monoFont(.kicker)
                .foregroundStyle(selected == nil ? Color.mono.textTertiary : Color.mono.accentText)
                .contentTransition(.opacity)
                Spacer()
                Button {
                    Haptics.soft()
                    withMonoAnimation(.quick) { settings.hideAmounts.toggle() }
                } label: {
                    Image(systemName: settings.hideAmounts ? "eye.slash" : "eye")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mono.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel(settings.hideAmounts ? Text("Показать суммы") : Text("Скрыть суммы"))
            }

            HeroAmount(money: selected?.balance ?? total)
                .onTapGesture(count: 2) {
                    Haptics.soft()
                    withMonoAnimation(.quick) { settings.hideAmounts.toggle() }
                }

            HStack(spacing: 8) {
                if let first = points.first, let last = points.last {
                    let end = selected ?? last
                    DeltaBadge(delta: end.balance - first.balance, caption: Text(verbatim: periodCaption))
                }
                if !excluded.isEmpty {
                    Button {
                        router.open(.exchangeRates)
                    } label: {
                        Label {
                            Text(verbatim: excluded.map(\.code).sorted().joined(separator: ", "))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.warning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.mono.warning.opacity(0.12)))
                    }
                    .accessibilityLabel(Text("Нет курса для части валют — не включены в общий баланс"))
                }
            }

            chart(points: points, selected: selected)
                .padding(.top, 8)

            SegmentedPills(options: [.last7Days, .last30Days, .last90Days, .last365Days], selection: $period,
                           title: { $0.shortTitle(language) }, stretch: true)
        }
        .onChange(of: period) { _, _ in selectedDate = nil }
    }

    @ViewBuilder
    private func chart(points: [BalancePoint], selected: BalancePoint?) -> some View {
        if points.count > 1 {
            let values = points.map(\.balance.chartValue)
            let low = values.min() ?? 0
            let high = values.max() ?? 1
            let pad = max((high - low) * 0.2, max(abs(high) * 0.01, 1))
            let domain = (low - pad)...(high + pad)
            let start = values.first ?? 0

            Chart {
                RuleMark(y: .value("Начало периода", start))
                    .foregroundStyle(Color.mono.strokeStrong)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Дата", point.date),
                        yStart: .value("Основание", domain.lowerBound),
                        yEnd: .value("Баланс", point.balance.chartValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(colors: [Color.mono.accent.opacity(0.26), Color.mono.accent.opacity(0)], startPoint: .top, endPoint: .bottom)
                    )
                    LineMark(x: .value("Дата", point.date), y: .value("Баланс", point.balance.chartValue))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Color.mono.accentText)
                }
                if let selected {
                    RuleMark(x: .value("Дата", selected.date))
                        .foregroundStyle(Color.mono.textTertiary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Дата", selected.date), y: .value("Баланс", selected.balance.chartValue))
                        .symbolSize(70)
                        .foregroundStyle(Color.mono.textPrimary)
                } else if let last = points.last {
                    PointMark(x: .value("Дата", last.date), y: .value("Баланс", last.balance.chartValue))
                        .symbolSize(40)
                        .foregroundStyle(Color.mono.accentText)
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
            .frame(height: 140)
            .sensoryFeedback(.selection, trigger: selected?.date)
            .monoAnimation(.standard, value: period)
            .accessibilityLabel(Text("График баланса"))
            .accessibilityHint(Text("Проведите пальцем, чтобы увидеть баланс на выбранный день"))
        } else {
            Text("График появится после первых операций")
                .monoFont(.footnote)
                .foregroundStyle(Color.mono.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    private var periodCaption: String {
        switch period {
        case .last7Days: return Phrase(ru: "за 7 дней", uz: "7 kunda", en: "in 7 days")(language)
        case .last30Days: return Phrase(ru: "за 30 дней", uz: "30 kunda", en: "in 30 days")(language)
        case .last90Days: return Phrase(ru: "за 90 дней", uz: "90 kunda", en: "in 90 days")(language)
        case .last365Days: return Phrase(ru: "за год", uz: "bir yilda", en: "in a year")(language)
        default: return ""
        }
    }

    private func nearest(to date: Date?, in points: [BalancePoint]) -> BalancePoint? {
        guard let date else { return nil }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

// MARK: - Быстрый ввод

/// Командная строка: самый короткий путь к новой операции — сказать её.
private struct VoiceCommandBar: View {
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            Haptics.tap()
            router.present(.voice(prefill: nil))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.mono.onAccent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.mono.accent))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Скажите операцию")
                        .monoFont(.headline)
                        .foregroundStyle(Color.mono.textPrimary)
                    Text("«Потратил 85 тысяч на обед»")
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.mono.textTertiary)
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(Color.mono.surface1))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.mono.strokeStrong, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityLabel(Text("Голосовой ввод операции"))
    }
}

/// Быстрые действия: расход, доход, перевод и остальное в меню.
private struct QuickActionsRow: View {
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 0) {
            action("Расход", symbol: "arrow.up.right") { router.newTransaction(.expense) }
            action("Доход", symbol: "arrow.down.left") { router.newTransaction(.income) }
            action("Перевод", symbol: "arrow.left.arrow.right") { router.newTransaction(.transfer) }
            Menu {
                Button { router.present(.importStatement(nil)) } label: { Label("Импорт выписки", systemImage: "tray.and.arrow.down") }
                Button { router.newTransaction(.refund) } label: { Label("Возврат", systemImage: "arrow.uturn.backward") }
                Button { router.newTransaction(.fee) } label: { Label("Комиссия", systemImage: "percent") }
                Button { router.open(.accounts) } label: { Label("Корректировка баланса", systemImage: "slider.horizontal.3") }
            } label: {
                label("Ещё", symbol: "ellipsis")
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text("Другие действия"))
        }
    }

    private func action(_ title: LocalizedStringKey, symbol: String, perform: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            perform()
        } label: {
            label(title, symbol: symbol)
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .frame(maxWidth: .infinity)
    }

    private func label(_ title: LocalizedStringKey, symbol: String) -> some View {
        VStack(spacing: 7) {
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
        .contentShape(Rectangle())
    }
}

// MARK: - Месяц

/// Месяц одним модулем: доходы, расходы, итог, темп относительно прошлого месяца и куда уходят деньги.
private struct MonthModule: View {
    let summary: PeriodSummary
    let categories: [CategoryAmount]
    let mtd: (current: Money, previous: Money, day: Int)
    let now: Date

    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Этот месяц")
                    Text(verbatim: DateFormatting.monthTitle(store.periods.monthKey(now), calendar: store.periods.calendar, language: language, includeYear: false))
                        .monoFont(.title)
                        .foregroundStyle(Color.mono.textPrimary)
                }
                Spacer()
                SectionLink(title: "Аналитика") { withMonoAnimation(.quick) { router.tab = .analytics } }
            }

            HStack(alignment: .top, spacing: 12) {
                metric("Доходы", money: summary.income, sign: .always, color: summary.income.isZero ? Color.mono.textPrimary : Color.mono.positive)
                metric("Расходы", money: summary.outflow, sign: .automatic, color: Color.mono.textPrimary)
                metric("Итог", money: summary.net, sign: .always, color: summary.net.isNegative ? Color.mono.negative : Color.mono.textPrimary)
            }

            paceLine

            if categories.isEmpty {
                Text("Расходов в этом месяце пока нет")
                    .monoFont(.callout)
                    .foregroundStyle(Color.mono.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    LiquidityBar(segments: segments, height: 8)
                    VStack(spacing: 0) {
                        ForEach(Array(categories.prefix(3).enumerated()), id: \.element.id) { index, item in
                            NavigationLink(value: Route.filteredTransactions(TransactionFilter(categoryID: item.categoryID, range: store.periods.range(for: .thisMonth, now: now)))) {
                                categoryRow(item, color: Color.mono.chart(index))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
    }

    private static let uncategorizedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private var segments: [LiquidityBar.Segment] {
        let top = Array(categories.prefix(5))
        var result = top.enumerated().map { index, item in
            LiquidityBar.Segment(id: item.categoryID ?? Self.uncategorizedID, color: Color.mono.chart(index), value: item.share)
        }
        let rest = categories.dropFirst(5).reduce(0.0) { $0 + $1.share }
        if rest > 0 { result.append(LiquidityBar.Segment(id: Self.otherID, color: Color.mono.neutral, value: rest)) }
        return result
    }

    private func metric(_ title: LocalizedStringKey, money: Money, sign: MoneyFormatter.SignDisplay, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .monoFont(.caption)
                .foregroundStyle(Color.mono.textTertiary)
            MoneyText(money: money, token: .headline, sign: sign, color: color, compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paceLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if mtd.previous.minorUnits > 0 {
                let ratio = Double(mtd.current.minorUnits - mtd.previous.minorUnits) / Double(mtd.previous.minorUnits)
                Image(systemName: ratio <= 0 ? "arrow.down.right" : "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ratio <= 0 ? Color.mono.positive : Color.mono.negative)
                Text(verbatim: comparisonText(ratio))
                    .monoFont(.footnote)
                    .foregroundStyle(Color.mono.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Сравнение появится, когда накопится история за прошлый месяц")
                    .monoFont(.footnote)
                    .foregroundStyle(Color.mono.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func categoryRow(_ item: CategoryAmount, color: Color) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(verbatim: item.categoryID.flatMap { store.categoryMap[$0]?.name } ?? String(localized: "Без категории"))
                .monoFont(.callout)
                .foregroundStyle(Color.mono.textPrimary)
                .lineLimit(1)
            Text(verbatim: PercentFormatting.string(item.share, language: language))
                .monoFont(.caption, digits: true)
                .foregroundStyle(Color.mono.textTertiary)
            Spacer(minLength: 8)
            MoneyText(money: item.amount, token: .subhead)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private func comparisonText(_ ratio: Double) -> String {
        let percent = Int((abs(ratio) * 100).rounded())
        if ratio <= 0 {
            return Phrase(ru: "На \(percent)% меньше трат, чем к \(mtd.day)-му числу прошлого месяца",
                          uz: "O‘tgan oyning \(mtd.day)-kuniga nisbatan \(percent)% kam",
                          en: "\(percent)% less than by day \(mtd.day) last month")(language)
        }
        return Phrase(ru: "На \(percent)% больше трат, чем к \(mtd.day)-му числу прошлого месяца",
                      uz: "O‘tgan oyning \(mtd.day)-kuniga nisbatan \(percent)% ko‘p",
                      en: "\(percent)% more than by day \(mtd.day) last month")(language)
    }
}
