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
        .package(
            url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter",
            exact: "0.8.0"
        ),
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
                .product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter"),
                "ffi"
            ],
            path: "Sources/azookey-engine",
            swiftSettings: [
                .enableExperimentalFeature("Extern")
            ]
        ),
    ]
)
