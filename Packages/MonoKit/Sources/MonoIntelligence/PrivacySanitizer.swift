import Foundation
import MonoCore

/// Вычищает персональные данные из текста, который может уйти во внешнюю нейросеть.
///
/// Через него проходят вопрос пользователя, названия продавцов и категорий. Убираются номера карт (полные и маскированные,
/// последние 4 цифры), номера счетов (8 и больше цифр подряд), RRN/TID/MID и номера документов, телефоны, e-mail,
/// паспортные данные и имена людей. Переводы людям сворачиваются в «перевод человеку».
/// Заметки и теги операций наружу не уходят вовсе (`stripped(_:)`).
public enum PrivacySanitizer {
    public static let personTransfer = "перевод человеку"
    public static let cardMark = "[карта]"
    public static let numberMark = "[номер]"
    public static let phoneMark = "[телефон]"
    public static let emailMark = "[e-mail]"
    public static let passportMark = "[паспорт]"
    public static let nameMark = "[имя]"

    /// Текст без персональных данных. Суммы до 7 цифр и обычные слова остаются как есть.
    public static func clean(_ text: String) -> String {
        var result = text
        for rule in rules {
            result = rule.apply(to: result)
        }
        return collapseSpaces(result)
    }

    /// Название продавца для сводки: перевод человеку или имя человека → «перевод человеку», остальное — `clean`.
    public static func merchant(_ name: String) -> String {
        if isPersonTransfer(name) { return personTransfer }
        let cleaned = clean(name)
        if cleaned.contains(nameMark) { return personTransfer }
        return cleaned
    }

    /// Похоже ли описание операции на перевод человеку (по ключевым словам или по имени в тексте).
    public static func isPersonTransfer(_ text: String) -> Bool {
        let folded = TextNormalizer.fold(text)
        if transferWords.contains(where: { folded.contains($0) }) { return true }
        return containsPersonName(text)
    }

    /// Есть ли в тексте имя человека (ФИО, инициалы, отчество).
    public static func containsPersonName(_ text: String) -> Bool {
        nameRules.contains { $0.matches(text) }
    }

    /// Копия операции без заметки, тегов, чека и отпечатка импорта; продавец — через `merchant(_:)`.
    public static func stripped(_ transaction: FinanceTransaction) -> FinanceTransaction {
        var copy = transaction
        copy.note = nil
        copy.tags = []
        copy.receiptFileName = nil
        copy.importFingerprint = nil
        copy.merchant = transaction.merchant.map(merchant)
        return copy
    }

    // MARK: - Правила

    struct Rule: Sendable {
        let regex: NSRegularExpression
        let template: String

        init(_ pattern: String, _ template: String, caseInsensitive: Bool = true) {
            var options: NSRegularExpression.Options = []
            if caseInsensitive { options.insert(.caseInsensitive) }
            regex = try! NSRegularExpression(pattern: pattern, options: options)
            self.template = template
        }

        func apply(to text: String) -> String {
            regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
        }

        func matches(_ text: String) -> Bool {
            regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }

    /// Слова, по которым операция считается переводом (текст уже приведён `TextNormalizer.fold`).
    static let transferWords = [
        "перевод", "перевел", "перечислен", "p2p", "card to card", "card2card", "c2c", "o'tkazma", "otkazma", "o'tkazish",
        "transfer", "на карту", "с карты на карту", "ўтказма"
    ]

    /// Буквы имени: латиница, кириллица, узбекские апострофы.
    private static let upper = "[A-ZА-ЯЁЎҚҒҲ]"
    private static let lower = "[a-zа-яёўқғҳ'‘’ʻ]"

    /// Имена людей. Регистр важен: имя пишется с заглавной буквы.
    static let nameRules: [Rule] = [
        // Слова после «перевод», «получатель», «кому»: «Перевод Алишеру Каримову», «Получатель: ALIYEV A.»
        Rule("((?i:перевод|перевёл|перевел|перевела|переведи|перечислил|перечислила|получатель|получателю|отправитель|кому|p2p|o['‘’ʻ]?tkazma|transfer to)[\\s\\-:]{1,3}(?i:на\\s+карту\\s+|to\\s+)?)"
             + "\(upper)[\\p{L}'‘’ʻ]+(?:\\s+\(upper)[\\p{L}'‘’ʻ]*\\.?){0,2}", "$1\(nameMark)", caseInsensitive: false),
        // Отчество (с одним-двумя словами перед ним): «Иванов Иван Иванович», «ALIYEV ALISHER ANVAROVICH».
        Rule("(?:\(upper)[\\p{L}'‘’ʻ]+\\s+){0,2}\(upper)[\\p{L}]*(?:ович|евич|ична|овна|евна|ОВИЧ|ЕВИЧ|ИЧНА|ОВНА|ЕВНА|ovich|evich|ovna|evna|OVICH|EVICH|OVNA|EVNA)(?![\\p{L}])",
             nameMark, caseInsensitive: false),
        // Узбекские «o‘g‘li», «qizi»: «Karimov Alisher o‘g‘li».
        Rule("(?:\(upper)[\\p{L}'‘’ʻ]+\\s+){1,2}(?:o['‘’ʻ`]?g['‘’ʻ`]?li|ugli|qizi|kizi|ўғли|қизи)(?![\\p{L}])", nameMark),
        // Фамилия с инициалами: «Иванов И.И.», «ALIYEV A. A.»
        Rule("\(upper)[\\p{L}'‘’ʻ]+\\s+\(upper)\\.\\s?(?:\(upper)\\.)?", nameMark, caseInsensitive: false),
        // Инициалы перед фамилией: «И. И. Иванов», «A.Aliyev»
        Rule("(?<![\\p{L}])\(upper)\\.\\s?(?:\(upper)\\.\\s?)?\(upper)\(lower){2,}", nameMark, caseInsensitive: false),
        // Фамилия + имя или имя + фамилия: «Петров Иван», «Алишер Каримов», «KARIMOV ALISHER».
        Rule("\(upper)\(lower)+(?:ов|ев|ёв|ова|ева|ёва|ский|ская|ov|ev|ova|eva|yev|yeva)\\s+\(upper)\(lower){2,}", nameMark, caseInsensitive: false),
        Rule("\(upper)\(lower){2,}\\s+\(upper)\(lower)+(?:ов|ев|ёв|ова|ева|ёва|ский|ская|ov|ev|ova|eva|yev|yeva)(?![\\p{L}])", nameMark, caseInsensitive: false),
        Rule("[A-ZА-ЯЁ]{2,}(?:OV|EV|OVA|EVA|YEV|YEVA|ОВ|ЕВ|ОВА|ЕВА)\\s+[A-ZА-ЯЁ]{3,}", nameMark, caseInsensitive: false),
        Rule("(?<![\\p{L}])[A-ZА-ЯЁ]{3,}\\s+[A-ZА-ЯЁ]{2,}(?:OV|EV|OVA|EVA|YEV|YEVA|ОВ|ЕВ|ОВА|ЕВА)(?![\\p{L}])", nameMark, caseInsensitive: false)
    ]

