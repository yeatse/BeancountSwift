//
//  RealizationTests.swift
//
//
//  Created by Codex on 2026/2/21.
//

import Foundation
import Testing

@testable import BeancountSwift

private enum PostingMarker: Equatable {
    case open
    case close
    case pad
    case balance
    case note
    case document
    case custom
    case txnPosting
    case other
}

private func marker(of item: TxnPostingsType) -> PostingMarker {
    switch item {
    case .txnPosting:
        return .txnPosting
    case .directive(let directive):
        switch directive.content {
        case .open:
            return .open
        case .close:
            return .close
        case .pad:
            return .pad
        case .balance:
            return .balance
        case .note:
            return .note
        case .document:
            return .document
        case .custom:
            return .custom
        default:
            return .other
        }
    }
}

private func bookedEntries(from content: String) throws -> [Directive<Cost>] {
    let provider = ContentProvider(source: content)
    let parsed = try provider.parseLedger()
    #expect(parsed.errors.isEmpty)

    let booked = Booking.book(ledger: parsed)
    #expect(booked.errors.isEmpty)
    return booked.directives
}

private func postings(
    _ account: String,
    in map: [Account: [TxnPostingsType]]
) -> [TxnPostingsType] {
    map[Account(id: account), default: []]
}

private func createReal(_ accountValuePairs: [(String, Inventory)]) -> RealAccount {
    let realRoot = RealAccount(account: .empty)
    for (accountName, value) in accountValuePairs {
        let realAccount = realRoot.ensureSubaccount(with: accountName)
        realAccount.balance = value
    }
    return realRoot
}

private enum DirectiveMarker: Equatable {
    case open
    case transaction
    case note
    case balance
    case other
}

private func marker(of directive: Directive<Cost>) -> DirectiveMarker {
    switch directive.content {
    case .open:
        return .open
    case .transaction:
        return .transaction
    case .note:
        return .note
    case .balance:
        return .balance
    default:
        return .other
    }
}

private struct SimplifiedBalanceRow: Equatable {
    let marker: DirectiveMarker
    let postingsCount: Int
    let change: Inventory
    let balance: Inventory
}

private func simplifyBalanceRows(_ rows: [BalanceIterationResult]) -> [SimplifiedBalanceRow] {
    rows.map { row in
        SimplifiedBalanceRow(
            marker: marker(of: row.entry),
            postingsCount: row.postings.count,
            change: row.change,
            balance: row.balance)
    }
}

@Suite("TestRealGetters")
struct TestRealGetters {
    @Test func get() {
        let realRoot = RealAccount(account: .empty)
        let _ = realRoot.ensureSubaccount(with: "Assets:US:Bank:Checking")

        #expect(realRoot.subaccount(with: "Assets")?.account.id == "Assets")
        #expect(realRoot.subaccount(with: "Assets:US:Bank")?.account.id == "Assets:US:Bank")
        #expect(
            realRoot.subaccount(with: "Assets:US:Bank:Checking")?.account.id
                == "Assets:US:Bank:Checking")
        #expect(realRoot.subaccount(with: "Assets:US:Bank:Savings") == nil)

        let fallback = RealAccount(account: Account(id: "Fallback"))
        #expect(realRoot.subaccount(with: "Assets:US:Bank:Savings", default: fallback) === fallback)
        #expect(realRoot.subaccount(with: "") == nil)
    }

    @Test func getOrCreate() {
        let realRoot = RealAccount(account: .empty)

        let checking = realRoot.ensureSubaccount(with: "Assets:US:Bank:Checking")
        let _ = realRoot.ensureSubaccount(with: "Assets:US:Bank:Savings")

        #expect(checking.account.id == "Assets:US:Bank:Checking")
        #expect(realRoot.subaccount(with: "Assets:US:Bank:Checking") === checking)
        #expect(
            Set(Array(realRoot.subaccount(with: "Assets:US:Bank")!.children.keys)) == Set([
                "Checking",
                "Savings",
            ]))
    }

    @Test func contains() {
        let realRoot = RealAccount(account: .empty)
        let _ = realRoot.ensureSubaccount(with: "Assets:US:Bank:Checking")
        let _ = realRoot.ensureSubaccount(with: "Assets:US:Bank:Savings")
        #expect(realRoot.contains("Assets"))
        #expect(realRoot.subaccount(with: "Assets:US:Bank:Checking") != nil)
        #expect(realRoot.subaccount(with: "Assets:US:Bank:Savings") != nil)
        #expect(realRoot.subaccount(with: "Assets:US:Cash") == nil)
    }

    @Test func iterChildren() {
        let realRoot = RealAccount(account: .empty)
        for name in [
            "Assets:US:Bank:Checking",
            "Assets:US:Bank:Savings",
            "Assets:US:Cash",
            "Assets:CA:Cash",
        ] {
            let _ = realRoot.ensureSubaccount(with: name)
        }

        #expect(
            Array(realRoot.childAccounts().map(\.account.id)).sorted() == [
                "",
                "Assets",
                "Assets:CA",
                "Assets:CA:Cash",
                "Assets:US",
                "Assets:US:Bank",
                "Assets:US:Bank:Checking",
                "Assets:US:Bank:Savings",
                "Assets:US:Cash",
            ])

        #expect(
            Array(realRoot.childAccounts(leafOnly: true).map(\.account.id)).sorted() == [
                "Assets:CA:Cash",
                "Assets:US:Bank:Checking",
                "Assets:US:Bank:Savings",
                "Assets:US:Cash",
            ])
    }

}

