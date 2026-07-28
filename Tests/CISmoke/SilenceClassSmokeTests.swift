// SilenceClassSmokeTests.swift
// Echoel — the invariants whose failure mode is "the app makes no sound and the user
// cannot get it back". They live HERE, in the CISmoke bundle, for one blunt reason:
//
//   THIS IS THE ONLY TEST BUNDLE THAT CAN FAIL THE BUILD.
//
// `project.yml`'s `EchoelmusicTests` target sources exactly one directory —
// `Tests/CISmoke` — so the 300+ files under `Tests/EchoelmusicTests/` run only in the
// NON-BLOCKING `full-tests.yml`. That workflow spent 2026-07-28 reporting "success"
// while its build step failed, because `continue-on-error` sits on the build. Two
// commits claimed "green-verified" tests that had never been executed. Moving the CI
// config is founder-gated (#208); adding a source file to a directory the blocking
// target already compiles is not. So this file is the lever that exists today.
//
// THE CHARTER, and it is deliberately narrow — a bundle that grows into a second copy
// of the suite will be slow, will drift, and will stop being read: ONLY invariants
// whose regression is (a) silent, (b) permanent within a session, and (c) audible as
// SILENCE rather than as a wrong sound. Everything else belongs in the real suite.
//
// Yes, three of these are also asserted in `Tests/EchoelmusicTests/` — that duplication
// is the point, not an oversight. Those copies are richer and cannot fail the build;
// these four are the minimum that must never merge red. When #208's structural half
// lands and the whole suite blocks, delete this file rather than growing it.

import XCTest
@testable import Echoelmusic

final class SilenceClassSmokeTests: XCTestCase {

    /// A NaN must not survive a clamp. `Comparable.clamped(to:)` is `min(max(…))`, and
    /// every comparison with NaN is false, so a NaN passes straight through — and one NaN
    /// on a gain or a frequency poisons oscillator/filter state for the rest of the
    /// session. This repo has SHIPPED that bug; `FloatingPointClamp.swift` is the fix, and
    /// it only works if overload resolution keeps choosing the FloatingPoint member over
    /// the generic Comparable one. That resolution is invisible at the call site, which is
    /// exactly why it is pinned rather than trusted.
    func testNaNCannotSurviveAClamp() {
        let clamped = Float.nan.clamped(to: 0...1)
        XCTAssertFalse(clamped.isNaN, "a NaN clamp must not return a NaN")
        XCTAssertEqual(clamped, 0, "NaN maps to the lower bound — finite and in range")

        // The bio path's real shape: a bad rPPG frame arriving as ±inf, on a range that
        // does not start at zero.
        XCTAssertEqual(Float.infinity.clamped(to: 20...200), 200)
        XCTAssertEqual((-Float.infinity).clamped(to: 20...200), 20)
    }

    /// A non-finite TARGET must be held, never propagated. `ParamGlide` feeds recursive
    /// structures — the FX tone filter, a delay read tap — where a NaN that reaches the
    /// STATE does not decay out: it is silence for the rest of the session, not a glitch.
    /// (Downstream guards exist in places — `EchoelSVFilter` substitutes 1 kHz for a
    /// non-finite cutoff — but the guard here is the one that keeps the value itself
    /// meaningful rather than merely non-fatal.) Both entry points are checked: the
    /// per-block `advance` and the `snap` used by every document-level edge.
    func testAGlideHoldsANonFiniteTargetInsteadOfPropagatingIt() {
        var glide = ParamGlide(2000)
        glide.advance(toward: .nan, coefficient: 0.1)
        XCTAssertEqual(glide.value, 2000, "a NaN target is ignored, not chased")
        glide.advance(toward: .infinity, coefficient: 0.1)
        XCTAssertEqual(glide.value, 2000, "…and so is an infinite one")
        glide.snap(to: .nan)
        XCTAssertEqual(glide.value, 2000, "snap has the same guard as advance")
    }

