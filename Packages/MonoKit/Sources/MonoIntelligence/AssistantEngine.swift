import Foundation
import MonoCore
import MonoAnalytics

/// Период из вопроса пользователя.
public enum AssistantPeriod: Equatable, Sendable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case lastDays(Int)
    case month(MonthKey)
    case year(Int)
    case allTime

    public func range(periods: PeriodCalendar, now: Date) -> DateRange {
        switch self {
        case .today: return periods.dayRange(now)
        case .yesterday: return periods.dayRange(periods.addingDays(-1, to: now))
        case .thisWeek: return periods.range(for: .thisWeek, now: now)
        case .lastWeek:
            let start = periods.addingDays(-7, to: periods.weekStart(now))
            return DateRange(start: start, end: periods.addingDays(7, to: start))
        case .thisMonth: return periods.range(for: .thisMonth, now: now)
        case .lastMonth: return periods.range(for: .lastMonth, now: now)
        case .lastDays(let days):
            let end = periods.addingDays(1, to: periods.startOfDay(now))
            return DateRange(start: periods.addingDays(-max(1, days), to: end), end: end)
        case .month(let key): return periods.monthRange(key)
        case .year(let year):
            return DateRange(start: periods.monthRange(MonthKey(year: year, month: 1)).start,
                             end: periods.monthRange(MonthKey(year: year + 1, month: 1)).start)
        case .allTime:
            return DateRange(start: Date(timeIntervalSince1970: 0), end: periods.addingDays(1, to: periods.startOfDay(now)))
        }
    }

    public func title(_ language: AppLanguage, periods: PeriodCalendar, now: Date) -> String {
        let currentYear = periods.calendar.component(.year, from: now)
        switch self {
        case .today: return Phrase(ru: "сегодня", uz: "bugun", en: "today")(language)
        case .yesterday: return Phrase(ru: "вчера", uz: "kecha", en: "yesterday")(language)
        case .thisWeek: return Phrase(ru: "на этой неделе", uz: "shu haftada", en: "this week")(language)
        case .lastWeek: return Phrase(ru: "на прошлой неделе", uz: "o‘tgan haftada", en: "last week")(language)
        case .thisMonth: return MonthNames.inMonth(periods.monthKey(now), language: language, currentYear: currentYear)
        case .lastMonth: return MonthNames.inMonth(periods.monthKey(now).previous, language: language, currentYear: currentYear)
        case .lastDays(let days): return Phrase(ru: "за последние \(days) дн.", uz: "so‘nggi \(days) kunda", en: "in the last \(days) days")(language)
        case .month(let key): return MonthNames.inMonth(key, language: language, currentYear: currentYear)
        case .year(let year): return Phrase(ru: "в \(year) году", uz: "\(year)-yilda", en: "in \(year)")(language)
        case .allTime: return Phrase(ru: "за всё время", uz: "butun davr uchun", en: "all time")(language)
        }
    }
}

/// Распознанный запрос к ассистенту.
public enum AssistantIntent: Equatable, Sendable {
    case spending(categoryIDs: [UUID], merchant: String?, period: AssistantPeriod)
    case income(period: AssistantPeriod)
    case topCategories(period: AssistantPeriod)
    case compare(AssistantPeriod, AssistantPeriod)
    case categoryGrowth(current: AssistantPeriod, previous: AssistantPeriod)
    case savingsForecast(months: Int)
    case unusualExpenses(period: AssistantPeriod)
    case largestExpenses(period: AssistantPeriod)
    case balance
    case averageDaily(period: AssistantPeriod)
    case budgets
    case unknown
}

/// Ответ ассистента. Все числа посчитаны детерминированно из сохранённых операций.
public struct AssistantAnswer: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var value: String
        public var detail: String?
        /// Доля 0…1 для полоски.
        public var share: Double?
        public var categoryID: UUID?
        public var transactionID: UUID?
        public var tone: Tone

        public enum Tone: String, Sendable {
            case neutral
            case positive
            case negative
        }
    }

    public var intent: AssistantIntent
    public var headline: String
    public var text: String
    public var rows: [Row]
    /// Оговорки о данных: нет курса, мало истории.
    public var note: String?
    public var hasData: Bool
}

/// Локальный ассистент: понимает типовые вопросы на русском (а также базовые на узбекском и английском),
/// считает ответы через `AnalyticsEngine` и формулирует их по шаблонам. Ничего не отправляет в сеть.
public struct AssistantEngine: Sendable {
    public let analytics: AnalyticsEngine
    public let budgets: [Budget]
    public let planned: [PlannedExpense]
    public let language: AppLanguage
    public let now: Date
    let formatter: MoneyFormatter

    public init(analytics: AnalyticsEngine, budgets: [Budget] = [], planned: [PlannedExpense] = [], language: AppLanguage = .ru, now: Date = Date()) {
        self.analytics = analytics
        self.budgets = budgets
        self.planned = planned
        self.language = language
        self.now = now
        self.formatter = MoneyFormatter(language: language)
    }

