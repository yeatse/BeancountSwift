//
//  Loader.swift
//
//
//  Created by Yeatse on 2023/12/21.
//
import Foundation

public protocol ContentProviding {
    func provideContent(for file: String) throws -> String
}

public struct ParsedLedger<T: PostingCost>: Sendable {
    public var options: Options
    public var plugins: [Plugin]
    public var directives: [Directive<T>]
    public var errors: [Error]
}

public struct Loader: Sendable {
    let booking = Booking()
    let parser = Parser()
    
    private let prologue: [Plugin] = []
    private let epilogue: [Plugin] = [
        .init(name: PadPlugin.name, config: nil),
        .init(name: BalanceCheckPlugin.name, config: nil)
    ]
    
    func transform(ledger: ParsedLedger<Cost>) -> ParsedLedger<Cost> {
        var result = ledger
        for plugin in prologue + ledger.plugins + epilogue {
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
    
    public func load(file: String, contentProvider: ContentProviding) throws -> ParsedLedger<Cost> {
        // parsing
        let parsedResult = try parser.parse(file: file, contentProvider: contentProvider)
        
        // booking
        let bookedLedger = booking.book(ledger: parsedResult)
        
        // transforming
        let transformedLedger = transform(ledger: bookedLedger)
        
        // validation
        return validate(ledger: transformedLedger)
    }
}
