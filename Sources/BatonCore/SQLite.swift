import Foundation
import SQLite3

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A minimal SQLite handle for Claude's Chromium cookie database.
final class SQLite {
    private let db: OpaquePointer

    init(_ url: URL, write: Bool, create: Bool = false) throws {
        var handle: OpaquePointer?
        var flags = (write ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY) | SQLITE_OPEN_NOMUTEX
        if create { flags |= SQLITE_OPEN_CREATE }
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            if handle != nil { sqlite3_close(handle) }
            throw BatonError("Claude's cookie database could not be opened.")
        }
        sqlite3_busy_timeout(handle, 2000)
        db = handle
    }

    deinit { sqlite3_close(db) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw BatonError("Claude's cookie database refused a change (\(String(cString: sqlite3_errmsg(db)))).")
        }
    }

    func rows(_ sql: String) throws -> [CookieRow] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BatonError("Claude's cookie database has an unexpected format.")
        }
        defer { sqlite3_finalize(statement) }
        var rows: [CookieRow] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            var row: CookieRow = [:]
            for i in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, i))
                switch sqlite3_column_type(statement, i) {
                case SQLITE_INTEGER: row[name] = .integer(String(sqlite3_column_int64(statement, i)))
                case SQLITE_FLOAT: row[name] = .real(String(sqlite3_column_double(statement, i)))
                case SQLITE_TEXT: row[name] = .text(String(cString: sqlite3_column_text(statement, i)))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, i))
                    row[name] = .blob(count == 0 ? Data() : Data(bytes: sqlite3_column_blob(statement, i), count: count))
                default: row[name] = .null
                }
            }
            rows.append(row)
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw BatonError("Claude's cookie database is busy. Try again.") }
        return rows
    }

    func schemaVersion() throws -> Int {
        guard let value = try rows("SELECT value FROM meta WHERE key='version'").first?["value"],
              let version = Int(value.text ?? { if case .integer(let v) = value { return v }; return "" }()) else {
            throw BatonError("Claude's cookie database has no version.")
        }
        return version
    }

    func insert(into table: String, _ row: CookieRow) throws {
        let names = row.keys.sorted()
        let sql = "INSERT INTO \(table) (\(names.map { "\"\($0)\"" }.joined(separator: ","))) VALUES (\(names.map { _ in "?" }.joined(separator: ",")))"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BatonError("A saved sign-in cookie could not be written.")
        }
        defer { sqlite3_finalize(statement) }
        for (index, name) in names.enumerated() {
            let position = Int32(index + 1)
            switch row[name]! {
            case .integer(let v): sqlite3_bind_int64(statement, position, Int64(v) ?? 0)
            case .real(let v): sqlite3_bind_double(statement, position, Double(v) ?? 0)
            case .text(let v): sqlite3_bind_text(statement, position, v, -1, transient)
            case .blob(let v): _ = v.withUnsafeBytes { sqlite3_bind_blob(statement, position, $0.baseAddress, Int32(v.count), transient) }
            case .null: sqlite3_bind_null(statement, position)
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw BatonError("A saved sign-in cookie could not be written.") }
    }

    /// Runs `body` in one immediate transaction; any failure leaves the database as it was.
    func transaction(_ body: () throws -> Void) throws {
        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
            throw BatonError("Claude's cookie database is busy. Nothing was changed.")
        }
        do {
            try body()
            try execute("COMMIT")
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }
}
