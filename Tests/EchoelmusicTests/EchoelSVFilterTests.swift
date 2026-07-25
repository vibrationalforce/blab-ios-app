//
//  EchoelSVFilterTests.swift
//  Echoelmusic — the state-variable filter's response contract.
//
//  This file did not exist while the filter silently capped every patch at 8 kHz,
//  which is most of why the cap survived: the parameter registry advertises
//  `ddsp.filter.cutoff` up to 18 kHz, `EchoelDDSP` clamps its modulated cutoff to
//  18 kHz, and the filter quietly ignored the top ~1.2 octaves of that range.
//  Nothing anywhere asserted that moving the cutoff changes the sound.
//

import XCTest
@testable import Echoelmusic

final class EchoelSVFilterTests: XCTestCase {

    private let sr: Float = 48_000

    /// RMS gain of a steady sine at `freq` through `filter`, after letting the state
    /// settle. Pure measurement — no tolerance decisions here.
    private func gain(_ filter: EchoelSVFilter, at freq: Float, cycles: Int = 200) -> Float {
        filter.reset()
        let samplesPerCycle = sr / freq
        // The window is floored in ABSOLUTE samples as well as probe cycles. Cycles
        // alone is a trap: a 16 kHz probe gets only ~600 samples, while a low-cutoff
        // high-Q filter rings for thousands, so such a case would silently measure the
        // transient instead of the steady state. Rounded down to whole probe cycles so
        // the RMS window still spans an exact number of periods.
        let minSamples = 20_000
        let wantedCycles = max(cycles, Int((Float(minSamples) / samplesPerCycle).rounded(.up)))
        let total = Int(samplesPerCycle * Float(wantedCycles))
        let settle = total / 2
        var sumOut: Float = 0
        var sumIn: Float = 0
        for n in 0..<total {
            let x = sinf(2 * .pi * freq * Float(n) / sr)
            let y = filter.process(x)
            if n >= settle {
                sumOut += y * y
                sumIn += x * x
            }
        }
        guard sumIn > 0 else { return 0 }
        return (sumOut / sumIn).squareRoot()
    }

    // MARK: - The lid

    func testCutoffAboveAnEighthOfTheSampleRate_stillMovesTheSound() {
        // THE regression this file exists for. The Chamberlin topology is only stable
        // to SR/6, so the old implementation clamped the normalized cutoff there —
        // 8 kHz at 48 kHz. Every cutoff above that collapsed onto the SAME filter, so
        // 9 kHz and 16 kHz were literally indistinguishable and the top of the range
        // was decorative. A correct filter must separate them.
        let f = EchoelSVFilter(sampleRate: sr)
        f.mode = .lowpass
        f.resonance = 0.3

        f.cutoff = 9_000
        let atNine = gain(f, at: 12_000)
        f.cutoff = 16_000
        let atSixteen = gain(f, at: 12_000)

        XCTAssertGreaterThan(atSixteen, atNine * 1.2,
                             "a 12 kHz tone must pass more freely at a 16 kHz cutoff than at 9 kHz; "
                             + "equal gains mean both cutoffs were clamped to the same lid")
    }

    func testTheFullAdvertisedRangeIsUsable() {
        // `EchoelParameterRegistry` promises 20 Hz…18 kHz. Walk the top of it and
        // require the response to keep opening — no plateau, no blow-up.
        //
        // The probe must sit ABOVE every cutoff under test. An earlier version of this
        // used 5 kHz, which is BELOW all of them: raising the cutoff then moves the
        // resonant shoulder away from the probe and the gain FALLS, so the test failed
        // on a perfectly correct filter. A lowpass is not monotone in cutoff below its
        // own corner — only above it.
        let f = EchoelSVFilter(sampleRate: sr)
        f.mode = .lowpass
        f.resonance = 0.2
        var previous: Float = 0
        for cutoff in stride(from: Float(6_000), through: 18_000, by: 3_000) {
            f.cutoff = cutoff
            let g = gain(f, at: 16_000)
            XCTAssertTrue(g.isFinite, "cutoff \(cutoff) Hz produced a non-finite response")
            // 1.1 not 1.3: the last step (15 k → 18 k) only has ~1.3x, since 16 kHz is
            // by then inside the passband and the response is flattening toward unity.
            XCTAssertGreaterThan(g, previous * 1.1,
                                 "response stopped opening at \(cutoff) Hz — a lid is still in place")
            previous = g
        }
    }

