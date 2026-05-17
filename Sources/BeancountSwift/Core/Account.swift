//
//  Account.swift
//
//
//  Created by Yeatse on 2024/1/27.
//

import Foundation
import RegexBuilder

/// A Beancount account name, representing a hierarchical account path.
///
/// Accounts in Beancount are organized in a hierarchy using colon-separated names
/// like "Assets:US:Bank:Checking". Account names must start with a capital letter
/// and follow specific naming conventions.
///
/// This corresponds to account handling in the original Beancount Python library,
/// providing all the utilities for account manipulation and classification.
///
/// ## Account Structure
/// - Root accounts: Assets, Liabilities, Equity, Income, Expenses
/// - Sub-accounts are separated by colons: "Assets:Bank:Checking"
/// - Account names must match the regex pattern for validity
///
/// ## Usage
/// ```swift
/// let account = Account(id: "Assets:US:Bank:Checking")
/// print(account.root)       // "Assets"
/// print(account.leaf)       // "Checking"
/// print(account.parent?.id) // "Assets:US:Bank"
/// ```
///
/// - SeeAlso: [Beancount Design Doc - Account](https://beancount.github.io/docs/beancount_design_doc.html#account)
public struct Account: Identifiable, Equatable, Hashable, Sendable {
    /// The full account name as a colon-separated string.
    public var id: String

    /// Creates an account with the specified name.
    ///
    /// - Parameter id: The account name (e.g., "Assets:Bank:Checking")
    public init(id: String) {
        self.id = id
    }

    /// An empty account constant used as a placeholder or default value.
    public static let empty = Account(id: "")
}

// MARK: relationships
extension Account {
    // Mirrors the actual parse behavior of the official beancount project, which
    // combines the lexer (beancount/parser/lexer.l) and the grammar callback
    // (beancount/parser/grammar.py:Builder.account):
    //
    //   - The lexer tokenizes the account: ACCOUNTTYPE(:ACCOUNTNAME)+ where each
    //     segment may use any non-ASCII codepoint anywhere (UTF-8-ONLY).
    //   - grammar.py then applies `valid_account_regexp.match(account)` with
    //     `[\p{Lu}][\p{L}\p{Nd}-]*(:[\p{Lu}\p{Nd}][\p{L}\p{Nd}-]*)+`. Because it
    //     uses `match`, not `fullmatch`, only the first two segments are
    //     enforced strictly; trailing segments only need to satisfy the lexer.
    //
    // The pattern below encodes that combined behavior: strict segments for the
    // type and the first name, lexer-permissive segments after that.
    static var regex: Regex<Substring> {
        #/(?:[\p{Lu}][\p{L}\p{Nd}-]*)(?::[\p{Lu}\p{Nd}][\p{L}\p{Nd}-]*)(?::[A-Z0-9\u{80}-\u{10FFFF}][A-Za-z0-9\u{80}-\u{10FFFF}\-]*)*/#
    }

    /// Validates whether the account name parses as a beancount account.
    ///
    /// Replicates the official beancount parser: the first segment must look
    /// like an ACCOUNTTYPE (`\p{Lu}` start, `[\p{L}\p{Nd}-]` body), the second
    /// segment must satisfy the stricter ACCOUNTNAME grammar
    /// (`[\p{Lu}\p{Nd}]` start, `[\p{L}\p{Nd}-]` body), and any further
    /// segments only need to satisfy the lexer (ASCII `[A-Z0-9]` or any
    /// non-ASCII codepoint as start; ASCII letters/digits/hyphen or any
    /// non-ASCII codepoint as body). At least two segments are required.
    ///
    /// As a consequence, `Assets:CMB:招商银行` is valid (the `招商银行`
    /// segment falls under the lexer-only third-segment rule) while
    /// `Assets:招商银行` is not (the second segment is checked strictly and
    /// `招` is `\p{Lo}`, not `\p{Lu}`/`\p{Nd}`).
    public var isValid: Bool {
        try! Account.regex.wholeMatch(in: id) != nil
    }

    /// Return true if the given string is a valid root account name.
    ///
    /// Matches `account.is_valid_root` from official beancount, which is used
    /// to validate option-supplied root names (e.g. `option "name_assets" …`).
    /// A single segment of the ACCOUNTTYPE shape: `\p{Lu}` start, then
    /// `[\p{L}\p{Nd}-]`.
    public var isValidRoot: Bool {
        return try! #/^[\p{Lu}][\p{L}\p{Nd}-]*$/#.wholeMatch(in: id) != nil
    }

