import Foundation
import MonoCore

/// Даты для интерфейса на языке приложения.
enum DateFormatting {
    static func dayTitle(_ date: Date, now: Date = Date(), calendar: Calendar, language: AppLanguage = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return Phrase(ru: "Сегодня", uz: "Bugun", en: "Today")(language)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return Phrase(ru: "Вчера", uz: "Kecha", en: "Yesterday")(language)
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide)
            .day()
            .month(.wide)
        if !sameYear { style = style.year() }
        let text = date.formatted(style)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// «Четверг, 15 октября».
    static func weekdayDay(_ date: Date, calendar: Calendar, language: AppLanguage = .current) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide)
            .day()
            .month(.wide)
        let text = date.formatted(style)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func time(_ date: Date, calendar: Calendar, language: AppLanguage = .current) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: language.locale, calendar: calendar, timeZone: calendar.timeZone))
    }

    static func short(_ date: Date, calendar: Calendar, language: AppLanguage = .current) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated))
    }

    static func full(_ date: Date, calendar: Calendar, language: AppLanguage = .current) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: language.locale, calendar: calendar, timeZone: calendar.timeZone))
    }

    static func monthTitle(_ key: MonthKey, calendar: Calendar, language: AppLanguage = .current, includeYear: Bool = true) -> String {
        let name = MonthNames.name(key.month, language: language)
        let capitalized = name.prefix(1).uppercased() + name.dropFirst()
        return includeYear ? "\(capitalized) \(key.year)" : capitalized
    }
}

/// Проценты для подписей: «12 %», «4,5 %» (ru/uz), «12%» (en).
enum PercentFormatting {
    static func string(_ ratio: Double, language: AppLanguage = .current, signed: Bool = false) -> String {
        guard ratio.isFinite else { return "—" }
        let value = abs(ratio * 100)
        var text = value < 9.95 && value >= 0.05 ? String(format: "%.1f", value) : String(format: "%.0f", value)
        if text.hasSuffix(".0") { text.removeLast(2) }
        if language != .en { text = text.replacingOccurrences(of: ".", with: ",") }
        let sign = signed ? (ratio > 0 ? "+" : (ratio < 0 ? MoneyFormatter.minus : "")) : ""
        return sign + text + (language == .en ? "%" : "\u{202F}%")
    }
}
