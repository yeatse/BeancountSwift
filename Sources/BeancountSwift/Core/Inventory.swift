//
//  Inventory.swift
//
//
//  Created by Yeatse on 2023/12/24.
//

import Algorithms
import Foundation
import OrderedCollections

/// A collection of positions representing account holdings.
///
/// Inventory manages a collection of positions (amounts with optional cost information)
/// for an account. It automatically aggregates positions with the same currency and cost,
/// maintaining the fundamental accounting property that positions can be added and subtracted.
///
/// This corresponds to the `Inventory` class in the original Beancount Python library,
/// providing efficient storage and manipulation of account holdings.
///
/// ## Usage
/// ```swift
/// var inventory = Inventory()
/// inventory.addAmount(Amount(number: 100, currency: Currency(id: "USD")))
/// inventory.addAmount(Amount(number: -25, currency: Currency(id: "USD")))
/// print(inventory.getCurrencyUnits(in: Currency(id: "USD"))) // 75 USD
/// ```
///
/// - SeeAlso: [Beancount Design Doc - Inventory](https://beancount.github.io/docs/beancount_design_doc.html#inventory)
public struct Inventory: Sendable {
    fileprivate var cache: OrderedDictionary<PositionKey, Position> = [:]

    /// Creates an inventory with the given positions.
    ///
    /// Positions with the same currency and cost will be automatically aggregated.
    ///
    /// - Parameter positions: Initial positions to add to the inventory
    public init(positions: [Position] = []) {
        positions.forEach { addPosition($0) }
    }

    struct PositionKey: Equatable, Hashable, Comparable {
        let currency: Currency
        let cost: Cost?

        static func < (lhs: Inventory.PositionKey, rhs: Inventory.PositionKey) -> Bool {
            if lhs.currency != rhs.currency {
                return lhs.currency < rhs.currency
            } else if let lc = lhs.cost, let rc = rhs.cost {
                return lc < rc
            } else if lhs.cost == nil {
                return true
            } else {
                return false
            }
        }
    }

    public enum MatchResult {
        case created
        case reduced
        case augmented
        case ignored
    }
}

extension Inventory {
    /// Returns true if the inventory contains no positions.
    ///
    /// - Returns: True if there are no positions in the inventory
    public var isEmpty: Bool {
        positions.isEmpty
    }

    /// A collection of all positions in this inventory.
    ///
    /// - Returns: A collection of positions sorted by their currency and cost
    var positions: some RandomAccessCollection<Position> {
        cache.map(\.value)
    }

    /// The set of all currencies present in this inventory.
    ///
    /// - Returns: A set containing all currencies held in positions
    public var currencies: Set<Currency> {
        Set(cache.keys.map(\.currency))
    }

    /// The set of all cost currencies used in this inventory.
    ///
    /// - Returns: A set of currencies used for cost specifications
    var costCurrencies: Set<Currency> {
        Set(cache.keys.compactMap(\.cost?.currency))
    }

    /// The set of all currency pairs represented in this inventory.
    ///
    /// A currency pair consists of the position's currency and its cost currency.
    ///
    /// - Returns: A set of currency pairs from all positions
    var currencyPairs: Set<Position.CurrencyPair> {
        Set(cache.values.map(\.currencyPair))
    }

    /// Returns the single position if inventory contains exactly one position.
    ///
    /// - Returns: The position if there is exactly one, nil otherwise
    var onlyPosition: Position? {
        return positions.first
    }

    public func getCurrencyUnits(in currency: Currency) -> Amount {
        let totalUnits =
            positions
            .filter { $0.units.currency == currency }
            .reduce(0) { $0 + $1.units.number }
        return Amount(number: totalUnits, currency: currency)
    }

    /// Segregates positions by specified currencies.
    ///
    /// Separates the inventory into multiple inventories based on whether
    /// positions match the specified currencies. Unmatched currencies go
    /// into the nil key inventory.
    ///
    /// - Parameter currencies: The currencies to segregate by
    /// - Returns: A dictionary mapping currencies to their respective inventories
    func segregateUnits(by currencies: [Currency]) -> [Currency?: Inventory] {
        var perCurrencyDict = [Currency?: Inventory]()
        for currency in currencies {
            perCurrencyDict[currency] = Inventory()
        }
        perCurrencyDict[nil] = Inventory()
        for position in positions {
            let currency = position.units.currency
            let key = currencies.contains(currency) ? currency : nil
            perCurrencyDict[key]!.addPosition(position)
        }
        return perCurrencyDict
    }

