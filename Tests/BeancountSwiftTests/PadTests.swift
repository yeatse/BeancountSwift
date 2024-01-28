//
//  PadTests.swift
//  
//
//  Created by Yeatse on 2024/1/28.
//

import XCTest

final class PadTests: XCTestCase {
    
    func testPadSimple() async throws {
        let p: ContentProvider =
        """
        2013-05-01 open Assets:Checking
        2013-05-01 open Equity:Opening-Balances
        
        ;; Test the simple case that this directive generates a padding entry.
        2013-05-01 pad Assets:Checking Equity:Opening-Balances
        
        2013-05-03 balance Assets:Checking                                 172.45 USD
        """
        let ledger = try await p.loadLedger()
        XCTAssertTrue(ledger.errors.isEmpty)
        
        let equal = await equalEntries(ledger.directives,
          """
          2013-05-01 open Assets:Checking
          2013-05-01 open Equity:Opening-Balances

          2013-05-01 pad Assets:Checking Equity:Opening-Balances

          ;; Check this is inserted.
          2013-05-01 P "(Padding inserted for Balance of 172.45 USD for difference 172.45 USD)"
            Assets:Checking                                                        172.45 USD
            Equity:Opening-Balances                                                -172.45 USD

          2013-05-03 balance Assets:Checking                                172.45 USD
          """)
        XCTAssertTrue(equal)
    }
    
    func testPadToZero() async throws {
        let p: ContentProvider =
        """
        ;; Test the case that this directive generates a padding entry, padding to zero.
        2013-01-01 open Assets:Checking
        2013-01-01 open Equity:Opening-Balances

        2013-02-01 *
          Assets:Checking           234.56 USD
          Equity:Opening-Balances  -234.56 USD

        2013-05-01 pad Assets:Checking Equity:Opening-Balances

        2013-05-03 balance Assets:Checking                                 0.00 USD
        """
        let ledger = try await p.loadLedger()
        XCTAssertTrue(ledger.errors.isEmpty)
        
        let equal = await equalEntries(ledger.directives,
          """
          2013-01-01 open Assets:Checking
          2013-01-01 open Equity:Opening-Balances

          2013-02-01 *
            Assets:Checking           234.56 USD
            Equity:Opening-Balances  -234.56 USD

          2013-05-01 pad Assets:Checking Equity:Opening-Balances

          ;; Check this is inserted.
          2013-05-01 P "(Padding inserted for Balance of 0.00 USD for difference -234.56 USD)"
            Assets:Checking          -234.56 USD
            Equity:Opening-Balances   234.56 USD

          2013-05-03 balance Assets:Checking                                 0.00 USD
          """)
        XCTAssertTrue(equal)
    }
    
    // TODO: add more tests
}
