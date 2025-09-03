//
//  Directives.swift
//
//
//  Created by Yeatse on 2023/12/21.
//

import Foundation
import OrderedCollections

/// A Beancount directive represents a single command or entry in the ledger.
/// 
/// Directives are the fundamental building blocks of a Beancount ledger file.
/// Each directive has common properties (metadata, date, optional comment) and
/// specific content that varies by directive type (transaction, open, close, etc.).
///
/// This corresponds to the directive system in the original Beancount Python
/// library, providing the structured representation of all ledger entries.
///
/// ## Usage
/// ```swift
/// let directive = Directive(
///     meta: [:],
///     date: Date(),
///     content: .open(Open(account: Account(id: "Assets:Checking"), currencies: [Currency(id: "USD")], booking: nil))
/// )
/// ```
///
/// - SeeAlso: [Beancount Design Doc - Common Properties](https://beancount.github.io/docs/beancount_design_doc.html#common-properties)
public struct Directive<T: PostingCost>: Hashable, Sendable {
    /// Metadata associated with this directive.
    public var meta: MetaData
    
    /// The date when this directive takes effect.
    public var date: Date
    
    /// Optional comment text associated with this directive.
    public var comment: String?
    
    /// The specific content of this directive (transaction, open, close, etc.).
    public var content: DirectiveContent<T>
    
    /// Creates a directive with the specified parameters.
    /// 
    /// - Parameters:
    ///   - meta: Metadata for this directive
    ///   - date: The effective date
    ///   - comment: Optional comment text
    ///   - content: The directive content
    public init(meta: MetaData, date: Date, comment: String? = nil, content: DirectiveContent<T>) {
        self.meta = meta
        self.date = date
        self.comment = comment
        self.content = content
    }
}

extension Directive<Cost>: Identifiable {
    public var id: String {
        if let filename = meta.filename, let lineno = meta.lineno {
            return "\(filename)-\(lineno)"
        } else {
            return UUID().uuidString
        }
    }
}

/// Enumeration of all possible directive content types in Beancount.
/// 
/// This enum represents the different types of directives that can appear in a
/// Beancount ledger file. Each case corresponds to a specific directive type
/// with its associated data structure.
/// 
/// ## Directive Types
/// - **open**: Opens an account for use
/// - **close**: Closes an account
/// - **commodity**: Declares a commodity/currency
/// - **pad**: Automatically fills account balance gaps
/// - **balance**: Asserts expected account balance
/// - **transaction**: Records financial transactions
/// - **note**: Adds textual notes to accounts
/// - **event**: Records significant events
/// - **query**: Defines named queries
/// - **price**: Sets market prices
/// - **document**: Links external documents
/// - **custom**: Allows custom directive types
public enum DirectiveContent<T: PostingCost>: Hashable, Sendable {
    /// Account opening directive.
    case open(Open)
    /// Account closing directive.
    case close(Close)
    /// Commodity declaration directive.
    case commodity(Commodity)
    /// Balance padding directive.
    case pad(Pad)
    /// Balance assertion directive.
    case balance(Balance)
    /// Financial transaction directive.
    case transaction(Transaction<T>)
    /// Account note directive.
    case note(Note)
    /// Event recording directive.
    case event(Event)
    /// Named query directive.
    case query(Query)
    /// Market price directive.
    case price(Price)
    /// Document attachment directive.
    case document(Document)
    /// Custom user-defined directive.
    case custom(Custom)
}

/// A wrapper that pairs a directive with its specific content type.
/// 
/// DirectiveValue provides type-safe access to directive content by combining
/// the generic Directive structure with its specific content type. This is useful
/// for pattern matching and type-safe processing of specific directive types.
/// 
/// ## Usage
/// ```swift
/// let openDirective = Directive(meta: [:], date: Date(), content: .open(openContent))
/// let directiveValue = DirectiveValue(openDirective, openContent)
/// ```
public struct DirectiveValue<T: PostingCost, Content>: Hashable, Sendable where Content: Hashable & Sendable {
    /// The generic directive containing common properties.
    public let directive: Directive<T>
    /// The specific typed content of the directive.
    public let content: Content
    
    /// Creates a directive-content pair.
    /// 
    /// - Parameters:
    ///   - directive: The generic directive
    ///   - content: The specific typed content
    public init(_ directive: Directive<T>, _ content: Content) {
        self.directive = directive
        self.content = content
    }
}

