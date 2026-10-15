import Foundation
import MonoCore

/// Поиск строки заголовка и предложение ролей колонок по названиям (RU/UZ/EN) и содержимому.
public enum ColumnDetector {
    private static let synonyms: [(ColumnRole, [String])] = [
        (.date, ["дата", "date", "sana", "день операции", "дата операции", "дата транзакции", "transaction date", "posting date", "operation date"]),
        (.time, ["время", "time", "vaqt"]),
        (.debit, ["расход", "дебет", "debit", "списан", "chiqim", "withdrawal", "outflow", "сумма списания"]),
        (.credit, ["приход", "кредит", "credit", "зачисл", "поступлен", "kirim", "deposit", "inflow", "сумма зачисления"]),
        (.amount, ["сумма", "amount", "summa", "miqdor", "сумма операции", "transaction amount"]),
        (.currency, ["валюта", "currency", "valyuta", "вал."]),
        (.direction, ["тип операции", "направление", "type", "turi", "вид операции"]),
        (.merchant, ["мерчант", "merchant", "получатель", "контрагент", "торговая точка", "магазин", "payee", "recipient", "qabul qiluvchi", "место"]),
        (.description, ["описание", "назначение", "детали", "комментарий", "description", "details", "narrative", "memo", "tavsif", "izoh", "наименование", "операция", "operation"]),
        (.category, ["категория", "category", "kategoriya"]),
        (.card, ["номер карты", "card number", "karta raqami", "номер счета", "account number", "hisob raqami"]),
        (.cardName, ["название карты", "card name", "karta nomi"]),
        (.status, ["состояние", "статус", "status", "holati"]),
        (.details, ["реквизиты", "requisites", "rekvizit"]),
        (.balance, ["остаток", "баланс", "balance", "qoldiq"])
    ]

    /// Роль по тексту заголовка.
    public static func role(forHeader header: String) -> ColumnRole? {
        let text = TextNormalizer.fold(header)
        guard !text.isEmpty else { return nil }
        // Более длинные синонимы проверяем первыми: «сумма списания» → списание, а не сумма.
        var best: (ColumnRole, Int)?
        for (role, words) in synonyms {
            for word in words where text.contains(word) {
                if best == nil || word.count > best!.1 { best = (role, word.count) }
            }
        }
        return best?.0
    }

    /// Предлагает сопоставление. Сначала ищет строку заголовка среди первых 25 строк, затем дополняет роли по содержимому.
    public static func suggestMapping(for table: ImportTable, calendar: Calendar) -> ColumnMapping {
        var headerRow: Int?
        var bestScore = 1
        for rowIndex in 0..<min(25, table.rows.count) {
            let roles = table.rows[rowIndex].compactMap { cell -> ColumnRole? in
                guard case .text(let text) = cell else { return nil }
                return role(forHeader: text)
            }
            let score = Set(roles).count
            if score > bestScore {
                bestScore = score
                headerRow = rowIndex
            }
        }

        var roles: [Int: ColumnRole] = [:]
        if let headerRow {
            var used = Set<ColumnRole>()
            for (column, cell) in table.rows[headerRow].enumerated() {
                guard case .text(let text) = cell, let role = role(forHeader: text) else { continue }
                if used.contains(role) && role != .description { continue }
                roles[column] = role
                used.insert(role)
            }
        }

        // По содержимому: даты и суммы, если по заголовкам не нашлись.
        let firstData = (headerRow ?? -1) + 1
        let sample = Array(table.rows.dropFirst(firstData).prefix(40))
        guard !sample.isEmpty else { return ColumnMapping(headerRow: headerRow, roles: roles) }
        let width = table.columnCount
        func ratio(_ column: Int, _ test: (CellValue) -> Bool) -> Double {
            let values = sample.map { column < $0.count ? $0[column] : .empty }.filter { !$0.isEmpty }
            guard !values.isEmpty else { return 0 }
            return Double(values.filter(test).count) / Double(values.count)
        }
        if !roles.values.contains(.date) {
            for column in 0..<width where roles[column] == nil {
                if ratio(column, { ValueParsers.date($0, calendar: calendar) != nil }) >= 0.7 {
                    roles[column] = .date
                    break
                }
            }
        }
        let hasAmount = roles.values.contains(.amount) || roles.values.contains(.debit) || roles.values.contains(.credit)
        if !hasAmount {
            var bestColumn: (Int, Double)?
            for column in 0..<width where roles[column] == nil {
                let numeric = ratio(column) { cell in
                    if case .date = cell { return false }
                    guard let value = ValueParsers.amount(cell) else { return false }
                    return value != 0
                }
                if numeric >= 0.7, bestColumn == nil || numeric > bestColumn!.1 { bestColumn = (column, numeric) }
            }
            if let bestColumn { roles[bestColumn.0] = .amount }
        }
        if !roles.values.contains(.description) {
            // Самая «текстовая» колонка — описание.
            var best: (Int, Int)?
            for column in 0..<width where roles[column] == nil {
                let length = sample.map { column < $0.count ? ($0[column].isEmpty ? 0 : $0[column].text.count) : 0 }.reduce(0, +)
                let numeric = ratio(column) { ValueParsers.amount($0) != nil }
                if numeric < 0.5, length > 0, best == nil || length > best!.1 { best = (column, length) }
            }
            if let best { roles[best.0] = .description }
        }
        return ColumnMapping(headerRow: headerRow, roles: roles)
    }

    /// Подпись набора заголовков — ключ для сохранённых профилей.
    public static func signature(for table: ImportTable, mapping: ColumnMapping) -> String {
        guard let headerRow = mapping.headerRow, headerRow < table.rows.count else {
            return "noheader:\(table.columnCount)"
        }
        return table.rows[headerRow].map { TextNormalizer.matchKey($0.text) }.joined(separator: "|")
    }
}
