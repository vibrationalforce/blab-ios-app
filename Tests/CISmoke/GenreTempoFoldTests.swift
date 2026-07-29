// GenreTempoFoldTests.swift
// Echoel — the body→tempo octave fold, in the BLOCKING bundle.
//
// THE CLAIM UNDER TEST is the product's one-sentence definition: *your body plays it.* Tempo is
// the half of that a listener perceives first, and `StudioCalculator.genreTempo` is the whole
// mapping — it takes the composed body tempo and folds it into the genre's BPM window.
//
// ⛔ WHY THIS FILE EXISTS. Between the B4 audit and 2026-07-29 that function INVERTED the
// mapping over a large part of its own input range. The old body halved a value that sat above
// the ceiling, never re-checked the floor, and then clamped — so on contemplation (44…66):
//
//     66 → 66        one BPM lower, and the window's top is reached
//     67 → 33.5 → 44 one BPM higher, and it collapses to the window's BOTTOM
//     80 → 40   → 44
//    134 → 67 → 33.5 → 44
//
// The faster the body, the slower the music. Measured in log space — the fraction of ONE octave
// of body tempo that collapsed onto the floor, `log2(2·lo/hi)` — that was 41 % of contemplation,
// 24 % of Fläche (46…78) and 90 % of psytrance (140…150), because every genre window in
// `MusicStyle.tempoRange` is NARROWER than an octave, which is exactly the condition the old
// two-loop shape could not handle.
//
// ⚠️ AND WHY IT IS HERE AND NOT IN `Tests/EchoelmusicTests`. `StudioCalculatorTests` already
// covered `genreTempo` with six cases and thirteen assertions — including one that asserts the
// nearest-edge rule the old code broke — and every one of them passed throughout, because none
// of them fed a value just above a ceiling. Two things follow, and the second is the reason for
// the directory:
// coverage is not protection unless it names the failure mode; and `Tests/EchoelmusicTests`
// builds only in `full-tests.yml`, which is `continue-on-error: true` on both its build and its
// run step. A regression pinned there cannot turn a merge red. `Tests/CISmoke` is the bundle
// `project.yml`'s `EchoelmusicTests` target actually compiles, and it is the blocking one.
//
// WHAT THIS CANNOT PROVE: that the resulting tempo sounds right, or that the value ever reaches
// the clock — `EchoelStudioView` moves at most ±8 BPM per evolve tick (25–45 s), so even a
// correct mapping arrives slowly. That is a separate, still-open defect.

import Foundation
import XCTest
@testable import Echoelmusic

final class GenreTempoFoldTests: XCTestCase {

    // MARK: - The inversion itself

    /// ⛔ THE REGRESSION GUARD. One BPM above the ceiling must stay AT the ceiling — it must not
    /// wrap around to the floor. This is the exact assertion the old code failed.
    func testAPulseJustAboveTheCeilingStaysAtTheCeiling() {
        // Contemplation, 44…66 — the slowest shipped window, and the one where a resting body
        // sits closest to the edge.
        XCTAssertEqual(StudioCalculator.genreTempo(67, into: 44...66), 66,
                       "67 bpm collapsed to the FLOOR. That is the inversion: a faster body "
                       + "produced the slowest tempo the genre allows.")
        XCTAssertEqual(StudioCalculator.genreTempo(134, into: 44...66), 66,
                       "134 halves to 67, which is still above the ceiling — the second halving "
                       + "must not be allowed to cross the floor unchecked.")
    }

