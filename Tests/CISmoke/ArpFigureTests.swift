// ArpFigureTests.swift
// Echoel — the arp's order walk, in the BLOCKING bundle.
//
// FOUNDER 2026-07-29: *"Vielleicht ist der arp auch eine eigene Kategorie und könnte ein
// komplexes bedienelement werden."* `ArpFigure` is the first slice of that: which chord tone, in
// which octave, at walk position i. No key, no pitch, no surface, no clock.
//
// WHY BEHAVIOURAL AND NOT A SOURCE SCAN, unlike the guards this bundle also holds: the whole type
// is `public static` on a pure Foundation enum, so every property below runs for real. There is
// nothing here that needs text-matching, and a source scan where a behavioural test is possible
// is a weaker test wearing the same green.
//
// ⚠️ THE ONE AN IMPLEMENTER GETS WRONG is `.upDown`'s turnaround, and it is worth naming before
// the assertions: the naive version plays the top note twice (…D E E D…) because it concatenates
// an ascending and a descending pass. The cycle length is 2n−2, not 2n. Test 2 is that, and it is
// the reason this file exists rather than a spot check.

import Foundation
import XCTest
@testable import Echoelmusic

final class ArpFigureTests: XCTestCase {

    /// The triad, as the shipped default will hand it in (#220 S3): scale-degree indices.
    private let triad = [0, 2, 4]

    /// One full cycle of a walk, as `Step`s. `nil` steps are kept as `nil` so a test can see
    /// them rather than have them silently dropped.
    private func walk(_ order: ArpFigure.Order,
                      chord: [Int]? = nil,
                      octaves: Int = 1,
                      length: Int,
                      seed: UInt64 = 7,
                      from start: Int = 0) -> [ArpFigure.Step?] {
        (start..<(start + length)).map {
            ArpFigure.step(atIndex: $0, chordDegrees: chord ?? triad,
                           octaves: octaves, order: order, seed: seed)
        }
    }

    // MARK: - 1. Up and down are mirror images

    func testUpAndDownAreMirrorImages() throws {
        let up = try walk(.up, length: 3).map { try XCTUnwrap($0) }
        let down = try walk(.down, length: 3).map { try XCTUnwrap($0) }
        XCTAssertEqual(up.reversed().map { $0 }, down,
                       "`.down` is not the reverse of `.up` over one cycle — the two are the same "
                       + "figure read the other way and nothing else")
        // Anti-vacuity: a symmetric-by-accident implementation (both orders returning the same
        // constant) would pass the line above.
        XCTAssertNotEqual(up, down, "the two orders produced the identical walk")
    }

    /// …and the octave sits OUTSIDE the degree loop, which is the shape a listener expects: an
    /// ascending two-octave arp climbs the whole chord, then climbs it again an octave up. The
    /// wrong nesting (octave inner, degree outer) also "covers everything" and is caught nowhere
    /// else, because coverage tests pass for both.
    func testTheOctaveIsTheOuterLoopNotTheInner() throws {
        let up = try walk(.up, octaves: 2, length: 6).map { try XCTUnwrap($0) }
        XCTAssertEqual(up.map(\.octaveOffset), [0, 0, 0, 1, 1, 1],
                       "the walk alternates octaves per note instead of finishing the chord "
                       + "first — it would arpeggiate in leaps rather than climb")
        XCTAssertEqual(up.map(\.degreeIndex), [0, 2, 4, 0, 2, 4])
    }

    /// `.down` on two octaves must start at the TOP octave's top tone. This is the assertion the
    /// canonical-ascending-plus-permutation design exists to make true; an implementation that
    /// reverses only the degree loop would descend each octave but climb between them.
    func testDownStartsAtTheTopOfTheTopOctave() throws {
        let first = try XCTUnwrap(walk(.down, octaves: 2, length: 1).first ?? nil)
        XCTAssertEqual(first, ArpFigure.Step(degreeIndex: 4, octaveOffset: 1))
        let down = try walk(.down, octaves: 2, length: 6).map { try XCTUnwrap($0) }
        XCTAssertEqual(down.map(\.octaveOffset), [1, 1, 1, 0, 0, 0])
    }

    // MARK: - 2. The turnaround

