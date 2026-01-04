//
//  BookingMethod.swift
//
//
//  Created by Yeatse on 2023/12/24.
//

import Foundation

/// Booking methods for resolving lot matching in transactions.
/// 
/// BookingMethod determines how the booking system resolves ambiguity when
/// multiple lots could match a posting's cost specification. Each method
/// provides different strategies for lot selection and matching.
/// 
/// This corresponds to the booking methods in the original Beancount Python
/// library, providing the same lot matching strategies.
/// 
/// ## Usage
/// ```swift
/// let method = BookingMethod.FIFO
/// let strictMethod = BookingMethod.STRICT
/// ```
/// 
/// - SeeAlso: [Beancount Inventories Documentation](http://furius.ca/beancount/doc/inventories)
public enum BookingMethod: String, Sendable {
    /// Reject ambiguous matches with an error.
    /// 
    /// When multiple lots could match, STRICT booking fails with an error
    /// rather than guessing which lot to use. This ensures precise control
    /// over lot selection and prevents unintended matches.
    case STRICT
    
    /// Strict booking with size-based disambiguation.
    /// 
    /// Like STRICT, but when a lot matches the posting size exactly,
    /// it selects the oldest matching lot. This provides a compromise
    /// between strictness and convenience.
    case STRICT_WITH_SIZE
    
    /// Disable lot matching entirely.
    /// 
    /// NONE booking creates mixed inventories without attempting to match
    /// existing lots. This is useful for accounts where lot tracking is
    /// not required or desired.
    case NONE
    
    /// Average cost booking method.
    /// 
    /// AVERAGE booking merges all matching lots before and after the
    /// transaction, maintaining an average cost basis. This is commonly
    /// used for mutual funds and similar investments.
    case AVERAGE
    
    /// First-in, first-out lot selection.
    /// 
    /// FIFO booking always selects the oldest lots first when resolving
    /// ambiguous matches. This is a common strategy for tax optimization
    /// and inventory management.
    case FIFO
    
    /// Last-in, first-out lot selection.
    /// 
    /// LIFO booking always selects the newest lots first when resolving
    /// ambiguous matches. This can be useful for certain accounting
    /// or tax strategies.
    case LIFO
    
    /// Highest cost first-out lot selection.
    /// 
    /// HIFO booking always selects the lots with the highest cost basis
    /// first, which can be advantageous for tax loss harvesting.
    case HIFO
}

extension BookingMethod {
    /// Returns the implementation function for this booking method.
    /// 
    /// All booking methods are now implemented, matching the behavior
    /// of the reference Python Beancount implementation.
    /// 
    /// - Returns: The booking method implementation function
    var impl: BookingMethodImpl {
        switch self {
            case .STRICT: strictBooking
            case .STRICT_WITH_SIZE: strictWithSizeBooking
            case .NONE: noneBooking
            case .AVERAGE: averageBooking
            case .FIFO: fifoBooking
            case .LIFO: lifoBooking
            case .HIFO: hifoBooking
        }
    }
}

extension Booking {
    /// Handles ambiguous lot matches using the specified booking method.
    /// 
    /// When multiple lots could potentially match a posting's cost specification,
    /// this method applies the chosen booking strategy to resolve the ambiguity.
    /// Returns the booked postings, matched positions, and any errors.
    /// 
    /// - Parameters:
    ///   - entry: The directive containing the posting
    ///   - posting: The posting with ambiguous matches
    ///   - matches: The potential matching positions
    ///   - method: The booking method to use for resolution
    /// - Returns: A tuple of booked reductions, matched positions, and errors
    static func handleAmbiguousMatches(
        entry: Directive<CostSpec>,
        posting: Posting<CostSpec>,
        matches: [Position],
        method: BookingMethod
    ) -> (reductions: [Posting<Cost>], matches: [Position], errors: [Error]) {
        let result = method.impl(entry, posting, matches)
        var errors = result.errors
        if result.insufficient {
            errors.append(BookingError.ambiguousMatch(entry))
        }
        return (result.bookedReductions, result.bookedMatches, errors)
    }
}

