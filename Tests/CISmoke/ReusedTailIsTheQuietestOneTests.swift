// ReusedTailIsTheQuietestOneTests.swift
// Echoel — #404. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PROTECTS. When a note arrives and no slot is both free AND silent, the poly
// engine reuses a slot whose release tail is still ringing. That reuse is never free:
// `spawnVoice` calls `prepareForNote(hardReset: false)`, which nevertheless clears
// `smoothedFreq`, and the render re-seeds it to the NEW pitch on the very next sample. The
// waveform's VALUE stays continuous (partial phases are kept) but its SLOPE does not, and
// the loudness of that kink scales with how loud the reused tail still was.
//
// Until #404 the choice was `voiceNotes.firstIndex(of: -1)` — the LOWEST INDEX, a number
// with no relationship to loudness. `quietestFreeSlot` makes it the quietest tail instead,
// so the unavoidable kink lands on the least audible voice available.
//
// ⚠️ HOW FAR THE CLAIM GOES — this bundle can prove the DECISION, never the SOUND. That the
// re-pitch is a real discontinuity is read off the code; that it is what the founder means
// by "teilweise extremes Knacken" is NOT established, and shipping this as "the crackle fix"
// would be exactly the overstatement this repo keeps paying for. It lowers a floor. Whether
// the floor was the ceiling is a device question.
//
// WHY THE WIRING IS SCANNED AND NOT DRIVEN: which slot was chosen is not observable from
// outside `EchoelPolyDDSP` — `allocateVoice` and `voiceNotes` are private, and the audible
// difference (one pitch keeps ringing instead of being replaced) needs a spectral read this
// bundle has no business doing. So the arithmetic is tested for real and the CALL is pinned
// by source text. A correct core with no caller is the same defect with more steps, which is
// why the scan is not optional decoration here.

import Foundation
import XCTest
@testable import Echoelmusic

final class ReusedTailIsTheQuietestOneTests: XCTestCase {

    // MARK: - The measure itself

    func testAFullEngineHasNoSlotToReuse() {
        let chosen = EchoelPolyDDSP.quietestFreeSlot(voiceNotes: [60, 64, 67],
                                                     levels: [0.1, 0.2, 0.3])
        let message = "Every slot still holds a note, so there is nothing to reuse — the "
            + "answer must be nil so the caller falls through to its steal path. Returning "
            + "an index here would hand out a slot that is still holding a live note."
        XCTAssertNil(chosen, message)
    }

    func testTheOnlyFreeSlotIsTheAnswer() {
        let chosen = EchoelPolyDDSP.quietestFreeSlot(voiceNotes: [60, -1, 67],
                                                     levels: [0.9, 0.9, 0.9])
        XCTAssertEqual(chosen, 1, "Exactly one slot is free; it is the only possible answer.")
    }

    func testTheQuietestFreeSlotWinsNotTheFirst() {
        // THE REGRESSION THIS FILE EXISTS FOR. Slots 0 and 3 are both free. The old rule
        // returned 0 because it was first; the loud tail paid the kink while a nearly
        // silent one sat unused.
        let chosen = EchoelPolyDDSP.quietestFreeSlot(voiceNotes: [-1, 64, 67, -1],
                                                     levels: [0.80, 0.50, 0.50, 0.02])
        let message = "Slot 3's tail is at 0.02 and slot 0's is at 0.80, yet slot 0 was "
            + "chosen — that is the pre-#404 lowest-index rule, and it puts the re-pitch "
            + "kink on the loudest voice in the engine."
        XCTAssertEqual(chosen, 3, message)
    }

    func testABusySlotIsNeverChosenNoMatterHowQuiet() {
        // A slot can be silent and still be holding a note (a long attack, or a note baked
        // to velocity 0 by a Mix fader at zero — #174). Loudness must never override the
        // free/busy question; reusing a held note would cut it dead.
        let chosen = EchoelPolyDDSP.quietestFreeSlot(voiceNotes: [-1, 64, -1],
                                                     levels: [0.40, 0.0, 0.60])
        let message = "Slot 1 has the lowest level but still holds note 64. It was chosen "
            + "anyway, which would silence a note the player is holding."
        XCTAssertEqual(chosen, 0, message)
    }

    func testTiesGoToTheLowestIndexSoNothingChangesWhereItWasAlreadyRight() {
        // This is what makes the change a strict refinement rather than a different policy:
        // with equal levels the answer is byte-identical to the old `firstIndex(of: -1)`.
        let chosen = EchoelPolyDDSP.quietestFreeSlot(voiceNotes: [-1, -1, -1],
                                                     levels: [0.3, 0.3, 0.3])
        let message = "All three tails are equally loud, so there is no reason to prefer a "
            + "later slot — and preferring one would make the new rule differ from the old "
            + "one on cases the old one already got right."
        XCTAssertEqual(chosen, 0, message)
    }

    func testTheQuietestIsFoundWhereverItSits() {
        // Guards against an implementation that only ever compares neighbours, or that
        // stops at the first improvement instead of scanning to the end.
        let levels: [Float] = [0.9, 0.7, 0.5, 0.3, 0.1]
        for winner in 0..<levels.count {
            var shaped = levels
            shaped[winner] = 0.001
            let notes = [Int](repeating: -1, count: levels.count)
            let chosen = EchoelPolyDDSP.quietestFreeSlot(voiceNotes: notes, levels: shaped)
            let message = "The quietest tail sits at slot \(winner) and slot "
                + "\(String(describing: chosen)) was chosen instead."
            XCTAssertEqual(chosen, winner, message)
        }
    }

    // MARK: - The edges that must not cost a voice

