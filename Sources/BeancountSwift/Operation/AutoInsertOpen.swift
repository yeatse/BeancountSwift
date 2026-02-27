//
//  AutoInsertOpen.swift
//
//
//  Created by Yeatse on 2024/1/28.
//

import Foundation

struct AutoInsertOpenPlugin: BeancountPlugin {
    static let name = "beancount.plugins.auto_accounts"

    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (
        entries: [Directive<Cost>], errors: [Error]
    ) {
        let openedAccounts = Set(
            entries.compactMap { entry in
                if case .open(let x) = entry.content { x.account } else { nil }
            }
        )
        var newEntries: [Directive<Cost>] = []
        let usedAccounts = entries.accountsUsage().sorted { $0.key.id < $1.key.id }
        for (index, (account, range)) in usedAccounts.indexed() {
            if openedAccounts.contains(account) {
                continue
            }
            newEntries.append(
                .init(
                    meta: ["<auto_accounts>": .number(.init(index))],
                    date: range.lowerBound,
                    content: .open(.init(account: account, currencies: [], booking: nil))
                ))
        }
        if newEntries.isEmpty {
            return (entries, [])
        } else {
            return ((newEntries + entries).sorted(), [])
        }
    }
}
