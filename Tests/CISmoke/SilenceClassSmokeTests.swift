// SilenceClassSmokeTests.swift
// Echoel — the invariants whose failure mode is "the app makes no sound and the user
// cannot get it back". They live HERE, in the CISmoke bundle, for one blunt reason:
//
//   THIS IS THE ONLY TEST BUNDLE THAT CAN FAIL THE **XCODE** BUILD.
//
// `project.yml`'s `EchoelmusicTests` target sources exactly one directory —
// `Tests/CISmoke` — so the 300+ files under `Tests/EchoelmusicTests/` run only in the
// NON-BLOCKING `full-tests.yml`. That workflow spent 2026-07-28 reporting "success"
// while its build step failed, because `continue-on-error` sits on the build. Two
// commits claimed "green-verified" tests that had never been executed. Moving the CI
// config is founder-gated (#208); adding a source file to a directory the blocking
// target already compiles is not. So this file is the lever that exists today.
//
// ⚠️ THE SHARP EDGE, because the sentence above is only true of the Xcode path:
// `Package.swift`'s `.testTarget(name: "EchoelmusicTests")` declares NO `path:`, so
// SwiftPM resolves the SAME NAME to `Tests/EchoelmusicTests` — the suite this file calls
// non-blocking. `Tests/CISmoke` belongs to no SwiftPM target at all. `swift test`
// therefore compiles the other suite and NEVER compiles this file, and a break here is
// invisible to every SwiftPM command. One name, two directories. Not corrected here
// because renaming either side is a build-config change; stated so nobody reads a green
// `swift test` as evidence that these invariants ran.
//
// THE CHARTER, and it is deliberately narrow — a bundle that grows into a second copy
// of the suite will be slow, will drift, and will stop being read: ONLY invariants
// whose regression is (a) silent, (b) permanent within a session, and (c) audible as
// SILENCE rather than as a wrong sound. Everything else belongs in the real suite.
//
// ALL FIVE of these are also asserted in `Tests/EchoelmusicTests/` — this file adds no
// new coverage, it relocates existing coverage to where failing has consequences. That
// duplication is the point. Those copies are richer and cannot fail the build; these
// five are the minimum that must never merge red. Every assertion here pins a VALUE,
// never just a predicate that zero also satisfies — the first draft asserted only
// `isFinite` on the filter, and a "sanitize NaN to 0 Hz" fix would have passed it while
// pinning the lowpass shut. When #208's structural half lands and the whole suite
// blocks, delete this file rather than growing it.

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

        // ±inf on a range that does not start at zero. Stated honestly: these two pass
        // under the buggy `min(max(…))` too — infinity compares fine, only NaN does not —
        // so they pin the RANGE behaviour, not the NaN guard. Kept because a bad rPPG
        // frame arrives as either, dropped from the charter claim above.
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

    /// The rate law, driven through the REAL chain rather than a hand-built copy of its
    /// arithmetic. That distinction is the whole value of this test: the regression that
    /// can actually ship is `EchoelFXChain.advanceFilterGlide` caching its coefficient
    /// against an ASSUMED 256 frames "for speed", which a test computing its own
    /// `stepRateHz` would never see. 20 blocks of 240 frames and 5 blocks of 960 are both
    /// exactly 0.1 s at 48 kHz and must land on the same value — with a fixed coefficient
    /// they cannot, because the block COUNTS differ.
    ///
    /// Silence-class because the failure is not merely "wrong speed": the same arithmetic
    /// is one divide-by-zero away from feeding a NaN coefficient into the recursive filter
    /// the test above protects.
    func testAGlideTakesTheSameWallClockTimeAtAnyBufferSize() {
        func landing(frames: Int, blocks: Int) -> Float {
            let fx = EchoelFXChain(sampleRate: 48000)
            fx.filterEnabled = true          // snaps the mirror to the 2000 Hz default
            fx.filterCutoff = 8000
            var left = [Float](repeating: 0, count: frames)
            var right = [Float](repeating: 0, count: frames)
            for _ in 0..<blocks {
                fx.processBuffer(left: &left, right: &right, frameCount: frames)
            }
            return fx.filterL.cutoff
        }
        let small = landing(frames: 240, blocks: 20)
        XCTAssertEqual(small, landing(frames: 960, blocks: 5), accuracy: 0.05,
                       "0.1 s is 0.1 s — the host's buffer size must not change the glide")
        // …and the absolute value, so "both wrong in the same direction" cannot pass:
        // 8000 − 6000·e^(−0.1/0.05) by construction.
        XCTAssertEqual(small, 7187.988, accuracy: 0.05, "0.1 s of a 50 ms one-pole")

        // Degenerate rates must yield "instant" (1), never a frozen or NaN coefficient.
        // The NEGATIVE case is the load-bearing one: without the input guard it clamps to
        // 0 — a parameter that never reaches its target at all — whereas 0 and NaN both
        // happen to fall out as 1 from the formula and the `isFinite` backstop, so those
        // two cannot detect the guard's removal. Keeping them anyway costs nothing;
        // relying on them would have been the `?? true` sentinel in a new dress.
        XCTAssertEqual(ParamGlide.coefficient(tauSeconds: 0.05, stepRateHz: -100), 1,
                       "a negative rate must not clamp to 0 and freeze the parameter")
        XCTAssertEqual(ParamGlide.coefficient(tauSeconds: -0.05, stepRateHz: 100), 1)
        XCTAssertEqual(ParamGlide.coefficient(tauSeconds: 0.05, stepRateHz: 0), 1)
        XCTAssertEqual(ParamGlide.coefficient(tauSeconds: .nan, stepRateHz: 100), 1)
    }

    /// End to end on the real chain: a NaN written to the tone-filter TARGET — one bad
    /// frame away, since a 30 Hz bio driver writes that field — must reach neither the
    /// filter's cutoff/resonance inputs nor the output samples. (The derived `g`/`k`
    /// coefficients are private and cannot be asserted; the inputs they are solved from
    /// are the reachable proxy.) Both paths in are exercised: the control-plane snap and
    /// a rendered block.
    ///
    /// ⚠️ The assertions pin the HELD VALUE, not just finiteness, and that is the point.
    /// A plausible future "hardening" — `filterL.cutoff = c.isFinite ? c : 0` — sanitizes
    /// the NaN away and pins the lowpass shut at 0 Hz: permanent silence, every sample
    /// finite, an `isFinite`-only test green. Holding the LAST GOOD value is the contract.
    func testANaNFilterTargetHoldsTheLastGoodValue_andEmitsNoNaNSamples() {
        let fx = EchoelFXChain(sampleRate: 48000)
        fx.filterEnabled = true                 // snaps the mirror to the 2000 Hz / 0.3 default
        fx.filterCutoff = .nan
        fx.filterResonance = .nan
        fx.snapFilterToTarget()
        XCTAssertEqual(fx.filterL.cutoff, 2000, "a snap must HOLD, not sanitize to zero")
        XCTAssertEqual(fx.filterL.resonance, 0.3, accuracy: 1e-6)

        var left = [Float](repeating: 0.25, count: 128)
        var right = [Float](repeating: 0.25, count: 128)
        fx.processBuffer(left: &left, right: &right, frameCount: 128)
        XCTAssertEqual(fx.filterL.cutoff, 2000, "…and so must a rendered block")
        // The whole chain runs here, not just the filter — saturation, chorus and the
        // limiter are on by default — so this also catches a NaN escaping any of those.
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
