//
//  ValidationTests.swift
//  BeancountSwift
//
//  Created by yeatse on 2026/1/4.
//

import Foundation
import Testing

@testable import BeancountSwift

struct ValidationTests {
    // MARK: - Open/Close Validation Tests

    @Test func validateOpenCloseDuplicateOpen() throws {
        let p: ContentProvider =
            """
            ; Regular, only appears once.
            2014-02-10 open Assets:US:Bank:Checking1

            ; Open twice on the same date.
            2014-02-11 open Assets:US:Bank:Checking2
            2014-02-11 open Assets:US:Bank:Checking2

            ; Open twice on different dates.
            2014-02-20 open Assets:US:Bank:Checking3
            2014-02-21 open Assets:US:Bank:Checking3
            """
        let ledger = try p.loadLedger()

        let errors = Validation.validateOpenClose(
            entries: ledger.directives, options: ledger.options)

        #expect(errors.count == 2)
        let accounts = errors.compactMap { error -> String? in
            if case let validationError as ValidationError = error,
                case .duplicateOpen(let account, _) = validationError
            {
                return account.id
            }
            return nil
        }
        #expect(accounts == ["Assets:US:Bank:Checking2", "Assets:US:Bank:Checking3"])
    }

    @Test func validateOpenCloseDuplicateClose() throws {
        let p: ContentProvider =
            """
            2014-02-10 open Assets:US:Bank:Checking1
            2014-02-10 open Assets:US:Bank:Checking2
            2014-02-10 open Assets:US:Bank:Checking3

            ; Regular, only appears once.
            2014-03-01 close Assets:US:Bank:Checking1

            ; Close twice on the same date.
            2014-03-11 close Assets:US:Bank:Checking2
            2014-03-11 close Assets:US:Bank:Checking2

            ; Close twice on different dates.
            2014-03-21 close Assets:US:Bank:Checking3
            2014-03-22 close Assets:US:Bank:Checking3
            """
        let ledger = try p.loadLedger()

        let errors = Validation.validateOpenClose(
            entries: ledger.directives, options: ledger.options)

        #expect(errors.count == 2)
        let accounts = errors.compactMap { error -> String? in
            if case let validationError as ValidationError = error,
                case .duplicateClose(let account, _) = validationError
            {
                return account.id
            }
            return nil
        }
        #expect(accounts == ["Assets:US:Bank:Checking2", "Assets:US:Bank:Checking3"])
    }

    @Test func validateOpenCloseUnopenedAccount() throws {
        let p: ContentProvider =
            """
            2014-03-01 close Assets:US:Bank:Checking1
            """
        let ledger = try p.loadLedger()

        let errors = Validation.validateOpenClose(
            entries: ledger.directives, options: ledger.options)

        #expect(errors.count == 1)
        if case let validationError as ValidationError = errors[0],
            case .unopenedAccount(let account, _) = validationError
        {
            #expect(account.id == "Assets:US:Bank:Checking1")
        } else {
            Issue.record("Expected unopenedAccount error")
        }
    }

    @Test func validateOpenCloseOrdering() throws {
        let p: ContentProvider =
            """
            2014-03-01 open Assets:US:Bank:Checking1
            2014-02-01 close Assets:US:Bank:Checking1
            """
        let ledger = try p.loadLedger()

        let errors = Validation.validateOpenClose(
            entries: ledger.directives, options: ledger.options)

        #expect(errors.count == 1)
        // After sorting, close (02-01) comes before open (03-01)
        // so we get "unopened account" error instead of "close before open"
        if case let validationError as ValidationError = errors[0],
            case .unopenedAccount(let account, _) = validationError
        {
            #expect(account.id == "Assets:US:Bank:Checking1")
        } else {
            Issue.record("Expected unopenedAccount error")
        }
    }

    // MARK: - Duplicate Balance Tests

