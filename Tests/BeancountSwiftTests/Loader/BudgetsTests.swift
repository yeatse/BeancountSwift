//
//  BudgetsTests.swift
//
//
//  Created by Yeatse on 2024/8/4.
//

import Foundation
import Testing

@testable import BeancountSwift

struct BudgetsTests {

    @Test func budgets() throws {
        let p: ContentProvider =
            """
            2016-01-01 custom "budget" Expenses:Groceries "weekly" 100.00 CNY
            2016-06-01 custom "budget" Expenses:Groceries "weekly"  10.00 EUR
            2016-06-01 custom "budget" Expenses:Groceries "asdfasdf"  10.00 EUR
            2016-06-01 custom "budget" Expenses:Groceries 10.00 EUR
            """
        let ledger = try p.parseLedger()
        let budgets = BudgetParser(from: ledger.directives)

        #expect(budgets.errors.count == 2)

        let empty = BudgetParser.calculateBudget(
            from: budgets.budgets, account: "Expenses", from: "2016-06-01", to: "2016-06-08")
        #expect(empty.isEmpty)

        let budgets_ = BudgetParser.calculateBudget(
            from: budgets.budgets, account: "Expenses:Groceries", from: "2016-06-01",
            to: "2016-06-08")
        #expect(almostEqual(budgets_["CNY"]!, 100))
        #expect(almostEqual(budgets_["EUR"]!, 10))
    }

    @Test func budgetsDaily() throws {
        let p: ContentProvider =
            """
            2016-05-01 custom "budget" Expenses:Books "daily" 2.5 EUR
            """
        let ledger = try p.parseLedger()
        let budgets = BudgetParser(from: ledger.directives)

        let cal1 = BudgetParser.calculateBudget(
            from: budgets.budgets, account: "Expenses:Books", from: "2010-02-01", to: "2010-02-02")
        #expect(!cal1.keys.contains("EUR"))

        let cases: [(Date, Date, Decimal)] = [
            ("2016-05-01", "2016-05-02", "2.5"),
            ("2016-05-01", "2016-05-03", "5.0"),
            ("2016-09-02", "2016-09-03", "2.5"),
            ("2018-12-31", "2019-01-01", "2.5"),
        ]
        for (start, end, num) in cases {
            let budget = BudgetParser.calculateBudget(
                from: budgets.budgets, account: "Expenses:Books", from: start, to: end)
            #expect(budget["EUR"] == num)
        }
    }

    @Test func budgetsWeekly() throws {
        let p: ContentProvider =
            """
            2016-05-01 custom "budget" Expenses:Books "weekly" 21 EUR
            """
        let ledger = try p.parseLedger()
        let budgets = BudgetParser(from: ledger.directives)

        let cases: [(Date, Date, Decimal)] = [
            ("2016-05-01", "2016-05-02", Decimal(21) / 7),
            ("2016-09-01", "2016-09-02", Decimal(21) / 7),
        ]
        for (start, end, num) in cases {
            let budget = BudgetParser.calculateBudget(
                from: budgets.budgets, account: "Expenses:Books", from: start, to: end)
            #expect(budget["EUR"] == num)
        }
    }

    @Test func budgetsMonthly() throws {
        let p: ContentProvider =
            """
            2014-05-01 custom "budget" Expenses:Books "monthly" 100 EUR
            """
        let ledger = try p.parseLedger()
        let budgets = BudgetParser(from: ledger.directives)

        let cases: [(Date, Date, Decimal)] = [
            ("2016-05-01", "2016-05-02", Decimal(100) / 31),
            ("2016-02-01", "2016-02-02", Decimal(100) / 29),
            ("2018-03-31", "2018-04-01", Decimal(100) / 31),
        ]
        for (start, end, num) in cases {
            let budget = BudgetParser.calculateBudget(
                from: budgets.budgets, account: "Expenses:Books", from: start, to: end)
            #expect(budget["EUR"] == num)
        }
    }

    @Test func budgetsQuarterly() throws {
        let p: ContentProvider =
            """
            2014-05-01 custom "budget" Expenses:Books "quarterly" 123456.7 EUR
            """
        let ledger = try p.parseLedger()
        let budgets = BudgetParser(from: ledger.directives)

        let cases: [(Date, Date, Decimal)] = [
            ("2016-05-01", "2016-05-02", "123456.7" / 91),
            ("2016-08-15", "2016-08-16", "123456.7" / 92),
        ]
        for (start, end, num) in cases {
            let budget = BudgetParser.calculateBudget(
                from: budgets.budgets, account: "Expenses:Books", from: start, to: end)
            #expect(budget["EUR"] == num)
        }
    }

    @Test func budgetsYearly() throws {
        let p: ContentProvider =
            """
            2010-01-01 custom "budget" Expenses:Books "yearly" 99999.87 EUR
            """
        let ledger = try p.parseLedger()
        let budgets = BudgetParser(from: ledger.directives)

        let cases: [(Date, Date, Decimal)] = [
            ("2011-02-01", "2011-02-02", "99999.87" / 365)
        ]
        for (start, end, num) in cases {
            let budget = BudgetParser.calculateBudget(
                from: budgets.budgets, account: "Expenses:Books", from: start, to: end)
            #expect(budget["EUR"] == num)
        }
    }

    @Test func budgetsChildren() throws {
        let p: ContentProvider =
            """
            2017-01-01 custom "budget" Expenses:Books "daily" 10.00 USD
            2017-01-01 custom "budget" Expenses:Books:Notebooks "daily" 2.00 USD
            """
        let ledger = try p.parseLedger()
        let budgets = BudgetParser(from: ledger.directives)

        var budget = BudgetParser.calculateBudgetChildren(
            for: budgets.budgets, account: "Expenses", from: "2017-01-01", to: "2017-01-02")
        #expect(budget["USD"] == "12")

        budget = BudgetParser.calculateBudgetChildren(
            for: budgets.budgets, account: "Expenses:Books", from: "2017-01-01", to: "2017-01-02")
        #expect(budget["USD"] == "12")

        budget = BudgetParser.calculateBudgetChildren(
            for: budgets.budgets, account: "Expenses:Books:Notebooks", from: "2017-01-01",
            to: "2017-01-02")
        #expect(budget["USD"] == "2")
    }

    @Test func budgetsSerializing() throws {
        let budget = Budget(
            account: "Expenses:Books", startDate: "2017-01-01", period: .day, number: 10,
            currency: "USD")
        let directive = Directive<CostSpec>(from: budget)!
        #expect(directive.date == "2017-01-01")
        #expect(
            directive.content
                == .custom(
                    Custom(
                        type: "budget",
                        values: [
                            .account("Expenses:Books"),
                            .string("daily"),
                            .amount("10 USD"),
                        ])))
        #expect(
            directive.description
                == "2017-01-01 custom \"budget\" Expenses:Books \"daily\" 10.00 USD\n")
    }
}
