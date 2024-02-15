//
//  Pad.swift
//
//
//  Created by Yeatse on 2024/1/28.
//

import Foundation

struct PadPlugin: BeancountPlugin {
    static let name = "pad"
    
    let realization = Realization()
    
    enum PadError: Error {
        case padWithCost(pad: Directive<Cost>)
        case negativePosition(pos: Position)
        case unusedPad(pad: Directive<Cost>)
    }
    
    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (entries: [Directive<Cost>], errors: [Error]) {
        var padErrors: [Error] = []
        
        let pads = entries.compactMap { entry in
            if case .pad(let pad) = entry.content {
                return DirectiveValue(entry, pad)
            } else {
                return nil
            }
        }
        let padDict = pads.grouped(by: \.content.account)
        let byAccount = realization.groupPostingsByAccount(entries)
        var newEntries: [UInt32: [Directive<Cost>]] = [:]
        
        // FIXME: padDict should be sorted by account
        for (account, _) in padDict {
            var activePad: DirectiveValue<Cost, Pad>? = nil
            var postings: [TxnPostingsType] = []
            for (itemAccount, itemPostings) in byAccount {
                if itemAccount.isChild(of: account) {
                    postings += itemPostings
                }
            }
            postings.sort()
            
            var paddedLots: Set<Currency> = []
            var padBalance = Inventory()
            
            for entry in postings {
                switch entry {
                    case .txnPosting(let txnPosting):
                        padBalance.addPosition(txnPosting.posting)
                    case .directive(let directive):
                        switch directive.content {
                            case .pad(let pad):
                                if pad.account == account {
                                    activePad = DirectiveValue(directive, pad)
                                    paddedLots = []
                                }
                            case .balance(let balance):
                                let checkAmount = balance.amount
                                let balanceAmount = padBalance.getCurrencyUnits(in: checkAmount.currency)
                                let diffAmount = balanceAmount - checkAmount
                                let tolerance = balance.tolerance(options: options)
                                if diffAmount.number.magnitude > tolerance {
                                    if let activePad, !paddedLots.contains(checkAmount.currency) {
                                        let positions = padBalance.positions.filter { $0.units.currency == checkAmount.currency }
                                        for position in positions {
                                            if position.cost != nil {
                                                padErrors.append(PadError.padWithCost(pad: activePad.directive))
                                            }
                                        }
                                        let diffPosition = Position(units: Amount(number: checkAmount.number - balanceAmount.number, currency: checkAmount.currency))
                                        
                                        let narration = "(Padding inserted for Balance of \(checkAmount) for difference \(diffPosition))"
                                        let negDiffPosition = -diffPosition
                                        let transaction = Transaction(flag: .paddingFlag,
                                                                      payee: nil,
                                                                      narration: narration,
                                                                      tags: [],
                                                                      links: [],
                                                                      postings: [
                                                                        Posting(account: activePad.content.account,
                                                                                units: diffPosition.units,
                                                                                cost: diffPosition.cost),
                                                                        Posting(account: activePad.content.sourceAccount,
                                                                                units: negDiffPosition.units,
                                                                                cost: negDiffPosition.cost)
                                                                      ])
                                        let newEntry = Directive(meta: activePad.directive.meta,
                                                                 date: activePad.directive.date,
                                                                 content: .transaction(transaction))
                                        if let lineno = activePad.directive.meta.lineno {
                                            newEntries[lineno, default: []].append(newEntry)
                                        }
                                        let (pos, _) = padBalance.addPosition(diffPosition)
                                        if let pos, pos.isNegativeAtCost {
                                            padErrors.append(PadError.negativePosition(pos: pos))
                                        }
                                    }
                                }
                                paddedLots.insert(checkAmount.currency)
                            default:
                                break
                        }
                }
            }
        }
        var paddedEntries: [Directive<Cost>] = []
        for entry in entries {
            paddedEntries.append(entry)
            if case .pad = entry.content {
                if let lineno = entry.meta.lineno, let entryList = newEntries[lineno] {
                    paddedEntries += entryList
                } else {
                    padErrors.append(PadError.unusedPad(pad: entry))
                }
            }
        }
        return (paddedEntries, padErrors)
    }
}
