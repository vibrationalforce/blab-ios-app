// RoleRhythmTests.swift
// Echoel — a rhythm per sound role, in the BLOCKING bundle.
//
// #253 A1 (founder 2026-07-30: *"Alle Soundrubriken von Pads, Bass bis arp etc. brauchen noch
// verschiedene Rhythmus Regler … die interessante, treibende, hypnotische, dynamische etc.
// Rhythmus pattern machen"*).
//
// ⚠️ WHAT THESE TESTS ARE FOR, because a rhythm generator is easy to test uselessly: asserting
// that a velocity is between 0 and 1 proves nothing about whether the thing grooves. The two
// properties that matter here are
//
//   1. **The six characters are actually six.** If two of them produce the same bar, one of them
//      is a lie in a picker — the "more options that sound the same" failure this project has
//      already hit twice (#81, #125). Pinned pairwise over a whole bar.
//   2. **`evolve == 0` means bar-for-bar identical**, so "off" is off rather than "less". With one
//      deliberate exception that is asserted rather than excused: `hypnotic` ROTATES by bar as its
//      defining character, independent of `evolve` and of the seed.
//
// Everything else here is a guard against a failure this repo has already paid for: a note-on at
// velocity 0 (#205, #176), a trap on a decoded integer (`FieldAutoPlay.maxPeriodSteps`), a NaN
// walking into a clamp written in the wrong argument order (CLAUDE.md), and a lossy decode that
// throws a whole saved setting away (#163, #189).

import Foundation
import XCTest
@testable import Echoelmusic

final class RoleRhythmTests: XCTestCase {

    private let cells = 16

    private func params(_ character: RoleRhythm.Character,
                        density: Float = 1, gate: Float = 0.8, accent: Float = 0.5,
                        push: Float = 0, evolve: Float = 0) -> RoleRhythm.Params {
        RoleRhythm.Params(character: character, density: density, gate: gate,
                          accent: accent, push: push, evolve: evolve)
    }

    /// One bar as an array, `nil` where the cell is silent.
    private func bar(_ p: RoleRhythm.Params, bar barIndex: Int = 0,
                     seed: UInt64 = 9) -> [RoleRhythm.Hit?] {
        (0..<cells).map {
            RoleRhythm.hit(bar: barIndex, cell: $0, cellsPerBar: cells, params: p, seed: seed)
        }
    }

    private func firedCells(_ p: RoleRhythm.Params, bar barIndex: Int = 0,
                            seed: UInt64 = 9) -> Set<Int> {
        Set(bar(p, bar: barIndex, seed: seed).enumerated().compactMap { $1 == nil ? nil : $0 })
    }

    // MARK: - The six are six

    /// The load-bearing test of this slice. Same dials, six characters, one bar: every pair must
    /// differ somewhere. A character that cannot be told apart from its neighbour is a control
    /// that lies about what it does.
    func testTheSixCharactersAreSixDifferentRhythms() {
        // ⚠️ SWEPT ACROSS `accent`, and that is the whole strength of this test. Pinned at one
        // dial setting it passed on a velocity difference alone — so `hypnotic` and `flowing`,
        // which have near-flat accent curves, were free to collapse onto each other at `accent: 0`
        // (identical cells at bar 0, identical level, identical length, 0.05 of push between them)
        // while this test still went green. `accent: 0` is a documented legitimate setting, so it
        // has to be in the sweep.
        for accent in [Float(0), 0.5, 1] {
            for barIndex in [0, 1, 3] {
                let bars = RoleRhythm.Character.allCases.map {
                    bar(params($0, density: 0.5, accent: accent), bar: barIndex)
                }
                for i in bars.indices {
                    for j in bars.indices where j > i {
                        XCTAssertNotEqual(bars[i], bars[j],
                                          "\(RoleRhythm.Character.allCases[i]) and "
                                          + "\(RoleRhythm.Character.allCases[j]) produce the same "
                                          + "bar at accent \(accent), bar \(barIndex)")
                    }
                }
            }
        }
        // And not merely different by a hair: at least one of the four dimensions must differ in
        // a way a listener could name — which cells sound, or how loud/long/late they are.
        XCTAssertNotEqual(firedCells(params(.sparse, density: 0.5)),
                          firedCells(params(.driving, density: 0.5)))
        XCTAssertNotEqual(firedCells(params(.syncopated, density: 0.5)),
                          firedCells(params(.driving, density: 0.5)))
    }