    func testUpDownDoesNotRepeatTheTurnaround() throws {
        // Three tones, one octave → cycle 3 → walk length 2·3−2 = 4: 0 1 2 1.
        let seq = try walk(.upDown, length: 4).map { try XCTUnwrap($0) }
        XCTAssertEqual(seq.map(\.degreeIndex), [0, 2, 4, 2],
                       "the up-down walk is not 2n−2 long — the naive version plays the "
                       + "turnaround twice (0 2 4 4 2 0) and that doubled note is audible")

        // Stated as a property too, so it survives a re-voiced default chord: no adjacent repeat,
        // including across the wrap from the end of one cycle into the start of the next.
        let two = try walk(.upDown, length: 8).map { try XCTUnwrap($0) }
        for (a, b) in zip(two, two.dropFirst()) {
            XCTAssertNotEqual(a, b, "up-down repeated \(a) back to back")
        }
    }

    func testDownUpIsTheMirrorAndAlsoDoesNotRepeat() throws {
        let seq = try walk(.downUp, length: 4).map { try XCTUnwrap($0) }
        XCTAssertEqual(seq.map(\.degreeIndex), [4, 2, 0, 2])
        let two = try walk(.downUp, length: 8).map { try XCTUnwrap($0) }
        for (a, b) in zip(two, two.dropFirst()) {
            XCTAssertNotEqual(a, b, "down-up repeated \(a) back to back")
        }
    }

    /// A ONE-TONE chord has no turnaround to avoid, and `2·1−2 == 0` would be a division by zero
    /// in the wrap. Pinned because it is the degenerate case a walk-length formula invites.
    func testASingleToneChordDoesNotDivideByZero() throws {
        for order in ArpFigure.Order.allCases {
            let seq = try walk(order, chord: [3], length: 5).map { try XCTUnwrap($0) }
            XCTAssertEqual(Set(seq), [ArpFigure.Step(degreeIndex: 3, octaveOffset: 0)],
                           "\(order) on a one-tone chord produced something other than that tone")
        }
    }

    // MARK: - 3. Coverage

    /// Every chord tone in every octave, exactly once per cycle — for all six orders. This is the
    /// property that makes an arp an arp: a walk that drops a tone or repeats one within a cycle
    /// is heard as a wrong pattern, not as a variation.
    func testTheWalkCoversEveryChordToneInEveryOctaveExactlyOncePerCycle() throws {
        for order in ArpFigure.Order.allCases {
            for octaves in 1...ArpFigure.maxOctaves {
                let cycle = triad.count * octaves
                let seen = try walk(order, octaves: octaves, length: cycle)
                    .map { try XCTUnwrap($0) }
                XCTAssertEqual(Set(seen).count, cycle,
                               "\(order) × \(octaves) octaves visited \(Set(seen).count) of "
                               + "\(cycle) positions in one cycle — it drops or repeats a tone")
            }
        }
    }

    // MARK: - 4. Octaves are capped, not climbed out of

    func testOctavesAreCappedInsteadOfClimbingOutOfTheSurface() throws {
        for absurd in [99, Int.max, 4] {
            let seq = try walk(.up, octaves: absurd, length: 200).map { try XCTUnwrap($0) }
            let highest = seq.map(\.octaveOffset).max() ?? 0
            XCTAssertLessThan(highest, ArpFigure.maxOctaves,
                              "octaves: \(absurd) produced octaveOffset \(highest) — the play "
                              + "surface has only \(ArpFigure.maxOctaves) bands "
                              + "(TouchPitchMap.octaveBands), so anything above could not sound")
        }
        // …and downward too: 0 and negative must become 1, not 0 (a zero span is silence).
        for tooLow in [0, -1, Int.min] {
            let seq = try walk(.up, octaves: tooLow, length: 6).map { try XCTUnwrap($0) }
            XCTAssertEqual(Set(seq.map(\.octaveOffset)), [0],
                           "octaves: \(tooLow) must collapse to a single octave, not to nothing")
            XCTAssertEqual(Set(seq.map(\.degreeIndex)), Set(triad))
        }
    }

    // MARK: - 5. An empty chord is nil, not a substituted note

    func testAnEmptyChordIsNilNotAnEmptyStep() {
        for order in ArpFigure.Order.allCases {
            XCTAssertNil(ArpFigure.step(atIndex: 0, chordDegrees: [], octaves: 1,
                                        order: order, seed: 1),
                         "\(order) invented a note for an empty chord. A generator that "
                         + "substitutes the root for `nothing to play` sounds like a stuck note "
                         + "and reads on a device as a broken arp")
            // An all-negative chord sanitizes to empty and must behave the same way.
            XCTAssertNil(ArpFigure.step(atIndex: 3, chordDegrees: [-1, -7], octaves: 2,
                                        order: order, seed: 1))
        }
    }

    // MARK: - 6. The seed reaches exactly one order

