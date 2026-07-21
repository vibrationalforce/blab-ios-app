// LaneNotePumpTests.swift
// Pure tests for the secondary-lane note scheduler (B08). No engine → every platform.

import XCTest
@testable import Echoelmusic

final class LaneNotePumpTests: XCTestCase {

    // A helper: collect (pitch, isOn) from a step for terse assertions.
    private func fire(_ pump: inout LaneNotePump, _ step: Int) -> [(Int, Bool)] {
        pump.step(step).map { ($0.pitch, $0.isOn) }
    }

    // `[(Int, Bool)]` can't use XCTAssertEqual — a tuple can't conform to Equatable
    // (though `(Int, Bool) == (Int, Bool)` is synthesized). Compare element-wise so
    // the terse `[(pitch, isOn)]` literals stay readable.
    private func assertFires(_ actual: [(Int, Bool)], _ expected: [(Int, Bool)],
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count,
                       "event count \(actual) vs \(expected)", file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertTrue(a == e, "\(a) != \(e)", file: file, line: line)
        }
    }

    func testEmptyPumpIsIdle() {
        var pump = LaneNotePump()
        XCTAssertTrue(pump.isEmpty)
        XCTAssertEqual(pump.step(0), [])
        XCTAssertTrue(pump.soundingPitches.isEmpty)
    }

    func testSingleNoteOnThenOff() {
        var pump = LaneNotePump()
        // One 1-step note at step 4 (start tick 480, length 120 → endStep 5).
        pump.load([Note(pitch: 60, startStep: 4, lengthSteps: 1, velocity: 0.7)])
        assertFires(fire(&pump, 3), [])
        // Onset at step 4.
        let on = fire(&pump, 4)
        assertFires(on, [(60, true)])
        XCTAssertEqual(pump.soundingPitches, [60])
        // Release at step 5 (exclusive end).
        let off = fire(&pump, 5)
        assertFires(off, [(60, false)])
        XCTAssertTrue(pump.soundingPitches.isEmpty)
    }

    func testOnsetVelocityPreserved() {
        var pump = LaneNotePump()
        pump.load([Note(pitch: 48, startStep: 0, lengthSteps: 2, velocity: 0.42)])
        let events = pump.step(0)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].pitch, 48)
        XCTAssertEqual(events[0].velocity, 0.42, accuracy: 0.0001)
        XCTAssertTrue(events[0].isOn)
    }

    func testSilentNoteNeverAttacks() {
        var pump = LaneNotePump()
        pump.load([Note(pitch: 50, startStep: 0, lengthSteps: 1, velocity: 0)])
        XCTAssertEqual(pump.step(0), [])
        XCTAssertTrue(pump.soundingPitches.isEmpty)
    }

    func testTwoSimultaneousNotesBothPlay() {
        var pump = LaneNotePump()
        pump.load([
            Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: 0.8),
            Note(pitch: 64, startStep: 0, lengthSteps: 4, velocity: 0.8),
        ])
        let on = pump.step(0).filter(\.isOn).map(\.pitch).sorted()
        XCTAssertEqual(on, [60, 64])
        XCTAssertEqual(pump.soundingPitches, [60, 64])
    }

    func testFullBarNoteLoopsSeamlessly() {
        var pump = LaneNotePump(stepCount: 16)
        // A whole-bar note: start 0, length 16 → endStep 16, 16 % 16 == 0.
        pump.load([Note(pitch: 36, startStep: 0, lengthSteps: 16, velocity: 0.9)])
        // Bar 1 onset.
        assertFires(fire(&pump, 0), [(36, true)])
        // Nothing mid-bar.
        for s in 1..<16 { assertFires(fire(&pump, s), []) }
        // Bar 2 step 0: release the old, then re-attack — clean loop.
        let wrap = fire(&pump, 0)
        assertFires(wrap, [(36, false), (36, true)])
        XCTAssertEqual(pump.soundingPitches, [36])
    }

    func testSamePitchRetriggerReleasesBeforeAttack() {
        var pump = LaneNotePump()
        // Note A ends exactly where note B (same pitch) starts — mid-bar retrigger.
        pump.load([
            Note(pitch: 62, startStep: 0, lengthSteps: 4, velocity: 0.8),  // endStep 4
            Note(pitch: 62, startStep: 4, lengthSteps: 4, velocity: 0.8),  // start 4
        ])
        _ = pump.step(0)                      // A on
        let s4 = fire(&pump, 4)               // A off, then B on
        assertFires(s4, [(62, false), (62, true)])
        XCTAssertEqual(pump.soundingPitches, [62])
    }

    func testPitchHeldBySecondNoteNotReleasedEarly() {
        var pump = LaneNotePump()
        // Two same-pitch notes overlap: A [0,8), B [4,12). At step 8 A ends but B
        // still holds pitch → NO note-off yet.
        pump.load([
            Note(pitch: 55, startStep: 0, lengthSteps: 8, velocity: 0.8),
            Note(pitch: 55, startStep: 4, lengthSteps: 8, velocity: 0.8),
        ])
        _ = pump.step(0)   // A on
        _ = pump.step(4)   // B on (same pitch, no new attack event needed but tracked)
        let s8 = pump.step(8)   // A ends, B survives → no off
        XCTAssertTrue(s8.isEmpty, "pitch still held by B must not release")
        XCTAssertEqual(pump.soundingPitches, [55])
    }

    func testResetReleasesAllSounding() {
        var pump = LaneNotePump()
        pump.load([
            Note(pitch: 60, startStep: 0, lengthSteps: 8, velocity: 0.8),
            Note(pitch: 67, startStep: 0, lengthSteps: 8, velocity: 0.8),
        ])
        _ = pump.step(0)
        let offs = pump.reset()
        XCTAssertEqual(offs.map(\.pitch).sorted(), [60, 67])
        XCTAssertTrue(offs.allSatisfy { !$0.isOn })
        XCTAssertTrue(pump.isEmpty)
    }

    func testContentSwapKeepsRingingNoteUntilItsEnd() {
        var pump = LaneNotePump()
        pump.load([Note(pitch: 72, startStep: 0, lengthSteps: 8, velocity: 0.8)])
        _ = pump.step(0)                 // 72 on
        // Swap content mid-loop — 72 keeps ringing (no cut), new note at step 8.
        pump.load([Note(pitch: 48, startStep: 8, lengthSteps: 4, velocity: 0.8)])
        XCTAssertEqual(pump.soundingPitches, [72])
        let s8 = fire(&pump, 8)          // 72 releases (endStep 8), 48 attacks
        XCTAssertEqual(s8.filter { !$0.1 }.map(\.0), [72])
        XCTAssertEqual(s8.filter { $0.1 }.map(\.0), [48])
    }

    func testStepWrapsOutOfRangeIndex() {
        var pump = LaneNotePump(stepCount: 16)
        pump.load([Note(pitch: 60, startStep: 0, lengthSteps: 1, velocity: 0.8)])
        // step 16 wraps to 0 → onset fires.
        let e = pump.step(16)
        XCTAssertEqual(e.map(\.pitch), [60])
    }

    // MARK: - Multi-bar region cycling (M1c — CLIP-1: secondary lanes must play
    // a multi-bar clip bar BY bar, never fold every bar onto steps 0-15)

    /// Walk the pump through one full bar of transport steps.
    private func runBar(_ pump: inout LaneNotePump, collect: inout [LaneNotePump.Event]) {
        for s in 0..<16 { collect.append(contentsOf: pump.step(s)) }
    }

    func testMultiBar_playsEachBarInSequence_notFolded() {
        var pump = LaneNotePump()
        // Bar 0: pitch 60 @0 · Bar 1: pitch 72 @0. The old %16 fold sounded BOTH
        // every bar, superimposed — the verified CLIP-1 failure.
        pump.load(bars: [[Note(pitch: 60, startStep: 0, lengthSteps: 2, velocity: 0.8)],
                         [Note(pitch: 72, startStep: 0, lengthSteps: 2, velocity: 0.8)]],
                  startBar: 0)
        var bar0: [LaneNotePump.Event] = []
        runBar(&pump, collect: &bar0)
        XCTAssertEqual(bar0.filter(\.isOn).map(\.pitch), [60], "bar 0 plays ONLY bar 0's note")
        var bar1: [LaneNotePump.Event] = []
        runBar(&pump, collect: &bar1)
        XCTAssertEqual(bar1.filter(\.isOn).map(\.pitch), [72], "bar 1 plays ONLY bar 1's note")
    }

    func testMultiBar_wrapsBackToBarZero() {
        var pump = LaneNotePump()
        pump.load(bars: [[Note(pitch: 60, startStep: 0, lengthSteps: 2, velocity: 0.8)],
                         [Note(pitch: 72, startStep: 0, lengthSteps: 2, velocity: 0.8)]],
                  startBar: 0)
        var all: [LaneNotePump.Event] = []
        runBar(&pump, collect: &all)   // bar 0
        runBar(&pump, collect: &all)   // bar 1
        var bar2: [LaneNotePump.Event] = []
        runBar(&pump, collect: &bar2)  // wraps → bar 0 again
        XCTAssertEqual(bar2.filter(\.isOn).map(\.pitch), [60], "region loops back to bar 0")
    }

    func testMultiBar_startBarOffset_beginsMidRegion() {
        var pump = LaneNotePump()
        // Prime mid-region (seek / region already active at play): startBar 1
        // must play bar 1 FIRST, without advancing on its own onset step 0.
        pump.load(bars: [[Note(pitch: 60, startStep: 0, lengthSteps: 2, velocity: 0.8)],
                         [Note(pitch: 72, startStep: 0, lengthSteps: 2, velocity: 0.8)]],
                  startBar: 1)
        let e = pump.step(0)
        XCTAssertEqual(e.filter(\.isOn).map(\.pitch), [72])
    }

    func testMultiBar_sustainAcrossBarBoundary_releasesInNextBar() {
        var pump = LaneNotePump()
        // Bar 0: note @12 sustaining 8 steps → exclusive end 20 ≡ step 4 of bar 1
        // (barSlices keeps sustains whole; active-note release is bar-agnostic).
        pump.load(bars: [[Note(pitch: 55, startStep: 12, lengthSteps: 8, velocity: 0.8)],
                         []],
                  startBar: 0)
        for s in 0..<16 { _ = pump.step(s) }
        XCTAssertEqual(pump.soundingPitches, [55], "sustain survives the bar boundary")
        _ = pump.step(0)   // bar advance to (empty) bar 1
        _ = pump.step(1); _ = pump.step(2); _ = pump.step(3)
        let s4 = pump.step(4)
        XCTAssertEqual(s4.map(\.pitch), [55])
        XCTAssertFalse(s4[0].isOn, "release lands at its true step in the NEXT bar")
    }

    func testMultiBar_singleBarLoadKeepsLegacyBehavior() {
        var pump = LaneNotePump()
        pump.load(bars: [[Note(pitch: 60, startStep: 0, lengthSteps: 1, velocity: 0.8)]],
                  startBar: 3)   // out-of-range startBar folds into the 1-bar region
        let e = pump.step(0)
        XCTAssertEqual(e.map(\.pitch), [60])
        var again: [LaneNotePump.Event] = []
        for s in 1..<16 { again.append(contentsOf: pump.step(s)) }
        let next = pump.step(0)  // wrap: same single bar again
        XCTAssertEqual(next.filter(\.isOn).map(\.pitch), [60])
    }

    func testMultiBar_emptyBarsLoad_isEmptyAndSilent() {
        var pump = LaneNotePump()
        pump.load(bars: [], startBar: 0)
        XCTAssertTrue(pump.isEmpty)
        XCTAssertTrue(pump.step(0).isEmpty)
    }

    func testMultiBar_contentInLaterBarOnly_isNotEmpty() {
        var pump = LaneNotePump()
        pump.load(bars: [[], [Note(pitch: 72, startStep: 0, lengthSteps: 2, velocity: 0.8)]],
                  startBar: 0)
        XCTAssertFalse(pump.isEmpty, "a region with notes only in bar 2 still has content")
    }
}
