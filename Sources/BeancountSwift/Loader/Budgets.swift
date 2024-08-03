//
//  Budgets.swift
//
//
//  Created by Yeatse on 2024/7/31.
//

import Foundation
import OrderedCollections

/// A budget entry.
public struct Budget {
    let account: Account
    let startDate: Date
    let period: Calendar.Component
    let number: Decimal
    let currency: Currency
}

public typealias BudgetDictionary = OrderedDictionary<Account, [Budget]>

enum BudgetError: Error {
    case invalidInterval
    case parsingFailed
}

public struct BudgetParser {
    public let budgets: BudgetDictionary
    public let errors: [Error]
    
    public init<T>(from entries: [Directive<T>]) {
        (budgets, errors) = Self.parseBudgets(from: entries)
    }
    
    /// Calculate the budget for an account in an interval.
    public func calculateBudget(for account: Account, withIn dateRange: DateInterval, includingChildren: Bool) -> [Currency: Decimal] {
        if includingChildren {
            return Self.calculateBudgetChildren(for: budgets, account: account, from: dateRange.start, to: dateRange.end)
        } else {
            return Self.calculateBudget(from: budgets, account: account, from: dateRange.start, to: dateRange.end)
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
    static func parseBudgets<T>(from entries: [Directive<T>]) -> (BudgetDictionary, [Error]) {
        let intervalMap: [String: Calendar.Component] = [
            "daily": .day,
            "weekly": .weekOfYear,
            "monthly": .month,
            "quarterly": .quarter,
            "yearly": .year
        ]
        var errors: [Error] = []
        var budgets: BudgetDictionary = [:]
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
            budgets[budget.account, default: []].append(budget)
        }
        return (budgets, errors)
    }
    
    /// Find matching budgets.
    /// - Returns: The budget that is active on the specified date for the specified account.
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
    static func calculateBudget(from budgets: BudgetDictionary, account: Account, from: Date, to: Date) -> [Currency: Decimal] {
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
            let matches = matchingBudgets(budgetList, activeDate: day)
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
    static func calculateBudgetChildren(for budgets: BudgetDictionary, account: Account, from: Date, to: Date) -> [Currency: Decimal] {
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
