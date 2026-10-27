//
//  FirstRead.swift
//  SQLiteReader
//
//  Created by David Sherlock on 2026.
//
//  What a failed first read means. A protected container can let a store
//  open and then refuse to read it — that is a permission problem. A file
//  that is not a database, or a damaged one, fails the same read with its
//  own message, and is unreadable, not refused. Pure.
//

import Foundation

enum FirstRead {

    /// SQLite's words for a file that is not a sound database.
    static let damaged = ["not a database", "malformed", "file is encrypted"]

    /// The error a failed first read is reported as.
    static func failure(_ error: SQLiteReaderError, path: String) -> SQLiteReaderError {
        if case .unreadable(_, let reason) = error, damaged.contains(where: reason.lowercased().contains) {
            return .unreadable(path, reason: reason)
        }
        return .permissionDenied(path)
    }
}
