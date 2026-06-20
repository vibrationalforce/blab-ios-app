// HapticControllerTests.swift
// Echoelmusic — the non-availability coordinator over HapticEngine.
// Pure step→cue logic is fully covered; engine paths are crash-safe smoke tests
// (CI has no Taptic Engine, so playback is a no-op).

#if canImport(CoreHaptics)
import XCTest
@testable import Echoelmusic

@MainActor
final class HapticControllerTests: XCTestCase {

    // MARK: - armed model

    func testDefault_isDisabled() {
        XCTAssertFalse(HapticController().isEnabled)
    }

    func testToggle_startsAndStops_withoutCrash() {
        let c = HapticController()
        c.isEnabled = true   // starts engine (no-op without hardware)
        c.isEnabled = false  // stops
        c.isEnabled = true
        XCTAssertTrue(c.isEnabled)
    }

    func testDrivers_whenDisabled_areNoOp() {
        let c = HapticController()
        c.tapBeat(step: 0)
        c.breath(phase: 0.5, coherence: 0.5)
        XCTAssertFalse(c.isEnabled)
    }

    func testDrivers_whenEnabled_doNotCrash() {
        let c = HapticController()
        c.isEnabled = true
        for step in 0..<16 { c.tapBeat(step: step) }
        c.breath(phase: 0.5, coherence: 0.2)
        XCTAssertTrue(c.isEnabled, "driving the controller must not disable it")
    }

    // MARK: - pure pulse gate

    func testIsPulseStep_quartersOnly() {
        for q in [0, 4, 8, 12] { XCTAssertTrue(HapticController.isPulseStep(q), "step \(q)") }
        for o in [1, 2, 3, 5, 7, 13, 15] { XCTAssertFalse(HapticController.isPulseStep(o), "step \(o)") }
    }

    func testIsPulseStep_wrapsAndHandlesNegatives() {
        XCTAssertTrue(HapticController.isPulseStep(16))   // wraps → 0
        XCTAssertTrue(HapticController.isPulseStep(-4))   // floored mod → 12
        XCTAssertFalse(HapticController.isPulseStep(-1))  // floored mod → 15
    }

    // MARK: - pure beat cue

    func testBeatCue_downbeatStrong_otherQuartersSoft() {
        XCTAssertEqual(HapticController.beatCue(forStep: 0).intensity, 1.0, accuracy: 1e-6)   // downbeat
        XCTAssertEqual(HapticController.beatCue(forStep: 4).intensity, 0.45, accuracy: 1e-6)  // soft quarter
        XCTAssertEqual(HapticController.beatCue(forStep: 16).intensity, 1.0, accuracy: 1e-6)  // wraps → downbeat
        XCTAssertEqual(HapticController.beatCue(forStep: 0).kind, .transient)
    }
}
#endif
