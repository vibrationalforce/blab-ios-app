// BioComposerChopDiagnosisTests.swift
// Echoel — locates WHY `BioComposerTests.testCompose_rhythmicGenresChopChords_notInertThroughPipeline`
// has been red in the full suite since it was wired.
//
// That test asserts three genres at once (disco, jazz, rocksteady) in one loop and carries a
// careful `census` of all three counts in its failure message. The message never arrives: the
// full suite runs with `-parallel-testing-enabled YES`, so xcodebuild reports only
// `Test case '<name>' failed on 'Clone N'` and the assertion body stays in the child runner.
// One red name for three genres and no numbers is not a diagnosis — the same blindness that
// kept the Community-bundle bug alive through three attempts (see HARNESS_LEDGER).
//
// So: one assertion per genre, and one per LAYER, with the answer in the name.
//
//   only ONE genre's compose test fails      → arithmetic, not inertness. That genre's
//                                              progression × chordTones happens to tie or lose
//                                              against classical's 4 sections × 3 tones = 12
//                                              pad notes, which says nothing about articulation.
//   all THREE compose tests fail             → the articulated branch is not being reached.
//   an ONSET test fails                      → `chordOnsets` itself is wrong; the core, not
//                                              the pipeline (and `BioComposerTests`'
//                                              `testChordArticulation_…` should be red too).
//   a ROUTING test fails                     → that genre takes the `profile.arpeggiated`
//                                              branch, which bypasses `chordOnsets` entirely,
//                                              so the chop can be perfectly correct and still
//                                              never appear.
//
// STATIC READING, recorded so the next session can check it against the run rather than redo it.
// All four genres have `profile.sustained == false` (none is in `sustainedFlächen`), so each
// gets one section per progression entry. Pad notes = sections × chordTones × onsets-per-section:
// classical [0,3,4,0] × [0,2,4] on the HELD branch = 4 × 3 × 1 = 12. disco [0,3,4] × [0,2,4,6];
// jazz [0,3,5,1] × [0,2,4,6]; rocksteady [0,5,3,4] × [0,2,4].
//
// THE HINGE IS SECTION LENGTH, and it is the one number I could not read off the source.
// `chordOnsets` scans `secStart..<secStart+secLen` against a bar-aligned 16-step phase, so:
//   · a section ≥ 1 bar → skank 4 hits (2,6,10,14), stab 4 (0,4,8,12), comp 2 (4,12).
//     Then disco 48, jazz 32, rocksteady 48 — all far above classical's 12, and the red
//     test's premise would be sound while its result is not.
//   · a SHORT section (≈4 steps) → skank 1, stab 1, comp 0 → the empty-fallback single held
//     onset. Then rocksteady = 4 × 3 × 1 = 12, EXACTLY classical's 12, and
//     `XCTAssertGreaterThan` fails on a tie — the confound the red test's own comment warned
//     about. disco (3 × 4 × ≥1 = 12+) and jazz (4 × 4 × 1 = 16) would still pass.
//
// So "only rocksteady red" and "all three red" mean completely different things, and the
// single looped assertion cannot tell them apart. That is the whole reason for this file.
// Note the second branch is NOT merely a test bug: if a section is too short for the genre
// grid to land more than one chop, the genre's rhythm is inaudible in production too —
// ship-gate 1 ("Klang", genre identity survives). Which it is decides whether the fix belongs
// in the test or in the composer.
//
// Cannot redden a gate: Tests/EchoelmusicTests is compiled only by the EchoelmusicFullTests
// scheme, which only the non-blocking full-tests.yml runs.

import XCTest
@testable import Echoelmusic

final class BioComposerChopDiagnosisTests: XCTestCase {