    /// Подсказки для пустого экрана ассистента.
    public static let suggestions: [Phrase] = [
        Phrase(ru: "Сколько я потратил на еду за этот месяц?", uz: "Shu oy ovqatga qancha sarfladim?", en: "How much did I spend on food this month?"),
        Phrase(ru: "На что я трачу больше всего денег?", uz: "Eng ko‘p pulni nimaga sarflayman?", en: "What do I spend the most on?"),
        Phrase(ru: "Сравни мои расходы за август и сентябрь", uz: "Avgust va sentyabr xarajatlarini solishtir", en: "Compare my spending in August and September"),
        Phrase(ru: "Какие категории выросли сильнее всего?", uz: "Qaysi kategoriyalar ko‘proq o‘sdi?", en: "Which categories grew the most?"),
        Phrase(ru: "Сколько я смогу накопить за три месяца при текущем темпе расходов?", uz: "Uch oyda qancha jamg‘ara olaman?", en: "How much can I save in three months at this pace?"),
        Phrase(ru: "Найди необычно крупные расходы", uz: "G‘ayrioddiy katta xarajatlarni top", en: "Find unusually large expenses")
    ]

    public func ask(_ question: String) -> AssistantAnswer {
        answer(interpret(question))
    }

    // MARK: - Понимание вопроса

    public func interpret(_ question: String) -> AssistantIntent {
        let words = TextNormalizer.words(question)
        guard !words.isEmpty else { return .unknown }
        func has(_ stems: [String]) -> Bool { words.contains { word in stems.contains { word.hasPrefix($0) } } }

        let periodsFound = detectPeriods(words)
        let period = periodsFound.first

        if has(["сравн", "solishtir", "taqqosla", "compare"]) {
            if periodsFound.count >= 2 {
                let sorted = periodsFound.prefix(2).sorted { lhs, rhs in
                    lhs.range(periods: analytics.periods, now: now).start < rhs.range(periods: analytics.periods, now: now).start
                }
                return .compare(sorted[1], sorted[0])
            }
            let current = period ?? .thisMonth
            return .compare(current, previousPeriod(of: current))
        }
        if has(["выросл", "вырос", "увеличил", "рост", "o'sdi", "osdi", "grew", "increase"]) {
            let current = period ?? .lastDays(30)
            return .categoryGrowth(current: current, previous: previousPeriod(of: current))
        }
        if has(["накоп", "отлож", "сэконом", "сберечь", "jamg'ar", "jamgar", "save", "saving"]) {
            return .savingsForecast(months: detectMonthsCount(words) ?? 3)
        }
        if has(["необычн", "аномал", "подозрит", "странн", "g'ayrioddiy", "unusual", "anomal"]) {
            return .unusualExpenses(period: period ?? .lastDays(90))
        }
        if (has(["крупн", "больш", "дорог", "katta", "largest", "biggest"]) && has(["покуп", "трат", "расход", "xarid", "xarajat", "purchase", "expense"]))
            && !words.contains("всего") {
            return .largestExpenses(period: period ?? .thisMonth)
        }
        if has(["бюджет", "лимит", "byudjet", "limit", "budget"]) {
            return .budgets
        }
        if has(["баланс", "balans", "balance"]) || (has(["сколько"]) && has(["денег", "осталось"]) && !has(["потрат", "трач"])) {
            return .balance
        }
        if has(["средн", "o'rtacha", "average"]) {
            return .averageDaily(period: period ?? .thisMonth)
        }
        let categoryIDs = detectCategories(words)
        let merchant = MerchantDirectory.firstMatch(in: words)?.entry.name
        let asksWhat = words.contains("что") && words.contains("на")
        let asksMost = (has(["больше"]) && words.contains("всего")) || (words.contains("most") && has(["spend", "what"]))
        if asksWhat || has(["куда"]) || asksMost || (has(["основн", "top", "eng"]) && categoryIDs.isEmpty) {
            return .topCategories(period: period ?? .thisMonth)
        }
        if has(["заработ", "доход", "получил", "пришл", "daromad", "topdim", "earn", "income"]) {
            return .income(period: period ?? .thisMonth)
        }
        if has(["потрат", "трач", "трат", "расход", "ушло", "заплат", "sarfla", "xarajat", "spend", "spent"]) || !categoryIDs.isEmpty || merchant != nil {
            return .spending(categoryIDs: categoryIDs, merchant: merchant, period: period ?? .thisMonth)
        }
        return .unknown
    }

    func previousPeriod(of period: AssistantPeriod) -> AssistantPeriod {
        switch period {
        case .today: return .yesterday
        case .yesterday: return .lastDays(1)
        case .thisWeek: return .lastWeek
        case .lastWeek: return .lastWeek
        case .thisMonth: return .lastMonth
        case .lastMonth: return .month(analytics.periods.monthKey(now).adding(months: -2))
        case .lastDays(let days):
            return .lastDays(days)
        case .month(let key): return .month(key.previous)
        case .year(let year): return .year(year - 1)
        case .allTime: return .allTime
        }
    }

    func detectPeriods(_ words: [String]) -> [AssistantPeriod] {
        var result: [AssistantPeriod] = []
        let current = analytics.periods.monthKey(now)
        for (index, word) in words.enumerated() {
            let previousWord = index > 0 ? words[index - 1] : ""
            let isPrevious = previousWord.hasPrefix("прошл") || previousWord == "last" || previousWord.hasPrefix("o'tgan") || previousWord.hasPrefix("otgan")
            if word.hasPrefix("месяц") || word == "oy" || word == "oyda" || word == "month" {
                result.append(isPrevious ? .lastMonth : .thisMonth)
            } else if word.hasPrefix("недел") || word.hasPrefix("hafta") || word == "week" {
                result.append(isPrevious ? .lastWeek : .thisWeek)
            } else if word == "сегодня" || word == "bugun" || word == "today" {
                result.append(.today)
            } else if word == "вчера" || word == "kecha" || word == "yesterday" {
                result.append(.yesterday)
            } else if word == "год" || word == "году" || word == "yil" || word == "year" {
                let year = analytics.periods.calendar.component(.year, from: now)
                result.append(.year(isPrevious ? year - 1 : year))
            } else if word.hasPrefix("дн") || word.hasPrefix("kun") || word.hasPrefix("day") {
                if index > 0, let count = numberValue(words[index - 1]) {
                    result.append(.lastDays(count))
                }
            } else if let month = MonthNames.month(fromWord: word), word.count >= 3 {
                var key = MonthKey(year: current.year, month: month)
                if key > current { key = MonthKey(year: current.year - 1, month: month) }
                result.append(.month(key))
            }
        }
        if words.contains("все") && words.contains("время") { result.insert(.allTime, at: 0) }
        return result
    }

