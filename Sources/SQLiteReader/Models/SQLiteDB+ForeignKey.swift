//
//  SQLiteDB+ForeignKey.swift
//  SwiftSQLiteReader
//
//  A foreign-key relationship declared on a table.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

public extension SQLiteDB {

    /// A foreign key declared on a table, from ``SQLiteDB/foreignKeys(_:)``.
    struct ForeignKey: Sendable, Equatable {

        /// The local column that references another table.
        public let from: String

        /// The referenced table.
        public let toTable: String

        /// The referenced column (empty for an implicit primary-key reference).
        public let toColumn: String

        /// Memberwise initializer. Foreign keys are normally produced by ``SQLiteDB/foreignKeys(_:)``.
        public init(from: String, toTable: String, toColumn: String) {
            self.from = from
            self.toTable = toTable
            self.toColumn = toColumn
        }
    }
}
