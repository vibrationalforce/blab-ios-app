//
//  RollChordStamp.swift
//  Echoelmusic — Sequencer (Piano Roll Pro, slice R2)
//
//  The Echoel twist on Ableton's chord stamp: tapping a roll cell drops not a
//  single note but a whole VOICE-LED, COHERENCE-CHOSEN chord — the same harmonic
//  brain that writes the composition (ChordSuggest H2 + VoiceLeader H1) placed by
//  the player's finger. A calm body (high coherence) stamps the plain functional
//  chord; an agitated body (low coherence) reaches for a borrowed / remoter colour.
//
//  Pure, deterministic value logic — no audio, no UI, no state. Given the tapped
//  anchor, the session key, the current coherence and a seed, it returns the Notes
//  to insert. The Piano Roll wires it into a long-press as ONE undoable edit,
//  reading the live coherence ONLY in the gesture handler (never in the roll body —
//  the 10 Hz menu-freeze law). Fully unit-tested on every platform.
//

import Foundation

public enum RollChordStamp {

    /// Own salted stream so the stamp's note-id fold never collides with the
    /// journey / voice-leader seeds it also feeds. ("ROLLCHRD")
    public static let seedSalt: UInt64 = 0x524F_4C4C_4348_5244

    /// The voice-led, coherence-chosen chord to insert when a roll cell is tapped.
    ///
    /// - `anchorPitch`: the tapped MIDI row — the chord is voiced at/above it.
    /// - `startTick` / `lengthTicks`: where and how long every chord note sits.
    /// - `key`: the session tonality (the chord is diatonic to it, plus borrowings).
    /// - `coherence`: [0..1] body coherence — widens the harmonic search at low
    ///   coherence (more adventurous), narrows to the plain function when calm.
    /// - `seed`: makes the pick + note identities reproducible.
    /// - `registerSpan`: how many semitones above the anchor the voicing may use.
    ///
    /// Returns 1…n Notes sharing `startTick`/`lengthTicks`/`velocity`, all within
    /// `[anchorPitch, anchorPitch + registerSpan]` (clamped to MIDI 0…127). A
    /// pathological empty key yields a single note on the tapped row (honest
    /// fallback — a tap always leaves at least the note you touched).
    public static func stamp(
        anchorPitch: Int,
        startTick: Int,
        lengthTicks: Int,
        velocity: Float = 0.8,
        key: MusicalKey,
        coherence: Float,
        seed: UInt64,
        registerSpan: Int = 12
    ) -> [Note] {
        let safeLen = Swift.max(1, lengthTicks)
        // Fail-neutral on a non-finite velocity (repo precedent), then floor so the
        // chord is always audible.
        let vel = Swift.min(Swift.max(velocity.isFinite ? velocity : 0.8, 0.05), 1)
        let anchor = Swift.min(Swift.max(anchorPitch, 0), 127)
        // Clamp the span BEFORE the add so `anchor + span` can never overflow.
        let span = Swift.min(127, Swift.max(1, registerSpan))
        let register = anchor ... Swift.min(127, anchor + span)

        // A separate stream for the deterministic note-id fold (the journey and
        // voice-leader build their OWN rngs from `seed`, so no stream collision).
        var idRNG = SeededRNG(seed: seed ^ seedSalt)

        // Coherence + seed pick ONE diatonic, voice-leadable chord.
        guard let candidate = ChordSuggest.journey(length: 1, in: key,
                                                    coherence: coherence,
                                                    register: register,
                                                    seed: seed).first else {
            return [Note(id: foldUUID(&idRNG), pitch: anchor,
                         startTick: startTick, lengthTicks: safeLen, velocity: vel)]
        }

        let pitchClasses = ChordSuggest.pitchClasses(of: candidate, in: key)
        // Fresh stamp: no previous voicing to lead from (an empty `from` makes the
        // voice count the chord's own size — the FULL chord, not a single led voice).
        // The register (anchored at the tapped row) is what places it.
        let voicing = VoiceLeader.resolve(from: [], to: pitchClasses,
                                          register: register,
                                          strictness: 1, spread: 0.5, seed: seed)
        let pitches = voicing.isEmpty ? [anchor] : voicing
        return pitches.map { p in
            Note(id: foldUUID(&idRNG), pitch: p,
                 startTick: startTick, lengthTicks: safeLen, velocity: vel)
        }
    }

    /// Deterministic UUID from the RNG (same fold as `BioComposer.nextUUID`), so a
    /// stamp — note identities included — is reproducible from its seed.
    private static func foldUUID(_ rng: inout SeededRNG) -> UUID {
        let hi = rng.next()
        let lo = rng.next()
        func byte(_ v: UInt64, _ i: Int) -> UInt8 { UInt8((v >> (UInt64(i) * 8)) & 0xFF) }
        return UUID(uuid: (
            byte(hi, 7), byte(hi, 6), byte(hi, 5), byte(hi, 4),
            byte(hi, 3), byte(hi, 2), byte(hi, 1), byte(hi, 0),
            byte(lo, 7), byte(lo, 6), byte(lo, 5), byte(lo, 4),
            byte(lo, 3), byte(lo, 2), byte(lo, 1), byte(lo, 0)
        ))
    }
}
