//
//  Summarize.swift
//  BeancountSwift
//
//  Created by yeatse on 2026/2/22.
//

import Foundation

/// Summarization helpers for period-based balance sheet style views.
///
/// This API mirrors Beancount Python's `beancount.ops.summarize` module:
/// it can transfer balances, summarize historical postings into opening
/// entries, truncate by date, and inject conversion transactions to keep
/// balance invariants valid across sliced periods.
public enum Summarize {
    /// A predicate used to select accounts for transfer operations.
    public typealias AccountPredicate = (Account) -> Bool

    /// Summarize entries before a date and transfer income/expense balances
    /// into an equity earnings account.
    ///
    /// This performs, in order:
    /// 1. `conversions()`
    /// 2. `clear()`
    /// 3. `summarize()`
    ///
    /// - Returns: The transformed directives and the boundary index that points
    ///   to the first original entry on/after `date`.
    public static func `open`(
        _ entries: [Directive<Cost>],
        date: Date,
        accountTypes: AccountTypeConfiguration,
        conversionCurrency: Currency,
        accountEarnings: Account,
        accountOpening: Account,
        accountConversions: Account
    ) -> (entries: [Directive<Cost>], index: Int) {
        let withConversions = conversions(
            entries,
            conversionAccount: accountConversions,
            conversionCurrency: conversionCurrency,
            date: date
        )
        let cleared = clear(
            withConversions,
            date: date,
            accountTypes: accountTypes,
            accountEarnings: accountEarnings
        )
        return summarize(
            cleared.entries,
            date: date,
            accountOpening: accountOpening
        )
    }

    /// Truncate entries on/after a date and append conversion entries to force
    /// global cost-balance neutrality.
    ///
    /// - Returns: The transformed directives and the index one past the last
    ///   original entry retained before inserting conversions.
    public static func close(
        _ entries: [Directive<Cost>],
        date: Date?,
        conversionCurrency: Currency,
        accountConversions: Account
    ) -> (entries: [Directive<Cost>], index: Int) {
        let truncated: [Directive<Cost>]
        if let date {
            truncated = truncate(entries, date: date)
        } else {
            truncated = entries
        }
        let index = truncated.count
        let converted = conversions(
            truncated,
            conversionAccount: accountConversions,
            conversionCurrency: conversionCurrency,
            date: date
        )
        return (converted, index)
    }

    /// Transfer balances from income-statement accounts into an earnings account
    /// at the cutoff date.
    ///
    /// - Returns: The transformed directives and the index one past the original
    ///   entries (before transfer entries are inserted).
    public static func clear(
        _ entries: [Directive<Cost>],
        date: Date?,
        accountTypes: AccountTypeConfiguration,
        accountEarnings: Account
    ) -> (entries: [Directive<Cost>], index: Int) {
        let index = entries.count
        let newEntries = transferBalances(
            entries,
            date: date,
            accountPredicate: { $0.isIncomeStatement(config: accountTypes) },
            transferAccount: accountEarnings
        )
        return (newEntries, index)
    }

    /// Convenience wrapper around ``open(_:date:accountTypes:conversionCurrency:accountEarnings:accountOpening:accountConversions:)`` using `Options`.
    public static func openOpt(
        _ entries: [Directive<Cost>],
        date: Date,
        options: Options
    ) -> (entries: [Directive<Cost>], index: Int) {
        let accountTypes = options.accountNames
        let previous = previousAccounts(from: options)
        let conversionCurrency = conversionCurrency(from: options)
        return `open`(
            entries,
            date: date,
            accountTypes: accountTypes,
            conversionCurrency: conversionCurrency,
            accountEarnings: previous.earnings,
            accountOpening: previous.balances,
            accountConversions: previous.conversions
        )
    }

    /// Convenience wrapper around ``close(_:date:conversionCurrency:accountConversions:)`` using `Options`.
    public static func closeOpt(
        _ entries: [Directive<Cost>],
        date: Date?,
        options: Options
    ) -> (entries: [Directive<Cost>], index: Int) {
        let current = currentAccounts(from: options)
        return close(
            entries,
            date: date,
            conversionCurrency: conversionCurrency(from: options),
            accountConversions: current.conversions
        )
    }

    /// Convenience wrapper around ``clear(_:date:accountTypes:accountEarnings:)`` using `Options`.
    public static func clearOpt(
        _ entries: [Directive<Cost>],
        date: Date?,
        options: Options
    ) -> (entries: [Directive<Cost>], index: Int) {
        let current = currentAccounts(from: options)
        return clear(
            entries,
            date: date,
            accountTypes: options.accountNames,
            accountEarnings: current.earnings
        )
    }

