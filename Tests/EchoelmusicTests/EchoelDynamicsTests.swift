// EchoelDynamicsTests.swift
// Echoelmusic — dynamics (compressor + brick-wall limiter).

import XCTest
@testable import Echoelmusic

final class EchoelDynamicsTests: XCTestCase {

    private let sr: Float = 48000

    // MARK: - Limiter

    func testLimiterNeverExceedsCeiling() {
        let lim = EchoelLimiter(sampleRate: sr)
        lim.ceilingDb = -6 // ~0.5012 linear
        let ceiling = powf(10.0, -6.0 / 20.0)
        var maxOut: Float = 0
        for i in 0..<4000 {
            let x = 4.0 * sinf(Float(i) * 0.1) // way over the ceiling
            let (l, r) = lim.processStereo(x, x)
            maxOut = Swift.max(maxOut, Swift.max(abs(l), abs(r)))
        }
        XCTAssertLessThanOrEqual(maxOut, ceiling * 1.001)
    }

    func testLimiterTransparentBelowCeiling() {
        let lim = EchoelLimiter(sampleRate: sr)
        lim.ceilingDb = -0.3 // ~0.966 linear
        for i in 0..<2000 {
            let x = 0.1 * sinf(Float(i) * 0.1) // well below ceiling
            let (l, _) = lim.processStereo(x, x)
            XCTAssertEqual(l, x, accuracy: 1e-5)
        }
    }

    /// THE FALSIFYING TEST for the 2026-07-27 crackle fix (#194). Both the old and the
    /// new limiter satisfy `testLimiterNeverExceedsCeiling` — a hard clipper does too, and
    /// that is exactly why that test did not catch the bug. What separates them is the
    /// SHAPE of what comes out on sustained over-ceiling material:
    ///
    /// · a hard clipper (`g = ceiling/peak` with no ballistics) flat-tops the waveform, so
    ///   the output tends toward a square wave — crest factor → ~1.07 at 4× overdrive;
    /// · a limiter with a real attack SCALES it, so the sine stays a sine — crest ≈ √2.
    ///
    /// The crest floor of 1.30 sits well clear of both. The flat-topping is what folded
    /// back as inharmonic aliasing at 48 kHz (un-oversampled) — the "gritty / like CPU
    /// overload in Ableton" texture, not a click.
    func testLimiterScalesSustainedMaterialInsteadOfFlatToppingIt() {
        let lim = EchoelLimiter(sampleRate: sr)
        lim.ceilingDb = -0.3
        let ceiling = powf(10.0, -0.3 / 20.0)

        let omega: Float = 2 * .pi * 200 / sr      // 200 Hz, period 240 samples
        let total = 48_000, window = 4_800         // measure the last 20 cycles only
        var peakOut: Float = 0, sumSq: Float = 0
        var minGain: Float = .greatestFiniteMagnitude, maxGain: Float = 0

        for i in 0..<total {
            let x = 4.0 * sinf(Float(i) * omega)   // ~12 dB over the ceiling
            let (l, _) = lim.processStereo(x, x)
            guard i >= total - window else { continue }
            peakOut = Swift.max(peakOut, abs(l))
            sumSq += l * l
            if abs(x) > 0.5 {                      // implied gain, away from zero crossings
                let g = l / x
                minGain = Swift.min(minGain, g); maxGain = Swift.max(maxGain, g)
            }
        }

        let rms = sqrtf(sumSq / Float(window))
        XCTAssertGreaterThan(rms, 0, "limiter went silent on sustained material")
        XCTAssertGreaterThan(peakOut / rms, 1.30, "output is flat-topped, not scaled")
        XCTAssertLessThanOrEqual(peakOut, ceiling * 1.001)

        // The gain is a CONTINUOUS signal, not a per-sample step train. The old version's
        // gain swung the full 0.24…1.0 every cycle (spread ~0.76) — multiplying audio by a
        // discontinuous gain IS the distortion. With ballistics it barely moves.
        XCTAssertLessThan(maxGain - minGain, 0.05, "gain is still stepping per sample")
    }

    /// "Fail to resting, never to silence": once loud material stops, the gain must come
    /// back. A limiter that sticks down is the permanent-silence class of bug.
    func testLimiterReleasesBackToUnityAfterLoudMaterial() {
        let lim = EchoelLimiter(sampleRate: sr)
        lim.ceilingDb = -0.3
        for i in 0..<4_800 { _ = lim.processStereo(4.0 * sinf(Float(i) * 0.1), 0) }
        XCTAssertLessThan(lim.gainReductionDb, -6, "limiter never engaged on loud input")

        var last: Float = 0
        let quiet: Float = 0.05
        for _ in 0..<48_000 { last = lim.processStereo(quiet, quiet).0 }   // 1 s of quiet
        XCTAssertEqual(last, quiet, accuracy: 1e-4)
        XCTAssertEqual(lim.gainReductionDb, 0, accuracy: 0.05)
    }

    /// A NaN sample must not poison the smoother's state. NaN fails every comparison, so
    /// it takes the release branch with `target = 1` and leaves `gain` untouched — the
    /// next finite sample is processed as if nothing happened. (An `inf` is a different
    /// case and is stopped UPSTREAM by `AudioOutputGuard`; see its file doc.)
    func testLimiterNaNDoesNotPoisonGainState() {
        let lim = EchoelLimiter(sampleRate: sr)
        lim.ceilingDb = -0.3
        let (l, _) = lim.processStereo(Float.nan, 0)
        XCTAssertTrue(l.isNaN)                                  // passes through, unclean
        XCTAssertTrue(lim.gainReductionDb.isFinite)             // state does not
        XCTAssertEqual(lim.processStereo(0.5, 0.5).0, 0.5, accuracy: 1e-6)
    }

    // MARK: - Compressor

    func testCompressorTransparentBelowThreshold() {
        let comp = EchoelCompressor(sampleRate: sr)
        comp.thresholdDb = -18; comp.ratio = 4; comp.makeupDb = 0
        for i in 0..<2000 {
            let x = 0.01 * sinf(Float(i) * 0.1) // -40 dBFS, below knee
            let (l, _) = comp.processStereo(x, x)
            XCTAssertEqual(l, x, accuracy: 1e-6)
        }
    }

    func testCompressorReducesLevelAboveThreshold() {
        let comp = EchoelCompressor(sampleRate: sr)
        comp.thresholdDb = -24; comp.ratio = 4; comp.makeupDb = 0
        comp.attackMs = 5; comp.releaseMs = 120

        var inSum: Float = 0, outSum: Float = 0
        let total = 8000
        for i in 0..<total {
            let x = 1.0 * sinf(Float(i) * 0.1) // 0 dBFS peaks
            let (l, _) = comp.processStereo(x, x)
            if i >= total - 2000 { inSum += x * x; outSum += l * l }
        }
        let inRMS = sqrtf(inSum / 2000)
        let outRMS = sqrtf(outSum / 2000)
        XCTAssertLessThan(outRMS, inRMS * 0.6)            // clear reduction
        XCTAssertLessThan(comp.gainReductionDb, -1.0)     // actively compressing
    }

    func testCompressorOutputIsFinite() {
        let comp = EchoelCompressor(sampleRate: sr)
        comp.thresholdDb = -30; comp.ratio = 20; comp.makeupDb = 6
        for i in 0..<20_000 {
            let x = (i % 2 == 0 ? 1.0 : -1.0) as Float
            let (l, r) = comp.processStereo(x, x)
            XCTAssertTrue(l.isFinite && r.isFinite)
        }
    }
}