    func numberValue(_ word: String) -> Int? {
        if let value = Int(word) { return value }
        if case .value(let decimal)? = NumberWord.lookup(word), let int = DecimalMath.exactInt64(decimal) { return Int(int) }
        return nil
    }

    func detectMonthsCount(_ words: [String]) -> Int? {
        if words.contains(where: { $0.hasPrefix("полгод") }) { return 6 }
        for (index, word) in words.enumerated() where word.hasPrefix("месяц") || word == "oy" || word.hasPrefix("oyda") || word.hasPrefix("month") {
            if index > 0, let value = numberValue(words[index - 1]) { return min(max(value, 1), 36) }
        }
        if words.contains(where: { $0 == "год" || $0 == "yil" || $0 == "year" }) { return 12 }
        return nil
    }

    /// Категории из вопроса: «еду» → продукты + кафе + доставка; «такси» → такси; собственные названия категорий.
    func detectCategories(_ words: [String]) -> [UUID] {
        let engine = CategorizationEngine(categories: Array(analytics.categories.values), rules: [])
        var keys: [String] = []
        if words.contains(where: { ["еду", "еда", "еды", "питание", "ovqat", "ovqatga", "food"].contains($0) }) {
            keys = [SystemCategoryKey.groceries, SystemCategoryKey.cafe, SystemCategoryKey.delivery]
        } else if words.contains(where: { $0.hasPrefix("транспорт") || $0 == "transport" }) {
            keys = [SystemCategoryKey.taxi, SystemCategoryKey.transport, SystemCategoryKey.fuel]
        } else if words.contains(where: { $0.hasPrefix("коммунал") || $0 == "kommunal" || $0 == "utilities" }) {
            keys = [SystemCategoryKey.utilities]
        }
        if !keys.isEmpty {
            return keys.compactMap { engine.category(forSystemKey: $0)?.id }
        }
        let filtered = words.filter { !["сколько", "я", "потратил", "потратила", "трачу", "на", "за", "в", "этот", "месяц", "этом"].contains($0) }
        if let best = CategoryKeywords.bestKey(words: filtered, kind: .expense), let category = engine.category(forSystemKey: best.key) {
            return [category.id]
        }
        for category in analytics.categories.values where !category.isArchived && category.kind == .expense && category.systemKey == nil {
            let nameWords = TextNormalizer.words(category.name).filter { $0.count >= 4 }
            for nameWord in nameWords {
                let stem = String(nameWord.prefix(max(4, nameWord.count - 2)))
                if filtered.contains(where: { $0.hasPrefix(stem) }) { return [category.id] }
            }
        }
        return []
    }

    // MARK: - Ответ

    public func answer(_ intent: AssistantIntent) -> AssistantAnswer {
        switch intent {
        case .spending(let categoryIDs, let merchant, let period): return spendingAnswer(categoryIDs: categoryIDs, merchant: merchant, period: period, intent: intent)
        case .income(let period): return incomeAnswer(period: period, intent: intent)
        case .topCategories(let period): return topCategoriesAnswer(period: period, intent: intent)
        case .compare(let current, let previous): return compareAnswer(current: current, previous: previous, intent: intent)
        case .categoryGrowth(let current, let previous): return growthAnswer(current: current, previous: previous, intent: intent)
        case .savingsForecast(let months): return forecastAnswer(months: months, intent: intent)
        case .unusualExpenses(let period): return unusualAnswer(period: period, intent: intent)
        case .largestExpenses(let period): return largestAnswer(period: period, intent: intent)
        case .balance: return balanceAnswer(intent: intent)
        case .averageDaily(let period): return averageAnswer(period: period, intent: intent)
        case .budgets: return budgetsAnswer(intent: intent)
        case .unknown:
            return AssistantAnswer(
                intent: intent,
                headline: Phrase(ru: "Не совсем понял вопрос", uz: "Savolni tushunmadim", en: "I didn't quite get that")(language),
                text: Phrase(ru: "Я отвечаю по вашим операциям: траты по категориям, сравнение месяцев, прогноз накоплений, крупные и необычные расходы. Попробуйте одну из подсказок.",
                             uz: "Men operatsiyalaringiz bo‘yicha javob beraman. Maslahatlardan birini sinab ko‘ring.",
                             en: "I answer from your transactions: spending by category, month comparisons, savings forecasts, large and unusual expenses.")(language),
                rows: [],
                note: nil,
                hasData: false
            )
        }
    }

