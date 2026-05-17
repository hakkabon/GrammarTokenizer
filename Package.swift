// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GrammarTokenizer",
    products: [
        .library(
            name: "Tokenizer",
            targets: ["Tokenizer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2"),
    ],
    targets: [
        .target(
            name: "Tokenizer",
            dependencies: []
        ),
        .testTarget(
            name: "TokenizerTests",
            dependencies: ["Tokenizer"]
        ),
        .executableTarget(
            name: "tokenize",
            dependencies: [
                "Tokenizer",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
    ]
)
