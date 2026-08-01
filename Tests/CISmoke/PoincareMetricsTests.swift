// PoincareMetricsTests.swift
// Echoel — #347 Slice 3a. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PROTECTS: the one place in the app where a drawn shape is meant to carry
// PHYSIOLOGICAL meaning. SD1 and SD2 have published definitions; a readout that prints
// them and computes something adjacent is the lying-control class (#164/#227) landing in
// the one area where the app touches the body. So the numbers are asserted against values
// derived independently, not against whatever the implementation happens to return.
//
// The load-bearing test is `testTheAlternatingSeriesHasNoSpreadAlongTheDiagonal`. It is
// the case that separates the GEOMETRIC definition (what this file implements) from the
// textbook ALGEBRAIC identity (what the first draft implemented, and what a future
// "simplification" will reach for): they disagree, and geometry is right.

import Foundation
import XCTest
@testable import Echoelmusic

final class PoincareMetricsTests: XCTestCase {

    // MARK: - the definition

    /// THE case that proves the formula. Every point of 800, 840, 800, 840 … is either
    /// (800, 840) or (840, 800); both sum to 1640, so the cloud has literally no extent
    /// along the line of identity and SD2 must be 0.
    ///
    /// The algebraic identity `SD2² = 2·SDNN² − ½·SDSD²` returns 4.0406 here — not a
    /// rounding difference but a different quantity, because its SDNN is taken over all 8
    /// intervals while the cloud has 7 points. If someone rewrites `descriptors` in terms
    /// of SDNN/SDSD "to reuse HRVMetrics", this is the test that stops them.
    func testTheAlternatingSeriesHasNoSpreadAlongTheDiagonal() throws {
        let rr = [800.0, 840, 800, 840, 800, 840, 800, 840]
        let d = try XCTUnwrap(PoincareMetrics.descriptors(rrMs: rr))

        XCTAssertEqual(d.sd2, 0, accuracy: 1e-9, """
            SD2 came out \(d.sd2) for a series whose every Poincaré point sums to 1640, \
            i.e. a cloud with zero extent along the identity line. The most likely cause \
            is a rewrite in terms of `2·SDNN² − ½·SDSD²`, which answers 4.0406 here \
            because its SDNN covers all 8 intervals while the cloud has 7 points. SD2 is \
            the spread of the CLOUD, so it must be computed from the cloud.
            """)
        XCTAssertEqual(d.sd1, 27.994168, accuracy: 1e-5, """
            SD1 came out \(d.sd1), expected 27.994168 — the population SD of \
            (RR(n) − RR(n+1))/√2 over the 7 pairs. Unlike SD2 this value is the same in \
            both formulations, so a mismatch here means the projection or the divisor \
            changed, not the choice of formula.
            """)
        XCTAssertNil(d.ratio, """
            SD2 is zero, so SD1/SD2 does not exist and `ratio` must be nil. It returned \
            \(String(describing: d.ratio)).

            AND THIS IS NOT THE OBVIOUS `sd2 > 0` CHECK, which is why it has its own \
            assertion: in `Double` this series yields sd2 = 2.3e-13, not 0. A `> 0` guard \
            passes it and reports a ratio of 1.2e14 — a number printed on screen, from \
            arithmetic residue. `degenerateSpreadMs` is what collapses it; if that constant \
            is removed or inlined as a bare zero-test, this is the assertion that catches it.
            """)
        XCTAssertEqual(d.pairs, 7)
    }

    /// A monotone ramp is the mirror image: every successive difference is identical, so
    /// there is no perpendicular scatter at all and SD1 is exactly 0 while SD2 is large.
    /// It also refutes the folklore that "SD1 = RMSSD/√2" always holds — here RMSSD/√2 is
    /// 14.14 and SD1 is 0, because that shortcut silently assumes the mean successive
    /// difference is zero.
    func testAMonotoneRampHasNoBeatToBeatScatter() throws {
        let rr = [800.0, 820, 840, 860, 880, 900, 920, 940]
        let d = try XCTUnwrap(PoincareMetrics.descriptors(rrMs: rr))

        XCTAssertEqual(d.sd1, 0, accuracy: 1e-9, """
            SD1 is \(d.sd1) for a series whose successive differences are all exactly \
            20 ms. Constant differences mean zero SCATTER around them; a non-zero answer \
            suggests RMSSD (a root-mean-square about zero) was used where a standard \
            deviation (about the mean) belongs. On this vector the two differ by 14.14.
            """)
        XCTAssertEqual(d.sd2, 56.568542, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(d.ratio), 0, accuracy: 1e-9)
    }

    /// A realistic, non-degenerate window — the everyday path, pinned against values
    /// derived independently so a plausible-looking drift cannot pass.
    func testARealisticWindowMatchesTheIndependentlyDerivedValues() throws {
        let rr = [820.0, 795, 810, 780, 830, 800, 815, 790, 825, 805]
        let d = try XCTUnwrap(PoincareMetrics.descriptors(rrMs: rr))
        XCTAssertEqual(d.sd1, 20.548047, accuracy: 1e-5)
        XCTAssertEqual(d.sd2, 8.351831, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(d.ratio), 2.460304, accuracy: 1e-5)
        XCTAssertEqual(d.pairs, 9)
    }

