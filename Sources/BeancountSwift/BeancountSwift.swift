import Foundation
import SwiftTreeSitter
import TreeSitterBeancount

/// BeancountSwift provides a complete toolkit for parsing and processing Beancount files.
///
/// Beancount is a double-entry accounting system that stores financial data in plain text files.
/// This Swift implementation mirrors the functionality of the original Python Beancount library,
/// providing native Swift access to parsing, loading, and processing Beancount ledger files.
///
/// ## Usage
/// ```swift
/// let beancount = Beancount()
/// let entries = try beancount.loader.load(file: "main.beancount", contentProvider: provider)
/// let accountTree = beancount.realization.realize(entries: entries.directives)
/// ```
///
/// - SeeAlso: [Beancount Documentation](http://furius.ca/beancount/)
public struct Beancount: Sendable {
    /// Provides functionality for loading and parsing Beancount files from disk.
    ///
    /// The loader handles file I/O, includes processing, plugin execution, and parsing
    /// of Beancount ledger files into structured data.
    public let loader = Loader.self

    /// Low-level parser for Beancount syntax using tree-sitter parsing.
    ///
    /// Provides direct access to the syntax tree and parsing capabilities for
    /// Beancount files. Most users should use the `loader` instead.
    public let parser = Parser.self

    /// Account realization and tree-building functionality.
    ///
    /// Converts flat lists of accounting entries into hierarchical account trees,
    /// computing running balances and account positions.
    public let realization = Realization.self

    /// Creates a new Beancount instance with default configuration.
    public init() {}
}
