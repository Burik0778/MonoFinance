import Foundation
import MonoCore

/// Значение ячейки таблицы выписки.
public enum CellValue: Equatable, Sendable {
    case empty
    case text(String)
    case number(Decimal)
    case date(Date)
    case bool(Bool)

    /// Текстовое представление для показа и разбора.
    public var text: String {
        switch self {
        case .empty: return ""
        case .text(let value): return value
        case .number(let value): return "\(value)"
        case .date(let value): return ISO8601DateFormatter().string(from: value)
        case .bool(let value): return value ? "TRUE" : "FALSE"
        }
    }

    public var isEmpty: Bool {
        switch self {
        case .empty: return true
        case .text(let value): return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return false
        }
    }
}

public enum ImportFormat: String, Sendable, Codable {
    case csv
    case xlsx
}

/// Лист таблицы.
public struct ImportTable: Sendable, Equatable {
    public var name: String
    public var rows: [[CellValue]]

    public init(name: String, rows: [[CellValue]]) {
        self.name = name
        self.rows = rows
    }

    public var columnCount: Int { rows.map(\.count).max() ?? 0 }

    public func cell(_ row: Int, _ column: Int) -> CellValue {
        guard row < rows.count, column < rows[row].count else { return .empty }
        return rows[row][column]
    }
}

/// Прочитанный файл выписки.
public struct ImportDocument: Sendable, Equatable {
    public var format: ImportFormat
    public var tables: [ImportTable]
}

public enum ImportError: Error, Equatable, Sendable {
    case unsupportedFormat
    case emptyFile
    case unreadableText
    case corruptArchive
    case noSheets
    case invalidXML
    case noDataRows
    case mappingIncomplete

    public func message(_ language: AppLanguage) -> String {
        switch self {
        case .unsupportedFormat:
            return Phrase(ru: "Поддерживаются файлы CSV и XLSX.", uz: "CSV va XLSX fayllari qo‘llab-quvvatlanadi.", en: "CSV and XLSX files are supported.")(language)
        case .emptyFile:
            return Phrase(ru: "Файл пустой.", uz: "Fayl bo‘sh.", en: "The file is empty.")(language)
        case .unreadableText:
            return Phrase(ru: "Не удалось определить кодировку текста.", uz: "Matn kodirovkasi aniqlanmadi.", en: "Couldn't detect the text encoding.")(language)
        case .corruptArchive:
            return Phrase(ru: "Файл XLSX повреждён или зашифрован.", uz: "XLSX fayli buzilgan yoki shifrlangan.", en: "The XLSX file is damaged or encrypted.")(language)
        case .noSheets:
            return Phrase(ru: "В книге нет листов с данными.", uz: "Kitobda ma’lumotli varaqlar yo‘q.", en: "The workbook has no sheets.")(language)
        case .invalidXML:
            return Phrase(ru: "Не удалось прочитать содержимое листа.", uz: "Varaq mazmunini o‘qib bo‘lmadi.", en: "Couldn't read the sheet contents.")(language)
        case .noDataRows:
            return Phrase(ru: "Не найдено строк с операциями.", uz: "Operatsiyali qatorlar topilmadi.", en: "No transaction rows found.")(language)
        case .mappingIncomplete:
            return Phrase(ru: "Укажите колонки даты и суммы.", uz: "Sana va summa ustunlarini belgilang.", en: "Choose the date and amount columns.")(language)
        }
    }
}

/// Роль колонки при сопоставлении.
public enum ColumnRole: String, Codable, Sendable, CaseIterable, Identifiable {
    case date
    case time
    case amount
    case debit
    case credit
    case direction
    case currency
    case description
    case merchant
    case category
    case balance
    case ignore

    public var id: String { rawValue }

    public var title: Phrase {
        switch self {
        case .date: return Phrase(ru: "Дата", uz: "Sana", en: "Date")
        case .time: return Phrase(ru: "Время", uz: "Vaqt", en: "Time")
        case .amount: return Phrase(ru: "Сумма (±)", uz: "Summa (±)", en: "Amount (±)")
        case .debit: return Phrase(ru: "Списание", uz: "Chiqim", en: "Debit")
        case .credit: return Phrase(ru: "Зачисление", uz: "Kirim", en: "Credit")
        case .direction: return Phrase(ru: "Тип операции", uz: "Operatsiya turi", en: "Direction")
        case .currency: return Phrase(ru: "Валюта", uz: "Valyuta", en: "Currency")
        case .description: return Phrase(ru: "Описание", uz: "Tavsif", en: "Description")
        case .merchant: return Phrase(ru: "Получатель / магазин", uz: "Qabul qiluvchi", en: "Merchant")
        case .category: return Phrase(ru: "Категория", uz: "Kategoriya", en: "Category")
        case .balance: return Phrase(ru: "Остаток (не импортируется)", uz: "Qoldiq", en: "Balance (ignored)")
        case .ignore: return Phrase(ru: "Не использовать", uz: "Ishlatilmasin", en: "Ignore")
        }
    }
}

/// Как трактовать знак в колонке «Сумма».
public enum AmountSignConvention: String, Codable, Sendable {
    /// Отрицательные — списания (по умолчанию).
    case negativeIsOutflow
    /// Положительные — списания (некоторые выписки по картам).
    case positiveIsOutflow
}

/// Сопоставление колонок таблицы.
public struct ColumnMapping: Codable, Equatable, Sendable {
    /// Строка заголовка (`nil` — заголовка нет).
    public var headerRow: Int?
    public var roles: [Int: ColumnRole]
    public var signConvention: AmountSignConvention

    public init(headerRow: Int?, roles: [Int: ColumnRole], signConvention: AmountSignConvention = .negativeIsOutflow) {
        self.headerRow = headerRow
        self.roles = roles
        self.signConvention = signConvention
    }

    public func column(_ role: ColumnRole) -> Int? {
        roles.filter { $0.value == role }.map(\.key).min()
    }

    public var firstDataRow: Int { (headerRow ?? -1) + 1 }

    /// Достаточно ли сопоставления для импорта: дата и сумма (или пара списание/зачисление).
    public var isComplete: Bool {
        column(.date) != nil && (column(.amount) != nil || column(.debit) != nil || column(.credit) != nil)
    }
}

/// Сохранённый профиль сопоставления: при следующем импорте файла с теми же заголовками применяется автоматически.
public struct ImportProfile: Codable, Equatable, Sendable {
    public var signature: String
    public var name: String
    public var mapping: ColumnMapping
    public var accountID: UUID?

    public init(signature: String, name: String, mapping: ColumnMapping, accountID: UUID?) {
        self.signature = signature
        self.name = name
        self.mapping = mapping
        self.accountID = accountID
    }

    public func encodedPayload() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    public static func decode(payload: String) -> ImportProfile? {
        try? JSONDecoder().decode(ImportProfile.self, from: Data(payload.utf8))
    }
}