    /// The property behind that single case, checked across every shipped `tempoRange` so a
    /// future genre is covered the day it is added rather than the day someone remembers this
    /// file: **the tempo handed to the clock is never more than one octave from the body.**
    ///
    /// ⚠️ NOTE WHAT THIS DELIBERATELY DOES *NOT* CLAIM, because the obvious stronger version is
    /// false and someone will try to "strengthen" it here. The mapping is NOT monotonic, and it
    /// cannot be: an octave fold into a sub-octave window has to break somewhere. On
    /// contemplation (44…66) the break is at √(2·44·66) = 76.2 —
    ///
    ///     body 76.0 → 66 (the ceiling)      body 76.5 → 44 (the floor)
    ///
    /// — so a faster body really does land lower, right at that one point. That is correct
    /// behaviour, and the geometric mean is the right place for it (it is where halving and
    /// holding are equally far in musical terms). The DEFECT this file was written for is
    /// different in kind: the break used to sit at the CEILING, one BPM above it, so the
    /// collapse was not a single crossover but 41–90 % of every window.
    func testTheChosenTempoIsNeverMoreThanAnOctaveFromTheBody() {
        for style in MusicStyle.allCases {
            let range = style.tempoRange
            // Walk the window and one octave above it in 0.5 bpm steps.
            var bpm = range.lowerBound
            let top = range.upperBound * 2
            // Every window shipped today is narrower than an octave (widest: klezmer 90…170,
            // ratio 1.89). A window that spans a FULL octave always has an exact octave of the
            // body inside it, so the one-octave bound is trivially satisfied there — but the
            // walk above would reach `2·hi`, which folds down TWICE and sits a factor of 4 from
            // the body while being perfectly correct. Guarding the assertion rather than the
            // loop keeps this test from reddening the BLOCKING gate on correct code the day a
            // wide genre is added.
            let isSubOctaveWindow = range.upperBound < range.lowerBound * 2
            while bpm <= top {
                let folded = StudioCalculator.genreTempo(bpm, into: range)
                XCTAssertTrue(range.contains(folded),
                              "\(style): \(bpm) → \(folded) escaped \(range)")
                // The result is always either an exact octave of the body or a bound of the
                // window — never an arbitrary number. This half holds for ANY window width.
                let isOctaveOfBody = Self.isOctaveMultiple(folded, of: bpm)
                XCTAssertTrue(isOctaveOfBody
                              || folded == range.lowerBound || folded == range.upperBound,
                              "\(style): \(bpm) → \(folded) is neither an octave of the body "
                              + "nor a bound of \(range).")
                if isSubOctaveWindow {
                    let ratio = folded > bpm ? folded / bpm : bpm / folded
                    XCTAssertLessThanOrEqual(ratio, 2.0 + 1e-9,
                                             "\(style): body \(bpm) → \(folded) is more than an "
                                             + "octave away; the fold picked the wrong side of "
                                             + "\(range).")
                }
                bpm += 0.5
            }
        }
    }

    /// `value == base · 2^k` for some integer k. Exact in binary floating point — doubling and
    /// halving are lossless — so this needs no tolerance.
    ///
    /// ⛔ The second loop's condition is `>= base * 2`, NOT `> base`. With `> base` this hangs
    /// forever on any value that is not an octave multiple (66 against 76.5 oscillates 66 ↔ 132
    /// and never settles) — a test helper that hangs the blocking gate is worse than the bug it
    /// was written to catch. As written, the value is driven into `[base, 2·base)` and stops.
    private static func isOctaveMultiple(_ value: Double, of base: Double) -> Bool {
        guard value > 0, base > 0, value.isFinite, base.isFinite else { return false }
        var v = value
        while v < base { v *= 2 }
        while v >= base * 2 { v /= 2 }
        return v == base
    }

    // MARK: - The behaviour that must NOT change

    /// The whole point of B4: a resting pulse still drives a fast genre, at double time. These
    /// mirror `StudioCalculatorTests` deliberately — those live in the non-blocking bundle, and
    /// a fix to the inversion is exactly the kind of change that could quietly break them there
    /// without anything going red.
    func testARestingPulseStillDrivesAFastGenreAtDoubleTime() {
        XCTAssertEqual(StudioCalculator.genreTempo(66, into: 130...150), 132)   // Trap
        XCTAssertEqual(StudioCalculator.genreTempo(72, into: 130...150), 144)   // Trap
        XCTAssertEqual(StudioCalculator.genreTempo(90, into: 160...210), 180)   // Punk
        XCTAssertEqual(StudioCalculator.genreTempo(120, into: 110...155), 120)  // Rock, direct
    }

    /// The runaway guard that motivated the fold in the first place (founder: *"springt ständig
    /// auf 196 bpm"*). A doubled rPPG estimate must not slam the clock.
    func testADoubledPulseEstimateDoesNotSlamTheClock() {
        XCTAssertEqual(StudioCalculator.genreTempo(196, into: 115...125), 115)
        XCTAssertEqual(StudioCalculator.genreTempo(196, into: 110...155), 110)
        XCTAssertEqual(StudioCalculator.genreTempo(66, into: 160...210), 160)
    }

    /// Non-finite and non-positive input reaches this function from the bio path (a bad rPPG
    /// frame produces NaN), so the guard is load-bearing, not defensive decoration.
    func testDegenerateInputFallsBackToTheFloor() {
        XCTAssertEqual(StudioCalculator.genreTempo(0, into: 130...150), 130)
        XCTAssertEqual(StudioCalculator.genreTempo(-20, into: 130...150), 130)
        XCTAssertEqual(StudioCalculator.genreTempo(.infinity, into: 130...150), 130)
        XCTAssertEqual(StudioCalculator.genreTempo(.nan, into: 130...150), 130)
    }

    /// Termination. Both loops in the implementation run on a value the caller supplies; an
    /// extreme one must still return, and return something playable.
    func testExtremeInputTerminatesInsideTheWindow() {
        for t in [1e-6, 1.0, 40, 65.4321, 100, 133, 500, 10_000, 1e9] {
            let r = StudioCalculator.genreTempo(t, into: 140...150)
            XCTAssertTrue((140...150).contains(r), "t=\(t) → \(r) must land in 140–150")
        }
    }
}
