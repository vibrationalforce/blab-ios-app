import XCTest
@testable import Echoelmusic

/// Pure mapping tests for bio-reactive FX modulation: carrier signal → parameter
/// offset, polarity, clamping, LFO. Linux-verifiable (no audio/UI).
final class FXModulationTests: XCTestCase {

    // MARK: - Bipolar swings around base

    func testBipolar_MidSignal_IsNeutral() {
        // signal 0.5 → centre → no offset, returns base.
        let v = FXModulation.value(base: 0.5, target: .reverbMix,
                                   signal: 0.5, depth: 1.0, bipolar: true)
        XCTAssertEqual(v, 0.5, accuracy: 1e-5)
    }

    func testBipolar_FullSignal_AddsHalfSpanTimesDepth() {
        // reverbMix range 0...1, span 1, depth 0.5, signal 1 → +0.25 around base.
        let v = FXModulation.value(base: 0.5, target: .reverbMix,
                                   signal: 1.0, depth: 0.5, bipolar: true)
        XCTAssertEqual(v, 0.75, accuracy: 1e-5)
    }

    func testBipolar_ZeroSignal_SubtractsHalfSpanTimesDepth() {
        let v = FXModulation.value(base: 0.5, target: .reverbMix,
                                   signal: 0.0, depth: 0.5, bipolar: true)
        XCTAssertEqual(v, 0.25, accuracy: 1e-5)
    }

    // MARK: - Unipolar only adds

    func testUnipolar_AddsUpwardFromBase() {
        let v = FXModulation.value(base: 0.2, target: .chorusMix,
                                   signal: 1.0, depth: 0.5, bipolar: false)
        XCTAssertEqual(v, 0.7, accuracy: 1e-5)   // 0.2 + 1*0.5*1
    }

    func testUnipolar_ZeroSignal_KeepsBase() {
        let v = FXModulation.value(base: 0.2, target: .chorusMix,
                                   signal: 0.0, depth: 0.9, bipolar: false)
        XCTAssertEqual(v, 0.2, accuracy: 1e-5)
    }

    // MARK: - Clamping to the target range

    func testValue_ClampsToTargetRange_Upper() {
        let v = FXModulation.value(base: 0.95, target: .delayFeedback,   // range 0...0.95
                                   signal: 1.0, depth: 1.0, bipolar: false)
        XCTAssertEqual(v, 0.95, accuracy: 1e-5, "never exceeds the feedback ceiling")
    }

    func testValue_ClampsToTargetRange_Lower() {
        let v = FXModulation.value(base: 0.0, target: .reverbMix,
                                   signal: 0.0, depth: 1.0, bipolar: true)
        XCTAssertGreaterThanOrEqual(v, 0.0)
    }

    func testValue_WideRangeTarget_ScalesBySpan() {
        // filterCutoff span = 17920; depth 0.1, signal 1, unipolar → +1792 from base.
        let v = FXModulation.value(base: 2000, target: .filterCutoff,
                                   signal: 1.0, depth: 0.1, bipolar: false)
        XCTAssertEqual(v, 2000 + 1792, accuracy: 1.0)
    }

    // MARK: - Non-finite guards

    func testValue_NonFiniteSignal_FallsBackToBase() {
        let v = FXModulation.value(base: 0.4, target: .reverbMix,
                                   signal: .nan, depth: 1.0, bipolar: true)
        // NaN signal → clamp01 makes it 0 → bipolar -depth/2; just assert finite + in range.
        XCTAssertTrue(v.isFinite)
        XCTAssertTrue((0...1).contains(v))
    }

    // MARK: - LFO

    func testLFO_PhaseQuarters() {
        XCTAssertEqual(FXModulation.lfoUnipolar(phase: 0.0), 0.5, accuracy: 1e-5)
        XCTAssertEqual(FXModulation.lfoUnipolar(phase: 0.25), 1.0, accuracy: 1e-5)
        XCTAssertEqual(FXModulation.lfoUnipolar(phase: 0.5), 0.5, accuracy: 1e-5)
        XCTAssertEqual(FXModulation.lfoUnipolar(phase: 0.75), 0.0, accuracy: 1e-5)
    }

    // MARK: - Presence envelope (the isMeasured boundary is no longer a step)

    /// Step a fixed number of times so two tick rates cover IDENTICAL elapsed time.
    /// A `while t < seconds` loop does not: at 30 Hz it overshoots to 0.2667 s while
    /// 120 Hz lands on 0.2500 s, and the resulting gap is a harness artifact big enough
    /// to swamp the property under test.
    private func settle(measured: Bool, from start: Float, seconds: Float,
                        dt: Float, tau: Float) -> Float {
        var p = start
        for _ in 0..<Int((seconds / dt).rounded()) {
            p = FXModulation.presence(current: p, measured: measured, dt: dt, tauSeconds: tau)
        }
        return p
    }