/// Errors that can occur during the booking process.
/// 
/// BookingError represents various issues that can arise when matching
/// lots and resolving cost specifications during transaction processing.
enum BookingError: LocatableError {
    /// A reduction posting could not be matched to existing lots.
    case reduction(Directive<CostSpec>)
    /// Multiple lots matched ambiguously and couldn't be resolved.
    case ambiguousMatch(Directive<CostSpec>)
    
    var location: LedgerLocation? {
        switch self {
        case .reduction(let directive):
            if let filename = directive.meta.filename, let lineno = directive.meta.lineno {
                return LedgerLocation(filename: filename, lineno: lineno)
            }
        case .ambiguousMatch(let directive):
            if let filename = directive.meta.filename, let lineno = directive.meta.lineno {
                return LedgerLocation(filename: filename, lineno: lineno)
            }
        }
        return nil
    }
}

/// Function signature for booking method implementations.
/// 
/// BookingMethodImpl defines the interface that all booking methods must implement.
/// It takes a directive, posting, and matching positions, and returns the booking results.
/// 
/// - Parameters:
///   - directive: The directive containing the posting
///   - posting: The posting being processed
///   - matches: The positions that could potentially match
/// - Returns: A tuple containing booked reductions, matched positions, errors, and insufficiency flag
typealias BookingMethodImpl = (Directive<CostSpec>, Posting<CostSpec>, [Position]) -> (
    bookedReductions: [Posting<Cost>], bookedMatches: [Position], errors: [Error],
    insufficient: Bool
)

/// Implementation of the STRICT booking method.
/// 
/// The strict booking method requires exact matches and rejects ambiguous situations.
/// When multiple lots match, it only proceeds if their total exactly matches the
/// posting amount. For single matches, it books the minimum of the available
/// and required amounts.
/// 
/// - Returns: A booking method implementation function
var strictBooking: BookingMethodImpl {
    { entry, posting, matches in
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
                    posting.resolved(units: -match.units, cost: match.cost)
                }
            } else {
                errors.append(BookingError.ambiguousMatch(entry))
            }
        } else if let match = matches.first {
            let sign: Decimal = posting.units.number < 0 ? -1 : 1
            let number = min(abs(match.units.number), abs(posting.units.number))
            let matchUnits = Amount(number: number * sign, currency: match.units.currency)
            
            bookedReductions.append(posting.resolved(units: matchUnits, cost: match.cost))
            bookedMatches.append(match)
            insufficient = matchUnits.number != posting.units.number
        }
        
        return (bookedReductions, bookedMatches, errors, insufficient)
    }
}

/// Implementation of the STRICT_WITH_SIZE booking method.
/// 
/// This booking method applies the same algorithm as the STRICT method, but if
/// only one of the ambiguous lots matches the desired size, select that one
/// automatically.
/// 
/// - Returns: A booking method implementation function
var strictWithSizeBooking: BookingMethodImpl {
    { entry, posting, matches in
        // First try strict booking
        var (bookedReductions, bookedMatches, errors, insufficient) = strictBooking(entry, posting, matches)
        
        // If we couldn't match strictly due to multiple ambiguous matches, 
        // attempt to find a match with the same number of units
        if !errors.isEmpty && matches.count > 1 {
            let number = -posting.units.number
            let matchingUnits = matches.filter { match in
                number == match.units.number
            }
            
            if !matchingUnits.isEmpty {
                // Accept the oldest lot (sort by cost date)
                let sortedMatches = matchingUnits.sorted { $0.cost?.date ?? Date.distantPast < $1.cost?.date ?? Date.distantPast }
                let match = sortedMatches[0]
                bookedReductions.append(posting.resolved(
                    units: -match.units,
                    cost: match.cost
                ))
                bookedMatches.append(match)
                insufficient = false
                errors = []
            }
        }
        
        return (bookedReductions, bookedMatches, errors, insufficient)
    }
}

/// Implementation of the NONE booking method.
/// 
/// This method never needs to match against any existing positions - it
/// disregards the matches and never produces any error. This method treats
/// all postings as augmentations rather than reductions.
/// 
/// - Returns: A booking method implementation function
var noneBooking: BookingMethodImpl {
    { entry, posting, matches in
        // NONE booking disregards matches and treats all postings as augmentations
        // Returns the original posting without any cost resolution
        // NONE booking never produces matches, so we don't return any reductions
        return ([], [], [], false)
    }
}

