import Foundation
import MonoCore

/// Числительные русского, узбекского (латиница) и английского языков.
enum NumberWord: Equatable {
    /// Слагаемое: «двадцать», «пятьсот», «sakson».
    case value(Decimal)
    /// «yuz», «hundred»: умножает накопленное на 100.
    case hundred
    /// «тысяча», «миллион», «ming», «million».
    case multiplier(Decimal)
    /// «пол», «половина», «yarim», «half».
    case half
    /// «полтора», «полторы».
    case oneAndHalf
    /// Слитные формы: «полмиллиона», «полтысячи».
    case composite(Decimal)

    static let thousand: Decimal = 1_000
    static let million: Decimal = 1_000_000
    static let billion: Decimal = 1_000_000_000

    private static let table: [String: NumberWord] = {
        var map: [String: NumberWord] = [:]
        func add(_ words: [String], _ value: NumberWord) { for word in words { map[word] = value } }
        // Русский
        add(["ноль"], .value(0))
        add(["один", "одна", "одно", "одну", "одного", "одной"], .value(1))
        add(["два", "две", "двух"], .value(2))
        add(["три", "трех"], .value(3))
        add(["четыре", "четырех"], .value(4))
        add(["пять", "пяти"], .value(5))
        add(["шесть", "шести"], .value(6))
        add(["семь", "семи"], .value(7))
        add(["восемь", "восьми"], .value(8))
        add(["девять", "девяти"], .value(9))
        add(["десять", "десяти"], .value(10))
        add(["одиннадцать"], .value(11))
        add(["двенадцать"], .value(12))
        add(["тринадцать"], .value(13))
        add(["четырнадцать"], .value(14))
        add(["пятнадцать"], .value(15))
        add(["шестнадцать"], .value(16))
        add(["семнадцать"], .value(17))
        add(["восемнадцать"], .value(18))
        add(["девятнадцать"], .value(19))
        add(["двадцать", "двадцати"], .value(20))
        add(["тридцать", "тридцати"], .value(30))
        add(["сорок", "сорока"], .value(40))
        add(["пятьдесят", "пятидесяти"], .value(50))
        add(["шестьдесят"], .value(60))
        add(["семьдесят"], .value(70))
        add(["восемьдесят"], .value(80))
        add(["девяносто"], .value(90))
        add(["сто", "ста"], .value(100))
        add(["двести", "двухсот"], .value(200))
        add(["триста", "трехсот"], .value(300))
        add(["четыреста", "четырехсот"], .value(400))
        add(["пятьсот", "пятисот"], .value(500))
        add(["шестьсот"], .value(600))
        add(["семьсот"], .value(700))
        add(["восемьсот"], .value(800))
        add(["девятьсот"], .value(900))
        add(["тысяча", "тысячи", "тысяч", "тысячу", "тысячей", "тыс", "тыща", "тыщи", "тыщу", "тыщ"], .multiplier(thousand))
        add(["миллион", "миллиона", "миллионов", "млн", "мил", "лям", "ляма", "лямов", "лимон", "лимона", "лимонов"], .multiplier(million))
        add(["миллиард", "миллиарда", "миллиардов", "млрд"], .multiplier(billion))
        add(["пол", "половина", "половину"], .half)
        add(["полтора", "полторы"], .oneAndHalf)
        add(["полмиллиона", "полляма", "пол-миллиона"], .composite(500_000))
        add(["полтысячи", "пол-тысячи"], .composite(500))
        // Узбекский
        add(["nol"], .value(0))
        add(["bir"], .value(1))
        add(["ikki"], .value(2))
        add(["uch"], .value(3))
        add(["to'rt", "tort"], .value(4))
        add(["besh"], .value(5))
        add(["olti"], .value(6))
        add(["yetti"], .value(7))
        add(["sakkiz"], .value(8))
        add(["to'qqiz", "toqqiz"], .value(9))
        add(["o'n"], .value(10))
        add(["yigirma"], .value(20))
        add(["o'ttiz", "ottiz"], .value(30))
        add(["qirq"], .value(40))
        add(["ellik"], .value(50))
        add(["oltmish"], .value(60))
        add(["yetmish"], .value(70))
        add(["sakson"], .value(80))
        add(["to'qson", "toqson"], .value(90))
        add(["yuz"], .hundred)
        add(["ming"], .multiplier(thousand))
        add(["million", "mln"], .multiplier(million))
        add(["milliard", "mlrd"], .multiplier(billion))
        add(["yarim"], .half)
        // Английский
        add(["zero"], .value(0))
        add(["one"], .value(1))
        add(["two"], .value(2))
        add(["three"], .value(3))
        add(["four"], .value(4))
        add(["five"], .value(5))
        add(["six"], .value(6))
        add(["seven"], .value(7))
        add(["eight"], .value(8))
        add(["nine"], .value(9))
        add(["ten"], .value(10))
        add(["eleven"], .value(11))
        add(["twelve"], .value(12))
        add(["thirteen"], .value(13))
        add(["fourteen"], .value(14))
        add(["fifteen"], .value(15))
        add(["sixteen"], .value(16))
        add(["seventeen"], .value(17))
        add(["eighteen"], .value(18))
        add(["nineteen"], .value(19))
        add(["twenty"], .value(20))
        add(["thirty"], .value(30))
        add(["forty"], .value(40))
        add(["fifty"], .value(50))
        add(["sixty"], .value(60))
        add(["seventy"], .value(70))
        add(["eighty"], .value(80))
        add(["ninety"], .value(90))
        add(["hundred"], .hundred)
        add(["thousand", "thousands"], .multiplier(thousand))
        add(["billion", "bn"], .multiplier(billion))
        add(["half"], .half)
        return map
    }()

