import Foundation
import MonoCore
import MonoIntelligence

/// Чтение файла: формат определяется по сигнатуре, а не только по расширению.
public enum ImportReader {
    public static func read(data: Data, fileName: String) throws -> ImportDocument {
        guard !data.isEmpty else { throw ImportError.emptyFile }
        let lower = fileName.lowercased()
        let isZip = data.count > 4 && data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4B
        if isZip {
            return ImportDocument(format: .xlsx, tables: try XLSXReader.read(data))
        }
        if lower.hasSuffix(".xls") {
            // Старый двоичный формат Excel 97–2003 не поддерживается.
            throw ImportError.unsupportedFormat
        }
        return ImportDocument(format: .csv, tables: [try CSVReader.read(data)])
    }
}

/// Строка выписки, готовая к импорту.
public struct ImportCandidate: Identifiable, Equatable, Sendable {
    public enum DuplicateStatus: Equatable, Sendable {
        case none
        /// Уже импортирована ранее (совпал отпечаток) — будет пропущена.
        case alreadyImported
        /// Похожа на существующую операцию (вероятно, внесённую вручную или голосом).
        case possible(existingID: UUID)
    }

    /// Перевод между своими счетами, собранный из пары строк выписки: списание + зачисление.
    public struct OwnTransfer: Equatable, Sendable {
        /// Строка зачисления, вошедшая в перевод.
        public var inflowID: UUID
        public var destinationAccountID: UUID
        /// Сколько пришло на счёт-получатель.
        public var received: Money
        /// Разница между списанием и зачислением — комиссия за перевод.
        public var fee: Money?
        /// Пара подтверждена реквизитами (в строке указана карта получателя или отправителя).
        public var confirmedByDetails: Bool
    }

    public var id: UUID
    public var rowIndex: Int
    /// Счёт строки: выбранный для файла или сопоставленный с картой из выписки.
    public var accountID: UUID
    public var date: Date
    public var amount: Money
    public var direction: ValueParsers.Direction
    public var kind: TransactionKind
    public var description: String
    public var merchant: String?
    public var categoryID: UUID?
    public var fingerprint: String
    public var duplicate: DuplicateStatus
    public var include: Bool
    /// Похоже на перевод между своими счетами (та же сумма противоположного знака на другом счёте).
    public var possibleOwnTransferID: UUID?
    /// Карта строки (выписка сразу по нескольким картам).
    public var card: CardKey? = nil
    /// Карта получателя или отправителя из реквизитов.
    public var counterpartCard: CardKey? = nil
    /// Категория из самой выписки («перевод», «такси»).
    public var statementCategory: String? = nil
    /// Списание, объединённое с зачислением в перевод между своими счетами.
    public var ownTransfer: OwnTransfer? = nil
    /// Зачисление, вошедшее в перевод: показывается и записывается вместе со списанием.
    public var mergedInto: UUID? = nil

    public var isTransfer: Bool { ownTransfer != nil }
    public var isVisible: Bool { mergedInto == nil }
}

public struct SkippedRow: Equatable, Sendable {
    public enum Reason: String, Sendable {
        case noDate
        case noAmount
        case zeroAmount
        case otherCurrency
        /// Платёж отменён или ещё не проведён.
        case notCompleted
        /// Карта из выписки не сопоставлена ни с одним счётом.
        case unassignedCard
    }

    public var rowIndex: Int
    public var reason: Reason
}

public struct ImportPreview: Equatable, Sendable {
    public var candidates: [ImportCandidate]
    public var skipped: [SkippedRow]

    /// Строки для списка: зачисления внутри переводов скрыты.
    public var visibleCandidates: [ImportCandidate] { candidates.filter(\.isVisible) }
    public var includedCount: Int { candidates.filter { $0.isVisible && $0.include }.count }
    public var duplicateCount: Int { candidates.filter { $0.isVisible && $0.duplicate != .none }.count }
    /// Переводы между своими счетами — не расходы и не доходы.
    public var transferCount: Int { candidates.filter { $0.include && $0.isTransfer }.count }

    /// Комиссии за отмеченные переводы.
    public var feeTotal: Money? {
        let fees = candidates.filter { $0.include }.compactMap { $0.ownTransfer?.fee }
        guard let currency = fees.first?.currency else { return nil }
        return Money.sum(fees, currency: currency)
    }

