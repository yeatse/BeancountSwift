//
//  Printer.swift
//
//
//  Created by 杨超 on 2024/2/11.
//

import Foundation

extension Option: CustomStringConvertible {
    public var description: String {
        "option \"\(key)\" \"\(value)\""
    }
}

extension Account: CustomStringConvertible {
    public var description: String { id }
}

extension Currency: CustomStringConvertible {
    public var description: String { id }
}

private extension Decimal {
    func formatted(withCurrency currency: Currency?) -> String {
        guard let currency else {
            return formatted(.number)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.id
        let fractionLength = formatter.minimumFractionDigits
        
        let result1 = formatted(.number.grouping(.never))
        let result2 = formatted(.number
            .precision(.fractionLength(fractionLength))
            .grouping(.never))
        if result1.count < result2.count {
            return result2
        } else {
            return result1
        }
    }
}

extension Amount: CustomStringConvertible {
    public var description: String {
        let num = number.formatted(withCurrency: currency)
        let curr = currency.description
        return "\(num) \(curr)"
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

extension CostSpec: CustomStringConvertible {
    public var description: String {
        var strlist: [String] = []
        if numberPerUnit != nil || numberTotal != nil {
            var amountlist: [String] = []
            if let numberPerUnit {
                amountlist.append(numberPerUnit.formatted(withCurrency: currency))
            }
            if let numberTotal {
                amountlist.append("#")
                amountlist.append(numberTotal.formatted(withCurrency: currency))
            }
            if let currency {
                amountlist.append(currency.description)
            }
            strlist.append(amountlist.joined(separator: " "))
        }
        if let date {
            strlist.append(date.isoDescription)
        }
        if let label {
            strlist.append("\"\(label)\"")
        }
        if let merge, merge {
            strlist.append("*")
        }
        return strlist.joined(separator: ", ")
    }
}

extension Position: CustomStringConvertible {
    public var description: String {
        var posStr = units.description
        if let cost {
            posStr += " {{\(cost.description)}}"
        }
        return posStr
    }
}

extension Posting: CustomStringConvertible {
    private var genericWeight: Amount {
        if let p = self as? Posting<Cost> {
            return p.weight
        } else if let p = self as? Posting<CostSpec> {
            return p.weight
        } else {
            fatalError()
        }
    }
    
    public var description: String {
        let flagStr: String
        if let flag {
            flagStr = String(flag)
        } else {
            flagStr = ""
        }
        
        var weightStr: String = ""
        var positionStr: String = ""
        
        if units != .missing {
            positionStr = units.description
            if let cost {
                positionStr += " {{\(cost.description)}}"
            }
            if cost == nil {
                weightStr = genericWeight.description
            } else if let cost = cost as? Cost, cost.number != .nan {
                weightStr = genericWeight.description
            }
        }
        if let price {
            positionStr += " @ \(price.number.formatted(.number.grouping(.never))) \(price.currency.description)"
        }
        
        var result = "\(flagStr)\(account.description) \(positionStr) ; \(weightStr)"
        if let meta {
            result.append("\n\(meta.toString.lineAligned())")
        }
        return result
    }
}

extension MetaDataValue: CustomStringConvertible {
    public var description: String {
        switch self {
            case .string(let string): "\"\(string.escaped)\""
            case .account(let account): account.description
            case .currency(let currency): currency.description
            case .date(let date): date.isoDescription
            case .tag(let tag): tag.id
            case .number(let decimal): decimal.formatted(.number.grouping(.never))
            case .bool(let bool): bool ? "TRUE" : "FALSE"
            case .amount(let amount): amount.description
            case .range: ""
        }
    }
}

private extension Dictionary where Key == String, Value == MetaDataValue {
    static let keysToIgnore: Set<String> = [
        "filename", "range", "lineno"
    ]
    
    var toString: String {
        var lines: [String] = []
        for (key, value) in self {
            guard !Self.keysToIgnore.contains(key) && !key.hasPrefix("__") else {
                continue
            }
            lines.append("\(key): \(value.description)")
        }
        return lines.joined(separator: "\n")
    }
}

extension Directive: CustomStringConvertible {
    public var description: String {
        switch content {
            case .transaction(let txn): txn.print(date: date, meta: meta, comment: comment)
            case .open(let open): open.print(date: date, meta: meta, comment: comment)
            default: ""
        }
    }
}

private protocol DirectivePrintable {
    func print(date: Date, meta: Dictionary<String, MetaDataValue>, comment: String?) -> String
}

extension Transaction: DirectivePrintable {
    func print(date: Date, meta: Dictionary<String, MetaDataValue>, comment: String?) -> String {
        var lines: [String] = []
        var strings: [String] = [
            date.isoDescription,
            flag.map(String.init) ?? "*",
        ]
        if let payee {
            strings.append("\"\(payee.escaped)\"")
        }
        if let narration {
            strings.append("\"\(narration.escaped)\"")
        } else if payee != nil {
            strings.append("\"\"")
        }
        
        for tag in self.tags {
            strings.append("#\(tag.id)")
        }
        for link in self.links {
            strings.append("^\(link)")
        }
        lines.append(strings.joined(separator: " "))
        let metaline = meta.toString.lineAligned()
        if !metaline.isEmpty {
            lines.append(metaline)
        }
        for posting in self.postings {
            lines.append(posting.description.lineAligned())
        }
        return lines.joined(separator: "\n")
    }
}

extension Open: DirectivePrintable {
    func print(date: Date, meta: Dictionary<String, MetaDataValue>, comment: String?) -> String {
        let currencies = self.currencies.map(\.description).joined(separator: ",")
        let booking = self.booking.map { "\"\($0.rawValue)\"" } ?? ""
        var result = "\(date.isoDescription) open \(account.description) \(currencies) \(booking)"
        if let comment, !comment.isEmpty {
            result += "    ;\(comment)"
        }
        let metaline = meta.toString.lineAligned()
        if !metaline.isEmpty {
            result += "\n" + metaline
        }
        return result
    }
}
