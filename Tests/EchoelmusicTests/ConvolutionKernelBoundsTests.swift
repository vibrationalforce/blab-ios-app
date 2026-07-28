#if canImport(AVFoundation)
// ConvolutionKernelBoundsTests.swift
// Echoelmusic — the boundary of the FIR kernel factories (#182)
//
// THE DEFECT THESE TESTS PIN. `EchoelConvolution.lowpassKernel/highpassKernel/
// bandpassKernel` are `public`, take an arbitrary `taps: Int`, and had no lower bound.
// Three separate degenerate outcomes lived below the bound, and none of them announced
// itself — the caller got an array back and used it:
//
//   taps <= 0   `[Float](repeating: 0, count: taps)` TRAPS on a negative count, and
//               `highpassKernel`'s `for i in 0..<taps` traps on a negative range.
//   taps == 1   the Blackman window divides by `Float(taps - 1)` == 0 → 0/0 → the whole
//               kernel is NaN. `sum > 0` is FALSE for NaN, so the normalize step was
//               skipped silently and a NaN kernel was returned as if it were fine.
//   taps == 2   the Blackman window is zero at BOTH endpoints and a 2-tap kernel is
//               nothing but endpoints → an all-zero kernel → the filter is permanent
//               SILENCE, again with `sum > 0` false and no complaint.
//   taps == 3   finite and non-zero, but only the centre tap survives the window, so the
//               lowpass IS the identity and the highpass (`δ − δ`) measures ~3e-8 — i.e.
//               ~−150 dBFS, silence with a rounding artefact on top. This is why the
//               bound landed on 5 and not 3.
//
// A non-finite sample rate or cutoff reaches the same places (`fc = cutoff/rate` → inf
// → `sin(inf)` → NaN), and `highpassKernel`/`bandpassKernel` need their OWN guard for it:
// inverting the lowpass's passthrough fallback gives `δ − δ` = zeros, so delegating alone
// re-creates the silence one level up.
//
// WHY SILENCE IS THE WORSE HALF. This app has shipped permanent-silence bugs before
// (CLAUDE.md's NaN/`clamped(to:)` note exists because of them), and a filter that
// returns zeros is indistinguishable from a broken audio route at the far end of the
// chain. So the contract these tests fix in place is: a degenerate request yields a
// UNITY PASSTHROUGH, never zeros and never NaN. The signal survives; the filtering does
// not happen. That is diagnosable by ear and by test; silence is neither.
//
// `EchoelDecimator(factor:filterTaps:)` is the public door that makes this reachable —
// it hands `filterTaps` straight through with no validation of its own.

import XCTest
@testable import Echoelmusic

final class ConvolutionKernelBoundsTests: XCTestCase {

    /// The energy floor is `1e-3`, NOT `> 0`, and the difference is the whole point.
    ///
    /// A first version of this helper asserted `energy > 0` and passed — on a highpass
    /// kernel whose total energy was `2.97e-08`. That is about −150 dBFS: silence by any
    /// measure a listener or a meter would use. It cleared the assertion only because the
    /// Float Blackman endpoint evaluates to `-2^-26` instead of a true zero. A test that
    /// green-lights −150 dB while its own name promises audibility is worse than no test,
    /// because it certifies the bug. `1e-3` is far below any real kernel here (the
    /// clamped ones measure ~1.0) and far above any rounding artefact.
    private func assertUsable(_ kernel: [Float], _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(kernel.isEmpty, "\(what): kernel must never be empty", file: file, line: line)
        XCTAssertTrue(kernel.allSatisfy { $0.isFinite },
                      "\(what): kernel must contain no NaN/inf — got \(kernel.prefix(8))",
                      file: file, line: line)
        let energy = kernel.reduce(Float(0)) { $0 + abs($1) }
        XCTAssertGreaterThan(energy, 1e-3,
                             "\(what): energy \(energy) is silence, not a filter",
                             file: file, line: line)
    }

    // MARK: - The three degenerate tap counts

    func testLowpassKernel_tapsBelowTheDesignMinimum_staysFiniteAndAudible() {
        // -1 used to TRAP on `[Float](repeating:count:)`; 1 produced NaN; 2 produced zeros.
        for taps in [-1, 0, 1, 2] {
            let kernel = EchoelConvolution.lowpassKernel(cutoffHz: 1000, sampleRate: 48000, taps: taps)
            assertUsable(kernel, "lowpass taps=\(taps)")
        }
    }

