//
//  SQLiteDB.swift
//  SwiftSQLiteReader
//
//  Zero-dependency read/introspect access to a SQLite database via the system
//  libsqlite3. Values are stringified for display.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation
import SQLite3

/// Lightweight access to a SQLite database via the system `libsqlite3`.
///
/// Opens read-write when possible and falls back to read-only. Row values are
/// stringified, making this ideal for *displaying* and *introspecting* a database
/// (schema, foreign keys, ad-hoc queries) rather than as a typed ORM.
///
/// ```swift
/// import SQLiteReader
///
/// guard let db = SQLiteDB(url: fileURL) else { return }
/// for table in db.tables() {
///     print(table, db.rowCount(table))
/// }
/// ```
public final class SQLiteDB {
    private var db: OpaquePointer?

    /// `true` when the database could only be opened read-only.
    public let readOnly: Bool

    /// Opens the database at `url`, read-write if possible, otherwise read-only.
    ///
    /// - Returns: `nil` if the file cannot be opened at all (e.g. it doesn't exist —
    ///   this initializer never *creates* a database).
    public init?(url: URL) {
        var handle: OpaquePointer?
        if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK {
            db = handle; readOnly = false
            // Retry briefly instead of failing instantly when another process holds a lock.
            sqlite3_busy_timeout(handle, 250)
            return
        }
        // A failed open still allocates a connection that must be closed before retrying.
        if let handle { sqlite3_close(handle) }
        handle = nil
        if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            db = handle; readOnly = true
            sqlite3_busy_timeout(handle, 250)
            return
        }
        if let handle { sqlite3_close(handle) }
        return nil
    }

    /// Builds an in-memory database by executing `sql`.
    ///
    /// Useful for visualizing a `schema.sql` (DDL text) without a real database file.
    /// Execution errors are tolerated so a partial schema still renders.
    public init?(sql: String) {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(":memory:", &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        db = handle
        readOnly = false
        var err: UnsafeMutablePointer<CChar>?
        sqlite3_exec(handle, sql, nil, nil, &err)
        if let err { sqlite3_free(err) }
    }

    deinit { if let db { sqlite3_close(db) } }

    /// Tables and views (user ones first; `sqlite_%` internals hidden), sorted by name.
    public func tables() -> [String] {
        let r = run("SELECT name FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY name")
        return r.rows.compactMap { $0.first }
    }

    /// The columns of `table`, via `PRAGMA table_info`.
    public func schema(_ table: String) -> [Column] {
        let r = run("PRAGMA table_info(\(quoteIdent(table)))")
        return r.rows.compactMap { row in
            guard row.count >= 6 else { return nil }
            return Column(name: row[1], type: row[2], pk: row[5] != "0", notNull: row[3] != "0")
        }
    }

    /// The number of rows in `table`.
    public func rowCount(_ table: String) -> Int {
        Int(run("SELECT COUNT(*) FROM \(quoteIdent(table))").rows.first?.first ?? "0") ?? 0
    }

    /// Foreign keys declared on `table` (via `PRAGMA foreign_key_list`).
    public func foreignKeys(_ table: String) -> [ForeignKey] {
        // columns: id, seq, table, from, to, on_update, on_delete, match
        // Read the pragma with a typed statement: an implicit PK reference (`REFERENCES parent`)
        // yields an actual SQL NULL "to", which must not be confused with a parent column
        // literally named "NULL" (the stringified `run()` result can't tell them apart).
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA foreign_key_list(\(quoteIdent(table)))", -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        var fks: [ForeignKey] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let toTable = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let from = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            let toColumn = sqlite3_column_type(stmt, 4) == SQLITE_NULL
                ? "" : (sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "")
            fks.append(ForeignKey(from: from, toTable: toTable, toColumn: toColumn))
        }
        return fks
    }

    /// Runs one SQL statement. Rows are capped at `limit` for display safety.
    ///
    /// - Returns: a ``Result`` with stringified rows, or an error message on failure.
    public func run(_ sql: String, limit: Int = 2000) -> Result {
        guard let db else { return Result(columns: [], rows: [], error: "No database", rowsAffected: 0) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return Result(columns: [], rows: [], error: String(cString: sqlite3_errmsg(db)), rowsAffected: 0)
        }
        defer { sqlite3_finalize(stmt) }

        let colCount = Int(sqlite3_column_count(stmt))
        var columns: [String] = []
        for i in 0..<colCount { columns.append(String(cString: sqlite3_column_name(stmt, Int32(i)))) }

        var rows: [[String]] = []
        var rc = sqlite3_step(stmt)
        while rc == SQLITE_ROW {
            var row: [String] = []
            for i in 0..<colCount {
                let c = Int32(i)
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_NULL:    row.append("NULL")
                case SQLITE_INTEGER: row.append(String(sqlite3_column_int64(stmt, c)))
                case SQLITE_FLOAT:   row.append(String(sqlite3_column_double(stmt, c)))
                case SQLITE_BLOB:    row.append("‹blob \(sqlite3_column_bytes(stmt, c))b›")
                default:             row.append(sqlite3_column_text(stmt, c).map { String(cString: $0) } ?? "")
                }
            }
            rows.append(row)
            if rows.count >= limit { break }
            rc = sqlite3_step(stmt)
        }
        // rc == SQLITE_ROW here means we stopped at the display limit; anything other than
        // SQLITE_DONE (BUSY, CORRUPT, runtime errors mid-iteration) must be surfaced, not
        // silently returned as a complete-looking result.
        let stepError = (rc == SQLITE_DONE || rc == SQLITE_ROW) ? nil : String(cString: sqlite3_errmsg(db))
        // sqlite3_changes reports the last write on the connection and is NOT reset by
        // read-only statements — only report it for statements that can actually write.
        let affected = sqlite3_stmt_readonly(stmt) != 0 ? 0 : Int(sqlite3_changes(db))
        return Result(columns: columns, rows: rows, error: stepError, rowsAffected: affected)
    }

    private func quoteIdent(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
}
