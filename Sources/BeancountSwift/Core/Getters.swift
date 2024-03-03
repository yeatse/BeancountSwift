//
//  Getters.swift
//
//
//  Created by 杨超 on 2024/2/15.
//

import Foundation

extension RandomAccessCollection {
    public func gatherAccountUsage<T>() -> [Account: ClosedRange<Date>] where Element == Directive<T> {
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
    
    public func gatherAccounts<T>() -> Set<Account> where Element == Directive<T> {
        return Set(gatherAccountUsage().keys)
    }
    
    public func gatherOpenCloses<T>() -> [Account: (DirectiveValue<T, Open>?, DirectiveValue<T, Close>?)] where Element == Directive<T> {
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
}

extension Directive {
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
