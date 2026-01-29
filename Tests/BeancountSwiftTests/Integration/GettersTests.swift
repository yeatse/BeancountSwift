//
//  GettersTests.swift
//
//
//  Created by Yeatse on 2024/2/26.
//

import Testing

@testable import BeancountSwift

let testInput = """

    2012-02-01 open Assets:US:Cash
    2012-02-01 open Assets:US:Credit-Card
    2012-02-01 open Expenses:Grocery
    2012-02-01 open Expenses:Coffee
    2012-02-01 open Expenses:Restaurant

    2012-02-01 commodity HOOL
      name: "Hooli Corp."
      ticker: "NYSE:HOOLI"

    2012-02-01 commodity PIPA
      name: "Pied Piper"

    2012-05-18 * "Buying food" #dinner
      Expenses:Restaurant         100 USD
      Expenses:Grocery            200 USD
      Assets:US:Cash

    2013-06-20 * "Whole Foods Market" "Buying books" #books #dinner ^ee89ada94a39
      Expenses:Restaurant         150 USD
      Assets:US:Credit-Card

    2013-06-22 * "La Colombe" "Buying coffee"  ^ee89ada94a39
      Expenses:Coffee         5 USD
      Assets:US:Cash

    2014-02-01 close Assets:US:Cash
    2014-02-01 close Assets:US:Credit-Card

    """

struct GettersTests {
    func loadEntries() throws -> [Directive<Cost>] {
        let p = ContentProvider(source: testInput)
        let loader = try p.loadLedger()
        return loader.directives
    }

    @Test func getAccountsUseMap() throws {
        let entries = try loadEntries()
        let accounts = entries.accountsUsage()
        #expect(
            accounts == [
                "Expenses:Coffee": "2012-02-01"..."2013-06-22",
                "Expenses:Restaurant": "2012-02-01"..."2013-06-20",
                "Assets:US:Cash": "2012-02-01"..."2014-02-01",
                "Expenses:Grocery": "2012-02-01"..."2012-05-18",
                "Assets:US:Credit-Card": "2012-02-01"..."2014-02-01",
            ])
    }

    @Test func getAccounts() throws {
        let entries = try loadEntries()
        let accounts = entries.allAccounts()
        #expect(
            accounts == [
                "Assets:US:Cash",
                "Assets:US:Credit-Card",
                "Expenses:Grocery",
                "Expenses:Coffee",
                "Expenses:Restaurant",
            ])
    }

    @Test func getEntryAccounts() throws {
        let entries = try loadEntries()
        let accounts = entries.firstNonNil { entry in
            if case .transaction = entry.content { entry } else { nil }
        }!.usedAccounts()
        #expect(
            accounts == [
                "Assets:US:Cash",
                "Expenses:Grocery",
                "Expenses:Restaurant",
            ])
    }

    @Test func getAllTags() throws {
        let entries = try loadEntries()
        let tags = entries.allTags()
        #expect(tags == ["books", "dinner"])
    }

    @Test func getAllPayees() throws {
        let entries = try loadEntries()
        let payees = entries.allPayees()
        #expect(payees == ["La Colombe", "Whole Foods Market"])
    }

    @Test func getAllLinks() throws {
        let entries = try loadEntries()
        let links = entries.allLinks()
        #expect(links == ["ee89ada94a39"])
    }

    @Test func getCommodityDirectives() throws {
        let entries = try loadEntries()
        let commodities = entries.allCommodityDirectives()
        #expect(Set(commodities.keys) == ["HOOL", "PIPA"])
    }
}
