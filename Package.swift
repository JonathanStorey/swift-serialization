// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-serialization",
    // Floors match the minimum deployment targets of the Swift Testing module.
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Serialization", targets: ["Serialization"]),
    ],
    targets: [
        .target(name: "Serialization"),
        .testTarget(
            name: "SerializationTests",
            dependencies: ["Serialization"]
        ),
    ]
)
