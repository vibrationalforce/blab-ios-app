// StepTickMathTests.swift
// Echoel — ULTRASYNC slice 2: the tick a live touch actually lands on.
//
// WHY THIS FILE EXISTS AT ALL. Slice 1 built `TouchQuantizer`, which decides what to do
// with a touch AT a 480-PPQ tick. Nothing in the touch path knew that tick. The only
// musical clock reachable there is the transport's `position`, and it moves once per
// SIXTEENTH — 120 ticks. Handed that alone, the quantizer sees every touch as landing
// exactly on the grid (offset 0, `.play`, no correction, ever): a feature that compiles,
// ships, and does nothing. So these tests pin the SUB-STEP half of the clock, which is
// the half that carries the whole feature.
//
// The two boundaries worth the most: the CLAMP (a late or missed step stamp must not let
// the interpolation walk into steps that have not happened) and MONOTONICITY across a
// step boundary (a clock that can go backwards would ask the quantizer to move a note
// earlier — the one thing it may never do).

import XCTest
import Foundation
@testable import Echoelmusic

final class StepTickMathTests: XCTestCase {

    // 120 BPM: one quarter = 0.5 s, one sixteenth step = 0.125 s, 960 ticks/second.
    private let bpm120 = 120.0
    private let stepSeconds120 = 0.125

    func testTicksPerStep_isTheONEExistingConstant_notASecondOne() {
        // `TimelineTime.ticksPerTransportStep` hardcodes `ticksPerQuarter / 4`, while
        // `Transport` derives its step grid from `stepsPerBeat`. Those are two independent
        // statements of the same fact, in two files. If one ever moves, every touch would
        // quantize against a grid the transport is not on — silently, with nothing failing.
        // This is the assertion that makes that impossible.
        XCTAssertEqual(StepTickMath.ticksPerStep, TimelineTime.ticksPerTransportStep)
        XCTAssertEqual(StepTickMath.ticksPerStep * Transport.stepsPerBeat,
                       TimelineTime.ticksPerQuarter,
                       "a step must tile the quarter exactly, or the grid drifts against the bar")
        XCTAssertEqual(StepTickMath.ticksPerStep, 120)
    }

    func testZeroElapsed_isTheStepBoundaryItself() {
        XCTAssertEqual(StepTickMath.tick(absoluteStep: 0, secondsSinceStep: 0, bpm: bpm120), 0)
        XCTAssertEqual(StepTickMath.tick(absoluteStep: 7, secondsSinceStep: 0, bpm: bpm120), 840)
    }

    func testMidStepTouch_landsHalfwayBetweenGridPoints() {
        // Half a sixteenth at 120 BPM = 62.5 ms = 60 ticks.
        let t = StepTickMath.tick(absoluteStep: 4,
                                  secondsSinceStep: stepSeconds120 / 2,
                                  bpm: bpm120)
        XCTAssertEqual(t, 4 * 120 + 60)
    }

    func testInterpolation_scalesWithTempo() {
        // The same 62.5 ms of wall time is a different musical distance at each tempo:
        // a quarter of a step at 60 BPM (steps last 0.25 s there), half a step at 120,
        // and a WHOLE step at 240 — where the clamp holds it at that step's last tick.
        let slow = StepTickMath.tick(absoluteStep: 0, secondsSinceStep: 0.0625, bpm: 60)
        XCTAssertEqual(slow, 30, "at 60 BPM, 62.5 ms is a quarter of a step")
        let fast = StepTickMath.tick(absoluteStep: 0, secondsSinceStep: 0.0625, bpm: 240)
        XCTAssertEqual(fast, 119, "at 240 BPM the same wall time overshoots the step — clamped")
    }

    func testHugeStepCount_clampsInsteadOfTrapping() {
        // The first version of the ceiling clamped the MULTIPLY and then overflowed on
        // the ADD (`base` at Int.max − 7, `within` up to 119). Unreachable from a running
        // transport — but a trap on a touch is not a defect anyone gets to debug live.
        let t = StepTickMath.tick(absoluteStep: .max, secondsSinceStep: 0.05, bpm: 120)
        XCTAssertGreaterThan(t, 0)
        XCTAssertLessThanOrEqual(t, Int.max)
    }

    func testStaleStamp_cannotWalkIntoStepsThatHaveNotHappened() {
        // THE clamp test. A missed step, a backgrounded app, a jittering timer: elapsed
        // keeps growing. Without the bound this returns a tick several bars ahead and the
        // quantizer corrects a touch against a beat the player is nowhere near — silently.
        for stale in [0.2, 1.0, 30.0, 600.0] {
            let t = StepTickMath.tick(absoluteStep: 3, secondsSinceStep: stale, bpm: bpm120)
            XCTAssertEqual(t, 3 * 120 + StepTickMath.ticksPerStep - 1,
                           "a \(stale)s-stale stamp escaped its own step")
        }
    }

