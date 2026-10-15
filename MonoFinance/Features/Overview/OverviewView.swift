import SwiftUI
import MonoCore
import MonoAnalytics
import MonoIntelligence

/// Главный экран: за 3–5 секунд понятно текущее положение — баланс, его движение, месяц, счета, куда уходят деньги.
struct OverviewView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(SettingsStore.self) private var settings
    @Environment(\.appLanguage) private var language
    @State private var period: PeriodPreset = .last30Days

    var body: some View {
        let now = Date()
        let analytics = store.analytics()
        let monthRange = store.periods.range(for: .thisMonth, now: now)
        let month = analytics.summary(monthRange)
        let total = analytics.totalBalance()

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                OverviewHeader(now: now)
                if store.activeAccounts.isEmpty {
                    EmptyStateView(symbol: "creditcard.and.123", title: "Добавьте первый счёт",
                                   message: "Карта, вклад или наличные. Укажите реальный остаток — дальше MONO посчитает всё сам.") {
                        Button("Добавить счёт") { router.present(.account(nil)) }
                            .buttonStyle(PrimaryButtonStyle())
                            .frame(maxWidth: 260)
                    }
                    .monoSurface(level: 1, radius: MonoTokens.Radius.xl, padding: 8)
                } else {
                    BalanceHero(total: total.total, excluded: total.excluded, history: analytics.balanceHistory(store.periods.range(for: period, now: now)), period: period)
                        .riseIn()
                    QuickActionsRow()
                        .riseIn(delay: 0.04)
                    FlowChartCard(analytics: analytics, period: $period, now: now)
                        .riseIn(delay: 0.08)
                    MonthPulse(summary: month, mtd: analytics.monthToDate(now: now), now: now)
                        .riseIn(delay: 0.12)
                    DueRecurringSection(now: now)
                    AccountsStrip()
                    TopCategoriesSection(items: analytics.spendingByCategory(monthRange), total: month.spending)
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
        .background(AmbientBackground(tint: stateTint(month), secondary: Color.mono.electric))
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { store.reload() }
    }

    /// Свет состояния: профицит месяца — изумрудный, дефицит — коралловый.
    private func stateTint(_ month: PeriodSummary) -> Color {
        if month.isEmpty { return Color.mono.violet }
        return month.net.isNegative ? Color.mono.coral : Color.mono.emerald
    }
}

private struct OverviewHeader: View {
    let now: Date
    @Environment(Router.self) private var router
    @Environment(FinanceStore.self) private var store
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "MONO")
                    .font(.system(size: 22, weight: .heavy).width(.expanded))
                    .foregroundStyle(Color.mono.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: DateFormatting.weekdayDay(now, calendar: store.periods.calendar, language: language))
                    .monoFont(.footnote)
                    .foregroundStyle(Color.mono.textSecondary)
            }
            Spacer()
            IconButton(systemName: "sparkles", label: "Спросить MONO", tint: Color.mono.violet) {
                router.present(.assistant)
            }
            IconButton(systemName: "gearshape.fill", label: "Настройки") {
                router.open(.settings)
            }
        }
    }
}

/// Герой экрана: общий баланс крупным серифом, изменение за период и «спектр» распределения по счетам.
private struct BalanceHero: View {
    let total: Money
    let excluded: Set<Currency>
    let history: [BalancePoint]
    let period: PeriodPreset

    @Environment(SettingsStore.self) private var settings
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Kicker("Общий баланс")
                Spacer()
                Button {
                    Haptics.soft()
                    withMonoAnimation(.quick) { settings.hideAmounts.toggle() }
                } label: {
                    Image(systemName: settings.hideAmounts ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.mono.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.mono.surface2.opacity(0.8)))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel(settings.hideAmounts ? Text("Показать суммы") : Text("Скрыть суммы"))
            }
            HeroAmount(money: total)
                .onTapGesture(count: 2) {
                    Haptics.soft()
                    withMonoAnimation(.quick) { settings.hideAmounts.toggle() }
                }
            HStack(spacing: 10) {
                if let first = history.first, let last = history.last {
                    DeltaBadge(delta: last.balance - first.balance, caption: Text(verbatim: periodCaption))
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
                        .foregroundStyle(Color.mono.tangerine)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.mono.tangerine.opacity(0.12)))
                    }
                    .accessibilityLabel(Text("Нет курса для части валют — не включены в общий баланс"))
                }
            }
            LiquidityBar(segments: segments)
                .padding(.top, 4)
        }
        .padding(.top, 6)
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

    private var segments: [LiquidityBar.Segment] {
        let converter = store.converter
        return store.activeAccounts.filter(\.includeInTotal).compactMap { account in
            guard let base = converter.toBase(store.balance(of: account)) else { return nil }
            return LiquidityBar.Segment(id: account.id, color: account.tint, value: max(0, Double(base.minorUnits)))
        }
    }
}