/// Opens an account for use in the ledger.
/// 
/// The open directive declares that an account is available for use starting from
/// the specified date. It can optionally restrict which currencies the account
/// can hold and specify a booking method for inventory management.
/// 
/// ## Usage
/// ```swift
/// let open = Open(
///     account: Account(id: "Assets:Checking"),
///     currencies: [Currency(id: "USD"), Currency(id: "EUR")],
///     booking: .STRICT
/// )
/// ```
/// 
/// - SeeAlso: [Beancount Language Syntax - Open](https://beancount.github.io/docs/beancount_language_syntax.html#open)
public struct Open: Hashable, Sendable {
    /// The account being opened.
    public let account: Account
    /// List of currencies this account can hold (empty means any currency).
    public let currencies: [Currency]
    /// Optional booking method for this account's inventory management.
    public let booking: BookingMethod?
    
    /// Creates an open directive.
    /// 
    /// - Parameters:
    ///   - account: The account to open
    ///   - currencies: Allowed currencies (empty for any currency)
    ///   - booking: Optional booking method
    public init(account: Account, currencies: [Currency], booking: BookingMethod?) {
        self.account = account
        self.currencies = currencies
        self.booking = booking
    }
}

/// Closes an account, preventing further transactions.
/// 
/// The close directive marks an account as closed from the specified date forward.
/// No transactions can post to a closed account after its close date.
/// 
/// ## Usage
/// ```swift
/// let close = Close(account: Account(id: "Assets:OldBank"))
/// ```
/// 
/// - SeeAlso: [Beancount Language Syntax - Close](https://beancount.github.io/docs/beancount_language_syntax.html#close)
public struct Close: Hashable, Sendable {
    /// The account being closed.
    public let account: Account
    
    /// Creates a close directive.
    /// 
    /// - Parameter account: The account to close
    public init(account: Account) {
        self.account = account
    }
}

/// Declares a commodity/currency for use in the ledger.
/// 
/// The commodity directive establishes a new currency or commodity that can be used
/// in the ledger. This is used to declare new financial instruments, currencies,
/// or other units of value before they are referenced in transactions.
/// 
/// ## Usage
/// ```swift
/// let commodity = Commodity(currency: Currency(id: "AAPL"))
/// ```
/// 
/// - SeeAlso: [Beancount Language Syntax - Commodity](https://beancount.github.io/docs/beancount_language_syntax.html#commodity)
public struct Commodity: Hashable, Sendable {
    /// The currency or commodity being declared.
    public let currency: Currency
    
    /// Creates a commodity directive.
    /// 
    /// - Parameter currency: The currency or commodity to declare
    public init(currency: Currency) {
        self.currency = currency
    }
}

/// Automatically pads account balances using another account.
/// 
/// The pad directive inserts transactions to make the balance of an account
/// match reality by using funds from a source account. This is typically used
/// to handle small discrepancies or rounding errors in account balances.
/// 
/// ## Usage
/// ```swift
/// let pad = Pad(
///     account: Account(id: "Assets:Checking"),
///     sourceAccount: Account(id: "Equity:Opening-Balances")
/// )
/// ```
/// 
/// - SeeAlso: [Beancount Language Syntax - Pad](https://beancount.github.io/docs/beancount_language_syntax.html#pad)
public struct Pad: Hashable, Sendable {
    /// The account whose balance should be padded.
    public let account: Account
    /// The source account to draw padding funds from.
    public let sourceAccount: Account
    
    /// Creates a pad directive.
    /// 
    /// - Parameters:
    ///   - account: The account to pad
    ///   - sourceAccount: The source of padding funds
    public init(account: Account, sourceAccount: Account) {
        self.account = account
        self.sourceAccount = sourceAccount
    }
}

/// Asserts that an account balance matches an expected amount.
/// 
/// The balance directive checks that an account's balance matches the expected
/// amount at a specific date. If the balance doesn't match, an error is generated.
/// An optional tolerance can be specified for slight discrepancies.
/// 
/// ## Usage
/// ```swift
/// let balance = Balance(
///     account: Account(id: "Assets:Checking"),
///     amount: Amount(number: 1500.00, currency: Currency(id: "USD")),
///     tolerance: 0.01,
///     diffAmount: nil
/// )
/// ```
/// 
/// - SeeAlso: [Beancount Language Syntax - Balance](https://beancount.github.io/docs/beancount_language_syntax.html#balance)
public struct Balance: Hashable, Sendable {
    /// The account whose balance is being checked.
    public let account: Account
    /// The expected balance amount.
    public let amount: Amount
    /// Optional tolerance for balance discrepancies.
    public let tolerance: Decimal?
    /// The difference amount if balance doesn't match (computed during processing).
    public let diffAmount: Amount?
    
