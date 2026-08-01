// PoincareMetricsTests.swift
// Echoel — #347 Slice 3a. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PROTECTS: the one place in the app where a drawn shape is meant to carry
// PHYSIOLOGICAL meaning. SD1 and SD2 have published definitions; a readout that prints
// them and computes something adjacent is the lying-control class (#164/#227) landing in
// the one area where the app touches the body. So the numbers are asserted against values
// derived independently, not against whatever the implementation happens to return.
//
// TWO tests are load-bearing, for two different mistakes:
//   · `testTheAlternatingSeriesHasNoSpreadAlongTheDiagonal` separates the GEOMETRIC
//     definition (what this file implements) from the textbook ALGEBRAIC identity (what
//     the first draft implemented, and what a future "simplification" will reach for):
//     they disagree, and geometry is right.
//   · `testAGapIsNotClosedIntoAFabricatedBeatPair` separates SEGMENTS from a compacted
//     array. The first draft compacted, which invents a beat-to-beat transition that never
//     happened — and the invented point looks completely ordinary in the picture.

import Foundation
import XCTest
@testable import Echoelmusic

final class PoincareMetricsTests: XCTestCase {

    // MARK: - the definition

    /// THE case that proves the formula. Every point of 800, 840, 800, 840 … is either
    /// (800, 840) or (840, 800); both sum to 1640, so the cloud has literally no extent
    /// along the line of identity and SD2 must be 0.
    ///
    /// The algebraic identity `SD2² = 2·SDNN² − ½·SDSD²` does NOT answer 0 here, and which
    /// wrong answer it gives depends on the divisors — 4.0406 with both deviations
    /// population, 11.4286 with a sample SDNN. If someone rewrites `descriptors` in terms
    /// of SDNN/SDSD "to reuse HRVMetrics", this is the test that stops them.
    func testTheAlternatingSeriesHasNoSpreadAlongTheDiagonal() throws {
        let rr = [800.0, 840, 800, 840, 800, 840, 800, 840]
        let d = try XCTUnwrap(PoincareMetrics.descriptors(rrMs: rr))

        // EXACTLY zero, with no `accuracy:` — and that is deliberate, not strictness for
        // its own sake. In `Double` this series projects to a spread of 2.27e−13 along the
        // diagonal, which sails through any tolerant comparison. `collapsed(_:)` is what
        // turns it into a real zero, and an `accuracy: 1e-9` assertion here would pass with
        // that function deleted — i.e. it would cover nothing.
        XCTAssertEqual(d.sd2, 0.0, """
            SD2 came out \(d.sd2) for a series whose every Poincaré point sums to 1640, \
            i.e. a cloud with zero extent along the identity line. Two likely causes: a \
            rewrite in terms of `2·SDNN² − ½·SDSD²` (which answers 4.0406 or 11.4286 here, \
            depending on the divisors, because its SDNN covers all 8 intervals while the \
            cloud has 7 points), or the removal of `collapsed(_:)`, which leaves the \
            2.27e−13 of float residue standing where a measurement belongs.
            """)
        XCTAssertEqual(d.sd1, 27.994168, accuracy: 1e-5, """
            SD1 came out \(d.sd1), expected 27.994168 — the population SD of \
            (RR(n) − RR(n+1))/√2 over the 7 pairs. Unlike SD2, SD1 is the SAME quantity in \
            both formulations (the perpendicular projection is ±SDSD/√2 exactly), so a \
            mismatch here means the projection, the divisor or the pairing changed — not \
            the choice between geometry and the identity.
            """)
        XCTAssertNil(d.ratio, """
            SD2 is zero, so SD1/SD2 does not exist and `ratio` must be nil. It returned \
            \(String(describing: d.ratio)).

            AND THIS IS NOT THE OBVIOUS `sd2 > 0` CHECK, which is why it has its own \
            assertion: in `Double` this series yields sd2 = 2.3e-13 before collapsing. A \
            `> 0` guard passes it and reports a ratio of 1.2e14 — a number printed on \
            screen, from arithmetic residue.
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
    /// derived independently so a plausible-looking drift cannot pass. Every step here is
    /// well inside the Malik 20 % bound, so hygiene keeps all ten intervals as ONE segment
    /// and the pair count is the full 9.
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
        let pts: [PoincareMetrics.Point] =
            PoincareMetrics.points(segments: [[800, 810, 820, 830]])
        let expected: [PoincareMetrics.Point] = [
            PoincareMetrics.Point(rr: 800, next: 810),
            PoincareMetrics.Point(rr: 810, next: 820),
            PoincareMetrics.Point(rr: 820, next: 830)
        ]
        XCTAssertEqual(pts, expected)
        XCTAssertEqual(PoincareMetrics.points(segments: [[800]]).count, 0)
        XCTAssertEqual(PoincareMetrics.points(segments: []).count, 0)
    }

    /// Pairing must stop at a segment boundary. Two segments of two beats give TWO points,
    /// not three — the third would be the beat before a gap paired with the beat after it.
    func testPointsNeverPairAcrossASegmentBoundary() {
        let pts: [PoincareMetrics.Point] =
            PoincareMetrics.points(segments: [[800, 810], [820, 830]])
        let expected: [PoincareMetrics.Point] = [
            PoincareMetrics.Point(rr: 800, next: 810),
            PoincareMetrics.Point(rr: 820, next: 830)
        ]
        XCTAssertEqual(pts, expected, """
            Pairing across the boundary produced \(pts.count) points where 2 are real. \
            The extra one would be (810, 820) — two beats separated by whatever was \
            rejected between them, drawn as if one had followed the other.
            """)
    }

    // MARK: - hygiene

    /// ⭐ THE REGRESSION GUARD for the defect this file shipped with. `dirty` is `clean`
    /// with a 9999 ms dropout and a NaN spliced in; COMPACTING the survivors reproduces
    /// `clean` exactly, so the old implementation returned identical numbers for the two.
    /// Segments do not: each rejection costs a pair, and the answers must differ.
    ///
    /// This is not a novel judgement — `RRIntervalHygiene`'s own header names the trap
    /// ("a compacted array makes the two beats either side of a removed one look
    /// adjacent"), and `HRVMetrics.rmssd(segments:)` already consumes the segment form.
    func testAGapIsNotClosedIntoAFabricatedBeatPair() throws {
        let clean = try XCTUnwrap(PoincareMetrics.descriptors(rrMs: [820, 795, 810, 780, 830]))
        let dirty = try XCTUnwrap(
            PoincareMetrics.descriptors(rrMs: [820, 9999, 795, 810, .nan, 780, 830]))

        XCTAssertEqual(clean.pairs, 4)
        XCTAssertEqual(dirty.pairs, 2, """
            The dirty series has \(dirty.pairs) pairs. Its accepted segments are \
            [820], [795, 810], [780, 830] — one pair each from the last two, none from a \
            lone interval. A count of 4 means the survivors were compacted into one run \
            and two transitions that never happened were drawn and measured.
            """)
        XCTAssertNotEqual(dirty.sd1, clean.sd1, """
            SD1 is \(dirty.sd1) for both the clean series and the same series with a \
            dropout and a NaN spliced in. Identical answers are the SIGNATURE of \
            compaction: the survivors of the dirty series ARE the clean series, so any \
            implementation that closes the gaps cannot tell them apart. Expected \
            22.980970 (clean, 4 pairs) vs 12.374369 (dirty, 2 pairs).
            """)
        XCTAssertEqual(clean.sd1, 22.980970, accuracy: 1e-5)
        XCTAssertEqual(dirty.sd1, 12.374369, accuracy: 1e-5)
        XCTAssertEqual(dirty.sd2, 1.767767, accuracy: 1e-5)
    }

    /// Hygiene is `RRIntervalHygiene`'s, not a second band re-derived here. One definition
    /// per repo: the previous version of this file carried its own 250…2000 window with no
    /// ectopic rule, so two files disagreed about what a heartbeat is.
    func testHygieneIsTheSharedOneAndNotALocalCopy() {
        let raw: [Double] = [800, 4000, 810, 120, 820, .nan, 830, .infinity]
        XCTAssertEqual(PoincareMetrics.segments(raw),
                       RRIntervalHygiene.acceptedSegments(rrMs: raw))
        // 4000 ms is 15 bpm and 120 ms is 500 bpm — neither is a heartbeat — and NaN/inf
        // must never reach a coordinate. What survives here is four ISOLATED beats, so
        // there is no pair at all and no number may be stated.
        let survivors: [[Double]] = [[800], [810], [820], [830]]
        XCTAssertEqual(PoincareMetrics.segments(raw), survivors)
        XCTAssertNil(PoincareMetrics.descriptors(rrMs: raw))
    }

    /// Negative and zero intervals are not beats. Pinned separately from the upper bound
    /// because a sign error upstream produces exactly these and they would otherwise sail
    /// through any "is it finite" check.
    func testNegativeAndZeroIntervalsAreNotBeats() {
        let raw: [Double] = [0, -800, 800, 810, 820]
        let survivors: [[Double]] = [[800, 810, 820]]
        XCTAssertEqual(PoincareMetrics.segments(raw), survivors)
    }

    // MARK: - the single entry point

    /// A view must get the cloud and the numbers from ONE call, or it can draw one set of
    /// beats and label it with statistics from another. `analyse` is that call, and this
    /// pins that its two halves are computed from the same segments.
    func testAnalyseLabelsExactlyWhatItDraws() throws {
        let raw = [820.0, 9999, 795, 810, .nan, 780, 830]
        let a = try XCTUnwrap(PoincareMetrics.analyse(rrMs: raw))

        XCTAssertEqual(a.points.count, a.descriptors.pairs, """
            \(a.points.count) points drawn against \(a.descriptors.pairs) pairs measured. \
            One point IS one pair; a mismatch means the picture and the caption came from \
            different series.
            """)
        XCTAssertEqual(a.points, PoincareMetrics.points(segments: PoincareMetrics.segments(raw)))
        XCTAssertEqual(a.descriptors, try XCTUnwrap(PoincareMetrics.descriptors(rrMs: raw)))
        // 5 of 7 raw intervals survived — below `minAcceptedFractionForHRV` (0.8), which
        // is what a view is meant to check before presenting SD1/SD2 as a body figure.
        XCTAssertEqual(a.acceptedFraction, 5.0 / 7.0, accuracy: 1e-12)
        XCTAssertLessThan(a.acceptedFraction, RRIntervalHygiene.minAcceptedFractionForHRV)
        XCTAssertNil(PoincareMetrics.analyse(rrMs: [800, 810]))
    }

    // MARK: - the edges

    /// Too little data reports NOTHING rather than a tidy zero. Two intervals give one
    /// point, and one point has no spread in any direction.
    func testTooFewBeatsReportNothing() {
        XCTAssertNil(PoincareMetrics.descriptors(rrMs: []))
        XCTAssertNil(PoincareMetrics.descriptors(rrMs: [800]))
        XCTAssertNil(PoincareMetrics.descriptors(rrMs: [800, 810]))
        XCTAssertNotNil(PoincareMetrics.descriptors(rrMs: [800, 810, 820]))
        // Three RAW values of which one is junk are two ISOLATED beats, not two
        // consecutive ones — no pair survives, so there is nothing to describe.
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
        XCTAssertEqual(d.pairs, 2)
        XCTAssertTrue(PoincareMetrics.points(segments: PoincareMetrics.segments([.nan, 800, 810]))
            .allSatisfy { $0.rr.isFinite && $0.next.isFinite })
    }
}
