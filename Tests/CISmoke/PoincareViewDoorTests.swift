// PoincareViewDoorTests.swift
// Echoel — #347 Slice 3b. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PROTECTS, and it is not the maths — `PoincareMetricsTests` owns that. This
// file protects the three things that can only go wrong BETWEEN the core and its view, and
// each of them has cost this repo a cycle before:
//   1. THE DOOR. A view nothing constructs is a file on a shelf. This repo keeps a whole
//      shelf of them (`SpectralDonutView` behind a flag with no setter, the VJ overlay,
//      `ImmersiveStageView`), and #322 is the named shape.
//   2. THE FREEZE LAW (10.76.50). `CameraRPPGBioPublisher.rrWindowMs` changes on every
//      heartbeat. Read from `EchoelStudioView` — which already holds that publisher in
//      `@Environment` — it would rebuild the whole Studio per beat and tear down any open
//      `.menu` Picker. The read belongs in a leaf, and "belongs in a leaf" is checkable.
//   3. THE HONESTY BAR. Artifact rejection preferentially removes the LARGEST successive
//      differences, so below `RRIntervalHygiene.minAcceptedFractionForHRV` an SD1 in
//      milliseconds is a confident number from a spliced record. The repo already made that
//      call for HRV; the view must not quietly invent a friendlier one.
//
// Source text, because `EchoelStudioView` and the view are SwiftUI types this bundle cannot
// build — the house pattern (`SoundPanelPresetBarTests`, `NoDoorlessStudioViewsTests`,
// `ScopeTriggerStandsStillTests`).

import Foundation
import XCTest
@testable import Echoelmusic

final class PoincareViewDoorTests: XCTestCase {

    func testThePoincarePlotHasADoor() throws {
        let code = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(code.contains("AnalysisPoincareView()"), """
            Nothing constructs `AnalysisPoincareView` any more, so the one picture in this \
            app that is about the PERSON rather than the sound has no surface. If it was \
            removed on purpose, remove this test and the view in the same commit; if it was \
            refactored, re-point this guard at the new call site.
            """)
        // Comments stripped first: the mount sits directly under a comment block that names
        // the view, and a naive `contains` would survive the mount being deleted. A door test
        // that outlives its door reports a green nobody earned.
        let mounts = Self.stripComments(code)
            .components(separatedBy: "AnalysisPoincareView").count - 1
        XCTAssertGreaterThanOrEqual(mounts, 1, """
            `AnalysisPoincareView` appears \(mounts) time(s) in the CODE (comments \
            excluded) — it is referenced only in prose, which is the #322 orphan shape.
            """)
    }

