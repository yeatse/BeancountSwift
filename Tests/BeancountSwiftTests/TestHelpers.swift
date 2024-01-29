//
//  TestHelpers.swift
//
//
//  Created by Yeatse on 2024/1/5.
//

@testable import BeancountSwift
import XCTest
import Foundation

struct ContentProvider: ContentProviding {
    let source: String

    func provideContent(for name: String) async throws -> String {
        return source
    }
    
    func parseLedger() async throws -> ParsedLedger<CostSpec> {
        let parser = Parser()
        return try await parser.parse(file: "test.bean", contentProvider: self)
    }
    
    func loadLedger() async throws -> ParsedLedger<Cost> {
        let loader = Loader()
        return try await loader.load(file: "test.bean", contentProvider: self)
    }
}

extension ContentProvider: ExpressibleByStringLiteral {
    init(stringLiteral value: StringLiteralType) {
        source = value
    }
}

extension Decimal: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self.init(string: value)!
    }
}

extension Date: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self = formatter.date(from: value)!
    }
}

extension CurrencyPair: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        let comps = value.split(separator: "/")
        self.init(base: .init(id: String(comps[0])),
                  quote: .init(id: String(comps[1])))
    }
}

extension DailyPrice: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: StringLiteralType...) {
        let date = Date(stringLiteral: elements[0])
        let rate = Decimal(stringLiteral: elements[1])
        self.init(date: date, rate: rate)
    }
}

extension Posting {
    func removingMeta() -> Self {
        return .init(account: account,
                     units: units,
                     cost: cost,
                     price: price,
                     flag: flag,
                     comment: comment)
    }
}

extension Transaction {
    func removingMeta() -> Self {
        return .init(flag: flag,
                     payee: payee,
                     narration: narration,
                     tags: tags,
                     links: links,
                     postings: postings.map({ $0.removingMeta() }))
    }
}

extension DirectiveContent {
    func removingMeta() -> Self {
        return switch self {
            case .transaction(let transaction): .transaction(transaction.removingMeta())
            default: self
        }
    }
}

extension Directive {
    func removingMeta() -> Self {
        return .init(meta: [:], date: date, comment: comment, content: content.removingMeta())
    }
}

func equalEntries<T>(_ lhs: [Directive<T>], _ rhs: [Directive<T>]) -> Bool {
    return lhs.map({ $0.removingMeta() }) == rhs.map({ $0.removingMeta() })
}

func equalEntries(_ lhs: [Directive<Cost>], _ rhs: String) async -> Bool {
    let r = try! await ContentProvider(source: rhs).loadLedger()
    return equalEntries(lhs, r.directives)
}

