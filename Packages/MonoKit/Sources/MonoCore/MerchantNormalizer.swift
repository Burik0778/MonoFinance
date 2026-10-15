import Foundation

/// Нормализация названий продавцов из выписок и речи: «KORZINKA CHILANZAR 12 TASHKENT UZ» → ключ «korzinka chilanzar».
public enum MerchantNormalizer {
    /// Слова-шум: города, страны, правовые формы, технические пометки терминалов.
    private static let noise: Set<String> = [
        "tashkent", "toshkent", "ташкент", "uz", "uzb", "uzbekistan", "ozbekiston", "узбекистан", "tash",
        "ooo", "mchj", "llc", "ltd", "chp", "ip", "xk", "ao", "aj", "ооо", "мчж", "чп", "ип", "ао",
        "pos", "atm", "terminal", "payment", "oplata", "оплата", "pokupka", "покупка", "purchase",
        "card", "karta", "карта", "uzcard", "humo", "visa", "mastercard", "p2p", "the", "shop", "store", "magazin"
    ]

    /// Стабильный ключ: транслитерация, нижний регистр, без цифр и шума, не более трёх слов.
    public static func key(_ raw: String) -> String {
        let latin = TextNormalizer.transliterate(raw)
        var words: [String] = []
        var current = ""
        func flush() {
            if current.count >= 2, !noise.contains(current) { words.append(current) }
            current = ""
        }
        for char in latin {
            if char.isLetter {
                current.append(char)
            } else {
                flush()
            }
        }
        flush()
        return words.prefix(3).joined(separator: " ")
    }

    /// Имя для показа: исходный текст без лишних пробелов, первые буквы слов заглавные для «КРИКА В ВЕРХНЕМ РЕГИСТРЕ».
    public static func displayName(_ raw: String) -> String {
        let trimmed = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        guard !trimmed.isEmpty else { return trimmed }
        let letters = trimmed.filter(\.isLetter)
        let isShouting = !letters.isEmpty && letters == letters.uppercased() && letters.count > 3
        guard isShouting else { return trimmed }
        return trimmed.lowercased().split(separator: " ").map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}