    /// Splits the inventory by currency into separate inventories.
    ///
    /// Creates a separate inventory for each currency present in this inventory.
    /// Each resulting inventory contains only positions of a single currency.
    ///
    /// - Returns: A dictionary mapping currencies to inventories containing only that currency
    func split() -> [Currency: Inventory] {
        var perCurrencyDict = [Currency: Inventory]()
        for position in positions {
            let key = position.units.currency
            perCurrencyDict[key, default: Inventory()].addPosition(position)
        }
        return perCurrencyDict
    }

    /// Checks if all positions are within specified tolerances.
    ///
    /// Determines whether all position amounts are smaller than their
    /// respective tolerance values. Useful for checking if an inventory
    /// can be considered "balanced" or "empty" within tolerance limits.
    ///
    /// - Parameter tolerances: A dictionary mapping currencies to their tolerance values
    /// - Returns: True if all positions are within tolerance, false otherwise
    func isSmall(tolerances: [Currency: Decimal]) -> Bool {
        for position in positions {
            let tolerance = tolerances[position.units.currency, default: .zero]
            if abs(position.units.number) > tolerance {
                return false
            }
        }
        return true
    }

    /// Checks if all positions are within a uniform tolerance.
    ///
    /// Determines whether all position amounts are smaller than the
    /// specified tolerance value, regardless of currency.
    ///
    /// - Parameter tolerance: The tolerance value to check against
    /// - Returns: True if all positions are within tolerance, false otherwise
    func isSmall(tolerance: Decimal) -> Bool {
        for position in positions {
            if abs(position.units.number) > tolerance {
                return false
            }
        }
        return true
    }

    /// Return true if all the positions in the inventory are small.
    ///
    /// - Parameter tolerances: A dict of currency to the small number of units
    /// under which a position is considered small
    /// - Returns: A boolean
    func isSmall(tolerances: Interpolate.ToleranceMapping) -> Bool {
        for position in positions {
            let tolerance = tolerances.mapping[position.units.currency, default: 0.01]
            if abs(position.units.number) > tolerance {
                return false
            }
        }
        return true
    }

    /// Checks if the inventory contains mixed signs for any currency.
    ///
    /// A mixed inventory has both positive and negative positions
    /// in the same currency. This is useful for detecting when an
    /// inventory might require special handling or represents conflicting positions.
    ///
    /// - Returns: True if any currency has both positive and negative positions
    func isMixed() -> Bool {
        var currencySigns: [Currency: Bool] = [:]

        for position in positions {
            let currency = position.units.currency
            let sign = position.units.number >= 0

            if let prevSign = currencySigns[currency] {
                if sign != prevSign {
                    return true
                }
            } else {
                currencySigns[currency] = sign
            }
        }

        return false
    }

    public func reduce(by reducer: (Position) -> Amount) -> Inventory {
        var inventory = Inventory()
        for position in positions {
            inventory.addAmount(reducer(position))
        }
        return inventory
    }

    /// Returns a new inventory containing only positions in the specified unit currency.
    ///
    /// Lot/cost information is preserved for retained positions.
    ///
    /// - Parameter currency: The unit currency to retain
    /// - Returns: A filtered inventory
    public func filtered(by currency: Currency) -> Inventory {
        var inventory = Inventory()
        for position in positions where position.units.currency == currency {
            _ = inventory.addAmount(position.units, cost: position.cost)
        }
        return inventory
    }

    /// Checks if adding the given amount would reduce any position.
    ///
    /// Determines whether adding the specified amount to this inventory
    /// would reduce (partially or completely) any existing position by
    /// having an opposite sign in the same currency.
    ///
    /// - Parameter ramount: The amount to test for reduction
    /// - Returns: True if the amount would reduce an existing position
    func isReducedBy(_ ramount: Amount) -> Bool {
        if ramount.number == .zero {
            return false
        }

        for position in positions {
            let units = position.units
            if ramount.currency == units.currency && ramount.number.sign != units.number.sign {
                return true
            }
        }

        return false
    }

    @discardableResult
    public mutating func addAmount(_ units: Amount, cost: Cost? = nil) -> (Position?, MatchResult) {
        let key = PositionKey(currency: units.currency, cost: cost)
        if let index = cache.index(forKey: key) {
            let pos = cache.values[index]
            let booking: MatchResult = pos.units.number.sign != units.number.sign ? .reduced : .augmented

            let number = pos.units.number + units.number
            if number == .zero {
                cache.remove(at: index)
            } else {
                cache.values[index] = Position(
                    units: Amount(number: number, currency: units.currency),
                    cost: cost
                )
            }
            return (pos, booking)
        }

        if units.number == .zero {
            return (nil, .ignored)
        }

        let index = cache.keys.partitioningIndex(where: { $0 > key })
        cache.updateValue(
            Position(
                units: units,
                cost: cost
            ), forKey: key, insertingAt: index)
        return (nil, .created)
    }

