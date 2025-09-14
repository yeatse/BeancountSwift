//
//  InventoryTests.swift
//
//
//  Created by Yeatse on 2024/1/5.
//

import Testing
import Foundation

@testable import BeancountSwift

struct InventoryTests {
    @Test func fromString() {
        var inv: Inventory = "10 USD"
        #expect(
            inv ==
            Inventory(positions: [
                Position(units: Amount(number: 10, currency: "USD"))
            ]))

        inv = "   10.00   USD "
        #expect(
            inv ==
            Inventory(positions: [
                Position(units: Amount(number: 10, currency: "USD"))
            ]))

        inv = "1 USD, 2 CAD"
        #expect(
            inv ==
            Inventory(positions: [
                Position(units: Amount(number: 1, currency: "USD")),
                Position(units: Amount(number: 2, currency: "CAD")),
            ]))

        inv = "2.2 HOOL {532.43 USD}, 3.413 EUR"
        #expect(
            inv ==
            Inventory(positions: [
                Position(
                    units: Amount(number: Decimal(string: "2.2")!, currency: "HOOL"),
                    cost: Cost(
                        number: Decimal(string: "532.43")!, currency: "USD", date: .distantPast)),
                Position(units: Amount(number: Decimal(string: "3.413")!, currency: "EUR")),
            ]))

        inv = "1.1 HOOL {500.00 # 11.00 USD}, 100 CAD"
        #expect(
            inv ==
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
        #expect(amount == invAmount)
    }

    @Test func ctorEmptyLen() {
        var inv = Inventory()
        #expect(inv.isEmpty)
        #expect(inv.positions.count == 0)

        inv = Inventory(positions: ["100.00 USD", "101.00 USD"])
        #expect(!inv.isEmpty)
        #expect(inv.positions.count == 1)

        inv = Inventory(positions: ["100.00 USD", "100.00 CAD"])
        #expect(!inv.isEmpty)
        #expect(inv.positions.count == 2)

        inv = Inventory()
        #expect(inv.positions.count == 0)
        inv.addAmount("100 USD")
        #expect(inv.positions.count == 1)
        inv.addAmount("100 CAD")
        #expect(inv.positions.count == 2)
    }

    @Test func copy() {
        var inv = Inventory()
        inv.addAmount("100.00 USD")
        checkAmount(inventory: inv, number: 100, currency: "USD")

        var inv2 = inv
        inv2.addAmount("50.00 USD")
        checkAmount(inventory: inv2, number: 150, currency: "USD")

        // make sure the original object is not modified
        checkAmount(inventory: inv, number: 100, currency: "USD")
    }

    @Test func equalOp() {
        let inv1: Inventory = "100 USD, 100 CAD"
        let inv2: Inventory = "100 CAD, 100 USD"
        #expect(inv1 == inv2)
        #expect(inv2 == inv1)

        let inv3: Inventory = "200 USD, 100 CAD"
        #expect(inv1 != inv3)
        #expect(inv3 != inv1)

        let inv4: Inventory = "100 USD, 100 JPY"
        #expect(inv1 != inv4)
        #expect(inv4 != inv1)

        let inv5: Inventory = "100 JPY, 100 USD"
        #expect(inv4 == inv5)
    }

    @Test func ltOp() {
        let inv1: Inventory = "100 USD, 100 CAD"
        let inv2: Inventory = "100 CAD, 100 USD"
        #expect(inv1 < inv2)
        #expect(inv2 > inv1)

        let inv3: Inventory = "200 USD, 100 CAD"
        #expect(inv1 < inv2)
        #expect(inv2 < inv3)
        #expect(inv3 > inv1)

        let inv4: Inventory = "100 USD, 100 JPY"
        #expect(inv1 > inv4)

        let inv5: Inventory = "100 JPY, 100 USD"
        #expect(inv1 > inv5)
        #expect(inv4 > inv5)
    }

    @Test func isSmallValue() {
        let testInv: Inventory = "1.50 JPY, 1.51 USD, 1.52 CAD"
        for inv in [testInv, -testInv] {
            #expect(!inv.isSmall(tolerance: 1.49))
            #expect(!inv.isSmall(tolerance: 1.50))
            #expect(inv.isSmall(tolerance: 1.53))
            #expect(inv.isSmall(tolerance: 1.52))
        }
    }

    @Test func isSmallDict() {
        let testInv: Inventory = "0.03 JPY, 0.003 USD"
        for inv in [testInv, -testInv] {
            #expect(inv.isSmall(tolerances: ["JPY": 0.05, "USD": 0.005]))
            #expect(!inv.isSmall(tolerances: ["JPY": 0.005, "USD": 0.0005]))
            #expect(inv.isSmall(tolerances: ["JPY": 0.05, "USD": 0.05]))
            #expect(!inv.isSmall(tolerances: ["JPY": 0.005, "USD": 0.005]))

            #expect(inv.isSmall(tolerances: ["JPY": 0.03, "USD": 0.003]))
            #expect(!inv.isSmall(tolerances: ["JPY": 0.02999999999999, "USD": 0.003]))
            #expect(!inv.isSmall(tolerances: ["JPY": 0.03, "USD": 0.00299999]))

            #expect(!inv.isSmall(tolerances: ["JPY": 0.05]))
            #expect(!inv.isSmall(tolerances: ["USD": 0.005]))

            #expect(inv.isSmall(tolerances: ["JPY": 0.05, "USD": 0.005, "CAD": 0.0005]))

            #expect(!inv.isSmall(tolerances: [:]))
        }
    }

    @Test func isSmallWithDefault() {
        let inv: Inventory = "0.03 JPY"
        #expect(inv.isSmall(tolerances: ["JPY": 0.05]))
        #expect(!inv.isSmall(tolerances: ["JPY": 0.02]))
    }

    @Test func isMixed() {
        var inv: Inventory = "100 HOOL {250 USD}, 101 HOOL {251 USD}"
        #expect(!inv.isMixed())

        inv = "100 HOOL {250 USD}, -1 HOOL {251 USD}"
        #expect(inv.isMixed())

        inv = "-2 HOOL {250 USD}, -1 HOOL {251 USD}"
        #expect(!inv.isMixed())
    }

    @Test func isReducedBy() {
        var inv: Inventory = "100 HOOL {250 USD}, 101 HOOL {251 USD}"
        #expect(!inv.isReducedBy("2 HOOL"))
        #expect(!inv.isReducedBy("0 HOOL"))
        #expect(inv.isReducedBy("-2 HOOL"))

        inv = "100 HOOL {250 USD}, -101 HOOL {251 USD}"
        #expect(inv.isReducedBy("2 HOOL"))
        #expect(!inv.isReducedBy("0 HOOL"))
        #expect(inv.isReducedBy("-2 HOOL"))
    }

    @Test func negOp() {
        var inv = Inventory()
        inv.addAmount("10 USD")
        checkAmount(inventory: -inv, number: -10, currency: "USD")

        let pinv: Inventory = "1.50 JPY, 1.51 USD, 1.52 CAD"
        let ninv: Inventory = "-1.50 JPY, -1.51 USD, -1.52 CAD"
        #expect(-pinv == ninv)
    }

    @Test func absOp() {
        let inv: Inventory = "1.50 USD, 2.00 USD, -1.52 CAD"
        #expect(inv.absolute == "3.50 USD, 1.52 CAD")
    }

    @Test func mulOp() {
        let inv: Inventory = "10 HOOL {1.11 USD}, 2.22 CAD"
        let inv2 = inv * 3
        #expect(inv2 == "30 HOOL {1.11 USD}, 6.66 CAD")
    }

    @Test func getOnlyPosition() {
        let inv: Inventory = "10 HOOL {1.11 USD}"
        #expect(inv.onlyPosition?.units == "10 HOOL")
        #expect(Inventory().onlyPosition == nil)
    }

    @Test func getCurrencyUnits() {
        let inv: Inventory = "40.50 JPY, 40.51 USD {1.01 CAD}, 40.52 CAD"
        #expect(inv.getCurrencyUnits(in: "JPY") == "40.50 JPY")
        #expect(inv.getCurrencyUnits(in: "USD") == "40.51 USD")
        #expect(inv.getCurrencyUnits(in: "CAD") == "40.52 CAD")
        #expect(inv.getCurrencyUnits(in: "AUD") == "0 AUD")
        #expect(inv.getCurrencyUnits(in: "NZD") == "0 NZD")
    }

    @Test func segregateUnits() {
        let inv: Inventory =
            "2.2 HOOL {532.43 USD}, 2.3 HOOL {564.00 USD, 2015-07-14}, 3.41 CAD, 101.20 USD"
        let ccymap = inv.segregateUnits(by: ["HOOL", "USD", "EUR"])
        #expect(
            ccymap ==
            [
                nil: "3.41 CAD",
                "USD": "101.20 USD",
                "EUR": Inventory(),
                "HOOL": "2.2 HOOL {532.43 USD}, 2.3 HOOL {564.00 USD, 2015-07-14}",
            ])
    }

    @Test func split() {
        let inv: Inventory =
            "2.2 HOOL {532.43 USD}, 2.3 HOOL {564.00 USD, 2015-07-14}, 3.41 CAD, 101.20 USD"
        let ccymap = inv.split()
        #expect(
            ccymap ==
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

    @Test func units() {
        var inv = Inventory()
        #expect(inv.reduce(by: \.units) == "")

        inv = "40.50 JPY, 40.51 USD {1.01 CAD}, 40.52 CAD"
        #expect(inv.reduce(by: \.units) == "40.50 JPY, 40.51 USD, 40.52 CAD")

        inv = "2 HOOL {400 USD}, 3 HOOL {410 USD}"
        #expect(inv.reduce(by: \.units) == "5 HOOL")

        inv = "2 HOOL {400 USD}, -3 HOOL {410 USD}"
        #expect(inv.reduce(by: \.units) == "-1 HOOL")

        inv = Inventory(positions: allKindsOfPositions + ["50.00 CAD"])
        #expect(inv.reduce(by: \.units) == "121.50 USD, 50.00 CAD")
    }

    @Test func cost() {
        let inv = Inventory(positions: allKindsOfPositions + ["50.00 CAD"])
        #expect(inv.reduce(by: \.totalCost) == "40.50 USD, 139.10 CAD")
    }

    @Test func average() {
        var inv: Inventory = "40.50 JPY, 40.51 USD {1.01 CAD}, 40.52 CAD"
        #expect(inv.average == inv)

        inv = "40 USD {1.01 CAD}, 40 USD"
        #expect(inv.average == inv)

        inv = "40 USD {1.01 CAD}, 40 USD {1.02 CAD}"
        #expect(inv.average == "80.00 USD {1.015 CAD}")

        inv = "2 HOOL {500 USD}, 3 HOOL {520 USD}, 4 HOOL {530 USD}"
        #expect(inv.average == "9 HOOL {520 USD}")

        inv = "2 HOOL {500 USD}"
        inv.addAmount("-2 HOOL", cost: Cost(number: 500, currency: "USD", date: .distantPast))
        #expect(inv.average == "")

        inv = "2 HOOL {500 USD}"
        inv.addAmount("-2 HOOL", cost: Cost(number: 500, currency: "USD", date: .now))
        #expect(inv.average == "")
    }

    @Test func currencies() {
        var inv = Inventory()
        #expect(Set(inv.currencies) == [])

        inv = "40 USD {1.01 CAD}, 40 USD"
        #expect(Set(inv.currencies) == ["USD"])

        inv = "40 AAPL {1.01 USD}, 10 HOOL {2.02 USD}"
        #expect(Set(inv.currencies) == ["AAPL", "HOOL"])
    }

    @Test func currencyPairs() throws {
        var inv = Inventory()
        #expect(inv.currencyPairs.isEmpty)

        inv = "40 USD {1.01 CAD}, 40 USD"
        var pairs: [Position.CurrencyPair] = [["USD", "CAD"], ["USD", nil]]
        for pair in inv.currencyPairs {
            let index = try #require(pairs.firstIndex(of: pair))
            pairs.remove(at: index)
        }
        #expect(pairs.isEmpty)

        inv = "40 AAPL {1.01 USD}, 10 HOOL {2.02 USD}"
        pairs = [["AAPL", "USD"], ["HOOL", "USD"]]
        for pair in inv.currencyPairs {
            let index = try #require(pairs.firstIndex(of: pair))
            pairs.remove(at: index)
        }
    }

    @Test func addAmount() {
        var inv = Inventory()
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

    @Test func addAmountZero() {
        var inv = Inventory()
        inv.addAmount("0 USD")
        #expect(inv.positions.count == 0)
    }

    @Test func addAmountBooking() {
        var inv = Inventory()
        var (_, booking) = inv.addAmount("100.00 USD")
        #expect(booking == .created)

        (_, booking) = inv.addAmount("20.00 USD")
        #expect(booking == .augmented)

        (_, booking) = inv.addAmount("-20 USD")
        #expect(booking == .reduced)

        (_, booking) = inv.addAmount("-100 USD")
        #expect(booking == .reduced)
    }

    @Test func addAmountMultiCurrency() {
        var inv = Inventory()
        inv.addAmount("100 USD")
        inv.addAmount("100 CAD")
        checkAmount(inventory: inv, number: 100, currency: "USD")
        checkAmount(inventory: inv, number: 100, currency: "CAD")

        inv.addAmount("25 USD")
        checkAmount(inventory: inv, number: 125, currency: "USD")
        checkAmount(inventory: inv, number: 100, currency: "CAD")
    }

    @Test func addAmountWithLots() {
        var inv = Inventory()
        inv.addAmount("50 HOOL", cost: .init(number: 700, currency: "USD", date: .distantPast))
        checkAmount(inventory: inv, number: 50, currency: "HOOL")

        inv.addAmount("-40 HOOL", cost: .init(number: 700, currency: "USD", date: .distantPast))
        checkAmount(inventory: inv, number: 10, currency: "HOOL")

        inv.addAmount("-12 HOOL", cost: .init(number: 700, currency: "USD", date: .distantPast))
        #expect(inv.positions.first!.isNegativeAtCost)

        inv = Inventory()
        let now = Date.now
        inv.addAmount("50 HOOL", cost: .init(number: 700, currency: "USD", date: now))
        checkAmount(inventory: inv, number: 50, currency: "HOOL")

        inv.addAmount("-40 HOOL", cost: .init(number: 700, currency: "USD", date: now))
        checkAmount(inventory: inv, number: 10, currency: "HOOL")

        inv.addAmount("-12 HOOL", cost: .init(number: 700, currency: "USD", date: now))
        #expect(inv.positions.first!.isNegativeAtCost)
    }

    @Test func addAmountAllowNegative() {
        var inv = Inventory()
        var (position, _) = inv.addAmount("-11 USD")
        #expect(position == nil)

        (position, _) = inv.addAmount(
            "-11 USD", cost: .init(number: "1.10", currency: "CAD", date: .distantPast))
        #expect(position == nil)

        (position, _) = inv.addAmount(
            "-11 USD", cost: .init(number: "1.10", currency: "CAD", date: "2012-01-01"))
        #expect(position == nil)

        let invlist = Array(inv.positions)
        #expect(invlist[1].isNegativeAtCost)
        #expect(invlist[2].isNegativeAtCost)
        inv.addAmount("-11 USD", cost: .init(number: "1.10", currency: "CAD", date: .distantPast))
        inv.addAmount("-11 USD", cost: .init(number: "1.10", currency: "CAD", date: "2012-01-01"))
        #expect(inv.positions.count == 3)

        inv = "10 USD, 10 USD {1.10 CAD}, 10 USD {1.10 CAD, 2012-01-01}"
        (position, _) = inv.addAmount("-11 USD")
        #expect(position == "10 USD")
        (position, _) = inv.addAmount(
            "-11 USD", cost: .init(number: "1.10", currency: "CAD", date: .distantPast))
        #expect(position == "10 USD {1.10 CAD}")
        (position, _) = inv.addAmount(
            "-11 USD", cost: .init(number: "1.10", currency: "CAD", date: "2012-01-01"))
    }

    @Test func addPosition() {
        var inv = Inventory()
        for position in allKindsOfPositions {
            inv.addPosition(position)
        }
        #expect(Inventory(positions: allKindsOfPositions) == inv)
    }

    @Test func addOp() {
        let inv1: Inventory = "17.00 USD"
        let origInv1: Inventory = "17.00 USD"
        let inv2: Inventory = "21.00 CAD"
        let inv3 = inv1 + inv2
        #expect(inv3 == "17.00 USD, 21.00 CAD")
        #expect(inv1 == origInv1)
    }

    @Test func update() {
        var inv1: Inventory = "11 USD"
        inv1.addInventory("12 CAD")
        #expect(inv1 == "11 USD, 12 CAD")
    }

    @Test func sumInventories() {
        var inv1 = Inventory()
        inv1.addAmount("10 USD")

        var inv2 = Inventory()
        inv2.addAmount("20 CAD")
        inv2.addAmount("55 HOOL")

        #expect(inv1 + inv2 == "10 USD, 20 CAD, 55 HOOL")
    }

    @Test func reduce() {
        let inv: Inventory = "100.00 USD, 101.00 CAD, 100 HOOL {300.00 USD}"
        let units = inv.reduce(by: \.units)
        #expect(units == "100.00 USD, 101.00 CAD, 100 HOOL")
    }
}
