// PianoRollUndoTests.swift
// Echoelmusic — #58 MIDI station: undo/redo (snapshot stack, TimelineStore's
// proven pattern) + non-destructive move (tick-delta preserves off-grid
// micro-timing; the old startStep-setter path snapped notes to the grid on the
// FIRST drag) + the quantize door for the never-wired Note.quantizedStart.

import XCTest
@testable import Echoelmusic

@MainActor
final class PianoRollUndoTests: XCTestCase {

    // MARK: - Undo / redo

    func testAdd_isUndoable_andRedoable() {
        let m = PianoRollModel()
        m.add(pitch: 60, startStep: 0)
        XCTAssertEqual(m.notes.count, 1)
        XCTAssertTrue(m.canUndo)

        m.undo()
        XCTAssertEqual(m.notes.count, 0)
        XCTAssertTrue(m.canRedo)

        m.redo()
        XCTAssertEqual(m.notes.count, 1)
        XCTAssertEqual(m.notes.first?.pitch, 60)
    }

    func testRemove_andClear_areUndoable() {
        let m = PianoRollModel()
        let n = m.add(pitch: 60, startStep: 0)
        m.add(pitch: 64, startStep: 4)

        m.remove(id: n.id)
        XCTAssertEqual(m.notes.count, 1)
        m.undo()
        XCTAssertEqual(m.notes.count, 2, "remove undone")

        m.clear()
        XCTAssertEqual(m.notes.count, 0)
        m.undo()
        XCTAssertEqual(m.notes.count, 2, "clear undone")
    }

    func testGestureSnapshot_capturesWholeDrag_notEveryTick() {
        // The view snapshots ONCE at drag-begin; every onChanged tick mutates
        // without snapshotting — one undo returns to the pre-gesture state.
        let m = PianoRollModel()
        let n = m.add(pitch: 60, startStep: 0)
        m.snapshotForUndo()
        m.move(id: n.id, toPitch: 62, toStartStep: 2)
        m.move(id: n.id, toPitch: 64, toStartStep: 4)   // same gesture, more ticks
        XCTAssertEqual(m.notes.first?.pitch, 64)

        m.undo()
        XCTAssertEqual(m.notes.first?.pitch, 60, "one undo = whole gesture")
        XCTAssertEqual(m.notes.first?.startStep, 0)
    }

    func testNewEdit_clearsRedo() {
        let m = PianoRollModel()
        m.add(pitch: 60, startStep: 0)
        m.undo()
        XCTAssertTrue(m.canRedo)
        m.add(pitch: 65, startStep: 1)
        XCTAssertFalse(m.canRedo, "a fresh edit invalidates the redo branch")
    }

    func testUndoDepth_isBounded() {
        let m = PianoRollModel()
        for i in 0..<60 { m.add(pitch: 60, startStep: i % 16) }
        var undos = 0
        while m.canUndo { m.undo(); undos += 1 }
        XCTAssertLessThanOrEqual(undos, 50, "stack is capped (no unbounded growth)")
        XCTAssertGreaterThanOrEqual(undos, 49, "cap keeps the most recent edits")
    }

    // MARK: - Non-destructive move (tick-delta)

    func testMove_preservesOffGridMicroTiming() {
        let m = PianoRollModel()
        let n = m.add(pitch: 60, startStep: 0)
        // Simulate a recorded, off-grid note: 30 ticks late (a quarter of a step).
        guard let i = m.notes.firstIndex(where: { $0.id == n.id }) else { return XCTFail("note lost") }
        m.setStartTickForTesting(index: i, tick: 30)

        m.move(id: n.id, toPitch: 60, toStartStep: 2)
        XCTAssertEqual(m.notes.first?.startTick, 2 * Note.ticksPerStep + 30,
                       "drag by whole steps keeps the +30-tick feel (no grid snap)")
    }

    func testMove_onGridNote_behavesExactlyAsBefore() {
        let m = PianoRollModel()
        let n = m.add(pitch: 60, startStep: 1)
        m.move(id: n.id, toPitch: 63, toStartStep: 5)
        XCTAssertEqual(m.notes.first?.startTick, 5 * Note.ticksPerStep)
        XCTAssertEqual(m.notes.first?.pitch, 63)
    }

    func testMove_clampsInsideTheBar() {
        let m = PianoRollModel()
        let n = m.add(pitch: 60, startStep: 0, lengthSteps: 2)
        m.move(id: n.id, toPitch: 60, toStartStep: 99)
        let tick = m.notes.first?.startTick ?? -1
        XCTAssertLessThanOrEqual(tick + (m.notes.first?.lengthTicks ?? 0),
                                 PianoRollModel.stepCount * Note.ticksPerStep,
                                 "note tail never crosses the loop boundary")
    }

    // MARK: - Quantize (the door for Note.quantizedStart)

    func testQuantize_selectionOnly_snapsStartsToGrid() {
        let m = PianoRollModel()
        let a = m.add(pitch: 60, startStep: 0)
        let b = m.add(pitch: 64, startStep: 4)
        guard let ia = m.notes.firstIndex(where: { $0.id == a.id }),
              let ib = m.notes.firstIndex(where: { $0.id == b.id }) else { return XCTFail() }
        m.setStartTickForTesting(index: ia, tick: 95)    // → nearest grid = step 1
        m.setStartTickForTesting(index: ib, tick: 4 * Note.ticksPerStep + 33)

        m.quantize(ids: [a.id])
        XCTAssertEqual(m.notes.first(where: { $0.id == a.id })?.startTick, Note.ticksPerStep,
                       "selected note snaps to the nearest step")
        XCTAssertEqual(m.notes.first(where: { $0.id == b.id })?.startTick, 4 * Note.ticksPerStep + 33,
                       "unselected note keeps its feel")
    }

    func testQuantize_emptySelection_quantizesWholePattern_andIsUndoable() {
        let m = PianoRollModel()
        let a = m.add(pitch: 60, startStep: 0)
        guard let ia = m.notes.firstIndex(where: { $0.id == a.id }) else { return XCTFail() }
        m.setStartTickForTesting(index: ia, tick: 30)

        m.quantize(ids: [])
        XCTAssertEqual(m.notes.first?.startTick, 0)
        m.undo()
        XCTAssertEqual(m.notes.first?.startTick, 30, "quantize is one undoable edit")
    }
}
