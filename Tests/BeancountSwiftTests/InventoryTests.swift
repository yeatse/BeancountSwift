//
//  InventoryTests.swift
//
//
//  Created by Yeatse on 2024/1/5.
//

import XCTest

@testable import BeancountSwift

final class InventoryTests: XCTestCase {
    func testFromString() {
        var inv: Inventory = "10 USD"
        XCTAssertEqual(
            inv,
            Inventory(positions: [
                Position(units: Amount(number: 10, currency: "USD"))
            ]))

        inv = "   10.00   USD "
        XCTAssertEqual(
            inv,
            Inventory(positions: [
                Position(units: Amount(number: 10, currency: "USD"))
            ]))

        inv = "1 USD, 2 CAD"
        XCTAssertEqual(
            inv,
            Inventory(positions: [
                Position(units: Amount(number: 1, currency: "USD")),
                Position(units: Amount(number: 2, currency: "CAD")),
            ]))

        inv = "2.2 HOOL {532.43 USD}, 3.413 EUR"
        XCTAssertEqual(
            inv,
            Inventory(positions: [
                Position(
                    units: Amount(number: Decimal(string: "2.2")!, currency: "HOOL"),
                    cost: Cost(
                        number: Decimal(string: "532.43")!, currency: "USD", date: .distantPast)),
                Position(units: Amount(number: Decimal(string: "3.413")!, currency: "EUR")),
            ]))

        inv = "1.1 HOOL {500.00 # 11.00 USD}, 100 CAD"
        XCTAssertEqual(
            inv,
            Inventory(positions: [
                Position(
                    units: Amount(number: Decimal(string: "1.1")!, currency: "HOOL"),
                    cost: Cost(number: 510, currency: "USD", date: .distantPast)),
                Position(units: Amount(number: 100, currency: "CAD")),
            ]))
    }

    func checkAmount(inventory: Inventory, number: Decimal, currency: Currency) {
        let amount = Amount(number: number, currency: currency)
        let invAmount = inventory.getCurrencyUnits(in: currency)
        XCTAssertEqual(amount, invAmount)
    }

    func testCtorEmptyLen() {
        var inv = Inventory()
        XCTAssertTrue(inv.isEmpty)
        XCTAssertEqual(inv.positions.count, 0)

        inv = Inventory(positions: ["100.00 USD", "101.00 USD"])
        XCTAssertFalse(inv.isEmpty)
        XCTAssertEqual(inv.positions.count, 1)

        inv = Inventory(positions: ["100.00 USD", "100.00 CAD"])
        XCTAssertFalse(inv.isEmpty)
        XCTAssertEqual(inv.positions.count, 2)

        inv = Inventory()
        XCTAssertEqual(inv.positions.count, 0)
        inv.addAmount("100 USD")
        XCTAssertEqual(inv.positions.count, 1)
        inv.addAmount("100 CAD")
        XCTAssertEqual(inv.positions.count, 2)
    }

    func testCopy() {
        let inv = Inventory()
        inv.addAmount("100.00 USD")
        checkAmount(inventory: inv, number: 100, currency: "USD")

        let inv2 = inv.copy() as! Inventory
        inv2.addAmount("50.00 USD")
        checkAmount(inventory: inv2, number: 150, currency: "USD")

        // make sure the original object is not modified
        checkAmount(inventory: inv, number: 100, currency: "USD")
    }

    func testEqualOp() {
        let inv1: Inventory = "100 USD, 100 CAD"
        let inv2: Inventory = "100 CAD, 100 USD"
        XCTAssertEqual(inv1, inv2)
        XCTAssertEqual(inv2, inv1)

        let inv3: Inventory = "200 USD, 100 CAD"
        XCTAssertNotEqual(inv1, inv3)
        XCTAssertNotEqual(inv3, inv1)

        let inv4: Inventory = "100 USD, 100 JPY"
        XCTAssertNotEqual(inv1, inv4)
        XCTAssertNotEqual(inv4, inv1)

        let inv5: Inventory = "100 JPY, 100 USD"
        XCTAssertEqual(inv4, inv5)
    }

