//
//  Printer.swift
//
//
//  Created by 杨超 on 2024/2/11.
//

/// Provides string formatting and printing capabilities for Beancount data structures.
///
/// This module implements the ``Printable`` protocol for all major Beancount
/// types, enabling them to be converted back to their original Beancount text
/// format. `Printable` refines `CustomStringConvertible`, so these types also
/// work in string interpolation and debugging. This is essential for round-trip
/// processing and generating output files.
///
/// The printing functionality corresponds to the format_entry functions in the
/// original Beancount Python library, maintaining compatibility with the standard format.

import Foundation
import OrderedCollections

/// Formatting options used when rendering directives back to Beancount text.
///
/// Mirrors the role of Beancount's `EntryPrinter` configuration (notably its
/// `prefix`): it lets callers control the indentation applied to postings and
/// metadata continuation lines. Pass a context to ``Printable/formatted(_:)``;
/// ``CustomStringConvertible`` conformances fall back to ``FormatContext/default``.
public struct FormatContext: Sendable, Equatable {
    /// The prefix prepended to each indented line (postings and metadata).
    public var indent: String

    /// Explicit fractional digits keyed by currency.
    ///
    /// Values originate from Beancount's `display_precision` options and take
    /// precedence over ISO currency defaults.
    public var displayPrecision: [Currency: Int]

    /// Creates a context with an explicit indent prefix.
    ///
    /// - Parameter indent: The whitespace prefix used for one indentation level
    ///   (default: four spaces, matching Beancount's conventional output).
    public init(indent: String = "    ", displayPrecision: [Currency: Int] = [:]) {
        self.indent = indent
        self.displayPrecision = displayPrecision
    }

    /// Creates a context that indents by a number of spaces.
    ///
    /// - Parameter indentWidth: The number of spaces per indentation level.
    public init(indentWidth: Int, displayPrecision: [Currency: Int] = [:]) {
        self.indent = String(repeating: " ", count: max(0, indentWidth))
        self.displayPrecision = displayPrecision
    }

    /// Creates a context using the ledger's `display_precision` options.
    public init(options: Options, indent: String = "    ") {
        self.indent = indent
        self.displayPrecision = [:]
        for option in options.rawOptions["display_precision"] ?? [] {
            let components = option.split(separator: ":", maxSplits: 1).map(String.init)
            guard components.count == 2,
                let precision = Amount.inferredPrecision(from: components[1])
            else {
                continue
            }
            self.displayPrecision[Currency(id: components[0])] = precision
        }
    }

    /// The default context: four-space indentation.
    public static let `default` = FormatContext()
}

/// A Beancount value that can render itself as source text.
///
/// Conformers implement ``formatted(_:)`` to produce their Beancount
/// representation, controlling indentation of any nested lines via a
/// ``FormatContext``. `Printable` refines `CustomStringConvertible` and
/// provides a default ``description`` derived from ``FormatContext/default``,
/// so conformers get string interpolation and round-trip printing for free.
public protocol Printable: CustomStringConvertible {
    /// Returns the Beancount source representation using the given context.
    ///
    /// - Parameter context: Formatting options controlling indentation. Values
    ///   without nested lines may ignore it.
    func formatted(_ context: FormatContext) -> String
}

extension Printable {
    /// The Beancount representation using the default (four-space) context.
    public var description: String { formatted(.default) }
}

extension ParsedLedger {
    /// Formats every directive using the ledger's display options.
    public func formatted(indent: String = "    ") -> String {
        let context = FormatContext(options: options, indent: indent)
        return directives.map { $0.formatted(context) }.joined()
    }
}

