//
//  File.swift
//
//
//  Created by Yeatse on 2024/1/5.
//

import XCTest

@testable import BeancountSwift

final class ParserTests: XCTestCase {
    func testIsEntryInComplete() async throws {
        let p: ContentProvider =
            """
            2014-01-27 * "UNION MARKET"
              Liabilities:US:Amex:BlueCash    -22.02 USD
              Expenses:Food:Grocery            22.02 USD

            2014-01-27 * "UNION MARKET"
              Liabilities:US:Amex:BlueCash    -22.02 USD
              Expenses:Food:Grocery
            """
        let ledger = try await parser.parse(file: "main", contentProvider: p)
        XCTAssertFalse(ledger.directives[0].isIncomplete)
        XCTAssertTrue(ledger.directives[1].isIncomplete)
    }

    func testParseErrors() async throws {
        let p: ContentProvider =
            """
            2013-05-40 * "Nice dinner at Mermaid Inn"
              Expenses:Restaurant         100 USD
              Assets:US:Cash
            """
        let ledger = try await parser.parse(file: "main", contentProvider: p)
        XCTAssert(!ledger.errors.isEmpty)
    }

    func testParseNoErrors() async throws {
        let p: ContentProvider =
            """
            2013-05-01 * "Valid date for parser"
              Expenses:Restaurant         100 USD
              Assets:US:Cash             -100 USD
            """
        let ledger = try await parser.parse(file: "main", contentProvider: p)
        XCTAssert(ledger.errors.isEmpty)
    }

    func testParseEmptyString() async throws {
        let p: ContentProvider = ""
        let ledger = try await parser.parse(file: "main", contentProvider: p)
        XCTAssertEqual(ledger.directives.count, 0)
        XCTAssertEqual(ledger.errors.count, 0)
    }

    func testUnicode() async throws {
        let p: ContentProvider =
            """
            2015-05-23 note Assets:Something "a¡¢£¤¥¦§¨©ª«¬®¯°±²³´µ¶·¸¹º»¼ z"
            """
        let ledger = try await parser.parse(file: "main", contentProvider: p)
        XCTAssertEqual(ledger.directives.count, 1)
        XCTAssertEqual(ledger.errors.count, 0)
    }

    func testParseMany() async throws {
        let p: ContentProvider =
            """
            2014-12-15 * "Payee" "Narration"
              Assets:Checking   101.23 USD
              Equity:Blah
            """
        let ledger = try await parser.parse(file: "main", contentProvider: p)
        guard case .transaction(let txn) = ledger.directives[0].content else {
            return XCTFail()
        }
        XCTAssertEqual(ledger.directives.count, 1)
        XCTAssertEqual(txn.postings[0].units.number, 101.23)
    }

    func testLineno() async throws {
        let p: ContentProvider = "2020-07-30 open Assets:Test"
        let ledger = try await parser.parse(file: "main", contentProvider: p)
        XCTAssertEqual(ledger.directives[0].meta["lineno"], .number(0))
    }

    func testMultiLineno() async throws {
        let p: ContentProvider =
            """
              2013-01-01 open Assets:US:Cash

              2013-05-18 * "Nice dinner at Mermaid Inn"
                Expenses:Restaurant         100 USD
                Assets:US:Cash             -100 USD

              2013-05-19 balance  Assets:US:Cash   -100 USD

              2013-05-20 note  Assets:US:Cash   "Something"
            """
        let ledger = try await parser.parse(file: "main", contentProvider: p)
        XCTAssertEqual(ledger.directives.count, 4)
        XCTAssertEqual(ledger.directives[0].meta.lineno, 0)
        XCTAssertEqual(ledger.directives[1].meta.lineno, 2)
        XCTAssertEqual(ledger.directives[2].meta.lineno, 6)
        XCTAssertEqual(ledger.directives[3].meta.lineno, 8)

        guard case .transaction(let txn) = ledger.directives[1].content else {
            return XCTFail()
        }
        XCTAssertEqual(txn.postings[0].meta?.lineno, 3)
        XCTAssertEqual(txn.postings[1].meta?.lineno, 4)
    }

    func testFilename() async throws {
        let p: ContentProvider =
            """
              2013-01-01 open Assets:US:Cash

              2013-05-18 * "Nice dinner at Mermaid Inn"
                Expenses:Restaurant         100 USD
                Assets:US:Cash             -100 USD

              2013-05-19 balance  Assets:US:Cash   -100 USD

              2013-05-20 note  Assets:US:Cash   "Something"
            """
        let ledger = try await parser.parse(file: "main", contentProvider: p)
        XCTAssertEqual(ledger.directives.count, 4)
        XCTAssertEqual(ledger.directives[0].meta.filename, "main")
        XCTAssertEqual(ledger.directives[1].meta.filename, "main")
        XCTAssertEqual(ledger.directives[2].meta.filename, "main")
        XCTAssertEqual(ledger.directives[3].meta.filename, "main")

        guard case .transaction(let txn) = ledger.directives[1].content else {
            return XCTFail()
        }
        XCTAssertEqual(txn.postings[0].meta?.filename, "main")
        XCTAssertEqual(txn.postings[1].meta?.filename, "main")
    }
}
