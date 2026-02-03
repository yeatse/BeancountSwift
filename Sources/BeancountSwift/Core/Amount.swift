//
//  Amount.swift
//
//
//  Created by Yeatse on 2024/1/28.
//

import Foundation

/// An amount represents a number of a particular unit of something.
///
/// An Amount is essentially a typed number with a currency, similar to how a unit
/// system works. It consists of a decimal number and a currency identifier.
/// All arithmetic operations preserve currency consistency.
///
/// This corresponds to the `Amount` class in the original Beancount Python library,
/// representing the fundamental unit of value in double-entry accounting.
///
/// ## Usage
/// ```swift
/// let amount1 = Amount(number: 100.50, currency: Currency(id: "USD"))
/// let amount2: Amount = "50.25 USD"  // Using string literal (DEBUG only)
/// let total = amount1 + amount2      // 150.75 USD
/// ```
///
/// - SeeAlso: [Beancount Design Doc - Amount](https://beancount.github.io/docs/beancount_design_doc.html#amount)
public struct Amount: Equatable, Hashable, Sendable {
    /// The numeric value of the amount as a Decimal for precision.
    public var number: Decimal

    /// The currency or commodity identifier for this amount.
    public var currency: Currency

    /// Optional fractional digit precision captured from parsed input.
    ///
    /// When available, this preserves the number of digits after the decimal point
    /// from the source text (e.g., "0.10" -> precision 2). This is used to infer
    /// balance tolerances more accurately than `Decimal` can on its own.
    var precision: Int?

    /// A special constant representing a missing or undefined amount.
    /// Uses NaN for the number and a special missing currency.
    public static let missing = Amount(number: .nan, currency: .missing)

    /// Creates a new amount with the specified number and currency.
    ///
    /// - Parameters:
    ///   - number: The numeric value as a Decimal
    ///   - currency: The currency identifier
    public init(number: Decimal, currency: Currency) {
        self.number = number
        self.currency = currency
        self.precision = nil
    }

    init(number: Decimal, currency: Currency, precision: Int?) {
        self.number = number
        self.currency = currency
        self.precision = precision
    }
}

extension Amount {
    /// Returns the least significant digit based on captured precision when available.
    ///
    /// Falls back to the Decimal-derived least significant digit when precision
    /// is not available.
    var leastSignificantDigit: Decimal {
        if let precision {
            return Decimal(sign: .plus, exponent: -precision, significand: 1)
        }
        return number.leastSignificantDigit
    }

    /// Infers fractional digit precision from a numeric string.
    ///
    /// Returns nil for unsupported formats (e.g., scientific notation).
    static func inferredPrecision(from numberText: String) -> Int? {
        var precision = 0
        var sawDigit = false
        for ch in numberText.reversed() {
            if ch == "." {
                return precision
            }
            if ch.isNumber {
                sawDigit = true
                precision += 1
                continue
            }
        }
        return sawDigit ? 0 : nil
    }
}

extension Amount {
    public static func == (lhs: Amount, rhs: Amount) -> Bool {
        lhs.number == rhs.number && lhs.currency == rhs.currency
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(number)
        hasher.combine(currency)
    }
}

extension Amount: Comparable {
    /// Compares two amounts, first by currency, then by numeric value.
    ///
    /// Amounts are ordered first by currency alphabetically, then by numeric value
    /// for amounts of the same currency.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand amount
    ///   - rhs: The right-hand amount
    /// - Returns: True if lhs is less than rhs
    public static func < (lhs: Amount, rhs: Amount) -> Bool {
        if lhs.currency != rhs.currency {
            return lhs.currency < rhs.currency
        } else {
            return lhs.number < rhs.number
        }
    }

    /// Negates an amount, returning a new amount with the opposite sign.
    ///
    /// - Parameter amount: The amount to negate
    /// - Returns: A new amount with negated number and same currency
    public static prefix func - (amount: Amount) -> Amount {
        Amount(number: -amount.number, currency: amount.currency)
    }

    /// Returns the absolute value of the amount.
    ///
    /// If the amount is negative, returns a new amount with the positive number.
    /// Otherwise returns the original amount unchanged.
    public var absolute: Amount {
        if number >= .zero {
            self
        } else {
            Amount(number: -number, currency: currency)
        }
    }

    /// Adds two amounts with the same currency.
    ///
    /// - Warning: Both amounts must have the same currency. The result
    ///   will use the currency from the left operand.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand amount
    ///   - rhs: The right-hand amount
    /// - Returns: A new amount with the sum of the numbers
    public static func + (lhs: Amount, rhs: Amount) -> Amount {
        Amount(number: lhs.number + rhs.number, currency: lhs.currency)
    }

    /// Subtracts two amounts with the same currency.
    ///
    /// - Warning: Both amounts must have the same currency. The result
    ///   will use the currency from the left operand.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand amount
    ///   - rhs: The right-hand amount
    /// - Returns: A new amount with the difference of the numbers
    public static func - (lhs: Amount, rhs: Amount) -> Amount {
        Amount(number: lhs.number - rhs.number, currency: lhs.currency)
    }

    /// Multiplies an amount by a scalar decimal value.
    ///
    /// - Parameters:
    ///   - lhs: The amount to multiply
    ///   - rhs: The scalar multiplier
    /// - Returns: A new amount with the multiplied number and same currency
    public static func * (lhs: Amount, rhs: Decimal) -> Amount {
        Amount(number: lhs.number * rhs, currency: lhs.currency)
    }

    /// Divides an amount by a scalar decimal value.
    ///
    /// - Parameters:
    ///   - lhs: The amount to divide
    ///   - rhs: The scalar divisor
    /// - Returns: A new amount with the divided number and same currency
    public static func / (lhs: Amount, rhs: Decimal) -> Amount {
        Amount(number: lhs.number / rhs, currency: lhs.currency)
    }

    /// Adds the right amount to the left amount in place.
    ///
    /// - Warning: Both amounts must have the same currency.
    ///
    /// - Parameters:
    ///   - left: The amount to modify
    ///   - right: The amount to add
    public static func += (left: inout Amount, right: Amount) {
        left = left + right
    }
}

#if DEBUG
extension Amount: ExpressibleByStringLiteral {
    /// Creates an amount from a string literal in DEBUG builds only.
    ///
    /// Parses strings in the format "123.45 USD" where the number can be positive
    /// or negative and the currency follows Beancount naming conventions.
    ///
    /// This initializer is only available in DEBUG builds to prevent runtime
    /// parsing in production code. Use explicit initialization in production.
    ///
    /// - Parameter value: A string containing number and currency separated by space
    ///
    /// ## Examples
    /// ```swift
    /// let amount1: Amount = "100.50 USD"
    /// let amount2: Amount = "-25.00 EUR"
    /// let amount3: Amount = "1000 /STOCK/AAPL"  // Commodity with path syntax
    /// ```
    ///
    /// - Warning: This will crash with `fatalError()` if the string format is invalid.
    public init(stringLiteral value: StringLiteralType) {
        guard
            let match = value.wholeMatch(
                of:
                    #/\s*([+-]?[0-9.]+)\s+([A-Z][A-Z0-9'\.\_\-]*[A-Z0-9]?\b|/[A-Z0-9'\.\_\-]*[A-Z](?:[A-Z0-9'\.\_\-]*[A-Z0-9])?)/#
            )
        else {
            fatalError()
        }
        let numberText = String(match.1)
        self.number = Decimal(string: numberText)!
        self.currency = Currency(id: String(match.2))
        self.precision = Amount.inferredPrecision(from: numberText)
    }
}
#endif
