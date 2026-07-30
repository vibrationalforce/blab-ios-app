// ArpFigureSurfaceTests.swift
// Echoel — the arp's projection onto the play surface, in the BLOCKING bundle.
//
// #220 S2. `ArpFigure.step(atIndex:…)` answers "which chord tone, in which octave"; this half
// answers "where on the surface do I have to touch for that to sound". It is the slice the plan
// marked MEDIUM risk, and the reason is worth stating before the assertions: an off-by-one here
// is not a wrong number, it is a WRONG NOTE — and a wrong note that is still in the key, so it
// sounds like a questionable arp rather than like a bug.
//
// ⚠️ WHY THESE TESTS GO THROUGH THE REAL `TouchPitchMap` AND `MusicalKey` INSTEAD OF RE-DERIVING
// THE EXPECTED CELL. `surfacePoint` exists only to feed `TouchPitchMap.pitch`, which FLOORS both
// coordinates. A test that recomputed `Int(x * n)` with the same arithmetic as the implementation
// would pass for any consistent pair of bugs — including the one this projection was written to
// avoid (a boundary value that lands one degree low half the time). So the composition is
// asserted end to end, and the expected pitch is stated in `MusicalKey`'s OWN vocabulary
// (`key.degree(index, octave:)`, which wraps octaves itself) rather than in this file's fold.
//
// ⚠️ ONE PRECONDITION IS ASSERTED RATHER THAN ASSUMED: the equality above only holds while
// `TouchPitchMap.octaveBands` is a run of CONSECUTIVE octaves, because "one band up" is then
// exactly "twelve semitones up". `testTheSurfacesBandsAreConsecutiveOctaves` pins that; if a
// future band layout skips an octave, that test fails first and explains why the others would.

import Foundation
import XCTest
@testable import Echoelmusic

final class ArpFigureSurfaceTests: XCTestCase {

    private let triad = [0, 2, 4]
    private var bandCount: Int { TouchPitchMap.octaveBands.count }

    /// The pitch the shipped mapping produces for a walk position, i.e. the composition that
    /// actually sounds: `Step` → surface point → the same `pitch` a finger goes through.
    private func pitch(_ step: ArpFigure.Step, key: MusicalKey, band: Int = 0) -> Int {
        let p = ArpFigure.surfacePoint(step,
                                       degreesPerOctave: key.degreesPerOctave,
                                       bandCount: bandCount,
                                       band: band)
        return TouchPitchMap.pitch(normX: p.x, normY: p.y, key: key)
    }

    // MARK: - The precondition the rest of the file leans on

    func testTheSurfacesBandsAreConsecutiveOctaves() {
        let bands = TouchPitchMap.octaveBands
        XCTAssertFalse(bands.isEmpty, "a surface with no octave band cannot be played at all")
        for (lower, upper) in zip(bands, bands.dropFirst()) {
            XCTAssertEqual(upper, lower + 1,
                           "bands \(bands) skip an octave — every 'one band up == one octave up' "
                           + "claim in this file, and in ArpFigure.surfacePoint's doc, is void")
        }
    }

    // MARK: - The cell centre

    /// The defect this function was written to prevent, stated as a test: the consumer FLOORS
    /// `x * degreesPerOctave`, so a coordinate on a cell boundary is one ulp away from resolving
    /// to the neighbouring degree. Every returned x must sit half a cell clear of both edges.
    func testEveryDegreeLandsInTheMiddleOfItsCellRatherThanOnAnEdge() {
        for degrees in 1...12 {
            for degree in 0..<degrees {
                let p = ArpFigure.surfacePoint(.init(degreeIndex: degree, octaveOffset: 0),
                                               degreesPerOctave: degrees,
                                               bandCount: bandCount, band: 0)
                XCTAssertTrue(p.x >= 0 && p.x < 1, "x \(p.x) left the surface")
                // The floor the consumer performs, on the value it is actually handed.
                XCTAssertEqual(Int(p.x * Double(degrees)), degree,
                               "degree \(degree) of \(degrees) resolved to the wrong cell")
                // And clear of the boundary by margin, not by luck: the distance to the nearer
                // edge must be a full half-cell, minus room for representation error.
                let inCell = p.x * Double(degrees) - Double(degree)
                XCTAssertEqual(inCell, 0.5, accuracy: 1e-9,
                               "degree \(degree) of \(degrees) is off-centre in its cell")
            }
        }
    }