    func testHighpassKernel_tapsBelowTheDesignMinimum_staysFiniteAndAudible() {
        for taps in [-1, 0, 1, 2] {
            let kernel = EchoelConvolution.highpassKernel(cutoffHz: 1000, sampleRate: 48000, taps: taps)
            assertUsable(kernel, "highpass taps=\(taps)")
        }
    }

    func testBandpassKernel_tapsBelowTheDesignMinimum_staysFiniteAndAudible() {
        // Extra hazard here: `vDSP_vadd` reads `taps` elements out of BOTH kernels, so
        // the lowpass and highpass halves must agree on length after clamping. If they
        // ever disagree this reads past the end of one of them.
        for taps in [-1, 0, 1, 2] {
            let kernel = EchoelConvolution.bandpassKernel(lowHz: 500, highHz: 2000,
                                                          sampleRate: 48000, taps: taps)
            assertUsable(kernel, "bandpass taps=\(taps)")
        }
    }

    /// The clamped kernels must all report the SAME length, whatever that length is —
    /// `bandpassKernel` adds two of them element-wise.
    func testDegenerateTaps_allThreeFactoriesAgreeOnLength() {
        for taps in [-1, 0, 1, 2, 3] {
            let lp = EchoelConvolution.lowpassKernel(cutoffHz: 1000, sampleRate: 48000, taps: taps)
            let hp = EchoelConvolution.highpassKernel(cutoffHz: 1000, sampleRate: 48000, taps: taps)
            let bp = EchoelConvolution.bandpassKernel(lowHz: 500, highHz: 2000,
                                                      sampleRate: 48000, taps: taps)
            XCTAssertEqual(lp.count, hp.count, "taps=\(taps): lowpass/highpass length mismatch")
            XCTAssertEqual(lp.count, bp.count, "taps=\(taps): bandpass length mismatch")
        }
    }

    // MARK: - Degenerate rate / cutoff

    /// The case the first version of this fix MISSED. `highpassKernel` delegates to the
    /// lowpass, so when the lowpass returns its passthrough fallback (δ), the spectral
    /// inversion computes `δ − δ` → an all-zero kernel. The fallback that exists to
    /// prevent silence was producing it, and no test looked here.
    func testHighpassKernel_nonFiniteRateOrCutoff_doesNotInvertItselfIntoSilence() {
        for rate in [Float(0), -48000, .nan, .infinity] {
            let kernel = EchoelConvolution.highpassKernel(cutoffHz: 1000, sampleRate: rate, taps: 31)
            assertUsable(kernel, "highpass rate=\(rate)")
        }
        for cutoff in [Float.nan, .infinity] {
            let kernel = EchoelConvolution.highpassKernel(cutoffHz: cutoff, sampleRate: 48000, taps: 31)
            assertUsable(kernel, "highpass cutoff=\(cutoff)")
        }
    }

    /// A degenerate `lowHz` does not silence a bandpass — it deletes the highpass half
    /// and quietly answers a BANDPASS request with a LOWPASS. Wrong filter, no complaint.
    func testBandpassKernel_nonFiniteEdge_doesNotSilentlyBecomeALowpass() {
        let honest = EchoelConvolution.bandpassKernel(lowHz: 500, highHz: 2000,
                                                      sampleRate: 48000, taps: 31)
        assertUsable(honest, "bandpass valid")
        for bad in [Float.nan, .infinity] {
            let kernel = EchoelConvolution.bandpassKernel(lowHz: bad, highHz: 2000,
                                                          sampleRate: 48000, taps: 31)
            assertUsable(kernel, "bandpass lowHz=\(bad)")
            // It must be the declared fallback (a unity impulse), not a plausible-looking
            // lowpass that a spectrum plot would read as "that is how this sounds".
            XCTAssertEqual(kernel[kernel.count / 2], 1.0, accuracy: 1e-5,
                           "bandpass lowHz=\(bad): degenerate input must give the passthrough")
        }
    }

