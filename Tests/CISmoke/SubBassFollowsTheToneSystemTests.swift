// SubBassFollowsTheToneSystemTests.swift
// Echoel — #312. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ THE DEFECT THIS PINS: the felt sub doubles the lowest sounding note an octave down, so
// it carries that note's PITCH CLASS — but it was the one pitched voice `applyTuning()` did
// not hand the tone system's retune table to. With a non-12-TET system selected (Maqām
// Bayātī, Gamelan Pélog, just intonation, meantone …) every melodic voice moved and the sub
// stayed on plain 12-TET, up to ±50 cents away, beating against the fundamental. Founder,
// 2026-07-31: "Bass teilweise nicht in tune" — and "teilweise" is precisely the signature:
// 12-TET is the default and its table is all zeros, so the fault only exists once a
// deviating system is chosen, and then only on the pitch classes that actually deviate.
//
// ⛔ THE JUSTIFICATION THAT KEPT IT ALIVE, written down so it cannot come back: the comment
// in `applyTuning()` said the sub's absence from the fan was "correct" because
// `SubBassVoice` "has no such method". That is a fact about the API standing in for a
// reason about behaviour — and the very same sentence had already been proven wrong once,
// two lines up, when the lead was found missing for exactly the same reason.
//
// WHAT EACH HALF CAN AND CANNOT SHOW:
//   · the numeric tests run the real mapping (`SubBassVoice.feltFrequency`) and are a true
//     behavioural check of the maths — including that 12-TET stays bit-identical, which is
//     what makes the unconditional fan safe;
//   · the fan test reads SOURCE TEXT, because `applyTuning()` is a private method on a
//     SwiftUI view this bundle cannot build. Weaker than behavioural, stronger than nothing,
//     and it is the link that was actually broken.

import Foundation
import XCTest
@testable import Echoelmusic

// `@MainActor` on the case, not per test: `SubBassVoice` is a `@MainActor @Observable`
// class, so constructing one from a nonisolated test body is a Swift 6 error. Same shape as
// `AutosaveSlotTests` / `LaunchGuardSmokeTests`, which this bundle already proves compiles.
@MainActor
final class SubBassFollowsTheToneSystemTests: XCTestCase {

    private static let twelveTET = [Float](repeating: 0, count: 12)

    /// A above the sub band's own reference: MIDI 45 = A2 = 110 Hz at A4 = 440, and it sits
    /// inside 28…180 Hz so no fold runs and the number is the raw mapping.
    func testTwelveTETIsBitIdenticalToTheOldMapping() {
        let f = SubBassVoice.feltFrequency(forMIDINote: 45, a4Hz: 440, cents: Self.twelveTET)
        XCTAssertEqual(f, 110, accuracy: 0.001, """
            The 12-TET table (all zeros) changed the sub's pitch. It must not: 12-TET is the \
            default tone system, so the #312 retune fan is only safe to apply unconditionally \
            as long as an all-zero table is exactly a no-op.
            """)
    }

    /// The whole point of #312: a deviating degree must actually move the sub.
    func testADeviatingPitchClassMovesTheSubByExactlyThatMuch() {
        var cents = Self.twelveTET
        cents[9] = -50            // pitch class A — the class of MIDI 45
        let retuned = SubBassVoice.feltFrequency(forMIDINote: 45, a4Hz: 440, cents: cents)
        let plain   = SubBassVoice.feltFrequency(forMIDINote: 45, a4Hz: 440, cents: Self.twelveTET)
        let moved   = 1200 * log2(Double(retuned) / Double(plain))

        XCTAssertEqual(moved, -50, accuracy: 0.05, """
            A −50-cent degree moved the sub by \(moved) cents instead of −50. Half a semitone \
            is the worst case in the shipped library (Maqām Bayātī's neutral second, Gamelan \
            Pélog) and it is the case the founder can hear as beating on the fundamental — \
            if this is off, the sub is following a different intonation from the pad it doubles.
            """)
    }

