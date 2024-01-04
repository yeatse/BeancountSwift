//
//  InventoryTests.swift
//
//
//  Created by Yeatse on 2024/1/5.
//

import XCTest

@testable import BeancountSwift

final class InventoryTests: XCTestCase {
    func checkAmount(inventory: Inventory, number: Decimal, currency: Currency) {
        let amount = Amount(number: number, currency: currency)
        let invAmount = inventory.getCurrencyUnits(in: currency)
        XCTAssertEqual(amount, invAmount)
    }

    func testCtorEmptyLen() {
        var inv = Inventory()
        XCTAssertTrue(inv.isEmpty)
        XCTAssertEqual(inv.positions.count, 0)

        inv = Inventory(positions: [
            .init(units: .init(number: 100, currency: "USD")),
            .init(units: .init(number: 101, currency: "USD")),
        ])
        XCTAssertFalse(inv.isEmpty)
        XCTAssertEqual(inv.positions.count, 1)

        inv = Inventory(positions: [
            .init(units: .init(number: 100, currency: "USD")),
            .init(units: .init(number: 100, currency: "CAD")),
        ])
        XCTAssertFalse(inv.isEmpty)
        XCTAssertEqual(inv.positions.count, 2)

        inv = Inventory()
        XCTAssertEqual(inv.positions.count, 0)
        inv.addAmount(.init(number: 100, currency: "USD"))
        XCTAssertEqual(inv.positions.count, 1)
        inv.addAmount(.init(number: 100, currency: "CAD"))
        XCTAssertEqual(inv.positions.count, 2)
    }

    func testCopy() {
        let inv = Inventory()
        inv.addAmount(.init(number: 100, currency: "USD"))
        checkAmount(inventory: inv, number: 100, currency: "USD")

        let inv2 = inv.copy() as! Inventory
        inv2.addAmount(.init(number: 50, currency: "USD"))
        checkAmount(inventory: inv2, number: 150, currency: "USD")

        // make sure the original object is not modified
        checkAmount(inventory: inv, number: 100, currency: "USD")
    }

    func testEqualOp() {
        let inv1 = Inventory(positions: [
            .init(units: .init(number: 100, currency: "USD")),
            .init(units: .init(number: 100, currency: "CAD")),
        ])
        let inv2 = Inventory(positions: [
            .init(units: .init(number: 100, currency: "CAD")),
            .init(units: .init(number: 100, currency: "USD")),
        ])
        XCTAssertEqual(inv1, inv2)
        XCTAssertEqual(inv2, inv1)

        let inv3 = Inventory(positions: [
            .init(units: .init(number: 200, currency: "USD")),
            .init(units: .init(number: 100, currency: "CAD")),
        ])
        XCTAssertNotEqual(inv1, inv3)
        XCTAssertNotEqual(inv3, inv1)

        let inv4 = Inventory(positions: [
            .init(units: .init(number: 100, currency: "USD")),
            .init(units: .init(number: 100, currency: "JPY")),
        ])
        XCTAssertNotEqual(inv1, inv4)
        XCTAssertNotEqual(inv4, inv1)

        let inv5 = Inventory(positions: [
            .init(units: .init(number: 100, currency: "JPY")),
            .init(units: .init(number: 100, currency: "USD")),
        ])
        XCTAssertEqual(inv4, inv5)
    }

    func testLtOp() {
        let inv1 = Inventory(positions: [
            .init(units: .init(number: 100, currency: "USD")),
            .init(units: .init(number: 100, currency: "CAD")),
        ])
        let inv2 = Inventory(positions: [
            .init(units: .init(number: 100, currency: "CAD")),
            .init(units: .init(number: 100, currency: "USD")),
        ])
        XCTAssertLessThan(inv1, inv2)
        XCTAssertGreaterThan(inv2, inv1)

        let inv3 = Inventory(positions: [
            .init(units: .init(number: 200, currency: "USD")),
            .init(units: .init(number: 100, currency: "CAD")),
        ])
        XCTAssertLessThan(inv1, inv2)
        XCTAssertLessThan(inv2, inv3)
        XCTAssertGreaterThan(inv3, inv1)

        let inv4 = Inventory(positions: [
            .init(units: .init(number: 100, currency: "USD")),
            .init(units: .init(number: 100, currency: "JPY")),
        ])
        XCTAssertGreaterThan(inv1, inv4)

        let inv5 = Inventory(positions: [
            .init(units: .init(number: 100, currency: "JPY")),
            .init(units: .init(number: 100, currency: "USD")),
        ])
        XCTAssertGreaterThan(inv1, inv5)
        XCTAssertGreaterThan(inv4, inv5)
    }

