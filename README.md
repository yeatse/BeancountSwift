# BeancountSwift

BeancountSwift is a Swift package for working with Beancount plain-text accounting.
It targets Apple platforms including iOS, macOS, watchOS, tvOS, and visionOS.
It builds on the official Tree-sitter grammar for Beancount.
The library exposes APIs for parsing ledgers, loading files, and realising account trees.

Used in [Cocono App - Beancount Agent for iOS](https://cocono.app)

[![Download on th AppStore](https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us?releaseDate=1776211200)](https://apps.apple.com/app/id6497061011) [![Download on th AppStore](https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/zh-cn?releaseDate=1776211200)](https://apps.apple.com/cn/app/cocono-%E8%AE%B0%E8%B4%A6-beancount-%E7%A7%BB%E5%8A%A8%E5%AE%A2%E6%88%B7%E7%AB%AF/id6497061011?itscg=30200&itsct=apps_box_badge&mttnsubad=6497061011)
    

## Requirements

- Swift 6.0 or newer (see `// swift-tools-version: 6.0`)
- iOS 17, macOS 13, watchOS 10, tvOS 17, or visionOS 1 and later

## Getting Started

Add **BeancountSwift** to your project using Swift Package Manager:

```swift
// In Package.swift
.package(url: "https://github.com/yeatse/BeancountSwift.git", from: "1.0.0")
```

Then add `BeancountSwift` to your target dependencies. The main entry point is the `Beancount` type.
It exposes services for loading ledgers, parsing directives, and computing balances.

## Development

- Refer to [CLAUDE.md](./CLAUDE.md) for working with Claude Code
- Refer to [AGENTS.md](./AGENTS.md) for working with Codex

## Contributing

We follow conventional commits (e.g. `feat:`, `fix:`) and ask contributors to format code with
`swift format .` before sending pull requests. Tests use Swift Testing and should live under the
`Tests/BeancountSwiftTests` hierarchy.

## License

Copyright (C) 2023 YANG Chao.

This project is licensed under the terms of the GNU General Public License, version 2 only.
See [LICENSE](LICENSE).

BeancountSwift is a Swift port of [Beancount](https://github.com/beancount/beancount), which is
distributed under the GPL-2.0-only license. Parts of this project, including test fixtures, are
derived from the Beancount source tree.
