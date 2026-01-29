//
//  Realization.swift
//
//
//  Created by Yeatse on 2023/12/21.
//

import Foundation

/// A transaction posting paired with its parent transaction and directive.
///
/// TxnPosting links a posting back to its originating transaction and directive,
/// providing complete context for each posting in the realization process.
/// This is essential for tracking the full lineage of each account movement.
///
/// This corresponds to similar structures in the original Beancount Python library's
/// realization module for maintaining posting context.
///
/// ## Usage
/// ```swift
/// let txnPosting = TxnPosting(entry: directive, txn: transaction, posting: posting)
/// ```
public struct TxnPosting: Equatable {
    /// The directive that contains the transaction.
    public let entry: Directive<Cost>
    /// The transaction that contains the posting.
    public let txn: Transaction<Cost>
    /// The individual posting.
    public let posting: Posting<Cost>
}

/// Represents either a standalone directive or a transaction posting in realized accounts.
///
/// This enum allows mixing directives (like open, close, balance) with transaction
/// postings in account histories, providing a unified view of all account-related events.
///
/// ## Cases
/// - **directive**: Account-related directives (open, close, balance, etc.)
/// - **txnPosting**: Individual postings from transactions
public enum TxnPostingsType: Equatable {
    /// A standalone directive affecting the account.
    case directive(Directive<Cost>)
    /// A transaction posting affecting the account.
    case txnPosting(TxnPosting)
}

extension [TxnPostingsType] {
    fileprivate mutating func append(_ directive: Directive<Cost>) {
        append(.directive(directive))
    }

    fileprivate mutating func append(_ txnPosting: TxnPosting) {
        append(.txnPosting(txnPosting))
    }
}

extension TxnPostingsType: Comparable {
    public static func < (lhs: TxnPostingsType, rhs: TxnPostingsType) -> Bool {
        let dl =
            switch lhs {
            case .directive(let directive): directive
            case .txnPosting(let txnPosting): txnPosting.entry
            }
        let dr =
            switch rhs {
            case .directive(let directive): directive
            case .txnPosting(let txnPosting): txnPosting.entry
            }
        return dl < dr
    }
}

/// Result of iterating through balance changes for an account.
///
/// Contains the cumulative balance changes and running balance for a specific
/// directive or set of postings at a particular date.
///
/// This is used internally for computing account balances over time.
struct BalanceIterationResult {
    /// The directive being processed.
    var entry: Directive<Cost>
    /// The postings from this directive.
    var postings: [Posting<Cost>]
    /// The balance change from these postings.
    var change: Inventory
    /// The running balance after applying this change.
    var balance: Inventory
}

/// Iterator for computing balance changes over time for an account.
///
/// BalanceIterator processes transaction postings and directives chronologically,
/// maintaining running balances and computing balance changes at each point in time.
///
/// This is used internally by the realization system to track account balance evolution.
struct BalanceIterator: IteratorProtocol {
    /// The transaction postings and directives to process.
    var txnPostings: [TxnPostingsType]

    var index = 0
    var runningBalance = Inventory()

    /// Groups postings by date for processing.
    ///
    /// Internal structure for accumulating postings that occur on the same date
    /// before applying them to the running balance.
    struct DateEntryItem {
        /// The directive or transaction entry.
        var entry: Directive<Cost>
        /// All postings from this entry.
        var postings: [Posting<Cost>]
    }

    var prevDate: Date?
    var prevDateItems = [DateEntryItem]()
    var prevDateChange = Inventory()
    var dateChanged = false

    mutating func next() -> BalanceIterationResult? {
        if dateChanged && !prevDateItems.isEmpty {
            let item = prevDateItems.removeFirst()
            for posting in item.postings {
                prevDateChange.addPosition(posting)
                runningBalance.addPosition(posting)
            }
            return BalanceIterationResult(
                entry: item.entry,
                postings: item.postings,
                change: prevDateChange,
                balance: runningBalance)
        }
        dateChanged = false

        guard index < txnPostings.count else {
            return nil
        }

        let txnPosting = txnPostings[index]
        index += 1

        let posting: Posting<Cost>?
        let entry: Directive<Cost>
        switch txnPosting {
        case .directive(let directive):
            posting = nil
            entry = directive
        case .txnPosting(let txnPosting):
            posting = txnPosting.posting
            entry = txnPosting.entry
        }
        if let posting {
            if let index = prevDateItems.firstIndex(where: { $0.entry == entry }) {
                prevDateItems[index].postings.append(posting)
            } else {
                prevDateItems.append(.init(entry: entry, postings: [posting]))
            }
        } else {
            prevDateItems.append(.init(entry: entry, postings: []))
        }
        if entry.date != prevDate || index == txnPostings.count {
            prevDateChange = Inventory()
            dateChanged = true
        }
        return next()
    }
}

