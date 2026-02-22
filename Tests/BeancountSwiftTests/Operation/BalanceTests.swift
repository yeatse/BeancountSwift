//
//  BalanceTests.swift
//
//
//  Created by 杨超 on 2024/2/15.
//

import Testing

@testable import BeancountSwift

extension Directive {
    fileprivate var balance: Balance {
        switch content {
        case .balance(let x): x
        default: fatalError()
        }
    }
}

struct BalanceTests {
    @Test func simpleError() throws {
        let p: ContentProvider =
            """
              2013-05-01 open Assets:US:Checking

              2013-05-03 balance Assets:US:Checking   100 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors[0] is BalanceError)
        #expect(ledger.directives[1].balance.diffAmount == "-100 USD")
    }

    @Test func simpleFirst() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Bank:Checking
            2013-05-01 open Equity:Opening-Balances

            2013-05-02 *
              Assets:Bank:Checking                100 USD
              Equity:Opening-Balances

            2013-05-03 balance Assets:Bank:Checking   100 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
        let entry = ledger.directives.last!
        #expect(entry.balance.diffAmount == nil)
    }

    @Test func simpleCont() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Bank:Checking
            2013-05-01 open Equity:Opening-Balances

            2013-05-02 *
              Assets:Bank:Checking                100 USD
              Equity:Opening-Balances

            2013-05-03 balance Assets:Bank:Checking   100 USD

            2013-05-04 *
              Assets:Bank:Checking                 10 USD
              Equity:Opening-Balances

            2013-05-05 balance Assets:Bank:Checking   110 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func simplePartialCurrencyFirst() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Bank:Checking
            2013-05-01 open Equity:Opening-Balances

            2013-05-02 *
              Assets:Bank:Checking                100 USD
              Assets:Bank:Checking                200 CAD
              Equity:Opening-Balances

            2013-05-03 balance Assets:Bank:Checking   100 USD
            2013-05-03 balance Assets:Bank:Checking   200 CAD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func simplePartialCurrencyCont() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Bank:Checking
            2013-05-01 open Equity:Opening-Balances

            2013-05-02 *
              Assets:Bank:Checking                100 USD
              Assets:Bank:Checking                200 CAD
              Equity:Opening-Balances

            2013-05-03 balance Assets:Bank:Checking   100 USD

            2013-05-04 *
              Assets:Bank:Checking                 10 USD
              Assets:Bank:Checking                 20 CAD
              Equity:Opening-Balances

            2013-05-05 balance Assets:Bank:Checking   110 USD
            2013-05-05 balance Assets:Bank:Checking   220 CAD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func simpleInvalidCurrency() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Bank:Checking      CAD
            2013-05-01 open Equity:Opening-Balances

            ;; This ought to fail because USD isn't a valid currency.
            2013-05-03 balance Assets:Bank:Checking   0.00 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors[0] is BalanceError)
    }

    @Test func parents() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Bank
            2013-05-01 open Assets:Bank:Checking1
            2013-05-01 open Assets:Bank:Checking2
            2013-05-01 open Assets:Bank:Savings   ;; Will go negative
            2013-05-01 open Equity:Opening-Balances

            2013-05-02 *
              Assets:Bank:Checking1                100 USD
              Equity:Opening-Balances

            2013-05-03 *
              Assets:Bank:Checking2                10 USD
              Equity:Opening-Balances

            2013-05-04 *
              Assets:Bank:Savings                 -50 USD
              Equity:Opening-Balances

            2013-05-05 balance Assets:Bank:Checking1  100 USD
            2013-05-05 balance Assets:Bank:Checking2   10 USD
            2013-05-05 balance Assets:Bank:Savings    -50 USD
            2013-05-05 balance Assets:Bank             60 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
        let diffAmounts = ledger.directives.compactMap { directive in
            if case .balance(let x) = directive.content { x } else { nil }
        }.map(\.diffAmount)
        #expect(diffAmounts == [nil, nil, nil, nil])
    }

    @Test func parentsOnly() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Bank
            2013-05-01 open Assets:Bank:Checking1
            2013-05-01 open Assets:Bank:Checking2
            2013-05-01 open Equity:Opening-Balances

            2013-05-02 *
              Assets:Bank:Checking1                100 USD
              Equity:Opening-Balances

            2013-05-03 *
              Assets:Bank:Checking2                10 USD
              Equity:Opening-Balances

            2013-05-05 balance Assets:Bank             110 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
        let diffAmounts = ledger.directives.compactMap { directive in
            if case .balance(let x) = directive.content { x } else { nil }
        }.map(\.diffAmount)
        #expect(diffAmounts == [nil])
    }

    @Test func parentsWithPostings() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Bank
            2013-05-01 open Assets:Bank:Checking1
            2013-05-01 open Assets:Bank:Checking2
            2013-05-01 open Equity:Opening-Balances

            2013-05-02 *
              Assets:Bank:Checking1                100 USD
              Equity:Opening-Balances

            2013-05-03 *
              Assets:Bank:Checking2                10 USD
              Equity:Opening-Balances

            2013-05-04 * "Posting on a parent account"
              Assets:Bank                          15 USD
              Equity:Opening-Balances

            2013-05-05 balance Assets:Bank             125 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
        let diffAmounts = ledger.directives.compactMap { directive in
            if case .balance(let x) = directive.content { x } else { nil }
        }.map(\.diffAmount)
        #expect(diffAmounts == [nil])
    }

    @Test func withLots() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Bank:Investing
            2013-05-01 open Equity:Opening-Balances

            2013-05-02 *
              Assets:Bank:Investing                1 HOOL {501 USD}
              Equity:Opening-Balances

            2013-05-03 balance Assets:Bank:Investing    1 HOOL
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func checkSameData() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:US:Checking   USD
            2013-05-01 open Expenses:Something

            2013-05-02 txn "Testing!"
              Assets:US:Checking            100 USD
              Expenses:Something           -100 USD

            2013-05-02 balance Assets:US:Checking     0 USD
            2013-05-03 balance Assets:US:Checking   100 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func precision() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Bank:Checking
            2013-05-01 open Income:Interest

            2013-05-02 *
              Assets:Bank:Checking        0.00001 USD
              Income:Interest

            2013-05-03 balance Assets:Bank:Checking   0.00 USD

            2013-05-03 *
              Assets:Bank:Checking        0.00001 USD
              Income:Interest

            2013-05-04 balance Assets:Bank:Checking   0.00 USD

            2013-05-04 *
              Assets:Bank:Checking        0.015 USD
              Income:Interest

            2013-05-05 balance Assets:Bank:Checking   0.01502 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func balanceBeforeCreate() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:US:Checking   USD
            2013-05-01 open Expenses:Something

            2013-05-01 balance Assets:US:Checking     0 USD

            2013-05-03 txn "Testing!"
              Assets:US:Checking            100 USD
              Expenses:Something           -100 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func balanceWithPrefixAccount() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Bank:Checking
            2013-05-01 open Assets:Bank:CheckingOld
            2013-05-01 open Equity:Opening-Balances

            2013-05-02 *
              Assets:Bank:Checking                100 USD
              Equity:Opening-Balances

            2013-05-03 *
              Assets:Bank:CheckingOld              27 USD
              Equity:Opening-Balances

            2013-05-10 balance Assets:Bank:Checking   100 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func balanceMixedCostAndNoCost() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Invest
            2013-05-01 open Equity:Opening-Balances

            2013-05-01 *
              Assets:Invest                100 HOOL {14.33 USD}
              Equity:Opening-Balances

            2013-05-02 *
              Assets:Invest               -100 HOOL @ 15.66 USD
              Equity:Opening-Balances

            2013-05-10 balance Assets:Invest   0 HOOL
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func balanceAccountDoesNotExist() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Invest
            2013-05-01 open Equity:Opening-Balances

            2013-05-10 balance Assets:Invest:Invalid   0 HOOL
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors[0] is BalanceError)
        // balance check shouldn't "eat" the balance entry.
        #expect(ledger.directives.count == 3)
        let entry = ledger.directives[2]
        if case .balance(_) = entry.content {
            // Test passes - entry is indeed a balance directive
        } else {
            Issue.record("Expected balance directive")
        }
    }

    @Test func getBalanceToleranceExplicit() throws {
        let p: ContentProvider =
            """
            2015-05-01 open Assets:Bank:Checking
            2015-05-02 balance Assets:Bank:Checking   0    ~ 0.002 USD
            2015-05-02 balance Assets:Bank:Checking   0.0  ~ 0.002 USD
            2015-05-02 balance Assets:Bank:Checking   0.00 ~ 0.002 USD
            2015-05-02 balance Assets:Bank:Checking   1    ~ 0.002 USD
            2015-05-02 balance Assets:Bank:Checking   1.0  ~ 0.002 USD
            2015-05-02 balance Assets:Bank:Checking   1.00 ~ 0.002 USD
            """
        let ledger = try p.loadLedger()
        let tolerances = ledger.directives.dropFirst().map { entry in
            entry.balance.tolerance(options: ledger.options)
        }
        #expect(tolerances == (0..<6).map { _ in "0.002" })
    }

    @Test func getBalanceToleranceRegular() throws {
        let p: ContentProvider =
            """
            2015-05-01 open Assets:Bank:Checking
            2015-05-02 balance Assets:Bank:Checking   0 USD
            2015-05-02 balance Assets:Bank:Checking   0.0 USD
            2015-05-02 balance Assets:Bank:Checking   0.00 USD
            2015-05-02 balance Assets:Bank:Checking   0.000 USD
            2015-05-02 balance Assets:Bank:Checking   1 USD
            2015-05-02 balance Assets:Bank:Checking   1.1 USD
            2015-05-02 balance Assets:Bank:Checking   1.01 USD
            2015-05-02 balance Assets:Bank:Checking   1.001 USD
            2015-05-02 balance Assets:Bank:Checking   1.01 USD
            """
        let ledger = try p.loadLedger()
        let tolerances = ledger.directives.dropFirst().map { entry in
            entry.balance.tolerance(options: ledger.options)
        }
        #expect(
            tolerances == [
                "0", "0.1", "0.01", "0.001",
                "0", "0.1", "0.01", "0.001", "0.01",
            ])
    }

    @Test func balanceWithTolerance() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Bank:Checking
            2013-05-01 open Equity:Opening-Balances

            2013-05-03 *
              Assets:Bank:Checking              23.024 USD
              Equity:Opening-Balances

            2015-05-02 balance Assets:Bank:Checking   23.022 ~ 0.001 USD
            2015-05-03 balance Assets:Bank:Checking   23.023 ~ 0.001 USD
            2015-05-04 balance Assets:Bank:Checking   23.024 ~ 0.001 USD
            2015-05-05 balance Assets:Bank:Checking   23.025 ~ 0.001 USD
            2015-05-06 balance Assets:Bank:Checking   23.026 ~ 0.001 USD

            2015-05-10 balance Assets:Bank:Checking   23.03 ~ 0.01 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.count == 2)
        #expect(String(describing: ledger.errors[0]).contains("23.022"))
        #expect(String(describing: ledger.errors[1]).contains("23.026"))
    }
}
