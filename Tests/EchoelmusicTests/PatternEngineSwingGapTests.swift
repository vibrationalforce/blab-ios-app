// PatternEngineSwingGapTests.swift
// Pins PatternEngine.swingGap — the single source of truth for the swung step
// interval, shared by advance() and the setTempo re-arm. Regression for the
// setTempo swing-parity inversion: the re-arm must key off the JUST-PLAYED step
// (currentStep − 1), because between ticks currentStep already points at the NEXT
// step; keying off currentStep inverted the swing for the step right after a
// mid-play tempo change.

import XCTest
@testable import Echoelmusic

@MainActor
final class PatternEngineSwingGapTests: XCTestCase {

    func testGapAfterEvenStep_isLengthened() {
        // After an even (down-beat) step the following gap is long → off-beat delayed.
        XCTAssertEqual(PatternEngine.swingGap(afterStep: 0, base: 1.0, swing: 0.5), 1.5, accuracy: 1e-12)
        XCTAssertEqual(PatternEngine.swingGap(afterStep: 2, base: 1.0, swing: 0.5), 1.5, accuracy: 1e-12)
    }

    func testGapAfterOddStep_isShortened() {
        XCTAssertEqual(PatternEngine.swingGap(afterStep: 1, base: 1.0, swing: 0.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(PatternEngine.swingGap(afterStep: 15, base: 1.0, swing: 0.5), 0.5, accuracy: 1e-12)
    }

    func testSwingClampedIntoWindow() {
        XCTAssertEqual(PatternEngine.swingGap(afterStep: 0, base: 1.0, swing: 0.9), 1.5, accuracy: 1e-12,
                       "swing clamps to 0.5")
        XCTAssertEqual(PatternEngine.swingGap(afterStep: 0, base: 1.0, swing: -0.3), 1.0, accuracy: 1e-12,
                       "negative swing clamps to 0 → straight")
    }

    func testZeroSwing_isStraight() {
        XCTAssertEqual(PatternEngine.swingGap(afterStep: 0, base: 1.0, swing: 0), 1.0, accuracy: 1e-12)
        XCTAssertEqual(PatternEngine.swingGap(afterStep: 1, base: 1.0, swing: 0), 1.0, accuracy: 1e-12)
    }

    /// Regression: after step 0 plays, currentStep == 1. The gap before step 1 must
    /// be the LONG (post-downbeat) gap. Keying off currentStep (odd) would wrongly
    /// give the SHORT gap — the inversion the fix removes.
    func testSetTempoReArm_usesJustPlayedStep_notCurrentStep() {
        let base = 60.0 / 140.0 / 4.0
        let currentStep = 1                       // step 0 just played
        let justPlayed = (currentStep + PatternEngine.stepCount - 1) % PatternEngine.stepCount
        XCTAssertEqual(justPlayed, 0)
        let correct = PatternEngine.swingGap(afterStep: justPlayed, base: base, swing: 0.5)
        XCTAssertEqual(correct, base * 1.5, accuracy: 1e-12,
                       "gap before off-beat step 1 is the long, post-downbeat gap")
        let buggy = PatternEngine.swingGap(afterStep: currentStep, base: base, swing: 0.5)
        XCTAssertEqual(buggy, base * 0.5, accuracy: 1e-12)
        XCTAssertNotEqual(correct, buggy, "the difference IS the inversion the fix removes")
    }

    /// Wrap: after the last step (15, odd) plays, currentStep == 0. justPlayed = 15,
    /// so the gap before step 0 is the short (post-odd) gap.
    func testSetTempoReArm_wrapAtStepZero_usesStep15Parity() {
        let currentStep = 0
        let justPlayed = (currentStep + PatternEngine.stepCount - 1) % PatternEngine.stepCount
        XCTAssertEqual(justPlayed, 15)
        XCTAssertEqual(PatternEngine.swingGap(afterStep: justPlayed, base: 1.0, swing: 0.5), 0.5, accuracy: 1e-12,
                       "after odd step 15 the gap before step 0 is short")
    }
}
