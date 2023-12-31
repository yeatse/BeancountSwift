//
//  Convert.swift
//
//
//  Created by Yeatse on 2023/12/31.
//

import Foundation

extension Position {
    var weight: Amount {
        if let cost, cost.number != .nan {
            return Amount(number: cost.number * units.number, currency: cost.currency)
        }
        else {
            return units
        }
    }
}

extension Posting<Cost> {
    var weight: Amount {
        if let cost, cost.number != .nan {
            return Amount(number: cost.number * units.number, currency: cost.currency)
        }
        else if let price {
            let convertedNumber: Decimal
            if price.number == .nan || units.number == .nan {
                convertedNumber = .nan
            }
            else {
                convertedNumber = price.number * units.number
            }
            return Amount(number: convertedNumber, currency: price.currency)
        }
        else {
            return units
        }
    }
}

extension Posting<CostSpec> {
    var weight: Amount {
        if let price {
            let convertedNumber: Decimal
            if price.number == .nan || units.number == .nan {
                convertedNumber = .nan
            }
            else {
                convertedNumber = price.number * units.number
            }
            return Amount(number: convertedNumber, currency: price.currency)
        }
        else {
            return units
        }
    }
}
