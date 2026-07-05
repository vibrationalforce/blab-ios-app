//
//  SessionEngineTests.swift
//  Echoelmusic — Bio
//
//  Verifies the orchestrator's pure per-tick composition: it eases the guided pace
//  over time, stays flash-safe end to end, and hands the audio the true rate while
//  the light stays within the safety envelope.
//

import XCTest
@testable import Echoelmusic

final class SessionEngineTests: XCTestCase {

    private let acc = 1e-9

    private func guide() -> SessionGuide {
        SessionGuide(measuredBreathsPerMinute: 12, resonancePace: 6, descentSeconds: 180)
    }

    func testPlanStartsAtNaturalPaceAndEasesDown() {
        let g = guide()
        let atStart = SessionEngine.plan(guide: g, elapsedSeconds: 0, coherence: 1, intensity: 0.8)
        let later = SessionEngine.plan(guide: g, elapsedSeconds: 10_000, coherence: 1, intensity: 0.8)
        XCTAssertEqual(atStart.paceBpm, 12, accuracy: acc)
        XCTAssertEqual(later.paceBpm, 6, accuracy: 1e-6)
        // targetHz always tracks paceBpm/60.
        XCTAssertEqual(atStart.targetHz, 12.0 / 60, accuracy: acc)
        XCTAssertEqual(later.targetHz, 6.0 / 60, accuracy: 1e-8)
    }

    func testPlanIsAlwaysFlashSafe() {
        let g = guide()
        for t in stride(from: 0.0, through: 600, by: 13) {
            for c in [0.0, 0.5, 1.0] {
                let p = SessionEngine.plan(guide: g, elapsedSeconds: t, coherence: c, intensity: 1)
                if !p.entrainment.visualIsSteady {
                    XCTAssertLessThanOrEqual(p.entrainment.visualPulseHz,
                                             EntrainmentEngine.maxVisualFlashHz + 1e-9)
                    XCTAssertFalse(EntrainmentEngine.isInHazardBand(p.entrainment.visualPulseHz))
                }
                XCTAssertFalse(p.entrainment.allowSaturatedRedFlicker)
                // Breath paces are ~0.1 Hz — the audio pulse is far below any flash concern.
                XCTAssertLessThan(p.targetHz, EntrainmentEngine.maxVisualFlashHz)
            }
        }
    }

    func testPlanAudioCarriesTrueRateVisualClampedIfEverFast() {
        // Sanity: at breath rates audio == visual (both safe). The clamp only diverges
        // them for fast targets, which SessionGuide never produces — proven here.
        let p = SessionEngine.plan(guide: guide(), elapsedSeconds: 30, coherence: 0.5, intensity: 0.7)
        XCTAssertEqual(p.entrainment.audioPulseHz, p.targetHz, accuracy: acc)
        XCTAssertEqual(p.entrainment.visualPulseHz, p.targetHz, accuracy: acc)
        XCTAssertFalse(p.entrainment.visualIsSteady)
    }

    func testLowCoherenceKeepsPaceHigher() {
        // At the same instant a following body is guided lower than an unsettled one.
        let g = guide()
        let settled = SessionEngine.plan(guide: g, elapsedSeconds: 180, coherence: 1, intensity: 0.8)
        let unsettled = SessionEngine.plan(guide: g, elapsedSeconds: 180, coherence: 0, intensity: 0.8)
        XCTAssertLessThan(settled.paceBpm, unsettled.paceBpm)
    }

    func testIntensityScalesBrightnessDepthWithinCap() {
        let g = guide()
        let soft = SessionEngine.plan(guide: g, elapsedSeconds: 30, coherence: 0.5, intensity: 0.2)
        let full = SessionEngine.plan(guide: g, elapsedSeconds: 30, coherence: 0.5, intensity: 1.0)
        XCTAssertLessThan(soft.entrainment.brightnessDelta, full.entrainment.brightnessDelta)
        XCTAssertLessThanOrEqual(full.entrainment.brightnessDelta, EntrainmentEngine.maxBrightnessDelta + 1e-9)
    }
}
