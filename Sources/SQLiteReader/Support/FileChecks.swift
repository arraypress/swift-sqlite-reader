//
//  FileChecks.swift
//  SQLiteReader
//
//  Created by David Sherlock on 2026.
//
//  Whether a path can be read, asked of the kernel with open(2): privacy
//  protection refuses with EPERM and plain permissions with EACCES, while
//  Foundation reports a refusal on a parent folder as "file not found".
//

import Foundation

/// Classifying paths and file errors.
public enum FileChecks {

    /// What opening `path` for reading finds.
    public static func access(_ path: String) -> FileAccess {
        let descriptor = open(path, O_RDONLY)
        if descriptor >= 0 {
            close(descriptor)
            return .readable
        }
        return isRefusal(errno: errno) ? .refused : .missing
    }

    /// Whether an error is a refusal to read, however deep it is wrapped.
    public static func isRefusal(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError { return true }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EPERM) || error.code == Int(EACCES) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isRefusal(underlying) }
        return false
    }

    /// Whether an errno is a refusal.
    public static func isRefusal(errno code: Int32) -> Bool { code == EPERM || code == EACCES }
}
