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
    /// - Note: Blocking — executes synchronously on the calling thread. Runs *any* SQL,
    ///   including writes, when the database was opened read-write (check ``readOnly``).
    ///   Values must be baked into the SQL text; for anything carrying user-supplied
    ///   values, use ``execute(_:parameters:limit:)`` instead.
    public func run(_ sql: String, limit: Int = 2000) -> Result {
        guard let db else { return Result(columns: [], rows: [], error: "No database", rowsAffected: 0) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return Result(columns: [], rows: [], error: String(cString: sqlite3_errmsg(db)), rowsAffected: 0)
        }
        defer { sqlite3_finalize(stmt) }
        return collect(stmt!, on: db, limit: limit)
    }

    /// Runs one *parameterized* SQL statement, binding `parameters` positionally
    /// (`?` placeholders, 1-based under the hood) with the proper `sqlite3_bind_*`
    /// call per ``Value`` case — values are never interpolated into the SQL text.
    ///
    /// ```swift
    /// db.execute("UPDATE \(SQLiteDB.quoteIdentifier(table)) SET name = ? WHERE rowid = ?",
    ///            parameters: [.text("Ada"), .integer(3)])
    /// ```
    ///
    /// - Parameter parameters: one entry per placeholder; `nil` binds SQL `NULL`.
    ///   A count mismatch against the statement's placeholders is an error (the
    ///   statement is not executed).
    /// - Returns: a ``Result`` exactly like ``run(_:limit:)`` — parameterized
    ///   SELECTs return rows; writes report ``Result/rowsAffected``.
    /// - Note: Blocking — executes synchronously on the calling thread.
    @discardableResult
    public func execute(_ sql: String, parameters: [Value?] = [], limit: Int = 2000) -> Result {
        guard let db else { return Result(columns: [], rows: [], error: "No database", rowsAffected: 0) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return Result(columns: [], rows: [], error: String(cString: sqlite3_errmsg(db)), rowsAffected: 0)
        }
        defer { sqlite3_finalize(stmt) }

        let expected = Int(sqlite3_bind_parameter_count(stmt))
        guard parameters.count == expected else {
            return Result(columns: [], rows: [],
                          error: "SQL expects \(expected) parameter\(expected == 1 ? "" : "s") but \(parameters.count) provided",
                          rowsAffected: 0)
        }
        for (i, p) in parameters.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch p {
            case .none:
                rc = sqlite3_bind_null(stmt, idx)
            case .some(.integer(let v)):
                rc = sqlite3_bind_int64(stmt, idx, v)
            case .some(.real(let v)):
                rc = sqlite3_bind_double(stmt, idx, v)
            case .some(.text(let s)):
                // Explicit byte length preserves embedded NULs; SQLITE_TRANSIENT copies
                // the buffer (the bridged pointer dies at the end of the call).
                rc = sqlite3_bind_text(stmt, idx, s, Int32(s.utf8.count), Self.transient)
            case .some(.blob(let d)):
                // bind_blob with a NULL base pointer binds SQL NULL — an empty Data
                // must instead bind a genuine zero-length blob.
                rc = d.isEmpty
                    ? sqlite3_bind_zeroblob(stmt, idx, 0)
                    : d.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(d.count), Self.transient) }
            }
            guard rc == SQLITE_OK else {
                return Result(columns: [], rows: [], error: String(cString: sqlite3_errmsg(db)), rowsAffected: 0)
            }
        }
        return collect(stmt!, on: db, limit: limit)
    }

    /// The rowid of the most recent successful `INSERT` on this connection
    /// (`sqlite3_last_insert_rowid`); `0` if nothing was inserted yet.
    public var lastInsertRowID: Int64 { db.map { sqlite3_last_insert_rowid($0) } ?? 0 }

    /// `SQLITE_TRANSIENT` — tells SQLite to copy bound text/blob buffers immediately.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Steps a prepared statement to completion, stringifying rows (capped at `limit`)
    /// — the shared back half of ``run(_:limit:)`` and ``execute(_:parameters:limit:)``.
    private func collect(_ stmt: OpaquePointer, on db: OpaquePointer, limit: Int) -> Result {
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

    /// Double-quotes an identifier (escaping embedded quotes) for safe interpolation
    /// into SQL/pragma text. Identifiers (table/column names) cannot be bound as
    /// parameters — quote them with this and bind the *values* via
    /// ``execute(_:parameters:limit:)``.
    public static func quoteIdentifier(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }

    /// Instance shorthand for ``quoteIdentifier(_:)`` used by the introspection helpers.
    private func quoteIdent(_ s: String) -> String { Self.quoteIdentifier(s) }
}
