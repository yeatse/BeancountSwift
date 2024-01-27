//
//  Directives.swift
//
//
//  Created by Yeatse on 2023/12/21.
//

import Foundation

/// https://beancount.github.io/docs/beancount_design_doc.html#common-properties
public struct Directive<T: PostingCost>: Equatable {
    public var meta: [String: MetaDataValue]
    public var date: Date
    public var comment: String?
    public var content: DirectiveContent<T>
}

public enum DirectiveContent<T: PostingCost>: Equatable {
    case open(Open)
    case close(Close)
    case commodity(Commodity)
    case pad(Pad)
    case balance(Balance)
    case transaction(Transaction<T>)
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
public struct Transaction<T: PostingCost>: Equatable {
    public let flag: Character?
    public let payee: String?
    public let narration: String?
    public let tags: Set<Tag>
    public let links: Set<String>
    public let postings: [Posting<T>]
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
    public let tags: Set<Tag>?
    public let links: Set<String>?
}

public struct Custom: Equatable {
    public let type: String
    public let values: [MetaDataValue]
}
