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
    /// Currently only STRICT booking is fully implemented, with other
    /// methods marked for future implementation.
    /// 
    /// - Returns: The booking method implementation function
    var impl: BookingMethodImpl {
        switch self {
            case .STRICT: strictBooking
            case .STRICT_WITH_SIZE: fatalError("STRICT_WITH_SIZE booking not yet implemented")
            case .NONE: fatalError("NONE booking not yet implemented")
            case .AVERAGE: fatalError("AVERAGE booking not yet implemented")
            case .FIFO: fatalError("FIFO booking not yet implemented")
            case .LIFO: fatalError("LIFO booking not yet implemented")
            case .HIFO: fatalError("HIFO booking not yet implemented")
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
    func handleAmbiguousMatches(
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

/// Storage for per-account booking method configurations.
/// 
/// BookingMethodStore manages booking method assignments for individual accounts,
/// with a fallback to a default method for accounts without specific assignments.
struct BookingMethodStore {
    /// Account-specific booking method assignments.
    var mappings: [Account: BookingMethod]
    /// The default booking method for accounts without specific assignments.
    var defaultMethod: BookingMethod
    
    /// Gets the booking method for an account.
    /// 
    /// Returns the specific method for the account if assigned,
    /// otherwise returns the default method.
    /// 
    /// - Parameter account: The account to query
    /// - Returns: The booking method for the account
    subscript(account: Account) -> BookingMethod {
        mappings[account, default: defaultMethod]
    }
}

/// Errors that can occur during the booking process.
/// 
/// BookingError represents various issues that can arise when matching
/// lots and resolving cost specifications during transaction processing.
enum BookingError: Error {
    /// A reduction posting could not be matched to existing lots.
    case reduction(Directive<CostSpec>)
    /// Multiple lots matched ambiguously and couldn't be resolved.
    case ambiguousMatch(Directive<CostSpec>)
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
                    return .init(
                        account: posting.account,
                        units: -match.units,
                        cost: match.cost,
                        price: posting.price,
                        flag: posting.flag,
                        meta: posting.meta,
                        comment: posting.comment
                    )
                }
            } else {
                errors.append(BookingError.ambiguousMatch(entry))
            }
        } else if let match = matches.first {
            let sign: Decimal = posting.units.number < 0 ? -1 : 1
            let number = min(abs(match.units.number), abs(posting.units.number))
            let matchUnits = Amount(number: number * sign, currency: match.units.currency)
            
            let updatedPosting = Posting(
                account: posting.account,
                units: matchUnits,
                cost: match.cost,
                price: posting.price,
                flag: posting.flag,
                meta: posting.meta,
                comment: posting.comment
            )
            bookedReductions.append(updatedPosting)
            bookedMatches.append(match)
            insufficient = matchUnits.number != posting.units.number
        }
        
        return (bookedReductions, bookedMatches, errors, insufficient)
    }
}
