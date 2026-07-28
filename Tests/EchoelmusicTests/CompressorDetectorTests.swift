#if canImport(AVFoundation)
// CompressorDetectorTests.swift
// Echoelmusic — the compressor's detector must follow the ENVELOPE, not the waveform (#198)
//
// THE DEFECT. `EchoelCompressor.processStereo` fed the raw sample magnitude
// `max(|inL|, |inR|)` straight into the log and the gain computer. On any periodic signal
// that magnitude collapses to zero twice per cycle, so the gain computer's target collapses
// with it and the ballistics' RELEASE branch walks the gain back up between peaks. The gain
// therefore ripples at twice the signal frequency — and a gain that moves at 2f while
// multiplying a carrier at f is amplitude modulation, whose sidebands land on the THIRD
// harmonic. The compressor manufactures distortion out of a clean sine.
//
// It gets worse the LOWER the note (the ripple roughly halves per octave up: 0.332 dB at
// 30 Hz, 0.249 at 40, 0.166 at 60, 0.083 at 120), which is exactly the "bass sounds
// hard/growly" signature and exactly the range `SubBassVoice` occupies.
//
// THE FIX is a peak-envelope detector like `EchoelLimiter`'s (#194) — but decaying at a
// FIXED 40 ms rather than at `releaseMs`. Coupling it to `releaseMs` cascades two one-poles
// at the same time constant and the stage then hangs onto reduction long after the peak that
// caused it. Measured (bit-accurate Float32 simulation of this exact code):
//
//     detector    ripple 30 Hz   ripple 40 Hz   H3 @40 Hz   GR at +100 ms   t63
//     raw             0.332          0.249       −41.7 dBc     −1.48 dB    ~120 ms
//     40 ms           0.076          0.044       −56.2 dBc     −6.16 dB    ~145 ms
//     releaseMs       0.029          0.017       −65.1 dBc     −9.73 dB    ~210 ms
//
// The +100 ms column is measured after a 5 ms 0 dBFS transient into a body at −20 dBFS —
// 2 dB UNDER the threshold, so it must be let go. Its reference value is −2.08 dB (a
// ripple-free detector with these same ballistics), NOT −12·e^(−100/120): a 5 ms transient
// into a 10 ms attack only ever reaches −4.40 dB, so nothing decays from −12. Against −2.08
// the raw detector is the closest of the three here — this change is not fixing a
// release-accuracy problem, it is fixing the ripple and the third harmonic, and only the
// cascade (−9.73 dB) is pinned below as a failure.
//
// ⚠️ THIS CHANGES THE SOUND, deliberately, and in two sizes. Sustained material compresses
// ~0.6 dB harder (which is why `testCompressor_stillCompresses` pins a band, not a value).
// The larger half is post-transient: a held peak keeps driving the gain computer after the
// sound is gone, so on that 5 ms transient the deepest reduction is −9.20 dB arriving 18 ms
// AFTER it ended, against −3.40 dB DURING it with the raw detector. On percussive material
// that late duck is the audible change, and it is what a device listen must check.

import XCTest
@testable import Echoelmusic

final class CompressorDetectorTests: XCTestCase {

    private let sr: Float = 48000

    /// Drives a mono sine through the compressor and returns the gain reduction over the
    /// STEADY-STATE tail (the first second is the attack settling and must not be measured).
    private func gainReductionTail(hz: Float, peakDb: Float, seconds: Float = 1.5) -> [Float] {
        let comp = EchoelCompressor(sampleRate: sr)
        let n = Int(sr * seconds)
        let amp = powf(10, peakDb / 20)
        let w = 2 * Float.pi * hz / sr
        var tail: [Float] = []
        tail.reserveCapacity(n / 3)
        let settle = Int(sr * 1.0)
        for i in 0..<n {
            let x = amp * sinf(w * Float(i))
            _ = comp.processStereo(x, x)
            if i >= settle { tail.append(comp.gainReductionDb) }
        }
        return tail
    }

    private func ripple(_ v: [Float]) -> Float {
        guard let lo = v.min(), let hi = v.max() else { return .infinity }
        return hi - lo
    }

