import SwiftUI
import MonoCore
import MonoAnalytics

/// Период аналитики.
enum AnalyticsScope: String, Hashable, CaseIterable, Identifiable {
    case month
    case last30
    case last90
    case year

    var id: String { rawValue }

    var title: Phrase {
        switch self {
        case .month: return Phrase(ru: "Месяц", uz: "Oy", en: "Month")
        case .last30: return Phrase(ru: "30 дней", uz: "30 kun", en: "30 days")
        case .last90: return Phrase(ru: "90 дней", uz: "90 kun", en: "90 days")
        case .year: return Phrase(ru: "Год", uz: "Yil", en: "Year")
        }
    }

    var granularity: Granularity {
        switch self {
        case .month, .last30: return .day
        case .last90: return .week
        case .year: return .month
        }
    }
}

/// Все цифры экрана за один проход — из `AnalyticsEngine`, без выдуманных данных.
struct AnalyticsReport {
    let range: DateRange
    let previousRange: DateRange
    let summary: PeriodSummary
    let comparison: PeriodComparison
    let categories: [CategoryAmount]
    let incomeCategories: [CategoryAmount]
    let series: [SeriesPoint]
    let granularity: Granularity
    let merchants: [MerchantStat]
    let flows: [AccountFlow]
    let split: MandatorySplit
    let unusual: [UnusualExpense]
    let averageDaily: Money
    /// Для текущего месяца: сравнение «с начала месяца» с тем же числом прошлого месяца.
    let monthToDate: (current: Money, previous: Money, day: Int)?
    let projectedMonth: Money?

    @MainActor
    init(analytics: AnalyticsEngine, scope: AnalyticsScope, month: MonthKey, now: Date) {
        let periods = analytics.periods
        switch scope {
        case .month:
            range = periods.monthRange(month)
            previousRange = periods.monthRange(month.previous)
        case .last30:
            range = periods.range(for: .last30Days, now: now)
            previousRange = periods.previousRange(of: range)
        case .last90:
            range = periods.range(for: .last90Days, now: now)
            previousRange = periods.previousRange(of: range)
        case .year:
            range = periods.range(for: .last365Days, now: now)
            previousRange = periods.previousRange(of: range)
        }
        granularity = scope.granularity
        summary = analytics.summary(range)
        comparison = analytics.compare(range, with: previousRange)
        categories = analytics.spendingByCategory(range)
        incomeCategories = analytics.incomeByCategory(range)
        series = analytics.series(range, granularity: scope.granularity)
        merchants = analytics.topMerchants(range, limit: 6)
        flows = analytics.flowsByAccount(range)
        split = analytics.mandatorySplit(range)
        unusual = analytics.unusualExpenses(range, limit: 4)
        averageDaily = analytics.averageDailySpending(range, now: now)
        let isCurrentMonth = scope == .month && month == periods.monthKey(now)
        monthToDate = isCurrentMonth ? analytics.monthToDate(now: now) : nil
        projectedMonth = isCurrentMonth ? analytics.projectedMonthSpending(now: now) : nil
    }
}

