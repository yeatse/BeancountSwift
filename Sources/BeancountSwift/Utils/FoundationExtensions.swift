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