    /// `driving` and `dynamic` deliberately fire the SAME cells; what tells them apart is the
    /// accent shape and the note length. Pinned so a later slice cannot quietly equalise the gate
    /// and leave two identical entries in a picker.
    func testDrivingAndDynamicShareCellsAndDifferInLengthAndAccent() {
        XCTAssertEqual(firedCells(params(.driving, density: 0.5)),
                       firedCells(params(.dynamic, density: 0.5)))
        let driving = bar(params(.driving, density: 1)).compactMap { $0 }
        let dynamic = bar(params(.dynamic, density: 1)).compactMap { $0 }
        XCTAssertFalse(driving.isEmpty)
        XCTAssertEqual(driving.count, dynamic.count)
        for (a, b) in zip(driving, dynamic) {
            XCTAssertLessThan(a.gateFraction, b.gateFraction, "driving is no longer the shorter one")
        }
        XCTAssertNotEqual(driving.map(\.velocity), dynamic.map(\.velocity))
    }

    // MARK: - Silence and the velocity-0 law

    func testDensityZeroIsSilenceEverywhere() {
        for character in RoleRhythm.Character.allCases {
            XCTAssertTrue(bar(params(character, density: 0)).allSatisfy { $0 == nil },
                          "\(character) played at density 0")
        }
    }