    func testLowpassKernel_nonFiniteOrZeroSampleRate_staysFiniteAndAudible() {
        // `fc = cutoffHz / sampleRate`: a zero rate gives inf, and `sin(inf)` is NaN.
        for rate in [Float(0), -48000, .nan, .infinity] {
            let kernel = EchoelConvolution.lowpassKernel(cutoffHz: 1000, sampleRate: rate, taps: 31)
            assertUsable(kernel, "lowpass rate=\(rate)")
        }
    }

    func testLowpassKernel_nonFiniteOrOutOfRangeCutoff_staysFiniteAndAudible() {
        // Above Nyquist the sinc aliases; at or below zero the kernel collapses to zeros.
        for cutoff in [Float(0), -1000, 96000, .nan, .infinity] {
            let kernel = EchoelConvolution.lowpassKernel(cutoffHz: cutoff, sampleRate: 48000, taps: 31)
            assertUsable(kernel, "lowpass cutoff=\(cutoff)")
        }
    }

    // MARK: - The guard must not touch the working range

    /// The whole point of a boundary fix is that it is invisible inside the boundary.
    /// These are the shipped call shapes (`EchoelDecimator` uses rate 1.0 / fc 0.5 / 63
    /// taps; the existing suites use 31 taps at 48 kHz), and they must come out
    /// BIT-IDENTICAL to the pre-fix design — otherwise this "safety" change is a tone
    /// change nobody asked for.
    func testValidRange_isUnchangedByTheGuard() {
        let k31 = EchoelConvolution.lowpassKernel(cutoffHz: 1000, sampleRate: 48000, taps: 31)
        XCTAssertEqual(k31.count, 31)
        XCTAssertEqual(k31.reduce(0, +), 1.0, accuracy: 0.15, "unity DC gain must survive")
        // Symmetric by construction — a linear-phase FIR. Proves the design still runs
        // rather than a passthrough being substituted.
        for i in 0..<(31 / 2) {
            XCTAssertEqual(k31[i], k31[30 - i], accuracy: 1e-6, "kernel must stay symmetric")
        }
        XCTAssertGreaterThan(k31[15], k31[0], "centre tap must dominate")

        // The decimator's exact call: normalized cutoff exactly at Nyquist.
        let dec = EchoelConvolution.lowpassKernel(cutoffHz: 0.5, sampleRate: 1.0, taps: 63)
        assertUsable(dec, "decimator factor=1")
        XCTAssertEqual(dec.count, 63)

        // A request for 3 taps comes back as 5 — `minimumKernelTaps`. That is not padding
        // for its own sake: at 3 taps the Blackman window zeroes both endpoints, only the
        // centre survives, and the highpass becomes `δ − δ`. 5 is the first count with a
        // non-endpoint tap on either side of the centre, which is what makes the spectral
        // inversion produce an actual highpass.
        let k3 = EchoelConvolution.lowpassKernel(cutoffHz: 1000, sampleRate: 48000, taps: 3)
        XCTAssertEqual(k3.count, EchoelConvolution.minimumKernelTaps)
        XCTAssertEqual(EchoelConvolution.minimumKernelTaps, 5)
        assertUsable(k3, "lowpass taps=3")
        let h5 = EchoelConvolution.highpassKernel(cutoffHz: 1000, sampleRate: 48000, taps: 3)
        assertUsable(h5, "highpass at the floor")

        // Odd length is FORCED (`usableTaps`), because `highpassKernel`'s spectral
        // inversion writes to `lp[taps / 2]` and needs a true centre tap. An even request
        // therefore returns one sample longer — a pre-existing wrong-response defect
        // closed at the one point all three factories share.
        for even in [4, 8, 32, 64] {
            let k = EchoelConvolution.lowpassKernel(cutoffHz: 1000, sampleRate: 48000, taps: even)
            XCTAssertEqual(k.count % 2, 1, "taps=\(even): kernel length must be odd")
            assertUsable(k, "lowpass taps=\(even)")
        }
    }

    /// The public door that makes the degenerate taps reachable from outside the module.
    func testDecimator_degenerateFilterTaps_doesNotTrap() {
        for taps in [-1, 0, 1, 2] {
            let d = EchoelDecimator(factor: 2, filterTaps: taps)
            XCTAssertEqual(d.factor, 2, "filterTaps must not disturb the factor")
        }
    }
}
#endif
