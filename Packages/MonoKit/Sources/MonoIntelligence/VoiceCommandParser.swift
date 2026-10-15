import Foundation
import MonoCore

/// Данные, на которые опирается разбор фразы.
public struct VoiceParserContext: Sendable {
    public var accounts: [Account]
    public var categories: [FinanceCategory]
    public var merchantRules: [MerchantRule]
    public var defaultAccountID: UUID?
    public var baseCurrency: Currency
    public var converter: CurrencyConverter?
    public var now: Date
    public var periods: PeriodCalendar

    public init(
        accounts: [Account],
        categories: [FinanceCategory],
        merchantRules: [MerchantRule] = [],
        defaultAccountID: UUID? = nil,
        baseCurrency: Currency = .uzs,
        converter: CurrencyConverter? = nil,
        now: Date = Date(),
        periods: PeriodCalendar = PeriodCalendar()
    ) {
        self.accounts = accounts
        self.categories = categories
        self.merchantRules = merchantRules
        self.defaultAccountID = defaultAccountID
        self.baseCurrency = baseCurrency
        self.converter = converter
        self.now = now
        self.periods = periods
    }
}

/// Детерминированный разбор финансовых фраз: «Вчера купил продукты в Корзинке на 245 тысяч с карты Капиталбанка».
/// Никаких сетевых вызовов. Неоднозначности не угадываются, а помечаются в `VoiceDraft.issues`.
public struct VoiceCommandParser: Sendable {
    public let context: VoiceParserContext
    let categorizer: CategorizationEngine
    let activeAccounts: [Account]

    public init(context: VoiceParserContext) {
        self.context = context
        self.categorizer = CategorizationEngine(categories: context.categories, rules: context.merchantRules)
        self.activeAccounts = context.accounts.filter { !$0.isArchived }
    }

    // MARK: - Внутренние структуры

    struct AmountMention {
        var range: Range<Int>
        var value: Decimal
        var hasMultiplier: Bool
        var currency: Currency?
        var currencyTokens: [Int] = []

        var fullStart: Int { min(range.lowerBound, currencyTokens.min() ?? range.lowerBound) }
        var fullEnd: Int { max(range.upperBound, (currencyTokens.max() ?? -1) + 1) }
        var isSmallBare: Bool { value < 100 && !hasMultiplier && currency == nil }
    }

    struct DateMention {
        var range: Range<Int>
        var date: Date
    }

    enum Role {
        case source
        case destination
        case unspecified
    }

    struct AccountMention {
        var index: Int
        var candidates: [UUID]
        var role: Role
        var text: String
    }

    // MARK: - Разбор

    public func parse(_ text: String) -> VoiceParseResult {
        var tokens = VoiceTokenizer.tokenize(text)
        let dates = detectDates(&tokens)
        let cardRefs = consumeNonMoneyNumbers(&tokens)
        let amounts = detectAmounts(tokens)
        var amountTokens = Set<Int>()
        for amount in amounts {
            amountTokens.formUnion(amount.range)
            amountTokens.formUnion(amount.currencyTokens)
        }
        let mentions = detectAccountMentions(tokens, cardRefs: cardRefs, excluding: amountTokens)
        let allWords = tokens.filter { $0.kind == .word }.map(\.text)
        let globalKind = detectKind(allWords)

        guard !amounts.isEmpty else {
            guard globalKind != nil || CategoryKeywords.bestKey(words: allWords, kind: .expense) != nil else {
                return VoiceParseResult(transcript: text, drafts: [])
            }
            let draft = makeDraft(tokens: tokens, range: 0..<tokens.count, amount: nil, dates: dates, mentions: mentions,
                                  allMentions: mentions, globalKind: globalKind, singleDate: dates.count == 1 ? dates.first : nil)
            return VoiceParseResult(transcript: text, drafts: [draft])
        }

        let segments = segmentRanges(tokens: tokens, amounts: amounts)
        let mentionSegments = Set(mentions.compactMap { mention in segments.firstIndex { $0.contains(mention.index) } })
        let singleDate = dates.count == 1 ? dates.first : nil

        var drafts: [VoiceDraft] = []
        for (index, amount) in amounts.enumerated() {
            let range = segments[index]
            var local = mentions.filter { range.contains($0.index) }
            if local.isEmpty && mentionSegments.count == 1 {
                local = mentions
            }
            drafts.append(makeDraft(tokens: tokens, range: range, amount: amount, dates: dates, mentions: local,
                                    allMentions: mentions, globalKind: globalKind, singleDate: singleDate))
        }
        return VoiceParseResult(transcript: text, drafts: drafts)
    }

