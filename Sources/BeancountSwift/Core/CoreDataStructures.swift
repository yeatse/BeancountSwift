//
//  CoreDataStructures.swift
//
//
//  Created by Yeatse on 2023/12/21.
//
import Foundation
import SwiftTreeSitter
import OrderedCollections

/// A currency or commodity identifier in Beancount.
/// 
/// Currencies represent units of value in the accounting system. They can be
/// traditional currencies (USD, EUR), commodities (gold, oil), or financial
/// instruments (stocks, bonds). Currency names must follow Beancount naming
/// conventions using capital letters, numbers, and limited special characters.
///
/// This corresponds to commodities in the original Beancount Python library,
/// representing any unit that can have value attached to it.
///
/// ## Usage
/// ```swift
/// let usd = Currency(id: "USD")           // Traditional currency
/// let stock = Currency(id: "AAPL")        // Stock symbol
/// let commodity = Currency(id: "/GOLD")   // Commodity with path syntax
/// ```
///
/// - SeeAlso: [Beancount Design Doc - Commodity](https://beancount.github.io/docs/beancount_design_doc.html#commodity)
public struct Currency: Identifiable, Hashable, Sendable {
    /// The currency or commodity identifier (e.g., "USD", "AAPL", "/GOLD").
    public var id: String
    
    /// Creates a currency with the specified identifier.
    /// 
    /// - Parameter id: The currency identifier following Beancount naming conventions
    public init(id: String) {
        self.id = id
    }
}

extension Currency: ExpressibleByStringLiteral {
    /// Creates a currency from a string literal.
    /// 
    /// - Parameter value: The currency identifier as a string
    /// 
    /// ## Example
    /// ```swift
    /// let usd: Currency = "USD"
    /// let euro: Currency = "EUR"
    /// ```
    public init(stringLiteral value: StringLiteralType) {
        self.id = value
    }
}

extension Currency: Comparable {
    /// Compares two currencies alphabetically by their identifiers.
    /// 
    /// - Parameters:
    ///   - lhs: The left-hand currency
    ///   - rhs: The right-hand currency
    /// - Returns: True if lhs identifier is lexicographically less than rhs
    public static func < (lhs: Currency, rhs: Currency) -> Bool {
        lhs.id < rhs.id
    }
}

extension Currency {
    /// A special constant representing a missing or undefined currency.
    /// Uses an empty string as the identifier.
    public static let missing = Currency(id: "")
}

/// Protocol for cost information that can be attached to postings.
/// 
/// This protocol defines the interface for cost specifications that can be
/// associated with postings in transactions. Implementations include `Cost`
/// for concrete cost values and `CostSpec` for cost specifications.
public protocol PostingCost: Hashable, CustomStringConvertible, Sendable {}

/// Represents the acquisition cost of a position.
/// 
/// A Cost stores the concrete price, currency, date, and optional label for
/// when a position was acquired. This is essential for tracking capital gains
/// and implementing lot-based inventory management in Beancount.
///
/// This corresponds to the `Cost` namedtuple in the original Beancount Python
/// library, providing precise cost tracking for financial positions.
///
/// ## Usage
/// ```swift
/// let cost = Cost(
///     number: 150.00,
///     currency: Currency(id: "USD"),
///     date: Date(),
///     label: "ref-001"
/// )
/// ```
///
/// - SeeAlso: [Beancount Design Doc - Cost](https://beancount.github.io/docs/beancount_design_doc.html#cost)
public struct Cost: PostingCost {
    /// The unit cost as a decimal number.
    public var number: Decimal
    
    /// The currency in which the cost is denominated.
    public var currency: Currency
    
    /// The date when this cost was established (acquisition date).
    public var date: Date
    
    /// Optional label for identifying specific lots or transactions.
    public var label: String?
}

