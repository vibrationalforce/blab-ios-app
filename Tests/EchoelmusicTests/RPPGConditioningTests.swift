// RPPGConditioningTests.swift
// Pure unit tests for RPPGConditioning — no AVFoundation, runs on Linux CI.

import XCTest
@testable import Echoelmusic

final class RPPGConditioningTests: XCTestCase {

    // Deterministic pseudo-noise in [-1, 1] (no Date/random — reproducible on every run).
    private func pseudoNoise(_ i: Int) -> Float {
        let s = sin(Double(i) * 127.1 + 311.7) * 43758.5453
        let frac = s - s.rounded(.down)          // 0..1
        return Float(frac * 2.0 - 1.0)           // -1..1
    }

    /// Synthetic rPPG window: 66-bpm sine (small AC) + 0.3 linear ramp + small noise,
    /// sampled at a 0.02 s step. Amplitudes chosen so the ramp swamps the raw AC (device
    /// reality: cardiac AC ≪ DC drift), which the detrend then rescues.
    private func makeWindow(count: Int = 450) -> [Float] {
        let dt = 0.02
        let freq = 1.1                            // 66 bpm
        let sineAmp = 0.03
        let rampRise = 0.3
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let sine = sineAmp * sin(2.0 * Double.pi * freq * Double(i) * dt)
            let ramp = rampRise * Double(i) / Double(count - 1)
            let noise = 0.005 * Double(pseudoNoise(i))
            out[i] = Float(sine + ramp + noise)
        }
        return out
    }

    // MARK: - acfProminence: raw vs detrended

    func testACFProminence_rawWeakDetrendedStrong_andLagMapsTo66BPM() {
        let dt = 0.02
        let window = makeWindow()

        // Lag band: 200 bpm → lag 15, 40 bpm → lag 75 (period/dt). 66 bpm → lag ≈ 45.
        let minLag = 15
        let maxLag = 75

        let raw = RPPGConditioning.acfProminence(window, minLag: minLag, maxLag: maxLag)
        let detrended = RPPGConditioning.acfProminence(
            RPPGConditioning.linearDetrend(window), minLag: minLag, maxLag: maxLag)

        // Raw: the 0.3 ramp dominates → smooth ACF → low prominence.
        XCTAssertLessThan(raw.score, 0.2, "raw prominence should be swamped by the DC ramp")

        // Detrended: cardiac sine dominates → sharp peak → high prominence.
        XCTAssertGreaterThan(detrended.score, 0.5, "detrended prominence should reveal the pulse")

        // Detrended lag maps back to ~66 bpm.
        XCTAssertGreaterThan(detrended.lag, 0)
        let bpm = 60.0 / (Double(detrended.lag) * dt)
        XCTAssertEqual(bpm, 66.0, accuracy: 3.0, "detrended peak lag should map to 66 bpm ±3")
    }

    // MARK: - perfusionIsMotion

    func testPerfusionIsMotion_highPerfusionOrPeriodic_notMotion() {
        // High perfusion (0.3/0.7 ≈ 0.43) AND periodic → keep.
        XCTAssertFalse(RPPGConditioning.perfusionIsMotion(amplitude: 0.3, dc: 0.7, autoStrength: 0.6))
    }

    func testPerfusionIsMotion_lowPerfusionAndAperiodic_isMotion() {
        // Low perfusion (0.002/0.7 ≈ 0.003) AND aperiodic → discard.
        XCTAssertTrue(RPPGConditioning.perfusionIsMotion(amplitude: 0.002, dc: 0.7, autoStrength: 0.05))
    }

    func testPerfusionIsMotion_lowPerfusionButPeriodic_neverDiscarded() {
        // Weak AC but a STRONG periodicity is the real pulse → must NOT be discarded.
        XCTAssertFalse(RPPGConditioning.perfusionIsMotion(amplitude: 0.002, dc: 0.7, autoStrength: 0.9))
    }

    func testPerfusionIsMotion_zeroDC_noCrashGuarded() {
        // dc = 0 must not divide-by-zero; 0/epsilon = 0 (low) + aperiodic → motion.
        XCTAssertTrue(RPPGConditioning.perfusionIsMotion(amplitude: 0, dc: 0, autoStrength: 0))
    }

    // MARK: - linearDetrend edge cases

    func testLinearDetrend_pureRamp_isApproximatelyZero() {
        // A perfect straight line detrends to ~0 at every sample.
        let ramp = (0..<128).map { Float(0.3) * Float($0) / Float(127) }
        let out = RPPGConditioning.linearDetrend(ramp)
        XCTAssertEqual(out.count, ramp.count)
        let maxAbs = out.map { abs($0) }.max() ?? 0
        XCTAssertLessThan(maxAbs, 1e-4, "pure ramp should detrend to ~0")
    }

    func testLinearDetrend_empty_returnsEmpty() {
        XCTAssertTrue(RPPGConditioning.linearDetrend([]).isEmpty)
    }

    func testLinearDetrend_singleSample_returnsZero() {
        XCTAssertEqual(RPPGConditioning.linearDetrend([0.9]), [0])
    }

    func testLinearDetrend_removesOffsetAndSlope() {
        // y = 5 + 2i + a small centered bump; detrended keeps the bump, drops line.
        var s = [Float]()
        for i in 0..<64 { s.append(Float(5.0 + 2.0 * Double(i))) }
        s[32] += 1.0
        let out = RPPGConditioning.linearDetrend(s)
        // Endpoints (pure line) land near zero; the bump survives near the middle.
        XCTAssertLessThan(abs(out[0]), 0.2)
        XCTAssertLessThan(abs(out[63]), 0.2)
        XCTAssertGreaterThan(out[32], 0.5)
    }

    // MARK: - acfProminence edge cases

    func testACFProminence_empty_returnsZero() {
        let r = RPPGConditioning.acfProminence([], minLag: 1, maxLag: 5)
        XCTAssertEqual(r.lag, 0)
        XCTAssertEqual(r.score, 0)
    }

    func testACFProminence_tooShort_returnsZero() {
        let r = RPPGConditioning.acfProminence([1, 2, 3], minLag: 1, maxLag: 2)
        XCTAssertEqual(r.lag, 0)
        XCTAssertEqual(r.score, 0)
    }

    func testACFProminence_flatSignal_returnsZero() {
        // Zero-energy after Hann windowing (constant → still non-zero energy), so use
        // an all-zero window to exercise the energy guard.
        let r = RPPGConditioning.acfProminence([Float](repeating: 0, count: 64),
                                               minLag: 5, maxLag: 20)
        XCTAssertEqual(r.lag, 0)
        XCTAssertEqual(r.score, 0)
    }

    func testACFProminence_invalidLagRange_returnsZero() {
        // maxLag < minLag after clamping → no valid band.
        let window = makeWindow(count: 64)
        let r = RPPGConditioning.acfProminence(window, minLag: 40, maxLag: 10)
        XCTAssertEqual(r.lag, 0)
        XCTAssertEqual(r.score, 0)
    }
}
