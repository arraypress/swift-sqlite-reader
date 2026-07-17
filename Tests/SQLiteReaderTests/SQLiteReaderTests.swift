//
//  SQLiteReaderTests.swift
//  Tests for SwiftSQLiteReader
//
//  Created by David Sherlock on 7/9/26.
//

import XCTest
import SQLite3
@testable import SQLiteReader

final class SQLiteReaderTests: XCTestCase {

    // MARK: - In-memory schema (init?(sql:))

    func testTablesIncludeViewsSorted() throws {
        let db = try XCTUnwrap(SQLiteDB(sql: """
            CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, age INTEGER);
            CREATE VIEW adults AS SELECT * FROM users WHERE age >= 18;
        """))
        XCTAssertFalse(db.readOnly)
        XCTAssertEqual(db.tables(), ["adults", "users"])   // sorted; view + table, internals hidden
    }

    func testSchemaReportsPKAndNotNull() throws {
        let db = try XCTUnwrap(SQLiteDB(sql:
            "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, age INTEGER);"))
        let cols = db.schema("users")
        XCTAssertEqual(cols.map(\.name), ["id", "name", "age"])
        XCTAssertTrue(cols[0].pk)
        XCTAssertFalse(cols[1].pk)
        XCTAssertTrue(cols[1].notNull)
        XCTAssertFalse(cols[2].notNull)
    }

    func testRowCountAndQuery() throws {
        let db = try XCTUnwrap(SQLiteDB(sql: """
            CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
            INSERT INTO users (name) VALUES ('Ada'), ('Alan');
        """))
        XCTAssertEqual(db.rowCount("users"), 2)
        let r = db.run("SELECT name FROM users ORDER BY name")
        XCTAssertNil(r.error)
        XCTAssertEqual(r.rows.map { $0[0] }, ["Ada", "Alan"])
        XCTAssertEqual(r.columns, ["name"])
    }

    func testForeignKeys() throws {
        let db = try XCTUnwrap(SQLiteDB(sql: """
            CREATE TABLE parent (id INTEGER PRIMARY KEY);
            CREATE TABLE child (id INTEGER PRIMARY KEY, parent_id INTEGER REFERENCES parent(id));
        """))
        let fks = db.foreignKeys("child")
        XCTAssertEqual(fks.count, 1)
        XCTAssertEqual(fks[0].from, "parent_id")
        XCTAssertEqual(fks[0].toTable, "parent")
        XCTAssertEqual(fks[0].toColumn, "id")
    }

    func testColumnTypesAreStringified() throws {
        let db = try XCTUnwrap(SQLiteDB(sql:
            "CREATE TABLE t (i INTEGER, f REAL, s TEXT, n); INSERT INTO t VALUES (7, 1.5, 'hi', NULL);"))
        let r = db.run("SELECT i, f, s, n FROM t")
        XCTAssertEqual(r.rows.first, ["7", "1.5", "hi", "NULL"])
    }

    func testRunReturnsErrorForBadSQL() throws {
        let db = try XCTUnwrap(SQLiteDB(sql: "CREATE TABLE t (a);"))
        XCTAssertNotNil(db.run("SELECT * FROM nonexistent").error)
    }

    func testRunHonorsRowLimit() throws {
        let db = try XCTUnwrap(SQLiteDB(sql:
            "CREATE TABLE t (n); INSERT INTO t VALUES (1),(2),(3),(4),(5);"))
        let r = db.run("SELECT * FROM t", limit: 3)
        XCTAssertEqual(r.rows.count, 3)
        XCTAssertNil(r.error)   // stopping at the display limit is not an error
    }

    func testStepTimeErrorIsSurfaced() throws {
        // abs() of the most negative integer raises a runtime "integer overflow" at
        // step time (prepare succeeds) — it must not look like a successful empty result.
        let db = try XCTUnwrap(SQLiteDB(sql:
            "CREATE TABLE t (n INTEGER); INSERT INTO t VALUES (-9223372036854775808);"))
        let r = db.run("SELECT abs(n) FROM t")
        XCTAssertNotNil(r.error)
    }

