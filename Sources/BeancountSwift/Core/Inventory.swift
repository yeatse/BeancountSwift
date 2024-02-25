//
//  Inventory.swift
//
//
//  Created by Yeatse on 2023/12/24.
//

import Foundation

/// https://beancount.github.io/docs/beancount_design_doc.html#inventory
public struct Inventory {
    fileprivate var cache: [PositionKey: Position] = [:]
    
    init(positions: [Position] = []) {
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
    
    enum MatchResult {
        case created
        case reduced
        case augmented
        case ignored
    }
}

extension Inventory {
    var isEmpty: Bool {
        positions.isEmpty
    }
    
    var positions: some RandomAccessCollection<Position> {
        cache.sorted { $0.key < $1.key }.map(\.value)
    }
    
    var currencies: Set<Currency> {
        Set(cache.keys.map(\.currency))
    }
    
    var costCurrencies: Set<Currency> {
        Set(cache.keys.compactMap(\.cost?.currency))
    }
    
    var currencyPairs: Set<Position.CurrencyPair> {
        Set(cache.values.map(\.currencyPair))
    }
    
    var onlyPosition: Position? {
        return positions.first
    }
    
    public func getCurrencyUnits(in currency: Currency) -> Amount {
        let totalUnits = positions
            .filter { $0.units.currency == currency }
            .reduce(0) { $0 + $1.units.number }
        return Amount(number: totalUnits, currency: currency)
    }
    
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
    
    func split() -> [Currency: Inventory] {
        var perCurrencyDict = [Currency: Inventory]()
        for position in positions {
            let key = position.units.currency
            perCurrencyDict[key, default: Inventory()].addPosition(position)
        }
        return perCurrencyDict
    }
    
    func isSmall(tolerances: [Currency: Decimal]) -> Bool {
        for position in positions {
            let tolerance = tolerances[position.units.currency, default: .zero]
            if abs(position.units.number) > tolerance {
                return false
            }
        }
        return true
    }
    
    func isSmall(tolerance: Decimal) -> Bool {
        for position in positions {
            if abs(position.units.number) > tolerance {
                return false
            }
        }
        return true
    }
    
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
    mutating func addAmount(_ units: Amount, cost: Cost? = nil) -> (Position?, MatchResult) {
        let key = PositionKey(currency: units.currency, cost: cost)
        let booking: MatchResult
        if let pos = cache[key] {
            if pos.units.number.sign != units.number.sign {
                booking = .reduced
            } else {
                booking = .augmented
            }
            
            let number = pos.units.number + units.number
            if number == .zero {
                cache.removeValue(forKey: key)
            } else {
                cache[key] = Position(
                    units: Amount(number: number, currency: units.currency),
                    cost: cost
                )
            }
            return (pos, booking)
        } else {
            if units.number == .zero {
                booking = .ignored
            } else {
                cache[key] = Position(units: units, cost: cost)
                booking = .created
            }
            return (nil, booking)
        }
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
    
    mutating func addInventory(_ inventory: Inventory) {
        if isEmpty {
            cache = inventory.cache
        } else {
            inventory.positions.forEach { addPosition($0) }
        }
    }
}

extension Inventory: Equatable, Comparable {
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
    
    static func + (lhs: Inventory, rhs: Inventory) -> Inventory {
        var ret = lhs
        ret.addInventory(rhs)
        return ret
    }
    
    prefix static func - (inventory: Inventory) -> Inventory {
        var negatedInventory = Inventory()
        for position in inventory.positions {
            var negatedPosition = position
            negatedPosition.units = -position.units
            negatedInventory.addPosition(negatedPosition)
        }
        return negatedInventory
    }
    
    static func * (lhs: Inventory, rhs: Decimal) -> Inventory {
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
    var absolute: Inventory {
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
    
    var average: Inventory {
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
                let minDate: Date =
                positions.reduce(nil) { result, pos in
                    guard let posDate = pos.cost?.date else { return result }
                    guard let result else { return posDate }
                    return min(result, posDate)
                } ?? .distantPast
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
