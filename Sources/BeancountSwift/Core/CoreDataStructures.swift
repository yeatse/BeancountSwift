//
//  CoreDataStructures.swift
//
//
//  Created by Yeatse on 2023/12/21.
//
import Foundation
import SwiftTreeSitter
import OrderedCollections

/// https://beancount.github.io/docs/beancount_design_doc.html#commodity
public struct Currency: Identifiable, Hashable {
    public var id: String
    
    public init(id: String) {
        self.id = id
    }
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
    public static let missing = Currency(id: "")
}

public protocol PostingCost: Hashable, CustomStringConvertible {}

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
    
    public init(numberPerUnit: Decimal? = nil, numberTotal: Decimal? = nil, currency: Currency? = nil, date: Date? = nil, label: String? = nil, merge: Bool? = nil) {
        self.numberPerUnit = numberPerUnit
        self.numberTotal = numberTotal
        self.currency = currency
        self.date = date
        self.label = label
        self.merge = merge
    }
}

public typealias MetaData = OrderedDictionary<String, MetaDataValue>

/// https://beancount.github.io/docs/beancount_design_doc.html#posting
public struct Posting<T: PostingCost>: Hashable {
    public var account: Account
    ///  the units of the position, or nil if it is to be inferred from the other postings in the transaction.
    public var units: Amount
    public var cost: T?
    public var price: Amount?
    public var flag: Character?
    public var meta: MetaData?
    public var comment: String?
    
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

public struct Tag: Hashable, Identifiable {
    public var id: String
    
    public init(id: String) {
        self.id = id
    }
}

extension Tag: Comparable {
    public static func < (lhs: Tag, rhs: Tag) -> Bool {
        lhs.id < rhs.id
    }
}

#if DEBUG
extension Tag: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self.id = value
    }
}
#endif

public enum MetaDataValue: Hashable {
    case string(String)
    case account(Account)
    case currency(Currency)
    case date(Date)
    case tag(Tag)
    case number(Decimal)
    case bool(Bool)
    case amount(Amount)
    case range(TSRange)
}

extension OrderedDictionary where Key == String, Value == MetaDataValue {
    public var lineno: UInt32? {
        if case .number(let val) = self["lineno"] {
            return NSDecimalNumber(decimal: val).uint32Value
        }
        return range?.points.lowerBound.row
    }
    
    public var filename: String? {
        if case .string(let val) = self["filename"] {
            return val
        } else {
            return nil
        }
    }
    
    public var range: TSRange? {
        if case .range(let val) = self["range"] {
            return val
        } else {
            return nil
        }
    }
}