    /// Return true if the given string is a valid leaf account name.
    ///
    /// Matches `account.is_valid_leaf` from official beancount: each
    /// colon-separated component must satisfy the strict ACCOUNTNAME shape
    /// (`[\p{Lu}\p{Nd}]` start, `[\p{L}\p{Nd}-]` body).
    public var isValidLeaf: Bool {
        // Check for empty components by looking for consecutive colons
        if id.contains("::") {
            return false
        }

        let components = id.split(separator: ":")
        guard !components.isEmpty else { return false }

        // Each component should match the leaf pattern
        for component in components {
            if try! #/^[\p{Lu}\p{Nd}][\p{L}\p{Nd}-]*$/#.wholeMatch(in: component) == nil {
                return false
            }
        }
        return true
    }

    /// Creates an account from individual name components.
    ///
    /// - Parameter components: Array of account name components
    /// - Returns: A new account with components joined by colons
    ///
    /// ## Example
    /// ```swift
    /// let account = Account.joined(from: ["Assets", "Bank", "Checking"])
    /// // Results in "Assets:Bank:Checking"
    /// ```
    public static func joined(from components: [String]) -> Account {
        .init(id: components.joined(separator: ":"))
    }

    /// Splits the account name into individual components.
    ///
    /// - Returns: Array of account name components
    ///
    /// ## Example
    /// ```swift
    /// let account = Account(id: "Assets:Bank:Checking")
    /// let components = account.split() // ["Assets", "Bank", "Checking"]
    /// ```
    public func split() -> [String] {
        id.split(separator: #/:/#).map { String($0) }
    }

    /// Returns the parent account, or nil if this is a root account.
    ///
    /// The parent is the account with all components except the last one.
    ///
    /// ## Example
    /// ```swift
    /// let account = Account(id: "Assets:Bank:Checking")
    /// let parent = account.parent // Account(id: "Assets:Bank")
    /// ```
    public var parent: Account? {
        let components = id.split(separator: #/:/#)
        if components.count <= 1 {
            return nil
        } else {
            return .init(id: components.dropLast().joined(separator: ":"))
        }
    }

    /// Determines if this account is a child (or same as) the specified account.
    ///
    /// An account is considered a child if it starts with the parent's name
    /// followed by a colon, or if it's the same account.
    ///
    /// - Parameter account: The potential parent account
    /// - Returns: True if this account is a child of the specified account
    ///
    /// ## Example
    /// ```swift
    /// let child = Account(id: "Assets:Bank:Checking")
    /// let parent = Account(id: "Assets:Bank")
    /// print(child.isChild(of: parent)) // true
    /// ```
    public func isChild(of account: Account) -> Bool {
        return id == account.id || id.hasPrefix(account.id + ":")
    }

    /// Returns the leaf (last component) of the account name.
    ///
    /// For "Assets:Bank:Checking", the leaf is "Checking".
    /// For root accounts like "Assets", returns the entire name.
    ///
    /// ## Example
    /// ```swift
    /// let account = Account(id: "Assets:Bank:Checking")
    /// print(account.leaf) // "Checking"
    /// ```
    public var leaf: String {
        guard let lastSep = id.lastIndex(of: ":") else { return id }
        return String(id[id.index(after: lastSep)...])
    }

    /// Returns the account name without the root component.
    ///
    /// For "Assets:Bank:Checking", returns "Bank:Checking".
    /// For root accounts, returns an empty string.
    ///
    /// ## Example
    /// ```swift
    /// let account = Account(id: "Assets:Bank:Checking")
    /// print(account.sansRoot) // "Bank:Checking"
    /// ```
    public var sansRoot: String {
        guard let firstSep = id.firstIndex(of: ":") else { return "" }
        return String(id[id.index(after: firstSep)...])
    }

    /// Returns the account name with only the specified number of components.
    ///
    /// - Parameter components: Number of components to include from the beginning
    /// - Returns: Account name with the specified number of components
    ///
    /// ## Example
    /// ```swift
    /// let account = Account(id: "Assets:Bank:Checking:Main")
    /// print(account.root(2)) // "Assets:Bank"
    /// ```
    public func root(_ components: Int) -> String {
        return id.split(separator: #/:/#).prefix(components).joined(separator: ":")
    }

    /// Returns the root (first component) of the account name.
    ///
    /// For "Assets:Bank:Checking", returns "Assets".
    /// For root accounts, returns the entire name.
    ///
    /// ## Example
    /// ```swift
    /// let account = Account(id: "Assets:Bank:Checking")
    /// print(account.root) // "Assets"
    /// ```
    public var root: String {
        guard let sepIndex = id.firstIndex(of: ":") else { return id }
        return String(id[..<sepIndex])
    }

    /// Checks if the account contains the specified component.
    ///
    /// - Parameter component: The component name to search for
    /// - Returns: True if the account contains this component
    ///
    /// ## Example
    /// ```swift
    /// let account = Account(id: "Assets:US:Bank:Checking")
    /// print(account.hasComponent("Bank")) // true
    /// print(account.hasComponent("EU"))   // false
    /// ```
    public func hasComponent(_ component: String) -> Bool {
        let regex = Regex {
            ChoiceOf {
                Anchor.startOfLine
                ":"
            }
            component
            ChoiceOf {
                Anchor.endOfLine
                ":"
            }
        }
        return id.contains(regex)
    }

    /// Finds the common prefix of multiple account names.
    ///
    /// Returns the longest common prefix shared by all accounts in the array.
    ///
    /// - Parameter accounts: Array of accounts to find the common prefix for
    /// - Returns: The common prefix as a colon-separated string
    ///
    /// ## Example
    /// ```swift
    /// let accounts = [
    ///     Account(id: "Assets:US:Bank:Checking"),
    ///     Account(id: "Assets:US:Bank:Savings"),
    ///     Account(id: "Assets:US:Investment")
    /// ]
    /// let prefix = Account.commonPrefix(in: accounts) // "Assets:US"
    /// ```
    public static func commonPrefix(in accounts: [Account]) -> String {
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

    public var isRoot: Bool {
        return try! #/[A-Z][A-Za-z0-9\\-]+/#.wholeMatch(in: id) != nil
    }

    public func isBalanceSheet(config: AccountTypeConfiguration) -> Bool {
        return switch root {
        case config.assets: true
        case config.liabilities: true
        case config.equity: true
        default: false
        }
    }

    public func isIncomeStatement(config: AccountTypeConfiguration) -> Bool {
        return switch root {
        case config.income: true
        case config.expenses: true
        default: false
        }
    }

    public func isEquity(config: AccountTypeConfiguration) -> Bool {
        return switch root {
        case config.equity: true
        default: false
        }
    }

    public func isInverted(config: AccountTypeConfiguration) -> Bool {
        return switch root {
        case config.income: true
        case config.liabilities: true
        case config.equity: true
        default: false
        }
    }

    public func sign(config: AccountTypeConfiguration) -> FloatingPointSign {
        return switch root {
        case config.assets: .plus
        case config.expenses: .plus
        default: .minus
        }
    }
}

/// The five fundamental account types in double-entry accounting.
///
/// These correspond to the standard accounting equation:
/// Assets = Liabilities + Equity + (Income - Expenses)
///
/// - SeeAlso: [Beancount Account Types](http://furius.ca/beancount/doc/cheat_sheet.html#account-categories)
public enum AccountType: Comparable, Sendable {
    /// Asset accounts (things you own): cash, bank accounts, investments, etc.
    case assets
    /// Liability accounts (things you owe): credit cards, loans, mortgages, etc.
    case liabilities
    /// Equity accounts (net worth): opening balances, retained earnings, etc.
    case equity
    /// Income accounts (money coming in): salary, dividends, interest, etc.
    case income
    /// Expense accounts (money going out): groceries, rent, utilities, etc.
    case expenses
}

/// Configuration for account type root names.
///
/// Allows customization of the root account names used to identify
/// the five fundamental account types. The default configuration
/// uses English names following Beancount conventions.
///
/// ## Usage
/// ```swift
/// // Using default English names
/// let account = Account(id: "Assets:Bank:Checking")
/// let type = account.type() // .assets
///
/// // Using custom configuration
/// let germanConfig = AccountTypeConfiguration(
///     assets: "Aktiva",
///     liabilities: "Passiva",
///     equity: "Eigenkapital",
///     income: "Ertrag",
///     expenses: "Aufwand"
/// )
/// ```
public struct AccountTypeConfiguration: Sendable {
    /// Root name for asset accounts (default: "Assets")
    public var assets: String
    /// Root name for liability accounts (default: "Liabilities")
    public var liabilities: String
    /// Root name for equity accounts (default: "Equity")
    public var equity: String
    /// Root name for income accounts (default: "Income")
    public var income: String
    /// Root name for expense accounts (default: "Expenses")
    public var expenses: String

    /// Default English configuration following Beancount conventions.
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
    /// Creates an account from a string literal in DEBUG builds only.
    ///
    /// This convenience initializer allows using string literals for accounts
    /// in test code and debugging scenarios.
    ///
    /// - Parameter value: The account name as a string
    ///
    /// ## Example
    /// ```swift
    /// let account: Account = "Assets:Bank:Checking"
    /// ```
    ///
    /// - Warning: Only available in DEBUG builds to prevent accidental use in production.
    public init(stringLiteral value: StringLiteralType) {
        self.id = value
    }
}
#endif
