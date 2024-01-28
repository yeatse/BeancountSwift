//
//  Loader.swift
//
//
//  Created by Yeatse on 2023/12/21.
//
import Foundation

public protocol ContentProviding {
    func provideContent(for file: String) async throws -> String
}

public struct ParsedLedger<T: PostingCost> {
    public var options: [Option]
    public var plugins: [Plugin]
    public var directives: [Directive<T>]
    public var errors: [Error]
}

public struct Loader {
    let booking = Booker()
    let parser = Parser()
    let defaultPlugins: [Plugin] = [
        .init(name: PadPlugin.name, config: nil),
    ]
    
    func transform(ledger: ParsedLedger<Cost>) -> ParsedLedger<Cost> {
        var result = ledger
        for plugin in defaultPlugins + ledger.plugins {
            let (entries, errors) = plugin.process(
                entries: result.directives,
                options: result.options
            )
            result.directives = entries
            result.errors += errors
        }
        result.directives.sort()
        return result
    }

    func validate(ledger: ParsedLedger<Cost>) -> ParsedLedger<Cost> {
        // TODO: validate
        return ledger
    }

    public func load(file: String, contentProvider: ContentProviding) async throws -> ParsedLedger<Cost> {
        // parsing
        let parsedResult = try await parser.parse(file: file, contentProvider: contentProvider)

        // booking
        let bookedLedger = booking.book(ledger: parsedResult)

        // transforming
        let transformedLedger = transform(ledger: bookedLedger)

        // validation
        return validate(ledger: transformedLedger)
    }
}