    /// Keep only activity in `[beginDate, endDate)`, while preserving opening
    /// balances and ensuring post-truncation conversion neutrality.
    ///
    /// - Returns: The transformed directives and the index boundary after the
    ///   synthesized opening set.
    public static func clamp(
        _ entries: [Directive<Cost>],
        beginDate: Date,
        endDate: Date,
        accountTypes: AccountTypeConfiguration,
        conversionCurrency: Currency,
        accountEarnings: Account,
        accountOpening: Account,
        accountConversions: Account
    ) -> (entries: [Directive<Cost>], index: Int) {
        let transferred = transferBalances(
            entries,
            date: beginDate,
            accountPredicate: { $0.isIncomeStatement(config: accountTypes) },
            transferAccount: accountEarnings
        )
        let summarized = summarize(
            transferred,
            date: beginDate,
            accountOpening: accountOpening
        )
        let truncated = truncate(
            summarized.entries,
            date: endDate
        )
        let converted = conversions(
            truncated,
            conversionAccount: accountConversions,
            conversionCurrency: conversionCurrency,
            date: endDate
        )
        return (converted, summarized.index)
    }

    /// Convenience wrapper around ``clamp(_:beginDate:endDate:accountTypes:conversionCurrency:accountEarnings:accountOpening:accountConversions:)`` using `Options`.
    public static func clampOpt(
        _ entries: [Directive<Cost>],
        beginDate: Date,
        endDate: Date,
        options: Options
    ) -> (entries: [Directive<Cost>], index: Int) {
        let previous = previousAccounts(from: options)
        let current = currentAccounts(from: options)
        return clamp(
            entries,
            beginDate: beginDate,
            endDate: endDate,
            accountTypes: options.accountNames,
            conversionCurrency: conversionCurrency(from: options),
            accountEarnings: previous.earnings,
            accountOpening: previous.balances,
            accountConversions: current.conversions
        )
    }

    /// Transfer final net income/expense balances and inject a final conversion
    /// transaction.
    public static func cap(
        _ entries: [Directive<Cost>],
        accountTypes: AccountTypeConfiguration,
        conversionCurrency: Currency,
        accountEarnings: Account,
        accountConversions: Account
    ) -> [Directive<Cost>] {
        let transferred = transferBalances(
            entries,
            date: nil,
            accountPredicate: { $0.isIncomeStatement(config: accountTypes) },
            transferAccount: accountEarnings
        )
        return conversions(
            transferred,
            conversionAccount: accountConversions,
            conversionCurrency: conversionCurrency,
            date: nil
        )
    }

    /// Convenience wrapper around ``cap(_:accountTypes:conversionCurrency:accountEarnings:accountConversions:)`` using `Options`.
    public static func capOpt(_ entries: [Directive<Cost>], options: Options) -> [Directive<Cost>] {
        let current = currentAccounts(from: options)
        return cap(
            entries,
            accountTypes: options.accountNames,
            conversionCurrency: conversionCurrency(from: options),
            accountEarnings: current.earnings,
            accountConversions: current.conversions
        )
    }

    /// Synthesize transfer transactions for accounts matching `accountPredicate`
    /// using balances computed strictly before `date`.
    public static func transferBalances(
        _ entries: [Directive<Cost>],
        date: Date?,
        accountPredicate: AccountPredicate,
        transferAccount: Account
    ) -> [Directive<Cost>] {
        guard !entries.isEmpty else {
            return entries
        }

        let balanceResult = balanceByAccount(entries, date: date)
        let transferBalances = balanceResult.balances.filter { accountPredicate($0.key) }

        let transferDate: Date
        if let date {
            transferDate = dayBefore(date)
        } else {
            transferDate = entries[entries.count - 1].date
        }

        let transferEntries = createEntriesFromBalances(
            transferBalances,
            date: transferDate,
            sourceAccount: transferAccount,
            direction: false,
            meta: newMetadata(filename: "<transfer_balances>", lineno: 0),
            flag: .transferFlag,
            narrationTemplate: "Transfer balance for '{account}' (Transfer balance)"
        )

        let transferAccounts = Set(transferBalances.keys)
        let afterEntries = entries.suffix(from: balanceResult.index).filter { entry in
            if case .balance(let balance) = entry.content {
                return !transferAccounts.contains(balance.account)
            }
            return true
        }

        return Array(entries.prefix(balanceResult.index)) + transferEntries + afterEntries
    }

