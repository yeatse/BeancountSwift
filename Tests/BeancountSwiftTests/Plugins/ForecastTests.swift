//
//  ForecastTests.swift
//
//
//  Created by Yeatse on 2024/1/28.
//

import Testing
@testable import BeancountSwift

/// Comprehensive test suite for the ForecastPlugin functionality.
///
/// Tests cover various forecasting scenarios including:
/// - Basic monthly/yearly/weekly/daily recurring transactions
/// - SKIP functionality for non-consecutive intervals
/// - REPEAT functionality with count limits
/// - UNTIL functionality with end dates
/// - Error handling for invalid patterns
/// - Edge cases and boundary conditions
struct ForecastTests {

    /// Test basic monthly forecast functionality
    @Test func monthlyForecast() throws {
        let p: ContentProvider =
        """
        plugin "beanlabs.plugins.forecast"
        
        2011-01-01 open Expenses:Restaurant
        2011-01-01 open Assets:Cash

        2011-05-17 # "Something [MONTHLY UNTIL 2011-12-31]"
          Expenses:Restaurant   50.02 USD
          Assets:Cash
        """

        let ledger = try p.loadLedger()

        assertEqualEntries(ledger.directives,
        """
        2011-01-01 open Expenses:Restaurant
        2011-01-01 open Assets:Cash

        2011-05-17 # "Something"
          Expenses:Restaurant   50.02 USD
          Assets:Cash          -50.02 USD

        2011-06-17 # "Something"
          Expenses:Restaurant   50.02 USD
          Assets:Cash          -50.02 USD

        2011-07-17 # "Something"
          Expenses:Restaurant   50.02 USD
          Assets:Cash          -50.02 USD

        2011-08-17 # "Something"
          Expenses:Restaurant   50.02 USD
          Assets:Cash          -50.02 USD

        2011-09-17 # "Something"
          Expenses:Restaurant   50.02 USD
          Assets:Cash          -50.02 USD

        2011-10-17 # "Something"
          Expenses:Restaurant   50.02 USD
          Assets:Cash          -50.02 USD

        2011-11-17 # "Something"
          Expenses:Restaurant   50.02 USD
          Assets:Cash          -50.02 USD

        2011-12-17 # "Something"
          Expenses:Restaurant   50.02 USD
          Assets:Cash          -50.02 USD
        """)
    }

    /// Test yearly forecast with repeat count
    @Test func yearlyForecastWithRepeat() throws {
        let p: ContentProvider =
        """
        plugin "beanlabs.plugins.forecast"

        2011-01-01 open Expenses:Insurance
        2011-01-01 open Assets:Cash

        2014-03-08 # "Insurance premium [YEARLY REPEAT 3 TIMES]"
          Expenses:Insurance   500.00 USD
          Assets:Cash
        """

        let ledger = try p.loadLedger()

        assertEqualEntries(ledger.directives,
        """
        2011-01-01 open Expenses:Insurance
        2011-01-01 open Assets:Cash

        2014-03-08 # "Insurance premium"
          Expenses:Insurance   500.00 USD
          Assets:Cash          -500.00 USD

        2015-03-08 # "Insurance premium"
          Expenses:Insurance   500.00 USD
          Assets:Cash          -500.00 USD

        2016-03-08 # "Insurance premium"
          Expenses:Insurance   500.00 USD
          Assets:Cash          -500.00 USD
        """)
    }

    /// Test weekly forecast with skip functionality
    @Test func weeklyForecastWithSkip() throws {
        let p: ContentProvider =
        """
        plugin "beanlabs.plugins.forecast"

        2011-01-01 open Expenses:Groceries
        2011-01-01 open Assets:Cash

        2014-01-06 # "Biweekly groceries [WEEKLY SKIP 1 TIME REPEAT 4 TIMES]"
          Expenses:Groceries   75.00 USD
          Assets:Cash
        """

        let ledger = try p.loadLedger()

        assertEqualEntries(ledger.directives,
        """
        2011-01-01 open Expenses:Groceries
        2011-01-01 open Assets:Cash

        2014-01-06 # "Biweekly groceries"
          Expenses:Groceries   75.00 USD
          Assets:Cash          -75.00 USD

        2014-01-20 # "Biweekly groceries"
          Expenses:Groceries   75.00 USD
          Assets:Cash          -75.00 USD

        2014-02-03 # "Biweekly groceries"
          Expenses:Groceries   75.00 USD
          Assets:Cash          -75.00 USD

        2014-02-17 # "Biweekly groceries"
          Expenses:Groceries   75.00 USD
          Assets:Cash          -75.00 USD
        """)
    }