    /// THE REGRESSION THIS FILE EXISTS FOR. With the raw-sample detector this measures
    /// 0.249 dB and fails; with the 40 ms peak envelope it measures 0.044 dB.
    ///
    /// The bound is 0.08 dB — 3.1× under the defect and 1.8× over the fixed value, so it
    /// cannot pass by accident and has real headroom. Nothing here is stochastic, so the
    /// margins are exact rather than statistical.
    func testCompressor_lowFrequencySine_gainDoesNotRippleAtTwiceTheSignalRate() {
        let r = ripple(gainReductionTail(hz: 40, peakDb: -6))
        XCTAssertLessThan(r, 0.08,
                          "40 Hz: gain ripple \(r) dB — the detector is following the waveform, "
                          + "not its envelope; that ripple IS the third harmonic")
    }

    /// The defect scales with period, so the test does too. A fix that only helped at one
    /// frequency (a fixed smoothing constant tuned to 40 Hz, say) would pass the case above
    /// and fail here at 30 Hz.
    ///
    /// Honest about the margins, since they are not uniform: measured after the fix the
    /// ripple is 0.076 dB at 30 Hz, 0.044 at 40, 0.021 at 60, 0.012 at 80, 0.006 at 120,
    /// against a defect of 0.332 / 0.249 / 0.166 / 0.125 / 0.083. So the 0.12 dB bound is a
    /// comfortable 22× at 120 Hz but only 1.6× at 30 Hz — the bottom of the range is where a
    /// change to the detector constant would show first, which is deliberate rather than an
    /// oversight to be loosened away. 60 ms is where 30 Hz starts to have real room; that is
    /// the top of the usable band for the constant.
    func testCompressor_rippleStaysFlatAcrossTheBassRange() {
        for hz in [Float(30), 40, 60, 80, 120] {
            let r = ripple(gainReductionTail(hz: hz, peakDb: -6))
            XCTAssertLessThan(r, 0.12, "\(hz) Hz: gain ripple \(r) dB")
        }
    }

    /// THE OTHER HALF OF THE FIX, and the one a well-meaning simplification would undo:
    /// decaying the envelope at `releaseMs` looks tidier and breaks this.
    ///
    /// A 5 ms transient at 0 dBFS, then a body at −20 dBFS — 2 dB BELOW the threshold, so the
    /// stage must let it go. The reference is a ripple-free detector with these same
    /// ballistics: −2.08 dB at +100 ms. Measured:
    ///
    ///   · raw detector           −1.48 dB   (closest here — the ripple, not this, is why it
    ///                                        is the defect; see the ripple tests above)
    ///   · envelope at 40 ms      −6.16 dB   ✓ deeper than ideal, the price of a held peak
    ///   · envelope at releaseMs  −9.73 dB   ✗ two cascaded one-poles at the same time
    ///                                         constant; audibly ducks every note body
    ///
    /// ONLY the cascade is asserted against. There is deliberately no lower bound: a
    /// genuinely better detector (a decoupled one at 5–15 ms) lands between −2.5 and −3.9 dB,
    /// and a bound tight enough to reject the raw detector's −1.48 would reject those too —
    /// it would pin the amount of HOLD rather than the defect. The ripple tests are what
    /// reject the raw detector, and they do it with a 3–4× margin.
    func testCompressor_detectorDoesNotCascadeWithTheBallistics() {
        let comp = EchoelCompressor(sampleRate: sr)
        let w = 2 * Float.pi * 200 / sr
        let transientSamples = Int(sr * 0.005)
        for i in 0..<transientSamples {
            let x = sinf(w * Float(i))                       // 0 dBFS
            _ = comp.processStereo(x, x)
        }
        let bodyAmp = powf(10, -20.0 / 20)                   // 2 dB under the threshold
        var grAt100ms: Float = 0
        let bodySamples = Int(sr * 0.100)
        for i in 0..<bodySamples {
            let x = bodyAmp * sinf(w * Float(transientSamples + i))
            _ = comp.processStereo(x, x)
            grAt100ms = comp.gainReductionDb
        }
        XCTAssertGreaterThan(grAt100ms, -8.0,
                             "GR \(grAt100ms) dB 100 ms after the transient, against a ripple-free "
                             + "reference of −2.08 dB — the detector is almost certainly decaying "
                             + "at releaseMs and cascading with the ballistics")
    }

