//
//  CoreDataStructures.swift
//
//
//  Created by Yeatse on 2023/12/21.
//
import Foundation
import SwiftTreeSitter

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
    static let missing = Currency(id: "")
}

public protocol PostingCost: Hashable {}

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

extension Cost: CustomStringConvertible {
    public var description: String {
        var strlist: [String] = []
        if number != .nan {
            strlist.append(Amount(number: number, currency: currency).description)
        }
        if date != .distantPast {
            strlist.append(date.isoDescription)
        }
        if let label {
            strlist.append("\"\(label)\"")
        }
        return strlist.joined(separator: ", ")
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
public struct Posting<T: PostingCost>: Hashable {
    public var account: Account
    public var units: Amount
    public var cost: T?
    public var price: Amount?
    public var flag: Character?
    public var meta: [String: MetaDataValue]?
    public var comment: String?
}

public struct Tag: Hashable, Identifiable {
    public var id: String
}

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

extension Dictionary where Key == String, Value == MetaDataValue {
    public var lineno: UInt32? {
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
