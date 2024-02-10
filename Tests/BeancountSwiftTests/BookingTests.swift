//
//  BookingTests.swift
//
//
//  Created by Yeatse on 2023/12/25.
//

import XCTest

@testable import BeancountSwift

final class BookingTests: XCTestCase {
    let booking = Booking()
    
    func testZeroAmount() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      0 MSFT
                Assets:Investments:Cash      0 USD
            """
        let ledger = try p.parseLedger()
        let bookedLedger = booking.book(ledger: ledger)
        XCTAssertEqual(bookedLedger.errors.count, 0)
    }

    func testZeroAmountWithCost() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      0 MSFT {200.00 USD}
                Assets:Investments:Cash    1 USD
            """
        let ledger = try p.parseLedger()
        let bookedLedger = booking.book(ledger: ledger)
        XCTAssertEqual(bookedLedger.errors.count, 1)
        XCTAssert(bookedLedger.errors[0] is InterpolationError)
    }

    func testCostZero() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      -10 MSFT {0.00 USD}
                Assets:Investments:Cash  2000.00 USD
            """
        let ledger = try p.parseLedger()
        let bookedLedger = booking.book(ledger: ledger)
        XCTAssertEqual(bookedLedger.errors.count, 0)
    }

    func testCostNegative() throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      -10 MSFT {-200.00 USD}
                Assets:Investments:Cash  2000.00 USD
            """
        let ledger = try p.parseLedger()
        let bookedLedger = booking.book(ledger: ledger)
        XCTAssertEqual(bookedLedger.directives.count, 1)
        XCTAssertEqual(bookedLedger.errors.count, 1)
        XCTAssert(bookedLedger.errors[0] is InterpolationError)
    }
    
    func testAllCurrencyInterpolations() throws {
        let p: ContentProvider =
"""
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
        XCTAssert(ledger.errors.isEmpty)
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
    
    func testCategorizeUnitsUnambiguous() throws {
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
    
    func testCategorizeUnitsAmbiguous() throws {
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
        var (groups, errors) = booking.categorizeByCurrency(transaction: ledger.directives[0].transaction,
                                                            balances: [:])
        XCTAssert(errors.isEmpty)
        XCTAssertEqual(indexes(of: groups), [
            "USD": [0, 1]
        ])
        
        (groups, errors) = booking.categorizeByCurrency(transaction: ledger.directives[1].transaction,
                                                        balances: ["Assets:Account": "1.00 USD"])
        XCTAssert(errors.isEmpty)
        XCTAssertEqual(indexes(of: groups), [
            "USD": [0, 1]
        ])
        
        (groups, errors) = booking.categorizeByCurrency(transaction: ledger.directives[1].transaction,
                                                        balances: [:])
        XCTAssert(!errors.isEmpty)
        XCTAssert(String(describing: errors[0]).contains("failedToCategorize"))
        XCTAssertEqual(indexes(of: groups), [:])
    }
    
    func testCategorizeUnitsPriceUnambiguous() throws {
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
        var (groups, errors) = booking.categorizeByCurrency(transaction: ledger.directives[0].transaction,
                                                            balances: [:])
        XCTAssert(errors.isEmpty)
        XCTAssertEqual(indexes(of: groups), [
            "CAD": [0, 1]
        ])
        
        (groups, errors) = booking.categorizeByCurrency(transaction: ledger.directives[1].transaction,
                                                        balances: ["Assets:Account": "1.00 USD"])
        XCTAssert(errors.isEmpty)
        XCTAssertEqual(indexes(of: groups), [
            "CAD": [0, 1]
        ])
        
        (groups, errors) = booking.categorizeByCurrency(transaction: ledger.directives[1].transaction,
                                                        balances: [:])
        XCTAssert(!errors.isEmpty)
        XCTAssert(String(describing: errors[0]).contains("cannotResolve"))
        XCTAssertEqual(indexes(of: groups), [
            "CAD": [0, 1]
        ])
    }
}
