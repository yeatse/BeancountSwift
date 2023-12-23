//
//  Parser.swift
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
    case badNode(SwiftTreeSitter.Node)
    case popAbsentTag(SwiftTreeSitter.Node)
    case unbalancedTags([String])
}

public struct ParsedLedger {
    let options: [Option]
    let plugins: [Plugin]
    let directives: [Directive]
    let errors: [String: [Error]]
}

extension Dictionary where Key == String, Value == Array<Error> {
    mutating func addError(_ error: Error, in file: String) {
        var errors = self[file] ?? []
        errors.append(error)
        self[file] = errors
    }
}

extension Directive: Comparable {
    public static func < (lhs: Directive, rhs: Directive) -> Bool {
        if lhs.date == rhs.date, let ll = lhs.meta.lineno, let rl = rhs.meta.lineno {
            return ll < rl
        } else {
            return lhs.date < rhs.date
        }
    }
    
    public static func == (lhs: Directive, rhs: Directive) -> Bool {
        return lhs.date == rhs.date && lhs.meta.lineno == rhs.meta.lineno
    }
}

public struct Parser {
    let treeSitter: SwiftTreeSitter.Parser = {
        let parser = SwiftTreeSitter.Parser()
        let language = Language(language: tree_sitter_beancount())
        try! parser.setLanguage(language)
        return parser
    }()
    
    public func parse(file: String, contentProvider: ContentProviding) async throws -> ParsedLedger {
        let content = try await contentProvider.provideContent(for: file)
        guard let tree = treeSitter.parse(content) else {
            throw ParserError.badContent(file: file, content: content)
        }
        var options: [Option] = []
        var plugins: [Plugin] = []
        var directives: [Directive] = []
        var errors: [String: [Error]] = [:]
        var includes: [String] = []
        
        var tags: [String] = []
        tree.rootNode?.enumerateChildren { child in
            do {
                switch child.nodeType {
                    case "pushtag":
                        let tag = try child.namedChild(at: 0).map { try String(from: $0, content: content) }
                        guard let tag else { throw ParserError.badNode(child) }
                        tags.append(tag)
                    case "poptag":
                        let tag = try child.namedChild(at: 0).map { try String(from: $0, content: content) }
                        guard let tag else { throw ParserError.badNode(child) }
                        if let idx = tags.firstIndex(of: tag) {
                            tags.remove(at: idx)
                        } else {
                            throw ParserError.popAbsentTag(child)
                        }
                    case "pushmeta":
                        break
                    case "popmeta":
                        break
                    case "option":
                        let option = try Option(from: child, content: content)
                        options.append(option)
                    case "include":
                        let include = try child.namedChild(at: 0).map { try String(from: $0, content: content) }
                        guard let include else { throw ParserError.badNode(child) }
                        includes.append(include)
                    case "plugin":
                        let plugin = try Plugin(from: child, content: content)
                        plugins.append(plugin)
                    case "transaction", "balance", "open", "close", "pad", "document", "note", "event", "price", "commodity", "query", "custom":
                        var directive = try Directive(from: child, content: content)
                        if !tags.isEmpty {
                            directive = directive.mergingTags(tags)
                        }
                        directives.append(directive.mergingMetaData(["filename": file]))
                    default:
                        break
                }
            } catch {
                errors.addError(error, in: file)
            }
        }
        
        for include in includes {
            do {
                let ledger = try await parse(file: include, contentProvider: contentProvider)
                // options are ignored in the included files
                plugins.append(contentsOf: ledger.plugins)
                directives.append(contentsOf: ledger.directives)
                errors.merge(ledger.errors) { old, new in old + new }
            } catch {
                errors.addError(error, in: file)
            }
        }
        
        return ParsedLedger(options: options,
                            plugins: plugins,
                            directives: directives.sorted(),
                            errors: errors)
    }
}

