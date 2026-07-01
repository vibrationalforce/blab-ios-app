// BioEntrainmentDirectorTests.swift
// Echoel — biofeedback-driven brainwave entrainment. Covers the pure director:
// coherence→band selection, quality-gated depth, flash-safe visual pulse (≤3 Hz),
// and manual band override.

import XCTest
@testable import Echoelmusic

final class BioEntrainmentDirectorTests: XCTestCase {

    typealias D = BioEntrainmentDirector

    // MARK: - Auto band selection (arousal → calm axis)

    func testAutoBand_lowCoherence_isBeta() {
        XCTAssertEqual(D.autoBand(coherence: 0.0), .beta)
        XCTAssertEqual(D.autoBand(coherence: 0.29), .beta)
    }

    func testAutoBand_midCoherence_isAlpha() {
        XCTAssertEqual(D.autoBand(coherence: 0.30), .alpha)
        XCTAssertEqual(D.autoBand(coherence: 0.64), .alpha)
    }

    func testAutoBand_highCoherence_isTheta() {
        XCTAssertEqual(D.autoBand(coherence: 0.65), .theta)
        XCTAssertEqual(D.autoBand(coherence: 1.0), .theta)
    }

    // MARK: - Quality gate

    func testDepth_belowQualityFloor_isInactive() {
        let t = D().target(coherence: 1.0, quality: 0.2)
        XCTAssertFalse(t.isActive)
        XCTAssertEqual(t.depth, 0)
    }

    func testDepth_scalesWithQualityAndCoherence_andNeverExceedsMax() {
        let hi = D().target(coherence: 1.0, quality: 1.0)
        XCTAssertTrue(hi.isActive)
        XCTAssertLessThanOrEqual(hi.depth, D.maxDepth + 1e-6)
        XCTAssertEqual(hi.depth, D.maxDepth, accuracy: 1e-5)   // q=1, c=1 → full maxDepth

        let lo = D().target(coherence: 0.0, quality: 0.5)
        XCTAssertTrue(lo.isActive)
        XCTAssertLessThan(lo.depth, hi.depth)                  // lower quality/coherence → shallower
        XCTAssertLessThanOrEqual(lo.depth, D.maxDepth)
    }

    // MARK: - Flash safety (WCAG ≤ 3 Hz) for EVERY band

    func testVisualPulse_isFlashSafeForAllBands() {
        for band in BrainwaveBand.allCases {
            let hz = D.visualHz(for: band)
            XCTAssertGreaterThan(hz, 0)
            XCTAssertLessThanOrEqual(hz, D.maxVisualHz + 1e-9, "\(band) visual pulse must be ≤3 Hz")
        }
    }

    func testVisualPulse_knownFolds() {
        XCTAssertEqual(D.visualHz(for: .delta), 2.0, accuracy: 1e-9)   // 2 → 2
        XCTAssertEqual(D.visualHz(for: .theta), 3.0, accuracy: 1e-9)   // 6 → 3
        XCTAssertEqual(D.visualHz(for: .alpha), 2.5, accuracy: 1e-9)   // 10 → 2.5
    }

    func testTarget_visualPulseAlwaysFlashSafe() {
        for c in stride(from: Float(0), through: 1, by: 0.1) {
            let t = D().target(coherence: c, quality: 1.0)
            XCTAssertLessThanOrEqual(t.visualPulseHz, D.maxVisualHz + 1e-9)
        }
    }

    // MARK: - Manual override

    func testManualBand_overridesAutoSelection() {
        let t = D(manualBand: .gamma).target(coherence: 1.0, quality: 1.0)  // auto would be theta
        XCTAssertEqual(t.band, .gamma)
        XCTAssertEqual(t.visualPulseHz, D.visualHz(for: .gamma), accuracy: 1e-9)
    }

    func testManualBand_stillQualityGated() {
        let t = D(manualBand: .alpha).target(coherence: 1.0, quality: 0.1)
        XCTAssertFalse(t.isActive)   // bad lock → no stimulus even in manual mode
    }
}
