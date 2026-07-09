//
//  SQLiteDB+Result.swift
//  SwiftSQLiteReader
//
//  The outcome of running a SQL statement. Kept nested (`SQLiteDB.Result`) so it
//  does not collide with the standard library's `Swift.Result`.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

public extension SQLiteDB {

    /// The result of ``SQLiteDB/run(_:limit:)`` — stringified rows or an error.
    struct Result: Sendable, Equatable {

        /// Column names, in order.
        public let columns: [String]

        /// Rows, each a stringified value per column.
        public let rows: [[String]]

        /// An error message if the statement failed, otherwise `nil`.
        public let error: String?

        /// The number of rows changed by the statement (for INSERT/UPDATE/DELETE).
        public let rowsAffected: Int

        public init(columns: [String], rows: [[String]], error: String?, rowsAffected: Int) {
            self.columns = columns
            self.rows = rows
            self.error = error
            self.rowsAffected = rowsAffected
        }
    }
}
