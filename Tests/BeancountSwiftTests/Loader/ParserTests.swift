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
    
    @Test func parseSnippetTransaction() throws {
        let parser = Parser()
        let content = """
            2014-12-15 * "Payee" "Narration"
              Assets:Checking   101.23 USD
              Equity:Blah      -101.23 USD
            """
        let directive = parser.parseSnippet(from: content)
        #expect(directive != nil)
        guard case .transaction(let txn) = directive?.content else {
            Issue.record("Expected transaction directive")
            return
        }
        #expect(txn.payee == "Payee")
        #expect(txn.narration == "Narration")
        #expect(txn.postings.count == 2)
        #expect(txn.postings[0].units.number == 101.23)
    }

    @Test func parseSnippetOpen() throws {
        let parser = Parser()
        let directive = parser.parseSnippet(from: "2020-07-30 open Assets:Test USD")
        #expect(directive != nil)
        guard case .open(let open) = directive?.content else {
            Issue.record("Expected open directive")
            return
        }
        #expect(open.account == "Assets:Test")
        #expect(open.currencies == ["USD"])
    }

    @Test func parseSnippetClose() throws {
        let parser = Parser()
        let directive = parser.parseSnippet(from: "2020-12-31 close Assets:Test")
        #expect(directive != nil)
        guard case .close(let close) = directive?.content else {
            Issue.record("Expected close directive")
            return
        }
        #expect(close.account == "Assets:Test")
    }

    @Test func parseSnippetBalance() throws {
        let parser = Parser()
        let directive = parser.parseSnippet(from: "2020-07-30 balance Assets:Test 1000.00 USD")
        #expect(directive != nil)
        guard case .balance(let balance) = directive?.content else {
            Issue.record("Expected balance directive")
            return
        }
        #expect(balance.account == "Assets:Test")
        #expect(balance.amount.number == 1000.00)
        #expect(balance.amount.currency == "USD")
    }

    @Test func parseSnippetNote() throws {
        let parser = Parser()
        let directive = parser.parseSnippet(from: "2020-07-30 note Assets:Test \"This is a note\"")
        #expect(directive != nil)
        guard case .note(let note) = directive?.content else {
            Issue.record("Expected note directive")
            return
        }
        #expect(note.account == "Assets:Test")
        #expect(note.note == "This is a note")
    }

    @Test func parseSnippetPrice() throws {
        let parser = Parser()
        let directive = parser.parseSnippet(from: "2020-07-30 price EUR 1.20 USD")
        #expect(directive != nil)
        guard case .price(let price) = directive?.content else {
            Issue.record("Expected price directive")
            return
        }
        #expect(price.currency == "EUR")
        #expect(price.amount.number == 1.20)
        #expect(price.amount.currency == "USD")
    }

    @Test func parseSnippetInvalidContent() throws {
        let parser = Parser()
        let directive = parser.parseSnippet(from: "invalid content")
        #expect(directive == nil)
    }

    @Test func parseSnippetEmptyString() throws {
        let parser = Parser()
        let directive = parser.parseSnippet(from: "")
        #expect(directive == nil)
    }

    @Test func parseSnippetMultipleDirectives() throws {
        let parser = Parser()
        let content = """
            2020-07-30 open Assets:Test USD
            2020-07-31 close Assets:Test
            """
        // parseSnippet should only return the first directive
        let directive = parser.parseSnippet(from: content)
        #expect(directive != nil)
        guard case .open = directive?.content else {
            Issue.record("Expected open directive")
            return
        }
    }

    @Test func parseSnippetsMultipleDirectives() throws {
        let parser = Parser()
        let content = """
            2020-07-30 open Assets:Checking USD
            2020-07-31 open Assets:Savings USD

            2020-08-01 * "Test transaction"
              Assets:Checking  100.00 USD
              Income:Salary   -100.00 USD

            2020-08-02 balance Assets:Checking 100.00 USD
            2020-12-31 close Assets:Savings
            """
        let directives = parser.parseSnippets(from: content)
        #expect(directives.count == 5)

        guard case .open = directives[0].content else {
            Issue.record("Expected open directive at index 0")
            return
        }
        guard case .open = directives[1].content else {
            Issue.record("Expected open directive at index 1")
            return
        }
        guard case .transaction = directives[2].content else {
            Issue.record("Expected transaction directive at index 2")
            return
        }
        guard case .balance = directives[3].content else {
            Issue.record("Expected balance directive at index 3")
            return
        }
        guard case .close = directives[4].content else {
            Issue.record("Expected close directive at index 4")
            return
        }
    }

    @Test func parseSnippetsEmptyString() throws {
        let parser = Parser()
        let directives = parser.parseSnippets(from: "")
        #expect(directives.isEmpty)
    }

    @Test func parseSnippetsSingleDirective() throws {
        let parser = Parser()
        let content = "2020-07-30 open Assets:Test USD"
        let directives = parser.parseSnippets(from: content)
        #expect(directives.count == 1)
        guard case .open = directives[0].content else {
            Issue.record("Expected open directive")
            return
        }
    }

    @Test func parseSnippetsWithInvalidContent() throws {
        let parser = Parser()
        let content = """
            2020-07-30 open Assets:Checking USD
            invalid line that should be skipped
            2020-07-31 close Assets:Checking
            another invalid line
            """
        let directives = parser.parseSnippets(from: content)
        // Should parse only the valid directives
        #expect(directives.count == 2)
        guard case .open = directives[0].content else {
            Issue.record("Expected open directive at index 0")
            return
        }
        guard case .close = directives[1].content else {
            Issue.record("Expected close directive at index 1")
            return
        }
    }

    @Test func parseSnippetsWithComments() throws {
        let parser = Parser()
        let content = """
            ; This is a comment
            2020-07-30 open Assets:Test USD
            ; Another comment
            2020-07-31 balance Assets:Test 100.00 USD
            """
        let directives = parser.parseSnippets(from: content)
        #expect(directives.count == 2)
    }

    @Test func parseSnippetsPreservesOrder() throws {
        let parser = Parser()
        let content = """
            2020-07-30 open Assets:A USD
            2020-07-29 open Assets:B USD
            2020-07-31 open Assets:C USD
            """
        let directives = parser.parseSnippets(from: content)
        #expect(directives.count == 3)
        #expect(directives[0].date == "2020-07-30")
        #expect(directives[1].date == "2020-07-29")
        #expect(directives[2].date == "2020-07-31")
    }
}
