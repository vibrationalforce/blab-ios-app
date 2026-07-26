// CommunityLibraryTests.swift
// Echoel — verifies the bundled community library loads + merges. This also
// proves the SwiftPM resource bundling of Resources/Community/ (if the subdir
// were flattened, these fail in CI rather than silently no-opping on device).

import XCTest
@testable import Echoelmusic

final class CommunityLibraryTests: XCTestCase {

    // Both assertions below report WHAT WAS FOUND, not just that the expected name was
    // absent. That distinction is the whole diagnosis and the bare version cost a full
    // CI round: an EMPTY list means the resource was never located in any candidate
    // bundle (a packaging problem), while a NON-EMPTY list without "Aurora Drift" means
    // it was found and decoded into something else (a schema/name problem). The CI
    // reveal prints only a failing test's name, so an un-instrumented assertion here is
    // unfalsifiable from the log.
    private func census(_ names: [String]) -> String {
        names.isEmpty ? "EMPTY (resource not located in any candidate bundle)"
                      : "\(names.count) found: \(names.sorted().joined(separator: ", "))"
    }

    func testBundledFXCommunity_loadsSeededExample() {
        let names = CommunityLibrary.fx.map(\.name)
        XCTAssertTrue(names.contains("Aurora Drift"),
                      "seeded Resources/Community/fx/aurora-drift.json should bundle + decode — "
                      + census(names))
    }

    func testCuratedCommunity_includesBundledCommunity() {
        let names = FXPreset.curatedCommunity.map(\.name)
        XCTAssertTrue(names.contains("Aurora Drift"),
                      "curatedCommunity should append CommunityLibrary.fx — " + census(names)
                      + " | CommunityLibrary.fx alone: \(census(CommunityLibrary.fx.map(\.name)))")
    }

    func testPatchesCommunity_neverCrashes() {
        // No seeded patches yet — must be a safe empty list, not a crash.
        XCTAssertNotNil(CommunityLibrary.patches)
    }
}