    /// Списания или поступления без переводов между своими счетами.
    public func total(_ direction: ValueParsers.Direction) -> Money? {
        let items = candidates.filter { $0.include && $0.isVisible && !$0.isTransfer && $0.direction == direction }
        guard let currency = items.first?.amount.currency else { return nil }
        return Money.sum(items.map(\.amount), currency: currency)
    }

    /// «Это не перевод»: возвращает пару обратно в отдельные списание и зачисление.
    public mutating func splitTransfer(_ id: UUID) {
        guard let index = candidates.firstIndex(where: { $0.id == id }), let transfer = candidates[index].ownTransfer else { return }
        candidates[index].ownTransfer = nil
        if let inflow = candidates.firstIndex(where: { $0.id == transfer.inflowID }) {
            candidates[inflow].mergedInto = nil
            candidates[inflow].include = candidates[inflow].duplicate == .none
        }
    }
}

/// Превращает таблицу в операции: направление, категории, отпечатки, поиск дублей и переводов между своими счетами.
public struct ImportPipeline: Sendable {
    /// Счёт файла (если в выписке нет колонки с номером карты).
    public let account: Account
    /// Ключ карты из выписки (`StatementCard.id`) → счёт.
    public let cardAccounts: [String: Account]
    public let existing: [FinanceTransaction]
    public let existingFingerprints: Set<String>
    public let categorizer: CategorizationEngine
    public let calendar: Calendar

    /// Разделитель отпечатков двух строк, из которых собран перевод.
    static let pairSeparator = " ⇄ "
    /// Списание и зачисление перевода — не дальше трёх минут друг от друга.
    static let pairingWindow: TimeInterval = 180
    /// Комиссия за перевод — не больше 2% суммы списания (1/50).
    static let maxFeeDivisor: Int64 = 50

    public init(account: Account, cardAccounts: [String: Account] = [:], existing: [FinanceTransaction],
                existingFingerprints: Set<String>, categorizer: CategorizationEngine, calendar: Calendar) {
        self.account = account
        self.cardAccounts = cardAccounts
        self.existing = existing
        // Перевод хранит отпечатки обеих строк — повторный импорт узнаёт каждую из них.
        self.existingFingerprints = Set(existingFingerprints.flatMap { $0.components(separatedBy: Self.pairSeparator) })
        self.categorizer = categorizer
        self.calendar = calendar
    }

