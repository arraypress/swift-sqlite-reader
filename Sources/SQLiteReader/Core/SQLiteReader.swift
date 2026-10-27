//
//  SQLiteReader.swift
//  SQLiteReader
//
//  Created by David Sherlock on 2026.
//
//  Reading an app's SQLite store, the one way the fleet does it: never
//  writing it. A store is opened read-only in place, or copied (with its
//  write-ahead log) into a private folder and read there (SQLiteOpening).
//  Before anything is opened, the path is asked of the kernel (FileChecks):
//  a protected container lets a file be listed but refuses the read, and
//  Foundation reports a refusal on a parent folder as "not found" — so
//  "missing" and "give the app Full Disk Access" are told apart.
//

import Foundation
import SQLite3

/// A SQLite store, read and never written.
///
/// ```swift
/// let store = try SQLiteReader(path: url, opening: .snapshot)
/// for row in try store.rows("SELECT ZTITLE, ZDATE FROM ZITEM WHERE ZDELETED = ?", [.integer(0)]) {
///     print(row["ZTITLE"].string ?? "", row["ZDATE"].appleDate ?? .distantPast)
/// }
/// ```
public final class SQLiteReader {

    /// The store's path.
    public let path: String

    private let handle: OpaquePointer
    private let copy: URL?

    /// Opens a store.
    ///
    /// - Parameters:
    ///   - path: The store.
    ///   - opening: In place read-only, or a private copy (see ``SQLiteOpening``).
    /// - Throws: ``SQLiteReaderError/notFound(_:)``, ``SQLiteReaderError/permissionDenied(_:)`` or
    ///   ``SQLiteReaderError/unreadable(_:reason:)``.
    public init(path: URL, opening: SQLiteOpening = .readOnly) throws(SQLiteReaderError) {
        self.path = path.path
        switch FileChecks.access(path.path) {
        case .readable: break
        case .missing: throw .notFound(path.path)
        case .refused: throw .permissionDenied(path.path)
        }
        switch opening {
        case .readOnly:
            copy = nil
            handle = try Self.open("file:\(Self.uriPath(path.path))?mode=ro", flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, for: path.path)
        case .snapshot:
            let folder = try Self.copied(path)
            copy = folder
            do {
                // Read-write on the copy only: folding its log into a read needs an index beside it.
                handle = try Self.open(folder.appendingPathComponent(path.lastPathComponent).path, flags: SQLITE_OPEN_READWRITE, for: path.path)
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
        }
        // A protected store can open and still refuse its first read.
        do { _ = try rows("SELECT count(*) FROM sqlite_master") } catch {
            sqlite3_close_v2(handle)
            if let copy { try? FileManager.default.removeItem(at: copy) }
            throw .permissionDenied(path.path)
        }
    }

    deinit {
        sqlite3_close_v2(handle)
        if let copy { try? FileManager.default.removeItem(at: copy) }
    }

    // MARK: - Reading

    /// Runs a query, handing each row over as it comes.
    ///
    /// - Parameters:
    ///   - sql: One statement.
    ///   - bindings: Values for its `?` placeholders, in order.
    ///   - row: Called with each row.
    public func query(_ sql: String, _ bindings: [SQLiteValue] = [], row: (SQLiteRow) -> Void) throws(SQLiteReaderError) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw .unreadable(path, reason: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() { Statement.bind(value, at: Int32(index + 1), in: statement) }
        let names = Statement.names(statement)
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: row(SQLiteRow(values: Statement.values(statement), names: names))
            case SQLITE_DONE: return
            default: throw .unreadable(path, reason: String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    /// Every row of a query.
    public func rows(_ sql: String, _ bindings: [SQLiteValue] = []) throws(SQLiteReaderError) -> [SQLiteRow] {
        var found: [SQLiteRow] = []
        try query(sql, bindings) { found.append($0) }
        return found
    }

    /// The tables the store has.
    public func tables() -> Set<String> {
        Set(((try? rows("SELECT name FROM sqlite_master WHERE type = 'table'")) ?? []).compactMap { $0[0].string })
    }

    /// The columns a table has, upper-cased — they come and go between
    /// releases of an app, and a query naming a missing one fails outright.
    public func columns(of table: String) -> Set<String> {
        Set(((try? rows("PRAGMA table_info(\(Statement.quoted(table)))")) ?? []).compactMap { $0[1].string?.uppercased() })
    }

    // MARK: - Opening

    private static func open(_ location: String, flags: Int32, for path: String) throws(SQLiteReaderError) -> OpaquePointer {
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(location, &opened, flags, nil)
        guard result == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(result)"
            sqlite3_close_v2(opened)
            if message.lowercased().contains("authoriz") || message.lowercased().contains("permission") { throw .permissionDenied(path) }
            throw .unreadable(path, reason: message)
        }
        return opened
    }

    /// The store and its log copied into a new private folder.
    private static func copied(_ source: URL) throws(SQLiteReaderError) -> URL {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("sqlite-reader-\(UUID().uuidString)", isDirectory: true)
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let from = URL(fileURLWithPath: source.path + suffix)
                guard suffix.isEmpty || manager.fileExists(atPath: from.path) else { continue }
                try manager.copyItem(at: from, to: folder.appendingPathComponent(source.lastPathComponent + suffix))
            }
            return folder
        } catch {
            try? manager.removeItem(at: folder)
            if FileChecks.isRefusal(error) { throw .permissionDenied(source.path) }
            throw .unreadable(source.path, reason: error.localizedDescription)
        }
    }

    /// A path made safe for a `file:` URI.
    static func uriPath(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#"))) ?? path
    }
}