    func testLtOp() {
        let inv1: Inventory = "100 USD, 100 CAD"
        let inv2: Inventory = "100 CAD, 100 USD"
        XCTAssertLessThan(inv1, inv2)
        XCTAssertGreaterThan(inv2, inv1)

        let inv3: Inventory = "200 USD, 100 CAD"
        XCTAssertLessThan(inv1, inv2)
        XCTAssertLessThan(inv2, inv3)
        XCTAssertGreaterThan(inv3, inv1)

        let inv4: Inventory = "100 USD, 100 JPY"
        XCTAssertGreaterThan(inv1, inv4)

        let inv5: Inventory = "100 JPY, 100 USD"
        XCTAssertGreaterThan(inv1, inv5)
        XCTAssertGreaterThan(inv4, inv5)
    }

    func testIsSmallValue() {
        let testInv: Inventory = "1.50 JPY, 1.51 USD, 1.52 CAD"
        for inv in [testInv, -testInv] {
            XCTAssertFalse(inv.isSmall(tolerance: 1.49))
            XCTAssertFalse(inv.isSmall(tolerance: 1.50))
            XCTAssertTrue(inv.isSmall(tolerance: 1.53))
            XCTAssertTrue(inv.isSmall(tolerance: 1.52))
        }
    }

    func testIsSmallDict() {
        let testInv: Inventory = "0.03 JPY, 0.003 USD"
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
        let inv: Inventory = "0.03 JPY"
        XCTAssertTrue(inv.isSmall(tolerances: ["JPY": 0.05]))
        XCTAssertFalse(inv.isSmall(tolerances: ["JPY": 0.02]))
    }

    func testIsMixed() {
        var inv: Inventory = "100 HOOL {250 USD}, 101 HOOL {251 USD}"
        XCTAssertFalse(inv.isMixed())

        inv = "100 HOOL {250 USD}, -1 HOOL {251 USD}"
        XCTAssertTrue(inv.isMixed())

        inv = "-2 HOOL {250 USD}, -1 HOOL {251 USD}"
        XCTAssertFalse(inv.isMixed())
    }

    func testIsReducedBy() {
        var inv: Inventory = "100 HOOL {250 USD}, 101 HOOL {251 USD}"
        XCTAssertFalse(inv.isReducedBy("2 HOOL"))
        XCTAssertFalse(inv.isReducedBy("0 HOOL"))
        XCTAssertTrue(inv.isReducedBy("-2 HOOL"))

        inv = "100 HOOL {250 USD}, -101 HOOL {251 USD}"
        XCTAssertTrue(inv.isReducedBy("2 HOOL"))
        XCTAssertFalse(inv.isReducedBy("0 HOOL"))
        XCTAssertTrue(inv.isReducedBy("-2 HOOL"))
    }

    func testNegOp() {
        let inv = Inventory()
        inv.addAmount("10 USD")
        checkAmount(inventory: -inv, number: -10, currency: "USD")

        let pinv: Inventory = "1.50 JPY, 1.51 USD, 1.52 CAD"
        let ninv: Inventory = "-1.50 JPY, -1.51 USD, -1.52 CAD"
        XCTAssertEqual(-pinv, ninv)
    }

    func testAbsOp() {
        let inv: Inventory = "1.50 USD, 2.00 USD, -1.52 CAD"
        XCTAssertEqual(inv.absolute, "3.50 USD, 1.52 CAD")
    }

    func testMulOp() {
        let inv: Inventory = "10 HOOL {1.11 USD}, 2.22 CAD"
        let inv2 = inv * 3
        XCTAssertEqual(inv2, "30 HOOL {1.11 USD}, 6.66 CAD")
    }

    func testGetOnlyPosition() {
        let inv: Inventory = "10 HOOL {1.11 USD}"
        XCTAssertEqual(inv.onlyPosition?.units, "10 HOOL")
        XCTAssertNil(Inventory().onlyPosition)
    }

