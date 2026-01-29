//
//  Position.swift
//
//
//  Created by Yeatse on 2023/12/24.
//

import Foundation

/// A position represents a number of units of a currency held at a specific cost.
///
/// In Beancount, a position combines an amount (units and currency) with optional
/// cost information, allowing tracking of investments and trades where the
/// purchase price differs from the current value.
///
/// This corresponds to the `Position` class in the original Beancount Python library,
/// providing the foundation for portfolio tracking and capital gains calculations.
///
/// ## Usage
/// ```swift
/// // Simple position without cost
/// let position1 = Position(units: Amount(number: 100, currency: Currency(id: "USD")), cost: nil)
///
/// // Position with cost (e.g., stock purchased at specific price)
/// let cost = Cost(number: 150, currency: Currency(id: "USD"), date: Date(), label: nil)
/// let position2 = Position(units: Amount(number: 10, currency: Currency(id: "AAPL")), cost: cost)
/// ```
///
/// - SeeAlso: [Beancount Design Doc - Position](https://beancount.github.io/docs/beancount_design_doc.html#position)
public struct Position: Equatable, Hashable, Sendable {
    /// The amount (number and currency) held in this position.
    public var units: Amount

    /// Optional cost information for this position, used for tracking purchase prices.
    public var cost: Cost?
}

let currencyOrder: [Currency: Int] = [
    "CNY": -1,
    "USD": 0,
    "EUR": 1,
    "JPY": 2,
    "CAD": 3,
    "GBP": 4,
    "AUD": 5,
    "NZD": 6,
    "CHF": 7,
]

extension Position {
    /// Creates a position from a posting.
    ///
    /// Extracts the units and cost information from a posting to create
    /// a corresponding position. This is commonly used when converting
    /// transaction postings into portfolio positions.
    ///
    /// - Parameter posting: The posting to convert to a position
    public init(posting: Posting<Cost>) {
        self.init(units: posting.units, cost: posting.cost)
    }

    /// Creates a position from units and a cost amount.
    ///
    /// Constructs a position by converting a cost amount into a full Cost structure.
    /// The cost date is set to distant past when not specified.
    ///
    /// - Parameters:
    ///   - units: The position units
    ///   - costAmount: Optional cost amount to convert to Cost structure
    init(units: Amount, costAmount: Amount?) {
        let cost = costAmount.map { amount in
            Cost(number: amount.number, currency: amount.currency)
        }
        self.init(units: units, cost: cost)
    }

    /// A pair representing the unit currency and optional cost currency of a position.
    ///
    /// Currency pairs are used for grouping positions and analyzing currency relationships
    /// in portfolios. They help identify which currencies are held and at what cost currencies.
    struct CurrencyPair: Equatable, Hashable {
        /// The currency of the position units.
        let unit: Currency
        /// The currency used for the cost, if any.
        let cost: Currency?
    }

    /// The currency pair for this position.
    ///
    /// Returns a CurrencyPair representing the unit currency and cost currency
    /// of this position, useful for grouping and analysis.
    ///
    /// - Returns: The currency pair for this position
    var currencyPair: CurrencyPair {
        return CurrencyPair(unit: units.currency, cost: cost?.currency)
    }
}

extension Position: Comparable {
    /// Determines the sort order for the position's currency.
    ///
    /// Uses a predefined currency ordering for common currencies,
    /// falling back to string length-based ordering for others.
    ///
    /// - Returns: An integer representing the sort order
    private var orderUnits: Int {
        currencyOrder[units.currency, default: currencyOrder.count + units.currency.id.count]
    }

    public static func < (lhs: Position, rhs: Position) -> Bool {
        let lou = lhs.orderUnits
        let rou = rhs.orderUnits
        if lou != rou {
            return lou < rou
        }
        let lcn = lhs.cost?.number ?? .zero
        let rcn = rhs.cost?.number ?? .zero
        if lcn != rcn {
            return lcn < rcn
        }
        let lcc = lhs.cost?.currency ?? ""
        let rcc = rhs.cost?.currency ?? ""
        if lcc != rcc {
            return lcc < rcc
        }
        return lhs.units.number < rhs.units.number
    }
}

extension Position {
    /// Returns the negation of this position.
    ///
    /// Creates a new position with negated units while preserving the cost information.
    /// This is useful for representing opposite positions or adjustments.
    ///
    /// - Parameter position: The position to negate
    /// - Returns: A new position with negated units
    static prefix func - (position: Position) -> Position {
        Position(units: -position.units, cost: position.cost)
    }

    /// Returns the absolute value of this position.
    ///
    /// Creates a new position with the absolute value of the units while
    /// preserving the cost information. Useful for calculating totals
    /// regardless of position direction.
    ///
    /// - Returns: A new position with absolute units
    var absolute: Position {
        Position(units: units.absolute, cost: cost)
    }