extension Option: Printable {
    /// Returns the option formatted as Beancount option directive syntax.
    ///
    /// Formats as: `option "key" "value"`
    public func formatted(_ context: FormatContext) -> String {
        let escapedValue =
            value
            .replacingOccurrences(of: "\"", with: #"\""#)
            .replacingOccurrences(of: "'", with: #"\'"#)
        return "option \"\(key)\" \"\(escapedValue)\""
    }
}

extension Account: Printable {
    /// Returns the account ID.
    public func formatted(_ context: FormatContext) -> String { id }
}

extension Currency: Printable {
    /// Returns the currency ID.
    public func formatted(_ context: FormatContext) -> String { id }
}

extension Decimal {
    /// Locale used for machine-readable Beancount source.
    ///
    /// Beancount reserves `.` for the decimal separator and `,` for optional
    /// thousands grouping, so source formatting must stay independent of the
    /// user's regional settings.
    private static let beancountLocale = Locale(identifier: "en_US_POSIX")

    /// ISO 4217 fractional digits resolved once through Foundation currency data.
    private static let isoCurrencyFractionDigits: [String: Int] = {
        var result: [String: Int] = [:]
        for code in Locale.commonISOCurrencyCodes {
            let formatter = NumberFormatter()
            formatter.locale = beancountLocale
            formatter.numberStyle = .currency
            formatter.currencyCode = code
            result[code] = formatter.maximumFractionDigits
        }
        return result
    }()

    fileprivate static func hasISODefault(for currency: Currency) -> Bool {
        isoCurrencyFractionDigits[currency.id] != nil
    }

    /// Returns a locale-independent canonical decimal representation.
    fileprivate var beancountRawDescription: String {
        var value = self
        return NSDecimalString(&value, Self.beancountLocale)
    }

    /// Formats using an explicit precision, an ISO currency default, or two digits.
    fileprivate func beancountCurrencyDescription(
        currency: Currency,
        context: FormatContext
    ) -> String {
        let fractionalDigits =
            context.displayPrecision[currency]
            ?? Self.isoCurrencyFractionDigits[currency.id]
            ?? 2
        let value = rounded(fractionalDigits, .bankers)
        return value.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(fractionalDigits))
                .locale(Self.beancountLocale)
        )
    }
}

extension Amount: Printable {
    /// Returns the amount formatted in Beancount syntax.
    ///
    /// Formats as: `number CURRENCY` (e.g., "100.00 USD")
    /// Preserves original precision to maintain round-trip accuracy.
    public func formatted(_ context: FormatContext) -> String {
        let curr = currency.description
        if number.isNaN {
            return curr
        } else {
            let num = number.beancountCurrencyDescription(currency: currency, context: context)
            return "\(num) \(curr)"
        }
    }

    /// Returns the amount with its Decimal canonical representation.
    func rawFormatted() -> String {
        if number.isNaN {
            return currency.description
        }
        return "\(number.beancountRawDescription) \(currency)"
    }

    /// Formats generated explanatory text while preserving custom commodities.
    func narrationFormatted() -> String {
        Decimal.hasISODefault(for: currency) ? formatted(.default) : rawFormatted()
    }
}