/// Быстрые действия: расход, доход, перевод, импорт.
private struct QuickActionsRow: View {
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 10) {
            action("Расход", symbol: "minus", tint: Color.mono.coral) { router.newTransaction(.expense) }
            action("Доход", symbol: "plus", tint: Color.mono.emerald) { router.newTransaction(.income) }
            action("Перевод", symbol: "arrow.left.arrow.right", tint: Color.mono.sky) { router.newTransaction(.transfer) }
            Menu {
                Button { router.present(.importStatement(nil)) } label: { Label("Импорт выписки", systemImage: "tray.and.arrow.down") }
                Button { router.newTransaction(.refund) } label: { Label("Возврат", systemImage: "arrow.uturn.backward") }
                Button { router.newTransaction(.fee) } label: { Label("Комиссия", systemImage: "percent") }
                Button { router.open(.accounts) } label: { Label("Корректировка баланса", systemImage: "slider.horizontal.3") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.mono.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface1))
                    .overlay(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
            }
            .accessibilityLabel(Text("Другие действия"))
        }
    }

    private func action(_ title: LocalizedStringKey, symbol: String, tint: Color, perform: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            perform()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(tint.opacity(0.16)))
                Text(title)
                    .monoFont(.subhead)
                    .foregroundStyle(Color.mono.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface1))
            .overlay(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Пульс месяца: доходы и расходы, честное сравнение с тем же отрезком прошлого месяца.
private struct MonthPulse: View {
    let summary: PeriodSummary
    let mtd: (current: Money, previous: Money, day: Int)
    let now: Date

    @Environment(FinanceStore.self) private var store
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Kicker("Этот месяц")
                Spacer()
                Text(verbatim: DateFormatting.monthTitle(store.periods.monthKey(now), calendar: store.periods.calendar, language: language))
                    .monoFont(.footnote)
                    .foregroundStyle(Color.mono.textTertiary)
            }
            HStack(alignment: .top, spacing: 16) {
                column(title: "Доходы", money: summary.income, tint: Color.mono.emerald, sign: .always)
                Rectangle().fill(Color.mono.strokeSubtle).frame(width: 1)
                column(title: "Расходы", money: summary.outflow, tint: Color.mono.coral, sign: .automatic)
            }
            .fixedSize(horizontal: false, vertical: true)
            ratioBar
            HStack(spacing: 6) {
                if mtd.previous.minorUnits > 0 {
                    let ratio = Double(mtd.current.minorUnits - mtd.previous.minorUnits) / Double(mtd.previous.minorUnits)
                    Image(systemName: ratio <= 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ratio <= 0 ? Color.mono.emerald : Color.mono.coral)
                    Text(verbatim: comparisonText(ratio))
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textSecondary)
                } else {
                    Text("Сравнение появится, когда накопится история за прошлый месяц")
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textTertiary)
                }
                Spacer()
                if summary.fees.minorUnits > 0 {
                    Text("Комиссии")
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.textTertiary)
                    MoneyText(money: summary.fees, token: .caption, color: Color.mono.tangerine, compact: true)
                }
            }
        }
        .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
    }

    private func column(title: LocalizedStringKey, money: Money, tint: Color, sign: MoneyFormatter.SignDisplay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(title).monoFont(.subhead).foregroundStyle(Color.mono.textSecondary)
            }
            MoneyText(money: money, token: .title2, sign: sign, compact: money.majorValue >= 100_000_000)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ratioBar: some View {
        GeometryReader { proxy in
            let income = Double(max(summary.income.minorUnits, 0))
            let outflow = Double(max(summary.outflow.minorUnits, 0))
            let total = max(income + outflow, 1)
            HStack(spacing: 3) {
                Capsule().fill(Color.mono.emerald).frame(width: max(4, proxy.size.width * income / total))
                Capsule().fill(Color.mono.coral).frame(width: max(4, proxy.size.width * outflow / total))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
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
