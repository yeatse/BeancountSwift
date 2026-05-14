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
}
