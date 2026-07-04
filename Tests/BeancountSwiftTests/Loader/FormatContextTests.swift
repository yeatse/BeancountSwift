//
//  FormatContextTests.swift
//  BeancountSwift
//
//  Verifies that `Directive.formatted(_:)` honours the configured indentation
//  while `description` keeps its default four-space output.
//

import Foundation
import Testing

@testable import BeancountSwift

@Suite("Format Context Tests")
struct FormatContextTests {

    private func transaction() throws -> Directive<CostSpec> {
        let source = """
            2024-01-15 * "Store" "Groceries"
                foo: "bar"
                Expenses:Food    10.00 USD
                Assets:Cash     -10.00 USD
            """
        let ledger = try ContentProvider(source: source).parseLedger()
        #expect(ledger.errors.isEmpty)
        let directive = try #require(ledger.directives.first)
        return directive
    }

    @Test("description keeps the default four-space indent")
    func defaultIndent() throws {
        let output = try transaction().description
        #expect(output.contains("\n    foo: \"bar\""))
        #expect(output.contains("\n    Expenses:Food"))
    }

    @Test("formatted honours a two-space context")
    func twoSpaceIndent() throws {
        let output = try transaction().formatted(FormatContext(indentWidth: 2))
        #expect(output.contains("\n  foo: \"bar\""))
        #expect(output.contains("\n  Expenses:Food"))
        #expect(!output.contains("\n    Expenses:Food"))
    }

    @Test("output remains round-trippable at a custom indent")
    func roundTrip() throws {
        let output = try transaction().formatted(FormatContext(indentWidth: 3))
        let reparsed = try ContentProvider(source: output).parseLedger()
        #expect(reparsed.errors.isEmpty)
        #expect(reparsed.directives.count == 1)
    }
}