    /// Test daily forecast functionality
    @Test func dailyForecast() throws {
        let p: ContentProvider =
        """
        plugin "beanlabs.plugins.forecast"

        2011-01-01 open Expenses:Coffee
        2011-01-01 open Assets:Cash

        2014-01-01 # "Daily coffee [DAILY REPEAT 5 TIMES]"
          Expenses:Coffee   3.50 USD
          Assets:Cash
        """

        let ledger = try p.loadLedger()

        assertEqualEntries(ledger.directives,
        """
        2011-01-01 open Expenses:Coffee
        2011-01-01 open Assets:Cash

        2014-01-01 # "Daily coffee"
          Expenses:Coffee   3.50 USD
          Assets:Cash       -3.50 USD

        2014-01-02 # "Daily coffee"
          Expenses:Coffee   3.50 USD
          Assets:Cash       -3.50 USD

        2014-01-03 # "Daily coffee"
          Expenses:Coffee   3.50 USD
          Assets:Cash       -3.50 USD

        2014-01-04 # "Daily coffee"
          Expenses:Coffee   3.50 USD
          Assets:Cash       -3.50 USD

        2014-01-05 # "Daily coffee"
          Expenses:Coffee   3.50 USD
          Assets:Cash       -3.50 USD
        """)
    }

    /// Test that transactions without forecast patterns remain unchanged
    @Test func nonForecastTransactions() throws {
        let p: ContentProvider =
        """
        plugin "beanlabs.plugins.forecast"

        2011-01-01 open Expenses:Restaurant
        2011-01-01 open Assets:Cash

        2011-05-17 * "Regular transaction"
          Expenses:Restaurant   25.00 USD
          Assets:Cash          -25.00 USD

        2011-06-01 ! "Another regular transaction"
          Expenses:Restaurant   30.00 USD
          Assets:Cash          -30.00 USD
        """

        let ledger = try p.loadLedger()

        // Should remain exactly the same
        assertEqualEntries(ledger.directives,
        """
        2011-01-01 open Expenses:Restaurant
        2011-01-01 open Assets:Cash

        2011-05-17 * "Regular transaction"
          Expenses:Restaurant   25.00 USD
          Assets:Cash          -25.00 USD

        2011-06-01 ! "Another regular transaction"
          Expenses:Restaurant   30.00 USD
          Assets:Cash          -30.00 USD
        """)
    }

    /// Test complex forecast with multiple postings
    @Test func complexForecastMultiplePostings() throws {
        let p: ContentProvider =
        """
        plugin "beanlabs.plugins.forecast"

        2011-01-01 open Expenses:Rent
        2011-01-01 open Expenses:Utils
        2011-01-01 open Assets:Checking

        2014-01-01 # "Monthly rent and utilities [MONTHLY REPEAT 3 TIMES]"
          Expenses:Rent      1200.00 USD
          Expenses:Utils      150.00 USD
          Assets:Checking
        """

        let ledger = try p.loadLedger()

        assertEqualEntries(ledger.directives,
        """
        2011-01-01 open Expenses:Rent
        2011-01-01 open Expenses:Utils
        2011-01-01 open Assets:Checking

        2014-01-01 # "Monthly rent and utilities"
          Expenses:Rent      1200.00 USD
          Expenses:Utils      150.00 USD
          Assets:Checking    -1350.00 USD

        2014-02-01 # "Monthly rent and utilities"
          Expenses:Rent      1200.00 USD
          Expenses:Utils      150.00 USD
          Assets:Checking    -1350.00 USD

        2014-03-01 # "Monthly rent and utilities"
          Expenses:Rent      1200.00 USD
          Expenses:Utils      150.00 USD
          Assets:Checking    -1350.00 USD
        """)
    }

    /// Test forecast with tags and links preservation
    @Test func forecastWithTagsAndLinks() throws {
        let p: ContentProvider =
        """
        plugin "beanlabs.plugins.forecast"

        2011-01-01 open Expenses:Gym
        2011-01-01 open Assets:Cash

        2014-01-01 # "Gym membership [MONTHLY REPEAT 2 TIMES]" #health ^gym-membership
          Expenses:Gym   45.00 USD
          Assets:Cash
        """

        let ledger = try p.loadLedger()

        assertEqualEntries(ledger.directives,
        """
        2011-01-01 open Expenses:Gym
        2011-01-01 open Assets:Cash

        2014-01-01 # "Gym membership" #health ^gym-membership
          Expenses:Gym   45.00 USD
          Assets:Cash    -45.00 USD

        2014-02-01 # "Gym membership" #health ^gym-membership
          Expenses:Gym   45.00 USD
          Assets:Cash    -45.00 USD
        """)
    }

