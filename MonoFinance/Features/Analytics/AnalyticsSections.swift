import SwiftUI
import Charts
import MonoCore
import MonoAnalytics

// MARK: - Главная цифра

/// Заголовок-«разворот»: сумма расходов крупным серифом и одно человеческое предложение о динамике.
struct SpendingHeadline: View {
    let report: AnalyticsReport
    let scope: AnalyticsScope
    let month: MonthKey

    @Environment(\.appLanguage) private var language
    @Environment(\.moneyFormatter) private var formatter
    @Environment(\.hideAmounts) private var hideAmounts

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker("Расходы за период")
            HeroAmount(money: report.summary.spending, token: .hero, secondaryToken: .title)
            if let sentence {
                Text(verbatim: sentence)
                    .monoFont(.quote)
                    .foregroundStyle(Color.mono.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 12) {
                stat(title: Phrase(ru: "В день", uz: "Kuniga", en: "Per day")(language), value: report.averageDaily)
                if let projected = report.projectedMonth {
                    stat(title: Phrase(ru: "Прогноз", uz: "Prognoz", en: "Forecast")(language), value: projected)
                }
                stat(title: Phrase(ru: "Операций", uz: "Amallar", en: "Transactions")(language), count: report.summary.transactionCount)
            }
        }
    }

    private func stat(title: String, value: Money? = nil, count: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: title)
                .textCase(.uppercase)
                .monoFont(.kicker)
                .foregroundStyle(Color.mono.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let value {
                MoneyText(money: value, token: .headline, compact: true)
            } else if let count {
                Text(verbatim: "\(count)")
                    .monoFont(.headline, digits: true)
                    .foregroundStyle(Color.mono.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// «На 12 % меньше, чем в сентябре» — только из реальных сумм; без данных за прошлый период ничего не утверждаем.
    private var sentence: String? {
        guard !hideAmounts else { return nil }
        if let mtd = report.monthToDate {
            guard mtd.previous.isPositive, let raw = mtd.current.ratio(to: mtd.previous) else { return nil }
            let ratio = raw - 1
            let previousName = MonthNames.name(month.previous.month, language: language, form: .prepositional)
            let percent = PercentFormatting.string(ratio, language: language)
            if abs(ratio) < 0.02 {
                return Phrase(ru: "За \(mtd.day) дн. — столько же, сколько за то же время в \(previousName).",
                              uz: "\(mtd.day) kunda — o‘tgan oydagi kabi.",
                              en: "In \(mtd.day) days — about the same as last month by now.")(language)
            }
            return ratio < 0
                ? Phrase(ru: "За \(mtd.day) дн. — на \(percent) меньше, чем за то же время в \(previousName).",
                         uz: "\(mtd.day) kunda o‘tgan oyga nisbatan \(percent) kam.",
                         en: "In \(mtd.day) days — \(percent) less than last month by now.")(language)
                : Phrase(ru: "За \(mtd.day) дн. — на \(percent) больше, чем за то же время в \(previousName).",
                         uz: "\(mtd.day) kunda o‘tgan oyga nisbatan \(percent) ko‘p.",
                         en: "In \(mtd.day) days — \(percent) more than last month by now.")(language)
        }
        guard let ratio = report.comparison.spendingChangeRatio else { return nil }
        let percent = PercentFormatting.string(ratio, language: language)
        let previous: String
        switch scope {
        case .month:
            previous = Phrase(ru: "в \(MonthNames.name(month.previous.month, language: .ru, form: .prepositional))",
                              uz: "o‘tgan oyga nisbatan", en: "last month")(language)
        case .last30, .last90, .year:
            previous = Phrase(ru: "за предыдущий такой же период", uz: "oldingi davrga nisbatan", en: "the previous period")(language)
        }
        if abs(ratio) < 0.02 {
            return Phrase(ru: "Примерно столько же, сколько \(previous).", uz: "Taxminan \(previous) kabi.", en: "About the same as \(previous).")(language)
        }
        return ratio < 0
            ? Phrase(ru: "На \(percent) меньше, чем \(previous).", uz: "\(previous) \(percent) kam.", en: "\(percent) less than \(previous).")(language)
            : Phrase(ru: "На \(percent) больше, чем \(previous).", uz: "\(previous) \(percent) ko‘p.", en: "\(percent) more than \(previous).")(language)
    }
}

// MARK: - Строка-«гроссбух»

/// Доходы · Расходы · Итог тремя колонками с тонкими разделителями.
struct LedgerStrip: View {
    let summary: PeriodSummary
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                column("Доходы", money: summary.income, color: Color.mono.positive)
                divider
                column("Расходы", money: summary.spending, color: Color.mono.textPrimary)
                divider
                column("Итог", money: summary.net, color: summary.net.isNegative ? Color.mono.negative : Color.mono.positive, signed: true)
            }
            if !summary.fees.isZero || !summary.refunds.isZero {
                HStack(spacing: 14) {
                    if !summary.fees.isZero {
                        Label {
                            HStack(spacing: 4) {
                                Text("Комиссии")
                                MoneyText(money: summary.fees, token: .footnote, color: Color.mono.textSecondary, compact: true)
                            }
                        } icon: { Image(systemName: "percent") }
                    }
                    if !summary.refunds.isZero {
                        Label {
                            HStack(spacing: 4) {
                                Text("Возвраты")
                                MoneyText(money: summary.refunds, token: .footnote, color: Color.mono.textSecondary, compact: true)
                            }
                        } icon: { Image(systemName: "arrow.uturn.backward") }
                    }
                }
                .monoFont(.footnote)
                .foregroundStyle(Color.mono.textTertiary)
            }
        }
        .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.mono.strokeSubtle)
            .frame(width: 1, height: 44)
            .padding(.horizontal, 12)
    }

    private func column(_ title: LocalizedStringKey, money: Money, color: Color, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(title)
            MoneyText(money: money, token: .amountRow, sign: signed ? .always : .automatic, color: color, compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Структура расходов

/// Кольцо категорий с выбором сектора касанием и легендой-переходом к операциям.
struct CategoryDonutCard: View {
    let items: [CategoryAmount]
    let total: Money
    let range: DateRange

    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language
    @State private var selectedAngle: Double?
    @State private var selectedID: String?

    /// До 6 крупнейших категорий + «Остальное», чтобы кольцо читалось.
    private var slices: [Slice] {
        let sorted = items.filter { $0.amount.isPositive }
        let head = sorted.prefix(6).map { item in
            Slice(id: item.id, categoryID: item.categoryID, amount: item.amount, share: item.share, isOther: false)
        }
        let tail = sorted.dropFirst(6)
        guard !tail.isEmpty else { return head }
        let rest = Money.sum(tail.map(\.amount), currency: total.currency)
        return head + [Slice(id: "other", categoryID: nil, amount: rest, share: tail.reduce(0) { $0 + $1.share }, isOther: true)]
    }

    struct Slice: Identifiable, Equatable {
        let id: String
        let categoryID: UUID?
        let amount: Money
        let share: Double
        let isOther: Bool
    }

    var body: some View {
        let slices = self.slices
        let selected = slices.first { $0.id == selectedID }
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(kicker: "Структура", title: "По категориям")
            if slices.isEmpty {
                Text("Расходов за период нет.")
                    .monoFont(.callout)
                    .foregroundStyle(Color.mono.textTertiary)
            } else {
                ZStack {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Сумма", slice.amount.chartValue),
                            innerRadius: .ratio(0.64),
                            outerRadius: .ratio(slice.id == selectedID ? 1.0 : 0.94),
                            angularInset: 1.5
                        )
                        .cornerRadius(5)
                        .foregroundStyle(color(of: slice))
                        .opacity(selectedID == nil || slice.id == selectedID ? 1 : 0.35)
                    }
                    .chartLegend(.hidden)
                    .chartAngleSelection(value: $selectedAngle)
                    .frame(height: 240)
                    .accessibilityLabel(Text("Кольцевая диаграмма расходов по категориям"))

                    VStack(spacing: 4) {
                        if let selected {
                            Text(verbatim: name(of: selected))
                                .monoFont(.subhead)
                                .foregroundStyle(Color.mono.textSecondary)
                                .lineLimit(1)
                            MoneyText(money: selected.amount, token: .title2, compact: true)
                            Text(verbatim: PercentFormatting.string(selected.share, language: language))
                                .monoFont(.footnote, digits: true)
                                .foregroundStyle(color(of: selected))
                        } else {
                            Kicker("Всего")
                            MoneyText(money: total, token: .title2, compact: true)
                        }
                    }
                    .frame(maxWidth: 130)
                    .allowsHitTesting(false)
                }
                .sensoryFeedback(.selection, trigger: selectedID)
                .onChange(of: selectedAngle) { _, angle in
                    guard let angle else { return }
                    selectedID = slice(at: angle, in: slices)?.id
                }

                VStack(spacing: 0) {
                    ForEach(slices) { slice in
                        Button {
                            if slice.isOther {
                                withMonoAnimation(.quick) { selectedID = selectedID == slice.id ? nil : slice.id }
                            } else {
                                router.open(.filteredTransactions(TransactionFilter(kinds: [.expense, .refund], categoryID: slice.categoryID, range: range)))
                            }
                        } label: {
                            legendRow(slice)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
            }
        }
        .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
    }

    private func legendRow(_ slice: Slice) -> some View {
        HStack(spacing: 12) {
            if slice.isOther {
                CategoryGlyph(icon: "ellipsis", color: Color.mono.neutral, size: 34)
            } else {
                CategoryGlyph(category: slice.categoryID.flatMap { store.categoryMap[$0] }, kind: .expense, size: 34)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(verbatim: name(of: slice))
                        .monoFont(.body)
                        .foregroundStyle(Color.mono.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    MoneyText(money: slice.amount, token: .amountRow, compact: true)
                }
                HStack(spacing: 8) {
                    ProgressTrack(progress: slice.share, tint: color(of: slice), height: 4)
                    Text(verbatim: PercentFormatting.string(slice.share, language: language))
                        .monoFont(.caption, digits: true)
                        .foregroundStyle(Color.mono.textTertiary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func name(of slice: Slice) -> String {
        if slice.isOther { return Phrase(ru: "Остальное", uz: "Boshqalar", en: "Other")(language) }
        guard let id = slice.categoryID, let category = store.categoryMap[id] else {
            return Phrase(ru: "Без категории", uz: "Kategoriyasiz", en: "Uncategorized")(language)
        }
        return category.name
    }

    private func color(of slice: Slice) -> Color {
        if slice.isOther { return Color.mono.neutral }
        guard let id = slice.categoryID, let category = store.categoryMap[id] else { return Color.mono.neutral }
        return category.color.color
    }

    /// `chartAngleSelection` отдаёт накопленное значение — находим сектор, в который оно попало.
    private func slice(at value: Double, in slices: [Slice]) -> Slice? {
        var cumulative = 0.0
        for slice in slices {
            cumulative += slice.amount.chartValue
            if value <= cumulative { return slice }
        }
        return slices.last
    }
}

// MARK: - Динамика

/// «Зеркальные» столбцы: доходы вверх, расходы вниз от нулевой линии.
struct TrendCard: View {
    let points: [SeriesPoint]
    let granularity: Granularity
    let calendar: Calendar

    @Environment(\.appLanguage) private var language
    @Environment(\.moneyFormatter) private var formatter
    @State private var selectedDate: Date?

    private var unit: Calendar.Component {
        switch granularity {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    var body: some View {
        let selected = selectedDate.flatMap { date in points.first { calendar.isDate($0.date, equalTo: date, toGranularity: unit) } }
        let currency = points.first?.income.currency ?? .uzs
        let income = selected?.income ?? Money.sum(points.map(\.income), currency: currency)
        let outflow = selected?.outflow ?? Money.sum(points.map(\.outflow), currency: currency)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Динамика")
                    Text(verbatim: selected.map { title(for: $0.date) } ?? Phrase(ru: "Доходы и расходы", uz: "Daromad va xarajat", en: "Income and spending")(language))
                        .monoFont(.title2)
                        .foregroundStyle(Color.mono.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    MoneyText(money: income, token: .callout, sign: .always, color: Color.mono.positive, compact: true)
                    MoneyText(money: outflow.negated, token: .callout, color: Color.mono.negative, compact: true)
                }
            }
            if points.count > 1 {
                Chart {
                    ForEach(points) { point in
                        BarMark(x: .value("Период", point.date, unit: unit), y: .value("Доход", point.income.chartValue))
                            .foregroundStyle(Color.mono.positive.gradient)
                            .cornerRadius(3)
                            .opacity(selected == nil || selected?.date == point.date ? 1 : 0.35)
                        BarMark(x: .value("Период", point.date, unit: unit), y: .value("Расход", -point.outflow.chartValue))
                            .foregroundStyle(Color.mono.negative.gradient)
                            .cornerRadius(3)
                            .opacity(selected == nil || selected?.date == point.date ? 1 : 0.35)
                    }
                    RuleMark(y: .value("Ноль", 0))
                        .foregroundStyle(Color.mono.strokeStrong)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                .chartXSelection(value: $selectedDate)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(Color.mono.strokeSubtle)
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(verbatim: formatter.axisLabel(Decimal(abs(number))))
                                    .monoFont(.caption, digits: true)
                                    .foregroundStyle(Color.mono.textTertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel(format: axisFormat)
                            .foregroundStyle(Color.mono.textTertiary)
                    }
                }
                .frame(height: 200)
                .sensoryFeedback(.selection, trigger: selected?.date)
                .accessibilityLabel(Text("Столбчатая диаграмма доходов и расходов"))
            }
        }
        .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
    }

    private var axisFormat: Date.FormatStyle {
        let base = Date.FormatStyle(locale: language.locale, calendar: calendar, timeZone: calendar.timeZone)
        switch granularity {
        case .day: return base.day()
        case .week: return base.day().month(.abbreviated)
        case .month: return base.month(.abbreviated)
        }
    }

    private func title(for date: Date) -> String {
        switch granularity {
        case .day:
            return DateFormatting.weekdayDay(date, calendar: calendar, language: language)
        case .week:
            let end = calendar.date(byAdding: .day, value: 6, to: date) ?? date
            return "\(DateFormatting.short(date, calendar: calendar, language: language)) – \(DateFormatting.short(end, calendar: calendar, language: language))"
        case .month:
            return DateFormatting.monthTitle(MonthKey(date: date, calendar: calendar), calendar: calendar, language: language)
        }
    }
}

// MARK: - Изменения по категориям

struct CategoryChangesCard: View {
    let comparison: PeriodComparison
    let scope: AnalyticsScope

    @Environment(FinanceStore.self) private var store
    @Environment(\.appLanguage) private var language

    var body: some View {
        let movers = comparison.categories
            .filter { !$0.change.isZero && ($0.current.isPositive || $0.previous.isPositive) }
            .sorted { $0.change.magnitude.minorUnits > $1.change.magnitude.minorUnits }
            .prefix(5)
        if !movers.isEmpty && comparison.previous.spending.isPositive {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(kicker: "Сравнение", title: scope == .month ? "С прошлым месяцем" : "С прошлым периодом")
                ForEach(Array(movers)) { delta in
                    HStack(spacing: 12) {
                        CategoryGlyph(category: delta.categoryID.flatMap { store.categoryMap[$0] }, kind: .expense, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: delta.categoryID.flatMap { store.categoryMap[$0]?.name } ?? Phrase(ru: "Без категории", uz: "Kategoriyasiz", en: "Uncategorized")(language))
                                .monoFont(.body)
                                .foregroundStyle(Color.mono.textPrimary)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                MoneyText(money: delta.previous, token: .caption, color: Color.mono.textTertiary, compact: true)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.mono.textTertiary)
                                MoneyText(money: delta.current, token: .caption, color: Color.mono.textSecondary, compact: true)
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            // Рост расходов — коралловый, снижение — изумрудный.
                            MoneyText(money: delta.change, token: .amountRow, sign: .always,
                                      color: delta.change.isPositive ? Color.mono.negative : Color.mono.positive, compact: true)
                            if let ratio = delta.changeRatio {
                                Text(verbatim: PercentFormatting.string(ratio, language: language, signed: true))
                                    .monoFont(.caption, digits: true)
                                    .foregroundStyle(Color.mono.textTertiary)
                            } else {
                                Text("новая")
                                    .monoFont(.caption)
                                    .foregroundStyle(Color.mono.accentText)
                            }
                        }
                    }
                }
            }
            .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
        }
    }
}

// MARK: - Обязательные и необязательные

struct MandatorySplitCard: View {
    let split: MandatorySplit
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language

    var body: some View {
        if split.total.isPositive {
            let total = max(split.total.chartValue, 1)
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(kicker: "Структура", title: "Обязательные траты") {
                    Button("Настроить") { router.open(.categories) }
                        .monoFont(.subhead)
                        .foregroundStyle(Color.mono.accentText)
                }
                GeometryReader { proxy in
                    HStack(spacing: 3) {
                        segment(split.mandatory, total: total, width: proxy.size.width, color: Color.mono.accent)
                        segment(split.optional, total: total, width: proxy.size.width, color: Color.mono.accent)
                        segment(split.uncategorized, total: total, width: proxy.size.width, color: Color.mono.neutral)
                    }
                }
                .frame(height: 14)
                HStack(alignment: .top, spacing: 12) {
                    legend("Обязательные", money: split.mandatory, share: split.mandatory.chartValue / total, color: Color.mono.accent)
                    legend("Остальные", money: split.optional, share: split.optional.chartValue / total, color: Color.mono.accent)
                    if split.uncategorized.isPositive {
                        legend("Без категории", money: split.uncategorized, share: split.uncategorized.chartValue / total, color: Color.mono.neutral)
                    }
                }
                Text("Обязательными считаются категории с отметкой «Обязательная»: жильё, связь, кредиты и т. п.")
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.textTertiary)
            }
            .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
        }
    }

    @ViewBuilder
    private func segment(_ money: Money, total: Double, width: CGFloat, color: Color) -> some View {
        if money.isPositive {
            Capsule(style: .continuous)
                .fill(color.gradient)
                .frame(width: max(6, (width - 6) * money.chartValue / total))
        }
    }

    private func legend(_ title: LocalizedStringKey, money: Money, share: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.textSecondary)
            }
            MoneyText(money: money, token: .callout, compact: true)
            Text(verbatim: PercentFormatting.string(share, language: language))
                .monoFont(.caption, digits: true)
                .foregroundStyle(Color.mono.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Продавцы

struct MerchantsCard: View {
    let merchants: [MerchantStat]
    let range: DateRange

    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(kicker: "Где тратите", title: "Магазины и сервисы")
            ForEach(Array(merchants.enumerated()), id: \.element.id) { index, merchant in
                Button {
                    router.open(.filteredTransactions(TransactionFilter(query: merchant.name, kinds: [.expense], range: range)))
                } label: {
                    HStack(spacing: 14) {
                        Text(verbatim: "\(index + 1)")
                            .font(.system(size: 26, weight: .semibold, design: .default).monospacedDigit())
                            .foregroundStyle(index == 0 ? Color.mono.accent : Color.mono.textTertiary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: merchant.name)
                                .monoFont(.body)
                                .foregroundStyle(Color.mono.textPrimary)
                                .lineLimit(1)
                            Text(verbatim: countText(merchant.count))
                                .monoFont(.caption)
                                .foregroundStyle(Color.mono.textTertiary)
                        }
                        Spacer(minLength: 8)
                        MoneyText(money: merchant.total, token: .amountRow, compact: true)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
        }
        .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
    }

    private func countText(_ count: Int) -> String {
        switch language {
        case .ru:
            let mod10 = count % 10, mod100 = count % 100
            let word = mod10 == 1 && mod100 != 11 ? "покупка" : (2...4).contains(mod10) && !(12...14).contains(mod100) ? "покупки" : "покупок"
            return "\(count) \(word)"
        case .uz: return "\(count) ta xarid"
        case .en: return count == 1 ? "1 purchase" : "\(count) purchases"
        }
    }
}

// MARK: - Счета

struct AccountFlowsCard: View {
    let flows: [AccountFlow]
    let range: DateRange

    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kicker: "Счета", title: "Движение по счетам")
            ForEach(flows.filter { $0.count > 0 || $0.transfersIn.isPositive }) { flow in
                if let account = store.accountMap[flow.accountID] {
                    Button {
                        router.open(.filteredTransactions(TransactionFilter(accountID: account.id, range: range)))
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(account.skin.linearGradient)
                                .frame(width: 38, height: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: account.displayName)
                                    .monoFont(.body)
                                    .foregroundStyle(Color.mono.textPrimary)
                                    .lineLimit(1)
                                Text(verbatim: account.bank.displayName)
                                    .monoFont(.caption)
                                    .foregroundStyle(Color.mono.textTertiary)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                if flow.income.isPositive {
                                    MoneyText(money: flow.income, token: .footnote, sign: .always, color: Color.mono.positive, compact: true)
                                }
                                if (flow.spending + flow.fees).isPositive {
                                    MoneyText(money: (flow.spending + flow.fees).negated, token: .footnote, color: Color.mono.textPrimary, compact: true)
                                }
                                if flow.transfersIn.isPositive || flow.transfersOut.isPositive {
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.left.arrow.right")
                                            .font(.system(size: 9, weight: .bold))
                                        MoneyText(money: flow.transfersIn - flow.transfersOut, token: .caption, sign: .always, color: Color.mono.textSecondary, compact: true)
                                    }
                                    .foregroundStyle(Color.mono.textSecondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            }
            Text("Суммы — в основной валюте. Переводы между своими счетами не считаются доходом или расходом.")
                .monoFont(.caption)
                .foregroundStyle(Color.mono.textTertiary)
        }
        .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
    }
}

// MARK: - Источники дохода

struct IncomeSourcesCard: View {
    let items: [CategoryAmount]
    let total: Money

    @Environment(FinanceStore.self) private var store
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kicker: "Доходы", title: "Источники")
            ForEach(items.prefix(5)) { item in
                HStack(spacing: 12) {
                    CategoryGlyph(category: item.categoryID.flatMap { store.categoryMap[$0] }, kind: .income, size: 34)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(verbatim: item.categoryID.flatMap { store.categoryMap[$0]?.name } ?? Phrase(ru: "Без категории", uz: "Kategoriyasiz", en: "Uncategorized")(language))
                                .monoFont(.body)
                                .foregroundStyle(Color.mono.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            MoneyText(money: item.amount, token: .amountRow, color: Color.mono.positive, compact: true)
                        }
                        ProgressTrack(progress: item.share, tint: Color.mono.positive, height: 4)
                    }
                }
            }
        }
        .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
    }
}

