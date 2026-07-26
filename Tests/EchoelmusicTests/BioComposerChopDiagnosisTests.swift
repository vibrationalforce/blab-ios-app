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
//   2. A REAL SOUND DEFECT — `.comp` on a section that misses the grid. FOUND HERE, FIXED IN
//      THE SOURCE; these tests are now its regression pins. comp hits absolute steps 4 and 12
//      only, so a section containing neither caught nothing and took `chordOnsets`' empty
//      fallback: ONE onset holding the whole section. How bad that was is PER GENRE, and the
//      first draft of this header got it wrong by naming the whole comp family:
//
//        jazz, rock        prog 4 → 4-step sections; 0..<4 and 8..<12 both miss → pad starts
//                          {0,4,8,12}, BYTE-IDENTICAL to held classical. The worst case.
//        punk, rocknroll,  prog 3 → 0..<5, 5..<10, 10..<16; only the MIDDLE one misses → one
//        heavyMetal        5-step hold out of three. Real, but not identical-to-held.
//        oriental          prog 2 → 0..<8, 8..<16; both contain a hit → never degenerate.
//                          It was NEVER broken and must not be listed as such.
//
//      That is ship-gate 1, "genre identity survives", and it was invisible to the red test
//      because jazz's 4 chord TONES still push its note COUNT above classical's — it passed on
//      chord size, not on rhythm. The fallback is now a short chop displaced off the section
//      downbeat and snapped to the 8th grid, so jazz's pad starts become {2, 4, 10, 12} and
//      punk's missed section lands on 6 rather than the 16th at 7 a fixed +2 would give.
//
// Finding 1 is still open: `testPipeline_rocksteady_…` below is expected RED, and the fix is to
// reshape the RED TEST'S assertion (count → distinct positions), not to touch the music.
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
    // anyway, so it is not re-asserted. What was never covered is the SHORT section — the only
    // length production actually reaches, and the one the empty fallback governs.

    func testOnsets_skank_onAFourStepSection_stillChopsOffbeat() {
        // One chop per section — but on step 2, i.e. off the beat. Across four sections that
        // is 2, 6, 10, 14: the complete skank grid. Sparse per section, correct overall.
        let onsets = BioComposer.chordOnsets(secStart: 0, secLen: 4, energy: 0.2,
                                             syncopation: 0, articulation: .skank)
        XCTAssertEqual(onsets.map(\.start), [2])
    }

    func testOnsets_comp_onAFourStepSection_chopsOffTheDownbeatInsteadOfHolding() {
        // THE SOUND DEFECT, isolated — and now the pin on its fix. comp hits phase % 8 == 4, so
        // a section covering steps 0..<4 catches no grid hit and takes `chordOnsets`' empty
        // fallback. That fallback used to return ONE onset spanning the whole section, i.e. a
        // held chord indistinguishable from the `.sustained` branch. It is now a short chop
        // placed off the section downbeat.
        let onsets = BioComposer.chordOnsets(secStart: 0, secLen: 4, energy: 0.2,
                                             syncopation: 0, articulation: .comp)
        XCTAssertEqual(onsets.map(\.start), [2])
        // The LENGTH is the half that makes this a defect report and not a spacing observation:
        // a 4-long onset on a 4-long section is a hold no matter where it starts.
        XCTAssertEqual(onsets.first?.len, 2, "the fallback must be a chop, not a held chord")
    }

    func testOnsets_comp_onAFiveStepSectionStartingOdd_snapsToTheEighthGrid() {
        // punk/rocknroll/heavyMetal's real geometry: prog.count 3 → sections 0..<5, 5..<10,
        // 10..<16, and the MIDDLE one catches neither comp hit (4 and 12). Its `secStart` is
        // ODD, so a fixed +2 displacement would land on absolute step 7 — a 16th, a position
        // no articulation in this function ever plays. The fallback snaps to the 8th grid
        // instead: step 6, the "and" of beat 2.
        let onsets = BioComposer.chordOnsets(secStart: 5, secLen: 5, energy: 0.2,
                                             syncopation: 0, articulation: .comp)
        XCTAssertEqual(onsets.map(\.start), [6])
        XCTAssertEqual(onsets.first?.len, 2)
    }

    func testOnsets_comp_fallbackIsAlwaysOffTheDownbeatAndOnAnEighth() {
        // The general contract, swept rather than pinned at one geometry — the earlier
        // single-case version would have passed for ANY non-zero displacement, including one
        // off the 8th grid. Two claims: never the section downbeat (that is `.stab`'s grid, and
        // chopping there would collapse comp into stab on every section it misses), and always
        // 8th-aligned (the grid every real hit in this function sits on).
        var fallbacksSeen = 0
        for secLen in 3...5 {
            for secStart in 0...(16 - secLen) {
                // Only sections that catch NO comp hit take the fallback; the rest are real
                // grid hits and are covered elsewhere.
                let caughtAHit = (secStart..<(secStart + secLen)).contains { $0 % 8 == 4 }
                if caughtAHit { continue }
                fallbacksSeen += 1
                let onsets = BioComposer.chordOnsets(secStart: secStart, secLen: secLen,
                                                     energy: 0.2, syncopation: 0,
                                                     articulation: .comp)
                let at = "sec \(secStart)+\(secLen)"
                XCTAssertEqual(onsets.count, 1, "\(at): the fallback is exactly one onset")
                guard let only = onsets.first else { continue }
                XCTAssertNotEqual(only.start, secStart, "\(at): fallback sits on the downbeat")
                XCTAssertTrue(only.start.isMultiple(of: 2), "\(at): fallback is off the 8th grid")
                XCTAssertLessThan(only.len, secLen, "\(at): fallback holds the whole section")
                XCTAssertLessThanOrEqual(only.start + only.len, secStart + secLen,
                                         "\(at): fallback leaves the section")
            }
        }
        // The sweep must actually exercise the branch — an empty loop would pass silently,
        // which is the #140 defect class this file was written to avoid.
        XCTAssertGreaterThan(fallbacksSeen, 0, "the sweep never reached the fallback branch")
    }

    func testOnsets_comp_onASectionWithNoEighthToMoveTo_holds() {
        // The fallback's own edge, both halves. A 1-step section has no room at all; a 2-step
        // section starting on an 8th has no OTHER 8th inside it. Both must still produce a
        // note — an empty list would be silence — and must not start outside the section.
        let one = BioComposer.chordOnsets(secStart: 5, secLen: 1, energy: 0.2,
                                          syncopation: 0, articulation: .comp)
        XCTAssertEqual(one.map(\.start), [5])
        XCTAssertEqual(one.first?.len, 1)

        let two = BioComposer.chordOnsets(secStart: 0, secLen: 2, energy: 0.2,
                                          syncopation: 0, articulation: .comp)
        XCTAssertEqual(two.map(\.start), [0])
        XCTAssertEqual(two.first?.len, 2)
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
        // Finding 2, and the reason the file exists. This was RED on c3cfde8: jazz's comp grid
        // produced the SAME onset positions as a held chord ({0,4,8,12}), so the comp family
        // carried no audible chord rhythm at all. With the off-downbeat fallback the two missed
        // sections land on 2 and 10, which no other layer contributes. It must not be silenced
        // by editing this assertion — red here means the comp family is inert again.
        XCTAssertGreaterThan(distinctStarts(.jazz), distinctStarts(.classical))
    }
}
