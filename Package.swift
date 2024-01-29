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
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter.git", from: "0.8.0"),
        .package(url: "https://github.com/polarmutex/tree-sitter-beancount.git", branch: "master"),
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "BeancountSwift",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "TreeSitterBeancount", package: "tree-sitter-beancount"),
                .product(name: "Algorithms", package: "swift-algorithms"),
            ]
        ),
        .testTarget(
            name: "BeancountSwiftTests",
            dependencies: ["BeancountSwift"]
        ),
    ]
)
