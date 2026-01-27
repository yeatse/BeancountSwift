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
    
    @Test func parenNumericExpressionAmount() throws {
        let p: ContentProvider =
                """
                  2024-01-01 * ""
                    Assets:Savings (+1.0+4.0+5) CNY
                    Liabilities:CreditCard
                """
        let ledger = try p.parseLedger()
        let posting = ledger.directives[0].transaction.postings[0]
        #expect(posting.units.number == 10)
        #expect(posting.units.currency == "CNY")
    }

    @Test func openAccount() throws {
        let p: ContentProvider =
                """
                  2014-01-01 open Assets:Invest CNY,JPY ; Investing
                """
        let ledger = try p.parseLedger()
        let directive = ledger.directives[0]
        #expect(directive.comment == "Investing")
        guard case .open(let open) = directive.content else {
            Issue.record("Expected open directive")
            return
        }
        #expect(open.account == "Assets:Invest")
        #expect(open.currencies == ["CNY", "JPY"])
    }

    @Test func postingComment() throws {
        let p: ContentProvider =
                """
                  2014-01-01 * "Purchase"
                    Assets:Checking  -100.00 USD  ; Payment method
                    Expenses:Grocery  100.00 USD  ; Weekly groceries
                """
        let ledger = try p.parseLedger()
        let posting1 = ledger.directives[0].transaction.postings[0]
        let posting2 = ledger.directives[0].transaction.postings[1]
        #expect(posting1.comment == "Payment method")
        #expect(posting2.comment == "Weekly groceries")
    }

    @Test func postingCommentPrinting() throws {
        let p: ContentProvider =
                """
                  2014-01-01 * "Purchase"
                    Assets:Checking  -100.00 USD  ; My comment
                    Expenses:Test     100.00 USD
                """
        let ledger = try p.parseLedger()
        let posting = ledger.directives[0].transaction.postings[0]
        let description = posting.description
        #expect(description.contains("; My comment"))
    }

    @Test func padDirectivePrinting() throws {
        let p: ContentProvider =
                """
                  2014-06-01 pad Assets:BofA:Checking Equity:Opening-Balances
                """
        let ledger = try p.parseLedger()
        let directive = ledger.directives[0]
        guard case .pad(let pad) = directive.content else {
            Issue.record("Expected pad directive")
            return
        }
        #expect(pad.account == "Assets:BofA:Checking")
        #expect(pad.sourceAccount == "Equity:Opening-Balances")

        let description = directive.description
        #expect(description == "2014-06-01 pad Assets:BofA:Checking Equity:Opening-Balances\n")
    }

    @Test func balanceDirectivePrinting() throws {
        let p: ContentProvider =
                """
                  2014-07-09 balance Assets:US:BofA:Checking 987.34 USD
                """
        let ledger = try p.parseLedger()
        let directive = ledger.directives[0]
        guard case .balance(let balance) = directive.content else {
            Issue.record("Expected balance directive")
            return
        }
        #expect(balance.account == "Assets:US:BofA:Checking")
        #expect(balance.amount.number == 987.34)
        #expect(balance.amount.currency == "USD")

        let description = directive.description
        #expect(description == "2014-07-09 balance Assets:US:BofA:Checking 987.34 USD\n")
    }

    @Test func balanceDirectiveWithTolerancePrinting() throws {
        let p: ContentProvider =
                """
                  2014-07-09 balance Assets:Checking 1000.00 ~ 0.01 USD
                """
        let ledger = try p.parseLedger()
        let directive = ledger.directives[0]
        guard case .balance(let balance) = directive.content else {
            Issue.record("Expected balance directive")
            return
        }
        #expect(balance.account == "Assets:Checking")
        #expect(balance.amount.number == 1000.00)
        #expect(balance.amount.currency == "USD")
        #expect(balance.tolerance == 0.01)

        let description = directive.description
        #expect(description == "2014-07-09 balance Assets:Checking 1000.00 ~ 0.01 USD\n")
    }

    @Test func padDirectiveWithCommentPrinting() throws {
        let p: ContentProvider =
                """
                  2014-06-01 pad Assets:BofA:Checking Equity:Opening-Balances ; Opening balance
                """
        let ledger = try p.parseLedger()
        let directive = ledger.directives[0]
        guard case .pad = directive.content else {
            Issue.record("Expected pad directive")
            return
        }

        let description = directive.description
        #expect(description == "2014-06-01 pad Assets:BofA:Checking Equity:Opening-Balances  ; Opening balance\n")
    }

    @Test func balanceDirectiveWithCommentPrinting() throws {
        let p: ContentProvider =
                """
                  2014-07-09 balance Assets:Checking 987.34 USD ; Monthly check
                """
        let ledger = try p.parseLedger()
        let directive = ledger.directives[0]
        guard case .balance = directive.content else {
            Issue.record("Expected balance directive")
            return
        }

        let description = directive.description
        #expect(description == "2014-07-09 balance Assets:Checking 987.34 USD  ; Monthly check\n")
    }

    @Test func balanceDirectiveWithDiffAmountPrinting() throws {
        let balance = Balance(
            account: "Assets:Checking",
            amount: "1000.00 USD",
            tolerance: nil,
            diffAmount: "-10.50 USD"
        )
        let directive = Directive<CostSpec>(meta: [:], date: "2014-07-09", content: .balance(balance))
        let description = directive.description
        #expect(description == "2014-07-09 balance Assets:Checking 1000.00 USD  ; Diff: -10.50 USD\n")
    }
}
