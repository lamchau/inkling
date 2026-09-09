// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Inkling",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Inkling", targets: ["Inkling"]),
    ],
    targets: [
        .executableTarget(
            name: "Inkling",
            path: "Sources/Inkling"
        ),
        .testTarget(
            name: "InklingTests",
            dependencies: ["Inkling"],
            path: "Tests/InklingTests"
        ),
    ]
)
