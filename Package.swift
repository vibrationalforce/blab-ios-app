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
        // ⛔ THE STRING FORM IS LOAD-BEARING — `.iOS(.v18)` DOES NOT COMPILE HERE, and #420
        // only found that out because it fixed a DIFFERENT error first. The enum case is
        //   PackageDescription.SupportedPlatform.IOSVersion.v18
        // and the toolchain says plainly: "'v18' was introduced in PackageDescription 6.0".
        // Line 1 of this file declares `swift-tools-version: 5.10`, so the case does not
        // exist for this manifest. `SupportedPlatform.iOS(_ versionString: String)` is the
        // documented escape hatch for exactly this — a deployment target newer than the
        // tools version knows about — and it keeps the iOS 18 floor CLAUDE.md states.
        //
        // ⚠️ WHY NOT BUMP THE TOOLS VERSION TO 6.0 INSTEAD. That is the other honest fix and
        // it was rejected deliberately: tools-version 6.0 flips the default Swift LANGUAGE
        // MODE to 6 for every target. Combined with the `-warnings-as-errors` below, that
        // turns today's strict-concurrency warnings into build failures — a large, untestable
        // change (there is no local toolchain here) smuggled in behind a one-line platform
        // fix. If the tools version is ever bumped, it must be its own slice, and it must
        // carry an explicit `.swiftLanguageMode(.v5)` to keep today's semantics.
        //
        // ⚠️ SCOPE, so nobody over-reads this: SwiftPM does NOT build the app. XcodeGen +
        // `project.yml` set `IPHONEOS_DEPLOYMENT_TARGET`, and both CI gates go through
        // xcodebuild. This line only decides whether `swift build` / `swift test` — the two
        // commands CLAUDE.md's SESSION START ritual tells every fresh session to run first —
        // work at all. It was broken for both of the errors #420 turned up.
        .iOS("18.0")       // iPhone-first per master prompt §1. Other-platform code remains
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
            // No `exclude:` — every path this used to list (Platforms/, VisionOS/,
            // WatchOS/, tvOS/, Widgets/, LiveActivity/, AppClips/, Targets/) is gone from
            // disk, so the list only told SwiftPM to skip directories that do not exist.
            // Nothing else needs excluding: Sources/ holds only Echoelmusic,
            // EchoelmusicWatch and EchoelmusicWidgets.
            //
            // ⛔ `resources:` MUST STAY ABOVE `swiftSettings:`, and this is not style.
            // `PackageDescription.target` is
            //   (name:dependencies:path:exclude:sources:resources:publicHeadersPath:
            //    cSettings:cxxSettings:swiftSettings:linkerSettings:plugins:)
            // — all defaulted, so writing them in the WRONG ORDER is not a nice error about
            // ordering: overload resolution walks off to a different `target` overload and
            // reports two lies instead. That is exactly what CI printed for an unknown length
            // of time:
            //   Package.swift:39: incorrect argument labels in call (have
            //     'name:dependencies:swiftSettings:resources:', expected 'name:dependencies:
            //     path:exclude:sources:publicHeadersPath:…')
            //   Package.swift:54: type 'Array<String>.ArrayLiteralElement' (aka 'String')
            //     has no member 'process'
            // The second one points at `.process("Resources")` and reads like a resources
            // problem. It is not — `resources` had been bound to `path`'s position.
            //
            // ⛔ WHY NOBODY NOTICED: `ci.yml:165` runs `swift package resolve || true`. The
            // mask means an invalid manifest cannot fail anything, so the error just sat in
            // every CI/CD log as noise. Meanwhile CLAUDE.md's SESSION START ritual tells every
            // session to run `swift build` and `swift test` first — and what they got back was
            // this manifest error, about a file they had not touched. The `|| true` is in a
            // founder-gated file and is reported, not edited.
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                // Treat all warnings as errors — prevents broken builds from reaching CI
                .unsafeFlags(["-warnings-as-errors"]),
                // Strict concurrency checking for Sendable/actor isolation
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ]),

        // Test target for unit tests
        .testTarget(
            name: "EchoelmusicTests",
            dependencies: ["Echoelmusic"]),
    ]
)