// MARK: - Необычные траты

struct UnusualExpensesCard: View {
    let items: [UnusualExpense]

    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language
    @Environment(\.moneyFormatter) private var formatter
    @Environment(\.hideAmounts) private var hideAmounts

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kicker: "Внимание", title: "Необычные траты")
            ForEach(items) { item in
                let category = item.transaction.categoryID.flatMap { store.categoryMap[$0] }
                Button {
                    router.open(.transaction(item.transaction.id))
                } label: {
                    HStack(spacing: 12) {
                        CategoryGlyph(category: category, kind: item.transaction.kind, size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: item.transaction.merchant ?? category?.name ?? item.transaction.kind.title(language))
                                .monoFont(.body)
                                .foregroundStyle(Color.mono.textPrimary)
                                .lineLimit(1)
                            Text(verbatim: hideAmounts ? "" : detail(item))
                                .monoFont(.caption)
                                .foregroundStyle(Color.mono.warning)
                        }
                        Spacer(minLength: 8)
                        MoneyText(money: item.transaction.amount, token: .amountRow, compact: true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
        }
        .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
    }

    private func detail(_ item: UnusualExpense) -> String {
        let ratio = String(format: "%.1f", item.ratio).replacingOccurrences(of: ".", with: language == .en ? "." : ",")
        let typical = formatter.compact(item.typical)
        return Phrase(ru: "В \(ratio) раза больше обычного (обычно \(typical))",
                      uz: "Odatdagidan \(ratio) baravar ko‘p (odatda \(typical))",
                      en: "\(ratio)× the usual (typically \(typical))")(language)
    }
}