/// Аналитика: редакционный «разворот» месяца — главная цифра, структура расходов, динамика, сравнения.
struct AnalyticsView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language
    @State private var scope: AnalyticsScope = .month
    @State private var month: MonthKey?

    var body: some View {
        let now = Date()
        let analytics = store.analytics()
        let currentMonth = store.periods.monthKey(now)
        let selectedMonth = month ?? currentMonth
        let report = AnalyticsReport(analytics: analytics, scope: scope, month: selectedMonth, now: now)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                periodControls(selectedMonth: selectedMonth, currentMonth: currentMonth)
                if store.transactions.isEmpty {
                    EmptyStateView(symbol: "chart.pie", title: "Пока нечего анализировать",
                                   message: "Добавьте операции вручную, голосом или импортом выписки — графики построятся по реальным данным.") {
                        Button("Добавить операцию") { router.newTransaction(.expense) }
                            .buttonStyle(PrimaryButtonStyle())
                            .frame(maxWidth: 260)
                    }
                    .monoSurface(radius: MonoTokens.Radius.xl, padding: 8)
                } else {
                    if !report.summary.excludedCurrencies.isEmpty {
                        MissingRatesNote(currencies: report.summary.excludedCurrencies)
                    }
                    SpendingHeadline(report: report, scope: scope, month: selectedMonth)
                        .riseIn()
                    LedgerStrip(summary: report.summary)
                        .riseIn(delay: 0.04)
                    if report.summary.isEmpty {
                        Text("За этот период операций нет.")
                            .monoFont(.callout)
                            .foregroundStyle(Color.mono.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        CategoryDonutCard(items: report.categories, total: report.summary.spending, range: report.range)
                            .riseIn(delay: 0.08)
                        TrendCard(points: report.series, granularity: report.granularity, calendar: store.periods.calendar)
                        CategoryChangesCard(comparison: report.comparison, scope: scope)
                        MandatorySplitCard(split: report.split)
                        if !report.merchants.isEmpty {
                            MerchantsCard(merchants: report.merchants, range: report.range)
                        }
                        if report.flows.count > 1 {
                            AccountFlowsCard(flows: report.flows, range: report.range)
                        }
                        if !report.incomeCategories.isEmpty {
                            IncomeSourcesCard(items: report.incomeCategories, total: report.summary.income)
                        }
                        if !report.unusual.isEmpty {
                            UnusualExpensesCard(items: report.unusual)
                        }
                    }
                    RecurringCandidatesCard(candidates: analytics.recurringCandidates(now: now))
                    ForecastCard(forecast: analytics.savingsForecast(months: 3, now: now, planned: store.planned))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(DebugFlags.scrollAnchor)
        .background(MonoBackdrop(haze: true))
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { store.reload() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Kicker("Аналитика")
                Text("Куда уходят деньги")
                    .monoFont(.display)
                    .foregroundStyle(Color.mono.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            IconButton(systemName: "sparkles", label: "Спросить MONO", tint: Color.mono.accent) {
                router.present(.assistant)
            }
        }
    }

    @ViewBuilder
    private func periodControls(selectedMonth: MonthKey, currentMonth: MonthKey) -> some View {
        VStack(spacing: 12) {
            SegmentedPills(options: AnalyticsScope.allCases, selection: $scope, title: { $0.title(language) }, stretch: true)
            if scope == .month {
                HStack {
                    Button {
                        Haptics.selection()
                        withMonoAnimation(.quick) { month = selectedMonth.previous }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel(Text("Предыдущий месяц"))
                    Spacer()
                    Text(verbatim: DateFormatting.monthTitle(selectedMonth, calendar: store.periods.calendar, language: language,
                                                             includeYear: selectedMonth.year != currentMonth.year))
                        .monoFont(.title2)
                        .foregroundStyle(Color.mono.textPrimary)
                        .contentTransition(.opacity)
                    Spacer()
                    Button {
                        Haptics.selection()
                        withMonoAnimation(.quick) { month = selectedMonth.next }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 40, height: 40)
                    }
                    .disabled(selectedMonth >= currentMonth)
                    .accessibilityLabel(Text("Следующий месяц"))
                }
                .foregroundStyle(Color.mono.textPrimary)
                .gesture(
                    DragGesture(minimumDistance: 30).onEnded { value in
                        if value.translation.width > 60 {
                            withMonoAnimation(.quick) { month = selectedMonth.previous }
                        } else if value.translation.width < -60, selectedMonth < currentMonth {
                            withMonoAnimation(.quick) { month = selectedMonth.next }
                        }
                    }
                )
            }
        }
    }
}

/// Предупреждение: часть операций в валюте без курса не попала в итоги.
struct MissingRatesNote: View {
    let currencies: Set<Currency>
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            router.open(.exchangeRates)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.mono.warning)
                Text("Не учтены операции в \(currencies.map(\.code).sorted().joined(separator: ", ")): нет курса. Добавьте курс, чтобы итоги были полными.")
                    .monoFont(.footnote)
                    .foregroundStyle(Color.mono.textSecondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.mono.textTertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.warning.opacity(0.1)))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }
}
