//
//  SummarizeTests.swift
//  BeancountSwift
//
//  Created by yeatse on 2026/2/22.
//

import Foundation
import Testing

@testable import BeancountSwift

private func loadDirectives(_ source: String) -> [Directive<Cost>] {
    let ledger = try! ContentProvider(source: source).loadLedger()
    return ledger.directives
}

private func loadLedger(_ source: String) -> ParsedLedger<Cost> {
    try! ContentProvider(source: source).loadLedger()
}

private func assertIncludesEntries(
    _ expected: String,
    _ actual: [Directive<Cost>],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let expectedEntries = loadDirectives(expected).map { $0.removingMeta() }
    let actualEntries = actual.map { $0.removingMeta() }
    for entry in expectedEntries {
        #expect(actualEntries.contains(entry), sourceLocation: sourceLocation)
    }
}

private func assertExcludesEntries(
    _ expected: String,
    _ actual: [Directive<Cost>],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let expectedEntries = loadDirectives(expected).map { $0.removingMeta() }
    let actualEntries = actual.map { $0.removingMeta() }
    for entry in expectedEntries {
        #expect(!actualEntries.contains(entry), sourceLocation: sourceLocation)
    }
}

private func computeEntriesBalance(_ entries: [Directive<Cost>], date: Date? = nil) -> Inventory {
    var balance = Inventory()
    for entry in entries {
        if let date, entry.date >= date {
            break
        }
        guard case .transaction(let txn) = entry.content else {
            continue
        }
        for posting in txn.postings {
            balance.addPosition(posting)
        }
    }
    return balance
}

private func computeEntriesCostBalance(_ entries: [Directive<Cost>], date: Date? = nil) -> Inventory
{
    computeEntriesBalance(entries, date: date).reduce { $0.totalCost }
}

private func isSortedByDate(_ entries: [Directive<Cost>]) -> Bool {
    zip(entries, entries.dropFirst()).allSatisfy { lhs, rhs in
        lhs.date <= rhs.date
    }
}

extension Summarize {
    fileprivate static func meta(_ filename: String, _ lineno: UInt32) -> MetaData {
        ["filename": .string(filename), "lineno": .number(.init(lineno))]
    }
}

@Suite("TestOpenClose")
struct TestOpenClose {
    fileprivate static let input = """
        option "account_previous_earnings"    "Earnings:Previous"
        option "account_previous_balances"    "Opening-Balances"
        option "account_previous_conversions" "Conversions:Previous"

        option "account_current_earnings"     "Earnings:Current"
        option "account_current_conversions"  "Conversions:Current"
        option "conversion_currency"          "NOTHING"

        2012-01-01 open Income:Salary
        2012-01-01 open Expenses:Taxes
        2012-01-01 open Assets:US:Checking
        2012-01-01 open Assets:CA:Checking

        2012-03-01 * "Some income and expense to be summarized"
          Income:Salary        10000 USD
          Expenses:Taxes        3600 USD
          Assets:US:Checking  -13600 USD

        2012-03-02 * "Some conversion to be summarized"
          Assets:US:Checking   -5000 USD @ 1.2 CAD
          Assets:CA:Checking    6000 CAD

        ;; 2012-06-01  BEGIN --------------------------------

        2012-08-01 * "Some income and expense to show"
          Income:Salary        11000 USD
          Expenses:Taxes        3200 USD
          Assets:US:Checking  -14200 USD

        2012-08-02 * "Some other conversion to be summarized"
          Assets:US:Checking   -3000 USD @ 1.25 CAD
          Assets:CA:Checking    3750 CAD

        ;; 2012-09-01  END   --------------------------------

        2012-11-01 * "Some income and expense to be truncated"
          Income:Salary        10000 USD
          Expenses:Taxes        3600 USD
          Assets:US:Checking  -13600 USD
        """

    fileprivate static func fixture() -> (entries: [Directive<Cost>], options: Options) {
        let ledger = loadLedger(Self.input)
        #expect(ledger.errors.isEmpty)
        return (ledger.directives, ledger.options)
    }

    @Test func open() {
        let (entries, options) = Self.fixture()
        let opened = Summarize.open(
            entries,
            date: "2012-06-01",
            accountTypes: options.accountNames,
            conversionCurrency: "NOTHING",
            accountEarnings: "Equity:Earnings:Previous",
            accountOpening: "Equity:Opening-Balances",
            accountConversions: "Equity:Conversions:Previous"
        )

        assertEqualEntries(
            opened.entries,
            """
            2012-01-01 open Income:Salary
            2012-01-01 open Expenses:Taxes
            2012-01-01 open Assets:US:Checking
            2012-01-01 open Assets:CA:Checking

            2012-05-31 S "Opening balance for 'Assets:CA:Checking' (Summarization)"
              Assets:CA:Checking             6000 CAD
              Equity:Opening-Balances       -6000 CAD

            2012-05-31 S "Opening balance for 'Assets:US:Checking' (Summarization)"
              Assets:US:Checking           -18600 USD
              Equity:Opening-Balances       18600 USD

            2012-05-31 S "Opening balance for 'Equity:Conversions:Previous' (Summarization)"
              Equity:Conversions:Previous    5000 USD
              Equity:Opening-Balances       -5000 USD
              Equity:Conversions:Previous   -6000 CAD
              Equity:Opening-Balances        6000 CAD

            2012-05-31 S "Opening balance for 'Equity:Earnings:Previous' (Summarization)"
              Equity:Earnings:Previous      13600 USD
              Equity:Opening-Balances      -13600 USD

            2012-08-01 * "Some income and expense to show"
              Income:Salary                 11000 USD
              Expenses:Taxes                 3200 USD
              Assets:US:Checking           -14200 USD

            2012-08-02 * "Some other conversion to be summarized"
              Assets:US:Checking            -3000 USD @ 1.25 CAD
              Assets:CA:Checking             3750 CAD

            2012-11-01 * "Some income and expense to be truncated"
              Income:Salary                 10000 USD
              Expenses:Taxes                 3600 USD
              Assets:US:Checking           -13600 USD
            """
        )

        #expect(opened.index == 8)

        let inputBalance = computeEntriesBalance(entries)
        #expect(!inputBalance.isEmpty)

        let summarizedEntries = Array(opened.entries.prefix(opened.index))
        #expect(computeEntriesBalance(summarizedEntries).isEmpty)

        #expect(!computeEntriesBalance(opened.entries).isEmpty)
    }

