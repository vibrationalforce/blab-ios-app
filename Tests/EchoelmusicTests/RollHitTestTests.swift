// RollHitTestTests.swift
// Echoel — pins the pure piano-roll hit-test (#58 Slice 1). Foundation-only, so
// it runs on CI without a SwiftUI host. Covers every branch move + resize +
// create will depend on: body vs. right-edge boundary, edge cap on short notes,
// topmost-wins overlap, empty-cell clamping, and degenerate geometry.

import XCTest
@testable import Echoelmusic

final class RollHitTestTests: XCTestCase {

    // Canonical geometry for the tests.
    private let stepW = 26.0
    private let rowH = 22.0
    private let high = PianoRollModel.highPitch      // top row pitch
    private let low = PianoRollModel.lowPitch        // bottom row pitch
    private let steps = PianoRollModel.stepCount     // 16
    private let slop = 8.0

    /// A 4-step note at pitch `high-2`, starting at step 3.
    private func sampleNote() -> Note {
        Note(pitch: high - 2, startStep: 3, lengthSteps: 4, velocity: 0.8)
    }

    private func classify(_ x: Double, _ y: Double, _ notes: [Note]) -> RollHit {
        RollHitTest.classify(x: x, y: y, notes: notes,
                             stepW: stepW, rowH: rowH,
                             highPitch: high, lowPitch: low,
                             stepCount: steps, edgeSlop: slop)
    }

    func testEmptyCanvas_returnsClampedCell() {
        // A point in row 0, step 5 → pitch high, step 5.
        let hit = classify(5.5 * stepW, 0.5 * rowH, [])
        XCTAssertEqual(hit, .empty(pitch: high, step: 5))
    }

    func testBodyHit_returnsMoveTarget() {
        let n = sampleNote()
        // Middle of the note: step 4.5 → well inside [3,7), edge zone is the last
        // 8pt of a 104pt-wide note, so the centre is unambiguously body.
        let x = (Double(n.startStep) + 1.5) * stepW
        let y = (Double(high - n.pitch) + 0.5) * rowH
        XCTAssertEqual(classify(x, y, [n]), .body(id: n.id))
    }

    func testRightEdge_withinSlop_returnsResizeTarget() {
        let n = sampleNote()
        let noteRight = Double(n.startStep + n.lengthSteps) * stepW   // exclusive edge
        // 2pt inside the right edge → inside the 8pt slop zone.
        let x = noteRight - 2.0
        let y = (Double(high - n.pitch) + 0.5) * rowH
        XCTAssertEqual(classify(x, y, [n]), .rightEdge(id: n.id))
    }

    func testJustBeforeSlop_staysBody() {
        let n = sampleNote()
        let noteRight = Double(n.startStep + n.lengthSteps) * stepW
        // 9pt inside (> 8pt slop) → still body.
        let x = noteRight - 9.0
        let y = (Double(high - n.pitch) + 0.5) * rowH
        XCTAssertEqual(classify(x, y, [n]), .body(id: n.id))
    }

    func testOneStepNote_slopCappedToHalf_bodyStaysGraspable() {
        // A 1-step note is 26pt wide; slop would be 8 but is capped to 13 (half),
        // so 8 is used. The left half must read as body, not edge.
        let n = Note(pitch: high - 5, startStep: 2, lengthSteps: 1, velocity: 0.5)
        let noteLeft = Double(n.startStep) * stepW
        let y = (Double(high - n.pitch) + 0.5) * rowH
        // 3pt from the left edge → body.
        XCTAssertEqual(classify(noteLeft + 3.0, y, [n]), .body(id: n.id))
        // 2pt from the right edge → edge.
        let noteRight = noteLeft + stepW
        XCTAssertEqual(classify(noteRight - 2.0, y, [n]), .rightEdge(id: n.id))
    }

    func testOverlap_topmostWins() {
        // Two notes on the SAME cell; the later one is drawn on top.
        let under = Note(pitch: high - 1, startStep: 0, lengthSteps: 2, velocity: 0.4)
        let over = Note(pitch: high - 1, startStep: 0, lengthSteps: 2, velocity: 0.9)
        let x = 0.5 * stepW
        let y = (Double(high - over.pitch) + 0.5) * rowH
        XCTAssertEqual(classify(x, y, [under, over]), .body(id: over.id))
    }

    func testMissOnNoteRow_butDifferentStep_isEmpty() {
        let n = sampleNote()
        // Same row, but step 10 (note spans 3..<7) → empty cell at that pitch/step.
        let x = 10.5 * stepW
        let y = (Double(high - n.pitch) + 0.5) * rowH
        XCTAssertEqual(classify(x, y, [n]), .empty(pitch: n.pitch, step: 10))
    }

    func testEmptyCell_clampsBeyondBounds() {
        // Past the right edge and above the top → clamps to last step / top pitch.
        let hit = classify(999.0, -50.0, [])
        XCTAssertEqual(hit, .empty(pitch: high, step: steps - 1))
    }

    func testDegenerateGeometry_returnsSafeEmpty() {
        let hit = RollHitTest.classify(x: 10, y: 10, notes: [sampleNote()],
                                       stepW: 0, rowH: 0,
                                       highPitch: high, lowPitch: low,
                                       stepCount: steps, edgeSlop: slop)
        // Zero cell size → no note hit, safe empty at the low pitch / step 0.
        XCTAssertEqual(hit, .empty(pitch: low, step: 0))
    }
}
