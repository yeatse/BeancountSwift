//
//  Pad.swift
//
//
//  Created by Yeatse on 2024/1/28.
//

import Foundation

struct PadPlugin: BeancountPlugin {
    static let name = "pad"
    static let automaticPad = "__automatic__"

    enum PadError: LocatableError, LocalizedError {
        case padWithCost(pad: Directive<Cost>)
        case negativePosition(pos: Position)
        case unusedPad(pad: Directive<Cost>)

        var location: LedgerLocation? {
            switch self {
            case .padWithCost(let pad), .unusedPad(let pad):
                if let filename = pad.meta.filename, let lineno = pad.meta.lineno {
                    return LedgerLocation(filename: filename, lineno: lineno)
                }
            case .negativePosition:
                break
            }
            return nil
        }

        var errorDescription: String? {
            switch self {
            case .padWithCost:
                "Pad directive cannot be applied to postings with cost"
            case .negativePosition(let pos):
                "Padding created negative position: \"\(pos)\""
            case .unusedPad:
                "Unused Pad directive"
            }
        }
    }

    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (
        entries: [Directive<Cost>], errors: [Error]
    ) {
        var padErrors: [Error] = []

        // Use (filename, lineno) as a stable identity key for each pad directive.
        // Keying by lineno alone collides across files, which caused pad
        // padding transactions to be inserted under sibling pads in other files.
        struct PadKey: Hashable {
            var filename: String?
            var lineno: Int?
        }

        struct PadState {
            var activePad: DirectiveValue<Cost, Pad>? = nil
            var padBalance = Inventory()
            var paddedLots: Set<Currency> = []
        }

        // Collect the set of distinct accounts being padded.
        var states: [Account: PadState] = [:]
        for entry in entries {
            if case .pad(let pad) = entry.content {
                if states[pad.account] == nil {
                    states[pad.account] = PadState()
                }
            }
        }
        if states.isEmpty {
            return (entries, [])
        }

        var newEntries: [PadKey: [Directive<Cost>]] = [:]

        // Walk all entries once in chronological order, maintaining per-pad-account
        // running balances. For each posting / balance, find the ancestor accounts
        // that are being padded and update / check their state accordingly.
        let sortedEntries = entries.sorted()

        // Cache resolved ancestor pad accounts per encountered account.
        var ancestorCache: [Account: [Account]] = [:]
        func paddedAncestors(of account: Account) -> [Account] {
            if let cached = ancestorCache[account] { return cached }
            var result: [Account] = []
            var current: Account? = account
            while let acc = current {
                if states[acc] != nil {
                    result.append(acc)
                }
                current = acc.parent
            }
            ancestorCache[account] = result
            return result
        }

        for entry in sortedEntries {
            switch entry.content {
            case .transaction(let txn):
                for posting in txn.postings {
                    for padAccount in paddedAncestors(of: posting.account) {
                        states[padAccount]?.padBalance.addPosition(posting)
                    }
                }
            case .pad(let pad):
                if states[pad.account] != nil {
                    states[pad.account]?.activePad = DirectiveValue(entry, pad)
                    states[pad.account]?.paddedLots = []
                }
            case .balance(let balance):
                for padAccount in paddedAncestors(of: balance.account) {
                    let checkAmount = balance.amount
                    guard var state = states[padAccount] else { continue }
                    let balanceAmount = state.padBalance.getCurrencyUnits(in: checkAmount.currency)
                    let diffAmount = balanceAmount - checkAmount
                    let tolerance = balance.tolerance(options: options)
                    if diffAmount.number.magnitude > tolerance,
                        let activePad = state.activePad,
                        !state.paddedLots.contains(checkAmount.currency)
                    {
                        for position in state.padBalance.positions
                        where position.units.currency == checkAmount.currency {
                            if position.cost != nil {
                                padErrors.append(
                                    PadError.padWithCost(pad: activePad.directive))
                            }
                        }
                        let diffPosition = Position(
                            units: Amount(
                                number: checkAmount.number - balanceAmount.number,
                                currency: checkAmount.currency))

                        let narration =
                            "(Padding inserted for Balance of \(checkAmount) for difference \(diffPosition))"
                        let negDiffPosition = -diffPosition
                        let transaction = Transaction(
                            flag: .paddingFlag,
                            payee: nil,
                            narration: narration,
                            tags: [],
                            links: [],
                            postings: [
                                Posting(
                                    account: activePad.content.account,
                                    units: diffPosition.units,
                                    cost: diffPosition.cost,
                                    meta: activePad.directive.meta.merging(
                                        [
                                            PadPlugin.automaticPad: .string(
                                                UUID().uuidString)
                                        ], uniquingKeysWith: { $1 })),
                                Posting(
                                    account: activePad.content.sourceAccount,
                                    units: negDiffPosition.units,
                                    cost: negDiffPosition.cost,
                                    meta: activePad.directive.meta.merging(
                                        [
                                            PadPlugin.automaticPad: .string(
                                                UUID().uuidString)
                                        ], uniquingKeysWith: { $1 })),
                            ])
                        let newEntry = Directive(
                            meta: activePad.directive.meta.merging(
                                [
                                    PadPlugin.automaticPad: .string(UUID().uuidString)
                                ], uniquingKeysWith: { $1 }),
                            date: activePad.directive.date,
                            content: .transaction(transaction))
                        let padKey = PadKey(
                            filename: activePad.directive.meta.filename,
                            lineno: activePad.directive.meta.lineno)
                        newEntries[padKey, default: []].append(newEntry)
                        let (pos, _) = state.padBalance.addPosition(diffPosition)
                        if let pos, pos.isNegativeAtCost {
                            padErrors.append(PadError.negativePosition(pos: pos))
                        }
                    }
                    state.paddedLots.insert(checkAmount.currency)
                    states[padAccount] = state
                }
            default:
                break
            }
        }

        var paddedEntries: [Directive<Cost>] = []
        paddedEntries.reserveCapacity(entries.count + newEntries.values.reduce(0) { $0 + $1.count })
        for entry in entries {
            paddedEntries.append(entry)
            guard case .pad = entry.content else { continue }
            let padKey = PadKey(filename: entry.meta.filename, lineno: entry.meta.lineno)
            if let entryList = newEntries[padKey] {
                paddedEntries += entryList
            } else {
                padErrors.append(PadError.unusedPad(pad: entry))
            }
        }
        return (paddedEntries, padErrors)
    }
}
