// FieldAutoPlayPushTests.swift
// Echoel — #253 A2b: the rhythm's timing offset finally reaches a note, in the BLOCKING bundle.
//
// `RoleRhythm` has computed `pushFraction` since A1 and BOTH consumers threw it away. The arp's reason
// is that handing a pushed tick to `TouchQuantizer` cannot delay anything: `plan` returns `.play` at
// `offset == 0` — every generated note — and `.play` sounds immediately whatever tick it carries. A2b
// gives the generated onset its OWN scheduled delay instead. (The composer's reason is PLAYBACK
// granularity, not its data model — `Note.startTick` carries 14 ticks fine; see `BioComposer`'s own
// note. The first version of this header said "`Note.startStep` is a whole 16th" and that a pushed
// tick would flam; both were wrong, and both are corrected at their real sites.)
//
// ⚠️ WHAT IS WORTH PINNING HERE IS NOT "the number is in range". Three properties are:
//
//  1. **The five travelling motions must be untouched.** This slice adds a field to `Touch` and a
//     delay to the driver. The cheap proof that nothing shifted is that those motions emit `nil`
//     and `nil` folds to a delay of exactly 0 — asserted over the whole `Motion` set, not argued.
//  2. **A pushed note must stay inside its own cell.** `RoleRhythm.hit` already discounts the gate
//     by the push (`headroom = 1 - push`), so delay + length ≤ one cell. On a device an inversion
//     would only show up as an arp that ties into itself.
//     ⚠️ DRIVEN AT `gate: 1` FOR A MEASURED REASON, and the first version at the default 0.8 could
//     NOT fail: the largest `gateScale` is 1.0, so the product was at most 0.8 while `headroom` was
//     at worst 0.95 — the cap never bound, and flipping `1 - push` to `1 + push` left ~19 ms of
//     slack. At `gate: 1` `flowing` sits at exactly 0.95 + 0.05 and the inversion goes red.
//     The BROADER guard is `RoleRhythmTests.testANoteCanNeverReachTheNextCell`, which sweeps
//     gate × push at the `Hit` level. This one adds only the arp's own path — do not delete that
//     one believing this replaces it.
//  3. **Only two of the six characters may be late.** `pushBias` is 0 for `driving`, `hypnotic`,
//     `dynamic` and `sparse` — `driving` deliberately dead straight. UI copy is written off this
//     fact (the A7 review had to strike timing words out of two blurbs), so it is pinned here
//     rather than left to a reader of `pushBias`.
//
// Everything under test is PURE, and the honest limit is ACCESS CONTROL, not UIKit: this bundle IS
// an iOS unit-test target with a `TEST_HOST`, but `autoPlayTick()` is `fileprivate` and
// `cancelGeneratedPending`/`soundGenerated` are `private`. So cancel-on-stop, cancel-on-touch,
// replace-cancel and the consumer's 2 ms floor have NO coverage here — that is the risky half, and
// naming UIKit as the obstacle would have made it sound impossible rather than merely unexposed
// (`FieldAutoPlayDriverTests` states the same limit for the driver). The consumer stays deliberately
// thin for that reason: it reads `pushDelaySeconds` and stores one `Task` in the map it already had.

import Foundation
import XCTest
@testable import Echoelmusic

final class FieldAutoPlayPushTests: XCTestCase {

    /// 1/16 at 120 BPM — the shipped default grid, so the numbers below are the ones a player hears.
    private let cellSeconds = 0.125

    private func arpParams(character: RoleRhythm.Character,
                           density: Float = 1, period: Int = 8,
                           gate: Float = 0.8) -> FieldAutoPlay.Params {
        FieldAutoPlay.Params(motion: .arp, density: density, span: 0.6, centre: 0.5,
                             band: 0.5, bandDrift: 0, voices: 1, periodSteps: period,
                             arpChordDegrees: [0, 2, 4],
                             arpRhythm: RoleRhythm.Params(character: character, gate: gate,
                                                          evolve: 0))
    }

    // MARK: - The pure fold

    func testNoOpinionMeansOnTheGrid() {
        XCTAssertEqual(FieldAutoPlay.pushDelaySeconds(nil, cellSeconds: cellSeconds), 0,
                       "nil is what the five travelling motions pass; it must mean the grid, not a value")
    }

    func testANonFiniteOrNegativePushIsOnTheGrid() {
        let bads: [Float] = [.nan, .infinity, -.infinity, -0.2, -0.45, 0]
        for bad in bads {
            XCTAssertEqual(FieldAutoPlay.pushDelaySeconds(bad, cellSeconds: cellSeconds), 0,
                           "\(bad) must fold to the grid — a generated onset has no earlier moment to be early against")
        }
    }