    func testIsSmallValue() {
        let testInv = Inventory(positions: [
            .init(units: .init(number: 1.50, currency: "JPY")),
            .init(units: .init(number: 1.51, currency: "USD")),
            .init(units: .init(number: 1.52, currency: "CAD")),
        ])
        for inv in [testInv, -testInv] {
            XCTAssertFalse(inv.isSmall(tolerance: 1.49))
            XCTAssertFalse(inv.isSmall(tolerance: 1.50))
            XCTAssertTrue(inv.isSmall(tolerance: 1.53))
            XCTAssertTrue(inv.isSmall(tolerance: 1.52))
        }
    }

    func testIsSmallDict() {
        let testInv = Inventory(positions: [
            .init(units: .init(number: 0.03, currency: "JPY")),
            .init(units: .init(number: 0.003, currency: "USD")),
        ])
        for inv in [testInv, -testInv] {
            XCTAssertTrue(inv.isSmall(tolerances: ["JPY": 0.05, "USD": 0.005]))
            XCTAssertFalse(inv.isSmall(tolerances: ["JPY": 0.005, "USD": 0.0005]))
            XCTAssertTrue(inv.isSmall(tolerances: ["JPY": 0.05, "USD": 0.05]))
            XCTAssertFalse(inv.isSmall(tolerances: ["JPY": 0.005, "USD": 0.005]))

            XCTAssertTrue(inv.isSmall(tolerances: ["JPY": 0.03, "USD": 0.003]))
            XCTAssertFalse(inv.isSmall(tolerances: ["JPY": 0.02999999999999, "USD": 0.003]))
            XCTAssertFalse(inv.isSmall(tolerances: ["JPY": 0.03, "USD": 0.00299999]))

            XCTAssertFalse(inv.isSmall(tolerances: ["JPY": 0.05]))
            XCTAssertFalse(inv.isSmall(tolerances: ["USD": 0.005]))

            XCTAssertTrue(inv.isSmall(tolerances: ["JPY": 0.05, "USD": 0.005, "CAD": 0.0005]))

            XCTAssertFalse(inv.isSmall(tolerances: [:]))
        }
    }

    func testIsSmallWithDefault() {
        let inv = Inventory(positions: [
            .init(units: .init(number: 0.03, currency: "JPY"))
        ])
        XCTAssertTrue(inv.isSmall(tolerances: ["JPY": 0.05]))
        XCTAssertFalse(inv.isSmall(tolerances: ["JPY": 0.02]))
    }

    func testIsMixed() {
        var inv = Inventory(positions: [
            .init(
                units: .init(number: 100, currency: "HOOL"),
                cost: .init(number: 250, currency: "USD", date: .distantFuture)),
            .init(
                units: .init(number: 101, currency: "HOOL"),
                cost: .init(number: 251, currency: "USD", date: .distantFuture)),
        ])
        XCTAssertFalse(inv.isMixed())

        inv = Inventory(positions: [
            .init(
                units: .init(number: 100, currency: "HOOL"),
                cost: .init(number: 250, currency: "USD", date: .distantFuture)),
            .init(
                units: .init(number: -1, currency: "HOOL"),
                cost: .init(number: 251, currency: "USD", date: .distantFuture)),
        ])
        XCTAssertTrue(inv.isMixed())

        inv = Inventory(positions: [
            .init(
                units: .init(number: -2, currency: "HOOL"),
                cost: .init(number: 250, currency: "USD", date: .distantFuture)),
            .init(
                units: .init(number: -1, currency: "HOOL"),
                cost: .init(number: 251, currency: "USD", date: .distantFuture)),
        ])
        XCTAssertFalse(inv.isMixed())
    }

