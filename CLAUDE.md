# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BeancountSwift is a Swift package for working with Beancount plain-text accounting. It parses and processes Beancount ledger files using Tree-sitter, providing native Swift APIs for loading files, parsing directives, and computing account trees. The library targets all Apple platforms (iOS 17+, macOS 13+, watchOS 10+, tvOS 17+, visionOS 1+).

## Build and Test Commands

```bash
# Build the library
swift build

# Run all tests
swift test

# Run filtered tests (by container or specific test)
swift test --filter ParserTests
swift test --filter ParserTests/parseErrors

# Format code
swift format .

# Update dependencies
swift package update

# Refresh Package.resolved
swift package resolve
```

## Architecture

The library is organized around three main components exposed via the `Beancount` type:

1. **`beancount.loader`**: High-level file loading pipeline
   - Reads Beancount files via `ContentProviding` protocol
   - Handles include directives recursively
   - Executes the full processing pipeline: parse → book → transform → validate
   - Returns `ParsedLedger<Cost>` with options, plugins, directives, and errors

2. **`beancount.parser`**: Low-level Tree-sitter parsing
   - Uses SwiftTreeSitter with TreeSitterBeancount grammar
   - Produces AST and converts to Swift types
   - Mostly used internally by the loader

3. **`beancount.realization`**: Account tree computation
   - Converts flat directive lists into hierarchical account trees
   - Computes running balances and positions per account

## Module Organization

- **Core/**: Accounting data structures (`Account`, `Inventory`, `Prices`, `Amount`, `Position`, `Directives`)
- **Loader/**: File loading, parsing, booking (lot matching), interpolation, printing
- **Operation/**: Built-in plugins and operations (Balance, Pad, Forecast, AutoInsertOpen)
- **Utils/**: Small helpers and extensions

## Plugin System

Plugins execute during the loading pipeline to transform or validate directives:

1. **Prologue**: Runs before user plugins (currently empty)
2. **User plugins**: Registered via `plugin` directives in ledger files
3. **Epilogue**: Runs after user plugins (Pad, BalanceCheck)

All plugins implement `BeancountPlugin` protocol and are registered in `allPlugins` dictionary in `Plugins/Plugin.swift`.

## Testing

- Uses **Swift Testing** framework (`import Testing`)
- Tests organized in `Tests/BeancountSwiftTests/` mirroring source structure
- Container types (e.g., `struct ParserTests`) group related tests
- Functions annotated with `@Test`, assertions use `#expect(...)`
- `Integration/` subfolder contains end-to-end ledger tests
- `TestHelpers.swift` provides shared utilities

## Code Style

- 4-space indentation, 100-character line length (configured in `.swift-format`)
- UpperCamelCase for types, lowerCamelCase for methods/properties
- Run `swift format .` before commits
- Conventional commits: `feat:`, `fix:`, `chore:`, imperative mood, ≤50 chars

## Dependencies

Defined in Package.swift:
- `swift-tree-sitter` → SwiftTreeSitter
- `tree-sitter-beancount` → TreeSitterBeancount
- `apple/swift-algorithms` (≥1.2.0) → Algorithms
- `apple/swift-collections` (≥1.1.0) → OrderedCollections

## Key Patterns

- **Booking**: The `Booking` type in `Loader/Booking.swift` handles lot matching and converts `CostSpec` to concrete `Cost` values
- **Interpolation**: Completes incomplete transactions (missing amounts/costs) via `Interpolate.swift`
- **ContentProviding**: Abstract protocol for file access, enabling testability and custom file sources
- **Sendable conformance**: All core types are `Sendable` for Swift Concurrency compatibility