    func testAStoppedOrCorruptClockIsOnTheGrid() {
        for bad in [0.0, -0.125, Double.nan, Double.infinity] {
            XCTAssertEqual(FieldAutoPlay.pushDelaySeconds(0.12, cellSeconds: bad), 0,
                           "cellSeconds \(bad) leaves nothing for a fraction to be a fraction OF")
        }
    }

    func testAPushIsThatFractionOfTheCell() {
        XCTAssertEqual(FieldAutoPlay.pushDelaySeconds(0.12, cellSeconds: cellSeconds),
                       0.12 * cellSeconds, accuracy: 1e-6,
                       "syncopated's off-beat pull is 15 ms at the default grid")
        XCTAssertEqual(FieldAutoPlay.pushDelaySeconds(0.05, cellSeconds: cellSeconds),
                       0.05 * cellSeconds, accuracy: 1e-6)
    }

    func testAnAbsurdPushIsCappedBelowOneCell() {
        // A public field on a public struct: a bio mapping or a future UI can hand over anything,
        // and the one thing that must never happen is a note landing on the NEXT cell's onset.
        for wild: Float in [0.5, 1, 8, Float.greatestFiniteMagnitude] {
            let d = FieldAutoPlay.pushDelaySeconds(wild, cellSeconds: cellSeconds)
            XCTAssertLessThan(d, cellSeconds,
                              "a push of \(wild) must not reach the next cell")
            XCTAssertEqual(d, Double(FieldAutoPlay.maxPushFraction) * cellSeconds, accuracy: 1e-6)
        }
    }

    /// ⚠️ A MIRROR GUARD, and weak by construction: `maxPushFraction` is DECLARED as
    /// `{ RoleRhythm.maxPush }`, so this can only fail if someone replaces the mirror with a literal
    /// in the same edit. Kept because that is exactly the edit worth catching — a generator that may
    /// ask for 0.45 against a consumer that honours less is a silently truncated groove — but it
    /// carries no information about the current code and must not be read as coverage.
    func testTheCeilingIsTheRhythmsOwnCeilingAndNotASecondNumber() {
        XCTAssertEqual(FieldAutoPlay.maxPushFraction, RoleRhythm.maxPush)
    }

    /// The consumer discards anything under its 2 ms jitter floor, and at the grid extremes that is a
    /// REAL push being dropped rather than a rounding artefact: `flowing`'s 0.05 needs a 40 ms cell,
    /// which a 1/16-triplet grid (80 ticks) falls below above ~250 BPM. Pinned from the pure side
    /// because the consumer's own guard has no test surface here (see the file header).
    func testAtTheFastestGridTheSmallestPushFallsUnderTheConsumersJitterFloor() {
        let secondsPerTick = 60.0 / (300.0 * 480.0)          // Transport's BPM ceiling
        let tripletCell = 80.0 * secondsPerTick              // 1/16-triplet = 80 ticks ≈ 33 ms
        XCTAssertLessThan(FieldAutoPlay.pushDelaySeconds(0.05, cellSeconds: tripletCell), 0.002,
                          "flowing's push is sub-millisecond here — the consumer is right to drop it")
        // …and at the shipped default grid the same push is comfortably ABOVE the floor, so the
        // dropping is an extreme and not the normal case.
        XCTAssertGreaterThan(FieldAutoPlay.pushDelaySeconds(0.05, cellSeconds: cellSeconds), 0.002)
    }

    // MARK: - What the arp actually carries

    func testTheArpCarriesTheCharactersOwnLateness() {
        let syncopated = arpParams(character: .syncopated)
        var sawLate = false, sawStraight = false
        for cell in 0..<8 {
            guard let t = FieldAutoPlay.touches(atStep: cell, params: syncopated, seed: 7,
                                                degreesPerOctave: 7,
                                                bandCount: TouchPitchMap.octaveBands.count).first,
                  let push = t.pushFraction else { continue }
            // beat = cells/4 = 2, so odd cells are the off-beats that get +0.12.
            if cell % 2 == 0 { XCTAssertEqual(push, 0, accuracy: 1e-6); sawStraight = true } else {
                XCTAssertEqual(push, 0.12, accuracy: 1e-6); sawLate = true
            }
        }
        XCTAssertTrue(sawLate && sawStraight,
                      "syncopated's whole character is the CONTRAST between on- and off-beat placement")
    }

