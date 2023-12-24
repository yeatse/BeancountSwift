//
//  CoreDataStructures.swift
//
//
//  Created by Yeatse on 2023/12/21.
//
import Foundation

/// https://beancount.github.io/docs/beancount_design_doc.html#commodity
public struct Currency: Identifiable, Equatable, Hashable {
    public let id: String
}

extension Currency: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self.id = value
    }
}

/// https://beancount.github.io/docs/beancount_design_doc.html#account
public struct Account: Identifiable, Equatable, Hashable {
    public let id: String
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
    public let number: Decimal
    public let currency: Currency
}

extension Amount {
    public static prefix func - (amount: Amount) -> Amount {
        return Amount(number: -amount.number, currency: amount.currency)
    }
}

public protocol PostingCost: Equatable, Hashable {}

/// https://beancount.github.io/docs/beancount_design_doc.html#cost
public struct Cost: PostingCost {
    public let number: Decimal
    public let currency: Currency
    public let date: Date
    public let label: String?
}

/// https://beancount.github.io/docs/beancount_design_doc.html#costspec
public struct CostSpec: PostingCost {
    public let numberPerUnit: Decimal?
    public let numberTotal: Decimal?
    public let currency: Currency?
    public let date: Date?
    public let label: String?
    public let merge: Bool?
}

/// https://beancount.github.io/docs/beancount_design_doc.html#posting
public struct Posting<T: PostingCost>: Equatable {
    public let account: Account
    public let units: Amount
    public let cost: T?
    public let price: Amount?
    public let flag: Character?
    public let meta: [String: MetaDataValue]?
    public let comment: String?
}

public struct Tag: Equatable, Hashable, Identifiable {
    public let id: String
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
