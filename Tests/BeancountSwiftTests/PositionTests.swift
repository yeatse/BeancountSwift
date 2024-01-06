//
//  PositionTests.swift
//
//
//  Created by Yeatse on 2024/1/7.
//

import XCTest

@testable import BeancountSwift

final class PositionTests: XCTestCase {
    func testCompareZeroToNone() {
        let pos1 = Position(units: Amount(number: .zero, currency: "CAD"))
        let pos2 = Position(units: Amount(number: .zero, currency: "USD"))
        XCTAssertNotEqual(pos1, pos2)
    }

    func testNeg() {
        let pos = Position(units: "7 CAD")
        let npos = -pos
        XCTAssertEqual(npos.units.number, -7)
        XCTAssertEqual(npos.units.currency, "CAD")
        XCTAssertEqual(pos.cost, npos.cost)
    }

    func testAbs() {
        var pos = Position(units: "7 CAD")
        XCTAssertEqual(pos.absolute.units.number, 7)
        pos = Position(units: "-7 CAD")
        XCTAssertEqual(pos.absolute.units.number, 7)
    }

    func testMul() {
        let pos: Position = "2 HOOL {100.00 USD}"
        let pos2 = pos * 3
        XCTAssertEqual(pos2, "6 HOOL {100.00 USD}")
    }

    func testEqAndSortKey() {
        let pos1 = Position(units: "200 USD")
        let pos2 = Position(units: "201 USD")
        let pos3 = Position(units: "100 CAD")
        let pos4 = Position(units: "101 CAD")
        let pos5 = Position(units: "50 ZZZ")
        let positions = [pos5, pos4, pos3, pos2, pos1].sorted()

        XCTAssertLessThan(pos1, pos2)
        XCTAssertLessThan(pos2, pos3)
        XCTAssertLessThan(pos3, pos4)
        XCTAssertLessThan(pos4, pos5)

        XCTAssertEqual(positions[0], pos1)
        XCTAssertEqual(positions[1], pos2)
        XCTAssertEqual(positions[2], pos3)
        XCTAssertEqual(positions[3], pos4)
        XCTAssertEqual(positions[4], pos5)
    }

    func testEqAndSortKeyByCost() {
        let pos1 = Position(units: "1 USD")
        let pos2 = Position(
            units: "1 USD", cost: Cost(number: 10, currency: "USD", date: .distantPast))
        let pos3 = Position(
            units: "1 USD", cost: Cost(number: 11, currency: "USD", date: .distantPast))
        let pos4 = Position(
            units: "1 USD", cost: Cost(number: 12, currency: "USD", date: .distantPast))

        var positions = [pos3, pos2, pos1, pos4]
        XCTAssertEqual([pos1, pos2, pos3, pos4], positions.sorted())

        for _ in 0..<64 {
            positions.shuffle()
            XCTAssertEqual([pos1, pos2, pos3, pos4], positions.sorted())
        }
    }

    func testQuantities() {
        var pos = Position(units: "10 USD")
        XCTAssertEqual(pos.units, "10 USD")
        XCTAssertEqual(pos.totalCost, "10 USD")

        pos = Position(
            units: "10 USD", cost: Cost(number: "1.5", currency: "AUD", date: .distantPast))
        XCTAssertEqual(pos.units, "10 USD")
        XCTAssertEqual(pos.totalCost, "15 AUD")
    }

    func testNegative() {
        let pos = Position(
            units: "28372 USD", cost: Cost(number: 10, currency: "AUD", date: .distantPast))
        let negpos = -pos
        XCTAssertEqual(negpos.units, "-28372 USD")
        XCTAssertEqual(negpos.totalCost, "-283720 AUD")
    }

    func testIsNegativeAtCost() {
        let pos1 = Position(
            units: "1 USD", cost: Cost(number: 10, currency: "AUD", date: .distantPast))
        let pos2 = Position(
            units: "-1 USD", cost: Cost(number: 10, currency: "AUD", date: .distantPast))
        XCTAssertFalse(pos1.isNegativeAtCost)
        XCTAssertTrue(pos2.isNegativeAtCost)
    }

    func testCurrencyPair() {
        var pair = Position(units: "100 USD").currencyPair
        XCTAssert(pair.0 == "USD" && pair.1 == nil)

        pair =
            Position(
                units: "100 AAPL", cost: Cost(number: "43.23", currency: "USD", date: .distantPast)
            ).currencyPair
        XCTAssertEqual(pair.0 == "AAPL", pair.1 == "USD")
    }
}
