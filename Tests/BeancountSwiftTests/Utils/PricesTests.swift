//
//  PricesTests.swift
//
//
//  Created by Yeatse on 2024/1/27.
//

import Foundation
import Testing

@testable import BeancountSwift

struct PricesTests {
    @Test func getLastPriceEntries() throws {
        let p: ContentProvider =
            """
            2013-01-01 price  USD  1.01 CAD
            2013-02-01 price  USD  1.02 CAD
            2013-03-01 price  USD  1.03 CAD
            2013-04-01 price  USD  1.04 CAD
            2013-05-01 price  USD  1.05 CAD
            2013-06-01 price  USD  1.06 CAD
            2013-07-01 price  USD  1.07 CAD
            """
        let ledger = try p.loadLedger()
        assertEqualEntries(
            ledger.directives.lastPriceEntries(until: "2013-05-01"),
            "2013-04-01 price  USD  1.04 CAD")

        assertEqualEntries(
            ledger.directives.lastPriceEntries(until: "2013-05-02"),
            "2013-05-01 price  USD  1.05 CAD")

        assertEqualEntries(
            ledger.directives.lastPriceEntries(until: "2014-01-01"),
            "2013-07-01 price  USD  1.07 CAD")

        assertEqualEntries(
            ledger.directives.lastPriceEntries(until: "2012-01-01"),
            "")
    }

    @Test func buildPriceMap() throws {
        let p: ContentProvider =
            """
            2013-06-01 price  USD  1.10 CAD

            ;; Try some prices at the same date.
            2013-06-02 price  USD  1.11 CAD
            2013-06-02 price  USD  1.12 CAD
            2013-06-02 price  USD  1.13 CAD

            ;; One after too.
            2013-06-03 price  USD  1.14 CAD

            ;; Try a few inverse prices.
            2013-06-05 price  CAD  0.86956 USD
            2013-06-06 price  CAD  0.86207 USD
            """
        let ledger = try p.loadLedger()
        let priceMap = PriceMap.build(from: ledger.directives)
        #expect(priceMap.prices.count == 2)
        #expect(Set(priceMap.prices.keys) == ["USD/CAD", "CAD/USD"])

        let values = priceMap.prices["USD/CAD"]!
        let expected: [(Date, Decimal)] = [
            ("2013-06-01", "1.10"),
            ("2013-06-02", "1.13"),
            ("2013-06-03", "1.14"),
            ("2013-06-05", "1.15"),
            ("2013-06-06", "1.16"),
        ]
        zip(expected, values).forEach { (exp, act) in
            #expect(exp.0 == act.date)
            #expect(exp.1 == act.rate.rounded(2, .plain))
        }
        #expect(priceMap.prices["CAD/USD"]?.count == 5)
    }

    @Test func buildPriceMapZeroPrices() throws {
        let p: ContentProvider =
            """
            1999-12-27 commodity EFA
            2010-10-01 price EFA                                 57.53 EFA
            2010-11-01 price EFA                                     0 EFA
            2011-03-01 price EFA                                 60.69 EFA
            """
        let ledger = try p.loadLedger()
        let priceMap = PriceMap.build(from: ledger.directives)
        #expect(!priceMap.prices.isEmpty)
    }

    @Test func lookupPriceAndInverse() throws {
        let p: ContentProvider =
            """
            2013-06-01 price  USD  1.01 CAD
            """
        let ledger = try p.loadLedger()
        let priceMap = PriceMap.build(from: ledger.directives)

        #expect(priceMap.lookupPriceAndInverse("EUR/USD").isEmpty)
    }

    @Test func getAllPrices() throws {
        let p: ContentProvider =
            """
            2013-06-01 price  USD  1.01 CAD
            2013-06-03 price  USD  1.03 CAD
            2013-06-05 price  USD  1.05 CAD
            2013-06-07 price  USD  1.07 CAD
            2013-06-09 price  USD  1.09 CAD
            2013-06-11 price  USD  1.11 CAD
            """
        let ledger = try p.loadLedger()
        let priceMap = PriceMap.build(from: ledger.directives)
        let priceList = priceMap.allPrices(for: "USD/CAD")
        let expected: [DailyPrice] = [
            ["2013-06-01", "1.01"],
            ["2013-06-03", "1.03"],
            ["2013-06-05", "1.05"],
            ["2013-06-07", "1.07"],
            ["2013-06-09", "1.09"],
            ["2013-06-11", "1.11"],
        ]
        #expect(expected == priceList)

        let invPriceList = priceMap.allPrices(for: "CAD/USD")
        #expect(priceList.count == invPriceList.count)

        #expect(priceMap.allPrices(for: "EWJ/JPY") == [])
    }

    @Test func getLatestPrice() throws {
        let p: ContentProvider =
            """
            2013-06-01 price  USD  1.01 CAD
            2013-06-09 price  USD  1.09 CAD
            2013-06-11 price  USD  1.11 CAD
            """
        let ledger = try p.loadLedger()
        let priceMap = PriceMap.build(from: ledger.directives)
        let priceList = priceMap.latestPrice(for: "USD/CAD")
        let expected = DailyPrice(date: "2013-06-11", rate: "1.11")
        #expect(expected == priceList)

        #expect(priceMap.latestPrice(for: "EWJ/JPY") == nil)
    }

