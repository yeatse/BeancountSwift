//
//  AccountTests.swift
//  
//
//  Created by Yeatse on 2024/1/28.
//

import XCTest
@testable import BeancountSwift

final class AccountTests: XCTestCase {
    
    func testAccountRegexp() {
        XCTAssertNotNil(try! Account.regex.wholeMatch(in: "Assets:Something"))
        XCTAssertNil(try! Account.regex.wholeMatch(in: "assets:Something"))
    }
    
    func testAccountIsValid() {
        XCTAssertTrue(Account(id: "Assets:US:RBS:Checking").isValid)
        XCTAssertTrue(Account(id: "Equity:Opening-Balances").isValid)
        XCTAssertTrue(Account(id: "Income:US:ETrade:Dividends-USD").isValid)
        XCTAssertTrue(Account(id: "Assets:US:RBS").isValid)
        XCTAssertTrue(Account(id: "Assets:US").isValid)
        XCTAssertFalse(Account(id: "Assets").isValid)
        XCTAssertFalse(Account(id: "Invalid").isValid)
        XCTAssertFalse(Account(id: "Other").isValid)
        XCTAssertFalse(Account(id: "Assets:US:RBS*Checking").isValid)
        XCTAssertFalse(Account(id: "Assets:US:RBS:Checking&").isValid)
        XCTAssertFalse(Account(id: "Assets:US:RBS:checking").isValid)
        XCTAssertFalse(Account(id: "Assets:us:RBS:checking").isValid)
    }
    
    func testJoinAccount() {
        XCTAssertEqual(Account.joined(from: ["Expenses", "Toys", "Computer"]),
                       "Expenses:Toys:Computer")
        XCTAssertEqual(Account.joined(from: ["Expenses"]), "Expenses")
        XCTAssertEqual(Account.joined(from: []), "")
    }
    
    func testSplitAccount() {
        XCTAssertEqual(Account(id: "Expenses:Toys:Computer").split(),
                       ["Expenses", "Toys", "Computer"])
        XCTAssertEqual(Account(id: "Expenses").split(), ["Expenses"])
        XCTAssertEqual(Account(id: "").split(), [])
    }
    
    func testParentAccount() {
        XCTAssertEqual(Account(id: "Expenses:Toys:Computer").parent, "Expenses:Toys")
        XCTAssertEqual(Account(id: "Expenses:Toys").parent, "Expenses")
        XCTAssertNil(Account(id: "Expenses").parent)
        XCTAssertNil(Account(id: "").parent)
    }
    
    func testIsChildAccount() {
        let parent = Account(id: "Assets:Bank:Checking")
        XCTAssertTrue(Account(id: "Assets:Bank:Checking").isChild(of: parent))
        XCTAssertTrue(Account(id: "Assets:Bank:Checking:SubAccount").isChild(of: parent))
        XCTAssertFalse(Account(id: "Assets:Bank:CheckingOld").isChild(of: parent))
        XCTAssertFalse(Account(id: "Assets:Bank:Checking-Old").isChild(of: parent))
    }
    
    func testLeafAccount() {
        XCTAssertEqual(Account(id: "Expenses:Toys:Computer").leaf, "Computer")
        XCTAssertEqual(Account(id: "Expenses:Toys").leaf, "Toys")
        XCTAssertEqual(Account(id: "Expenses").leaf, "Expenses")
        XCTAssertEqual(Account(id: "").leaf, "")
    }
    
    func testAccountSansRoot() {
        XCTAssertEqual(Account(id: "Expenses:Toys:Computer").sansRoot, "Toys:Computer")
        XCTAssertEqual(Account(id: "Assets:US:BofA:Checking").sansRoot, "US:BofA:Checking")
        XCTAssertEqual(Account(id: "Assets").sansRoot, "")
    }
    
    func testAccountRoot() {
        let account = Account(id: "Liabilities:US:Credit-Card:Blue")
        XCTAssertEqual(account.root(0), "")
        XCTAssertEqual(account.root(1), "Liabilities")
        XCTAssertEqual(account.root(2), "Liabilities:US")
        XCTAssertEqual(account.root(3), "Liabilities:US:Credit-Card")
        XCTAssertEqual(account.root(4), "Liabilities:US:Credit-Card:Blue")
        XCTAssertEqual(account.root(5), "Liabilities:US:Credit-Card:Blue")
    }
    
