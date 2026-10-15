import Foundation
import MonoCore
import MonoAnalytics

/// Сводка финансов для внешней нейросети. Считается на телефоне и содержит только агрегаты:
/// итоги по месяцам, топ категорий и продавцов, средние, регулярные траты, бюджеты и сравнение периодов.
///
/// Ни списка операций, ни счетов, ни остатков, ни заметок и тегов здесь нет. Названия категорий и продавцов
/// проходят через `PrivacySanitizer`, переводы людям сворачиваются в «перевод человеку».
public struct FinancialSummaryBuilder: Sendable {
    public let analytics: AnalyticsEngine
    public let budgets: [Budget]
    public let now: Date
    /// Сколько месяцев показывать в итогах (включая текущий).
    public let months: Int

    let formatter = MoneyFormatter(language: .ru)

    public init(analytics: AnalyticsEngine, budgets: [Budget] = [], now: Date = Date(), months: Int = 6) {
        self.analytics = analytics
        self.budgets = budgets
        self.now = now
        self.months = max(1, months)
    }

    private var periods: PeriodCalendar { analytics.periods }
    private var currentMonth: MonthKey { periods.monthKey(now) }

    /// Полный текст сводки — ровно то, что уйдёт в нейросеть.
    public func text() -> String {
        let sections = [header(), monthlyTotals(), categories(), comparison(), merchants(), averages(), recurring(), budgetLines()]
        return sections.compactMap { $0 }.joined(separator: "\n\n")
    }

    // MARK: - Разделы

    func header() -> String {
        let day = periods.calendar.component(.day, from: now)
        let total = periods.dayCount(of: currentMonth)
        let today = "\(day) \(MonthNames.name(currentMonth.month, language: .ru, form: .genitive)) \(currentMonth.year)"
        var lines = ["Сводка финансов пользователя, посчитанная приложением MONO на телефоне. Суммы в валюте \(analytics.base.code), переводы между своими счетами не считаются расходами."]
        lines.append("Сегодня \(today), прошло \(day) из \(total) дн. текущего месяца.")
        if analytics.transactions.allSatisfy({ $0.kind == .adjustment || $0.kind == .transfer }) {
            lines.append("Операций пока нет — данных для анализа нет.")
        }
        return lines.joined(separator: "\n")
    }

    func monthlyTotals() -> String? {
        var lines: [String] = []
        for offset in stride(from: 0, to: months, by: 1) {
            let key = currentMonth.adding(months: -offset)
            let summary = analytics.summary(periods.monthRange(key))
            guard !summary.isEmpty else { continue }
            var line = "- \(monthTitle(key))"
            if offset == 0 { line += " (текущий, неполный)" }
            line += ": доходы \(money(summary.income)), расходы \(money(summary.spending))"
            if summary.fees.minorUnits != 0 { line += ", комиссии \(money(summary.fees))" }
            line += ", итог \(money(summary.net, sign: true)), операций \(summary.transactionCount)"
            if !summary.excludedCurrencies.isEmpty {
                line += " (без операций в \(summary.excludedCurrencies.map(\.code).sorted().joined(separator: ", ")) — нет курса)"
            }
            lines.append(line)
        }
        guard !lines.isEmpty else { return nil }
        return "Итоги по месяцам:\n" + lines.joined(separator: "\n")
    }

    func categories() -> String? {
        var blocks: [String] = []
        for (key, title) in [(currentMonth, "текущий месяц"), (currentMonth.previous, "прошлый месяц")] {
            let items = analytics.spendingByCategory(periods.monthRange(key)).filter { $0.amount.isPositive }.prefix(8)
            guard !items.isEmpty else { continue }
            let lines = items.map { item in
                "- \(categoryName(item.categoryID)): \(money(item.amount)) (\(percent(item.share)), операций \(item.count))"
            }
            blocks.append("Расходы по категориям, \(monthTitle(key)) (\(title)):\n" + lines.joined(separator: "\n"))
        }
        let split = analytics.mandatorySplit(periods.monthRange(currentMonth))
        if split.total.isPositive {
            blocks.append("Обязательные расходы в текущем месяце: \(money(split.mandatory)), необязательные: \(money(split.optional))"
                          + (split.uncategorized.isPositive ? ", без категории: \(money(split.uncategorized))." : "."))
        }
        return blocks.isEmpty ? nil : blocks.joined(separator: "\n\n")
    }