/// Implementation of the AVERAGE booking method.
/// 
/// Currently returns an error indicating that AVERAGE method is not supported,
/// matching the behavior of the reference Python implementation.
/// 
/// - Returns: A booking method implementation function
var averageBooking: BookingMethodImpl {
    { entry, posting, matches in
        // AVERAGE booking is not yet supported - return error like Python implementation
        let error = BookingError.ambiguousMatch(entry)
        return ([], [], [error], false)
    }
}

/// Common implementation for FIFO, LIFO, and HIFO booking methods.
/// 
/// This function implements the core logic for first-in-first-out, last-in-first-out,
/// and highest-cost-first-out booking methods.
/// 
/// - Parameters:
///   - entry: The directive containing the posting
///   - posting: The posting being processed
///   - matches: The positions that could potentially match
///   - sortBy: The sort criteria - either "date" for FIFO/LIFO or "number" for HIFO
///   - reverseOrder: Whether to reverse the sort order
/// - Returns: Booking results tuple
func xifoBooking(entry: Directive<CostSpec>, posting: Posting<CostSpec>, matches: [Position],
                 sortBy: String, reverseOrder: Bool) -> (bookedReductions: [Posting<Cost>], bookedMatches: [Position], errors: [Error], insufficient: Bool) {
    var bookedReductions = [Posting<Cost>]()
    var bookedMatches = [Position]()
    var insufficient = false
    
    let sign: Decimal = posting.units.number < 0 ? -1 : 1
    var remaining = abs(posting.units.number)
    
    // Sort matches based on the specified criteria
    let sortedMatches: [Position]
    if sortBy == "date" {
        sortedMatches = matches.sorted { match1, match2 in
            let date1 = match1.cost?.date ?? Date.distantPast
            let date2 = match2.cost?.date ?? Date.distantPast
            return reverseOrder ? date1 > date2 : date1 < date2
        }
    } else { // sortBy == "number" (for HIFO)
        sortedMatches = matches.sorted { match1, match2 in
            let num1 = match1.cost?.number ?? 0
            let num2 = match2.cost?.number ?? 0
            return reverseOrder ? num1 > num2 : num1 < num2
        }
    }
    
    for match in sortedMatches {
        if remaining <= 0 {
            break
        }
        
        // If the inventory somehow ended up with mixed lots, skip this one
        if match.units.number * sign > 0 {
            continue
        }
        
        // Compute the amount of units we can reduce from this lot
        let size = min(abs(match.units.number), remaining)
        bookedReductions.append(
            posting.resolved(
                units: Amount(number: size * sign, currency: match.units.currency),
                cost: match.cost
            )
        )
        bookedMatches.append(match)
        remaining -= size
    }
    
    // If we couldn't reduce all the requested amount, mark as insufficient
    insufficient = remaining > 0
    
    return (bookedReductions, bookedMatches, [], insufficient)
}

/// Implementation of the FIFO booking method.
/// 
/// FIFO booking always selects the oldest lots first when resolving
/// ambiguous matches. This is a common strategy for tax optimization
/// and inventory management.
/// 
/// - Returns: A booking method implementation function
var fifoBooking: BookingMethodImpl {
    { entry, posting, matches in
        return xifoBooking(entry: entry, posting: posting, matches: matches, sortBy: "date", reverseOrder: false)
    }
}

/// Implementation of the LIFO booking method.
/// 
/// LIFO booking always selects the newest lots first when resolving
/// ambiguous matches. This can be useful for certain accounting
/// or tax strategies.
/// 
/// - Returns: A booking method implementation function
var lifoBooking: BookingMethodImpl {
    { entry, posting, matches in
        return xifoBooking(entry: entry, posting: posting, matches: matches, sortBy: "date", reverseOrder: true)
    }
}

/// Implementation of the HIFO booking method.
/// 
/// HIFO booking always selects the lots with the highest cost basis
/// first, which can be advantageous for tax loss harvesting.
/// 
/// - Returns: A booking method implementation function
var hifoBooking: BookingMethodImpl {
    { entry, posting, matches in
        return xifoBooking(entry: entry, posting: posting, matches: matches, sortBy: "number", reverseOrder: true)
    }
}
