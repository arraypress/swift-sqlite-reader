//
//  SQLiteRow.swift
//  SQLiteReader
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One row of a result: its values, read by position or by column name.
/// The values are copied out, so a row can be kept after the query.
public struct SQLiteRow: Sendable, Equatable {
    /// The values, in the query's column order.
    public let values: [SQLiteValue]
    /// The column names, in the same order.
    public let names: [String]

    /// A row.
    public init(values: [SQLiteValue], names: [String]) {
        self.values = values
        self.names = names
    }

    /// The value at `index`, NULL past the end.
    public subscript(_ index: Int) -> SQLiteValue { values.indices.contains(index) ? values[index] : .null }

    /// The value of the column named `name` (ignoring case), NULL when there is none.
    public subscript(_ name: String) -> SQLiteValue {
        names.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }.map { self[$0] } ?? .null
    }
}
