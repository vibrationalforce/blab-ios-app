// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Blab",
    platforms: [
        .iOS(.v16)  // Minimum iOS 16 for iPhone 16 Pro Max compatibility
    ],
    products: [
        // The main app product
        .library(
            name: "Blab",
            targets: ["Blab"]),
    ],
    dependencies: [
        // Add future dependencies here (e.g., for audio processing, ML, etc.)
    ],
    targets: [
        // The main app target
        .target(
            name: "Blab",
            dependencies: []),

        // Test target for unit tests
        .testTarget(
            name: "BlabTests",
            dependencies: ["Blab"]),
    ]
)
