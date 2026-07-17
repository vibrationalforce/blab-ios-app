// RollFitMathTests.swift
// Echoel — boundaries of the piano roll's adaptive-fit math (founder 2026-07-17:
// "Piano Roll passt immer noch nicht in den Bildschirm … adaptives Design").
// Pure Foundation math — runs on CI without a SwiftUI host, same law as
// RollHitTestTests / AutomationCanvasMathTests.

import XCTest
import Foundation
@testable import Echoelmusic

final class RollFitMathTests: XCTestCase {

    // MARK: - fittedStepW

    func testFittedStepW_wholeBarFitsAPhoneWidth() {
        // iPhone 390pt, gutter 42 → (390 − 42) / 16 = 21.75pt per step.
        let w = RollFitMath.fittedStepW(availableWidth: 390, gutterWidth: 42,
                                        stepCount: 16, minStepW: 16, maxStepW: 56)
        XCTAssertEqual(w, 21.75, accuracy: 1e-9)
        // The fitted bar really spans the usable width.
        XCTAssertEqual(w * 16 + 42, 390, accuracy: 1e-9)
    }

    func testFittedStepW_narrowestSupportedPhone_staysAtOrAboveMin() {
        // 320pt (iPhone SE 1st-gen class): (320 − 42) / 16 = 17.375 ≥ min 16 —
        // the WHOLE 16-step bar fits every iPhone width without clamping.
        let w = RollFitMath.fittedStepW(availableWidth: 320, gutterWidth: 42,
                                        stepCount: 16, minStepW: 16, maxStepW: 56)
        XCTAssertEqual(w, 17.375, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(w, 16)
    }

    func testFittedStepW_clampsToMin_whenWidthIsTiny() {
        XCTAssertEqual(RollFitMath.fittedStepW(availableWidth: 100, gutterWidth: 42,
                                               stepCount: 16, minStepW: 16, maxStepW: 56),
                       16, "tiny width clamps to minStepW — roll scrolls instead")
    }

    func testFittedStepW_clampsToMax_onWideScreens() {
        XCTAssertEqual(RollFitMath.fittedStepW(availableWidth: 2000, gutterWidth: 42,
                                               stepCount: 16, minStepW: 16, maxStepW: 56),
                       56, "iPad-class width clamps to maxStepW, cells don't balloon")
    }

    func testFittedStepW_degenerateInputs_fallBackToMin() {
        XCTAssertEqual(RollFitMath.fittedStepW(availableWidth: 0, gutterWidth: 42,
                                               stepCount: 16, minStepW: 16, maxStepW: 56), 16)
        XCTAssertEqual(RollFitMath.fittedStepW(availableWidth: 30, gutterWidth: 42,
                                               stepCount: 16, minStepW: 16, maxStepW: 56),
                       16, "usable width ≤ 0 (gutter wider than view)")
        XCTAssertEqual(RollFitMath.fittedStepW(availableWidth: 390, gutterWidth: 42,
                                               stepCount: 0, minStepW: 16, maxStepW: 56),
                       16, "stepCount 0 guards the division")
        XCTAssertEqual(RollFitMath.fittedStepW(availableWidth: .nan, gutterWidth: 42,
                                               stepCount: 16, minStepW: 16, maxStepW: 56),
                       16, "non-finite width guards")
    }

    // MARK: - fittedRowH

    func testFittedRowH_typicalPhoneHeight_landsInBand() {
        // ~500pt roll area / 25 target rows = 20pt — inside the 16…26 band.
        XCTAssertEqual(RollFitMath.fittedRowH(availableHeight: 500, targetRows: 25,
                                              minRowH: 16, maxRowH: 26),
                       20, accuracy: 1e-9)
    }

    func testFittedRowH_clampsBothEnds() {
        XCTAssertEqual(RollFitMath.fittedRowH(availableHeight: 200, targetRows: 25,
                                              minRowH: 16, maxRowH: 26),
                       16, "short viewport clamps to the readable minimum")
        XCTAssertEqual(RollFitMath.fittedRowH(availableHeight: 2000, targetRows: 25,
                                              minRowH: 16, maxRowH: 26),
                       26, "tall viewport clamps to the max — no giant rows")
    }

    func testFittedRowH_degenerateInputs_fallBackToMin() {
        XCTAssertEqual(RollFitMath.fittedRowH(availableHeight: 0, targetRows: 25,
                                              minRowH: 16, maxRowH: 26), 16)
        XCTAssertEqual(RollFitMath.fittedRowH(availableHeight: 500, targetRows: 0,
                                              minRowH: 16, maxRowH: 26), 16)
        XCTAssertEqual(RollFitMath.fittedRowH(availableHeight: .infinity, targetRows: 25,
                                              minRowH: 16, maxRowH: 26), 16)
    }

    // MARK: - medianPitch

    func testMedianPitch_emptyClip_usesFallback() {
        XCTAssertEqual(RollFitMath.medianPitch(of: [], fallback: 60), 60,
                       "empty clip centers on the C4 region")
    }

    func testMedianPitch_singleNote_isThatNote() {
        XCTAssertEqual(RollFitMath.medianPitch(of: [43], fallback: 60), 43)
    }

    func testMedianPitch_oddCount_isTheMiddle() {
        XCTAssertEqual(RollFitMath.medianPitch(of: [72, 36, 60], fallback: 0), 60)
    }

    func testMedianPitch_evenCount_isTheLowerMedian() {
        // Lower median = a REAL note row (never an in-between average).
        XCTAssertEqual(RollFitMath.medianPitch(of: [36, 48, 60, 72], fallback: 0), 48)
    }

    // MARK: - centeredOffsetY

    func testCenteredOffsetY_centersMidContent() {
        // Target 500 in 1000-tall content, 400 viewport → offset 300.
        XCTAssertEqual(RollFitMath.centeredOffsetY(targetCenterY: 500,
                                                   visibleHeight: 400,
                                                   contentHeight: 1000),
                       300, accuracy: 1e-9)
    }

    func testCenteredOffsetY_clampsAtTopAndBottom() {
        XCTAssertEqual(RollFitMath.centeredOffsetY(targetCenterY: 50,
                                                   visibleHeight: 400,
                                                   contentHeight: 1000),
                       0, "near-top target clamps to 0 — no overscroll")
        XCTAssertEqual(RollFitMath.centeredOffsetY(targetCenterY: 990,
                                                   visibleHeight: 400,
                                                   contentHeight: 1000),
                       600, "near-bottom target clamps to content − viewport")
    }

    func testCenteredOffsetY_contentFitsViewport_staysAtTop() {
        XCTAssertEqual(RollFitMath.centeredOffsetY(targetCenterY: 100,
                                                   visibleHeight: 400,
                                                   contentHeight: 300), 0)
        XCTAssertEqual(RollFitMath.centeredOffsetY(targetCenterY: 100,
                                                   visibleHeight: 0,
                                                   contentHeight: 300),
                       0, "zero viewport guards")
    }
}
