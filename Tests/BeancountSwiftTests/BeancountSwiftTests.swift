import XCTest
@testable import BeancountSwift

struct ContentProvider: ContentProviding {
    let source: String
    
    func provideContent(for name: String) async throws -> String {
        return source
    }
}

final class BeancountSwiftTests: XCTestCase {
    func testParser() async throws {
        let source = """
option "title" "我的账本"
option "operating_currency" "CNY"

1990-01-01 open Assets:Card:1234 CNY,USD
1990-01-01 open Liabilities:CreditCard:5678 CNY,USD
1990-01-01 open Income:Salary
1990-01-01 open Expenses:Tax
1990-01-01 open Expenses:Traffic:Taxi
1990-01-01 open Equity:OpenBalance
1990-01-01 open Assets:Card CNY
1990-01-01 open Assets:US:Bank:Checking USD
1990-01-01 open Expenses:SomeExpense USD

2019-08-27 * "" "银行卡，初始余额 1000 元"
  Assets:Card:1234    10000.00 + 10 / 2 CNY
  Equity:OpenBalance -10000.00 CNY

2022-10-16 * "" "测试开销"
  Assets:Card         -500.00 CNY
  Expenses:Tax        500     CNY

2022-10-16 * "" "测试外币"
  Assets:Card:1234  500 USD
  Expenses:Traffic:Taxi -500 USD

2023-12-15 * "" "交易描述"
  ;timezone: Beijing
  Assets:US:Bank:Checking  -100.00 USD
  Expenses:SomeExpense     100.00 USD

2022-10-18 * "" "测试开销"
  Assets:Card         -500.00 CNY
  Expenses:Tax        500     CNY

2023-12-15 * "" "交易描述"
  timezone: Beijing
  Assets:US:Bank:Checking  -100.00 USD
  Expenses:SomeExpense     100.00 USD

2022-10-18 * "" "测试开销"
  Assets:Card         -500.00 CNY
  Expenses:Tax        500     CNY

2014-07-11 * "Sold shares of S&P 500"
  Assets:ETrade:IVV               -10 IVV {183.07 USD} @ 197.90 USD
  Assets:ETrade:Cash          1979.90 USD
  Income:ETrade:CapitalGains

2012-11-03 * "Transfer to account in Canada"
  Assets:MyBank:Checking            -400.00 USD @@ 436.01 CAD
  Assets:FR:SocGen:Checking          436.01 CAD

2014-02-11 * "Bought shares of S&P 500"
  Assets:ETrade:IVV                20 IVV {183.07 USD, "ref-001"}

2020-03-31 note Assets:Etrade:IVV "Some"
"""
        let parser = Parser()
        let provider = ContentProvider(source: source)
        let ledger = try await parser.parse(file: "main.bean", contentProvider: provider)
        print(ledger)
    }
}
