// ThePaceIsTiltedInsideTheGenreTests.swift
// Echoel — #403 Slice 2. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PROTECTS. Slice 1 gave the performer a fingerprint and folded it into the
// structure seed. On the genre a fresh install opens with — `.selfObservation`, three chords,
// four sustained tones, no lead — a different skeleton has almost nothing to move, which the
// plan says outright. This slice is the one that reaches that genre: the person tilts the
// PACE inside the genre's own tempo window.
//
// TWO PROPERTIES, AND THE SECOND IS THE ONE THAT COULD SINK THE PRODUCT:
//   · a different body must open the same preset at a different pace, and
//   · the tilt must NEVER take a take out of its genre's window. #81 already cost this repo a
//     round of "erst individuell, dann klingt alles gleich"; a tilt that could cross a genre
//     boundary is the same mistake pointing the other way, and it would undo two curation
//     passes (#81, #125) that were done by ear.
// The second is guaranteed by SHAPE, not by a clamp — the move is a fraction of the remaining
// headroom — and the tests below are what keep that shape honest if someone "simplifies" it
// into an additive offset plus a clamp, which looks equivalent and is not.
//
// ⚠️ WHY THIS IS NOT A SECOND COPY OF THE LIVE BODY→TEMPO MAPPING. The live heart rate
// already sets the tempo, and it would be double-counting if `genreTempo` passed every body
// through. It does not: it octave-FOLDS, and any body whose octave overshoots the window's
// ceiling comes back as one of the two BOUNDS. Walked over contemplation (44…66): 68, 70, 72,
// 74, 76 all → 66; 78 through 88 all → 44. Roughly half of ordinary resting hearts land on two
// numbers, non-monotonically — the founder's 2026-08-05 log is that in the wild, nine takes and
// one tempo. The tilt is applied AFTER the fold and restores what the fold erased. In the
// pass-through band it amplifies instead, deliberately: the tilt is the HABITUAL rate, the fold
// is this moment's.

import Foundation
import XCTest
@testable import Echoelmusic

final class ThePaceIsTiltedInsideTheGenreTests: XCTestCase {

    /// Contemplation's shipped window — the genre a fresh install opens on, and the one where
    /// the fold's collapse is worst.
    private let contemplation: ClosedRange<Double> = 44...66

    // MARK: - The genre boundary is inviolable

    func testNoTiltCanLeaveTheWindow() {
        // Swept rather than spot-checked: the failure this guards against is a refactor to
        // "offset then clamp", which passes any single case you happen to write down and then
        // saturates a whole population of performers onto one bound.
        for step in 0...40 {
            let tilt = Double(step) / 20 - 1                    // −1 … +1
            for bpmStep in 0...22 {
                let bpm = 44 + Double(bpmStep)
                let out = StudioCalculator.tilted(bpm, within: contemplation, by: tilt)
                let message = "A tilt moved a take outside its genre window. The genre owns "
                    + "its boundary — a curated 44…66 pad drifting into another genre's tempo "
                    + "is exactly the convergence #81 and #125 were fixed by ear to prevent."
                XCTAssertGreaterThanOrEqual(out, contemplation.lowerBound, message)
                XCTAssertLessThanOrEqual(out, contemplation.upperBound, message)
            }
        }
    }

    func testAtTheCeilingAFastTiltHasNowhereToGo() {
        let out = StudioCalculator.tilted(66, within: contemplation, by: 1)
        let message = "A body already folded to the genre's ceiling was pushed above it. At an "
            + "edge the tilt must do nothing in that direction; the genre wins there."
        XCTAssertEqual(out, 66, accuracy: 0.0001, message)
    }

    func testAtTheFloorASlowTiltHasNowhereToGo() {
        XCTAssertEqual(StudioCalculator.tilted(44, within: contemplation, by: -1), 44,
                       accuracy: 0.0001,
                       "Same law at the other bound.")
    }

    // MARK: - …and it must still be audible