    /// The cheapest way to pass every ripple assertion above is to stop compressing. Pin
    /// that shut: a −6 dBFS peak against a −18 dB threshold at 3:1 must still land near
    /// −8 dB of reduction. The band is wide (−6…−10) precisely because the envelope
    /// detector legitimately compresses ~0.6 dB harder than the raw one did.
    func testCompressor_stillCompresses() {
        let tail = gainReductionTail(hz: 40, peakDb: -6)
        let mean = tail.reduce(0, +) / Float(tail.count)
        XCTAssertLessThan(mean, -6.0, "mean gain reduction \(mean) dB — barely compressing")
        XCTAssertGreaterThan(mean, -10.0, "mean gain reduction \(mean) dB — over-compressing")
    }

    /// Below the threshold nothing may be reduced at all — a detector that holds peaks must
    /// not turn into a detector that invents them.
    func testCompressor_belowThreshold_isTransparent() {
        let tail = gainReductionTail(hz: 40, peakDb: -30)
        XCTAssertEqual(ripple(tail), 0, accuracy: 1e-5)
        XCTAssertEqual(tail.last ?? -1, 0, accuracy: 1e-4,
                       "a −30 dBFS signal is 12 dB under the threshold — no reduction")
    }

    /// The envelope adds STATE, and state is what survives a bad frame and poisons the next
    /// take. A non-finite sample must leave the detector intact: the compressor keeps
    /// working on the finite samples that follow, at the same reduction as before.
    func testCompressor_nonFiniteSample_doesNotPoisonTheDetector() {
        let comp = EchoelCompressor(sampleRate: sr)
        let amp = powf(10, -6.0 / 20)
        let w = 2 * Float.pi * 40 / sr
        for i in 0..<Int(sr) { _ = comp.processStereo(amp * sinf(w * Float(i)), amp * sinf(w * Float(i))) }
        let before = comp.gainReductionDb

        _ = comp.processStereo(.nan, 0)
        _ = comp.processStereo(0, .infinity)
        XCTAssertTrue(comp.gainReductionDb.isFinite, "one bad frame poisoned the gain state")
        XCTAssertEqual(comp.gainReductionDb, before, accuracy: 1e-5,
                       "a bad frame must HOLD the state, not advance it")

        // And it recovers: the next finite samples produce finite output.
        let (l, r) = comp.processStereo(amp, amp)
        XCTAssertTrue(l.isFinite && r.isFinite, "detector did not recover after a bad frame")
    }

    /// An absurd `releaseMs` must not be able to latch the stage. Past ~700 s,
    /// `1 - expf(-1/t)` rounds to exactly 0 in Float and `grState` could never move back
    /// toward 0 again — permanent attenuation, the "fail to resting, never to silence" law.
    /// Nothing writes `releaseMs` today (no preset field, no UI row), so this guards a future
    /// control rather than a live path — which is precisely when a guard is cheap to add and
    /// expensive to retrofit. The clamp in `coeff(forMs:)` is what keeps recovery possible.
    func testCompressor_absurdReleaseTime_stillRecovers() {
        let comp = EchoelCompressor(sampleRate: sr)
        comp.releaseMs = 1_000_000
        let w = 2 * Float.pi * 200 / sr
        for i in 0..<Int(sr / 10) { _ = comp.processStereo(sinf(w * Float(i)), sinf(w * Float(i))) }
        let loud = comp.gainReductionDb
        XCTAssertLessThan(loud, -1.0, "expected the loud passage to be compressed")

        for _ in 0..<Int(sr * 60) { _ = comp.processStereo(0, 0) }
        XCTAssertGreaterThan(comp.gainReductionDb, loud + 0.01,
                             "gain reduction never moved off \(loud) dB — the release coefficient "
                             + "underflowed to zero and the stage is latched")
    }
}
#endif
