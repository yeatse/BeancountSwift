//
//  FoundationExtensions.swift
//
//
//  Created by Yeatse on 2023/12/31.
//

import Foundation

extension Dictionary {
    mutating func putIfAbsent(key: Key, value: Value) {
        if !keys.contains(key) {
            self[key] = value
        }
    }
}

extension Decimal {
    mutating func round(_ scale: Int, _ roundingMode: NSDecimalNumber.RoundingMode) {
        var localCopy = self
        NSDecimalRound(&self, &localCopy, scale, roundingMode)
    }

    func rounded(_ scale: Int, _ roundingMode: NSDecimalNumber.RoundingMode) -> Decimal {
        var result = Decimal()
        var localCopy = self
        NSDecimalRound(&result, &localCopy, scale, roundingMode)
        return result
    }

    var leastSignificantDigit: Decimal {
        if exponent < 0 {
            return Decimal(sign: .plus, exponent: exponent, significand: 1)
        } else {
            return 1
        }
    }
}

fileprivate let cDateFormat = "%Y-%m-%d"

extension Date {
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
                        let comp = DateComponents(year: Int(tm.tm_year) + 1900,
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
    
    static var isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
    
    var isoDescription: String {
        return Self.isoDateFormatter.string(from: self)
    }
}