extension Cost: Comparable {
    /// Compares two costs in order: number, currency, date, then label.
    /// 
    /// Costs are ordered first by numeric value, then by currency alphabetically,
    /// then by date chronologically, and finally by label alphabetically.
    /// Costs with nil labels are considered less than costs with labels.
    /// 
    /// - Parameters:
    ///   - lhs: The left-hand cost
    ///   - rhs: The right-hand cost
    /// - Returns: True if lhs is less than rhs according to the ordering criteria
    public static func < (lhs: Cost, rhs: Cost) -> Bool {
        if lhs.number != rhs.number {
            return lhs.number < rhs.number
        } else if lhs.currency != rhs.currency {
            return lhs.currency < rhs.currency
        } else if lhs.date != rhs.date {
            return lhs.date < rhs.date
        } else if let ll = lhs.label, let rl = rhs.label {
            return ll < rl
        } else if lhs.label == nil {
            return true
        } else {
            return false
        }
    }
}

/// A specification for matching and resolving costs during transaction processing.
/// 
/// CostSpec is used when parsing Beancount transactions to specify which existing
/// lots should be matched. Unlike Cost which stores concrete values, CostSpec
/// contains partial information that gets resolved during the booking process.
/// 
/// This corresponds to the `CostSpec` namedtuple in the original Beancount Python
/// library, used for cost specification and lot matching in the booking system.
///
/// ## Usage
/// ```swift
/// // Match lots with specific unit price
/// let spec1 = CostSpec(numberPerUnit: 150.00, currency: Currency(id: "USD"))
/// 
/// // Match lots by total cost
/// let spec2 = CostSpec(numberTotal: 1500.00, currency: Currency(id: "USD"))
/// 
/// // Match lots by date and label
/// let spec3 = CostSpec(date: someDate, label: "ref-001")
/// ```
///
/// - SeeAlso: [Beancount Design Doc - CostSpec](https://beancount.github.io/docs/beancount_design_doc.html#costspec)
public struct CostSpec: PostingCost {
    /// The cost per unit for lot matching.
    public var numberPerUnit: Decimal?
    
    /// The total cost for lot matching.
    public var numberTotal: Decimal?
    
    /// The currency for cost matching.
    public var currency: Currency?
    
    /// The acquisition date for lot matching.
    public var date: Date?
    
    /// The label for lot identification.
    public var label: String?
    
    /// Whether to merge matching lots.
    public var merge: Bool?
    
    /// Creates a cost specification with the given parameters.
    /// 
    /// - Parameters:
    ///   - numberPerUnit: Cost per unit for matching
    ///   - numberTotal: Total cost for matching
    ///   - currency: Currency for matching
    ///   - date: Date for matching
    ///   - label: Label for matching
    ///   - merge: Whether to merge matching lots
    public init(numberPerUnit: Decimal? = nil, numberTotal: Decimal? = nil, currency: Currency? = nil, date: Date? = nil, label: String? = nil, merge: Bool? = nil) {
        self.numberPerUnit = numberPerUnit
        self.numberTotal = numberTotal
        self.currency = currency
        self.date = date
        self.label = label
        self.merge = merge
    }
}

/// Type alias for metadata attached to directives and postings.
/// 
/// Metadata is stored as an ordered dictionary mapping string keys to
/// metadata values, preserving the order in which metadata was specified
/// in the source file.
public typealias MetaData = OrderedDictionary<String, MetaDataValue>

/// A posting represents one leg of a double-entry accounting transaction.
/// 
/// Each posting specifies an account, amount, and optional cost/price information.
/// Multiple postings together form a balanced transaction where debits equal credits.
/// Postings can have flags for special handling and metadata for additional information.
///
/// This corresponds to the `Posting` namedtuple in the original Beancount Python
/// library, representing individual account entries within transactions.
///
/// ## Usage
/// ```swift
/// let posting = Posting(
///     account: Account(id: "Assets:Checking"),
///     units: Amount(number: -100.00, currency: Currency(id: "USD")),
///     flag: "*"
/// )
/// ```
///
/// - SeeAlso: [Beancount Design Doc - Posting](https://beancount.github.io/docs/beancount_design_doc.html#posting)
public struct Posting<T: PostingCost>: Hashable, Sendable {
    /// The account affected by this posting.
    public var account: Account
    
