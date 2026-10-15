import Foundation

/// Названия месяцев без зависимости от системной локали.
public enum MonthNames {
    private static let ruNominative = ["январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]
    private static let ruGenitive = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    private static let ruPrepositional = ["январе", "феврале", "марте", "апреле", "мае", "июне", "июле", "августе", "сентябре", "октябре", "ноябре", "декабре"]
    private static let uz = ["yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avgust", "sentyabr", "oktyabr", "noyabr", "dekabr"]
    private static let en = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    public enum Form: Sendable {
        /// «октябрь», «October»
        case nominative
        /// «октября» (3 октября)
        case genitive
        /// «в октябре»
        case prepositional
    }

    public static func name(_ month: Int, language: AppLanguage, form: Form = .nominative) -> String {
        let index = max(1, min(12, month)) - 1
        switch language {
        case .ru:
            switch form {
            case .nominative: return ruNominative[index]
            case .genitive: return ruGenitive[index]
            case .prepositional: return ruPrepositional[index]
            }
        case .uz: return uz[index]
        case .en: return en[index]
        }
    }

    /// «в октябре», «oktyabrda», «in October»; с годом, если он не текущий.
    public static func inMonth(_ key: MonthKey, language: AppLanguage, currentYear: Int) -> String {
        let yearSuffix = key.year == currentYear ? "" : " \(key.year)"
        switch language {
        case .ru: return "в " + name(key.month, language: .ru, form: .prepositional) + (yearSuffix.isEmpty ? "" : yearSuffix + " г.")
        case .uz: return name(key.month, language: .uz) + yearSuffix + "da"
        case .en: return "in " + name(key.month, language: .en) + yearSuffix
        }
    }

    /// Номер месяца по слову в любой форме: «августе», «август», «avgustda», «August».
    public static func month(fromWord word: String) -> Int? {
        let folded = TextNormalizer.fold(word)
        let stems: [(String, Int)] = [
            ("январ", 1), ("феврал", 2), ("март", 3), ("апрел", 4), ("июн", 6), ("июл", 7), ("август", 8), ("сентябр", 9),
            ("октябр", 10), ("ноябр", 11), ("декабр", 12),
            ("yanvar", 1), ("fevral", 2), ("aprel", 4), ("iyun", 6), ("iyul", 7), ("avgust", 8), ("sentyabr", 9),
            ("oktyabr", 10), ("noyabr", 11), ("dekabr", 12),
            ("january", 1), ("february", 2), ("march", 3), ("april", 4), ("june", 6), ("july", 7), ("august", 8),
            ("september", 9), ("october", 10), ("november", 11), ("december", 12)
        ]
        if ["май", "мае", "мая", "may", "mayda"].contains(folded) { return 5 }
        if folded.hasPrefix("mart") { return 3 }
        return stems.first { folded.hasPrefix($0.0) }?.1
    }
}
