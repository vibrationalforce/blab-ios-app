// BioComposerVoiceLeadingTests.swift
// Echoel — H1 wiring (PLAN_HARMONY_CORE.md): VoiceLeader into BioComposer.
//
// Pins the two laws of the slice:
//   • GOLDEN: `Input.voiceLeading` defaults to false and the false path is the
//     legacy path — compose() output is byte-identical with the field omitted,
//     with it explicitly false, and across repeated calls (determinism).
//   • AUDIBILITY: with the switch ON, the pad's chord-to-chord voicings move by
//     FEWER total semitones than the legacy whole-block octave shift (the reason
//     H1 exists), while bass + lead stay identical (only the pad voicing path
//     changed — RNG stream parity is part of the design).
// Plus the bio→control mapping law (coherence → strictness, breathDepth →
// spread, structureSeed → seed) documented on `voiceLeadControl`.

import XCTest
@testable import Echoelmusic

final class BioComposerVoiceLeadingTests: XCTestCase {

    private func input(style: MusicStyle = .jazz,
                       coherence: Float = 0.9,
                       breathDepth: Float = 0.5,
                       seed: UInt64 = 0x5EED,
                       voiceLeading: Bool = false) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: 70, hrvNormalized: 0.5, coherence: coherence,
                          breathPhase: 0, breathDepth: breathDepth,
                          key: MusicalKey(root: 0, scale: .minor),
                          style: style, mode: .studioLocked, lockedTempo: 100,
                          seed: seed, voiceLeading: voiceLeading)
    }

    /// The pad-chord voicings of a take, in section order: `.harmony` notes
    /// grouped by start step, each group as sorted pitches.
    private func padVoicings(_ comp: BioComposition) -> [[Int]] {
        let pads = comp.notes.filter { $0.role == .harmony }
        let grouped = Dictionary(grouping: pads, by: \.startStep)
        return grouped.keys.sorted().compactMap { grouped[$0]?.map(\.pitch).sorted() }
    }

    /// Total semitone movement across consecutive voicings (sorted pairwise
    /// voice matching — the non-crossing assignment, same convention as
    /// `VoiceLeader.movementCost` without the common-tone rebate).
    private func totalMovement(_ voicings: [[Int]]) -> Int {
        guard voicings.count > 1 else { return 0 }
        var total = 0
        for i in 1..<voicings.count {
            let a = voicings[i - 1].sorted()
            let b = voicings[i].sorted()
            total += zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) }
        }
        return total
    }

    // MARK: - Golden: default-false is the legacy path, byte-identical

    func testGolden_sameInputComposesIdenticallyTwice() {
        // Determinism pin around the new field: the same Input (voiceLeading
        // omitted → false) must reproduce the identical composition.
        let a = BioComposer.compose(input())
        let b = BioComposer.compose(input())
        XCTAssertEqual(a, b, "compose must stay deterministic with the H1 field present")
    }

    func testVoiceLeadingOff_matchesLegacyPath() {
        // The new field default-false changes NOTHING: an Input built without
        // naming it equals one with an explicit `voiceLeading: false`, note for
        // note, across genre archetypes (sustained Fläche, arp, block chords).
        for style in [MusicStyle.jazz, .dubTechno, .esotericMeditation, .rock, .eighties] {
            let defaulted = BioComposer.Input(heartRateBPM: 70, hrvNormalized: 0.5,
                                              coherence: 0.9, breathPhase: 0, breathDepth: 0.5,
                                              key: MusicalKey(root: 0, scale: .minor),
                                              style: style, mode: .studioLocked,
                                              lockedTempo: 100, seed: 0x5EED)
            let explicit = input(style: style, voiceLeading: false)
            XCTAssertEqual(BioComposer.compose(defaulted), BioComposer.compose(explicit),
                           "\(style): default voiceLeading must equal explicit false (legacy path)")
        }
    }

    // MARK: - ON: deterministic

    func testVoiceLeadingOn_isDeterministic() {
        let a = BioComposer.compose(input(voiceLeading: true))
        let b = BioComposer.compose(input(voiceLeading: true))
        XCTAssertEqual(a, b, "the voice-led path must be seed-deterministic too")
    }

    // MARK: - ON: the audibility proof — less pad movement than the legacy shift

    func testVoiceLeadingOn_padMovesFewerSemitonesThanLegacyPath() {
        // Jazz: a clear 4-chord 7th-chord progression, block pads (not sustained,
        // not arpeggiated), high coherence → strict leading AND the inner pulse
        // layer dropped (calm > 0.5), so `.harmony` notes are exactly the pad.
        let off = BioComposer.compose(input(voiceLeading: false))
        let on = BioComposer.compose(input(voiceLeading: true))

        let offVoicings = padVoicings(off)
        let onVoicings = padVoicings(on)
        XCTAssertEqual(offVoicings.count, onVoicings.count,
                       "both paths voice the same progression sections")
        XCTAssertGreaterThan(offVoicings.count, 1, "needs a real progression to compare")
        XCTAssertNotEqual(offVoicings, onVoicings, "the switch must actually change the voicings")

        // The point of H1: the voice-led pad travels FEWER total semitones
        // between chords than the parallel whole-block shift.
        XCTAssertLessThan(totalMovement(onVoicings), totalMovement(offVoicings),
                          "VoiceLeader must reduce chord-to-chord pad movement")

        // Design pin: ONLY the pad voicing path changed — bass and lead are
        // note-for-note identical (RNG stream parity: the ON branch consumes
        // no extra draws and emits the same note count per section).
        XCTAssertEqual(off.notes.filter { $0.role == .bass },
                       on.notes.filter { $0.role == .bass },
                       "bass must be untouched by the pad voice-leading")
        XCTAssertEqual(off.notes.filter { $0.role == .lead },
                       on.notes.filter { $0.role == .lead },
                       "lead must be untouched by the pad voice-leading")
        XCTAssertEqual(off.drumSteps, on.drumSteps, "drums must be untouched")
    }

    func testVoiceLeadingOn_staysInKey() {
        // The resolver only transposes chord tones by octaves, so every voice-led
        // note must still satisfy the composer's in-key invariant.
        for style in [MusicStyle.jazz, .classical, .rock, .eighties] {
            let key = MusicalKey(root: 7, scale: .dorian)
            let comp = BioComposer.compose(
                BioComposer.Input(heartRateBPM: 90, hrvNormalized: 0.5, coherence: 0.4,
                                  breathPhase: 0.6, breathDepth: 0.8, key: key,
                                  style: style, mode: .studioLocked, lockedTempo: 110,
                                  seed: 42, voiceLeading: true))
            for note in comp.notes {
                XCTAssertTrue(key.contains(note.pitch),
                              "\(style): voice-led pitch \(note.pitch) must be in key")
            }
        }
    }

    // MARK: - Bio → control mapping (the documented law)

    func testVoiceLeadControl_bioMappingLaw() {
        // OFF → nil (the legacy path sees no control at all).
        XCTAssertNil(BioComposer.voiceLeadControl(for: input(voiceLeading: false)))

        // strictness = 0.6 + 0.4·coherence — settled body leads strictly,
        // floor 0.6 keeps the leading recognizably smooth at zero coherence.
        let calm = BioComposer.voiceLeadControl(for: input(coherence: 1, voiceLeading: true))
        XCTAssertEqual(calm?.strictness ?? -1, 1.0, accuracy: 1e-6)
        let restless = BioComposer.voiceLeadControl(for: input(coherence: 0, voiceLeading: true))
        XCTAssertEqual(restless?.strictness ?? -1, 0.6, accuracy: 1e-6)

        // spread = clamp01(breathDepth) — deep breath opens the voicing.
        let deep = BioComposer.voiceLeadControl(for: input(breathDepth: 2, voiceLeading: true))
        XCTAssertEqual(deep?.spread ?? -1, 1.0, accuracy: 1e-6)

        // seed = structureSeed ?? seed — the skeleton stream owns the inversions.
        var withStructure = input(voiceLeading: true)
        withStructure.structureSeed = 777
        XCTAssertEqual(BioComposer.voiceLeadControl(for: withStructure)?.seed, 777)
        XCTAssertEqual(BioComposer.voiceLeadControl(for: input(seed: 9, voiceLeading: true))?.seed, 9)
    }
}
