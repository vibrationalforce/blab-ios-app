// TimelineDragMathTests.swift
// Echoel — #56 C4: the live drag preview must land EXACTLY where the release
// commits, so letting go is a visual no-op. These tests pin the pure preview
// math AND its parity with the commit formulas (replicated here from
// RegionBlockView's onEnded closures / TimelineRegion.trimmedStart).
// Pure value math — runs on the macOS SwiftPM CI (the repo has no Linux gate).

import XCTest
@testable import Echoelmusic

final class TimelineDragMathTests: XCTestCase {

    // ppb 24 → 1 beat = 24 pt, 1 tick = 0.05 pt; ticksPerBeat = 480.

    // MARK: - Guards

    func testDegenerateZoom_yieldsZeroNotNaN() {
        for ppb in [CGFloat(0), -5, .nan, .infinity] {
            XCTAssertEqual(TimelineDragMath.pointsPerTick(ppb: ppb), 0)
            XCTAssertEqual(TimelineDragMath.tickDelta(fromPoints: 48, ppb: ppb), 0)
            XCTAssertEqual(TimelineDragMath.movePreviewDeltaX(
                rawDeltaX: 48, startTick: 480, ppb: ppb, snap: .sixteenth), 0)
        }
        XCTAssertEqual(TimelineDragMath.laneShift(fromPoints: 30, laneHeight: 0), 0)
    }

    // MARK: - Move

    func testMovePreview_snapsToGrid_andParityWithCommit() {
        // +50 pt at ppb 24 = +1000 ticks; from 480 → raw 1480 → 1/16 grid (120) → 1440.
        let d = TimelineDragMath.movePreviewDeltaX(rawDeltaX: 50, startTick: 480,
                                                   ppb: 24, snap: .sixteenth)
        // Commit parity (RegionBlockView.moveGesture.onEnded, sans edge magnet):
        let deltaTicks = Int((50.0 / 24.0 * 480.0).rounded())
        let committed = TimelineSnap.snap(max(0, 480 + deltaTicks), to: .sixteenth)
        XCTAssertEqual(d, CGFloat(committed - 480) * 24 / 480)
        XCTAssertEqual(committed, 1440)
    }

    func testMovePreview_neverBeforeTickZero() {
        // Dragging far left from tick 240 clamps the preview at 0, like the commit.
        let d = TimelineDragMath.movePreviewDeltaX(rawDeltaX: -500, startTick: 240,
                                                   ppb: 24, snap: .off)
        XCTAssertEqual(d, CGFloat(0 - 240) * 24 / 480)
    }

    func testMovePreview_steplessWhenSnapOff() {
        // .off: raw tick delta survives (only the ≥0 clamp) — stepless contract.
        let d = TimelineDragMath.movePreviewDeltaX(rawDeltaX: 7, startTick: 4800,
                                                   ppb: 24, snap: .off)
        let rawTicks = Int((7.0 / 24.0 * 480.0).rounded())   // 140
        XCTAssertEqual(d, CGFloat(rawTicks) * 24 / 480)
    }

    func testLaneShift_roundsAtHalfRow() {
        XCTAssertEqual(TimelineDragMath.laneShift(fromPoints: 20, laneHeight: 56), 0)
        XCTAssertEqual(TimelineDragMath.laneShift(fromPoints: 29, laneHeight: 56), 1)
        XCTAssertEqual(TimelineDragMath.laneShift(fromPoints: -29, laneHeight: 56), -1)
        XCTAssertEqual(TimelineDragMath.laneShift(fromPoints: 85, laneHeight: 56), 2)
    }

    // MARK: - Lane-gate-aware move preview (#56 MEDIUM #2)

    /// Rows: 0 audio · 1 audio · 2 midi · 3 bio(midi). Mirrors TimelineStore's
    /// acceptance: same kind + in bounds + not bio, else the shift is REFUSED (0)
    /// and only the time move previews/commits.
    private let gates: [TimelineDragMath.LaneGate] = [
        .init(kind: .audio, isBio: false),
        .init(kind: .audio, isBio: false),
        .init(kind: .midi, isBio: false),
        .init(kind: .midi, isBio: true),
    ]

    func testGatedLaneShift_allowsSameKindNeighbour() {
        XCTAssertEqual(TimelineDragMath.gatedLaneShift(
            fromPoints: 56, laneHeight: 56, laneIndex: 0, gates: gates), 1)
        XCTAssertEqual(TimelineDragMath.gatedLaneShift(
            fromPoints: -56, laneHeight: 56, laneIndex: 1, gates: gates), -1)
    }

    func testGatedLaneShift_refusesKindMismatch_outOfBounds_andBio() {
        // audio → midi row: refused (preview must not seat where release rejects).
        XCTAssertEqual(TimelineDragMath.gatedLaneShift(
            fromPoints: 112, laneHeight: 56, laneIndex: 0, gates: gates), 0)
        // above the first row: out of bounds.
        XCTAssertEqual(TimelineDragMath.gatedLaneShift(
            fromPoints: -56, laneHeight: 56, laneIndex: 0, gates: gates), 0)
        // midi → bio(midi) row: same kind but bio is never a drop target.
        XCTAssertEqual(TimelineDragMath.gatedLaneShift(
            fromPoints: 56, laneHeight: 56, laneIndex: 2, gates: gates), 0)
        // unknown own index: defensive 0.
        XCTAssertEqual(TimelineDragMath.gatedLaneShift(
            fromPoints: 56, laneHeight: 56, laneIndex: 9, gates: gates), 0)
    }

