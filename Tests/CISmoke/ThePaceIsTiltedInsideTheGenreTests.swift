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
// headroom. `testNearABoundTheTiltStaysInjective` is the ONE test that can tell that shape
// apart from an additive offset plus a clamp; the sweeps cannot, and an earlier version of
// this header claimed they could. See that test for why.
//
// ⚠️ THE RATIONALE FOR THE WHOLE SLICE LIVES ON `StudioCalculator.tilted`, not here — read it
// there. Two earlier versions of it were wrong (one quoted a fixed bug in the present tense,
// one measured the flattering genre and called it the default), so a second copy in this file
// is a liability, not a service. The one thing this file adds is that the premise is RUN:
// `testTheFoldReallyDoesCollapseDistinctBodies` measures it instead of asserting it in prose.

import Foundation
import XCTest
@testable import Echoelmusic

final class ThePaceIsTiltedInsideTheGenreTests: XCTestCase {

    /// The genre a fresh install actually opens on (`StudioDefaultKeys` ships
    /// `.selfObservation`) — the window every claim about "the default" must be measured on.
    private var defaultWindow: ClosedRange<Double> { MusicStyle.selfObservation.tempoRange }

    /// Contemplation is the NARROWEST calm window, so it is where the fold's collapse and the
    /// tilt's reach are both easiest to see. ⛔ It is NOT the default — an earlier version of
    /// this line said it was, 31 lines after the header correctly named `.selfObservation`.
    /// Same file, two answers; the wrong one is the one a session would have quoted.
    private let contemplation: ClosedRange<Double> = 44...66

    // MARK: - The genre boundary is inviolable

    func testNoTiltCanLeaveTheWindow() {
        // Swept rather than spot-checked — but see `testNearABoundTheTiltStaysInjective`:
        // sweeping CANNOT catch an "offset then clamp" refactor, because clamping keeps you
        // inside the window by construction. This test guards the boundary. That one guards
        // the shape.
        let message = "A tilt moved a take outside its genre window. The genre owns "
            + "its boundary — a curated pad drifting into another genre's tempo is exactly "
            + "the convergence #81 and #125 were fixed by ear to prevent."
        for window in [contemplation, defaultWindow] {
            for step in 0...40 {
                let tilt = Double(step) / 20 - 1                    // −1 … +1
                for bpmStep in 0...Int(window.upperBound - window.lowerBound) {
                    let bpm = window.lowerBound + Double(bpmStep)
                    let out = StudioCalculator.tilted(bpm, within: window, by: tilt)
                    XCTAssertGreaterThanOrEqual(out, window.lowerBound, message)
                    XCTAssertLessThanOrEqual(out, window.upperBound, message)
                }
            }
        }
    }

