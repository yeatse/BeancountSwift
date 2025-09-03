//
//  Options.swift
//
//
//  Created by Yeatse on 2024/1/29.
//

import Foundation

public struct Option {
    let key: String
    let value: String
    
    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct DisplayConfiguration: Sendable {
    public var displayPrecision: [Currency: Decimal]
    
    static let `default` = DisplayConfiguration(displayPrecision: [:])
    
    init(displayPrecision: [Currency: Decimal]) {
        self.displayPrecision = displayPrecision
    }
}

public struct Options: Sendable {
    public private(set) var title: String = ""
    public private(set) var operatingCurrencies: [Currency] = [
        Currency(id: "USD")
    ]
    public var defaultCurrency: Currency {
        operatingCurrencies.first ?? Currency(id: "USD")
    }
    public private(set) var bookingMethod: BookingMethod = .STRICT
    public private(set) var accountNames: AccountTypeConfiguration = .default
    public private(set) var tolerances: ToleranceConfiguration = .default
    public private(set) var display: DisplayConfiguration = .default
    
    public let rawOptions: [String: [String]]
    
    init(from options: [Option]) {
        rawOptions = options.grouped(by: \.key).mapValues { $0.map(\.value) }
        var mutableTolerance = tolerances
        var mutableDisplay = display
        
        for (key, values) in rawOptions {
            switch key {
                case "title": title = values[0]
                case "operating_currency": operatingCurrencies = values.map { Currency(id: $0) }
                case "name_assets": accountNames.assets = values[0]
                case "name_liabilities": accountNames.liabilities = values[0]
                case "name_equity": accountNames.equity = values[0]
                case "name_income": accountNames.income = values[0]
                case "name_expenses": accountNames.expenses = values[0]
                case "infer_tolerance_from_cost": mutableTolerance.interFromCost = (values[0] == "True")
                case "inferred_tolerance_multiplier":
                    if let multiplier = Decimal(string: values[0]) {
                        mutableTolerance.multiplier = multiplier
                    }
                case "inferred_tolerance_default":
                    for value in values {
                        let components = value.split(separator: ":").map { String($0) }
                        if components.count == 2, let value = Decimal(string: components[1]) {
                            mutableTolerance.defaultTolerances[Currency(id: components[0])] = value
                        }
                    }
                case "display_precision":
                    for value in values {
                        let components = value.split(separator: ":").map { String($0) }
                        if components.count == 2, let precision = Decimal(string: components[1]) {
                            mutableDisplay.displayPrecision[Currency(id: components[0])] = precision
                        }
                    }
                case "booking_method":
                    if let method = BookingMethod(rawValue: values[0]) {
                        bookingMethod = method
                    }
                default:
                    break
            }
        }
        
        tolerances = mutableTolerance
        display = mutableDisplay
    }
}
