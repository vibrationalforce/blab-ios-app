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
// OWN test method, so the set of failing NAMES is the diagnosis. FX and moods are walked
// SEPARATELY at every link, because "fx ships, moods does not" is a real possible answer
// and a chain that only tracked fx would read fully green while `MoodPresetTests` stayed
// red — the one wrong row in the first version of this table.
//
//   Diag3 fails        → no bundled JSON is reachable at all; the resourceURL walk finds
//                        nothing. Look at which bundle is resolved, not at the folder.
//   Diag3 ok, 4 and/or 4b fail → that folder never reached the app bundle. Both failing =
//                        the Community tree as a whole; one failing = per-folder.
//   Diag4 ok, 5 fails  → the file SHIPS but FLATTENED to the bundle root, so the
//                        parent-path-suffix match in `CommunityLibrary.load` can never
//                        hit. The fix is then in the LOADER, not in project.yml.
//   Diag5 ok, 6 fails  → it ships at the right path and fails to READ or DECODE.
//   4–7 ok, 8 fails    → bundling is whole and the bug is downstream: `load`'s filtering,
//                        or static-initialiser ordering.
//   All pass           → the chain, INCLUDING the mood file, is whole; the original three
//                        failures come from somewhere else entirely.
//
// Where a link cannot be evaluated because the file is absent, these `XCTUnwrap` and so
// FAIL, deliberately double-reporting what Diag4/4b already said. The first version
// `return`ed there, which reads as a PASS — and a silent pass is the one thing that must
// not happen in a design whose only channel is the pass/fail name set. Two red names
// pointing at one real cause is a cheap price for never reading green while broken.
//
// These assert against `CommunityLibrary`'s OWN `allJSONURLs`, never a re-implementation
// of the walk — a replica can diverge from the real loader and confidently answer a
// question nobody asked.
//
// HISTORY, stated precisely because the fix depends on it: there have been THREE prior
// attempts, not two. `95f0602` and `8f362ea` changed project.yml; `eea6928` rewrote the
// LOADER itself (multi-candidate bundle + path-suffix search). All three left the tests
// red — which matters most for the Diag5 row above, since "the fix is in the loader" is
// advice the loader rewrite has already tried once.
//
// And "no measurable effect" was only ever true at the TEST level: `8f362ea` added the
// `sources:` excludes, which (given XcodeGen silently drops the `resources:` key it was
// paired with — see project.yml) removed three resource trees from every build phase.
// It changed the product a great deal; the instrument just could not see it.
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

    // Diag1/Diag2 (candidateBundles non-empty, some bundle has a resourceURL) were
    // DELETED after review: neither could fail on the Xcode path — the non-SwiftPM branch
    // always inserts `Bundle.main`, and an app bundle always has a `resourceURL` — and
    // under SwiftPM `Bundle.module` TRAPS on a missing bundle rather than returning nil,
    // so the first would have killed the process instead of failing. Two names that carry
    // no information are worse than no names; Diag3 covers the same ground with teeth.

    func testDiag3_bundleContainsAtLeastOneJSONFile() {
        // Deliberately not "contains OUR json" — this separates "the walk finds nothing"
        // from "the walk works but our folder is missing", which the original tests
        // conflated into one red line. Weak on its own: `Resources/EchoelAI/
        // echoelai-vocabulary.json` is not excluded from the group walk, so this can pass
        // on an unrelated file. Passing proves the walk RUNS, nothing about Community.
        XCTAssertFalse(CommunityLibrary.allJSONURLs.isEmpty)
    }

    func testDiag4_bundleContainsTheSeededFXFileSomewhere() {
        XCTAssertNotNil(url(named: Self.seededFXFile))
    }

    func testDiag4b_bundleContainsTheSeededMoodFileSomewhere() {
        // The moods half of Diag4. Without this, "fx ships, moods does not" produced an
        // all-green chain while MoodPresetTests stayed red — the failure mode the mood
        // checks exist to catch, defeating itself.
        XCTAssertNotNil(url(named: Self.seededMoodFile))
    }

    func testDiag5_seededFXFileParentPathEndsWithCommunitySlashFX() throws {
        // THE DISCRIMINATING LINK. `CommunityLibrary.load` matches on the parent path
        // SUFFIX, so a file that ships flattened to the bundle root is invisible to it
        // even though Diag4 passes.
        let u = try XCTUnwrap(url(named: Self.seededFXFile))
        let parents = u.deletingLastPathComponent().pathComponents
        XCTAssertEqual(Array(parents.suffix(2)), ["Community", "fx"])
    }

    func testDiag6_seededFXFileIsReadableAndDecodesAsFXPreset() throws {
        let u = try XCTUnwrap(url(named: Self.seededFXFile))
        // Readability is asserted SEPARATELY from decoding: a zero-byte or corrupt copy
        // is a distinct failure from a schema mismatch, and the first version of this
        // test swallowed it into the same silent pass as "file absent".
        let data = try XCTUnwrap(try? Data(contentsOf: u), "the file is in the bundle but unreadable")
        let preset = try? JSONDecoder().decode(FXPreset.self, from: data)
        XCTAssertEqual(preset?.name, "Aurora Drift")
    }

    func testDiag7_seededMoodFileParentPathEndsWithCommunitySlashMoods() throws {
        // The moods twin of Diag5: if fx resolves at the right path and moods does not,
        // the cause is per-folder; if both break identically, it is the Community tree.
        let u = try XCTUnwrap(url(named: Self.seededMoodFile))
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