    private func money(_ value: Money) -> String { formatter.string(value) }
    private func compact(_ value: Money) -> String { formatter.compact(value) }
    private func percent(_ ratio: Double) -> String {
        let value = Int((ratio * 100).rounded())
        return "\(value)%"
    }
    private func signedPercent(_ ratio: Double) -> String {
        let value = Int((ratio * 100).rounded())
        return value > 0 ? "+\(value)%" : (value < 0 ? "\(MoneyFormatter.minus)\(-value)%" : "0%")
    }
    private func categoryName(_ id: UUID?) -> String {
        guard let id, let category = analytics.categories[id] else {
            return Phrase(ru: "Без категории", uz: "Kategoriyasiz", en: "Uncategorized")(language)
        }
        return category.name
    }
    private func periodTitle(_ period: AssistantPeriod) -> String {
        period.title(language, periods: analytics.periods, now: now)
    }
    private func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
    private func excludedNote(_ currencies: Set<Currency>) -> String? {
        guard !currencies.isEmpty else { return nil }
        let codes = currencies.map(\.code).sorted().joined(separator: ", ")
        return Phrase(ru: "Не учтены операции в \(codes): нет курса к базовой валюте.",
                      uz: "\(codes) dagi operatsiyalar hisobga olinmadi: kurs yo‘q.",
                      en: "Transactions in \(codes) are excluded: no exchange rate.")(language)
    }

    func spendingAnswer(categoryIDs: [UUID], merchant: String?, period: AssistantPeriod, intent: AssistantIntent) -> AssistantAnswer {
        let range = period.range(periods: analytics.periods, now: now)
        let summary = analytics.summary(range)
        let periodText = periodTitle(period)

        if let merchant {
            let key = MerchantNormalizer.key(merchant)
            let matches = analytics.transactions.filter {
                $0.kind == .expense && range.contains($0.date) && $0.merchant.map { MerchantNormalizer.key($0).hasPrefix(key) || CategorizationEngine.learningKey(for: $0) == key } == true
            }
            var total = Money.zero(analytics.base)
            for transaction in matches { if let amount = analytics.converter.toBase(transaction.amount) { total += amount } }
            let has = !matches.isEmpty
            let text = has
                ? Phrase(ru: "\(capitalized(periodText)) в \(merchant): \(money(total)), \(matches.count) покуп.",
                         uz: "\(capitalized(periodText)) \(merchant): \(money(total)), \(matches.count) ta xarid.",
                         en: "\(capitalized(periodText)) at \(merchant): \(money(total)) across \(matches.count) purchases.")(language)
                : Phrase(ru: "\(capitalized(periodText)) покупок в \(merchant) не найдено.", uz: "\(capitalized(periodText)) \(merchant) da xaridlar topilmadi.", en: "No purchases at \(merchant) \(periodText).")(language)
            let rows = matches.prefix(8).map { transaction in
                AssistantAnswer.Row(id: transaction.id.uuidString, title: transaction.merchant ?? merchant,
                                    value: money(analytics.converter.toBase(transaction.amount) ?? transaction.amount),
                                    detail: shortDate(transaction.date), share: nil, categoryID: transaction.categoryID,
                                    transactionID: transaction.id, tone: .neutral)
            }
            return AssistantAnswer(intent: intent, headline: money(total), text: text, rows: Array(rows), note: excludedNote(summary.excludedCurrencies), hasData: has)
        }

        let breakdown = analytics.spendingByCategory(range)
        let selected = categoryIDs.isEmpty ? breakdown : breakdown.filter { item in item.categoryID.map(categoryIDs.contains) ?? false }
        var total = Money.zero(analytics.base)
        for item in selected { total += item.amount }
        let share = summary.spending.minorUnits > 0 ? Double(total.minorUnits) / Double(summary.spending.minorUnits) : 0
        let label: String
        if categoryIDs.isEmpty {
            label = Phrase(ru: "Все расходы", uz: "Barcha xarajatlar", en: "All spending")(language)
        } else if categoryIDs.count == 1 {
            label = "«\(categoryName(categoryIDs[0]))»"
        } else {
            label = categoryIDs.map { categoryName($0) }.joined(separator: ", ")
        }

        guard total.minorUnits > 0 else {
            return AssistantAnswer(
                intent: intent,
                headline: money(total),
                text: Phrase(ru: "\(capitalized(periodText)) трат по запросу (\(label)) не найдено.",
                             uz: "\(capitalized(periodText)) bu bo‘yicha xarajat topilmadi.",
                             en: "No spending for \(label) \(periodText).")(language),
                rows: [], note: excludedNote(summary.excludedCurrencies), hasData: false
            )
        }

        let text: String
        if categoryIDs.isEmpty {
            text = Phrase(ru: "\(capitalized(periodText)) расходы составили \(money(total)) (без учёта комиссий \(money(summary.fees))).",
                          uz: "\(capitalized(periodText)) xarajatlar \(money(total)).",
                          en: "\(capitalized(periodText)) you spent \(money(total)) (plus \(money(summary.fees)) in fees).")(language)
        } else {
            let target = categoryIDs.count == 1 ? label : label.lowercased()
            text = Phrase(ru: "\(capitalized(periodText)) на \(target) ушло \(money(total)) — \(percent(share)) всех расходов.",
                          uz: "\(capitalized(periodText)) \(target) uchun \(money(total)) sarflandi — barcha xarajatlarning \(percent(share)).",
                          en: "\(capitalized(periodText)) \(target) cost \(money(total)) — \(percent(share)) of all spending.")(language)
        }
        let rows = selected.map { item in
            AssistantAnswer.Row(id: item.id, title: categoryName(item.categoryID), value: money(item.amount),
                                detail: Phrase(ru: "\(item.count) опер.", uz: "\(item.count) ta", en: "\(item.count) txns")(language),
                                share: total.minorUnits > 0 ? Double(item.amount.minorUnits) / Double(total.minorUnits) : nil,
                                categoryID: item.categoryID, transactionID: nil, tone: .neutral)
        }
        return AssistantAnswer(intent: intent, headline: money(total), text: text, rows: rows, note: excludedNote(summary.excludedCurrencies), hasData: true)
    }