    @Test func close() {
        let (entries, _) = Self.fixture()

        let closed = Summarize.close(
            entries,
            date: "2012-09-01",
            conversionCurrency: "NOTHING",
            accountConversions: "Equity:Conversions:Current"
        )

        assertEqualEntries(
            closed.entries,
            """
            2012-01-01 open Income:Salary
            2012-01-01 open Expenses:Taxes
            2012-01-01 open Assets:US:Checking
            2012-01-01 open Assets:CA:Checking

            2012-03-01 * "Some income and expense to be summarized"
              Income:Salary        10000 USD
              Expenses:Taxes        3600 USD
              Assets:US:Checking  -13600 USD

            2012-03-02 * "Some conversion to be summarized"
              Assets:US:Checking   -5000 USD @ 1.2 CAD
              Assets:CA:Checking    6000 CAD

            2012-08-01 * "Some income and expense to show"
              Income:Salary        11000 USD
              Expenses:Taxes        3200 USD
              Assets:US:Checking  -14200 USD

            2012-08-02 * "Some other conversion to be summarized"
              Assets:US:Checking   -3000 USD @ 1.25 CAD
              Assets:CA:Checking    3750 CAD

            2012-08-31 C "Conversion for -8000.00 USD, 9750.00 CAD"
              Equity:Conversions:Current    8000 USD  @ 0 NOTHING
              Equity:Conversions:Current   -9750 CAD  @ 0 NOTHING
            """
        )

        #expect(closed.index == 8)
        #expect(!computeEntriesBalance(entries).isEmpty)
        #expect(!computeEntriesBalance(Array(closed.entries.prefix(closed.index))).isEmpty)
        #expect(computeEntriesBalance(closed.entries).isEmpty)
    }

    @Test func clear() {
        let (entries, options) = Self.fixture()

        let cleared = Summarize.clear(
            entries,
            date: "2013-01-01",
            accountTypes: options.accountNames,
            accountEarnings: "Equity:Earnings:Current"
        )

        assertEqualEntries(
            cleared.entries,
            """
            2012-01-01 open Income:Salary
            2012-01-01 open Expenses:Taxes
            2012-01-01 open Assets:US:Checking
            2012-01-01 open Assets:CA:Checking

            2012-03-01 * "Some income and expense to be summarized"
              Income:Salary        10000 USD
              Expenses:Taxes        3600 USD
              Assets:US:Checking  -13600 USD

            2012-03-02 * "Some conversion to be summarized"
              Assets:US:Checking   -5000 USD @ 1.2 CAD
              Assets:CA:Checking    6000 CAD

            2012-08-01 * "Some income and expense to show"
              Income:Salary        11000 USD
              Expenses:Taxes        3200 USD
              Assets:US:Checking  -14200 USD

            2012-08-02 * "Some other conversion to be summarized"
              Assets:US:Checking   -3000 USD @ 1.25 CAD
              Assets:CA:Checking    3750 CAD

            2012-11-01 * "Some income and expense to be truncated"
              Income:Salary        10000 USD
              Expenses:Taxes        3600 USD
              Assets:US:Checking  -13600 USD

            2012-12-31 T "Transfer balance for 'Expenses:Taxes' (Transfer balance)"
              Expenses:Taxes           -10400 USD
              Equity:Earnings:Current   10400 USD

            2012-12-31 T "Transfer balance for 'Income:Salary' (Transfer balance)"
              Income:Salary             -31000 USD
              Equity:Earnings:Current    31000 USD
            """
        )

        #expect(cleared.index == 9)
        #expect(!computeEntriesBalance(cleared.entries).isEmpty)
    }

    @Test func openCloseClear() {
        let (entries, options) = Self.fixture()

        let opened = Summarize.open(
            entries,
            date: "2012-06-01",
            accountTypes: options.accountNames,
            conversionCurrency: "NOTHING",
            accountEarnings: "Equity:Earnings:Previous",
            accountOpening: "Equity:Opening-Balances",
            accountConversions: "Equity:Conversions:Previous"
        )

        let closed = Summarize.close(
            opened.entries,
            date: "2012-09-01",
            conversionCurrency: "NOTHING",
            accountConversions: "Equity:Conversions:Current"
        )

        let cleared = Summarize.clear(
            closed.entries,
            date: "2013-01-01",
            accountTypes: options.accountNames,
            accountEarnings: "Equity:Earnings:Current"
        )

        assertEqualEntries(
            cleared.entries,
            """
            2012-01-01 open Income:Salary
            2012-01-01 open Expenses:Taxes
            2012-01-01 open Assets:US:Checking
            2012-01-01 open Assets:CA:Checking

            2012-05-31 S "Opening balance for 'Assets:CA:Checking' (Summarization)"
              Assets:CA:Checking            6000 CAD
              Equity:Opening-Balances      -6000 CAD

            2012-05-31 S "Opening balance for 'Assets:US:Checking' (Summarization)"
              Assets:US:Checking          -18600 USD
              Equity:Opening-Balances      18600 USD

            2012-05-31 S "Opening balance for 'Equity:Conversions:Previous' (Summarization)"
              Equity:Conversions:Previous   5000 USD
              Equity:Opening-Balances      -5000 USD
              Equity:Conversions:Previous  -6000 CAD
              Equity:Opening-Balances       6000 CAD

            2012-05-31 S "Opening balance for 'Equity:Earnings:Previous' (Summarization)"
              Equity:Earnings:Previous     13600 USD
              Equity:Opening-Balances     -13600 USD

            2012-08-01 * "Some income and expense to show"
              Income:Salary                11000 USD
              Expenses:Taxes                3200 USD
              Assets:US:Checking          -14200 USD

            2012-08-02 * "Some other conversion to be summarized"
              Assets:US:Checking           -3000 USD @ 1.25 CAD
              Assets:CA:Checking            3750 CAD

            2012-08-31 C "Conversion for -3000.00 USD, 3750.00 CAD"
              Equity:Conversions:Current    3000 USD @ 0 NOTHING
              Equity:Conversions:Current   -3750 CAD @ 0 NOTHING

            2012-12-31 T "Transfer balance for 'Expenses:Taxes' (Transfer balance)"
              Expenses:Taxes               -3200 USD
              Equity:Earnings:Current       3200 USD

            2012-12-31 T "Transfer balance for 'Income:Salary' (Transfer balance)"
              Income:Salary              -11000 USD
              Equity:Earnings:Current     11000 USD
            """
        )
    }

}

@Suite("TestOpenCloseWithOptions")
struct TestOpenCloseWithOptions {
    @Test func openCloseClearWithOptions() {
        let (entries, options) = TestOpenClose.fixture()

        let openedManual = Summarize.open(
            entries,
            date: "2012-06-01",
            accountTypes: options.accountNames,
            conversionCurrency: "NOTHING",
            accountEarnings: "Equity:Earnings:Previous",
            accountOpening: "Equity:Opening-Balances",
            accountConversions: "Equity:Conversions:Previous"
        )
        let openedOpt = Summarize.openOpt(entries, date: "2012-06-01", options: options)
        #expect(openedManual.index == openedOpt.index)
        assertEqualEntries(openedManual.entries, openedOpt.entries)

        let closedManual = Summarize.close(
            entries,
            date: "2012-09-01",
            conversionCurrency: "NOTHING",
            accountConversions: "Equity:Conversions:Current"
        )
        let closedOpt = Summarize.closeOpt(entries, date: "2012-09-01", options: options)
        #expect(closedManual.index == closedOpt.index)
        assertEqualEntries(closedManual.entries, closedOpt.entries)

        let clearManual = Summarize.clear(
            entries,
            date: "2013-01-01",
            accountTypes: options.accountNames,
            accountEarnings: "Equity:Earnings:Current"
        )
        let clearOpt = Summarize.clearOpt(entries, date: "2013-01-01", options: options)
        #expect(clearManual.index == clearOpt.index)
        assertEqualEntries(clearManual.entries, clearOpt.entries)
    }

}

