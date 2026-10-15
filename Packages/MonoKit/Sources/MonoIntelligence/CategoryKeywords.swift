import Foundation
import MonoCore

/// Ключевые слова (основы) → встроенная категория. Русский, узбекский (латиница) и английский.
/// Основы сравниваются как префиксы слов, поэтому покрывают падежи: «обед», «обеда», «обедом».
enum CategoryKeywords {
    struct Rule: Sendable {
        let stem: String
        let key: String
        /// Точное совпадение слова вместо префикса (для коротких слов: «зал», «кот», «зп»).
        let exact: Bool
    }

    private static func rules(_ key: String, _ stems: [String], exact: [String] = []) -> [Rule] {
        stems.map { Rule(stem: $0, key: key, exact: false) } + exact.map { Rule(stem: $0, key: key, exact: true) }
    }

    static let expense: [Rule] =
        rules(SystemCategoryKey.cafe, ["обед", "пообедал", "ужин", "поужинал", "завтрак", "позавтракал", "кофе", "кофейн", "капучино", "латте",
                                       "кафе", "ресторан", "чайхан", "перекус", "ланч", "пицц", "бургер", "шаурм", "донер", "фастфуд", "самс", "суши",
                                       "tushlik", "nonushta", "kechki", "restoran", "qahva", "choyxona", "lunch", "dinner", "breakfast", "coffee", "restaurant"],
              exact: ["kafe", "cafe"])
        + rules(SystemCategoryKey.groceries, ["продукт", "супермаркет", "рынок", "рынке", "базар", "овощ", "фрукт", "хлеб", "молок", "мяс", "магазин",
                                              "oziq", "bozor", "grocer", "supermarket"])
        + rules(SystemCategoryKey.taxi, ["такси", "taksi", "taxi", "uber"])
        + rules(SystemCategoryKey.transport, ["метро", "автобус", "маршрутк", "проезд", "трамва", "электричк", "avtobus", "subway"], exact: ["metro", "bus"])
        + rules(SystemCategoryKey.fuel, ["заправ", "бензин", "топлив", "дизел", "метан", "пропан", "агзс", "benzin", "yoqilg", "zapravka", "petrol", "fuel"],
                exact: ["азс"])
        + rules(SystemCategoryKey.car, ["автомойк", "мойк", "машин", "автомобил", "шиномонтаж", "автосервис", "запчаст", "парковк", "стоянк", "техосмотр", "moyka", "parking", "carwash"])
        + rules(SystemCategoryKey.housing, ["аренд", "квартплат", "ijara", "rent"])
        + rules(SystemCategoryKey.utilities, ["коммунал", "электричеств", "отоплен", "kommunal", "utilit", "electricity"])
        + rules(SystemCategoryKey.mobile, ["связь", "интернет", "мобильн", "сотов", "aloqa", "internet", "mobile"])
        + rules(SystemCategoryKey.subscriptions, ["подписк", "obuna", "subscription"])
        + rules(SystemCategoryKey.health, ["аптек", "лекарств", "таблетк", "врач", "клиник", "больниц", "анализ", "стоматолог", "медицин", "dorixona",
                                           "shifokor", "klinika", "pharmacy", "medicine", "doctor"], exact: ["зуб", "зубы", "dori"])
        + rules(SystemCategoryKey.beauty, ["парикмахер", "стрижк", "подстриг", "барбер", "маникюр", "педикюр", "косметик", "sartarosh", "haircut", "barber"])
        + rules(SystemCategoryKey.clothes, ["одежд", "обув", "кроссовк", "куртк", "футболк", "джинс", "плать", "рубашк", "брюк", "носк", "кофт",
                                           "kiyim", "poyabzal", "clothes", "shoes", "sneakers"])
        + rules(SystemCategoryKey.shopping, ["маркетплейс", "посылк"])
        + rules(SystemCategoryKey.electronics, ["смартфон", "айфон", "ноутбук", "наушник", "планшет", "зарядк", "гаджет", "iphone", "laptop", "headphones"])
        + rules(SystemCategoryKey.home, ["мебел", "посуд", "хозтовар", "ремонт", "mebel", "furniture"])
        + rules(SystemCategoryKey.entertainment, ["кино", "театр", "концерт", "боулинг", "развлеч", "аттракцион", "konsert", "cinema", "movie", "concert"])
        + rules(SystemCategoryKey.sport, ["спортзал", "фитнес", "тренаж", "бассейн", "абонемент", "тренировк", "fitnes", "fitness"], exact: ["зал", "gym", "sport"])
        + rules(SystemCategoryKey.education, ["курс", "учеб", "обучен", "книг", "школ", "репетитор", "универ", "контракт", "o'qish", "kitob", "kontrakt",
                                              "course", "tuition"], exact: ["kurs"])
        + rules(SystemCategoryKey.travel, ["авиабилет", "самолет", "перелет", "отель", "гостиниц", "хостел", "путешеств", "sayohat", "mehmonxona",
                                           "flight", "hotel", "travel"])
        + rules(SystemCategoryKey.gifts, ["подар", "цвет", "букет", "sovg'a", "gift", "flowers"], exact: ["gul"])
        + rules(SystemCategoryKey.family, ["детск", "садик", "ребенк", "детям", "игрушк", "bolalar", "kids"])
        + rules(SystemCategoryKey.pets, ["корм", "ветеринар", "питом", "кошк", "собак", "veterinar", "pet"], exact: ["кот", "коту"])
        + rules(SystemCategoryKey.loans, ["кредит", "рассрочк", "ипотек", "займ", "kredit", "nasiya", "qarz", "loan", "installment"], exact: ["долг"])
        + rules(SystemCategoryKey.taxes, ["налог", "штраф", "пошлин", "soliq", "jarima", "tax"], exact: ["fine"])
        + rules(SystemCategoryKey.charity, ["садак", "благотвор", "пожертв", "sadaqa", "xayriya", "charity", "donation"])

