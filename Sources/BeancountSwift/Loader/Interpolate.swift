//
//  Interpolate.swift
//
//
//  Created by Yeatse on 2023/12/25.
//

/// Provides transaction interpolation and automatic posting completion.
/// 
/// This module implements the interpolation logic for completing incomplete
/// transactions by automatically filling in missing posting amounts. This
/// corresponds to the interpolation functionality in the original Beancount
/// Python library.

import Foundation

/// Configuration for balance checking tolerances.
/// 
/// ToleranceConfiguration defines the settings used when checking whether
/// transaction postings balance correctly, allowing for small rounding
/// differences and floating-point precision issues.
/// 
/// This corresponds to the tolerance configuration in the original Beancount
/// Python library's interpolation system.
/// 
/// ## Usage
/// ```swift
/// let config = ToleranceConfiguration(
///     interFromCost: true,
///     multiplier: 0.5,
///     defaultTolerances: ["USD": 0.01]
/// )
/// ```
public struct ToleranceConfiguration: Sendable {
    /// Whether to infer tolerances from cost information.
    public var interFromCost: Bool
    /// Multiplier for inferred tolerances.
    public var multiplier: Decimal
    /// Default tolerance values for specific currencies.
    public var defaultTolerances: [Currency: Decimal]
    
    /// Default tolerance configuration.
    /// 
    /// Provides reasonable defaults: no cost inference, 0.5 multiplier,
    /// and no currency-specific tolerances.
    static let `default` = ToleranceConfiguration(
        interFromCost: false,
        multiplier: Decimal(string: "0.5")!,
        defaultTolerances: [:]
    )
}

/// Engine for transaction interpolation and automatic posting completion.
/// 
/// Interpolate implements the core logic for completing incomplete transactions
/// by filling in missing amounts and checking balance tolerances. This ensures
/// that transactions balance according to double-entry accounting principles.
enum Interpolate {
    /// Maps currencies to their tolerance values for balance checking.
    /// 
    /// ToleranceMapping provides currency-specific tolerances with a fallback
    /// default tolerance for currencies not explicitly configured.
    struct ToleranceMapping {
        /// Currency-specific tolerance mappings.
        let mapping: [Currency: Decimal]
        /// Default tolerance for unmapped currencies.
        let `default`: Decimal
    }
    
    /// Metadata key for marking automatically generated residual postings.
    static let automaticResidual = "__residual__"
    /// Metadata key for marking automatically generated postings.
    static let automaticMeta = "__automatic__"
    
    /// Infers appropriate tolerances from posting amounts and options.
    /// 
    /// Analyzes the postings to determine suitable tolerance values for
    /// balance checking, taking into account the precision of amounts
    /// and any configuration options.
    /// 
    /// - Parameters:
    ///   - postings: The postings to analyze
    ///   - options: Configuration options
    /// - Returns: A tolerance mapping for balance checking
    static func inferTolerances<T: PostingCost>(postings: [Posting<T>], options: Options)
    -> ToleranceMapping
    {
        return .init(mapping: [:], default: .zero)
    }
    
    /// Computes the residual amounts needed to balance a transaction.
    /// 
    /// Calculates the net imbalance in a transaction by summing all posting
    /// weights, excluding any automatically generated residual postings.
    /// The result indicates what amounts need to be added to balance the transaction.
    /// 
    /// - Parameter postings: The booked postings to analyze
    /// - Returns: An inventory representing the residual imbalance
    static func computeResidual(postings: [Posting<Cost>]) -> Inventory {
        var inventory = Inventory()
        for posting in postings {
            if let meta = posting.meta, meta[Interpolate.automaticResidual, default: .bool(false)] == .bool(true) {
                continue
            }
            inventory.addAmount(posting.weight)
        }
        return inventory
    }
}
