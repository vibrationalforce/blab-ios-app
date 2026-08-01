// SlowScrubStillMovesTests.swift
// Echoel — a slow drag must move the value, not merely fail quietly. BLOCKING bundle.
//
// THE DEFECT (#376). `EchoelValueField`'s drag added each event's travel to the STORED value —
// which `apply` has already snapped to the display grid. Everything below half a grid unit was
// therefore discarded every frame instead of accumulating, and that does not make a slow drag
// slow: it makes it IMPOSSIBLE, for as long as the finger keeps moving.
//
// Measured against the app's own fields at 60 Hz, before the fix:
//   • `0…1, decimals: 2` — every FX parameter row, the master volume, the metronome level, the
//     weather mixers — needed ≈140 pt/s before the number responded AT ALL.
//   • `8…90, decimals: 0` ("Detail") needed ≈150 pt/s.
// And the threshold rose with the refresh rate (≈195 pt/s at 120 Hz), because each event then
// carries half the travel and loses proportionally more to rounding — quietly undoing the
// frame-rate independence that the speed measurement in `ScrubPrecision.scale` exists to provide.
//
// ⛔ WHY THIS IS A GUARD AND NOT A NOTE. `ScrubPrecisionSmokeTests` already pins
// `fineScale > 0`, with the words "a zero-travel control reads as broken, not as precise". That
// guard was GREEN throughout, because it holds the multiplier and the grid ate the result one
// step later. A guard can only hold the layer it can see, so this one asserts the composition —
// `advanced` then `snapped`, in a loop, the way the gesture actually runs it — rather than either
// half alone.
//
// ⚠️ WHAT A GREEN HERE DOES NOT MEAN. It is arithmetic over the same pure functions the view
// calls; it cannot say a finger reaches the field (that is gesture arbitration, #360) nor that
// the resulting feel is right. The device question is narrow and answerable: does a deliberately
// slow drag on an FX row now move the number?

import Foundation
import XCTest
@testable import Echoelmusic

final class SlowScrubStillMovesTests: XCTestCase {

    typealias P = ScrubPrecision

    /// The drag as the view runs it: an un-snapped target advanced per event, snapped for the
    /// write. Returns the value the field would display after `events` events.
    private func drivenValue(lowerBound lo: Double, upperBound hi: Double, decimals: Int,
                             pointsPerEvent: Double, events: Int, from start: Double) -> Double {
        let delta = (pointsPerEvent * P.fineScale / 200.0) * (hi - lo)
        var target = start
        for _ in 0..<events {
            target = P.advanced(target: target, by: delta, lowerBound: lo, upperBound: hi)
        }
        return P.snapped(target, lowerBound: lo, upperBound: hi, decimals: decimals)
    }

    /// The SUPERSEDED composition — snap on every event, which is what discarded the remainder.
    /// Kept so the two can be compared in one assertion instead of asserted from memory.
    private func drivenValueTheOldWay(lowerBound lo: Double, upperBound hi: Double, decimals: Int,
                                      pointsPerEvent: Double, events: Int,
                                      from start: Double) -> Double {
        let delta = (pointsPerEvent * P.fineScale / 200.0) * (hi - lo)
        var value = P.snapped(start, lowerBound: lo, upperBound: hi, decimals: decimals)
        for _ in 0..<events {
            value = P.snapped(value + delta, lowerBound: lo, upperBound: hi, decimals: decimals)
        }
        return value
    }

    // MARK: - The two field shapes the defect actually reached

    /// One point of finger travel per event, one second at 60 Hz, on the shape that covers every
    /// FX row and the master volume. The old composition is frozen; the new one has moved.
    func testASlowDragOnATwoDecimalUnitFieldMoves() {
        let moved = drivenValue(lowerBound: 0, upperBound: 1, decimals: 2,
                                pointsPerEvent: 1, events: 60, from: 0.50)
        let frozen = drivenValueTheOldWay(lowerBound: 0, upperBound: 1, decimals: 2,
                                          pointsPerEvent: 1, events: 60, from: 0.50)
        XCTAssertEqual(frozen, 0.50, """
            The superseded per-event snap moved the value to \(frozen). If that is no longer \
            0.50 the premise of #376 has changed and these numbers need re-deriving — but note \
            that a NON-frozen result here would mean the defect never existed, which the device \
            reports contradict.
            """)
        XCTAssertGreaterThan(moved, 0.50, """
            A one-second slow drag left a 0…1 two-decimal field on \(moved). This is every FX \
            parameter, the master volume and the weather mixers: below the grid the row is inert \
            for as long as the finger moves, which is the dead control `fineScale > 0` is \
            supposed to prevent and cannot see.
            """)
    }

