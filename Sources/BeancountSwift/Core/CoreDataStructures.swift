//
//  CoreDataStructures.swift
//
//
//  Created by Yeatse on 2023/12/21.
//
import Foundation

/// https://beancount.github.io/docs/beancount_design_doc.html#commodity
public struct Currency: Identifiable, Equatable, Hashable {
    public var id: String
}

extension Currency: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self.id = value
    }
}

extension Currency {
    static let missing = Currency(id: "__MISSING__")
}

/// https://beancount.github.io/docs/beancount_design_doc.html#account
public struct Account: Identifiable, Equatable, Hashable {
    public var id: String
}

public enum AccountType: String {
    case Assets
    case Liabilities
    case Equity
    case Income
    case Expenses
}

/// https://beancount.github.io/docs/beancount_design_doc.html#amount
public struct Amount: Equatable, Hashable {
    public var number: Decimal
    public var currency: Currency

    static let missing = Amount(number: .nan, currency: .missing)
}

extension Amount {
    public static prefix func - (amount: Amount) -> Amount {
        return Amount(number: -amount.number, currency: amount.currency)
    }
}

public protocol PostingCost: Equatable, Hashable {}

/// https://beancount.github.io/docs/beancount_design_doc.html#cost
public struct Cost: PostingCost {
    public var number: Decimal
    public var currency: Currency
    public var date: Date
    public var label: String?
}

/// https://beancount.github.io/docs/beancount_design_doc.html#costspec
public struct CostSpec: PostingCost {
    public var numberPerUnit: Decimal?
    public var numberTotal: Decimal?
    public var currency: Currency?
    public var date: Date?
    public var label: String?
    public var merge: Bool?
}

/// https://beancount.github.io/docs/beancount_design_doc.html#posting
public struct Posting<T: PostingCost>: Equatable {
    public var account: Account
    public var units: Amount
    public var cost: T?
    public var price: Amount?
    public var flag: Character?
    public var meta: [String: MetaDataValue]?
    public var comment: String?
}

public struct Tag: Equatable, Hashable, Identifiable {
    public var id: String
}

public enum MetaDataValue: Equatable {
    case string(String)
    case account(Account)
    case currency(Currency)
    case date(Date)
    case tag(Tag)
    case number(Decimal)
    case bool(Bool)
    case amount(Amount)
}

extension Dictionary where Key == String {
    var lineno: UInt32? {
        return self["lineno"] as? UInt32
    }

    var filename: String? {
        return self["filename"] as? String
    }
}
