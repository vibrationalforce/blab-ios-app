// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Echoelmusic",
    platforms: [
        .iOS(.v18)         // iPhone-first per master prompt §1. Other-platform code remains
                           // compilable behind #if canImport(...) guards but is not a v10 deliverable.
    ],
    products: [
        // Core library - shared across all platforms
        .library(
            name: "Echoelmusic",
            targets: ["Echoelmusic"]),
    ],
    dependencies: [
        // Add future dependencies here (e.g., for audio processing, ML, etc.)
    ],
    targets: [
        // Core Echoelmusic target - cross-platform code
        .target(
            name: "Echoelmusic",
            dependencies: [],
            swiftSettings: [
                // Treat all warnings as errors — prevents broken builds from reaching CI
                .unsafeFlags(["-warnings-as-errors"]),
                // Strict concurrency checking for Sendable/actor isolation
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            exclude: [
                // Platform-specific directories (handled separately)
                "Platforms/visionOS",
                "Platforms/watchOS",
                "Platforms/tvOS",
                "Platforms/iOS",
                "Platforms/macOS",
                // Files requiring platform-specific frameworks
                "VisionOS",
                "WatchOS",
                "tvOS",
                "Widgets",
                "LiveActivity",
                "AppClips",
                // Extension targets (separate Xcode targets, not part of main SPM build)
                "Targets"
                // NOTE: Sources/_Deferred/ is automatically excluded (sibling folder)
                // See DEFERRED_FEATURES.md for deferred features roadmap
            ],
            resources: [
                .process("Resources")
            ]),

        // Test target for unit tests
        .testTarget(
            name: "EchoelmusicTests",
            dependencies: ["Echoelmusic"]),
    ]
)
