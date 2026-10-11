//
//  File.swift
//
//
//  Created by Yeatse on 2024/1/5.
//

import Testing

@testable import BeancountSwift

struct ParserTests {
    @Test func isEntryInComplete() throws {
        let p: ContentProvider =
            """
            2014-01-27 * "UNION MARKET"
              Liabilities:US:Amex:BlueCash    -22.02 USD
              Expenses:Food:Grocery            22.02 USD

            2014-01-27 * "UNION MARKET"
              Liabilities:US:Amex:BlueCash    -22.02 USD
              Expenses:Food:Grocery
            """
        let ledger = try p.parseLedger()
        #expect(!ledger.directives[0].isIncomplete)
        #expect(ledger.directives[1].isIncomplete)
    }

    @Test func parseErrors() throws {
        let p: ContentProvider =
            """
            2013-05-40 * "Nice dinner at Mermaid Inn"
              Expenses:Restaurant         100 USD
              Assets:US:Cash
            """
        let ledger = try p.parseLedger()
        #expect(!ledger.errors.isEmpty)
    }

    @Test func parseNoErrors() throws {
        let p: ContentProvider =
            """
            2013-05-01 * "Valid date for parser"
              Expenses:Restaurant         100 USD
              Assets:US:Cash             -100 USD
            """
        let ledger = try p.parseLedger()
        #expect(ledger.errors.isEmpty)
    }

    @Test func parseEmptyString() throws {
        let p: ContentProvider = ""
        let ledger = try p.parseLedger()
        #expect(ledger.directives.count == 0)
        #expect(ledger.errors.count == 0)
    }

    @Test func unicode() throws {
        let p: ContentProvider =
            """
            2015-05-23 note Assets:Something "a¡¢£¤¥¦§¨©ª«¬®¯°±²³´µ¶·¸¹º»¼ z"
            """
        let ledger = try p.parseLedger()
        #expect(ledger.directives.count == 1)
        #expect(ledger.errors.count == 0)
    }

    @Test func parseMany() throws {
        let p: ContentProvider =
            """
            2014-12-15 * "Payee" "Narration"
              Assets:Checking   101.23 USD
              Equity:Blah
            """
        let ledger = try p.parseLedger()
        guard case .transaction(let txn) = ledger.directives[0].content else {
            Issue.record("Expected transaction directive")
            return
        }
        #expect(ledger.directives.count == 1)
        #expect(txn.postings[0].units.number == 101.23)
    }

    /// Line numbers count from 1, like Beancount. The expectations here and in
    /// ``multiLineno()`` were verified by running the same ledger through Python
    /// `bean-query`, whose parser numbers lines from 1 while the tree-sitter rows
    /// this parser reads are 0-based.
    @Test func lineno() throws {
        let p: ContentProvider = "2020-07-30 open Assets:Test"
        let ledger = try p.parseLedger()
        #expect(ledger.directives[0].meta.lineno == 1)
    }

    /// Directives synthesized by operations such as ``Summarize`` carry an explicit
    /// line number that is already in Beancount's numbering and must be reported
    /// unchanged, including the negative `<conversions>` sentinel.
    @Test func explicitLinenoIsReportedUnchanged() throws {
        let summarized: MetaData = ["filename": .string("<summarize>"), "lineno": .number(0)]
        let converted: MetaData = ["filename": .string("<conversions>"), "lineno": .number(-1)]
        #expect(summarized.lineno == 0)
        #expect(converted.lineno == -1)
    }

    @Test func multiLineno() throws {
        let p: ContentProvider =
            """
              2013-01-01 open Assets:US:Cash

              2013-05-18 * "Nice dinner at Mermaid Inn"
                Expenses:Restaurant         100 USD
                Assets:US:Cash             -100 USD

              2013-05-19 balance  Assets:US:Cash   -100 USD

              2013-05-20 note  Assets:US:Cash   "Something"
            """
        let ledger = try p.parseLedger()
        #expect(ledger.directives.count == 4)
        #expect(ledger.directives[0].meta.lineno == 1)
        #expect(ledger.directives[1].meta.lineno == 3)
        #expect(ledger.directives[2].meta.lineno == 7)
        #expect(ledger.directives[3].meta.lineno == 9)

        guard case .transaction(let txn) = ledger.directives[1].content else {
            Issue.record("Expected transaction directive")
            return
        }
        #expect(txn.postings[0].meta?.lineno == 4)
        #expect(txn.postings[1].meta?.lineno == 5)
    }