@Suite("TestClamp")
struct TestClamp {
    private static let input = """
        2012-01-01 open Income:Salary
        2012-01-01 open Expenses:Taxes
        2012-01-01 open Assets:US:Checking
        2012-01-01 open Assets:CA:Checking

        2012-03-01 * "Some income and expense to be summarized"
          Income:Salary        10000.00 USD
          Expenses:Taxes        3600.00 USD
          Assets:US:Checking  -13600.00 USD

        2012-03-02 * "Some conversion to be summarized"
          Assets:US:Checking   -5000.00 USD @ 1.2 CAD
          Assets:CA:Checking    6000.00 CAD

        ;; 2012-06-01  BEGIN --------------------------------

        2012-08-01 * "Some income and expense to show"
          Income:Salary        11000.00 USD
          Expenses:Taxes        3200.00 USD
          Assets:US:Checking  -14200.00 USD

        2012-08-02 * "Some other conversion to be summarized"
          Assets:US:Checking   -3000.00 USD @ 1.25 CAD
          Assets:CA:Checking    3750.00 CAD

        ;; 2012-09-01  END   --------------------------------

        2012-11-01 * "Some income and expense to be truncated"
          Income:Salary        10000.00 USD
          Expenses:Taxes        3600.00 USD
          Assets:US:Checking  -13600.00 USD
        """

    @Test func clamp() {
        let ledger = loadLedger(Self.input)
        #expect(ledger.errors.isEmpty)

        let clamped = Summarize.clamp(
            ledger.directives,
            beginDate: "2012-06-01",
            endDate: "2012-09-01",
            accountTypes: ledger.options.accountNames,
            conversionCurrency: "NOTHING",
            accountEarnings: "Equity:Earnings",
            accountOpening: "Equity:Opening-Balances",
            accountConversions: "Equity:Conversions"
        )

        assertEqualEntries(
            clamped.entries,
            """
            2012-01-01 open Income:Salary
            2012-01-01 open Expenses:Taxes
            2012-01-01 open Assets:US:Checking
            2012-01-01 open Assets:CA:Checking

            2012-05-31 S "Opening balance for 'Assets:CA:Checking' (Summarization)"
              Assets:CA:Checking              6000.00 CAD
              Equity:Opening-Balances        -6000.00 CAD

            2012-05-31 S "Opening balance for 'Assets:US:Checking' (Summarization)"
              Assets:US:Checking            -18600.00 USD
              Equity:Opening-Balances        18600.00 USD

            2012-05-31 S "Opening balance for 'Equity:Earnings' (Summarization)"
              Equity:Earnings                13600.00 USD
              Equity:Opening-Balances       -13600.00 USD

            2012-08-01 * "Some income and expense to show"
              Income:Salary                  11000.00 USD
              Expenses:Taxes                  3200.00 USD
              Assets:US:Checking            -14200.00 USD

            2012-08-02 * "Some other conversion to be summarized"
              Assets:US:Checking             -3000.00 USD @ 1.25 CAD
              Assets:CA:Checking              3750.00 CAD

            2012-08-31 C "Conversion for -3000.00 USD, 3750.00 CAD"
              Equity:Conversions              3000.00 USD @ 0 NOTHING
              Equity:Conversions             -3750.00 CAD @ 0 NOTHING
            """
        )

        #expect(clamped.index == 7)
        #expect(!computeEntriesBalance(ledger.directives).isEmpty)
        #expect(computeEntriesBalance(clamped.entries).isEmpty)
    }

}

@Suite("TestCap")
struct TestCap {
    private static let input = """
        2014-01-01 open Income:Salary
        2014-01-01 open Expenses:Taxes
        2014-01-01 open Assets:US:Checking
        2014-01-01 open Assets:CA:Checking

        2014-03-01 * "Some income and expense"
          Income:Salary        10000.00 USD
          Expenses:Taxes        3500.00 USD
          Assets:US:Checking

        2014-02-01 * "Some conversion"
          Assets:US:Checking   -5000.00 USD @ 1.2 CAD
          Assets:CA:Checking    6000.00 CAD
        """

    @Test func cap() {
        let ledger = loadLedger(Self.input)
        #expect(ledger.errors.isEmpty)

        let capped = Summarize.cap(
            ledger.directives,
            accountTypes: ledger.options.accountNames,
            conversionCurrency: "NOTHING",
            accountEarnings: "Equity:Earnings",
            accountConversions: "Equity:Conversions"
        )

        assertIncludesEntries(Self.input, capped)
        assertIncludesEntries(
            """
            2014-03-01 T "Transfer balance for 'Expenses:Taxes' (Transfer balance)"
              Expenses:Taxes       -3500.00 USD
              Equity:Earnings       3500.00 USD

            2014-03-01 T "Transfer balance for 'Income:Salary' (Transfer balance)"
              Income:Salary       -10000.00 USD
              Equity:Earnings      10000.00 USD

            2014-03-01 C "Conversion for -5000.00 USD, 6000.00 CAD"
              Equity:Conversions    5000.00 USD @ 0 NOTHING
              Equity:Conversions   -6000.00 CAD @ 0 NOTHING
            """,
            capped
        )
        #expect(capped.count == 9)
    }

}

@Suite("TestTransferBalances")
struct TestTransferBalances {
    private static let inputPlugins = """
        option "plugin_processing_mode" "raw"
        """

    private static let inputOpen = """
        ;; These should be preserved after summarization.
        2010-01-01 open  Assets:US:Chase:Checking
        2010-01-01 open  Assets:US:Investing:HOOL
        2010-01-01 open  Assets:CA:BMO:Checking
        2010-01-01 open  Liabilities:US:Chase:CreditCard
        2010-01-01 open  Income:US:Employer:Salary
        2010-01-01 open  Expenses:Taxes
        2010-01-01 open  Expenses:Restaurant
        2010-01-01 open  Expenses:Flights
        2010-01-01 open  Expenses:Internet
        """

    private static let inputPricesRedundant = """
        ;; These prices are redundant; only the last price will be preserved after
        ;; summarization.
        2010-02-01 price USD  1.10 CAD
        2010-03-01 price USD  1.11 CAD
        2010-04-01 price USD  1.12 CAD
        2010-05-01 price USD  1.13 CAD
        2010-08-01 price USD  1.14 CAD
        2010-10-01 price USD  1.15 CAD
        """

    private static let inputPricesLast = """
        ;; This is the last price before the period, will be preserved.
        2010-12-01 price USD  1.16 CAD
        """