    @Test func validateDuplicateBalances() throws {
        let p: ContentProvider =
            """
            2014-01-01 open Assets:US:Bank:Checking1
            2014-01-01 open Assets:US:Bank:Checking2

            ; Duplicates, with different amounts (error).
            2014-03-01 balance Assets:US:Bank:Checking1 100 USD
            2014-03-01 balance Assets:US:Bank:Checking1 101 USD

            ; Duplicates, with same amount (okay).
            2014-03-02 balance Assets:US:Bank:Checking1 100 USD
            2014-03-02 balance Assets:US:Bank:Checking1 100 USD

            ; Different dates (okay).
            2014-03-03 balance Assets:US:Bank:Checking1 100 USD
            2014-03-04 balance Assets:US:Bank:Checking1 101 USD

            ; Different currencies (okay).
            2014-03-05 balance Assets:US:Bank:Checking1 100 USD
            2014-03-05 balance Assets:US:Bank:Checking1 100 CAD

            ; Different accounts at same date (okay).
            2014-03-06 balance Assets:US:Bank:Checking1 100 USD
            2014-03-06 balance Assets:US:Bank:Checking2 100 USD
            """
        let ledger = try p.loadLedger()

        let errors = Validation.validateDuplicateBalances(
            entries: ledger.directives, options: ledger.options)

        #expect(errors.count == 1)
        if let error = errors.first as? ValidationError,
            case .duplicateBalanceWithDifferentAmounts(let entry) = error
        {
            #expect(entry.date == "2014-03-01")
        } else {
            Issue.record("Expected duplicateBalanceWithDifferentAmounts error")
        }
    }

    // MARK: - Duplicate Commodities Tests

    @Test func validateDuplicateCommodities() throws {
        let p: ContentProvider =
            """
            2014-01-01 commodity USD
            2014-01-02 commodity CAD
            2014-01-03 commodity AAPL
            2014-01-04 commodity HOOL
            2014-01-05 commodity USD
            2014-01-06 commodity HOOL
            """
        let ledger = try p.loadLedger()

        let errors = Validation.validateDuplicateCommodities(
            entries: ledger.directives, options: ledger.options)

        #expect(errors.count == 2)
        let dates = errors.compactMap { error -> Date? in
            if case let validationError as ValidationError = error,
                case .duplicateCommodity(_, let entry) = validationError
            {
                return entry.date
            }
            return nil
        }
        let expected: [Date] = ["2014-01-05", "2014-01-06"]
        #expect(dates == expected)
    }

    // MARK: - Active Accounts Tests

    @Test func validateActiveAccounts() throws {
        let p: ContentProvider =
            """
            2014-01-01 open Equity:Opening-Balances

            2014-02-01 * "Invalid before"
              Assets:Temporary          1 USD
              Equity:Opening-Balances  -1 USD

            2014-02-02 note Assets:Temporary "Invalid note entry"
            2014-02-03 pad Assets:Temporary Equity:Opening-Balances

            2014-03-01 open Assets:Temporary

            2014-04-01 * "Valid"
              Assets:Temporary           1 USD
              Equity:Opening-Balances   -1 USD

            2014-05-01 * "Unknown account"
              Assets:Temporary    1 USD
              Equity:ImUnknown   -1 USD

            2014-09-01 close Assets:Temporary

            2014-10-01 * "Invalid after"
              Assets:Temporary           1 USD
              Equity:Opening-Balances   -1 USD

            ; These should be allowed after close.
            2014-10-02 note Assets:Temporary "Invalid note entry again"
            2014-10-03 document Assets:Temporary "/path/to/allowed-doc.pdf"
            """
        let ledger = try p.loadLedger()

        let errors = Validation.validateActiveAccounts(
            entries: ledger.directives, options: ledger.options)

        // Should have errors for: invalid before transaction, invalid note, pad, unknown account, invalid after
        #expect(errors.count == 5)

        // Check that note and document after close are NOT in errors
        let errorDates = errors.compactMap { error -> Date? in
            if case let validationError as ValidationError = error,
                case .inactiveAccount(_, let entry) = validationError
            {
                return entry.date
            } else if case let validationError as ValidationError = error,
                case .unknownAccount(_, let entry) = validationError
            {
                return entry.date
            }
            return nil
        }

        // Should not contain the dates of allowed directives after close
        #expect(!errorDates.contains("2014-10-02"))
        #expect(!errorDates.contains("2014-10-03"))
    }