    @Test func filename() throws {
        let p: ContentProvider =
            """
              2013-01-01 open Assets:US:Cash

              2013-05-18 * "Nice dinner at Mermaid Inn"
                Expenses:Restaurant         100 USD
                Assets:US:Cash             -100 USD

              2013-05-19 balance  Assets:US:Cash   -100 USD

              2013-05-20 note  Assets:US:Cash   "Something"
            """
        let ledger = try Parser.parse(file: "main", contentProvider: p)
        #expect(ledger.directives.count == 4)
        #expect(ledger.directives[0].meta.filename == "main")
        #expect(ledger.directives[1].meta.filename == "main")
        #expect(ledger.directives[2].meta.filename == "main")
        #expect(ledger.directives[3].meta.filename == "main")

        guard case .transaction(let txn) = ledger.directives[1].content else {
            Issue.record("Expected transaction directive")
            return
        }
        #expect(txn.postings[0].meta?.filename == "main")
        #expect(txn.postings[1].meta?.filename == "main")
    }

    @Test func includeResolvesRelativeToParent() throws {
        struct MapContentProvider: ContentProviding {
            let files: [String: String]

            enum TestError: Error {
                case missing(String)
            }

            func provideContent(for name: String) throws -> String {
                guard let content = files[name] else {
                    throw TestError.missing(name)
                }
                return content
            }
        }

        let provider = MapContentProvider(files: [
            "main.beancount":
                """
            include "account/account.bean"
            2024-01-01 open Assets:Cash USD
            """,
            "account/account.bean":
                """
            include "expenses.bean"
            2024-01-02 open Expenses:Food USD
            """,
            "account/expenses.bean":
                """
            2024-01-03 open Expenses:Travel USD
            """,
        ])

        let ledger = try Parser.parse(file: "main.beancount", contentProvider: provider)
        #expect(ledger.errors.isEmpty)
        let expenseDirectives = ledger.directives.filter {
            $0.meta.filename == "account/expenses.bean"
        }
        #expect(expenseDirectives.count == 1)
    }

    @Test func includeResolvesDotSegments() throws {
        struct MapContentProvider: ContentProviding {
            let files: [String: String]

            enum TestError: Error {
                case missing(String)
            }

            func provideContent(for name: String) throws -> String {
                guard let content = files[name] else {
                    throw TestError.missing(name)
                }
                return content
            }
        }

        let provider = MapContentProvider(files: [
            "main.beancount":
                """
            include "./account/sub/root.bean"
            2024-01-01 open Assets:Cash USD
            """,
            "account/sub/root.bean":
                """
            include "./child.bean"
            2024-01-02 open Expenses:Food USD
            """,
            "account/sub/child.bean":
                """
            2024-01-03 open Expenses:Travel USD
            """,
        ])

        let ledger = try Parser.parse(file: "main.beancount", contentProvider: provider)
        #expect(ledger.errors.isEmpty)

        let filenames = Set(ledger.directives.compactMap { $0.meta.filename })
        #expect(filenames.contains("account/sub/root.bean"))
        #expect(filenames.contains("account/sub/child.bean"))
    }

    @Test func includeExpandsWithProvider() throws {
        struct ExpandingContentProvider: ContentProviding {
            let files: [String: String]
            let expansions: [String: [String]]

            enum TestError: Error {
                case missing(String)
            }

            func provideContent(for name: String) throws -> String {
                guard let content = files[name] else {
                    throw TestError.missing(name)
                }
                return content
            }

            func expandInclude(_ include: String) -> [String] {
                expansions[include] ?? [include]
            }
        }

        let provider = ExpandingContentProvider(
            files: [
                "main.beancount":
                    """
                include "account/accounts.bean"
                """,
                "account/accounts.bean":
                    """
                include "*.bean"
                """,
                "account/a.bean":
                    """
                2024-01-01 open Assets:Cash USD
                """,
                "account/b.bean":
                    """
                2024-01-02 open Expenses:Food USD
                """,
            ],
            expansions: [
                "account/*.bean": ["account/a.bean", "account/b.bean"]
            ]
        )

        let ledger = try Parser.parse(file: "main.beancount", contentProvider: provider)
        #expect(ledger.errors.isEmpty)
        #expect(ledger.directives.count == 2)
        let filenames = ledger.directives.compactMap { $0.meta.filename }
        #expect(filenames.contains("account/a.bean"))
        #expect(filenames.contains("account/b.bean"))
    }

