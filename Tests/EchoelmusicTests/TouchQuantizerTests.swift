// TouchQuantizerTests.swift
// Echoel — the boundaries of ULTRASYNC (founder 2026-07-28: "einen Ultrasync … damit das
// Touch Instrument immer perfekt im timing ist auch microtime (somit wird ungeschicktes
// Spielen auch zum ästhetischen Ereignis) sei hier ruhig etwas creativer mit delays etc.").
//
// The gap this closes, stated exactly: `TouchInstrumentView` already quantizes PITCH into
// the take's key — a wrong note is impossible. It does not quantize TIME. So a clumsy touch
// produces a right note at a wrong moment, which is precisely what "ungeschicktes Spielen"
// feels like.
//
// THE ONE PHYSICAL LAW these tests exist to pin: a live note cannot be moved EARLIER. Once
// a finger has landed you may hold the note back, never un-play it. That asymmetry is the
// whole design — early touches are delayed onto the grid, late ones sound where they landed
// and get the pulse restored by an echo on the next grid point. Every "the result is never
// before the input" assertion below is that law, not a style choice.

import XCTest
import Foundation
@testable import Echoelmusic

final class TouchQuantizerTests: XCTestCase {

    private func quantizer(_ grid: TouchQuantizer.Grid,
                           _ strength: Float,
                           echo: Bool = true,
                           tolerance: Int = 12) -> TouchQuantizer {
        TouchQuantizer(grid: grid, strength: strength, echoesLateNotes: echo,
                       latenessToleranceTicks: tolerance)
    }

    // MARK: - Grid geometry

    func testGridSpans_areExactAt480PPQ() {
        XCTAssertEqual(TouchQuantizer.Grid.quarter.tickSpan, 480)
        XCTAssertEqual(TouchQuantizer.Grid.eighth.tickSpan, 240)
        XCTAssertEqual(TouchQuantizer.Grid.sixteenth.tickSpan, 120)
        // Triplets must divide the quarter exactly too, or a quantized run drifts against
        // the bar — three eighth-triplets and six sixteenth-triplets per quarter.
        XCTAssertEqual(TouchQuantizer.Grid.eighthTriplet.tickSpan * 3, 480)
        XCTAssertEqual(TouchQuantizer.Grid.sixteenthTriplet.tickSpan * 6, 480)
    }

    // MARK: - Off means OFF (byte-identical passthrough)

    /// Strength 0 is the "don't touch my playing" setting and must be exactly that: the
    /// same tick back, no echo, no jitter. A quantizer that still nudges at 0 is a lying
    /// control.
    func testStrengthZero_passesEveryTickThroughUnchanged() {
        for tick in [0, 1, 37, 119, 120, 121, 479, 480, 4801] {
            let plan = quantizer(.sixteenth, 0).plan(forTick: tick)
            XCTAssertEqual(plan, .play(atTick: tick), "strength 0 must not move tick \(tick)")
        }
    }

    func testAlreadyOnGrid_isLeftAlone_evenAtFullStrength() {
        for tick in [0, 120, 240, 360, 480, 960] {
            XCTAssertEqual(quantizer(.sixteenth, 1).plan(forTick: tick), .play(atTick: tick))
        }
    }

    // MARK: - Early → delay (the causally possible correction)

    func testEarlyTouch_isDelayedOntoTheGrid_atFullStrength() {
        // 110 sits 10 ticks before the 120 grid point → closer to the NEXT point.
        XCTAssertEqual(quantizer(.sixteenth, 1).plan(forTick: 110), .delay(toTick: 120))
        XCTAssertEqual(quantizer(.eighth, 1).plan(forTick: 235), .delay(toTick: 240))
    }

    func testEarlyTouch_atHalfStrength_movesHalfway() {
        // 100 → next grid 120, gap 20, half strength → +10.
        XCTAssertEqual(quantizer(.sixteenth, 0.5).plan(forTick: 100), .delay(toTick: 110))
    }

    /// A tie — exactly between two grid points — must resolve to the LATER point, i.e. be
    /// treated as early and delayed. Rounding it to the earlier point would demand moving a
    /// note backwards in time, which cannot be done live. The rule needs a test because it
    /// is the one place the function could silently become non-total.
    func testExactMidpoint_resolvesAsEarly_neverBackwards() {
        // 60 is exactly between 0 and 120 on the sixteenth grid.
        XCTAssertEqual(quantizer(.sixteenth, 1).plan(forTick: 60), .delay(toTick: 120))
        XCTAssertEqual(quantizer(.quarter, 1).plan(forTick: 240), .delay(toTick: 480))
    }

    // MARK: - Late → sound now, restore the pulse with an echo

    func testLateTouch_soundsWhereItLanded_andEchoesOnTheNextGridPoint() {
        // 145 is 25 ticks AFTER the 120 grid point — past the 12-tick tolerance, so it is
        // late enough to be a real mistake rather than a human's normal spread.
        XCTAssertEqual(quantizer(.sixteenth, 1).plan(forTick: 145),
                       .playThenEcho(atTick: 145, echoTick: 240, echoVelocityScale: 0.5))
    }