    func testResult_alwaysStaysInsideItsOwnStep() {
        for step in 0...8 {
            for ms in stride(from: 0.0, through: 400.0, by: 3.0) {
                let t = StepTickMath.tick(absoluteStep: step,
                                          secondsSinceStep: ms / 1000, bpm: bpm120)
                XCTAssertGreaterThanOrEqual(t, step * 120)
                XCTAssertLessThan(t, (step + 1) * 120,
                                  "step \(step) at \(ms) ms leaked into the next step")
            }
        }
    }

    func testStepBoundary_isMonotone_neverGoesBackwards() {
        // The last tick reachable inside step N must be strictly below the first tick of
        // step N+1. A clock that can go backwards would hand the quantizer a note to move
        // earlier, which is the one operation physics does not allow it.
        let lastOfStep = StepTickMath.tick(absoluteStep: 5, secondsSinceStep: 999, bpm: bpm120)
        let firstOfNext = StepTickMath.tick(absoluteStep: 6, secondsSinceStep: 0, bpm: bpm120)
        XCTAssertLessThan(lastOfStep, firstOfNext)
    }

    func testNegativeOrNonFiniteInputs_collapseToTheStepBoundary() {
        let base = 2 * 120
        XCTAssertEqual(StepTickMath.tick(absoluteStep: 2, secondsSinceStep: -0.5, bpm: bpm120), base,
                       "a touch before the stamp is not a reason to invent a negative offset")
        XCTAssertEqual(StepTickMath.tick(absoluteStep: 2, secondsSinceStep: .nan, bpm: bpm120), base)
        XCTAssertEqual(StepTickMath.tick(absoluteStep: 2, secondsSinceStep: .infinity, bpm: bpm120), base)
        XCTAssertEqual(StepTickMath.tick(absoluteStep: 2, secondsSinceStep: 0.05, bpm: .nan), base)
        XCTAssertEqual(StepTickMath.tick(absoluteStep: 2, secondsSinceStep: 0.05, bpm: 0), base)
        XCTAssertEqual(StepTickMath.tick(absoluteStep: 2, secondsSinceStep: 0.05, bpm: -120), base)
    }

    func testNegativeStep_readsAsTheStart_neverAsANegativeTick() {
        // `TouchQuantizer` passes a negative tick through untouched, so a negative result
        // here would not crash — it would quietly disable correction with no explanation.
        XCTAssertEqual(StepTickMath.tick(absoluteStep: -4, secondsSinceStep: 0, bpm: bpm120), 0)
        XCTAssertGreaterThanOrEqual(
            StepTickMath.tick(absoluteStep: -4, secondsSinceStep: 0.05, bpm: bpm120), 0)
    }

    func testAbsurdTempo_doesNotTrapOnTheIntConversion() {
        // `secondsSinceStep * ticksPerSecond` is an unbounded Double. Converting THAT to
        // Int before bounding it would trap; the bound is applied on the Double first.
        let t = StepTickMath.tick(absoluteStep: 0, secondsSinceStep: 1e9, bpm: 300)
        XCTAssertEqual(t, StepTickMath.ticksPerStep - 1)
    }

    // MARK: - The reason the clock exists: it must make the quantizer fire

    func testAStepPositionAlone_wouldNeverTriggerCorrection() {
        // The bug this whole slice prevents, stated as a test. Without interpolation every
        // touch reads as exactly on the grid, and the quantizer correctly does nothing.
        let q = TouchQuantizer(grid: .sixteenth, strength: 1)
        for step in 0...15 {
            let onlyStepResolution = step * StepTickMath.ticksPerStep
            XCTAssertEqual(q.plan(forTick: onlyStepResolution), .play(atTick: onlyStepResolution))
        }
    }