    func testGetCurrencyUnits() {
        let inv: Inventory = "40.50 JPY, 40.51 USD {1.01 CAD}, 40.52 CAD"
        XCTAssertEqual(inv.getCurrencyUnits(in: "JPY"), "40.50 JPY")
        XCTAssertEqual(inv.getCurrencyUnits(in: "USD"), "40.51 USD")
        XCTAssertEqual(inv.getCurrencyUnits(in: "CAD"), "40.52 CAD")
        XCTAssertEqual(inv.getCurrencyUnits(in: "AUD"), "0 AUD")
        XCTAssertEqual(inv.getCurrencyUnits(in: "NZD"), "0 NZD")
    }

    func testSegregateUnits() {
        let inv: Inventory =
            "2.2 HOOL {532.43 USD}, 2.3 HOOL {564.00 USD, 2015-07-14}, 3.41 CAD, 101.20 USD"
        let ccymap = inv.segregateUnits(by: ["HOOL", "USD", "EUR"])
        XCTAssertEqual(
            ccymap,
            [
                nil: "3.41 CAD",
                "USD": "101.20 USD",
                "EUR": Inventory(),
                "HOOL": "2.2 HOOL {532.43 USD}, 2.3 HOOL {564.00 USD, 2015-07-14}",
            ])
    }

    func testSplit() {
        let inv: Inventory =
            "2.2 HOOL {532.43 USD}, 2.3 HOOL {564.00 USD, 2015-07-14}, 3.41 CAD, 101.20 USD"
        let ccymap = inv.split()
        XCTAssertEqual(
            ccymap,
            [
                "CAD": "3.41 CAD",
                "USD": "101.20 USD",
                "HOOL": "2.2 HOOL {532.43 USD}, 2.3 HOOL {564.00 USD, 2015-07-14}",
            ])
    }

    let allKindsOfPositions: [Position] = [
        "40.50 USD",
        "40.50 USD {1.10 CAD}",
        "40.50 USD {1.10 CAD, 2012-01-01}",
    ]

    func testUnits() {
        var inv = Inventory()
        XCTAssertEqual(inv.reduce(by: \.units), "")

        inv = "40.50 JPY, 40.51 USD {1.01 CAD}, 40.52 CAD"
        XCTAssertEqual(inv.reduce(by: \.units), "40.50 JPY, 40.51 USD, 40.52 CAD")

        inv = "2 HOOL {400 USD}, 3 HOOL {410 USD}"
        XCTAssertEqual(inv.reduce(by: \.units), "5 HOOL")

        inv = "2 HOOL {400 USD}, -3 HOOL {410 USD}"
        XCTAssertEqual(inv.reduce(by: \.units), "-1 HOOL")

        inv = Inventory(positions: allKindsOfPositions + ["50.00 CAD"])
        XCTAssertEqual(inv.reduce(by: \.units), "121.50 USD, 50.00 CAD")
    }

    func testCost() {
        let inv = Inventory(positions: allKindsOfPositions + ["50.00 CAD"])
        XCTAssertEqual(inv.reduce(by: \.totalCost), "40.50 USD, 139.10 CAD")
    }

    func testAverage() {
        var inv: Inventory = "40.50 JPY, 40.51 USD {1.01 CAD}, 40.52 CAD"
        XCTAssertEqual(inv.average, inv)

        inv = "40 USD {1.01 CAD}, 40 USD"
        XCTAssertEqual(inv.average, inv)

        inv = "40 USD {1.01 CAD}, 40 USD {1.02 CAD}"
        XCTAssertEqual(inv.average, "80.00 USD {1.015 CAD}")

        inv = "2 HOOL {500 USD}, 3 HOOL {520 USD}, 4 HOOL {530 USD}"
        XCTAssertEqual(inv.average, "9 HOOL {520 USD}")

        inv = "2 HOOL {500 USD}"
        inv.addAmount("-2 HOOL", cost: Cost(number: 500, currency: "USD", date: .distantPast))
        XCTAssertEqual(inv.average, "")

        inv = "2 HOOL {500 USD}"
        inv.addAmount("-2 HOOL", cost: Cost(number: 500, currency: "USD", date: .now))
        XCTAssertEqual(inv.average, "")
    }

