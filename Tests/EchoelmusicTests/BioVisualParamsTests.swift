// BioVisualParamsTests.swift
// Echoel — the pure bio→visual mapping (flash-safe foundation of the visual engine).

import XCTest
@testable import Echoelmusic

final class BioVisualParamsTests: XCTestCase {

    private func frame(hr: Float = 60, hrv: Float = 0.5, breath: Float = 0.5,
                       coherence: Float = 0.5) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: 0, heartRateBPM: hr, hrvNormalized: hrv,
            breathRate: 6, breathPhase: breath, coherence: coherence,
            motionEnergy: 0, source: .fallback
        )
    }

    // MARK: Flash safety (the whole point)

    func testPulse_neverExceedsWcagLimit() {
        let p = BioVisualParams.from(frame(hr: 600))   // absurd HR
        XCTAssertLessThanOrEqual(p.pulseHz, FlashGuard.maxFlashHz)
    }

    func testReduceMotion_freezesPulse() {
        let p = BioVisualParams.from(frame(hr: 120), reduceMotion: true)
        XCTAssertEqual(p.pulseHz, 0, accuracy: 1e-9)
    }

    func testPulse_boundedFloorForSlowHeart() {
        // Even a very low HR keeps a gentle ≥0.5 Hz pulse (not frozen).
        let p = BioVisualParams.from(frame(hr: 12))
        XCTAssertGreaterThanOrEqual(p.pulseHz, 0.5 - 1e-9)
    }

    // MARK: Bio mapping

    func testCoherence_drivesHueAndIntensity() {
        // 0.1, not 0: exactly-0 now means "not measured" and maps to the neutral 0.5,
        // so a 0-vs-1 pair no longer exercises the LOW end of the mapping at all.
        let low = BioVisualParams.from(frame(coherence: 0.1))
        let coherent = BioVisualParams.from(frame(coherence: 1))
        XCTAssertGreaterThan(coherent.hue, low.hue)             // red → cyan
        XCTAssertGreaterThan(coherent.intensity, low.intensity)
        XCTAssertLessThanOrEqual(coherent.hue, 0.45 + 1e-9)
    }

    func testHRV_drivesComplexity_inRange() {
        let low = BioVisualParams.from(frame(hrv: 0.1))   // not 0 — see the coherence test
        let high = BioVisualParams.from(frame(hrv: 1))
        XCTAssertGreaterThan(high.complexity, low.complexity)
        XCTAssertGreaterThanOrEqual(low.complexity, 0)
        XCTAssertLessThanOrEqual(high.complexity, 1)
    }

    func testBreath_drivesSpread() {
        let exhale = BioVisualParams.from(frame(breath: 0))
        let inhale = BioVisualParams.from(frame(breath: 1))
        XCTAssertGreaterThan(inhale.spread, exhale.spread)
    }

    func testOutOfRangeBio_clamps() {
        let wild = BioVisualParams.from(frame(hrv: 9, breath: -4, coherence: 5))
        XCTAssertGreaterThanOrEqual(wild.hue, 0)
        XCTAssertLessThanOrEqual(wild.hue, 0.45 + 1e-9)
        XCTAssertGreaterThanOrEqual(wild.complexity, 0)
        XCTAssertLessThanOrEqual(wild.complexity, 1)
    }

    // MARK: Defaults & patterns

    func testNilFrame_usesSafeDefaults() {
        let p = BioVisualParams.from(nil, pattern: .cymatics)
        XCTAssertEqual(p.pattern, .cymatics)
        XCTAssertGreaterThanOrEqual(p.pulseHz, 0.5 - 1e-9)   // hr defaults to 60 → 1 Hz
        XCTAssertLessThanOrEqual(p.pulseHz, FlashGuard.maxFlashHz)
    }

    func testPatternRosterComplete() {
        XCTAssertEqual(Set(BioVisualPattern.allCases), [.rings, .cymatics, .mandala])
        for p in BioVisualPattern.allCases { XCTAssertFalse(p.displayName.isEmpty) }
    }

    func testNeutralIsStill() {
        XCTAssertEqual(BioVisualParams.neutral.pulseHz, 0, accuracy: 1e-9)
    }
}
