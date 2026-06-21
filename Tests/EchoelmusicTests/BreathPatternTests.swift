// BreathPatternTests.swift
// Echoel — the multi-phase breath pattern core: safe segment clamping, the
// raised-cosine amplitude curve (flat on holds), and the curated techniques.

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
@testable import Echoelmusic

final class BreathPatternTests: XCTestCase {

    func testResonance_isNoHold_sixPerMinute_exhaleEmphasis() {
        let p = BreathPattern.resonance
        XCTAssertFalse(p.hasHolds)
        XCTAssertEqual(p.cycleSeconds, 10, accuracy: 1e-9)
        XCTAssertEqual(p.ratePerMinute, 6, accuracy: 1e-9)
        // Exhale longer than inhale (vagal emphasis).
        let inhale = p.segments.first { $0.kind == .inhale }?.seconds ?? 0
        let exhale = p.segments.first { $0.kind == .exhale }?.seconds ?? 0
        XCTAssertGreaterThan(exhale, inhale)
    }

    func testBox_hasHolds_andFourEqualSegments() {
        let p = BreathPattern.box
        XCTAssertTrue(p.hasHolds)
        XCTAssertEqual(p.segments.count, 4)
        XCTAssertEqual(p.cycleSeconds, 16, accuracy: 1e-9)
        XCTAssertEqual(Set(p.segments.map(\.kind)),
                       [.inhale, .holdFull, .exhale, .holdEmpty])
    }

    func test478_segmentsMatchTechnique() {
        let p = BreathPattern.relaxing478
        XCTAssertEqual(p.segments.map(\.seconds), [4, 7, 8])
        XCTAssertEqual(p.segments.map(\.kind), [.inhale, .holdFull, .exhale])
    }

    func testCurated_resonanceIsFirst() {
        XCTAssertEqual(BreathPattern.curated.first?.id, "resonance")
    }

    func testSafetyClamp_capsLongHoldsAndActivePhases() {
        let p = BreathPattern(
            id: "x", name: "x", evidence: "",
            segments: [.init(kind: .inhale, seconds: 999),       // → maxActive
                       .init(kind: .holdFull, seconds: 999),     // → maxHoldFull
                       .init(kind: .holdEmpty, seconds: 999),    // → maxHoldEmpty (tighter)
                       .init(kind: .exhale, seconds: 5)]
        )
        XCTAssertEqual(p.segments[0].seconds, BreathPattern.maxActiveSeconds, accuracy: 1e-9)
        XCTAssertEqual(p.segments[1].seconds, BreathPattern.maxHoldFullSeconds, accuracy: 1e-9)
        XCTAssertEqual(p.segments[2].seconds, BreathPattern.maxHoldEmptySeconds, accuracy: 1e-9)
        // Empty-lung holds are capped tighter than full-lung holds (higher risk).
        XCTAssertLessThan(BreathPattern.maxHoldEmptySeconds, BreathPattern.maxHoldFullSeconds)
    }

    func testHoldContraindications_pointToResonanceForHRV_andSelfObservation() {
        let joined = BreathPattern.holdContraindications.joined(separator: " ").lowercased()
        XCTAssertFalse(BreathPattern.holdContraindications.isEmpty)
        XCTAssertTrue(joined.contains("resonance"))          // steer HRV users to the no-hold path
        XCTAssertTrue(joined.contains("self-observation"))   // non-medical framing preserved
        XCTAssertTrue(joined.contains("strain"))             // explicit no-strain guidance
    }

    func testInit_dropsNonPositiveSegments_neverEmpty() {
        let p = BreathPattern(
            id: "x", name: "x", evidence: "",
            segments: [.init(kind: .inhale, seconds: 0),
                       .init(kind: .exhale, seconds: -3),
                       .init(kind: .holdFull, seconds: .nan)]
        )
        XCTAssertFalse(p.segments.isEmpty)         // falls back to a safe default
        XCTAssertGreaterThan(p.cycleSeconds, 0)
    }

    func testSample_amplitudeAlwaysInRange_overWholeCycle() {
        for p in BreathPattern.curated {
            var t = 0.0
            while t <= p.cycleSeconds + 0.01 {
                let s = p.sample(atCycleTime: t)
                XCTAssertGreaterThanOrEqual(s.amplitude, 0.0, "\(p.id) @\(t)")
                XCTAssertLessThanOrEqual(s.amplitude, 1.0, "\(p.id) @\(t)")
                t += 0.1
            }
        }
    }

    func testSample_inhaleRisesFromEmptyToFull() {
        let p = BreathPattern.resonance // inhale 4 then exhale 6
        let start = p.sample(atCycleTime: 0.0)
        let nearFull = p.sample(atCycleTime: 3.99)
        XCTAssertEqual(start.kind, .inhale)
        XCTAssertEqual(start.instruction, "Breathe in")
        XCTAssertLessThan(start.amplitude, 0.05)        // empty at inhale start
        XCTAssertGreaterThan(nearFull.amplitude, 0.95)  // full at inhale end
    }

    func testSample_holdFull_staysAtOne_andSaysHold() {
        let p = BreathPattern.box // inhale 0-4, holdFull 4-8
        let s = p.sample(atCycleTime: 6.0)
        XCTAssertEqual(s.kind, .holdFull)
        XCTAssertEqual(s.instruction, "Hold")
        XCTAssertEqual(s.amplitude, 1.0, accuracy: 1e-9)
    }

    func testSample_holdEmpty_staysAtZero() {
        let p = BreathPattern.box // ... exhale 8-12, holdEmpty 12-16
        let s = p.sample(atCycleTime: 14.0)
        XCTAssertEqual(s.kind, .holdEmpty)
        XCTAssertEqual(s.amplitude, 0.0, accuracy: 1e-9)
    }

    func testSample_isCyclic() {
        let p = BreathPattern.box
        let a = p.sample(atCycleTime: 2.0)
        let b = p.sample(atCycleTime: 2.0 + p.cycleSeconds)
        XCTAssertEqual(a.amplitude, b.amplitude, accuracy: 1e-9)
        XCTAssertEqual(a.kind, b.kind)
    }

    func testSample_continuousAcrossInhaleToHoldBoundary() {
        let p = BreathPattern.box
        let beforeBoundary = p.sample(atCycleTime: 3.99).amplitude  // end of inhale ~1
        let afterBoundary  = p.sample(atCycleTime: 4.01).amplitude  // start of holdFull = 1
        XCTAssertEqual(beforeBoundary, afterBoundary, accuracy: 0.02)
    }
}
#endif
