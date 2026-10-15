import Foundation
import MonoCore
import MonoAnalytics

/// Короткий вывод для главного экрана. Строится только из сохранённых данных; при нехватке данных не создаётся.
public struct Insight: Identifiable, Equatable, Sendable {
    public enum Tone: String, Sendable {
        case positive
        case negative
        case warning
        case neutral
    }

    public enum Kind: String, Sendable {
        case budget
        case monthToDate
        case categoryGrowth
        case pace
        case upcoming
        case savingsRate
        case largestPurchase
        case fees
    }

    public var kind: Kind
    public var tone: Tone
    /// Короткая надпись-«кикер»: «ТЕМП МЕСЯЦА».
    public var title: String
    /// Текст в стиле журнальной цитаты.
    public var text: String
    public var value: Money?
    public var categoryID: UUID?
    public var id: String { kind.rawValue + (categoryID?.uuidString ?? "") }
}

public struct InsightEngine: Sendable {
    public let analytics: AnalyticsEngine
    public let budgets: [Budget]
    public let recurring: [RecurringRule]
    public let language: AppLanguage
    public let now: Date
    let formatter: MoneyFormatter

    public init(analytics: AnalyticsEngine, budgets: [Budget] = [], recurring: [RecurringRule] = [], language: AppLanguage = .ru, now: Date = Date()) {
        self.analytics = analytics
        self.budgets = budgets
        self.recurring = recurring
        self.language = language
        self.now = now
        self.formatter = MoneyFormatter(language: language)
    }

    public func insights(limit: Int = 5) -> [Insight] {
        let candidates: [Insight?] = [
            budgetInsight(),
            monthToDateInsight(),
            categoryGrowthInsight(),
            paceInsight(),
            upcomingInsight(),
            savingsRateInsight(),
            largestPurchaseInsight(),
            feesInsight()
        ]
        return Array(candidates.compactMap { $0 }.prefix(limit))
    }

    private var monthKey: MonthKey { analytics.periods.monthKey(now) }
    private var day: Int { analytics.periods.calendar.component(.day, from: now) }

    private func percent(_ ratio: Double) -> String { "\(Int((abs(ratio) * 100).rounded()))%" }

    private func categoryName(_ id: UUID?) -> String {
        id.flatMap { analytics.categories[$0]?.name } ?? Phrase(ru: "Без категории", uz: "Kategoriyasiz", en: "Uncategorized")(language)
    }

    // MARK: - Правила

    func budgetInsight() -> Insight? {
        let statuses = analytics.budgetStatuses(budgets, month: monthKey, now: now)
        guard let worst = statuses.filter({ $0.state != .ok }).max(by: { $0.progress < $1.progress }) else { return nil }
        let name = worst.budget.categoryID.map { "«\(categoryName($0))»" } ?? Phrase(ru: "месяца", uz: "oylik", en: "monthly")(language)
        let title = Phrase(ru: "БЮДЖЕТ", uz: "BYUDJET", en: "BUDGET")(language)
        if worst.state == .exceeded {
            let over = (worst.spent - worst.effectiveLimit)
            return Insight(kind: .budget, tone: .negative, title: title,
                           text: Phrase(ru: "Бюджет \(name) превышен на \(formatter.string(over)).",
                                        uz: "\(name) byudjeti \(formatter.string(over)) ga oshdi.",
                                        en: "The \(name) budget is over by \(formatter.string(over)).")(language),
                           value: over, categoryID: worst.budget.categoryID)
        }
        var text = Phrase(ru: "Бюджет \(name) использован на \(percent(worst.progress)) — осталось \(formatter.string(worst.remaining))",
                          uz: "\(name) byudjetining \(percent(worst.progress)) ishlatildi — \(formatter.string(worst.remaining)) qoldi",
                          en: "\(percent(worst.progress)) of the \(name) budget is used — \(formatter.string(worst.remaining)) left")(language)
        if worst.daysLeft > 0 {
            text += Phrase(ru: " на \(worst.daysLeft) дн.", uz: " \(worst.daysLeft) kunga.", en: " for \(worst.daysLeft) days.")(language)
        } else {
            text += "."
        }
        return Insight(kind: .budget, tone: .warning, title: title, text: text, value: worst.remaining, categoryID: worst.budget.categoryID)
    }

