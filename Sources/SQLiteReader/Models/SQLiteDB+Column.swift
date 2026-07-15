//
//  SQLiteDB+Column.swift
//  SwiftSQLiteReader
//
//  A single column from a table's schema.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

public extension SQLiteDB {

    /// A column in a table's schema, from ``SQLiteDB/schema(_:)``.
    struct Column: Sendable, Equatable {

        /// The column name.
        public let name: String

        /// The declared column type (may be empty for typeless columns).
        public let type: String

        /// Whether the column is part of the primary key.
        public let pk: Bool

        /// Whether the column has a `NOT NULL` constraint.
        public let notNull: Bool

        /// Memberwise initializer. Columns are normally produced by ``SQLiteDB/schema(_:)``.
        public init(name: String, type: String, pk: Bool, notNull: Bool) {
            self.name = name
            self.type = type
            self.pk = pk
            self.notNull = notNull
        }
    }
}
