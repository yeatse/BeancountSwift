// swift-tools-version: 6.0

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
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter.git", branch: "main"),
        .package(url: "https://github.com/yeatse/tree-sitter-beancount.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "BeancountSwift",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterBeancount", package: "tree-sitter-beancount"),
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "OrderedCollections", package: "swift-collections"),
            ]
        ),
        .testTarget(
            name: "BeancountSwiftTests",
            dependencies: ["BeancountSwift"]
        ),
    ]
)
