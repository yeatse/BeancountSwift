//
//  Loader.swift
//
//
//  Created by Yeatse on 2023/12/21.
//
import Foundation

/// Protocol for providing file content to the loader.
/// 
/// This protocol abstracts file access, allowing different content providers
/// for various use cases (local files, remote resources, test data, etc.).
public protocol ContentProviding {
    /// Provides content for the specified file path.
    /// 
    /// - Parameter file: The file path to read
    /// - Returns: The file content as a string
    /// - Throws: Any error that occurs during file reading
    func provideContent(for file: String) throws -> String
}

/// Represents a parsed Beancount ledger with all its components.
/// 
/// Contains the parsed options, plugins, directives, and any errors that
/// occurred during parsing or processing. This is the primary result type
/// returned by the loader.
/// 
/// ## Usage
/// ```swift
/// let ledger = try loader.load(file: "ledger.beancount", contentProvider: provider)
/// print("Loaded \(ledger.directives.count) directives")
/// print("Found \(ledger.errors.count) errors")
/// ```
public struct ParsedLedger<T: PostingCost>: Sendable {
    /// The parsed options configuration.
    public var options: Options
    /// List of active plugins.
    public var plugins: [Plugin]
    /// The ledger directives (transactions, opens, etc.).
    public var directives: [Directive<T>]
    /// Any errors encountered during processing.
    public var errors: [Error]
}

/// The main loader for processing Beancount files.
/// 
/// The Loader orchestrates the entire process of loading a Beancount file:
/// parsing, booking (lot matching), plugin processing, and validation.
/// It provides a high-level interface for converting Beancount text files
/// into structured data.
///
/// This corresponds to the loading functionality in the original Beancount
/// Python library, implementing the complete Beancount processing pipeline.
/// 
/// ## Usage
/// ```swift
/// let ledger = try Loader.load(file: "accounts.beancount", contentProvider: FileContentProvider())
/// ```
/// 
/// - SeeAlso: [Beancount Design Doc - Loader](http://furius.ca/beancount/doc/design_doc.html#loader)
public enum Loader {
    private static let prologue: [Plugin] = []
    private static let epilogue: [Plugin] = [
        .init(name: PadPlugin.name, config: nil),
        .init(name: BalanceCheckPlugin.name, config: nil)
    ]
    
    private static func transform(ledger: ParsedLedger<Cost>) -> ParsedLedger<Cost> {
        var result = ledger
        for plugin in prologue + ledger.plugins + epilogue {
            let (entries, errors) = plugin.process(
                entries: result.directives,
                options: result.options
            )
            result.directives = entries
            result.errors += errors
        }
        result.directives.sort()
        return result
    }
    
    private static func validate(ledger: ParsedLedger<Cost>) -> ParsedLedger<Cost> {
        let validationErrors = Validation.validate(entries: ledger.directives, options: ledger.options)
        var result = ledger
        result.errors += validationErrors
        return result
    }
    
    /// Loads and processes a Beancount file through the complete pipeline.
    /// 
    /// This method performs the full Beancount loading process:
    /// 1. **Parsing**: Converts text to structured directives
    /// 2. **Booking**: Matches lots and resolves cost specifications
    /// 3. **Transformation**: Runs plugins (pad, balance check, etc.)
    /// 4. **Validation**: Performs final validation checks
    /// 
    /// - Parameters:
    ///   - file: The main Beancount file to load
    ///   - contentProvider: Provider for file content access
    /// - Returns: A `ParsedLedger` containing all processed data and any errors
    /// - Throws: Errors from file access or critical parsing failures
    /// 
    /// ## Example
    /// ```swift
    /// let ledger = try Loader.load(file: "main.beancount", contentProvider: FileContentProvider())
    /// 
    /// // Process results
    /// for directive in ledger.directives {
    ///     // Handle directive
    /// }
    /// 
    /// // Check for errors
    /// if !ledger.errors.isEmpty {
    ///     print("Found \(ledger.errors.count) errors")
    /// }
    /// ```
    public static func load(file: String, contentProvider: ContentProviding) throws -> ParsedLedger<Cost> {
        // parsing
        let parsedResult = try Parser.parse(file: file, contentProvider: contentProvider)

        // booking
        let bookedLedger = Booking.book(ledger: parsedResult)
        
        // transforming
        let transformedLedger = transform(ledger: bookedLedger)
        
        // validation
        return validate(ledger: transformedLedger)
    }
}