    /// Replace entries strictly before `date` with opening-balance
    /// summarization transactions, preserving active opens and last prices.
    public static func summarize(
        _ entries: [Directive<Cost>],
        date: Date,
        accountOpening: Account
    ) -> (entries: [Directive<Cost>], index: Int) {
        let balanceResult = balanceByAccount(entries, date: date)
        let summarizeDate = dayBefore(date)

        let summarizingEntries = createEntriesFromBalances(
            balanceResult.balances,
            date: summarizeDate,
            sourceAccount: accountOpening,
            direction: true,
            meta: newMetadata(filename: "<summarize>", lineno: 0),
            flag: .summarizeFlag,
            narrationTemplate: "Opening balance for '{account}' (Summarization)"
        )

        let priceEntries = Array(entries.lastPriceEntries(until: date))
        let openEntries = getOpenEntries(entries, date: date)

        let beforeEntries = (openEntries + priceEntries + summarizingEntries).sorted()
        let afterEntries = Array(entries.suffix(from: balanceResult.index))
        return (beforeEntries + afterEntries, beforeEntries.count)
    }

    /// Insert a conversion transaction (if needed) to neutralize the
    /// cost-reduced aggregate balance up to `date`.
    public static func conversions(
        _ entries: [Directive<Cost>],
        conversionAccount: Account,
        conversionCurrency: Currency,
        date: Date? = nil
    ) -> [Directive<Cost>] {
        let conversionBalance = computeEntriesBalance(entries, date: date)
        let conversionCostBalance = conversionBalance.reduce { $0.totalCost }
        if conversionCostBalance.isEmpty {
            return entries
        }

        let index: Int
        let lastDate: Date
        if let date {
            index = entries.partitioningIndex { $0.date >= date }
            lastDate = dayBefore(date)
        } else {
            index = entries.count
            guard let last = entries.last else {
                return entries
            }
            lastDate = last.date
        }

        var postings: [Posting<Cost>] = []
        for position in conversionCostBalance.positions.sorted() {
            let price = Amount(number: .zero, currency: conversionCurrency)
            let negPosition = -position
            postings.append(
                Posting(
                    account: conversionAccount,
                    units: negPosition.units,
                    cost: negPosition.cost,
                    price: price
                ))
        }

        let conversionEntry = Directive<Cost>(
            meta: newMetadata(filename: "<conversions>", lineno: -1),
            date: lastDate,
            content: .transaction(
                Transaction(
                    flag: .conversionsFlag,
                    payee: nil,
                    narration: "Conversion for \(formatInventory(conversionBalance))",
                    tags: [],
                    links: [],
                    postings: postings
                ))
        )

        var newEntries = entries
        newEntries.insert(conversionEntry, at: index)
        return newEntries
    }

    /// Return all directives strictly before `date`.
    public static func truncate(_ entries: [Directive<Cost>], date: Date) -> [Directive<Cost>] {
        let index = entries.partitioningIndex { $0.date >= date }
        return Array(entries.prefix(index))
    }

    /// Build synthetic transactions from account balances, using
    /// `sourceAccount` as the balancing leg.
    ///
    /// - Parameter direction:
    ///   - `true`: transfer *to* account balances from source.
    ///   - `false`: transfer *from* account balances into source.
    public static func createEntriesFromBalances(
        _ balances: [Account: Inventory],
        date: Date,
        sourceAccount: Account,
        direction: Bool,
        meta: MetaData,
        flag: Character,
        narrationTemplate: String
    ) -> [Directive<Cost>] {
        var newEntries: [Directive<Cost>] = []
        for (account, accountBalance) in balances.sorted(by: { $0.key.id < $1.key.id }) {
            if accountBalance.isEmpty {
                continue
            }

            let narration =
                narrationTemplate
                .replacingOccurrences(of: "{account}", with: account.id)
                .replacingOccurrences(of: "{date}", with: date.isoDescription)

            let signedBalance = direction ? accountBalance : -accountBalance
            var postings: [Posting<Cost>] = []
            for position in signedBalance.positions.sorted() {
                postings.append(
                    Posting(
                        account: account,
                        units: position.units,
                        cost: position.cost
                    ))
                postings.append(
                    Posting(
                        account: sourceAccount,
                        units: -position.totalCost,
                        cost: nil
                    ))
            }

            newEntries.append(
                Directive(
                    meta: meta,
                    date: date,
                    content: .transaction(
                        Transaction(
                            flag: flag,
                            payee: nil,
                            narration: narration,
                            tags: [],
                            links: [],
                            postings: postings
                        ))
                ))
        }
        return newEntries
    }