    func testRowsAffectedIsZeroForReadOnlyStatements() throws {
        // sqlite3_changes reports the last write on the connection; a SELECT after a
        // DELETE must not inherit the DELETE's count.
        let db = try XCTUnwrap(SQLiteDB(sql:
            "CREATE TABLE t (n); INSERT INTO t VALUES (1),(2),(3);"))
        XCTAssertEqual(db.run("DELETE FROM t WHERE n < 3").rowsAffected, 2)
        XCTAssertEqual(db.run("SELECT * FROM t").rowsAffected, 0)
    }

    func testForeignKeyToColumnLiterallyNamedNULL() throws {
        // An explicit reference to a parent column named "NULL" must not be collapsed
        // into an implicit-PK reference (SQL NULL "to" in PRAGMA foreign_key_list).
        let db = try XCTUnwrap(SQLiteDB(sql: """
            CREATE TABLE p ("NULL" INTEGER PRIMARY KEY);
            CREATE TABLE c (x REFERENCES p("NULL"));
            CREATE TABLE q (id INTEGER PRIMARY KEY);
            CREATE TABLE d (y REFERENCES q);
        """))
        XCTAssertEqual(db.foreignKeys("c").first?.toColumn, "NULL")   // explicit column
        XCTAssertEqual(db.foreignKeys("d").first?.toColumn, "")       // implicit PK reference
    }