// MARK: - Найденные регулярные платежи

struct RecurringCandidatesCard: View {
    let candidates: [RecurringCandidate]

    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language

    /// Скрываем то, для чего уже есть правило.
    private var fresh: [RecurringCandidate] {
        let known = Set(store.recurring.compactMap { rule in rule.merchant.map { MerchantNormalizer.key($0) } }
                        + store.recurring.map { MerchantNormalizer.key($0.title) })
        return candidates.filter { !known.contains(MerchantNormalizer.key($0.name)) }
    }

    var body: some View {
        let items = fresh.prefix(4)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(kicker: "Похоже на регулярные", title: "Подписки и платежи")
                ForEach(Array(items)) { candidate in
                    HStack(spacing: 12) {
                        CategoryGlyph(category: candidate.categoryID.flatMap { store.categoryMap[$0] }, kind: .expense, size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: candidate.name)
                                .monoFont(.body)
                                .foregroundStyle(Color.mono.textPrimary)
                                .lineLimit(1)
                            Text(verbatim: "\(candidate.frequency.title(language)) · \(Phrase(ru: "далее", uz: "keyingi", en: "next")(language)) \(DateFormatting.short(candidate.nextExpectedDate, calendar: store.periods.calendar, language: language))")
                                .lineLimit(2)
                                .monoFont(.caption)
                            .foregroundStyle(Color.mono.textTertiary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 6) {
                            MoneyText(money: candidate.typicalAmount, token: .footnote, compact: true)
                            Button("Напоминать") {
                                router.present(.recurring(RecurringRule(
                                    title: candidate.name,
                                    amount: candidate.typicalAmount,
                                    accountID: candidate.accountID,
                                    categoryID: candidate.categoryID,
                                    merchant: candidate.name,
                                    frequency: candidate.frequency,
                                    anchorDate: candidate.nextExpectedDate
                                )))
                            }
                            .buttonStyle(ChipStyle(isSelected: true, tint: Color.mono.accent))
                        }
                    }
                }
                Text("Найдено по повторяющимся суммам. Операции не создаются автоматически — только напоминание и подтверждение.")
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.textTertiary)
            }
            .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
        }
    }
}

