//
//  Forecast.swift
//  
//
//  Created by Yeatse on 2024/1/28.
//

import Foundation

struct ForecastPlugin: BeancountPlugin {
    static let name = "forecast_plugin"
    
    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (
        entries: [Directive<Cost>], errors: [Error]
    ) {
        return (entries, [])
    }
}