    func monthToDateInsight() -> Insight? {
        guard day >= 3 else { return nil }
        let mtd = analytics.monthToDate(now: now)
        guard mtd.previous.minorUnits > 0, mtd.current.minorUnits > 0 else { return nil }
        let ratio = Double(mtd.current.minorUnits - mtd.previous.minorUnits) / Double(mtd.previous.minorUnits)
        guard abs(ratio) >= 0.05 else { return nil }
        let currentMonth = MonthNames.name(monthKey.month, language: language, form: .genitive)
        let previousMonth = MonthNames.name(monthKey.previous.month, language: language, form: .genitive)
        let less = ratio < 0
        let text = less
            ? Phrase(ru: "За \(day) дн. \(currentMonth) потрачено на \(percent(ratio)) меньше, чем за те же дни \(previousMonth).",
                     uz: "\(currentMonth.capitalized) oyining \(day) kunida o‘tgan oyning shu kunlariga nisbatan \(percent(ratio)) kam sarflandi.",
                     en: "In the first \(day) days of \(currentMonth) you spent \(percent(ratio)) less than in the same days of \(previousMonth).")(language)
            : Phrase(ru: "За \(day) дн. \(currentMonth) потрачено на \(percent(ratio)) больше, чем за те же дни \(previousMonth).",
                     uz: "\(currentMonth.capitalized) oyining \(day) kunida o‘tgan oyga nisbatan \(percent(ratio)) ko‘p sarflandi.",
                     en: "In the first \(day) days of \(currentMonth) you spent \(percent(ratio)) more than in the same days of \(previousMonth).")(language)
        return Insight(kind: .monthToDate, tone: less ? .positive : .negative,
                       title: Phrase(ru: "ТЕМП МЕСЯЦА", uz: "OY SUR’ATI", en: "MONTH PACE")(language), text: text, value: mtd.current, categoryID: nil)
    }

    func categoryGrowthInsight() -> Insight? {
        guard day >= 5 else { return nil }
        let monthRange = analytics.periods.monthRange(monthKey)
        let elapsed = now.timeIntervalSince(monthRange.start)
        let previousRange = analytics.periods.monthRange(monthKey.previous)
        let comparison = analytics.compare(DateRange(start: monthRange.start, end: now),
                                           with: DateRange(start: previousRange.start, end: min(previousRange.start.addingTimeInterval(elapsed), previousRange.end)))
        let threshold = Money(major: 100_000, currency: analytics.base) ?? .zero(analytics.base)
        guard let grown = comparison.categories.first(where: { delta in
            guard let ratio = delta.changeRatio else { return false }
            return ratio >= 0.3 && delta.change.minorUnits >= threshold.minorUnits && delta.previous.minorUnits > 0
        }), let ratio = grown.changeRatio else { return nil }
        let previousMonth = MonthNames.name(monthKey.previous.month, language: language, form: .prepositional)
        let text = Phrase(ru: "«\(categoryName(grown.categoryID))» — на \(percent(ratio)) больше, чем к этому дню в \(previousMonth): \(formatter.compact(grown.current)).",
                          uz: "«\(categoryName(grown.categoryID))» — o‘tgan oyga nisbatan \(percent(ratio)) ko‘p: \(formatter.compact(grown.current)).",
                          en: "“\(categoryName(grown.categoryID))” is up \(percent(ratio)) versus this point last month: \(formatter.compact(grown.current)).")(language)
        return Insight(kind: .categoryGrowth, tone: .negative, title: Phrase(ru: "РОСТ ТРАТ", uz: "XARAJAT O‘SISHI", en: "SPENDING UP")(language),
                       text: text, value: grown.current, categoryID: grown.categoryID)
    }

    func paceInsight() -> Insight? {
        guard let projected = analytics.projectedMonthSpending(now: now) else { return nil }
        let range = analytics.periods.monthRange(monthKey)
        let average = analytics.averageDailySpending(range, now: now)
        guard average.minorUnits > 0 else { return nil }
        let text = Phrase(ru: "В среднем \(formatter.string(average)) в день. К концу месяца расходы выйдут примерно на \(formatter.compact(projected)).",
                          uz: "Kuniga o‘rtacha \(formatter.string(average)). Oy oxirida taxminan \(formatter.compact(projected)) bo‘ladi.",
                          en: "About \(formatter.string(average)) a day. At this pace the month ends near \(formatter.compact(projected)).")(language)
        return Insight(kind: .pace, tone: .neutral, title: Phrase(ru: "ПРОГНОЗ", uz: "PROGNOZ", en: "FORECAST")(language), text: text, value: projected, categoryID: nil)
    }

