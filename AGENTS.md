# Repository Guidelines

## Project Structure & Module Organization
- **Sources**: Core library code in `Sources/BeancountSwift`.
- **Tests**: Unit tests in `Tests/BeancountSwiftTests`.
- **Configuration**: Manifests and tooling in `Package.swift`, `Package.resolved`, and `.swift-format`.
- **Metadata**: `README.md`, `LICENSE`, and project root files.

## Architecture Overview
BeancountSwift uses Tree Sitter (via SwiftTreeSitter) to generate an AST from the Beancount grammar. Core parsing logic lives in `Sources/BeancountSwift`, exposing directives, postings, and comment handlers.

## Dependency Management
- Run `swift package update` to bump external package versions.
- Use `swift package resolve` to refresh `Package.resolved`.
- Review `Package.swift` for defined dependencies.

## Build, Test, and Development Commands
- `swift build`: Compile the library.
- `swift test`: Execute the XCTest suite.
- `swift format .`: Apply formatting rules from `.swift-format`.
- `swift package generate-xcodeproj`: (Optional) Create an Xcode project for IDE workflows.

## Coding Style & Naming Conventions
- **Indentation**: 4 spaces (config in `.swift-format`).
- **Line length**: 100 characters max.
- **Naming**: UpperCamelCase for types, lowerCamelCase for methods and properties.
- **Formatting**: Run `swift format .` before committing changes.

## Testing Guidelines
- **Framework**: XCTest.
- **Location**: Tests in `Tests/BeancountSwiftTests`.
- **Naming**: Test files end with `Tests.swift`; methods start with `test`.
- **Coverage**: Focus on parsing rules, directives, and edge cases.

## Commit & Pull Request Guidelines
- **Commits**: Follow Conventional Commits (`feat:`, `fix:`, `chore:`), use imperative mood, keep summary under 50 characters.
- **Pull Requests**: Include a clear description, link related issues, and add examples or snippets if relevant.
- **Review**: Ensure all tests pass and code is formatted per `.swift-format`.
