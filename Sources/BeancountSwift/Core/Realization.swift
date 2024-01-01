//
//  Realization.swift
//
//
//  Created by Yeatse on 2023/12/21.
//

/// A pair of a Posting and its parent Transaction. This is inserted as
/// temporaries in lists of postings-of-entries, which is the product of a
/// realization.
public struct TxnPosting {
    public let entry: Directive<Cost>
    public let txn: Transaction<Cost>
    public let posting: Posting<Cost>
}

enum TxnPostingsType {
    case directive(Directive<Cost>)
    case txnPosting(TxnPosting)
    case posting(Posting<Cost>)
}

/// A realized account, inserted in a tree, that contains the list of realized entries.
class RealAccount {
    fileprivate(set) var account: Account
    fileprivate(set) var txnPostings: [TxnPostingsType]
    fileprivate(set) var balance: Inventory

    private var children = [String: RealAccount]()

    init(account: Account) {
        self.account = account
        self.txnPostings = []
        self.balance = Inventory()
    }

    subscript(key: String) -> RealAccount? {
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
}

struct Realization {
    func realize(entries: [Directive<Cost>], computeBalance: Bool = true) -> RealAccount {
        let txnPostingsMap = groupPostingsByAccount(entries)
        let realRoot = RealAccount(account: "")
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
                    txnPostingsMap[posting.account, default: []].append(.txnPosting(item))
                }
            case .open(let open):
                txnPostingsMap[open.account, default: []].append(.directive(entry))
            case .close(let close):
                txnPostingsMap[close.account, default: []].append(.directive(entry))
            case .pad(let pad):
                txnPostingsMap[pad.account, default: []].append(.directive(entry))
                txnPostingsMap[pad.sourceAccount, default: []].append(.directive(entry))
            case .balance(let balance):
                txnPostingsMap[balance.account, default: []].append(.directive(entry))
            case .note(let note):
                txnPostingsMap[note.account, default: []].append(.directive(entry))
            case .document(let document):
                txnPostingsMap[document.account, default: []].append(.directive(entry))
            case .custom(let custom):
                for customValue in custom.values {
                    if case .account(let account) = customValue {
                        txnPostingsMap[account, default: []].append(.directive(entry))
                    }
                }
            case .commodity(_), .event(_), .query(_), .price(_):
                break
            }
        }
        return txnPostingsMap
    }

    func computeBalance(in postings: [TxnPostingsType]) -> Inventory {
        let finalBalance = Inventory()
        for posting in postings {
            switch posting {
            case .directive(_): break
            case .txnPosting(let txnPosting):
                finalBalance.addPosition(txnPosting.posting)
            case .posting(let posting):
                finalBalance.addPosition(posting)
            }
        }
        return finalBalance
    }
}