    func testLateTouch_withEchoDisabled_justPlays() {
        XCTAssertEqual(quantizer(.sixteenth, 1, echo: false).plan(forTick: 145),
                       .play(atTick: 145))
    }

    /// THE DEAD ZONE — the assertion this whole parameter exists for. Without it a touch
    /// ONE tick late (~1 ms at 120 BPM, inaudible as a separate event) produced a whole
    /// extra note, while a touch exactly on the tick produced none. Since "late" means
    /// anywhere in the first half of a grid interval, that fired an echo on roughly HALF of
    /// everything played — and the tighter you play, the more of your notes land just late.
    func testSlightlyLateTouch_isLeftAlone_noEcho() {
        for offset in 1...12 {
            XCTAssertEqual(quantizer(.sixteenth, 1).plan(forTick: 120 + offset),
                           .play(atTick: 120 + offset),
                           "\(offset) ticks late is inside human spread — it must not echo")
        }
        // …and one tick past the tolerance it DOES fire, so the parameter is load-bearing
        // rather than decorative.
        XCTAssertNotNil(quantizer(.sixteenth, 1).plan(forTick: 133).echoTick)
    }

    /// The tolerance can never swallow the whole late half of the interval, or the echo
    /// would be unreachable on a fine grid. It is capped at half the grid span.
    func testTolerance_isCappedAtHalfTheGrid() {
        // 1/16T span is 80, so half is 40; a 200-tick tolerance must clamp, not disable.
        let qz = quantizer(.sixteenthTriplet, 1, tolerance: 200)
        XCTAssertEqual(qz.plan(forTick: 39), .play(atTick: 39), "inside the capped tolerance")
        // 41 is past half the span → it is EARLY, not late, so it delays rather than echoes.
        XCTAssertEqual(qz.plan(forTick: 41), .delay(toTick: 80))
    }

    /// `strength` must stay continuous on the LATE branch too. Before the echo carried a
    /// level, strength 0.05 and strength 1.0 produced an identical hard double — a knob that
    /// pulled early notes gently and doubled late ones the instant it left zero.
    func testEchoLevel_scalesWithStrength_soTheKnobIsContinuous() {
        guard case let .playThenEcho(_, _, quiet) = quantizer(.sixteenth, 0.2).plan(forTick: 145),
              case let .playThenEcho(_, _, loud) = quantizer(.sixteenth, 1).plan(forTick: 145)
        else { return XCTFail("both should be late") }
        XCTAssertLessThan(quiet, loud, "a gentler setting must give a gentler echo")
        XCTAssertEqual(quiet, 0.1, accuracy: 1e-6)   // echoLevel 0.5 × strength 0.2
        XCTAssertGreaterThan(quiet, 0, "…but not silence, or the branch is a no-op")
    }

    /// The echo is a musical event, so it must land on a real grid point — never on the
    /// note's own tick (that would be a flam, not a correction) and never in the past.
    func testEcho_alwaysLandsOnAGridPoint_afterTheNote() {
        for tick in stride(from: 133, through: 179, by: 7) {
            guard case let .playThenEcho(at, echo, level) = quantizer(.sixteenth, 1).plan(forTick: tick) else {
                XCTFail("tick \(tick) should be late")
                continue
            }
            XCTAssertEqual(at, tick)
            XCTAssertGreaterThan(echo, tick, "the echo cannot precede or coincide with the note")
            XCTAssertEqual(echo % TouchQuantizer.Grid.sixteenth.tickSpan, 0,
                           "the echo must sit on the grid")
            XCTAssertGreaterThan(level, 0)
            XCTAssertLessThanOrEqual(level, 1, "an echo may never exceed the note that caused it")
        }
    }

    func testEchoTick_isNilForEveryNonEchoAction() {
        XCTAssertNil(quantizer(.sixteenth, 0).plan(forTick: 145).echoTick)
        XCTAssertNil(quantizer(.sixteenth, 1).plan(forTick: 110).echoTick)   // delayed
        XCTAssertNil(quantizer(.sixteenth, 1).plan(forTick: 120).echoTick)   // on grid
        XCTAssertEqual(quantizer(.sixteenth, 1).plan(forTick: 145).echoTick, 240)
    }

    // MARK: - THE LAW: nothing may ever move earlier

    /// Swept across a whole bar, every grid and a range of strengths — no plan may ever
    /// produce a sounding tick before the touch. This is the assertion that would catch a
    /// "round to nearest" refactor, which is the obvious and wrong implementation.
    func testNoPlanEverMovesANoteEarlier() {
        for grid in TouchQuantizer.Grid.allCases {
            for strength in [Float(0), 0.13, 0.5, 0.87, 1] {
                for tick in stride(from: 0, through: 1920, by: 13) {
                    let plan = quantizer(grid, strength).plan(forTick: tick)
                    XCTAssertGreaterThanOrEqual(plan.soundingTick, tick,
                        "grid \(grid) strength \(strength) tick \(tick) moved backwards")
                }
            }
        }
    }

