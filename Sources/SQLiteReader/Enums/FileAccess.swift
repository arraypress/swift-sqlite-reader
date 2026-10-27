//
//  FileAccess.swift
//  SQLiteReader
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What opening a path for reading finds.
public enum FileAccess: Sendable, Equatable {
    /// It opens.
    case readable
    /// There is nothing there.
    case missing
    /// macOS refused it: privacy protection (Full Disk Access) or permissions.
    case refused
}
