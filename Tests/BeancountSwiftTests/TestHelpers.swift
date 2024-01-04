//
//  TestHelpers.swift
//
//
//  Created by Yeatse on 2024/1/5.
//

import BeancountSwift

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
