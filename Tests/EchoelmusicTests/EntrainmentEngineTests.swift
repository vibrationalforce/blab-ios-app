//
//  EntrainmentEngineTests.swift
//  Echoelmusic — Bio
//
//  Proves the SAFETY ENVELOPE of the bio-paced Session core is inviolable: the
//  visual layer never flickers faster than 3 Hz, never inside the 4–70 Hz hazardous
//  band, never on saturated red, and luminance depth stays capped — for ANY input,
//  including hostile/degenerate ones. Plus the personal-target mapping and the pure
//  phase/gate math. These are the invariants that keep a "brainwave" ambition from
//  becoming a photosensitive hazard.
//

import XCTest
@testable import Echoelmusic

final class EntrainmentEngineTests: XCTestCase {

    private let acc = 1e-9

    // MARK: - Personal target (cardiac/respiratory only)

    func testBreathTargetMapsBpmToHz() {
        // 6 breaths/min = 0.1 Hz (the canonical resonance pace).
        XCTAssertEqual(EntrainmentEngine.breathTargetHz(breathsPerMinute: 6), 0.1, accuracy: acc)
        // 4.5/min = 0.075 Hz (fastest-relaxation edge of the window).
        XCTAssertEqual(EntrainmentEngine.breathTargetHz(breathsPerMinute: 4.5), 0.075, accuracy: acc)
    }

    func testBreathTargetClampsToSafeWindow() {
        // Below the floor clamps up to 4.5/min; above the ceiling clamps to 7/min.
        XCTAssertEqual(EntrainmentEngine.breathTargetHz(breathsPerMinute: 1), 4.5 / 60, accuracy: acc)
        XCTAssertEqual(EntrainmentEngine.breathTargetHz(breathsPerMinute: 30), 7.0 / 60, accuracy: acc)
    }

    func testBreathTargetGuardsDegenerateInput() {
        for bad in [0.0, -5, .nan, .infinity] {
            XCTAssertEqual(EntrainmentEngine.breathTargetHz(breathsPerMinute: bad), 0.1, accuracy: acc,
                           "degenerate bpm \(bad) falls back to the canonical 6/min")
        }
    }

    // MARK: - THE SAFETY ENVELOPE (the non-negotiable invariants)

    func testVisualNeverExceedsThreeHzForAnyTarget() {
        // Sweep an enormous range of target rates — the visual pulse must ALWAYS be
        // ≤ 3 Hz and NEVER inside the 4–70 Hz hazardous band.
        var target = 0.01
        while target <= 500 {
            let plan = EntrainmentEngine.plan(targetHz: target, intensity: 1.0)
            if !plan.visualIsSteady {
                XCTAssertLessThanOrEqual(plan.visualPulseHz, EntrainmentEngine.maxVisualFlashHz + 1e-9,
                                         "target \(target) → visual \(plan.visualPulseHz) exceeds 3 Hz")
                XCTAssertFalse(EntrainmentEngine.isInHazardBand(plan.visualPulseHz),
                               "target \(target) → visual \(plan.visualPulseHz) is in the hazardous band")
            }
            target *= 1.3
        }
    }

    func testHazardBandTargetsFoldToSafeSubHarmonic() {
        // 10 Hz (alpha-ish) is hazardous → fold 10→5→2.5 Hz (safe, ≤3, out of band).
        let plan = EntrainmentEngine.plan(targetHz: 10, intensity: 1)
        XCTAssertFalse(plan.visualIsSteady)
        XCTAssertEqual(plan.visualPulseHz, 2.5, accuracy: acc)
        XCTAssertFalse(EntrainmentEngine.isInHazardBand(plan.visualPulseHz))
        // The AUDIO pulse still carries the true 10 Hz (audio isn't a flash hazard).
        XCTAssertEqual(plan.audioPulseHz, 10, accuracy: acc)
    }

    func testFortyHzGammaVisualIsFoldedFlashSafe() {
        // The 40 Hz "gamma" ambition: audio may carry 40 Hz, but the light must fold
        // to a safe sub-harmonic (40→20→10→5→2.5) — never a 40 Hz strobe.
        let plan = EntrainmentEngine.plan(targetHz: 40, intensity: 1)
        XCTAssertEqual(plan.audioPulseHz, 40, accuracy: acc)
        XCTAssertLessThanOrEqual(plan.visualPulseHz, EntrainmentEngine.maxVisualFlashHz)
        XCTAssertFalse(EntrainmentEngine.isInHazardBand(plan.visualPulseHz))
    }

    func testSafeLowTargetPassesThrough() {
        // A slow breath pace (0.1 Hz) is already safe → used verbatim on both layers.
        let plan = EntrainmentEngine.plan(targetHz: 0.1, intensity: 0.8)
        XCTAssertEqual(plan.visualPulseHz, 0.1, accuracy: acc)
        XCTAssertEqual(plan.audioPulseHz, 0.1, accuracy: acc)
        XCTAssertFalse(plan.visualIsSteady)
    }

