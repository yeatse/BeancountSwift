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
        #expect(
            description
                == "2014-06-01 pad Assets:BofA:Checking Equity:Opening-Balances  ; Opening balance\n"
        )
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
        let directive = Directive<CostSpec>(
            meta: [:], date: "2014-07-09", content: .balance(balance))
        let description = directive.description
        #expect(
            description == "2014-07-09 balance Assets:Checking 1000.00 USD  ; Diff: -10.50 USD\n")
    }
}

struct TestTotalsAndSigns {
    @Test func zeroAmount() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      0 MSFT {200.00 USD}
                Assets:Investments:Cash      0 USD
            """
        let ledger = try p.parseLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func zeroCost() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      -10 MSFT {0.00 USD}
                Assets:Investments:Cash     0.00 USD
            """
        let ledger = try p.parseLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func costNegative() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      -10 MSFT {-200.00 USD}
                Assets:Investments:Cash  2000.00 USD
            """
        let ledger = try p.parseLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func totalCost() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      10 MSFT {{2,000 USD}}
                Assets:Investments:Cash  -20000 USD

              2013-05-18 * ""
                Assets:Investments:MSFT      10 MSFT {{2000 USD, 2014-02-25}}
                Assets:Investments:Cash  -20000 USD

              2013-06-01 * ""
                Assets:Investments:MSFT      -10 MSFT {{2,000 USD}}
                Assets:Investments:Cash    20000 USD
            """
        let ledger = try p.parseLedger()
        for directive in ledger.directives {
            guard case .transaction(let txn) = directive.content else {
                Issue.record("Expected transaction directive")
                continue
            }
            let posting = txn.postings[0]
            let cost = try #require(posting.cost)
            let perUnit = try #require(cost.numberPerUnit)
            let total = try #require(cost.numberTotal)
            let currency = try #require(cost.currency)
            #expect(perUnit == 0)
            #expect(total == 2000)
            #expect(currency == "USD")
            #expect(posting.price == nil)
        }
    }

    @Test func totalCostInvalid() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      10 MSFT {{100 # 2,000 USD}}
                Assets:Investments:Cash  -20000 USD
            """
        let ledger = try p.parseLedger()
        guard case .transaction(let txn) = ledger.directives[0].content else {
            Issue.record("Expected transaction directive")
            return
        }
        let posting = txn.postings[0]
        let cost = try #require(posting.cost)
        let perUnit = try #require(cost.numberPerUnit)
        let total = try #require(cost.numberTotal)
        let currency = try #require(cost.currency)
        #expect(perUnit == 0)
        #expect(total == 2000)
        #expect(currency == "USD")
        #expect(posting.price == nil)
    }

    @Test func totalCostNegative() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      -10 MSFT {{-200.00 USD}}
                Assets:Investments:Cash   200.00 USD
            """
        let ledger = try p.parseLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func priceNegative() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      -10 MSFT @ -200.00 USD
                Assets:Investments:Cash  2000.00 USD
            """
        let ledger = try p.parseLedger()
        guard case .transaction(let txn) = ledger.directives[0].content else {
            Issue.record("Expected transaction directive")
            return
        }
        #expect(txn.postings[0].price == "200 USD")
    }

    @Test func totalPricePositive() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT        10 MSFT @@ 2000.00 USD
                Assets:Investments:Cash  -2000.00 USD
            """
        let ledger = try p.parseLedger()
        guard case .transaction(let txn) = ledger.directives[0].content else {
            Issue.record("Expected transaction directive")
            return
        }
        let posting = txn.postings[0]
        let price = try #require(posting.price)
        #expect(price == "200 USD")
        #expect(posting.cost == nil)
    }

    @Test func totalPriceNegative() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT       -10 MSFT @@ 2000.00 USD
                Assets:Investments:Cash  20000.00 USD
            """
        let ledger = try p.parseLedger()
        guard case .transaction(let txn) = ledger.directives[0].content else {
            Issue.record("Expected transaction directive")
            return
        }
        let posting = txn.postings[0]
        let price = try #require(posting.price)
        #expect(price == "200 USD")
        #expect(posting.cost == nil)
    }

    @Test func totalPriceInverted() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT         10 MSFT @@ -2000.00 USD
                Assets:Investments:Cash   20000.00 USD
            """
        let ledger = try p.parseLedger()
        guard case .transaction(let txn) = ledger.directives[0].content else {
            Issue.record("Expected transaction directive")
            return
        }
        #expect(txn.postings[0].price == "200 USD")
    }

    @Test func totalPriceWithMissing() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT            MSFT @@ 2000.00 USD
                Assets:Investments:Cash   20000.00 USD
            """
        let ledger = try p.parseLedger()
        guard case .transaction(let txn) = ledger.directives[0].content else {
            Issue.record("Expected transaction directive")
            return
        }
        #expect(txn.postings[0].price == nil)
    }
}

struct TestBalance {
    @Test func totalPrice() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      10 MSFT @@ 2000 USD
                Assets:Investments:Cash  -20000 USD
            """
        let ledger = try p.parseLedger()
        guard case .transaction(let txn) = ledger.directives[0].content else {
            Issue.record("Expected transaction directive")
            return
        }
        let posting = txn.postings[0]
        let price = try #require(posting.price)
        #expect(price == "200 USD")
        #expect(posting.cost == nil)
    }

    @Test func totalCost() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      10 MSFT {{2,000 USD}}
                Assets:Investments:Cash  -20000 USD

              2013-05-18 * ""
                Assets:Investments:MSFT      10 MSFT {{2000 USD, 2014-02-25}}
                Assets:Investments:Cash  -20000 USD
            """
        let ledger = try p.parseLedger()
        for directive in ledger.directives {
            guard case .transaction(let txn) = directive.content else {
                Issue.record("Expected transaction directive")
                continue
            }
            let posting = txn.postings[0]
            let cost = try #require(posting.cost)
            let perUnit = try #require(cost.numberPerUnit)
            let total = try #require(cost.numberTotal)
            let currency = try #require(cost.currency)
            #expect(perUnit == 0)
            #expect(total == 2000)
            #expect(currency == "USD")
            #expect(posting.price == nil)
        }
    }
}