    func testWithInterpolation_aClumsyTouchIsActuallyCorrected() {
        let q = TouchQuantizer(grid: .sixteenth, strength: 1)

        // 100 ms into a 125 ms step at 120 BPM = 96 ticks past the grid point, i.e. much
        // closer to the NEXT one → held back onto it, never moved backwards.
        let early = StepTickMath.tick(absoluteStep: 0, secondsSinceStep: 0.100, bpm: bpm120)
        XCTAssertEqual(early, 96)
        XCTAssertEqual(q.plan(forTick: early), .delay(toTick: 120))

        // 20 ms late — past the 12-tick tolerance → sounds where it landed, echo restores
        // the pulse. (~19 ticks; the ear hears this as sloppy, which is the point.)
        let late = StepTickMath.tick(absoluteStep: 0, secondsSinceStep: 0.020, bpm: bpm120)
        XCTAssertEqual(late, 19)
        XCTAssertEqual(q.plan(forTick: late).echoTick, 120)

        // 5 ms late — inside the tolerance, well under the ~20-30 ms at which two onsets
        // separate. A good player must not be punished with a doubled note.
        let tight = StepTickMath.tick(absoluteStep: 0, secondsSinceStep: 0.005, bpm: bpm120)
        XCTAssertEqual(tight, 5)
        XCTAssertEqual(q.plan(forTick: tight), .play(atTick: 5))
    }
}

@MainActor
final class TransportCurrentTickTests: XCTestCase {

    func testStopped_hasNoGrid() {
        let t = Transport()
        XCTAssertNil(t.currentTick(), "quantizing against a beat the player cannot hear is worse than not quantizing")
        t.play()
        t.tick(step: 5)                       // a real anchor exists now
        XCTAssertNotNil(t.currentTick())
        t.stop()
        XCTAssertNil(t.currentTick())
        XCTAssertEqual(t.lastStepAt, 0, "a stale stamp must not survive a stop")
    }

    func testPlay_doesNotAnchor_untilTheFirstStepActuallyFires() {
        // THE BUG THIS PINS, and it would have broken the feature outright.
        // `PatternEngine.play()` calls `Transport.play()` and then schedules its FIRST
        // `advance()` a whole step later — which relays `tick(step: 0)`, i.e. step 0
        // AGAIN. Stamping in `play()` anchored step 0 at play-time and then re-anchored
        // it 125 ms later, so a touch just before the second stamp read tick 119 and one
        // just after read tick 0: the clock ran BACKWARDS by a full step.
        //
        // `TouchQuantizer` is built entirely on "a live note can never be moved earlier"
        // — two consecutive touches across that boundary would have been scheduled out
        // of order. It is also the wrong instant musically: step 0's notes SOUND at that
        // first `advance()`, not at play-time.
        let t = Transport()
        t.play()
        XCTAssertNil(t.currentTick(), "play() must not anchor a step the sequencer has not reached")
        XCTAssertEqual(t.lastStepAt, 0)

        t.tick(step: 0)
        XCTAssertEqual(t.currentTick(at: t.lastStepAt), 0, "the first real step is the downbeat anchor")
    }

    func testTheComposedClock_neverRunsBackwardsAcrossTheFirstStep() {
        // The pure function is monotone by construction; this asserts the COMPOSED
        // Transport clock is too, which is where the defect actually lived.
        let t = Transport()
        t.setTempo(120)
        t.play()
        XCTAssertNil(t.currentTick(at: t.lastStepAt + 0.124))   // no grid yet — uncorrected
        t.tick(step: 0)
        XCTAssertEqual(t.currentTick(at: t.lastStepAt), 0)
        XCTAssertEqual(t.currentTick(at: t.lastStepAt + 0.124), 119, "saturates, never spills over")
        t.tick(step: 1)
        XCTAssertEqual(t.currentTick(at: t.lastStepAt), 120,
                       "the next step starts ABOVE the highest tick the previous one could reach")
    }

    func testStepPlusElapsed_isTheSongAbsoluteTick() {
        let t = Transport()
        t.setTempo(120)
        t.play()
        t.tick(step: 4)
        // Half a sixteenth past step 4 → 4 * 120 + 60.
        XCTAssertEqual(t.currentTick(at: t.lastStepAt + 0.0625), 540)
    }

    func testBarWrap_keepsTheTickRising() {
        let t = Transport()
        t.setTempo(120)
        t.play()
        for s in 0..<16 { t.tick(step: s) }
        let endOfBarOne = t.currentTick(at: t.lastStepAt)
        t.tick(step: 0)                         // 15 → 0 wraps into bar 1
        let startOfBarTwo = t.currentTick(at: t.lastStepAt)
        XCTAssertEqual(endOfBarOne, 15 * 120)
        XCTAssertEqual(startOfBarTwo, 16 * 120)
    }

    func testSeek_reAnchorsTheStamp() {
        let t = Transport()
        t.play()
        t.tick(step: 3)
        let before = t.lastStepAt
        t.seek(toBar: 2, step: 8)
        XCTAssertGreaterThanOrEqual(t.lastStepAt, before,
                                    "after a jump the interpolation must not still measure from the old position")
        XCTAssertEqual(t.currentTick(at: t.lastStepAt), (2 * 16 + 8) * 120)
    }
}