@Suite("TestRealization")
struct TestRealization {
    @Test func postingsByAccount() throws {
        let entries = try bookedEntries(
            from:
                """
                2012-01-01 open Expenses:Restaurant
                2012-01-01 open Expenses:Movie
                2012-01-01 open Assets:Cash
                2012-01-01 open Liabilities:CreditCard
                2012-01-01 open Equity:Opening-Balances

                2012-01-15 pad Liabilities:CreditCard Equity:Opening-Balances

                2012-03-01 * "Food"
                  Expenses:Restaurant     100 CAD
                  Assets:Cash            -100 CAD

                2012-03-10 * "Food again"
                  Expenses:Restaurant      80 CAD
                  Liabilities:CreditCard  -80 CAD

                ;; Two postings on the same account.
                2012-03-15 * "Two Movies"
                  Expenses:Movie           10 CAD
                  Expenses:Movie           10 CAD
                  Liabilities:CreditCard  -20 CAD

                2012-03-20 note Liabilities:CreditCard "Called Amex, asked about 100 CAD dinner"

                2012-03-28 document Liabilities:CreditCard "march-statement.pdf"

                2013-04-01 balance Liabilities:CreditCard   204 CAD

                2014-01-01 close Liabilities:CreditCard
                """
        )

        let grouped = Realization.groupPostingsByAccount(entries)

        #expect(
            postings("Assets:Cash", in: grouped).map(marker(of:)) == [
                .open,
                .txnPosting,
            ])

        #expect(
            postings("Expenses:Restaurant", in: grouped).map(marker(of:)) == [
                .open,
                .txnPosting,
                .txnPosting,
            ])

        #expect(
            postings("Expenses:Movie", in: grouped).map(marker(of:)) == [
                .open,
                .txnPosting,
                .txnPosting,
            ])

        #expect(
            postings("Liabilities:CreditCard", in: grouped).map(marker(of:)) == [
                .open,
                .pad,
                .txnPosting,
                .txnPosting,
                .note,
                .document,
                .balance,
                .close,
            ])

        #expect(
            postings("Equity:Opening-Balances", in: grouped).map(marker(of:)) == [
                .open,
                .pad,
            ])
    }

    @Test func realizeEmpty() {
        let realRoot = Realization.realize(entries: [])
        #expect(realRoot.account == .empty)
        #expect(realRoot.children.isEmpty)
    }

    @Test func simpleRealize() throws {
        let entries = try bookedEntries(
            from:
                """
                2013-05-01 open Assets:US:Checking:Sub   USD
                2013-05-01 open Expenses:Stuff
                2013-05-02 * "Testing!"
                  Assets:US:Checking:Sub            100 USD
                  Expenses:Stuff                   -100 USD
                """
        )
        let realRoot = Realization.realize(entries: entries)

        #expect(realRoot.subaccount(with: "Assets:US:Checking:Sub")?.account.id == "Assets:US:Checking:Sub")
        #expect(realRoot.subaccount(with: "Expenses:Stuff")?.account.id == "Expenses:Stuff")
    }

    @Test func realize() throws {
        let entries = try bookedEntries(
            from:
                """
                2012-01-01 open Expenses:Movie
                2012-01-01 open Liabilities:CreditCard

                2012-03-15 * "Two Movies"
                  Expenses:Movie           10 CAD
                  Expenses:Movie           10 CAD
                  Liabilities:CreditCard  -20 CAD
                """
        )
        let realRoot = Realization.realize(entries: entries)
        #expect(realRoot.subaccount(with: "Expenses:Movie")?.balance == "20 CAD")
    }

}