    // MARK: - Microtiming (the "auch microtime" half)

    /// Hard quantization is machine-stiff; the founder asked for micro changes so it "lives
    /// like a real instrument". The offset is seeded, so a take is reproducible.
    func testMicrotiming_variesTheResult_butStaysDeterministic() {
        var qz = quantizer(.sixteenth, 1)
        qz.microtiming = Humanizer(timingTicks: 6, velocityJitter: 0)
        let a = (0..<12).map { qz.plan(forTick: 110, index: $0, seed: 42).soundingTick }
        let b = (0..<12).map { qz.plan(forTick: 110, index: $0, seed: 42).soundingTick }

        XCTAssertEqual(a, b, "same seed and index must give the same feel")
        XCTAssertGreaterThan(Set(a).count, 1, "microtiming must actually vary something")

        // The three assertions above are all satisfied by an implementation that IGNORES
        // `seed` entirely — calling one pure function twice proves only that it is pure.
        // These pin what the doc actually promises: a take is reproducible BY ITS SEED, and
        // the offset stays inside the amount that was asked for.
        let other = (0..<12).map { qz.plan(forTick: 110, index: $0, seed: 43).soundingTick }
        XCTAssertNotEqual(a, other, "a different seed must give a different feel")
        XCTAssertTrue(a.allSatisfy { abs($0 - 120) <= 6 },
                      "microtiming must stay within timingTicks of the grid point: \(a)")
    }

    /// …and it must not smuggle the note backwards past the touch. A ±6-tick jitter on a
    /// note delayed by only 2 ticks would otherwise land 4 ticks BEFORE the finger.
    func testMicrotiming_neverPushesTheNoteBeforeTheTouch() {
        var qz = quantizer(.sixteenth, 1)
        qz.microtiming = Humanizer(timingTicks: 20, velocityJitter: 0)
        for tick in stride(from: 100, through: 140, by: 1) {
            for index in 0..<24 {
                let t = qz.plan(forTick: tick, index: index, seed: 7).soundingTick
                XCTAssertGreaterThanOrEqual(t, tick,
                    "microtiming moved tick \(tick) index \(index) backwards to \(t)")
            }
        }
    }

    func testMicrotiming_isInertWhenTight() {
        var qz = quantizer(.sixteenth, 1)
        qz.microtiming = .tight
        XCTAssertEqual(qz.plan(forTick: 110, index: 3, seed: 9), .delay(toTick: 120))
    }

    // MARK: - Degenerate input (a bad value must disable correction, never trap)

    /// A meaningless strength must read as OFF, not as "some correction": a silently
    /// half-quantized instrument is worse than an unquantized one, because the player
    /// cannot tell which of the two they are fighting.
    func testMeaninglessStrength_readsAsOff() {
        for bad in [Float.nan, .infinity, -.infinity, -1, 0] {
            XCTAssertEqual(TouchQuantizer(grid: .sixteenth, strength: bad,
                                          echoesLateNotes: true).plan(forTick: 110),
                           .play(atTick: 110),
                           "strength \(bad) must disable correction entirely")
        }
    }

    /// …but a strength ABOVE the range is a different case and must CLAMP, not disable.
    /// `+infinity` is nonsense; `2` is a caller who scaled a slider wrong, and silently
    /// switching their quantizer off would be the more confusing answer.
    func testStrengthAboveOne_clampsToFull_ratherThanDisabling() {
        XCTAssertEqual(TouchQuantizer(grid: .sixteenth, strength: 2,
                                      echoesLateNotes: true).plan(forTick: 110),
                       .delay(toTick: 120))
    }

    func testNegativeTick_isPassedThrough_notInvented() {
        // Ticks before the anchor are the caller's business (MIDINoteRecorder drops them);
        // this core must not fabricate a grid position for them.
        XCTAssertEqual(quantizer(.sixteenth, 1).plan(forTick: -5), .play(atTick: -5))
    }

    // MARK: - The action's own accessor

    func testSoundingTick_reportsWhenTheNoteIsHeard_notTheEcho() {
        XCTAssertEqual(TouchQuantizeAction.play(atTick: 130).soundingTick, 130)
        XCTAssertEqual(TouchQuantizeAction.delay(toTick: 120).soundingTick, 120)
        // `echoVelocityScale` is part of the case and must be passed. Asserted at BOTH ends of
        // its range, because the point of `soundingTick` is that neither the echo's position
        // nor its level moves when the note is first heard.
        XCTAssertEqual(TouchQuantizeAction.playThenEcho(atTick: 130, echoTick: 240,
                                                        echoVelocityScale: 0.5).soundingTick, 130)
        XCTAssertEqual(TouchQuantizeAction.playThenEcho(atTick: 130, echoTick: 240,
                                                        echoVelocityScale: 1).soundingTick, 130)
    }
}