    func incomeAnswer(period: AssistantPeriod, intent: AssistantIntent) -> AssistantAnswer {
        let range = period.range(periods: analytics.periods, now: now)
        let summary = analytics.summary(range)
        let breakdown = analytics.incomeByCategory(range)
        let periodText = periodTitle(period)
        let has = summary.income.minorUnits > 0
        let text = has
            ? Phrase(ru: "\(capitalized(periodText)) доходы составили \(money(summary.income)). Чистый поток после расходов и комиссий: \(formatter.string(summary.net, sign: .always)).",
                     uz: "\(capitalized(periodText)) daromad \(money(summary.income)). Sof oqim: \(formatter.string(summary.net, sign: .always)).",
                     en: "\(capitalized(periodText)) income was \(money(summary.income)). Net after spending and fees: \(formatter.string(summary.net, sign: .always)).")(language)
            : Phrase(ru: "\(capitalized(periodText)) доходов не найдено.", uz: "\(capitalized(periodText)) daromad topilmadi.", en: "No income \(periodText).")(language)
        let rows = breakdown.map { item in
            AssistantAnswer.Row(id: item.id, title: categoryName(item.categoryID), value: money(item.amount), detail: nil,
                                share: item.share, categoryID: item.categoryID, transactionID: nil, tone: .positive)
        }
        return AssistantAnswer(intent: intent, headline: money(summary.income), text: text, rows: rows, note: excludedNote(summary.excludedCurrencies), hasData: has)
    }

    func topCategoriesAnswer(period: AssistantPeriod, intent: AssistantIntent) -> AssistantAnswer {
        let range = period.range(periods: analytics.periods, now: now)
        let breakdown = analytics.spendingByCategory(range)
        let summary = analytics.summary(range)
        let periodText = periodTitle(period)
        guard let first = breakdown.first else {
            return AssistantAnswer(intent: intent, headline: "—",
                                   text: Phrase(ru: "\(capitalized(periodText)) расходов пока нет.", uz: "\(capitalized(periodText)) xarajatlar yo‘q.", en: "No spending \(periodText) yet.")(language),
                                   rows: [], note: nil, hasData: false)
        }
        let next = breakdown.dropFirst().prefix(2).map { "«\(categoryName($0.categoryID))»" }.joined(separator: Phrase(ru: " и ", uz: " va ", en: " and ")(language))
        var text = Phrase(ru: "\(capitalized(periodText)) больше всего ушло на «\(categoryName(first.categoryID))»: \(money(first.amount)) (\(percent(first.share)) расходов).",
                          uz: "\(capitalized(periodText)) eng ko‘p «\(categoryName(first.categoryID))» uchun: \(money(first.amount)) (\(percent(first.share))).",
                          en: "\(capitalized(periodText)) most went to “\(categoryName(first.categoryID))”: \(money(first.amount)) (\(percent(first.share)) of spending).")(language)
        if !next.isEmpty {
            text += Phrase(ru: " Дальше — \(next).", uz: " Keyin — \(next).", en: " Next: \(next).")(language)
        }
        let rows = breakdown.prefix(8).map { item in
            AssistantAnswer.Row(id: item.id, title: categoryName(item.categoryID), value: money(item.amount), detail: percent(item.share),
                                share: item.share, categoryID: item.categoryID, transactionID: nil, tone: .neutral)
        }
        return AssistantAnswer(intent: intent, headline: categoryName(first.categoryID), text: text, rows: Array(rows),
                               note: excludedNote(summary.excludedCurrencies), hasData: true)
    }

    func compareAnswer(current: AssistantPeriod, previous: AssistantPeriod, intent: AssistantIntent) -> AssistantAnswer {
        let currentRange = current.range(periods: analytics.periods, now: now)
        let previousRange = previous.range(periods: analytics.periods, now: now)
        let comparison = analytics.compare(currentRange, with: previousRange)
        let currentTitle = periodTitle(current)
        let previousTitle = periodTitle(previous)
        let has = !comparison.current.isEmpty || !comparison.previous.isEmpty
        guard has else {
            return AssistantAnswer(intent: intent, headline: "—",
                                   text: Phrase(ru: "Нет операций ни \(currentTitle), ни \(previousTitle).", uz: "Ikkala davrda ham operatsiya yo‘q.", en: "No transactions in either period.")(language),
                                   rows: [], note: nil, hasData: false)
        }
        let delta = comparison.current.spending - comparison.previous.spending
        let ratio = comparison.spendingChangeRatio
        var text = Phrase(ru: "\(capitalized(currentTitle)) расходы — \(money(comparison.current.spending)), \(previousTitle) — \(money(comparison.previous.spending)). Разница: \(formatter.string(delta, sign: .always))",
                          uz: "\(capitalized(currentTitle)) xarajatlar — \(money(comparison.current.spending)), \(previousTitle) — \(money(comparison.previous.spending)). Farq: \(formatter.string(delta, sign: .always))",
                          en: "\(capitalized(currentTitle)) spending was \(money(comparison.current.spending)) vs \(money(comparison.previous.spending)) \(previousTitle). Difference: \(formatter.string(delta, sign: .always))")(language)
        if let ratio { text += " (\(signedPercent(ratio)))" }
        text += "."
        if let biggest = comparison.categories.first(where: { $0.change.minorUnits > 0 }) {
            text += Phrase(ru: " Сильнее всего выросли «\(categoryName(biggest.categoryID))»: \(formatter.string(biggest.change, sign: .always)).",
                           uz: " Eng ko‘p o‘sgan: «\(categoryName(biggest.categoryID))» \(formatter.string(biggest.change, sign: .always)).",
                           en: " Biggest increase: “\(categoryName(biggest.categoryID))” \(formatter.string(biggest.change, sign: .always)).")(language)
        }
        let rows = comparison.categories.prefix(8).map { delta in
            AssistantAnswer.Row(id: delta.id, title: categoryName(delta.categoryID), value: formatter.string(delta.change, sign: .always),
                                detail: "\(compact(delta.previous)) → \(compact(delta.current))", share: nil, categoryID: delta.categoryID,
                                transactionID: nil, tone: delta.change.minorUnits > 0 ? .negative : (delta.change.minorUnits < 0 ? .positive : .neutral))
        }
        let excluded = comparison.current.excludedCurrencies.union(comparison.previous.excludedCurrencies)
        return AssistantAnswer(intent: intent, headline: ratio.map(signedPercent) ?? formatter.string(delta, sign: .always), text: text,
                               rows: Array(rows), note: excludedNote(excluded), hasData: true)
    }

