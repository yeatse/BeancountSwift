//
//  Plugin.swift
//
//
//  Created by Yeatse on 2024/1/1.
//

import Foundation

struct Plugin {
    let name: String
    let config: String?
}

extension Plugin {
    func process(entries: [Directive<Cost>], options: [Option]) -> (
        entries: [Directive<Cost>], errors: [Error]
    ) {
        guard let plugin = allPlugins[name] else {
            return (entries, [PluginError.notImplemented(name)])
        }
        do {
            return try plugin.process(entries: entries, options: options, config: config)
        } catch {
            return (entries, [error])
        }
    }
}

enum PluginError: Error {
    case notImplemented(String)
}

protocol BeancountPlugin {
    func process(entries: [Directive<Cost>], options: [Option], config: String?) throws -> (
        entries: [Directive<Cost>], errors: [Error]
    )
}

let allPlugins: [String: BeancountPlugin] = [
    "auto_insert_open": AutoInsertOpenPlugin(),
    "forecast_plugin": ForecastPlugin(),
]

struct AutoInsertOpenPlugin: BeancountPlugin {
    func process(entries: [Directive<Cost>], options: [Option], config: String?) throws -> (
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

struct ForecastPlugin: BeancountPlugin {
    func process(entries: [Directive<Cost>], options: [Option], config: String?) throws -> (
        entries: [Directive<Cost>], errors: [Error]
    ) {
        return (entries, [])
    }
}
