//
//  Budgets.swift
//
//
//  Created by Yeatse on 2024/7/31.
//

/// Provides budget management and calculation functionality for Beancount.
/// 
/// This module implements budget parsing, storage, and calculation features,
/// allowing users to define periodic budgets for accounts and track spending
/// against those budgets over time.
/// 
/// Budgets are represented as custom directives in Beancount files and can
/// specify daily, weekly, monthly, quarterly, or yearly budget amounts.

import Foundation
import OrderedCollections

/// Represents a budget allocation for a specific account and time period.
/// 
/// Budget defines a periodic budget amount for an account, specifying how much
/// should be allocated over a given time period (daily, monthly, etc.).
/// 
/// ## Usage
/// ```swift
/// let budget = Budget(
///     account: Account(id: "Expenses:Food"),
///     startDate: Date(),
///     period: .month,
///     number: 500.00,
///     currency: Currency(id: "USD")
/// )
/// ```
public struct Budget: Sendable {
    /// The account this budget applies to.
    public let account: Account
    /// The date when this budget becomes active.
    public let startDate: Date
    /// The time period for this budget (day, week, month, etc.).
    public let period: Calendar.Component
    /// The budget amount for the specified period.
    public let number: Decimal
    /// The currency of the budget amount.
    public let currency: Currency
    
    /// Creates a budget entry.
    /// 
    /// - Parameters:
    ///   - account: The account this budget applies to
    ///   - startDate: When this budget becomes active
    ///   - period: The time period for this budget
    ///   - number: The budget amount for the period
    ///   - currency: The currency of the budget amount
    public init(account: Account, startDate: Date, period: Calendar.Component, number: Decimal, currency: Currency) {
        self.account = account
        self.startDate = startDate
        self.period = period
        self.number = number
        self.currency = currency
    }
}

public extension Directive {
    /// Creates a custom directive from a budget entry.
    /// 
    /// Converts a Budget into a Beancount custom directive that can be
    /// written to a ledger file. The directive uses the "budget" type
    /// with account, interval, and amount values.
    /// 
    /// - Parameter budget: The budget to convert
    /// - Returns: A directive representing the budget, or nil if conversion fails
    init?(from budget: Budget) {
        let intervalMap: [Calendar.Component: String] = [
            .day: "daily",
            .weekOfYear: "weekly",
            .month: "monthly",
            .quarter: "quarterly",
            .year: "yearly"
        ]
        guard let interval = intervalMap[budget.period] else {
            return nil
        }
        let custom = Custom(type: "budget", values: [
            .account(budget.account),
            .string(interval),
            .amount(Amount(number: budget.number, currency: budget.currency))
        ])
        self.init(meta: [:], date: budget.startDate, content: .custom(custom))
    }
}

/// A budget entry paired with its originating directive.
/// 
/// BudgetDirective links a parsed budget back to the custom directive
/// it was created from, preserving the full context and metadata.
public struct BudgetDirective<T>: Sendable where T: PostingCost {
    /// The parsed budget information.
    public let budget: Budget
    /// The original custom directive and its content.
    public let directive: DirectiveValue<T, Custom>
}

/// A dictionary mapping accounts to their budget directives.
/// 
/// BudgetDictionary organizes budget directives by account for efficient lookup
/// and calculation. Multiple budget directives per account are supported to
/// handle budget changes over time.
public typealias BudgetDictionary<T> = OrderedDictionary<Account, [BudgetDirective<T>]> where T: PostingCost

/// Errors that can occur during budget parsing.
enum BudgetError: Error {
    /// An unsupported time interval was specified.
    case invalidInterval
    /// Budget directive parsing failed due to invalid format.
    case parsingFailed
}