    func testIdentifierQuotingSurvivesSpecialTableName() throws {
        // A table name with a double quote must be quote-escaped internally.
        let db = try XCTUnwrap(SQLiteDB(sql: #"CREATE TABLE "we ird" (a); INSERT INTO "we ird" VALUES (1);"#))
        XCTAssertEqual(db.rowCount("we ird"), 1)
        XCTAssertEqual(db.schema("we ird").map(\.name), ["a"])
    }

    // MARK: - Parameterized execution (execute)

    func testExecuteBindsTypedParameters() throws {
        let db = try XCTUnwrap(SQLiteDB(sql: "CREATE TABLE t (i INTEGER, f REAL, s TEXT, n);"))
        let w = db.execute("INSERT INTO t VALUES (?, ?, ?, ?)",
                           parameters: [.integer(7), .real(1.5), .text("hi"), nil])
        XCTAssertNil(w.error)
        XCTAssertEqual(w.rowsAffected, 1)
        XCTAssertEqual(db.run("SELECT i, f, s, n FROM t").rows.first, ["7", "1.5", "hi", "NULL"])
    }

    func testExecuteSelectWithParametersReturnsRows() throws {
        let db = try XCTUnwrap(SQLiteDB(sql: "CREATE TABLE t (n); INSERT INTO t VALUES (1),(2),(3);"))
        let r = db.execute("SELECT n FROM t WHERE n > ? ORDER BY n", parameters: [.integer(1)])
        XCTAssertNil(r.error)
        XCTAssertEqual(r.rows.map { $0[0] }, ["2", "3"])
        XCTAssertEqual(r.rowsAffected, 0)   // reads never inherit a write count
    }

    func testExecuteUpdateByRowid() throws {
        // The cell-edit shape: UPDATE <table> SET <col> = ? WHERE rowid = ?
        let db = try XCTUnwrap(SQLiteDB(sql: "CREATE TABLE t (name TEXT); INSERT INTO t VALUES ('a'),('b');"))
        let r = db.execute("UPDATE t SET name = ? WHERE rowid = ?", parameters: [.text("z"), .integer(2)])
        XCTAssertNil(r.error)
        XCTAssertEqual(r.rowsAffected, 1)
        XCTAssertEqual(db.run("SELECT name FROM t ORDER BY rowid").rows.map { $0[0] }, ["a", "z"])
    }

    func testExecuteNeverInterpretsValueAsSQL() throws {
        // A bound value must stay a literal — no string interpolation into the SQL.
        let db = try XCTUnwrap(SQLiteDB(sql: "CREATE TABLE t (s TEXT);"))
        let hostile = "x'); DROP TABLE t;--"
        XCTAssertNil(db.execute("INSERT INTO t VALUES (?)", parameters: [.text(hostile)]).error)
        XCTAssertEqual(db.tables(), ["t"])                                    // still here
        XCTAssertEqual(db.run("SELECT s FROM t").rows.first?.first, hostile)  // stored verbatim
    }

    func testExecuteParameterCountMismatchErrors() throws {
        let db = try XCTUnwrap(SQLiteDB(sql: "CREATE TABLE t (a, b);"))
        XCTAssertNotNil(db.execute("INSERT INTO t VALUES (?, ?)", parameters: [.integer(1)]).error)
        XCTAssertNotNil(db.execute("INSERT INTO t VALUES (?, ?)",
                                   parameters: [.integer(1), .integer(2), .integer(3)]).error)
        XCTAssertEqual(db.rowCount("t"), 0)   // neither mismatched statement executed
    }

    func testExecuteBindsBlobIncludingEmpty() throws {
        // Empty Data must bind a genuine zero-length blob, not SQL NULL
        // (sqlite3_bind_blob with a NULL pointer would bind NULL).
        let db = try XCTUnwrap(SQLiteDB(sql: "CREATE TABLE t (d BLOB);"))
        XCTAssertNil(db.execute("INSERT INTO t VALUES (?)", parameters: [.blob(Data([1, 2, 3]))]).error)
        XCTAssertNil(db.execute("INSERT INTO t VALUES (?)", parameters: [.blob(Data())]).error)
        XCTAssertEqual(db.run("SELECT d FROM t ORDER BY rowid").rows.map { $0[0] },
                       ["‹blob 3b›", "‹blob 0b›"])
    }

    func testExecuteHonorsRowLimit() throws {
        let db = try XCTUnwrap(SQLiteDB(sql: "CREATE TABLE t (n); INSERT INTO t VALUES (1),(2),(3),(4);"))
        let r = db.execute("SELECT * FROM t WHERE n > ?", parameters: [.integer(0)], limit: 2)
        XCTAssertNil(r.error)
        XCTAssertEqual(r.rows.count, 2)
    }

    func testLastInsertRowID() throws {
        let db = try XCTUnwrap(SQLiteDB(sql: "CREATE TABLE t (a);"))
        XCTAssertNil(db.execute("INSERT INTO t DEFAULT VALUES").error)   // the + Row shape
        XCTAssertEqual(db.lastInsertRowID, 1)
        XCTAssertNil(db.execute("INSERT INTO t DEFAULT VALUES").error)
        XCTAssertEqual(db.lastInsertRowID, 2)
    }

    func testQuoteIdentifierEscapesEmbeddedQuotes() {
        XCTAssertEqual(SQLiteDB.quoteIdentifier("plain"), "\"plain\"")
        XCTAssertEqual(SQLiteDB.quoteIdentifier(#"we"ird"#), #""we""ird""#)
    }

    // MARK: - File-backed (init?(url:))

    func testOpensExistingFileReadWrite() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sqlitereader-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }

        var h: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &h, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
        sqlite3_exec(h, "CREATE TABLE t (a); INSERT INTO t VALUES (1);", nil, nil, nil)
        sqlite3_close(h)

        let db = try XCTUnwrap(SQLiteDB(url: url))
        XCTAssertFalse(db.readOnly)
        XCTAssertEqual(db.tables(), ["t"])
        XCTAssertEqual(db.rowCount("t"), 1)
    }

    func testLockedDatabaseSurfacesErrorInsteadOfEmptyResult() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sqlitereader-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }

        var h: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &h, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
        sqlite3_exec(h, "CREATE TABLE t (a); INSERT INTO t VALUES (1),(2);", nil, nil, nil)
        sqlite3_close(h)

        let db = try XCTUnwrap(SQLiteDB(url: url))
        XCTAssertEqual(db.tables(), ["t"])   // warm the schema cache so prepare succeeds later

        // A second connection holds an exclusive write lock (the terminal agent mid-write).
        var locker: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &locker, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_close(locker) }
        XCTAssertEqual(sqlite3_exec(locker, "BEGIN EXCLUSIVE; INSERT INTO t VALUES (3);", nil, nil, nil), SQLITE_OK)

        // SQLITE_BUSY at step time must surface as an error, not a clean empty result.
        let r = db.run("SELECT * FROM t")
        XCTAssertNotNil(r.error)

        sqlite3_exec(locker, "ROLLBACK;", nil, nil, nil)
    }

    func testNonexistentFileReturnsNil() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing-\(UUID().uuidString).db")
        XCTAssertNil(SQLiteDB(url: url))   // never creates a database
    }
}
