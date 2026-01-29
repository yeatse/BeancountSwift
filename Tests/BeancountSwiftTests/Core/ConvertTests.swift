//
//  ConvertTests.swift
//
//
//  Created by Yeatse on 2024/1/27.
//

import Foundation
import Testing

@testable import BeancountSwift

extension PriceMap {
    static func build(from dateCurrencyPriceTuples: [(Date, Currency, Amount)]) -> PriceMap {
        return PriceMap.build(
            from: dateCurrencyPriceTuples.map({ date, currency, price in
                Directive(
                    meta: [:], date: date, content: .price(Price(currency: currency, amount: price))
                )
            }))
    }
}

struct ConvertTests {
    func pos(_ literal: String) -> Position {
        return Position(stringLiteral: literal)
    }

    func posWithMissingCost(_ literal: String) -> Position {
        var position = Position(stringLiteral: literal)
        position.cost?.number = .nan
        return position
    }

    @Test func costEmpty() {
        let position = pos("100 HOOL")
        #expect(position.totalCost == "100 HOOL")
    }

    @Test func costNotEmpty() {
        let position = pos("100 HOOL {514.00 USD}")
        #expect(position.totalCost == "51400.00 USD")
    }

    @Test func costMissing() {
        let position = posWithMissingCost("100 HOOL {0 USD}")
        #expect(position.totalCost == "100 HOOL")
    }

    @Test func weightNoCost() {
        let position = pos("100 HOOL")
        #expect(position.weight == "100 HOOL")
    }

    @Test func weightWithCost() {
        let position = pos("100 HOOL {514.00 USD}")
        #expect(position.weight == "51400.00 USD")
    }

    @Test func weightWithCostMissing() {
        let position = posWithMissingCost("100 HOOL {0 USD}")
        #expect(position.weight == "100 HOOL")
    }

    let emptyPriceMap = PriceMap.build(from: [(Date, Currency, Amount)]())

    let hitPriceMap = PriceMap.build(from: [
        ("2016-02-01", "HOOL", "530.00 USD"),
        ("2016-02-01", "USD", "1.2 CAD"),
    ])

    let rateOnlyPriceMap = PriceMap.build(from: [
        ("2016-02-01", "USD", "1.2 CAD")
    ])

    @Test func valueNoCurrency() {
        let pos = pos("100 HOOL")
        #expect(pos.marketValue(from: emptyPriceMap) == "100 HOOL")
        #expect(pos.marketValue(from: hitPriceMap) == "100 HOOL")
    }

    @Test func valueCurrencyFromCost() {
        let pos = pos("100 HOOL {514.00 USD}")
        #expect(pos.marketValue(from: hitPriceMap) == "53000.00 USD")
        #expect(pos.marketValue(from: emptyPriceMap) == "100 HOOL")
    }

    @Test func convertPositionSuccess() {
        let pos = pos("100 HOOL {514.00 USD}")
        #expect(pos.converted(to: "USD", priceMap: hitPriceMap) == "53000.00 USD")
    }

    @Test func convertPositionMissButSameCurrency() {
        let pos = pos("100 HOOL {514.00 USD}")
        #expect(pos.converted(to: "USD", priceMap: emptyPriceMap) == "100 HOOL")
    }

    @Test func convertPositionMissAndMissRateToRate() {
        let pos = pos("100 HOOL {514.00 USD}")
        #expect(pos.converted(to: "JPY", priceMap: hitPriceMap) == "100 HOOL")
    }

    @Test func convertPositionMissAndMissValueRate() {
        let pos = pos("100 HOOL {514.00 USD}")
        #expect(pos.converted(to: "CAD", priceMap: rateOnlyPriceMap) == "100 HOOL")
    }

    @Test func convertPositionMissAndMissBoth() {
        let pos = pos("100 HOOL {514.00 USD}")
        #expect(pos.converted(to: "CAD", priceMap: emptyPriceMap) == "100 HOOL")
    }

    @Test func convertPositionMissAndSuccessOnImplieds() {
        let pos = pos("100 HOOL {514.00 USD}")
        #expect(pos.converted(to: "CAD", priceMap: hitPriceMap) == "63600.00 CAD")
    }

    @Test func convertAmountFail() {
        let amt: Amount = "127.00 USD"
        #expect(amt.converted(to: "CAD", priceMap: emptyPriceMap) == amt)
    }

    @Test func convertAmountSuccess() {
        let amt: Amount = "127.00 USD"
        #expect(amt.converted(to: "CAD", priceMap: hitPriceMap) == "152.40 CAD")
    }

    @Test func convertAmountNoop() {
        let amt: Amount = "127.00 USD"
        #expect(amt.converted(to: "USD", priceMap: emptyPriceMap) == amt)
        #expect(amt.converted(to: "USD", priceMap: hitPriceMap) == amt)
    }

    @Test func convertAmountWithDate() throws {
        let p: ContentProvider =
            """
            2013-01-01 price  USD  1.20 CAD
            2014-01-01 price  USD  1.25 CAD
            2015-01-01 price  USD  1.30 CAD
            """
        let ledger = try p.loadLedger()
        let priceMap = PriceMap.build(from: ledger.directives)

        let cases: [(Date?, Amount)] = [
            (nil, "130 CAD"),
            ("2015-01-01", "130 CAD"),
            ("2014-12-31", "125 CAD"),
            ("2014-01-01", "125 CAD"),
            ("2013-12-31", "120 CAD"),
            ("2013-01-01", "120 CAD"),
            ("2012-12-31", "100 USD"),
        ]
        let amount: Amount = "100 USD"
        for exp in cases {
            #expect(amount.converted(to: "CAD", priceMap: priceMap, date: exp.0) == exp.1)
        }
    }
}
