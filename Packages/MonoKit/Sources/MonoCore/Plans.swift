import Foundation

/// Месячный бюджет: общий (`categoryID == nil`) или по категории. Лимит — в базовой валюте.
public struct Budget: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var categoryID: UUID?
    public var limit: Money
    /// Переносить неиспользованный остаток на следующий месяц.
    public var rolloverEnabled: Bool
    /// С какого месяца действует бюджет (для расчёта переносов).
    public var startMonth: MonthKey
    public var isArchived: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        categoryID: UUID?,
        limit: Money,
        rolloverEnabled: Bool = false,
        startMonth: MonthKey,
        isArchived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.categoryID = categoryID
        self.limit = limit
        self.rolloverEnabled = rolloverEnabled
        self.startMonth = startMonth
        self.isArchived = isArchived
        self.createdAt = createdAt
    }

    public var isOverall: Bool { categoryID == nil }
}

/// Финансовая цель. Прогресс — либо баланс привязанного счёта, либо сумма взносов.
public struct Goal: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var target: Money
    public var deadline: Date?
    public var icon: String
    public var color: CategoryColor
    public var linkedAccountID: UUID?
    public var isArchived: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        target: Money,
        deadline: Date? = nil,
        icon: String = "star.fill",
        color: CategoryColor = .violet,
        linkedAccountID: UUID? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.deadline = deadline
        self.icon = icon
        self.color = color
        self.linkedAccountID = linkedAccountID
        self.isArchived = isArchived
        self.createdAt = createdAt
    }
}

/// Взнос в цель (учётная отметка; деньги остаются на счетах пользователя).
public struct GoalContribution: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var goalID: UUID
    public var amount: Money
    public var date: Date
    public var note: String?

    public init(id: UUID = UUID(), goalID: UUID, amount: Money, date: Date, note: String? = nil) {
        self.id = id
        self.goalID = goalID
        self.amount = amount
        self.date = date
        self.note = note
    }
}

/// Запланированный крупный расход.
public struct PlannedExpense: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var amount: Money
    public var date: Date
    public var categoryID: UUID?
    public var note: String?
    public var isCompleted: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        amount: Money,
        date: Date,
        categoryID: UUID? = nil,
        note: String? = nil,
        isCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.categoryID = categoryID
        self.note = note
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}

public enum RecurrenceFrequency: String, Codable, Sendable, CaseIterable, Identifiable {
    case weekly
    case monthly
    case yearly

    public var id: String { rawValue }

    public var title: Phrase {
        switch self {
        case .weekly: return Phrase(ru: "Каждую неделю", uz: "Har hafta", en: "Weekly")
        case .monthly: return Phrase(ru: "Каждый месяц", uz: "Har oy", en: "Monthly")
        case .yearly: return Phrase(ru: "Каждый год", uz: "Har yil", en: "Yearly")
        }
    }

    var component: Calendar.Component {
        switch self {
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .yearly: return .year
        }
    }
}

/// Регулярный платёж или поступление. Операции создаются только после подтверждения пользователем.
public struct RecurringRule: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: TransactionKind
    public var amount: Money
    public var accountID: UUID
    public var categoryID: UUID?
    public var merchant: String?
    public var frequency: RecurrenceFrequency
    public var interval: Int
    /// Первая дата; задаёт день месяца/недели для всех следующих.
    public var anchorDate: Date
    /// Ближайшая неподтверждённая дата.
    public var nextDueDate: Date
    public var reminderEnabled: Bool
    public var isActive: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        kind: TransactionKind = .expense,
        amount: Money,
        accountID: UUID,
        categoryID: UUID? = nil,
        merchant: String? = nil,
        frequency: RecurrenceFrequency = .monthly,
        interval: Int = 1,
        anchorDate: Date,
        nextDueDate: Date? = nil,
        reminderEnabled: Bool = true,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.amount = amount
        self.accountID = accountID
        self.categoryID = categoryID
        self.merchant = merchant
        self.frequency = frequency
        self.interval = max(1, interval)
        self.anchorDate = anchorDate
        self.nextDueDate = nextDueDate ?? anchorDate
        self.reminderEnabled = reminderEnabled
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

/// Даты повторений всегда считаются от якорной даты, поэтому 31-е число не «съезжает» после февраля.
public enum RecurrenceMath {
    public static func occurrence(
        _ index: Int,
        anchor: Date,
        frequency: RecurrenceFrequency,
        interval: Int,
        calendar: Calendar
    ) -> Date {
        let step = max(1, interval) * index
        return calendar.date(byAdding: frequency.component, value: step, to: anchor) ?? anchor
    }

    /// Первое повторение строго после `date`.
    public static func nextOccurrence(
        after date: Date,
        anchor: Date,
        frequency: RecurrenceFrequency,
        interval: Int,
        calendar: Calendar
    ) -> Date {
        if anchor > date { return anchor }
        var low = 0
        var high = 1
        while occurrence(high, anchor: anchor, frequency: frequency, interval: interval, calendar: calendar) <= date {
            low = high
            high *= 2
            if high > 100_000 { break }
        }
        while high - low > 1 {
            let mid = (low + high) / 2
            if occurrence(mid, anchor: anchor, frequency: frequency, interval: interval, calendar: calendar) <= date {
                low = mid
            } else {
                high = mid
            }
        }
        return occurrence(high, anchor: anchor, frequency: frequency, interval: interval, calendar: calendar)
    }

    /// Все повторения в интервале [from, to].
    public static func occurrences(
        from start: Date,
        through end: Date,
        anchor: Date,
        frequency: RecurrenceFrequency,
        interval: Int,
        calendar: Calendar,
        limit: Int = 500
    ) -> [Date] {
        var result: [Date] = []
        var cursor = anchor >= start ? anchor : nextOccurrence(after: start.addingTimeInterval(-1), anchor: anchor, frequency: frequency, interval: interval, calendar: calendar)
        while cursor <= end && result.count < limit {
            result.append(cursor)
            cursor = nextOccurrence(after: cursor, anchor: anchor, frequency: frequency, interval: interval, calendar: calendar)
        }
        return result
    }
}