extension Cost: Printable {
    /// Returns the cost formatted in Beancount syntax.
    ///
    /// Formats cost components (amount, date, label) separated by commas.
    /// Omits components that are not set or have default values.
    public func formatted(_ context: FormatContext) -> String {
        var strlist: [String] = []
        if number != .nan {
            strlist.append(Amount(number: number, currency: currency).formatted(context))
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

extension CostSpec: Printable {
    /// Whether this cost spec represents a total-only cost (no per-unit amount).
    public var isTotal: Bool {
        numberPerUnit == 0 && numberTotal != nil && numberTotal != .nan
    }
    /// Returns the cost specification formatted in Beancount syntax.
    ///
    /// Formats cost specification components including per-unit costs,
    /// total costs, dates, labels, and merge flags.
    public func formatted(_ context: FormatContext) -> String {
        var strlist: [String] = []
        if (numberPerUnit != nil && numberPerUnit != .nan)
            || (numberTotal != nil && numberTotal != .nan)
        {
            var amountlist: [String] = []
            if isTotal {
                amountlist.append(numberTotal!.beancountRawDescription)
            } else {
                if let numberPerUnit, numberPerUnit != .nan {
                    amountlist.append(numberPerUnit.beancountRawDescription)
                }
                if let numberTotal, numberTotal != .nan {
                    amountlist.append("#")
                    amountlist.append(numberTotal.beancountRawDescription)
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

extension Position: Printable {
    /// Returns the position formatted in Beancount syntax.
    ///
    /// Formats as: `amount {cost}` where cost is included if present.
    /// Uses double braces for cost specification formatting.
    public func formatted(_ context: FormatContext) -> String {
        var posStr = units.formatted(context)
        if let cost {
            posStr += " {{\(cost.formatted(context))}}"
        }
        return posStr
    }
}

extension Inventory: Printable {
    /// Returns the inventory formatted in Beancount syntax.
    ///
    /// Formats as a comma-separated list of positions.
    public func formatted(_ context: FormatContext) -> String {
        positions.map { $0.formatted(context) }.joined(separator: ", ")
    }
}

extension Posting: Printable {
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

    /// Returns the posting formatted in Beancount syntax using the given context.
    ///
    /// Formats the complete posting including flag, account, units, cost,
    /// price, weight comment, and metadata. Nested metadata is indented using
    /// the context's indentation prefix.
    ///
    /// - Parameter context: Formatting options controlling indentation.
    /// - Returns: The posting in Beancount format
    public func formatted(_ context: FormatContext) -> String {
        let flagStr: String
        if let flag {
            flagStr = "\(flag) "
        } else {
            flagStr = ""
        }

        var weightStr: String = ""
        var positionStr: String = ""

        if units != .missing {
            positionStr = units.formatted(context)
            if let cost = cost as? CostSpec, cost.isTotal {
                positionStr += " {{\(cost.formatted(context))}}"
            } else if let cost = cost as? CostSpec {
                positionStr += " {\(cost.formatted(context))}"
            } else if let cost = cost as? Cost {
                positionStr += " {\(cost.formatted(context))}"
            }
            if cost == nil {
                weightStr = genericWeight.rawFormatted()
            } else if let cost = cost as? Cost, cost.number != .nan {
                weightStr = genericWeight.rawFormatted()
            }
        }
        if let price {
            let num = price.number.isNaN ? "" : price.number.beancountRawDescription
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
            result += "\n\(meta.formatted(context).lineAligned(by: context.indent))"
        }
        return result
    }
}

extension MetaDataValue: Printable {
    /// Returns the metadata value formatted for Beancount output.
    ///
    /// Formats each metadata value type according to Beancount conventions,
    /// including proper quoting for strings and appropriate formatting for dates.
    public func formatted(_ context: FormatContext) -> String {
        switch self {
        case .string(let string): string.quoted
        case .account(let account): account.description
        case .currency(let currency): currency.description
        case .date(let date): date.isoDescription
        case .tag(let tag): "#\(tag.id)"
        case .number(let decimal): decimal.beancountRawDescription
        case .bool(let bool): bool ? "TRUE" : "FALSE"
        case .amount(let amount): amount.formatted(context)
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
    fileprivate func formatted(_ context: FormatContext) -> String {
        var lines: [String] = []
        for (key, value) in self {
            guard !Self.keysToIgnore.contains(key) && !key.hasPrefix("__") else {
                continue
            }
            lines.append("\(key): \(value.formatted(context))")
        }
        return lines.joined(separator: "\n")
    }
}

extension Directive: Printable {
    /// Returns the directive formatted in Beancount syntax using the given context.
    ///
    /// Formats the complete directive including date, metadata, and content
    /// according to Beancount conventions, applying the context's indentation to
    /// postings and metadata continuation lines.
    ///
    /// - Parameter context: Formatting options controlling indentation.
    /// - Returns: The directive in Beancount format with trailing newline
    public func formatted(_ context: FormatContext) -> String {
        let text =
            switch content {
            case .transaction(let txn):
                txn.print(date: date, meta: meta, comment: comment, context: context)
            case .open(let open):
                open.print(date: date, meta: meta, comment: comment, context: context)
            case .custom(let custom):
                custom.print(date: date, meta: meta, comment: comment, context: context)
            case .pad(let pad):
                pad.print(date: date, meta: meta, comment: comment, context: context)
            case .balance(let balance):
                balance.print(date: date, meta: meta, comment: comment, context: context)
            case .close(let close):
                close.print(date: date, meta: meta, comment: comment, context: context)
            case .commodity(let commodity):
                commodity.print(date: date, meta: meta, comment: comment, context: context)
            case .note(let note):
                note.print(date: date, meta: meta, comment: comment, context: context)
            case .event(let event):
                event.print(date: date, meta: meta, comment: comment, context: context)
            case .query(let query):
                query.print(date: date, meta: meta, comment: comment, context: context)
            case .price(let price):
                price.print(date: date, meta: meta, comment: comment, context: context)
            case .document(let document):
                document.print(date: date, meta: meta, comment: comment, context: context)
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
    ///   - context: Formatting options controlling indentation
    /// - Returns: The formatted directive string
    func print(date: Date, meta: MetaData, comment: String?, context: FormatContext) -> String
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
    func print(date: Date, meta: MetaData, comment: String?, context: FormatContext) -> String {
        var lines: [String] = []
        var strings: [String] = [
            date.isoDescription,
            flag.map(String.init) ?? "*",
        ]
        if let payee {
            strings.append(payee.quoted)
        }
        if let narration {
            strings.append(narration.quoted)
        } else if payee != nil {
            strings.append(#""""#)
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
        let metaline = meta.formatted(context).lineAligned(by: context.indent)
        if !metaline.isEmpty {
            lines.append(metaline)
        }
        for posting in self.postings {
            lines.append(posting.formatted(context).lineAligned(by: context.indent))
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
    func print(date: Date, meta: MetaData, comment: String?, context: FormatContext) -> String {
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
        let metaline = meta.formatted(context).lineAligned(by: context.indent)
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
    func print(date: Date, meta: MetaData, comment: String?, context: FormatContext) -> String {
        let customValues = values.map { $0.formatted(context) }.joined(separator: " ")
        var result = "\(date.isoDescription) custom \"\(type)\" \(customValues)"
        if let comment, !comment.isEmpty {
            result += "    ; \(comment)"
        }
        let metaline = meta.formatted(context).lineAligned(by: context.indent)
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
    func print(date: Date, meta: MetaData, comment: String?, context: FormatContext) -> String {
        var resultLine = [
            date.isoDescription, "pad", account.description, sourceAccount.description,
        ]
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.formatted(context).lineAligned(by: context.indent)
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
    func print(date: Date, meta: MetaData, comment: String?, context: FormatContext) -> String {
        var resultLine = [date.isoDescription, "balance", account.description]

        // Format amount with optional tolerance
        if let tolerance {
            let num = amount.number.beancountCurrencyDescription(
                currency: amount.currency,
                context: context
            )
            let tol = tolerance.beancountRawDescription
            let curr = amount.currency.description
            resultLine.append("\(num) ~ \(tol) \(curr)")
        } else {
            resultLine.append(amount.formatted(context))
        }

        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        } else if let diffAmount {
            resultLine.append(" ; Diff: \(diffAmount.formatted(context))")
        }

        var result = resultLine.joined(separator: " ")
        let metaline = meta.formatted(context).lineAligned(by: context.indent)
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
    func print(date: Date, meta: MetaData, comment: String?, context: FormatContext) -> String {
        var resultLine = [date.isoDescription, "close", account.description]
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.formatted(context).lineAligned(by: context.indent)
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
    func print(date: Date, meta: MetaData, comment: String?, context: FormatContext) -> String {
        var resultLine = [date.isoDescription, "commodity", currency.description]
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.formatted(context).lineAligned(by: context.indent)
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
    func print(date: Date, meta: MetaData, comment: String?, context: FormatContext) -> String {
        var resultLine = [
            date.isoDescription,
            "note",
            account.description,
            note.quoted,
        ]
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.formatted(context).lineAligned(by: context.indent)
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
    func print(date: Date, meta: MetaData, comment: String?, context: FormatContext) -> String {
        var resultLine = [
            date.isoDescription,
            "event",
            type.quoted,
            description.quoted,
        ]
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.formatted(context).lineAligned(by: context.indent)
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
    func print(date: Date, meta: MetaData, comment: String?, context: FormatContext) -> String {
        var resultLine = [
            date.isoDescription,
            "query",
            name.quoted,
            queryString.quoted,
        ]
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.formatted(context).lineAligned(by: context.indent)
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
    func print(date: Date, meta: MetaData, comment: String?, context: FormatContext) -> String {
        var resultLine = [
            date.isoDescription,
            "price",
            currency.description,
            amount.rawFormatted(),
        ]
        if let comment, !comment.isEmpty {
            resultLine.append(" ; \(comment)")
        }
        var result = resultLine.joined(separator: " ")
        let metaline = meta.formatted(context).lineAligned(by: context.indent)
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
    func print(date: Date, meta: MetaData, comment: String?, context: FormatContext) -> String {
        var resultLine = [
            date.isoDescription,
            "document",
            account.description,
            filename.quoted,
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
        let metaline = meta.formatted(context).lineAligned(by: context.indent)
        if !metaline.isEmpty {
            result += "\n" + metaline
        }
        return result
    }
}
