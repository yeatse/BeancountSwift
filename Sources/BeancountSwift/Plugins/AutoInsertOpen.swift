//
//  AutoInsertOpen.swift
//  
//
//  Created by Yeatse on 2024/1/28.
//

import Foundation

struct AutoInsertOpenPlugin: BeancountPlugin {
    static let name = "auto_insert_open"
    
    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (
        entries: [Directive<Cost>], errors: [Error]
    ) {
        var newEntries = entries
        let openedAccounts = Set(
            entries.compactMap { entry in
                if case let .open(open) = entry.content {
                    open.account
                } else {
                    nil
                }
            }
        )
        var usedAccounts = [Account: Date]()
        for entry in entries {
            let accounts: [Account] =
                switch entry.content {
                case .open(let x): [x.account]
                case .close(let x): [x.account]
                case .commodity(_): []
                case .pad(let x): [x.account, x.sourceAccount]
                case .balance(let x): [x.account]
                case .transaction(let x): x.postings.map(\.account)
                case .note(let x): [x.account]
                case .event: []
                case .query: []
                case .price: []
                case .document: []
                case .custom: []
                }
            for account in accounts {
                if let date = usedAccounts[account], entry.date >= date {
                    continue
                }
                usedAccounts[account] = entry.date
            }
        }
        for (account, date) in usedAccounts {
            if !openedAccounts.contains(account) {
                newEntries.insert(
                    .init(
                        meta: ["<auto_accounts>": .bool(true)],
                        date: date,
                        content: .open(.init(account: account, currencies: [], booking: nil))
                    ),
                    at: 0
                )
            }
        }
        return (newEntries.sorted(), [])
    }
}
