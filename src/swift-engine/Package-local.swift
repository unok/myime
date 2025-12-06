// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "azookey-engine",
    products: [
        .library(
            name: "azookey-engine",
            type: .dynamic,
            targets: ["azookey-engine"]
        ),
    ],
    dependencies: [
        // Temporarily comment out AzooKeyKanaKanjiConverter
        // We'll add it back once platform issue is resolved
    ],
    targets: [
        .target(
            name: "ffi",
            dependencies: [],
            path: "Sources/ffi",
            sources: ["ffi.c"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "azookey-engine",
            dependencies: [
                // .product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter"),
                "ffi"
            ],
            path: "Sources/azookey-engine",
            swiftSettings: [
                .enableExperimentalFeature("Extern")
            ]
        ),
    ]
)