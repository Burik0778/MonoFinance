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

    public var id: UUID
    public var rowIndex: Int
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
}

public struct SkippedRow: Equatable, Sendable {
    public enum Reason: String, Sendable {
        case noDate
        case noAmount
        case zeroAmount
        case otherCurrency
    }

    public var rowIndex: Int
    public var reason: Reason
}

public struct ImportPreview: Equatable, Sendable {
    public var candidates: [ImportCandidate]
    public var skipped: [SkippedRow]

    public var includedCount: Int { candidates.filter(\.include).count }
    public var duplicateCount: Int { candidates.filter { $0.duplicate != .none }.count }

    public func total(_ direction: ValueParsers.Direction) -> Money? {
        let items = candidates.filter { $0.include && $0.direction == direction }
        guard let currency = items.first?.amount.currency else { return nil }
        return Money.sum(items.map(\.amount), currency: currency)
    }
}

/// Превращает таблицу в операции: направление, категории, отпечатки, поиск дублей.
public struct ImportPipeline: Sendable {
    public let account: Account
    public let existing: [FinanceTransaction]
    public let existingFingerprints: Set<String>
    public let categorizer: CategorizationEngine
    public let calendar: Calendar

    public init(account: Account, existing: [FinanceTransaction], existingFingerprints: Set<String>, categorizer: CategorizationEngine, calendar: Calendar) {
        self.account = account
        self.existing = existing
        self.existingFingerprints = existingFingerprints
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
            if let currency = ValueParsers.currency(cell(.currency)), currency != account.currency {
                skipped.append(SkippedRow(rowIndex: rowIndex, reason: .otherCurrency))
                continue
            }
            let magnitude = value < 0 ? -value : value
            guard let money = Money(major: magnitude, currency: account.currency), money.isPositive else {
                skipped.append(SkippedRow(rowIndex: rowIndex, reason: .noAmount))
                continue
            }
            let direction: ValueParsers.Direction = value < 0 ? .outflow : .inflow

            // Описание и продавец
            let descriptionText = [cell(.description), cell(.merchant)].map(\.text).filter { !$0.isEmpty }.joined(separator: " · ")
            let merchantRaw = cell(.merchant).text.isEmpty ? cell(.description).text : cell(.merchant).text
            let merchant = merchantRaw.isEmpty ? nil : (CategorizationEngine.canonicalMerchantName(merchantRaw) ?? MerchantNormalizer.displayName(merchantRaw))
            let folded = TextNormalizer.fold(descriptionText)

            var kind: TransactionKind = direction == .outflow ? .expense : .income
            if direction == .outflow && (folded.contains("комисси") || folded.contains("komissiya") || folded.contains(" fee")) {
                kind = .fee
            } else if direction == .inflow && (folded.contains("возврат") || folded.contains("refund") || folded.contains("qaytar")) {
                kind = .refund
            }
            let categoryID = kind.usesCategory ? categorizer.suggest(merchant: merchant, text: descriptionText, kind: kind)?.categoryID : nil

            // Отпечаток: счёт, минута, сумма со знаком, описание + номер повтора внутри файла.
            let minuteKey = Self.minuteKey(date, calendar: calendar)
            let base = "\(account.id.uuidString.prefix(8))|\(minuteKey)|\(value < 0 ? "-" : "+")\(money.minorUnits)|\(String(TextNormalizer.matchKey(descriptionText).prefix(40)))"
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            let fingerprint = base + "#\(occurrence)"

            var duplicate = ImportCandidate.DuplicateStatus.none
            if existingFingerprints.contains(fingerprint) {
                duplicate = .alreadyImported
            } else if let match = possibleDuplicate(amount: money, direction: direction, date: date, claimed: candidates) {
                duplicate = .possible(existingID: match)
            }

            candidates.append(ImportCandidate(
                id: UUID(),
                rowIndex: rowIndex,
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
                possibleOwnTransferID: possibleOwnTransfer(amount: money, direction: direction, date: date)
            ))
        }
        guard !candidates.isEmpty else { throw ImportError.noDataRows }
        return ImportPreview(candidates: candidates, skipped: skipped)
    }

    /// Ручная или голосовая операция на том же счёте с той же суммой и направлением в пределах суток.
    private func possibleDuplicate(amount: Money, direction: ValueParsers.Direction, date: Date, claimed: [ImportCandidate]) -> UUID? {
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
    private func possibleOwnTransfer(amount: Money, direction: ValueParsers.Direction, date: Date) -> UUID? {
        existing.first { transaction in
            guard transaction.accountID != account.id, transaction.kind != .transfer,
                  transaction.amount.currency == amount.currency, transaction.amount.magnitude == amount else { return false }
            let otherIsInflow = transaction.kind == .income || transaction.kind == .refund
            guard otherIsInflow == (direction == .outflow) else { return false }
            return abs(transaction.date.timeIntervalSince(date)) <= 24 * 3600
        }?.id
    }

    static func minuteKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d%02d%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// Операции для записи (только отмеченные и не импортированные ранее).
    public func transactions(from candidates: [ImportCandidate], now: Date = Date()) -> [FinanceTransaction] {
        candidates.filter { $0.include && $0.duplicate != .alreadyImported }.map { candidate in
            FinanceTransaction(
                kind: candidate.kind,
                amount: candidate.amount,
                accountID: account.id,
                categoryID: candidate.kind.usesCategory ? candidate.categoryID : nil,
                merchant: candidate.merchant,
                note: candidate.description.isEmpty ? nil : candidate.description,
                date: candidate.date,
                createdAt: now,
                source: .importFile,
                importFingerprint: candidate.fingerprint
            )
        }
    }
}