    static let income: [Rule] =
        rules(SystemCategoryKey.salary, ["зарплат", "заработн", "аванс", "оклад", "получк", "преми", "maosh", "oylik", "avans", "salary", "paycheck", "wage"], exact: ["зп"])
        + rules(SystemCategoryKey.freelance, ["фриланс", "заказчик", "гонорар", "клиент", "upwork", "fiverr", "frilans", "freelance", "client"])
        + rules(SystemCategoryKey.business, ["выручк", "бизнес", "biznes", "savdo", "revenue", "business"])
        + rules(SystemCategoryKey.cashback, ["кэшбэк", "кешбек", "кэшбек", "кешбэк", "cashback", "keshbek"])
        + rules(SystemCategoryKey.interest, ["процент", "депозит", "вклад", "foiz", "interest", "deposit"])
        + rules(SystemCategoryKey.giftsIncome, ["подарил", "подарок", "подарк", "sovg'a", "gift"])
        + rules(SystemCategoryKey.sale, ["продал", "продажа", "продаж", "sotdim", "sold"])

    /// Фразы «за свет/газ/воду/квартиру/телефон/интернет»: оплата услуг, а не покупка.
    static let paymentForPhrases: [String: String] = [
        "свет": SystemCategoryKey.utilities, "газ": SystemCategoryKey.utilities, "воду": SystemCategoryKey.utilities,
        "коммуналку": SystemCategoryKey.utilities, "отопление": SystemCategoryKey.utilities, "мусор": SystemCategoryKey.utilities,
        "квартиру": SystemCategoryKey.housing, "аренду": SystemCategoryKey.housing,
        "телефон": SystemCategoryKey.mobile, "интернет": SystemCategoryKey.mobile, "связь": SystemCategoryKey.mobile,
        "садик": SystemCategoryKey.family, "учебу": SystemCategoryKey.education, "контракт": SystemCategoryKey.education,
        "svet": SystemCategoryKey.utilities, "gaz": SystemCategoryKey.utilities
    ]

    static let purchaseVerbs: Set<String> = ["купил", "купила", "купили", "взял", "взяла", "заказал", "заказала", "oldim", "bought"]

    /// Оценивает категорию по словам. Возвращает ключ и число совпадений.
    static func bestKey(words: [String], kind: CategoryKind) -> (key: String, hits: Int)? {
        // 1. «за свет», «за телефон» — однозначные платежи за услуги.
        if kind == .expense {
            for (index, word) in words.enumerated() where word == "за" && index + 1 < words.count {
                if let key = paymentForPhrases[words[index + 1]] { return (key, 3) }
            }
            // «купил телефон» — техника, а не связь.
            if words.contains(where: { purchaseVerbs.contains($0) }) && words.contains(where: { $0.hasPrefix("телефон") }) {
                return (SystemCategoryKey.electronics, 2)
            }
            if words.contains(where: { $0.hasPrefix("заправ") }) && words.contains(where: { $0.hasPrefix("газ") }) {
                return (SystemCategoryKey.fuel, 3)
            }
            // «пополнил телефон», «закинул на номер» — оплата связи.
            let topUp = words.contains { $0.hasPrefix("пополн") || $0.hasPrefix("закинул") || $0.hasPrefix("to'ldir") }
            if topUp && words.contains(where: { $0.hasPrefix("телефон") || $0.hasPrefix("номер") || $0.hasPrefix("баланс") || $0.hasPrefix("telefon") }) {
                return (SystemCategoryKey.mobile, 3)
            }
        }
        let table = kind == .expense ? expense : income
        var scores: [String: (hits: Int, first: Int)] = [:]
        for (index, word) in words.enumerated() {
            for rule in table {
                let matched = rule.exact ? word == rule.stem : word.hasPrefix(rule.stem)
                if matched {
                    let current = scores[rule.key] ?? (0, index)
                    scores[rule.key] = (current.hits + 1, min(current.first, index))
                    break
                }
            }
        }
        guard let best = scores.max(by: { lhs, rhs in
            lhs.value.hits != rhs.value.hits ? lhs.value.hits < rhs.value.hits : lhs.value.first > rhs.value.first
        }) else { return nil }
        return (best.key, best.value.hits)
    }
}