    private static let inputBefore = """
        ;; An account that gets capped before the period, should not appear in the
        ;; output.

        2010-01-01 open  Assets:US:Temporary
        2010-11-22 close  Assets:US:Temporary

        2010-11-16 *
          Income:US:Employer:Salary    -5000.00 USD
          Assets:US:Chase:Checking      3000.00 USD
          Expenses:Taxes                2000.00 USD

        2010-11-20 * "First hit on credit card account"
          Liabilities:US:Chase:CreditCard   -67.20 USD
          Expenses:Restaurant                67.20 USD

        2010-11-26 * "Second hit on credit card account (same account)"
          Liabilities:US:Chase:CreditCard   -345.23 USD
          Expenses:Flights                   345.23 USD

        2010-11-30 *
          Assets:US:Chase:Checking      -80.02 USD
          Expenses:Internet              80.02 USD

        2010-12-05 * "Unit held at cost"
          Assets:US:Investing:HOOL        5 HOOL {510.00 USD}
          Assets:US:Chase:Checking    -2550 USD

        2010-12-05 * "Conversion"
          Assets:US:Chase:Checking    -910.00 USD
          Assets:CA:BMO:Checking      1000.00 CAD @ 0.91 USD

        2010-12-16 *
          Income:US:Employer:Salary    -5000.00 USD
          Assets:US:Chase:Checking      3000.00 USD
          Expenses:Taxes                2000.00 USD
        """

    private static let inputPeriod = """
        2011-02-01 price USD  1.17 CAD
        2011-04-01 price USD  1.18 CAD

        2011-01-16 *
          Income:US:Employer:Salary    -5000.00 USD
          Assets:US:Chase:Checking      3000.00 USD
          Expenses:Taxes                2000.00 USD

        2011-01-20 * "Dinner at Cull & Pistol"
          Liabilities:US:Chase:CreditCard   -89.23 USD
          Expenses:Restaurant                89.23 USD

        2011-02-01 open  Assets:Cash

        2011-02-02 * "Cafe Mogador"
          Expenses:Restaurant      37.92 USD
          Assets:Cash             -37.92 USD

        2011-02-16 *
          Income:US:Employer:Salary    -5000.00 USD
          Assets:US:Chase:Checking      3000.00 USD
          Expenses:Taxes                2000.00 USD
        """

    private static let inputPeriodRemoved = """
        2011-03-15 balance Assets:US:Chase:Checking    8459.98 USD
        """

    private static let summarizeInput = [
        Self.inputPlugins,
        Self.inputOpen,
        Self.inputPricesRedundant,
        Self.inputPricesLast,
        Self.inputBefore,
        Self.inputPeriod,
        Self.inputPeriodRemoved,
    ].joined(separator: "\n\n")

    private static let summarizeInputWithoutBalance = [
        Self.inputOpen,
        Self.inputPricesRedundant,
        Self.inputPricesLast,
        Self.inputBefore,
        Self.inputPeriod,
    ].joined(separator: "\n\n")

    private static func fixture() -> [Directive<Cost>] {
        let ledger = loadLedger(Self.summarizeInput)
        return ledger.directives
    }

    @Test func transferBalancesEmpty() {
        let xferEntries = Summarize.transferBalances(
            [],
            date: "2011-01-01",
            accountPredicate: { $0.id.hasPrefix("Assets:US:Chase") },
            transferAccount: "Equity:Transfer"
        )
        #expect(xferEntries.isEmpty)
    }

    @Test func transferBalancesMiddleAssets() {
        let entries = Self.fixture()
        let date: Date = "2011-01-01"
        let xferEntries = Summarize.transferBalances(
            entries,
            date: date,
            accountPredicate: { $0.id.hasPrefix("Assets:US:Chase") },
            transferAccount: "Equity:Transfer"
        )

        assertIncludesEntries(
            Self.summarizeInputWithoutBalance,
            xferEntries
        )
        assertIncludesEntries(
            """
            2010-12-31 T "Transfer balance for 'Assets:US:Chase:Checking' (Transfer balance)"
              Assets:US:Chase:Checking                                             -2459.98 USD
              Equity:Transfer                                                       2459.98 USD
            """,
            xferEntries
        )
        #expect(xferEntries.count == entries.count)
    }

    @Test func transferBalancesMiddleAtCost() {
        let entries = Self.fixture()
        let date: Date = "2011-01-01"

        let xferEntries = Summarize.transferBalances(
            entries,
            date: date,
            accountPredicate: { $0.id.hasPrefix("Assets:US:Investing") },
            transferAccount: "Equity:Transfer"
        )

        assertIncludesEntries(Self.summarizeInput, xferEntries)
        assertIncludesEntries(
            """
            2010-12-31 T "Transfer balance for 'Assets:US:Investing:HOOL' (Transfer balance)"
              Assets:US:Investing:HOOL         -5 HOOL {510.00 USD, 2010-12-05}
              Equity:Transfer                2550.00 USD
            """,
            xferEntries
        )
        #expect(xferEntries.count == entries.count + 1)
    }

    @Test func transferBalancesEndAssetsImplicit() {
        let entries = Self.fixture()

        let xferEntries = Summarize.transferBalances(
            entries,
            date: "2011-03-01",
            accountPredicate: { $0.id.hasPrefix("Assets:US:Chase") },
            transferAccount: "Equity:Transfer"
        )

        assertIncludesEntries(
            Self.summarizeInputWithoutBalance,
            xferEntries
        )
        assertIncludesEntries(
            """
            2011-02-28 T "Transfer balance for 'Assets:US:Chase:Checking' (Transfer balance)"
              Assets:US:Chase:Checking                                             -8459.98 USD
              Equity:Transfer                                                       8459.98 USD
            """,
            xferEntries
        )
        #expect(xferEntries.count == entries.count)
    }

    @Test func transferBalancesEndAssetsExplicit() {
        let entries = Self.fixture()

        let xferEntries = Summarize.transferBalances(
            entries,
            date: nil,
            accountPredicate: { $0.id.hasPrefix("Assets:US:Chase") },
            transferAccount: "Equity:Transfer"
        )

        assertIncludesEntries(Self.summarizeInput, xferEntries)
        assertIncludesEntries(
            """
            2011-04-01 T "Transfer balance for 'Assets:US:Chase:Checking' (Transfer balance)"
              Assets:US:Chase:Checking                                             -8459.98 USD
              Equity:Transfer                                                       8459.98 USD
            """,
            xferEntries
        )
        #expect(xferEntries.count == entries.count + 1)
    }

