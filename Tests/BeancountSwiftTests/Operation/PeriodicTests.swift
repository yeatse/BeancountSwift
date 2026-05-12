//
//  PeriodicTests.swift
//
//
//  Created by OpenAI on 2026/5/12.
//

import Testing

@testable import BeancountSwift

struct PeriodicTests {
    @Test func recurGeneratesTransactions() throws {
        let p: ContentProvider =
            """
            plugin "beancount_periodic.recur"

            2022-01-01 open Liabilities:Card
            2022-01-01 open Expenses:Service

            2022-03-31 * "Provider" "Net Fee"
              recur: "3 Months /Monthly"
              Liabilities:Card    -50 USD
              Expenses:Service
            """

        let ledger = try p.loadLedger()

        assertEqualEntries(
            ledger.directives,
            """
            2022-01-01 open Liabilities:Card
            2022-01-01 open Expenses:Service

            2022-03-31 * "Provider" "Net Fee Recurring(1/3)"
              Liabilities:Card    -50 USD
              Expenses:Service     50 USD

            2022-04-30 * "Provider" "Net Fee Recurring(2/3)"
              Liabilities:Card    -50 USD
              Expenses:Service     50 USD

            2022-05-31 * "Provider" "Net Fee Recurring(3/3)"
              Liabilities:Card    -50 USD
              Expenses:Service     50 USD
            """
        )
    }

    @Test func splitDividesTransactionByStepDays() throws {
        let p: ContentProvider =
            """
            plugin "beancount_periodic.split"

            2022-01-01 open Liabilities:Tax
            2022-01-01 open Expenses:Tax

            2022-01-01 * "Tax Estimate"
              split: "4 Days /Daily"
              Liabilities:Tax   -100 USD
              Expenses:Tax
            """

        let ledger = try p.loadLedger()

        assertEqualEntries(
            ledger.directives,
            """
            2022-01-01 open Liabilities:Tax
            2022-01-01 open Expenses:Tax

            2022-01-01 * "Tax Estimate Split(1/4)"
              Liabilities:Tax   -25 USD
              Expenses:Tax       25 USD

            2022-01-02 * "Tax Estimate Split(2/4)"
              Liabilities:Tax   -25 USD
              Expenses:Tax       25 USD

            2022-01-03 * "Tax Estimate Split(3/4)"
              Liabilities:Tax   -25 USD
              Expenses:Tax       25 USD

            2022-01-04 * "Tax Estimate Split(4/4)"
              Liabilities:Tax   -25 USD
              Expenses:Tax       25 USD
            """
        )
    }

    @Test func amortizeMovesExpenseThroughEquity() throws {
        let p: ContentProvider =
            """
            plugin "beancount_periodic.amortize"

            2022-01-01 open Liabilities:Card
            2022-01-01 open Equity:Amortization:Home:Rent
            2022-01-01 open Expenses:Home:Rent

            2022-03-31 * "Landlord" "Rent"
              Liabilities:Card    -120 USD
              Expenses:Home:Rent
                amortize: "3 Months @2022-04-01 /Monthly"
            """

        let ledger = try p.loadLedger()

        assertEqualEntries(
            ledger.directives,
            """
            2022-01-01 open Liabilities:Card
            2022-01-01 open Equity:Amortization:Home:Rent
            2022-01-01 open Expenses:Home:Rent

            2022-03-31 * "Landlord" "Rent"
              Liabilities:Card                 -120 USD
              Equity:Amortization:Home:Rent    120 USD

            2022-04-01 * "Landlord" "Rent Amortized(1/3)"
              Equity:Amortization:Home:Rent   -40 USD
              Expenses:Home:Rent               40 USD

            2022-05-01 * "Landlord" "Rent Amortized(2/3)"
              Equity:Amortization:Home:Rent   -40 USD
              Expenses:Home:Rent               40 USD

            2022-06-01 * "Landlord" "Rent Amortized(3/3)"
              Equity:Amortization:Home:Rent   -40 USD
              Expenses:Home:Rent               40 USD
            """
        )
    }

    @Test func depreciateGeneratesExpenseAndOpenDirective() throws {
        let p: ContentProvider =
            """
            plugin "beancount_periodic.depreciate"

            2022-01-01 open Liabilities:Card
            2022-01-01 open Assets:Car:ModelX

            2022-03-31 * "Tesla" "Model X"
              Liabilities:Card    -120 USD
              Assets:Car:ModelX
                depreciate: "3 Months /Monthly =30"
            """

        let ledger = try p.loadLedger()

        assertEqualEntries(
            ledger.directives,
            """
            2022-01-01 open Liabilities:Card
            2022-01-01 open Assets:Car:ModelX

            2022-03-31 open Expenses:Depreciation:Car:ModelX USD

            2022-03-31 * "Tesla" "Model X"
              Liabilities:Card    -120 USD
              Assets:Car:ModelX    120 USD

            2022-03-31 * "Tesla" "Model X Depreciated(1/3)"
              Expenses:Depreciation:Car:ModelX    30 USD
              Assets:Car:ModelX                  -30 USD

            2022-04-30 * "Tesla" "Model X Depreciated(2/3)"
              Expenses:Depreciation:Car:ModelX    30 USD
              Assets:Car:ModelX                  -30 USD

            2022-05-31 * "Tesla" "Model X Depreciated(3/3)"
              Expenses:Depreciation:Car:ModelX    30 USD
              Assets:Car:ModelX                  -30 USD
            """
        )
    }

    @Test func generateUntilLimitsGeneratedEntries() throws {
        let p: ContentProvider =
            """
            plugin "beancount_periodic.recur" "{'generate_until':'2022-04-30'}"

            2022-01-01 open Liabilities:Card
            2022-01-01 open Expenses:Service

            2022-03-31 * "Provider" "Net Fee"
              recur: "3 Months /Monthly"
              Liabilities:Card    -50 USD
              Expenses:Service
            """

        let ledger = try p.loadLedger()

        assertEqualEntries(
            ledger.directives,
            """
            2022-01-01 open Liabilities:Card
            2022-01-01 open Expenses:Service

            2022-03-31 * "Provider" "Net Fee Recurring(1/3)"
              Liabilities:Card    -50 USD
              Expenses:Service     50 USD

            2022-04-30 * "Provider" "Net Fee Recurring(2/3)"
              Liabilities:Card    -50 USD
              Expenses:Service     50 USD
            """
        )
    }
}
