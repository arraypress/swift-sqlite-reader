//
//  AppleTime.swift
//  SQLiteReader
//
//  Created by David Sherlock on 2026.
//
//  Apple's apps store times as a count since 1 January 2001: Core Data in
//  seconds, Messages and some others in nanoseconds. A nanosecond reading of
//  a seconds value lands in January 2001, and a seconds reading of
//  nanoseconds lands thousands of years out; so a value of 10^11 or more
//  (over three thousand years in seconds) is nanoseconds. Pure.
//

import Foundation

/// Apple's stored times.
public enum AppleTime {

    /// At or above this, a stored time is nanoseconds.
    public static let nanosecondThreshold = 1e11

    /// A stored time as a date; nil for 0 or less (Apple's "never").
    public static func date(_ stored: Double) -> Date? {
        guard stored > 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: stored >= nanosecondThreshold ? stored / 1e9 : stored)
    }
}