    func testFlickerNeverAllowsSaturatedRed() {
        for target in [0.1, 2, 3, 8, 10, 40] {
            let plan = EntrainmentEngine.plan(targetHz: Double(target), intensity: 1)
            XCTAssertFalse(plan.allowSaturatedRedFlicker,
                           "saturated-red flicker must never be permitted (target \(target))")
        }
    }

    func testBrightnessDepthIsCapped() {
        // Even at full intensity the luminance-modulation depth stays ≤ the cap.
        let plan = EntrainmentEngine.plan(targetHz: 0.1, intensity: 1)
        XCTAssertLessThanOrEqual(plan.brightnessDelta, EntrainmentEngine.maxBrightnessDelta + 1e-9)
        // Intensity scales it linearly; out-of-range intensity is clamped.
        XCTAssertEqual(EntrainmentEngine.plan(targetHz: 0.1, intensity: 0.5).brightnessDelta,
                       0.5 * EntrainmentEngine.maxBrightnessDelta, accuracy: acc)
        XCTAssertEqual(EntrainmentEngine.plan(targetHz: 0.1, intensity: 5).brightnessDelta,
                       EntrainmentEngine.maxBrightnessDelta, accuracy: acc)
        XCTAssertEqual(EntrainmentEngine.plan(targetHz: 0.1, intensity: .nan).brightnessDelta,
                       0, accuracy: acc)
    }

    func testDegenerateTargetGoesSteady() {
        for bad in [0.0, -1, .nan, .infinity] {
            let plan = EntrainmentEngine.plan(targetHz: bad, intensity: 1)
            XCTAssertEqual(plan, .steady, "degenerate target \(bad) → the safe steady plan")
            XCTAssertTrue(plan.visualIsSteady)
            XCTAssertEqual(plan.visualPulseHz, 0)
        }
    }

    func testSafeVisualHzReturnsNilWhenNoSafeSubHarmonic() {
        // A rate whose every octave-fold lands in the hazard band before reaching ≤3 Hz
        // has no safe sub-harmonic. (Any real audio rate folds to ≤3 eventually, so this
        // guards the explicit invariant rather than a reachable production case.)
        XCTAssertNotNil(EntrainmentEngine.safeVisualHz(for: 8))     // 8→4(band)→2 ✓ folds through to 2
        XCTAssertNil(EntrainmentEngine.safeVisualHz(for: 0))
        XCTAssertNil(EntrainmentEngine.safeVisualHz(for: .nan))
    }

    // MARK: - Phase / gate (pure, render-thread math)

    func testPhaseIsInUnitInterval() {
        for t in stride(from: 0.0, through: 5.0, by: 0.137) {
            let p = EntrainmentEngine.phase(atSeconds: t, hz: 0.1)
            XCTAssertGreaterThanOrEqual(p, 0)
            XCTAssertLessThan(p, 1)
        }
    }

    func testPhaseWrapsEachCycle() {
        // At 1 Hz, phase at t and t+1 match (one full cycle later).
        XCTAssertEqual(EntrainmentEngine.phase(atSeconds: 0.25, hz: 1),
                       EntrainmentEngine.phase(atSeconds: 1.25, hz: 1), accuracy: 1e-12)
        XCTAssertEqual(EntrainmentEngine.phase(atSeconds: 0.0, hz: 2), 0, accuracy: acc)
        XCTAssertEqual(EntrainmentEngine.phase(atSeconds: 0.25, hz: 1), 0.25, accuracy: acc)
    }

    func testPhaseGuardsBadRate() {
        XCTAssertEqual(EntrainmentEngine.phase(atSeconds: 3, hz: 0), 0)
        XCTAssertEqual(EntrainmentEngine.phase(atSeconds: 3, hz: .nan), 0)
        XCTAssertEqual(EntrainmentEngine.phase(atSeconds: .infinity, hz: 1), 0)
    }

    func testGateIsRaisedCosinePeakingMidCycle() {
        // 0 at phase 0, 1 at phase 0.5, 0 again at phase 1 — smooth, click-free.
        XCTAssertEqual(EntrainmentEngine.gate(atSeconds: 0.0, hz: 1), 0, accuracy: 1e-12)
        XCTAssertEqual(EntrainmentEngine.gate(atSeconds: 0.5, hz: 1), 1, accuracy: 1e-12)
        XCTAssertEqual(EntrainmentEngine.gate(atSeconds: 1.0, hz: 1), 0, accuracy: 1e-9)
        // Bounded 0…1 across the cycle.
        for t in stride(from: 0.0, through: 2.0, by: 0.05) {
            let g = EntrainmentEngine.gate(atSeconds: t, hz: 0.7)
            XCTAssertGreaterThanOrEqual(g, -1e-12)
            XCTAssertLessThanOrEqual(g, 1 + 1e-12)
        }
    }
}
