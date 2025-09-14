//
//  GrammarTests.swift
//  
//
//  Created by Yeatse on 2024/3/31.
//

import Testing
@testable import BeancountSwift

struct GrammarTests {
    @Test func costMerge() throws {
        let p: ContentProvider =
                """
                  2014-01-01 *
                    Assets:Invest:AAPL   20 AAPL {*}
                    Assets:Invest:Cash  -20 AAPL
                """
        let ledger = try p.parseLedger()
        #expect(ledger.directives[0].transaction.isIncomplete)
        let posting = ledger.directives[0].transaction.postings[0]
        #expect(posting.units == "20 AAPL")
        #expect(posting.cost == CostSpec(merge: true))
    }
    
    @Test func openAccount() throws {
        let p: ContentProvider =
                """
                  2014-01-01 open Assets:Invest ; Investing
                """
        let ledger = try p.parseLedger()
        let directive = ledger.directives[0]
        #expect(directive.comment == "Investing")
        guard case .open(let open) = directive.content else {
            Issue.record("Expected open directive")
            return
        }
        #expect(open.account == "Assets:Invest")
    }
}