    func growthAnswer(current: AssistantPeriod, previous: AssistantPeriod, intent: AssistantIntent) -> AssistantAnswer {
        let currentRange = current.range(periods: analytics.periods, now: now)
        var previousRange = previous.range(periods: analytics.periods, now: now)
        if current == previous, case .lastDays(let days) = current {
            previousRange = DateRange(start: analytics.periods.addingDays(-days, to: currentRange.start), end: currentRange.start)
        }
        let comparison = analytics.compare(currentRange, with: previousRange)
        let grown = comparison.categories
            .filter { $0.change.minorUnits > 0 }
            .sorted { $0.change.minorUnits > $1.change.minorUnits }
        guard !grown.isEmpty else {
            return AssistantAnswer(intent: intent, headline: Phrase(ru: "Роста нет", uz: "O‘sish yo‘q", en: "No growth")(language),
                                   text: Phrase(ru: "По сравнению с предыдущим периодом ни одна категория не выросла.", uz: "Hech bir kategoriya o‘smadi.", en: "No category grew compared with the previous period.")(language),
                                   rows: [], note: nil, hasData: !comparison.current.isEmpty)
        }
        let top = grown[0]
        let ratioText = top.changeRatio.map { " (\(signedPercent($0)))" } ?? Phrase(ru: " (новая статья расходов)", uz: " (yangi)", en: " (new)")(language)
        let periodLabel: String
        if case .lastDays(let days) = current {
            periodLabel = Phrase(ru: "за последние \(days) дн. против предыдущих \(days)", uz: "so‘nggi \(days) kun va undan oldingi \(days) kun", en: "last \(days) days vs the \(days) before")(language)
        } else {
            periodLabel = "\(periodTitle(current)) / \(periodTitle(previous))"
        }
        let text = Phrase(ru: "Сильнее всего выросли «\(categoryName(top.categoryID))»: \(formatter.string(top.change, sign: .always))\(ratioText) — \(periodLabel).",
                          uz: "Eng ko‘p o‘sgan: «\(categoryName(top.categoryID))» \(formatter.string(top.change, sign: .always))\(ratioText) — \(periodLabel).",
                          en: "“\(categoryName(top.categoryID))” grew the most: \(formatter.string(top.change, sign: .always))\(ratioText) — \(periodLabel).")(language)
        let rows = grown.prefix(8).map { delta in
            AssistantAnswer.Row(id: delta.id, title: categoryName(delta.categoryID), value: formatter.string(delta.change, sign: .always),
                                detail: delta.changeRatio.map(signedPercent) ?? Phrase(ru: "новое", uz: "yangi", en: "new")(language),
                                share: nil, categoryID: delta.categoryID, transactionID: nil, tone: .negative)
        }
        return AssistantAnswer(intent: intent, headline: categoryName(top.categoryID), text: text, rows: Array(rows), note: nil, hasData: true)
    }