    /// Creates a balance assertion directive.
    /// 
    /// - Parameters:
    ///   - account: The account to check
    ///   - amount: The expected balance
    ///   - tolerance: Optional tolerance for discrepancies
    ///   - diffAmount: Computed difference amount
    public init(account: Account, amount: Amount, tolerance: Decimal?, diffAmount: Amount?) {
        self.account = account
        self.amount = amount
        self.tolerance = tolerance
        self.diffAmount = diffAmount
    }
}

/// Represents a financial transaction with multiple postings.
/// 
/// Transactions are the core of double-entry accounting, recording the movement
/// of value between accounts. Each transaction contains multiple postings that
/// must balance according to the accounting equation.
/// 
/// ## Usage
/// ```swift
/// let transaction = Transaction(
///     flag: "*",
///     payee: "Grocery Store",
///     narration: "Weekly shopping",
///     tags: [Tag(id: "food")],
///     links: [],
///     postings: [
///         Posting(account: Account(id: "Assets:Checking"), units: Amount(number: -50.00, currency: Currency(id: "USD"))),
///         Posting(account: Account(id: "Expenses:Food"), units: Amount(number: 50.00, currency: Currency(id: "USD")))
///     ]
/// )
/// ```
/// 
/// - SeeAlso: [Beancount Design Doc - Transactions](https://beancount.github.io/docs/beancount_design_doc.html#transactions)
public struct Transaction<T: PostingCost>: Hashable, Sendable {
    /// Transaction flag indicating status (*, !, etc.).
    public let flag: Character?
    /// The payee or counterparty in the transaction.
    public let payee: String?
    /// Descriptive text explaining the transaction.
    public let narration: String?
    /// Set of tags for categorization.
    public let tags: OrderedSet<Tag>
    /// Set of links connecting related transactions.
    public let links: OrderedSet<Link>
    /// List of postings that make up this transaction.
    public let postings: [Posting<T>]
    
    /// Creates a transaction.
    /// 
    /// - Parameters:
    ///   - flag: Transaction status flag
    ///   - payee: The payee or counterparty
    ///   - narration: Transaction description
    ///   - tags: Categorization tags
    ///   - links: Connecting links
    ///   - postings: Account postings
    public init(flag: Character?, payee: String?, narration: String?, tags: OrderedSet<Tag>, links: OrderedSet<Link>, postings: [Posting<T>]) {
        self.flag = flag
        self.payee = payee
        self.narration = narration
        self.tags = tags
        self.links = links
        self.postings = postings
    }
}

extension Character {
    public static let okeyFlag: Character = "*"
    public static let warningFlag: Character = "!"
    public static let paddingFlag: Character = "P"
    public static let summarizeFlag: Character = "S"
    public static let transferFlag: Character = "T"
    public static let conversionsFlag: Character = "C"
    public static let mergingFlag: Character = "M"
}

/// Attaches a note to an account at a specific date.
/// 
/// The note directive allows you to attach descriptive text to an account
/// at a specific point in time. Notes are useful for documentation, explanations
/// of account purpose, or recording important events related to the account.
/// 
/// ## Usage
/// ```swift
/// let note = Note(
///     account: Account(id: "Assets:Checking"),
///     note: "Opened new high-yield savings account"
/// )
/// ```
/// 
/// - SeeAlso: [Beancount Language Syntax - Note](https://beancount.github.io/docs/beancount_language_syntax.html#note)
public struct Note: Hashable, Sendable {
    /// The account this note applies to.
    public let account: Account
    /// The note text content.
    public let note: String
    
    /// Creates a note directive.
    /// 
    /// - Parameters:
    ///   - account: The account to attach the note to
    ///   - note: The note text
    public init(account: Account, note: String) {
        self.account = account
        self.note = note
    }
}

/// Records a significant event in the ledger.
/// 
/// The event directive allows you to record important events that affect your
/// financial situation but don't necessarily involve account balance changes.
/// Events are useful for tracking life changes, employment changes, or other
/// significant occurrences that provide context for your financial records.
/// 
/// ## Usage
/// ```swift
/// let event = Event(
///     type: "location",
///     description: "Moved to New York"
/// )
/// ```
/// 
/// - SeeAlso: [Beancount Language Syntax - Event](https://beancount.github.io/docs/beancount_language_syntax.html#event)
public struct Event: Hashable, Sendable {
    /// The event type/category.
    public let type: String
    /// The event description.
    public let description: String
    