    @Test func getPrice() throws {
        let p: ContentProvider =
            """
            2013-06-01 price  USD  1.00 CAD
            2013-06-10 price  USD  1.50 CAD
            2013-07-01 price  USD  2.00 CAD
            """
        let ledger = try p.loadLedger()
        let priceMap = PriceMap.build(from: ledger.directives)

        var dailyPrice = priceMap.price(for: "USD/CAD", date: "2013-05-15")
        #expect(dailyPrice == nil)

        dailyPrice = priceMap.price(for: "USD/CAD", date: "2013-06-01")
        #expect(dailyPrice?.date == "2013-06-01")
        #expect(dailyPrice?.rate == "1.00")

        dailyPrice = priceMap.price(for: "USD/CAD", date: "2013-06-05")
        #expect(dailyPrice?.date == "2013-06-01")
        #expect(dailyPrice?.rate == "1.00")

        dailyPrice = priceMap.price(for: "USD/CAD", date: "2013-06-10")
        #expect(dailyPrice?.date == "2013-06-10")
        #expect(dailyPrice?.rate == "1.50")

        dailyPrice = priceMap.price(for: "USD/CAD", date: "2013-06-20")
        #expect(dailyPrice?.date == "2013-06-10")
        #expect(dailyPrice?.rate == "1.50")

        dailyPrice = priceMap.price(for: "USD/CAD", date: "2013-07-01")
        #expect(dailyPrice?.date == "2013-07-01")
        #expect(dailyPrice?.rate == "2.00")

        dailyPrice = priceMap.price(for: "USD/CAD", date: "2013-07-15")
        #expect(dailyPrice?.date == "2013-07-01")
        #expect(dailyPrice?.rate == "2.00")

        dailyPrice = priceMap.price(for: "USD/CAD")
        #expect(dailyPrice?.date == "2013-07-01")
        #expect(dailyPrice?.rate == "2.00")

        dailyPrice = priceMap.price(for: "EWJ/JPY")
        #expect(dailyPrice == nil)
    }

    @Test func orderingSameDate() throws {
        let p: ContentProvider =
            """
            ;; The last one to appear in the file should be selected.
            2013-06-02 price  USD  1.13 CAD
            2013-06-02 price  USD  1.12 CAD
            2013-06-02 price  USD  1.11 CAD
            """
        let ledger = try p.loadLedger()
        let priceMap = PriceMap.build(from: ledger.directives)

        #expect(priceMap.prices.count == 2)
        #expect(Set(priceMap.prices.keys) == ["USD/CAD", "CAD/USD"])

        let values = priceMap.prices["USD/CAD"]!
        let expected = [DailyPrice(date: "2013-06-02", rate: "1.11")]
        zip(expected, values).forEach { (exp, act) in
            #expect(exp.date == act.date)
            #expect(exp.rate == act.rate.rounded(2, .plain))
        }
        #expect(priceMap.prices["CAD/USD"]?.count == 1)
    }

    @Test func project() throws {
        let p: ContentProvider =
            """
            2013-06-01 price  USD      1.12 CAD
            2013-06-15 price  HOOL  1000.00 USD
            2013-06-15 price  MFFT   200.00 USD

            2013-07-01 price  USD      1.13 CAD
            2013-07-15 price  HOOL  1010.00 USD
            """
        let ledger = try p.loadLedger()
        let priceMap = PriceMap.build(from: ledger.directives)

        let noopPriceMap = priceMap.projected(from: "USD", to: "USD")
        #expect(noopPriceMap == priceMap)

        let newPriceMap = priceMap.projected(from: "USD", to: "CAD")
        #expect(!priceMap.prices.keys.contains("HOOL/CAD"))

        #expect(
            newPriceMap.allPrices(for: "HOOL/CAD") == [
                ["2013-06-15", "1120.0000"],
                ["2013-07-15", "1141.3000"],
            ])

        #expect(
            newPriceMap.allPrices(for: "CAD/HOOL") == [
                ["2013-06-15", "0.000892857142857142857142857142857142857"],
                ["2013-07-15", "0.0008761938140716726539910628230964689"],
            ])

        let consPriceMap = priceMap.projected(from: "USD", to: "CAD", base: ["MFFT"])
        #expect(newPriceMap.prices.keys.contains("HOOL/CAD"))
        #expect(!consPriceMap.prices.keys.contains("HOOL/CAD"))

        for prices in newPriceMap.prices.values {
            #expect(
                zip(prices.dropLast(), prices.dropFirst()).allSatisfy { x, y in x.date <= y.date })
        }
    }

    @Test func projectMissing() throws {
        let p: ContentProvider =
            """
            2013-06-15 price  HOOL  1000.00 USD
            2013-07-01 price  USD      1.12 CAD
            2013-07-15 price  HOOL  1100.00 USD
            """
        let ledger = try p.loadLedger()
        let priceMap = PriceMap.build(from: ledger.directives)
        let newPriceMap = priceMap.projected(from: "USD", to: "CAD")

        #expect(
            newPriceMap.allPrices(for: "HOOL/CAD") == [
                ["2013-07-15", "1232.0000"]
            ])
    }

    @Test func projectCollisions() throws {
        let p: ContentProvider =
            """
            2013-06-01 price  USD      1.12 CAD
            2013-06-15 price  HOOL  1000.00 USD
            2013-06-15 price  HOOL  1125.00 CAD
            """
        let ledger = try p.loadLedger()
        let priceMap = PriceMap.build(from: ledger.directives)
        let newPriceMap = priceMap.projected(from: "USD", to: "CAD")

        #expect(
            newPriceMap.allPrices(for: "HOOL/CAD") == [
                ["2013-06-15", "1120.0000"],
                ["2013-06-15", "1125.00"],
            ])
    }
}