/// A realized account node in the account tree structure.
///
/// RealAccount represents an account with its complete transaction history,
/// current balance, and hierarchical relationship to other accounts. It forms
/// the core of the account realization system, providing a tree-like view
/// of the entire chart of accounts.
///
/// This corresponds to the `RealAccount` class in the original Beancount Python
/// library, implementing the account tree structure for reporting and analysis.
///
/// ## Usage
/// ```swift
/// let realRoot = realization.realize(entries: directives)
/// let checkingAccount = realRoot.subaccount(with: "Assets:Checking")
/// ```
public class RealAccount {
    /// The account name and path.
    fileprivate(set) public var account: Account
    /// All transaction postings and directives affecting this account.
    fileprivate(set) public var txnPostings: [TxnPostingsType]
    /// The current balance of this account.
    public var balance: Inventory

    /// Child accounts in the account hierarchy.
    fileprivate(set) public var children = [String: RealAccount]()

    init(account: Account) {
        self.account = account
        self.txnPostings = []
        self.balance = Inventory()
    }

    /// Accesses child accounts by name.
    ///
    /// Provides direct access to immediate child accounts by their component name.
    ///
    /// - Parameter key: The child account component name
    /// - Returns: The child account, or nil if it doesn't exist
    public private(set) subscript(key: String) -> RealAccount? {
        get {
            children[key]
        }
        set {
            children[key] = newValue
        }
    }
}

extension RealAccount {
    /// Finds a subaccount by its full path.
    ///
    /// Traverses the account hierarchy to find a subaccount with the given path.
    /// Returns the default value if the account doesn't exist.
    ///
    /// - Parameters:
    ///   - name: The account path (e.g., "Checking:Savings")
    ///   - default: Value to return if account doesn't exist
    /// - Returns: The found account or the default value
    public func subaccount(with name: String, default: RealAccount? = nil) -> RealAccount? {
        var current = self
        for component in name.components(separatedBy: ":") {
            if let next = current[component] {
                current = next
            } else {
                return `default`
            }
        }
        return current
    }

    /// Ensures a subaccount exists, creating it if necessary.
    ///
    /// Traverses the account hierarchy, creating any missing accounts along the path.
    /// This guarantees that the specified account exists after the call.
    ///
    /// - Parameter name: The full account path to ensure exists
    /// - Returns: The existing or newly created account
    public func ensureSubaccount(with name: String) -> RealAccount {
        var path = [String]()
        var current = self
        for component in name.components(separatedBy: ":") {
            path.append(component)
            if let next = current[component] {
                current = next
            } else {
                let next = RealAccount(account: Account(id: path.joined(separator: ":")))
                current[component] = next
                current = next
            }
        }
        return current
    }

    /// Checks if a direct child account exists.
    ///
    /// Tests whether this account has a direct child with the given name.
    ///
    /// - Parameter name: The child account component name
    /// - Returns: True if the child exists
    public func contains(_ name: String) -> Bool {
        children.keys.contains(name)
    }

    /// Creates a filtered copy of the account tree.
    ///
    /// Recursively filters the account tree, including only accounts that
    /// satisfy the predicate or have descendants that do. The result is
    /// a new tree containing only the matching accounts and their paths.
    ///
    /// - Parameter predicate: Function to test each account
    /// - Returns: Filtered account tree, or nil if no accounts match
    public func filtered(with predicate: (RealAccount) -> Bool) -> RealAccount? {
        let realCopy = RealAccount(account: account)
        realCopy.balance = balance
        realCopy.txnPostings = txnPostings

        for (name, child) in children {
            if let childCopy = child.filtered(with: predicate) {
                realCopy[name] = childCopy
            }
        }

        if !realCopy.children.isEmpty || predicate(self) {
            return realCopy
        } else {
            return nil
        }
    }

    /// Returns all descendant accounts in this subtree.
    ///
    /// Provides a sequence of all accounts under this account in the hierarchy.
    /// Can be limited to leaf accounts only (accounts with no children).
    ///
    /// - Parameter leafOnly: If true, returns only leaf accounts
    /// - Returns: Sequence of all descendant accounts
    public func childAccounts(leafOnly: Bool = false) -> some Sequence<RealAccount> {
        AnySequence {
            var stack: [RealAccount] = [self]
            return AnyIterator {
                while let current = stack.popLast() {
                    if !leafOnly || current.children.isEmpty {
                        stack.append(contentsOf: current.children.values)
                        return current
                    } else if !current.children.isEmpty {
                        stack.append(contentsOf: current.children.values)
                    }
                }
                return nil
            }
        }.lazy
    }

    /// All postings from this account and its descendants.
    ///
    /// Collects and sorts all transaction postings from this account and
    /// all its child accounts, providing a comprehensive view of activity.
    ///
    /// - Returns: Sorted array of all postings in this subtree
    public var postings: [TxnPostingsType] {
        childAccounts().flatMap(\.txnPostings).sorted()
    }

