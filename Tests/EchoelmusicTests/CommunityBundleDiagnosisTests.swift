// CommunityBundleDiagnosisTests.swift
// Echoel — WHY THIS FILE EXISTS, and why it is shaped so oddly.
//
// Three tests have been red in the full suite since it was first wired:
// `CommunityLibraryTests.testBundledFXCommunity_loadsSeededExample`,
// `…testCuratedCommunity_includesBundledCommunity`, and
// `MoodPresetTests.testBundledCommunity_loadsSeededExample`. All three say the same
// thing — a JSON file that IS committed under `Sources/Echoelmusic/Resources/Community/`
// does not come back from `CommunityLibrary`. TWO project.yml bundling changes were made
// to fix it (commit 95f0602, then the `sources:` excludes) and, as `CommunityLibrary.swift`
// itself records, both had ZERO measurable effect.
//
// The reason they were guesses is structural: the CI summary step surfaces only the
// `Test case '<Class>.<name>()' failed` lines, NEVER the XCTAssert message. So the
// existing tests' careful `census(names)` diagnostics — which say exactly what WAS
// found — are written into a log nobody reads. Every attempt was therefore blind.
//
// This file makes the failure self-describing by putting each link of the chain in its
// OWN test method, so the set of failing NAMES is the diagnosis:
//
//   Diag3 fails  → no bundled JSON is reachable at all; the resourceURL walk finds
//                  nothing. Look at which bundle is resolved, not at the folder.
//   Diag3 ok, 4 fails → the Community folder never reached the app bundle. That IS a
//                  project.yml bundling problem (founder-gated file) — but now with
//                  evidence instead of a third guess.
//   Diag4 ok, 5 fails → the file SHIPS but FLATTENED to the bundle root, so the
//                  parent-path-suffix match in `CommunityLibrary.load` can never hit.
//                  The fix is then in the LOADER, not in project.yml at all.
//   Diag5 ok, 6 fails → it ships at the right path and fails to DECODE.
//   All pass      → the chain is whole and the original three failures come from
//                  somewhere else entirely (e.g. static-initialiser ordering).
//
// These assert against `CommunityLibrary`'s OWN `allJSONURLs`, never a re-implementation
// of the walk — a replica can diverge from the real loader and confidently answer a
// question nobody asked.
//
// SAFETY: this file lives in `Tests/EchoelmusicTests`, which only the
// `EchoelmusicFullTests` scheme compiles — run by the explicitly NON-BLOCKING
// full-tests.yml. The blocking gates use the `Echoelmusic` scheme (Tests/CISmoke), so a
// red diagnosis here cannot redden a gate. It is meant to be red until the bug is found.

import XCTest
@testable import Echoelmusic

final class CommunityBundleDiagnosisTests: XCTestCase {

    private static let seededFXFile = "aurora-drift.json"
    private static let seededMoodFile = "aurora-calm.json"

    private func url(named name: String) -> URL? {
        CommunityLibrary.allJSONURLs.first { $0.lastPathComponent == name }
    }

    // MARK: - The chain, one link per test name

    func testDiag1_candidateBundlesIsNotEmpty() {
        XCTAssertFalse(CommunityLibrary.candidateBundles.isEmpty)
    }

    func testDiag2_someCandidateBundleHasAResourceURL() {
        // `resourceURL` is nil for a bundle with no resource directory at all. If this
        // fails, the walk below cannot even start and every later link is meaningless.
        XCTAssertTrue(CommunityLibrary.candidateBundles.contains { $0.resourceURL != nil })
    }

    func testDiag3_bundleContainsAtLeastOneJSONFile() {
        // Deliberately not "contains OUR json" — this separates "the walk finds nothing"
        // from "the walk works but our folder is missing", which the original tests
        // conflated into one red line.
        XCTAssertFalse(CommunityLibrary.allJSONURLs.isEmpty)
    }

    func testDiag4_bundleContainsTheSeededFXFileSomewhere() {
        XCTAssertNotNil(url(named: Self.seededFXFile))
    }

    func testDiag5_seededFXFileParentPathEndsWithCommunitySlashFX() {
        // THE DISCRIMINATING LINK. `CommunityLibrary.load` matches on the parent path
        // SUFFIX, so a file that ships flattened to the bundle root is invisible to it
        // even though Diag4 passes. Skipping the assertion when the file is absent keeps
        // this test's failure meaning ONE thing (wrong path), not two.
        guard let u = url(named: Self.seededFXFile) else {
            return   // Diag4 already reports the absence; don't double-report it here.
        }
        let parents = u.deletingLastPathComponent().pathComponents
        XCTAssertEqual(Array(parents.suffix(2)), ["Community", "fx"])
    }

    func testDiag6_seededFXFileDecodesAsFXPreset() {
        guard let u = url(named: Self.seededFXFile), let data = try? Data(contentsOf: u) else {
            return   // absence is Diag4's story
        }
        let preset = try? JSONDecoder().decode(FXPreset.self, from: data)
        XCTAssertEqual(preset?.name, "Aurora Drift")
    }

    func testDiag7_seededMoodFileParentPathEndsWithCommunitySlashMoods() {
        // The mood file is a SECOND, independent instance of the same shipping question.
        // If FX resolves and moods does not (or vice versa), the cause is per-folder;
        // if both break identically, it is the Community folder as a whole.
        guard let u = url(named: Self.seededMoodFile) else { return }
        let parents = u.deletingLastPathComponent().pathComponents
        XCTAssertEqual(Array(parents.suffix(2)), ["Community", "moods"])
    }

    func testDiag8_theSeededFXPresetArrivesInCommunityLibraryFX() {
        // The end of the chain — same claim as the long-red `CommunityLibraryTests`
        // assertion, restated here so one run shows the whole chain together. If Diag1–6
        // pass and ONLY this fails, the bundling is fine and the bug is in `load`'s
        // filtering or in static-initialiser ordering.
        XCTAssertTrue(CommunityLibrary.fx.contains { $0.name == "Aurora Drift" })
    }
}
