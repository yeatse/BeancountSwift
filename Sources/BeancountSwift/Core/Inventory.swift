//
//  Inventory.swift
//
//
//  Created by Yeatse on 2023/12/24.
//

import Foundation

/// https://beancount.github.io/docs/beancount_design_doc.html#inventory
public class Inventory {
    fileprivate var cache: [PositionKey: Position] = [:]

    init(positions: [Position] = []) {
        positions.forEach { addPosition($0) }
    }

    struct PositionKey: Hashable {
        let currency: Currency
        let cost: Cost?
    }

    enum MatchResult {
        case created
        case reduced
        case augmented
        case ignored
    }
}

extension Inventory: NSCopying {
    public func copy(with zone: NSZone? = nil) -> Any {
        let copied = Inventory()
        copied.cache = cache
        return copied
    }
}

extension Inventory {
    var isEmpty: Bool {
        positions.isEmpty
    }

    var positions: any Collection<Position> {
        cache.values
    }

    var currencies: any Collection<Currency> {
        cache.keys.map { $0.currency }
    }

    var costCurrencies: any Collection<Currency> {
        cache.keys.compactMap { $0.cost?.currency }
    }

    var currencyPairs: any Collection<(Currency, Currency?)> {
        cache.values.map { $0.currencyPair }
    }

    var onlyPosition: Position? {
        return self.positions.first
    }

    func getCurrencyUnits(in currency: Currency) -> Amount {
        let totalUnits =
            positions
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
            let inventory = perCurrencyDict[key, default: Inventory()]
            inventory.addPosition(position)
            perCurrencyDict[key] = inventory
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

    func negated() -> Inventory {
        let negatedInventory = Inventory()
        for position in positions {
            var negatedPosition = position
            negatedPosition.units = -position.units
            negatedInventory.addPosition(negatedPosition)
        }
        return negatedInventory
    }

    // Absolute value
    var absolute: Inventory {
        let absInventory = Inventory()
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

    // Multiplication by a scalar
    func multiplied(by scalar: Decimal) -> Inventory {
        let multipliedInventory = Inventory()
        for position in positions {
            var multipliedPosition = position
            multipliedPosition.units = .init(
                number: multipliedPosition.units.number * scalar,
                currency: multipliedPosition.units.currency
            )
            multipliedInventory.addPosition(multipliedPosition)
        }
        return multipliedInventory
    }

    @discardableResult
    func addAmount(_ units: Amount, cost: Cost? = nil) -> (Position?, MatchResult) {
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
    func addPosition(_ position: Position) -> (Position?, MatchResult) {
        return addAmount(position.units, cost: position.cost)
    }

    @discardableResult
    func addPosition(_ position: Posting<Cost>) -> (Position?, MatchResult) {
        return addAmount(position.units, cost: position.cost)
    }
}
