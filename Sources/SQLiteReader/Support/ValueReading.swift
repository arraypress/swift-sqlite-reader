//
//  ValueReading.swift
//  SQLiteReader
//
//  Created by David Sherlock on 2026.
//
//  How a stored value reads as each Swift type — SQLite lets any column
//  hold any type, and apps' stores do. Pure.
//

import Foundation

enum ValueReading {

    static func int(_ value: SQLiteValue) -> Int? {
        switch value {
        case .integer(let number): return Int(exactly: number)
        case .real(let number): return number.rounded() == number ? Int(exactly: number) : nil
        case .text(let text): return Int(text.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    static func double(_ value: SQLiteValue) -> Double? {
        switch value {
        case .integer(let number): return Double(number)
        case .real(let number): return number
        case .text(let text): return Double(text.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    static func string(_ value: SQLiteValue) -> String? {
        switch value {
        case .text(let text): return text
        case .integer(let number): return String(number)
        case .real(let number): return String(number)
        default: return nil
        }
    }

    static func data(_ value: SQLiteValue) -> Data? {
        switch value {
        case .blob(let data): return data
        case .text(let text): return Data(text.utf8)
        default: return nil
        }
    }

    static func uuid(_ data: Data) -> String? {
        guard data.count == 16 else { return nil }
        return data.withUnsafeBytes { NSUUID(uuidBytes: $0.bindMemory(to: UInt8.self).baseAddress!).uuidString }
    }
}
