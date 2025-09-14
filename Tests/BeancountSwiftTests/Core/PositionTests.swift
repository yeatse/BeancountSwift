//
//  PositionTests.swift
//
//
//  Created by Yeatse on 2024/1/7.
//

import Testing

@testable import BeancountSwift

struct PositionTests {
    @Test func compareZeroToNone() {
        let pos1 = Position(units: Amount(number: .zero, currency: "CAD"))
        let pos2 = Position(units: Amount(number: .zero, currency: "USD"))
        #expect(pos1 != pos2)
    }

    @Test func neg() {
        let pos = Position(units: "7 CAD")
        let npos = -pos
        #expect(npos.units.number == -7)
        #expect(npos.units.currency == "CAD")
        #expect(pos.cost == npos.cost)
    }

    @Test func abs() {
        var pos = Position(units: "7 CAD")
        #expect(pos.absolute.units.number == 7)
        pos = Position(units: "-7 CAD")
        #expect(pos.absolute.units.number == 7)
    }

    @Test func mul() {
        let pos: Position = "2 HOOL {100.00 USD}"
        let pos2 = pos * 3
        #expect(pos2 == "6 HOOL {100.00 USD}")
    }

    @Test func eqAndSortKey() {
        let pos1 = Position(units: "200 USD")
        let pos2 = Position(units: "201 USD")
        let pos3 = Position(units: "100 CAD")
        let pos4 = Position(units: "101 CAD")
        let pos5 = Position(units: "50 ZZZ")
        let positions = [pos5, pos4, pos3, pos2, pos1].sorted()

        #expect(pos1 < pos2)
        #expect(pos2 < pos3)
        #expect(pos3 < pos4)
        #expect(pos4 < pos5)

        #expect(positions[0] == pos1)
        #expect(positions[1] == pos2)
        #expect(positions[2] == pos3)
        #expect(positions[3] == pos4)
        #expect(positions[4] == pos5)
    }

    @Test func eqAndSortKeyByCost() {
        let pos1 = Position(units: "1 USD")
        let pos2 = Position(
            units: "1 USD", cost: Cost(number: 10, currency: "USD", date: .distantPast))
        let pos3 = Position(
            units: "1 USD", cost: Cost(number: 11, currency: "USD", date: .distantPast))
        let pos4 = Position(
            units: "1 USD", cost: Cost(number: 12, currency: "USD", date: .distantPast))

        var positions = [pos3, pos2, pos1, pos4]
        #expect([pos1, pos2, pos3, pos4] == positions.sorted())

        for _ in 0..<64 {
            positions.shuffle()
            #expect([pos1, pos2, pos3, pos4] == positions.sorted())
        }
    }

    @Test func quantities() {
        var pos = Position(units: "10 USD")
        #expect(pos.units == "10 USD")
        #expect(pos.totalCost == "10 USD")

        pos = Position(
            units: "10 USD", cost: Cost(number: "1.5", currency: "AUD", date: .distantPast))
        #expect(pos.units == "10 USD")
        #expect(pos.totalCost == "15 AUD")
    }

    @Test func negative() {
        let pos = Position(
            units: "28372 USD", cost: Cost(number: 10, currency: "AUD", date: .distantPast))
        let negpos = -pos
        #expect(negpos.units == "-28372 USD")
        #expect(negpos.totalCost == "-283720 AUD")
    }

    @Test func isNegativeAtCost() {
        let pos1 = Position(
            units: "1 USD", cost: Cost(number: 10, currency: "AUD", date: .distantPast))
        let pos2 = Position(
            units: "-1 USD", cost: Cost(number: 10, currency: "AUD", date: .distantPast))
        #expect(!pos1.isNegativeAtCost)
        #expect(pos2.isNegativeAtCost)
    }

    @Test func currencyPair() {
        var pair = Position(units: "100 USD").currencyPair
        #expect(pair.unit == "USD" && pair.cost == nil)

        pair = Position(
            units: "100 AAPL",
            cost: Cost(number: "43.23", currency: "USD", date: .distantPast)
        ).currencyPair
        #expect(pair.unit == "AAPL" && pair.cost == "USD")
    }
}