    func upcomingInsight() -> Insight? {
        let horizon = analytics.periods.addingDays(7, to: now)
        guard let next = recurring.filter({ $0.isActive && $0.nextDueDate <= horizon }).min(by: { $0.nextDueDate < $1.nextDueDate }) else { return nil }
        let days = analytics.periods.calendar.dateComponents([.day], from: analytics.periods.startOfDay(now), to: analytics.periods.startOfDay(next.nextDueDate)).day ?? 0
        let when: String
        if days < 0 {
            when = Phrase(ru: "Ожидает подтверждения", uz: "Tasdiqlash kutilmoqda", en: "Awaiting confirmation")(language)
        } else if days == 0 {
            when = Phrase(ru: "Сегодня", uz: "Bugun", en: "Today")(language)
        } else if days == 1 {
            when = Phrase(ru: "Завтра", uz: "Ertaga", en: "Tomorrow")(language)
        } else {
            when = Phrase(ru: "Через \(days) дн.", uz: "\(days) kundan keyin", en: "In \(days) days")(language)
        }
        let text = "\(when): «\(next.title)» — \(formatter.string(next.amount))."
        return Insight(kind: .upcoming, tone: days < 0 ? .warning : .neutral,
                       title: Phrase(ru: "РЕГУЛЯРНЫЙ ПЛАТЁЖ", uz: "DOIMIY TO‘LOV", en: "UPCOMING")(language), text: text, value: next.amount, categoryID: next.categoryID)
    }

    func savingsRateInsight() -> Insight? {
        let previous = analytics.summary(analytics.periods.monthRange(monthKey.previous))
        guard previous.income.minorUnits > 0, previous.transactionCount >= 5 else { return nil }
        let rate = Double(previous.net.minorUnits) / Double(previous.income.minorUnits)
        let month = MonthNames.name(monthKey.previous.month, language: language, form: .prepositional)
        let text: String
        if rate > 0 {
            text = Phrase(ru: "В \(month) удалось сохранить \(percent(rate)) дохода — \(formatter.compact(previous.net)).",
                          uz: "O‘tgan oyda daromadning \(percent(rate)) qismi saqlandi — \(formatter.compact(previous.net)).",
                          en: "Last month you kept \(percent(rate)) of income — \(formatter.compact(previous.net)).")(language)
        } else {
            text = Phrase(ru: "В \(month) расходы превысили доходы на \(formatter.compact(previous.net.magnitude)).",
                          uz: "O‘tgan oyda xarajatlar daromaddan \(formatter.compact(previous.net.magnitude)) ga oshdi.",
                          en: "Last month spending exceeded income by \(formatter.compact(previous.net.magnitude)).")(language)
        }
        return Insight(kind: .savingsRate, tone: rate > 0 ? .positive : .negative,
                       title: Phrase(ru: "НОРМА СБЕРЕЖЕНИЙ", uz: "JAMG‘ARMA", en: "SAVINGS RATE")(language), text: text, value: previous.net, categoryID: nil)
    }

    func largestPurchaseInsight() -> Insight? {
        let range = analytics.periods.monthRange(monthKey)
        let expenses = analytics.transactions.filter { $0.kind == .expense && range.contains($0.date) }
        guard expenses.count >= 3, let largest = analytics.largestExpenses(range, limit: 1).first,
              let amount = analytics.converter.toBase(largest.amount) else { return nil }
        let label = largest.merchant ?? categoryName(largest.categoryID)
        let text = Phrase(ru: "Крупнейшая покупка месяца — «\(label)», \(formatter.string(amount)).",
                          uz: "Oyning eng katta xaridi — «\(label)», \(formatter.string(amount)).",
                          en: "Largest purchase this month: “\(label)”, \(formatter.string(amount)).")(language)
        return Insight(kind: .largestPurchase, tone: .neutral, title: Phrase(ru: "КРУПНЕЙШАЯ ТРАТА", uz: "ENG KATTA XARID", en: "LARGEST")(language),
                       text: text, value: amount, categoryID: largest.categoryID)
    }

    func feesInsight() -> Insight? {
        let summary = analytics.summary(analytics.periods.monthRange(monthKey))
        guard summary.fees.minorUnits > 0 else { return nil }
        let share = summary.outflow.minorUnits > 0 ? Double(summary.fees.minorUnits) / Double(summary.outflow.minorUnits) : 0
        let shareText = String(format: "%.1f", share * 100).replacingOccurrences(of: ".", with: language == .en ? "." : ",")
        let text = Phrase(ru: "Комиссии за месяц — \(formatter.string(summary.fees)), это \(shareText)% всех трат.",
                          uz: "Oylik komissiyalar — \(formatter.string(summary.fees)), barcha xarajatlarning \(shareText)%.",
                          en: "Fees this month: \(formatter.string(summary.fees)), \(shareText)% of all spending.")(language)
        return Insight(kind: .fees, tone: .neutral, title: Phrase(ru: "КОМИССИИ", uz: "KOMISSIYALAR", en: "FEES")(language), text: text, value: summary.fees, categoryID: nil)
    }
}