    static func lookup(_ word: String) -> NumberWord? { table[word] }

    /// Суффиксы-множители сразу после цифр: «85к», «85 k», «2 млн».
    static func digitSuffixMultiplier(_ word: String) -> Decimal? {
        switch word {
        case "к", "k", "т", "тыс", "тысяч", "тысячи", "тысяча", "ming": return thousand
        case "млн", "м", "mln", "m": return million
        case "млрд", "mlrd", "b", "bn": return billion
        default: return nil
        }
    }
}

/// Элемент числовой фразы.
enum NumberPart: Equatable {
    case digits(Decimal)
    case word(NumberWord)
}

/// Собирает значение числовой фразы с учётом разговорных сокращений:
/// «миллион двести» = 1 200 000, «полтора миллиона» = 1 500 000, «sakson besh ming» = 85 000.
enum NumberComposer {
    struct Result: Equatable {
        let value: Decimal
        let hasMultiplier: Bool
    }

    static func compose(_ parts: [NumberPart]) -> Result? {
        guard !parts.isEmpty else { return nil }
        var total: Decimal = 0
        var current: Decimal = 0
        var hasMultiplier = false
        var lastMultiplier: Decimal?
        var currentStartedAfterMultiplier = false

        for part in parts {
            switch part {
            case .digits(let value):
                if lastMultiplier != nil && current == 0 { currentStartedAfterMultiplier = true }
                current += value
            case .word(let word):
                switch word {
                case .value(let value):
                    if lastMultiplier != nil && current == 0 { currentStartedAfterMultiplier = true }
                    current += value
                case .hundred:
                    current = (current == 0 ? 1 : current) * 100
                case .half:
                    current += Decimal(string: "0.5")!
                case .oneAndHalf:
                    current += Decimal(string: "1.5")!
                case .composite(let value):
                    total += value
                    hasMultiplier = true
                case .multiplier(let multiplier):
                    total += (current == 0 ? 1 : current) * multiplier
                    current = 0
                    hasMultiplier = true
                    lastMultiplier = multiplier
                    currentStartedAfterMultiplier = false
                }
            }
        }
        // «миллион двести» → двести относится к тысячам.
        if current > 0, current < 1000, currentStartedAfterMultiplier, let last = lastMultiplier, last >= NumberWord.million {
            current *= last / NumberWord.thousand
        }
        let value = total + current
        return Result(value: value, hasMultiplier: hasMultiplier)
    }
}
