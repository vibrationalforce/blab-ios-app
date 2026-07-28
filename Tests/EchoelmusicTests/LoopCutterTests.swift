// LoopCutterTests.swift
// Echoel — cutting one-bar material into 2/4/8/16/32/64-bar loops/stems.

import XCTest
@testable import Echoelmusic

final class LoopCutterTests: XCTestCase {

    func testBarLengthsAreTheExpectedSet() {
        // 64 added 2026-07-28 (#200, founder ask). The full contract — raw-value
        // stability and which lengths the RETROACTIVE path can actually deliver — lives
        // in LoopRetroCaptureFitTests; this stays the plain shape check.
        XCTAssertEqual(LoopBarLength.allCases.map(\.rawValue), [1, 2, 4, 8, 16, 32, 64])
        XCTAssertEqual(LoopBarLength.four.label, "4 bars")
    }

    func testTileGridRepeatsEachBar() {
        // One track, kick on step 0 only.
        var row = Array(repeating: false, count: 16); row[0] = true
        let out = LoopCutter.tile(grid: [row], bars: 4)
        XCTAssertEqual(out[0].count, 64, "4 bars × 16 steps")
        let onSteps = out[0].enumerated().filter { $0.element }.map { $0.offset }
        XCTAssertEqual(onSteps, [0, 16, 32, 48], "kick repeats once per bar")
    }

    func testTileGridHandlesMultipleTracksAndEmptyRows() {
        var snare = Array(repeating: false, count: 16); snare[8] = true
        let out = LoopCutter.tile(grid: [[], snare], bars: 2)
        XCTAssertEqual(out[0], Array(repeating: false, count: 32), "empty row padded")
        XCTAssertEqual(out[1].enumerated().filter { $0.element }.map { $0.offset }, [8, 24])
    }

    func testTileNotesRepeatsAndOffsets() {
        let n = Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: 0.8)
        let out = LoopCutter.tile(notes: [n], bars: 2)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.map(\.startStep).sorted(), [0, 16])
        XCTAssertTrue(out.allSatisfy { $0.pitch == 60 })
    }

    func testTileNotesClipsAtLoopBoundary() {
        // A note that ends exactly at the bar line stays in bounds across the loop.
        let n = Note(pitch: 62, startStep: 14, lengthSteps: 2, velocity: 0.7)
        let out = LoopCutter.tile(notes: [n], bars: 2)
        for note in out {
            XCTAssertLessThanOrEqual(note.startStep + note.lengthSteps, 32,
                                     "no note crosses the loop end")
            XCTAssertGreaterThanOrEqual(note.lengthSteps, 1)
        }
        XCTAssertEqual(out.map(\.startStep).sorted(), [14, 30])
    }

    func testTileNotesFreshIdsPerCopy() {
        let n = Note(pitch: 60, startStep: 0, lengthSteps: 2, velocity: 0.8)
        let out = LoopCutter.tile(notes: [n], bars: 4)
        XCTAssertEqual(Set(out.map(\.id)).count, out.count, "each copy has a unique id")
    }

    func testZeroBarsIsEmpty() {
        XCTAssertTrue(LoopCutter.tile(notes: [Note(pitch: 60, startStep: 0)], bars: 0).isEmpty)
        XCTAssertEqual(LoopCutter.tile(grid: [[true]], bars: 0).first?.count, 0)
    }
}
