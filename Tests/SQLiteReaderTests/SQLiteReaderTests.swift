//
//  SQLiteReaderTests.swift
//  SQLiteReader
//
//  Created by David Sherlock on 2026.
//
//  Real SQLite files made here: a store whose newest rows live only in its
//  write-ahead log while another connection holds it open, a refused file,
//  and every way a value reads. Every value is invented.
//

import Foundation
import SQLite3
import XCTest
@testable import SQLiteReader

final class SQLiteReaderTests: XCTestCase {

    var folder: URL!

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sqlite-reader-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }

    /// A store in WAL mode with rows that were never checkpointed; the writer stays open.
    func liveStore() -> (URL, OpaquePointer?) {
        let url = folder.appendingPathComponent("live.sqlite")
        var writer: OpaquePointer?
        sqlite3_open(url.path, &writer)
        for sql in ["PRAGMA journal_mode=WAL", "PRAGMA wal_autocheckpoint=0",
                    "CREATE TABLE ZCALL (ZNAME TEXT, ZDATE REAL, ZID BLOB, ZFLAG INTEGER)",
                    "INSERT INTO ZCALL VALUES ('Alex Rivera', 800000000, x'000102030405060708090A0B0C0D0E0F', 1)",
                    "INSERT INTO ZCALL VALUES ('Harbour Café', 800000000000000000, NULL, 0)"] {
            XCTAssertEqual(sqlite3_exec(writer, sql, nil, nil, nil), SQLITE_OK, sql)
        }
        return (url, writer)
    }

    func testASnapshotReadsRowsThatLiveOnlyInTheLogAndLeavesNothing() throws {
        let (url, writer) = liveStore()
        defer { sqlite3_close(writer) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path + "-wal"), "the rows are in the log")
        var copyFolder: String?
        do {
            let store = try SQLiteReader(path: url, opening: .snapshot)
            let rows = try store.rows("SELECT ZNAME, ZDATE, ZID, ZFLAG FROM ZCALL ORDER BY ZNAME")
            XCTAssertEqual(rows.map { $0["zname"].string }, ["Alex Rivera", "Harbour Café"], "names ignore case")
            copyFolder = try FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory()).first { $0.hasPrefix("sqlite-reader-") && !$0.contains("tests") }
            XCTAssertNotNil(copyFolder)
            XCTAssertEqual(store.columns(of: "ZCALL"), ["ZNAME", "ZDATE", "ZID", "ZFLAG"])
            XCTAssertEqual(store.tables(), ["ZCALL"])
        }
        let leftover = try FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory()).filter { $0 == copyFolder }
        XCTAssertTrue(leftover.isEmpty, "the private copy is deleted with the reader")
    }

    func testReadOnlyReadsInPlaceWithBindingsAndNeverWrites() throws {
        let (url, writer) = liveStore()
        defer { sqlite3_close(writer) }
        let store = try SQLiteReader(path: url)
        let rows = try store.rows("SELECT ZNAME FROM ZCALL WHERE ZFLAG = ? AND ZNAME LIKE ?", [.integer(1), .text("Alex%")])
        XCTAssertEqual(rows.map { $0[0].string }, ["Alex Rivera"])
        XCTAssertThrowsError(try store.rows("INSERT INTO ZCALL VALUES ('x', 0, NULL, 0)"), "read-only means read-only")
        XCTAssertThrowsError(try store.rows("SELECT nope FROM ZCALL")) {
            guard case .unreadable = $0 as? SQLiteReaderError else { return XCTFail("\($0)") }
        }
        var count = 0
        try store.query("SELECT * FROM ZCALL") { _ in count += 1 }
        XCTAssertEqual(count, 2)
    }

    func testMissingAndRefusedAreToldApart() throws {
        let missing = folder.appendingPathComponent("none.sqlite")
        XCTAssertThrowsError(try SQLiteReader(path: missing)) { XCTAssertEqual($0 as? SQLiteReaderError, .notFound(missing.path)) }
        let (url, writer) = liveStore()
        sqlite3_close(writer)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        XCTAssertEqual(FileChecks.access(url.path), .refused)
        XCTAssertThrowsError(try SQLiteReader(path: url)) { XCTAssertEqual($0 as? SQLiteReaderError, .permissionDenied(url.path)) }
        XCTAssertThrowsError(try SQLiteReader(path: url, opening: .snapshot)) { XCTAssertEqual($0 as? SQLiteReaderError, .permissionDenied(url.path)) }
        XCTAssertTrue(FileChecks.isRefusal(NSError(domain: NSCocoaErrorDomain, code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])),
                      "a refusal wrapped in another error")
        XCTAssertFalse(FileChecks.isRefusal(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))))
    }

    func testValuesReadAsEachType() {
        XCTAssertEqual(SQLiteValue.integer(7).int, 7)
        XCTAssertEqual(SQLiteValue.real(7).int, 7, "a whole real")
        XCTAssertNil(SQLiteValue.real(7.5).int)
        XCTAssertEqual(SQLiteValue.text(" 42 ").int, 42)
        XCTAssertEqual(SQLiteValue.integer(3).double, 3)
        XCTAssertEqual(SQLiteValue.text("2.5").double, 2.5)
        XCTAssertEqual(SQLiteValue.integer(12).string, "12")
        XCTAssertNil(SQLiteValue.blob(Data([1])).string)
        XCTAssertEqual(SQLiteValue.text("hi").data, Data("hi".utf8))
        XCTAssertEqual(SQLiteValue.integer(2).bool, true)
        XCTAssertEqual(SQLiteValue.integer(0).bool, false)
        XCTAssertNil(SQLiteValue.null.bool)
        XCTAssertTrue(SQLiteValue.null.isNull)
        XCTAssertEqual(SQLiteValue.blob(Data(0..<16)).uuid, "00010203-0405-0607-0809-0A0B0C0D0E0F")
        XCTAssertNil(SQLiteValue.blob(Data(0..<15)).uuid)
        let row = SQLiteRow(values: [.integer(1)], names: ["Z_PK"])
        XCTAssertEqual(row[5], .null, "past the end is NULL")
        XCTAssertEqual(row["nope"], .null)
    }

    func testAppleTimesAreSecondsOrNanoseconds() {
        XCTAssertEqual(SQLiteValue.real(800_000_000).appleDate, Date(timeIntervalSinceReferenceDate: 800_000_000))
        XCTAssertEqual(SQLiteValue.integer(800_000_000_000_000_000).appleDate, Date(timeIntervalSinceReferenceDate: 800_000_000), "nanoseconds")
        XCTAssertEqual(AppleTime.date(99_999_999_999), Date(timeIntervalSinceReferenceDate: 99_999_999_999), "just below the threshold is seconds")
        XCTAssertNil(AppleTime.date(0), "0 is never")
        XCTAssertNil(SQLiteValue.null.appleDate)
    }

    func testAPathWithAQuestionMarkStillOpens() throws {
        let odd = folder.appendingPathComponent("odd?name#1.sqlite")
        var db: OpaquePointer?
        sqlite3_open(odd.path, &db)
        sqlite3_exec(db, "CREATE TABLE T (A INTEGER); INSERT INTO T VALUES (5);", nil, nil, nil)
        sqlite3_close(db)
        XCTAssertEqual(try SQLiteReader(path: odd).rows("SELECT A FROM T").first?[0].int, 5)
    }
}
