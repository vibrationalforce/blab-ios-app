// CommunityLibraryTests.swift
// Echoel — verifies the bundled community library loads + merges. This also
// proves the SwiftPM resource bundling of Resources/Community/ (if the subdir
// were flattened, these fail in CI rather than silently no-opping on device).

import XCTest
@testable import Echoelmusic

final class CommunityLibraryTests: XCTestCase {

    func testBundledFXCommunity_loadsSeededExample() {
        XCTAssertTrue(CommunityLibrary.fx.contains { $0.name == "Aurora Drift" },
                      "seeded Resources/Community/fx/aurora-drift.json should bundle + decode")
    }

    func testCuratedCommunity_includesBundledCommunity() {
        XCTAssertTrue(FXPreset.curatedCommunity.contains { $0.name == "Aurora Drift" },
                      "curatedCommunity should append CommunityLibrary.fx")
    }

    func testPatchesCommunity_neverCrashes() {
        // No seeded patches yet — must be a safe empty list, not a crash.
        XCTAssertNotNil(CommunityLibrary.patches)
    }
}
