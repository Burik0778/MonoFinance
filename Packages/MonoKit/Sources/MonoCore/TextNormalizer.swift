import Foundation

/// Нормализация текста для сопоставления: регистр, ё→е, узбекские апострофы, пробелы.
public enum TextNormalizer {
    private static let apostrophes: Set<Character> = ["‘", "’", "ʻ", "ʼ", "`", "´", "'", "ʹ"]
    private static let spaces: Set<Character> = ["\u{00A0}", "\u{202F}", "\u{2009}", "\u{2007}", "\t", "\n", "\r"]

    /// Нижний регистр, «ё» → «е», все апострофы → «'», все виды пробелов → обычный, схлопывание пробелов.
    public static func fold(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var lastWasSpace = true
        for char in text.lowercased() {
            var c = char
            if c == "ё" { c = "е" }
            if apostrophes.contains(c) { c = "'" }
            if spaces.contains(c) { c = " " }
            if c == " " {
                if lastWasSpace { continue }
                lastWasSpace = true
            } else {
                lastWasSpace = false
            }
            result.append(c)
        }
        if result.hasSuffix(" ") { result.removeLast() }
        return result
    }

    /// Слова из букв/цифр (апостроф внутри узбекских слов сохраняется: «so'm», «to'rt»).
    public static func words(_ text: String) -> [String] {
        let folded = fold(text)
        var words: [String] = []
        var current = ""
        for char in folded {
            if char.isLetter || char.isNumber || (char == "'" && !current.isEmpty) {
                current.append(char)
            } else {
                if !current.isEmpty { words.append(current.trimmingTrailingApostrophes()); current = "" }
            }
        }
        if !current.isEmpty { words.append(current.trimmingTrailingApostrophes()) }
        return words.filter { !$0.isEmpty }
    }

    private static let cyrillicToLatin: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ж": "zh", "з": "z", "и": "i",
        "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s",
        "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "",
        "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
        // узбекская кириллица
        "ў": "o'", "қ": "q", "ғ": "g'", "ҳ": "h"
    ]

    /// Транслитерация кириллицы в латиницу (для сопоставления «Корзинка» ↔ «KORZINKA»).
    public static func transliterate(_ text: String) -> String {
        var result = ""
        for char in fold(text) {
            if let mapped = cyrillicToLatin[char] {
                result += mapped
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Ключ для сравнения: транслитерация + только буквы и цифры.
    public static func matchKey(_ text: String) -> String {
        String(transliterate(text).filter { $0.isLetter || $0.isNumber })
    }
}

extension String {
    fileprivate func trimmingTrailingApostrophes() -> String {
        var copy = self
        while copy.hasSuffix("'") { copy.removeLast() }
        return copy
    }
}
