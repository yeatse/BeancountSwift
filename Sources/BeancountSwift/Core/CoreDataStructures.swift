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

extension Currency: Comparable {
    public static func < (lhs: Currency, rhs: Currency) -> Bool {
        lhs.id < rhs.id
    }
}

extension Currency {
    static let missing = Currency(id: "__MISSING__")
}

/// https://beancount.github.io/docs/beancount_design_doc.html#account
public struct Account: Identifiable, Equatable, Hashable {
    public var id: String
}

extension Account: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self.id = value
    }
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

extension Amount: Comparable {
    public static func < (lhs: Amount, rhs: Amount) -> Bool {
        if lhs.currency != rhs.currency {
            return lhs.currency < rhs.currency
        } else {
            return lhs.number < rhs.number
        }
    }

    public static prefix func - (amount: Amount) -> Amount {
        Amount(number: -amount.number, currency: amount.currency)
    }

    var absolute: Amount {
        if number >= .zero {
            self
        } else {
            Amount(number: -number, currency: currency)
        }
    }

    static func * (lhs: Amount, rhs: Decimal) -> Amount {
        Amount(number: lhs.number * rhs, currency: lhs.currency)
    }
}

extension Amount: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        guard
            let match = value.wholeMatch(
                of:
                    #/\s*([+-]?[0-9.]+)\s+([A-Z][A-Z0-9'\.\_\-]*[A-Z0-9]?\b|/[A-Z0-9'\.\_\-]*[A-Z](?:[A-Z0-9'\.\_\-]*[A-Z0-9])?)/#
            )
        else {
            fatalError()
        }
        self.number = Decimal(string: String(match.1))!
        self.currency = Currency(id: String(match.2))
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

extension Cost: Comparable {
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

extension Dictionary where Key == String, Value == MetaDataValue {
    var lineno: UInt32? {
        if case .number(let val) = self["lineno"] {
            return .init(exactly: NSDecimalNumber(decimal: val))
        } else {
            return nil
        }
    }

    var filename: String? {
        if case .string(let val) = self["filename"] {
            return val
        } else {
            return nil
        }
    }
}