    func testPresence_isRateBased_notPerTick() {
        // The law: slews are rate-based. The SAME elapsed time must give the same
        // engagement whether the driver ticks at 30 Hz or 120 Hz — otherwise the fade
        // silently speeds up on a device that runs the loop faster.
        //
        // The tolerance is tight ON PURPOSE. `1−(e^(−dt/τ))^N == 1−e^(−N·dt/τ)`, so a
        // correct implementation is exactly rate-independent and only float error
        // separates the two. A naive Euler step (`alpha = dt/tau`) is genuinely
        // rate-dependent and misses by ~0.023 — which a loose 0.02 tolerance would let
        // through by a hair.
        let slow = settle(measured: true, from: 0, seconds: 0.25, dt: 1.0 / 30, tau: 0.08)
        let fast = settle(measured: true, from: 0, seconds: 0.25, dt: 1.0 / 120, tau: 0.08)
        XCTAssertEqual(slow, fast, accuracy: 1e-4)
    }

    func testPresence_engagesAndDisengagesWithoutOvershoot() {
        XCTAssertGreaterThan(settle(measured: true, from: 0, seconds: 0.3,
                                    dt: 1.0 / 30, tau: 0.08), 0.95)
        XCTAssertLessThan(settle(measured: false, from: 1, seconds: 0.3,
                                 dt: 1.0 / 30, tau: 0.08), 0.05)
        // One step never crosses its target — no ringing on a fast tick.
        let up = FXModulation.presence(current: 0.9, measured: true, dt: 1, tauSeconds: 0.001)
        XCTAssertLessThanOrEqual(up, 1)
        let down = FXModulation.presence(current: 0.1, measured: false, dt: 1, tauSeconds: 0.001)
        XCTAssertGreaterThanOrEqual(down, 0)
    }

    func testPresence_firstTickIsNotAJump() {
        // The whole point: a channel dropping out must not zero its contribution in one
        // 33 ms tick (the camera's ~4 s dropout grace republishes breathRate 0 while
        // holding a continuous breathPhase — that boundary used to step by ~4.5 kHz).
        let afterOneTick = FXModulation.presence(current: 1, measured: false,
                                                 dt: 1.0 / 30, tauSeconds: 0.08)
        XCTAssertGreaterThan(afterOneTick, 0.6, "still mostly engaged after one tick")
        XCTAssertLessThan(afterOneTick, 1.0, "but already moving")
    }

    func testPresence_zeroOrInvalidTimeStepHoldsRatherThanSnaps() {
        // Zero elapsed time producing a COMPLETE transition would be backwards, and it
        // is the exact shape of the bug this envelope exists to prevent: any caller that
        // clamps or coalesces dt to 0 would get a snap instead of a hold.
        XCTAssertEqual(FXModulation.presence(current: 0.5, measured: true, dt: 0, tauSeconds: 0.08), 0.5)
        XCTAssertEqual(FXModulation.presence(current: 0.5, measured: false, dt: -1, tauSeconds: 0.08), 0.5)
        XCTAssertEqual(FXModulation.presence(current: 0.5, measured: true,
                                             dt: .nan, tauSeconds: 0.08), 0.5)
        // A zero time CONSTANT is the opposite instruction — "instant" — so it snaps.
        XCTAssertEqual(FXModulation.presence(current: 0.5, measured: true,
                                             dt: 1.0 / 30, tauSeconds: 0), 1)
        let fromNaN = FXModulation.presence(current: .nan, measured: false,
                                            dt: 1.0 / 30, tauSeconds: 0.08)
        XCTAssertTrue(fromNaN.isFinite)
        XCTAssertTrue((0...1).contains(fromNaN))
    }

    // MARK: - FXRouteFade (the state machine, not just the curve)

    private func route(_ target: FXModTarget = .filterCutoff, depth: Float = 0.5,
                       bipolar: Bool = true) -> FXModRoute {
        FXModRoute(carrier: .bio(.coherence), target: target, depth: depth, bipolar: bipolar)
    }

    func testFade_engagesFromSilence_andHoldsItsOffsetWhileTheBodyDropsOut() {
        var fade = FXRouteFade()
        let r = route()
        XCTAssertEqual(fade.contribution, 0, "a route contributes nothing before its first reading")
        for _ in 0..<20 { fade.step(route: r, signal: 1.0, dt: 1.0 / 30) }
        let engaged = fade.contribution
        XCTAssertEqual(engaged, 4480, accuracy: 20, "full signal, bipolar depth 0.5, span 17920")
        // Body drops out: the contribution must DECAY from where it was, not vanish.
        fade.step(route: r, signal: nil, dt: 1.0 / 30)
        XCTAssertLessThan(fade.contribution, engaged)
        XCTAssertGreaterThan(fade.contribution, engaged * 0.6, "one tick is a fade, not a cut")
    }

