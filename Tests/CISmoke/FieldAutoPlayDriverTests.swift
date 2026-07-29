// FieldAutoPlayDriverTests.swift
// Echoel — the LOOP that turns `FieldAutoPlay.cell` into notes, tested without the view.
//
// The driver in `TouchInstrumentUIView` is five lines: a display link looks at the clock,
// computes the cell, and fires when the cell CHANGED. Five lines with two ways to be wrong,
// and both are silent on a device rather than loud:
//   · fire twice in one cell → a doubled part, heard as a flam;
//   · miss a cell entirely   → a dropped note, heard as the generator "stuttering".
// Neither raises anything. The rule is pure arithmetic, so it is simulated here instead of
// being discovered by ear.
//
// ⚠️ WHAT THIS IS NOT. It does not exercise `CADisplayLink`, the view, or the audio path —
// it re-implements the idiom the view uses and pins the arithmetic underneath it. If someone
// changes the view's rule without changing this loop, the test stays green and says nothing.
// That is the honest limit of testing a driver whose host is a UIView; what it does buy is
// that the RATE choice and the cell maths are pinned, and those were the two uncertain parts.

import Foundation
import XCTest
@testable import Echoelmusic

final class FieldAutoPlayDriverTests: XCTestCase {

    /// The view's rule, in shape: look at a tick, compute the cell, fire on change.
    ///
    /// - Parameter dropEveryNthLook: simulates a MISSED display-link callback (a busy main
    ///   actor, a dropped frame). 0 = a perfect clock. This is the whole reason the rate
    ///   question has an answer — see `testAMissedFrameCostsACellAtThirtyHertz`.
    private func firedCells(ticksPerCell: Int, secondsPerTick: Double,
                            lookHz: Double, seconds: Double,
                            dropEveryNthLook: Int = 0) -> [Int] {
        var fired: [Int] = []
        var lastFiredCell: Int?
        let looks = Int((seconds * lookHz).rounded(.down))
        for look in 0...looks {
            if dropEveryNthLook > 0, look > 0, look % dropEveryNthLook == 0 { continue }
            let t = Double(look) / lookHz
            let tick = Int((t / secondsPerTick).rounded(.down))
            let cell = FieldAutoPlay.cell(forTick: tick, ticksPerCell: ticksPerCell)
            guard cell != lastFiredCell else { continue }
            lastFiredCell = cell
            fired.append(cell)
        }
        return fired
    }

    /// 480 PPQ, so one tick is a quarter's worth of seconds divided by 480.
    private func secondsPerTick(bpm: Double) -> Double { 60.0 / (bpm * 480.0) }

    /// Every cell exactly once, in order, no gaps. "In order with no gaps" catches BOTH
    /// failure modes at once — a double fire repeats a value, a miss skips one, and
    /// `Array(0...n)` admits neither.
    private func assertConsecutive(_ fired: [Int], _ message: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(fired.isEmpty, "nothing fired at all: \(message)", file: file, line: line)
        guard let last = fired.last else { return }
        XCTAssertEqual(fired, Array(0...last), message, file: file, line: line)
    }

    /// THE COMMON CASE: sixteenths at 120 BPM.
    func testEveryCellFiresExactlyOnceAtTheCommonSetting() {
        let fired = firedCells(ticksPerCell: 120,                 // 1/16
                               secondsPerTick: secondsPerTick(bpm: 120),
                               lookHz: 60, seconds: 5)
        XCTAssertEqual(fired.first, 0, "the first look must fire, not wait for an edge")
        assertConsecutive(fired, "a repeat is a flam, a gap is a dropped note")
        // 5 s of 125 ms cells is cells 0…40. Asserted as a RANGE, not 41 exactly: the last
        // look lands on t = 5.0, which is a cell boundary, and whether `5.0 / secondsPerTick`
        // rounds to 4800 or 4799.999… is a property of binary floating point, not of the
        // driver. The range is still tight enough to catch a half-rate or double-rate loop,
        // which is what this count is for.
        XCTAssertTrue((40...41).contains(fired.count), "expected ~41 cells, got \(fired.count)")
    }

    /// THE WORST CASE THE APP ALLOWS: 1/16-triplet (80 ticks) at Transport's 300 BPM ceiling
    /// is a 33.3 ms cell. At 60 Hz that is two looks per cell.
    func testTheFastestGridAtTheFastestTempoStillSeesEveryCell() {
        let fired = firedCells(ticksPerCell: 80,                  // 1/16T
                               secondsPerTick: secondsPerTick(bpm: 300),
                               lookHz: 60, seconds: 2)
        assertConsecutive(fired, "at 60 Hz the fastest grid must still be seen cell by cell")
        XCTAssertGreaterThan(fired.count, 55, "2 s of 33.3 ms cells is ~60 of them")
    }

