//
//  Parser.swift
//
//
//  Created by Yeatse on 2024/1/5.
//

import Foundation
import SwiftTreeSitter
import TreeSitterBeancount

/// Errors that can occur during Beancount parsing.
///
/// ParserError represents various parsing failures that can occur when
/// processing Beancount files, providing detailed context for debugging.
enum ParserError: LocatableError, LocalizedError {
    /// The file content could not be parsed as valid syntax.
    case badContent(file: String, content: String)
    /// Invalid syntax encountered at a specific location.
    case invalidSyntax(file: String, lineno: UInt32, content: String?)
    /// An include file was referenced multiple times.
    case duplicatedInclude(String)
    /// Attempted to pop a tag that wasn't pushed.
    case popAbsentTag(file: String, lineno: UInt32, tag: Tag)
    /// Tags were pushed but not popped at end of file.
    case unbalancedTags(file: String, tags: [Tag])

    var location: LedgerLocation? {
        switch self {
        case .invalidSyntax(let file, let lineno, _):
            return LedgerLocation(filename: file, lineno: lineno)
        case .popAbsentTag(let file, let lineno, _):
            return LedgerLocation(filename: file, lineno: lineno)
        default:
            return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .badContent(let file, _):
            return "Failed to parse file \(file)"
        case .invalidSyntax(_, let lineno, let content):
            if let content {
                let preview = String(content.prefix(30))
                return "Invalid syntax at line \(lineno): \(preview)"
            }
            return "Invalid syntax at line \(lineno)"
        case .duplicatedInclude(let include):
            return "Duplicate include: \(include)"
        case .popAbsentTag(_, let lineno, let tag):
            return "Popped tag '\(tag.id)' at line \(lineno) without matching push"
        case .unbalancedTags(_, let tags):
            let tagList = tags.map(\.id).joined(separator: ", ")
            if tagList.isEmpty {
                return "Unbalanced tags at end of file"
            }
            return "Unbalanced tags at end of file: \(tagList)"
        }
    }
}

extension DirectiveContent {
    /// Determines the sort order for directives on the same date.
    ///
    /// Provides stable ordering for directives that occur on the same date,
    /// ensuring opens come before transactions, which come before closes, etc.
    ///
    /// - Returns: Sort priority integer (lower values sort first)
    var sortOrder: Int {
        switch self {
        case .open(_): -2
        case .balance(_): -1
        case .document(_): 1
        case .close(_): 2
        default: 0
        }
    }
}

extension Directive: Comparable {
    public static func < (lhs: Directive, rhs: Directive) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }
        if lhs.content.sortOrder != rhs.content.sortOrder {
            return lhs.content.sortOrder < rhs.content.sortOrder
        }
        if let l1 = lhs.meta.lineno, let l2 = rhs.meta.lineno {
            return l1 < l2
        }
        return false
    }
}

extension Posting<CostSpec> {
    /// Indicates whether this posting has missing or invalid information.
    ///
    /// Checks for missing amounts, invalid numbers, or incomplete cost specifications
    /// that would prevent the posting from being processed correctly.
    ///
    /// - Returns: True if the posting is incomplete or invalid
    var isIncomplete: Bool {
        if units == .missing || units.number == .nan || units.currency == .missing {
            return true
        }
        if price == .missing {
            return true
        }
        if let price, price.number == .nan || price.currency == .missing {
            return true
        }
        if let cost,
            (cost.numberTotal == nil && cost.numberPerUnit == nil) || cost.currency == .missing
        {
            return true
        }
        return false
    }
}

extension Transaction<CostSpec> {
    /// Indicates whether this transaction has any incomplete postings.
    ///
    /// A transaction is considered incomplete if any of its postings are incomplete.
    ///
    /// - Returns: True if any posting in the transaction is incomplete
    var isIncomplete: Bool {
        postings.contains(where: \.isIncomplete)
    }
}

extension Directive<CostSpec> {
    /// Indicates whether this directive is incomplete.
    ///
    /// Only transaction directives can be incomplete (due to incomplete postings).
    /// All other directive types are considered complete by definition.
    ///
    /// - Returns: True if this is an incomplete transaction directive
    var isIncomplete: Bool {
        if case .transaction(let txn) = content {
            return txn.isIncomplete
        } else {
            return false
        }
    }
}