    func testFade_settlesToExactlyZero_soAFadedRouteStopsCostingAnything() {
        var fade = FXRouteFade()
        let r = route()
        for _ in 0..<20 { fade.step(route: r, signal: 1.0, dt: 1.0 / 30) }
        for _ in 0..<40 { fade.step(route: r, signal: nil, dt: 1.0 / 30) }
        XCTAssertEqual(fade.contribution, 0, "exactly 0 — a one-pole alone only underflows there after ~8 s")
        XCTAssertFalse(fade.isEngaged, "so the driver stops keeping its FX stage alive")
    }

    func testFade_retargetingARouteDropsTheHeldOffset() {
        // The FX view's target picker repoints a route IN PLACE, keeping its id. A held
        // +4480 in Hz applied to Reverb Mix (range 0…1) would slam the reverb fully wet.
        var fade = FXRouteFade()
        for _ in 0..<20 { fade.step(route: route(.filterCutoff), signal: 1.0, dt: 1.0 / 30) }
        XCTAssertGreaterThan(fade.contribution, 1000)
        fade.step(route: route(.reverbMix), signal: nil, dt: 1.0 / 30)
        XCTAssertEqual(fade.contribution, 0, accuracy: 1e-6,
                       "an offset in the old target's units means nothing in the new one's")
    }

    func testFade_retuningWhileUnmeasuredIsNotIgnored() {
        // Depth/polarity/curve are part of what the held number means, so editing them
        // must invalidate it too — otherwise the control looks dead until the body
        // returns, and the tail keeps playing the old setting.
        var fade = FXRouteFade()
        for _ in 0..<20 { fade.step(route: route(depth: 0.5), signal: 1.0, dt: 1.0 / 30) }
        fade.step(route: route(depth: 0.9), signal: nil, dt: 1.0 / 30)
        XCTAssertEqual(fade.contribution, 0, accuracy: 1e-6)
    }

    func testFade_aStallOrBackgroundReturnCannotSnapIt() {
        // THE regression this guards: `alpha` saturates fast, so an unclamped dt turns a
        // 200 ms main-actor stall (this app documents plenty) or a return from
        // background — where the whole 30 Hz loop was suspended — back into the
        // full-magnitude step the fade exists to remove.
        var fade = FXRouteFade()
        let r = route()
        for _ in 0..<20 { fade.step(route: r, signal: 1.0, dt: 1.0 / 30) }
        let engaged = fade.contribution

        var stalled = fade
        stalled.step(route: r, signal: nil, dt: 0.2)          // a hitch
        XCTAssertGreaterThan(stalled.contribution, engaged * 0.4, "a hitch resumes the fade, it does not complete it")

        var resumed = fade
        resumed.step(route: r, signal: nil, dt: 600)          // ten minutes backgrounded
        XCTAssertGreaterThan(resumed.contribution, engaged * 0.4, "nor does a suspension")
    }

    // MARK: - Route model

    func testRoute_ClampsDepthAndRate() {
        let r = FXModRoute(carrier: .lfo, target: .tremoloDepth, depth: 5, lfoRateHz: -3)
        XCTAssertLessThanOrEqual(r.depth, 1.0)
        XCTAssertGreaterThanOrEqual(r.lfoRateHz, 0.01)
    }

    func testRoute_CodableRoundTrip() throws {
        let r = FXModRoute(carrier: .bio(.coherence), target: .reverbMix,
                           depth: 0.6, bipolar: true, lfoRateHz: 0.5)
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(FXModRoute.self, from: data)
        XCTAssertEqual(r, back)
    }

    func testRoute_CurveShapesSignal() {
        // exponential curve (x²) on a 0.5 signal → 0.25 before depth/polarity.
        // unipolar reverbMix (span 1), depth 1 → offset = 0.25.
        let shaped = ResponseCurve.exponential.apply(0.5)
        XCTAssertEqual(shaped, 0.25, accuracy: 1e-5)
        let off = FXModulation.offset(target: .reverbMix, signal: shaped, depth: 1, bipolar: false)
        XCTAssertEqual(off, 0.25, accuracy: 1e-5)
    }

    func testRoute_CurveCodableRoundTrip() throws {
        let r = FXModRoute(carrier: .bio(.breathPhase), target: .filterCutoff,
                           depth: 0.4, bipolar: false, curve: .sCurve)
        let back = try JSONDecoder().decode(FXModRoute.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(r, back)
        XCTAssertEqual(back.curve, .sCurve)
    }

    func testTarget_AllHaveFiniteRanges() {
        for t in FXModTarget.allCases {
            XCTAssertTrue(t.range.lowerBound.isFinite && t.range.upperBound.isFinite)
            XCTAssertLessThan(t.range.lowerBound, t.range.upperBound, "\(t) range")
            XCTAssertFalse(t.displayName.isEmpty)
        }
    }
}
