//
//  File.swift
//
//
//  Created by Yeatse on 2024/1/5.
//

import Testing

@testable import BeancountSwift

struct ParserTests {
    @Test func isEntryInComplete() throws {
        let p: ContentProvider =
            """
            2014-01-27 * "UNION MARKET"
              Liabilities:US:Amex:BlueCash    -22.02 USD
              Expenses:Food:Grocery            22.02 USD

            2014-01-27 * "UNION MARKET"
              Liabilities:US:Amex:BlueCash    -22.02 USD
              Expenses:Food:Grocery
            """
        let ledger = try p.parseLedger()
        #expect(!ledger.directives[0].isIncomplete)
        #expect(ledger.directives[1].isIncomplete)
    }

    @Test func parseErrors() throws {
        let p: ContentProvider =
            """
            2013-05-40 * "Nice dinner at Mermaid Inn"
              Expenses:Restaurant         100 USD
              Assets:US:Cash
            """
        let ledger = try p.parseLedger()
        #expect(!ledger.errors.isEmpty)
    }

    @Test func parseNoErrors() throws {
        let p: ContentProvider =
            """
            2013-05-01 * "Valid date for parser"
              Expenses:Restaurant         100 USD
              Assets:US:Cash             -100 USD
            """
        let ledger = try p.parseLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func parseEmptyString() throws {
        let p: ContentProvider = ""
        let ledger = try p.parseLedger()
        #expect(ledger.directives.count == 0)
        #expect(ledger.errors.count == 0)
    }

    @Test func unicode() throws {
        let p: ContentProvider =
            """
            2015-05-23 note Assets:Something "a¡¢£¤¥¦§¨©ª«¬®¯°±²³´µ¶·¸¹º»¼ z"
            """
        let ledger = try p.parseLedger()
        #expect(ledger.directives.count == 1)
        #expect(ledger.errors.count == 0)
    }

    @Test func parseMany() throws {
        let p: ContentProvider =
            """
            2014-12-15 * "Payee" "Narration"
              Assets:Checking   101.23 USD
              Equity:Blah
            """
        let ledger = try p.parseLedger()
        guard case .transaction(let txn) = ledger.directives[0].content else {
            Issue.record("Expected transaction directive")
            return
        }
        #expect(ledger.directives.count == 1)
        #expect(txn.postings[0].units.number == 101.23)
    }

    @Test func lineno() throws {
        let p: ContentProvider = "2020-07-30 open Assets:Test"
        let ledger = try p.parseLedger()
        #expect(ledger.directives[0].meta.lineno == 0)
    }

    @Test func multiLineno() throws {
        let p: ContentProvider =
            """
              2013-01-01 open Assets:US:Cash

              2013-05-18 * "Nice dinner at Mermaid Inn"
                Expenses:Restaurant         100 USD
                Assets:US:Cash             -100 USD

              2013-05-19 balance  Assets:US:Cash   -100 USD

              2013-05-20 note  Assets:US:Cash   "Something"
            """
        let ledger = try p.parseLedger()
        #expect(ledger.directives.count == 4)
        #expect(ledger.directives[0].meta.lineno == 0)
        #expect(ledger.directives[1].meta.lineno == 2)
        #expect(ledger.directives[2].meta.lineno == 6)
        #expect(ledger.directives[3].meta.lineno == 8)

        guard case .transaction(let txn) = ledger.directives[1].content else {
            Issue.record("Expected transaction directive")
            return
        }
        #expect(txn.postings[0].meta?.lineno == 3)
        #expect(txn.postings[1].meta?.lineno == 4)
    }

    @Test func filename() throws {
        let p: ContentProvider =
            """
              2013-01-01 open Assets:US:Cash

              2013-05-18 * "Nice dinner at Mermaid Inn"
                Expenses:Restaurant         100 USD
                Assets:US:Cash             -100 USD

              2013-05-19 balance  Assets:US:Cash   -100 USD

              2013-05-20 note  Assets:US:Cash   "Something"
            """
        let ledger = try Parser().parse(file: "main", contentProvider: p)
        #expect(ledger.directives.count == 4)
        #expect(ledger.directives[0].meta.filename == "main")
        #expect(ledger.directives[1].meta.filename == "main")
        #expect(ledger.directives[2].meta.filename == "main")
        #expect(ledger.directives[3].meta.filename == "main")

        guard case .transaction(let txn) = ledger.directives[1].content else {
            Issue.record("Expected transaction directive")
            return
        }
        #expect(txn.postings[0].meta?.filename == "main")
        #expect(txn.postings[1].meta?.filename == "main")
    }
    
    @Test func identifiers() throws {
        let p: ContentProvider =
            """
            ; first directive
            2013-05-01 * "Valid date for parser"
              Expenses:Restaurant         100 USD
              Assets:US:Cash             -100 USD
            
            2014-12-15 * "Payee" "Narration"
              phone: 1234-5678
              Assets:Checking   101.23 USD
              Equity:Blah
            """
        let ledger = try Loader().load(file: "test.bean", contentProvider: p)
        #expect(ledger.directives[0].id == "test.bean-1")
        #expect(ledger.directives[0].transaction.postings[0].id == "test.bean-2")
        #expect(ledger.directives[0].transaction.postings[1].id == "test.bean-3")
        
        #expect(ledger.directives[1].id == "test.bean-5")
        #expect(ledger.directives[1].transaction.postings[0].id == "test.bean-7")
        #expect(ledger.directives[1].transaction.postings[1].id == "test.bean-8")
    }
}