    /// Test empty narration handling
    @Test func emptyNarration() throws {
        let p: ContentProvider =
        """
        plugin "beanlabs.plugins.forecast"

        2011-01-01 open Expenses:Misc
        2011-01-01 open Assets:Cash

        2014-01-01 # " [MONTHLY REPEAT 2 TIMES]"
          Expenses:Misc   10.00 USD
          Assets:Cash
        """

        let ledger = try p.loadLedger()

        assertEqualEntries(ledger.directives,
        """
        2011-01-01 open Expenses:Misc
        2011-01-01 open Assets:Cash

        2014-01-01 #
          Expenses:Misc   10.00 USD
          Assets:Cash     -10.00 USD

        2014-02-01 #
          Expenses:Misc   10.00 USD
          Assets:Cash     -10.00 USD
        """)
    }

    /// Test forecast with skip and multiple times
    @Test func complexSkipPattern() throws {
        let p: ContentProvider =
        """
        plugin "beanlabs.plugins.forecast"

        2011-01-01 open Expenses:Subscription
        2011-01-01 open Assets:Cash

        2014-01-01 # "Quarterly subscription [MONTHLY SKIP 2 TIMES REPEAT 4 TIMES]"
          Expenses:Subscription   99.99 USD
          Assets:Cash
        """

        let ledger = try p.loadLedger()

        assertEqualEntries(ledger.directives,
        """
        2011-01-01 open Expenses:Subscription
        2011-01-01 open Assets:Cash

        2014-01-01 # "Quarterly subscription"
          Expenses:Subscription   99.99 USD
          Assets:Cash             -99.99 USD

        2014-04-01 # "Quarterly subscription"
          Expenses:Subscription   99.99 USD
          Assets:Cash             -99.99 USD

        2014-07-01 # "Quarterly subscription"
          Expenses:Subscription   99.99 USD
          Assets:Cash             -99.99 USD

        2014-10-01 # "Quarterly subscription"
          Expenses:Subscription   99.99 USD
          Assets:Cash             -99.99 USD
        """)
    }

    /// Test no errors are returned for valid patterns
    @Test func noErrorsForValidPatterns() throws {
        let p: ContentProvider =
        """
        plugin "beanlabs.plugins.forecast"

        2011-01-01 open Expenses:Test
        2011-01-01 open Assets:Cash

        2014-01-01 # "Valid pattern [MONTHLY REPEAT 1 TIME]"
          Expenses:Test   10.00 USD
          Assets:Cash
        """

        let ledger = try p.loadLedger()

        #expect(ledger.errors.isEmpty)
    }

    /// Test handling invalid pattern returns error
    @Test func invalidPatternHandling() throws {
        let p: ContentProvider =
        """
        plugin "beanlabs.plugins.forecast"

        2011-01-01 open Expenses:Test
        2011-01-01 open Assets:Cash

        2014-01-01 # "Invalid pattern [INVALID_INTERVAL]"
          Expenses:Test   10.00 USD
          Assets:Cash
        """

        let ledger = try p.loadLedger()

        #expect(!ledger.errors.isEmpty)
        #expect(ledger.directives.count == 3) // Original entries plus the invalid forecast entry
    }

    /// Test forecast with end date boundary
    @Test func forecastWithUntilDate() throws {
        let p: ContentProvider =
        """
        plugin "beanlabs.plugins.forecast"

        2011-01-01 open Expenses:Test
        2011-01-01 open Assets:Cash

        2014-01-01 # "Limited forecast [MONTHLY UNTIL 2014-03-01]"
          Expenses:Test   25.00 USD
          Assets:Cash
        """

        let ledger = try p.loadLedger()

        assertEqualEntries(ledger.directives,
        """
        2011-01-01 open Expenses:Test
        2011-01-01 open Assets:Cash

        2014-01-01 # "Limited forecast"
          Expenses:Test   25.00 USD
          Assets:Cash    -25.00 USD

        2014-02-01 # "Limited forecast"
          Expenses:Test   25.00 USD
          Assets:Cash    -25.00 USD

        2014-03-01 # "Limited forecast"
          Expenses:Test   25.00 USD
          Assets:Cash    -25.00 USD
        """)
    }
}