@Suite("TestRealFilter")
struct TestRealFilter {
    @Test func filterToEmpty() {
        let realRoot = createReal([
            ("Assets:US:Bank:Checking", "1 USD"),
            ("Assets:US:Bank:Savings", "2 USD"),
            ("Liabilities:Bank:CreditCard", "3 USD"),
        ])
        let filtered = realRoot.filtered { _ in false }
        #expect(filtered == nil)
    }

    @Test func filterAlmostAll() {
        let realRoot = createReal([
            ("Assets:US:Bank:Checking", "1 USD"),
            ("Assets:US:Bank:Savings", "2 USD"),
            ("Liabilities:USBank:CreditCard", "3 USD"),
            ("Assets", "100 USD"),
            ("Liabilities:US:Bank", "101 USD"),
        ])

        let filtered = realRoot.filtered { account in
            account.balance.getCurrencyUnits(in: "USD").number >= 100
        }
        #expect(filtered != nil)
        #expect(
            Set(Array(filtered!.childAccounts(leafOnly: true).map(\.account.id))) == Set([
                "Assets",
                "Liabilities:US:Bank",
            ]))
    }

    @Test func filterWithLeaves() {
        let realRoot = createReal([
            ("Assets:US:Bank:Checking", "1 USD"),
            ("Assets:US:Bank:Savings", "2 USD"),
            ("Liabilities:USBank:CreditCard", "3 USD"),
        ])

        let filtered = realRoot.filtered { account in
            !account.balance.isEmpty
        }
        #expect(filtered != nil)
        #expect(
            Set(Array(filtered!.childAccounts(leafOnly: true).map(\.account.id))) == Set([
                "Assets:US:Bank:Checking",
                "Assets:US:Bank:Savings",
                "Liabilities:USBank:CreditCard",
            ]))
    }

    @Test func filterNoLeaves() {
        let realRoot = createReal([
            ("Assets:US:Bank:Checking", "1 USD"),
            ("Assets:US:Bank:Savings", "2 USD"),
            ("Assets:US", "100 USD"),
            ("Assets", "100 USD"),
        ])

        let filtered = realRoot.filtered { account in
            account.balance.getCurrencyUnits(in: "USD").number >= 100
        }
        #expect(filtered != nil)
        #expect(
            Set(Array(filtered!.childAccounts(leafOnly: true).map(\.account.id))) == Set([
                "Assets:US"
            ]))
    }

}