    func testAZeroTiltChangesNothing() {
        // THE GOLDEN LAW OF THIS SLICE. An unlearned performer must render bit-identically to
        // before #403 — not "close enough", the same Double.
        for bpmStep in 0...22 {
            let bpm = 44 + Double(bpmStep)
            XCTAssertEqual(StudioCalculator.tilted(bpm, within: contemplation, by: 0), bpm,
                           "A zero tilt is a no-op. Anything else changes every take of every "
                           + "user who never showed the app a pulse.")
        }
    }

    func testTwoBodiesOpenTheSamePresetAtDifferentPaces() {
        // The founder's ask, reduced to the one number it comes down to.
        let calm = StudioCalculator.tilted(55, within: contemplation, by: -1)
        let busy = StudioCalculator.tilted(55, within: contemplation, by: 1)
        let apart = busy - calm
        let message = "Two opposite performers opened the same genre at nearly the same pace. "
            + "That is the complaint this epic exists for — same preset, different person, "
            + "same-sounding song."
        XCTAssertGreaterThan(apart, 5, message)
    }

    func testTheTiltIsMonotonic() {
        // A tilt that is not monotonic is not a character — it is noise wearing one.
        var previous = -Double.infinity
        for step in 0...20 {
            let tilt = Double(step) / 10 - 1
            let out = StudioCalculator.tilted(55, within: contemplation, by: tilt)
            XCTAssertGreaterThanOrEqual(out, previous,
                                        "A more forward tilt produced a slower pace.")
            previous = out
        }
    }

    // MARK: - The edges that must not move a tempo

    func testNonFiniteInputsLeaveTheTempoAlone() {
        XCTAssertEqual(StudioCalculator.tilted(55, within: contemplation, by: .nan), 55,
                       "A NaN tilt is not a reason to move a tempo.")
        XCTAssertEqual(StudioCalculator.tilted(55, within: contemplation, by: .infinity), 55,
                       "Neither is an infinite one.")
        XCTAssertTrue(StudioCalculator.tilted(.nan, within: contemplation, by: 1).isNaN,
                      "A NaN tempo is the caller's problem and must pass through unchanged "
                      + "rather than become a plausible-looking number.")
    }

    func testADegenerateWindowIsNotATempoDecision() {
        let single: ClosedRange<Double> = 60...60
        XCTAssertEqual(StudioCalculator.tilted(60, within: single, by: 1), 60,
                       "A zero-width window has no headroom in either direction.")
    }

    func testATempoOutsideTheWindowIsBroughtInBeforeItIsTilted() {
        // Production always passes an already-folded value. This pins what happens if that
        // stops being true: the anchor is clamped first, so the result is still inside the
        // window rather than being tilted away from somewhere it should never have been.
        let out = StudioCalculator.tilted(200, within: contemplation, by: 1)
        XCTAssertLessThanOrEqual(out, contemplation.upperBound,
                                 "An out-of-window input must not carry the result out too.")
    }

    // MARK: - The premise itself, measured rather than asserted in prose

    func testTheFoldReallyDoesCollapseDistinctBodies() {
        // ⭐ THIS TEST GUARDS THE RATIONALE, NOT THE CODE — and it is here because the first
        // version of that rationale was WRONG in four files at once: it quoted `genreTempo`'s
        // description of the bug #237 FIXED ("41 % collapses onto the floor") in the present
        // tense. A prose claim nobody can run is exactly how that survives review. So the
        // premise is measured.
        //
        // If this ever goes RED, do NOT "fix" it — it means `genreTempo` stopped collapsing,
        // and the honest response is to re-argue whether the tilt is still restoring a lost
        // distinction or has become a second opinion about the same body.
        var byOutput: [Double: [Int]] = [:]
        for bpm in 44...96 {
            let out = StudioCalculator.genreTempo(Double(bpm), into: contemplation)
            byOutput[out, default: []].append(bpm)
        }
        let collapsed = byOutput.values.filter { $0.count > 1 }
        let worst = collapsed.map(\.count).max() ?? 0
        let message = "The genre fold no longer collapses distinct resting hearts onto one "
            + "tempo. That was the entire justification for tilting after the fold."
        XCTAssertGreaterThanOrEqual(worst, 4, message)

        // And it is not merely lossy — it is NON-MONOTONIC, which is the part that makes a
        // post-fold tilt the only place the person can be restored: 76 → 66 while the faster
        // 78 → 44.
        let slower = StudioCalculator.genreTempo(76, into: contemplation)
        let faster = StudioCalculator.genreTempo(78, into: contemplation)
        XCTAssertGreaterThan(slower, faster,
                             "The fold used to hand a faster heart a slower tempo (76→66 vs "
                             + "78→44). If that is gone, re-read the tilt's rationale.")
    }

