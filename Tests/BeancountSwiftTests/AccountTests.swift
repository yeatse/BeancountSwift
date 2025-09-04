//
//  AccountTests.swift
//  
//
//  Created by Yeatse on 2024/1/28.
//

import Testing
@testable import BeancountSwift

struct AccountTests {
    
    @Test func accountRegexp() {
        #expect(try! Account.regex.wholeMatch(in: "Assets:Something") != nil)
        #expect(try! Account.regex.wholeMatch(in: "assets:Something") == nil)
    }
    
    @Test func accountIsValid() {
        #expect(Account(id: "Assets:US:RBS:Checking").isValid)
        #expect(Account(id: "Equity:Opening-Balances").isValid)
        #expect(Account(id: "Income:US:ETrade:Dividends-USD").isValid)
        #expect(Account(id: "Assets:US:RBS").isValid)
        #expect(Account(id: "Assets:US").isValid)
        #expect(!Account(id: "Assets").isValid)
        #expect(!Account(id: "Invalid").isValid)
        #expect(!Account(id: "Other").isValid)
        #expect(!Account(id: "Assets:US:RBS*Checking").isValid)
        #expect(!Account(id: "Assets:US:RBS:Checking&").isValid)
        #expect(!Account(id: "Assets:US:RBS:checking").isValid)
        #expect(!Account(id: "Assets:us:RBS:checking").isValid)
    }
    
    @Test func joinAccount() {
        #expect(Account.joined(from: ["Expenses", "Toys", "Computer"]) == "Expenses:Toys:Computer")
        #expect(Account.joined(from: ["Expenses"]) == "Expenses")
        #expect(Account.joined(from: []) == "")
    }
    
    @Test func splitAccount() {
        #expect(Account(id: "Expenses:Toys:Computer").split() == ["Expenses", "Toys", "Computer"])
        #expect(Account(id: "Expenses").split() == ["Expenses"])
        #expect(Account(id: "").split() == [])
    }
    
    @Test func parentAccount() {
        #expect(Account(id: "Expenses:Toys:Computer").parent == "Expenses:Toys")
        #expect(Account(id: "Expenses:Toys").parent == "Expenses")
        #expect(Account(id: "Expenses").parent == nil)
        #expect(Account(id: "").parent == nil)
    }
    
    @Test func isChildAccount() {
        let parent = Account(id: "Assets:Bank:Checking")
        #expect(Account(id: "Assets:Bank:Checking").isChild(of: parent))
        #expect(Account(id: "Assets:Bank:Checking:SubAccount").isChild(of: parent))
        #expect(!Account(id: "Assets:Bank:CheckingOld").isChild(of: parent))
        #expect(!Account(id: "Assets:Bank:Checking-Old").isChild(of: parent))
    }
    
    @Test func leafAccount() {
        #expect(Account(id: "Expenses:Toys:Computer").leaf == "Computer")
        #expect(Account(id: "Expenses:Toys").leaf == "Toys")
        #expect(Account(id: "Expenses").leaf == "Expenses")
        #expect(Account(id: "").leaf == "")
    }
    
    @Test func accountSansRoot() {
        #expect(Account(id: "Expenses:Toys:Computer").sansRoot == "Toys:Computer")
        #expect(Account(id: "Assets:US:BofA:Checking").sansRoot == "US:BofA:Checking")
        #expect(Account(id: "Assets").sansRoot == "")
    }
    
    @Test func accountRoot() {
        let account = Account(id: "Liabilities:US:Credit-Card:Blue")
        #expect(account.root(0) == "")
        #expect(account.root(1) == "Liabilities")
        #expect(account.root(2) == "Liabilities:US")
        #expect(account.root(3) == "Liabilities:US:Credit-Card")
        #expect(account.root(4) == "Liabilities:US:Credit-Card:Blue")
        #expect(account.root(5) == "Liabilities:US:Credit-Card:Blue")
    }
    
    @Test func hasAccountComponent() {
        let account = Account(id: "Liabilities:US:Credit-Card")
        #expect(account.hasComponent("US"))
        #expect(!account.hasComponent("CA"))
        #expect(account.hasComponent("Credit-Card"))
        #expect(account.hasComponent("Liabilities"))
        #expect(!account.hasComponent("Credit"))
        #expect(!account.hasComponent("Card"))
    }
    
    @Test func commonPrefix() {
        #expect(Account.commonPrefix(in: ["Assets:US:Bank", "Liabilities:US:Mortgage"]) == "")
        #expect(Account.commonPrefix(in: []) == "")
        #expect(Account.commonPrefix(in: ["Liabilities:US:Credit-Card", "Liabilities:US:Mortgage"]) == "Liabilities:US")
        #expect(Account.commonPrefix(in: ["Liabilities:US", "Liabilities:US:Mortgage"]) == "Liabilities:US")
        #expect(Account.commonPrefix(in: ["Liabilities:US:Mortgage", "Liabilities:US"]) == "Liabilities:US")
        #expect(Account.commonPrefix(in: ["Liabilities", "Liabilities:US:Mortgage"]) == "Liabilities")
        #expect(Account.commonPrefix(in: ["Liabilities", "Liabilit"]) == "")
        #expect(Account.commonPrefix(in: ["Liabilit", "Liabilities"]) == "")
        #expect(Account.commonPrefix(in: ["Liabilities:US:Mort", "Liabilities:US:Mortgage"]) == "Liabilities:US")
    }
    
    @Test func isValidRoot() {
        #expect(Account(id: "Assets").isValidRoot)
        #expect(Account(id: "Liabilities").isValidRoot)
        #expect(Account(id: "Equity").isValidRoot)
        #expect(Account(id: "Income").isValidRoot)
        #expect(Account(id: "Expenses").isValidRoot)
        #expect(Account(id: "Opening-Balances").isValidRoot)
        
        #expect(!Account(id: "assets").isValidRoot)
        #expect(!Account(id: "Assets:US").isValidRoot)
        #expect(!Account(id: "123Assets").isValidRoot)
        #expect(!Account(id: "").isValidRoot)
        #expect(!Account(id: "Asset*").isValidRoot)
    }
    
    @Test func isValidLeaf() {
        #expect(Account(id: "Assets:US:Bank:Checking").isValidLeaf)
        #expect(Account(id: "Liabilities:Credit-Card").isValidLeaf)
        #expect(Account(id: "Expenses:Food:Restaurant").isValidLeaf)
        #expect(Account(id: "Income:Salary").isValidLeaf)
        #expect(Account(id: "Assets").isValidLeaf)
        #expect(Account(id: "Opening-Balances").isValidLeaf)
        #expect(Account(id: "123Account").isValidLeaf)
        
        #expect(!Account(id: "assets:US:Bank").isValidLeaf)
        #expect(!Account(id: "Assets:us:Bank").isValidLeaf)
        #expect(!Account(id: "Assets:US:bank").isValidLeaf)
        #expect(!Account(id: "").isValidLeaf)
        #expect(!Account(id: "Assets:US:Bank*").isValidLeaf)
        #expect(!Account(id: "Assets::Bank").isValidLeaf)
    }
}
