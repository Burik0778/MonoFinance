import Foundation
import MonoCore
import MonoStorage
import MonoImport

/// Ошибка для показа пользователю: понятный текст вместо технических деталей.
struct AppError: Error, Identifiable, Equatable {
    let id = UUID()
    let message: String

    init(_ message: String) {
        self.message = message
    }

    init(_ error: Error, language: AppLanguage = .current) {
        switch error {
        case let ledger as LedgerError:
            message = ledger.message(language)
        case let storage as StorageError:
            message = storage.message(language)
        case let importError as ImportError:
            message = importError.message(language)
        case let sqlite as SQLiteError:
            switch sqlite {
            case .constraint:
                message = Phrase(ru: "Такая запись уже есть или нарушает правила данных.", uz: "Bunday yozuv allaqachon mavjud.", en: "This record already exists or breaks data rules.")(language)
            default:
                message = Phrase(ru: "Ошибка базы данных. Данные не изменены.", uz: "Ma’lumotlar bazasi xatosi.", en: "Database error. Nothing was changed.")(language)
            }
        case let app as AppError:
            message = app.message
        default:
            message = error.localizedDescription
        }
    }

    static func == (lhs: AppError, rhs: AppError) -> Bool { lhs.id == rhs.id }
}
