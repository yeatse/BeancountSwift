//
//  Realization.swift
//
//
//  Created by Yeatse on 2023/12/21.
//

import Foundation

/// A pair of a Posting and its parent Transaction. This is inserted as
/// temporaries in lists of postings-of-entries, which is the product of a
/// realization.
public struct TxnPosting: Equatable {
    public let entry: Directive<Cost>
    public let txn: Transaction<Cost>
    public let posting: Posting<Cost>
}

public enum TxnPostingsType: Equatable {
    case directive(Directive<Cost>)
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

struct BalanceIterationResult {
    var entry: Directive<Cost>
    var postings: [Posting<Cost>]
    var change: Inventory
    var balance: Inventory
}

struct BalanceIterator: IteratorProtocol {
    var txnPostings: [TxnPostingsType]
    
    var index = 0
    var runningBalance = Inventory()
    
    struct DateEntryItem {
        var entry: Directive<Cost>
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

/// A realized account, inserted in a tree, that contains the list of realized entries.
public class RealAccount {
    fileprivate(set) public var account: Account
    fileprivate(set) public var txnPostings: [TxnPostingsType]
    public var balance: Inventory
    
    fileprivate(set) public var children = [String: RealAccount]()
    
    init(account: Account) {
        self.account = account
        self.txnPostings = []
        self.balance = Inventory()
    }
    
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
    func subaccount(with name: String, default: RealAccount? = nil) -> RealAccount? {
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
    
    func ensureSubaccount(with name: String) -> RealAccount {
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
    
    func contains(_ name: String) -> Bool {
        children.keys.contains(name)
    }
    
    func filtered(with predicate: (RealAccount) -> Bool) -> RealAccount? {
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
    
    public var postings: [TxnPostingsType] {
        childAccounts().flatMap(\.txnPostings).sorted()
    }
    
    public func computeBalance(leafOnly: Bool = false) -> Inventory {
        childAccounts(leafOnly: leafOnly).map(\.balance).reduce(Inventory(), +)
    }
}

public struct Realization {
    public func realize(entries: [Directive<Cost>], computeBalance: Bool = true) -> RealAccount {
        let txnPostingsMap = groupPostingsByAccount(entries)
        let realRoot = RealAccount(account: .empty)
        for (accountName, txnPostings) in txnPostingsMap {
            let realAccount = realRoot.ensureSubaccount(with: accountName.id)
            realAccount.txnPostings = txnPostings
            if computeBalance {
                realAccount.balance = self.computeBalance(in: txnPostings)
            }
        }
        return realRoot
    }
    
    func groupPostingsByAccount(_ entries: [Directive<Cost>]) -> [Account: [TxnPostingsType]] {
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
    
    func computeBalance(in postings: [TxnPostingsType]) -> Inventory {
        var balance = Inventory()
        for posting in postings {
            if case .txnPosting(let txnPosting) = posting {
                balance.addPosition(txnPosting.posting)
            }
        }
        return balance
    }
    
    func balanceChanges(in postings: [TxnPostingsType]) -> any Sequence<BalanceIterationResult> {
        AnySequence {
            BalanceIterator(txnPostings: postings)
        }.lazy
    }
}