@Suite("TestRealOther")
struct TestRealOther {
    @Test func getPostings() throws {
        let entries = try bookedEntries(
            from:
                """
                2012-01-01 open Assets:Bank:Checking
                2012-01-01 open Expenses:Restaurant
                2012-01-01 open Equity:Opening-Balances

                2012-01-15 pad Assets:Bank:Checking Equity:Opening-Balances

                2012-03-01 * "Food"
                  Expenses:Restaurant     11.11 CAD
                  Assets:Bank:Checking   -11.11 CAD

                2012-03-20 note Assets:Bank:Checking "Bla bla 444.44"

                2013-04-01 balance Assets:Bank:Checking   11.11 CAD

                2013-04-22 custom "customentry" Assets:Bank:Checking
                2013-05-01 close Assets:Bank:Checking
                """
        )
        let realRoot = Realization.realize(entries: entries)
        let allPostings = realRoot.postings

        #expect(allPostings.map(marker(of:)) == [
            .open,
            .open,
            .open,
            .pad,
            .pad,
            .txnPosting,
            .txnPosting,
            .note,
            .balance,
            .custom,
            .close,
        ])

        let txnPostings = allPostings.compactMap { item -> TxnPosting? in
            if case .txnPosting(let posting) = item {
                return posting
            }
            return nil
        }
        #expect(txnPostings.count == 2)

        let postingMap = Dictionary(uniqueKeysWithValues: txnPostings.map {
            ($0.posting.account.id, $0.posting.units)
        })
        #expect(postingMap["Assets:Bank:Checking"] == "-11.11 CAD")
        #expect(postingMap["Expenses:Restaurant"] == "11.11 CAD")
    }

    @Test func iterateWithBalance() throws {
        let entries = try bookedEntries(
            from:
                """
                2012-01-01 open Assets:Bank:Checking
                2012-01-01 open Expenses:Restaurant
                2012-01-01 open Equity:Opening-Balances

                2012-01-15 pad Assets:Bank:Checking Equity:Opening-Balances

                2012-01-20 balance Assets:Bank:Checking  20.00 USD

                2012-03-01 * "With a single entry"
                  Expenses:Restaurant     11.11 CAD
                  Assets:Bank:Checking   -11.11 CAD

                2012-03-02 * "With two entries"
                  Expenses:Restaurant     20.01 CAD
                  Expenses:Restaurant     20.02 CAD
                  Assets:Bank:Checking   -40.03 CAD

                2012-03-02 note Expenses:Restaurant  "This was good"

                2012-04-01 balance Expenses:Restaurant  51.14 CAD
                """
        )
        let realRoot = Realization.realize(entries: entries)
        guard let realAccount = realRoot.subaccount(with: "Expenses:Restaurant") else {
            Issue.record("Expected realized account Expenses:Restaurant")
            return
        }

        let expectedPrefix: [SimplifiedBalanceRow] = [
            .init(marker: .open, postingsCount: 0, change: Inventory(), balance: Inventory()),
            .init(marker: .transaction, postingsCount: 1, change: "11.11 CAD", balance: "11.11 CAD"),
            .init(marker: .transaction, postingsCount: 2, change: "40.03 CAD", balance: "51.14 CAD"),
        ]
        let expectedAll: [SimplifiedBalanceRow] = expectedPrefix + [
            .init(marker: .note, postingsCount: 0, change: Inventory(), balance: "51.14 CAD"),
            .init(marker: .balance, postingsCount: 0, change: Inventory(), balance: "51.14 CAD"),
        ]

        // Match Python: iterate_with_balance(real_account.txn_postings[:-2])
        let prefixRows = Array(
            Realization.balanceChanges(in: Array(realAccount.txnPostings.dropLast(2))))
        #expect(simplifyBalanceRows(prefixRows) == expectedPrefix)

        // Match Python: iterate_with_balance(real_account.txn_postings)
        let allRows = Array(Realization.balanceChanges(in: realAccount.txnPostings))
        #expect(simplifyBalanceRows(allRows) == expectedAll)

        // Match Python: swap [-3] and [-2], should still produce same result.
        var reordered = realAccount.txnPostings
        reordered.swapAt(reordered.count - 3, reordered.count - 2)
        let reorderedRows = Array(Realization.balanceChanges(in: reordered))
        #expect(simplifyBalanceRows(reorderedRows) == expectedAll)
    }

    @Test func computeBalance() {
        let realRoot = createReal([
            ("Assets:US:Bank:Checking", "100 USD"),
            ("Assets:US:Bank:Savings", "200 USD"),
            ("Assets:US:Bank", "10 USD"),
            ("Liabilities:Bank:CreditCard", "-500 USD"),
        ])

        #expect(realRoot.computeBalance() == "-190 USD")
        #expect(realRoot.subaccount(with: "Assets:US:Bank")?.computeBalance() == "310 USD")
    }

}

@Suite("TestComputeBalance")
struct TestComputeBalance {
    @Test func computePostingsBalance() throws {
        let entries = try bookedEntries(
            from:
                """
                2014-01-01 open Assets:Bank:Checking
                2014-01-01 open Assets:Bank:Savings
                2014-01-01 open Assets:Investing
                2014-01-01 open Assets:Other

                2014-05-26 note Assets:Investing "Buying some shares"

                2014-05-30 *
                  Assets:Bank:Checking  111.23 USD
                  Assets:Bank:Savings   222.74 USD
                  Assets:Bank:Savings   17.23 CAD
                  Assets:Investing      10000 EUR
                  Assets:Investing      32 HOOL {45.203 USD}
                  Assets:Other          1000 EUR @ 1.78 GBP
                  Assets:Other          1000 EUR @@ 1780 GBP
                """
        )
        let grouped = Realization.groupPostingsByAccount(entries)
        let flattened = grouped.values.flatMap { $0 }
        let computed = Realization.computeBalance(in: flattened)

        #expect(computed.getCurrencyUnits(in: "USD") == "333.97 USD")
        #expect(computed.getCurrencyUnits(in: "CAD") == "17.23 CAD")
        #expect(computed.getCurrencyUnits(in: "EUR") == "12000 EUR")

        let hoolPositions = Array(computed.positions.filter { $0.units.currency == "HOOL" })
        #expect(hoolPositions.count == 1)
        #expect(hoolPositions[0].units == "32 HOOL")
        #expect(hoolPositions[0].cost?.currency == "USD")
    }
}
