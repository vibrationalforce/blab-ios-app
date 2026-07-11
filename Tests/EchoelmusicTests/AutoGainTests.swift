// AutoGainTests.swift
// Echoel — the smoothed master auto-gain (AutoMixChain.steadyGainDB). Guards the
// "profi-Pegel" fix (founder 2026-07-11: "EchoelSynth rudimentär bei den Levels"):
// the master must SETTLE toward its target loudness, not pump across ±12 dB with
// every 200 ms reading. Pure function → fully unit-testable, no AVAudio.

#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

final class AutoGainTests: XCTestCase {

    private typealias Mix = AutoMixChain

    func testCorrectionIsNarrowedToPlusMinus6dB() {
        // A wildly quiet reading must not ask for more than +6 dB, nor a wildly loud
        // one for more than −6 dB — the old ±12 dB range is what let the level swing.
        // Drive to steady state by iterating the one-pole many times.
        var gUp: Float = 0
        var gDown: Float = 0
        for _ in 0..<500 {
            gUp = Mix.steadyGainDB(current: gUp, targetLUFS: -14, lufsReading: -40)   // very quiet
            gDown = Mix.steadyGainDB(current: gDown, targetLUFS: -14, lufsReading: 0) // very loud
        }
        // Converges to within the dead-zone of the ±6 dB rails (never past them).
        XCTAssertLessThanOrEqual(gUp, 6.001, "boost never exceeds +6 dB")
        XCTAssertGreaterThanOrEqual(gUp, 5.5, "a very quiet passage climbs to near the +6 dB ceiling")
        XCTAssertGreaterThanOrEqual(gDown, -6.001, "cut never exceeds −6 dB")
        XCTAssertLessThanOrEqual(gDown, -5.5, "a very loud passage falls to near the −6 dB floor")
    }

    func testEasesGraduallyNotInOneJump() {
        // One tick must move only a FRACTION of the way to the target (no slam) — this
        // is the anti-pump property. Quiet reading wants +6 dB; one step stays small.
        let step1 = Mix.steadyGainDB(current: 0, targetLUFS: -14, lufsReading: -40)
        XCTAssertGreaterThan(step1, 0, "it does move toward the target")
        XCTAssertLessThan(step1, 1.5, "but only a small fraction in one 200 ms tick (no jump)")
    }

    func testBoostIsSlowerThanCut() {
        // Asymmetric ballistics: raising gain for a quiet passage (boost) must ease in
        // SLOWER than lowering it for a loud one (cut), so gaps/held notes never pump up
        // while sudden loud chords are still tamed reasonably quickly.
        let boostStep = Mix.steadyGainDB(current: 0, targetLUFS: -14, lufsReading: -26) // +6 wanted → boost
        let cutStep   = 0 - Mix.steadyGainDB(current: 0, targetLUFS: -14, lufsReading: -2) // −6 wanted → cut
        XCTAssertGreaterThan(cutStep, boostStep,
                             "the cut moves further per tick than the boost (faster to tame loud)")
    }

    func testDeadZoneHoldsTheLevelSteady() {
        // A tiny deviation (well inside the dead-zone) must NOT move the gain at all —
        // otherwise the level micro-jitters. Current 0 dB, reading only 0.2 dB off target.
        let held = Mix.steadyGainDB(current: 0, targetLUFS: -14, lufsReading: -14.2)
        XCTAssertEqual(held, 0, "inside the dead-zone the gain is held — no micro-pumping")
    }

    func testConvergesToTargetAtSteadyState() {
        // Held at a constant program loudness, the smoothed gain must converge to the
        // exact correction (target − reading), clamped to the ±6 dB window.
        var g: Float = 0
        for _ in 0..<800 { g = Mix.steadyGainDB(current: g, targetLUFS: -14, lufsReading: -18) }
        // Target correction is −14 − (−18) = +4 dB; the dead-zone parks it a hair short.
        XCTAssertLessThanOrEqual(g, 4.0, "never overshoots the target correction")
        XCTAssertGreaterThanOrEqual(g, 3.5, "settles at the target within the dead-zone")
    }
}
#endif
