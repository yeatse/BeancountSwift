//
//  BookingTests.swift
//
//
//  Created by Yeatse on 2023/12/25.
//

import XCTest

@testable import BeancountSwift

final class BookingTests: XCTestCase {
    let booking = Booker()
    
    func testZeroAmount() async throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      0 MSFT
                Assets:Investments:Cash      0 USD
            """
        let ledger = try await p.parseLedger()
        let bookedLedger = booking.book(ledger: ledger)
        XCTAssertEqual(bookedLedger.errors.count, 0)
    }

    func testZeroAmountWithCost() async throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      0 MSFT {200.00 USD}
                Assets:Investments:Cash    1 USD
            """
        let ledger = try await p.parseLedger()
        let bookedLedger = booking.book(ledger: ledger)
        XCTAssertEqual(bookedLedger.errors.count, 1)
        XCTAssert(bookedLedger.errors[0] is InterpolationError)
    }

    func testCostZero() async throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      -10 MSFT {0.00 USD}
                Assets:Investments:Cash  2000.00 USD
            """
        let ledger = try await p.parseLedger()
        let bookedLedger = booking.book(ledger: ledger)
        XCTAssertEqual(bookedLedger.errors.count, 0)
    }

    func testCostNegative() async throws {
        let p: ContentProvider =
            """
              2013-05-18 * ""
                Assets:Investments:MSFT      -10 MSFT {-200.00 USD}
                Assets:Investments:Cash  2000.00 USD
            """
        let ledger = try await p.parseLedger()
        let bookedLedger = booking.book(ledger: ledger)
        XCTAssertEqual(bookedLedger.directives.count, 1)
        XCTAssertEqual(bookedLedger.errors.count, 1)
        XCTAssert(bookedLedger.errors[0] is InterpolationError)
    }

    let inputStr =
        """
                2014-01-01 open Assets:Investments:Cash
                2014-01-01 open Assets:Investments:Stock

                2014-06-22 * "Add some positive units"
                  Assets:Investments:Stock    1 HOOL {500 USD}
                  Assets:Investments:Cash  -500 USD

                2014-06-23 * "Down to zero"
                  Assets:Investments:Stock   -1 HOOL {500 USD}
                  Assets:Investments:Cash   500 USD

                2014-06-24 * "Go negative from zero"
                  Assets:Investments:Stock   -1 HOOL {500 USD}
                  Assets:Investments:Cash   500 USD

                2014-06-25 * "Go positive much"
                  Assets:Investments:Stock    11 HOOL {500 USD}
                  Assets:Investments:Cash  -5500 USD

                2014-06-26 * "Cross to negative from above zero"
                  Assets:Investments:Stock  -15 HOOL {500 USD}
                  Assets:Investments:Cash  7500 USD
        """

    let bookmeth = BookingMethodStore(mappings: [:], defaultMethod: .STRICT)
}
