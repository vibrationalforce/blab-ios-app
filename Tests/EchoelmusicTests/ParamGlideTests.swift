// ParamGlideTests.swift
// The one-pole parameter glide that lets the FX chain stop stepping its parameters
// at control rate (#138). Pure arithmetic → Linux-verifiable, no audio, no device.

import XCTest
@testable import Echoelmusic

final class ParamGlideTests: XCTestCase {

    /// Step for an EXACT number of steps, and report the wall-clock time it covered.
    /// Deriving the count from `seconds * rateHz` and rounding is a trap: 0.05 s at
    /// 187.5 Hz is 9.375 steps, which truncates to 9 and covers 0.048 s — so two rates
    /// silently glide for different durations and the comparison measures the harness
    /// rather than the property.
    private func glide(from start: Float, to target: Float,
                       steps: Int, rateHz: Float, tau: Float) -> Float {
        var g = ParamGlide(start)
        let c = ParamGlide.coefficient(tauSeconds: tau, stepRateHz: rateHz)
        for _ in 0..<steps { g.advance(toward: target, coefficient: c) }
        return g.value
    }

    func testGlide_isRateBased_blockRateMatchesSampleRate() {
        // The law: slews are rate-based. The intended caller is BLOCK-rate, because
        // gliding the filter per sample runs `tanf` on every sample the glide is moving
        // — ~3000 of them per glide instead of ~10 — for no audible gain. So the same
        // glide must land in the same place at either rate, or the sound would depend on
        // whatever buffer size the host happens to hand us.
        //
        // Both arms cover exactly 0.05 s. The tolerance is tight ON PURPOSE: the
        // recurrence has the closed form v = T + (v₀−T)·e^(−t/τ), in which the rate
        // cancels completely, so a correct implementation differs only by float error
        // (~0.1 Hz here). A loose tolerance would pass a genuinely rate-dependent form.
        let perBlock  = glide(from: 200, to: 8000, steps: 10, rateHz: 200, tau: 0.05)
        let perSample = glide(from: 200, to: 8000, steps: 2400, rateHz: 48000, tau: 0.05)
        XCTAssertEqual(perBlock, perSample, accuracy: 0.5)

        // And both must match the ANALYTIC answer, not merely each other — two loops
        // sharing one wrong coefficient would agree perfectly.
        let expected: Float = 8000 - 7800 * expf(-0.05 / 0.05)
        XCTAssertEqual(perBlock, expected, accuracy: 0.5)
    }

    func testGlide_settlesExactly_ratherThanStallingShort() {
        // Not a CPU argument — a Float32 one-pole does stop on its own once the
        // increment rounds away. What it would stop AT is the problem: with an
        // absolute-only threshold a cutoff heading for 8 kHz parks a fraction short and
        // stays there, because an absolute 1e-4 is unreachable at that magnitude.
        var g = ParamGlide(200)
        let c = ParamGlide.coefficient(tauSeconds: ParamGlide.bioTau, stepRateHz: 187.5)
        for _ in 0..<400 { g.advance(toward: 8000, coefficient: c) }
        XCTAssertEqual(g.value, 8000, "exactly, not asymptotically close")
    }

    func testGlide_neverOvershoots_inEitherDirection() {
        var up = ParamGlide(0)
        up.advance(toward: 1, coefficient: 1)
        XCTAssertLessThanOrEqual(up.value, 1)
        var down = ParamGlide(1)
        down.advance(toward: 0, coefficient: 1)
        XCTAssertGreaterThanOrEqual(down.value, 0)
    }

    func testGlide_movesTowardTheTargetOnTheFirstStep_notInstantly() {
        // The whole point: one control-rate write must become a ramp, not a step.
        var g = ParamGlide(200)
        let c = ParamGlide.coefficient(tauSeconds: ParamGlide.bioTau, stepRateHz: 187.5)
        g.advance(toward: 8000, coefficient: c)
        XCTAssertGreaterThan(g.value, 200, "it moved")
        XCTAssertLessThan(g.value, 1500, "but nowhere near arriving — that is the declick")
    }