    // MARK: - the cloud

    /// Points must come from ADJACENT entries. If the pairing ever skips or wraps, the
    /// picture still looks like a Poincaré plot while showing beats that never followed
    /// one another — the worst kind of wrong, because it is invisible.
    func testPointsPairAdjacentBeatsOnly() {
        // Both sides annotated: `XCTAssertEqual`'s two autoclosures plus a bare `.init`
        // literal is a generic-inference knot, and this repo has taken the blocking gate
        // down twice over type-check cost in test files (see HARNESS_LEDGER).
        let pts: [PoincareMetrics.Point] = PoincareMetrics.points([800, 810, 820, 830])
        let expected: [PoincareMetrics.Point] = [
            PoincareMetrics.Point(rr: 800, next: 810),
            PoincareMetrics.Point(rr: 810, next: 820),
            PoincareMetrics.Point(rr: 820, next: 830)
        ]
        XCTAssertEqual(pts, expected)
        XCTAssertEqual(PoincareMetrics.points([800]).count, 0)
        XCTAssertEqual(PoincareMetrics.points([]).count, 0)
    }

    /// Implausible intervals are dropped BEFORE pairing. An rPPG dropout arrives as one
    /// impossible 4-second interval; left in, it rescales the axes and squashes the real
    /// cloud into a dot.
    func testImplausibleIntervalsAreFilteredOut() {
        let cleaned = PoincareMetrics.plausible([800, 4000, 810, 120, 820, .nan, 830, .infinity])
        XCTAssertEqual(cleaned, [800, 810, 820, 830], """
            Filtering kept \(cleaned). 4000 ms is 15 bpm and 120 ms is 500 bpm — neither \
            is a heartbeat — and NaN/inf must never reach a coordinate.
            """)
    }

    /// The filter runs inside `descriptors`, not only when a caller remembers it.
    func testDescriptorsFilterBeforeMeasuring() throws {
        let clean = try XCTUnwrap(PoincareMetrics.descriptors(rrMs: [820, 795, 810, 780, 830]))
        let dirty = try XCTUnwrap(
            PoincareMetrics.descriptors(rrMs: [820, 9999, 795, 810, .nan, 780, 830]))
        XCTAssertEqual(dirty.sd1, clean.sd1, accuracy: 1e-9, """
            A 9999 ms dropout changed SD1 from \(clean.sd1) to \(dirty.sd1), so \
            `descriptors` measured the raw series. It must call `plausible(_:)` first — \
            and note the filtered result is NOT merely "the clean one with a gap": \
            removing an interval joins its neighbours into a new pair, which is why the \
            two must be compared on identical surviving series.
            """)
        XCTAssertEqual(dirty.pairs, clean.pairs)
    }

    // MARK: - the edges

    /// Too little data reports NOTHING rather than a tidy zero. Two intervals give one
    /// point, and one point has no spread in any direction.
    func testTooFewBeatsReportNothing() {
        XCTAssertNil(PoincareMetrics.descriptors(rrMs: []))
        XCTAssertNil(PoincareMetrics.descriptors(rrMs: [800]))
        XCTAssertNil(PoincareMetrics.descriptors(rrMs: [800, 810]))
        XCTAssertNotNil(PoincareMetrics.descriptors(rrMs: [800, 810, 820]))
        // Three RAW values of which one is junk are still only two real intervals.
        XCTAssertNil(PoincareMetrics.descriptors(rrMs: [800, 9999, 810]))
    }

    /// A perfectly constant series has no spread in either direction. It must not trap,
    /// must not produce NaN, and must not invent a ratio out of 0/0.
    func testAConstantSeriesIsFlatInBothDirections() throws {
        let d = try XCTUnwrap(PoincareMetrics.descriptors(rrMs: [800, 800, 800, 800]))
        XCTAssertEqual(d.sd1, 0, accuracy: 1e-12)
        XCTAssertEqual(d.sd2, 0, accuracy: 1e-12)
        XCTAssertNil(d.ratio)
    }

    /// Hostile input must never reach a coordinate. This feeds a drawing loop, where a
    /// NaN becomes an undrawn or wildly out-of-frame point and reads as a rendering bug.
    func testNonFiniteInputCannotProduceANumber() throws {
        XCTAssertNil(PoincareMetrics.descriptors(rrMs: [.nan, .infinity, -.infinity]))
        let d = try XCTUnwrap(
            PoincareMetrics.descriptors(rrMs: [.nan, 820, 795, .infinity, 810, 780]))
        XCTAssertTrue(d.sd1.isFinite && d.sd2.isFinite)
        XCTAssertTrue(PoincareMetrics.points(PoincareMetrics.plausible([.nan, 800, 810]))
            .allSatisfy { $0.rr.isFinite && $0.next.isFinite })
    }

    /// Negative and zero intervals are not beats. Pinned separately from the upper bound
    /// because a sign error upstream produces exactly these and they would otherwise sail
    /// through any "is it finite" check.
    func testNegativeAndZeroIntervalsAreNotBeats() {
        XCTAssertEqual(PoincareMetrics.plausible([0, -800, 800, 810, 820]), [800, 810, 820])
    }
}
