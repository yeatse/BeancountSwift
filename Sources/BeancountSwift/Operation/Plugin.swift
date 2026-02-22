//
//  Plugin.swift
//
//
//  Created by Yeatse on 2024/1/1.
//

/// Provides the plugin system for extending Beancount functionality.
///
/// This module implements the plugin architecture that allows custom processing
/// of Beancount directives. Plugins can transform, validate, or generate new
/// directives during the loading process.
///
/// This corresponds to the plugin system in the original Beancount Python library,
/// providing similar extensibility and processing capabilities.

import Foundation

/// Represents a Beancount plugin configuration.
///
/// Plugin defines a plugin instance with its name and optional configuration.
/// Plugins are registered in Beancount files using plugin directives and are
/// executed during the loading process to transform or validate ledger data.
///
/// ## Usage
/// ```swift
/// let plugin = Plugin(name: "forecast", config: "Assets:Forecast")
/// ```
public struct Plugin: Sendable {
    /// The name of the plugin to execute.
    public let name: String
    /// Optional configuration string passed to the plugin.
    public let config: String?
}

extension Plugin {
    /// Processes directives using this plugin.
    ///
    /// Executes the plugin with the given entries and options, returning
    /// the transformed entries and any errors encountered during processing.
    ///
    /// - Parameters:
    ///   - entries: The directives to process
    ///   - options: The ledger options
    /// - Returns: A tuple of processed entries and any errors
    func process(entries: [Directive<Cost>], options: Options) -> (
        entries: [Directive<Cost>], errors: [Error]
    ) {
        guard let plugin = allPlugins[name] else {
            return (entries, [PluginError.notImplemented(name)])
        }
        do {
            return try plugin.process(entries: entries, options: options, config: config)
        } catch {
            return (entries, [error])
        }
    }
}

/// Errors that can occur during plugin execution.
enum PluginError: Error {
    /// The requested plugin is not implemented or available.
    case notImplemented(String)
}

/// Protocol that all Beancount plugins must implement.
///
/// BeancountPlugin defines the interface for plugin implementations,
/// requiring a name identifier and a processing method that transforms
/// directives and returns any errors encountered.
protocol BeancountPlugin {
    /// The unique name identifier for this plugin.
    static var name: String { get }

    /// Processes the given directives with optional configuration.
    ///
    /// - Parameters:
    ///   - entries: The directives to process
    ///   - options: The ledger options
    ///   - config: Optional plugin configuration string
    /// - Returns: A tuple of processed entries and any errors
    /// - Throws: Plugin-specific errors during processing
    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (
        entries: [Directive<Cost>], errors: [Error]
    )
}

/// Registry of all available Beancount plugins.
///
/// Maps plugin names to their implementations, providing a central
/// registry for plugin lookup and execution.
///
/// - Returns: A dictionary mapping plugin names to plugin instances
var allPlugins: [String: BeancountPlugin] {
    [
        AutoInsertOpenPlugin.name: AutoInsertOpenPlugin(),
        BalanceCheckPlugin.name: BalanceCheckPlugin(),
        ForecastPlugin.name: ForecastPlugin(),
        PadPlugin.name: PadPlugin(),
    ]
}