    /// Computes the total balance for this account and its descendants.
    ///
    /// Aggregates balances from this account and all child accounts to compute
    /// a total balance. Can be limited to leaf accounts only for certain calculations.
    ///
    /// - Parameter leafOnly: If true, includes only leaf account balances
    /// - Returns: The aggregated inventory balance
    public func computeBalance(leafOnly: Bool = false) -> Inventory {
        childAccounts(leafOnly: leafOnly).map(\.balance).reduce(Inventory(), +)
    }
}

/// The main realization engine for building account trees from directives.
///
/// Realization processes a list of Beancount directives and constructs a hierarchical
/// tree of accounts with their complete transaction histories and balances. This is
/// the foundation for all account-based reporting and analysis in Beancount.
///
/// This corresponds to the realization functionality in the original Beancount Python
/// library, providing the same tree-building and balance computation capabilities.
///
/// ## Usage
/// ```swift
/// let accountTree = Realization.realize(entries: directives)
/// ```
public enum Realization {
    /// Builds the realized account tree from a list of directives.
    ///
    /// Processes all directives to create a complete account tree with transaction
    /// histories and balances. This is the primary entry point for realization.
    ///
    /// - Parameters:
    ///   - entries: The directives to process
    ///   - computeBalance: Whether to compute account balances (default: true)
    /// - Returns: The root of the realized account tree
    public static func realize(entries: [Directive<Cost>], computeBalance: Bool = true)
        -> RealAccount
    {
        let txnPostingsMap = groupPostingsByAccount(entries)
        let realRoot = RealAccount(account: .empty)
        for (accountName, txnPostings) in txnPostingsMap {
            let realAccount = realRoot.ensureSubaccount(with: accountName.id)
            realAccount.txnPostings = txnPostings
            if computeBalance {
                realAccount.balance = Self.computeBalance(in: txnPostings)
            }
        }
        return realRoot
    }

    /// Groups directives and postings by the accounts they affect.
    ///
    /// Processes all directives and extracts account-affecting information,
    /// grouping them by account for tree construction. Transaction postings
    /// are converted to TxnPosting instances for full context preservation.
    ///
    /// - Parameter entries: The directives to process
    /// - Returns: Dictionary mapping accounts to their affecting directives and postings
    static func groupPostingsByAccount(_ entries: [Directive<Cost>]) -> [Account: [TxnPostingsType]]
    {
        var txnPostingsMap = [Account: [TxnPostingsType]]()
        for entry in entries {
            switch entry.content {
            case .transaction(let transaction):
                for posting in transaction.postings {
                    let item = TxnPosting(entry: entry, txn: transaction, posting: posting)
                    txnPostingsMap[posting.account, default: []].append(item)
                }
            case .open(let open):
                txnPostingsMap[open.account, default: []].append(entry)
            case .close(let close):
                txnPostingsMap[close.account, default: []].append(entry)
            case .pad(let pad):
                txnPostingsMap[pad.account, default: []].append(entry)
                txnPostingsMap[pad.sourceAccount, default: []].append(entry)
            case .balance(let balance):
                txnPostingsMap[balance.account, default: []].append(entry)
            case .note(let note):
                txnPostingsMap[note.account, default: []].append(entry)
            case .document(let document):
                txnPostingsMap[document.account, default: []].append(entry)
            case .custom(let custom):
                for customValue in custom.values {
                    if case .account(let account) = customValue {
                        txnPostingsMap[account, default: []].append(entry)
                    }
                }
            case .commodity(_), .event(_), .query(_), .price(_):
                break
            }
        }
        return txnPostingsMap
    }

    /// Computes the balance for a list of postings and directives.
    ///
    /// Aggregates all transaction postings to compute the net balance for an account.
    /// Non-posting directives (like open, close) don't affect the balance calculation.
    ///
    /// - Parameter postings: The postings and directives to process
    /// - Returns: The net inventory balance
    static func computeBalance(in postings: [TxnPostingsType]) -> Inventory {
        var balance = Inventory()
        for posting in postings {
            if case .txnPosting(let txnPosting) = posting {
                balance.addPosition(txnPosting.posting)
            }
        }
        return balance
    }

    /// Returns a sequence of balance changes over time for an account.
    ///
    /// Provides a chronological sequence showing how an account's balance
    /// changes with each directive or transaction, useful for balance validation
    /// and historical analysis.
    ///
    /// - Parameter postings: The postings and directives to iterate through
    /// - Returns: Sequence of balance changes over time
    static func balanceChanges(in postings: [TxnPostingsType]) -> any Sequence<
        BalanceIterationResult
    > {
        AnySequence {
            BalanceIterator(txnPostings: postings)
        }.lazy
    }
}
