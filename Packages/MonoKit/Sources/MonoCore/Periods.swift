import Foundation

/// Полуоткрытый интервал дат [start, end).
public struct DateRange: Hashable, Codable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = max(start, end)
    }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Пересечение интервалов.
    public func clamped(to other: DateRange) -> DateRange {
        DateRange(start: max(start, other.start), end: min(end, other.end))
    }
}

/// Календарный месяц.
public struct MonthKey: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int

    public init(year: Int, month: Int) {
        var y = year
        var m = month
        while m > 12 { m -= 12; y += 1 }
        while m < 1 { m += 12; y -= 1 }
        self.year = y
        self.month = m
    }

    public init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1)
    }

    public func adding(months: Int) -> MonthKey { MonthKey(year: year, month: month + months) }
    public var next: MonthKey { adding(months: 1) }
    public var previous: MonthKey { adding(months: -1) }

    /// Сколько месяцев от `self` до `other` (может быть отрицательным).
    public func distance(to other: MonthKey) -> Int {
        (other.year - year) * 12 + (other.month - month)
    }

    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    public var description: String { String(format: "%04d-%02d", year, month) }

    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return nil }
        self.init(year: parts[0], month: parts[1])
    }
}

/// Готовые периоды для аналитики и графиков.
public enum PeriodPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case last7Days
    case last30Days
    case last90Days
    case last365Days
    case thisWeek
    case thisMonth
    case lastMonth
    case thisYear

    public var id: String { rawValue }

    public var shortTitle: Phrase {
        switch self {
        case .last7Days: return Phrase(ru: "7Д", uz: "7K", en: "7D")
        case .last30Days: return Phrase(ru: "30Д", uz: "30K", en: "30D")
        case .last90Days: return Phrase(ru: "90Д", uz: "90K", en: "90D")
        case .last365Days: return Phrase(ru: "1Г", uz: "1Y", en: "1Y")
        case .thisWeek: return Phrase(ru: "Неделя", uz: "Hafta", en: "Week")
        case .thisMonth: return Phrase(ru: "Месяц", uz: "Oy", en: "Month")
        case .lastMonth: return Phrase(ru: "Прошлый месяц", uz: "O‘tgan oy", en: "Last month")
        case .thisYear: return Phrase(ru: "Год", uz: "Yil", en: "Year")
        }
    }
}

/// Календарь приложения: григорианский, неделя с понедельника, часовой пояс устройства.
public struct PeriodCalendar: Sendable {
    public var calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        self.calendar = calendar
    }

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    public func addingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(TimeInterval(days) * 86_400)
    }

    public func dayRange(_ date: Date) -> DateRange {
        let start = startOfDay(date)
        return DateRange(start: start, end: addingDays(1, to: start))
    }

    public func monthKey(_ date: Date) -> MonthKey { MonthKey(date: date, calendar: calendar) }

    public func monthRange(_ key: MonthKey) -> DateRange {
        var components = DateComponents()
        components.year = key.year
        components.month = key.month
        components.day = 1
        let start = calendar.date(from: components) ?? Date()
        var nextComponents = DateComponents()
        nextComponents.year = key.next.year
        nextComponents.month = key.next.month
        nextComponents.day = 1
        let end = calendar.date(from: nextComponents) ?? start.addingTimeInterval(31 * 86_400)
        return DateRange(start: start, end: end)
    }

    public func weekStart(_ date: Date) -> Date {
        let start = startOfDay(date)
        let weekday = calendar.component(.weekday, from: start)
        let shift = (weekday - calendar.firstWeekday + 7) % 7
        return addingDays(-shift, to: start)
    }

    public func range(for preset: PeriodPreset, now: Date) -> DateRange {
        let tomorrow = addingDays(1, to: startOfDay(now))
        switch preset {
        case .last7Days: return DateRange(start: addingDays(-7, to: tomorrow), end: tomorrow)
        case .last30Days: return DateRange(start: addingDays(-30, to: tomorrow), end: tomorrow)
        case .last90Days: return DateRange(start: addingDays(-90, to: tomorrow), end: tomorrow)
        case .last365Days: return DateRange(start: addingDays(-365, to: tomorrow), end: tomorrow)
        case .thisWeek:
            let start = weekStart(now)
            return DateRange(start: start, end: addingDays(7, to: start))
        case .thisMonth: return monthRange(monthKey(now))
        case .lastMonth: return monthRange(monthKey(now).previous)
        case .thisYear:
            let year = calendar.component(.year, from: now)
            return DateRange(start: monthRange(MonthKey(year: year, month: 1)).start,
                             end: monthRange(MonthKey(year: year + 1, month: 1)).start)
        }
    }

    /// Интервал той же длины непосредственно перед данным (для сравнения).
    /// Для календарного месяца возвращает предыдущий календарный месяц.
    public func previousRange(of range: DateRange) -> DateRange {
        let key = monthKey(range.start)
        if monthRange(key) == range {
            return monthRange(key.previous)
        }
        let days = numberOfDays(in: range)
        return DateRange(start: addingDays(-days, to: range.start), end: range.start)
    }

    /// Количество календарных дней в интервале (по началам дней).
    public func numberOfDays(in range: DateRange) -> Int {
        let start = startOfDay(range.start)
        let end = startOfDay(range.end)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        let partial = end < range.end ? 1 : 0
        return max(days + partial, 0)
    }

    /// Начала дней внутри интервала.
    public func days(in range: DateRange) -> [Date] {
        var result: [Date] = []
        var cursor = startOfDay(range.start)
        while cursor < range.end {
            result.append(cursor)
            cursor = addingDays(1, to: cursor)
        }
        return result
    }

    /// Месяцы, пересекающиеся с интервалом.
    public func months(in range: DateRange) -> [MonthKey] {
        guard range.end > range.start else { return [] }
        var result: [MonthKey] = []
        var key = monthKey(range.start)
        let last = monthKey(range.end.addingTimeInterval(-1))
        while key <= last {
            result.append(key)
            key = key.next
        }
        return result
    }

    /// Количество дней в месяце.
    public func dayCount(of key: MonthKey) -> Int {
        numberOfDays(in: monthRange(key))
    }
}
