//
//  PadTests.swift
//
//
//  Created by Yeatse on 2024/1/28.
//

import Foundation
import Testing

@testable import BeancountSwift

struct PadTests {

    @Test func padSimple() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Checking
            2013-05-01 open Equity:Opening-Balances

            ;; Test the simple case that this directive generates a padding entry.
            2013-05-01 pad Assets:Checking Equity:Opening-Balances

            2013-05-03 balance Assets:Checking                                 172.45 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)

        assertEqualEntries(
            ledger.directives,
            """
            2013-05-01 open Assets:Checking
            2013-05-01 open Equity:Opening-Balances

            2013-05-01 pad Assets:Checking Equity:Opening-Balances

            ;; Check this is inserted.
            2013-05-01 P "(Padding inserted for Balance of 172.45 USD for difference 172.45 USD)"
              Assets:Checking                                                        172.45 USD
              Equity:Opening-Balances                                                -172.45 USD

            2013-05-03 balance Assets:Checking                                172.45 USD
            """)
    }

    @Test func padToZero() throws {
        let p: ContentProvider =
            """
            ;; Test the case that this directive generates a padding entry, padding to zero.
            2013-01-01 open Assets:Checking
            2013-01-01 open Equity:Opening-Balances

            2013-02-01 *
              Assets:Checking           234.56 USD
              Equity:Opening-Balances  -234.56 USD

            2013-05-01 pad Assets:Checking Equity:Opening-Balances

            2013-05-03 balance Assets:Checking                                 0.00 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)

        assertEqualEntries(
            ledger.directives,
            """
            2013-01-01 open Assets:Checking
            2013-01-01 open Equity:Opening-Balances

            2013-02-01 *
              Assets:Checking           234.56 USD
              Equity:Opening-Balances  -234.56 USD

            2013-05-01 pad Assets:Checking Equity:Opening-Balances

            ;; Check this is inserted.
            2013-05-01 P "(Padding inserted for Balance of 0.00 USD for difference -234.56 USD)"
              Assets:Checking          -234.56 USD
              Equity:Opening-Balances   234.56 USD

            2013-05-03 balance Assets:Checking                                 0.00 USD
            """)
    }

    @Test func padRespectsBalancePrecision() throws {
        let p: ContentProvider =
            """
            2026-02-01 open Assets:BOC:Checking
            2026-02-01 open Equity:Opening-Balances

            2026-02-01 pad Assets:BOC:Checking Equity:Opening-Balances

            2026-02-02 balance Assets:BOC:Checking 0.10 CNY
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)

        assertEqualEntries(
            ledger.directives,
            """
            2026-02-01 open Assets:BOC:Checking
            2026-02-01 open Equity:Opening-Balances

            2026-02-01 pad Assets:BOC:Checking Equity:Opening-Balances

            ;; Check this is inserted.
            2026-02-01 P "(Padding inserted for Balance of 0.10 CNY for difference 0.10 CNY)"
              Assets:BOC:Checking                                                   0.10 CNY
              Equity:Opening-Balances                                              -0.10 CNY

            2026-02-02 balance Assets:BOC:Checking 0.10 CNY
            """)
    }

    /// Regression: when two pad directives in different files share the same
    /// line number, the generated padding transactions must be attributed to
    /// the correct pad and not leak across files.
    @Test func padAcrossFilesWithCollidingLinenos() throws {
        struct MapContentProvider: ContentProviding {
            let files: [String: String]
            enum TestError: Error { case missing(String) }
            func provideContent(for name: String) throws -> String {
                guard let content = files[name] else { throw TestError.missing(name) }
                return content
            }
        }

        // Both included files have the `pad` directive at the same line number.
        let provider = MapContentProvider(files: [
            "main.bean":
                """
                2020-01-01 open Assets:BOC USD
                2020-01-01 open Assets:WeChat USD
                2020-01-01 open Equity:Opening-Balances

                include "boc.bean"
                include "wechat.bean"
                """,
            "boc.bean":
                """
                2021-07-01 pad Assets:BOC Equity:Opening-Balances
                2021-07-02 balance Assets:BOC 100.00 USD
                """,
            "wechat.bean":
                """
                2021-07-01 pad Assets:WeChat Equity:Opening-Balances
                2021-07-02 balance Assets:WeChat 50.00 USD
                """,
        ])

        let ledger = try Loader.load(file: "main.bean", contentProvider: provider)
        #expect(
            ledger.errors.isEmpty,
            "Expected no errors, got: \(ledger.errors.map { "\($0)" })")

        // Each pad should produce exactly one padding transaction with the
        // right amount on the right account. No doubling, no leakage.
        let paddingTxns = ledger.directives.compactMap {
            entry -> Transaction<Cost>? in
            if case .transaction(let txn) = entry.content, txn.flag == .paddingFlag {
                return txn
            }
            return nil
        }
        #expect(paddingTxns.count == 2)

        let bocPad = paddingTxns.first { txn in
            txn.postings.contains { $0.account.id == "Assets:BOC" }
        }
        let wechatPad = paddingTxns.first { txn in
            txn.postings.contains { $0.account.id == "Assets:WeChat" }
        }
        #expect(bocPad?.postings.first(where: { $0.account.id == "Assets:BOC" })?.units.number
            == Decimal(string: "100.00"))
        #expect(wechatPad?.postings.first(where: { $0.account.id == "Assets:WeChat" })?.units.number
            == Decimal(string: "50.00"))
    }

    @Test func padNoOverflow() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Checking
            2013-05-01 open Assets:Cash
            2013-05-01 open Equity:Opening-Balances

            ;; Pad before the next check.
            2013-05-01 pad Assets:Checking Equity:Opening-Balances

            ;; The check that is being padded.
            2013-05-03 balance Assets:Checking                                 172.45 USD

            2013-05-15 * "Add 20$"
              Assets:Checking                                                   20.00 USD
              Assets:Cash                                                      -20.00 USD

            ;; This is the next check, should not have been padded.
            2013-06-01 balance Assets:Checking                                 200.00 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.count == 1)
        #expect(ledger.errors.first is BalanceError)

        assertEqualEntries(
            ledger.directives,
            """
            2013-05-01 open Assets:Checking
            2013-05-01 open Assets:Cash
            2013-05-01 open Equity:Opening-Balances

            2013-05-01 pad Assets:Checking Equity:Opening-Balances

            2013-05-01 P "(Padding inserted for Balance of 172.45 USD for difference 172.45 USD)"
              Assets:Checking                                                        172.45 USD
              Equity:Opening-Balances                                                -172.45 USD

            2013-05-03 balance Assets:Checking                                 172.45 USD

            2013-05-15 * "Add 20$"
              Assets:Checking                                                         20.00 USD
              Assets:Cash                                                            -20.00 USD

            2013-06-01 balance Assets:Checking                                 200.00 USD
            """)
    }

    @Test func padUsedTwiceLegally() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Checking
            2013-05-01 open Assets:Cash
            2013-05-01 open Equity:Opening-Balances

            ;; First pad.
            2013-05-01 pad  Assets:Checking   Equity:Opening-Balances

            2013-05-03 balance Assets:Checking   172.45 USD

            2013-05-15 * "Add 20$"
              Assets:Checking             20.00 USD
              Assets:Cash                -20.00 USD

            ;; Second pad.
            2013-05-20 pad  Assets:Checking   Equity:Opening-Balances

            2013-06-01 balance Assets:Checking   200 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)

        assertEqualEntries(
            ledger.directives,
            """
            2013-05-01 open Assets:Checking
            2013-05-01 open Assets:Cash
            2013-05-01 open Equity:Opening-Balances

            2013-05-01 pad Assets:Checking Equity:Opening-Balances

            2013-05-01 P "(Padding inserted for Balance of 172.45 USD for difference 172.45 USD)"
              Assets:Checking                                                        172.45 USD
              Equity:Opening-Balances                                                -172.45 USD

            2013-05-03 balance Assets:Checking                                 172.45 USD

            2013-05-15 * "Add 20$"
              Assets:Checking                                                         20.00 USD
              Assets:Cash                                                            -20.00 USD

            2013-05-20 pad Assets:Checking Equity:Opening-Balances

            2013-05-20 P "(Padding inserted for Balance of 200.00 USD for difference 7.55 USD)"
              Assets:Checking                                                          7.55 USD
              Equity:Opening-Balances                                                  -7.55 USD

            2013-06-01 balance Assets:Checking                                 200 USD
            """)
    }

    @Test func padUsedTwiceIllegally() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Checking
            2013-05-01 open Equity:Opening-Balances

            2013-05-03 balance Assets:Checking   0.00 USD

            ;; Two pads in between checks.
            2013-05-10 pad  Assets:Checking   Equity:Opening-Balances
            2013-05-20 pad  Assets:Checking   Equity:Opening-Balances

            2013-06-01 balance Assets:Checking   200 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.count == 1)
        #expect(ledger.errors.first is PadPlugin.PadError)

        assertEqualEntries(
            ledger.directives,
            """
            2013-05-01 open Assets:Checking
            2013-05-01 open Equity:Opening-Balances

            2013-05-03 balance Assets:Checking                                 0.00 USD

            2013-05-10 pad Assets:Checking Equity:Opening-Balances

            2013-05-20 pad Assets:Checking Equity:Opening-Balances

            2013-05-20 P "(Padding inserted for Balance of 200.00 USD for difference 200.00 USD)"
              Assets:Checking                                                        200 USD
              Equity:Opening-Balances                                               -200 USD

            2013-06-01 balance Assets:Checking                                 200 USD
            """)
    }

    @Test func padUnused() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Checking
            2013-05-01 open Assets:Cash
            2013-05-01 open Equity:Opening-Balances

            2013-05-10 * "Add 200$"
              Assets:Checking       200.00 USD
              Assets:Cash          -200.00 USD

            ;; This pad will do nothing, should raise a warning.
            2013-05-20 pad  Assets:Checking   Equity:Opening-Balances

            2013-06-01 balance Assets:Checking   200.00 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.count == 1)
        #expect(ledger.errors.first is PadPlugin.PadError)

        assertEqualEntries(
            ledger.directives,
            """
            2013-05-01 open Assets:Checking
            2013-05-01 open Assets:Cash
            2013-05-01 open Equity:Opening-Balances

            2013-05-10 * "Add 200$"
              Assets:Checking                                                        200.00 USD
              Assets:Cash                                                           -200.00 USD

            2013-05-20 pad Assets:Checking Equity:Opening-Balances

            2013-06-01 balance Assets:Checking                                 200.00 USD
            """)
    }

    @Test func padParents() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:US
            2013-05-01 open Assets:US:Bank1:Checking
            2013-05-01 open Assets:US:Bank1:Savings
            2013-05-01 open Assets:US:Bank2:Checking
            2013-05-01 open Assets:US:Bank2:Savings
            2013-05-01 open Equity:Opening-Balances

            2013-05-10 *
              Assets:US:Bank1:Checking                                 1.00 USD
              Assets:US:Bank1:Savings                                  2.00 USD
              Assets:US:Bank2:Checking                                 3.00 USD
              Assets:US:Bank2:Savings                                  4.00 USD
              Equity:Opening-Balances                                 -10.00 USD

            2013-05-20 pad Assets:US Equity:Opening-Balances

            2013-06-01 balance Assets:US                                       100.00 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)

        assertEqualEntries(
            ledger.directives,
            """
            2013-05-01 open Assets:US
            2013-05-01 open Assets:US:Bank1:Checking
            2013-05-01 open Assets:US:Bank1:Savings
            2013-05-01 open Assets:US:Bank2:Checking
            2013-05-01 open Assets:US:Bank2:Savings
            2013-05-01 open Equity:Opening-Balances

            2013-05-10 *
              Assets:US:Bank1:Checking                                                 1.00 USD
              Assets:US:Bank1:Savings                                                  2.00 USD
              Assets:US:Bank2:Checking                                                 3.00 USD
              Assets:US:Bank2:Savings                                                  4.00 USD
              Equity:Opening-Balances                                                 -10.00 USD

            2013-05-20 pad Assets:US Equity:Opening-Balances

            ;; A single pad that does not include child accounts should be inserted.
            2013-05-20 P "(Padding inserted for Balance of 100.00 USD for difference 90.00 USD)"
              Assets:US                                                              90.00 USD
              Equity:Opening-Balances                                                -90.00 USD

            2013-06-01 balance Assets:US                                       100.00 USD
            """)
    }

    @Test func padMultipleCurrencies() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Checking
            2013-05-01 open Equity:Opening-Balances

            2013-05-10 *
              Assets:Checking                     1.00 USD
              Assets:Checking                     1.00 CAD
              Assets:Checking                     1.00 EUR
              Equity:Opening-Balances

            ;; This should insert two entries: one for USD, one for CAD (different
            ;; amount) and none for EUR.
            2013-05-20 pad Assets:Checking Equity:Opening-Balances

            2013-06-01 balance Assets:Checking    5.00 USD
            2013-06-01 balance Assets:Checking    3.00 CAD
            2013-06-01 balance Assets:Checking    1.00 EUR
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)

        assertEqualEntries(
            ledger.directives,
            """
            2013-05-01 open Assets:Checking
            2013-05-01 open Equity:Opening-Balances

            2013-05-10 *
              Assets:Checking                    1.00 USD
              Assets:Checking                    1.00 CAD
              Assets:Checking                    1.00 EUR
              Equity:Opening-Balances           -1.00 USD
              Equity:Opening-Balances           -1.00 CAD
              Equity:Opening-Balances           -1.00 EUR

            2013-05-20 pad Assets:Checking Equity:Opening-Balances

            2013-05-20 P "(Padding inserted for Balance of 5.00 USD for difference 4.00 USD)"
              Assets:Checking                    4.00 USD
              Equity:Opening-Balances           -4.00 USD

            2013-05-20 P "(Padding inserted for Balance of 3.00 CAD for difference 2.00 CAD)"
              Assets:Checking                    2.00 CAD
              Equity:Opening-Balances           -2.00 CAD

            2013-06-01 balance Assets:Checking   5.00 USD
            2013-06-01 balance Assets:Checking   3.00 CAD
            2013-06-01 balance Assets:Checking   1.00 EUR
            """)
    }

    @Test func padMultipleTimes() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Checking
            2013-05-01 open Equity:Opening-Balances

            2013-06-01 pad Assets:Checking Equity:Opening-Balances
            2013-07-01 pad Assets:Checking Equity:Opening-Balances

            2013-10-01 balance Assets:Checking    5.00 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.count == 1)
        #expect(ledger.errors.first is PadPlugin.PadError)
    }

    @Test func padAtCost() throws {
        let p: ContentProvider =
            """
            2013-05-01 open Assets:Investments
            2013-05-01 open Equity:Opening-Balances

            2013-05-15 *
              Assets:Investments   10 MSFT {54.30 USD}
              Equity:Opening-Balances

            2013-06-01 pad Assets:Investments Equity:Opening-Balances

            2013-10-01 balance Assets:Investments   12 MSFT
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.contains { $0 is PadPlugin.PadError })
        let hasPadWithCost = ledger.errors.contains { err in
            if case .padWithCost = err as? PadPlugin.PadError { return true }
            return false
        }
        #expect(hasPadWithCost)
    }

    @Test func padParent() throws {
        let p: ContentProvider =
            """
            1998-01-01 open Assets:CA:Bank:Checking     CAD
            1998-01-01 open Assets:CA:Bank:CheckingOld  CAD
            1998-01-01 open Income:CA:Something         USD
            1998-01-01 open Equity:Beginning-Balances

            2006-01-01 pad Assets:CA:Bank:Checking   Equity:Beginning-Balances

            2006-04-04 balance Assets:CA:Bank:Checking      742.50 CAD

            2001-01-15 * "Referral"
              Assets:CA:Bank:CheckingOld   1000.00 CAD @ 0.6625 USD
              Income:CA:Something          -662.50 USD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func padTolerance() throws {
        let p: ContentProvider =
            """
            option "inferred_tolerance_default" "*:0.005"

            1998-01-01 open Assets:CA:Bank:Checking
            1998-01-01 open Income:CA:Something
            1998-01-01 open Equity:Beginning-Balances

            2006-01-01 pad Assets:CA:Bank:Checking   Equity:Beginning-Balances

            2001-01-15 * "Referral"
              Assets:CA:Bank:Checking   999.95 CAD
              Income:CA:Something

            2006-04-04 balance Assets:CA:Bank:Checking      1000.00 ~ 0.05 CAD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.count == 1)
        let isUnused: Bool = {
            if case .unusedPad = ledger.errors.first as? PadPlugin.PadError { return true }
            return false
        }()
        #expect(isUnused)
    }

    @Test func padZeroPaddingIssue78a() throws {
        let p: ContentProvider =
            """
            1970-01-01 open Assets:Cash
            1970-01-01 open Expenses:Food

            2015-09-15 pad Assets:Cash Expenses:Food

            2015-09-16 balance Assets:Cash 0 HKD

            ;; The error should be reported here, not on the previous balance check.
            2015-11-02 balance Assets:Cash 1000 HKD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.count == 2)

        let unusedDate: Date? = ledger.errors.compactMap { err -> Date? in
            if case .unusedPad(let pad) = err as? PadPlugin.PadError { return pad.date }
            return nil
        }.first
        #expect(unusedDate == Date(stringLiteral: "2015-09-15"))

        let balanceFailDate: Date? = ledger.errors.compactMap { err -> Date? in
            if case .balanceFailed(_, _, _, let entry) = err as? BalanceError {
                return entry.date
            }
            return nil
        }.first
        #expect(balanceFailDate == Date(stringLiteral: "2015-11-02"))
    }

    @Test func padZeroPaddingIssue78aOriginal() throws {
        let p: ContentProvider =
            """
            1970-01-01 open Assets:Cash
            1970-01-01 open Expenses:Food

            ;; Inserted this before the pad, because it was in the original example.
            2015-09-15 balance Assets:Cash 0 HKD

            2015-09-15 pad Assets:Cash Expenses:Food

            2015-09-16 balance Assets:Cash 0 HKD

            ;; The error should be reported here, not on the previous balance check.
            2015-11-02 balance Assets:Cash 1000 HKD
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.count == 2)

        let unusedDate: Date? = ledger.errors.compactMap { err -> Date? in
            if case .unusedPad(let pad) = err as? PadPlugin.PadError { return pad.date }
            return nil
        }.first
        #expect(unusedDate == Date(stringLiteral: "2015-09-15"))

        let balanceFailDate: Date? = ledger.errors.compactMap { err -> Date? in
            if case .balanceFailed(_, _, _, let entry) = err as? BalanceError {
                return entry.date
            }
            return nil
        }.first
        #expect(balanceFailDate == Date(stringLiteral: "2015-11-02"))
    }

    @Test func padZeroPaddingIssue78b() throws {
        let p: ContentProvider =
            """
            1970-01-01 open Assets:Cash
            1970-01-01 open Expenses:Food

            ;; Balance should fail here.
            2015-09-15 balance Assets:Cash 1 HKD

            ;; This will not end up being marked as unused because it will fill in a transaction
            ;; for the missing amount, even though there was a matching balance check earlier. A
            ;; failing balance check does not automatically bring the balance to its value.
            2015-09-15 pad Assets:Cash Expenses:Food

            2015-09-16 balance Assets:Cash 1 HKD
            """
        let ledger = try p.loadLedger()

        let hasInsertedTxn = ledger.directives.contains { entry in
            if case .transaction(let txn) = entry.content, txn.flag == .paddingFlag {
                return true
            }
            return false
        }
        #expect(hasInsertedTxn)

        #expect(ledger.errors.count == 1)
        let firstErr = ledger.errors.first
        #expect(firstErr is BalanceError)
        if case .balanceFailed(_, _, _, let entry) = firstErr as? BalanceError {
            #expect(entry.date == Date(stringLiteral: "2015-09-15"))
        }
    }

    @Test func padIssue362() throws {
        let p: ContentProvider =
            """
            1970-01-01 open Assets:Bank
            1970-01-01 open Assets:Bank-Two
            1970-01-01 open Equity:Opening-Balance
            1970-01-01 open Equity:Adjustments
            1970-01-01 open Expenses:Food

            2019-01-01 * "Opening balance"
              Assets:Bank                  20.00 GBP
              Equity:Opening-Balance      -20.00 GBP

            2019-01-03 * "Tesco" "Buy food"
              Expenses:Food                30.00 GBP
              Assets:Bank                 -30.00 GBP

            2019-01-04 balance Assets:Bank -10.00 GBP

            2019-01-03 * "Tesco" "Buy food"
              Expenses:Food                 6.00 GBP
              Assets:Bank-Two              -6.00 GBP

            ; Get rid of overdraft somehow and get a £50 balance
            2019-01-04 pad Assets:Bank Equity:Adjustments
            2019-01-05 balance Assets:Bank 50.00 GBP
            """
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
    }
}
