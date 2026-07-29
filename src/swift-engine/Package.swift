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
        .package(path: "../AzooKeyKanaKanjiConverter", traits: ["Zenzai"]),
    ],
    targets: [
        .target(
            name: "azookey-engine",
            dependencies: [
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter"),
            ],
            path: "Sources/azookey-engine",
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ],
            linkerSettings: [
                .linkedLibrary("llama", .when(platforms: [.windows])),
                .linkedLibrary("ggml", .when(platforms: [.windows])),
                .linkedLibrary("ggml-base", .when(platforms: [.windows])),
                .unsafeFlags(["-L../AzooKeyKanaKanjiConverter/lib/windows"], .when(platforms: [.windows]))
            ]
        ),
        .testTarget(
            name: "AzookeyEngineTests",
            dependencies: ["azookey-engine"],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
    ]
)