    func forecastAnswer(months: Int, intent: AssistantIntent) -> AssistantAnswer {
        let forecast = analytics.savingsForecast(months: months, now: now, planned: planned)
        let monthsWord = Phrase(ru: "\(months) мес.", uz: "\(months) oy", en: "\(months) months")(language)
        var note: String?
        switch forecast.basisDescription {
        case .none:
            return AssistantAnswer(intent: intent, headline: "—",
                                   text: Phrase(ru: "Пока недостаточно операций, чтобы оценить темп. Добавьте доходы и расходы хотя бы за пару недель.",
                                                uz: "Hali yetarli ma’lumot yo‘q.", en: "Not enough data yet to estimate your pace.")(language),
                                   rows: [], note: nil, hasData: false)
        case .recentDays(let days):
            note = Phrase(ru: "Мало истории: расчёт по последним \(days) дн., пересчитанным на месяц. Точность низкая.",
                          uz: "Ma’lumot kam: so‘nggi \(days) kun asosida hisoblandi.", en: "Limited history: based on the last \(days) days scaled to a month.")(language)
        case .fullMonths(let keys):
            let currentYear = analytics.periods.calendar.component(.year, from: now)
            let names = keys.sorted().map { MonthNames.name($0.month, language: language) + ($0.year == currentYear ? "" : " \($0.year)") }
            note = Phrase(ru: "Основа расчёта: \(names.joined(separator: ", ")).", uz: "Hisob asosi: \(names.joined(separator: ", ")).", en: "Based on: \(names.joined(separator: ", ")).")(language)
            if keys.count < 2 {
                note! += Phrase(ru: " Это всего один месяц — прогноз приблизительный.", uz: " Faqat bir oy.", en: " Only one month — rough estimate.")(language)
            }
        }
        let positive = forecast.projectedSavings.minorUnits > 0
        var text = positive
            ? Phrase(ru: "При текущем темпе за \(monthsWord) можно отложить около \(money(forecast.projectedSavings)).",
                     uz: "Joriy sur’atda \(monthsWord) ichida taxminan \(money(forecast.projectedSavings)) jamg‘arish mumkin.",
                     en: "At the current pace you could save about \(money(forecast.projectedSavings)) in \(monthsWord).")(language)
            : Phrase(ru: "При текущем темпе за \(monthsWord) расходы превысят доходы на \(money(forecast.projectedSavings.magnitude)).",
                     uz: "Joriy sur’atda xarajatlar daromaddan \(money(forecast.projectedSavings.magnitude)) ga oshadi.",
                     en: "At the current pace spending will exceed income by \(money(forecast.projectedSavings.magnitude)) over \(monthsWord).")(language)
        text += Phrase(ru: " В среднем в месяц: доход \(compact(forecast.averageIncome)), расходы с комиссиями \(compact(forecast.averageOutflow)).",
                       uz: " O‘rtacha oyiga: daromad \(compact(forecast.averageIncome)), xarajat \(compact(forecast.averageOutflow)).",
                       en: " Monthly average: income \(compact(forecast.averageIncome)), spending incl. fees \(compact(forecast.averageOutflow)).")(language)
        if forecast.plannedExpenses.minorUnits > 0 {
            text += Phrase(ru: " Учтены запланированные траты: \(compact(forecast.plannedExpenses)).",
                           uz: " Rejalashtirilgan xarajatlar hisobga olindi: \(compact(forecast.plannedExpenses)).",
                           en: " Planned expenses included: \(compact(forecast.plannedExpenses)).")(language)
        }
        let rows = [
            AssistantAnswer.Row(id: "income", title: Phrase(ru: "Средний доход", uz: "O‘rtacha daromad", en: "Avg income")(language), value: money(forecast.averageIncome), detail: nil, share: nil, categoryID: nil, transactionID: nil, tone: .positive),
            AssistantAnswer.Row(id: "outflow", title: Phrase(ru: "Средние расходы", uz: "O‘rtacha xarajat", en: "Avg spending")(language), value: money(forecast.averageOutflow), detail: nil, share: nil, categoryID: nil, transactionID: nil, tone: .negative),
            AssistantAnswer.Row(id: "planned", title: Phrase(ru: "Запланировано", uz: "Rejada", en: "Planned")(language), value: money(forecast.plannedExpenses), detail: nil, share: nil, categoryID: nil, transactionID: nil, tone: .neutral)
        ]
        return AssistantAnswer(intent: intent, headline: formatter.string(forecast.projectedSavings, sign: .automatic), text: text, rows: rows, note: note, hasData: true)
    }

    func unusualAnswer(period: AssistantPeriod, intent: AssistantIntent) -> AssistantAnswer {
        let range = period.range(periods: analytics.periods, now: now)
        let unusual = analytics.unusualExpenses(range, limit: 8)
        guard !unusual.isEmpty else {
            return AssistantAnswer(intent: intent, headline: Phrase(ru: "Всё в норме", uz: "Hammasi joyida", en: "All normal")(language),
                                   text: Phrase(ru: "\(capitalized(periodTitle(period))) необычно крупных трат не найдено (или пока мало истории для сравнения).",
                                                uz: "G‘ayrioddiy katta xarajatlar topilmadi.", en: "No unusually large expenses \(periodTitle(period)).")(language),
                                   rows: [], note: nil, hasData: false)
        }
        let first = unusual[0]
        let times = String(format: "%.1f", first.ratio).replacingOccurrences(of: ".", with: language == .en ? "." : ",")
        let text = Phrase(ru: "Нашёл \(unusual.count) необычно крупн. трат. Самая заметная — \(money(first.amount)) в «\(categoryName(first.transaction.categoryID))», в \(times) раза больше обычного (\(money(first.typical))).",
                          uz: "\(unusual.count) ta g‘ayrioddiy xarajat topildi. Eng kattasi — \(money(first.amount)), odatdagidan \(times) baravar ko‘p.",
                          en: "Found \(unusual.count) unusually large expenses. The most notable: \(money(first.amount)) in “\(categoryName(first.transaction.categoryID))”, \(times)× the usual (\(money(first.typical))).")(language)
        let rows = unusual.map { item in
            AssistantAnswer.Row(id: item.id.uuidString, title: item.transaction.merchant ?? categoryName(item.transaction.categoryID), value: money(item.amount),
                                detail: shortDate(item.transaction.date) + " · ×" + String(format: "%.1f", item.ratio),
                                share: nil, categoryID: item.transaction.categoryID, transactionID: item.transaction.id, tone: .negative)
        }
        return AssistantAnswer(intent: intent, headline: money(first.amount), text: text, rows: rows, note: nil, hasData: true)
    }

