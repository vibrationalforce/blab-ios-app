// BioComposerChopDiagnosisTests.swift
// Echoel — locates WHY `BioComposerTests.testCompose_rhythmicGenresChopChords_notInertThroughPipeline`
// has been red in the full suite (observed on 8f953de, 7b7f998, 08a7bbb and 60a1e34), and pins a
// SECOND finding the red test cannot see at all.
//
// That test asserts three genres in one loop and carries a census of all three counts in its
// failure message. The message never arrives — the full suite runs `-parallel-testing-enabled YES`
// and xcodebuild then reports only `Test case '<name>' failed on 'Clone N'`. One red name for
// three genres and no numbers is not a diagnosis, so: one assertion per genre and per layer,
// with the answer in the name. (Same playbook as the Community-bundle bug, HARNESS_LEDGER.)
//
// THE ARITHMETIC, now read fully off the source rather than hedged. A composition is ONE 16-step
// bar (`BioComposer.stepCount`) and `composeHarmonic` cuts it into `max(1, 16 / prog.count)`
// sections (`BioComposer.swift`, `let sectionLen = …`), the last one extended to the bar end. So
// for every genre here the sections are SHORT, and the earlier draft of this file documented a
// "section ≥ 1 bar" case that cannot occur — that would need `prog.count == 1`.
//
//   classical  [0,3,4,0] × [0,2,4]    4 sections of 4   held branch        → pad starts 0,4,8,12
//   jazz       [0,3,5,1] × [0,2,4,6]  4 sections of 4   .comp
//   rocksteady [0,5,3,4] × [0,2,4]    4 sections of 4   .skank
//   disco      [0,3,4]   × [0,2,4,6]  5,5,6             .stab
//
// `.skank` hits phase % 4 == 2, `.stab` phase % 4 == 0, `.comp` phase % 8 == 4 — all bar-aligned
// absolute phases, and at this bio state (`coherence 0.4, hr 90`) the energy fills for stab
// (≥0.60) and comp (≥0.62) are both off. Two consequences, and they are different in kind:
//
//   1. TEST ARITHMETIC. rocksteady gets one skank chop per 4-step section, so 4 × 3 × 1 = 12 pad
//      notes — EXACTLY classical's 4 × 3 × 1 = 12. It shares prog.count, sectionLen and
//      chordTones.count with classical, so its bass and pulse counts match too and the tie
//      survives at whole-composition level. `XCTAssertGreaterThan` then fails on a TIE, which
//      reads as "articulation is inert" while rocksteady's chops actually land on 2, 6, 10, 14 —
//      the full skank grid, audibly offbeat. The red test's own comment warned about exactly
//      this confound. This is a defect in the ASSERTION, not in the music.
//
//   2. A REAL SOUND DEFECT — `.comp` on a 4-step section. comp hits absolute steps 4 and 12
//      only, so of jazz's four sections two catch nothing and take `chordOnsets`' empty-guard
//      fallback: ONE onset holding the whole section. Jazz's distinct pad starts come out as
//      {0, 4, 8, 12} — byte-identical to a HELD chord. The 2026-07-22 "going through the genres,
//      everything sounds the same" fix therefore does not reach the comp family at all (jazz,
//      oriental, rock, punk, rocknroll, heavyMetal). That is ship-gate 1, "genre identity
//      survives", and it is invisible to the red test because jazz's 4 chord TONES still push
//      its note COUNT above classical's.
//
// `testChop_jazz_…` below is expected RED and is the point of this file. Fixing it changes what
// the instrument sounds like, so it is a Council slice, not a test edit.
//
// Cannot redden a gate: Tests/EchoelmusicTests is compiled only by the EchoelmusicFullTests
// scheme, which only the non-blocking full-tests.yml runs.

import XCTest
@testable import Echoelmusic

final class BioComposerChopDiagnosisTests: XCTestCase {

