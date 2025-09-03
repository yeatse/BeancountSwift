//
//  Printer.swift
//
//
//  Created by 杨超 on 2024/2/11.
//

/// Provides string formatting and printing capabilities for Beancount data structures.
/// 
/// This module implements CustomStringConvertible for all major Beancount types,
/// enabling them to be converted back to their original Beancount text format.
/// This is essential for round-trip processing, debugging, and generating output files.
/// 
/// The printing functionality corresponds to the format_entry functions in the
/// original Beancount Python library, maintaining compatibility with the standard format.

import Foundation
import OrderedCollections

extension Option: CustomStringConvertible {
    /// Returns the option formatted as Beancount option directive syntax.
    /// 
    /// Formats as: `option "key" "value"`
    /// 
    /// - Returns: The option in Beancount syntax format
    public var description: String {
        "option \"\(key)\" \"\(value)\""
    }
}

extension Account: CustomStringConvertible {
    /// Returns the account ID.
    /// 
    /// - Returns: The account identifier string
    public var description: String { id }
}

extension Currency: CustomStringConvertible {
    /// Returns the currency ID.
    /// 
    /// - Returns: The currency identifier string
    public var description: String { id }
}

private extension Decimal {
    /// Formats a decimal number with currency-specific formatting.
    /// 
    /// Applies appropriate decimal precision and formatting based on the currency.
    /// Uses the shorter of two formatting options to minimize string length.
    /// 
    /// - Parameter currency: The currency for formatting context
    /// - Returns: The formatted decimal string
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
    /// Returns the amount formatted in Beancount syntax.
    /// 
    /// Formats as: `number CURRENCY` (e.g., "100.00 USD")
    /// 
    /// - Returns: The amount in Beancount format
    public var description: String {
        let num = number.formatted(withCurrency: currency)
        let curr = currency.description
        return "\(num) \(curr)"
    }
}

extension Cost: CustomStringConvertible {
    /// Returns the cost formatted in Beancount syntax.
    /// 
    /// Formats cost components (amount, date, label) separated by commas.
    /// Omits components that are not set or have default values.
    /// 
    /// - Returns: The cost in Beancount format
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
    /// Returns the cost specification formatted in Beancount syntax.
    /// 
    /// Formats cost specification components including per-unit costs,
    /// total costs, dates, labels, and merge flags.
    /// 
    /// - Returns: The cost specification in Beancount format
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
    /// Returns the position formatted in Beancount syntax.
    /// 
    /// Formats as: `amount {cost}` where cost is included if present.
    /// Uses double braces for cost specification formatting.
    /// 
    /// - Returns: The position in Beancount format
    public var description: String {
        var posStr = units.description
        if let cost {
            posStr += " {{\(cost.description)}}"
        }
        return posStr
    }
}

extension Posting: CustomStringConvertible {
    /// Computes the generic weight for any posting type.
    /// 
    /// Handles both Cost and CostSpec posting types by casting and
    /// computing their respective weights.
    /// 
    /// - Returns: The weight amount for the posting
    private var genericWeight: Amount {
        if let p = self as? Posting<Cost> {
            return p.weight
        } else if let p = self as? Posting<CostSpec> {
            return p.weight
        } else {
            fatalError()
        }
    }
    
    /// Returns the posting formatted in Beancount syntax.
    /// 
    /// Formats the complete posting including flag, account, units, cost,
    /// price, weight comment, and metadata. Follows standard Beancount
    /// posting format with proper indentation and alignment.
    /// 
    /// - Returns: The posting in Beancount format
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
        
        var result = "\(flagStr)\(account.description) \(positionStr)"
        if cost != nil || price != nil {
            result += " ; \(weightStr)"
        }
        if let meta {
            result += "\n\(meta.toString.lineAligned())"
        }
        return result
    }
}