    func testNearABoundTheTiltStaysInjective() {
        // ⭐ THE ONLY TEST IN THIS FILE THAT DISTINGUISHES THE SHIPPED SHAPE FROM
        // "offset then clamp" — and it exists because three separate comments (two here, one
        // in the commit body) claimed the sweeps did that, and a review proved every single
        // assertion in the file passes on the clamp version:
        //
        //     let span = (hi - lo) * maxTiltShare
        //     return (bpm + amount * span).clamped(to: lo...hi)     // passes everything else
        //
        // What separates them is INJECTIVITY near a bound. Under the headroom shape the move
        // shrinks to zero as the anchor approaches the edge, so distinct bodies stay distinct.
        // Under offset-then-clamp the top of the range is flattened onto the ceiling — which
        // is precisely the "saturates a whole population onto one bound" the other comments
        // describe and could not detect.
        for window in [contemplation, defaultWindow] {
            let lo = Int(window.lowerBound), hi = Int(window.upperBound)
            for tilt in [1.0, -1.0] {
                let outs = (lo...hi).map {
                    StudioCalculator.tilted(Double($0), within: window, by: tilt)
                }
                let message = "Two different bodies near a genre bound came back with the "
                    + "SAME tempo. That is the clamp shape, not the headroom shape, and it "
                    + "is the exact failure the rest of this file cannot see."
                XCTAssertEqual(Set(outs).count, outs.count, message)
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
        //
        // ⛔ THE FIRST VERSION SWEPT ONLY bpm 55 — the exact CENTRE of 44…66, where both
        // branches of the sign split have equal slope by construction. It therefore could not
        // have caught an asymmetry bug in the very branch it was written to guard. The
        // off-centre anchors are the point; 55 stays only as the symmetric control. And the
        // comparison is STRICT: the shipped shape is strictly increasing here, so a
        // constant-returning implementation must not pass.
        for anchor in [48.0, 55.0, 63.0] {
            var previous = -Double.infinity
            for step in 0...20 {
                let tilt = Double(step) / 10 - 1
                let out = StudioCalculator.tilted(anchor, within: contemplation, by: tilt)
                XCTAssertGreaterThan(out, previous,
                                     "A more forward tilt produced the same or a slower pace.")
                previous = out
            }
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
        //
        // Measured on the DEFAULT window, not the flattering one. On `.selfObservation`
        // (46…78) the collapse is milder than on contemplation — 79…84 → 78 and 85…92 → 46 —
        // and saying so is the whole reason this is a test and not a sentence.
        var byOutput: [Double: [Int]] = [:]
        for bpm in 46...96 {
            let out = StudioCalculator.genreTempo(Double(bpm), into: defaultWindow)
            byOutput[out, default: []].append(bpm)
        }
        let worst = byOutput.values.map(\.count).max() ?? 0
        let message = "The genre fold no longer collapses distinct habitual hearts onto one "
            + "tempo on the SHIPPED DEFAULT genre. That is one of the three justifications "
            + "for tilting after the fold — re-read `StudioCalculator.tilted`'s doc."
        XCTAssertGreaterThanOrEqual(worst, 4, message)

        // And it is not merely lossy — it is NON-MONOTONIC, which is the part that makes a
        // post-fold tilt the only place the person can be restored: on the default window 84
        // gives 78 while the faster 85 gives 46.
        let slower = StudioCalculator.genreTempo(84, into: defaultWindow)
        let faster = StudioCalculator.genreTempo(85, into: defaultWindow)
        XCTAssertGreaterThan(slower, faster,
                             "The fold used to hand a faster heart a slower tempo. If that is "
                             + "gone, re-read the tilt's rationale.")
    }

    func testCoherenceErasesTheBodyEntirely() {
        // THE STRONGEST OF THE THREE JUSTIFICATIONS, and the one that is not genre-dependent:
        // `BioComposer.tempo(for:)` pulls toward the resonance pulse as coherence rises, so at
        // full coherence a calm room full of different people gets ONE suggested tempo. No
        // fold is involved. Everything downstream of that has already lost the person; the
        // tilt is the only thing that still knows who is playing.
        let calm = BioComposer.Input(heartRateBPM: 52, coherence: 1, mode: .flowFree)
        let busy = BioComposer.Input(heartRateBPM: 88, coherence: 1, mode: .flowFree)
        let message = "Two very different hearts no longer converge to one tempo at full "
            + "coherence. If the entrainment pull changed, the tilt's primary justification "
            + "changed with it and the doc on `StudioCalculator.tilted` needs re-reading."
        XCTAssertEqual(BioComposer.tempo(for: calm), BioComposer.tempo(for: busy),
                       accuracy: 0.0001, message)
    }

    // MARK: - The tilt is a body, not a dice roll

    /// A signature taught by ONE person's steady heart. Repeats the observation
    /// `confidentAfter` times by default, spaced past the 30 s rate limit, because
    /// `tempoTilt` deliberately ramps in — a single sample carries only 1/8 of the magnitude.
    /// Identical samples keep the running mean exactly at `habitualHR` (`blend(m, m, n) == m`),
    /// so the numbers below stay exact rather than approximate.
    private func learned(habitualHR: Float,
                         observations: Int = PerformerSignature.confidentAfter)
    -> PerformerSignature {
        var signature = PerformerSignature.unknown
        for i in 0..<observations {
            signature = signature.observing(
                BioSampleFrame(timestamp: 1000 + Double(i) * 60,
                               heartRateBPM: habitualHR, hrvNormalized: 0,
                               breathRate: 0, breathPhase: 0.25, coherence: 0,
                               motionEnergy: 0, source: .cameraPPG))
        }
        return signature
    }

    func testAnUnlearnedPerformerTiltsByExactlyZero() {
        let message = "An unmeasured performer produced a non-zero tilt, so every take of "
            + "every user who never showed the app a pulse now runs at a different tempo than "
            + "it did — a behaviour change nobody asked for and nobody can explain."
        XCTAssertEqual(PerformerSignature.unknown.tempoTilt, 0, message)
    }

    func testACalmHeartTiltsSlowAndABusyOneTiltsFast() {
        XCTAssertLessThan(learned(habitualHR: 52).tempoTilt, 0,
                          "A heart habitually at 52 should open its preset on the calm side.")
        XCTAssertGreaterThan(learned(habitualHR: 84).tempoTilt, 0,
                             "…and one habitually at 84 on the forward side.")
    }

    func testTheMiddleOfTheSpanIsTheMiddleOfTheTilt() {
        let mid = learned(habitualHR: 70).tempoTilt
        XCTAssertEqual(mid, 0, accuracy: 0.0001,
                       "70 BPM sits at the centre of the 50…90 habitual span, so it must be "
                       + "the neutral tilt — otherwise the mapping has a hidden bias.")
    }

    func testExtremeHeartsSaturateRatherThanRunAway() {
        // A tilt beyond ±1 would be handed to `tilted`, clamped there, and the two clamps
        // would then disagree about who owns the range. Pinned at the source.
        XCTAssertEqual(learned(habitualHR: 30).tempoTilt, -1, accuracy: 0.0001,
                       "Below the span the tilt saturates.")
        XCTAssertEqual(learned(habitualHR: 200).tempoTilt, 1, accuracy: 0.0001,
                       "Above it too.")
    }

    func testOneSampleCannotDecideThePaceForTheWholeTake() {
        // `blend`'s weight is 1/(n+1), so the FIRST accepted sample sets the mean outright.
        // Without the ramp a single startle ~30 s into a fresh install's first take would move
        // the converge target by the full 0.35·headroom — inside the 8 BPM/tick limiter on the
        // calm windows, i.e. one tick, mid-take. This is what makes "slowly learned" true of
        // sample one as well, and it is the only reason the numbers above need 8 observations.
        let one = learned(habitualHR: 90, observations: 1).tempoTilt
        let many = learned(habitualHR: 90).tempoTilt
        let message = "One observation now carries the full tilt. A single rPPG artefact would "
            + "own the pace of the take it landed in."
        XCTAssertLessThan(one, many * 0.5, message)
        XCTAssertGreaterThan(one, 0, "…but it must still point the right way from the start.")
    }

    // MARK: - The wiring (source text — the call sites live in a private @MainActor method)

    func testBothBodyTempoPathsAreTilted() throws {
        // ⛔ THIS COUNTED THE LITERAL `StudioCalculator.tilted(` AND WAS ONE CHARACTER FROM
        // BREAKING: the same commit added a doc comment naming that function two lines above a
        // real call site, and had it written the parenthesis the BLOCKING bundle would have
        // gone red for a documentation edit. The #367 code-vs-prose trap, inflating instead of
        // deflating. It now counts the ARGUMENT, which no prose has a reason to contain.
        //
        // ⚠️ AND THE EXACT `== 2` IS LOAD-BEARING FOR `testTheLockedTempoIsNotTilted`, which
        // pins one LINE and cannot see a tilt added on the next one. Only this count stops a
        // third call site appearing. Relaxing it to `>= 2` — which looks harmless — silently
        // removes the locked-tempo guarantee. The two tests are one guard; change neither alone.
        let source = try Self.studioSource()
        let calls = source.components(separatedBy: "by: performerSignature.tempoTilt)").count - 1
        let message = "The instrument no longer tilts exactly the TWO body-tempo paths — the "
            + "first seed of a take and the per-tick convergence. One means the pace jumps the "
            + "moment the pulse becomes trustworthy; three means a path nobody argued for."
        XCTAssertEqual(calls, 2, message)
    }

    func testTheLockedTempoIsNotTilted() throws {
        // ⚠️ A NEGATIVE SCAN CANNOT TELL CODE FROM PROSA (the #367 trap running backwards, and
        // it has already reddened this bundle once). So this does NOT scan for the absence of
        // a string: it asserts that the locked assignment still reads exactly as it did, which
        // is a positive check that fails if the tilt is ever wrapped around it. Its blind spot
        // — a tilt added on the FOLLOWING line — is covered by the exact count above, not here.
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
