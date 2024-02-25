//
//  Balance.swift
//
//
//  Created by Yeatse on 2024/1/29.
//

import Foundation

extension Balance {
    func tolerance(options: Options) -> Decimal {
        if let tolerance {
            return tolerance
        } else {
            let lsd = amount.number.leastSignificantDigit
            if lsd < 1 {
                return lsd * options.tolerances.multiplier * 2
            } else {
                return .zero
            }
        }
    }
}

enum BalanceError: Error {
    case unknownAccount(account: Account)
    case invalidCurrency(currency: Currency)
    case balanceFailed(account: Account, expected: Amount, balance: Amount)
}

struct BalanceCheckPlugin: BeancountPlugin {
    static let name = "check"
    
    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (entries: [Directive<Cost>], errors: [Error]) {
        var newEntries: [Directive<Cost>] = []
        var errors: [Error] = []
        
        let realRoot = RealAccount(account: .init(id: ""))
        let assertedAccounts = entries.compactMap { entry in
            if case .balance(let x) = entry.content { x.account } else { nil }
        }
        for account in entries.gatherAccounts() {
            if assertedAccounts.contains(account) || assertedAccounts.contains(where: { asserted in
                account.isChild(of: asserted)
            }) {
                let _ = realRoot.ensureSubaccount(with: account.id)
            }
        }
        let openCloseMap = entries.gatherOpenCloses()
        for entry in entries {
            var newEntry = entry
            switch entry.content {
                case .transaction(let transaction):
                    for posting in transaction.postings {
                        if let realAccount = realRoot.subaccount(with: posting.account.id) {
                            realAccount.balance.addPosition(posting)
                        }
                    }
                case .balance(let balance):
                    let expectedAmount = balance.amount
                    guard let openClose = openCloseMap[balance.account] else {
                        errors.append(BalanceError.unknownAccount(account: balance.account))
                        continue
                    }
                    if let open = openClose.0,
                       !open.content.currencies.isEmpty,
                       !open.content.currencies.contains(expectedAmount.currency)
                    {
                        errors.append(BalanceError.invalidCurrency(currency: expectedAmount.currency))
                    }
                    let realAcount = realRoot.subaccount(with: balance.account.id)!
                    let subtreeBalance = realAcount.computeBalance()
                    let balanceAmount = subtreeBalance.getCurrencyUnits(in: expectedAmount.currency)
                    let diffAmount = balanceAmount - expectedAmount
                    let tolerance = balance.tolerance(options: options)
                    if diffAmount.number.magnitude > tolerance {
                        errors.append(BalanceError.balanceFailed(
                            account: balance.account,
                            expected: expectedAmount,
                            balance: balanceAmount
                        ))
                        newEntry.content = .balance(.init(
                            account: balance.account,
                            amount: balance.amount,
                            tolerance: balance.tolerance,
                            diffAmount: diffAmount))
                    }
                default:
                    break
            }
            newEntries.append(newEntry)
        }
        return (newEntries, errors)
    }
}
