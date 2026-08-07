// ASnappedValueIsLegalForItsRowTests.swift
// Echoel — #442. What a parameter row COMMITS has to be a value that row admits.
//
// WHAT WAS WRONG. `ScrubPrecision.snapped` clamped into the range and THEN rounded to the
// row's `10^-decimals` grid. Rounding goes to the NEAREST grid point, so it can move a value
// OUTWARD: on a `0…0.995` row at two places, clamping gives `0.995` and gridding turns that
// into `1.00` — half a grid step ABOVE the declared maximum, written straight into the
// binding. On a `0.4…0.6` row at whole numbers the same arithmetic commits `1.0`, which is
// not merely off by a rounding unit but outside by two thirds of the range.
//
// ⭐ AND SWAPPING THE TWO LINES IS NOT THE FIX — that is the reason this file exists rather
// than a one-line diff. Grid-then-clamp lands exactly ON an off-grid bound, and the readout
// formats the GRIDDED value (#432), so the row would show one number and keep another: the
// defect #432 closed, reintroduced at the edge. Neither order satisfies both promises. The
// shipped rule rounds toward the INTERIOR — nearest grid point, stepped one unit back inside
// if that landed outside — so the result is on the grid AND in the range. The only thing
// given up is landing exactly ON an off-grid bound, which the row cannot display anyway.
//
// ⛔ THE `slack` IS NOT DEFENSIVE PADDING; WITHOUT IT THIS SLICE WOULD HAVE TAKEN `0.95` OFF
// FIVE SHIPPED ROWS. A bound arrives as `Double(range.upperBound)`, and for a `Float` row that
// is not the literal: `Float(0.95)` is `0.9499999880790710`. #430 measured 11 of 86 bounds in
// that state. A bare `landed > upperBound` reads `0.95 > 0.94999998…` as a real overshoot and
// steps the row's maximum down to `0.94`. The OLD order was immune to that by accident, which
// is exactly why the obvious-looking change is the dangerous one.
// `testTheFloatRoundTripBoundIsNotTreatedAsOffGrid` is that case, and it is the one test here
// that is GREEN on the old code — it guards against the naive fix, not against the defect.
//
// ⚠️ WHAT THIS CANNOT SHOW: that any shipped row was wrong today. None is. Every bound
// reachable from a literal in `Sources/` is already on its own row's grid (74 checks across
// `EchoelValueField(` and `EchoelFXView.field(` call sites plus the named constants they use),
// and where the bound is on the grid, monotone rounding cannot cross it. Measured over 23
// shipped-shaped ranges × 2001 samples each — 46 023 in total — the new rule and the old one
// agree on every single value. This removes a mechanism and buys the NEXT row, in a file that
// already ships an 80…18000 Hz cutoff at `decimals: 0`.
//
// ⛔ AND THE FIRST VERSION OF THIS FILE DID NOT COMPILE — it was missing `@testable import
// Echoelmusic`, so all nine `ScrubPrecision` references failed with "cannot find … in scope"
// and the blocking bundle died at `** TEST BUILD FAILED **` (run 31138211848). The measured
// sweeps above were all done in a transcription; nothing here had ever been through a compiler,
// because there is none in this container. The reason that is worth a paragraph rather than a
// silent fix is the READING problem it exposes: with #396 alive, `Echoelmusic CI/CD Pipeline`
// reports `failure` on EVERY push, so the conclusion alone cannot distinguish "the known
// founder-gated test-host death" from "your new file does not build". The two are one line
// apart in the log and nowhere else — `** TEST EXECUTE FAILED **` is #396 and harmless,
// `** TEST BUILD FAILED **` is yours. A cycle that reads the conclusion and stops has not
// checked anything. **A blanket guard was measured and rejected:** 61 of the 180 files in
// `Tests/CISmoke` legitimately have no such import (they are pure source scans), so a rule
// requiring it everywhere would turn 61 correct files red — the #364 trap.

import Foundation
import XCTest
@testable import Echoelmusic

final class ASnappedValueIsLegalForItsRowTests: XCTestCase {

    /// Mirrors `ScrubPrecision.snapped`'s own definition of "close enough to the bound to be
    /// the bound": one hundredth of a grid step.
    private func slack(_ decimals: Int) -> Double { pow(10.0, -Double(decimals)) * 1e-2 }

    private func onGrid(_ v: Double, _ decimals: Int) -> Bool {
        let step = pow(10.0, -Double(decimals))
        return abs(ScrubPrecision.gridded(v, decimals: decimals) - v) <= step * 1e-9
    }

    // MARK: - The defect, from both ends

    /// RED on clamp-then-grid, which commits `1.00` on a row whose maximum is `0.995`.
    func testAnOffGridUpperBoundIsNeverExceeded() {
        let landed = ScrubPrecision.snapped(1.0, lowerBound: 0.0, upperBound: 0.995, decimals: 2)
        XCTAssertLessThanOrEqual(landed, 0.995 + slack(2), """
            snapped committed \(landed) on a row whose declared maximum is 0.995. Rounding to \
            the nearest grid point carried the clamped value OUTWARD past the bound.
            """)
        XCTAssertEqual(landed, 0.99, accuracy: 1e-12,
                       "The landing point is the largest grid value the row admits.")
    }