    @Test func parseSnippetTransaction() throws {

        let content = """
            2014-12-15 * "Payee" "Narration"
              Assets:Checking   101.23 USD
              Equity:Blah      -101.23 USD
            """
        let directive = Parser.parseSnippet(from: content)
        #expect(directive != nil)
        guard case .transaction(let txn) = directive?.content else {
            Issue.record("Expected transaction directive")
            return
        }
        #expect(txn.payee == "Payee")
        #expect(txn.narration == "Narration")
        #expect(txn.postings.count == 2)
        #expect(txn.postings[0].units.number == 101.23)
    }

    @Test func parseSnippetOpen() throws {

        let directive = Parser.parseSnippet(from: "2020-07-30 open Assets:Test USD")
        #expect(directive != nil)
        guard case .open(let open) = directive?.content else {
            Issue.record("Expected open directive")
            return
        }
        #expect(open.account == "Assets:Test")
        #expect(open.currencies == ["USD"])
    }

    @Test func parseSnippetClose() throws {

        let directive = Parser.parseSnippet(from: "2020-12-31 close Assets:Test")
        #expect(directive != nil)
        guard case .close(let close) = directive?.content else {
            Issue.record("Expected close directive")
            return
        }
        #expect(close.account == "Assets:Test")
    }

    @Test func parseSnippetBalance() throws {

        let directive = Parser.parseSnippet(from: "2020-07-30 balance Assets:Test 1000.00 USD")
        #expect(directive != nil)
        guard case .balance(let balance) = directive?.content else {
            Issue.record("Expected balance directive")
            return
        }
        #expect(balance.account == "Assets:Test")
        #expect(balance.amount.number == 1000.00)
        #expect(balance.amount.currency == "USD")
    }

    @Test func parseSnippetNote() throws {

        let directive = Parser.parseSnippet(from: "2020-07-30 note Assets:Test \"This is a note\"")
        #expect(directive != nil)
        guard case .note(let note) = directive?.content else {
            Issue.record("Expected note directive")
            return
        }
        #expect(note.account == "Assets:Test")
        #expect(note.note == "This is a note")
    }

    @Test func parseSnippetPrice() throws {

        let directive = Parser.parseSnippet(from: "2020-07-30 price EUR 1.20 USD")
        #expect(directive != nil)
        guard case .price(let price) = directive?.content else {
            Issue.record("Expected price directive")
            return
        }
        #expect(price.currency == "EUR")
        #expect(price.amount.number == 1.20)
        #expect(price.amount.currency == "USD")
    }

    @Test func parseSnippetInvalidContent() throws {

        let directive = Parser.parseSnippet(from: "invalid content")
        #expect(directive == nil)
    }

    @Test func parseSnippetEmptyString() throws {

        let directive = Parser.parseSnippet(from: "")
        #expect(directive == nil)
    }

    @Test func parseSnippetMultipleDirectives() throws {

        let content = """
            2020-07-30 open Assets:Test USD
            2020-07-31 close Assets:Test
            """
        // parseSnippet should only return the first directive
        let directive = Parser.parseSnippet(from: content)
        #expect(directive != nil)
        guard case .open = directive?.content else {
            Issue.record("Expected open directive")
            return
        }
    }

    @Test func parseSnippetsMultipleDirectives() throws {

        let content = """
            2020-07-30 open Assets:Checking USD
            2020-07-31 open Assets:Savings USD

            2020-08-01 * "Test transaction"
              Assets:Checking  100.00 USD
              Income:Salary   -100.00 USD

            2020-08-02 balance Assets:Checking 100.00 USD
            2020-12-31 close Assets:Savings
            """
        let directives = Parser.parseSnippets(from: content)
        #expect(directives.count == 5)

        guard case .open = directives[0].content else {
            Issue.record("Expected open directive at index 0")
            return
        }
        guard case .open = directives[1].content else {
            Issue.record("Expected open directive at index 1")
            return
        }
        guard case .transaction = directives[2].content else {
            Issue.record("Expected transaction directive at index 2")
            return
        }
        guard case .balance = directives[3].content else {
            Issue.record("Expected balance directive at index 3")
            return
        }
        guard case .close = directives[4].content else {
            Issue.record("Expected close directive at index 4")
            return
        }
    }

    @Test func parseSnippetsEmptyString() throws {

        let directives = Parser.parseSnippets(from: "")
        #expect(directives.isEmpty)
    }

