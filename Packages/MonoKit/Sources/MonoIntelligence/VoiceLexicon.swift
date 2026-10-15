import Foundation
import MonoCore

/// Словари для разбора речи: глаголы, даты, валюты, предлоги. Все слова — после `TextNormalizer.fold`.
enum VoiceLexicon {
    // MARK: Тип операции

    static let transferStems = ["перевел", "перевела", "перевели", "перекинул", "перекинула", "скинул", "скинула", "закинул", "закинула",
                                "пополнил", "пополнила", "o'tkazdim", "otkazdim", "o'tkazib", "transferred", "moved"]
    static let expenseStems = ["потратил", "потрачен", "заплатил", "оплатил", "купил", "заправил", "отдал", "списал", "ушло", "ушел", "ушла",
                               "расход", "пообедал", "поужинал", "позавтракал", "взял", "заказал", "sarfladim", "sarfla", "to'ladim", "toladim",
                               "xarajat", "spent", "paid", "bought"]
    static let incomeStems = ["получил", "пришл", "поступил", "поступлени", "зачисл", "заработал", "доход", "tushdi", "kirim", "received",
                              "earned", "income"]
    static let refundStems = ["вернули", "возврат", "refund", "qaytarildi", "qaytdi", "qaytardi"]
    static let feeStems = ["комисси", "komissiya"]
    static let feeExact: Set<String> = ["fee"]
    static let debtWords = ["долг", "qarz", "debt"]
    static let personRecipients: Set<String> = [
        "другу", "подруге", "маме", "папе", "брату", "сестре", "жене", "мужу", "сыну", "дочке", "дочери", "коллеге", "бабушке",
        "дедушке", "родителям", "отцу", "матери", "тете", "дяде", "ему", "ей", "onamga", "otamga", "akamga", "ukamga", "opamga",
        "singlimga", "do'stimga", "dostimga", "friend", "mom", "dad"
    ]
    static let topUpStems = ["пополнил", "пополнила", "закинул", "закинула"]

    static func contains(_ words: [String], stems: [String]) -> Bool {
        words.contains { word in stems.contains { word.hasPrefix($0) } }
    }

    // MARK: Сегментация

    static let conjunctions: Set<String> = ["и", "а", "еще", "плюс", "также", "потом", "затем", "ва", "and", "then", "plus"]

    // MARK: Валюты

    static func currency(forWord word: String) -> Currency? {
        if word.hasPrefix("сум") || word == "so'm" || word == "som" || word == "sum" || word == "сўм" || word == "uzs" || word.hasPrefix("so'm") {
            return .uzs
        }
        if word.hasPrefix("доллар") || word.hasPrefix("долл") || word.hasPrefix("бакс") || word.hasPrefix("dollar") || word == "usd" || word == "$" {
            return .usd
        }
        if word == "евро" || word == "eur" || word == "euro" || word == "yevro" || word == "€" { return .eur }
        if word.hasPrefix("рубл") || word == "руб" || word == "rub" || word == "₽" || word.hasPrefix("rubl") { return .rub }
        if word == "тенге" || word == "kzt" || word == "₸" { return .kzt }
        if word.hasPrefix("фунт") || word == "gbp" || word == "£" { return .gbp }
        return nil
    }

    // MARK: Даты

    static let relativeDays: [String: Int] = [
        "сегодня": 0, "сейчас": 0, "вчера": -1, "позавчера": -2,
        "bugun": 0, "kecha": -1, "today": 0, "yesterday": -1
    ]

    /// Номер дня недели в нотации Calendar (1 — воскресенье).
    static let weekdays: [String: Int] = [
        "понедельник": 2, "вторник": 3, "среду": 4, "среда": 4, "четверг": 5, "пятницу": 6, "пятница": 6,
        "субботу": 7, "суббота": 7, "воскресенье": 1,
        "dushanba": 2, "seshanba": 3, "chorshanba": 4, "payshanba": 5, "juma": 6, "shanba": 7, "yakshanba": 1,
        "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7, "sunday": 1
    ]

    static let previousMarkers = ["прошл", "o'tgan", "otgan", "last"]

    static func month(forWord word: String) -> Int? {
        let exact: [String: Int] = [
            "января": 1, "январь": 1, "февраля": 2, "февраль": 2, "марта": 3, "март": 3, "апреля": 4, "апрель": 4,
            "мая": 5, "май": 5, "июня": 6, "июнь": 6, "июля": 7, "июль": 7, "августа": 8, "август": 8,
            "сентября": 9, "сентябрь": 9, "октября": 10, "октябрь": 10, "ноября": 11, "ноябрь": 11, "декабря": 12, "декабрь": 12,
            "may": 5, "mart": 3
        ]
        if let value = exact[word] { return value }
        let prefixes: [(String, Int)] = [
            ("yanvar", 1), ("fevral", 2), ("aprel", 4), ("iyun", 6), ("iyul", 7), ("avgust", 8), ("sentyabr", 9),
            ("oktyabr", 10), ("noyabr", 11), ("dekabr", 12),
            ("january", 1), ("february", 2), ("march", 3), ("april", 4), ("june", 6), ("july", 7), ("august", 8),
            ("september", 9), ("october", 10), ("november", 11), ("december", 12)
        ]
        return prefixes.first { word.hasPrefix($0.0) }?.1
    }

    /// Порядковые числительные дня месяца: «третьего», «двадцать первого», «первое».
    static let ordinalDays: [String: Int] = {
        let stems: [(String, Int)] = [
            ("перв", 1), ("втор", 2), ("трет", 3), ("четверт", 4), ("пят", 5), ("шест", 6), ("седьм", 7), ("восьм", 8), ("девят", 9),
            ("десят", 10), ("одиннадцат", 11), ("двенадцат", 12), ("тринадцат", 13), ("четырнадцат", 14), ("пятнадцат", 15),
            ("шестнадцат", 16), ("семнадцат", 17), ("восемнадцат", 18), ("девятнадцат", 19), ("двадцат", 20), ("тридцат", 30)
        ]
        var map: [String: Int] = [:]
        for (stem, value) in stems {
            for ending in ["ого", "ое", "ье", "ьего", "ий"] { map[stem + ending] = value }
        }
        map["третьего"] = 3
        map["третье"] = 3
        return map
    }()

    // MARK: Не деньги

    static let quantityUnits: Set<String> = ["шт", "штук", "штуки", "штука", "кг", "кило", "килограмм", "килограмма", "грамм", "г",
                                             "литр", "литра", "литров", "л", "dona", "kg", "litr", "pcs", "раз", "раза", "дня", "дней",
                                             "день", "минут", "часа", "часов", "час", "процент", "процента", "процентов", "%"]
    static let cardWords = ["карт", "karta", "card", "карточк"]

    // MARK: Счета

    static let sourcePrepositions: Set<String> = ["с", "со", "из", "from"]
    static let destinationPrepositions: Set<String> = ["на", "to", "в", "во"]
    /// Слова между предлогом и названием счёта: «с карты Капиталбанка».
    static let accountFillers = ["карт", "карточк", "счет", "банк", "karta", "hisob", "card", "account", "моей", "моего", "мою", "свою", "своей", "основн"]
    static let merchantContinuations = ["маркет", "market", "тезкор", "tezkor", "насия", "nasiya"]
    static let genericAccountWords: Set<String> = ["карта", "карты", "card", "karta", "kartasi", "счет", "счета", "hisob", "мой", "моя", "my"]
}
