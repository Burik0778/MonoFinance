import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

/// Ошибки слоя SQLite.
public enum SQLiteError: Error, CustomStringConvertible, Equatable {
    case open(code: Int32, message: String)
    case prepare(code: Int32, message: String, sql: String)
    case step(code: Int32, message: String)
    case constraint(message: String)
    case bind(code: Int32)
    case migration(String)

    public var description: String {
        switch self {
        case .open(let code, let message): return "SQLite open \(code): \(message)"
        case .prepare(let code, let message, let sql): return "SQLite prepare \(code): \(message) — \(sql)"
        case .step(let code, let message): return "SQLite step \(code): \(message)"
        case .constraint(let message): return "SQLite constraint: \(message)"
        case .bind(let code): return "SQLite bind \(code)"
        case .migration(let message): return "Migration: \(message)"
        }
    }
}

/// Значение для привязки к параметру запроса.
public enum SQLValue: Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    static func uuid(_ value: UUID?) -> SQLValue { value.map { .text($0.uuidString) } ?? .null }
    static func date(_ value: Date?) -> SQLValue { value.map { .real($0.timeIntervalSince1970) } ?? .null }
    static func bool(_ value: Bool) -> SQLValue { .integer(value ? 1 : 0) }
    static func optionalText(_ value: String?) -> SQLValue { value.map { .text($0) } ?? .null }
    static func optionalInteger(_ value: Int64?) -> SQLValue { value.map { .integer($0) } ?? .null }
}

nonisolated(unsafe) private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Строка результата запроса.
struct SQLRow {
    let statement: OpaquePointer

    func isNull(_ index: Int32) -> Bool { sqlite3_column_type(statement, index) == SQLITE_NULL }
    func int64(_ index: Int32) -> Int64 { sqlite3_column_int64(statement, index) }
    func int(_ index: Int32) -> Int { Int(sqlite3_column_int64(statement, index)) }
    func double(_ index: Int32) -> Double { sqlite3_column_double(statement, index) }
    func bool(_ index: Int32) -> Bool { sqlite3_column_int64(statement, index) != 0 }

    func text(_ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    func optionalText(_ index: Int32) -> String? { isNull(index) ? nil : text(index) }
    func optionalInt64(_ index: Int32) -> Int64? { isNull(index) ? nil : int64(index) }
    func optionalDouble(_ index: Int32) -> Double? { isNull(index) ? nil : double(index) }
    func uuid(_ index: Int32) -> UUID? { UUID(uuidString: text(index)) }
    func optionalUUID(_ index: Int32) -> UUID? { isNull(index) ? nil : UUID(uuidString: text(index)) }
    func date(_ index: Int32) -> Date { Date(timeIntervalSince1970: double(index)) }
    func optionalDate(_ index: Int32) -> Date? { isNull(index) ? nil : date(index) }
}

/// Тонкая обёртка над соединением SQLite с явными транзакциями.
/// Не потокобезопасна: используется с одного актора (в приложении — с MainActor).
final class SQLiteConnection {
    private(set) var handle: OpaquePointer?
    private var transactionDepth = 0

    init(path: String) throws {
        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(path, &pointer, flags, nil)
        guard code == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close_v2(pointer)
            throw SQLiteError.open(code: code, message: message)
        }
        handle = pointer
        sqlite3_busy_timeout(pointer, 3_000)
        try execute("PRAGMA foreign_keys = ON;")
        if path != ":memory:" {
            try execute("PRAGMA journal_mode = WAL;")
            try execute("PRAGMA synchronous = NORMAL;")
        }
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    var lastErrorMessage: String {
        guard let handle else { return "closed" }
        return String(cString: sqlite3_errmsg(handle))
    }

    /// Выполняет один или несколько SQL-операторов без параметров.
    func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        if code != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorPointer)
            if code & 0xFF == SQLITE_CONSTRAINT { throw SQLiteError.constraint(message: message) }
            throw SQLiteError.step(code: code, message: message)
        }
    }

    private func prepare(_ sql: String, _ parameters: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else {
            throw SQLiteError.prepare(code: code, message: lastErrorMessage, sql: sql)
        }
        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .integer(let number):
                result = sqlite3_bind_int64(statement, index, number)
            case .real(let number):
                result = sqlite3_bind_double(statement, index, number)
            case .text(let string):
                result = sqlite3_bind_text(statement, index, string, -1, transientDestructor)
            case .blob(let data):
                result = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), transientDestructor)
                }
            }
            if result != SQLITE_OK {
                sqlite3_finalize(statement)
                throw SQLiteError.bind(code: result)
            }
        }
        return statement
    }

    /// Выполняет оператор изменения данных. Возвращает число затронутых строк.
    @discardableResult
    func run(_ sql: String, _ parameters: [SQLValue] = []) throws -> Int {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE || code == SQLITE_ROW else {
            if code & 0xFF == SQLITE_CONSTRAINT { throw SQLiteError.constraint(message: lastErrorMessage) }
            throw SQLiteError.step(code: code, message: lastErrorMessage)
        }
        return Int(sqlite3_changes(handle))
    }

    /// Выполняет запрос и преобразует строки.
    func query<T>(_ sql: String, _ parameters: [SQLValue] = [], _ transform: (SQLRow) throws -> T?) throws -> [T] {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        var result: [T] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW {
                if let value = try transform(SQLRow(statement: statement)) { result.append(value) }
            } else if code == SQLITE_DONE {
                break
            } else {
                throw SQLiteError.step(code: code, message: lastErrorMessage)
            }
        }
        return result
    }

    func scalarInt(_ sql: String, _ parameters: [SQLValue] = []) throws -> Int64? {
        try query(sql, parameters) { row in row.optionalInt64(0) }.first
    }

    /// Атомарный блок. Вложенные вызовы используют SAVEPOINT.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        let depth = transactionDepth
        let savepoint = "sp_\(depth)"
        if depth == 0 {
            try execute("BEGIN IMMEDIATE;")
        } else {
            try execute("SAVEPOINT \(savepoint);")
        }
        transactionDepth += 1
        do {
            let value = try body()
            transactionDepth -= 1
            if depth == 0 {
                try execute("COMMIT;")
            } else {
                try execute("RELEASE \(savepoint);")
            }
            return value
        } catch {
            transactionDepth -= 1
            if depth == 0 {
                try? execute("ROLLBACK;")
            } else {
                try? execute("ROLLBACK TO \(savepoint); RELEASE \(savepoint);")
            }
            throw error
        }
    }

    var userVersion: Int {
        get throws { Int(try scalarInt("PRAGMA user_version;") ?? 0) }
    }

    func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version);")
    }

    static var libraryVersion: String { String(cString: sqlite3_libversion()) }
}