    @Test func transferBalancesMiddleIncome() {
        let entries = Self.fixture()

        let xferEntries = Summarize.transferBalances(
            entries,
            date: "2011-01-01",
            accountPredicate: { account in
                account.id.hasPrefix("Income:") || account.id.hasPrefix("Expenses:")
            },
            transferAccount: "Equity:Transfer"
        )

        assertIncludesEntries(Self.summarizeInput, xferEntries)
        assertIncludesEntries(
            """
            2010-12-31 T "Transfer balance for 'Expenses:Flights' (Transfer balance)"
              Expenses:Flights                                                      -345.23 USD
              Equity:Transfer                                                        345.23 USD

            2010-12-31 T "Transfer balance for 'Expenses:Internet' (Transfer balance)"
              Expenses:Internet                                                      -80.02 USD
              Equity:Transfer                                                         80.02 USD

            2010-12-31 T "Transfer balance for 'Expenses:Restaurant' (Transfer balance)"
              Expenses:Restaurant                                                    -67.20 USD
              Equity:Transfer                                                         67.20 USD

            2010-12-31 T "Transfer balance for 'Expenses:Taxes' (Transfer balance)"
              Expenses:Taxes                                                       -4000.00 USD
              Equity:Transfer                                                       4000.00 USD

            2010-12-31 T "Transfer balance for 'Income:US:Employer:Salary' (Transfer balance)"
              Income:US:Employer:Salary                                            10000.00 USD
              Equity:Transfer                                                     -10000.00 USD
            """,
            xferEntries
        )
        #expect(xferEntries.count == entries.count + 5)
    }

}

@Suite("TestSummarize")
struct TestSummarize {
    private static let inputPlugins = """
        option "plugin_processing_mode" "raw"
        """

    private static let inputOpen = """
        ;; These should be preserved after summarization.
        2010-01-01 open  Assets:US:Chase:Checking
        2010-01-01 open  Assets:US:Investing:HOOL
        2010-01-01 open  Assets:CA:BMO:Checking
        2010-01-01 open  Liabilities:US:Chase:CreditCard
        2010-01-01 open  Income:US:Employer:Salary
        2010-01-01 open  Expenses:Taxes
        2010-01-01 open  Expenses:Restaurant
        2010-01-01 open  Expenses:Flights
        2010-01-01 open  Expenses:Internet
        """

    private static let inputPricesRedundant = """
        ;; These prices are redundant; only the last price will be preserved after
        ;; summarization.
        2010-02-01 price USD  1.10 CAD
        2010-03-01 price USD  1.11 CAD
        2010-04-01 price USD  1.12 CAD
        2010-05-01 price USD  1.13 CAD
        2010-08-01 price USD  1.14 CAD
        2010-10-01 price USD  1.15 CAD
        """

    private static let inputPricesLast = """
        ;; This is the last price before the period, will be preserved.
        2010-12-01 price USD  1.16 CAD
        """

    private static let inputBefore = """
        ;; An account that gets capped before the period, should not appear in the
        ;; output.

        2010-01-01 open  Assets:US:Temporary
        2010-11-22 close  Assets:US:Temporary

        2010-11-16 *
          Income:US:Employer:Salary    -5000.00 USD
          Assets:US:Chase:Checking      3000.00 USD
          Expenses:Taxes                2000.00 USD

        2010-11-20 * "First hit on credit card account"
          Liabilities:US:Chase:CreditCard   -67.20 USD
          Expenses:Restaurant                67.20 USD

        2010-11-26 * "Second hit on credit card account (same account)"
          Liabilities:US:Chase:CreditCard   -345.23 USD
          Expenses:Flights                   345.23 USD

        2010-11-30 *
          Assets:US:Chase:Checking      -80.02 USD
          Expenses:Internet              80.02 USD

        2010-12-05 * "Unit held at cost"
          Assets:US:Investing:HOOL        5 HOOL {510.00 USD}
          Assets:US:Chase:Checking    -2550 USD

        2010-12-05 * "Conversion"
          Assets:US:Chase:Checking    -910.00 USD
          Assets:CA:BMO:Checking      1000.00 CAD @ 0.91 USD

        2010-12-16 *
          Income:US:Employer:Salary    -5000.00 USD
          Assets:US:Chase:Checking      3000.00 USD
          Expenses:Taxes                2000.00 USD
        """

    private static let inputPeriod = """
        2011-02-01 price USD  1.17 CAD
        2011-04-01 price USD  1.18 CAD

        2011-01-16 *
          Income:US:Employer:Salary    -5000.00 USD
          Assets:US:Chase:Checking      3000.00 USD
          Expenses:Taxes                2000.00 USD

        2011-01-20 * "Dinner at Cull & Pistol"
          Liabilities:US:Chase:CreditCard   -89.23 USD
          Expenses:Restaurant                89.23 USD

        2011-02-01 open  Assets:Cash

        2011-02-02 * "Cafe Mogador"
          Expenses:Restaurant      37.92 USD
          Assets:Cash             -37.92 USD

        2011-02-16 *
          Income:US:Employer:Salary    -5000.00 USD
          Assets:US:Chase:Checking      3000.00 USD
          Expenses:Taxes                2000.00 USD
        """

    private static let inputPeriodRemoved = """
        2011-03-15 balance Assets:US:Chase:Checking    8459.98 USD
        """

    private static let summarizeInput = [
        Self.inputPlugins,
        Self.inputOpen,
        Self.inputPricesRedundant,
        Self.inputPricesLast,
        Self.inputBefore,
        Self.inputPeriod,
        Self.inputPeriodRemoved,
    ].joined(separator: "\n\n")

    private static func fixture() -> [Directive<Cost>] {
        let ledger = loadLedger(Self.summarizeInput)
        return ledger.directives
    }