    /// Текущий месяц по сегодняшний день против тех же дней прошлого месяца.
    func comparison() -> String? {
        let monthStart = periods.monthRange(currentMonth).start
        let tomorrow = periods.addingDays(1, to: periods.startOfDay(now))
        let current = DateRange(start: monthStart, end: tomorrow)
        let elapsed = periods.numberOfDays(in: current)
        let previousRange = periods.monthRange(currentMonth.previous)
        let previousEnd = min(periods.addingDays(elapsed, to: previousRange.start), previousRange.end)
        let previous = DateRange(start: previousRange.start, end: previousEnd)
        let result = analytics.compare(current, with: previous)
        guard !result.current.isEmpty || !result.previous.isEmpty else { return nil }

        var lines = ["Сравнение: 1–\(elapsed) число \(MonthNames.name(currentMonth.month, language: .ru, form: .genitive)) против тех же дней \(MonthNames.name(currentMonth.previous.month, language: .ru, form: .genitive)):"]
        var total = "- расходы \(money(result.current.spending)) против \(money(result.previous.spending))"
        if let ratio = result.spendingChangeRatio { total += " (\(signedPercent(ratio)))" }
        lines.append(total)
        lines.append("- доходы \(money(result.current.income)) против \(money(result.previous.income))")
        let movers = result.categories
            .filter { $0.change.minorUnits != 0 }
            .sorted { abs($0.change.minorUnits) > abs($1.change.minorUnits) }
            .prefix(5)
        for delta in movers {
            var line = "- \(categoryName(delta.categoryID)): \(money(delta.current)) против \(money(delta.previous))"
            if let ratio = delta.changeRatio { line += " (\(signedPercent(ratio)))" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Частые продавцы за 90 дней. Одинаковые после очистки названия («перевод человеку») объединяются.
    func merchants() -> String? {
        let range = periods.range(for: .last90Days, now: now)
        var merged: [String: (count: Int, total: Money)] = [:]
        var order: [String] = []
        for stat in analytics.topMerchants(range, limit: 30) {
            let name = merchantName(stat.name, categoryID: stat.categoryID)
            guard !name.isEmpty else { continue }
            if let existing = merged[name] {
                merged[name] = (existing.count + stat.count, existing.total + stat.total)
            } else {
                merged[name] = (stat.count, stat.total)
                order.append(name)
            }
        }
        let top = order
            .sorted { merged[$0]!.total.minorUnits > merged[$1]!.total.minorUnits }
            .prefix(10)
        guard !top.isEmpty else { return nil }
        let lines = top.map { name in
            let item = merged[name]!
            return "- \(name): \(money(item.total)), покупок \(item.count)"
        }
        return "Частые продавцы за последние 90 дней:\n" + lines.joined(separator: "\n")
    }

    func averages() -> String? {
        var lines: [String] = []
        let fullMonths = (1...3).map { currentMonth.adding(months: -$0) }
            .map { analytics.summary(periods.monthRange($0)) }
            .filter { !$0.isEmpty }
        if !fullMonths.isEmpty {
            let count = Int64(fullMonths.count)
            let spending = fullMonths.reduce(Money.zero(analytics.base)) { $0 + $1.outflow }
            let income = fullMonths.reduce(Money.zero(analytics.base)) { $0 + $1.income }
            lines.append("- в среднем за месяц (последние полные месяцы: \(fullMonths.count)): расходы \(money(divide(spending, count))), доходы \(money(divide(income, count)))")
        }
        let thisMonth = periods.monthRange(currentMonth)
        let daily = analytics.averageDailySpending(thisMonth, now: now)
        if daily.isPositive {
            lines.append("- в среднем в день в текущем месяце: \(money(daily))")
        }
        if let projected = analytics.projectedMonthSpending(now: now), projected.isPositive {
            lines.append("- прогноз расходов на весь текущий месяц при том же темпе: \(money(projected))")
        }
        guard !lines.isEmpty else { return nil }
        return "Средние:\n" + lines.joined(separator: "\n")
    }

    func recurring() -> String? {
        let items = analytics.recurringCandidates(now: now).prefix(12)
        guard !items.isEmpty else { return nil }
        let lines = items.map { item in
            let frequency = item.frequency == .weekly ? "раз в неделю" : (item.frequency == .monthly ? "раз в месяц" : "раз в год")
            let next = periods.calendar.dateComponents([.day, .month], from: item.nextExpectedDate)
            let nextText = "\(next.day ?? 1) \(MonthNames.name(next.month ?? 1, language: .ru, form: .genitive))"
            return "- \(merchantName(item.name, categoryID: item.categoryID)) (\(categoryName(item.categoryID))): около \(money(item.typicalAmount)) \(frequency), платежей \(item.occurrences), следующий примерно \(nextText)"
        }
        return "Регулярные траты и подписки (найдены по повторяющимся платежам):\n" + lines.joined(separator: "\n")
    }

    func budgetLines() -> String? {
        let statuses = analytics.budgetStatuses(budgets, month: currentMonth, now: now)
        guard !statuses.isEmpty else { return nil }
        let lines = statuses.map { status in
            let name = status.budget.isOverall ? "Общий бюджет" : categoryName(status.budget.categoryID)
            var line = "- \(name): лимит \(money(status.effectiveLimit)), потрачено \(money(status.spent)) (\(percent(status.progress)))"
            if status.remaining.isNegative {
                line += ", превышен на \(money(Money(minorUnits: -status.remaining.minorUnits, currency: status.remaining.currency)))"
            } else {
                line += ", осталось \(money(status.remaining))"
            }
            if let projected = status.projectedSpend { line += ", прогноз на месяц \(money(projected))" }
            return line
        }
        return "Бюджеты на текущий месяц:\n" + lines.joined(separator: "\n")
    }

    // MARK: - Форматирование

    func categoryName(_ id: UUID?) -> String {
        guard let id, let category = analytics.categories[id] else { return "Без категории" }
        let cleaned = PrivacySanitizer.clean(category.name)
        return cleaned.contains(PrivacySanitizer.nameMark) ? "Категория пользователя" : cleaned
    }

    func merchantName(_ name: String, categoryID: UUID?) -> String {
        if let categoryID, analytics.categories[categoryID]?.systemKey == SystemCategoryKey.transfersOut {
            return PrivacySanitizer.personTransfer
        }
        return PrivacySanitizer.merchant(name)
    }

    func monthTitle(_ key: MonthKey) -> String {
        "\(MonthNames.name(key.month, language: .ru)) \(key.year)"
    }

    /// Сумма обычными пробелами: «1 250 000 сум».
    func money(_ value: Money, sign: Bool = false) -> String {
        formatter.string(value, sign: sign ? .always : .automatic)
            .replacingOccurrences(of: MoneyFormatter.groupSeparatorNarrow, with: " ")
            .replacingOccurrences(of: MoneyFormatter.nbsp, with: " ")
            .replacingOccurrences(of: MoneyFormatter.minus, with: "-")
    }

    func divide(_ value: Money, _ count: Int64) -> Money {
        Money(minorUnits: value.minorUnits / max(1, count), currency: value.currency)
    }

    func percent(_ ratio: Double) -> String { "\(Int((ratio * 100).rounded()))%" }

    func signedPercent(_ ratio: Double) -> String {
        let value = Int((ratio * 100).rounded())
        return value > 0 ? "+\(value)%" : "\(value)%"
    }
}