    /// The freeze law, as a structural fact rather than a comment. The publisher is already
    /// in the Studio's `@Environment`, so reading its beat window there is one keystroke
    /// away — and the resulting freeze only shows up on a device, while biofeedback runs,
    /// with a menu open. Exactly the class this repo took four cycles to diagnose
    /// (10.76.41/43/47/48) before finding the read one level up in `WorkspaceView`.
    func testTheBeatWindowIsReadOnlyFromALeaf() throws {
        let studio = Self.stripComments(try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift"))
        XCTAssertFalse(studio.contains("rrWindowMs"), """
            `EchoelStudioView` reads `rrWindowMs`. That property changes on every accepted \
            heartbeat, so this registers the whole Studio — and every open `.menu` Picker \
            in it — as an observer that rebuilds once per beat. Move the read into its own \
            leaf `View` struct, the way `AnalysisPoincareView` and its readout do it.
            """)
        let workspace = Self.stripComments(try source("Sources/Echoelmusic/Studio/WorkspaceView.swift"))
        XCTAssertFalse(workspace.contains("rrWindowMs"), """
            `WorkspaceView` reads `rrWindowMs`. It is the ROOT — a per-beat read here \
            rebuilds every surface below it. This is the exact position the 10.76.50 \
            menu-freeze was finally found in, after three audits scoped to the wrong view.
            """)
    }

    /// The view must draw and label from ONE analysis. With two entry points it can plot one
    /// set of beats and caption it with statistics derived from another — and the picture
    /// would look entirely reasonable while doing it.
    func testTheViewDrawsAndLabelsFromOneAnalysis() throws {
        let code = Self.stripComments(try source("Sources/Echoelmusic/Studio/AnalysisPoincareView.swift"))
        XCTAssertTrue(code.contains("PoincareMetrics.analyse("), """
            The view no longer calls `PoincareMetrics.analyse(rrMs:)`. That is the single \
            entry point that guarantees the cloud and the numbers come from the same \
            segments; it exists precisely so a view cannot assemble them separately.
            """)
        XCTAssertFalse(code.contains("PoincareMetrics.descriptors("), """
            The view calls `PoincareMetrics.descriptors(...)` directly. Combined with a \
            separate `points(...)` call that is how the plot and its caption start \
            describing different beats. Use `analyse(rrMs:)`.
            """)
        XCTAssertFalse(code.contains("PoincareMetrics.points("), """
            The view calls `PoincareMetrics.points(...)` directly — see above. \
            `analyse(rrMs:)` returns both halves from one hygiene pass.
            """)
    }

    /// The honesty bar and the decimal law, both pinned because both are invisible in a
    /// screenshot: a fabricated-looking SD1 under a broken signal reads exactly like a good
    /// one, and a hard-coded "." reads correct to anyone testing in English (#267).
    func testTheReadoutRefusesToStateANumberItCannotSupport() throws {
        let code = try source("Sources/Echoelmusic/Studio/AnalysisPoincareView.swift")
        XCTAssertTrue(code.contains("RRIntervalHygiene.minAcceptedFractionForHRV"), """
            The readout no longer checks `minAcceptedFractionForHRV`. Below that fraction \
            the surviving beats had their LARGEST successive differences preferentially \
            removed, so an SD1 in milliseconds states something the record cannot support. \
            The repo already refuses to print HRV and coherence there; this must match.
            """)
        XCTAssertTrue(code.contains("EchoelDecimalText.string("), """
            The SD values no longer go through `EchoelDecimalText`. See #267 — the decimal \
            separator is a setting, not a literal, and a lone "24.3" next to "24,3" \
            everywhere else is the whole defect.
            """)
        XCTAssertFalse(code.contains("String(format:"), """
            A `String(format:)` readout is back. #267 removed exactly this class app-wide.
            """)
    }

    /// The core it draws must not have drifted back to a self-invented hygiene band. This is
    /// the view-side echo of `PoincareMetricsTests`' segment guard: if `PoincareMetrics`
    /// ever re-grows its own filter, the plot silently starts showing fabricated pairs again.
    func testTheCoreStillDelegatesHygiene() throws {
        let core = try source("Sources/Echoelmusic/Bio/PoincareMetrics.swift")
        XCTAssertTrue(core.contains("RRIntervalHygiene.acceptedSegments"), """
            `PoincareMetrics` no longer routes through `RRIntervalHygiene.acceptedSegments`. \
            A local filter compacts survivors, which joins the beats either side of a \
            rejection into a pair that never occurred — measured at up to +851 % on SD1 \
            when the artifact lands at the head of the window.
            """)
    }

    // MARK: - helpers

    /// Drops `//` line comments so a guard counts call sites and not the prose about them.
    /// Line comments only, deliberately: this repo writes its explanations as `//` blocks,
    /// and a half-working `/* */` stripper would be a new way to be wrong.
    private static func stripComments(_ code: String) -> String {
        code.components(separatedBy: .newlines)
            .map { line -> String in
                guard let r = line.range(of: "//") else { return line }
                return String(line[line.startIndex..<r.lowerBound])
            }
            .joined(separator: "\n")
    }

    private func source(_ path: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than \
                reporting a green this file did not earn.
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
