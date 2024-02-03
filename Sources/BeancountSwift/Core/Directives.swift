//
//  Directives.swift
//
//
//  Created by Yeatse on 2023/12/21.
//

import Foundation

/// https://beancount.github.io/docs/beancount_design_doc.html#common-properties
public struct Directive<T: PostingCost>: Hashable {
    public var meta: [String: MetaDataValue]
    public var date: Date
    public var comment: String?
    public var content: DirectiveContent<T>
}

public enum DirectiveContent<T: PostingCost>: Hashable {
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
public struct Open: Hashable {
    public let account: Account
    public let currencies: [Currency]
    public let booking: BookingMethod?
}

/// https://beancount.github.io/docs/beancount_language_syntax.html#open
public struct Close: Hashable {
    public let account: Account
}

public struct Commodity: Hashable {
    public let currency: Currency
}

public struct Pad: Hashable {
    public let account: Account
    public let sourceAccount: Account
}

public struct Balance: Hashable {
    public let account: Account
    public let amount: Amount
    public let tolerance: Decimal?
    public let diffAmount: Amount?
}

/// https://beancount.github.io/docs/beancount_design_doc.html#transactions
public struct Transaction<T: PostingCost>: Hashable {
    public let flag: Character?
    public let payee: String?
    public let narration: String?
    public let tags: Set<Tag>
    public let links: Set<String>
    public let postings: [Posting<T>]
}

extension Character {
    static let okeyFlag: Character = "*"
    static let warningFlag: Character = "!"
    static let paddingFlag: Character = "P"
    static let summarizeFlag: Character = "S"
    static let transferFlag: Character = "T"
    static let conversionsFlag: Character = "C"
    static let mergingFlag: Character = "M"
}

public struct Note: Hashable {
    public let account: Account
    public let note: String
}

public struct Event: Hashable {
    public let type: String
    public let description: String
}

public struct Query: Hashable {
    public let name: String
    public let queryString: String
}

public struct Price: Hashable {
    public let currency: Currency
    public let amount: Amount
}

public struct Document: Hashable {
    public let account: Account
    public let filename: String
    public let tags: Set<Tag>?
    public let links: Set<String>?
}

public struct Custom: Hashable {
    public let type: String
    public let values: [MetaDataValue]
}