    /// Copy of the assertion shape in `FieldAutoPlaySmokeTests.testTheSeedOnlyChangesTheMotionThatUsesIt`:
    /// five of the six orders are SHAPES and must be reproducible without a seed; only `.random`
    /// is a draw. A seed leaking into `.up` would make a saved take unrepeatable.
    func testTheSameSeedProducesTheSameWalkAndOnlyRandomUsesIt() throws {
        for order in ArpFigure.Order.allCases {
            let a = try walk(order, octaves: 2, length: 24, seed: 11).map { try XCTUnwrap($0) }
            let again = try walk(order, octaves: 2, length: 24, seed: 11).map { try XCTUnwrap($0) }
            XCTAssertEqual(a, again, "\(order) is not deterministic from its own arguments")

            let other = try walk(order, octaves: 2, length: 24, seed: 12).map { try XCTUnwrap($0) }
            if order == .random {
                XCTAssertNotEqual(a, other, "`.random` ignored the seed — it is the one order "
                                  + "that is supposed to change with it")
            } else {
                XCTAssertEqual(a, other, "\(order) changed with the seed. It is a shape, not a "
                               + "draw, and a saved take must reproduce it")
            }
        }
    }

    /// `.random` must re-draw per CYCLE, not once forever — otherwise it is `.asPlayed` with a
    /// scrambled chord, which is a different (and much duller) feature than the one offered.
    func testRandomRedrawsEachCycleRatherThanRepeatingOne() throws {
        let cycle = triad.count
        let first = try walk(.random, length: cycle, seed: 5).map { try XCTUnwrap($0) }
        var sawADifferentCycle = false
        for c in 1..<12 {
            let next = try walk(.random, length: cycle, seed: 5, from: c * cycle)
                .map { try XCTUnwrap($0) }
            XCTAssertEqual(Set(next).count, cycle,
                           "cycle \(c) did not cover the chord — a shuffle must be a permutation")
            if next != first { sawADifferentCycle = true }
        }
        XCTAssertTrue(sawADifferentCycle,
                      "`.random` produced the same permutation for twelve consecutive cycles — "
                      + "it is keyed on the seed alone rather than on (seed, cycle)")
    }

    // MARK: - 7. Negative positions

    /// A caller resolving a cell from a transport tick can legitimately ask for a negative
    /// position (pre-roll, a scrub before zero). Swift's `%` truncates toward zero, so the naive
    /// index crashes; "fixed" with `abs` it silently MIRRORS the walk. Both wrong versions look
    /// right, so the correct behaviour is pinned: −1 is the LAST position of the previous cycle.
    func testANegativePositionWrapsByFlooringRatherThanCrashingOrMirroring() throws {
        // ⚠️ `.random` IS EXCLUDED FROM THE EQUALITY, and not as a convenience: for the five
        // shapes, position −1 and position `length−1` are the same point of the same repeating
        // figure. `.random` re-draws per cycle, so −1 belongs to cycle −1 and legitimately holds
        // a different tone than the last position of cycle 0. Asserting equality there would have
        // been a test demanding the feature be broken — it is covered by the coverage assertion
        // further down instead. (My first draft did assert it, and would have gone red for the
        // correct implementation.)
        for order in ArpFigure.Order.allCases where order != .random {
            for octaves in 1...ArpFigure.maxOctaves {
                let length = order == .upDown || order == .downUp
                    ? Swift.max(1, 2 * triad.count * octaves - 2)
                    : triad.count * octaves
                let atMinusOne = try XCTUnwrap(
                    ArpFigure.step(atIndex: -1, chordDegrees: triad, octaves: octaves,
                                   order: order, seed: 3))
                let atLast = try XCTUnwrap(
                    ArpFigure.step(atIndex: length - 1, chordDegrees: triad, octaves: octaves,
                                   order: order, seed: 3))
                XCTAssertEqual(atMinusOne, atLast,
                               "\(order) × \(octaves): position −1 is not the last position of "
                               + "the previous cycle")
            }
        }

        // `.random`'s floor property, stated correctly: the cycle BEFORE zero is a full cycle,
        // so indices −cycle…−1 must still cover the chord exactly once. That is what proves the
        // position wrapped by flooring rather than mirroring; a mirrored index would revisit.
        for octaves in 1...ArpFigure.maxOctaves {
            let cycle = triad.count * octaves
            let previous = try (-cycle...(-1)).map {
                try XCTUnwrap(ArpFigure.step(atIndex: $0, chordDegrees: triad, octaves: octaves,
                                             order: .random, seed: 3))
            }
            XCTAssertEqual(Set(previous).count, cycle,
                           "`.random` × \(octaves) octaves: the cycle before zero covered "
                           + "\(Set(previous).count) of \(cycle) positions — position and cycle "
                           + "are not both flooring, so they disagree across zero")
        }
        // And the extremes do not trap — `-Int.min` overflows, which is why `floorMod` uses `%`
        // before adjusting rather than negating.
        for extreme in [Int.min, Int.max, Int.min + 1] {
            for order in ArpFigure.Order.allCases {
                XCTAssertNotNil(ArpFigure.step(atIndex: extreme, chordDegrees: triad,
                                               octaves: 2, order: order, seed: 3),
                                "\(order) returned nil at index \(extreme) on a real chord")
            }
        }
    }