    /// THE NEGATIVE CONTROL, and the actual justification for 60 Hz. At that same setting a
    /// 30 Hz look period EQUALS the cell duration (33.3 ms), so each cell gets at most one
    /// look and boundary rounding decides whether it gets any: this simulation fires ~46 of
    /// the ~61 cells. Critical sampling is not "just enough", it is a coin flip per cell.
    ///
    /// Without this half, "60 Hz works" would be true of any rate and the constant would look
    /// arbitrary — which is exactly how a later cycle talks itself into halving it.
    func testThirtyHertzGenuinelyDropsCellsAtThatSetting() {
        let fired = firedCells(ticksPerCell: 80,
                               secondsPerTick: secondsPerTick(bpm: 300),
                               lookHz: 30, seconds: 2)
        guard let last = fired.last else { return XCTFail("nothing fired") }
        XCTAssertNotEqual(fired, Array(0...last),
                          "if 30 Hz no longer skipped cells, the 60 Hz choice has lost its "
                          + "justification and should be re-derived rather than kept on faith")
    }

    /// …and 60 Hz has real MARGIN, not just a passing grade: it still sees every cell when
    /// one look in ten is missed entirely — a busy main actor, a dropped frame. Two looks per
    /// cell is what buys that, and it is the reason the answer is 60 rather than 45.
    func testSixtyHertzAbsorbsAMissedFrame() {
        let fired = firedCells(ticksPerCell: 80,
                               secondsPerTick: secondsPerTick(bpm: 300),
                               lookHz: 60, seconds: 2, dropEveryNthLook: 10)
        assertConsecutive(fired, "60 Hz must absorb a dropped frame at the fastest setting")
    }

    /// A stopped or very slow transport must not fire the same cell again and again. This is
    /// the failure that would be LOUD — a note every frame — and it is what the change check
    /// exists for, so it gets its own case rather than being implied.
    func testASlowClockDoesNotRefireTheSameCell() {
        let fired = firedCells(ticksPerCell: 480,                 // 1/4
                               secondsPerTick: secondsPerTick(bpm: 30),
                               lookHz: 60, seconds: 4)
        assertConsecutive(fired, "a slow clock must still advance one cell at a time")
        // A quarter at 30 BPM is 2 s, so 4 s is cells 0,1,2 — three notes, not 240.
        XCTAssertTrue((2...3).contains(fired.count), "expected ~3 cells, got \(fired.count)")
    }

    /// The generated positions must land INSIDE the surface, because the view maps them with
    /// `TouchPitchMap.pitch(normX:normY:key:)` and an out-of-range coordinate would clamp to
    /// an edge note — a wander that silently parks on the top or bottom row.
    func testGeneratedPositionsStayOnTheSurface() {
        for motion in FieldAutoPlay.Motion.allCases {
            for voices in [1, 3, FieldAutoPlay.maxVoices] {
                let p = FieldAutoPlay.Params(motion: motion, density: 1, span: 1,
                                             centre: 0.5, band: 0.5, bandDrift: 1,
                                             voices: voices, periodSteps: 16)
                for step in 0..<64 {
                    let touches = FieldAutoPlay.touches(atStep: step, params: p, seed: 7)
                    // Non-vacuity: at density 1 every cell must fire, so an empty result is
                    // itself the bug. Without this the loop below could pass by never running
                    // — the failure mode this repo has already written into two other test
                    // files after hitting it.
                    XCTAssertFalse(touches.isEmpty, "\(motion) step \(step) fired nothing at density 1")
                    for t in touches {
                        XCTAssertTrue((0...1).contains(t.x), "\(motion) x \(t.x)")
                        XCTAssertTrue((0...1).contains(t.y), "\(motion) y \(t.y)")
                        XCTAssertTrue(t.velocity > 0 && t.velocity <= 1)
                    }
                }
            }
        }
    }

    /// And the resulting NOTE must be a legal MIDI pitch in every key the app offers. The view
    /// feeds `t.x`/`t.y` straight into the same mapping a finger uses, so this is the
    /// composition that actually ships — the one place where a bad generated position would
    /// become a bad note rather than a bad number.
    func testGeneratedPositionsBecomeLegalPitchesInEveryKey() {
        let params = FieldAutoPlay.Params(motion: .pendulum, density: 1, span: 1,
                                          centre: 0.5, band: 0.5, bandDrift: 1,
                                          voices: 4, periodSteps: 16)
        for root in 0..<12 {
            for scale in Scale.allCases {
                let key = MusicalKey(root: root, scale: scale)
                for step in 0..<32 {
                    let touches = FieldAutoPlay.touches(atStep: step, params: params, seed: 3)
                    XCTAssertFalse(touches.isEmpty, "step \(step) fired nothing at density 1")
                    for t in touches {
                        let pitch = TouchPitchMap.pitch(normX: Double(t.x),
                                                        normY: Double(t.y), key: key)
                        XCTAssertTrue((0...127).contains(pitch),
                                      "root \(root) \(scale) step \(step) → \(pitch)")
                    }
                }
            }
        }
    }
}
