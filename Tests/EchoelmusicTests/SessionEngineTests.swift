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

    func testPhaseOffsetKeepsGateContinuousAcrossRateChanges() {
        // The bio-safety HIGH: republishing hz jumps the phase by t·Δhz cycles unless
        // the offset absorbs it. Law: offset' = offset + t·(h1 − h2) makes
        // gate(t, h2, offset') EXACTLY equal gate(t, h1, offset) at the changeover —
        // continuity by construction. Sweep a jittering rate for 10 simulated
        // minutes of 10 Hz ticks and assert the gate never steps discontinuously.
        var offset = 0.0
        var hz = 0.2
        var prevGate: Double? = nil
        var t = 0.0
        var i = 0
        while t < 600 {
            t += 0.1
            i += 1
            // Jitter the rate every few ticks (like coherence-driven pace updates).
            if i % 7 == 0 {
                let newHz = 0.075 + 0.15 * Double((i * 37) % 100) / 100.0
                offset = SessionEngine.continuedPhaseOffset(
                    oldHz: hz, newHz: newHz, elapsed: t, current: offset)
                hz = newHz
            }
            let g = EntrainmentEngine.gate(atSeconds: t, hz: hz, phaseOffset: offset)
            if let p = prevGate {
                // Max slope of the raised cosine is π·hz per second → per 0.1 s tick
                // the largest legitimate move is π·hzMax·0.1 ≈ 0.071. Allow slack ×2.
                XCTAssertLessThan(abs(g - p), 0.15,
                                  "gate stepped discontinuously at t=\(t) (\(p) → \(g))")
            }
            prevGate = g
        }
    }

    func testContinuedPhaseOffsetLawIsExactAtChangeover() {
        // gate(t, h2, offset') == gate(t, h1, offset) — the algebraic identity.
        let t = 312.7, h1 = 0.1833, h2 = 0.0917, offset = 0.42
        let offset2 = SessionEngine.continuedPhaseOffset(oldHz: h1, newHz: h2,
                                                         elapsed: t, current: offset)
        XCTAssertEqual(EntrainmentEngine.gate(atSeconds: t, hz: h2, phaseOffset: offset2),
                       EntrainmentEngine.gate(atSeconds: t, hz: h1, phaseOffset: offset),
                       accuracy: 1e-9)
        // Result is wrapped to [0,1) so the Float mirror keeps full precision.
        XCTAssertGreaterThanOrEqual(offset2, 0)
        XCTAssertLessThan(offset2, 1)
    }

    func testContinuedPhaseOffsetGuardsDegenerateInput() {
        XCTAssertEqual(SessionEngine.continuedPhaseOffset(oldHz: 0.1, newHz: 0.1,
                                                          elapsed: 100, current: 0.3),
                       0.3, accuracy: 1e-12, "no rate change → unchanged")
        XCTAssertEqual(SessionEngine.continuedPhaseOffset(oldHz: .nan, newHz: 0.1,
                                                          elapsed: 100, current: 0.3),
                       0.3, accuracy: 1e-12, "NaN rate → hold current")
        XCTAssertEqual(SessionEngine.continuedPhaseOffset(oldHz: 0.2, newHz: 0.1,
                                                          elapsed: 100, current: .nan),
                       0, accuracy: 1e-12, "NaN accumulator → reset to 0")
    }

    func testIntensityScalesBrightnessDepthWithinCap() {
        let g = guide()
        let soft = SessionEngine.plan(guide: g, elapsedSeconds: 30, coherence: 0.5, intensity: 0.2)
        let full = SessionEngine.plan(guide: g, elapsedSeconds: 30, coherence: 0.5, intensity: 1.0)
        XCTAssertLessThan(soft.entrainment.brightnessDelta, full.entrainment.brightnessDelta)
        XCTAssertLessThanOrEqual(full.entrainment.brightnessDelta, EntrainmentEngine.maxBrightnessDelta + 1e-9)
    }
}
