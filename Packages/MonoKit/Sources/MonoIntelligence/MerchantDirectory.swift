import Foundation
import MonoCore

/// Известные продавцы Узбекистана и международные сервисы: варианты написания → каноническое имя и категория по умолчанию.
/// Это эвристика: пользователь может исправить категорию, и выученное правило получит приоритет.
public enum MerchantDirectory {
    public struct Entry: Sendable, Equatable {
        public let name: String
        /// Варианты после `TextNormalizer.fold`. Однословные варианты сравниваются как префикс слова (падежи),
        /// многословные — как последовательность префиксов.
        public let aliases: [String]
        public let categoryKey: String
    }

    public struct Match: Sendable, Equatable {
        public let entry: Entry
        /// Индексы слов, занятых совпадением.
        public let wordRange: Range<Int>
    }

    public static let entries: [Entry] = [
        Entry(name: "Korzinka", aliases: ["корзинк", "korzinka"], categoryKey: SystemCategoryKey.groceries),
        Entry(name: "Makro", aliases: ["макро", "makro"], categoryKey: SystemCategoryKey.groceries),
        Entry(name: "Havas", aliases: ["хавас", "havas"], categoryKey: SystemCategoryKey.groceries),
        Entry(name: "Carrefour", aliases: ["карфур", "карефур", "carrefour"], categoryKey: SystemCategoryKey.groceries),
        Entry(name: "Baraka Market", aliases: ["барака маркет", "baraka market", "baraka"], categoryKey: SystemCategoryKey.groceries),
        Entry(name: "Yandex Go", aliases: ["яндекс го", "яндекс такси", "yandex go", "yandex taxi", "yandexgo"], categoryKey: SystemCategoryKey.taxi),
        Entry(name: "MyTaxi", aliases: ["майтакси", "май такси", "mytaxi", "my taxi"], categoryKey: SystemCategoryKey.taxi),
        Entry(name: "Uklon", aliases: ["уклон", "uklon"], categoryKey: SystemCategoryKey.taxi),
        Entry(name: "inDrive", aliases: ["индрайв", "indrive", "indriver"], categoryKey: SystemCategoryKey.taxi),
        Entry(name: "Yandex Eats", aliases: ["яндекс еда", "яндекс ит", "yandex eats", "yandex eda"], categoryKey: SystemCategoryKey.delivery),
        Entry(name: "Express24", aliases: ["экспресс 24", "express 24", "express24", "экспресс24"], categoryKey: SystemCategoryKey.delivery),
        Entry(name: "Uzum Tezkor", aliases: ["узум тезкор", "uzum tezkor"], categoryKey: SystemCategoryKey.delivery),
        Entry(name: "Wolt", aliases: ["волт", "wolt"], categoryKey: SystemCategoryKey.delivery),
        Entry(name: "Uzum Market", aliases: ["узум маркет", "uzum market"], categoryKey: SystemCategoryKey.shopping),
        Entry(name: "Wildberries", aliases: ["вайлдберриз", "вайлдбериз", "валдберис", "wildberries"], categoryKey: SystemCategoryKey.shopping),
        Entry(name: "Ozon", aliases: ["озон", "ozon"], categoryKey: SystemCategoryKey.shopping),
        Entry(name: "AliExpress", aliases: ["алиэкспресс", "aliexpress"], categoryKey: SystemCategoryKey.shopping),
        Entry(name: "EVOS", aliases: ["эвос", "evos"], categoryKey: SystemCategoryKey.cafe),
        Entry(name: "Max Way", aliases: ["макс вей", "максвей", "max way", "maxway"], categoryKey: SystemCategoryKey.cafe),
        Entry(name: "Les Ailes", aliases: ["лез эль", "лезаиль", "les ailes"], categoryKey: SystemCategoryKey.cafe),
        Entry(name: "KFC", aliases: ["кфс", "kfc"], categoryKey: SystemCategoryKey.cafe),
        Entry(name: "Safia", aliases: ["сафия", "safia"], categoryKey: SystemCategoryKey.cafe),
        Entry(name: "Beeline", aliases: ["билайн", "beeline"], categoryKey: SystemCategoryKey.mobile),
        Entry(name: "Ucell", aliases: ["юселл", "юсел", "ucell"], categoryKey: SystemCategoryKey.mobile),
        Entry(name: "Uzmobile", aliases: ["узмобайл", "uzmobile"], categoryKey: SystemCategoryKey.mobile),
        Entry(name: "Mobiuz", aliases: ["мобиуз", "mobiuz"], categoryKey: SystemCategoryKey.mobile),
        Entry(name: "Uztelecom", aliases: ["узтелеком", "uztelecom"], categoryKey: SystemCategoryKey.mobile),
        Entry(name: "UNG Petro", aliases: ["унг петро", "ung petro"], categoryKey: SystemCategoryKey.fuel),
        Entry(name: "Mediapark", aliases: ["медиапарк", "mediapark"], categoryKey: SystemCategoryKey.electronics),
        Entry(name: "Texnomart", aliases: ["техномарт", "texnomart"], categoryKey: SystemCategoryKey.electronics),
        Entry(name: "Netflix", aliases: ["нетфликс", "netflix"], categoryKey: SystemCategoryKey.subscriptions),
        Entry(name: "Spotify", aliases: ["спотифай", "spotify"], categoryKey: SystemCategoryKey.subscriptions),
        Entry(name: "Apple Services", aliases: ["айклауд", "icloud", "itunes", "apple music", "apple com bill"], categoryKey: SystemCategoryKey.subscriptions),
        Entry(name: "YouTube Premium", aliases: ["ютуб премиум", "youtube premium"], categoryKey: SystemCategoryKey.subscriptions)
    ]

    /// Слова алиасов, разбитые заранее.
    private static let aliasWords: [(entry: Entry, words: [String])] = entries.flatMap { entry in
        entry.aliases.map { (entry, $0.split(separator: " ").map(String.init)) }
    }

    /// Ищет первого известного продавца в последовательности слов (после `TextNormalizer.words`).
    public static func firstMatch(in words: [String]) -> Match? {
        var best: Match?
        for (entry, alias) in aliasWords where !alias.isEmpty {
            guard words.count >= alias.count else { continue }
            for start in 0...(words.count - alias.count) {
                var matched = true
                for (offset, part) in alias.enumerated() {
                    let word = words[start + offset]
                    let ok = part.count >= 4 ? word.hasPrefix(part) : word == part || (part.allSatisfy(\.isNumber) && word == part)
                    if !ok { matched = false; break }
                }
                if matched {
                    let candidate = Match(entry: entry, wordRange: start..<(start + alias.count))
                    if best == nil || start < best!.wordRange.lowerBound ||
                        (start == best!.wordRange.lowerBound && alias.count > best!.wordRange.count) {
                        best = candidate
                    }
                    break
                }
            }
        }
        return best
    }

    public static func firstMatch(in text: String) -> Match? {
        firstMatch(in: TextNormalizer.words(text))
    }
}