    /// The rate law. A glide coefficient derived from an ASSUMED buffer size makes the
    /// glide's wall-clock duration scale with whatever the host hands us — and the user
    /// never chose the audio session's I/O size. 20 blocks of 240 frames and 5 blocks of
    /// 960 are both exactly 0.1 s at 48 kHz and must land on the same value.
    ///
    /// Silence-class because the failure is not merely "wrong speed": a coefficient
    /// computed from a zero or non-finite rate returns 1 ("instant") at best, and the
    /// arithmetic that produced it is one divide-by-zero away from feeding NaN into the
    /// same recursive filters as the test above.
    func testAGlideTakesTheSameWallClockTimeAtAnyBufferSize() {
        func landing(frames: Int, blocks: Int) -> Float {
            let c = ParamGlide.coefficient(tauSeconds: ParamGlide.bioTau,
                                           stepRateHz: 48000 / Float(frames))
            var glide = ParamGlide(2000)
            for _ in 0..<blocks { glide.advance(toward: 8000, coefficient: c) }
            return glide.value
        }
        XCTAssertEqual(landing(frames: 240, blocks: 20),
                       landing(frames: 960, blocks: 5), accuracy: 0.05,
                       "0.1 s is 0.1 s — the host's buffer size must not change the glide")

        // Degenerate rates must yield "instant", never a NaN coefficient.
        XCTAssertEqual(ParamGlide.coefficient(tauSeconds: 0.05, stepRateHz: 0), 1)
        XCTAssertEqual(ParamGlide.coefficient(tauSeconds: .nan, stepRateHz: 100), 1)
    }

    /// End to end on the real chain: a NaN written to the tone-filter TARGET — one bad
    /// frame away, since a 30 Hz bio driver writes that field — must reach neither the
    /// state-variable filter's coefficients nor the output samples. Both paths into the
    /// filter are exercised: the control-plane snap and a rendered block.
    func testANaNFilterTargetProducesNeitherNaNCoefficientsNorNaNSamples() {
        let fx = EchoelFXChain(sampleRate: 48000)
        fx.filterEnabled = true
        fx.filterCutoff = .nan
        fx.filterResonance = .nan
        fx.snapFilterToTarget()
        XCTAssertTrue(fx.filterL.cutoff.isFinite, "a NaN must not reach the SVF via a snap")
        XCTAssertTrue(fx.filterL.resonance.isFinite)

        var left = [Float](repeating: 0.25, count: 128)
        var right = [Float](repeating: 0.25, count: 128)
        fx.processBuffer(left: &left, right: &right, frameCount: 128)
        XCTAssertTrue(fx.filterL.cutoff.isFinite, "…nor via a rendered block")
        XCTAssertTrue(left.allSatisfy { $0.isFinite }, "and no sample may come out NaN")
        XCTAssertTrue(right.allSatisfy { $0.isFinite })
    }

    #if canImport(Accelerate)
    /// The polyphony makeup divides by √N. It must never reach zero or go negative at any
    /// voice count — that is not "quiet", it is a voice that cannot be brought back
    /// without restarting the session. The floor is the guard; this pins that the floor
    /// is actually reached rather than merely declared.
    func testThePolyphonyMakeupNeverCollapsesToSilence() {
        for n in [0, -5, 1, 4, 12, 64, 1000] {
            let g = EchoelPolyDDSP.polyMakeupTarget(voiceCount: n)
            XCTAssertGreaterThanOrEqual(g, 0.22, "\(n) voices: makeup fell through the floor")
            XCTAssertTrue(g.isFinite, "\(n) voices: makeup is not finite")
        }
    }
    #else
    /// Deliberately a FAILURE, not a silent omission. `EchoelPolyDDSP` sits behind
    /// `canImport(Accelerate)`, which is always true on the iOS simulator this bundle
    /// builds for. If this ever compiles, the bundle has moved somewhere the invariant
    /// above no longer covers — and a quietly-absent test is the exact failure this whole
    /// file exists to stop. Fix the coverage; do not delete the guard.
    func testThePolyphonyMakeupNeverCollapsesToSilence() {
        XCTFail("Accelerate is unavailable here, so the poly-makeup floor is UNCHECKED")
    }
    #endif
}
