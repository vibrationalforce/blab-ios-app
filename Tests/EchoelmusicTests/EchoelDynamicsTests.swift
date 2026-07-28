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

    /// THE FALSIFYING TEST for the 2026-07-27 crackle fix (#194) — and the ONE assertion
    /// that discriminates is the gain-spread one at the bottom, not the crest factor.
    ///
    /// The first version of this test asserted `crest > 1.30` and called that the falsifier.
    /// It was not: the OLD limiter measures **1.358** here and would have gone green. The
    /// reasoning behind 1.30 was wrong in a specific way worth recording, because it is the
    /// obvious mistake to make again. "Hard clipper ⇒ square wave ⇒ crest → 1.07" describes
    /// a UNITY-GAIN clipper. The old code was not that: its release ballistic had already
    /// scaled the whole waveform to ~0.24, so `peak * g > ceiling` fired only above
    /// |sin| ≈ 0.965 — **16.7% of samples**, the tips. That flat-tops the peaks and aliases
    /// audibly (measured 3rd harmonic −31.2 dBc, vs −73.4 dBc for the version below), but
    /// it leaves the RMS of a mostly-intact sine. Crest simply cannot see it.
    ///
    /// What DOES separate them is how still the gain sits — which is the actual defect,
    /// since a gain that jumps per sample is itself the distortion:
    ///
    ///     old  gain spread over one cycle:  0.0262
    ///     new  gain spread over one cycle:  0.000185   (141× smaller)
    ///
    /// The 0.005 threshold sits 5× under the bug and 27× over the fix. The crest assertion
    /// is KEPT but only as a sanity floor (it catches a limiter that has gone to silence or
    /// to DC); it is not what proves the fix, and it must not be tightened toward 1.4 —
    /// 1.4138 measured leaves under 9% headroom, and the bug lives inside that band.
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
        // Sanity floor only — see the doc. Measures 1.4138; the OLD version measures 1.358,
        // so this cannot discriminate and must not be read as the proof.
        XCTAssertGreaterThan(peakOut / rms, 1.30, "output collapsed toward DC or silence")
        XCTAssertLessThanOrEqual(peakOut, ceiling * 1.001)

        // ⬇ THIS is the falsifying assertion. The gain must be a near-still signal, because
        // a gain that moves per sample is itself the distortion. Old: 0.0262. New: 0.000185.
        XCTAssertLessThan(maxGain - minGain, 0.005, "gain is still stepping per cycle")
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

    /// A NaN sample must not poison the smoother's state. The `peak.isFinite` guard bails
    /// before any state is touched, so the next finite sample is processed as if nothing
    /// happened. (An earlier version of this comment claimed NaN "takes the release branch
    /// with target = 1" — it does not reach a branch at all. Same observable behaviour,
    /// wrong reason on the record, so it is corrected rather than left as folklore.)
    ///
    /// The sample itself still leaves as NaN. That is deliberate: `AudioOutputGuard` sweeps
    /// non-finite samples at the source-node output, which is the stage DOWNSTREAM of this
    /// whole FX chain (`PolySynthVoice` runs `fxChain.processBuffer` and only then
    /// `copySilencingNonFinite`). Zeroing here would duplicate that and would make the
    /// limiter stop being a pure gain computer.
    func testLimiterNaNDoesNotPoisonGainState() {
        let lim = EchoelLimiter(sampleRate: sr)
        lim.ceilingDb = -0.3
        let (l, _) = lim.processStereo(Float.nan, 0)
        XCTAssertTrue(l.isNaN)                                  // passes through, unclean
        XCTAssertTrue(lim.gainReductionDb.isFinite)             // state does not
        XCTAssertEqual(lim.processStereo(0.5, 0.5).0, 0.5, accuracy: 1e-6)
    }

    /// A NaN in the RIGHT channel must hold the state exactly like a NaN in the left one.
    ///
    /// This is the falsifier for a guard I got wrong first time: `guard peak.isFinite` on
    /// `Swift.max(abs(inL), abs(inR))` cannot see a right-channel NaN, because
    /// `Swift.max(x, y)` is `y >= x ? y : x` and `NaN >= x` is false — the max returns the
    /// finite LEFT channel. So the old guard let a half-valid frame run a full
    /// envelope+ballistics update. Not a silence bug (the state stayed finite, and the NaN
    /// sample leaves the stage either way by design), which is why the assertion below is
    /// about the state ADVANCING, not about NaN reaching the output.
    ///
    /// Why this falsifies (derived, not measured — there is no local toolchain): with the
    /// pre-fix guard, `(0, NaN)` is processed as a legitimate silent frame. `env` decays at
    /// the release rate and the gain walks back toward unity. Solving the one-pole with
    /// τ = 2880 samples (60 ms at 48 kHz) over 4000 samples: `env` only falls below the
    /// ceiling at n ≈ 2880·ln(2/0.96605) ≈ 2096, so the gain first rises as 0.483·cosh(t)
    /// and only then relaxes toward 1 — landing at g ≈ 0.80, i.e. **≈62%** of the way back,
    /// and `gainReductionDb` −6.32 → ≈ −1.9 dB. (My first note here said ≈75%; that is the
    /// upper bound you get by assuming `target == 1` for all 4000 samples, which is not
    /// true for the first ~2100 of them. The conclusion is unaffected — ≈4.4 dB against a
    /// 1e-6 tolerance — but an upper bound must not be written down as the value.)
    func testLimiterRightChannelNaNHoldsStateLikeLeft() {
        let lim = EchoelLimiter(sampleRate: sr)
        lim.ceilingDb = -0.3
        lim.releaseMs = 60
        // Feed material ABOVE the ceiling (0.966 lin) — 0.9 would not reduce at all.
        for _ in 0..<4000 { _ = lim.processStereo(2.0, 2.0) }
        let reduced = lim.gainReductionDb
        XCTAssertLessThan(reduced, -1, "setup failed: limiter is not reducing")

        for _ in 0..<4000 { _ = lim.processStereo(0, Float.nan) }
        XCTAssertEqual(lim.gainReductionDb, reduced, accuracy: 1e-6,
                       "a right-channel NaN advanced the limiter's state")
        XCTAssertTrue(lim.gainReductionDb.isFinite)
    }

    /// The compressor half of the same guard, with its own falsifier.
    ///
    /// `EchoelCompressor.processStereo` got the identical `peak.isFinite` →
    /// `inL.isFinite, inR.isFinite` change, but the existing compressor NaN test only feeds
    /// `(NaN, 0)` — a LEFT-channel NaN, which the old guard already caught. So nothing in
    /// the suite would have noticed the compressor guard regressing. This closes that.
    func testCompressorRightChannelNaNHoldsStateLikeLeft() {
        let comp = EchoelCompressor(sampleRate: sr)
        comp.thresholdDb = -18; comp.ratio = 4; comp.makeupDb = 0
        comp.attackMs = 5; comp.releaseMs = 120
        for _ in 0..<8000 { _ = comp.processStereo(0.9, 0.9) }   // well above threshold
        let reduced = comp.gainReductionDb
        XCTAssertLessThan(reduced, -1, "setup failed: compressor is not reducing")

        for _ in 0..<8000 { _ = comp.processStereo(0, Float.nan) }
        XCTAssertEqual(comp.gainReductionDb, reduced, accuracy: 1e-6,
                       "a right-channel NaN advanced the compressor's state")
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

    /// The compressor had the same NaN state-poisoning the limiter was hardened against,
    /// and unlike the limiter's it was REACHABLE as permanent silence: `Swift.max(peak, 1e-7)`
    /// does not filter NaN, so one bad sample wrote `grState = NaN` and every later sample
    /// returned NaN until a `reset()` that nothing calls. It sits immediately before the
    /// limiter in `EchoelFXChain`, so the limiter's guard could not catch it — the NaN was
    /// manufactured downstream of it.
    func testCompressorNaNDoesNotPoisonGainState() {
        let comp = EchoelCompressor(sampleRate: sr)
        comp.thresholdDb = -24; comp.ratio = 4; comp.makeupDb = 0
        for i in 0..<2000 { _ = comp.processStereo(0.9 * sinf(Float(i) * 0.1), 0) }
        let engaged = comp.gainReductionDb
        XCTAssertLessThan(engaged, -0.5, "compressor never engaged — test proves nothing")

        XCTAssertTrue(comp.processStereo(Float.nan, 0).0.isNaN)   // sample passes through
        XCTAssertEqual(comp.gainReductionDb, engaged, accuracy: 1e-6)   // state untouched

        // The falsifier: BEFORE the fix every subsequent sample was NaN forever.
        for i in 0..<200 {
            let (l, r) = comp.processStereo(0.9 * sinf(Float(i) * 0.1), 0)
            XCTAssertTrue(l.isFinite && r.isFinite, "compressor poisoned at sample \(i)")
        }
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
