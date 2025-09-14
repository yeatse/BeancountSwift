# Repository Guidelines

## Project Structure & Module Organization
- **Sources**: Core library code in `Sources/BeancountSwift`.
  - `Core/`: Accounting data structures and realization (`Account`, `Inventory`, `Prices`).
  - `Loader/`: File loading, parsing, options, interpolation, printing.
  - `Plugins/`: Built-in plugins (`Balance`, `Pad`, `Forecast`, `AutoInsertOpen`).
  - `Utils/`: Small helpers and extensions.
- **Tests**: Unit tests in `Tests/BeancountSwiftTests`.
  - Subfolders mirror `Core/`, `Loader/`, `Plugins/`, plus `Integration/`, `Utils/`.
- **Configuration**: `Package.swift`, `Package.resolved`, and `.swift-format`.
- **Metadata**: `README.md`, `LICENSE`, and project root files.

## Architecture Overview
BeancountSwift uses Tree-sitter (via `SwiftTreeSitter`) with the Beancount grammar
(`TreeSitterBeancount`) to produce an AST and parse directives. The public surface
is centered around `Beancount`, which exposes:
- `loader`: High-level file loading, include handling, plugin execution, parsing.
- `parser`: Low-level Tree-sitter-backed parsing utilities.
- `realization`: Account tree building and balance computation.

## Platform & Toolchain
- **Swift tools**: 6.0 (see `// swift-tools-version: 6.0`).
- **Platforms**: iOS 17+, macOS 13+, watchOS 10+, visionOS 1+, tvOS 17+.

## Dependencies
Defined in `Package.swift`:
- `swift-tree-sitter` (product: `SwiftTreeSitter`).
- `tree-sitter-beancount` (product: `TreeSitterBeancount`).
- `apple/swift-algorithms` (>= 1.2.0) (product: `Algorithms`).
- `apple/swift-collections` (>= 1.1.0) (product: `OrderedCollections`).

## Dependency Management
- Run `swift package update` to bump external package versions.
- Use `swift package resolve` to refresh `Package.resolved`.
- Review and edit `Package.swift` for dependency changes.

## Build, Test, and Development Commands
- `swift build`: Compile the library.
- `swift test`: Execute the test suite (Swift Testing).
  - Filter examples:
    - By container: `swift test --filter ParserTests`
    - By test: `swift test --filter ParserTests/parseErrors`
- `swift format .`: Apply formatting per `.swift-format`.
- `swift package generate-xcodeproj`: Optional, for older IDE workflows.

## Coding Style & Naming Conventions
- **Indentation**: 4 spaces (configured in `.swift-format`).
- **Line length**: 100 characters max.
- **Naming**: UpperCamelCase for types; lowerCamelCase for methods/properties.
- **Formatting**: Run `swift format .` before committing changes.

## Testing Guidelines
- **Framework**: Swift Testing (`import Testing`).
- **Location**: `Tests/BeancountSwiftTests` with subfolders by domain.
- **Structure**: Define container types (e.g., `struct ParserTests { ... }`).
- **Tests**: Annotate functions with `@Test`; use `#expect(...)` assertions and `Issue.record(...)` for diagnostics.
- **Naming**: Test files end with `Tests.swift`; test functions use descriptive names (no `test` prefix required).
- **Coverage**: Parsing rules, directives, plugin behavior, and edge cases.
- **Integration**: Use `Integration/` tests for end-to-end ledger flows.

## Commit & Pull Request Guidelines
- **Commits**: Conventional Commits (`feat:`, `fix:`, `chore:`); imperative mood; ≤ 50 chars.
- **Pull Requests**: Describe changes, link issues, include examples if relevant.
- **Review**: Ensure tests pass and code is formatted per `.swift-format`.
