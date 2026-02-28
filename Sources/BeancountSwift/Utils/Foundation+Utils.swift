//
//  FoundationExtensions.swift
//
//
//  Created by Yeatse on 2023/12/31.
//

/// Utility extensions for Foundation types used throughout BeancountSwift.
///
/// This module provides essential extensions to Foundation types like Dictionary,
/// Decimal, Date, and String to support Beancount functionality. These extensions
/// handle common operations like number formatting, date parsing, and string manipulation.

import Foundation

extension Dictionary {
    /// Adds a key-value pair only if the key doesn't already exist.
    ///
    /// Provides a convenient way to conditionally add values to a dictionary
    /// without overwriting existing entries.
    ///
    /// - Parameters:
    ///   - key: The key to add
    ///   - value: The value to associate with the key
    mutating func putIfAbsent(key: Key, value: Value) {
        if !keys.contains(key) {
            self[key] = value
        }
    }
}

extension Decimal {
    /// Returns a rounded copy of the decimal to the specified scale.
    ///
    /// Creates a new decimal value rounded to the specified number of decimal places
    /// using the given rounding mode, without modifying the original value.
    ///
    /// - Parameters:
    ///   - scale: The number of decimal places to round to
    ///   - roundingMode: The rounding mode to apply
    /// - Returns: A new decimal rounded to the specified scale
    func rounded(_ scale: Int, _ roundingMode: NSDecimalNumber.RoundingMode) -> Decimal {
        var result = Decimal()
        withUnsafePointer(to: self) {
            NSDecimalRound(&result, $0, scale, roundingMode)
        }
        return result
    }

    /// The value representing the least significant digit position.
    ///
    /// Returns the decimal value that represents the smallest unit that can be
    /// added to or subtracted from this decimal while still affecting the value.
    /// Used for tolerance calculations and precision tracking.
    ///
    /// - Returns: The least significant digit value
    var leastSignificantDigit: Decimal {
        if exponent < 0 {
            return Decimal(sign: .plus, exponent: exponent, significand: 1)
        } else {
            return 1
        }
    }
}

private let cDateFormat = "%Y-%m-%d"

extension Date {
    /// Parses a date from a Beancount date string format (YYYY-MM-DD).
    ///
    /// Converts a Beancount-style date string to a Date object using C library
    /// functions for fast and accurate parsing. Handles timezone and daylight
    /// saving time considerations.
    ///
    /// - Parameter string: The date string in YYYY-MM-DD format
    /// - Returns: The parsed date, or nil if parsing fails
    static func fromDateString(_ string: String) -> Date? {
        var tm = tm()
        return string.withCString { cString in
            return cDateFormat.withCString { cFormat in
                if strptime(cString, cFormat, &tm) == nil {
                    return nil
                } else {
                    tm.tm_isdst = -1
                    let ts = mktime(&tm)
                    if ts == -1 {
                        let comp = DateComponents(
                            year: Int(tm.tm_year) + 1900,
                            month: Int(tm.tm_mon) + 1,
                            day: Int(tm.tm_mday))
                        return Calendar.current.date(from: comp)
                    } else {
                        return Date(timeIntervalSince1970: Double(ts))
                    }
                }
            }
        }
    }

    /// Returns the date formatted as ISO date string (YYYY-MM-DD).
    ///
    /// Formats the date in the standard Beancount date format using ISO 8601
    /// date representation with dashes as separators.
    ///
    /// - Returns: The date formatted as YYYY-MM-DD string
    var isoDescription: String {
        self.formatted(
            ISO8601FormatStyle(dateSeparator: .dash, timeZone: .autoupdatingCurrent)
                .year().month().day()
        )
    }
}

extension String {
    var quoted: String {
        var out = "\""
        out.reserveCapacity(self.count + 2)

        for scalar in self.unicodeScalars {
            switch scalar.value {
            case 0x22: out += #"\""#         // "
            case 0x5C: out += #"\\"#         // \  -> \\ in beancount literal
            default:
                out.unicodeScalars.append(scalar)
            }
        }

        out += "\""
        return out
    }
    
    /// Strips surrounding double quotes and unescapes backslash sequences,
    /// mirroring beancount's cunescape() in tokens.c (non-strict mode).
    var unquoted: String {
        guard count >= 2, first == "\"", last == "\"" else {
            return self
        }
        let inner = dropFirst().dropLast()
        
        var result = ""
        result.reserveCapacity(inner.count)
        
        var iter = inner.makeIterator()
        while let ch = iter.next() {
            guard ch == "\\" else {
                result.append(ch)
                continue
            }
            guard let escaped = iter.next() else { break }
            switch escaped {
            case "\"": result.append("\"")
            case "n":  result.append("\n")
            case "t":  result.append("\t")
            case "r":  result.append("\r")
            case "f":  result.append("\u{0C}")
            case "b":  result.append("\u{08}")
            default:   result.append(escaped)   // non-strict: \X → X（含 \\ → \）
            }
        }
        return result
    }
    
    /// Returns the string with each line indented by the specified prefix.
    ///
    /// Adds the prefix string to the beginning of each line, useful for
    /// formatting nested structures in Beancount output with proper indentation.
    ///
    /// - Parameter prefix: The prefix to add to each line (default: four spaces)
    /// - Returns: The indented string
    func lineAligned(by prefix: String = "    ") -> String {
        return split(separator: "\n")
            .map { "\(prefix)\($0)" }
            .joined(separator: "\n")
    }
}

#if DEBUG
extension Date: @retroactive ExpressibleByStringLiteral {
    /// Creates a date from a string literal in DEBUG builds only.
    ///
    /// Allows creating Date objects using string literals for testing and debugging.
    /// The string must be in YYYY-MM-DD format.
    ///
    /// ## Example
    /// ```swift
    /// let date: Date = "2024-01-15"
    /// ```
    ///
    /// - Parameter value: The date string in YYYY-MM-DD format
    /// - Warning: Only available in DEBUG builds for testing purposes
    public init(stringLiteral value: StringLiteralType) {
        self = .fromDateString(value)!
    }
}
#endif
