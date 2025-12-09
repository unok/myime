// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-transformers",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "Transformers", targets: ["Tokenizers"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.4.0")),
        .package(url: "https://github.com/johnmai-dev/Jinja", .upToNextMinor(from: "1.1.0"))
    ],
    targets: [
        .target(name: "Hub", resources: [.process("FallbackConfigs")]),
        .target(name: "Tokenizers", dependencies: ["Hub", .product(name: "Jinja", package: "Jinja")]),
        .testTarget(name: "TokenizersTests", dependencies: ["Tokenizers", "Hub"], resources: [.process("Resources"), .process("Vocabs")]),
        .testTarget(name: "HubTests", dependencies: ["Hub"]),
        .testTarget(name: "PreTokenizerTests", dependencies: ["Tokenizers", "Hub"]),
    ]
)