    /// Compute per-account balances strictly before `date`.
    ///
    /// - Returns: Account balances and the index of the first entry on/after
    ///   `date` (or `entries.count` if no cutoff is reached).
    public static func balanceByAccount(
        _ entries: [Directive<Cost>],
        date: Date? = nil,
        compressUnbooked: Bool = false
    ) -> (balances: [Account: Inventory], index: Int) {
        var balances = [Account: Inventory]()
        var index = entries.count

        for (i, entry) in entries.enumerated() {
            if let date, entry.date >= date {
                index = i
                break
            }

            guard case .transaction(let transaction) = entry.content else {
                continue
            }
            for posting in transaction.postings {
                var accountBalance = balances[posting.account, default: Inventory()]
                accountBalance.addPosition(posting)
                balances[posting.account] = accountBalance
            }
        }

        if compressUnbooked {
            let openClose = entries.accountOpenClose()
            for (account, balance) in balances {
                if let open = openClose[account]?.0?.content, open.booking == .NONE {
                    balances[account] = balance.average
                }
            }
        }

        return (balances, index)
    }

    /// Return open directives that are still active strictly before `date`.
    ///
    /// Duplicate opens are tolerated by keeping the earliest open date for each
    /// account, matching Beancount Python behavior.
    public static func getOpenEntries(_ entries: [Directive<Cost>], date: Date?) -> [Directive<
        Cost
    >] {
        var openEntries = [Account: (index: Int, entry: Directive<Cost>)]()
        for (index, entry) in entries.enumerated() {
            if let date, entry.date >= date {
                break
            }

            switch entry.content {
            case .open(let open):
                if let existing = openEntries[open.account] {
                    if entry.date < existing.entry.date {
                        openEntries[open.account] = (index, entry)
                    }
                } else {
                    openEntries[open.account] = (index, entry)
                }
            case .close(let close):
                openEntries.removeValue(forKey: close.account)
            default:
                break
            }
        }

        return openEntries.values.sorted(by: { $0.index < $1.index }).map(\.entry)
    }

    private static func dayBefore(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: date)!
    }

    private static func newMetadata(filename: String, lineno: Int) -> MetaData {
        [
            "filename": .string(filename),
            "lineno": .number(.init(lineno)),
        ]
    }

    private static func computeEntriesBalance(_ entries: [Directive<Cost>], date: Date?)
        -> Inventory
    {
        var balance = Inventory()
        for entry in entries {
            if let date, entry.date >= date {
                break
            }
            guard case .transaction(let transaction) = entry.content else {
                continue
            }
            for posting in transaction.postings {
                balance.addPosition(posting)
            }
        }
        return balance
    }

    private static func formatInventory(_ inventory: Inventory) -> String {
        inventory.positions.sorted().map { position in
            if let cost = position.cost {
                return "\(position.units.narrationFormatted()) {\(cost)}"
            }
            return position.units.narrationFormatted()
        }.joined(separator: ", ")
    }

    private static func conversionCurrency(from options: Options) -> Currency {
        Currency(id: options.rawOptions["conversion_currency"]?.last ?? "NOTHING")
    }

    private static func previousAccounts(from options: Options) -> (
        earnings: Account, balances: Account, conversions: Account
    ) {
        let equity = options.accountNames.equity
        return (
            Account(
                id: "\(equity):"
                    + (options.rawOptions["account_previous_earnings"]?.last
                        ?? "Earnings:Previous")),
            Account(
                id: "\(equity):"
                    + (options.rawOptions["account_previous_balances"]?.last
                        ?? "Opening-Balances")),
            Account(
                id: "\(equity):"
                    + (options.rawOptions["account_previous_conversions"]?.last
                        ?? "Conversions:Previous"))
        )
    }

    private static func currentAccounts(from options: Options) -> (
        earnings: Account, conversions: Account
    ) {
        let equity = options.accountNames.equity
        return (
            Account(
                id: "\(equity):"
                    + (options.rawOptions["account_current_earnings"]?.last
                        ?? "Earnings:Current")),
            Account(
                id: "\(equity):"
                    + (options.rawOptions["account_current_conversions"]?.last
                        ?? "Conversions:Current"))
        )
    }
}