    func testBioTau_isStillMovingWhenTheNextBioValueArrives() {
        // The property that makes bioTau the right number rather than merely a small
        // one: bio carriers land a new value about every 100 ms, and the glide must
        // still be in motion at that point so consecutive steps overlap into a single
        // contour instead of resolving into ten separate ramps a second. A much shorter
        // constant declicks but leaves the staircase.
        let after100ms = glide(from: 0, to: 1, steps: 19, rateHz: 187.5, tau: ParamGlide.bioTau)
        XCTAssertGreaterThan(after100ms, 0.75, "well underway")
        XCTAssertLessThan(after100ms, 0.95, "but not finished — that overlap is the point")
    }

    func testCoefficient_degradesToInstantOnNonsenseTiming() {
        // A zero/negative/non-finite tau or rate means "no glide", not a divide-by-zero
        // or a NaN coefficient that would poison a recursive filter downstream.
        for c in [ParamGlide.coefficient(tauSeconds: 0, stepRateHz: 187.5),
                  ParamGlide.coefficient(tauSeconds: -1, stepRateHz: 187.5),
                  ParamGlide.coefficient(tauSeconds: .nan, stepRateHz: 187.5),
                  ParamGlide.coefficient(tauSeconds: 0.02, stepRateHz: 0),
                  ParamGlide.coefficient(tauSeconds: 0.02, stepRateHz: .infinity)] {
            XCTAssertTrue(c.isFinite)
            XCTAssertTrue((0...1).contains(c))
        }
        XCTAssertEqual(ParamGlide.coefficient(tauSeconds: 0, stepRateHz: 187.5), 1)
    }

    func testGlide_nonFiniteTargetIsIgnored_notPropagated() {
        // Holding the last good value is the only safe answer. Stated precisely, because
        // the same claim was overstated in three places: today's one consumer
        // (`EchoelFXChain`'s tone filter) substitutes 1 kHz for a non-finite cutoff itself,
        // so this guard is what keeps the value MEANINGFUL rather than what prevents
        // silence there — and it is what a future consumer with no such substitute, feeding
        // recursive state a NaN cannot decay out of, will depend on.
        var g = ParamGlide(2000)
        g.advance(toward: .nan, coefficient: 0.5)
        XCTAssertEqual(g.value, 2000)
        g.advance(toward: .infinity, coefficient: 0.5)
        XCTAssertEqual(g.value, 2000)
        g.snap(to: .nan)
        XCTAssertEqual(g.value, 2000)
        XCTAssertEqual(ParamGlide(.nan).value, 0, "a non-finite seed cannot start it poisoned either")
    }

    func testSnap_bypassesTheGlideEntirely() {
        var g = ParamGlide(200)
        g.snap(to: 8000)
        XCTAssertEqual(g.value, 8000, "loading a document must not sweep the filter up")
    }

    func testGlide_epsilonIsIgnoredWhenNonsense() {
        // `Swift.max(.nan, x)` returns NaN — argument order decides, per the house rule
        // — and a NaN threshold makes every comparison false, so the glide would never
        // settle. The one input that was not validated.
        var g = ParamGlide(200)
        let c = ParamGlide.coefficient(tauSeconds: ParamGlide.bioTau, stepRateHz: 187.5)
        for _ in 0..<400 { g.advance(toward: 8000, coefficient: c, epsilon: .nan) }
        XCTAssertEqual(g.value, 8000)
    }

    func testGlide_largeAndSmallRangedParametersBothSettle() {
        // Cutoff lives in Hz up to 18 000; the mixes live in 0…1. A purely absolute
        // epsilon would never be reached in Float at the top of the Hz range, and a
        // purely relative one would never settle at a target of 0.
        var hz = ParamGlide(80)
        var mix = ParamGlide(1)
        let c = ParamGlide.coefficient(tauSeconds: ParamGlide.bioTau, stepRateHz: 187.5)
        for _ in 0..<400 {
            hz.advance(toward: 18000, coefficient: c)
            mix.advance(toward: 0, coefficient: c)
        }
        XCTAssertEqual(hz.value, 18000)
        XCTAssertEqual(mix.value, 0)
    }
}