    /// Same argument for the vertical axis: `pitch` floors `y * bandCount` too.
    func testEveryBandLandsInTheMiddleOfItsRowRatherThanOnAnEdge() {
        for band in 0..<bandCount {
            let p = ArpFigure.surfacePoint(.init(degreeIndex: 0, octaveOffset: 0),
                                           degreesPerOctave: 7, bandCount: bandCount, band: band)
            XCTAssertTrue((0...1).contains(p.y), "y \(p.y) left the surface")
            XCTAssertEqual(Int(p.y * Double(bandCount)), band, "band \(band) resolved wrong")
        }
    }

    // MARK: - The lead property: every walk position is a legal note in every key

    /// The sweep the plan named as this slice's gate: every scale the app offers × every root ×
    /// every order × every octave span. A generated position that is out of MIDI range or out of
    /// key would be audible immediately and is exactly what a fold error produces.
    func testEveryWalkPositionBecomesALegalPitchInEveryKey() {
        var checked = 0
        for root in 0..<12 {
            for scale in Scale.allCases {
                let key = MusicalKey(root: root, scale: scale)
                // Hoisted out of the inner loops: `MusicalKey.contains` rebuilds `pitchClasses`
                // — a fresh array — on every call, and this is the heaviest test in the blocking
                // bundle. Same predicate, one allocation per key instead of 172,800.
                let classes = Set(key.pitchClasses)
                for order in ArpFigure.Order.allCases {
                    for octaves in 1...ArpFigure.maxOctaves {
                        // 16 = the LONGEST cycle any combination here has: `.upDown` over three
                        // tones × three octaves is 2·9 − 2. A smaller number would leave the
                        // turnaround half of the longest walk unswept, and that is exactly the
                        // position an off-by-one hides in.
                        for index in 0..<16 {
                            guard let step = ArpFigure.step(atIndex: index, chordDegrees: triad,
                                                            octaves: octaves, order: order,
                                                            seed: 11) else {
                                return XCTFail("the triad is not an empty chord")
                            }
                            let p = pitch(step, key: key)
                            XCTAssertTrue((0...127).contains(p),
                                          "root \(root) \(scale) \(order) oct \(octaves) → \(p)")
                            XCTAssertTrue(classes.contains(((p % 12) + 12) % 12),
                                          "root \(root) \(scale) \(order) → \(p) is out of key")
                            checked += 1
                        }
                    }
                }
            }
        }
        // Non-vacuity: without this the whole sweep could pass by never entering the body — the
        // failure mode this bundle has already been bitten by twice.
        XCTAssertEqual(checked,
                       12 * Scale.allCases.count * ArpFigure.Order.allCases.count
                       * ArpFigure.maxOctaves * 16)
    }