    func largestAnswer(period: AssistantPeriod, intent: AssistantIntent) -> AssistantAnswer {
        let range = period.range(periods: analytics.periods, now: now)
        let largest = analytics.largestExpenses(range, limit: 8)
        guard let first = largest.first else {
            return AssistantAnswer(intent: intent, headline: "—", text: Phrase(ru: "\(capitalized(periodTitle(period))) расходов нет.", uz: "Xarajatlar yo‘q.", en: "No expenses \(periodTitle(period)).")(language),
                                   rows: [], note: nil, hasData: false)
        }
        let firstAmount = analytics.converter.toBase(first.amount) ?? first.amount
        let text = Phrase(ru: "Крупнейшая трата \(periodTitle(period)) — \(money(firstAmount))\(first.merchant.map { " (\($0))" } ?? "").",
                          uz: "Eng katta xarajat — \(money(firstAmount)).", en: "Largest expense \(periodTitle(period)): \(money(firstAmount)).")(language)
        let rows = largest.map { transaction in
            AssistantAnswer.Row(id: transaction.id.uuidString, title: transaction.merchant ?? categoryName(transaction.categoryID),
                                value: money(analytics.converter.toBase(transaction.amount) ?? transaction.amount), detail: shortDate(transaction.date),
                                share: nil, categoryID: transaction.categoryID, transactionID: transaction.id, tone: .neutral)
        }
        return AssistantAnswer(intent: intent, headline: money(firstAmount), text: text, rows: rows, note: nil, hasData: true)
    }

    func balanceAnswer(intent: AssistantIntent) -> AssistantAnswer {
        let total = analytics.totalBalance()
        let balances = Ledger.balances(accounts: analytics.totalAccounts, transactions: analytics.transactions)
        let rows = analytics.totalAccounts.sorted { $0.sortOrder < $1.sortOrder }.map { account in
            AssistantAnswer.Row(id: account.id.uuidString, title: account.displayName, value: money(balances[account.id] ?? .zero(account.currency)),
                                detail: account.bank.displayName, share: nil, categoryID: nil, transactionID: nil, tone: .neutral)
        }
        let text = Phrase(ru: "Общий баланс по всем счетам — \(money(total.total)) по текущим курсам.",
                          uz: "Barcha hisoblar bo‘yicha umumiy balans — \(money(total.total)).",
                          en: "Total balance across accounts: \(money(total.total)) at current rates.")(language)
        return AssistantAnswer(intent: intent, headline: money(total.total), text: text, rows: rows, note: excludedNote(total.excluded), hasData: !analytics.totalAccounts.isEmpty)
    }

    func averageAnswer(period: AssistantPeriod, intent: AssistantIntent) -> AssistantAnswer {
        let range = period.range(periods: analytics.periods, now: now)
        let average = analytics.averageDailySpending(range, now: now)
        let days = analytics.elapsedDays(range, now: now)
        let has = average.minorUnits > 0
        let text = Phrase(ru: "\(capitalized(periodTitle(period))) в среднем \(money(average)) в день (по \(days) дн.).",
                          uz: "\(capitalized(periodTitle(period))) kuniga o‘rtacha \(money(average)) (\(days) kun).",
                          en: "\(capitalized(periodTitle(period))) you spent \(money(average)) per day on average (\(days) days).")(language)
        return AssistantAnswer(intent: intent, headline: money(average), text: text, rows: [], note: nil, hasData: has)
    }

    func budgetsAnswer(intent: AssistantIntent) -> AssistantAnswer {
        let statuses = analytics.budgetStatuses(budgets, month: analytics.periods.monthKey(now), now: now)
        guard !statuses.isEmpty else {
            return AssistantAnswer(intent: intent, headline: "—", text: Phrase(ru: "Бюджеты ещё не настроены. Их можно создать во вкладке «Планы».", uz: "Byudjetlar hali sozlanmagan.", en: "No budgets yet. Create them in Plans.")(language),
                                   rows: [], note: nil, hasData: false)
        }
        let exceeded = statuses.filter { $0.state == .exceeded }
        let text = exceeded.isEmpty
            ? Phrase(ru: "Все бюджеты в пределах лимитов.", uz: "Barcha byudjetlar limit doirasida.", en: "All budgets are within limits.")(language)
            : Phrase(ru: "Превышено бюджетов: \(exceeded.count).", uz: "Oshib ketgan byudjetlar: \(exceeded.count).", en: "Budgets exceeded: \(exceeded.count).")(language)
        let rows = statuses.map { status in
            AssistantAnswer.Row(id: status.id.uuidString,
                                title: status.budget.categoryID.map { categoryName($0) } ?? Phrase(ru: "Общий бюджет", uz: "Umumiy byudjet", en: "Overall")(language),
                                value: "\(compact(status.spent)) / \(compact(status.effectiveLimit))", detail: percent(status.progress),
                                share: min(status.progress, 1), categoryID: status.budget.categoryID, transactionID: nil,
                                tone: status.state == .exceeded ? .negative : .neutral)
        }
        return AssistantAnswer(intent: intent, headline: percent(statuses[0].progress), text: text, rows: rows, note: nil, hasData: true)
    }

    private func shortDate(_ date: Date) -> String {
        let components = analytics.periods.calendar.dateComponents([.day, .month], from: date)
        let day = components.day ?? 1
        let month = components.month ?? 1
        switch language {
        case .ru: return "\(day) \(MonthNames.name(month, language: .ru, form: .genitive))"
        case .uz: return "\(day)-\(MonthNames.name(month, language: .uz))"
        case .en: return "\(MonthNames.name(month, language: .en)) \(day)"
        }
    }
}