    public func preview(table: ImportTable, mapping: ColumnMapping) throws -> ImportPreview {
        guard mapping.isComplete else { throw ImportError.mappingIncomplete }
        var candidates: [ImportCandidate] = []
        var skipped: [SkippedRow] = []
        var occurrences: [String: Int] = [:]

        for rowIndex in mapping.firstDataRow..<table.rows.count {
            let cell = { (role: ColumnRole) -> CellValue in
                guard let column = mapping.column(role) else { return .empty }
                return table.cell(rowIndex, column)
            }
            let rowCells = table.rows[rowIndex]
            if rowCells.allSatisfy(\.isEmpty) { continue }

            guard let date = ValueParsers.date(cell(.date), time: mapping.column(.time) != nil ? cell(.time) : nil, calendar: calendar) else {
                // Итоговые строки и подписи внутри таблицы не считаем ошибкой, если в них нет суммы.
                skipped.append(SkippedRow(rowIndex: rowIndex, reason: .noDate))
                continue
            }
            if mapping.column(.status) != nil, !ValueParsers.isCompleted(cell(.status)) {
                skipped.append(SkippedRow(rowIndex: rowIndex, reason: .notCompleted))
                continue
            }

            // Счёт строки: по номеру карты (выписка по нескольким картам) или счёт файла.
            var rowAccount = account
            var card: CardKey?
            if mapping.column(.card) != nil {
                let number = cell(.card).text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let assigned = cardAccounts[StatementCard.key(for: number)] else {
                    skipped.append(SkippedRow(rowIndex: rowIndex, reason: .unassignedCard))
                    continue
                }
                rowAccount = assigned
                card = CardKey(number)
            }

            // Сумма и направление
            var signed: Decimal?
            if mapping.column(.debit) != nil || mapping.column(.credit) != nil {
                let debit = ValueParsers.amount(cell(.debit)).map { $0 < 0 ? -$0 : $0 } ?? 0
                let credit = ValueParsers.amount(cell(.credit)).map { $0 < 0 ? -$0 : $0 } ?? 0
                if debit != 0 { signed = -debit } else if credit != 0 { signed = credit }
                if signed == nil, let amount = ValueParsers.amount(cell(.amount)) { signed = amount }
            } else if let amount = ValueParsers.amount(cell(.amount)) {
                signed = mapping.signConvention == .negativeIsOutflow ? amount : -amount
            }
            if let explicit = ValueParsers.direction(cell(.direction)), let value = signed {
                let magnitude = value < 0 ? -value : value
                signed = explicit == .outflow ? -magnitude : magnitude
            }
            guard let value = signed else {
                skipped.append(SkippedRow(rowIndex: rowIndex, reason: .noAmount))
                continue
            }
            guard value != 0 else {
                skipped.append(SkippedRow(rowIndex: rowIndex, reason: .zeroAmount))
                continue
            }
            if let currency = ValueParsers.currency(cell(.currency)), currency != rowAccount.currency {
                skipped.append(SkippedRow(rowIndex: rowIndex, reason: .otherCurrency))
                continue
            }
            let magnitude = value < 0 ? -value : value
            guard let money = Money(major: magnitude, currency: rowAccount.currency), money.isPositive else {
                skipped.append(SkippedRow(rowIndex: rowIndex, reason: .noAmount))
                continue
            }
            let direction: ValueParsers.Direction = value < 0 ? .outflow : .inflow

            // Описание и продавец
            let descriptionText = [cell(.description), cell(.merchant)].map(\.text).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: " · ")
            let merchantRaw = cell(.merchant).text.isEmpty ? cell(.description).text : cell(.merchant).text
            let merchant = merchantRaw.isEmpty ? nil : (CategorizationEngine.canonicalMerchantName(merchantRaw) ?? MerchantNormalizer.displayName(merchantRaw))
            let folded = TextNormalizer.fold(descriptionText)
            let statementCategory = cell(.category).text.trimmingCharacters(in: .whitespacesAndNewlines)

            var kind: TransactionKind = direction == .outflow ? .expense : .income
            if direction == .outflow && (folded.contains("комисси") || folded.contains("komissiya") || folded.contains(" fee")) {
                kind = .fee
            } else if direction == .inflow && (folded.contains("возврат") || folded.contains("refund") || folded.contains("qaytar")) {
                kind = .refund
            }
            // Категория выписки («такси», «продукты») — подсказка для категоризации.
            let hint = [descriptionText, statementCategory].filter { !$0.isEmpty }.joined(separator: " ")
            let categoryID = kind.usesCategory ? categorizer.suggest(merchant: merchant, text: hint, kind: kind)?.categoryID : nil

            // Отпечаток: счёт, минута, сумма со знаком, описание + номер повтора внутри файла.
            let minuteKey = Self.minuteKey(date, calendar: calendar)
            let base = "\(rowAccount.id.uuidString.prefix(8))|\(minuteKey)|\(value < 0 ? "-" : "+")\(money.minorUnits)|\(String(TextNormalizer.matchKey(descriptionText).prefix(40)))"
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            let fingerprint = base + "#\(occurrence)"

            var duplicate = ImportCandidate.DuplicateStatus.none
            if existingFingerprints.contains(fingerprint) {
                duplicate = .alreadyImported
            } else if let match = possibleDuplicate(account: rowAccount, amount: money, direction: direction, date: date, claimed: candidates) {
                duplicate = .possible(existingID: match)
            }

            candidates.append(ImportCandidate(
                id: UUID(),
                rowIndex: rowIndex,
                accountID: rowAccount.id,
                date: date,
                amount: money,
                direction: direction,
                kind: kind,
                description: descriptionText,
                merchant: merchant,
                categoryID: categoryID,
                fingerprint: fingerprint,
                duplicate: duplicate,
                include: duplicate == .none,
                possibleOwnTransferID: possibleOwnTransfer(account: rowAccount, amount: money, direction: direction, date: date),
                card: card,
                counterpartCard: mapping.column(.details) != nil ? CardKey(cell(.details).text) : nil,
                statementCategory: statementCategory.isEmpty ? nil : statementCategory
            ))
        }
        guard !candidates.isEmpty else { throw ImportError.noDataRows }
        Self.pairOwnTransfers(&candidates)
        return ImportPreview(candidates: candidates, skipped: skipped)
    }

    /// Ручная или голосовая операция на том же счёте с той же суммой и направлением в пределах суток.
    private func possibleDuplicate(account: Account, amount: Money, direction: ValueParsers.Direction, date: Date, claimed: [ImportCandidate]) -> UUID? {
        let alreadyMatched = Set(claimed.compactMap { candidate -> UUID? in
            if case .possible(let id) = candidate.duplicate { return id }
            return nil
        })
        return existing.first { transaction in
            guard transaction.accountID == account.id, transaction.importFingerprint == nil,
                  !alreadyMatched.contains(transaction.id), transaction.amount == amount else { return false }
            let outflow = transaction.kind == .expense || transaction.kind == .fee || transaction.kind == .transfer
            guard outflow == (direction == .outflow) else { return false }
            return abs(transaction.date.timeIntervalSince(date)) <= 36 * 3600
        }?.id
    }

    /// Та же сумма с противоположным направлением на другом своём счёте в пределах суток — вероятно, перевод.
    private func possibleOwnTransfer(account: Account, amount: Money, direction: ValueParsers.Direction, date: Date) -> UUID? {
        existing.first { transaction in
            guard transaction.accountID != account.id, transaction.kind != .transfer,
                  transaction.amount.currency == amount.currency, transaction.amount.magnitude == amount else { return false }
            let otherIsInflow = transaction.kind == .income || transaction.kind == .refund
            guard otherIsInflow == (direction == .outflow) else { return false }
            return abs(transaction.date.timeIntervalSince(date)) <= 24 * 3600
        }?.id
    }

    // MARK: - Переводы между своими счетами

    /// Категории выписки, при которых строка может быть переводом (покупка в магазине или такси — не может).
    private static let transferCategories = ["перевод", "конверт", "прочее", "кредит", "вклад", "депозит", "другое",
                                             "transfer", "other", "o'tkazma", "otkazma", "boshqa"]
    private static let transferWords = ["перевод", "конверт", "пополнен", "transfer", "p2p", "o'tkazma", "otkazma", "card to card", " 2 ", " to "]

    static func isTransferLike(_ candidate: ImportCandidate) -> Bool {
        if let category = candidate.statementCategory.map(TextNormalizer.fold), !category.isEmpty {
            return transferCategories.contains { category.hasPrefix($0) }
        }
        let text = " " + TextNormalizer.fold(candidate.description) + " "
        return transferWords.contains { text.contains($0) }
    }

    /// В реквизитах одной строки указана карта другой.
    static func references(_ outflow: ImportCandidate, _ inflow: ImportCandidate) -> Bool {
        if let card = inflow.card, let counterpart = outflow.counterpartCard, counterpart.matches(card) { return true }
        if let card = outflow.card, let counterpart = inflow.counterpartCard, counterpart.matches(card) { return true }
        return false
    }

    /// Склеивает списание с одного своего счёта и зачисление на другой в один перевод.
    ///
    /// Пара: разные счета, одна валюта, не дальше трёх минут, зачислено не больше списанного, разница (комиссия) ≤ 2%.
    /// Сначала пары, подтверждённые реквизитами (карта получателя / отправителя), затем — строки, похожие на перевод
    /// по категории или описанию. Из нескольких подходящих выбирается ближайшая по времени.
    static func pairOwnTransfers(_ candidates: inout [ImportCandidate]) {
        let outflows = candidates.indices.filter {
            candidates[$0].direction == .outflow && candidates[$0].kind != .fee && candidates[$0].duplicate == .none
        }
        let inflows = candidates.indices.filter {
            candidates[$0].direction == .inflow && candidates[$0].kind != .refund && candidates[$0].duplicate == .none
        }.sorted { candidates[$0].date < candidates[$1].date }
        guard !outflows.isEmpty, !inflows.isEmpty else { return }
        let inflowDates = inflows.map { candidates[$0].date }
        var used = Set<Int>()

        for confirmed in [true, false] {
            for outflowIndex in outflows where candidates[outflowIndex].ownTransfer == nil {
                let source = candidates[outflowIndex]
                // Первое зачисление не раньше начала окна (двоичный поиск по отсортированным датам).
                var low = 0
                var high = inflowDates.count
                let windowStart = source.date.addingTimeInterval(-pairingWindow)
                while low < high {
                    let middle = (low + high) / 2
                    if inflowDates[middle] < windowStart { low = middle + 1 } else { high = middle }
                }
                var best: (index: Int, gap: TimeInterval)?
                var position = low
                while position < inflows.count, inflowDates[position].timeIntervalSince(source.date) <= pairingWindow {
                    let inflowIndex = inflows[position]
                    position += 1
                    guard !used.contains(inflowIndex) else { continue }
                    let target = candidates[inflowIndex]
                    guard target.accountID != source.accountID, target.amount.currency == source.amount.currency else { continue }
                    let fee = source.amount.minorUnits - target.amount.minorUnits
                    guard fee >= 0, fee * maxFeeDivisor <= source.amount.minorUnits else { continue }
                    if confirmed {
                        guard references(source, target) else { continue }
                    } else {
                        guard isTransferLike(source), isTransferLike(target) else { continue }
                    }
                    let gap = abs(target.date.timeIntervalSince(source.date))
                    if best == nil || gap < best!.gap { best = (inflowIndex, gap) }
                }
                guard let best else { continue }
                let target = candidates[best.index]
                let feeUnits = source.amount.minorUnits - target.amount.minorUnits
                candidates[outflowIndex].ownTransfer = ImportCandidate.OwnTransfer(
                    inflowID: target.id,
                    destinationAccountID: target.accountID,
                    received: target.amount,
                    fee: feeUnits > 0 ? Money(minorUnits: feeUnits, currency: source.amount.currency) : nil,
                    confirmedByDetails: confirmed
                )
                candidates[outflowIndex].possibleOwnTransferID = nil
                candidates[best.index].mergedInto = source.id
                candidates[best.index].possibleOwnTransferID = nil
                used.insert(best.index)
            }
        }
    }

    static func minuteKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d%02d%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// Операции для записи (только отмеченные и не импортированные ранее).
    /// Пара «списание + зачисление» записывается одним переводом и отдельной комиссией, связанной с ним.
    public func transactions(from candidates: [ImportCandidate], now: Date = Date()) -> [FinanceTransaction] {
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [FinanceTransaction] = []
        for candidate in candidates where candidate.include && candidate.duplicate != .alreadyImported && candidate.isVisible {
            if let transfer = candidate.ownTransfer, let inflow = byID[transfer.inflowID] {
                let transferID = UUID()
                result.append(FinanceTransaction(
                    id: transferID,
                    kind: .transfer,
                    amount: transfer.received,
                    accountID: candidate.accountID,
                    counterAccountID: transfer.destinationAccountID,
                    counterAmount: transfer.received,
                    note: candidate.description.isEmpty ? nil : candidate.description,
                    date: candidate.date,
                    createdAt: now,
                    source: .importFile,
                    importFingerprint: candidate.fingerprint + Self.pairSeparator + inflow.fingerprint
                ))
                if let fee = transfer.fee {
                    result.append(FinanceTransaction(
                        kind: .fee,
                        amount: fee,
                        accountID: candidate.accountID,
                        date: candidate.date,
                        createdAt: now,
                        source: .importFile,
                        importFingerprint: "fee:" + candidate.fingerprint,
                        linkedTransactionID: transferID
                    ))
                }
                continue
            }
            result.append(FinanceTransaction(
                kind: candidate.kind,
                amount: candidate.amount,
                accountID: candidate.accountID,
                categoryID: candidate.kind.usesCategory ? candidate.categoryID : nil,
                merchant: candidate.merchant,
                note: candidate.description.isEmpty ? nil : candidate.description,
                date: candidate.date,
                createdAt: now,
                source: .importFile,
                importFingerprint: candidate.fingerprint
            ))
        }
        return result
    }
}
