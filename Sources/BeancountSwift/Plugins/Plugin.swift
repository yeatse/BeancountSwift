//
//  Plugin.swift
//
//
//  Created by Yeatse on 2024/1/1.
//

import Foundation

public struct Plugin {
    public let name: String
    public let config: String?
}

extension Plugin {
    func process(entries: [Directive<Cost>], options: Options) -> (entries: [Directive<Cost>], errors: [Error]) {
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

enum PluginError: Error {
    case notImplemented(String)
}

protocol BeancountPlugin {
    static var name: String { get }
    
    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (
        entries: [Directive<Cost>], errors: [Error]
    )
}

let allPlugins: [String: BeancountPlugin] = [
    AutoInsertOpenPlugin.name: AutoInsertOpenPlugin(),
    ForecastPlugin.name: ForecastPlugin(),
    PadPlugin.name: PadPlugin()
]