// MARK: - Прогноз накоплений

struct ForecastCard: View {
    let forecast: SavingsForecast
    @Environment(\.appLanguage) private var language

    var body: some View {
        if hasBasis {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(kicker: "Прогноз", title: "Накопления за 3 месяца")
                HeroAmount(money: forecast.projectedSavings, token: .display, secondaryToken: .title2,
                           color: forecast.projectedSavings.isNegative ? Color.mono.negative : Color.mono.positive)
                HStack(alignment: .top, spacing: 12) {
                    figure(Phrase(ru: "Доход/мес", uz: "Daromad/oy", en: "Income/mo")(language), forecast.averageIncome, Color.mono.positive)
                    figure(Phrase(ru: "Расход/мес", uz: "Xarajat/oy", en: "Spend/mo")(language), forecast.averageOutflow, Color.mono.textPrimary)
                    if forecast.plannedExpenses.isPositive {
                        figure(Phrase(ru: "План", uz: "Reja", en: "Planned")(language), forecast.plannedExpenses, Color.mono.warning)
                    }
                }
                Text(verbatim: basisText)
                    .monoFont(.caption)
                    .foregroundStyle(forecast.isReliable ? Color.mono.textTertiary : Color.mono.warning)
            }
            .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
        }
    }

    private var hasBasis: Bool {
        switch forecast.basisDescription {
        case SavingsForecast.Basis.none: return false
        default: return true
        }
    }

    private func figure(_ title: String, _ money: Money, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: title)
                .textCase(.uppercase)
                .monoFont(.kicker)
                .foregroundStyle(Color.mono.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            MoneyText(money: money, token: .callout, color: color, compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var basisText: String {
        switch forecast.basisDescription {
        case .fullMonths(let months):
            return Phrase(ru: "Среднее по \(months.count) полным месяцам. Это оценка, а не обещание.",
                          uz: "\(months.count) to‘liq oy bo‘yicha o‘rtacha. Bu taxmin.",
                          en: "Average of \(months.count) full months. An estimate, not a promise.")(language)
        case .recentDays(let days):
            return Phrase(ru: "Мало данных: оценка по последним \(days) дням.",
                          uz: "Ma’lumot kam: oxirgi \(days) kun bo‘yicha.",
                          en: "Limited data: based on the last \(days) days.")(language)
        case .none:
            return ""
        }
    }
}
