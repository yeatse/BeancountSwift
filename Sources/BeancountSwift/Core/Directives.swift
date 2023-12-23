//
//  Directives.swift
//
//
//  Created by Yeatse on 2023/12/21.
//

import Foundation

/// https://beancount.github.io/docs/beancount_design_doc.html#common-properties
public struct Directive: Equatable {
    let meta: [String: Any]
    let date: Date
    let comment: String?
    let content: DirectiveContent
    
    public static func == (lhs: Directive, rhs: Directive) -> Bool {
        lhs.date == rhs.date
        && lhs.content == rhs.content
        && lhs.meta.lineno == rhs.meta.lineno
    }
}

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

public enum DirectiveContent: Equatable {
    case open(Open)
    case close(Close)
    case commodity(Commodity)
    case pad(Pad)
    case balance(Balance)
    case transaction(Transaction)
    case note(Note)
    case event(Event)
    case query(Query)
    case price(Price)
    case document(Document)
    case custom(Custom)
}

/// https://beancount.github.io/docs/beancount_language_syntax.html#open
public struct Open: Equatable {
    public let account: Account
    public let currencies: [Currency]
    public let booking: Booking?
}

/// https://beancount.github.io/docs/beancount_language_syntax.html#open
public struct Close: Equatable {
    public let account: Account
}

public struct Commodity: Equatable {
    public let currency: Currency
}

public struct Pad: Equatable {
    public let account: Account
    public let sourceAccount: Account
}

public struct Balance: Equatable {
    public let account: Account
    public let amount: Amount
    public let tolerance: Decimal?
    public let diffAmount: Amount?
}

/// https://beancount.github.io/docs/beancount_design_doc.html#transactions
public struct Transaction: Equatable {
    public let flag: Character?
    public let payee: String?
    public let narration: String?
    public let tags: Set<String>
    public let links: Set<String>
    public let postings: [Posting]
}

public struct Note: Equatable {
    public let account: Account
    public let note: String
}

public struct Event: Equatable {
    public let type: String
    public let description: String
}

public struct Query: Equatable {
    public let name: String
    public let queryString: String
}

public struct Price: Equatable {
    public let currency: Currency
    public let amount: Amount
}

public struct Document: Equatable {
    public let account: Account
    public let filename: String
    public let tags: Set<String>?
    public let links: Set<String>?
}

public struct Custom: Equatable {
    public let type: String
    public let values: [Any]
    
    public static func == (lhs: Custom, rhs: Custom) -> Bool {
        lhs.type == rhs.type
    }
}
