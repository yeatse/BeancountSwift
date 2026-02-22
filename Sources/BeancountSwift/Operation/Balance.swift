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
            let lsd = amount.leastSignificantDigit
            if lsd < 1 {
                return lsd * options.tolerances.multiplier * 2
            } else {
                return .zero
            }
        }
    }
}

enum BalanceError: LocatableError, LocalizedError {
    case unknownAccount(account: Account, entry: Directive<Cost>)
    case invalidCurrency(currency: Currency, entry: Directive<Cost>)
    case balanceFailed(account: Account, expected: Amount, balance: Amount, entry: Directive<Cost>)

    var location: LedgerLocation? {
        func getLocation(_ entry: Directive<Cost>) -> LedgerLocation? {
            if let filename = entry.meta.filename, let lineno = entry.meta.lineno {
                return LedgerLocation(filename: filename, lineno: lineno)
            } else {
                return nil
            }
        }
        return switch self {
        case .unknownAccount(_, let entry): getLocation(entry)
        case .invalidCurrency(_, let entry): getLocation(entry)
        case .balanceFailed(_, _, _, let entry): getLocation(entry)
        }
    }

    var errorDescription: String? {
        switch self {
        case .unknownAccount(let account, _):
            return "Invalid reference to unknown account '\(account.id)'"
        case .invalidCurrency(let currency, _):
            return "Invalid currency '\(currency.id)' for Balance directive"
        case .balanceFailed(let account, let expected, let balance, _):
            let diff = balance - expected
            let direction = diff.number > 0 ? "too much" : "too little"
            return
                "Balance failed for '\(account.id)': expected \(expected) != accumulated \(balance) (\(abs(diff.number)) \(direction))"
        }
    }
}

struct BalanceCheckPlugin: BeancountPlugin {
    static let name = "check"

    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (
        entries: [Directive<Cost>], errors: [Error]
    ) {
        var newEntries: [Directive<Cost>] = []
        var errors: [Error] = []

        let realRoot = RealAccount(account: .init(id: ""))
        let assertedAccounts = entries.compactMap { entry in
            if case .balance(let x) = entry.content { x.account } else { nil }
        }
        for account in entries.allAccounts() {
            if assertedAccounts.contains(account)
                || assertedAccounts.contains(where: { asserted in
                    account.isChild(of: asserted)
                })
            {
                let _ = realRoot.ensureSubaccount(with: account.id)
            }
        }
        let openCloseMap = entries.accountOpenClose()
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
                let openClose = openCloseMap[balance.account]
                if openClose == nil {
                    errors.append(
                        BalanceError.unknownAccount(account: balance.account, entry: entry))
                }

                if let openClose = openClose,
                    let open = openClose.0,
                    !open.content.currencies.isEmpty,
                    !open.content.currencies.contains(expectedAmount.currency)
                {
                    errors.append(
                        BalanceError.invalidCurrency(
                            currency: expectedAmount.currency, entry: entry))
                }

                if let realAcount = realRoot.subaccount(with: balance.account.id) {
                    let subtreeBalance = realAcount.computeBalance()
                    let balanceAmount = subtreeBalance.getCurrencyUnits(in: expectedAmount.currency)
                    let diffAmount = balanceAmount - expectedAmount
                    let tolerance = balance.tolerance(options: options)
                    if diffAmount.number.magnitude > tolerance {
                        errors.append(
                            BalanceError.balanceFailed(
                                account: balance.account,
                                expected: expectedAmount,
                                balance: balanceAmount,
                                entry: entry
                            ))
                        newEntry.content = .balance(
                            .init(
                                account: balance.account,
                                amount: balance.amount,
                                tolerance: balance.tolerance,
                                diffAmount: diffAmount))
                    }
                }
            default:
                break
            }
            newEntries.append(newEntry)
        }
        return (newEntries, errors)
    }
}