    func testGatedLaneShift_zeroRawStaysZero() {
        XCTAssertEqual(TimelineDragMath.gatedLaneShift(
            fromPoints: 10, laneHeight: 56, laneIndex: 0, gates: gates), 0)
    }

    // MARK: - Trailing trim

    func testTrailingTrimPreview_snapsAndParityWithCommit() {
        // −37 pt at ppb 24 = −740 ticks; 1920 → raw 1180 → 1/16 grid → 1200.
        let d = TimelineDragMath.trailingTrimPreviewDeltaW(
            rawDeltaX: -37, lengthTicks: 1920, ppb: 24, snap: .sixteenth)
        // Commit parity (resizeGesture.onEnded):
        let deltaTicks = Int((-37.0 / 24.0 * 480.0).rounded())
        let committed = max(TimelineTime.ticksPerTransportStep,
                            TimelineSnap.snap(1920 + deltaTicks, to: .sixteenth))
        XCTAssertEqual(d, CGFloat(committed - 1920) * 24 / 480)
        XCTAssertEqual(committed, 1200)
    }

    func testTrailingTrimPreview_floorsAtMinLength() {
        // Shrinking far below one transport step previews AT the floor (120 ticks).
        let d = TimelineDragMath.trailingTrimPreviewDeltaW(
            rawDeltaX: -500, lengthTicks: 480, ppb: 24, snap: .off)
        XCTAssertEqual(d, CGFloat(TimelineTime.ticksPerTransportStep - 480) * 24 / 480)
    }

    // MARK: - Front trim

    func testFrontTrimPreview_zeroOffset_trimOnlyNeverExtends() {
        // Fresh region (offset 0/0): dragging LEFT must preview NO extension —
        // exactly what trimmedStart commits (minStart == startTick).
        let d = TimelineDragMath.frontTrimPreviewDeltaX(
            rawDeltaX: -60, startTick: 960, endTick: 2880,
            contentOffsetTicks: 0, contentOffsetSeconds: 0, ppb: 24, snap: .sixteenth)
        XCTAssertEqual(d, 0, "zero-offset region cannot reveal media before its start")
    }

    func testFrontTrimPreview_tickTwinFloorsExtension() {
        // Twin 240: extending left stops exactly 240 ticks before the start.
        let d = TimelineDragMath.frontTrimPreviewDeltaX(
            rawDeltaX: -600, startTick: 960, endTick: 2880,
            contentOffsetTicks: 240, contentOffsetSeconds: 0.25, ppb: 24, snap: .off)
        XCTAssertEqual(d, CGFloat((960 - 240) - 960) * 24 / 480)
    }

    func testFrontTrimPreview_snapAndEndClamp_parityWithTrimmedStart() {
        // Trim right toward the end: preview clamps at endTick − 1 and snaps —
        // parity with TimelineRegion.trimmedStart on a tick-twin region.
        let start = 480, end = 2400, twin = 480
        let raw: CGFloat = 200   // +4000 ticks → way past end
        let d = TimelineDragMath.frontTrimPreviewDeltaX(
            rawDeltaX: raw, startTick: start, endTick: end,
            contentOffsetTicks: twin, contentOffsetSeconds: 0.5, ppb: 24, snap: .sixteenth)
        let previewStart = start + Int((d / 24 * 480).rounded())
        XCTAssertEqual(previewStart, end - 1, "preview must stop at ≥ 1 tick, like the commit")

        // Mid-range parity: +10 pt → +200 ticks → snap 1/16.
        let d2 = TimelineDragMath.frontTrimPreviewDeltaX(
            rawDeltaX: 10, startTick: start, endTick: end,
            contentOffsetTicks: twin, contentOffsetSeconds: 0.5, ppb: 24, snap: .sixteenth)
        let deltaTicks = Int((10.0 / 24.0 * 480.0).rounded())
        let snapped = TimelineSnap.snap(start + deltaTicks, to: .sixteenth)
        // Commit path: trimRegionStart(toTick: max(0, snapped)) → trimmedStart clamps.
        let region = TimelineRegion(laneID: UUID(), clipID: UUID(), startTick: start,
                                    lengthTicks: end - start,
                                    contentOffsetSeconds: 0.5, contentOffsetTicks: twin)
        let committed = region.trimmedStart(toTick: max(0, snapped), bpm: 120)?.startTick
        XCTAssertEqual(start + Int((d2 / 24 * 480).rounded()), committed,
                       "preview start must equal the committed start")
    }

    func testFrontTrimPreview_legacySecondsOnly_skipsMediaFloor() {
        // Legacy (seconds > 0, twin 0): the preview lets the drag pass; only the
        // commit clamps (documented, release-safe residual).
        let d = TimelineDragMath.frontTrimPreviewDeltaX(
            rawDeltaX: -60, startTick: 960, endTick: 2880,
            contentOffsetTicks: 0, contentOffsetSeconds: 1.5, ppb: 24, snap: .off)
        XCTAssertLessThan(d, 0, "legacy region may preview a left-extend; commit clamps")
    }
}
