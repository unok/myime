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
        .package(path: "../AzooKeyKanaKanjiConverter-local", traits: ["Zenzai"]),
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
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter-local"),
                "ffi"
            ],
            path: "Sources/azookey-engine",
            swiftSettings: [
                .enableExperimentalFeature("Extern"),
                .interoperabilityMode(.Cxx)
            ],
            linkerSettings: [
                .linkedLibrary("llama"),
                .linkedLibrary("ggml"),
                .linkedLibrary("ggml-base"),
                .linkedLibrary("ggml-cpu"),
                .linkedLibrary("ggml-vulkan"),
                .unsafeFlags(["-LC:/Users/unok/git/myime/src/AzooKeyKanaKanjiConverter-local/lib/windows"])
            ]
        ),
    ]
)