    /// Multiplies a position by a scalar value.
    ///
    /// Creates a new position by scaling the units by the given multiplier
    /// while preserving the cost information. Commonly used for position
    /// adjustments, splits, or proportional calculations.
    ///
    /// - Parameters:
    ///   - lhs: The position to multiply
    ///   - rhs: The scalar multiplier
    /// - Returns: A new position with scaled units
    static func * (lhs: Position, rhs: Decimal) -> Position {
        Position(units: lhs.units * rhs, cost: lhs.cost)
    }

    /// Indicates whether this is a negative position with cost information.
    ///
    /// Returns true if the position has negative units and includes cost data.
    /// This is important for identifying short positions or borrowed assets
    /// that have specific cost tracking requirements.
    ///
    /// - Returns: True if the position is negative and has cost information
    var isNegativeAtCost: Bool {
        units.number < .zero && cost != nil
    }
}

#if DEBUG
extension Position: ExpressibleByStringLiteral {
    /// Creates a position from a string literal in DEBUG builds only.
    ///
    /// Parses Beancount-style position strings including units and optional cost specifications.
    /// The string format follows the pattern: "NUMBER CURRENCY {COST_SPEC}"
    ///
    /// ## Examples
    /// ```swift
    /// let simple: Position = "100 USD"
    /// let withCost: Position = "10 AAPL {150.00 USD, 2024-01-15}"
    /// let withLabel: Position = "50 BTC {45000 USD, \"purchase-1\"}"
    /// ```
    ///
    /// - Parameter value: The string representation of the position
    /// - Warning: Only available in DEBUG builds for testing purposes
    public init(stringLiteral value: StringLiteralType) {
        guard
            let match = value.wholeMatch(
                of:
                    #/\s*([+-]?\s*[0-9,]*(?:\.[0-9]*)?)\s+([A-Z][A-Z0-9'\.\_\-]*[A-Z0-9]?\b|/[A-Z0-9'\.\_\-]*[A-Z](?:[A-Z0-9'\.\_\-]*[A-Z0-9])?)(?:\s+\{([^\}]*)\})?\s*$/#
            )
        else {
            fatalError()
        }
        guard let number = Decimal(string: String(match.1)) else {
            fatalError()
        }
        let currency = Currency(id: String(match.2))
        let cost: Cost?
        if let costExpression = match.3 {
            let expressions = costExpression.split { $0 == "," || $0 == "/" }.map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            var costNumber = Decimal.nan
            var costCurrency = Currency.missing
            var date: Date?
            var label: String?
            for expr in expressions {
                if let match = expr.wholeMatch(
                    of:
                        #/([+-]?\s*[0-9,]*(?:\.[0-9]*)?)\s*(?:#\s*([+-]?\s*[0-9,]*(?:\.[0-9]*)?))?\s+([A-Z][A-Z0-9'\.\_\-]*[A-Z0-9]?\b|/[A-Z0-9'\.\_\-]*[A-Z](?:[A-Z0-9'\.\_\-]*[A-Z0-9])?)$/#
                ) {
                    var perNumber = Decimal(string: String(match.1)) ?? .zero
                    let totalNumber = match.2.flatMap { Decimal(string: String($0)) } ?? .zero
                    if totalNumber != .zero {
                        let total = number * perNumber + totalNumber
                        perNumber = total / number
                    }
                    costNumber = perNumber
                    costCurrency = Currency(id: String(match.3))
                } else if let match = expr.wholeMatch(of: #/(\d\d\d\d)[-/](\d\d)[-/](\d\d)$/#) {
                    let year = Int(match.1)
                    let month = Int(match.2)
                    let day = Int(match.3)
                    date = Calendar.current.date(
                        from: DateComponents(year: year, month: month, day: day))!
                } else if let match = expr.wholeMatch(of: #/"([^"]+)*"$/#) {
                    label = match.1.map { String($0) }
                }
            }
            cost = Cost(number: costNumber, currency: costCurrency, date: date, label: label)
        } else {
            cost = nil
        }
        self.init(units: Amount(number: number, currency: currency), cost: cost)
    }
}

extension Position.CurrencyPair: ExpressibleByArrayLiteral {
    /// Creates a currency pair from an array literal in DEBUG builds only.
    ///
    /// Allows creating currency pairs using array literal syntax with
    /// the unit currency as the first element and optional cost currency as the second.
    ///
    /// ## Example
    /// ```swift
    /// let pair: Position.CurrencyPair = ["USD", "EUR"]
    /// let simple: Position.CurrencyPair = ["USD", nil]
    /// ```
    ///
    /// - Parameter elements: Array of currency strings (unit, cost)
    /// - Warning: Only available in DEBUG builds for testing purposes
    public init(arrayLiteral elements: StringLiteralType?...) {
        self.init(
            unit: Currency(stringLiteral: elements[0]!),
            cost: elements[1].map { Currency(stringLiteral: $0) })
    }
}

#endif
