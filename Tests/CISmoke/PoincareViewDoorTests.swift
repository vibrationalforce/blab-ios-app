// PoincareViewDoorTests.swift
// Echoel — #347 Slice 3b. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PROTECTS, and it is not the maths — `PoincareMetricsTests` owns that. This
// file protects the three things that can only go wrong BETWEEN the core and its view, and
// each of them has cost this repo a cycle before:
//   1. ⛔ THE DOOR — RETIRED 2026-08-02, and the file keeps its name so the history is
//      findable. The founder struck this plot out in red (#385), the mount left
//      `signalSection`, and the view is now PARKED: doorless on purpose, file intact,
//      restorable in one line. The assertion that survives is only that the FILE still
//      exists; the long reasoning sits on that test. Everything below is unchanged — a
//      parked view still has to obey the freeze law and the honesty bar, and those are what
//      keep it from rotting while it waits.
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

    /// ⛔ THE DOOR ASSERTION IS RETIRED (2026-08-02) BECAUSE THE FOUNDER CLOSED THE DOOR.
    ///
    /// He struck the Poincaré plot out in red on the screenshot that asked for a physically
    /// honest picture of the sound (#385), and the mount came out of `signalSection` one cycle
    /// later. Three ways this could have been handled, and why this is the one:
    ///   · Keep asserting the mount → the guard goes red on a change the founder ordered. A
    ///     guard that fights an instruction gets deleted wholesale, and the OTHER two things
    ///     this file protects (the freeze law, the honesty bar) would die with it.
    ///   · Invert it to "must NOT be mounted" → that pins the parking as if it were the
    ///     decision, and would go red on the very restore this note is written to make easy.
    ///   · Retire the door half, keep the content halves. ← this.
    ///
    /// The view file is NOT deleted. `PoincareMetricsTests` still owns the maths and the two
    /// tests below still own the freeze law and the honesty bar, so the file cannot rot while
    /// it is parked. Restoring it is one line in `signalSection` (`AnalysisPoincareView()`)
    /// plus its caption plus the "Body" heading — and whoever does that should bring this
    /// assertion back in the same commit.
    ///
    /// ⚠️ WHAT IS UNGUARDED WHILE IT IS PARKED, said plainly: nothing now notices if the view
    /// is deleted outright. That is the accepted cost of a deliberate doorless state, and it
    /// is bounded by the founder's verdict on the wavefront picture.
    func testTheParkedPlotStillExistsAsAFile() throws {
        // The one door-shaped fact still worth asserting: the file is on disk. `source(_:)`
        // throws if it is not, which is the whole assertion — a parked view that quietly
        // vanished would make the "one line to restore" promise above a lie.
        let view = try source("Sources/Echoelmusic/Studio/AnalysisPoincareView.swift")
        XCTAssertTrue(view.contains("struct AnalysisPoincareView"), """
            `AnalysisPoincareView.swift` no longer declares `AnalysisPoincareView`. The view is \
            PARKED (doorless on purpose since 2026-08-02), not retired — the promise recorded \
            in `signalSection` is that restoring it costs one line. If it was genuinely \
            deleted, delete this file with it and say so in the commit.
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

    /// ⭐ THE UPSTREAM HALF OF THE SEGMENT DISCIPLINE, and the one that was missed the first
    /// time. `PoincareMetrics` routing through `RRIntervalHygiene` buys nothing if the series
    /// it receives has ALREADY had intervals removed and the gaps closed — hygiene cannot see
    /// a gap that is no longer there, so it emits one segment and the plot draws a transition
    /// that never happened. `CameraAnalyzer.rrIntervals` is exactly that: a `continue` past
    /// out-of-band peak differences, then an IQR filter, both into fresh compacted arrays.
    /// The first version of `rrWindowMs` returned it under a doc comment asserting the
    /// opposite ("RAW … no plausibility band, no ectopic rejection").
    ///
    /// It also breaks `acceptedFraction`: measured against a pre-filtered denominator it reads
    /// near 1.0 on a broken contact, so the honest-sensor check the whole readout rests on
    /// silently stops working.
    func testTheBeatWindowIsTheUnfilteredSeries() throws {
        let pub = Self.stripComments(try source("Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"))
        XCTAssertTrue(pub.contains("analyzer.rawIntervalsMs"), """
            `rrWindowMs` no longer returns `rawIntervalsMs`. If it went back to \
            `rrIntervals`, the consumer receives a series whose gaps are already closed — \
            `RRIntervalHygiene` then cannot reject what it cannot see, and both the plot and \
            the surviving-fraction readout become confident about beats that never followed \
            one another.
            """)
        XCTAssertFalse(pub.contains("{ analyzer.rrIntervals }"), """
            `rrWindowMs` reads `analyzer.rrIntervals` again — the twice-compacted array. See \
            that property's own doc, and `RRIntervalHygiene`'s header, which has named this \
            file as the bad example since July.
            """)
        let analyzer = try source("Sources/Echoelmusic/Video/CameraAnalyzer.swift")
        XCTAssertTrue(analyzer.contains("var rawIntervalsMs"), """
            `CameraAnalyzer.rawIntervalsMs` is gone. It is the only unfiltered view of the \
            beat timings; without it there is no honest denominator for `acceptedFraction` \
            anywhere in the camera path.
            """)
    }

    // MARK: - helpers

    /// Drops `//` line comments so a guard counts call sites and not the prose about them.
    ///
    /// ⛔ #460: this was a private naive truncate at the first `//`, which is NOT the same
    /// operation — it also cuts a `//` that sits INSIDE a string literal. TWO of the four sources
    /// this file scans carry one: `EchoelStudioView.swift` (the WeatherKit attribution URL) and
    /// `WorkspaceView.swift:134` (`websiteURL = URL(string: "https://echoelmusic.com")`, which
    /// the old strip left as `URL(string: "https:`). Exactly one line each; the other two
    /// sources are identical under both.
    /// Verdict-neutral on today's anchors (measured: 0 flips over every literal in this file) —
    /// but a future needle anywhere on such a line would have gone red on CORRECT code.
    /// `SourceText.codeOnly` (#453) is the ONE definition: string-aware, ordered,
    /// line-count-preserving. Do not re-inline a local copy.
    private static func stripComments(_ code: String) -> String {
        SourceText.codeOnly(code)
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