    func testOnlyTwoCharactersAreEverLate() {
        // Pinned because UI copy is written off it: a timing word in any of the other four would be
        // the same lying-caption the A7 review already had to strike out.
        let expectedLate: Set<RoleRhythm.Character> = [.syncopated, .flowing]
        for character in RoleRhythm.Character.allCases {
            let params = arpParams(character: character)
            // ⚠️ `compactMap`, NOT `.first?.pushFraction ?? 0`. Coalescing made a RESTING cell
            // indistinguishable from a straight one, and that is not hypothetical: `sparse` fires only
            // on the beats, so 4 of these 8 cells produce no touch at all and used to contribute a
            // silent 0. A future `pushBias` that biased `sparse` off the beat would have kept this
            // green while breaking the caption law it exists to protect.
            let pushes: [Float] = (0..<8).compactMap {
                FieldAutoPlay.touches(atStep: $0, params: params, seed: 3, degreesPerOctave: 7,
                                      bandCount: TouchPitchMap.octaveBands.count).first?.pushFraction
            }
            XCTAssertFalse(pushes.isEmpty, "\(character) sounded no cell at all — nothing was measured")
            let maxPush = pushes.reduce(0) { Swift.max($0, $1) }
            if expectedLate.contains(character) {
                XCTAssertGreaterThan(maxPush, 0, "\(character) is documented as laid back")
            } else {
                XCTAssertEqual(maxPush, 0, accuracy: 1e-6,
                               "\(character) must be dead straight — that is the point of it")
            }
        }
    }

    func testAPushedNoteStillEndsInsideItsOwnCell() {
        // The property that makes the delay and the gate independent in the consumer: `RoleRhythm.hit`
        // has ALREADY taken the push out of the gate ceiling, so the consumer must not discount twice.
        for character in RoleRhythm.Character.allCases {
            let params = arpParams(character: character, gate: 1)   // see the header: 0.8 cannot fail
            for cell in 0..<16 {
                guard let t = FieldAutoPlay.touches(atStep: cell, params: params, seed: 11,
                                                    degreesPerOctave: 7,
                                                    bandCount: TouchPitchMap.octaveBands.count).first
                else { continue }
                let delay = FieldAutoPlay.pushDelaySeconds(t.pushFraction, cellSeconds: cellSeconds)
                let hold = Double(t.gateFraction ?? 1) * cellSeconds
                XCTAssertLessThanOrEqual(delay + hold, cellSeconds + 1e-6,
                                         "\(character) cell \(cell) ties into the next cell")
            }
        }
    }

    func testTheTravellingMotionsHaveNoTimingOpinionAtAll() {
        for motion in FieldAutoPlay.Motion.allCases where motion != .arp {
            let params = FieldAutoPlay.Params(motion: motion, density: 1, span: 0.6, centre: 0.5,
                                              band: 0.5, bandDrift: 0.2, voices: 2, periodSteps: 16)
            var sawATouch = false
            for step in 0..<32 {
                for t in FieldAutoPlay.touches(atStep: step, params: params, seed: 5) {
                    sawATouch = true
                    XCTAssertNil(t.pushFraction,
                                 "\(motion) must stay byte-identical — it never had a timing opinion")
                    XCTAssertEqual(FieldAutoPlay.pushDelaySeconds(t.pushFraction,
                                                                  cellSeconds: cellSeconds), 0)
                }
            }
            XCTAssertTrue(sawATouch, "\(motion) produced nothing — the assertion above proved nothing")
        }
    }

    func testTheDefaultArpCharacterIsStraightSoTodaysSoundIsUnchanged() {
        // A2 shipped `character: .driving` as the arp's actual sound with no UI involved. A2b must not
        // have moved that: `driving` has no bias, so every default-configured note is still on the grid.
        let params = FieldAutoPlay.Params(motion: .arp, density: 1, periodSteps: 8)
        XCTAssertEqual(params.arpRhythm.character, .driving)
        for cell in 0..<8 {
            let delay = FieldAutoPlay.touches(atStep: cell, params: params, seed: 0,
                                              degreesPerOctave: 7,
                                              bandCount: TouchPitchMap.octaveBands.count)
                .map { FieldAutoPlay.pushDelaySeconds($0.pushFraction, cellSeconds: cellSeconds) }
            XCTAssertTrue(delay.allSatisfy { $0 == 0 },
                          "the shipped default must sound exactly as it did before A2b")
        }
    }
}
