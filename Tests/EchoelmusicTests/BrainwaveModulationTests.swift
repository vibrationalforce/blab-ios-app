// BrainwaveModulationTests.swift
// Pure tests for the EEG modulation-source foundation (#61, Haffelder framing):
// band model, relative power, the derived indices, and interhemispheric cosine
// coherence. All outputs finite + clamped [0…1]; every division guarded. No
// engine → runs on every platform.

import XCTest
@testable import Echoelmusic

final class BrainwaveModulationTests: XCTestCase {

    // MARK: EEGBandPowers sanitizes input

    func testBandPowers_negativeAndNonFinite_collapseToZero() {
        let p = EEGBandPowers(delta: -5, theta: .nan, alpha: .infinity, beta: 3, gamma: 0)
        XCTAssertEqual(p.delta, 0)
        XCTAssertEqual(p.theta, 0)
        XCTAssertEqual(p.alpha, 0)
        XCTAssertEqual(p.beta, 3)
        XCTAssertEqual(p.total, 3)
    }

    // MARK: relative power

    func testRelativePower_sharesSumToOne() {
        let p = EEGBandPowers(delta: 1, theta: 1, alpha: 2, beta: 3, gamma: 3) // total 10
        XCTAssertEqual(BrainwaveModulation.relativePower(.alpha, in: p), 0.2, accuracy: 1e-6)
        XCTAssertEqual(BrainwaveModulation.relativePower(.beta, in: p), 0.3, accuracy: 1e-6)
        let sum = BrainwaveModulation.Band.allCases
            .reduce(Float(0)) { $0 + BrainwaveModulation.relativePower($1, in: p) }
        XCTAssertEqual(sum, 1.0, accuracy: 1e-6)
    }

    func testRelativePower_silentSpectrum_isZero() {
        let silent = EEGBandPowers()
        XCTAssertEqual(BrainwaveModulation.relativePower(.alpha, in: silent), 0)
    }

    // MARK: relaxation index (alpha vs beta)

    func testRelaxationIndex_alphaDominant_towardOne() {
        let calm = EEGBandPowers(alpha: 9, beta: 1)
        XCTAssertEqual(BrainwaveModulation.relaxationIndex(calm), 0.9, accuracy: 1e-6)
    }

    func testRelaxationIndex_betaDominant_towardZero() {
        let alert = EEGBandPowers(alpha: 1, beta: 9)
        XCTAssertEqual(BrainwaveModulation.relaxationIndex(alert), 0.1, accuracy: 1e-6)
    }

    func testRelaxationIndex_noAlphaBeta_isNeutralHalf() {
        XCTAssertEqual(BrainwaveModulation.relaxationIndex(EEGBandPowers(delta: 5)), 0.5, accuracy: 1e-6)
    }

    // MARK: arousal index (fast over qualifying, delta excluded)

    func testArousalIndex_excludesDelta() {
        // Only delta present → denom (theta+alpha+beta+gamma) is 0 → 0.
        XCTAssertEqual(BrainwaveModulation.arousalIndex(EEGBandPowers(delta: 100)), 0)
        // beta+gamma = 4 of denom 4 (delta ignored) → 1.
        let fast = EEGBandPowers(delta: 50, beta: 2, gamma: 2)
        XCTAssertEqual(BrainwaveModulation.arousalIndex(fast), 1.0, accuracy: 1e-6)
    }

    func testArousalIndex_halfFastHalfSlow() {
        let p = EEGBandPowers(theta: 1, alpha: 1, beta: 1, gamma: 1) // fast 2 / denom 4
        XCTAssertEqual(BrainwaveModulation.arousalIndex(p), 0.5, accuracy: 1e-6)
    }

    // MARK: meditative index (theta over theta+alpha)

    func testMeditativeIndex_thetaShare() {
        let p = EEGBandPowers(theta: 3, alpha: 1)
        XCTAssertEqual(BrainwaveModulation.meditativeIndex(p), 0.75, accuracy: 1e-6)
        XCTAssertEqual(BrainwaveModulation.meditativeIndex(EEGBandPowers(beta: 5)), 0)
    }

    // MARK: hemisphere coherence (cosine similarity of relative shape)

    func testHemisphereCoherence_identicalShape_isOne() {
        let l = EEGBandPowers(delta: 1, theta: 2, alpha: 3, beta: 4, gamma: 5)
        // Same DISTRIBUTION, different magnitude → cosine similarity 1.
        let r = EEGBandPowers(delta: 2, theta: 4, alpha: 6, beta: 8, gamma: 10)
        XCTAssertEqual(BrainwaveModulation.hemisphereCoherence(left: l, right: r), 1.0, accuracy: 1e-5)
    }

    func testHemisphereCoherence_orthogonal_isZero() {
        let l = EEGBandPowers(alpha: 5)           // all in alpha
        let r = EEGBandPowers(gamma: 5)           // all in gamma
        XCTAssertEqual(BrainwaveModulation.hemisphereCoherence(left: l, right: r), 0, accuracy: 1e-6)
    }

    func testHemisphereCoherence_silentHemisphere_isZero() {
        let l = EEGBandPowers(alpha: 5)
        XCTAssertEqual(BrainwaveModulation.hemisphereCoherence(left: l, right: EEGBandPowers()), 0)
    }
}