    /// The other end, and it needs a bound that rounds DOWN — `0.005` would round away from
    /// zero and land back inside by luck, which is how a one-sided test passes on a two-sided
    /// defect.
    func testAnOffGridLowerBoundIsNeverUndercut() {
        let landed = ScrubPrecision.snapped(0.0, lowerBound: 0.994, upperBound: 1.0, decimals: 2)
        XCTAssertGreaterThanOrEqual(landed, 0.994 - slack(2), """
            snapped committed \(landed) on a row whose declared minimum is 0.994.
            """)
        XCTAssertEqual(landed, 1.0, accuracy: 1e-12,
                       "The landing point is the smallest grid value the row admits.")
    }

    /// A range narrower than one grid step holds no grid point at all. IN-RANGE wins over
    /// ON-GRID there: an out-of-range number reaches an engine, an off-grid one can only
    /// misdisplay. RED on the old rule, which committed `1.0` for a `0.4…0.6` row.
    func testARangeWithNoGridPointStaysInRange() {
        let landed = ScrubPrecision.snapped(0.55, lowerBound: 0.4, upperBound: 0.6, decimals: 0)
        XCTAssertGreaterThanOrEqual(landed, 0.4)
        XCTAssertLessThanOrEqual(landed, 0.6)
    }

    // MARK: - The counterweight: what must NOT move

    /// GREEN before and after — it guards the naive fix, not the defect. A bare `>` against the
    /// bound treats the `Float` round-trip of `0.95` as an overshoot and takes the row's
    /// maximum down to `0.94`.
    func testTheFloatRoundTripBoundIsNotTreatedAsOffGrid() {
        let bound = Double(Float(0.95))
        XCTAssertNotEqual(bound, 0.95, "The premise: Float(0.95) is not the literal 0.95.")
        let landed = ScrubPrecision.snapped(1.0, lowerBound: 0.0,
                                            upperBound: bound, decimals: 2)
        XCTAssertEqual(landed, 0.95, accuracy: 1e-12, """
            A bound that is on the grid as written but inexact as a Float was mistaken for an \
            off-grid bound, so the row can no longer reach 0.95. Five shipped rows are in that \
            state (#430).
            """)
    }

    /// Every shipped-shaped range, swept past both ends: the landing point must be bit-equal to
    /// what the old rule produced. Where the bound is on the grid, monotone rounding cannot
    /// cross it — so this slice is inert for the app as it stands today, and the sweep is what
    /// makes that claim checkable instead of asserted.
    func testEveryShippedShapedRangeIsUnchanged() {
        let rows: [(Double, Double, Int)] = [
            (0, 1, 2), (0, 1, 0), (20, 18000, 0), (40, 18000, 0), (-12, 12, 0), (-24, 24, 0),
            (-48, 0, 0), (-1, 1, 2), (0.05, 1, 2), (0, 0.45, 2), (1, 8, 0), (1, 16, 0),
            (1, 12, 0), (0, 10, 2), (0, 20, 2), (0, 50, 0), (8, 90, 0), (0.3, 1.5, 2),
            (0, 0.008, 3), (30, 300, 4), (380, 500, 2), (1, 65535, 0), (0, 32767, 0),
        ]
        var moved: [String] = []
        for (lo, hi, decimals) in rows {
            let span = hi - lo
            for i in 0...400 {
                let raw = lo - span * 0.1 + span * 1.2 * Double(i) / 400
                let now = ScrubPrecision.snapped(raw, lowerBound: lo,
                                                 upperBound: hi, decimals: decimals)
                let before = ScrubPrecision.gridded(
                    ScrubPrecision.clamped(raw, lowerBound: lo, upperBound: hi),
                    decimals: decimals)
                if now != before { moved.append("\(lo)…\(hi)@\(decimals) raw=\(raw)") }
            }
        }
        XCTAssertEqual(moved.count, 0, """
            \(moved.prefix(5).joined(separator: ", ")) — the interior rounding changed a value \
            on a range whose bounds are already on the grid. It must not: this slice is meant \
            to be inert for every row the app ships today.
            """)
    }

    // MARK: - The invariant itself

    /// The promise, stated as a sweep over ranges the app does NOT ship — including bounds
    /// deliberately placed off the grid, which is the whole point. Two claims: the result is
    /// inside the range to within `slack`, always; and it sits on the grid whenever the range
    /// contains a grid point at all.
    func testTheLandingPointIsAlwaysLegalForItsRow() {
        var outOfRange = 0
        var offGrid = 0
        var checked = 0
        var seed: UInt64 = 0x5EED_442
        func next() -> Double {                    // xorshift, so the sweep is reproducible
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 1_000_000) / 1_000_000
        }
        for _ in 0..<20_000 {
            let decimals = Int(next() * 5)         // 0…4, the shipped span
            let lo = next() * 200 - 100
            let hi = lo + next() * 40
            let raw = lo - 10 + next() * (hi - lo + 20)
            let step = pow(10.0, -Double(decimals))
            let landed = ScrubPrecision.snapped(raw, lowerBound: lo,
                                                upperBound: hi, decimals: decimals)
            checked += 1
            if landed < lo - slack(decimals) - 1e-12 || landed > hi + slack(decimals) + 1e-12 {
                outOfRange += 1
            }
            let holdsAGridPoint = (hi / step).rounded(.down) >= (lo / step).rounded(.up)
            if holdsAGridPoint, !onGrid(landed, decimals) { offGrid += 1 }
        }
        XCTAssertGreaterThan(checked, 19_000, "The sweep did not run — a green below proves nothing.")
        XCTAssertEqual(outOfRange, 0, "\(outOfRange) landings fell outside their own range.")
        XCTAssertEqual(offGrid, 0, """
            \(offGrid) landings were off the grid on a range that does contain a grid point. \
            Off-grid is only acceptable where no grid point exists at all.
            """)
    }
}
