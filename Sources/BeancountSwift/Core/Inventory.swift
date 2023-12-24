//
//  File.swift
//  
//
//  Created by Yeatse on 2023/12/24.
//

import Foundation

/// https://beancount.github.io/docs/beancount_design_doc.html#inventory
public struct Inventory {
    private var cache: [PositionKey: Position] = [:]
    
    init(positions: [Position] = []) {
        positions.forEach { addPosition($0) }
    }
    
    var positions: any Collection<Position> {
        cache.values
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

extension Inventory {
    var isEmpty: Bool {
        positions.isEmpty
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
        var negatedInventory = Inventory()
        for position in positions {
            var negatedPosition = position
            negatedPosition.units = -position.units
            negatedInventory.addPosition(negatedPosition)
        }
        return negatedInventory
    }
    
    // Absolute value
    var absolute: Inventory {
        var absInventory = Inventory()
        for position in positions {
            var absPosition = position
            absPosition.units = .init(number: abs(position.units.number),
                                      currency: absPosition.units.currency)
            absInventory.addPosition(absPosition)
        }
        return absInventory
    }
    
    // Multiplication by a scalar
    func multiplied(by scalar: Decimal) -> Inventory {
        var multipliedInventory = Inventory()
        for position in positions {
            var multipliedPosition = position
            multipliedPosition.units = .init(number: multipliedPosition.units.number * scalar,
                                             currency: multipliedPosition.units.currency)
            multipliedInventory.addPosition(multipliedPosition)
        }
        return multipliedInventory
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
                cache[key] = Position(units: Amount(number: number, currency: units.currency), cost: cost)
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
    
    // Other methods like isSmall, isMixed, reduce, etc., can be added similarly
    // ...
    
    
}
