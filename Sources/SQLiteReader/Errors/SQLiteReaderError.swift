//
//  SQLiteReaderError.swift
//  SQLiteReader
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Why a store could not be read.
public enum SQLiteReaderError: Error, Sendable, Equatable, LocalizedError {
    /// There is no store at the path.
    case notFound(String)
    /// macOS refused it: the app running this needs Full Disk Access.
    case permissionDenied(String)
    /// SQLite could not open or query it.
    case unreadable(String, reason: String)

    /// A sentence for a person.
    public var errorDescription: String? {
        switch self {
        case .notFound(let path): return "no database at \(path)"
        case .permissionDenied(let path): return "macOS refused \(path) — give the app running this Full Disk Access"
        case .unreadable(let path, let reason): return "\(path) could not be read: \(reason)"
        }
    }
}
