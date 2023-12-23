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

/// https://beancount.github.io/docs/beancount_design_doc.html#cost
public struct Cost: Equatable, Hashable {
    public let number: Decimal
    public let currency: Currency
    public let date: Date
    public let label: String?
}

/// https://beancount.github.io/docs/beancount_design_doc.html#costspec
public struct CostSpec: Equatable {
    public let numberPerUnit: Decimal?
    public let numberTotal: Decimal?
    public let currency: Currency?
    public let date: Date?
    public let label: String?
    public let merge: Bool?
}

public enum CostOrCostSpec: Equatable {
    case cost(Cost)
    case costSpec(CostSpec)
}

/// https://beancount.github.io/docs/beancount_design_doc.html#position
public struct Position: Equatable, Hashable {
    public let units: Amount
    public let cost: Cost?
}

/// https://beancount.github.io/docs/beancount_design_doc.html#posting
public struct Posting: Equatable {
    public let account: Account
    public let units: Amount
    public let cost: CostOrCostSpec?
    public let price: Amount?
    public let flag: Character?
    public let meta: [String: Any]?
    public let comment: String?
    
    public static func == (lhs: Posting, rhs: Posting) -> Bool {
        lhs.account == rhs.account
        && lhs.units == rhs.units
        && lhs.cost == rhs.cost
        && lhs.price == rhs.price
        && lhs.flag == rhs.flag
        && lhs.meta?.lineno == rhs.meta?.lineno
    }
}

/// https://beancount.github.io/docs/beancount_design_doc.html#inventory
public struct Inventory {
    public let positions: [Position]
}

extension Dictionary where Key == String {
    var lineno: UInt32? {
        return self["lineno"] as? UInt32
    }
    
    var filename: String? {
        return self["filename"] as? String
    }
}
