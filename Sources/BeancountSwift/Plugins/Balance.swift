//
//  Balance.swift
//
//
//  Created by Yeatse on 2024/1/29.
//

import Foundation

extension Balance {
    func tolerance(options: Options) -> Decimal {
        if let tolerance {
            return tolerance
        } else {
            let expo = amount.number.exponent
            if expo < 0 {
                return pow(Decimal(10), expo) * options.tolerances.multiplier * 2
            } else {
                return .zero
            }
        }
    }
}

struct BalanceCheckPlugin: BeancountPlugin {
    static let name = "check"
    
    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (entries: [Directive<Cost>], errors: [Error]) {
        return (entries, [])
    }
}
