import SwiftUI
import MonoCore
import MonoAnalytics

/// Планы: лимит месяца, бюджеты категорий, цели, запланированные траты, регулярные платежи.
struct PlansView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language

    var body: some View {
        let now = Date()
        let analytics = store.analytics()
        let month = store.periods.monthKey(now)
        let statuses = analytics.budgetStatuses(store.budgets, month: month, now: now)
        let overall = statuses.first { $0.budget.isOverall }
        let categoryStatuses = statuses.filter { !$0.budget.isOverall }
        let goals = analytics.goalStatuses(store.goals, contributions: store.contributions, balances: store.balances, now: now)

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 2) {
                    Kicker("Планы")
                    Text(verbatim: DateFormatting.monthTitle(month, calendar: store.periods.calendar, language: language, includeYear: false))
                        .monoFont(.display)
                        .foregroundStyle(Color.mono.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }

                MonthLimitCard(status: overall)
                    .riseIn()

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(kicker: "Бюджеты", title: "По категориям") {
                        Button {
                            router.present(.budget(nil))
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.mono.accentText)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.mono.accent.opacity(0.12)))
                        }
                        .accessibilityLabel(Text("Новый бюджет"))
                    }
                    if categoryStatuses.isEmpty {
                        Text("Задайте лимит для категорий, где хотите держать расходы под контролем: кафе, такси, покупки.")
                            .monoFont(.callout)
                            .foregroundStyle(Color.mono.textTertiary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(categoryStatuses) { status in
                                Button {
                                    router.present(.budget(status.budget))
                                } label: {
                                    BudgetRow(status: status)
                                }
                                .buttonStyle(PressableStyle(scale: 0.98))
                            }
                        }
                        .monoSurface(radius: MonoTokens.Radius.xl, padding: 14)
                    }
                }

                GoalsSection(goals: goals)

                PlannedSection(now: now)

                RecurringSummary(now: now)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(DebugFlags.scrollAnchor)
        .background(MonoBackdrop(haze: true))
        .toolbar(.hidden, for: .navigationBar)
    }

}

extension BudgetStatus.State {
    var tint: Color {
        switch self {
        case .ok: return Color.mono.accent
        case .warning: return Color.mono.warning
        case .exceeded: return Color.mono.negative
        }
    }
}

// MARK: - Лимит месяца

/// Общий лимит: большое кольцо, сколько осталось, сколько можно тратить в день.
private struct MonthLimitCard: View {
    let status: BudgetStatus?
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language