    @Test func summarizeComplete() {
        let entries = Self.fixture()
        let summarizeDate: Date = "2011-01-01"

        let summarized = Summarize.summarize(
            entries,
            date: summarizeDate,
            accountOpening: "Equity:Opening-Balances"
        )

        assertIncludesEntries(Self.inputOpen, summarized.entries)
        assertExcludesEntries(Self.inputBefore, summarized.entries)
        assertExcludesEntries(Self.inputPricesRedundant, summarized.entries)
        assertIncludesEntries(Self.inputPricesLast, summarized.entries)
        assertIncludesEntries(Self.inputPeriod, summarized.entries)

        let summarizingEntries = summarized.entries.filter { directive in
            if case .transaction(let txn) = directive.content {
                return txn.flag == .summarizeFlag
            }
            return false
        }
        assertEqualEntries(
            summarizingEntries,
            """
            2010-12-31 S "Opening balance for 'Assets:CA:BMO:Checking' (Summarization)"
              Assets:CA:BMO:Checking                                                1000.00 CAD
              Equity:Opening-Balances                                              -1000.00 CAD

            2010-12-31 S "Opening balance for 'Assets:US:Chase:Checking' (Summarization)"
              Assets:US:Chase:Checking                                              2459.98 USD
              Equity:Opening-Balances                                              -2459.98 USD

            2010-12-31 S "Opening balance for 'Assets:US:Investing:HOOL' (Summarization)"
              Assets:US:Investing:HOOL                                                5 HOOL {510.00 USD, 2010-12-05}
              Equity:Opening-Balances                                              -2550.00 USD

            2010-12-31 S "Opening balance for 'Expenses:Flights' (Summarization)"
              Expenses:Flights                                                       345.23 USD
              Equity:Opening-Balances                                               -345.23 USD

            2010-12-31 S "Opening balance for 'Expenses:Internet' (Summarization)"
              Expenses:Internet                                                       80.02 USD
              Equity:Opening-Balances                                                -80.02 USD

            2010-12-31 S "Opening balance for 'Expenses:Restaurant' (Summarization)"
              Expenses:Restaurant                                                     67.20 USD
              Equity:Opening-Balances                                                -67.20 USD

            2010-12-31 S "Opening balance for 'Expenses:Taxes' (Summarization)"
              Expenses:Taxes                                                        4000.00 USD
              Equity:Opening-Balances                                              -4000.00 USD

            2010-12-31 S "Opening balance for 'Income:US:Employer:Salary' (Summarization)"
              Income:US:Employer:Salary                                           -10000.00 USD
              Equity:Opening-Balances                                              10000.00 USD

            2010-12-31 S "Opening balance for 'Liabilities:US:Chase:CreditCard' (Summarization)"
              Liabilities:US:Chase:CreditCard                                       -412.43 USD
              Equity:Opening-Balances                                                412.43 USD
            """
        )

        let beforeTxns = summarized.entries.prefix(summarized.index).compactMap {
            entry -> Transaction<Cost>? in
            if case .transaction(let txn) = entry.content {
                return txn
            }
            return nil
        }
        #expect(beforeTxns.allSatisfy { $0.flag == .summarizeFlag })
        #expect(
            Array(summarized.entries.prefix(summarized.index)).allSatisfy {
                $0.date < summarizeDate
            })

        let afterTxns = summarized.entries.suffix(from: summarized.index).compactMap {
            entry -> Transaction<Cost>? in
            if case .transaction(let txn) = entry.content {
                return txn
            }
            return nil
        }
        #expect(afterTxns.allSatisfy { $0.flag != .summarizeFlag })
        #expect(
            Array(summarized.entries.suffix(from: summarized.index)).allSatisfy {
                $0.date >= summarizeDate
            })
    }

    @Test func summarizeOrderingNonTransactions() {
        let entries = loadDirectives(
            """
            2016-01-15 price HOOL    123.45 USD

            2016-02-01 open Assets:Invest:Cash
            2016-02-01 open Assets:Invest:HOOL

            2016-02-16 *
              Assets:Invest:HOOL    10 HOOL {143.45 USD}
              Assets:Invest:Cash

            2016-04-01 *
              Assets:Invest:HOOL      2 HOOL {156.32 USD}
              Assets:Invest:Cash
            """
        )

        let summarized = Summarize.summarize(
            entries,
            date: "2016-03-01",
            accountOpening: "Equity:Opening-Balances"
        )

        #expect(isSortedByDate(summarized.entries))
    }

}

@Suite("TestConversions")
struct TestConversions {
    private static let input = """
        2012-01-01 open Income:US:Job
        2012-01-01 open Assets:US:Checking
        2012-01-01 open Assets:CA:Invest
        2012-01-01 open Assets:CA:Invest:NT

        2012-03-01 * "Earn some money"
          Income:US:Job            -1000.00 USD
          Assets:US:Checking        1000.00 USD

        2012-03-02 * "Transfer to Investment"
          Assets:US:Checking       -800.00 USD
          Assets:CA:Invest          800.00 CAD @ 1 USD

        2012-03-03 * "Buy some stock"
          Assets:CA:Invest         -600.00 CAD
          Assets:CA:Invest:NT        60 NT {10 CAD}

        2012-05-01 * "Transfer some money back"
          Assets:CA:Invest         -100.00 CAD @ 1 USD
          Assets:US:Checking        100.00 USD
        """

    @Test func conversionsEmpty() {
        let entries = loadDirectives(Self.input)
        let date: Date = "2012-02-01"
        let conversionEntries = Summarize.conversions(
            entries,
            conversionAccount: "Equity:Conversions",
            conversionCurrency: "NOTHING",
            date: date
        )
        assertEqualEntries(entries, conversionEntries)
        #expect(computeEntriesCostBalance(conversionEntries, date: date).isEmpty)
    }

    @Test func conversionsNotNeeded() {
        let entries = loadDirectives(Self.input)
        let date: Date = "2012-03-02"
        let conversionEntries = Summarize.conversions(
            entries,
            conversionAccount: "Equity:Conversions",
            conversionCurrency: "NOTHING",
            date: date
        )
        assertEqualEntries(entries, conversionEntries)
        #expect(computeEntriesCostBalance(conversionEntries, date: date).isEmpty)
    }

    @Test func conversionsNeededMiddle() {
        let entries = loadDirectives(Self.input)
        let date: Date = "2012-03-03"
        let conversionEntries = Summarize.conversions(
            entries,
            conversionAccount: "Equity:Conversions",
            conversionCurrency: "NOTHING",
            date: date
        )

        assertIncludesEntries(Self.input, conversionEntries)
        assertIncludesEntries(
            """
            2012-03-02 C "Conversion for -800.00 USD, 800.00 CAD"
              Equity:Conversions       800.00 USD @ 0 NOTHING
              Equity:Conversions      -800.00 CAD @ 0 NOTHING
            """,
            conversionEntries
        )
        #expect(computeEntriesCostBalance(conversionEntries, date: date).isEmpty)
    }

    @Test func conversionsWithTransactionsAtCost() {
        let entries = loadDirectives(Self.input)
        let date: Date = "2012-03-10"
        let conversionEntries = Summarize.conversions(
            entries,
            conversionAccount: "Equity:Conversions",
            conversionCurrency: "XFER",
            date: date
        )

        assertIncludesEntries(Self.input, conversionEntries)
        assertIncludesEntries(
            """
            2012-03-09 C "Conversion for -800.00 USD, 200.00 CAD, 60 NT {10.00 CAD, 2012-03-03}"
              Equity:Conversions   800.00 USD @ 0 XFER
              Equity:Conversions  -800.00 CAD @ 0 XFER
            """,
            conversionEntries
        )
        #expect(computeEntriesCostBalance(conversionEntries, date: date).isEmpty)
    }

    @Test func conversionsMultiple() {
        let entries = loadDirectives(Self.input)
        let date: Date = "2012-05-10"
        let conversionEntries = Summarize.conversions(
            entries,
            conversionAccount: "Equity:Conversions",
            conversionCurrency: "NOTHING",
            date: date
        )

        assertIncludesEntries(Self.input, conversionEntries)
        assertIncludesEntries(
            """
            2012-05-09 C "Conversion for -700.00 USD, 100.00 CAD, 60 NT {10.00 CAD, 2012-03-03}"
              Equity:Conversions   700.00 USD @ 0 NOTHING
              Equity:Conversions  -700.00 CAD @ 0 NOTHING
            """,
            conversionEntries
        )
        #expect(computeEntriesCostBalance(conversionEntries).isEmpty)
    }