    @Test func parseSnippetsSingleDirective() throws {

        let content = "2020-07-30 open Assets:Test USD"
        let directives = Parser.parseSnippets(from: content)
        #expect(directives.count == 1)
        guard case .open = directives[0].content else {
            Issue.record("Expected open directive")
            return
        }
    }

    @Test func parseSnippetsWithInvalidContent() throws {

        let content = """
            2020-07-30 open Assets:Checking USD
            invalid line that should be skipped
            2020-07-31 close Assets:Checking
            another invalid line
            """
        let directives = Parser.parseSnippets(from: content)
        // Should parse only the valid directives
        #expect(directives.count == 2)
        guard case .open = directives[0].content else {
            Issue.record("Expected open directive at index 0")
            return
        }
        guard case .close = directives[1].content else {
            Issue.record("Expected close directive at index 1")
            return
        }
    }

    @Test func parseSnippetsWithComments() throws {

        let content = """
            ; This is a comment
            2020-07-30 open Assets:Test USD
            ; Another comment
            2020-07-31 balance Assets:Test 100.00 USD
            """
        let directives = Parser.parseSnippets(from: content)
        #expect(directives.count == 2)
    }

    @Test func parseSnippetsPreservesOrder() throws {

        let content = """
            2020-07-30 open Assets:A USD
            2020-07-29 open Assets:B USD
            2020-07-31 open Assets:C USD
            """
        let directives = Parser.parseSnippets(from: content)
        #expect(directives.count == 3)
        #expect(directives[0].date == "2020-07-30")
        #expect(directives[1].date == "2020-07-29")
        #expect(directives[2].date == "2020-07-31")
    }

    private func validationProblems(_ content: String) -> [SnippetError] {
        do {
            try Parser.validateSnippets(content)
            return []
        } catch {
            return error.problems
        }
    }

    @Test func validateSnippetsAcceptsCleanSnippet() throws {
        let content = """
            ; leading comment
            2026-10-11 * "JD" "" #trip
              payer: "Me"
              Expenses:Food  (120.00 - 10.00) CNY  ; discounted
              Assets:Cash
            2026-10-11 open Assets:Bank CNY
            """
        #expect(validationProblems(content).isEmpty)
        #expect(Parser.parseSnippets(from: content).count == 2)
    }

    @Test(arguments: [
        ("2026-10-11 * \"A\"\nExpenses:Food  4.50 USD\n  Assets:Cash", 2),
        ("2026-10-11 * \"A\"\n  Expenses:Food  4.50 USD USD\n  Assets:Cash", 2),
        ("2026-10-11 * \"A\"\n  expenses:food  4.50 USD\n  Assets:Cash", 2),
        ("2026-10-11 * Latte\n  Expenses:Food  4.50 USD\n  Assets:Cash", 1),
        ("2026-10-11 * \"A\"\n  Expenses:Food  4.50 USD\n    k: 1\n  Assets:Cash", 3),
        ("2026-13-41 * \"A\"\n  Expenses:Food  4.50 USD\n  Assets:Cash", 1),
    ])
    func validateSnippetsReportsRecoveredErrors(content: String, lineno: Int) throws {
        #expect(validationProblems(content).map(\.lineno) == [lineno])
    }

    @Test func validateSnippetsRejectsNonDirectives() throws {
        let problems = validationProblems(
            """
            option "title" "x"
            plugin "beancount.plugins.auto"
            include "other.bean"
            2026-10-11 open Assets:Bank CNY
            trailing junk
            """
        )
        #expect(problems.map(\.lineno) == [1, 2, 3, 5])
        #expect(problems[0].message == "Only directives are allowed, found option")
    }

    @Test func validateSnippetsRejectsUnbalancedTransactions() throws {
        let problems = validationProblems(
            """
            2026-10-11 * "Balanced by omission"
              Expenses:Food  4.50 USD
              Assets:Cash
            2026-10-11 * "Unbalanced"
              Expenses:Food  4.50 USD
              Assets:Cash  -4.00 USD
            2026-10-11 * "Two omissions"
              Expenses:Food  4.50 USD
              Assets:Cash
              Assets:Bank
            """
        )
        #expect(problems.map(\.lineno) == [4, 7])
        #expect(problems[0].message == "Transaction does not balance: residual 0.50 USD")
        #expect(
            problems[1].message == "2 postings omit their amount; at most one posting may omit it")
    }
}