    /// And the pitch must be the one the KEY itself would name for that degree — stated through
    /// `MusicalKey.degree`, which does its own octave wrapping, so this is an independent
    /// formulation rather than a re-run of the implementation's arithmetic.
    ///
    /// The chord deliberately includes a degree PAST THE OCTAVE (degree 7, which in a seven-note
    /// scale is the octave itself — the eighth degree, not a ninth) so the fold is covered: it
    /// must become "the root, one octave up", not a position off the right edge of the surface.
    func testTheProjectedPitchIsTheOneTheKeyItselfWouldName() {
        let chord = [0, 2, 4, 7]
        var checked = 0
        for root in 0..<12 {
            for scale in Scale.allCases {
                let key = MusicalKey(root: root, scale: scale)
                let n = key.degreesPerOctave
                for order in ArpFigure.Order.allCases {
                    for index in 0..<12 {
                        guard let step = ArpFigure.step(atIndex: index, chordDegrees: chord,
                                                        octaves: 1, order: order, seed: 5) else {
                            return XCTFail("a four-tone chord is not empty")
                        }
                        // Octaves = 1 and band 0, so `octaveOffset` is 0 and the only lift comes
                        // from a degree past the octave. That lift is ASSERTED to stay inside the
                        // surface rather than guarded around: the smallest `degreesPerOctave` in
                        // `Scale.allCases` is 5 and the chord's highest degree is 7, so the carry
                        // can only ever be 1 — if a future scale with fewer degrees broke that,
                        // this equality would silently stop being exact, and an assertion says so
                        // where a `continue` would just quietly shrink the sweep.
                        let lift = step.degreeIndex / n
                        XCTAssertLessThan(lift, bandCount,
                                          "\(scale) has \(n) degrees — the chord's carry now "
                                          + "reaches the band ceiling and the equality below is "
                                          + "no longer exact")
                        let expected = key.degree(step.degreeIndex,
                                                  octave: TouchPitchMap.octaveBands[0])
                        XCTAssertEqual(pitch(step, key: key), expected,
                                       "root \(root) \(scale) \(order) degree \(step.degreeIndex)")
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(checked,
                       12 * Scale.allCases.count * ArpFigure.Order.allCases.count * 12,
                       "the sweep skipped iterations")
    }

    /// ⛔ THE COMBINATION NEITHER SWEEP ABOVE REACHES, and it is where a reviewer found the real
    /// defect in this slice: a non-zero base `band` TOGETHER with a chord degree past the octave.
    /// The default triad's carry is 0, so `carry` and `band` were only ever exercised separately.
    ///
    /// What this pins is the DOCUMENTED ceiling, stated as the audible consequence: degree 7 (the
    /// octave) cannot rise above the top band, so it lands on the same pitch as the root and the
    /// cycle plays the root twice. That is the honest behaviour of a three-register surface — and the
    /// reason `surfacePoint`'s doc had to grow the carry term into the caller's condition, because
    /// the first version of that condition said this configuration was safe.
    func testABaseBandPlusACarryHitsTheCeilingTheDocNowNames() {
        let key = MusicalKey(root: 0, scale: .major)             // 7 degrees
        let root = ArpFigure.Step(degreeIndex: 0, octaveOffset: 0)
        // Degree 7 is the OCTAVE, not the ninth — the first degree past a seven-note scale, i.e.
        // the eighth degree. (A ninth would be degree 8. Naming it wrong is how the +12 below
        // becomes a +14 in someone's head.)
        let octaveUp = ArpFigure.Step(degreeIndex: 7, octaveOffset: 0)
        // band 2 of 3 satisfies the OLD condition (band + octaves - 1 = 2 < 3) and still hits
        // the ceiling, because degree 7 carries one band on its own.
        XCTAssertEqual(pitch(octaveUp, key: key, band: 2), pitch(root, key: key, band: 2),
                       "degree 7 must saturate onto the top band, i.e. collide with the root")
        // One band lower, both are audible and exactly an octave apart: the same configuration is
        // correct as soon as the carry fits, which is what the corrected condition expresses.
        XCTAssertEqual(pitch(octaveUp, key: key, band: 1) - pitch(root, key: key, band: 1), 12)
    }

    /// And across every key: a non-zero band plus a carry may saturate, but it must never leave
    /// the key or the MIDI range — the two things a fold-direction error would break.
    func testANonZeroBandCombinedWithACarryStaysLegal() {
        var checked = 0
        for root in 0..<12 {
            for scale in Scale.allCases {
                let key = MusicalKey(root: root, scale: scale)
                let classes = Set(key.pitchClasses)              // hoisted: `contains` allocates
                for band in 0..<bandCount {
                    for degree in [0, 2, 4, 7, 11, 14] {
                        for offset in -1...2 {
                            let p = pitch(.init(degreeIndex: degree, octaveOffset: offset),
                                          key: key, band: band)
                            XCTAssertTrue((0...127).contains(p),
                                          "\(scale) band \(band) degree \(degree) → \(p)")
                            XCTAssertTrue(classes.contains(((p % 12) + 12) % 12),
                                          "\(scale) band \(band) degree \(degree) → \(p) "
                                          + "is out of key")
                            checked += 1
                        }
                    }
                }
            }
        }
        XCTAssertEqual(checked, 12 * Scale.allCases.count * bandCount * 6 * 4)
    }

    // MARK: - The shapes have to survive the projection

    /// An ascending walk must ASCEND after projection, and a descending one descend. This is the
    /// property a fold error breaks while every note stays in key and in range — i.e. the one
    /// thing the sweep above cannot see.
    func testAnAscendingWalkStillAscendsAfterProjection() {
        let key = MusicalKey(root: 0, scale: .major)
        let cycle = triad.count * ArpFigure.maxOctaves          // 3 tones × 3 octaves = 9
        func pitches(_ order: ArpFigure.Order) -> [Int] {
            (0..<cycle).compactMap {
                ArpFigure.step(atIndex: $0, chordDegrees: triad,
                               octaves: ArpFigure.maxOctaves, order: order, seed: 3)
            }.map { pitch($0, key: key) }
        }
        let up = pitches(.up)
        XCTAssertEqual(up.count, cycle)
        XCTAssertEqual(up, up.sorted(), "the ascending walk did not ascend: \(up)")
        XCTAssertEqual(Set(up).count, cycle, "two positions of one cycle collapsed onto one pitch")
        // `Array(...)` spells the type out. (An earlier comment here claimed `up.reversed()`
        // "does not compile" — that was an unverified guess, and wrong: `Sequence.reversed()`
        // returns `[Element]` and the solver picks it when the other argument pins `[Int]`.
        // `ArpFigureTests.swift:46` already relies on that. Keeping the explicit form, dropping
        // the false claim about it.)
        XCTAssertEqual(pitches(.down), Array(up.reversed()),
                       "down is not the mirror after projection")
    }

    /// Distinct degrees must never collapse onto one pitch — the cell width has to be the scale's
    /// own, not a fixed twelve. A pentatonic scale packs five degrees across the same surface.
    func testDistinctDegreesNeverCollapseOntoOnePitch() {
        for scale in Scale.allCases {
            let key = MusicalKey(root: 7, scale: scale)
            let n = key.degreesPerOctave
            let pitches = (0..<n).map {
                pitch(.init(degreeIndex: $0, octaveOffset: 0), key: key)
            }
            XCTAssertEqual(Set(pitches).count, n,
                           "\(scale): \(n) degrees produced \(Set(pitches).count) pitches")
        }
    }

    // MARK: - The documented ceiling

    /// The surface spans `bandCount` registers and cannot express a higher one — the consumer
    /// clamps the band it derives. So a walk that reaches past the top plays the top octave
    /// again. That is documented behaviour, and it is pinned here for the reason the doc gives:
    /// the alternative failure — folding DOWN an octave — sounds like a mistake rather than like
    /// a range limit, and a future edit could introduce it without any other test noticing.
    func testTheTopBandSaturatesInsteadOfFoldingDown() {
        let key = MusicalKey(root: 0, scale: .major)
        let top = bandCount - 1
        let atTop = ArpFigure.surfacePoint(.init(degreeIndex: 2, octaveOffset: 0),
                                          degreesPerOctave: 7, bandCount: bandCount, band: top)
        let pastTop = ArpFigure.surfacePoint(.init(degreeIndex: 2, octaveOffset: 1),
                                            degreesPerOctave: 7, bandCount: bandCount, band: top)
        XCTAssertEqual(pastTop.y, atTop.y, accuracy: 1e-12, "the ceiling moved")
        XCTAssertEqual(pitch(.init(degreeIndex: 2, octaveOffset: 1), key: key, band: top),
                       pitch(.init(degreeIndex: 2, octaveOffset: 0), key: key, band: top),
                       "a lift past the top band produced a different note — if it is LOWER, "
                       + "the projection folded instead of saturating")
    }

    /// The mirror at the bottom: a lift below band 0 saturates there too.
    func testTheBottomBandSaturatesAsWell() {
        let p = ArpFigure.surfacePoint(.init(degreeIndex: 0, octaveOffset: -4),
                                       degreesPerOctave: 7, bandCount: bandCount, band: 0)
        XCTAssertEqual(p.y, 0.5 / Double(bandCount), accuracy: 1e-12)
    }

    // MARK: - Folds and degenerate input

    func testADegreePastTheOctaveBecomesAnOctaveLiftNotAStepRight() {
        let root = ArpFigure.surfacePoint(.init(degreeIndex: 0, octaveOffset: 0),
                                         degreesPerOctave: 7, bandCount: bandCount, band: 0)
        let ninth = ArpFigure.surfacePoint(.init(degreeIndex: 7, octaveOffset: 0),
                                          degreesPerOctave: 7, bandCount: bandCount, band: 0)
        XCTAssertEqual(ninth.x, root.x, accuracy: 1e-12, "the ninth moved sideways")
        XCTAssertEqual(ninth.y, 1.5 / Double(bandCount), accuracy: 1e-12,
                       "the ninth did not move up one band")
    }

    func testANegativeDegreeFoldsDownwardsRatherThanOffTheLeftEdge() {
        // −1 in a seven-note scale is "the seventh, one octave down". With a +1 octaveOffset the
        // two cancel, so this must land on the top degree of the BASE band.
        let p = ArpFigure.surfacePoint(.init(degreeIndex: -1, octaveOffset: 1),
                                       degreesPerOctave: 7, bandCount: bandCount, band: 0)
        XCTAssertEqual(p.x, 6.5 / 7, accuracy: 1e-12)
        XCTAssertEqual(p.y, 0.5 / Double(bandCount), accuracy: 1e-12)
        // And the note agrees with the key's own reading of degree −1 lifted an octave.
        let key = MusicalKey(root: 3, scale: .minor)
        XCTAssertEqual(pitch(.init(degreeIndex: -1, octaveOffset: 1), key: key),
                       key.degree(-1 + key.degreesPerOctave,
                                  octave: TouchPitchMap.octaveBands[0]))
    }

    /// Decoded data reaches this function (S3 persists the chord), so the extremes are inputs,
    /// not impossibilities. `floorDiv(Int.max, 1)` is `Int.max`, and Swift's `+` TRAPS on
    /// overflow — a crash on the 60 Hz self-play path. Nothing here may leave the surface either.
    func testACorruptStepCannotOverflowOrLeaveTheSurface() {
        let extremes = [Int.max, Int.min, Int.max - 1, Int.min + 1, 0, -1, 1]
        for degree in extremes {
            for offset in extremes {
                let p = ArpFigure.surfacePoint(.init(degreeIndex: degree, octaveOffset: offset),
                                               degreesPerOctave: 7,
                                               bandCount: bandCount, band: 1)
                XCTAssertTrue(p.x >= 0 && p.x < 1, "x \(p.x) for (\(degree), \(offset))")
                XCTAssertTrue((0...1).contains(p.y), "y \(p.y) for (\(degree), \(offset))")
            }
        }
        // And the sign of the intent survives: an absurdly high ask saturates at the TOP, not —
        // as `&+` wrapping would have it — at the bottom.
        let high = ArpFigure.surfacePoint(.init(degreeIndex: .max, octaveOffset: .max),
                                          degreesPerOctave: 7, bandCount: bandCount, band: 0)
        XCTAssertEqual(high.y, (Double(bandCount) - 0.5) / Double(bandCount), accuracy: 1e-12)
        let low = ArpFigure.surfacePoint(.init(degreeIndex: .min, octaveOffset: .min),
                                         degreesPerOctave: 7, bandCount: bandCount, band: 0)
        XCTAssertEqual(low.y, 0.5 / Double(bandCount), accuracy: 1e-12)
    }

    func testSaturatingSumPinsInsteadOfTrappingOrWrapping() {
        XCTAssertEqual(ArpFigure.saturatingSum(3, 4), 7)
        XCTAssertEqual(ArpFigure.saturatingSum(.max, 1), .max)
        XCTAssertEqual(ArpFigure.saturatingSum(.max, .max), .max)
        XCTAssertEqual(ArpFigure.saturatingSum(.min, -1), .min)
        XCTAssertEqual(ArpFigure.saturatingSum(.min, .min), .min)
        XCTAssertEqual(ArpFigure.saturatingSum(.max, .min), -1)   // no overflow, exact
    }

    /// A scale with no notes, or a surface with no bands, is corruption rather than a request —
    /// but it must still return a point ON the surface instead of dividing by zero.
    func testADegenerateScaleOrSurfaceStillReturnsAPointOnTheSurface() {
        for degrees in [0, -3] {
            let p = ArpFigure.surfacePoint(.init(degreeIndex: 5, octaveOffset: 2),
                                           degreesPerOctave: degrees,
                                           bandCount: bandCount, band: 0)
            XCTAssertEqual(p.x, 0.5, accuracy: 1e-12, "degreesPerOctave \(degrees)")
            XCTAssertTrue((0...1).contains(p.y))
        }
        for bands in [0, -1] {
            let p = ArpFigure.surfacePoint(.init(degreeIndex: 1, octaveOffset: 1),
                                           degreesPerOctave: 7, bandCount: bands, band: 0)
            XCTAssertEqual(p.y, 0.5, accuracy: 1e-12, "bandCount \(bands)")
            XCTAssertTrue(p.x >= 0 && p.x < 1)
        }
    }

    // ⛔ NO empty-chord test here on purpose: `ArpFigureTests`
    // `testAnEmptyChordIsNilNotAnEmptyStep` already pins it in this same bundle, and a second
    // copy would grow the count of tests without growing what is actually checked. The nil path
    // never reaches `surfacePoint` — the caller cannot build a `Step` out of nothing.
}