    @Test func conversionsNoDate() {
        let entries = loadDirectives(Self.input)
        let conversionEntries = Summarize.conversions(
            entries,
            conversionAccount: "Equity:Conversions",
            conversionCurrency: "NOTHING"
        )

        assertIncludesEntries(Self.input, conversionEntries)
        assertIncludesEntries(
            """
            2012-05-01 C "Conversion for -700.00 USD, 100.00 CAD, 60 NT {10.00 CAD, 2012-03-03}"
              Equity:Conversions   700.00 USD @ 0 NOTHING
              Equity:Conversions  -700.00 CAD @ 0 NOTHING
            """,
            conversionEntries
        )
        #expect(computeEntriesCostBalance(conversionEntries).isEmpty)
    }

    @Test func conversionsNonEmptyButEmptyCost() {
        let entries = loadDirectives(
            """
            2012-01-01 open Assets:Checking
            2012-01-01 open Assets:Invest

            2012-03-01 *
              Assets:Checking        -800.00 USD
              Assets:Invest           40 HOOL {20.00 USD}
            """
        )

        let conversionEntries = Summarize.conversions(
            entries,
            conversionAccount: "Equity:Conversions",
            conversionCurrency: "XFER"
        )
        assertEqualEntries(entries, conversionEntries)
        #expect(computeEntriesCostBalance(entries).isEmpty)
    }

}

@Suite("TestTruncate")
struct TestTruncate {
    private static let input = """
        2014-01-01 open Assets:US:Bank:Checking
        2014-01-01 open Equity:Opening-Balances

        2014-03-10 * "A"
          Assets:US:Bank:Checking   1 USD
          Equity:Opening-Balances  -1 USD

        2014-03-11 * "B"
          Assets:US:Bank:Checking   1 USD
          Equity:Opening-Balances  -1 USD

        2014-03-12 * "C"
          Assets:US:Bank:Checking   1 USD
          Equity:Opening-Balances  -1 USD

        2014-03-13 * "D1"
          Assets:US:Bank:Checking   1 USD
          Equity:Opening-Balances  -1 USD

        2014-03-13 * "D2"
          Assets:US:Bank:Checking   1 USD
          Equity:Opening-Balances  -1 USD

        2014-03-14 * "E"
          Assets:US:Bank:Checking   1 USD
          Equity:Opening-Balances  -1 USD
        """

    @Test func truncateBefore() {
        let entries = loadDirectives(Self.input)
        let truncatedEntries = Summarize.truncate(entries, date: "2014-02-15")
        assertEqualEntries(
            truncatedEntries,
            """
            2014-01-01 open Assets:US:Bank:Checking
            2014-01-01 open Equity:Opening-Balances
            """
        )
    }

    @Test func truncateNormal1() {
        let entries = loadDirectives(Self.input)
        let truncatedEntries = Summarize.truncate(entries, date: "2014-03-13")
        assertEqualEntries(
            truncatedEntries,
            """
            2014-01-01 open Assets:US:Bank:Checking
            2014-01-01 open Equity:Opening-Balances

            2014-03-10 * "A"
              Assets:US:Bank:Checking   1 USD
              Equity:Opening-Balances  -1 USD

            2014-03-11 * "B"
              Assets:US:Bank:Checking   1 USD
              Equity:Opening-Balances  -1 USD

            2014-03-12 * "C"
              Assets:US:Bank:Checking   1 USD
              Equity:Opening-Balances  -1 USD
            """
        )
    }

    @Test func truncateNormal2() {
        let entries = loadDirectives(Self.input)
        let truncatedEntries = Summarize.truncate(entries, date: "2014-03-14")
        assertEqualEntries(
            truncatedEntries,
            """
            2014-01-01 open Assets:US:Bank:Checking
            2014-01-01 open Equity:Opening-Balances

            2014-03-10 * "A"
              Assets:US:Bank:Checking   1 USD
              Equity:Opening-Balances  -1 USD

            2014-03-11 * "B"
              Assets:US:Bank:Checking   1 USD
              Equity:Opening-Balances  -1 USD

            2014-03-12 * "C"
              Assets:US:Bank:Checking   1 USD
              Equity:Opening-Balances  -1 USD

            2014-03-13 * "D1"
              Assets:US:Bank:Checking   1 USD
              Equity:Opening-Balances  -1 USD

            2014-03-13 * "D2"
              Assets:US:Bank:Checking   1 USD
              Equity:Opening-Balances  -1 USD
            """
        )
    }

    @Test func truncateAfter() {
        let entries = loadDirectives(Self.input)
        let truncatedEntries = Summarize.truncate(entries, date: "2014-03-15")
        assertEqualEntries(entries, truncatedEntries)
    }

}

@Suite("TestEntriesFromBalance")
struct TestEntriesFromBalance {
    @Test func createEntriesFromBalancesEmpty() {
        let entries = Summarize.createEntriesFromBalances(
            ["Assets:US:Bank:Empty": Inventory()],
            date: Date.now,
            sourceAccount: "Equity:Opening-Balances",
            direction: true,
            meta: Summarize.meta("<test>", 0),
            flag: "!",
            narrationTemplate: "narration"
        )
        #expect(entries.isEmpty)
    }

    @Test func createEntriesFromBalancesSimple() {
        let balances: [Account: Inventory] = [
            "Assets:US:Investment": "10 HOOL {500.00 USD, 2014-01-01}",
            "Assets:US:Bank:Checking": "1823.23 USD",
        ]

        let entries = Summarize.createEntriesFromBalances(
            balances,
            date: "2014-01-01",
            sourceAccount: "Equity:Opening-Balances",
            direction: true,
            meta: Summarize.meta("<test>", 0),
            flag: "!",
            narrationTemplate: "Narration for {account} at {date}"
        )
        assertEqualEntries(
            entries,
            """
            2014-01-01 ! "Narration for Assets:US:Bank:Checking at 2014-01-01"
              Assets:US:Bank:Checking                                               1823.23 USD
              Equity:Opening-Balances                                               -1823.23 USD

            2014-01-01 ! "Narration for Assets:US:Investment at 2014-01-01"
              Assets:US:Investment                                                   10 HOOL {500.00 USD, 2014-01-01}
              Equity:Opening-Balances                                               -5000.00 USD
            """
        )
    }

    @Test func createEntriesFromBalancesReverse() {
        let balances: [Account: Inventory] = [
            "Assets:US:Investment": "10 HOOL {500.00 USD, 2014-01-01}",
            "Assets:US:Bank:Checking": "1823.23 USD",
        ]

        let entries = Summarize.createEntriesFromBalances(
            balances,
            date: "2014-01-01",
            sourceAccount: "Equity:Opening-Balances",
            direction: false,
            meta: Summarize.meta("<test>", 0),
            flag: "*",
            narrationTemplate: "Narration for {account} at {date}"
        )
        assertEqualEntries(
            entries,
            """
            2014-01-01 * "Narration for Assets:US:Bank:Checking at 2014-01-01"
              Assets:US:Bank:Checking                                              -1823.23 USD
              Equity:Opening-Balances                                                1823.23 USD

            2014-01-01 * "Narration for Assets:US:Investment at 2014-01-01"
              Assets:US:Investment                                                  -10 HOOL {500.00 USD, 2014-01-01}
              Equity:Opening-Balances                                                5000.00 USD
            """
        )
    }

}

