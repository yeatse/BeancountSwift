//
//  Amount.swift
//
//
//  Created by Yeatse on 2024/1/28.
//

import Foundation

/// https://beancount.github.io/docs/beancount_design_doc.html#amount
public struct Amount: Equatable, Hashable, Sendable {
    public var number: Decimal
    public var currency: Currency
    
    public static let missing = Amount(number: .nan, currency: .missing)
    
    public init(number: Decimal, currency: Currency) {
        self.number = number
        self.currency = currency
    }
}

extension Amount: Comparable {
    public static func < (lhs: Amount, rhs: Amount) -> Bool {
        if lhs.currency != rhs.currency {
            return lhs.currency < rhs.currency
        } else {
            return lhs.number < rhs.number
        }
    }
    
    public static prefix func - (amount: Amount) -> Amount {
        Amount(number: -amount.number, currency: amount.currency)
    }
    
    public var absolute: Amount {
        if number >= .zero {
            self
        } else {
            Amount(number: -number, currency: currency)
        }
    }
    
    public static func + (lhs: Amount, rhs: Amount) -> Amount {
        Amount(number: lhs.number + rhs.number, currency: lhs.currency)
    }
    
    public static func - (lhs: Amount, rhs: Amount) -> Amount {
        Amount(number: lhs.number - rhs.number, currency: lhs.currency)
    }
    
    public static func * (lhs: Amount, rhs: Decimal) -> Amount {
        Amount(number: lhs.number * rhs, currency: lhs.currency)
    }
    
    public static func / (lhs: Amount, rhs: Decimal) -> Amount {
        Amount(number: lhs.number / rhs, currency: lhs.currency)
    }
    
    public static func += (left: inout Amount, right: Amount) {
        left = left + right
    }
}

#if DEBUG
extension Amount: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        guard
            let match = value.wholeMatch(
                of:
                    #/\s*([+-]?[0-9.]+)\s+([A-Z][A-Z0-9'\.\_\-]*[A-Z0-9]?\b|/[A-Z0-9'\.\_\-]*[A-Z](?:[A-Z0-9'\.\_\-]*[A-Z0-9])?)/#
            )
        else {
            fatalError()
        }
        self.number = Decimal(string: String(match.1))!
        self.currency = Currency(id: String(match.2))
    }
}
#endif
