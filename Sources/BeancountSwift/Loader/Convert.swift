//
//  Convert.swift
//
//
//  Created by Yeatse on 2023/12/31.
//

import Foundation

fileprivate func getCost(_ units: Amount, _ cost: Cost?) -> Amount {
    if let cost, cost.number != .nan {
        return Amount(number: cost.number * units.number, currency: cost.currency)
    } else {
        return units
    }
}

fileprivate func getWeight(_ units: Amount, _ cost: Cost?, _ price: Amount? = nil) -> Amount {
    if let cost, cost.number != .nan {
        return Amount(number: cost.number * units.number, currency: cost.currency)
    } else if let price {
        let convertedNumber: Decimal
        if price.number == .nan || units.number == .nan {
            convertedNumber = .nan
        } else {
            convertedNumber = price.number * units.number
        }
        return Amount(number: convertedNumber, currency: price.currency)
    } else {
        return units
    }
}

fileprivate func getValue(_ units: Amount, _ cost: Cost?, _ price: Amount?, _ priceMap: PriceMap, _ date: Date?) -> Amount {
    if let valueCurrency = cost?.currency ?? price?.currency, valueCurrency != .missing {
        let baseQuote = CurrencyPair(base: units.currency, quote: valueCurrency)
        if let price = priceMap.price(for: baseQuote, date: date) {
            return Amount(number: units.number * price.rate, currency: valueCurrency)
        }
    }
    return units
}

extension Position {
    var totalCost: Amount { getCost(units, cost) }
    var weight: Amount { getWeight(units, cost) }
    
    func marketValue(from priceMap: PriceMap, date: Date? = nil) -> Amount {
        getValue(units, cost, nil, priceMap, date)
    }
    
    func converted(to target: Currency, priceMap: PriceMap, date: Date? = nil) -> Amount {
        units.converted(to: target, priceMap: priceMap, date: date, via: cost.map { [$0.currency] })
    }
}

extension Posting<Cost> {
    var totalCost: Amount { getCost(units, cost) }
    var weight: Amount { getWeight(units, cost, price) }
    
    func marketValue(from priceMap: PriceMap, date: Date? = nil) -> Amount {
        getValue(units, cost, price, priceMap, date)
    }
    
    func converted(to target: Currency, priceMap: PriceMap, date: Date? = nil) -> Amount {
        let via = cost.map { [$0.currency] } ?? price.map { [$0.currency] }
        return units.converted(to: target, priceMap: priceMap, date: date, via: via)
    }
}

extension Posting<CostSpec> {
    var totalCost: Amount { getCost(units, nil) }
    var weight: Amount { getWeight(units, nil, price) }
    func marketValue(from priceMap: PriceMap, date: Date? = nil) -> Amount {
        getValue(units, nil, price, priceMap, date)
    }
    func converted(to target: Currency, priceMap: PriceMap, date: Date? = nil) -> Amount {
        units.converted(to: target, priceMap: priceMap, date: date, via: price.map { [$0.currency] })
    }
}

extension Amount {
    func converted(to targetCurrency: Currency, priceMap: PriceMap, date: Date? = nil, via: [Currency]? = nil) -> Amount {
        let baseQuote = CurrencyPair(base: currency, quote: targetCurrency)
        if let price = priceMap.price(for: baseQuote, date: date) {
            return Amount(number: number * price.rate, currency: targetCurrency)
        } else if let via {
            for impliedCurrency in via {
                if impliedCurrency == targetCurrency {
                    continue
                }
                let baseQuote1 = CurrencyPair(base: currency, quote: impliedCurrency)
                if let price1 = priceMap.price(for: baseQuote1, date: date) {
                    let baseQuote2 = CurrencyPair(base: impliedCurrency, quote: targetCurrency)
                    if let price2 = priceMap.price(for: baseQuote2, date: date) {
                        return Amount(number: number * price1.rate * price2.rate, currency: targetCurrency)
                    }
                }
            }
        }
        return self
    }
}
