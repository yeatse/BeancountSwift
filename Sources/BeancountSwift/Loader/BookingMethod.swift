//
//  BookingMethod.swift
//  
//
//  Created by Yeatse on 2023/12/24.
//

import Foundation

/// A set of valid booking method names for positions on accounts.
/// See http://furius.ca/beancount/doc/inventories for a full explanation.
public enum Booking: String {
    /// Reject ambiguous matches with an error.
    case STRICT

    /// Strict booking method, but disambiguate further with sizes. Reject
    /// ambiguous matches with an error but if a lot matches the size exactly,
    /// accept it the oldest.
    case STRICT_WITH_SIZE

    /// Disable matching and accept the creation of mixed inventories.
    case NONE

    /// Average cost booking: merge all matching lots before and after.
    case AVERAGE

    /// First-in first-out in the case of ambiguity.
    case FIFO

    /// Last-in first-out in the case of ambiguity.
    case LIFO

    /// Highest-in first-out in the case of ambiguity.
    case HIFO
}

extension Booking {
    var method: BookingMethod {
        switch self {
            case .STRICT: strictBooking
            case .STRICT_WITH_SIZE: fatalError()
            case .NONE: fatalError()
            case .AVERAGE: fatalError()
            case .FIFO: fatalError()
            case .LIFO: fatalError()
            case .HIFO: fatalError()
        }
    }
    
    
}

extension Booker {
    func handleAmbiguousMatches(entry: Directive<CostSpec>,
                                posting: Posting<CostSpec>,
                                matches: [Position],
                                method: Booking) ->
    (reductions: [Posting<Cost>], matches: [Position], errors: [Error]) {
        #if false
        let result = method(entry, posting, matches)
        var errors = result.errors
        if result.insufficient {
            errors.append(BookingError.ambiguousMatch(entry))
        }
        return (result.bookedReductions, result.bookedMatches, errors)
        #endif
        fatalError()
    }
}

struct BookingMethodStore {
    var mappings: [Account: Booking]
    var defaultMethod: Booking
    
    subscript(account: Account) -> Booking {
        mappings[account, default: defaultMethod]
    }
}

enum BookingError: Error {
    case reduction(Directive<CostSpec>)
    case ambiguousMatch(Transaction<CostSpec>)
}

typealias BookingMethod = (Transaction<CostSpec>, Posting<CostSpec>, Array<Position>) -> (bookedReductions: [Posting<Cost>], bookedMatches: [Position], errors: [Error], insufficient: Bool)

let strictBooking: BookingMethod = { entry, posting, matches in
    var bookedReductions = [Posting<Cost>]()
    var bookedMatches = [Position]()
    var errors = [Error]()
    var insufficient = false
    
    if matches.count > 1 {
        let sumMatches = matches.reduce(Decimal(0)) { val, pos in
            val + pos.units.number
        }
        if sumMatches == -posting.units.number {
            bookedReductions += matches.map { match in
                return .init(account: posting.account,
                             units: -match.units,
                             cost: match.cost,
                             price: posting.price,
                             flag: posting.flag,
                             meta: posting.meta,
                             comment: posting.comment)
            }
        } else {
            errors.append(BookingError.ambiguousMatch(entry))
        }
    } else {
        let match = matches[0]
        let sign: Decimal = posting.units.number < 0 ? -1 : 1
        let number = min(abs(match.units.number), abs(posting.units.number))
        let matchUnits = Amount(number: number * sign, currency: match.units.currency)
        
        var posting = Posting(account: posting.account,
                              units: matchUnits,
                              cost: match.cost,
                              price: posting.price,
                              flag: posting.flag,
                              meta: posting.meta,
                              comment: posting.comment)
        bookedReductions.append(posting)
        bookedMatches.append(match)
        insufficient = matchUnits.number != posting.units.number
    }
    
    return (bookedReductions, bookedMatches, errors, insufficient)
}

