// BioPhaserTests.swift
// Echoel — EchoelLux L3: an MA3-style bio-phaser. Each fixture gets a fanned phase
// offset; the base phase is body-driven (breath passthrough or heart integration).
// The output feeds the dimmer, so FLASH-SAFETY is the contract: advance ≤3 Hz AND
// per-tick luminance slew-limited, so even a 200 bpm heart can never strobe.

import XCTest
import Foundation
@testable import Echoelmusic

final class BioPhaserTests: XCTestCase {

    private func frame(hr: Float = 60, breath: Float = 0) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: hr, hrvNormalized: 0.5,
                       breathRate: 6, breathPhase: breath, coherence: 0.5,
                       motionEnergy: 0, source: .fallback)
    }

    // MARK: - Pure formulas

    func testPhaseOffsets_fanEvenly_withEdges() {
        XCTAssertEqual(BioPhaser.phaseOffsets(count: 0, spread: 1), [])
        XCTAssertEqual(BioPhaser.phaseOffsets(count: 1, spread: 1), [0])
        XCTAssertEqual(BioPhaser.phaseOffsets(count: 4, spread: 1), [0, 0.25, 0.5, 0.75])
        XCTAssertEqual(BioPhaser.phaseOffsets(count: 4, spread: 0.5), [0, 0.125, 0.25, 0.375])
    }

    func testValue_isRaisedSineAtBoundaries() {
        XCTAssertEqual(BioPhaser.value(bioPhase: 0, offset: 0), 0.5, accuracy: 1e-6)
        XCTAssertEqual(BioPhaser.value(bioPhase: 0.25, offset: 0), 1.0, accuracy: 1e-6)
        XCTAssertEqual(BioPhaser.value(bioPhase: 0.5, offset: 0), 0.5, accuracy: 1e-6)
        XCTAssertEqual(BioPhaser.value(bioPhase: 0.75, offset: 0), 0.0, accuracy: 1e-6)
    }

    // MARK: - Base phase sources

    func testBreathSource_isPassthroughOnFirstFrame() {
        var phaser = BioPhaser(source: .breath, count: 1, spread: 1)
        let out = phaser.step(frame: frame(breath: 0.3), dt: 0.1)
        XCTAssertEqual(out[0], BioPhaser.value(bioPhase: 0.3, offset: 0), accuracy: 1e-6,
                       "breath phase drives the base directly")
    }

    func testHeartPhase_accumulatesAndWrapsInUnitInterval() {
        var phaser = BioPhaser(source: .heart, count: 1, spread: 1)
        // 120 bpm → 2 Hz → +0.2 phase per 0.1 s tick.
        for step in 1...12 {
            _ = phaser.step(frame: frame(hr: 120), dt: 0.1)
            XCTAssertGreaterThanOrEqual(phaser.heartPhase, 0)
            XCTAssertLessThan(phaser.heartPhase, 1, "heart phase stays wrapped in [0,1) (step \(step))")
        }
        // After 5 ticks of +0.2 it has wrapped once (1.0 → 0.0).
        var p2 = BioPhaser(source: .heart, count: 1, spread: 1)
        for _ in 0..<3 { _ = p2.step(frame: frame(hr: 120), dt: 0.1) }
        XCTAssertEqual(p2.heartPhase, 0.6, accuracy: 1e-5)
    }

    // MARK: - Flash safety (the whole point)

    func testHeartAdvance_isClampedToThreeHz() {
        // 300 bpm = 5 Hz would advance 0.5/tick; the WCAG clamp caps it at 3 Hz = 0.3/tick.
        var phaser = BioPhaser(source: .heart, count: 1, spread: 1)
        _ = phaser.step(frame: frame(hr: 300), dt: 0.1)
        XCTAssertEqual(phaser.heartPhase, 0.3, accuracy: 1e-5,
                       "advance clamped to FlashGuard.safeFrequency (≤3 Hz)")
    }

    func testPerTickLuminanceDeltaNeverExceedsSlewCap_evenAt180bpm() {
        var phaser = BioPhaser(source: .heart, count: 3, spread: 1)
        let dt = 0.1
        let perTickCap = BioPhaser.maxLuminancePerSecond * dt   // rate-based → poll-invariant
        var outputs: [[Float]] = []
        for _ in 0..<50 { outputs.append(phaser.step(frame: frame(hr: 180), dt: dt)) }
        for t in 1..<outputs.count {
            for i in 0..<3 {
                let delta = abs(outputs[t][i] - outputs[t - 1][i])
                XCTAssertLessThanOrEqual(Double(delta), perTickCap + 1e-6,
                                         "fixture \(i) step \(t) must not jump more than the slew cap")
            }
        }
    }

    func testSlewCapIsRateBased_pollRateInvariant() {
        // The per-tick cap scales with dt, so doubling the poll rate halves the per-tick
        // move — the per-SECOND flash bound (and thus WCAG safety) is independent of poll rate.
        var slow = BioPhaser(source: .breath, count: 1, spread: 1)
        var fast = BioPhaser(source: .breath, count: 1, spread: 1)
        _ = slow.step(frame: frame(breath: 0), dt: 0.1)   // seed both from the same base
        _ = fast.step(frame: frame(breath: 0), dt: 0.05)
        let slowStep = abs(slow.step(frame: frame(breath: 0.25), dt: 0.1)[0]
                           - BioPhaser.value(bioPhase: 0, offset: 0))
        let fastStep = abs(fast.step(frame: frame(breath: 0.25), dt: 0.05)[0]
                           - BioPhaser.value(bioPhase: 0, offset: 0))
        XCTAssertLessThanOrEqual(Double(slowStep), BioPhaser.maxLuminancePerSecond * 0.1 + 1e-6)
        XCTAssertLessThanOrEqual(Double(fastStep), BioPhaser.maxLuminancePerSecond * 0.05 + 1e-6)
        XCTAssertLessThan(fastStep, slowStep, "a faster poll takes a smaller per-tick step")
    }

    // MARK: - Robustness (nil / NaN)

    func testNilFrame_holdsLastOutput() {
        var phaser = BioPhaser(source: .breath, count: 2, spread: 1)
        let a = phaser.step(frame: frame(breath: 0.4), dt: 0.1)
        let held = phaser.step(frame: nil, dt: 0.1)
        XCTAssertEqual(held, a, "a stalled body freezes the look, it does not snap to black")
    }

    func testNilFrame_beforeAnyData_isZeroes() {
        var phaser = BioPhaser(source: .breath, count: 3, spread: 1)
        XCTAssertEqual(phaser.step(frame: nil, dt: 0.1), [0, 0, 0])
    }

    func testNaNInfInputs_sanitizedToFiniteOutput() {
        var breathP = BioPhaser(source: .breath, count: 2, spread: 1)
        for out in breathP.step(frame: frame(breath: .nan), dt: 0.1) {
            XCTAssertTrue(out.isFinite)
        }
        var heartP = BioPhaser(source: .heart, count: 2, spread: 1)
        let out = heartP.step(frame: frame(hr: .infinity), dt: .nan)
        XCTAssertTrue(out.allSatisfy { $0.isFinite })
        XCTAssertTrue(heartP.heartPhase.isFinite)
    }

    // MARK: - Determinism

    func testDeterministic_sameSequenceSameOutput() {
        var a = BioPhaser(source: .heart, count: 4, spread: 0.75)
        var b = BioPhaser(source: .heart, count: 4, spread: 0.75)
        for hr: Float in [70, 90, 130, 60, 110] {
            XCTAssertEqual(a.step(frame: frame(hr: hr), dt: 0.1),
                           b.step(frame: frame(hr: hr), dt: 0.1),
                           "no RNG, no wall clock → identical")
        }
    }
}
