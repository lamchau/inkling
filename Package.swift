// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Inkling",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "InklingDiff", targets: ["InklingDiff"]),
        .executable(name: "Inkling", targets: ["Inkling"]),
    ],
    targets: [
        .target(
            name: "InklingDiff",
            path: "Sources/InklingDiff"
        ),
        .executableTarget(
            name: "Inkling",
            dependencies: ["InklingDiff"],
            path: "Sources/Inkling",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "InklingTests",
            dependencies: ["Inkling", "InklingDiff"],
            path: "Tests/InklingTests"
        ),
    ]
)