    /// ⛔ A HIT IS NEVER VELOCITY 0. An inaudible note-on still takes a voice, still counts
    /// against polyphony and still reads in a log as a played note — this app has spent two
    /// cycles chasing exactly that ghost. Silence must be `nil`.
    func testAHitIsNeverSilentlyInaudible() {
        var checked = 0
        for character in RoleRhythm.Character.allCases {
            for accent in [Float(0), 0.5, 1] {
                for density in [Float(0.1), 0.5, 1] {
                    for barIndex in 0..<4 {
                        let p = params(character, density: density, accent: accent, evolve: 0.7)
                        for hit in bar(p, bar: barIndex).compactMap({ $0 }) {
                            XCTAssertGreaterThan(hit.velocity, 0, "\(character) accent \(accent)")
                            XCTAssertLessThanOrEqual(hit.velocity, 1)
                            checked += 1
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 0, "no hit was produced at all")
    }

    func testGateAndPushStayInsideTheirDeclaredRanges() {
        var checked = 0
        for character in RoleRhythm.Character.allCases {
            for gate in [Float(0), 0.5, 1, 9] {
                for push in [Float(-9), -0.4, 0, 0.4, 9] {
                    let p = params(character, gate: gate, push: push, evolve: 0.5)
                    for hit in bar(p).compactMap({ $0 }) {
                        XCTAssertTrue((RoleRhythm.minGate...RoleRhythm.maxGate)
                                        .contains(hit.gateFraction),
                                      "\(character) gate \(gate) → \(hit.gateFraction)")
                        XCTAssertTrue((-RoleRhythm.maxPush...RoleRhythm.maxPush)
                                        .contains(hit.pushFraction),
                                      "\(character) push \(push) → \(hit.pushFraction)")
                        checked += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 0, "the sweep produced no hit at all — it proved nothing")
    }

    /// A note may fill its cell but never spill into the next one, and it may never sit half a
    /// cell away — at exactly 0.5 a late note and the next cell's early note collide into a flam.
    ///
    /// ⚠️ THIS NOW TESTS THE COMPOSITE PROPERTY ITS NAME PROMISES. The first version asserted
    /// three literals against three literals (`maxPush < 0.5`, `maxGate <= 1`, `minGate > 0`),
    /// which guards a future constant edit but says nothing about a NOTE — and the code violated
    /// the name on every `flowing` note, where gate scale 1.0 met an unconditional +0.05 push and
    /// ran 5 % into the next cell.
    func testANoteCanNeverReachTheNextCell() {
        XCTAssertLessThan(RoleRhythm.maxPush, 0.5)
        XCTAssertLessThanOrEqual(RoleRhythm.maxGate, 1)
        XCTAssertGreaterThan(RoleRhythm.minGate, 0)

        var checked = 0
        for character in RoleRhythm.Character.allCases {
            for gate in [Float(0.3), 0.8, 1, 9] {
                for push in [Float(-0.45), 0, 0.2, 0.45, 9] {
                    let p = params(character, gate: gate, push: push, evolve: 0.5)
                    for hit in bar(p).compactMap({ $0 }) {
                        let end = Swift.max(0, hit.pushFraction) + hit.gateFraction
                        XCTAssertLessThanOrEqual(end, 1 + 1e-6,
                                                 "\(character) gate \(gate) push \(push) ends at "
                                                 + "\(end) — inside the next cell")
                        checked += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }

    // MARK: - Evolve off means off

    /// `evolve == 0` must give bar-for-bar identical output — five of six characters. `hypnotic`
    /// is the exception BY DESIGN: its rotation is what makes a repeating figure hypnotic rather
    /// than merely repetitive, and it is not a variation dial.
    func testEvolveZeroRepeatsTheBarExactly() {
        for character in RoleRhythm.Character.allCases where character != .hypnotic {
            let first = bar(params(character, density: 0.6, evolve: 0), bar: 0)
            for barIndex in [1, 5, 40, -3] {
                XCTAssertEqual(bar(params(character, density: 0.6, evolve: 0), bar: barIndex),
                               first, "\(character) changed at bar \(barIndex) with evolve 0")
            }
        }
    }

    /// And with `evolve == 0` the seed cannot matter either — for ALL six, `hypnotic` included:
    /// its rotation is a function of the bar, not of a draw.
    func testEvolveZeroMakesTheSeedIrrelevant() {
        for character in RoleRhythm.Character.allCases {
            let a = bar(params(character, density: 0.6, evolve: 0), bar: 3, seed: 1)
            let b = bar(params(character, density: 0.6, evolve: 0), bar: 3, seed: 999_331)
            XCTAssertEqual(a, b, "\(character) consulted the seed with evolve 0")
        }
    }

    /// The character that `evolve` is FOR must actually change when it is turned up — otherwise
    /// the dial is decoration.
    func testEvolveChangesTheBarWhenTurnedUp() {
        let still = bar(params(.dynamic, density: 0.6, evolve: 0), bar: 2)
        let moving = bar(params(.dynamic, density: 0.6, evolve: 1), bar: 2)
        XCTAssertNotEqual(still, moving, "evolve 1 changed nothing on the dynamic character")
        // Two different bars of a moving pattern must differ from each other too, or "evolve"
        // would just be a one-off offset.
        XCTAssertNotEqual(bar(params(.dynamic, density: 0.6, evolve: 1), bar: 2),
                          bar(params(.dynamic, density: 0.6, evolve: 1), bar: 3))
    }

    /// ⛔ THE ANTI-LYING-DIAL TEST (#164, #227). `Character.usesEvolve` is what A7 reads to decide
    /// whether to draw the row at all, so it must describe the CODE and not the intention: for
    /// every character, turning `evolve` from 0 to 1 must change the output exactly when that
    /// property says it does. Without this, `evolve` was a full-range slider that did nothing on
    /// four of the six — and nothing would have gone red if it had been deleted from a fifth.
    func testEvolveChangesExactlyTheCharactersThatClaimToUseIt() {
        for character in RoleRhythm.Character.allCases {
            var differed = false
            for barIndex in 0..<8 {
                let still = bar(params(character, density: 0.6, evolve: 0), bar: barIndex)
                let moving = bar(params(character, density: 0.6, evolve: 1), bar: barIndex)
                if still != moving { differed = true }
            }
            XCTAssertEqual(differed, character.usesEvolve,
                           "\(character).usesEvolve is \(character.usesEvolve) but the output "
                           + (differed ? "changed" : "did not change") + " when evolve went to 1")
        }
    }

    /// ⛔ REGRESSION: `flowing`'s `evolve` must add or drop INDIVIDUAL notes, never invert the bar.
    ///
    /// The first version of `hit` folded only `(seed, bar)` into the draw stream, so every cell of
    /// a bar re-derived the identical stream and drew the identical first number — one coin toss
    /// per bar that flipped EVERY cell at once. At density 1 that produced a completely silent bar
    /// roughly every fifth one, on a character whose whole job is to sit under everything else.
    /// The only test that exercised it asserted nothing about counts, so an all-`nil` bar passed.
    func testFlowingBreathesPerNoteAndNeverInvertsTheWholeBar() {
        let p = params(.flowing, density: 1, evolve: 1)
        var sawAPartialBar = false
        for barIndex in 0..<24 {
            let count = firedCells(p, bar: barIndex).count
            XCTAssertGreaterThan(count, 0, "bar \(barIndex) went completely silent")
            if count < cells { sawAPartialBar = true }
        }
        XCTAssertTrue(sawAPartialBar,
                      "evolve 1 never dropped a single note — the per-cell draw is not reaching it")
    }

    // MARK: - Each character's defining property

    /// `driving` means the downbeat, always — even at a density that fires almost nothing else.
    func testDrivingAlwaysLandsOnTheDownbeat() {
        for density in [Float(0.01), 0.1, 0.5, 1] {
            let hit = RoleRhythm.hit(bar: 0, cell: 0, cellsPerBar: cells,
                                     params: params(.driving, density: density), seed: 9)
            XCTAssertNotNil(hit, "driving lost the downbeat at density \(density)")
        }
        // Dead straight and short: those two are what separate it from `dynamic`.
        let straight = bar(params(.driving)).compactMap { $0 }
        XCTAssertFalse(straight.isEmpty, "driving produced no hit — the loop below proved nothing")
        for hit in straight {
            XCTAssertEqual(hit.pushFraction, 0, accuracy: 1e-6)
            XCTAssertLessThanOrEqual(hit.gateFraction, 0.8 * 0.45 + 1e-6)
        }
    }

    /// `hypnotic` rotates by exactly one cell per bar — the same figure entering one cell later,
    /// not a different figure.
    func testHypnoticRotatesOneCellPerBar() {
        let p = params(.hypnotic, density: 0.5)
        let first = firedCells(p, bar: 0)
        let second = firedCells(p, bar: 1)
        XCTAssertEqual(second, Set(first.map { ($0 + 1) % cells }),
                       "bar 1 is not bar 0 shifted by one cell")
        XCTAssertEqual(first.count, second.count, "the rotation changed how many notes sound")
        // A full cycle returns home: that is what makes it a rotation rather than a drift.
        XCTAssertEqual(firedCells(p, bar: cells), first)
    }

    /// `sparse` only ever plays on the beats. That is the character; a sparse pattern that put a
    /// note between beats would just be a quiet one.
    func testSparseOnlyPlaysOnTheBeats() {
        let beat = cells / 4
        for density in [Float(0.2), 0.6, 1] {
            let fired = firedCells(params(.sparse, density: density))
            // ⚠️ THE NON-EMPTY ASSERTION IS THE POINT AT density 0.2. Without it this loop
            // iterated an EMPTY set and passed vacuously — hiding that `sparse` squared the
            // density against a 4-cell grid and rounded to zero notes for its whole bottom third.
            XCTAssertFalse(fired.isEmpty, "sparse went silent at density \(density)")
            for cell in fired {
                XCTAssertEqual(cell % beat, 0, "sparse played off the beat at cell \(cell)")
            }
        }
        // And it is genuinely sparser than the density asks for — the squared density is what
        // makes the low half of the dial wide instead of merely thinner.
        XCTAssertLessThan(firedCells(params(.sparse, density: 0.5)).count,
                          firedCells(params(.driving, density: 0.5)).count)
    }

    /// `syncopated` inverts the accent: the cells BETWEEN the beats are the loud ones, and they
    /// sit a little late. That inversion is the character far more than the placement is.
    func testSyncopatedAccentsAndDelaysTheOffBeats() {
        let beat = cells / 4
        let hits = bar(params(.syncopated, density: 1, accent: 1))
        var onBeat: [Float] = []
        var offBeat: [Float] = []
        for (cell, hit) in hits.enumerated() {
            guard let hit else { continue }
            if cell % beat == 0 {
                onBeat.append(hit.velocity)
                XCTAssertEqual(hit.pushFraction, 0, accuracy: 1e-6, "a beat was pushed late")
            } else {
                offBeat.append(hit.velocity)
                XCTAssertGreaterThan(hit.pushFraction, 0, "an off-beat was not laid back")
            }
        }
        XCTAssertFalse(onBeat.isEmpty)
        XCTAssertFalse(offBeat.isEmpty)
        let loudestBeat = onBeat.max() ?? 1
        let quietestOffBeat = offBeat.min() ?? 0
        XCTAssertGreaterThan(quietestOffBeat, loudestBeat,
                             "the off-beats are not the loud ones — that IS the character")
    }

    /// `flowing` leaves the player's gate alone (its scale is 1) and sits a hair behind the grid.
    func testFlowingKeepsTheGateAndSitsSlightlyLate() {
        let hits = bar(params(.flowing, gate: 0.6)).compactMap { $0 }
        XCTAssertFalse(hits.isEmpty, "flowing produced no hit — the loop below proved nothing")
        for hit in hits {
            XCTAssertEqual(hit.gateFraction, 0.6, accuracy: 1e-6)
            XCTAssertGreaterThan(hit.pushFraction, 0)
        }
    }

    /// `hypnotic` is long but NOT legato — that hair of air is the second dimension keeping it
    /// apart from `flowing`, which is the one character that fills its cell.
    func testHypnoticIsLongButLeavesAirWhereFlowingDoesNot() {
        let hypnotic = bar(params(.hypnotic, gate: 1)).compactMap { $0?.gateFraction }
        let flowing = bar(params(.flowing, gate: 1)).compactMap { $0?.gateFraction }
        XCTAssertFalse(hypnotic.isEmpty)
        XCTAssertFalse(flowing.isEmpty)
        for gate in hypnotic {
            XCTAssertGreaterThan(gate, 0.7, "hypnotic stopped being a long note")
            XCTAssertLessThan(gate, 1, "hypnotic filled the cell — nothing left to retrigger on")
        }
        // `flowing` yields only what its own +0.05 push takes, and no more.
        for gate in flowing { XCTAssertEqual(gate, 0.95, accuracy: 1e-6) }
    }

    /// At `accent == 0` every hit is exactly the same level — a machine, which is a legitimate
    /// setting and must therefore be exactly flat rather than nearly flat.
    func testAccentZeroIsPerfectlyFlat() {
        for character in RoleRhythm.Character.allCases {
            let levels = Set(bar(params(character, accent: 0)).compactMap { $0?.velocity })
            XCTAssertLessThanOrEqual(levels.count, 1,
                                     "\(character) still varied its level at accent 0: \(levels)")
        }
    }

    /// And turning the accent up must widen the gap rather than merely move it.
    func testAccentDepthWidensTheGapBetweenStrongAndWeak() {
        func spread(_ accent: Float) -> Float {
            let levels = bar(params(.driving, accent: accent)).compactMap { $0?.velocity }
            return (levels.max() ?? 0) - (levels.min() ?? 0)
        }
        XCTAssertEqual(spread(0), 0, accuracy: 1e-6)
        XCTAssertGreaterThan(spread(1), spread(0.5))
        XCTAssertGreaterThan(spread(0.5), 0)
    }

    // MARK: - Density behaves like a rate

    func testDensityOneFillsTheGridForEveryTravellingCharacter() {
        // `sparse` is excluded on purpose: "only on the beats" is its definition, so a full grid
        // would be the bug.
        for character in RoleRhythm.Character.allCases where character != .sparse {
            XCTAssertEqual(firedCells(params(character, density: 1)).count, cells,
                           "\(character) left gaps at density 1")
        }
        XCTAssertEqual(firedCells(params(.sparse, density: 1)).count, 4)
    }

    /// ⛔ THE CONVERSE OF "0 IS SILENCE": any density ABOVE 0 must play something, on every
    /// character. `round(density · cells)` reaches 0 for everything below `1/(2·cells)`, and
    /// `sparse` squares the density against a quarter-size grid, so it was silent for its whole
    /// bottom third — a dial reading "on" and producing nothing, which is the lying-control
    /// failure (#164, #227) in the one place a player would blame the synth instead of the dial.
    func testAnyDensityAboveZeroPlaysSomething() {
        for character in RoleRhythm.Character.allCases {
            for density in [Float(0.001), 0.01, 0.05, 0.1, 0.2, 0.3, 0.35, 0.5] {
                XCTAssertFalse(firedCells(params(character, density: density)).isEmpty,
                               "\(character) was silent at density \(density)")
            }
        }
    }

    /// More density must never mean fewer notes. Monotonicity is what makes it read as a RATE
    /// rather than as a random seed — the same reason the even Euclidean spread is used at all.
    func testDensityNeverLosesNotesAsItRises() {
        for character in RoleRhythm.Character.allCases {
            var previous = 0
            for step in 0...10 {
                let count = firedCells(params(character, density: Float(step) / 10)).count
                XCTAssertGreaterThanOrEqual(count, previous,
                                            "\(character) lost notes going up to "
                                            + "density \(Float(step) / 10)")
                previous = count
            }
        }
    }

    // MARK: - Corrupt and degenerate input

    /// A grid of zero, or one from a hand-edited file, must not divide by zero or trap.
    func testADegenerateOrAbsurdGridDoesNotCrash() {
        for cellsPerBar in [0, -5, 1, 3, Int.max, Int.min, RoleRhythm.maxCellsPerBar * 4] {
            for cell in [0, 1, -1, Int.max, Int.min] {
                let hit = RoleRhythm.hit(bar: 0, cell: cell, cellsPerBar: cellsPerBar,
                                         params: params(.driving), seed: 3)
                if let hit {
                    XCTAssertTrue((0...1).contains(hit.velocity))
                    XCTAssertTrue((RoleRhythm.minGate...RoleRhythm.maxGate)
                                    .contains(hit.gateFraction))
                }
            }
        }
    }

    /// An absurd bar index must not trap either — the seed fold uses wrapping arithmetic for
    /// exactly this reason.
    func testAnAbsurdBarIndexDoesNotTrap() {
        for barIndex in [Int.max, Int.min, Int.max - 1, -1_000_000] {
            let hit = RoleRhythm.hit(bar: barIndex, cell: 0, cellsPerBar: cells,
                                     params: params(.hypnotic, evolve: 1), seed: 3)
            if let hit { XCTAssertTrue((0...1).contains(hit.velocity)) }
        }
    }

    /// Non-finite dials come from decoded data and from bio mappings, so they are inputs rather
    /// than impossibilities. A NaN density SILENCES the role — it must never blast, and it must
    /// never produce a NaN velocity that would poison a voice downstream.
    func testNonFiniteDialsAreSanitizedRatherThanPropagated() {
        let nanDensity = RoleRhythm.Params(character: .driving, density: .nan, gate: 0.8,
                                           accent: 0.5, push: 0, evolve: 0.3)
        XCTAssertTrue(bar(nanDensity).allSatisfy { $0 == nil }, "a NaN density played something")

        let nanRest = RoleRhythm.Params(character: .driving, density: 1, gate: .nan,
                                        accent: .nan, push: .nan, evolve: .nan)
        let hits = bar(nanRest).compactMap { $0 }
        XCTAssertFalse(hits.isEmpty, "a NaN gate silenced a role that has a density")
        for hit in hits {
            XCTAssertTrue(hit.velocity.isFinite && hit.gateFraction.isFinite
                          && hit.pushFraction.isFinite, "a NaN reached the output")
            XCTAssertGreaterThan(hit.velocity, 0)
            XCTAssertGreaterThanOrEqual(hit.gateFraction, RoleRhythm.minGate)
            // ⛔ AND IT MUST LAND ON THE GRID, not at an end of the range. `push` is the one dial
            // whose neutral value is 0 rather than a boundary, and clamping a non-finite value the
            // way every other dial is clamped made every note MAXIMALLY EARLY — a groove-wide
            // timing shift from a single bad bio frame, with `isFinite` still true so a range
            // assertion would never have seen it.
            XCTAssertEqual(hit.pushFraction, 0, accuracy: 1e-6,
                           "a NaN push moved the note off the grid")
        }
    }

    /// ±infinity must clamp to the END of the range it points at — not both collapse to the
    /// bottom. The `isFinite`-branch version of `clampRange` sent `+infinity` to `lower`, which
    /// happened to look right for `-infinity` and for NaN and was wrong for the third case.
    func testPositiveInfinityClampsToTheTopAndNotTheBottom() {
        XCTAssertEqual(RoleRhythm.clampRange(.infinity, -1, 1), 1)
        XCTAssertEqual(RoleRhythm.clampRange(-.infinity, -1, 1), -1)
        XCTAssertEqual(RoleRhythm.clampRange(.nan, -1, 1), -1)
        // And through the live path: an infinite push is a request for "as late as allowed".
        let p = RoleRhythm.Params(character: .driving, density: 1, gate: 0.8,
                                  accent: 0.5, push: .infinity, evolve: 0)
        let hits = bar(p).compactMap { $0 }
        XCTAssertFalse(hits.isEmpty)
        for hit in hits {
            XCTAssertEqual(hit.pushFraction, RoleRhythm.maxPush, accuracy: 1e-6)
        }
    }

    func testTheHelperClampsAreNaNSafeInBothDirections() {
        XCTAssertEqual(RoleRhythm.clamp01(.nan), 0)
        XCTAssertEqual(RoleRhythm.clamp01(-5), 0)
        XCTAssertEqual(RoleRhythm.clamp01(5), 1)
        XCTAssertEqual(RoleRhythm.clampRange(.nan, -1, 1), -1)
        // (±infinity lives in `testPositiveInfinityClampsToTheTopAndNotTheBottom` — it is a
        // different property, and conflating the two is how the wrong one stayed green.)
        // Flooring modulo, both signs, and the value that breaks the `abs` version.
        XCTAssertEqual(RoleRhythm.floorMod(-1, 4), 3)
        XCTAssertEqual(RoleRhythm.floorMod(4, 4), 0)
        XCTAssertEqual(RoleRhythm.floorMod(Int.min, 4), 0)
        XCTAssertEqual(RoleRhythm.floorMod(5, 0), 0)
    }

    // MARK: - Persistence (law 9)

    func testAParamsSavedBeforeADialExistedLoadsWithItsDefault() throws {
        let json = #"{"character":"hypnotic","density":0.25}"#
        let p = try JSONDecoder().decode(RoleRhythm.Params.self, from: Data(json.utf8))
        let d = RoleRhythm.Params()
        XCTAssertEqual(p.character, .hypnotic)
        XCTAssertEqual(p.density, 0.25, accuracy: 1e-6)
        XCTAssertEqual(p.gate, d.gate, accuracy: 1e-6)
        XCTAssertEqual(p.accent, d.accent, accuracy: 1e-6)
        XCTAssertEqual(p.push, d.push, accuracy: 1e-6)
        XCTAssertEqual(p.evolve, d.evolve, accuracy: 1e-6)
    }

    /// A character a LATER build removes must fall back without discarding its neighbours —
    /// `decodeIfPresent` absorbs absence but not the `dataCorrupted` a raw-value enum throws.
    func testAnUnknownCharacterFallsBackWithoutLosingTheOtherDials() throws {
        let json = #"{"character":"stomping","density":0.9,"gate":0.2,"accent":0.7}"#
        let p = try JSONDecoder().decode(RoleRhythm.Params.self, from: Data(json.utf8))
        XCTAssertEqual(p.character, RoleRhythm.Params().character)
        XCTAssertEqual(p.density, 0.9, accuracy: 1e-6)
        XCTAssertEqual(p.gate, 0.2, accuracy: 1e-6)
        XCTAssertEqual(p.accent, 0.7, accuracy: 1e-6)
    }

    func testParamsSurviveASaveAndLoad() throws {
        let original = RoleRhythm.Params(character: .syncopated, density: 0.35, gate: 0.45,
                                        accent: 0.85, push: -0.2, evolve: 0.6)
        let back = try JSONDecoder().decode(RoleRhythm.Params.self,
                                           from: JSONEncoder().encode(original))
        XCTAssertEqual(back, original)
        XCTAssertEqual(back.schemaVersion, RoleRhythm.Params.currentSchemaVersion)
    }
}