/// Namespace for Beancount parsing functionality using Tree-sitter.
///
/// Parser provides static methods for processing Beancount text files and converting
/// them into structured Swift data types. It handles include files, tag management,
/// options processing, and comprehensive error reporting.
///
/// This corresponds to the parsing functionality in the original Beancount Python
/// library, providing the same level of syntax support and error handling.
///
/// ## Usage
/// ```swift
/// let ledger = try Parser.parse(file: "accounts.beancount", contentProvider: provider)
/// ```
public enum Parser {
    /// Creates and configures a Tree-sitter parser for Beancount syntax.
    ///
    /// Initializes the Tree-sitter parser with the Beancount grammar for
    /// accurate syntax parsing of Beancount files.
    ///
    /// - Returns: A configured Tree-sitter parser instance
    private static func makeTreeSitter() -> SwiftTreeSitter.Parser {
        let parser = SwiftTreeSitter.Parser()
        let language = Language(language: tree_sitter_beancount())
        try! parser.setLanguage(language)
        return parser
    }

    /// Parses a Beancount file and all its includes into a complete ledger.
    ///
    /// Processes the main file and recursively handles all include directives,
    /// building a complete ledger with all directives, options, plugins, and errors.
    /// Maintains proper ordering and prevents circular includes.
    ///
    /// - Parameters:
    ///   - file: The main Beancount file to parse
    ///   - contentProvider: Provider for file content access
    /// - Returns: A complete parsed ledger with cost specifications
    /// - Throws: Parser errors for syntax issues, missing files, or circular includes
    public static func parse(file: String, contentProvider: ContentProviding) throws
        -> ParsedLedger<
            CostSpec
        >
    {
        let content = try contentProvider.provideContent(for: file)
        var (ledger, includes) = try parseContent(content: content, in: file)

        var seenIncludes: Set<String> = [file]
        while !includes.isEmpty {
            let include = includes.popLast()!
            let expandedFiles = contentProvider.expandInclude(include)
            for expandedFile in expandedFiles {
                if seenIncludes.contains(expandedFile) {
                    ledger.errors.append(ParserError.duplicatedInclude(expandedFile))
                    continue
                }
                seenIncludes.insert(expandedFile)
                do {
                    let childContent = try contentProvider.provideContent(for: expandedFile)
                    let (childLedger, childIncludes) = try parseContent(
                        content: childContent,
                        in: expandedFile
                    )
                    ledger.directives += childLedger.directives
                    ledger.errors += childLedger.errors
                    includes.append(contentsOf: childIncludes)
                } catch {
                    ledger.errors.append(error)
                }
            }
        }
        ledger.directives.sort()
        return ledger
    }

    /// Parses a single directive from a text snippet.
    ///
    /// Attempts to parse a single Beancount directive from the provided text.
    /// Useful for interactive parsing, validation, or processing individual directives.
    ///
    /// - Parameter content: The text content containing a single directive
    /// - Returns: The parsed directive, or nil if parsing fails
    public static func parseSnippet(from content: String) -> Directive<CostSpec>? {
        let treeSitter = makeTreeSitter()
        guard let tree = treeSitter.parse(content) else { return nil }
        let directives: Set<String> = [
            "transaction", "balance", "open", "close", "pad", "document", "note", "event", "price",
            "commodity", "query", "custom",
        ]
        if let node = tree.rootNode?.namedChild(at: 0), let nodeType = node.nodeType,
            directives.contains(nodeType)
        {
            return try? Directive(from: node, content: content)
        }
        return nil
    }

    /// Parses multiple directives from a text snippet.
    ///
    /// Processes text content containing multiple Beancount directives and returns
    /// all successfully parsed directives. Invalid or unparseable directives are
    /// silently skipped, making this method suitable for batch processing of
    /// potentially malformed input.
    ///
    /// This method is useful for:
    /// - Processing clipboard content with multiple directives
    /// - Batch importing partially formatted data
    /// - Interactive editing where some directives may be incomplete
    /// - Testing and validation of directive collections
    ///
    /// ## Example
    /// ```swift
    /// let content = """
    /// 2024-01-01 open Assets:Checking USD
    /// 2024-01-02 * "Grocery shopping"
    ///   Assets:Checking  -50.00 USD
    ///   Expenses:Food     50.00 USD
    /// 2024-01-03 balance Assets:Checking  1000.00 USD
    /// """
    ///
    /// let parser = Parser()
    /// let directives = parser.parseSnippets(from: content)
    /// // Returns array with 3 successfully parsed directives
    /// ```
    ///
    /// - Parameter content: The text content containing zero or more Beancount directives
    /// - Returns: An array of successfully parsed directives in document order
    ///
    /// - Note: Unlike `parseSnippet(from:)` which expects exactly one directive,
    ///   this method handles multiple directives and gracefully ignores parsing failures.
    /// - Warning: Parsing errors are silently ignored. Use the main `parse(file:contentProvider:)`
    ///   method if you need comprehensive error reporting.
    public static func parseSnippets(from content: String) -> [Directive<CostSpec>] {
        var result: [Directive<CostSpec>] = []
        let treeSitter = makeTreeSitter()
        guard let rootNode = treeSitter.parse(content)?.rootNode else { return result }
        let directives: Set<String> = [
            "transaction", "balance", "open", "close", "pad", "document", "note", "event", "price",
            "commodity", "query", "custom",
        ]
        for i in 0..<rootNode.namedChildCount {
            if let child = rootNode.namedChild(at: i),
                let nodeType = child.nodeType,
                directives.contains(nodeType),
                let directive = try? Directive(from: child, content: content)
            {
                result.append(directive)
            }
        }
        return result
    }

