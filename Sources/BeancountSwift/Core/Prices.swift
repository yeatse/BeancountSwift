//
//  Prices.swift
//
//
//  Created by Yeatse on 2024/1/26.
//

import Algorithms
import Foundation

/// A currency pair representing an exchange rate relationship.
///
/// CurrencyPair defines an exchange rate from a base currency to a quote currency.
/// For example, in USD/EUR, USD is the base and EUR is the quote currency.
/// This structure is fundamental for price tracking and currency conversion operations.
///
/// ## Usage
/// ```swift
/// let usdEur = CurrencyPair(base: Currency(id: "USD"), quote: Currency(id: "EUR"))
/// ```
public struct CurrencyPair: Hashable, Sendable {
    /// The base currency (the currency being priced).
    public let base: Currency
    /// The quote currency (the currency used for pricing).
    public let quote: Currency

    /// Creates a currency pair.
    ///
    /// - Parameters:
    ///   - base: The base currency
    ///   - quote: The quote currency
    public init(base: Currency, quote: Currency) {
        self.base = base
        self.quote = quote
    }

    /// Returns the inverse currency pair.
    ///
    /// Creates a new currency pair with base and quote currencies swapped.
    /// For example, USD/EUR becomes EUR/USD.
    ///
    /// - Returns: The inversed currency pair
    func inversed() -> CurrencyPair {
        return CurrencyPair(base: quote, quote: base)
    }
}

/// A price point representing an exchange rate on a specific date.
///
/// DailyPrice captures the exchange rate between two currencies at a particular
/// point in time. It's used for building historical price series and performing
/// time-based currency conversions.
///
/// ## Usage
/// ```swift
/// let price = DailyPrice(date: Date(), rate: 1.25)
/// ```
public struct DailyPrice: Hashable, Comparable, Sendable {
    /// The date of this price quote.
    public let date: Date
    /// The exchange rate at this date.
    public let rate: Decimal

    /// Returns the reciprocal of this price.
    ///
    /// Calculates the inverse exchange rate (1/rate) with the same date.
    /// Returns nil if the rate is zero to avoid division by zero.
    ///
    /// - Returns: The reciprocal price, or nil if rate is zero
    func reciprocal() -> DailyPrice? {
        guard rate != .zero else { return nil }
        return DailyPrice(date: date, rate: 1 / rate)
    }

    /// Multiplies a price by a scalar value.
    ///
    /// Creates a new price with the same date but scaled rate.
    /// Useful for currency conversions and price adjustments.
    ///
    /// - Parameters:
    ///   - price: The price to multiply
    ///   - multiplier: The scalar multiplier
    /// - Returns: A new price with scaled rate
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

/// A comprehensive mapping of currency exchange rates over time.
///
/// PriceMap maintains historical price data for currency pairs and provides
/// efficient lookup and conversion capabilities. It automatically handles
/// inverse relationships and supports price projections across multiple currencies.
///
/// This corresponds to price mapping functionality in the original Beancount Python library.
///
/// ## Usage
/// ```swift
/// let priceMap = PriceMap.build(from: directives)
/// let rate = priceMap.price(for: CurrencyPair(base: "USD", quote: "EUR"))
/// ```
public struct PriceMap: Equatable, Sendable {
    /// Maps currency pairs to their historical price series.
    var prices: [CurrencyPair: [DailyPrice]] = [:]
    /// Tracks which currency pairs are explicitly defined (not computed inverses).
    var forwardPairs: Set<CurrencyPair> = []
}

extension PriceMap {
    /// Builds a price map from a collection of directives.
    ///
    /// Processes price directives from the ledger to create a comprehensive price map.
    /// Automatically handles inverse pairs, deduplicates prices on the same date,
    /// and optimizes storage by choosing the more frequently updated direction.
    ///
    /// - Parameter entries: The directives to process for price information
    /// - Returns: A fully constructed price map
    public static func build(from entries: [Directive<Cost>]) -> PriceMap {
        var priceMap = PriceMap()

        for entry in entries {
            if case .price(let price) = entry.content {
                let baseQuote = CurrencyPair(base: price.currency, quote: price.amount.currency)
                priceMap.prices[baseQuote, default: []].append(
                    .init(date: entry.date, rate: price.amount.number))
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

    /// Projects prices through an intermediate currency.
    ///
    /// Creates new price series by combining existing exchange rates through
    /// a common currency. For example, if you have USD->EUR and EUR->GBP prices,
    /// this can create USD->GBP prices by combining the two rates.
    ///
    /// - Parameters:
    ///   - fromCurrency: The source currency for projection
    ///   - toCurrency: The target currency for projection
    ///   - baseCurrencies: Optional set of currencies to limit projection to
    /// - Returns: A new price map with projected rates
    func projected(
        from fromCurrency: Currency,
        to toCurrency: Currency,
        base baseCurrencies: Set<Currency>? = nil
    ) -> PriceMap {
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
                let inverted =
                    priceMap.prices[invKey, default: []]
                    + newProjected.map { $0.reciprocal() ?? $0 * 0 }
                priceMap.prices[invKey] = inverted.sorted()
            }
        }
        return priceMap
    }

    /// Looks up prices for a currency pair, considering inverse pairs.
    ///
    /// Searches for prices for the given currency pair, and if not found,
    /// looks for the inverse pair. This provides comprehensive price coverage
    /// regardless of which direction was originally specified.
    ///
    /// - Parameter baseQuote: The currency pair to look up
    /// - Returns: Array of daily prices for the pair or its inverse
    func lookupPriceAndInverse(_ baseQuote: CurrencyPair) -> [DailyPrice] {
        if let prices = prices[baseQuote] {
            return prices
        } else if let prices = prices[baseQuote.inversed()] {
            return prices
        } else {
            return []
        }
    }

    /// Returns all prices for a currency pair.
    ///
    /// Provides access to the complete historical price series for a currency pair.
    ///
    /// - Parameter baseQuote: The currency pair to query
    /// - Returns: Array of all daily prices for the pair
    func allPrices(for baseQuote: CurrencyPair) -> [DailyPrice] {
        return lookupPriceAndInverse(baseQuote)
    }

    /// Returns the most recent price for a currency pair.
    ///
    /// Gets the latest available exchange rate for the specified currency pair.
    /// Returns a rate of 1.0 for identical currencies (e.g., USD/USD).
    ///
    /// - Parameter baseQuote: The currency pair to query
    /// - Returns: The latest price, or nil if no prices available
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

    /// Returns the exchange rate for a currency pair at a specific date.
    ///
    /// Looks up the most recent exchange rate at or before the specified date.
    /// If no date is provided, returns the latest available rate.
    ///
    /// - Parameters:
    ///   - baseQuote: The currency pair to query
    ///   - date: The date for price lookup (nil for latest)
    /// - Returns: The price at the specified date, or nil if unavailable
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
    /// Returns the latest price entry for each currency pair up to a specified date.
    ///
    /// Filters the directive collection to find the most recent price directive
    /// for each currency pair, optionally limiting to entries before a cutoff date.
    /// This is useful for getting a snapshot of market prices at a specific point in time.
    ///
    /// - Parameter date: Optional cutoff date (nil for no limit)
    /// - Returns: Collection of the latest price directives for each currency pair
    public func lastPriceEntries(until date: Date? = nil) -> some RandomAccessCollection<
        Directive<Cost>
    > {
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