    // MARK: - The tilt is a body, not a dice roll

    private func learned(restingHR: Float) -> PerformerSignature {
        PerformerSignature.unknown.observing(
            BioSampleFrame(timestamp: 1000, heartRateBPM: restingHR, hrvNormalized: 0,
                           breathRate: 0, breathPhase: 0.25, coherence: 0,
                           motionEnergy: 0, source: .cameraPPG))
    }

    func testAnUnlearnedPerformerTiltsByExactlyZero() {
        let message = "An unmeasured performer produced a non-zero tilt, so every take of "
            + "every user who never showed the app a pulse now runs at a different tempo than "
            + "it did — a behaviour change nobody asked for and nobody can explain."
        XCTAssertEqual(PerformerSignature.unknown.tempoTilt, 0, message)
    }

    func testACalmHeartTiltsSlowAndABusyOneTiltsFast() {
        XCTAssertLessThan(learned(restingHR: 52).tempoTilt, 0,
                          "A heart resting at 52 should open its preset on the calm side.")
        XCTAssertGreaterThan(learned(restingHR: 84).tempoTilt, 0,
                             "…and one resting at 84 on the forward side.")
    }

    func testTheMiddleOfTheSpanIsTheMiddleOfTheTilt() {
        let mid = learned(restingHR: 70).tempoTilt
        XCTAssertEqual(mid, 0, accuracy: 0.0001,
                       "70 BPM sits at the centre of the 50…90 resting span, so it must be "
                       + "the neutral tilt — otherwise the mapping has a hidden bias.")
    }

    func testExtremeHeartsSaturateRatherThanRunAway() {
        // A tilt beyond ±1 would be handed to `tilted`, clamped there, and the two clamps
        // would then disagree about who owns the range. Pinned at the source.
        XCTAssertEqual(learned(restingHR: 30).tempoTilt, -1, accuracy: 0.0001,
                       "Below the span the tilt saturates.")
        XCTAssertEqual(learned(restingHR: 200).tempoTilt, 1, accuracy: 0.0001,
                       "Above it too.")
    }

    // MARK: - The wiring (source text — the call sites live in a private @MainActor method)

    func testBothBodyTempoPathsAreTilted() throws {
        let source = try Self.studioSource()
        let calls = source.components(separatedBy: "StudioCalculator.tilted(").count - 1
        let message = "The instrument no longer tilts BOTH body-tempo paths. There are two — "
            + "the first seed of a take and the per-tick convergence — and tilting only one "
            + "makes the pace jump the moment the pulse becomes trustworthy."
        XCTAssertEqual(calls, 2, message)
    }

    func testTheLockedTempoIsNotTilted() throws {
        // ⚠️ A NEGATIVE SCAN CANNOT TELL CODE FROM PROSA (the #367 trap running backwards, and
        // it has already reddened this bundle once). So this does NOT scan for the absence of
        // a string: it asserts that the locked assignment still reads exactly as it did, which
        // is a positive check that fails if the tilt is ever wrapped around it.
        let source = try Self.studioSource()
        let untouched = "tempo = lockedBPM.clamped(to: Transport.minTempo...Transport.maxTempo)"
        let message = "The locked-tempo assignment changed. A number the user typed into the "
            + "tempo field is theirs; a fingerprint quietly moving it would be a lying control "
            + "— the class of defect #164 catalogued."
        XCTAssertTrue(source.contains(untouched), message)
    }

    private static func studioSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/CISmoke
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
