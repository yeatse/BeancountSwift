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
    let parser = Parser()
    let loader = Loader()

    func provideContent(for name: String) throws -> String {
        return source
    }
    
    func parseLedger() throws -> ParsedLedger<CostSpec> {
        return try parser.parse(file: "test.bean", contentProvider: self)
    }
    
    func loadLedger() throws -> ParsedLedger<Cost> {
        return try loader.load(file: "test.bean", contentProvider: self)
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
    
    var transaction: Transaction<T> {
        if case .transaction(let txn) = content {
            return txn
        } else {
            fatalError()
        }
    }
}

func assertEqualEntries<T>(_ lhs: some RandomAccessCollection<Directive<T>>, _ rhs: [Directive<T>]) {
    XCTAssertEqual(lhs.map({ $0.removingMeta() }), rhs.map({ $0.removingMeta() }))
}

func assertEqualEntries(_ lhs: some RandomAccessCollection<Directive<Cost>>, _ rhs: String) {
    let r = try! ContentProvider(source: rhs).loadLedger()
    assertEqualEntries(lhs, r.directives)
}

