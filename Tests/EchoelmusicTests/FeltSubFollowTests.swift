// FeltSubFollowTests.swift
// Echoel — the felt sub (the "Vibration" dimension) is reconciled every tick to the
// lowest sounding note, an octave down. These pin WHICH note it is allowed to follow.
//
// THE DEFECT THEY EXIST FOR, and the honest history of it. Pulling the Bass fader to 0
// bakes velocity 0 into the bass notes at compose time. Those notes still enter the
// roll's `active` set — correctly, because `active` is note BOOKKEEPING (ties, releases,
// un-mute) and must not depend on level. But the felt sub was derived from `active`
// without looking at level, so it kept droning an octave below a note nobody could hear.
//
// It was INVISIBLE until 6f2932d. Before that fix the bio pulse overwrote every voice's
// amplitude, so a velocity-0 bass note sounded anyway and the sub matched something
// audible. Making the faders real is what exposed this — a fix uncovering the next
// defect is the normal shape of the thing, not a regression in it.
//
// Note also what this is NOT: I first recorded this as "SubBassVoice discards velocity".
// That is true of `noteOn(pitch:velocity:)` but irrelevant here — it only applies when a
// sub-bass LANE is bound as the primary kind voice. In a normal generated take the bass
// ROLE plays through the poly voice (`outputVoice(for:)` sends .bass and .harmony to
// `voice`), where the fader has worked since 6f2932d. The felt sub is a separate layer
// with its own gain, and pitch-only by design. Tracing the routing refuted my own note.

#if canImport(SwiftUI) && canImport(AVFoundation) && canImport(Accelerate)
import XCTest
import Foundation
@testable import Echoelmusic

@MainActor
final class FeltSubFollowTests: XCTestCase {

    private func note(_ pitch: Int, _ velocity: Float) -> Note {
        Note(pitch: pitch, startStep: 0, lengthSteps: 4, velocity: velocity)
    }

    /// THE DEFECT. A muted bass note must not anchor the felt sub — otherwise pulling the
    /// Bass fader down leaves a sub droning under silence.
    func testFeltSub_ignoresAMutedNote_andFollowsTheLowestAUDIBLEOneInstead() {
        let pitch = PianoRollModel.feltSubPitch(forActive: [note(36, 0), note(60, 0.6)],
                                                laneAudible: true, hasKindVoice: false)
        XCTAssertEqual(pitch, 48, "the muted 36 must be skipped; 60 − 12 = 48")
    }

    /// Every note muted ⇒ no sub at all. This is the founder-facing case: all faders down
    /// must mean silence, not a bass drone.
    func testFeltSub_isSilentWhenEveryNoteIsMuted() {
        XCTAssertNil(PianoRollModel.feltSubPitch(forActive: [note(36, 0), note(43, 0)],
                                                 laneAudible: true, hasKindVoice: false))
    }

    /// NEGATIVE CONTROL — the ordinary case is unchanged. If this ever goes red alongside
    /// the two above, the filter is too aggressive rather than the mute being honoured.
    func testFeltSub_followsTheLowestNoteAnOctaveDown_whenNothingIsMuted() {
        XCTAssertEqual(PianoRollModel.feltSubPitch(forActive: [note(48, 0.7), note(36, 0.5)],
                                                   laneAudible: true, hasKindVoice: false),
                       24, "lowest of {48, 36} is 36 → 36 − 12 = 24")
    }

    /// A QUIET note is not a MUTED note. The composer's humanizers clamp velocity to a
    /// 0.05 floor, so the threshold has to sit well below that or genuinely soft passages
    /// would silently lose their sub.
    func testFeltSub_stillFollowsAVeryQuietNote_becauseQuietIsNotMuted() {
        XCTAssertEqual(PianoRollModel.feltSubPitch(forActive: [note(36, 0.05)],
                                                   laneAudible: true, hasKindVoice: false),
                       24, "0.05 is the composer's softest real note, not a mute")
    }

    /// The two pre-existing suppressions must survive the change: a muted LANE and a bound
    /// kind voice both mean no doubling sub, whatever the notes say.
    func testFeltSub_staysSuppressedForAMutedLaneAndForABoundKindVoice() {
        XCTAssertNil(PianoRollModel.feltSubPitch(forActive: [note(36, 0.9)],
                                                 laneAudible: false, hasKindVoice: false),
                     "a muted lane fires no attacks, so it must not drive the sub either")
        XCTAssertNil(PianoRollModel.feltSubPitch(forActive: [note(36, 0.9)],
                                                 laneAudible: true, hasKindVoice: true),
                     "a kit or sub-bass lane IS the instrument — no octave-doubled sub")
    }

    /// An empty chord is not a special case, but it is the one a tick hits between phrases,
    /// so pin it rather than leaving it to the `min()` of an empty collection.
    func testFeltSub_isSilentOnAnEmptyChord() {
        XCTAssertNil(PianoRollModel.feltSubPitch(forActive: [],
                                                 laneAudible: true, hasKindVoice: false))
    }

    /// THE BOUNDARY ITSELF. The comparison is strict, so a note sitting exactly ON the floor
    /// counts as muted. Untested, that is the kind of off-by-one nobody notices until a fader
    /// lands on the grid value that produces it.
    func testFeltSub_treatsANoteExactlyOnTheFloorAsMuted() {
        XCTAssertNil(PianoRollModel.feltSubPitch(forActive: [note(36, 0.001)],
                                                 laneAudible: true, hasKindVoice: false),
                     "the floor comparison is strict: 0.001 is muted, not the quietest audible")
        XCTAssertEqual(PianoRollModel.feltSubPitch(forActive: [note(36, 0.0011)],
                                                   laneAudible: true, hasKindVoice: false),
                       24, "just above the floor is audible")
    }

    /// A NaN velocity now EXCLUDES the note, where it previously anchored the sub — `NaN > x`
    /// is false. That is a real behaviour change riding along with this fix, and it is
    /// reachable rather than theoretical: `Note.velocity`'s clamp `min(max(v, 0), 1)` returns
    /// NaN for a NaN input (task #176), because `max(NaN, 0)` is NaN by argument order. Pinned
    /// so the improvement is deliberate and cannot silently flip back.
    func testFeltSub_excludesANaNVelocityRatherThanFollowingIt() {
        let nan = Note(pitch: 24, startStep: 0, lengthSteps: 4, velocity: .nan)
        XCTAssertEqual(PianoRollModel.feltSubPitch(forActive: [nan, note(60, 0.6)],
                                                   laneAudible: true, hasKindVoice: false),
                       48, "a NaN-velocity note must not win the min() and drag the sub down")
    }
}
#endif
