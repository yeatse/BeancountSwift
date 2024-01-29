//
//  Options.swift
//  
//
//  Created by Yeatse on 2024/1/29.
//

import Foundation

public struct Option {
    public let key: String
    public let value: String
}

enum OptionKey: String {
    case title
    
    case name_assets
    case name_liabilities
    case name_equity
    case name_income
    case name_expenses
    
    case inferred_tolerance_default
    case operating_currency
    case booking_method
}

public struct Options {
}
