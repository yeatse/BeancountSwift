//
//  LedgerError.swift
//  BeancountSwift
//
//  Created by 杨超 on 2025/12/23.
//

import Foundation

/// A concrete source location in a Beancount ledger file.
public struct LedgerLocation {
    /// The source filename.
    public var filename: String
    /// The line number within the source file.
    public var lineno: UInt32
    
    /// Creates a source location for a file and line number.
    public init(filename: String, lineno: UInt32) {
        self.filename = filename
        self.lineno = lineno
    }
}

/// An error that can report a source location in a ledger.
public protocol LocatableError: Error {
    /// The associated source location, if available.
    var location: LedgerLocation? { get }
}