    /// The whole-number field, where the grid is 1 and one slow point is ~0.09 of it.
    func testASlowDragOnAWholeNumberFieldMoves() {
        let moved = drivenValue(lowerBound: 8, upperBound: 90, decimals: 0,
                                pointsPerEvent: 1, events: 60, from: 23)
        let frozen = drivenValueTheOldWay(lowerBound: 8, upperBound: 90, decimals: 0,
                                          pointsPerEvent: 1, events: 60, from: 23)
        XCTAssertEqual(frozen, 23, "The superseded per-event snap moved \"Detail\" to \(frozen).")
        XCTAssertGreaterThan(moved, 23, """
            A one-second slow drag left \"Detail\" (8…90, whole numbers) on \(moved). One point \
            of slow travel is ~0.09 there, so without accumulation the field can never leave the \
            integer it started on.
            """)
    }

    /// How long the user waits for the first visible step — stated as a number so a regression
    /// that merely makes it *slower* is visible too, not only one that freezes it.
    func testTheFirstStepArrivesWithinAFewFrames() {
        let lo = 0.0, hi = 1.0, decimals = 2
        let delta = (1.0 * P.fineScale / 200.0) * (hi - lo)
        var target = 0.50
        var events = 0
        while P.snapped(target, lowerBound: lo, upperBound: hi, decimals: decimals) == 0.50,
              events < 600 {
            target = P.advanced(target: target, by: delta, lowerBound: lo, upperBound: hi)
            events += 1
        }
        XCTAssertLessThanOrEqual(events, 10, """
            The first visible step of a slow drag took \(events) events — about \
            \(Double(events) / 60.0) s at 60 Hz. Anything beyond a few frames reads as a control \
            that ignores you before it obeys you.
            """)
        XCTAssertGreaterThan(events, 1, """
            The first step arrived after \(events) event(s), i.e. essentially immediately. That \
            would mean the fine mode is not fine any more — `fineScale` or `fullRangePoints` \
            changed and the precision half of the scrub is gone.
            """)
    }

    // MARK: - The target is CLAMPED, which is what keeps a reversal honest

    /// Accumulating without clamping would build an invisible overshoot that the user has to
    /// unwind before the number responds again — the classic "I dragged back and nothing
    /// happened" rubber band. `advanced` clamps, so the reversal is immediate.
    func testPastTheEndAndBackRespondsAtOnce() {
        let lo = 0.0, hi = 1.0
        let delta = (1.0 * P.fineScale / 200.0) * (hi - lo)
        var target = hi
        for _ in 0..<50 {
            target = P.advanced(target: target, by: delta, lowerBound: lo, upperBound: hi)
        }
        XCTAssertEqual(target, hi, """
            50 events past the upper bound accumulated to \(target) instead of staying at \(hi). \
            That overshoot is invisible and has to be dragged back through before the value \
            moves again.
            """)
        let back = P.snapped(P.advanced(target: target, by: -delta * 10,
                                        lowerBound: lo, upperBound: hi),
                             lowerBound: lo, upperBound: hi, decimals: 2)
        XCTAssertLessThan(back, 1.0, """
            Reversing straight after pushing against the top left the value at \(back). The \
            clamp on the target exists precisely so this responds on the first event back.
            """)
    }

    /// `advanced` clamps and does NOT snap — the two are separate on purpose, and a change that
    /// folded the grid back in here would silently restore #376.
    func testAdvancedKeepsSubGridPrecision() {
        let fine = P.advanced(target: 0.5, by: 0.0011, lowerBound: 0, upperBound: 1)
        XCTAssertEqual(fine, 0.5011, accuracy: 1e-12, """
            `advanced` returned \(fine) for a 0.0011 step from 0.5 — it has started snapping. \
            The grid belongs in `snapped`, at the write; a scrub in progress must be allowed to \
            hold an intent finer than the field can display.
            """)
        XCTAssertEqual(P.advanced(target: 0.5, by: 10, lowerBound: 0, upperBound: 1), 1.0,
                       "`advanced` stopped clamping to the upper bound.")
        XCTAssertEqual(P.advanced(target: 0.5, by: -10, lowerBound: 0, upperBound: 1), 0.0,
                       "`advanced` stopped clamping to the lower bound.")
    }

    /// The fast half is unchanged in the large: 200 points of travel at full scale still covers
    /// the whole range, which is the feel the founder asked for ("fast/direct").
    func testTwoHundredPointsStillCoversTheFullRange() {
        let lo = 0.0, hi = 1.0
        // 20 pt per event is far above `fullSpeed`, so `scale` is 1 and the fine factor is out.
        let delta = (20.0 / 200.0) * (hi - lo)
        var target = lo
        for _ in 0..<10 {
            target = P.advanced(target: target, by: delta, lowerBound: lo, upperBound: hi)
        }
        XCTAssertEqual(target, hi, accuracy: 1e-9, """
            Ten fast events of 20 pt — 200 points, the documented full-range travel — reached \
            \(target) instead of \(hi). Accumulating must not have changed the gearing.
            """)
    }
}
