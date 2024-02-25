//
//  Account.swift
//
//
//  Created by Yeatse on 2024/1/27.
//

import Foundation
import RegexBuilder

/// https://beancount.github.io/docs/beancount_design_doc.html#account
public struct Account: Identifiable, Equatable, Hashable {
    public var id: String
    
    public init(id: String) {
        self.id = id
    }
}

// MARK: relationships
extension Account {
    static let regex = #/(?:[\p{Lu}][\p{L}\p{Nd}-]*)(?::[\p{Lu}\p{Nd}][\p{L}\p{Nd}-]*)+/#
    
    public var isValid: Bool {
        try! Account.regex.wholeMatch(in: id) != nil
    }
    
    static func joined(from components: [String]) -> Account {
        .init(id: components.joined(separator: ":"))
    }
    
    public func split() -> [String] {
        id.split(separator: #/:/#).map { String($0) }
    }
    
    public var parent: Account? {
        let components = id.split(separator: #/:/#)
        if components.count <= 1 {
            return nil
        } else {
            return .init(id: components.dropLast().joined(separator: ":"))
        }
    }
    
    public func isChild(of account: Account) -> Bool {
        let regex = Regex {
            account.id
            ChoiceOf { Anchor.endOfLine; ":" }
        }
        return id.contains(regex)
    }
    
    public var leaf: String {
        guard let lastSep = id.lastIndex(of: ":") else { return id }
        return String(id[id.index(after: lastSep)...])
    }
    
    var sansRoot: String {
        guard let firstSep = id.firstIndex(of: ":") else { return "" }
        return String(id[id.index(after: firstSep)...])
    }
    
    func root(_ components: Int) -> String {
        return id.split(separator: #/:/#).prefix(components).joined(separator: ":")
    }
    
    var root: String {
        guard let sepIndex = id.firstIndex(of: ":") else { return id }
        return String(id[..<sepIndex])
    }
    
    func hasComponent(_ component: String) -> Bool {
        let regex = Regex {
            ChoiceOf { Anchor.startOfLine; ":" }
            component
            ChoiceOf { Anchor.endOfLine; ":" }
        }
        return id.contains(regex)
    }
    
    static func commonPrefix(in accounts: [Account]) -> String {
        func commonPrefix<T: Equatable>(of arrays: [[T]]) -> [T] {
            guard let firstArray = arrays.first, !firstArray.isEmpty else {
                return []
            }
            
            var prefix: [T] = []
            
            for i in 0..<firstArray.count {
                let element = firstArray[i]
                
                // Check if all arrays contain this element at the current index
                for array in arrays {
                    if i >= array.count || array[i] != element {
                        return prefix
                    }
                }
                
                prefix.append(element)
            }
            
            return prefix
        }
        
        let splitAccounts = accounts.map { account in account.id.split(separator: ":") }
        let prefix = commonPrefix(of: splitAccounts)
        return prefix.joined(separator: ":")
    }
}

// MARK: types
extension Account {
    public func type(config: AccountTypeConfiguration = .default) -> AccountType? {
        return switch root {
            case config.assets: .assets
            case config.liabilities: .liabilities
            case config.equity: .equity
            case config.income: .income
            case config.expenses: .expenses
            default: nil
        }
    }
    
    var isRoot: Bool {
        return try! #/[A-Z][A-Za-z0-9\\-]+/#.wholeMatch(in: id) != nil
    }
    
    func isBalanceSheet(config: AccountTypeConfiguration) -> Bool {
        return switch root {
            case config.assets: true
            case config.liabilities: true
            case config.equity: true
            default: false
        }
    }
    
    func isIncomeStatement(config: AccountTypeConfiguration) -> Bool {
        return switch root {
            case config.income: true
            case config.expenses: true
            default: false
        }
    }
    
    func isEquity(config: AccountTypeConfiguration) -> Bool {
        return switch root {
            case config.equity: true
            default: false
        }
    }
    
    func isInverted(config: AccountTypeConfiguration) -> Bool {
        return switch root {
            case config.income: true
            case config.liabilities: true
            case config.equity: true
            default: false
        }
    }
    
    func sign(config: AccountTypeConfiguration) -> FloatingPointSign {
        return switch root {
            case config.assets: .plus
            case config.expenses: .plus
            default: .minus
        }
    }
}

public enum AccountType: Comparable {
    case assets
    case liabilities
    case equity
    case income
    case expenses
}

public struct AccountTypeConfiguration {
    public var assets: String
    public var liabilities: String
    public var equity: String
    public var income: String
    public var expenses: String
    
    static public let `default` = AccountTypeConfiguration(
        assets: "Assets",
        liabilities: "Liabilities",
        equity: "Equity",
        income: "Income",
        expenses: "Expenses"
    )
}

#if DEBUG
extension Account: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self.id = value
    }
}
#endif
