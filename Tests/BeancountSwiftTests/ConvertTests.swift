//
//  ConvertTests.swift
//  
//
//  Created by Yeatse on 2024/1/27.
//

import XCTest
@testable import BeancountSwift

extension PriceMap {
    static func build(from dateCurrencyPriceTuples: [(Date, Currency, Amount)]) -> PriceMap {
        return PriceMap.build(from: dateCurrencyPriceTuples.map({ date, currency, price in
            Directive(meta: [:], date: date, content: .price(Price(currency: currency, amount: price)))
        }))
    }
}

final class ConvertTests: XCTestCase {
    func _pos(_ units: Amount, _ cost: Cost? = nil) -> Position {
        return .init(units: units, cost: cost)
    }
    
    func testCostEmpty() {
        XCTAssertEqual(_pos("100 HOOL").totalCost, "100 HOOL")
    }
    
    func testCostNotEmpty() {
        XCTAssertEqual(_pos("100 HOOL", .init(number: "514.00", currency: "USD", date: .distantPast)).totalCost,
                       "51400.00 USD")
    }
    
    func testCostMissing() {
        XCTAssertEqual(_pos("100 HOOL", .init(number: .nan, currency: "USD", date: .distantPast)).totalCost,
                       "100 HOOL")
    }
    
    func testWeightNoCost() {
        XCTAssertEqual(_pos("100 HOOL").weight, "100 HOOL")
    }
    
    func testWeightWithCost() {
        XCTAssertEqual(_pos("100 HOOL", .init(number: "514.00", currency: "USD", date: .distantPast)).weight,
                       "51400.00 USD")
    }
    
    func testWeightWithCostMissing() {
        XCTAssertEqual(_pos("100 HOOL", .init(number: .nan, currency: "USD", date: .distantPast)).weight,
                       "100 HOOL")
    }
    
    let emptyPriceMap = PriceMap.build(from: [(Date, Currency, Amount)]())
    
    let hitPriceMap = PriceMap.build(from: [
        ("2016-02-01", "HOOL", "530.00 USD"),
        ("2016-02-01", "USD", "1.2 CAD"),
    ])
    
    let rateOnlyPriceMap = PriceMap.build(from: [
        ("2016-02-01", "USD", "1.2 CAD"),
    ])
    
    
    func testValueNoCurrency() {
        let pos = _pos("100 HOOL")
        XCTAssertEqual(pos.marketValue(from: emptyPriceMap),
                       "100 HOOL")
        XCTAssertEqual(pos.marketValue(from: hitPriceMap),
                       "100 HOOL")
    }
    
    func testValueCurrencyFromCost() {
        let pos = _pos("100 HOOL", .init(number: "514.00", currency: "USD", date: .distantPast))
        XCTAssertEqual(pos.marketValue(from: hitPriceMap),
                       "53000.00 USD")
        XCTAssertEqual(pos.marketValue(from: emptyPriceMap),
                       "100 HOOL")
    }
    
    func testConvertPositionSuccess() {
        let pos = _pos("100 HOOL", .init(number: "514.00", currency: "USD", date: .distantPast))
        XCTAssertEqual(pos.converted(to: "USD", priceMap: hitPriceMap),
                       "53000.00 USD")
    }
    
    func testConvertPositionMissButSameCurrency() {
        let pos = _pos("100 HOOL", .init(number: "514.00", currency: "USD", date: .distantPast))
        XCTAssertEqual(pos.converted(to: "USD", priceMap: emptyPriceMap),
                       "100 HOOL")
    }
    
    func testConvertPositionMissAndMissRateToRate() {
        let pos = _pos("100 HOOL", .init(number: "514.00", currency: "USD", date: .distantPast))
        XCTAssertEqual(pos.converted(to: "JPY", priceMap: hitPriceMap),
                       "100 HOOL")
    }
    
    func testConvertPositionMissAndMissValueRate() {
        let pos = _pos("100 HOOL", .init(number: "514.00", currency: "USD", date: .distantPast))
        XCTAssertEqual(pos.converted(to: "CAD", priceMap: rateOnlyPriceMap),
                       "100 HOOL")
    }
    
    func testConvertPositionMissAndMissBoth() {
        let pos = _pos("100 HOOL", .init(number: "514.00", currency: "USD", date: .distantPast))
        XCTAssertEqual(pos.converted(to: "CAD", priceMap: emptyPriceMap),
                       "100 HOOL")
    }
    
    func testConvertPositionMissAndSuccessOnImplieds() {
        let pos = _pos("100 HOOL", .init(number: "514.00", currency: "USD", date: .distantPast))
        XCTAssertEqual(pos.converted(to: "CAD", priceMap: hitPriceMap),
                       "63600.00 CAD")
    }
    
    func testConvertAmountFail() {
        let amt: Amount = "127.00 USD"
        XCTAssertEqual(amt.converted(to: "CAD", priceMap: emptyPriceMap), amt)
    }
    
    func testConvertAmountSuccess() {
        let amt: Amount = "127.00 USD"
        XCTAssertEqual(amt.converted(to: "CAD", priceMap: hitPriceMap), "152.40 CAD")
    }
    
    func testConvertAmountNoop() {
        let amt: Amount = "127.00 USD"
        XCTAssertEqual(amt.converted(to: "USD", priceMap: emptyPriceMap), amt)
        XCTAssertEqual(amt.converted(to: "USD", priceMap: hitPriceMap), amt)
    }
    
    func testConvertAmountWithDate() async throws {
        let p: ContentProvider =
        """
        2013-01-01 price  USD  1.20 CAD
        2014-01-01 price  USD  1.25 CAD
        2015-01-01 price  USD  1.30 CAD
        """
        let ledger = try await p.loadLedger()
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
            XCTAssertEqual(amount.converted(to: "CAD", priceMap: priceMap, date: exp.0),
                           exp.1)
        }
    }
}
