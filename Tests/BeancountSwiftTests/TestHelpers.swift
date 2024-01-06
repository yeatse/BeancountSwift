//
//  TestHelpers.swift
//
//
//  Created by Yeatse on 2024/1/5.
//

import BeancountSwift
import Foundation

struct ContentProvider: ContentProviding {
    let source: String

    func provideContent(for name: String) async throws -> String {
        return source
    }
}

extension ContentProvider: ExpressibleByStringLiteral {
    init(stringLiteral value: StringLiteralType) {
        source = value
    }
}

extension Decimal: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self.init(string: value)!
    }
}

extension Date: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self = formatter.date(from: value)!
    }
}