    @Test func validateActiveAccountsUnopened() throws {
        let p: ContentProvider =
            """
            2014-02-01 *
              Assets:US:Bank:Checking     100 USD
              Assets:US:Bank:Savings     -100 USD
            """
        let ledger = try p.loadLedger()

        let errors = Validation.validateActiveAccounts(
            entries: ledger.directives, options: ledger.options)

        #expect(errors.count == 2)
        let allUnknownAccount = errors.allSatisfy { error in
            if case let validationError as ValidationError = error,
                case .unknownAccount = validationError
            {
                return true
            }
            return false
        }
        #expect(allUnknownAccount)
    }

    @Test func validateBalanceAfterClose() throws {
        let p: ContentProvider =
            """
            2014-01-01 open Assets:US:Bank:Checking
            2014-02-01 close Assets:US:Bank:Checking
            2014-02-05 balance Assets:US:Bank:Checking 0.00 USD
            """
        let ledger = try p.loadLedger()

        let errors = Validation.validateActiveAccounts(
            entries: ledger.directives, options: ledger.options)

        // Balance directives should be allowed after close
        #expect(errors.isEmpty)
    }

    // MARK: - Currency Constraints Tests

    @Test func validateCurrencyConstraints() throws {
        let p: ContentProvider =
            """
            2014-01-01 open Assets:Account1 USD
            2014-01-01 open Assets:Account2 HOOL
            2014-01-01 open Equity:Opening-Balances

            2014-01-02 * "Entries without cost - valid"
              Assets:Account1             1 USD
              Equity:Opening-Balances    -1 USD

            2014-01-03 * "Entries without cost - invalid currency"
              Assets:Account1             1 CAD
              Equity:Opening-Balances    -1 CAD

            2014-01-04 * "Entries with cost - valid"
              Assets:Account2             1 HOOL {500 USD}
              Equity:Opening-Balances  -500 USD

            2014-01-05 * "Entries with cost - invalid currency"
              Assets:Account2             1 AAPL {500 USD}
              Equity:Opening-Balances  -500 USD
            """
        let ledger = try p.loadLedger()

        let errors = Validation.validateCurrencyConstraints(
            entries: ledger.directives, options: ledger.options)

        #expect(errors.count == 2)
        let invalidCurrencies = errors.compactMap { error -> Currency? in
            if case let validationError as ValidationError = error,
                case .invalidCurrency(let currency, _, _) = validationError
            {
                return currency
            }
            return nil
        }
        #expect(invalidCurrencies.map { $0.id }.sorted() == ["AAPL", "CAD"])
    }

    // MARK: - Document Paths Tests

    @Test(
        "Document paths validation",
        .disabled("Document directive parsing not yet fully implemented"))
    func validateDocumentsPaths() throws {
        let p: ContentProvider =
            """
            2014-01-01 open Assets:US:Bank:Checking

            2014-01-02 document Assets:US:Bank:Checking "/absolute/path/to/doc.pdf"
            2014-01-03 document Assets:US:Bank:Checking "relative/path/to/doc.pdf"
            2014-01-04 document Assets:US:Bank:Checking "~/home/path/to/doc.pdf"
            """
        let ledger = try p.loadLedger()

        let errors = Validation.validateDocumentsPaths(
            entries: ledger.directives, options: ledger.options)

        #expect(errors.count == 1)
        if case let validationError as ValidationError = errors[0],
            case .invalidRelativePath(let entry) = validationError
        {
            #expect(entry.date == "2014-01-03")
        } else {
            Issue.record("Expected invalidRelativePath error")
        }
    }

    // MARK: - Transaction Balance Tests

