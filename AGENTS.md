# Repository Guidelines

## Project Structure & Module Organization

BeancountSwift is a Swift Package Manager library. Production code lives in
`Sources/BeancountSwift`: `Core/` defines accounting models and realization, `Loader/` handles
Tree-sitter parsing and ledger loading, `Operation/` contains plugins and validations, and `Utils/`
provides shared helpers. Tests live in `Tests/BeancountSwiftTests` and mirror those areas; use
`Integration/` for end-to-end ledger flows. Package metadata and formatting rules are defined in
`Package.swift`, `Package.resolved`, and `.swift-format`.

## Architecture Overview

The package parses Beancount syntax with `SwiftTreeSitter` and `TreeSitterBeancount`. The public
entry point is `Beancount`, which exposes loading, parsing, and account-realization services. Keep
syntax conversion in `Loader`, accounting behavior in `Core`, and reusable ledger transformations
in `Operation`.

## Build, Test, and Development Commands

- `swift build` compiles the package and resolves missing dependencies.
- `swift test` runs the complete Swift Testing suite.
- `swift test --filter ParserTests` runs one test container; append a test name for a narrower run.
- `swift format . --in-place` formats Swift sources using the repository configuration.
- `swift package resolve` refreshes dependency resolution after package changes.

The package requires Swift 6.0 and targets iOS 17+, macOS 13+, watchOS 10+, tvOS 17+, and
visionOS 1+.

## Coding Style & Naming Conventions

Use four-space indentation and keep lines within 100 characters. Follow Swift API naming:
`UpperCamelCase` for types and `lowerCamelCase` for properties, functions, and test methods. Place
new files in the narrowest matching module directory. Run the formatter before submitting changes.

## Testing Guidelines

Tests use Swift Testing (`import Testing`) with `@Test`, `#expect`, and `Issue.record`. Name test
files `*Tests.swift`, group related cases in descriptive containers such as `ParserTests`, and give
test functions behavior-focused names without a `test` prefix. Add focused unit coverage for edge
cases and integration coverage when behavior crosses parsing, operations, and realization.

## Commit & Pull Request Guidelines

Recent history follows Conventional Commits such as `feat: add FormatContext` and
`fix: stabilize decimal serialization`. Use an imperative subject, a suitable prefix (`feat:`,
`fix:`, `test:`, `docs:`, or `chore:`), and keep the first line concise. Pull requests should
explain the behavioral change, link relevant issues, include examples for user-visible APIs, and
report the tests run. Keep each pull request focused and ensure formatting and tests pass.