    // Add a position to the inventory
    @discardableResult
    mutating func addPosition(_ position: Position) -> (Position?, MatchResult) {
        return addAmount(position.units, cost: position.cost)
    }

    @discardableResult
    mutating func addPosition(_ position: Posting<Cost>) -> (Position?, MatchResult) {
        return addAmount(position.units, cost: position.cost)
    }

    /// Adds all positions from another inventory to this inventory.
    ///
    /// Efficiently merges another inventory into this one by adding all
    /// its positions. If this inventory is empty, the operation is optimized
    /// by directly copying the other inventory's cache.
    ///
    /// - Parameter inventory: The inventory to add
    mutating func addInventory(_ inventory: Inventory) {
        if isEmpty {
            cache = inventory.cache
        } else {
            inventory.positions.forEach { addPosition($0) }
        }
    }
}

extension Inventory: Hashable, Equatable, Comparable {
    public func hash(into hasher: inout Hasher) {
        for (key, position) in cache {
            hasher.combine(key)
            hasher.combine(position)
        }
    }

    public static func < (lhs: Inventory, rhs: Inventory) -> Bool {
        let lkeys = lhs.cache.keys.sorted()
        let rkeys = rhs.cache.keys.sorted()
        var i = 0
        while true {
            guard i < rkeys.count else { return false }
            guard i < lkeys.count else { return true }
            if lkeys[i] < rkeys[i] { return true }
            i += 1
        }
    }

    public static func == (lhs: Inventory, rhs: Inventory) -> Bool {
        return lhs.cache == rhs.cache
    }

    public static func + (lhs: Inventory, rhs: Inventory) -> Inventory {
        var ret = lhs
        ret.addInventory(rhs)
        return ret
    }

    public prefix static func - (inventory: Inventory) -> Inventory {
        var negatedInventory = Inventory()
        for position in inventory.positions {
            var negatedPosition = position
            negatedPosition.units = -position.units
            negatedInventory.addPosition(negatedPosition)
        }
        return negatedInventory
    }

    public static func - (lhs: Inventory, rhs: Inventory) -> Inventory {
        return lhs + (-rhs)
    }

    public static func * (lhs: Inventory, rhs: Decimal) -> Inventory {
        var multipliedInventory = Inventory()
        for position in lhs.positions {
            var multipliedPosition = position
            multipliedPosition.units = .init(
                number: multipliedPosition.units.number * rhs,
                currency: multipliedPosition.units.currency
            )
            multipliedInventory.addPosition(multipliedPosition)
        }
        return multipliedInventory
    }

    // Absolute value
    public var absolute: Inventory {
        var absInventory = Inventory()
        for position in positions {
            var absPosition = position
            absPosition.units = .init(
                number: abs(position.units.number),
                currency: absPosition.units.currency
            )
            absInventory.addPosition(absPosition)
        }
        return absInventory
    }

    public var average: Inventory {
        struct GroupKey: Hashable {
            let currency: Currency
            let costCurrency: Currency?
        }

        var groups = [GroupKey: [Position]]()
        for position in positions {
            let key = GroupKey(
                currency: position.units.currency, costCurrency: position.cost?.currency)
            groups[key, default: []].append(position)
        }
        var averageInventory = Inventory()
        for (key, positions) in groups {
            let totalUnits: Decimal = positions.reduce(0) { $0 + $1.units.number }
            if totalUnits == .zero {
                continue
            }
            let unitsAmount = Amount(number: totalUnits, currency: key.currency)
            let cost: Cost?
            if let costCurrency = key.costCurrency {
                let totalCost: Decimal = positions.reduce(0) { $0 + $1.totalCost.number }
                let costNumber: Decimal =
                    totalUnits == .zero ? .greatestFiniteMagnitude : totalCost / totalUnits
                let minDate: Date? = positions.reduce(nil) { result, pos in
                    guard let posDate = pos.cost?.date else { return result }
                    guard let result else { return posDate }
                    return min(result, posDate)
                }
                cost = Cost(number: costNumber, currency: costCurrency, date: minDate)
            } else {
                cost = nil
            }
            averageInventory.addAmount(unitsAmount, cost: cost)
        }
        return averageInventory
    }
}

#if DEBUG
extension Inventory: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        let matches = value.matches(of: #/([-+]?[0-9,.]+\s+[A-Z]+\s*(?:{[^}]*})?)\s*,?\s*/#).map {
            String($0.1)
        }
        var positions = [Position]()
        for match in matches {
            positions.append(Position(stringLiteral: match))
        }
        self.init(positions: positions)
    }
}
#endif
