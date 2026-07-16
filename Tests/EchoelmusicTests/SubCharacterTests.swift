// SubCharacterTests.swift
// Echoelmusic — the EchoelBass "sub culture" shaper. Pins the two hard laws:
// (1) defaults reproduce the previously hard-coded SubBassVoice shaping EXACTLY
//     (an un-touched sub stays bit-identical), and
// (2) octave harmonics ONLY — no 3rd harmonic ("komische Töne" regression guard).

import XCTest
@testable import Echoelmusic

final class SubCharacterTests: XCTestCase {

    // MARK: - Law 1: defaults are today's sound, bit-identical

    func testDefaults_reproduceLegacyShapingExactly() {
        let c = SubCharacter.coefficients(presence: SubCharacter.defaultPresence,
                                          heat: SubCharacter.defaultHeat)
        XCTAssertEqual(c.h2Amp, 0.32, accuracy: 1e-6, "legacy 2nd-harmonic amount")
        XCTAssertEqual(c.h4Amp, 0, "4th harmonic OFF at the default (bit-identical)")
        XCTAssertEqual(c.drive, 1.05, accuracy: 1e-6, "legacy tanh drive")
        XCTAssertEqual(c.post, 0.6, accuracy: 1e-6, "legacy output scale")

        // Sample-level identity with the old inline formula across a phase sweep.
        for i in 0..<64 {
            let phase = Float(i) / 64 * 2 * .pi
            let legacy = tanhf((sinf(phase) + sinf(2 * phase) * 0.32) * 1.05) * 0.6
            XCTAssertEqual(SubCharacter.sample(phase: phase, coefficients: c),
                           legacy, accuracy: 1e-6)
        }
    }

    // MARK: - Law 2: octave harmonics only (never the 3rd / fifth)

    func testFullPresence_hasNoThirdHarmonic() {
        // Project one period onto sin(kx): energy at k=2 (and 4), none at k=3.
        // Low heat keeps the tanh near-linear so saturation doesn't smear the
        // projection (at high drive tanh itself makes ODD harmonics of the
        // STACK, which is a different, phase-locked thing — the law guards the
        // deliberately ADDED partials).
        let c = SubCharacter.coefficients(presence: 1, heat: 0)
        let n = 512
        var e2: Float = 0, e3: Float = 0
        for i in 0..<n {
            let phase = Float(i) / Float(n) * 2 * .pi
            let s = SubCharacter.sample(phase: phase, coefficients: c)
            e2 += s * sinf(2 * phase)
            e3 += s * sinf(3 * phase)
        }
        // NB: tanh's cubic term intermodulates the stack (h1·h2² → a small 3f
        // residual ≈0.01 even with NO deliberate 3rd partial) — the law guards
        // the ADDED partials, so the bound is dominance + a loose residual cap.
        XCTAssertGreaterThan(abs(e2), 8 * abs(e3),
                             "octave (2f) must dominate; no deliberate 3rd harmonic")
        XCTAssertLessThan(abs(e3) / Float(n), 0.025, "3rd-harmonic content is residual-only")
    }

    // MARK: - Presence behaviour

    func testPresenceZero_isPureFundamental() {
        let c = SubCharacter.coefficients(presence: 0, heat: 0.5)
        XCTAssertEqual(c.h2Amp, 0)
        XCTAssertEqual(c.h4Amp, 0)
        for i in 0..<32 {
            let phase = Float(i) / 32 * 2 * .pi
            let pure = tanhf(sinf(phase) * c.drive) * c.post
            XCTAssertEqual(SubCharacter.sample(phase: phase, coefficients: c),
                           pure, accuracy: 1e-6)
        }
    }

    func testPresence_monotonicHarmonicGrowth_and4thOnlyAboveDefault() {
        let low = SubCharacter.coefficients(presence: 0.25, heat: 0.5)
        let mid = SubCharacter.coefficients(presence: 0.5, heat: 0.5)
        let high = SubCharacter.coefficients(presence: 1, heat: 0.5)
        XCTAssertLessThan(low.h2Amp, mid.h2Amp)
        XCTAssertLessThan(mid.h2Amp, high.h2Amp)
        XCTAssertEqual(low.h4Amp, 0, "no 4th below the default midpoint")
        XCTAssertEqual(mid.h4Amp, 0, "no 4th AT the default (bit-identical)")
        XCTAssertGreaterThan(high.h4Amp, 0, "4th joins above the midpoint")
    }

    // MARK: - Heat behaviour (character, not loudness)

    func testHeat_isLoudnessCompensated_atFundamentalPeak() {
        // The fundamental's peak (phase π/2) must stay in a tight window across
        // the whole heat range — heat shifts harmonic content, not level.
        let peaks: [Float] = [0, 0.5, 1].map { heat in
            let c = SubCharacter.coefficients(presence: 0, heat: heat)
            return abs(SubCharacter.sample(phase: .pi / 2, coefficients: c))
        }
        let reference = peaks[1]   // default
        for p in peaks {
            XCTAssertEqual(p, reference, accuracy: reference * 0.12,
                           "peak stays within ~12% across the heat range")
        }
    }

    func testHeat_increasesSaturationHarmonics() {
        // More heat → the shaped wave deviates more from a pure (scaled) sine.
        func distortion(_ heat: Float) -> Float {
            let c = SubCharacter.coefficients(presence: 0, heat: heat)
            let n = 256
            var dev: Float = 0
            let peak = SubCharacter.sample(phase: .pi / 2, coefficients: c)
            for i in 0..<n {
                let phase = Float(i) / Float(n) * 2 * .pi
                dev += abs(SubCharacter.sample(phase: phase, coefficients: c) - peak * sinf(phase))
            }
            return dev
        }
        XCTAssertLessThan(distortion(0), distortion(1),
                          "hot setting is measurably more saturated than clean")
    }

    // MARK: - Safety

    func testBounds_outputNeverExceedsUnity_andNaNIsSilence() {
        for p in stride(from: Float(0), through: 1, by: 0.25) {
            for h in stride(from: Float(0), through: 1, by: 0.25) {
                let c = SubCharacter.coefficients(presence: p, heat: h)
                for i in 0..<64 {
                    let phase = Float(i) / 64 * 2 * .pi
                    let s = SubCharacter.sample(phase: phase, coefficients: c)
                    XCTAssertTrue(s.isFinite)
                    XCTAssertLessThanOrEqual(abs(s), 1)
                }
            }
        }
        let c = SubCharacter.coefficients(presence: .nan, heat: .infinity)
        XCTAssertEqual(c, SubCharacter.coefficients(presence: SubCharacter.defaultPresence,
                                                    heat: SubCharacter.defaultHeat),
                       "non-finite params fall back to the neutral defaults")
        XCTAssertEqual(SubCharacter.sample(phase: .nan, coefficients: c), 0,
                       "non-finite phase renders silence, never NaN")
    }
}
