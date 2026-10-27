//
//  Statement.swift
//  SQLiteReader
//
//  Created by David Sherlock on 2026.
//
//  Moving values in and out of a prepared statement.
//

import Foundation
import SQLite3

enum Statement {

    /// SQLite's "copy this now" destructor.
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Binds a value to a placeholder.
    static func bind(_ value: SQLiteValue, at index: Int32, in statement: OpaquePointer) {
        switch value {
        case .null: sqlite3_bind_null(statement, index)
        case .integer(let number): sqlite3_bind_int64(statement, index, number)
        case .real(let number): sqlite3_bind_double(statement, index, number)
        case .text(let text): sqlite3_bind_text(statement, index, text, -1, transient)
        case .blob(let data): _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
        }
    }

    /// The column names of a statement.
    static func names(_ statement: OpaquePointer) -> [String] {
        (0..<sqlite3_column_count(statement)).map { sqlite3_column_name(statement, $0).map { String(cString: $0) } ?? "" }
    }

    /// The current row's values.
    static func values(_ statement: OpaquePointer) -> [SQLiteValue] {
        (0..<sqlite3_column_count(statement)).map { index in
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, index))
            case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, index))
            case SQLITE_TEXT: return .text(sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "")
            case SQLITE_BLOB:
                let count = Int(sqlite3_column_bytes(statement, index))
                guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return .blob(Data()) }
                return .blob(Data(bytes: bytes, count: count))
            default: return .null
            }
        }
    }

    /// A name quoted for SQL.
    static func quoted(_ name: String) -> String { "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
}