    // MARK: - Basic response contract

    func testLowpassPassesDC_highpassBlocksIt() {
        let f = EchoelSVFilter(sampleRate: sr)
        f.cutoff = 1_000

        f.mode = .lowpass
        f.reset()
        var y: Float = 0
        for _ in 0..<4_000 { y = f.process(1.0) }
        XCTAssertEqual(y, 1.0, accuracy: 0.02, "a lowpass must pass DC")

        f.mode = .highpass
        f.reset()
        for _ in 0..<4_000 { y = f.process(1.0) }
        XCTAssertEqual(y, 0.0, accuracy: 0.02, "a highpass must block DC")
    }

    func testLowpassAttenuatesWellAboveCutoff() {
        let f = EchoelSVFilter(sampleRate: sr)
        f.mode = .lowpass
        f.resonance = 0.2
        f.cutoff = 500
        XCTAssertLessThan(gain(f, at: 8_000), 0.1, "two poles above cutoff should be well down")
        XCTAssertGreaterThan(gain(f, at: 100), 0.8, "well below cutoff should pass")
    }

    func testResonanceLiftsTheCornerWithoutRunningAway() {
        let f = EchoelSVFilter(sampleRate: sr)
        f.mode = .lowpass
        f.cutoff = 2_000
        f.resonance = 0.0
        let flat = gain(f, at: 2_000)
        f.resonance = 0.9
        let peaked = gain(f, at: 2_000)
        XCTAssertGreaterThan(peaked, flat, "resonance must lift the corner")
        XCTAssertLessThan(peaked, 25, "…but the peak must stay bounded, not self-oscillate")
    }

    // MARK: - Stability and state hygiene

    func testExtremeCutoffsStayFinite() {
        // Both ends, including a cutoff ABOVE Nyquist — the tan() prewarp diverges at
        // SR/2, so the guard is the filter's, not the caller's.
        for cutoff in [Float(0), 1, 20, 20_000, 24_000, 48_000, 200_000] {
            for mode in EchoelSVFilter.Mode.allCases {
                let f = EchoelSVFilter(sampleRate: sr)
                f.mode = mode
                f.resonance = 0.95
                f.cutoff = cutoff
                var y: Float = 0
                for n in 0..<2_000 { y = f.process(sinf(Float(n) * 0.1)) }
                XCTAssertTrue(y.isFinite,
                              "cutoff \(cutoff) Hz in \(mode) went non-finite")
                XCTAssertLessThan(abs(y), 100,
                                  "cutoff \(cutoff) Hz in \(mode) blew up to \(y)")
            }
        }
    }

    func testStateDecaysToEXACTLYZeroAfterSilence() {
        // Denormals: a decaying IIR tail approaches zero asymptotically and can spend
        // thousands of samples in the denormal range, where each operation traps into
        // microcode. On a per-voice filter that is a real CPU cliff during release
        // tails — precisely when a polyphonic patch has the most voices alive.
        let f = EchoelSVFilter(sampleRate: sr)
        f.mode = .lowpass
        f.cutoff = 800
        _ = f.process(1.0)
        var y: Float = 1
        for _ in 0..<200_000 { y = f.process(0) }
        XCTAssertEqual(y, 0, "the tail must flush to exact zero, not linger as denormals")
    }

    func testANonFiniteInputCannotPoisonTheFilterForever() {
        // This repo has twice shipped a permanent-silence bug from a single NaN landing
        // in a recursive accumulator. A filter is a recursive accumulator, so it must
        // recover on its own rather than needing the voice torn down.
        let f = EchoelSVFilter(sampleRate: sr)
        f.mode = .lowpass
        f.cutoff = 1_000
        _ = f.process(.nan)
        _ = f.process(.infinity)
        var y: Float = 0
        for _ in 0..<4_000 { y = f.process(1.0) }
        XCTAssertTrue(y.isFinite, "the filter stayed poisoned after a non-finite input")
        XCTAssertEqual(y, 1.0, accuracy: 0.05, "…and must return to its normal DC response")
    }

