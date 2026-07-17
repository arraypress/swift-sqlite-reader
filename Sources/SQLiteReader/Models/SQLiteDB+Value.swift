//
//  SQLiteDB+Value.swift
//  SwiftSQLiteReader
//
//  A typed SQLite value for parameter binding. Kept nested (`SQLiteDB.Value`)
//  to match `SQLiteDB.Result`.
//
//  Created by David Sherlock on 7/17/26.
//

import Foundation

public extension SQLiteDB {

    /// A typed SQLite value for binding into a parameterized statement via
    /// ``SQLiteDB/execute(_:parameters:limit:)``.
    ///
    /// Parameters are declared `Value?` — `nil` binds SQL `NULL`.
    enum Value: Sendable, Equatable {
        /// A 64-bit integer (`sqlite3_bind_int64`).
        case integer(Int64)
        /// A double (`sqlite3_bind_double`).
        case real(Double)
        /// UTF-8 text (`sqlite3_bind_text`, copied).
        case text(String)
        /// Raw bytes (`sqlite3_bind_blob`, copied; empty data binds a zero-length blob).
        case blob(Data)
    }
}