    /// Creates an event directive.
    /// 
    /// - Parameters:
    ///   - type: The event type or category
    ///   - description: A description of the event
    public init(type: String, description: String) {
        self.type = type
        self.description = description
    }
}

/// Defines a named query that can be executed on the ledger.
/// 
/// The query directive allows you to define reusable SQL-like queries that can
/// be executed against the ledger data. Named queries are useful for creating
/// reports, analyzing data, or extracting specific information from the ledger.
/// 
/// ## Usage
/// ```swift
/// let query = Query(
///     name: "monthly_expenses",
///     queryString: "SELECT account, sum(position) FROM postings WHERE account ~ '^Expenses:' GROUP BY account"
/// )
/// ```
/// 
/// - SeeAlso: [Beancount Query Language](https://beancount.github.io/docs/beancount_query_language.html)
public struct Query: Hashable, Sendable {
    /// The query name identifier.
    public let name: String
    /// The SQL-like query string.
    public let queryString: String
    
    /// Creates a query directive.
    /// 
    /// - Parameters:
    ///   - name: The query name
    ///   - queryString: The SQL-like query to execute
    public init(name: String, queryString: String) {
        self.name = name
        self.queryString = queryString
    }
}

/// Sets the market price of a currency or commodity.
/// 
/// The price directive establishes the market value of a currency or commodity
/// at a specific date. Prices are used for portfolio valuation, currency conversion,
/// and reporting purposes throughout the ledger.
/// 
/// ## Usage
/// ```swift
/// let price = Price(
///     currency: Currency(id: "AAPL"),
///     amount: Amount(number: 150.00, currency: Currency(id: "USD"))
/// )
/// ```
/// 
/// - SeeAlso: [Beancount Language Syntax - Price](https://beancount.github.io/docs/beancount_language_syntax.html#price)
public struct Price: Hashable, Sendable {
    /// The currency or commodity being priced.
    public let currency: Currency
    /// The price amount in terms of another currency.
    public let amount: Amount
    
    /// Creates a price directive.
    /// 
    /// - Parameters:
    ///   - currency: The currency/commodity to price
    ///   - amount: The price value
    public init(currency: Currency, amount: Amount) {
        self.currency = currency
        self.amount = amount
    }
}

/// Links an external document to an account.
/// 
/// The document directive creates an association between an account and an external
/// file (receipt, statement, invoice, etc.). This helps maintain audit trails and
/// provides supporting documentation for transactions and account activities.
/// 
/// ## Usage
/// ```swift
/// let document = Document(
///     account: Account(id: "Expenses:Groceries"),
///     filename: "receipt-2024-01-15.pdf",
///     tags: [Tag(id: "receipt")],
///     links: nil
/// )
/// ```
/// 
/// - SeeAlso: [Beancount Language Syntax - Document](https://beancount.github.io/docs/beancount_language_syntax.html#document)
public struct Document: Hashable, Sendable {
    /// The account this document relates to.
    public let account: Account
    /// The filename or path to the document.
    public let filename: String
    /// Optional tags for categorizing the document.
    public let tags: OrderedSet<Tag>?
    /// Optional links for connecting related documents.
    public let links: OrderedSet<Link>?
    
    /// Creates a document directive.
    /// 
    /// - Parameters:
    ///   - account: The related account
    ///   - filename: The document filename
    ///   - tags: Optional categorization tags
    ///   - links: Optional connecting links
    public init(account: Account, filename: String, tags: OrderedSet<Tag>?, links: OrderedSet<Link>?) {
        self.account = account
        self.filename = filename
        self.tags = tags
        self.links = links
    }
}

/// Defines a custom directive type for specialized use cases.
/// 
/// The custom directive allows you to create application-specific directives
/// that extend Beancount's functionality. Custom directives are processed by
/// plugins and can carry arbitrary data values for specialized processing.
/// 
/// ## Usage
/// ```swift
/// let custom = Custom(
///     type: "budget",
///     values: [
///         .string("monthly"),
///         .number(1500.00),
///         .currency(Currency(id: "USD"))
///     ]
/// )
/// ```
/// 
/// - SeeAlso: [Beancount Language Syntax - Custom](https://beancount.github.io/docs/beancount_language_syntax.html#custom)
public struct Custom: Hashable, Sendable {
    /// The custom directive type name.
    public let type: String
    /// The associated data values for this custom directive.
    public let values: [MetaDataValue]
    
    /// Creates a custom directive.
    /// 
    /// - Parameters:
    ///   - type: The custom directive type
    ///   - values: Associated data values
    public init(type: String, values: [MetaDataValue]) {
        self.type = type
        self.values = values
    }
}
