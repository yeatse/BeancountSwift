//
//  Validation.swift
//  BeancountSwift
//
//  Created by yeatse on 2026/1/4.
//

import Foundation

/// Validation error types
enum ValidationError: LocatableError {
    case duplicateOpen(account: Account, entry: Directive<Cost>)
    case duplicateClose(account: Account, entry: Directive<Cost>)
    case closeBeforeOpen(account: Account, entry: Directive<Cost>)
    case unopenedAccount(account: Account, entry: Directive<Cost>)
    case duplicateBalanceWithDifferentAmounts(entry: Directive<Cost>)
    case duplicateCommodity(currency: Currency, entry: Directive<Cost>)
    case inactiveAccount(account: Account, entry: Directive<Cost>)
    case unknownAccount(account: Account, entry: Directive<Cost>)
    case invalidCurrency(currency: Currency, account: Account, entry: Directive<Cost>)
    case invalidRelativePath(entry: Directive<Cost>)
    case transactionDoesNotBalance(residual: Inventory, entry: Directive<Cost>)
    
    var location: LedgerLocation? {
        func getLocation(_ entry: Directive<Cost>) -> LedgerLocation? {
            if let filename = entry.meta.filename, let lineno = entry.meta.lineno {
                return LedgerLocation(filename: filename, lineno: lineno)
            } else {
                return nil
            }
        }
        
        return switch self {
        case .duplicateOpen(_, let entry): getLocation(entry)
        case .duplicateClose(_, let entry): getLocation(entry)
        case .closeBeforeOpen(_, let entry): getLocation(entry)
        case .unopenedAccount(_, let entry): getLocation(entry)
        case .duplicateBalanceWithDifferentAmounts(let entry): getLocation(entry)
        case .duplicateCommodity(_, let entry): getLocation(entry)
        case .inactiveAccount(_, let entry): getLocation(entry)
        case .unknownAccount(_, let entry): getLocation(entry)
        case .invalidCurrency(_, _, let entry): getLocation(entry)
        case .invalidRelativePath(let entry): getLocation(entry)
        case .transactionDoesNotBalance(_, let entry): getLocation(entry)
        }
    }
    
    var localizedDescription: String {
        return switch self {
        case .duplicateOpen(let account, _):
            "Duplicate open directive for \(account.id)"
        case .duplicateClose(let account, _):
            "Duplicate close directive for \(account.id)"
        case .closeBeforeOpen(let account, _):
            "Internal error: closing date for \(account.id) appears before opening date"
        case .unopenedAccount(let account, _):
            "Unopened account \(account.id) is being closed"
        case .duplicateBalanceWithDifferentAmounts:
            "Duplicate balance assertion with different amounts"
        case .duplicateCommodity(let currency, _):
            "Duplicate commodity directives for '\(currency.id)'"
        case .inactiveAccount(let account, _):
            "Invalid reference to inactive account '\(account.id)'"
        case .unknownAccount(let account, _):
            "Invalid reference to unknown account '\(account.id)'"
        case .invalidCurrency(let currency, let account, _):
            "Invalid currency \(currency.id) for account '\(account.id)'"
        case .invalidRelativePath:
            "Invalid relative path for entry"
        case .transactionDoesNotBalance(let residual, _):
            "Transaction does not balance: \(residual)"
        }
    }
}

/// Namespace for Beancount directive validation functionality.
///
/// Validation provides static methods for performing various consistency checks
/// on parsed directives to ensure they satisfy Beancount's semantic rules. These
/// checks are run after all plugins have transformed the entries, just before
/// serving them or generating reports.
///
/// This corresponds to the validation functionality in the original Beancount Python
/// library, providing the same constraint checking capabilities.
///
/// ## Usage
/// ```swift
/// let errors = Validation.validate(entries: directives, options: options)
/// ```
public enum Validation {
    
    /// Check constraints on open and close directives themselves.
    ///
    /// This method checks three kinds of constraints:
    ///
    /// 1. An open or a close directive may only show up once for each account. If a
    ///    duplicate is detected, an error is generated.
    ///
    /// 2. Close directives may only appear if an open directive has been seen
    ///    previously (chronologically).
    ///
    /// 3. The date of close directives must be strictly greater than their
    ///    corresponding open directive.
    ///
    /// - Parameters:
    ///   - entries: A list of directives.
    ///   - options: An options map.
    /// - Returns: A list of new errors, if any were found.
    public static func validateOpenClose(entries: [Directive<Cost>], options: Options) -> [Error] {
        var errors: [Error] = []
        var openMap: [Account: Directive<Cost>] = [:]
        var closeMap: [Account: Directive<Cost>] = [:]
        
        for entry in entries {
            switch entry.content {
            case .open(let open):
                if openMap[open.account] != nil {
                    errors.append(ValidationError.duplicateOpen(account: open.account, entry: entry))
                } else {
                    openMap[open.account] = entry
                }
                
            case .close(let close):
                if closeMap[close.account] != nil {
                    errors.append(ValidationError.duplicateClose(account: close.account, entry: entry))
                } else {
                    if let openEntry = openMap[close.account] {
                        if entry.date < openEntry.date {
                            errors.append(ValidationError.closeBeforeOpen(account: close.account, entry: entry))
                        }
                    } else {
                        errors.append(ValidationError.unopenedAccount(account: close.account, entry: entry))
                    }
                    closeMap[close.account] = entry
                }
                
            default:
                break
            }
        }
        
        return errors
    }
    