    /// The SAME input the red test uses — if these diverge, this file stops explaining it.
    private func chopInput(_ style: MusicStyle) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: 90, hrvNormalized: 0.5, coherence: 0.4,
                          breathPhase: 0, breathDepth: 0.5,
                          key: MusicalKey(root: 0, scale: .minor),
                          style: style, mode: .studioLocked, lockedTempo: 124, seed: 0x5EED)
    }

    private func noteCount(_ style: MusicStyle) -> Int {
        BioComposer.compose(chopInput(style)).notes.count
    }

    // MARK: - Layer 1: routing (does the genre even reach the articulated branch?)

    func testRouting_disco_isNotArpeggiated() {
        XCTAssertFalse(MusicStyle.disco.harmonicProfile.arpeggiated)
    }

    func testRouting_jazz_isNotArpeggiated() {
        XCTAssertFalse(MusicStyle.jazz.harmonicProfile.arpeggiated)
    }

    func testRouting_rocksteady_isNotArpeggiated() {
        XCTAssertFalse(MusicStyle.rocksteady.harmonicProfile.arpeggiated)
    }

    // MARK: - Layer 2: the articulation core, per genre grid

    func testOnsets_skank_hitsFourOffbeatsPerBar() {
        // Reggae/ska offbeat 8ths: steps 2, 6, 10, 14. Energy-independent by design
        // ("the offbeat IS the genre, at rest or aroused"), so a low-energy body is
        // not an excuse for a sparse skank.
        let onsets = BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: 0.2,
                                             syncopation: 0, articulation: .skank)
        XCTAssertEqual(onsets.map(\.start), [2, 6, 10, 14])
    }

    func testOnsets_stab_hitsFourDownbeatsPerBar() {
        let onsets = BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: 0.2,
                                             syncopation: 0, articulation: .stab)
        XCTAssertEqual(onsets.map(\.start), [0, 4, 8, 12])
    }

    func testOnsets_comp_hitsTheBackbeatTwicePerBar() {
        let onsets = BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: 0.2,
                                             syncopation: 0, articulation: .comp)
        XCTAssertEqual(onsets.map(\.start), [4, 12])
    }

    // MARK: - Layer 2b: the same grids on a SHORT section (the section-length hinge)

    func testOnsets_skank_onAFourStepSection_collapsesToOneChop() {
        // Not a bug report — a measurement. The offbeat grid is bar-aligned, so a quarter-bar
        // section can only ever catch step 2. If this is the section length production uses,
        // rocksteady's 4 × 3 × 1 = 12 ties classical exactly and the red test's
        // `XCTAssertGreaterThan` fails without anything being inert.
        let onsets = BioComposer.chordOnsets(secStart: 0, secLen: 4, energy: 0.2,
                                             syncopation: 0, articulation: .skank)
        XCTAssertEqual(onsets.map(\.start), [2])
    }

    func testOnsets_comp_onAFourStepSection_fallsBackToOneHeldOnset() {
        // `.comp` hits phase 4 and 12, so steps 0..<4 catch NOTHING and the empty-guard
        // returns one section-length onset — i.e. a jazz chop that is indistinguishable from
        // a held chord. Worth pinning separately: it is the articulation most likely to
        // disappear on short sections.
        let onsets = BioComposer.chordOnsets(secStart: 0, secLen: 4, energy: 0.2,
                                             syncopation: 0, articulation: .comp)
        XCTAssertEqual(onsets.map(\.start), [0])
        XCTAssertEqual(onsets.first?.len, 4, "the fallback holds the whole section")
    }

    func testOnsets_sustained_isTheOneThingThatMayBeSparse() {
        // The held genres delegate to `heartbeatOnsets`. Asserted only as "at least one",
        // because a calm body is SUPPOSED to yield a single held onset — this exists so a
        // reader cannot mistake a sparse sustained result for a bug.
        let onsets = BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: 0.2,
                                             syncopation: 0, articulation: .sustained)
        XCTAssertGreaterThanOrEqual(onsets.count, 1)
    }

    // MARK: - Layer 3: the pipeline, ONE genre per name

    func testPipeline_disco_producesMoreNotesThanHeldClassical() {
        XCTAssertGreaterThan(noteCount(.disco), noteCount(.classical))
    }

    func testPipeline_jazz_producesMoreNotesThanHeldClassical() {
        XCTAssertGreaterThan(noteCount(.jazz), noteCount(.classical))
    }

    func testPipeline_rocksteady_producesMoreNotesThanHeldClassical() {
        XCTAssertGreaterThan(noteCount(.rocksteady), noteCount(.classical))
    }

    // MARK: - Layer 3b: the same claim WITHOUT the cross-genre confound

    /// The comparison the red test actually wants to make. Counting whole compositions across
    /// two different genres mixes in progression length, chord size, bass, pulse and lead — so
    /// a red result there does NOT establish that articulation is inert, and a green one does
    /// not establish that it works. Counting DISTINCT ONSET POSITIONS inside one genre's own
    /// output isolates the chop: a held chord contributes one start per section, a chopped one
    /// contributes several, whatever the progression looks like.
    private func distinctStarts(_ style: MusicStyle) -> Int {
        Set(BioComposer.compose(chopInput(style)).notes.map(\.startStep)).count
    }

    func testChop_disco_hasMoreDistinctOnsetPositionsThanClassical() {
        XCTAssertGreaterThan(distinctStarts(.disco), distinctStarts(.classical))
    }

    func testChop_rocksteady_hasMoreDistinctOnsetPositionsThanClassical() {
        XCTAssertGreaterThan(distinctStarts(.rocksteady), distinctStarts(.classical))
    }
}
