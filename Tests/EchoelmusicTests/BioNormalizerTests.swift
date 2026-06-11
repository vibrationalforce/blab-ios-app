// BioNormalizerTests.swift
// Echoelmusic — science-grounded biosignal normalization (rolling-z → tanh → EMA).
// Expected values are hand-computed so the math is pinned, not approximated.

import XCTest
@testable import Echoelmusic

final class BioNormalizerTests: XCTestCase {

    // MARK: - RollingStats

    func testRollingStats_meanAndSampleStd_knownVector() {
        var s = RollingStats(capacity: 4)
        [1.0, 2.0, 3.0, 4.0].forEach { s.push($0) }
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s.mean, 2.5, accuracy: 1e-9)
        // devs −1.5,−0.5,0.5,1.5 → sumSq 5 → var 5/3 → std √(5/3) ≈ 1.290994
        XCTAssertEqual(s.std, 1.290994449, accuracy: 1e-6)
    }

    func testRollingStats_evictsOldestWhenFull() {
        var s = RollingStats(capacity: 3)
        [10.0, 20.0, 30.0, 40.0].forEach { s.push($0) }  // 10 evicted → {20,30,40}
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.mean, 30.0, accuracy: 1e-9)
    }

    func testRollingStats_constantInput_stdZero() {
        var s = RollingStats(capacity: 5)
        (0..<5).forEach { _ in s.push(850.0) }
        XCTAssertEqual(s.std, 0, accuracy: 1e-9)
    }

    // MARK: - BioNormalizer warm-up & neutrality

    func testNormalize_firstSample_returnsNeutralHalf() {
        var n = BioNormalizer(windowSamples: 8, emaAlpha: 1.0)
        XCTAssertEqual(n.normalize(123.0), 0.5, accuracy: 1e-9)
    }

    func testNormalize_constantInput_settlesToHalf() {
        // Flat signal → std 0 → σ-floor → z 0 → squash 0.5.
        var n = BioNormalizer(windowSamples: 8, emaAlpha: 1.0)
        var out: Float = 0
        for _ in 0..<10 { out = n.normalize(100.0) }
        XCTAssertEqual(out, 0.5, accuracy: 1e-6)
    }

    // MARK: - BioNormalizer z-score → tanh squash (no smoothing)

    func testNormalize_knownZSquash_noSmoothing() {
        // window {1,2,3,4}: mean 2.5, std √(5/3)=1.290994.
        // raw 4 → z = 1.5/1.290994 = 1.161895 → 0.5*(tanh(1.161895)+1) ≈ 0.910847
        var n = BioNormalizer(windowSamples: 4, squashGain: 1.0, emaAlpha: 1.0)
        var out: Float = 0
        [1.0, 2.0, 3.0, 4.0].forEach { out = n.normalize(Float($0)) }
        XCTAssertEqual(out, 0.910847, accuracy: 1e-4)
    }

    func testNormalize_belowBaseline_belowHalf_aboveBaseline_aboveHalf() {
        var n = BioNormalizer(windowSamples: 16, squashGain: 1.0, emaAlpha: 1.0)
        for v in stride(from: 50.0, through: 60.0, by: 1.0) { _ = n.normalize(Float(v)) }
        let low = n.normalize(40.0)   // well below the rolling mean
        let high = n.normalize(80.0)  // well above
        XCTAssertLessThan(low, 0.5)
        XCTAssertGreaterThan(high, 0.5)
    }

    // MARK: - Accept gate (motion/confidence hold)

    func testNormalize_gateRejected_holdsPreviousValue() {
        var n = BioNormalizer(windowSamples: 8, squashGain: 1.0, emaAlpha: 1.0)
        for v in 1...6 { _ = n.normalize(Float(v)) }
        let held = n.value
        // A wild, untrusted sample must NOT move the output.
        let out = n.normalize(9999.0, accept: false)
        XCTAssertEqual(out, held, accuracy: 1e-9)
        XCTAssertEqual(n.value, held, accuracy: 1e-9)
    }

    // MARK: - EMA smoothing reduces step response

    func testNormalize_emaSmoothsStep() {
        var fast = BioNormalizer(windowSamples: 32, squashGain: 1.0, emaAlpha: 1.0)
        var slow = BioNormalizer(windowSamples: 32, squashGain: 1.0, emaAlpha: 0.2)
        for v in stride(from: 50.0, through: 60.0, by: 1.0) {
            _ = fast.normalize(Float(v)); _ = slow.normalize(Float(v))
        }
        let fastJump = fast.normalize(90.0)
        let slowJump = slow.normalize(90.0)
        // Smoothed output reacts less to the same step.
        XCTAssertGreaterThan(fastJump, slowJump)
    }

    func testReset_clearsState() {
        var n = BioNormalizer(windowSamples: 8, emaAlpha: 1.0)
        for v in 1...6 { _ = n.normalize(Float(v)) }
        n.reset()
        XCTAssertEqual(n.normalize(123.0), 0.5, accuracy: 1e-9)  // back to warm-up
    }

    // MARK: - alpha() time-constant helper

    func testAlpha_zeroTau_isOne() {
        XCTAssertEqual(BioNormalizer.alpha(tauSeconds: 0, dtSeconds: 0.1), 1.0, accuracy: 1e-9)
    }

    func testAlpha_knownValue() {
        // dt/(tau+dt) = 0.1/(0.9+0.1) = 0.1
        XCTAssertEqual(BioNormalizer.alpha(tauSeconds: 0.9, dtSeconds: 0.1), 0.1, accuracy: 1e-6)
    }

    func testAlpha_clampedAndSafe() {
        XCTAssertEqual(BioNormalizer.alpha(tauSeconds: 0, dtSeconds: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(BioNormalizer.alpha(tauSeconds: -5, dtSeconds: -5), 1.0, accuracy: 1e-9)
    }

    // MARK: - ResponseCurve

    func testResponseCurve_endpointsPreserved() {
        for c in ResponseCurve.allCases {
            XCTAssertEqual(c.apply(0), 0, accuracy: 1e-6, "\(c) at 0")
            XCTAssertEqual(c.apply(1), 1, accuracy: 1e-6, "\(c) at 1")
        }
    }

    func testResponseCurve_midpointValues() {
        XCTAssertEqual(ResponseCurve.linear.apply(0.5), 0.5, accuracy: 1e-6)
        XCTAssertEqual(ResponseCurve.exponential.apply(0.5), 0.25, accuracy: 1e-6)
        XCTAssertEqual(ResponseCurve.logarithmic.apply(0.5), 0.707107, accuracy: 1e-5)
        XCTAssertEqual(ResponseCurve.sCurve.apply(0.5), 0.5, accuracy: 1e-6)
    }

    func testResponseCurve_clampsInput() {
        XCTAssertEqual(ResponseCurve.linear.apply(-1), 0, accuracy: 1e-9)
        XCTAssertEqual(ResponseCurve.linear.apply(2), 1, accuracy: 1e-9)
    }
}