    /// Check that balance entries occur only once per day.
    ///
    /// Because we do not support time, and the declaration order of entries is
    /// meant to be kept irrelevant, two balance entries with different amounts
    /// should not occur in the file. We do allow two identical balance assertions,
    /// however, because this may occur during import.
    ///
    /// - Parameters:
    ///   - entries: A list of directives.
    ///   - options: An options map.
    /// - Returns: A list of new errors, if any were found.
    public static func validateDuplicateBalances(entries: [Directive<Cost>], options: Options) -> [Error] {
        var errors: [Error] = []
        
        // Mapping of (account, currency, date) to Balance entry.
        struct BalanceKey: Hashable {
            let account: Account
            let currency: Currency
            let date: Date
        }
        var balanceEntries: [BalanceKey: Directive<Cost>] = [:]
        
        for entry in entries {
            guard case .balance(let balance) = entry.content else {
                continue
            }
            
            let key = BalanceKey(account: balance.account, currency: balance.amount.currency, date: entry.date)
            if let previousEntry = balanceEntries[key] {
                if case .balance(let previousBalance) = previousEntry.content,
                   balance.amount != previousBalance.amount {
                    errors.append(ValidationError.duplicateBalanceWithDifferentAmounts(entry: entry))
                }
            } else {
                balanceEntries[key] = entry
            }
        }
        
        return errors
    }
    
    /// Check that commodity entries are unique for each commodity.
    ///
    /// - Parameters:
    ///   - entries: A list of directives.
    ///   - options: An options map.
    /// - Returns: A list of new errors, if any were found.
    public static func validateDuplicateCommodities(entries: [Directive<Cost>], options: Options) -> [Error] {
        var errors: [Error] = []
        var commodityEntries: [Currency: Directive<Cost>] = [:]
        
        for entry in entries {
            guard case .commodity(let commodity) = entry.content else {
                continue
            }
            
            if commodityEntries[commodity.currency] != nil {
                errors.append(ValidationError.duplicateCommodity(currency: commodity.currency, entry: entry))
            } else {
                commodityEntries[commodity.currency] = entry
            }
        }
        
        return errors
    }
    
    /// Check that all references to accounts occurs on active accounts.
    ///
    /// We basically check that references to accounts from all directives other
    /// than Open and Close occur at dates the open-close interval of that account.
    /// This should be good for all of the directive types where we can extract an
    /// account name.
    ///
    /// Note that this is more strict a check than comparing the dates: we actually
    /// check that no references to account are made on the same day before the open
    /// directive appears for that account. This is a nice property to have, and is
    /// supported by our custom sorting routine that will sort open entries before
    /// transaction entries, given the same date.
    ///
    /// - Parameters:
    ///   - entries: A list of directives.
    ///   - options: An options map.
    /// - Returns: A list of new errors, if any were found.
    public static func validateActiveAccounts(entries: [Directive<Cost>], options: Options) -> [Error] {
        var errorPairs: [(Account, Directive<Cost>)] = []
        var activeSet: Set<Account> = []
        var openedAccounts: Set<Account> = []
        
        for entry in entries {
            switch entry.content {
            case .open(let open):
                activeSet.insert(open.account)
                openedAccounts.insert(open.account)
                
            case .close(let close):
                activeSet.remove(close.account)
                
            default:
                for account in entry.usedAccounts() {
                    if !activeSet.contains(account) {
                        // Allow document and note directives that occur after an
                        // account is closed.
                        if isAllowedAfterClose(entry) && openedAccounts.contains(account) {
                            continue
                        }
                        
                        // Register an error to be logged later, with an appropriate
                        // message.
                        errorPairs.append((account, entry))
                    }
                }
            }
        }
        
        // Refine the error message to disambiguate between the case of an account
        // that has never been seen and one that was simply not active at the time.
        var errors: [Error] = []
        for (account, entry) in errorPairs {
            if openedAccounts.contains(account) {
                errors.append(ValidationError.inactiveAccount(account: account, entry: entry))
            } else {
                errors.append(ValidationError.unknownAccount(account: account, entry: entry))
            }
        }
        
        return errors
    }
    
