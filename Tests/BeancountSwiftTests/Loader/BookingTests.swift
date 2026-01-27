//
//  BookingTests.swift
//
//
//  Created by Yeatse on 2023/12/25.
//

import Testing

@testable import BeancountSwift

struct BookingTests {
    
    
    @Test func zeroAmount() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      0 MSFT
                Assets:Investments:Cash      0 USD
            """
        let ledger = try p.parseLedger()
        let bookedLedger = Booking.book(ledger: ledger)
        #expect(bookedLedger.errors.count == 0)
    }

    @Test func zeroAmountWithCost() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      0 MSFT {200.00 USD}
                Assets:Investments:Cash    1 USD
            """
        let ledger = try p.parseLedger()
        let bookedLedger = Booking.book(ledger: ledger)
        #expect(bookedLedger.errors.count == 1)
        #expect(bookedLedger.errors.first is InterpolationError)
    }

    @Test func costZero() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      -10 MSFT {0.00 USD}
                Assets:Investments:Cash  2000.00 USD
            """
        let ledger = try p.parseLedger()
        let bookedLedger = Booking.book(ledger: ledger)
        #expect(bookedLedger.errors.count == 0)
    }

    @Test func costNegative() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      -10 MSFT {-200.00 USD}
                Assets:Investments:Cash  2000.00 USD
            """
        let ledger = try p.parseLedger()
        let bookedLedger = Booking.book(ledger: ledger)
        #expect(bookedLedger.directives.count == 1)
        #expect(bookedLedger.errors.count == 1)
        #expect(bookedLedger.errors.first is InterpolationError)
    }

    @Test func emptyCostSpecWithPrice() throws {
        let p: ContentProvider =
            """
              2024-11-20 * "沪深300ETF (510300)" "证券卖出"
                Assets:Investments:EastMoney:CNS510300                 -100 CNS510300 {} @ 4.068 CNY
                Expenses:Investments:EastMoney:Commissions                      +0.10 CNY
                Assets:Investments:EastMoney:EastMoney-xxx                  +406.70 CNY
                Income:Investments:EastMoney:PnL
            """
        let ledger = try p.parseLedger()
        let bookedLedger = Booking.book(ledger: ledger)
        #expect(bookedLedger.errors.isEmpty)
        let posting = bookedLedger.directives[0].transaction.postings.first {
            $0.account == "Assets:Investments:EastMoney:CNS510300"
        }
        #expect(posting != nil)
        #expect(posting?.cost == nil)
        #expect(posting?.price == "4.068 CNY")
    }
    
    @Test func allCurrencyInterpolations() throws {
        let p: ContentProvider =
"""
2015-10-01 open Assets:Account
2015-10-01 open Assets:Other

2015-10-02 *
    Assets:Account  100.00 USD
    Assets:Other

2015-10-02 *
    Assets:Account  100.00 USD @ 1.20 CAD
    Assets:Other

2015-10-02 *
    Assets:Account  10 HOOL {{100.00 USD}} @ 120.00 USD
    Assets:Other
"""
        let ledger = try p.loadLedger()
        #expect(ledger.errors.isEmpty)
    }
    
    func indexes(of groups: [(Currency, [Booking.Refer])]) -> [Currency: Set<Int>] {
        var result: [Currency: Set<Int>] = [:]
        for (currency, refers) in groups {
            result[currency] = refers.reduce([], { p, refers in
                p.union([refers.index])
            })
        }
        return result
    }
    
    @Test func categorizeUnitsUnambiguous() throws {
        let p: ContentProvider =
        """
            2015-10-02 *
              Assets:Account  100.00 USD
              Assets:Other   -100.00 USD
        
            2015-10-02 *
              Assets:Account         USD
              Assets:Other   -100.00 USD
        """
        let _ = try p.parseLedger()
        // TOOD: not supported yet
    }
    
    @Test func categorizeUnitsAmbiguous() throws {
        let p: ContentProvider =
        """
        ;; Uses the other legs to disambiguate.
        2015-10-02 *
          Assets:Account  100.00
          Assets:Other   -100.00 USD

        ;; Uses the inventory contents to disambiguate.
        2015-10-02 *
          Assets:Account  100.00
          Assets:Other
        """
        let ledger = try p.parseLedger()
        var (groups, errors) = Booking.categorizeByCurrency(transaction: ledger.directives[0].transaction,
                                                            balances: [:])
        #expect(errors.isEmpty)
        #expect(indexes(of: groups) == [
            "USD": [0, 1]
        ])
        
        (groups, errors) = Booking.categorizeByCurrency(transaction: ledger.directives[1].transaction,
                                                        balances: ["Assets:Account": "1.00 USD"])
        #expect(errors.isEmpty)
        #expect(indexes(of: groups) == [
            "USD": [0, 1]
        ])
        
        (groups, errors) = Booking.categorizeByCurrency(transaction: ledger.directives[1].transaction,
                                                        balances: [:])
        #expect(!errors.isEmpty)
        #expect(String(describing: errors.first).contains("failedToCategorize"))
        #expect(indexes(of: groups) == [:])
    }
    
    @Test func categorizeUnitsPriceUnambiguous() throws {
        let p: ContentProvider =
        """
        2015-10-02 *
          Assets:Account  100.00 USD @ 1.20 CAD
          Assets:Other   -120.00 CAD

        2015-10-02 *
          Assets:Account  100.00     @ 1.20 CAD
          Assets:Other   -120.00 CAD
        """
        let ledger = try p.parseLedger()
        var (groups, errors) = Booking.categorizeByCurrency(transaction: ledger.directives[0].transaction,
                                                            balances: [:])
        #expect(errors.isEmpty)
        #expect(indexes(of: groups) == [
            "CAD": [0, 1]
        ])
        
        (groups, errors) = Booking.categorizeByCurrency(transaction: ledger.directives[1].transaction,
                                                        balances: ["Assets:Account": "1.00 USD"])
        #expect(errors.isEmpty)
        #expect(indexes(of: groups) == [
            "CAD": [0, 1]
        ])
        
        (groups, errors) = Booking.categorizeByCurrency(transaction: ledger.directives[1].transaction,
                                                        balances: [:])
        #expect(!errors.isEmpty)
        #expect(String(describing: errors.first).contains("cannotResolve"))
        #expect(indexes(of: groups) == [
            "CAD": [0, 1]
        ])
    }
}
