//
//  SQLiteOpening.swift
//  SQLiteReader
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// How a store is opened.
public enum SQLiteOpening: Sendable, Equatable {
    /// The store itself, read-only: for a store its app is not writing, or
    /// one whose write-ahead log can be read in place.
    case readOnly
    /// A private copy — the store and its `-wal`/`-shm` — opened there and
    /// deleted when the reader goes. The live store is never opened: for a
    /// store its app writes while this reads, whose newest rows may live
    /// only in the log (a call history once had eleven weeks there).
    case snapshot
}