    static let rules: [Rule] = [
        // E-mail.
        Rule("[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}", emailMark),
        // Маскированный номер карты: «414084******7058», «4140 84** **** 7058», «8600-12XX-XXXX-3456».
        Rule("(?<![\\p{L}\\d])\\d{4,6}[ \\-]?[\\d*•·xX#]{0,4}[*•·xX#]{2,}[ \\-*•·xX#\\d]*?\\d{2,4}(?!\\d)", cardMark),
        // Полный номер карты с пробелами или дефисами: «8600 1234 5678 9012».
        Rule("(?<!\\d)\\d{4}[ \\-]\\d{4,6}[ \\-]\\d{4,5}(?:[ \\-]\\d{1,4})?(?!\\d)", cardMark),
        // Хвост карты после маски: «•• 1234», «*7058», «**** 7058».
        Rule("(?<![\\p{L}\\d])(?:[*•·#]|[xX](?=[xX*•·#\\s\\d]))(?:[*•·#xX]|\\s(?=[*•·#xX\\d]))*\\d{4}(?!\\d)", cardMark),
        // Последние 4 цифры по смыслу: «карта 1234», «Visa 7058», «оканчивается на 1234», «последние 4 цифры 1234».
        Rule("(карт[а-яё]*|card|karta|kartasi|сч[её]т[а-яё]*|visa|mastercard|master|uzcard|humo|unionpay|оканчива[а-яё]*(?:\\s+на)?|ending(?:\\s+in)?|последние\\s+(?:4|четыре)\\s+цифры)(\\s*[#№:]?\\s*)\\d{4}(?!\\d)",
             "$1$2\(numberMark)"),
        // RRN, TID, MID, номера документов, чеков и операций: «RRN: 123456789012», «№ 4512», «док. 77/12».
        Rule("(?<![\\p{L}\\d])(rrn|tid|mid|trn|arn|stan|auth(?:\\s*code)?|код\\s+авторизации|ref(?:erence)?|номер\\s+документа|№\\s*документа|номер\\s+операции|номер\\s+чека|документ|док\\.?|чек|квитанци[яи]|terminal|терминал|merchant\\s*id|№|n[o°]\\.?|#)\\s*[#№:]?\\s*(?=[\\p{L}\\-/]*\\d)[\\p{L}\\d][\\p{L}\\d\\-/]{2,}",
             numberMark),
        // Паспорт: «AA 1234567», «паспорт 4510 123456».
        Rule("паспорт[а-яё]*\\s*(?:серии\\s*)?[№:]?\\s*(?:[A-ZА-Я]{2}\\s?)?\\d[\\d ]{5,10}\\d", "паспорт \(passportMark)"),
        Rule("passport\\s*[№#:]?\\s*(?:[A-Z]{2}\\s?)?\\d{6,9}", "passport \(passportMark)"),
        Rule("(?<![\\p{L}\\d])[A-ZА-Я]{2}\\s?\\d{7}(?!\\d)", passportMark, caseInsensitive: false),
        // Телефоны: «+998 90 123-45-67», «+7 (912) 345-67-89», «90 123 45 67».
        Rule("(?<![\\d+])\\+?998[\\s\\-()]*\\d{2}[\\s\\-()]*\\d{3}[\\s\\-]*\\d{2}[\\s\\-]*\\d{2}(?!\\d)", phoneMark),
        Rule("(?<![\\d])\\+\\d{1,3}[\\s\\-(]*\\d{2,4}[\\s\\-)]*\\d{2,4}[\\s\\-]*\\d{2,4}(?:[\\s\\-]*\\d{2,4})?(?!\\d)", phoneMark),
        Rule("(?<![\\d\\p{L}])\\(?\\d{2}\\)?[\\s\\-]\\d{3}[\\s\\-]\\d{2}[\\s\\-]\\d{2}(?!\\d)", phoneMark),
        // Номера счетов, ПИНФЛ, ИНН и любые 8+ цифр подряд.
        Rule("\\d{8,}", numberMark)
    ] + nameRules

    private static func collapseSpaces(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
