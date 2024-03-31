//
//  GrammarTests.swift
//  
//
//  Created by Yeatse on 2024/3/31.
//

import XCTest
@testable import BeancountSwift

final class GrammarTests: XCTestCase {
    func testCostMerge() throws {
        let p: ContentProvider =
                """
                  2014-01-01 *
                    Assets:Invest:AAPL   20 AAPL {*}
                    Assets:Invest:Cash  -20 AAPL
                """
        let ledger = try p.parseLedger()
        XCTAssertTrue(ledger.directives[0].transaction.isIncomplete)
        let posting = ledger.directives[0].transaction.postings[0]
        XCTAssertEqual(posting.units, "20 AAPL")
        XCTAssertEqual(posting.cost, CostSpec(merge: true))
    }
}
