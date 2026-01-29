//
//  Convert.swift
//
//
//  Created by Yeatse on 2023/12/31.
//

import Foundation

/// Calculates the total cost of a position.
///
/// Computes the total cost by multiplying the unit cost by the number of units.
/// Returns the units amount if no valid cost is available.
///
/// - Parameters:
///   - units: The amount of units
///   - cost: Optional cost information
/// - Returns: The total cost amount
private func getCost(_ units: Amount, _ cost: Cost?) -> Amount {
    if let cost, cost.number != .nan {
        return Amount(number: cost.number * units.number, currency: cost.currency)
    } else {
        return units
    }
}

/// Calculates the weight (book value) of a position.
///
/// Computes the weight by using cost information first, then price information,
/// or falling back to units if neither is available. Weight is used for
/// balance calculations and reporting.
///
/// - Parameters:
///   - units: The amount of units
///   - cost: Optional cost information
///   - price: Optional price information
/// - Returns: The weight amount
private func getWeight(_ units: Amount, _ cost: Cost?, _ price: Amount? = nil) -> Amount {
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

/// Calculates the market value of a position using price map data.
///
/// Determines the market value by looking up current market prices for the
/// position's currency. Uses cost or price currency as the target currency.
///
/// - Parameters:
///   - units: The amount of units
///   - cost: Optional cost information
///   - price: Optional price information
///   - priceMap: Price map for currency conversion
///   - date: Optional date for historical pricing
/// - Returns: The market value amount
private func getValue(
    _ units: Amount, _ cost: Cost?, _ price: Amount?, _ priceMap: PriceMap, _ date: Date?
) -> Amount {
    if let valueCurrency = cost?.currency ?? price?.currency, valueCurrency != .missing {
        let baseQuote = CurrencyPair(base: units.currency, quote: valueCurrency)
        if let price = priceMap.price(for: baseQuote, date: date) {
            return Amount(number: units.number * price.rate, currency: valueCurrency)
        }
    }
    return units
}

extension Position {
    /// The total cost of this position.
    ///
    /// Calculates the total cost by multiplying the position's units by their cost.
    /// Returns the units amount if no cost information is available.
    ///
    /// - Returns: The total cost amount
    public var totalCost: Amount { getCost(units, cost) }

    /// The weight (book value) of this position.
    ///
    /// The weight represents the book value using cost information.
    /// This is used in balance calculations and reporting.
    ///
    /// - Returns: The weight amount
    public var weight: Amount { getWeight(units, cost) }

    /// Calculates the current market value of this position.
    ///
    /// Uses the price map to determine the current market value of the position
    /// in the cost currency. Returns the units if no pricing information is available.
    ///
    /// - Parameters:
    ///   - priceMap: Price map for currency conversion
    ///   - date: Optional date for historical pricing (nil for latest)
    /// - Returns: The market value amount
    public func marketValue(from priceMap: PriceMap, date: Date? = nil) -> Amount {
        getValue(units, cost, nil, priceMap, date)
    }

    /// Converts this position to a target currency.
    ///
    /// Converts the position's units to the specified target currency using
    /// available price information. May use the cost currency as an intermediate
    /// conversion step if direct conversion is not available.
    ///
    /// - Parameters:
    ///   - target: The target currency for conversion
    ///   - priceMap: Price map for currency conversion rates
    ///   - date: Optional date for historical pricing (nil for latest)
    /// - Returns: The converted amount in the target currency
    public func converted(to target: Currency, priceMap: PriceMap, date: Date? = nil) -> Amount {
        units.converted(to: target, priceMap: priceMap, date: date, via: cost.map { [$0.currency] })
    }
}

extension Posting<Cost> {
    /// The total cost of this posting.
    ///
    /// Calculates the total cost by multiplying the posting's units by their cost.
    /// Returns the units amount if no cost information is available.
    ///
    /// - Returns: The total cost amount
    public var totalCost: Amount { getCost(units, cost) }

    /// The weight (book value) of this posting.
    ///
    /// The weight represents the book value using cost or price information.
    /// This is used in balance calculations and transaction balancing.
    ///
    /// - Returns: The weight amount
    public var weight: Amount { getWeight(units, cost, price) }

    /// Calculates the current market value of this posting.
    ///
    /// Uses the price map to determine the current market value of the posting
    /// in the cost or price currency. Returns the units if no pricing information is available.
    ///
    /// - Parameters:
    ///   - priceMap: Price map for currency conversion
    ///   - date: Optional date for historical pricing (nil for latest)
    /// - Returns: The market value amount
    public func marketValue(from priceMap: PriceMap, date: Date? = nil) -> Amount {
        getValue(units, cost, price, priceMap, date)
    }

    /// Converts this posting to a target currency.
    ///
    /// Converts the posting's units to the specified target currency using
    /// available price information. May use cost or price currency as an
    /// intermediate conversion step if direct conversion is not available.
    ///
    /// - Parameters:
    ///   - target: The target currency for conversion
    ///   - priceMap: Price map for currency conversion rates
    ///   - date: Optional date for historical pricing (nil for latest)
    /// - Returns: The converted amount in the target currency
    public func converted(to target: Currency, priceMap: PriceMap, date: Date? = nil) -> Amount {
        let via = cost.map { [$0.currency] } ?? price.map { [$0.currency] }
        return units.converted(to: target, priceMap: priceMap, date: date, via: via)
    }
}

extension Posting<CostSpec> {
    /// The total cost of this posting with cost specification.
    ///
    /// For cost specification postings, returns the units amount since
    /// cost specifications don't contain concrete cost values.
    ///
    /// - Returns: The units amount
    public var totalCost: Amount { getCost(units, nil) }

    /// The weight (book value) of this posting with cost specification.
    ///
    /// Uses price information if available, otherwise returns the units amount.
    ///
    /// - Returns: The weight amount
    public var weight: Amount { getWeight(units, nil, price) }

    /// Calculates the market value of this cost specification posting.
    ///
    /// Uses price information and the price map to determine market value.
    ///
    /// - Parameters:
    ///   - priceMap: Price map for currency conversion
    ///   - date: Optional date for historical pricing
    /// - Returns: The market value amount
    public func marketValue(from priceMap: PriceMap, date: Date? = nil) -> Amount {
        getValue(units, nil, price, priceMap, date)
    }

    /// Converts this cost specification posting to a target currency.
    ///
    /// Uses price information as an intermediate currency if available.
    ///
    /// - Parameters:
    ///   - target: The target currency
    ///   - priceMap: Price map for conversion rates
    ///   - date: Optional date for historical pricing
    /// - Returns: The converted amount
    public func converted(to target: Currency, priceMap: PriceMap, date: Date? = nil) -> Amount {
        units.converted(
            to: target, priceMap: priceMap, date: date, via: price.map { [$0.currency] })
    }
}

extension Amount {
    /// Converts this amount to a target currency using available price data.
    ///
    /// Attempts direct conversion first, then tries conversion through intermediate
    /// currencies if specified. This enables multi-step currency conversion when
    /// direct rates are not available.
    ///
    /// - Parameters:
    ///   - targetCurrency: The target currency for conversion
    ///   - priceMap: Price map containing exchange rates
    ///   - date: Optional date for historical rates (nil for latest)
    ///   - via: Optional intermediate currencies for multi-step conversion
    /// - Returns: The converted amount, or the original amount if conversion fails
    func converted(
        to targetCurrency: Currency, priceMap: PriceMap, date: Date? = nil, via: [Currency]? = nil
    ) -> Amount {
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
                        return Amount(
                            number: number * price1.rate * price2.rate, currency: targetCurrency)
                    }
                }
            }
        }
        return self
    }
}
