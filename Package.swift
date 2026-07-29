// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Echoelmusic",
    // Required the moment `Resources/` contains anything SwiftPM classifies as a LOCALIZED
    // resource. `PackageBuilder` throws `ModuleError.defaultLocalizationNotSet` — "manifest
    // property 'defaultLocalization' not set; it is required in the presence of localized
    // resources" — and it is a THROW during target construction, not a warning.
    //
    // Set pre-emptively together with `Resources/Localizable.xcstrings`. Whether SwiftPM 5.10
    // actually classifies a String Catalog as localized (the documented trigger is `.lproj`
    // directories) I could not verify without running it — and this repo has no local Swift
    // toolchain. Guessing "probably fine" would have been especially bad here: the only
    // SwiftPM invocation in CI is `swift package resolve || true` (ci.yml:165), so a manifest
    // error would be SWALLOWED and the package would simply stop resolving for anyone working
    // locally, with a green board. One line removes the question instead of masking it.
    //
    // "en" matches `Resources/iOS/Info.plist`'s CFBundleDevelopmentRegion and the catalog's
    // own `sourceLanguage`. All three must stay in step.
    defaultLocalization: "en",
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
            // No `exclude:` — every path this used to list (Platforms/, VisionOS/,
            // WatchOS/, tvOS/, Widgets/, LiveActivity/, AppClips/, Targets/) is gone from
            // disk, so the list only told SwiftPM to skip directories that do not exist.
            // Nothing else needs excluding: Sources/ holds only Echoelmusic,
            // EchoelmusicWatch and EchoelmusicWidgets.
            resources: [
                .process("Resources")
            ]),

        // Test target for unit tests
        .testTarget(
            name: "EchoelmusicTests",
            dependencies: ["Echoelmusic"]),
    ]
)