    func testANonFiniteLevelCannotWin() {
        // NaN loses every `<` comparison, so it could never win by accident — but relying on
        // that is how a later refactor to `<=` or a sort silently promotes a poisoned
        // envelope to "quietest". Pinned explicitly.
        let chosen = EchoelPolyDDSP.quietestFreeSlot(voiceNotes: [-1, 64, -1],
                                                     levels: [Float.nan, 0.5, 0.5])
        let message = "A NaN level is not a measurement of anything and must never read as "
            + "the quietest tail; slot 2 carries the only usable level here."
        XCTAssertEqual(chosen, 2, message)
    }

    func testEveryFreeLevelNonFiniteStillYieldsAVoice() {
        // The failure mode worth more than the optimisation: if no free slot carries a
        // usable level, the engine must still get a slot. Handing back nil would push the
        // caller into its steal path and cut a HELD note instead of a released one.
        let chosen = EchoelPolyDDSP.quietestFreeSlot(voiceNotes: [60, -1, 67, -1],
                                                     levels: [0.2, .nan, 0.2, .infinity])
        let message = "Both free slots carry unusable levels, so the level comparison can "
            + "pick nothing — the fallback must still return the lowest free slot (1). "
            + "Returning nil would send the caller stealing a note that is still held."
        XCTAssertEqual(chosen, 1, message)
    }

    func testAShortLevelsArrayStillYieldsAVoice() {
        // Production always passes equal lengths. This pins what happens if that ever stops
        // being true: a slot past the end of `levels` has no level to compare, but it is
        // still FREE, so it must remain allocatable rather than vanish from the search.
        let chosen = EchoelPolyDDSP.quietestFreeSlot(voiceNotes: [60, 64, -1], levels: [0.5])
        let message = "Slot 2 is free but sits past the end of `levels`. It was dropped "
            + "from the search entirely, which loses a usable voice on an array-length "
            + "mismatch instead of degrading to the old lowest-free-index answer."
        XCTAssertEqual(chosen, 2, message)
    }

    func testAnEmptyEngineHasNothingToOffer() {
        XCTAssertNil(EchoelPolyDDSP.quietestFreeSlot(voiceNotes: [], levels: []),
                     "No slots at all cannot produce an index.")
    }

    // MARK: - The wiring (source text — see the header for why)

    func testAllocateVoiceActuallyAsksForTheQuietestTail() throws {
        let source = try Self.dspSource()
        let message = "`EchoelPolyDDSP.allocateVoice` no longer calls `quietestFreeSlot`. "
            + "Everything above this line then tests a function nothing runs, and the reuse "
            + "decision is back to whatever index happened to come first."
        XCTAssertTrue(source.contains("Self.quietestFreeSlot(voiceNotes: voiceNotes, levels: voiceLevels)"),
                      message)
    }

    func testTheOldLowestIndexRuleIsGone() throws {
        let source = try Self.dspSource()
        // ⚠️ A NEGATIVE SCAN CANNOT TELL CODE FROM PROSE. This one nearly failed on the
        // doc comment written in the same commit, which merely NAMED the old rule — the
        // self-disarming-guard trap (#367) running in the other direction: not a guard that
        // cannot fail, but one that fails over a sentence. The fix is on the source side:
        // `quietestFreeSlot`'s doc says "the old lowest-free-index rule" in words and never
        // quotes the call. If you are here because this went red, check first whether a
        // comment reintroduced the literal before assuming the rule itself came back.
        let message = "`voiceNotes.firstIndex(of: -1)` is present in EchoelDDSP.swift again. "
            + "That is the pre-#404 rule; if both it and `quietestFreeSlot` are live, one of "
            + "them is dead code and the next reader cannot tell which one decides. (If it is "
            + "only a comment, reword the comment — see the note above this assertion.)"
        XCTAssertFalse(source.contains("voiceNotes.firstIndex(of: -1)"), message)
    }

    func testTheEngineCanStillSeeHowLoudAVoiceIs() throws {
        let source = try Self.dspSource()
        let message = "The `envelopeLevel` read-only accessor is gone from EchoelDDSP. "
            + "Without it the poly engine cannot fill `voiceLevels`, so the quietest-tail "
            + "rule has nothing to compare."
        XCTAssertTrue(source.contains("public var envelopeLevel: Float { envelopeValue }"),
                      message)
    }

    func testTheComparedLevelIsEnvelopeTimesAmplitude() throws {
        // THE REVIEW FINDING THIS PINS. The first version compared `envelopeLevel` alone
        // and its doc called that "how loud". It is not: the render is
        // `mixed * smoothedGain * envelopeValue`, `smoothedGain` follows `amplitude *
        // patchOutputLevel`, and since #174 a muted role bakes velocity 0 into its notes.
        // So a slot could sit at envelope 0.9 emitting exact silence and be ranked the
        // LOUDEST tail — protected, while an audible one was reused instead. Exactly
        // backwards, on a case this app ships (mute one role, play the others).
        let source = try Self.dspSource()
        let message = "The reuse comparison no longer multiplies the envelope by "
            + "`amplitude`. With the envelope alone the ranking inverts whenever one role "
            + "is muted: a silent slot reads loud and gets spared, an audible one gets the "
            + "re-pitch kink. See the doc on `envelopeLevel` for why it is not loudness."
        XCTAssertTrue(source.contains("voiceLevels[i] = voices[i].envelopeLevel * voices[i].amplitude"),
                      message)
    }

    /// The one place that resolves the source path, so a directory move breaks three tests
    /// with one honest error instead of three misleading ones.
    private static func dspSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/CISmoke
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/Echoelmusic/DSP/EchoelDDSP.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
