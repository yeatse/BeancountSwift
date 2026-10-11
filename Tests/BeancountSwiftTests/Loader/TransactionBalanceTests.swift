//
//  TransactionBalanceTests.swift
//  BeancountSwift
//

import Testing

@testable import BeancountSwift

struct TransactionBalanceTests {
    private func balance(of source: String) throws -> TransactionBalance {
        let directive = try #require(Parser.parseSnippet(from: source))
        guard case .transaction(let transaction) = directive.content else {
            Issue.record("Expected a transaction")
            return .undetermined
        }
        return transaction.checkBalance(options: Options(from: []))
    }

    @Test(arguments: [
        "2026-10-11 * \"A\"\n  Expenses:Food  4.50 USD\n  Assets:Cash  -4.50 USD",
        "2026-10-11 * \"A\"\n  Expenses:Food  4.50 USD\n  Assets:Cash",
        "2026-10-11 * \"A\"\n  Expenses:Food  (120.00 - 10.00) CNY\n  Assets:Cash  -110.00 CNY",
        "2026-10-11 * \"A\"\n  Assets:USD  100.00 USD @@ 712.00 CNY\n  Assets:CNY  -712.00 CNY",
        "2026-10-11 * \"A\"\n  Assets:USD  100.00 USD @ 7.12 CNY\n  Assets:CNY  -712.00 CNY",
        "2026-10-11 * \"A\"\n  Assets:Broker  10 AAPL {150.00 USD}\n  Assets:Cash  -1500.00 USD",
        "2026-10-11 * \"A\"\n  Expenses:Food  4.50 USD\n  Assets:Cash  -4.495 USD",
    ])
    func balanced(source: String) throws {
        #expect(try balance(of: source) == .balanced)
    }

    @Test func unbalanced() throws {
        let result = try balance(
            of: "2026-10-11 * \"A\"\n  Expenses:Food  4.50 USD\n  Assets:Cash  -4.00 USD"
        )
        #expect(result == .unbalanced(residual: [Amount(number: 0.5, currency: "USD")]))
    }

    @Test func tooManyMissingAmounts() throws {
        let result = try balance(
            of: "2026-10-11 * \"A\"\n  Expenses:Food  4.50 USD\n  Assets:Cash\n  Assets:Bank"
        )
        #expect(result == .tooManyMissingAmounts(count: 2))
    }

    @Test func emptyCostReductionIsUndetermined() throws {
        let result = try balance(
            of: "2026-10-11 * \"A\"\n  Assets:Broker  -10 AAPL {}\n  Assets:Cash  1500.00 USD"
        )
        #expect(result == .undetermined)
    }
}