extension MetaDataValue: CustomStringConvertible {
    /// Returns the metadata value formatted for Beancount output.
    /// 
    /// Formats each metadata value type according to Beancount conventions,
    /// including proper quoting for strings and appropriate formatting for dates.
    /// 
    /// - Returns: The metadata value in Beancount format
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

private extension OrderedDictionary where Key == String, Value == MetaDataValue {
    /// System metadata keys to ignore when formatting.
    /// 
    /// These keys are used internally by the parser and should not
    /// appear in formatted output.
    static let keysToIgnore: Set<String> = [
        "filename", "range", "lineno"
    ]
    
    /// Converts metadata dictionary to formatted string.
    /// 
    /// Formats user metadata (excluding system keys) as key-value pairs,
    /// one per line, suitable for inclusion in Beancount output.
    /// 
    /// - Returns: The formatted metadata string
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
    /// Returns the directive formatted in Beancount syntax.
    /// 
    /// Formats the complete directive including date, metadata, and content
    /// according to Beancount conventions. Currently supports transaction,
    /// open, and custom directives.
    /// 
    /// - Returns: The directive in Beancount format with trailing newline
    public var description: String {
        let text = switch content {
            case .transaction(let txn): txn.print(date: date, meta: meta, comment: comment)
            case .open(let open): open.print(date: date, meta: meta, comment: comment)
            case .custom(let custom): custom.print(date: date, meta: meta, comment: comment)
            default: ""
        }
        return text.appending("\n")
    }
}

/// Protocol for directive types that can be formatted as Beancount text.
/// 
/// DirectivePrintable defines the interface for directive content types
/// to format themselves as Beancount syntax strings.
private protocol DirectivePrintable {
    /// Formats the directive content with common directive properties.
    /// 
    /// - Parameters:
    ///   - date: The directive date
    ///   - meta: The directive metadata
    ///   - comment: Optional directive comment
    /// - Returns: The formatted directive string
    func print(date: Date, meta: MetaData, comment: String?) -> String
}

extension Transaction: DirectivePrintable {
    /// Formats the transaction in standard Beancount syntax.
    /// 
    /// Produces a complete transaction with header line containing date, flag,
    /// payee, narration, tags, and links, followed by metadata and postings.
    /// 
    /// - Parameters:
    ///   - date: Transaction date
    ///   - meta: Transaction metadata
    ///   - comment: Optional transaction comment
    /// - Returns: The formatted transaction string
    func print(date: Date, meta: MetaData, comment: String?) -> String {
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
            strings.append("^\(link.id)")
        }
        if let comment, !comment.isEmpty {
            strings.append("  ;\(comment)")
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
    /// Formats the open directive in Beancount syntax.
    /// 
    /// Produces an open directive with date, account, currencies, and booking method.
    /// 
    /// - Parameters:
    ///   - date: Open directive date
    ///   - meta: Open directive metadata
    ///   - comment: Optional directive comment
    /// - Returns: The formatted open directive string
    func print(date: Date, meta: MetaData, comment: String?) -> String {
        let currencies = self.currencies.map(\.description).joined(separator: ",")
        let booking = self.booking.map { "\"\($0.rawValue)\"" } ?? ""
        
        var resultLine = [date.isoDescription, "open", account.description]
        if !currencies.isEmpty {
            resultLine.append(currencies)
        }
        if !booking.isEmpty {
            resultLine.append(booking)
        }
        if let comment, !comment.isEmpty {
            resultLine.append(" ;\(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.toString.lineAligned()
        if !metaline.isEmpty {
            result += "\n" + metaline
        }
        return result
    }
}

extension Custom: DirectivePrintable {
    /// Formats the custom directive in Beancount syntax.
    /// 
    /// Produces a custom directive with date, type, and values.
    /// 
    /// - Parameters:
    ///   - date: Custom directive date
    ///   - meta: Custom directive metadata
    ///   - comment: Optional directive comment
    /// - Returns: The formatted custom directive string
    func print(date: Date, meta: MetaData, comment: String?) -> String {
        let customValues = values.map(\.description).joined(separator: " ")
        var result = "\(date.isoDescription) custom \"\(type)\" \(customValues)"
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
