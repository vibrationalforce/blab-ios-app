// GenreBassGrammarTests.swift
// Echoel — a genre OWNS its bass figure (#983), in the BLOCKING bundle.
//
// KIND: END-TO-END BEHAVIOUR on the pure composer (`BioComposer.compose` → `[Note]`) and on the
// pure figure tables (`BassGrammar.hits`) — Foundation-only value types, no engine. The one thing
// no assertion here can reach is whether the figure GROOVES on a device; that is the plan's
// NEEDS-FOUNDER-VERIFY line, not this file's.
//
// ⭐ THE ONE TEST THAT MATTERS IS THE CALM-BODY ONE. Before #983 every non-sustained genre lost
// its bass line the moment the body settled: `appendBass` guards the walk on `motion > 0.32`
// and a resting performer got ONE held root per section, whatever the genre. A house bass that
// only appears when the player is aroused is not a house bass. So the deep-house offbeat is
// asserted at coherence 0.9 / 58 BPM / shallow breath FIRST, and the aroused body second.
//
// ⛔ WHAT THIS FILE DOES NOT PIN, deliberately (#364): the level numbers inside a figure (a
// designer may re-balance 0.85 vs 0.9), and the exact genre→figure table beyond the three
// genres that carry one today — the plan's S3–S5 add arms, and `testEveryGrammarIsOwnedOrAuthoredAhead`
// says which figure is still waiting for a genre so a re-run after S5 goes red on the right line.

import XCTest
@testable import Echoelmusic

final class GenreBassGrammarTests: XCTestCase {