    /// Parses the content of a single file.
    ///
    /// Processes the syntax tree to extract directives, options, plugins, and includes.
    /// Handles tag stack management and provides comprehensive error reporting.
    ///
    /// - Parameters:
    ///   - content: The file content to parse
    ///   - file: The filename for error reporting
    /// - Returns: A tuple of the parsed ledger and list of include files
    /// - Throws: Parser errors for syntax issues or tag management problems
    private static func parseContent(content: String, in file: String) throws -> (
        ParsedLedger<CostSpec>, includes: [String]
    ) {
        let treeSitter = makeTreeSitter()
        guard let tree = treeSitter.parse(content) else {
            throw ParserError.badContent(file: file, content: content)
        }

        var options: [Option] = []
        var plugins: [Plugin] = []
        var directives: [Directive<CostSpec>] = []
        var errors: [Error] = []
        var includes: [String] = []

        var tags: [Tag] = []
        func process(child: Node) {
            do {
                switch child.nodeType {
                case "pushtag":
                    let tag = try child.namedChild(at: 0).map {
                        try Tag(from: $0, content: content)
                    }
                    guard let tag else { throw SyntaxError.badNode(child, content: content) }
                    tags.append(tag)
                case "poptag":
                    let tag = try child.namedChild(at: 0).map {
                        try Tag(from: $0, content: content)
                    }
                    guard let tag else { throw SyntaxError.badNode(child, content: content) }
                    if let idx = tags.firstIndex(of: tag) {
                        tags.remove(at: idx)
                    } else {
                        throw ParserError.popAbsentTag(
                            file: file,
                            lineno: child.pointRange.lowerBound.row,
                            tag: tag
                        )
                    }
                case "pushmeta":
                    break
                case "popmeta":
                    break
                case "option":
                    let option = try Option(from: child, content: content)
                    options.append(option)
                case "include":
                    let include = try child.namedChild(at: 0).map {
                        try String(from: $0, content: content)
                    }
                    guard let include else { throw SyntaxError.badNode(child, content: content) }
                    let includePath = resolveInclude(include.unescaped(), relativeTo: file)
                    includes.append(includePath)
                case "plugin":
                    let plugin = try Plugin(from: child, content: content)
                    plugins.append(plugin)
                case "transaction", "balance", "open", "close", "pad", "document", "note", "event",
                    "price", "commodity", "query", "custom":
                    var directive = try Directive<CostSpec>(from: child, content: content)
                    if !tags.isEmpty {
                        directive = directive.mergingTags(tags)
                    }
                    directives.append(directive.mergingMetaData(["filename": .string(file)]))
                case "ERROR":
                    throw SyntaxError.badNode(child, content: content)
                case "section":
                    processChildren(of: child)
                default:
                    break
                }
            } catch SyntaxError.badNode(let lineno, let source) {
                let err = ParserError.invalidSyntax(file: file, lineno: lineno, content: source)
                errors.append(err)
            } catch {
                errors.append(error)
            }
        }
        func processChildren(of node: Node) {
            for i in 0..<node.namedChildCount {
                guard let child = node.namedChild(at: i) else { continue }
                process(child: child)
            }
        }
        tree.rootNode.map(processChildren(of:))
        if !tags.isEmpty {
            errors.append(ParserError.unbalancedTags(file: file, tags: tags))
        }
        return (
            ParsedLedger(
                options: Options(from: options),
                plugins: plugins,
                directives: directives,
                errors: errors
            ),
            includes
        )
    }

    private static func resolveInclude(_ include: String, relativeTo file: String) -> String {
        let includePath = include as NSString
        
        if includePath.isAbsolutePath {
            return includePath.standardizingPath
        }

        let baseDir = (file as NSString).deletingLastPathComponent
        let joined = (baseDir as NSString).appendingPathComponent(include)
        return (joined as NSString).standardizingPath
    }
}
