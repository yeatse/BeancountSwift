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
    
    public init(meta: [String : MetaDataValue], date: Date, comment: String? = nil, content: DirectiveContent<T>) {
        self.meta = meta
        self.date = date
        self.comment = comment
        self.content = content
    }
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

public struct DirectiveValue<T: PostingCost, Content> {
    public let directive: Directive<T>
    public let content: Content
    
    public init(_ directive: Directive<T>, _ content: Content) {
        self.directive = directive
        self.content = content
    }
}

/// https://beancount.github.io/docs/beancount_language_syntax.html#open
public struct Open: Hashable {
    public let account: Account
    public let currencies: [Currency]
    public let booking: BookingMethod?
    
    public init(account: Account, currencies: [Currency], booking: BookingMethod?) {
        self.account = account
        self.currencies = currencies
        self.booking = booking
    }
}

/// https://beancount.github.io/docs/beancount_language_syntax.html#open
public struct Close: Hashable {
    public let account: Account
    
    public init(account: Account) {
        self.account = account
    }
}

public struct Commodity: Hashable {
    public let currency: Currency
    
    public init(currency: Currency) {
        self.currency = currency
    }
}

public struct Pad: Hashable {
    public let account: Account
    public let sourceAccount: Account
    
    public init(account: Account, sourceAccount: Account) {
        self.account = account
        self.sourceAccount = sourceAccount
    }
}

public struct Balance: Hashable {
    public let account: Account
    public let amount: Amount
    public let tolerance: Decimal?
    public let diffAmount: Amount?
    
    public init(account: Account, amount: Amount, tolerance: Decimal?, diffAmount: Amount?) {
        self.account = account
        self.amount = amount
        self.tolerance = tolerance
        self.diffAmount = diffAmount
    }
}

/// https://beancount.github.io/docs/beancount_design_doc.html#transactions
public struct Transaction<T: PostingCost>: Hashable {
    public let flag: Character?
    public let payee: String?
    public let narration: String?
    public let tags: Set<Tag>
    public let links: Set<String>
    public let postings: [Posting<T>]
    
    public init(flag: Character?, payee: String?, narration: String?, tags: Set<Tag>, links: Set<String>, postings: [Posting<T>]) {
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

public struct Note: Hashable {
    public let account: Account
    public let note: String
    
    public init(account: Account, note: String) {
        self.account = account
        self.note = note
    }
}

public struct Event: Hashable {
    public let type: String
    public let description: String
    
    public init(type: String, description: String) {
        self.type = type
        self.description = description
    }
}

public struct Query: Hashable {
    public let name: String
    public let queryString: String
    
    public init(name: String, queryString: String) {
        self.name = name
        self.queryString = queryString
    }
}

public struct Price: Hashable {
    public let currency: Currency
    public let amount: Amount
    
    public init(currency: Currency, amount: Amount) {
        self.currency = currency
        self.amount = amount
    }
}

public struct Document: Hashable {
    public let account: Account
    public let filename: String
    public let tags: Set<Tag>?
    public let links: Set<String>?
    
    public init(account: Account, filename: String, tags: Set<Tag>?, links: Set<String>?) {
        self.account = account
        self.filename = filename
        self.tags = tags
        self.links = links
    }
}

public struct Custom: Hashable {
    public let type: String
    public let values: [MetaDataValue]
    
    public init(type: String, values: [MetaDataValue]) {
        self.type = type
        self.values = values
    }
}
