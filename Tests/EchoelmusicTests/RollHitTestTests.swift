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

    func testExactSlopThreshold_isInclusivelyEdge() {
        // The slop boundary itself: x == noteRight - slop must read as edge (the
        // resize zone is the half-open [right-slop, right)). Pins `>=` against a
        // regression to `>` — which every other test would still pass.
        let n = sampleNote()
        let noteRight = Double(n.startStep + n.lengthSteps) * stepW
        let x = noteRight - slop                       // exactly on the threshold
        let y = (Double(high - n.pitch) + 0.5) * rowH
        XCTAssertEqual(classify(x, y, [n]), .rightEdge(id: n.id))
    }

    func testAdjacentNotes_sharedBoundaryHitsRightNeighbourOnly() {
        // A ends at step 7; B starts at step 7 — same pitch, touching. A point
        // exactly on the shared column line belongs to B (left-inclusive),
        // never A (right-exclusive). Pins the half-open `< noteX+noteW`.
        let p = high - 4
        let a = Note(pitch: p, startStep: 3, lengthSteps: 4, velocity: 0.5) // steps 3..<7
        let b = Note(pitch: p, startStep: 7, lengthSteps: 2, velocity: 0.5) // steps 7..<9
        let sharedX = Double(7) * stepW                // A's exclusive right == B's left
        let y = (Double(high - p) + 0.5) * rowH
        XCTAssertEqual(classify(sharedX, y, [a, b]), .body(id: b.id))
    }

    func testOneStepNote_slopCapBinds_whenSlopExceedsHalf() {
        // slop=20 on a 26pt note: the cap clamps it to noteW/2 = 13. Edge zone is
        // the last 13pt; the first 13pt stays body. Exercises the cap branch that
        // testOneStepNote (slop=8 < 13) never took.
        let n = Note(pitch: high - 6, startStep: 4, lengthSteps: 1, velocity: 0.6)
        let noteLeft = Double(n.startStep) * stepW
        let y = (Double(high - n.pitch) + 0.5) * rowH
        func hit(_ x: Double) -> RollHit {
            RollHitTest.classify(x: x, y: y, notes: [n],
                                 stepW: stepW, rowH: rowH,
                                 highPitch: high, lowPitch: low,
                                 stepCount: steps, edgeSlop: 20.0)
        }
        XCTAssertEqual(hit(noteLeft + 6.0), .body(id: n.id))       // inside first half
        XCTAssertEqual(hit(noteLeft + 20.0), .rightEdge(id: n.id)) // inside capped edge
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

    func testResizedLength_fingerStepBecomesLastCoveredStep() {
        // Note starts at step 3; dragging the edge to step 8 → covers 3…8 = 6 steps.
        XCTAssertEqual(RollHitTest.resizedLengthSteps(fingerStep: 8, startStep: 3), 6)
        // Finger on the start step → a single-step note.
        XCTAssertEqual(RollHitTest.resizedLengthSteps(fingerStep: 3, startStep: 3), 1)
        // Dragging left past the start collapses to the 1-step floor, never 0/negative.
        XCTAssertEqual(RollHitTest.resizedLengthSteps(fingerStep: 0, startStep: 3), 1)
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
