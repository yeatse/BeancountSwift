//
//  Getters.swift
//
//
//  Created by 杨超 on 2024/2/15.
//

/// Provides collection extensions for extracting information from Beancount directives.
///
/// This module implements various getter methods that analyze collections of directives
/// to extract useful information like account usage, tags, payees, and other metadata.
/// These methods are essential for reporting, analysis, and data extraction from ledgers.
///
/// The functionality corresponds to similar getter functions in the original Beancount
/// Python library, providing efficient ways to query and analyze ledger data.

import Foundation
import OrderedCollections

extension RandomAccessCollection {
    /// Returns the date ranges when each account was used.
    ///
    /// Analyzes all directives to determine the first and last dates when each
    /// account was referenced, providing insight into account activity periods.
    ///
    /// - Returns: A dictionary mapping accounts to their usage date ranges
    public func accountsUsage<T>() -> [Account: ClosedRange<Date>] where Element == Directive<T> {
        var result: [Account: ClosedRange<Date>] = [:]
        func book(account: Account, date: Date) {
            if let range = result[account] {
                let lower = date < range.lowerBound ? date : range.lowerBound
                let upper = date > range.upperBound ? date : range.upperBound
                result[account] = lower...upper
            } else {
                result[account] = date...date
            }
        }
        for directive in self {
            switch directive.content {
            case .open(let x):
                book(account: x.account, date: directive.date)
            case .close(let x):
                book(account: x.account, date: directive.date)
            case .pad(let x):
                book(account: x.account, date: directive.date)
                book(account: x.sourceAccount, date: directive.date)
            case .balance(let x):
                book(account: x.account, date: directive.date)
            case .transaction(let x):
                x.postings.forEach { posting in
                    book(account: posting.account, date: directive.date)
                }
            case .note(let x):
                book(account: x.account, date: directive.date)
            case .document(let x):
                book(account: x.account, date: directive.date)
            default:
                break
            }
        }
        return result
    }

    /// Returns all accounts referenced in the directives.
    ///
    /// Extracts all unique accounts mentioned across all directives in the collection,
    /// providing a comprehensive set of all accounts used in the ledger.
    ///
    /// - Returns: A set of all accounts referenced in the directives
    public func allAccounts<T>() -> Set<Account> where Element == Directive<T> {
        return Set(accountsUsage().keys)
    }

    /// Returns the open and close directives for each account.
    ///
    /// Maps each account to its corresponding open and close directives,
    /// handling cases where accounts may only have open directives or may
    /// have been reopened. Uses the latest directive of each type.
    ///
    /// - Returns: A dictionary mapping accounts to their open/close directive pairs
    public func accountOpenClose<T>() -> [Account: (
        DirectiveValue<T, Open>?, DirectiveValue<T, Close>?
    )] where Element == Directive<T> {
        var openClose = [Account: (DirectiveValue<T, Open>?, DirectiveValue<T, Close>?)]()
        for entry in self {
            switch entry.content {
            case .open(let x):
                if let previous = openClose[x.account] {
                    if let previousOpen = previous.0?.directive, previousOpen.date > entry.date {
                        continue
                    } else {
                        openClose[x.account] = (DirectiveValue(entry, x), previous.1)
                    }
                } else {
                    openClose[x.account] = (DirectiveValue(entry, x), nil)
                }
            case .close(let x):
                if let previous = openClose[x.account] {
                    if let previousClose = previous.1?.directive, previousClose.date > entry.date {
                        continue
                    } else {
                        openClose[x.account] = (previous.0, DirectiveValue(entry, x))
                    }
                } else {
                    openClose[x.account] = (nil, DirectiveValue(entry, x))
                }
            default:
                break
            }
        }
        return openClose
    }

    /// Returns all tags used in transactions.
    ///
    /// Collects all unique tags from transaction directives and returns them
    /// in a sorted ordered set for consistent iteration and display.
    ///
    /// - Returns: An ordered set of all tags used in transactions
    public func allTags<T>() -> OrderedSet<Tag> where Element == Directive<T> {
        var tags: Set<Tag> = []
        for entry in self {
            if case .transaction(let txn) = entry.content {
                tags.formUnion(txn.tags)
            }
        }
        return OrderedSet(tags.sorted())
    }

    /// Returns all payees mentioned in transactions.
    ///
    /// Extracts all unique payee names from transaction directives, providing
    /// a comprehensive list of all transaction counterparties.
    ///
    /// - Returns: An ordered set of all payee names from transactions
    public func allPayees<T>() -> OrderedSet<String> where Element == Directive<T> {
        var payees: Set<String> = []
        for entry in self {
            if case .transaction(let txn) = entry.content, let payee = txn.payee {
                payees.insert(payee)
            }
        }
        return OrderedSet(payees.sorted())
    }

    /// Returns all links used in transactions.
    ///
    /// Collects all unique links from transaction directives, which are used
    /// to connect related transactions across the ledger.
    ///
    /// - Returns: An ordered set of all links used in transactions
    public func allLinks<T>() -> OrderedSet<Link> where Element == Directive<T> {
        var links: Set<Link> = []
        for entry in self {
            if case .transaction(let txn) = entry.content {
                links.formUnion(txn.links)
            }
        }
        return OrderedSet(links.sorted())
    }

    /// Returns all commodity directives indexed by currency.
    ///
    /// Collects all commodity declaration directives and indexes them by their
    /// currency for efficient lookup. Provides access to currency metadata and
    /// declaration information.
    ///
    /// - Returns: A dictionary mapping currencies to their commodity directives
    public func allCommodityDirectives<T>() -> OrderedDictionary<
        Currency, DirectiveValue<T, Commodity>
    > where Element == Directive<T> {
        var result = OrderedDictionary<Currency, DirectiveValue<T, Commodity>>()
        for entry in self {
            if case .commodity(let commodity) = entry.content {
                result[commodity.currency] = .init(entry, commodity)
            }
        }
        return result
    }
}

extension Directive {
    /// Returns all accounts referenced by this directive.
    ///
    /// Extracts all account references from a single directive, including
    /// transaction postings, pad source accounts, and other account-related
    /// directive content.
    ///
    /// - Returns: A set of all accounts referenced by this directive
    public func usedAccounts() -> Set<Account> {
        var result = Set<Account>()
        switch content {
        case .transaction(let txn):
            txn.postings.map(\.account).forEach { result.insert($0) }
        case .pad(let pad):
            result.insert(pad.account)
            result.insert(pad.sourceAccount)
        case .open(let open):
            result.insert(open.account)
        case .close(let close):
            result.insert(close.account)
        case .balance(let balance):
            result.insert(balance.account)
        case .note(let note):
            result.insert(note.account)
        case .document(let document):
            result.insert(document.account)
        default:
            break
        }
        return result
    }
}
