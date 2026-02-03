//
//  AmountTests.swift
//
//
//  Created by Yeatse on 2026/2/4.
//

import Testing

@testable import BeancountSwift

struct AmountTests {
    @Test func inferredPrecision() {
        #expect(Amount.inferredPrecision(from: "0.10") == 2)
        #expect(Amount.inferredPrecision(from: "10") == 0)
        #expect(Amount.inferredPrecision(from: "-12.340") == 3)
        #expect(Amount.inferredPrecision(from: "0.0") == 1)
    }
}