    /// Check the currency constraints from account open declarations.
    ///
    /// Open directives admit an optional list of currencies that specify the only
    /// types of commodities that the running inventory for this account may
    /// contain. This function checks that all postings are only made in those
    /// commodities.
    ///
    /// - Parameters:
    ///   - entries: A list of directives.
    ///   - options: An options map.
    /// - Returns: A list of new errors, if any were found.
    public static func validateCurrencyConstraints(entries: [Directive<Cost>], options: Options) -> [Error] {
        // Get all the open entries with currency constraints.
        var openMap: [Account: Open] = [:]
        for entry in entries {
            if case .open(let open) = entry.content, !open.currencies.isEmpty {
                openMap[open.account] = open
            }
        }
        
        var errors: [Error] = []
        for entry in entries {
            guard case .transaction(let transaction) = entry.content else {
                continue
            }
            
            for posting in transaction.postings {
                // Look up the corresponding account's valid currencies; skip the
                // check if there are none specified.
                guard let open = openMap[posting.account] else {
                    continue
                }
                
                let validCurrencies = open.currencies
                if validCurrencies.isEmpty {
                    continue
                }
                
                // Perform the check.
                if !validCurrencies.contains(posting.units.currency) {
                    errors.append(ValidationError.invalidCurrency(
                        currency: posting.units.currency,
                        account: posting.account,
                        entry: entry
                    ))
                }
            }
        }
        
        return errors
    }
    
    /// Check that all filenames in resolved Document entries are absolute filenames.
    ///
    /// The processing of document entries is assumed to result in absolute paths.
    /// Relative paths are resolved at the parsing stage and at point we want to
    /// make sure we don't have to do any further processing on them.
    ///
    /// - Parameters:
    ///   - entries: A list of directives.
    ///   - options: An options map.
    /// - Returns: A list of new errors, if any were found.
    public static func validateDocumentsPaths(entries: [Directive<Cost>], options: Options) -> [Error] {
        var errors: [Error] = []
        
        for entry in entries {
            if case .document(let document) = entry.content {
                if !document.filename.hasPrefix("/") && !document.filename.hasPrefix("~") {
                    errors.append(ValidationError.invalidRelativePath(entry: entry))
                }
            }
        }
        
        return errors
    }
    
    /// Check again that all transaction postings balance, as users may have
    /// transformed transactions.
    ///
    /// - Parameters:
    ///   - entries: A list of directives.
    ///   - options: An options map.
    /// - Returns: A list of new errors, if any were found.
    static func validateCheckTransactionBalances(entries: [Directive<Cost>], options: Options) -> [Error] {
        var errors: [Error] = []
        
        for entry in entries {
            guard case .transaction(let transaction) = entry.content else {
                continue
            }
            
            // IMPORTANT: This validation is _crucial_ and cannot be skipped.
            // This is where we actually detect and warn on unbalancing
            // transactions. This _must_ come after the user routines, because
            // unbalancing input is legal, as those types of transactions may be
            // "fixed up" by a user-plugin. In other words, we want to allow
            // users to input unbalancing transactions as long as the final
            // transactions objects that appear on the stream (after processing
            // the plugins) are balanced.
            
            // Detect complete sets of postings that have residual balance
            let residual = Interpolate.computeResidual(postings: transaction.postings)
            let tolerances = Interpolate.inferTolerances(postings: transaction.postings, options: options)
            
            if !residual.isSmall(tolerance: tolerances.default) {
                errors.append(ValidationError.transactionDoesNotBalance(residual: residual, entry: entry))
            }
        }
        
        return errors
    }
    
    /// Perform all the standard checks on parsed contents.
    ///
    /// Runs a comprehensive set of validation checks on the directives,
    /// including optional extra validations provided by the caller.
    ///
    /// - Parameters:
    ///   - entries: A list of directives.
    ///   - options: An options map.
    ///   - extraValidations: Optional extra validation functions to run
    /// - Returns: A list of new errors, if any were found.
    public static func validate(
        entries: [Directive<Cost>],
        options: Options,
        extraValidations: [(([Directive<Cost>], Options) -> [Error])]? = nil
    ) -> [Error] {
        // Run basic validation routines
        var errors: [Error] = []
        let basicValidations: [(([Directive<Cost>], Options) -> [Error])] = [
            validateOpenClose(entries:options:),
            validateActiveAccounts(entries:options:),
            validateCurrencyConstraints(entries:options:),
            validateDuplicateBalances(entries:options:),
            validateDuplicateCommodities(entries:options:),
            validateDocumentsPaths(entries:options:),
            validateCheckTransactionBalances(entries:options:),
        ]
        for validation in basicValidations {
            errors.append(contentsOf: validation(entries, options))
        }
        
        // Run extra validations if provided
        if let extraValidations = extraValidations {
            for validationFunction in extraValidations {
                let newErrors = validationFunction(entries, options)
                errors.append(contentsOf: newErrors)
            }
        }
        
        return errors
    }
    
    // MARK: - Private Helper Methods
    
    /// Directive types that should be allowed after the account is closed.
    ///
    /// - Balance directives may be useful to ensure the closed account is empty.
    /// - Documents may be received well after account closure.
    /// - Notes may be taken in the future for various reasons.
    private static func isAllowedAfterClose(_ entry: Directive<Cost>) -> Bool {
        switch entry.content {
        case .balance, .document, .note:
            return true
        default:
            return false
        }
    }
}
