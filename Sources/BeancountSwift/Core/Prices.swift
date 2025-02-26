//
//  Prices.swift
//
//
//  Created by Yeatse on 2024/1/26.
//

import Foundation
import Algorithms

public struct CurrencyPair: Hashable, Sendable {
    public let base: Currency
    public let quote: Currency
    
    public init(base: Currency, quote: Currency) {
        self.base = base
        self.quote = quote
    }
    
    func inversed() -> CurrencyPair {
        return CurrencyPair(base: quote, quote: base)
    }
}

public struct DailyPrice: Hashable, Comparable, Sendable {
    public let date: Date
    public let rate: Decimal
    
    func reciprocal() -> DailyPrice? {
        guard rate != .zero else { return nil }
        return DailyPrice(date: date, rate: 1 / rate)
    }
    
    static func * (price: DailyPrice, multiplier: Decimal) -> DailyPrice {
        return DailyPrice(date: price.date, rate: price.rate * multiplier)
    }
    
    public static func < (lhs: DailyPrice, rhs: DailyPrice) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        } else {
            return lhs.rate < rhs.rate
        }
    }
}

public struct PriceMap: Equatable, Sendable {
    var prices: [CurrencyPair: [DailyPrice]] = [:]
    var forwardPairs: Set<CurrencyPair> = []
}

extension PriceMap {
    public static func build(from entries: [Directive<Cost>]) -> PriceMap {
        var priceMap = PriceMap()
        
        for entry in entries {
            if case .price(let price) = entry.content {
                let baseQuote = CurrencyPair(base: price.currency, quote: price.amount.currency)
                priceMap.prices[baseQuote, default: []].append(.init(date: entry.date, rate: price.amount.number))
            }
        }
        
        // Find and process inverse pairs
        var inversedUnits: [CurrencyPair] = []
        for (baseQuote, _) in priceMap.prices {
            if priceMap.prices.keys.contains(baseQuote.inversed()) {
                inversedUnits.append(baseQuote)
            }
        }
        
        for baseQuote in inversedUnits {
            let bqPrices = priceMap.prices[baseQuote, default: []]
            let qbPrices = priceMap.prices[baseQuote.inversed(), default: []]
            
            // Determine which one to keep and which one to convert
            let removePair = bqPrices.count < qbPrices.count ? baseQuote : baseQuote.inversed()
            let removeList = priceMap.prices.removeValue(forKey: removePair) ?? []
            let invertedList = removeList.compactMap { $0.reciprocal() }
            priceMap.prices[removePair.inversed(), default: []] += invertedList
        }
        
        for baseQuote in priceMap.prices.keys {
            let sorted = priceMap.prices[baseQuote]!.sorted { $0.date < $1.date }
            var unified: [DailyPrice] = []
            
            var prevDate: Date?
            var prevPrice: DailyPrice?
            for price in sorted {
                if price.date != prevDate, let prevPrice {
                    unified.append(prevPrice)
                }
                prevDate = price.date
                prevPrice = price
            }
            if let prevPrice {
                unified.append(prevPrice)
            }
            priceMap.prices[baseQuote] = unified
        }
        
        let forwardPairs = Set(priceMap.prices.keys)
        for (baseQuote, priceList) in priceMap.prices {
            priceMap.prices[baseQuote.inversed()] = priceList.compactMap { $0.reciprocal() }
        }
        priceMap.forwardPairs = forwardPairs
        return priceMap
    }
    
    func projected(from fromCurrency: Currency,
                   to toCurrency: Currency,
                   base baseCurrencies: Set<Currency>? = nil) -> PriceMap {
        if fromCurrency == toCurrency {
            return self
        }
        
        var priceMap = self
        let currencyPair = CurrencyPair(base: fromCurrency, quote: toCurrency)
        for (baseQuote, prices) in priceMap.prices {
            let base = baseQuote.base
            let quote = baseQuote.quote
            if quote != fromCurrency {
                continue
            }
            
            if let baseCurrencies, !baseCurrencies.contains(base) {
                continue
            }
            
            let existingPrices: Set<Date>
            if let list = priceMap.prices[CurrencyPair(base: base, quote: toCurrency)] {
                existingPrices = Set(list.map(\.date))
            } else {
                existingPrices = []
            }
            
            var newProjected: [DailyPrice] = []
            for dailyPrice in prices {
                guard let rate = priceMap.price(for: currencyPair, date: dailyPrice.date) else {
                    continue
                }
                if existingPrices.contains(rate.date) {
                    continue
                }
                newProjected.append(dailyPrice * rate.rate)
            }
            if !newProjected.isEmpty {
                let key = CurrencyPair(base: base, quote: toCurrency)
                let projected = priceMap.prices[key, default: []] + newProjected
                priceMap.prices[key] = projected.sorted()
                
                let invKey = key.inversed()
                let inverted = priceMap.prices[invKey, default: []] + newProjected.map { $0.reciprocal() ?? $0 * 0 }
                priceMap.prices[invKey] = inverted.sorted()
            }
        }
        return priceMap
    }
    
    func lookupPriceAndInverse(_ baseQuote: CurrencyPair) -> [DailyPrice] {
        if let prices = prices[baseQuote] {
            return prices
        } else if let prices = prices[baseQuote.inversed()] {
            return prices
        } else {
            return []
        }
    }
    
    func allPrices(for baseQuote: CurrencyPair) -> [DailyPrice] {
        return lookupPriceAndInverse(baseQuote)
    }
    
    public func latestPrice(for baseQuote: CurrencyPair) -> DailyPrice? {
        if baseQuote.base == baseQuote.quote {
            return .init(date: .distantPast, rate: 1)
        }
        let priceList = lookupPriceAndInverse(baseQuote)
        if priceList.isEmpty {
            return nil
        } else {
            return priceList.last
        }
    }
    
    public func price(for baseQuote: CurrencyPair, date: Date? = nil) -> DailyPrice? {
        guard let date else {
            return latestPrice(for: baseQuote)
        }
        if baseQuote.base == baseQuote.quote {
            return .init(date: .distantPast, rate: 1)
        }
        let priceList = lookupPriceAndInverse(baseQuote)
        let index = priceList.partitioningIndex { $0.date > date }
        if index == 0 {
            return nil
        } else {
            return priceList[index - 1]
        }
    }
}

extension RandomAccessCollection<Directive<Cost>> {
    public func lastPriceEntries(until date: Date? = nil) -> some RandomAccessCollection<Directive<Cost>> {
        var priceEntryMap: [CurrencyPair: Directive<Cost>] = [:]
        for entry in self {
            if let date, entry.date >= date {
                break
            }
            if case .price(let price) = entry.content {
                let baseQuote = CurrencyPair(base: price.currency, quote: price.amount.currency)
                priceEntryMap[baseQuote] = entry
            }
        }
        return priceEntryMap.values.sorted()
    }
}
