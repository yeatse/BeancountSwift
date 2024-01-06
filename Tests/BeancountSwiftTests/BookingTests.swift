//
//  BookingTests.swift
//
//
//  Created by Yeatse on 2023/12/25.
//

import XCTest

@testable import BeancountSwift

final class BookingTests: XCTestCase {
    func testZeroAmount() async throws {
        let p: ContentProvider =
        """
          2013-05-18 * ""
            Assets:Investments:MSFT      0 MSFT
            Assets:Investments:Cash      0 USD
        """
        let ledger = try await parser.parse(file: "main", contentProvider: p)
        let bookedLedger = booking.book(ledger: ledger)
        XCTAssertEqual(bookedLedger.errors.count, 0)
    }
}