    func testIsReducedBy() {
        var inv = Inventory(positions: [
            .init(
                units: .init(number: 100, currency: "HOOL"),
                cost: .init(number: 250, currency: "USD", date: .distantFuture)),
            .init(
                units: .init(number: 101, currency: "HOOL"),
                cost: .init(number: 251, currency: "USD", date: .distantFuture)),
        ])
        XCTAssertFalse(inv.isReducedBy(.init(number: 2, currency: "HOOL")))
        XCTAssertFalse(inv.isReducedBy(.init(number: 0, currency: "HOOL")))
        XCTAssertTrue(inv.isReducedBy(.init(number: -2, currency: "HOOL")))

        inv = Inventory(positions: [
            .init(
                units: .init(number: 100, currency: "HOOL"),
                cost: .init(number: 250, currency: "USD", date: .distantFuture)),
            .init(
                units: .init(number: -101, currency: "HOOL"),
                cost: .init(number: 251, currency: "USD", date: .distantFuture)),
        ])
        XCTAssertTrue(inv.isReducedBy(.init(number: 2, currency: "HOOL")))
        XCTAssertFalse(inv.isReducedBy(.init(number: 0, currency: "HOOL")))
        XCTAssertTrue(inv.isReducedBy(.init(number: -2, currency: "HOOL")))
    }

    func testNegOp() {
        let inv = Inventory()
        inv.addAmount(.init(number: 10, currency: "USD"))
        checkAmount(inventory: -inv, number: -10, currency: "USD")

        let pinv = Inventory(positions: [
            .init(units: .init(number: 1.50, currency: "JPY")),
            .init(units: .init(number: 1.51, currency: "USD")),
            .init(units: .init(number: 1.52, currency: "CAD")),
        ])
        let ninv = Inventory(positions: [
            .init(units: .init(number: -1.50, currency: "JPY")),
            .init(units: .init(number: -1.51, currency: "USD")),
            .init(units: .init(number: -1.52, currency: "CAD")),
        ])
        XCTAssertEqual(-pinv, ninv)
    }

    func testAbsOp() {
        let inv = Inventory(positions: [
            .init(units: .init(number: 1.50, currency: "USD")),
            .init(units: .init(number: 2.00, currency: "USD")),
            .init(units: .init(number: -1.52, currency: "CAD")),
        ])
        XCTAssertEqual(
            inv.absolute,
            Inventory(positions: [
                .init(units: .init(number: 3.50, currency: "USD")),
                .init(units: .init(number: 1.52, currency: "CAD")),
            ]))
    }

    func testMulOp() {
        let inv = Inventory(positions: [
            .init(
                units: .init(number: 10, currency: "HOOL"),
                cost: .init(number: 1.11, currency: "USD", date: .distantPast)),
            .init(units: .init(number: Decimal(string: "2.22")!, currency: "CAD")),
        ])
        let inv2 = inv * 3
        XCTAssertEqual(
            inv2,
            Inventory(positions: [
                .init(
                    units: .init(number: 30, currency: "HOOL"),
                    cost: .init(number: 1.11, currency: "USD", date: .distantPast)),
                .init(units: .init(number: 6.66, currency: "CAD")),
            ]))
    }

    func testGetOnlyPosition() {
        let inv = Inventory(positions: [
            .init(
                units: .init(number: 10, currency: "HOOL"),
                cost: .init(number: 1.11, currency: "USD", date: .distantPast))
        ])
        XCTAssertEqual(Amount(number: 10, currency: "HOOL"), inv.onlyPosition?.units)
        XCTAssertNil(Inventory().onlyPosition)
    }

