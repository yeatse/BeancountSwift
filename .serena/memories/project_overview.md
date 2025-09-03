# BeancountSwift Project Overview

## Purpose
BeancountSwift is a Swift library that provides a parser for Beancount files. Beancount is a double-entry accounting system written in Python, and BeancountSwift aims to bring similar functionality to Swift platforms.

## Tech Stack
- **Language**: Swift 6.0
- **Platforms**: iOS 17+, macOS 13+, watchOS 10+, visionOS 1+, tvOS 17+
- **Dependencies**:
  - SwiftTreeSitter (tree-sitter parsing)
  - TreeSitterBeancount (Beancount grammar)
  - swift-algorithms (algorithm utilities)  
  - swift-collections (ordered collections)

## Project Structure
- `Sources/BeancountSwift/` - Main library source code
  - `Core/` - Core data structures (Amount, Account, Position, Inventory, etc.)
  - `Loader/` - Loading and parsing functionality
  - `Plugins/` - Plugin system (Balance, Pad, Forecast, etc.)
  - `Utils/` - Utility extensions
  - `BeancountSwift.swift` - Main entry point struct
- `Tests/BeancountSwiftTests/` - Test suite
- `Package.swift` - Swift Package Manager configuration

## Main Entry Point
The main entry point is the `Beancount` struct which provides access to:
- `loader` - Loading and parsing Beancount files
- `parser` - Low-level parsing functionality
- `realization` - Account realization and tree building