    func testHasAccountComponent() {
        let account = Account(id: "Liabilities:US:Credit-Card")
        XCTAssertTrue(account.hasComponent("US"))
        XCTAssertFalse(account.hasComponent("CA"))
        XCTAssertTrue(account.hasComponent("Credit-Card"))
        XCTAssertTrue(account.hasComponent("Liabilities"))
        XCTAssertFalse(account.hasComponent("Credit"))
        XCTAssertFalse(account.hasComponent("Card"))
    }
    
    func testCommonPrefix() {
        XCTAssertEqual(Account.commonPrefix(in: ["Assets:US:Bank", "Liabilities:US:Mortgage"]), "")
        XCTAssertEqual(Account.commonPrefix(in: []), "")
        XCTAssertEqual(Account.commonPrefix(in: ["Liabilities:US:Credit-Card", "Liabilities:US:Mortgage"]), "Liabilities:US")
        XCTAssertEqual(Account.commonPrefix(in: ["Liabilities:US", "Liabilities:US:Mortgage"]), "Liabilities:US")
        XCTAssertEqual(Account.commonPrefix(in: ["Liabilities:US:Mortgage", "Liabilities:US"]), "Liabilities:US")
        XCTAssertEqual(Account.commonPrefix(in: ["Liabilities", "Liabilities:US:Mortgage"]), "Liabilities")
        XCTAssertEqual(Account.commonPrefix(in: ["Liabilities", "Liabilit"]), "")
        XCTAssertEqual(Account.commonPrefix(in: ["Liabilit", "Liabilities"]), "")
        XCTAssertEqual(Account.commonPrefix(in: ["Liabilities:US:Mort", "Liabilities:US:Mortgage"]), "Liabilities:US")
    }
    
    func testIsValidRoot() {
        XCTAssertTrue(Account(id: "Assets").isValidRoot)
        XCTAssertTrue(Account(id: "Liabilities").isValidRoot)
        XCTAssertTrue(Account(id: "Equity").isValidRoot)
        XCTAssertTrue(Account(id: "Income").isValidRoot)
        XCTAssertTrue(Account(id: "Expenses").isValidRoot)
        XCTAssertTrue(Account(id: "Opening-Balances").isValidRoot)
        
        XCTAssertFalse(Account(id: "assets").isValidRoot)
        XCTAssertFalse(Account(id: "Assets:US").isValidRoot)
        XCTAssertFalse(Account(id: "123Assets").isValidRoot)
        XCTAssertFalse(Account(id: "").isValidRoot)
        XCTAssertFalse(Account(id: "Asset*").isValidRoot)
    }
    
    func testIsValidLeaf() {
        XCTAssertTrue(Account(id: "Assets:US:Bank:Checking").isValidLeaf)
        XCTAssertTrue(Account(id: "Liabilities:Credit-Card").isValidLeaf)
        XCTAssertTrue(Account(id: "Expenses:Food:Restaurant").isValidLeaf)
        XCTAssertTrue(Account(id: "Income:Salary").isValidLeaf)
        XCTAssertTrue(Account(id: "Assets").isValidLeaf)
        XCTAssertTrue(Account(id: "Opening-Balances").isValidLeaf)
        XCTAssertTrue(Account(id: "123Account").isValidLeaf)
        
        XCTAssertFalse(Account(id: "assets:US:Bank").isValidLeaf)
        XCTAssertFalse(Account(id: "Assets:us:Bank").isValidLeaf)
        XCTAssertFalse(Account(id: "Assets:US:bank").isValidLeaf)
        XCTAssertFalse(Account(id: "").isValidLeaf)
        XCTAssertFalse(Account(id: "Assets:US:Bank*").isValidLeaf)
        XCTAssertFalse(Account(id: "Assets::Bank").isValidLeaf)
    }
}