    /// Byte-identical to the red test's own input — if these diverge, this file stops explaining it.
    private func chopInput(_ style: MusicStyle) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: 90, hrvNormalized: 0.5, coherence: 0.4,
                          breathPhase: 0, breathDepth: 0.5,
                          key: MusicalKey(root: 0, scale: .minor),
                          style: style, mode: .studioLocked, lockedTempo: 124, seed: 0x5EED)
    }

    private func noteCount(_ style: MusicStyle) -> Int {
        BioComposer.compose(chopInput(style)).notes.count
    }

    /// Distinct onset POSITIONS across the whole take. Deliberately not called "the chop in
    /// isolation": bass and pulse also contribute starts, and their spacing follows `sectionLen`,
    /// so a genre whose progression length differs from classical's gets extra positions for free.
    /// It is decisive only where `prog.count` matches classical's 4 — jazz and rocksteady — which
    /// is why disco is compared by note count instead.
    private func distinctStarts(_ style: MusicStyle) -> Int {
        Set(BioComposer.compose(chopInput(style)).notes.map(\.startStep)).count
    }

    // MARK: - Layer 1: routing — does the genre reach the articulated branch at all?

    /// `arpeggiated` alone does NOT answer this: classical is also non-arpeggiated and still
    /// lands in the held `else`, because its articulation is `.sustained`. Both facts together
    /// are the routing claim, so both are asserted per genre.
    func testRouting_disco_isNonArpeggiatedWithStabArticulation() {
        XCTAssertFalse(MusicStyle.disco.harmonicProfile.arpeggiated)
        XCTAssertEqual(MusicStyle.disco.chordArticulation, .stab)
    }

    func testRouting_jazz_isNonArpeggiatedWithCompArticulation() {
        XCTAssertFalse(MusicStyle.jazz.harmonicProfile.arpeggiated)
        XCTAssertEqual(MusicStyle.jazz.chordArticulation, .comp)
    }

    func testRouting_rocksteady_isNonArpeggiatedWithSkankArticulation() {
        // Nothing else in the suite pins rocksteady's articulation — the existing
        // `testChordArticulation_mappedFromArchetype_andGenresDiffer` asserts `.ska`.
        XCTAssertFalse(MusicStyle.rocksteady.harmonicProfile.arpeggiated)
        XCTAssertEqual(MusicStyle.rocksteady.chordArticulation, .skank)
    }

    // MARK: - Layer 2: the grids on the section length production ACTUALLY uses

    // The full-bar behaviour of each grid is already covered by BioComposerTests
    // (`testChordOnsets_skankHitsOnlyOffbeatEighths` and siblings) and is unreachable here
    // anyway, so it is not re-asserted. What was never covered is the 4-step section.

    func testOnsets_skank_onAFourStepSection_stillChopsOffbeat() {
        // One chop per section — but on step 2, i.e. off the beat. Across four sections that
        // is 2, 6, 10, 14: the complete skank grid. Sparse per section, correct overall.
        let onsets = BioComposer.chordOnsets(secStart: 0, secLen: 4, energy: 0.2,
                                             syncopation: 0, articulation: .skank)
        XCTAssertEqual(onsets.map(\.start), [2])
    }

    func testOnsets_comp_onAFourStepSection_degeneratesToAHeldChord() {
        // THE SOUND DEFECT, isolated. comp hits phase % 8 == 4, so a section covering steps
        // 0..<4 catches nothing and the empty-guard returns one onset spanning the whole
        // section — indistinguishable from the held branch. Asserting the fallback's LENGTH is
        // what makes this a defect report rather than a spacing observation.
        let onsets = BioComposer.chordOnsets(secStart: 0, secLen: 4, energy: 0.2,
                                             syncopation: 0, articulation: .comp)
        XCTAssertEqual(onsets.map(\.start), [0])
        XCTAssertEqual(onsets.first?.len, 4, "a comp chop that holds the whole section is a held chord")
    }

    // MARK: - Layer 3: the pipeline, ONE genre per name

    func testPipeline_disco_producesMoreNotesThanHeldClassical() {
        XCTAssertGreaterThan(noteCount(.disco), noteCount(.classical))
    }

    func testPipeline_jazz_producesMoreNotesThanHeldClassical() {
        // Passes on chord SIZE (4 tones vs 3), not on articulation — see testChop_jazz.
        XCTAssertGreaterThan(noteCount(.jazz), noteCount(.classical))
    }

    func testPipeline_rocksteady_producesMoreNotesThanHeldClassical() {
        // EXPECTED RED, and expected to stay red until the red test's assertion is reshaped:
        // rocksteady ties classical exactly. Kept as the pin for finding 1.
        XCTAssertGreaterThan(noteCount(.rocksteady), noteCount(.classical))
    }

    // MARK: - Layer 3b: does the chord actually get CHOPPED, at equal progression length?

    func testChop_rocksteady_hasMoreDistinctOnsetPositionsThanClassical() {
        // Same prog.count as classical, so this is a fair comparison: rocksteady's offbeat
        // chops add positions 2, 6, 10, 14 that a held chord does not have.
        XCTAssertGreaterThan(distinctStarts(.rocksteady), distinctStarts(.classical))
    }

    func testChop_jazz_hasMoreDistinctOnsetPositionsThanClassical() {
        // EXPECTED RED — this is finding 2 and the reason the file exists. Jazz has the same
        // prog.count as classical, so the comparison is fair, and jazz's comp grid produces
        // the SAME onset positions as a held chord. Red here means the comp family carries no
        // audible chord rhythm; it must not be silenced by editing this assertion.
        XCTAssertGreaterThan(distinctStarts(.jazz), distinctStarts(.classical))
    }
}