    // MARK: - Sanitising the chord

    /// A duplicated tone must collapse, and not for tidiness: kept, it would sound twice per
    /// cycle while the cycle length still counted it twice, so the walk would stutter on that one
    /// note and the coverage property above would be false.
    func testADuplicatedChordToneCollapsesInsteadOfStuttering() throws {
        let seq = try walk(.up, chord: [0, 0, 4, 4, 4], length: 2).map { try XCTUnwrap($0) }
        XCTAssertEqual(seq.map(\.degreeIndex), [0, 4])
        // …and the cycle really is 2 long now, not 5.
        let third = try XCTUnwrap(ArpFigure.step(atIndex: 2, chordDegrees: [0, 0, 4, 4, 4],
                                                octaves: 1, order: .up, seed: 1))
        XCTAssertEqual(third.degreeIndex, 0, "the cycle did not shorten with the duplicates")
    }

    /// `.asPlayed` keeps the voicing it was handed; the other orders sort. That is the whole
    /// point of having it — an inversion stays an inversion.
    func testAsPlayedKeepsTheVoicingWhileUpSortsIt() throws {
        let voiced = [4, 0, 2]                     // a chord handed over already inverted
        let asPlayed = try walk(.asPlayed, chord: voiced, length: 3).map { try XCTUnwrap($0) }
        XCTAssertEqual(asPlayed.map(\.degreeIndex), [4, 0, 2],
                       "`.asPlayed` sorted the chord — it is the one order that must not")
        let up = try walk(.up, chord: voiced, length: 3).map { try XCTUnwrap($0) }
        XCTAssertEqual(up.map(\.degreeIndex), [0, 2, 4], "`.up` did not sort the chord")
    }

    /// The voice cap is real and bounded: `.random` re-derives its permutation on every call, and
    /// the caller is a 60 Hz display link, so an unbounded chord from a decoded field would make
    /// each frame's work unbounded. Asserted as a cap on what SOUNDS, not on the input array.
    func testAnAbsurdlyLongChordIsCappedRatherThanWalkedForever() throws {
        let huge = Array(0..<500)
        let cycle = ArpFigure.maxVoices
        let seq = try walk(.up, chord: huge, length: cycle + 1).map { try XCTUnwrap($0) }
        XCTAssertEqual(Set(seq.prefix(cycle)).count, cycle)
        XCTAssertEqual(seq[cycle], seq[0],
                       "the walk did not wrap after \(cycle) tones — the chord cap is not applied")
        XCTAssertLessThanOrEqual(seq.map(\.degreeIndex).max() ?? 0, ArpFigure.maxVoices - 1)
    }

    // MARK: - The six orders are six different figures

    /// Anti-vacuity for the whole file, and the thing the founder actually asked for: the orders
    /// must not be flavours of one walk. Compared over two octaves, where a shape difference has
    /// room to show.
    ///
    /// ⛔ ON A VOICED CHORD, DELIBERATELY, and this is the correction that matters: with the plain
    /// ascending triad `[0, 2, 4]`, `.asPlayed` and `.up` produce the IDENTICAL walk — because on
    /// an already-ascending chord "as played" simply IS "up". That is correct behaviour, not a
    /// collision, so pinning distinctness on that input would have been a test demanding a
    /// difference that should not exist. My first draft did exactly that and would have gone red.
    /// `[4, 0, 2]` is an inversion, which is the input where the six orders are six figures.
    func testTheSixOrdersAreAudiblyDistinctWalks() throws {
        let voiced = [4, 0, 2]
        var figures: [ArpFigure.Order: [ArpFigure.Step]] = [:]
        for order in ArpFigure.Order.allCases {
            figures[order] = try walk(order, chord: voiced, octaves: 2, length: 12, seed: 9)
                .map { try XCTUnwrap($0) }
        }
        for a in ArpFigure.Order.allCases {
            for b in ArpFigure.Order.allCases where a != b {
                XCTAssertNotEqual(figures[a], figures[b],
                                  "\(a) and \(b) produce the identical walk — two menu entries "
                                  + "for one figure is the `more options that sound the same` "
                                  + "failure this project has already hit twice (#81, #125)")
            }
        }
    }
}