    /// The units of the position, or the amount transferred.
    /// Can be inferred from other postings if left unspecified during parsing.
    public var units: Amount
    
    /// Optional cost information for tracking acquisition prices.
    public var cost: T?
    
    /// Optional price for conversion rate information.
    public var price: Amount?
    
    /// Optional flag character for special posting treatment.
    public var flag: Character?
    
    /// Optional metadata attached to this posting.
    public var meta: MetaData?
    
    /// Optional comment text for this posting.
    public var comment: String?
    
    /// Creates a posting with the specified parameters.
    /// 
    /// - Parameters:
    ///   - account: The account affected by this posting
    ///   - units: The amount transferred
    ///   - cost: Optional cost information
    ///   - price: Optional price information
    ///   - flag: Optional flag character
    ///   - meta: Optional metadata
    ///   - comment: Optional comment text
    public init(account: Account, units: Amount, cost: T? = nil, price: Amount? = nil, flag: Character? = nil, meta: MetaData? = nil, comment: String? = nil) {
        self.account = account
        self.units = units
        self.cost = cost
        self.price = price
        self.flag = flag
        self.meta = meta
        self.comment = comment
    }
}

/// A tag for categorizing and organizing transactions.
/// 
/// Tags are labels that can be attached to transactions for categorization,
/// filtering, and reporting purposes. They must follow specific naming conventions
/// and are commonly used for budgeting, project tracking, and custom reporting.
///
/// ## Usage
/// ```swift
/// let tag = Tag(id: "vacation")
/// let projectTag = Tag(id: "project-alpha")
/// ```
public struct Tag: Hashable, Identifiable, Sendable {
    /// The tag identifier following Beancount naming conventions.
    public var id: String
    
    /// Creates a tag with the specified identifier.
    /// 
    /// - Parameter id: The tag identifier
    public init(id: String) {
        self.id = id
    }
}

extension Tag: Comparable {
    /// Compares two tags alphabetically by their identifiers.
    /// 
    /// - Parameters:
    ///   - lhs: The left-hand tag
    ///   - rhs: The right-hand tag
    /// - Returns: True if lhs identifier is lexicographically less than rhs
    public static func < (lhs: Tag, rhs: Tag) -> Bool {
        lhs.id < rhs.id
    }
}

extension Tag {
    /// Validates whether the tag identifier conforms to Beancount naming conventions.
    /// 
    /// Valid tag names contain only alphanumeric characters, hyphens, underscores,
    /// forward slashes, and periods.
    /// 
    /// - Returns: True if the tag identifier is valid
    public var isValid: Bool {
        let match = #"^[A-Za-z0-9\-_/.]+$"#
        return id.range(of: match, options: .regularExpression) != nil
    }
}

#if DEBUG
extension Tag: ExpressibleByStringLiteral {
    /// Creates a tag from a string literal in DEBUG builds only.
    /// 
    /// - Parameter value: The tag identifier as a string
    /// 
    /// ## Example
    /// ```swift
    /// let tag: Tag = "vacation"
    /// ```
    /// 
    /// - Warning: Only available in DEBUG builds.
    public init(stringLiteral value: StringLiteralType) {
        self.id = value
    }
}
#endif

/// A link for connecting related transactions across the ledger.
/// 
/// Links provide a way to group related transactions that may occur at different
/// times or involve different accounts. They are commonly used for tracking
/// multi-step processes like transfers, reimbursements, or complex trades.
///
/// ## Usage
/// ```swift
/// let link = Link(id: "transfer-2024-001")
/// let tradeLink = Link(id: "stock-purchase-aapl")
/// ```
public struct Link: Hashable, Identifiable, Sendable {
    /// The link identifier following Beancount naming conventions.
    public var id: String
    