    /// The retune is applied BEFORE the octave fold. Order matters and is easy to get wrong:
    /// folding is by whole octaves and therefore transparent to a cent offset, whereas
    /// retuning after the fold could push a note that was just brought into the band back out
    /// of it — and then the final clamp, not the music, would decide the pitch.
    func testTheFoldPreservesTheRetunedPitchClass() {
        var cents = Self.twelveTET
        cents[9] = -50
        // MIDI 69 = A4 = 440 Hz — two folds above the band, same pitch class as MIDI 45.
        let folded = SubBassVoice.feltFrequency(forMIDINote: 69, a4Hz: 440, cents: cents)
        let inBand = SubBassVoice.feltFrequency(forMIDINote: 45, a4Hz: 440, cents: cents)

        XCTAssertEqual(folded, inBand, accuracy: 0.001, """
            A note folded into the felt band no longer lands on the same retuned frequency as \
            the same pitch class that needed no fold. Either the cents are applied after the \
            fold, or the fold is not by whole octaves — both turn the sub into a drone whose \
            pitch is decided by the 28/180 Hz clamp instead of by the music.
            """)
        XCTAssertTrue(folded >= 28 && folded <= 180, """
            The retuned, folded sub left the felt band (\(folded) Hz). The band exists so the \
            sub can be FELT; outside it the note is either inaudible or no longer a sub.
            """)
    }

    /// Concert pitch and tone system are independent axes and must compose, not overwrite.
    func testTheRetuneComposesWithConcertPitch() {
        var cents = Self.twelveTET
        cents[9] = -50
        let at432 = SubBassVoice.feltFrequency(forMIDINote: 45, a4Hz: 432, cents: cents)
        let expected = 432.0 * pow(2.0, -2.0) * pow(2.0, -50.0 / 1200.0)

        XCTAssertEqual(Double(at432), expected, accuracy: 0.01, """
            A=432 and a −50-cent degree did not compose. They are two independent tunings — \
            the Kammerton moves the whole instrument, the tone system moves one degree within \
            it — and a voice that applies only one of them is out of tune with the rest in \
            exactly the way #114 and #312 each found separately.
            """)
    }

    /// THE RENDER-SIDE half of the size guard, and the one that actually protects the audio
    /// thread: the mapping indexes the table by pitch class, so a short table would trap
    /// mid-render. It falls back to no deviation rather than reading out of bounds.
    ///
    /// Tested here rather than only at the setter because this is the branch a future
    /// caller could reach without going through `setTuningCents` at all.
    func testTheMappingIgnoresAMalformedTableInsteadOfIndexingIntoIt() {
        let short = SubBassVoice.feltFrequency(forMIDINote: 45, a4Hz: 440, cents: [50, 50, 50])
        XCTAssertEqual(short, 110, accuracy: 0.001, """
            A 3-entry table was indexed instead of ignored. The read happens on the render \
            thread, where an out-of-bounds index is a crash in the audio callback — the one \
            place this app cannot recover from. No deviation is the only safe fallback.
            """)
    }

    /// The CONTROL-SIDE half: the setter must reject a wrong-size table rather than partially
    /// apply it — its copy loop writes 12 entries unconditionally, so a short array would
    /// trap on the main actor. Pinned via the debug seam so the guard is observable rather
    /// than a silent branch; the blocking bundle is built `-configuration Debug` (`ci.yml`).
    func testTheSetterRejectsAWrongSizedTableRatherThanPartiallyApplyingIt() {
        let voice = SubBassVoice()
        voice.setTuningCents([Float](repeating: 7, count: 12))
        XCTAssertEqual(voice.lastTuningCentsForTests?.count, 12,
                       "A well-formed 12-entry table was not accepted.")

        voice.setTuningCents([0, 0, 0])
        let survivor = voice.lastTuningCentsForTests?.first ?? -1
        XCTAssertEqual(survivor, 7, accuracy: 0.001, """
            A 3-entry table was accepted, so the last good tuning was lost (or worse, the \
            copy loop trapped). Anything but exactly 12 entries must leave the voice on the \
            tuning it already had.
            """)
    }

    /// The link that was actually broken. `applyTuning()` is private on a SwiftUI view this
    /// bundle cannot build, so this reads source text — the same shape as
    /// `SoundPanelPresetBarTests` and `NoDoorlessStudioViewsTests`.
    func testTheStudioFansTheToneSystemToTheSub() throws {
        let code = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(code.contains("subBass.setTuningCents("), """
            `applyTuning()` no longer hands the tone system's retune table to the felt sub. \
            Every other pitched voice gets it, so the sub would once again play plain 12-TET \
            against a retuned pad — up to ±50 cents apart, on the one voice where beating is \
            least forgiving. This is #312; do not remove the fan without removing the sub.
            """)
    }

    // MARK: - helpers

    private func source(_ path: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than reporting \
                a green this file did not earn.
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