    var body: some View {
        if let status {
            Button {
                router.present(.budget(status.budget))
            } label: {
                HStack(spacing: 20) {
                    ZStack {
                        ProgressRing(progress: status.progress, tint: status.state.tint, lineWidth: 12)
                        VStack(spacing: 0) {
                            Text(verbatim: PercentFormatting.string(min(status.progress, 9.99), language: language))
                                .font(.system(size: 22, weight: .semibold, design: .default).monospacedDigit())
                                .foregroundStyle(Color.mono.textPrimary)
                            Text("лимита")
                                .monoFont(.caption)
                                .foregroundStyle(Color.mono.textTertiary)
                        }
                    }
                    .frame(width: 112, height: 112)

                    VStack(alignment: .leading, spacing: 8) {
                        Kicker("Лимит на месяц")
                        if status.remaining.isNegative {
                            Text("Превышен на")
                                .monoFont(.footnote)
                                .foregroundStyle(Color.mono.negative)
                            MoneyText(money: status.remaining.magnitude, token: .title2, color: Color.mono.negative, compact: true)
                        } else {
                            Text("Осталось")
                                .monoFont(.footnote)
                                .foregroundStyle(Color.mono.textSecondary)
                            MoneyText(money: status.remaining, token: .title2, compact: true)
                        }
                        HStack(spacing: 4) {
                            MoneyText(money: status.spent, token: .caption, color: Color.mono.textTertiary, compact: true)
                            Text(verbatim: "/")
                                .monoFont(.caption)
                                .foregroundStyle(Color.mono.textTertiary)
                            MoneyText(money: status.effectiveLimit, token: .caption, color: Color.mono.textTertiary, compact: true)
                        }
                        if let daily = status.dailyAllowance {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar.badge.clock")
                                MoneyText(money: daily, token: .caption, color: Color.mono.accentText, compact: true)
                                Text("в день")
                            }
                            .monoFont(.caption)
                            .foregroundStyle(Color.mono.accentText)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .monoSurface(level: 2, radius: MonoTokens.Radius.xl, padding: 18)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Kicker("Лимит на месяц")
                Text("Сколько вы готовы тратить в месяц?")
                    .monoFont(.title2)
                    .foregroundStyle(Color.mono.textPrimary)
                Text("MONO покажет остаток, допустимую сумму в день и предупредит заранее, если темп трат выше плана.")
                    .monoFont(.callout)
                    .foregroundStyle(Color.mono.textSecondary)
                Button("Задать лимит") { router.present(.budget(nil)) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)
        }
    }
}

// MARK: - Бюджет категории

private struct BudgetRow: View {
    let status: BudgetStatus
    @Environment(FinanceStore.self) private var store
    @Environment(\.appLanguage) private var language

    var body: some View {
        let category = status.budget.categoryID.flatMap { store.categoryMap[$0] }
        HStack(spacing: 12) {
            CategoryGlyph(category: category, kind: .expense, size: 38)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: category?.name ?? "—")
                        .monoFont(.body)
                        .foregroundStyle(Color.mono.textPrimary)
                        .lineLimit(1)
                    if status.budget.rolloverEnabled {
                        Image(systemName: "arrow.uturn.forward.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mono.accentText)
                            .accessibilityLabel(Text("С переносом остатка"))
                    }
                    Spacer(minLength: 8)
                    Text(verbatim: PercentFormatting.string(min(status.progress, 9.99), language: language))
                        .monoFont(.subhead, digits: true)
                        .foregroundStyle(status.state.tint)
                }
                ProgressTrack(progress: status.progress, tint: status.state.tint, height: 6)
                HStack(spacing: 4) {
                    MoneyText(money: status.spent, token: .caption, color: Color.mono.textSecondary, compact: true)
                    Text("из")
                    MoneyText(money: status.effectiveLimit, token: .caption, color: Color.mono.textTertiary, compact: true)
                    Spacer(minLength: 8)
                    if status.remaining.isNegative {
                        Text("Превышение")
                        MoneyText(money: status.remaining.magnitude, token: .caption, color: Color.mono.negative, compact: true)
                    } else if let daily = status.dailyAllowance {
                        MoneyText(money: daily, token: .caption, color: Color.mono.textSecondary, compact: true)
                        Text("в день")
                    }
                }
                .monoFont(.caption)
                .foregroundStyle(status.remaining.isNegative ? Color.mono.negative : Color.mono.textTertiary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Цели

private struct GoalsSection: View {
    let goals: [GoalStatus]
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kicker: "Цели", title: "Накопления") {
                Button {
                    router.present(.goal(nil))
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.mono.accentText)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.mono.accent.opacity(0.12)))
                }
                .accessibilityLabel(Text("Новая цель"))
            }
            if goals.isEmpty {
                Button {
                    router.present(.goal(nil))
                } label: {
                    HStack(spacing: 14) {
                        OrbitIllustration(symbol: "star.fill")
                            .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Поставьте первую цель")
                                .monoFont(.headline)
                                .foregroundStyle(Color.mono.textPrimary)
                            Text("Отпуск, машина, подушка безопасности — с суммой и сроком.")
                                .monoFont(.footnote)
                                .foregroundStyle(Color.mono.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .monoSurface(radius: MonoTokens.Radius.xl, padding: 16)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(goals) { status in
                            Button {
                                router.open(.goal(status.goal.id))
                            } label: {
                                GoalTile(status: status)
                            }
                            .buttonStyle(PressableStyle(scale: 0.97))
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }
}

/// Плитка цели: вертикальная «колба», заполненная по прогрессу; достигнутая цель — зелёная.
private struct GoalTile: View {
    let status: GoalStatus
    @Environment(FinanceStore.self) private var store
    @Environment(\.appLanguage) private var language

    var body: some View {
        let color = status.isCompleted ? Color.mono.positive : Color.mono.accent
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: status.goal.icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.mono.textSecondary)
                Spacer()
                if status.isCompleted {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.mono.positive)
                } else {
                    Text(verbatim: PercentFormatting.string(status.progress, language: language))
                        .monoFont(.caption, digits: true)
                        .foregroundStyle(Color.mono.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: status.goal.name)
                .monoFont(.headline)
                .foregroundStyle(Color.mono.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            MoneyText(money: status.saved, token: .title2, compact: true)
            HStack(spacing: 3) {
                Text("из")
                MoneyText(money: status.goal.target, token: .caption, color: Color.mono.textTertiary, compact: true)
            }
            .monoFont(.caption)
            .foregroundStyle(Color.mono.textTertiary)
            if let deadline = status.goal.deadline {
                Text(verbatim: DateFormatting.short(deadline, calendar: store.periods.calendar, language: language))
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.textTertiary)
            }
        }
        .padding(16)
        .frame(width: 168, height: 210, alignment: .topLeading)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    Color.mono.surface1
                    VStack(spacing: 0) {
                        Rectangle().fill(color.opacity(0.7)).frame(height: 1.5)
                        LinearGradient(colors: [color.opacity(0.20), color.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                    }
                    .frame(height: proxy.size.height * max(0.04, min(status.progress, 1)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MonoTokens.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MonoTokens.Radius.xl, style: .continuous).strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
    }
}

// MARK: - Запланированные траты

private struct PlannedSection: View {
    let now: Date
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.appLanguage) private var language

    var body: some View {
        let upcoming = store.planned.filter { !$0.isCompleted }.sorted { $0.date < $1.date }
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kicker: "Запланировано", title: "Крупные траты") {
                Button {
                    router.present(.planned(nil))
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.mono.warning)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.mono.warning.opacity(0.12)))
                }
                .accessibilityLabel(Text("Запланировать трату"))
            }
            if upcoming.isEmpty {
                Text("Отпуск, ремонт, подарки — запланированные траты учитываются в прогнозе накоплений.")
                    .monoFont(.callout)
                    .foregroundStyle(Color.mono.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(upcoming) { item in
                        HStack(spacing: 12) {
                            Button {
                                complete(item)
                            } label: {
                                Image(systemName: "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.mono.textTertiary)
                            }
                            .buttonStyle(PressableStyle(scale: 0.85))
                            .accessibilityLabel(Text("Отметить выполненным"))
                            Button {
                                router.present(.planned(item))
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: item.title)
                                            .monoFont(.body)
                                            .foregroundStyle(Color.mono.textPrimary)
                                        Text(verbatim: DateFormatting.dayTitle(item.date, now: now, calendar: store.periods.calendar, language: language))
                                            .monoFont(.caption)
                                            .foregroundStyle(item.date < now ? Color.mono.negative : Color.mono.textTertiary)
                                    }
                                    Spacer()
                                    MoneyText(money: item.amount, token: .amountRow, compact: true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .monoSurface(radius: MonoTokens.Radius.xl, padding: 14)
            }
        }
    }

    private func complete(_ item: PlannedExpense) {
        var done = item
        done.isCompleted = true
        do {
            try store.savePlanned(done)
            Haptics.success()
            toasts.show(ToastMessage(text: String(localized: "Отмечено выполненным"), actionTitle: String(localized: "Вернуть")) {
                try? store.savePlanned(item)
            })
        } catch {
            toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.negative))
        }
    }
}

// MARK: - Регулярные платежи

private struct RecurringSummary: View {
    let now: Date
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language

    var body: some View {
        let active = store.recurring.filter(\.isActive).sorted { $0.nextDueDate < $1.nextDueDate }
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kicker: "Регулярные", title: "Платежи и поступления") {
                Button("Все") { router.open(.recurringList) }
                    .monoFont(.subhead)
                    .foregroundStyle(Color.mono.accentText)
            }
            if active.isEmpty {
                Button {
                    router.present(.recurring(nil))
                } label: {
                    Label("Добавить регулярный платёж", systemImage: "repeat")
                        .monoFont(.callout)
                }
                .buttonStyle(ChipStyle())
            } else {
                VStack(spacing: 0) {
                    ForEach(active.prefix(4)) { rule in
                        Button {
                            router.present(.recurring(rule))
                        } label: {
                            RecurringRuleRow(rule: rule, now: now)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
                .monoSurface(radius: MonoTokens.Radius.xl, padding: 14)
            }
        }
    }
}

/// Строка регулярного правила: значок, название, частота, ближайшая дата, сумма.
struct RecurringRuleRow: View {
    let rule: RecurringRule
    let now: Date
    @Environment(FinanceStore.self) private var store
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(spacing: 12) {
            CategoryGlyph(category: rule.categoryID.flatMap { store.categoryMap[$0] }, kind: rule.kind, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: rule.title)
                    .monoFont(.body)
                    .foregroundStyle(rule.isActive ? Color.mono.textPrimary : Color.mono.textTertiary)
                    .lineLimit(1)
                Text(verbatim: "\(frequencyText) · \(DateFormatting.dayTitle(rule.nextDueDate, now: now, calendar: store.periods.calendar, language: language))")
                    .lineLimit(2)
                    .monoFont(.caption)
                .foregroundStyle(rule.nextDueDate < now && rule.isActive ? Color.mono.warning : Color.mono.textTertiary)
            }
            Spacer(minLength: 8)
            MoneyText(money: rule.kind == .income ? rule.amount : rule.amount.negated, token: .amountRow,
                      color: rule.kind == .income ? Color.mono.positive : Color.mono.textPrimary, compact: true)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var frequencyText: String {
        guard rule.interval > 1 else { return rule.frequency.title(language) }
        switch rule.frequency {
        case .weekly: return Phrase(ru: "Раз в \(rule.interval) нед.", uz: "Har \(rule.interval) haftada", en: "Every \(rule.interval) weeks")(language)
        case .monthly: return Phrase(ru: "Раз в \(rule.interval) мес.", uz: "Har \(rule.interval) oyda", en: "Every \(rule.interval) months")(language)
        case .yearly: return Phrase(ru: "Раз в \(rule.interval) г.", uz: "Har \(rule.interval) yilda", en: "Every \(rule.interval) years")(language)
        }
    }
}
