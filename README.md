# BeancountSwift

BeancountSwift is a Swift package for working with Beancount plain-text accounting.
It targets Apple platforms including iOS, macOS, watchOS, tvOS, and visionOS.
It builds on the official Tree-sitter grammar for Beancount.
The library exposes APIs for parsing ledgers, loading files, and realising account trees.
For background, see the [Beancount documentation](https://beancount.github.io/docs/).

## Requirements

- Swift 6.0 or newer (see `// swift-tools-version: 6.0`)
- iOS 17, macOS 13, watchOS 10, tvOS 17, or visionOS 1 and later

## Getting Started

Add **BeancountSwift** to your project using Swift Package Manager:

```swift
// In Package.swift
.package(url: "https://github.com/YOUR_ORG/BeancountSwift.git", from: "1.0.0")
```

Then add `BeancountSwift` to your target dependencies. The main entry point is the `Beancount` type.
It exposes services for loading ledgers, parsing directives, and computing balances.

## Development

- Refer to [AGENTS.md](./AGENTS.md) for working with Codex

## Contributing

We follow conventional commits (e.g. `feat:`, `fix:`) and ask contributors to format code with
`swift format .` before sending pull requests. Tests use Swift Testing and should live under the
`Tests/BeancountSwiftTests` hierarchy.

## License

This project is licensed under the terms of the MIT License. See [LICENSE](LICENSE).