    // MARK: - Черновик для сегмента

    func makeDraft(
        tokens: [VoiceToken],
        range: Range<Int>,
        amount: AmountMention?,
        dates: [DateMention],
        mentions: [AccountMention],
        allMentions: [AccountMention],
        globalKind: TransactionKind?,
        singleDate: DateMention?
    ) -> VoiceDraft {
        var excluded = Set<Int>()
        if let amount {
            excluded.formUnion(amount.range)
            excluded.formUnion(amount.currencyTokens)
        }
        let words = range.filter { tokens[$0].kind == .word && !excluded.contains($0) && !tokens[$0].consumed }.map { tokens[$0].text }
        let allWords = range.filter { tokens[$0].kind == .word }.map { tokens[$0].text }

        // Тип операции
        var kind = detectKind(words) ?? globalKind ?? inferKindFromCategories(words)
        var forcedCategoryKey: String?
        let hasDebt = allWords.contains { word in VoiceLexicon.debtWords.contains { word.hasPrefix($0) } }
        if kind == .refund && hasDebt {
            kind = .income
            forcedCategoryKey = SystemCategoryKey.debtReturn
        }
        let destinationMentioned = mentions.contains { $0.role == .destination && !$0.candidates.isEmpty }
        if kind == .transfer {
            let toPerson = allWords.contains { VoiceLexicon.personRecipients.contains($0) }
            let isTopUp = VoiceLexicon.contains(allWords, stems: VoiceLexicon.topUpStems)
            if toPerson && !destinationMentioned {
                kind = .expense
                forcedCategoryKey = SystemCategoryKey.transfersOut
            } else if isTopUp && !destinationMentioned && mentions.count < 2 {
                kind = .expense
            }
        }

        // Дата
        let dateMention = dates.first { range.contains($0.range.lowerBound) } ?? singleDate
        let date = dateMention?.date ?? context.now

        // Счета
        var issues: [VoiceIssue] = []
        var accountID: UUID?
        var counterAccountID: UUID?
        let spokenCurrency = amount?.currency

        if kind == .transfer {
            let source = mentions.first { $0.role == .source } ?? mentions.first { $0.role == .unspecified }
            let destination = mentions.first { $0.role == .destination }
                ?? mentions.first { $0.role == .unspecified && $0.index != source?.index }
            if let source {
                accountID = resolve(source, currency: spokenCurrency, issues: &issues)
            }
            if let destination {
                counterAccountID = resolve(destination, currency: nil, issues: &issues)
            }
            if source == nil {
                if let fallback = defaultAccount(excluding: counterAccountID) {
                    accountID = fallback
                    issues.append(.usedDefaultAccount)
                }
            }
        } else {
            let preferred: [AccountMention]
            switch kind {
            case .income, .refund:
                preferred = mentions.filter { $0.role != .source } + mentions.filter { $0.role == .source }
            default:
                preferred = mentions.filter { $0.role != .destination }
            }
            if let mention = preferred.first {
                accountID = resolve(mention, currency: spokenCurrency, issues: &issues)
            } else if let spokenCurrency, let byCurrency = singleAccount(in: spokenCurrency),
                      defaultAccountModel()?.currency != spokenCurrency {
                accountID = byCurrency
                issues.append(.accountInferredFromCurrency)
            } else if let fallback = defaultAccount(excluding: nil) {
                accountID = fallback
                issues.append(.usedDefaultAccount)
            }
        }

        let account = accountID.flatMap { id in activeAccounts.first { $0.id == id } }
        let currency = spokenCurrency ?? account?.currency ?? context.baseCurrency

        // Неоднозначная сумма: «на 300» в сумах без «тысяч».
        if let amount, currency == .uzs, !amount.hasMultiplier, amount.value < 1000, amount.value >= 1,
           DecimalMath.round(amount.value, scale: 0, rule: .down) == amount.value {
            issues.append(.amountMayNeedThousands(suggested: amount.value * 1000))
        }

        // Продавец и категория
        var merchant: String?
        if kind != .transfer && kind != .adjustment {
            merchant = MerchantDirectory.firstMatch(in: words)?.entry.name ?? fallbackMerchant(tokens: tokens, range: range)
        }
        var categoryID: UUID?
        if kind.usesCategory {
            if let forcedCategoryKey, let category = categorizer.category(forSystemKey: forcedCategoryKey) {
                categoryID = category.id
            } else if let suggestion = categorizer.suggest(merchant: merchant, text: words.joined(separator: " "), kind: kind) {
                categoryID = suggestion.categoryID
            } else {
                issues.append(.categoryUncertain)
            }
        }

        var draft = VoiceDraft(
            kind: kind,
            amount: amount?.value,
            currency: currency,
            accountID: accountID,
            counterAccountID: kind == .transfer ? counterAccountID : nil,
            categoryID: categoryID,
            merchant: merchant,
            date: date,
            sourceText: originalText(tokens: tokens, range: range),
            issues: issues
        )
        draft.revalidate(accounts: Dictionary(uniqueKeysWithValues: activeAccounts.map { ($0.id, $0) }), converter: context.converter)
        return draft
    }