/// Parser and calculator for budget directives.
/// 
/// BudgetParser processes custom budget directives from Beancount files
/// and provides methods for calculating budget amounts over time periods.
/// It handles periodic budgets with different intervals and can include
/// child account budgets in calculations.
/// 
/// ## Usage
/// ```swift
/// let parser = BudgetParser(from: directives)
/// let monthlyBudget = parser.calculateBudget(
///     for: Account(id: "Expenses:Food"),
///     withIn: startDate..<endDate,
///     includingChildren: false
/// )
/// ```
public struct BudgetParser<T> where T: PostingCost {
    /// All parsed budget directives organized by account.
    public let budgets: BudgetDictionary<T>
    /// Any errors encountered during parsing.
    public let errors: [Error]
    
    /// Creates a budget parser from directive entries.
    /// 
    /// Processes all custom directives in the entries to extract budget information.
    /// 
    /// - Parameter entries: The directives to parse for budget information
    public init(from entries: [Directive<T>]) {
        (budgets, errors) = Self.parseBudgets(from: entries)
    }
    
    /// Calculates the total budget for an account over a date range.
    /// 
    /// Computes the budget amount by summing daily budget allocations over
    /// the specified date range. Can optionally include child account budgets.
    /// 
    /// - Parameters:
    ///   - account: The account to calculate budget for
    ///   - dateRange: The date range to calculate over
    ///   - includingChildren: Whether to include child account budgets
    /// - Returns: A dictionary mapping currencies to total budget amounts
    public func calculateBudget(for account: Account, withIn dateRange: Range<Date>, includingChildren: Bool) -> [Currency: Decimal] {
        if includingChildren {
            return Self.calculateBudgetChildren(for: budgets, account: account, from: dateRange.lowerBound, to: dateRange.upperBound)
        } else {
            return Self.calculateBudget(from: budgets, account: account, from: dateRange.lowerBound, to: dateRange.upperBound)
        }
    }
}

extension BudgetParser {
    
    /// Parses budget directives from custom entries.
    ///
    /// - Parameters:
    ///   - entries: The custom entries to parse budgets from.
    ///
    /// - Returns: A tuple containing:
    ///   - A dictionary mapping account names to lists of `Budget` entries.
    ///   - An array of `BudgetError` values representing any errors encountered during parsing.
    ///
    /// - Example:
    /// ```
    /// let customEntries = [
    ///     CustomEntry(type: "budget", date: Date(), values: ["Expenses:Books", "monthly", Decimal(string: "20.00")!, "EUR"])
    /// ]
    /// let (budgets, errors) = parseBudgets(from: customEntries)
    /// ```
    static func parseBudgets(from entries: [Directive<T>]) -> (BudgetDictionary<T>, [Error]) {
        let intervalMap: [String: Calendar.Component] = [
            "daily": .day,
            "weekly": .weekOfYear,
            "monthly": .month,
            "quarterly": .quarter,
            "yearly": .year
        ]
        var errors: [Error] = []
        var budgets: BudgetDictionary<T> = [:]
        for entry in entries {
            guard case .custom(let custom) = entry.content, custom.type == "budget" else {
                continue
            }
            guard custom.values.count >= 3,
                  case .account(let account) = custom.values[0],
                  case .string(let intervalVal) = custom.values[1],
                  case .amount(let amount) = custom.values[2]
            else {
                errors.append(BudgetError.parsingFailed)
                continue
            }
            guard let interval = intervalMap[intervalVal] else {
                errors.append(BudgetError.invalidInterval)
                continue
            }
            let budget = Budget(account: account,
                                startDate: entry.date,
                                period: interval,
                                number: amount.number,
                                currency: amount.currency)
            let directive = BudgetDirective(budget: budget, directive: DirectiveValue(entry, custom))
            budgets[budget.account, default: []].append(directive)
        }
        return (budgets, errors)
    }
    