    func testEveryTornParameterPairIsStillAStableFilter() {
        // `cutoff` and `resonance` are written from the control thread (SynthPatch,
        // EchoelFXChain, FXBioModulator at ~30 Hz) and read on the audio thread with no
        // synchronisation. A preemption between the two stores means the render can see
        // a NEW cutoff beside a STALE resonance, or vice versa.
        //
        // That has to be harmless, and it is only harmless if the two are INDEPENDENT.
        // The Chamberlin form this file replaced had that property by accident; the
        // first TPT draft lost it by caching the three mutually-derived coefficients
        // a1/a2/a3 (a torn set of those reaches a spectral radius near 1.4 — full scale
        // within milliseconds, on a path with no non-finite sweep before the hardware
        // buffer). The solve therefore lives inside `process`, and this test is what
        // stops anyone moving it back out for the one saved divide.
        //
        // Simulated by writing every crossed pair directly and rendering.
        let extremes: [(Float, Float)] = [(20, 0.01), (20, 0.95), (18_000, 0.01),
                                          (18_000, 0.95), (2_000, 0.5), (23_000, 0.9)]
        for (cutoffA, resA) in extremes {
            for (cutoffB, resB) in extremes {
                let f = EchoelSVFilter(sampleRate: sr)
                f.mode = .lowpass
                f.cutoff = cutoffA
                f.resonance = resA
                // The tear: the other generation's cutoff arrives, its resonance does not.
                f.cutoff = cutoffB
                var peak: Float = 0
                for n in 0..<4_000 {
                    let y = f.process(sinf(Float(n) * 0.07))
                    peak = max(peak, abs(y))
                }
                XCTAssertTrue(peak.isFinite,
                              "torn pair (\(cutoffB) Hz, res \(resA)) went non-finite")
                XCTAssertLessThan(peak, 100,
                                  "torn pair (\(cutoffB) Hz, res \(resA)) grew to \(peak) — "
                                  + "the parameters are no longer independent")
                // And the reverse tear: resonance arrives first.
                let f2 = EchoelSVFilter(sampleRate: sr)
                f2.mode = .lowpass
                f2.cutoff = cutoffA
                f2.resonance = resB
                var peak2: Float = 0
                for n in 0..<4_000 {
                    peak2 = max(peak2, abs(f2.process(sinf(Float(n) * 0.07))))
                }
                XCTAssertTrue(peak2.isFinite && peak2 < 100,
                              "torn pair (\(cutoffA) Hz, res \(resB)) grew to \(peak2)")
            }
        }
    }

    func testAClosedFilterDecaysInsteadOfFreezing() {
        // At g = 0 both integrators are starved: the state does not close, it HOLDS —
        // and at normal magnitude, so the denormal flush never clears it. A cutoff of 0
        // would leave whatever DC was last there ringing forever.
        let f = EchoelSVFilter(sampleRate: sr)
        f.mode = .lowpass
        f.cutoff = 2_000
        for _ in 0..<2_000 { _ = f.process(1.0) }   // charge the state
        f.cutoff = 0
        var y: Float = 1
        for _ in 0..<Int(sr * 4) { y = f.process(0) }
        XCTAssertLessThan(abs(y), 0.05, "a closed filter froze on its last value instead of decaying")
    }

    func testResetClearsState() {
        let f = EchoelSVFilter(sampleRate: sr)
        f.mode = .lowpass
        f.cutoff = 1_000
        for _ in 0..<1_000 { _ = f.process(1.0) }
        f.reset()
        XCTAssertEqual(f.process(0), 0, accuracy: 1e-6, "reset must leave no energy behind")
    }

    func testProcessBufferMatchesPerSample() {
        let a = EchoelSVFilter(sampleRate: sr)
        let b = EchoelSVFilter(sampleRate: sr)
        for f in [a, b] { f.mode = .bandpass; f.cutoff = 3_000; f.resonance = 0.5 }
        var buffer = (0..<512).map { sinf(Float($0) * 0.05) }
        let expected = buffer.map { a.process($0) }
        b.processBuffer(&buffer, frameCount: buffer.count)
        for i in 0..<buffer.count {
            XCTAssertEqual(buffer[i], expected[i], accuracy: 1e-6, "buffer path diverged at \(i)")
        }
    }
}