    /// A SETTLED body — the case the walk always dropped.
    private func calmInput(_ style: MusicStyle, rhythm: RoleRhythm.Character? = nil) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: 58, hrvNormalized: 0.8, coherence: 0.9,
                          breathPhase: 0.5, breathDepth: 0.1,
                          key: MusicalKey(root: 0, scale: style.scale),
                          style: style, mode: .studioLocked,
                          lockedTempo: Double(style.defaultTempo),
                          seed: 0xBA55, bassRhythm: rhythm)
    }

    /// The same take with drive in it (the shape `BassRhythmOverrideTests` uses).
    private func busyInput(_ style: MusicStyle, rhythm: RoleRhythm.Character? = nil) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: 132, hrvNormalized: 0.3, coherence: 0.3,
                          breathPhase: 0.25, breathDepth: 0.9,
                          key: MusicalKey(root: 0, scale: style.scale),
                          style: style, mode: .studioLocked,
                          lockedTempo: Double(style.defaultTempo),
                          seed: 0xBA55, bassRhythm: rhythm)
    }

    private func bass(_ input: BioComposer.Input) -> [Note] {
        BioComposer.compose(input).notes.filter { $0.role == .bass }
            .sorted { $0.startStep < $1.startStep }
    }

    // MARK: - The figures themselves

    /// Every figure is a legal one-bar line: phases inside the bar, no zero-length note
    /// (#205/#176), ascending, and NO overlap — two bass notes over each other is the mud the
    /// founder has already reported on the low end.
    func testEveryFigureIsInsideTheBarAscendingAndNonOverlapping() {
        for grammar in BassGrammar.allCases {
            let hits = grammar.hits
            XCTAssertFalse(hits.isEmpty, "\(grammar.rawValue): an empty figure is a silent genre")
            for (i, hit) in hits.enumerated() {
                XCTAssertTrue((0..<16).contains(hit.phase), "\(grammar.rawValue): phase \(hit.phase)")
                XCTAssertGreaterThanOrEqual(hit.length, 1, "\(grammar.rawValue): zero-length hit")
                XCTAssertTrue((0...1).contains(hit.level), "\(grammar.rawValue): level \(hit.level)")
                if i + 1 < hits.count {
                    XCTAssertLessThanOrEqual(hit.phase + hit.length, hits[i + 1].phase,
                                             "\(grammar.rawValue): hit at \(hit.phase) overlaps the next")
                }
            }
        }
    }

    /// The psy roll leaves every downbeat FREE and rolls three 16ths under each beat.
    func testRollingSixteenthsLeaveTheDownbeatsFree() {
        let phases = BassGrammar.rollingSixteenths.hits.map(\.phase)
        XCTAssertEqual(phases.count, 12)
        XCTAssertTrue(phases.allSatisfy { $0 % 4 != 0 }, "a rolling bass never sits on the kick: \(phases)")
        for beat in 0..<4 {
            XCTAssertEqual(phases.filter { $0 / 4 == beat }.count, 3, "beat \(beat) must roll three")
        }
    }

    /// Every figure is either owned by an OFFERED genre or authored ahead for a planned one.
    /// `rollingSixteenths` waited for S5 (`psyProgHouse`) and is owned since that landed; the
    /// authored-ahead set is EMPTY today. A figure nobody will ever own is dead code with a name.
    func testEveryGrammarIsOwnedOrAuthoredAhead() {
        let owned = Set(MusicStyle.offered.compactMap(\.bassGrammar))
        let authoredAhead: Set<BassGrammar> = []
        XCTAssertEqual(owned.union(authoredAhead), Set(BassGrammar.allCases),
                       "a figure is neither owned by an offered genre nor listed as authored ahead")
        XCTAssertTrue(owned.isDisjoint(with: authoredAhead),
                      "a figure listed as authored ahead is already owned — update this test")
    }

    // MARK: - The figure reaches the take

    /// ⭐ Deep house at a RESTING body: every bass note on an "&" (phase ≡ 2 mod 4), none on a
    /// beat. Before #983 this take held one root per section instead.
    func testDeepHouseBassSitsOnTheOffbeatEvenWhenTheBodyIsCalm() {
        for input in [calmInput(.deepHouse), busyInput(.deepHouse)] {
            let line = bass(input)
            XCTAssertFalse(line.isEmpty)
            for n in line {
                XCTAssertEqual(n.startStep % 4, 2, "deep house bass at step \(n.startStep) is not on an '&'")
                XCTAssertEqual(n.lengthSteps, 2, "an 8th, not a held note")
            }
            XCTAssertTrue(line.allSatisfy { $0.velocity > 0 })
        }
    }

    /// Tech house drives every 8th, calm or not, and the last "&" carries the fifth (a different
    /// pitch from the root the other hits play).
    func testTechHouseDrivesEveryEighth() {
        for input in [calmInput(.techHouse), busyInput(.techHouse)] {
            let line = bass(input)
            XCTAssertEqual(Set(line.map(\.startStep)), Set(stride(from: 0, to: 16, by: 2)),
                           "tech house must land on all eight 8ths")
            let onBeats = line.filter { $0.startStep % 4 == 0 }
            XCTAssertTrue(onBeats.allSatisfy { $0.lengthSteps == 2 }, "on-beats are held to the '&'")
            let last = line.first { $0.startStep == 14 }
            let root = line.first { $0.startStep == 12 }
            if let last, let root {
                XCTAssertNotEqual(last.pitch, root.pitch, "step 14 is the fifth, not the root")
            } else {
                XCTFail("steps 12 and 14 must both sound")
            }
        }
    }

    /// Minimal techno holds ONE long dark root from the downbeat, then one short fifth on "3&".
    func testMinimalTechnoHoldsALongRootThenOneShortFifth() {
        for input in [calmInput(.minimalTechno), busyInput(.minimalTechno)] {
            let line = bass(input)
            XCTAssertEqual(line.map(\.startStep), [0, 10])
            guard line.count == 2 else { XCTFail("minimal techno must play exactly two bass hits"); continue }
            XCTAssertEqual(line[0].lengthSteps, 8, "the root is held half the bar")
            XCTAssertEqual(line[1].lengthSteps, 2)
            XCTAssertNotEqual(line[0].pitch, line[1].pitch, "the second hit is the fifth")
        }
    }

    /// The body still sets the LEVEL: the same figure plays softer on a shallow-breath calm
    /// body than on a deep-breath aroused one (`bassVelocity` = f(breathDepth, tilt)). Breath
    /// depths 0.1 vs 0.9 put ~0.67 between the two sums, well outside `hVel`'s ±0.05-per-note
    /// jitter even if the two takes' RNG streams diverge before the bass is drawn.
    func testTheBodyStillOwnsTheLevelUnderAFigure() {
        let calm = bass(calmInput(.deepHouse)).map(\.velocity).reduce(0, +)
        let busy = bass(busyInput(.deepHouse)).map(\.velocity).reduce(0, +)
        XCTAssertLessThan(calm, busy, "a resting body must play the figure softer, not identically")
    }

    /// The user's Bass-rhythm Picker still wins: a set character on a grammar genre gives a
    /// DIFFERENT line from the genre's figure (it takes the walking path, as documented).
    func testTheUserRhythmPickerWinsOverTheGenreFigure() {
        let figure = bass(busyInput(.deepHouse)).map { [$0.startStep, $0.lengthSteps] }
        let picked = bass(busyInput(.deepHouse, rhythm: .driving)).map { [$0.startStep, $0.lengthSteps] }
        XCTAssertNotEqual(figure, picked, "a chosen character must override the genre's figure")
    }

    /// NEGATIVE CONTROL for the Golden law: a genre WITHOUT a figure is not touched by this slice.
    /// `.disco` is the reference `BassRhythmOverrideTests` uses; its calm take must still be the
    /// old walk's held root (one bass note per section, on the section downbeat).
    func testAGenreWithoutAFigureKeepsTheOldWalk() {
        XCTAssertNil(MusicStyle.disco.bassGrammar)
        let line = bass(calmInput(.disco))
        let sections = MusicStyle.disco.harmonicProfile.progression.count
        XCTAssertEqual(line.count, sections, "a calm walk-genre holds exactly one root per section")
        let sectionLen = 16 / sections
        for n in line {
            XCTAssertEqual(n.startStep % sectionLen, 0, "the held root starts on its section downbeat")
        }
    }

    // MARK: - The felt sub honours the hole

    /// With `bassOnly` the sub ignores the pad, so a free downbeat is FELT free too; without it,
    /// the old lowest-of-everything rule is unchanged.
    /// `@MainActor` because `feltSubPitch` is a `static func` on `@MainActor PianoRollModel` and
    /// INHERITS that isolation (HARNESS_LEDGER dead-end; the first push of this file paid it).
    @MainActor
    func testTheFeltSubFollowsOnlyTheBassRoleWhenAsked() {
        let pad = Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: 0.6, role: .harmony)
        let low = Note(pitch: 36, startStep: 2, lengthSteps: 2, velocity: 0.8, role: .bass)
        XCTAssertEqual(PianoRollModel.feltSubPitch(forActive: [pad, low], laneAudible: true,
                                                   hasKindVoice: false, bassOnly: true), 24)
        XCTAssertNil(PianoRollModel.feltSubPitch(forActive: [pad], laneAudible: true,
                                                 hasKindVoice: false, bassOnly: true),
                     "pad only + bassOnly ⇒ the hole stays a hole")
        XCTAssertEqual(PianoRollModel.feltSubPitch(forActive: [pad], laneAudible: true,
                                                   hasKindVoice: false, bassOnly: false), 48,
                       "the pre-#983 rule is unchanged when the flag is off")
    }
}
