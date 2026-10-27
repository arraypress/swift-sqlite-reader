//
//  SQLiteValue.swift
//  SQLiteReader
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One column's value, as SQLite stored it.
public enum SQLiteValue: Sendable, Equatable, Hashable {
    /// NULL.
    case null
    /// An integer.
    case integer(Int64)
    /// A floating-point number.
    case real(Double)
    /// Text.
    case text(String)
    /// Bytes.
    case blob(Data)
}