    /// Creates a link with the specified identifier.
    /// 
    /// - Parameter id: The link identifier
    public init(id: String) {
        self.id = id
    }
}

extension Link: Comparable {
    /// Compares two links alphabetically by their identifiers.
    /// 
    /// - Parameters:
    ///   - lhs: The left-hand link
    ///   - rhs: The right-hand link
    /// - Returns: True if lhs identifier is lexicographically less than rhs
    public static func < (lhs: Link, rhs: Link) -> Bool {
        lhs.id < rhs.id
    }
}

extension Link {
    /// Validates whether the link identifier conforms to Beancount naming conventions.
    /// 
    /// Valid link names contain only alphanumeric characters, hyphens, underscores,
    /// forward slashes, and periods.
    /// 
    /// - Returns: True if the link identifier is valid
    public var isValid: Bool {
        let match = #"^[A-Za-z0-9\-_/.]+$"#
        return id.range(of: match, options: .regularExpression) != nil
    }
}

#if DEBUG
extension Link: ExpressibleByStringLiteral {
    /// Creates a link from a string literal in DEBUG builds only.
    /// 
    /// - Parameter value: The link identifier as a string
    /// 
    /// ## Example
    /// ```swift
    /// let link: Link = "transfer-001"
    /// ```
    /// 
    /// - Warning: Only available in DEBUG builds.
    public init(stringLiteral value: StringLiteralType) {
        self.id = value
    }
}
#endif

/// Represents possible values that can be stored in metadata.
/// 
/// Metadata values can be various types including strings, numbers, dates,
/// and Beancount-specific types like accounts and currencies. This enum
/// provides type-safe storage for all supported metadata value types.
/// 
/// ## Usage
/// ```swift
/// let meta: MetaData = [
///     "description": .string("Grocery shopping"),
///     "category": .tag(Tag(id: "food")),
///     "amount": .number(45.67)
/// ]
/// ```
public enum MetaDataValue: Hashable, Sendable {
    /// A string value.
    case string(String)
    /// An account reference.
    case account(Account)
    /// A currency reference.
    case currency(Currency)
    /// A date value.
    case date(Date)
    /// A tag reference.
    case tag(Tag)
    /// A numeric value.
    case number(Decimal)
    /// A boolean value.
    case bool(Bool)
    /// An amount value.
    case amount(Amount)
    /// A source range reference for parser integration.
    case range(TSRange)
}

extension OrderedDictionary where Key == String, Value == MetaDataValue {
    /// Extracts the line number from metadata.
    /// 
    /// Looks for a "lineno" key with a numeric value, or falls back to
    /// extracting the line number from the source range if available.
    /// 
    /// - Returns: The line number if available, nil otherwise
    public var lineno: UInt32? {
        if case .number(let val) = self["lineno"] {
            return NSDecimalNumber(decimal: val).uint32Value
        }
        return range?.points.lowerBound.row
    }
    
    /// Extracts the filename from metadata.
    /// 
    /// Looks for a "filename" key with a string value.
    /// 
    /// - Returns: The filename if available, nil otherwise
    public var filename: String? {
        if case .string(let val) = self["filename"] {
            return val
        } else {
            return nil
        }
    }
    
    /// Extracts the source range from metadata.
    /// 
    /// Looks for a "range" key with a range value, used for
    /// tracking source locations during parsing.
    /// 
    /// - Returns: The source range if available, nil otherwise
    public var range: TSRange? {
        if case .range(let val) = self["range"] {
            return val
        } else {
            return nil
        }
    }
    
    /// Returns metadata with system keys removed.
    /// 
    /// Filters out system-generated keys like "lineno", "filename", and "range"
    /// that are used internally by the parser, leaving only user-defined metadata.
    /// 
    /// - Returns: A new metadata dictionary with system keys removed
    public var removingSystemKeys: MetaData {
        return self.filter { key, value in
            if key == "lineno", case .number = value { return false }
            if key == "filename", case .string = value { return false }
            if key == "range", case .range = value { return false }
            return true
        }
    }
}
