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
        let escapedValue = value
            .replacingOccurrences(of: "\"", with: #"\""#)
            .replacingOccurrences(of: "'", with: #"\'"#)
        return "option \"\(key)\" \"\(escapedValue)\""
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

extension Decimal {
    /// Formats a decimal number with currency-specific formatting.
    ///
    /// Uses AttributedString-based currency formatting to determine appropriate decimal
    /// precision while stripping the currency symbol from the output. When `rounded` is false,
    /// selects the longer of two precision options to preserve significant digits.
    ///
    /// - Parameters:
    ///   - currency: The currency for formatting context
    ///   - rounded: Whether to use standard currency rounding (default: false).
    ///              When false, preserves maximum precision between default and flexible formats.
    /// - Returns: The formatted decimal string without currency symbol
    fileprivate func formatted(withCurrency currency: Currency?, rounded: Bool = false) -> String {
        guard let currency else {
            return formatted(.number.grouping(.never))
        }

        var result = ""
        let attributed: AttributedString
        if rounded {
            attributed = magnitude.formatted(
                .currency(code: currency.id).presentation(.narrow).grouping(.never).attributed)
        } else {
            let attr1 = magnitude.formatted(
                .currency(code: currency.id).presentation(.narrow).grouping(.never).attributed)
            let attr2 = magnitude.formatted(
                .currency(code: currency.id).presentation(.narrow).grouping(.never).precision(
                    .fractionLength(0...)
                ).attributed)
            attributed = attr1.characters.count >= attr2.characters.count ? attr1 : attr2
        }
        for run in attributed.runs {
            if run.numberSymbol == .currency {
                continue
            } else {
                result += String(attributed[run.range].characters)
            }
        }
        let sign = isSignMinus ? "-" : ""
        return "\(sign)\(result.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

extension Amount: CustomStringConvertible {
    /// Returns the amount formatted in Beancount syntax.
    ///
    /// Formats as: `number CURRENCY` (e.g., "100.00 USD")
    /// Preserves original precision to maintain round-trip accuracy.
    ///
    /// - Returns: The amount in Beancount format
    public var description: String {
        let curr = currency.description
        if number.isNaN {
            return curr
        } else {
            let num = number.formatted(withCurrency: currency, rounded: true)
            return "\(num) \(curr)"
        }
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
        if let date, date != .distantPast {
            strlist.append(date.isoDescription)
        }
        if let label {
            strlist.append("\"\(label)\"")
        }
        return strlist.joined(separator: ", ")
    }
}

extension CostSpec: CustomStringConvertible {
    /// Whether this cost spec represents a total-only cost (no per-unit amount).
    public var isTotal: Bool {
        numberPerUnit == 0 && numberTotal != nil && numberTotal != .nan
    }
    /// Returns the cost specification formatted in Beancount syntax.
    ///
    /// Formats cost specification components including per-unit costs,
    /// total costs, dates, labels, and merge flags.
    ///
    /// - Returns: The cost specification in Beancount format
    public var description: String {
        var strlist: [String] = []
        if (numberPerUnit != nil && numberPerUnit != .nan)
            || (numberTotal != nil && numberTotal != .nan)
        {
            var amountlist: [String] = []
            if isTotal {
                amountlist.append(numberTotal!.formatted(withCurrency: currency))
            } else {
                if let numberPerUnit, numberPerUnit != .nan {
                    amountlist.append(numberPerUnit.formatted(withCurrency: currency))
                }
                if let numberTotal, numberTotal != .nan {
                    amountlist.append("#")
                    amountlist.append(numberTotal.formatted(withCurrency: currency))
                }
            }
            if let currency, currency != .missing {
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

extension Inventory: CustomStringConvertible {
    /// Returns the inventory formatted in Beancount syntax.
    ///
    /// Formats as a comma-separated list of positions.
    ///
    /// - Returns: The inventory in Beancount format
    public var description: String {
        positions.map(\.description).joined(separator: ", ")
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
            flagStr = "\(flag) "
        } else {
            flagStr = ""
        }

        var weightStr: String = ""
        var positionStr: String = ""

        if units != .missing {
            positionStr = units.description
            if let cost = cost as? CostSpec, cost.isTotal {
                positionStr += " {{\(cost.description)}}"
            } else if let cost {
                positionStr += " {\(cost.description)}"
            }
            if cost == nil {
                weightStr = genericWeight.description
            } else if let cost = cost as? Cost, cost.number != .nan {
                weightStr = genericWeight.description
            }
        }
        if let price {
            let num = price.number.isNaN ? "" : price.number.formatted(.number.grouping(.never))
            let curr = price.currency.description
            positionStr += " @ \(num) \(curr)"
        }

        var result = "\(flagStr)\(account.description)    \(positionStr)"
        if let comment {
            result += "  ; \(comment)"
        } else if cost != nil || price != nil {
            result += "  ; \(weightStr)"
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

extension OrderedDictionary where Key == String, Value == MetaDataValue {
    /// System metadata keys to ignore when formatting.
    ///
    /// These keys are used internally by the parser and should not
    /// appear in formatted output.
    fileprivate static let keysToIgnore: Set<String> = [
        "filename", "range", "lineno", Interpolate.automaticMeta,
    ]

    /// Converts metadata dictionary to formatted string.
    ///
    /// Formats user metadata (excluding system keys) as key-value pairs,
    /// one per line, suitable for inclusion in Beancount output.
    ///
    /// - Returns: The formatted metadata string
    fileprivate var toString: String {
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
    /// according to Beancount conventions.
    ///
    /// - Returns: The directive in Beancount format with trailing newline
    public var description: String {
        let text =
            switch content {
            case .transaction(let txn): txn.print(date: date, meta: meta, comment: comment)
            case .open(let open): open.print(date: date, meta: meta, comment: comment)
            case .custom(let custom): custom.print(date: date, meta: meta, comment: comment)
            case .pad(let pad): pad.print(date: date, meta: meta, comment: comment)
            case .balance(let balance): balance.print(date: date, meta: meta, comment: comment)
            case .close(let close): close.print(date: date, meta: meta, comment: comment)
            case .commodity(let commodity):
                commodity.print(date: date, meta: meta, comment: comment)
            case .note(let note): note.print(date: date, meta: meta, comment: comment)
            case .event(let event): event.print(date: date, meta: meta, comment: comment)
            case .query(let query): query.print(date: date, meta: meta, comment: comment)
            case .price(let price): price.print(date: date, meta: meta, comment: comment)
            case .document(let document): document.print(date: date, meta: meta, comment: comment)
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
            strings.append("  ; \(comment)")
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
            resultLine.append(" ; \(comment)")
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
            result += "    ; \(comment)"
        }
        let metaline = meta.toString.lineAligned()
        if !metaline.isEmpty {
            result += "\n" + metaline
        }
        return result
    }
}

extension Pad: DirectivePrintable {
    /// Formats the pad directive in Beancount syntax.
    ///
    /// Produces a pad directive with date, account, and source account.
    ///
    /// - Parameters:
    ///   - date: Pad directive date
    ///   - meta: Pad directive metadata
    ///   - comment: Optional directive comment
    /// - Returns: The formatted pad directive string
    func print(date: Date, meta: MetaData, comment: String?) -> String {
        var resultLine = [
            date.isoDescription, "pad", account.description, sourceAccount.description,
        ]
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.toString.lineAligned()
        if !metaline.isEmpty {
            result += "\n" + metaline
        }
        return result
    }
}

extension Balance: DirectivePrintable {
    /// Formats the balance directive in Beancount syntax.
    ///
    /// Produces a balance assertion with date, account, and expected amount.
    /// Optionally includes tolerance if specified, formatted as "number ~ tolerance currency".
    ///
    /// - Parameters:
    ///   - date: Balance directive date
    ///   - meta: Balance directive metadata
    ///   - comment: Optional directive comment
    /// - Returns: The formatted balance directive string
    func print(date: Date, meta: MetaData, comment: String?) -> String {
        var resultLine = [date.isoDescription, "balance", account.description]

        // Format amount with optional tolerance
        if let tolerance {
            let num = amount.number.formatted(withCurrency: amount.currency)
            let tol = tolerance.formatted(.number.grouping(.never))
            let curr = amount.currency.description
            resultLine.append("\(num) ~ \(tol) \(curr)")
        } else {
            resultLine.append(amount.description)
        }

        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        } else if let diffAmount {
            resultLine.append(" ; Diff: \(diffAmount.description)")
        }

        var result = resultLine.joined(separator: " ")
        let metaline = meta.toString.lineAligned()
        if !metaline.isEmpty {
            result += "\n" + metaline
        }
        return result
    }
}

extension Close: DirectivePrintable {
    /// Formats the close directive in Beancount syntax.
    ///
    /// Produces a close directive with date and account.
    ///
    /// - Parameters:
    ///   - date: Close directive date
    ///   - meta: Close directive metadata
    ///   - comment: Optional directive comment
    /// - Returns: The formatted close directive string
    func print(date: Date, meta: MetaData, comment: String?) -> String {
        var resultLine = [date.isoDescription, "close", account.description]
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.toString.lineAligned()
        if !metaline.isEmpty {
            result += "\n" + metaline
        }
        return result
    }
}

extension Commodity: DirectivePrintable {
    /// Formats the commodity directive in Beancount syntax.
    ///
    /// Produces a commodity declaration with date and currency.
    ///
    /// - Parameters:
    ///   - date: Commodity directive date
    ///   - meta: Commodity directive metadata
    ///   - comment: Optional directive comment
    /// - Returns: The formatted commodity directive string
    func print(date: Date, meta: MetaData, comment: String?) -> String {
        var resultLine = [date.isoDescription, "commodity", currency.description]
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.toString.lineAligned()
        if !metaline.isEmpty {
            result += "\n" + metaline
        }
        return result
    }
}

extension Note: DirectivePrintable {
    /// Formats the note directive in Beancount syntax.
    ///
    /// Produces a note with date, account, and quoted note text.
    ///
    /// - Parameters:
    ///   - date: Note directive date
    ///   - meta: Note directive metadata
    ///   - comment: Optional directive comment
    /// - Returns: The formatted note directive string
    func print(date: Date, meta: MetaData, comment: String?) -> String {
        var resultLine = [
            date.isoDescription,
            "note",
            account.description,
            "\"\(note.escaped)\"",
        ]
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.toString.lineAligned()
        if !metaline.isEmpty {
            result += "\n" + metaline
        }
        return result
    }
}

extension Event: DirectivePrintable {
    /// Formats the event directive in Beancount syntax.
    ///
    /// Produces an event with date, type, and description.
    ///
    /// - Parameters:
    ///   - date: Event directive date
    ///   - meta: Event directive metadata
    ///   - comment: Optional directive comment
    /// - Returns: The formatted event directive string
    func print(date: Date, meta: MetaData, comment: String?) -> String {
        var resultLine = [
            date.isoDescription,
            "event",
            "\"\(type.escaped)\"",
            "\"\(description.escaped)\"",
        ]
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.toString.lineAligned()
        if !metaline.isEmpty {
            result += "\n" + metaline
        }
        return result
    }
}

extension Query: DirectivePrintable {
    /// Formats the query directive in Beancount syntax.
    ///
    /// Produces a query with date, name, and query string.
    ///
    /// - Parameters:
    ///   - date: Query directive date
    ///   - meta: Query directive metadata
    ///   - comment: Optional directive comment
    /// - Returns: The formatted query directive string
    func print(date: Date, meta: MetaData, comment: String?) -> String {
        var resultLine = [
            date.isoDescription,
            "query",
            "\"\(name.escaped)\"",
            "\"\(queryString.escaped)\"",
        ]
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.toString.lineAligned()
        if !metaline.isEmpty {
            result += "\n" + metaline
        }
        return result
    }
}

extension Price: DirectivePrintable {
    /// Formats the price directive in Beancount syntax.
    ///
    /// Produces a price with date, currency, and amount.
    ///
    /// - Parameters:
    ///   - date: Price directive date
    ///   - meta: Price directive metadata
    ///   - comment: Optional directive comment
    /// - Returns: The formatted price directive string
    func print(date: Date, meta: MetaData, comment: String?) -> String {
        var resultLine = [
            date.isoDescription,
            "price",
            currency.description,
            amount.description,
        ]
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.toString.lineAligned()
        if !metaline.isEmpty {
            result += "\n" + metaline
        }
        return result
    }
}

extension Document: DirectivePrintable {
    /// Formats the document directive in Beancount syntax.
    ///
    /// Produces a document with date, account, filename, and optional tags/links.
    ///
    /// - Parameters:
    ///   - date: Document directive date
    ///   - meta: Document directive metadata
    ///   - comment: Optional directive comment
    /// - Returns: The formatted document directive string
    func print(date: Date, meta: MetaData, comment: String?) -> String {
        var resultLine = [
            date.isoDescription,
            "document",
            account.description,
            "\"\(filename.escaped)\"",
        ]
        if let tags {
            for tag in tags {
                resultLine.append("#\(tag.id)")
            }
        }
        if let links {
            for link in links {
                resultLine.append("^\(link.id)")
            }
        }
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.toString.lineAligned()
        if !metaline.isEmpty {
            result += "\n" + metaline
        }
        return result
    }
}
