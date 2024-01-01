//
//  Loader.swift
//
//
//  Created by Yeatse on 2023/12/21.
//
import Foundation
import SwiftTreeSitter
import TreeSitterBeancount

public protocol ContentProviding {
    func provideContent(for file: String) async throws -> String
}

enum ParserError: Error {
    case badContent(file: String, content: String)
    case invalidSyntax(file: String, lineno: UInt32, content: String?)
    case duplicatedInclude(String)
    case popAbsentTag(file: String, lineno: UInt32, tag: Tag)
    case unbalancedTags(file: String, tags: [Tag])
}

public struct ParsedLedger<T: PostingCost> {
    var options: [Option]
    var plugins: [Plugin]
    var directives: [Directive<T>]
    var errors: [Error]
}

extension DirectiveContent {
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

public struct Loader {
    let treeSitter: SwiftTreeSitter.Parser = {
        let parser = SwiftTreeSitter.Parser()
        let language = Language(language: tree_sitter_beancount())
        try! parser.setLanguage(language)
        return parser
    }()

    func parse(file: String, contentProvider: ContentProviding) async throws -> ParsedLedger<
        CostSpec
    > {
        let content = try await contentProvider.provideContent(for: file)
        var (ledger, includes) = try parse(content: content, in: file)

        var seenIncludes: Set<String> = [file]
        while !includes.isEmpty {
            let childFile = includes.popLast()!
            do {
                let childContent = try await contentProvider.provideContent(for: childFile)
                let (childLedger, childIncludes) = try parse(content: childContent, in: file)
                ledger.directives += childLedger.directives
                ledger.errors += childLedger.errors
                for include in childIncludes {
                    if seenIncludes.contains(include) {
                        throw ParserError.duplicatedInclude(include)
                    } else {
                        seenIncludes.insert(include)
                        includes.append(include)
                    }
                }
            } catch {
                ledger.errors.append(error)
            }
        }
        ledger.directives.sort()
        return ledger
    }

    private func parse(content: String, in file: String) throws -> (
        ParsedLedger<CostSpec>, includes: [String]
    ) {
        guard let tree = treeSitter.parse(content) else {
            throw ParserError.badContent(file: file, content: content)
        }

        var options: [Option] = []
        var plugins: [Plugin] = []
        var directives: [Directive<CostSpec>] = []
        var errors: [Error] = []
        var includes: [String] = []

        var tags: [Tag] = []
        tree.rootNode?.enumerateChildren { child in
            do {
                switch child.nodeType {
                case "pushtag":
                    let tag = try child.namedChild(at: 0).map {
                        try Tag(from: $0, content: content)
                    }
                    guard let tag else { throw SyntaxError.badNode(child) }
                    tags.append(tag)
                case "poptag":
                    let tag = try child.namedChild(at: 0).map {
                        try Tag(from: $0, content: content)
                    }
                    guard let tag else { throw SyntaxError.badNode(child) }
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
                    guard let include else { throw SyntaxError.badNode(child) }
                    includes.append(include)
                case "plugin":
                    let plugin = try Plugin(from: child, content: content)
                    plugins.append(plugin)
                case "transaction", "balance", "open", "close", "pad", "document", "note", "event",
                    "price",
                    "commodity", "query", "custom":
                    var directive = try Directive<CostSpec>(from: child, content: content)
                    if !tags.isEmpty {
                        directive = directive.mergingTags(tags)
                    }
                    directives.append(directive.mergingMetaData(["filename": .string(file)]))
                default:
                    break
                }
            } catch SyntaxError.badNode(let node) {
                let err = ParserError.invalidSyntax(
                    file: file,
                    lineno: node.pointRange.lowerBound.row,
                    content: try? String(from: node, content: content)
                )
                errors.append(err)
            } catch {
                errors.append(error)
            }
        }
        if !tags.isEmpty {
            errors.append(ParserError.unbalancedTags(file: file, tags: tags))
        }
        return (
            ParsedLedger(
                options: options,
                plugins: plugins,
                directives: directives,
                errors: errors
            ),
            includes
        )
    }

    func book(ledger: ParsedLedger<CostSpec>) -> ParsedLedger<Cost> {
        return booker.book(ledger: ledger)
    }

    func transform(ledger: ParsedLedger<Cost>) -> ParsedLedger<Cost> {
        var result = ledger
        for plugin in ledger.plugins {
            let (entries, errors) = plugin.process(
                entries: result.directives,
                options: result.options
            )
            result.directives = entries
            result.errors += errors
        }
        result.directives.sort()
        return result
    }

    func validate(ledger: ParsedLedger<Cost>) -> ParsedLedger<Cost> {
        // TODO: validate
        return ledger
    }

    func load(file: String, contentProvider: ContentProviding) async throws -> ParsedLedger<Cost> {
        // parsing
        let parsedResult = try await parse(file: file, contentProvider: contentProvider)

        // booking
        let bookedLedger = book(ledger: parsedResult)

        // transforming
        let transformedLedger = transform(ledger: bookedLedger)

        // validation
        return validate(ledger: transformedLedger)
    }
}
