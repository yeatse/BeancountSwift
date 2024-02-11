//
//  Position.swift
//
//
//  Created by Yeatse on 2023/12/24.
//

import Foundation

/// https://beancount.github.io/docs/beancount_design_doc.html#position
public struct Position: Equatable, Hashable {
    public var units: Amount
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
    init(posting: Posting<Cost>) {
        self.init(units: posting.units, cost: posting.cost)
    }
    
    init(units: Amount, costAmount: Amount?) {
        let cost = costAmount.map { amount in
            Cost(number: amount.number, currency: amount.currency, date: .distantPast)
        }
        self.init(units: units, cost: cost)
    }
    
    struct CurrencyPair: Equatable, Hashable {
        let unit: Currency
        let cost: Currency?
    }

    var currencyPair: CurrencyPair {
        return CurrencyPair(unit: units.currency, cost: cost?.currency)
    }
}

extension Position: Comparable {
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
    static prefix func - (position: Position) -> Position {
        Position(units: -position.units, cost: position.cost)
    }

    var absolute: Position {
        Position(units: units.absolute, cost: cost)
    }

    static func * (lhs: Position, rhs: Decimal) -> Position {
        Position(units: lhs.units * rhs, cost: lhs.cost)
    }

    var isNegativeAtCost: Bool {
        units.number < .zero && cost != nil
    }
}

#if DEBUG
extension Position: ExpressibleByStringLiteral {
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
            var date = Date.distantPast
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
    public init(arrayLiteral elements: StringLiteralType?...) {
        self.init(unit: Currency(stringLiteral: elements[0]!),
                  cost: elements[1].map { Currency(stringLiteral: $0) })
    }
}

#endif
