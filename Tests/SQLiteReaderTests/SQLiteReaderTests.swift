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
        XCTAssertEqual(db.run("SELECT * FROM t", limit: 3).rows.count, 3)
    }

    func testIdentifierQuotingSurvivesSpecialTableName() throws {
        // A table name with a double quote must be quote-escaped internally.
        let db = try XCTUnwrap(SQLiteDB(sql: #"CREATE TABLE "we ird" (a); INSERT INTO "we ird" VALUES (1);"#))
        XCTAssertEqual(db.rowCount("we ird"), 1)
        XCTAssertEqual(db.schema("we ird").map(\.name), ["a"])
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

    func testNonexistentFileReturnsNil() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing-\(UUID().uuidString).db")
        XCTAssertNil(SQLiteDB(url: url))   // never creates a database
    }
}
