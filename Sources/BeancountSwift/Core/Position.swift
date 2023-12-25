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
    "CHF": 7
]

extension Position {
    init(posting: Posting<Cost>) {
        self.init(units: posting.units, cost: posting.cost)
    }
    
    var currencyPair: (Currency, Currency?) {
        return (units.currency, cost?.currency)
    }
}