    func testGetCurrencyUnits() {
        let inv = Inventory(positions: [
            .init(units: .init(number: 40.50, currency: "JPY")),
            .init(
                units: .init(number: 40.51, currency: "USD"),
                cost: .init(number: 1.01, currency: "CAD", date: .distantPast)),
            .init(units: .init(number: 40.52, currency: "CAD")),
        ])
        XCTAssertEqual(inv.getCurrencyUnits(in: "JPY"), .init(number: 40.50, currency: "JPY"))
        XCTAssertEqual(inv.getCurrencyUnits(in: "USD"), .init(number: 40.51, currency: "USD"))
        XCTAssertEqual(inv.getCurrencyUnits(in: "CAD"), .init(number: 40.52, currency: "CAD"))
        XCTAssertEqual(inv.getCurrencyUnits(in: "AUD"), .init(number: 0, currency: "AUD"))
        XCTAssertEqual(inv.getCurrencyUnits(in: "NZD"), .init(number: 0, currency: "NZD"))
    }

    func testSegregateUnits() {
        let inv = Inventory(positions: [
            .init(
                units: .init(number: 2.2, currency: "HOOL"),
                cost: .init(number: 532.43, currency: "USD", date: .distantPast)),
            .init(
                units: .init(number: 2.3, currency: "HOOL"),
                cost: .init(number: 564.00, currency: "USD", date: .distantFuture)),
            .init(units: .init(number: 3.41, currency: "CAD")),
            .init(units: .init(number: 101.20, currency: "USD")),
        ])
        let ccymap = inv.segregateUnits(by: ["HOOL", "USD", "EUR"])
        XCTAssertEqual(
            ccymap,
            [
                nil: Inventory(positions: [.init(units: .init(number: 3.41, currency: "CAD"))]),
                "USD": Inventory(positions: [.init(units: .init(number: 101.20, currency: "USD"))]),
                "EUR": Inventory(),
                "HOOL": Inventory(positions: [
                    .init(
                        units: .init(number: 2.2, currency: "HOOL"),
                        cost: .init(number: 532.43, currency: "USD", date: .distantPast)),
                    .init(
                        units: .init(number: 2.3, currency: "HOOL"),
                        cost: .init(number: 564.00, currency: "USD", date: .distantFuture)),
                ]),
            ])
    }

    func testSplit() {
        let inv = Inventory(positions: [
            .init(
                units: .init(number: 2.2, currency: "HOOL"),
                cost: .init(number: 532.43, currency: "USD", date: .distantPast)),
            .init(
                units: .init(number: 2.3, currency: "HOOL"),
                cost: .init(number: 564.00, currency: "USD", date: .distantFuture)),
            .init(units: .init(number: 3.41, currency: "CAD")),
            .init(units: .init(number: 101.20, currency: "USD")),
        ])
        let ccymap = inv.split()
        XCTAssertEqual(
            ccymap,
            [
                "CAD": Inventory(positions: [.init(units: .init(number: 3.41, currency: "CAD"))]),
                "USD": Inventory(positions: [.init(units: .init(number: 101.20, currency: "USD"))]),
                "HOOL": Inventory(positions: [
                    .init(
                        units: .init(number: 2.2, currency: "HOOL"),
                        cost: .init(number: 532.43, currency: "USD", date: .distantPast)),
                    .init(
                        units: .init(number: 2.3, currency: "HOOL"),
                        cost: .init(number: 564.00, currency: "USD", date: .distantFuture)),
                ]),
            ])
    }

    func testAddOp() {
        let inv1 = Inventory(positions: [.init(units: .init(number: 17.00, currency: "USD"))])
        let origInv1 = Inventory(positions: [.init(units: .init(number: 17.00, currency: "USD"))])
        let inv2 = Inventory(positions: [.init(units: .init(number: 21.00, currency: "CAD"))])
        let inv3 = inv1 + inv2
        XCTAssertEqual(
            inv3,
            Inventory(positions: [
                .init(units: .init(number: 17.00, currency: "USD")),
                .init(units: .init(number: 21.00, currency: "CAD")),
            ]))
        XCTAssertEqual(inv1, origInv1)
    }
}
