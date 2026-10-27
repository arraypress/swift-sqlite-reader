//
//  SQLiteValue+Reading.swift
//  SQLiteReader
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Reading a stored value as the Swift type a caller wants.
public extension SQLiteValue {

    /// The value as an integer: integers, whole reals, and text that is one; nil otherwise.
    var int: Int? { ValueReading.int(self) }

    /// The value as a double: integers, reals, and text that is one; nil otherwise.
    var double: Double? { ValueReading.double(self) }

    /// The value as a string: text, or numbers written out; nil for NULL and bytes.
    var string: String? { ValueReading.string(self) }

    /// The value as bytes: a blob, or text's UTF-8; nil otherwise.
    var data: Data? { ValueReading.data(self) }

    /// The value as a flag: a non-zero number is true; nil for NULL.
    var bool: Bool? { int.map { $0 != 0 } }

    /// Whether the value is NULL.
    var isNull: Bool { self == .null }

    /// The value as one of Apple's stored times, seconds or nanoseconds since 2001 (see ``AppleTime``).
    var appleDate: Date? { double.flatMap(AppleTime.date) }

    /// A 16-byte blob as a UUID string; nil otherwise.
    var uuid: String? { data.flatMap(ValueReading.uuid) }

    /// The value as an integer, a real truncated toward zero; nil for NULL and anything else.
    /// Apps store whole numbers as reals; this is how their own code reads them.
    var truncatedInt: Int? { int ?? double.flatMap { Int(exactly: $0.rounded(.towardZero)) } }

    /// The value as a string, a blob read as UTF-8 — apps store text as either.
    var decodedString: String? {
        if case .blob(let bytes) = self { return String(decoding: bytes, as: UTF8.self) }
        return string
    }

    /// ``decodedString``, or nil when it is empty.
    var nonEmptyString: String? { decodedString.flatMap { $0.isEmpty ? nil : $0 } }

    /// ``data``, or nil when it is empty.
    var nonEmptyData: Data? { data.flatMap { $0.isEmpty ? nil : $0 } }
}