    // MARK: - Тип операции

    func detectKind(_ words: [String]) -> TransactionKind? {
        if VoiceLexicon.contains(words, stems: VoiceLexicon.feeStems) || words.contains(where: { VoiceLexicon.feeExact.contains($0) }) {
            return .fee
        }
        if VoiceLexicon.contains(words, stems: VoiceLexicon.refundStems) { return .refund }
        if VoiceLexicon.contains(words, stems: VoiceLexicon.transferStems) { return .transfer }
        if VoiceLexicon.contains(words, stems: VoiceLexicon.incomeStems) { return .income }
        if VoiceLexicon.contains(words, stems: VoiceLexicon.expenseStems) { return .expense }
        return nil
    }

    func inferKindFromCategories(_ words: [String]) -> TransactionKind {
        let income = CategoryKeywords.bestKey(words: words, kind: .income)
        let expense = CategoryKeywords.bestKey(words: words, kind: .expense)
        if let income, expense == nil || income.hits > expense!.hits { return .income }
        return .expense
    }

    // MARK: - Даты

    func detectDates(_ tokens: inout [VoiceToken]) -> [DateMention] {
        var result: [DateMention] = []
        let calendar = context.periods.calendar
        let today = context.periods.startOfDay(context.now)

        func atNoon(_ day: Date) -> Date {
            day == today ? context.now : (calendar.date(byAdding: .hour, value: 12, to: day) ?? day)
        }

        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            guard token.kind == .word || token.kind == .number else { index += 1; continue }

            if let offset = VoiceLexicon.relativeDays[token.text] {
                let day = context.periods.addingDays(offset, to: today)
                tokens[index].consumed = true
                result.append(DateMention(range: index..<(index + 1), date: atNoon(day)))
                index += 1
                continue
            }

            if let weekday = VoiceLexicon.weekdays[token.text] {
                let previous = index > 0 && VoiceLexicon.previousMarkers.contains { tokens[index - 1].text.hasPrefix($0) }
                let currentWeekday = calendar.component(.weekday, from: today)
                var back = (currentWeekday - weekday + 7) % 7
                if previous && back == 0 { back = 7 }
                if previous && back < 7 && back != 0 {
                    // «в прошлую пятницу» — пятница прошлой недели, если ближайшая уже на этой неделе
                    let weekStart = context.periods.weekStart(today)
                    let candidate = context.periods.addingDays(-back, to: today)
                    if candidate >= weekStart { back += 7 }
                }
                let day = context.periods.addingDays(-back, to: today)
                let start = previous ? index - 1 : index
                for i in start...index { tokens[i].consumed = true }
                result.append(DateMention(range: start..<(index + 1), date: atNoon(day)))
                index += 1
                continue
            }

            // «3 октября», «третьего октября», «двадцать первого октября», «October 3»
            var dayValue: Int?
            var dayRange: Range<Int>?
            if token.kind == .number, !token.hasFraction, let value = token.value, value >= 1, value <= 31,
               index + 1 < tokens.count, VoiceLexicon.month(forWord: tokens[index + 1].text) != nil {
                dayValue = DecimalMath.exactInt64(value).map(Int.init)
                dayRange = index..<(index + 1)
            } else if let ordinal = VoiceLexicon.ordinalDays[token.text] {
                dayValue = ordinal
                dayRange = index..<(index + 1)
                if index > 0, case .value(let tens)? = NumberWord.lookup(tokens[index - 1].text), tens == 20 || tens == 30, ordinal < 10 {
                    dayValue = ordinal + (tens == 20 ? 20 : 30)
                    dayRange = (index - 1)..<(index + 1)
                }
            }
            if let dayValue, let dayRange, dayRange.upperBound < tokens.count,
               let month = VoiceLexicon.month(forWord: tokens[dayRange.upperBound].text) {
                var end = dayRange.upperBound + 1
                var year = calendar.component(.year, from: today)
                var explicitYear = false
                if end < tokens.count, tokens[end].kind == .number, let y = tokens[end].value, y >= 2000, y <= 2100,
                   let yearInt = DecimalMath.exactInt64(y) {
                    year = Int(yearInt)
                    explicitYear = true
                    end += 1
                }
                if let date = makeDate(year: year, month: month, day: dayValue, explicitYear: explicitYear, today: today) {
                    for i in dayRange.lowerBound..<end { tokens[i].consumed = true }
                    result.append(DateMention(range: dayRange.lowerBound..<end, date: atNoon(date)))
                    index = end
                    continue
                }
            }
            if let month = VoiceLexicon.month(forWord: token.text), token.kind == .word, index + 1 < tokens.count,
               tokens[index + 1].kind == .number, let value = tokens[index + 1].value, value >= 1, value <= 31, !tokens[index + 1].hasFraction,
               let dayInt = DecimalMath.exactInt64(value),
               !(index + 2 < tokens.count && (NumberWord.digitSuffixMultiplier(tokens[index + 2].text) != nil || VoiceLexicon.currency(forWord: tokens[index + 2].text) != nil)),
               let date = makeDate(year: calendar.component(.year, from: today), month: month, day: Int(dayInt), explicitYear: false, today: today) {
                tokens[index].consumed = true
                tokens[index + 1].consumed = true
                result.append(DateMention(range: index..<(index + 2), date: atNoon(date)))
                index += 2
                continue
            }
            index += 1
        }
        return result
    }

    private func makeDate(year: Int, month: Int, day: Int, explicitYear: Bool, today: Date) -> Date? {
        let calendar = context.periods.calendar
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }
        // Расходы в будущем маловероятны: «25 декабря» в октябре — это прошлый год.
        if !explicitYear && date > context.periods.addingDays(1, to: today) {
            components.year = year - 1
            return calendar.date(from: components)
        }
        return date
    }

    // MARK: - Числа, которые не являются суммами

    /// Время («в 14:30»), количества («2 кг»), номера карт («с карты 4417»). Возвращает номера карт по индексам токенов.
    func consumeNonMoneyNumbers(_ tokens: inout [VoiceToken]) -> [Int: String] {
        var cardRefs: [Int: String] = [:]
        for index in tokens.indices where tokens[index].kind == .number && !tokens[index].consumed {
            let token = tokens[index]
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            // Время 14:30
            if let next, next.kind == .punct, next.text == ":", index + 2 < tokens.count, tokens[index + 2].kind == .number {
                tokens[index].consumed = true
                tokens[index + 2].consumed = true
                continue
            }
            // Количество: «2 кг», «3 штуки», «10%»
            if let next, VoiceLexicon.quantityUnits.contains(next.text) {
                tokens[index].consumed = true
                continue
            }
            // Номер карты: 4 цифры рядом со словом «карта» или «*»
            if token.text.count == 4, token.text.allSatisfy(\.isNumber) {
                let lookback = max(0, index - 3)..<index
                let nearCard = lookback.contains { position in
                    let word = tokens[position].text
                    return VoiceLexicon.cardWords.contains { word.hasPrefix($0) } || word == "*" || word == "конце" || word == "оканчивается"
                }
                if nearCard {
                    tokens[index].consumed = true
                    cardRefs[index] = token.text
                }
            }
        }
        return cardRefs
    }

    // MARK: - Суммы

    private func isMultiplierWord(_ word: String) -> Bool {
        if case .multiplier? = NumberWord.lookup(word) { return true }
        return false
    }

    func detectAmounts(_ tokens: [VoiceToken]) -> [AmountMention] {
        var found: [AmountMention] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let startsNumber = !token.consumed && (token.kind == .number || (token.kind == .word && NumberWord.lookup(token.text) != nil))
            guard startsNumber else { index += 1; continue }

            var parts: [NumberPart] = []
            var position = index
            var lastWasDigits = false
            while position < tokens.count {
                let current = tokens[position]
                if current.consumed { break }
                if current.kind == .number, let value = current.value {
                    if lastWasDigits { break }
                    if !parts.isEmpty, case .word(let last)? = parts.last, case .multiplier = last {} else if !parts.isEmpty {
                        // «двадцать 5» — смешение слов и цифр без множителя: новое число.
                        break
                    }
                    parts.append(.digits(value))
                    lastWasDigits = true
                    position += 1
                    continue
                }
                if current.kind == .word {
                    if lastWasDigits, let multiplier = NumberWord.digitSuffixMultiplier(current.text) {
                        parts.append(.word(.multiplier(multiplier)))
                        lastWasDigits = false
                        position += 1
                        continue
                    }
                    if let word = NumberWord.lookup(current.text) {
                        if case .half = word {
                            let nextIsMultiplier = position + 1 < tokens.count && isMultiplierWord(tokens[position + 1].text)
                            let afterNumber = !parts.isEmpty
                            if !nextIsMultiplier && !afterNumber { break }
                        }
                        if lastWasDigits, case .value = word { break }
                        if lastWasDigits, case .hundred = word {} else if lastWasDigits, case .oneAndHalf = word { break }
                        parts.append(.word(word))
                        lastWasDigits = false
                        position += 1
                        continue
                    }
                }
                break
            }
            guard position > index, let composed = NumberComposer.compose(parts), composed.value > 0 else {
                index = max(position, index + 1)
                continue
            }
            var mention = AmountMention(range: index..<position, value: composed.value, hasMultiplier: composed.hasMultiplier, currency: nil)
            attachCurrency(&mention, tokens: tokens)
            found.append(mention)
            index = mention.fullEnd > position ? mention.fullEnd : position
        }

        guard found.count > 1 else { return found }
        let significant = found.filter { !$0.isSmallBare }
        if significant.isEmpty, let largest = found.max(by: { $0.value < $1.value }) { return [largest] }
        return significant
    }

    private func attachCurrency(_ mention: inout AmountMention, tokens: [VoiceToken]) {
        let after = mention.range.upperBound
        if after < tokens.count, tokens[after].kind != .punct, let currency = VoiceLexicon.currency(forWord: tokens[after].text) {
            mention.currency = currency
            mention.currencyTokens = [after]
            return
        }
        // «85 тысяч узбекских сум» — одно прилагательное между суммой и валютой.
        if after + 1 < tokens.count, tokens[after].kind == .word, tokens[after + 1].kind != .punct,
           let currency = VoiceLexicon.currency(forWord: tokens[after + 1].text), tokens[after].text.count > 3,
           NumberWord.lookup(tokens[after].text) == nil, VoiceLexicon.month(forWord: tokens[after].text) == nil {
            mention.currency = currency
            mention.currencyTokens = [after, after + 1]
            return
        }
        let before = mention.range.lowerBound - 1
        if before >= 0, tokens[before].kind == .symbol || ["usd", "eur", "uzs"].contains(tokens[before].text),
           let currency = VoiceLexicon.currency(forWord: tokens[before].text) {
            mention.currency = currency
            mention.currencyTokens = [before]
        }
    }

    // MARK: - Сегменты

    func segmentRanges(tokens: [VoiceToken], amounts: [AmountMention]) -> [Range<Int>] {
        guard amounts.count > 1 else { return [0..<tokens.count] }
        let beforeFirst = (0..<amounts[0].fullStart).filter { tokens[$0].kind == .word }.map { tokens[$0].text }
        let afterLast = (amounts[amounts.count - 1].fullEnd..<tokens.count).filter { tokens[$0].kind == .word }.map { tokens[$0].text }
        let purposeBefore = hasPurpose(beforeFirst) && !hasPurpose(afterLast)

        var starts = [0]
        var ends: [Int] = []
        for i in 0..<(amounts.count - 1) {
            let end = amounts[i].fullEnd
            let nextStart = amounts[i + 1].fullStart
            var boundary: Int?
            if end < nextStart {
                for position in end..<nextStart {
                    let token = tokens[position]
                    if (token.kind == .punct && [",", ";", "."].contains(token.text)) ||
                        (token.kind == .word && VoiceLexicon.conjunctions.contains(token.text)) {
                        boundary = position
                        break
                    }
                }
            }
            if let boundary {
                ends.append(boundary)
                starts.append(boundary + 1)
            } else {
                let cut = purposeBefore ? end : nextStart
                ends.append(cut)
                starts.append(cut)
            }
        }
        ends.append(tokens.count)
        return zip(starts, ends).map { $0..<max($0, $1) }
    }

    private func hasPurpose(_ words: [String]) -> Bool {
        CategoryKeywords.bestKey(words: words, kind: .expense) != nil || MerchantDirectory.firstMatch(in: words) != nil
    }

    // MARK: - Счета

    func detectAccountMentions(_ tokens: [VoiceToken], cardRefs: [Int: String], excluding: Set<Int> = []) -> [AccountMention] {
        var raw: [AccountMention] = []
        for (index, token) in tokens.enumerated() where !excluding.contains(index) {
            if let digits = cardRefs[index] {
                let candidates = activeAccounts.filter { $0.lastFour == digits }.map(\.id)
                raw.append(AccountMention(index: index, candidates: candidates, role: role(at: index, tokens: tokens), text: "•• " + digits))
                continue
            }
            guard token.kind == .word else { continue }
            let word = token.text

            // Банк. «узум маркет» — это магазин, а не счёт.
            if let nextWord = index + 1 < tokens.count ? tokens[index + 1].text : nil,
               VoiceLexicon.merchantContinuations.contains(where: { nextWord.hasPrefix($0) }) {
                continue
            }
            var matchedBank: Bank?
            for bank in Bank.allCases where bank != .other {
                if bank.mentionStems.contains(where: { stem in stem.count >= 4 ? word.hasPrefix(stem) : word == stem }) {
                    matchedBank = bank
                    break
                }
            }
            if let bank = matchedBank {
                let candidates = activeAccounts.filter { account in
                    bank == .cash ? (account.bank == .cash || account.kind == .cash) : account.bank == bank
                }.map(\.id)
                raw.append(AccountMention(index: index, candidates: candidates, role: role(at: index, tokens: tokens), text: bank.displayName))
                continue
            }
            // Платёжная система: «с хумо», «визой».
            if let system = PaymentSystem.allCases.first(where: { system in
                system.mentionStems.contains { stem in stem.count >= 4 ? word.hasPrefix(stem) : word == stem }
            }) {
                let candidates = activeAccounts.filter { $0.paymentSystem == system }.map(\.id)
                if !candidates.isEmpty {
                    raw.append(AccountMention(index: index, candidates: candidates, role: role(at: index, tokens: tokens), text: system.label))
                }
                continue
            }
            // Пользовательское название счёта: «с основной», «на накопительную».
            guard word.count >= 4, !VoiceLexicon.genericAccountWords.contains(word) else { continue }
            let named = activeAccounts.filter { account in
                TextNormalizer.words(account.name)
                    .filter { $0.count >= 4 && !VoiceLexicon.genericAccountWords.contains($0) }
                    .contains { nameWord in
                        let stem = String(nameWord.prefix(max(4, nameWord.count - 2)))
                        return word.hasPrefix(stem)
                    }
            }
            if !named.isEmpty {
                raw.append(AccountMention(index: index, candidates: named.map(\.id), role: role(at: index, tokens: tokens), text: token.original))
            }
        }

        // Склеиваем соседние упоминания одного счёта: «Капиталбанк Хумо».
        var merged: [AccountMention] = []
        for mention in raw {
            if var last = merged.last, mention.index - last.index <= 2 {
                let common = last.candidates.filter { mention.candidates.contains($0) }
                if !common.isEmpty || last.candidates.isEmpty || mention.candidates.isEmpty {
                    last.candidates = common.isEmpty ? (last.candidates.isEmpty ? mention.candidates : last.candidates) : common
                    if last.role == .unspecified { last.role = mention.role }
                    last.text += " " + mention.text
                    merged[merged.count - 1] = last
                    continue
                }
            }
            merged.append(mention)
        }
        return merged
    }

    func role(at index: Int, tokens: [VoiceToken]) -> Role {
        let word = tokens[index].text
        if word.count > 5 {
            if word.hasSuffix("dan") { return .source }
            if word.hasSuffix("ga") || word.hasSuffix("ka") || word.hasSuffix("qa") { return .destination }
        }
        var position = index - 1
        var steps = 0
        while position >= 0 && steps < 4 {
            let previous = tokens[position]
            guard previous.kind == .word else { break }
            if VoiceLexicon.sourcePrepositions.contains(previous.text) { return .source }
            if VoiceLexicon.destinationPrepositions.contains(previous.text) { return .destination }
            if VoiceLexicon.accountFillers.contains(where: { previous.text.hasPrefix($0) }) {
                position -= 1
                steps += 1
                continue
            }
            break
        }
        return .unspecified
    }

    /// Выбирает счёт по упоминанию. Неоднозначности и отсутствие счёта фиксируются в `issues`.
    func resolve(_ mention: AccountMention, currency: Currency?, issues: inout [VoiceIssue]) -> UUID? {
        if mention.candidates.isEmpty {
            issues.append(.accountNotFound(mention: mention.text))
            return nil
        }
        if mention.candidates.count == 1 { return mention.candidates[0] }
        var narrowed = mention.candidates
        if let currency {
            let sameCurrency = narrowed.filter { id in activeAccounts.first { $0.id == id }?.currency == currency }
            if sameCurrency.count == 1 { return sameCurrency[0] }
            if !sameCurrency.isEmpty { narrowed = sameCurrency }
        }
        issues.append(.ambiguousAccount(candidates: narrowed))
        if let defaultID = context.defaultAccountID, narrowed.contains(defaultID) { return defaultID }
        return narrowed.first
    }

    func defaultAccountModel() -> Account? {
        if let id = context.defaultAccountID, let account = activeAccounts.first(where: { $0.id == id }) { return account }
        return activeAccounts.count == 1 ? activeAccounts[0] : nil
    }

    func defaultAccount(excluding excluded: UUID?) -> UUID? {
        guard let account = defaultAccountModel(), account.id != excluded else { return nil }
        return account.id
    }

    func singleAccount(in currency: Currency) -> UUID? {
        let matches = activeAccounts.filter { $0.currency == currency }
        return matches.count == 1 ? matches[0].id : nil
    }

    // MARK: - Продавец по заглавной букве

    private static let cityStems = ["ташкент", "самарканд", "бухар", "андижан", "наманган", "ферган", "нукус", "карши", "термез",
                                    "хив", "ургенч", "навои", "джизак", "гулистан", "чирчик", "ангрен", "алмалык", "коканд", "москв",
                                    "toshkent", "samarqand", "buxoro"]

    func fallbackMerchant(tokens: [VoiceToken], range: Range<Int>) -> String? {
        for position in range where tokens[position].kind == .word && ["в", "во", "at", "in"].contains(tokens[position].text) {
            let nextIndex = position + 1
            guard nextIndex < range.upperBound, nextIndex < tokens.count else { continue }
            let next = tokens[nextIndex]
            guard next.kind == .word, next.isCapitalized, !next.consumed, next.original.count >= 3 else { continue }
            let word = next.text
            if Bank.allCases.contains(where: { bank in bank.mentionStems.contains { word.hasPrefix($0) } }) { continue }
            if VoiceLexicon.month(forWord: word) != nil || VoiceLexicon.weekdays[word] != nil { continue }
            if Self.cityStems.contains(where: { word.hasPrefix($0) }) { continue }
            if CategoryKeywords.bestKey(words: [word], kind: .expense) != nil { continue }
            var name = next.original
            if name.count > 5, let last = name.last, "еуаЕУА".contains(last),
               let previous = name.dropLast().last, !"аеёиоуыэюяАЕЁИОУЫЭЮЯ".contains(previous) {
                name.removeLast()
            }
            if nextIndex + 1 < range.upperBound, nextIndex + 1 < tokens.count {
                let second = tokens[nextIndex + 1]
                if second.kind == .word, second.isCapitalized, !second.consumed {
                    name += " " + second.original
                }
            }
            return name
        }
        return nil
    }

    func originalText(tokens: [VoiceToken], range: Range<Int>) -> String {
        var text = ""
        for position in range {
            let token = tokens[position]
            if !text.isEmpty && token.spaceBefore { text += " " }
            text += token.original
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ,;."))
    }
}