    func testCurrencies() {
        var inv = Inventory()
        XCTAssertEqual(Set(inv.currencies), [])

        inv = "40 USD {1.01 CAD}, 40 USD"
        XCTAssertEqual(Set(inv.currencies), ["USD"])

        inv = "40 AAPL {1.01 USD}, 10 HOOL {2.02 USD}"
        XCTAssertEqual(Set(inv.currencies), ["AAPL", "HOOL"])
    }

    func testCurrencyPairs() {
        var inv = Inventory()
        XCTAssertTrue(inv.currencyPairs.isEmpty)

        inv = "40 USD {1.01 CAD}, 40 USD"
        var pairs: [(Currency, Currency?)] = [("USD", "CAD"), ("USD", nil)]
        for pair in inv.currencyPairs {
            guard
                let index = pairs.firstIndex(where: { (a, b) in
                    pair.0 == a && pair.1 == b
                })
            else {
                return XCTFail()
            }
            pairs.remove(at: index)
        }
        XCTAssert(pairs.isEmpty)

        inv = "40 AAPL {1.01 USD}, 10 HOOL {2.02 USD}"
        pairs = [("AAPL", "USD"), ("HOOL", "USD")]
        for pair in inv.currencyPairs {
            guard
                let index = pairs.firstIndex(where: { (a, b) in
                    pair.0 == a && pair.1 == b
                })
            else {
                return XCTFail()
            }
            pairs.remove(at: index)
        }
    }

    func testAddAmount() {
        let inv = Inventory()
        inv.addAmount("100.00 USD")
        checkAmount(inventory: inv, number: 100, currency: "USD")

        inv.addAmount("25.01 USD")
        checkAmount(inventory: inv, number: "125.01", currency: "USD")

        inv.addAmount("-12.73 USD")
        checkAmount(inventory: inv, number: "112.28", currency: "USD")

        inv.addAmount("-120 USD")
        checkAmount(inventory: inv, number: "-7.72", currency: "USD")

        inv.addAmount("-1 USD")
        checkAmount(inventory: inv, number: "-8.72", currency: "USD")

        inv.addAmount("18.72 USD")
        checkAmount(inventory: inv, number: 10, currency: "USD")
    }

    func testAddAmountZero() {
        let inv = Inventory()
        inv.addAmount("0 USD")
        XCTAssertEqual(inv.positions.count, 0)
    }

    func testAddAmountBooking() {
        let inv = Inventory()
        var (_, booking) = inv.addAmount("100.00 USD")
        XCTAssertEqual(booking, .created)

        (_, booking) = inv.addAmount("20.00 USD")
        XCTAssertEqual(booking, .augmented)

        (_, booking) = inv.addAmount("-20 USD")
        XCTAssertEqual(booking, .reduced)

        (_, booking) = inv.addAmount("-100 USD")
        XCTAssertEqual(booking, .reduced)
    }

    func testAddAmountMultiCurrency() {
        let inv = Inventory()
        inv.addAmount("100 USD")
        inv.addAmount("100 CAD")
        checkAmount(inventory: inv, number: 100, currency: "USD")
        checkAmount(inventory: inv, number: 100, currency: "CAD")

        inv.addAmount("25 USD")
        checkAmount(inventory: inv, number: 125, currency: "USD")
        checkAmount(inventory: inv, number: 100, currency: "CAD")
    }