    @Test func validateCheckTransactionBalancesValid() throws {
        let p: ContentProvider =
            """
            2014-01-01 open Assets:Checking
            2014-01-01 open Expenses:Food

            2014-01-02 * "Balanced transaction"
              Assets:Checking   -100 USD
              Expenses:Food      100 USD
            """
        let ledger = try p.loadLedger()

        let errors = Validation.validateCheckTransactionBalances(
            entries: ledger.directives, options: ledger.options)

        #expect(errors.isEmpty)
    }

    @Test func validateCheckTransactionBalancesInvalid() throws {
        let p: ContentProvider =
            """
            2014-01-01 open Assets:Checking
            2014-01-01 open Expenses:Food

            2014-01-02 * "Unbalanced transaction"
              Assets:Checking   -100 USD
              Expenses:Food       99 USD
            """
        let ledger = try p.loadLedger()

        let errors = Validation.validateCheckTransactionBalances(
            entries: ledger.directives, options: ledger.options)

        #expect(errors.count == 1)
        if case let validationError as ValidationError = errors[0],
            case .transactionDoesNotBalance = validationError
        {
            // Success
        } else {
            Issue.record("Expected transactionDoesNotBalance error")
        }
    }

    // MARK: - Comprehensive Validation Tests

    @Test func validateAllChecks() throws {
        let p: ContentProvider =
            """
            2014-01-01 open Assets:Checking USD
            2014-01-01 open Expenses:Food
            2014-01-01 commodity USD

            2014-01-02 * "Valid transaction"
              Assets:Checking   -100 USD
              Expenses:Food      100 USD

            2014-01-03 balance Assets:Checking -100 USD

            ; Duplicate commodity - should error
            2014-01-04 commodity USD

            ; Invalid currency - should error
            2014-01-05 * "Invalid currency"
              Assets:Checking     1 CAD
              Expenses:Food      -1 CAD
            """
        let ledger = try p.loadLedger()

        let errors = Validation.validate(entries: ledger.directives, options: ledger.options)

        // Should have error for duplicate commodity and invalid currency
        #expect(errors.count >= 2)

        let hasDuplicateCommodity = errors.contains { error in
            if case let validationError as ValidationError = error,
                case .duplicateCommodity = validationError
            {
                return true
            }
            return false
        }
        #expect(hasDuplicateCommodity)

        let hasInvalidCurrency = errors.contains { error in
            if case let validationError as ValidationError = error,
                case .invalidCurrency = validationError
            {
                return true
            }
            return false
        }
        #expect(hasInvalidCurrency)
    }

    @Test func validateErrorDescription() {
        let account = Account(id: "Assets:Checking")
        let currency = Currency(id: "USD")
        let directive = Directive<Cost>(
            meta: [:],
            date: "2014-01-01",
            content: .open(Open(account: account, currencies: [], booking: nil))
        )

        let error1 = ValidationError.duplicateOpen(account: account, entry: directive)
        #expect(error1.localizedDescription.contains("Duplicate open directive"))
        #expect(error1.localizedDescription.contains("Assets:Checking"))

        let error2 = ValidationError.invalidCurrency(
            currency: currency, account: account, entry: directive)
        #expect(error2.localizedDescription.contains("Invalid currency"))
        #expect(error2.localizedDescription.contains("USD"))
        #expect(error2.localizedDescription.contains("Assets:Checking"))
    }

    @Test func validateErrorLocation() {
        let account = Account(id: "Assets:Checking")
        let metaWithLocation: MetaData = [
            "filename": .string("/path/to/file.beancount"),
            "lineno": .number(42),
        ]
        let directive = Directive<Cost>(
            meta: metaWithLocation,
            date: "2014-01-01",
            content: .open(Open(account: account, currencies: [], booking: nil))
        )

        let error = ValidationError.duplicateOpen(account: account, entry: directive)
        let location = error.location

        #expect(location != nil)
        #expect(location?.filename == "/path/to/file.beancount")
        #expect(location?.lineno == 42)
    }
}