    /// Finds the active budgets for a specific date.
    /// 
    /// Returns the most recent budget for each currency that was active
    /// on or before the specified date. This handles budget changes over time.
    /// 
    /// - Parameters:
    ///   - budgets: List of budgets to search (should be sorted by start date)
    ///   - activeDate: The date to find active budgets for
    /// - Returns: A dictionary mapping currencies to their active budgets
    private static func matchingBudgets(_ budgets: [Budget], activeDate: Date) -> [Currency: Budget] {
        var lastSeenBudgets: [Currency: Budget] = [:]
        for budget in budgets {
            if budget.startDate <= activeDate {
                lastSeenBudgets[budget.currency] = budget
            } else {
                break
            }
        }
        return lastSeenBudgets
    }
    
    /// Calculates the budget for a specified account over a given date range.
    ///
    /// - Parameters:
    ///   - budgets: A dictionary mapping account names to lists of `Budget` entries.
    ///   - account: The name of the account for which the budget is to be calculated.
    ///   - from: The starting date of the period to calculate the budget for.
    ///   - to: The end date of the period (exclusive) to calculate the budget for.
    ///
    /// - Returns: A dictionary mapping currency codes to `Decimal` values representing the budget
    ///   for the specified account and period.
    ///
    /// - Example:
    /// ```
    /// let budgets: BudgetDict = [ /* Budget entries here */ ]
    /// let account = "Expenses:Books"
    /// let dateFrom = Date() // Starting date
    /// let dateTo = Date() // End date (exclusive)
    /// let budget = calculateBudget(budgets: budgets, account: account, from: dateFrom, to: dateTo)
    /// ```
    static func calculateBudget(from budgets: BudgetDictionary<T>, account: Account, from: Date, to: Date) -> [Currency: Decimal] {
        guard let budgetList = budgets[account] else {
            return [:]
        }
        var currencyDict: [Currency: Decimal] = [:]
        let calendar = Calendar.autoupdatingCurrent
        
        var day = calendar.startOfDay(for: from)
        if day != from {
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        while day < to {
            let matches = matchingBudgets(budgetList.map(\.budget), activeDate: day)
            for budget in matches.values {
                guard let interval = calendar.dateInterval(of: budget.period, for: day),
                      let daysInPeriod = calendar.dateComponents([.day], from: interval.start, to: interval.end).day
                else {
                    continue
                }
                currencyDict[budget.currency, default: .zero] += budget.number / Decimal(daysInPeriod)
            }
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: day) {
                day = nextDay
            } else {
                break
            }
        }
        return currencyDict
    }
    
    /// Calculates the budget for a specified account and includes the budgets of its child accounts over a given date range.
    ///
    /// - Parameters:
    ///   - budgets: A dictionary mapping account names to lists of `Budget` entries.
    ///   - account: The name of the account for which the budget is to be calculated, including child accounts.
    ///   - dateFrom: The starting date of the period for which to calculate the budget.
    ///   - dateTo: The end date (exclusive) of the period for which to calculate the budget.
    ///
    /// - Returns: A dictionary mapping currency codes to `Decimal` values representing the total budget
    ///   for the specified account and its children over the specified period.
    ///
    /// - Example:
    /// ```
    /// let budgets: BudgetDict = [ /* Budget entries here */ ]
    /// let account = "Expenses:Books"
    /// let dateFrom = Date() // Starting date
    /// let dateTo = Date() // End date (exclusive)
    /// let totalBudget = calculateBudgetChildren(budgets: budgets, account: account, dateFrom: dateFrom, dateTo: dateTo)
    /// ```
    static func calculateBudgetChildren(for budgets: BudgetDictionary<T>, account: Account, from: Date, to: Date) -> [Currency: Decimal] {
        var currencyDict: [Currency: Decimal] = [:]
        for child in budgets.keys.filter({ $0.isChild(of: account) }) {
            let budget = calculateBudget(from: budgets, account: child, from: from, to: to)
            for (currency, value) in budget {
                currencyDict[currency, default: .zero] += value
            }
        }
        return currencyDict
    }
}