    func testAddAmountWithLots() {
        var inv = Inventory()
        inv.addAmount("50 HOOL", cost: .init(number: 700, currency: "USD", date: .distantPast))
        checkAmount(inventory: inv, number: 50, currency: "HOOL")

        inv.addAmount("-40 HOOL", cost: .init(number: 700, currency: "USD", date: .distantPast))
        checkAmount(inventory: inv, number: 10, currency: "HOOL")

        inv.addAmount("-12 HOOL", cost: .init(number: 700, currency: "USD", date: .distantPast))
        XCTAssertTrue(inv.positions.first!.isNegativeAtCost)

        inv = Inventory()
        let now = Date.now
        inv.addAmount("50 HOOL", cost: .init(number: 700, currency: "USD", date: now))
        checkAmount(inventory: inv, number: 50, currency: "HOOL")

        inv.addAmount("-40 HOOL", cost: .init(number: 700, currency: "USD", date: now))
        checkAmount(inventory: inv, number: 10, currency: "HOOL")

        inv.addAmount("-12 HOOL", cost: .init(number: 700, currency: "USD", date: now))
        XCTAssertTrue(inv.positions.first!.isNegativeAtCost)
    }

    func testAddAmountAllowNegative() {
        var inv = Inventory()
        var (position, _) = inv.addAmount("-11 USD")
        XCTAssertNil(position)

        (position, _) = inv.addAmount(
            "-11 USD", cost: .init(number: "1.10", currency: "CAD", date: .distantPast))
        XCTAssertNil(position)

        (position, _) = inv.addAmount(
            "-11 USD", cost: .init(number: "1.10", currency: "CAD", date: "2012-01-01"))
        XCTAssertNil(position)

        let invlist = Array(inv.positions)
        XCTAssertTrue(invlist[1].isNegativeAtCost)
        XCTAssertTrue(invlist[2].isNegativeAtCost)
        inv.addAmount("-11 USD", cost: .init(number: "1.10", currency: "CAD", date: .distantPast))
        inv.addAmount("-11 USD", cost: .init(number: "1.10", currency: "CAD", date: "2012-01-01"))
        XCTAssertEqual(inv.positions.count, 3)

        inv = "10 USD, 10 USD {1.10 CAD}, 10 USD {1.10 CAD, 2012-01-01}"
        (position, _) = inv.addAmount("-11 USD")
        XCTAssertEqual(position, "10 USD")
        (position, _) = inv.addAmount(
            "-11 USD", cost: .init(number: "1.10", currency: "CAD", date: .distantPast))
        XCTAssertEqual(position, "10 USD {1.10 CAD}")
        (position, _) = inv.addAmount(
            "-11 USD", cost: .init(number: "1.10", currency: "CAD", date: "2012-01-01"))
    }

    func testAddPosition() {
        let inv = Inventory()
        for position in allKindsOfPositions {
            inv.addPosition(position)
        }
        XCTAssertEqual(Inventory(positions: allKindsOfPositions), inv)
    }

    func testAddOp() {
        let inv1: Inventory = "17.00 USD"
        let origInv1: Inventory = "17.00 USD"
        let inv2: Inventory = "21.00 CAD"
        let inv3 = inv1 + inv2
        XCTAssertEqual(inv3, "17.00 USD, 21.00 CAD")
        XCTAssertEqual(inv1, origInv1)
    }

    func testUpdate() {
        let inv1: Inventory = "11 USD"
        inv1.addInventory("12 CAD")
        XCTAssertEqual(inv1, "11 USD, 12 CAD")
    }

    func testSumInventories() {
        let inv1 = Inventory()
        inv1.addAmount("10 USD")

        let inv2 = Inventory()
        inv2.addAmount("20 CAD")
        inv2.addAmount("55 HOOL")

        XCTAssertEqual(inv1 + inv2, "10 USD, 20 CAD, 55 HOOL")
    }

    func testReduce() {
        let inv: Inventory = "100.00 USD, 101.00 CAD, 100 HOOL {300.00 USD}"
        let units = inv.reduce(by: \.units)
        XCTAssertEqual(units, "100.00 USD, 101.00 CAD, 100 HOOL")
    }
}
