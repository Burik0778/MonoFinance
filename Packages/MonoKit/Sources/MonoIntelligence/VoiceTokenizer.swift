import Foundation
import MonoCore

/// Токен распознанной фразы.
struct VoiceToken: Equatable {
    enum Kind: Equatable {
        case word
        case number
        case symbol
        case punct
    }

    var kind: Kind
    /// Нормализованный текст (нижний регистр, «ё»→«е», апострофы).
    var text: String
    /// Исходное написание (для имён продавцов).
    var original: String
    /// Значение числа.
    var value: Decimal?
    /// Количество цифр целой части.
    var integerDigits: Int = 0
    var hasFraction: Bool = false
    /// Перед токеном был пробел.
    var spaceBefore: Bool
    /// Токен уже занят датой, временем, количеством или номером карты.
    var consumed: Bool = false

    var isCapitalized: Bool {
        guard let first = original.first else { return false }
        return first.isUppercase
    }
}

enum VoiceTokenizer {
    private static let spaces: Set<Character> = ["\u{00A0}", "\u{202F}", "\u{2009}", "\u{2007}"]
    private static let apostrophes: Set<Character> = ["'", "‘", "’", "ʻ", "ʼ", "`", "´"]
    private static let symbols: Set<Character> = ["$", "€", "₽", "£", "₸", "%", "+"]
    private static let punctuation: Set<Character> = [",", ".", ";", "!", "?", ":", "—", "–"]

    static func tokenize(_ text: String) -> [VoiceToken] {
        var tokens: [VoiceToken] = []
        let chars = Array(text)
        var buffer = ""
        var bufferIsNumber = false
        var bufferSpaceBefore = false
        var pendingSpace = false

        func flush() {
            guard !buffer.isEmpty else { return }
            if bufferIsNumber {
                let parsed = parseNumber(buffer)
                tokens.append(VoiceToken(kind: .number, text: buffer, original: buffer, value: parsed?.value,
                                         integerDigits: parsed?.integerDigits ?? buffer.count, hasFraction: parsed?.hasFraction ?? false,
                                         spaceBefore: bufferSpaceBefore))
            } else {
                tokens.append(VoiceToken(kind: .word, text: TextNormalizer.fold(buffer), original: buffer, spaceBefore: bufferSpaceBefore))
            }
            buffer = ""
        }

        func start(number: Bool) {
            bufferIsNumber = number
            bufferSpaceBefore = pendingSpace || tokens.isEmpty
            pendingSpace = false
        }

        var index = 0
        while index < chars.count {
            let char = chars[index]
            let next: Character? = index + 1 < chars.count ? chars[index + 1] : nil
            if char.isWhitespace || spaces.contains(char) {
                flush()
                pendingSpace = true
            } else if char.isLetter {
                if !buffer.isEmpty && bufferIsNumber { flush() }
                if buffer.isEmpty { start(number: false) }
                buffer.append(char)
            } else if char.isASCII && char.isNumber {
                if !buffer.isEmpty && !bufferIsNumber { flush() }
                if buffer.isEmpty { start(number: true) }
                buffer.append(char)
            } else if (char == "." || char == ",") && bufferIsNumber && !buffer.isEmpty, let next, next.isASCII, next.isNumber {
                buffer.append(char)
            } else if apostrophes.contains(char) && !bufferIsNumber && !buffer.isEmpty, let next, next.isLetter {
                buffer.append("'")
            } else if char == "-" && !bufferIsNumber && !buffer.isEmpty, let next, next.isLetter {
                buffer.append("-")
            } else if symbols.contains(char) {
                flush()
                tokens.append(VoiceToken(kind: .symbol, text: String(char), original: String(char), spaceBefore: pendingSpace))
                pendingSpace = false
            } else if punctuation.contains(char) {
                flush()
                tokens.append(VoiceToken(kind: .punct, text: String(char), original: String(char), spaceBefore: pendingSpace))
                pendingSpace = false
            } else {
                flush()
                pendingSpace = true
            }
            index += 1
        }
        flush()
        return mergeDigitGroups(tokens)
    }

    /// «245,000» и «12.500» — разделители разрядов; «1,5» и «2.75» — дробные.
    static func parseNumber(_ raw: String) -> (value: Decimal, integerDigits: Int, hasFraction: Bool)? {
        let separators = raw.filter { $0 == "." || $0 == "," }
        var normalized = raw
        var hasFraction = false
        if separators.isEmpty {
            normalized = raw
        } else if Set(separators).count == 2 {
            // Оба вида: последний — дробный.
            let lastSeparator = raw.lastIndex { $0 == "." || $0 == "," }!
            let integerPart = raw[..<lastSeparator].filter(\.isNumber)
            let fraction = raw[raw.index(after: lastSeparator)...]
            normalized = integerPart + "." + fraction
            hasFraction = true
        } else if separators.count > 1 {
            normalized = raw.filter(\.isNumber)
        } else {
            let parts = raw.split(whereSeparator: { $0 == "." || $0 == "," })
            if parts.count == 2, parts[1].count == 3, (1...3).contains(parts[0].count) {
                normalized = String(parts[0] + parts[1])
            } else if parts.count == 2 {
                normalized = parts[0] + "." + parts[1]
                hasFraction = true
            } else {
                normalized = raw.filter(\.isNumber)
            }
        }
        guard let value = DecimalMath.parse(normalized) else { return nil }
        let integerDigits = normalized.split(separator: ".").first.map(\.count) ?? normalized.count
        return (value, integerDigits, hasFraction)
    }

    /// «1 200 000» → одно число: группы по три цифры через пробел.
    static func mergeDigitGroups(_ tokens: [VoiceToken]) -> [VoiceToken] {
        var result: [VoiceToken] = []
        for token in tokens {
            if token.kind == .number, token.spaceBefore, token.text.count == 3, token.text.allSatisfy(\.isNumber),
               var last = result.last, last.kind == .number, !last.hasFraction,
               let lastValue = last.value, let value = token.value,
               // Первая группа — 1–3 цифры; дальше склеиваются только группы по три.
               last.integerDigits <= 3 || last.text.contains(" ") {
                last.value = lastValue * 1000 + value
                last.integerDigits += 3
                last.text += " " + token.text
                last.original += " " + token.original
                result[result.count - 1] = last
                continue
            }
            result.append(token)
        }
        return result
    }
}
