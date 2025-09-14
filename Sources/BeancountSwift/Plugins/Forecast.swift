//
//  Forecast.swift
//
//
//  Created by Yeatse on 2024/1/28.
//

/// An implementation of a forecasting plugin for Beancount in Swift.
///
/// This plugin automatically generates recurring transactions based on patterns
/// specified in transaction narrations. It supports various repetition intervals
/// (DAILY, WEEKLY, MONTHLY, YEARLY) and provides flexible configuration options.
///
/// Transactions marked with the '#' flag and containing specific patterns in their
/// narration will be used as templates for generating future recurring entries.

import Foundation
import RegexBuilder

struct ForecastPlugin: BeancountPlugin {
    static let name = "beanlabs.plugins.forecast"

    enum ForecastError: Error {
        case invalidDateFormat(String)
        case invalidConfiguration(String)
    }

    enum ForecastInterval {
        case daily
        case weekly
        case monthly
        case yearly

        func addTo(date: Date, count: Int = 1) -> Date {
            let calendar = Calendar.current
            switch self {
            case .daily:
                return calendar.date(byAdding: .day, value: count, to: date)!
            case .weekly:
                return calendar.date(byAdding: .weekOfYear, value: count, to: date)!
            case .monthly:
                return calendar.date(byAdding: .month, value: count, to: date)!
            case .yearly:
                return calendar.date(byAdding: .year, value: count, to: date)!
            }
        }
    }

    struct ForecastConfig {
        let interval: ForecastInterval
        let skipCount: Int
        let repeatCount: Int?
        let untilDate: Date?
        let cleanNarration: String

        init(
            interval: ForecastInterval,
            skipCount: Int = 0,
            repeatCount: Int? = nil,
            untilDate: Date? = nil,
            cleanNarration: String
        ) {
            self.interval = interval
            self.skipCount = skipCount
            self.repeatCount = repeatCount
            self.untilDate = untilDate
            self.cleanNarration = cleanNarration
        }
    }

    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (
        entries: [Directive<Cost>], errors: [Error]
    ) {
        guard !entries.isEmpty else {
            return (entries, [])
        }

        // Find the last entry's date for default until date
        let dateToday = entries.last?.date ?? .now

        // Separate forecast templates from regular entries
        var forecastEntries: [Directive<Cost>] = []
        var filteredEntries: [Directive<Cost>] = []

        for entry in entries {
            if case .transaction(let transaction) = entry.content, transaction.flag == "#" {
                forecastEntries.append(entry)
            } else {
                filteredEntries.append(entry)
            }
        }

        // Generate forecast entries from templates
        var newEntries: [Directive<Cost>] = []
        var errors: [Error] = []

        for forecastEntry in forecastEntries {
            guard case .transaction(let transaction) = forecastEntry.content else {
                continue
            }

            do {
                let forecastConfig = try parseForecastPattern(from: transaction.narration ?? "")
                let generatedEntries = try generateForecastEntries(
                    from: forecastEntry,
                    transaction: transaction,
                    config: forecastConfig,
                    defaultUntilDate: dateToday
                )
                newEntries.append(contentsOf: generatedEntries)
            } catch {
                errors.append(error)
                // Add the original entry if parsing failed
                newEntries.append(forecastEntry)
            }
        }

        // Sort all entries by date
        let allEntries = (filteredEntries + newEntries).sorted { $0.date < $1.date }

        return (allEntries, errors)
    }

    private func parseForecastPattern(from narration: String) throws -> ForecastConfig {
        // Regex pattern to match forecast configuration
        // Pattern: "Description [INTERVAL SKIP X TIME(S) REPEAT Y TIME(S) UNTIL YYYY-MM-DD]"
        let pattern = #/
            ^(.*?)\[
            (DAILY|WEEKLY|MONTHLY|YEARLY)
            (?:\s+SKIP\s+(\d+)\s+TIMES?)?
            (?:\s+REPEAT\s+(\d+)\s+TIMES?)?
            (?:\s+UNTIL\s+(\d{4}-\d{2}-\d{2}))?
            \]
        /#

        guard let match = narration.firstMatch(of: pattern) else {
            throw ForecastError.invalidConfiguration("Invalid forecast pattern in narration: \(narration)")
        }

        let cleanNarration = String(match.1).trimmingCharacters(in: .whitespaces)
        let intervalString = String(match.2)

        let interval: ForecastInterval
        switch intervalString {
        case "DAILY":
            interval = .daily
        case "WEEKLY":
            interval = .weekly
        case "MONTHLY":
            interval = .monthly
        case "YEARLY":
            interval = .yearly
        default:
            interval = .monthly
        }

        let skipCount = match.3.map { Int(String($0)) ?? 0 } ?? 0
        let repeatCount = match.4.flatMap { Int(String($0)) }

        var untilDate: Date?
        if let untilString = match.5 {
            untilDate = Date.fromDateString(String(untilString))
            if untilDate == nil {
                throw ForecastError.invalidDateFormat("Invalid until date format: \(untilString)")
            }
        }

        return ForecastConfig(
            interval: interval,
            skipCount: skipCount,
            repeatCount: repeatCount,
            untilDate: untilDate,
            cleanNarration: cleanNarration
        )
    }

    private func generateForecastEntries(
        from originalEntry: Directive<Cost>,
        transaction: Transaction<Cost>,
        config: ForecastConfig,
        defaultUntilDate: Date
    ) throws -> [Directive<Cost>] {
        var generatedEntries: [Directive<Cost>] = []
        let startDate = originalEntry.date
        let calendar = Calendar.current

        // Determine the end condition
        let endDate: Date
        if let untilDate = config.untilDate {
            endDate = untilDate
        } else if let repeatCount = config.repeatCount {
            // Calculate end date based on repeat count
            let totalSkip = config.skipCount + 1 // +1 because we skip by interval+1
            let lastIteration = (repeatCount - 1) * totalSkip
            endDate = config.interval.addTo(date: startDate, count: lastIteration)
        } else {
            // Default to end of current year
            let currentYear = calendar.component(.year, from: defaultUntilDate)
            endDate = calendar.date(from: DateComponents(year: currentYear, month: 12, day: 31)) ?? defaultUntilDate
        }

        // Generate forecast dates
        var currentDate = startDate
        var iterationCount = 0
        let skipMultiplier = config.skipCount + 1

        repeat {
            // Create new transaction with updated date and narration
            let newTransaction = Transaction<Cost>(
                flag: transaction.flag,
                payee: transaction.payee,
                narration: config.cleanNarration.isEmpty ? nil : config.cleanNarration,
                tags: transaction.tags,
                links: transaction.links,
                postings: transaction.postings
            )

            let newEntry = Directive<Cost>(
                meta: originalEntry.meta,
                date: currentDate,
                comment: originalEntry.comment,
                content: .transaction(newTransaction)
            )

            generatedEntries.append(newEntry)

            // Move to next occurrence
            currentDate = config.interval.addTo(date: currentDate, count: skipMultiplier)
            iterationCount += 1

            // Check repeat count limit
            if let repeatCount = config.repeatCount, iterationCount >= repeatCount {
                break
            }

        } while currentDate <= endDate

        return generatedEntries
    }
}