@Suite("TestBalanceByAccount")
struct TestBalanceByAccount {
    private static let input = """
        2001-01-01 open Assets:AccountA
        2001-01-01 open Assets:AccountB
        2001-01-01 open Equity:Opening-Balances

        2014-02-01 *
          Assets:AccountA   10 USD
          Equity:Opening-Balances

        2014-03-01 *
          Assets:AccountA   1 USD
          Assets:AccountB  12 USD
          Equity:Opening-Balances
        """

    @Test func balanceByAccountNoEndDate() {
        let entries = loadDirectives(Self.input)
        let result = Summarize.balanceByAccount(entries)
        #expect(result.index == entries.count)
        #expect(
            result.balances
                == [
                    "Assets:AccountA": "11 USD",
                    "Equity:Opening-Balances": "-23 USD",
                    "Assets:AccountB": "12 USD",
                ])
    }

    @Test func balanceByAccountFirstDate() {
        let entries = loadDirectives(Self.input)
        let result = Summarize.balanceByAccount(entries, date: "2014-02-01")
        #expect(result.index == 3)
        #expect(result.balances.isEmpty)
    }

    @Test func balanceByAccountMiddle() {
        let entries = loadDirectives(Self.input)
        let result = Summarize.balanceByAccount(entries, date: "2014-02-10")
        #expect(result.index == 4)
        #expect(
            result.balances
                == [
                    "Assets:AccountA": "10 USD",
                    "Equity:Opening-Balances": "-10 USD",
                ])
    }

}

@Suite("TestOpenAtDate")
struct TestOpenAtDate {
    private static let input = """
        2011-01-01 open Assets:AccountA
        2011-02-01 open Assets:AccountB
        2011-03-01 open Assets:AccountC

        2011-03-15 close Assets:AccountA

        2011-04-01 open Assets:AccountD
        2011-05-01 open Assets:AccountE
        2011-06-01 open Assets:AccountF
        2011-07-01 open Assets:AccountG
        2011-08-01 open Assets:AccountH
        2011-09-01 open Assets:AccountI
        2011-10-01 open Assets:AccountJ
        2011-11-01 open Assets:AccountK
        2011-12-01 open Assets:AccountL

        2012-07-01 close Assets:AccountG
        2012-07-01 close Assets:AccountH
        2012-07-01 close Assets:AccountI
        2012-07-01 close Assets:AccountJ
        2012-07-01 close Assets:AccountK
        2012-07-01 close Assets:AccountL
        """

    @Test func getOpenEntriesBefore() {
        let entries = loadDirectives(Self.input)
        assertEqualEntries(
            Summarize.getOpenEntries(entries, date: "2010-12-01"),
            ""
        )
    }

    @Test func getOpenEntriesFirstEntryOpen() {
        let entries = loadDirectives(Self.input)
        assertEqualEntries(
            Summarize.getOpenEntries(entries, date: "2011-01-01"),
            ""
        )
    }

    @Test func getOpenEntriesAfterFirstEntryOpen() {
        let entries = loadDirectives(Self.input)
        assertEqualEntries(
            Summarize.getOpenEntries(entries, date: "2011-01-02"),
            "2011-01-01 open Assets:AccountA"
        )
    }

    @Test func getOpenEntriesFirstClose() {
        let entries = loadDirectives(Self.input)
        assertEqualEntries(
            Summarize.getOpenEntries(entries, date: "2011-03-15"),
            """
            2011-01-01 open Assets:AccountA
            2011-02-01 open Assets:AccountB
            2011-03-01 open Assets:AccountC
            """
        )
    }

    @Test func getOpenEntriesAfterFirstClose() {
        let entries = loadDirectives(Self.input)
        assertEqualEntries(
            Summarize.getOpenEntries(entries, date: "2011-03-16"),
            """
            2011-02-01 open Assets:AccountB
            2011-03-01 open Assets:AccountC
            """
        )
    }

    @Test func getOpenEntriesAfterNewOpens() {
        let entries = loadDirectives(Self.input)
        assertEqualEntries(
            Summarize.getOpenEntries(entries, date: "2011-05-03"),
            """
            2011-02-01 open Assets:AccountB
            2011-03-01 open Assets:AccountC
            2011-04-01 open Assets:AccountD
            2011-05-01 open Assets:AccountE
            """
        )
    }

    @Test func getOpenEntriesAfterAllOpens() {
        let entries = loadDirectives(Self.input)
        assertEqualEntries(
            Summarize.getOpenEntries(entries, date: "2012-01-01"),
            """
            2011-02-01 open Assets:AccountB
            2011-03-01 open Assets:AccountC
            2011-04-01 open Assets:AccountD
            2011-05-01 open Assets:AccountE
            2011-06-01 open Assets:AccountF
            2011-07-01 open Assets:AccountG
            2011-08-01 open Assets:AccountH
            2011-09-01 open Assets:AccountI
            2011-10-01 open Assets:AccountJ
            2011-11-01 open Assets:AccountK
            2011-12-01 open Assets:AccountL
            """
        )
    }

    @Test func getOpenEntriesAfterAllEntries() {
        let entries = loadDirectives(Self.input)
        assertEqualEntries(
            Summarize.getOpenEntries(entries, date: "2013-01-01"),
            """
            2011-02-01 open Assets:AccountB
            2011-03-01 open Assets:AccountC
            2011-04-01 open Assets:AccountD
            2011-05-01 open Assets:AccountE
            2011-06-01 open Assets:AccountF
            """
        )
    }

    @Test func getOpenEntriesDuplicateOpen() {
        let entries = loadDirectives(
            """
            2011-01-01 open Assets:AccountA
            2011-02-01 open Assets:AccountA
            """
        )
        assertEqualEntries(
            Summarize.getOpenEntries(entries, date: "2013-01-01"),
            "2011-01-01 open Assets:AccountA"
        )
    }

    @Test func getOpenEntriesClosedTwice() {
        let entries = loadDirectives(
            """
            2011-01-01 open  Assets:AccountA
            2011-02-01 close Assets:AccountA
            2011-02-02 close Assets:AccountA
            """
        )
        assertEqualEntries(Summarize.getOpenEntries(entries, date: "2013-01-01"), "")
    }

    @Test func getOpenEntriesClosedWithoutOpen() {
        let entries = loadDirectives("2011-02-02 close Assets:AccountA")
        assertEqualEntries(Summarize.getOpenEntries(entries, date: "2013-01-01"), "")
    }
}
