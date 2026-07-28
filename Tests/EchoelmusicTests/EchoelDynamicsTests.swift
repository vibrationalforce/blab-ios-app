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

    /// THE GUARD ON `detectorReleaseMs`, and the reason this test exists at all: the first
    /// version of #199 set it to 25 ms and nothing in the suite could see the regression.
    /// `testLimiterScalesSustainedMaterialInsteadOfFlatToppingIt` runs at 200 Hz, where the
    /// ripple is under 0.02 dB for every candidate constant — it is structurally blind here.
    /// The defect lives in the bass, exactly as it did for the compressor sibling (#198),
    /// and it is worse in this stage because `limiterEnabled` defaults to TRUE.
    ///
    /// WHY IT RIPPLES. The detector's envelope droops between the peaks of a low note; the
    /// gain follows that droop and so moves at 2f while multiplying a carrier at f. That is
    /// amplitude modulation, and its sidebands land on the third harmonic. The shorter the
    /// detector's decay, the deeper the droop per half-period.
    ///
    /// Measured, bit-accurate Float32 simulation of this exact code (+12 dBFS sine into a
    /// −0.3 dBFS ceiling, gain spread over the steady-state tail, in dB):
    ///
    ///     detector       30 Hz    40 Hz    60 Hz    80 Hz   120 Hz   200 Hz
    ///     coupled 60 ms  0.2305   0.1376   0.0653   0.0382   0.0177   0.0067
    ///     40 ms (ships)  0.3274   0.1968   0.0942   0.0553   0.0258   0.0097
    ///     25 ms (bug)    0.4857   0.2949   0.1428   0.0843   0.0396   0.0151
    ///
    /// So the bound is per-frequency — a single number cannot work when the quantity itself
    /// spans 34× across the band. Each is the shipped value × 1.30.
    ///
    /// ⚠️ HONEST ABOUT THE MARGIN, because it is thinner than the compressor's: the two
    /// constants are only ~1.5× apart in ripple, so 25 ms overshoots these bounds by just
    /// 14–20%. That is deliberate and must not be loosened — a bound with comfortable
    /// headroom over 25 ms would not reject it at all. What it buys in exchange is that the
    /// SHIPPED value has a full 30% of room, so this cannot fail on a last-ulp `sinf`
    /// difference between toolchains. If a future change genuinely needs a shorter detector,
    /// the numbers above move together and the table is rewritten from a fresh measurement —
    /// never by widening the factor.
    ///
    /// Note the coupled 60 ms row is the QUIETEST of the three. Decoupling the detector cost
    /// ripple; #199 bought recovery time with it (t63 ~128 ms → ~106 ms against a 60 ms
    /// nominal). That trade is the whole content of the constant, and it is why the value is
    /// pinned from both sides rather than minimised.
    func testLimiter_rippleStaysFlatAcrossTheBassRange() {
        let ceilingDb: Float = -0.3
        let bounds: [(hz: Float, maxRipple: Float)] = [
            (30, 0.426), (40, 0.256), (60, 0.123), (80, 0.072), (120, 0.034), (200, 0.013)
        ]
        for (hz, bound) in bounds {
            let lim = EchoelLimiter(sampleRate: sr)
            lim.ceilingDb = ceilingDb
            // PINNED, because the table is release-sensitive and the failure message points
            // at the detector. Measured at 30/40/200 Hz: release 60 ms → 0.327/0.197/0.010,
            // release 30 ms → 0.591/0.364/0.019 — a future retune of the RELEASE default
            // would fail all six here and read as "the detector is drooping", sending the
            // next session at the wrong constant and tempting them to widen bounds the doc
            // says must never be widened. (`attackMs`, `ceilingDb` and the input amplitude
            // are all irrelevant to the spread — only the release is.)
            lim.releaseMs = 60
            let w = 2 * Float.pi * hz / sr
            let amp = powf(10, 12.0 / 20.0)          // +12 dBFS, well into limiting
            let total = Int(sr * 1.5), settle = Int(sr * 1.0)
            var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
            for i in 0..<total {
                _ = lim.processStereo(amp * sinf(w * Float(i)), amp * sinf(w * Float(i)))
                // Settling, not "attack settling" — `attackMs` is 0.5 ms; what takes time is
                // the 60 ms release / 40 ms detector pair, and everything is steady by
                // ~0.2 s. A full second is deliberate slack, not a measured requirement.
                guard i >= settle else { continue }
                let gr = lim.gainReductionDb
                lo = Swift.min(lo, gr); hi = Swift.max(hi, gr)
            }
            // ⛔ WITHOUT THIS LINE THE TEST PASSES ON A DEAD LIMITER. A stage that stopped
            // reducing (gain latched at 1, or `env` stuck at 0) holds `gainReductionDb`
            // constant, so the spread is 0 and all six ripple bounds go green — the
            // permanent-silence class this file exists to catch, passing in the one test
            // that drives deepest into limiting. Measured `hi` is −11.97…−12.29 dB, so −6
            // is a wide floor, not a brittle one. It also closes the vacuous case where
            // `settle >= total` would leave `hi - lo == -inf < bound`.
            XCTAssertLessThan(hi, -6,
                              "\(hz) Hz: limiter never engaged — the ripple bound proves nothing")
            XCTAssertLessThan(hi - lo, bound,
                              "\(hz) Hz: gain ripple \(hi - lo) dB — the detector is drooping "
                              + "between peaks; that ripple IS the third harmonic")
        }
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
