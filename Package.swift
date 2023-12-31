// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BeancountSwift",
    platforms: [.iOS(.v17), .macOS(.v13), .watchOS(.v10), .visionOS(.v1), .tvOS(.v17)],
    products: [
        .library(
            name: "BeancountSwift",
            targets: ["BeancountSwift"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/ChimeHQ/SwiftTreeSitter.git",
            .upToNextMajor(from: "0.7.2")
        ),
        .package(url: "https://github.com/polarmutex/tree-sitter-beancount.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "BeancountSwift",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "TreeSitterBeancount", package: "tree-sitter-beancount"),
            ]
        ),
        .testTarget(
            name: "BeancountSwiftTests",
            dependencies: ["BeancountSwift"]
        ),
    ]
)
