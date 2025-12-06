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
        // Temporarily disabled due to Windows path length issues
        // TODO: Enable after resolving submodule path issues
        // .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", from: "0.8.0"),
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