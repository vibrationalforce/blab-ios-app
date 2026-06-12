// GenrePatches.swift
// Echoel — the sound character behind each genre. The generative core writes the
// right notes and rhythm; this gives them the right *timbre* so a take actually
// sounds like its reference:
//
//   • Dub Techno — a warm, dark chord washed in a long reverb tail (the
//     delay-drenched Basic Channel / Echochord stab).
//   • Trap       — a bright, inharmonic bell with cinematic space (Metro Boomin /
//     808 Mafia lead); the low 808 root notes read as sub underneath it.
//   • Self-Observation — a soft, slow warm pad, long and immersive, for breath-
//     paced meditation.
//
// IMPORTANT: enum-valued params (noiseColor / spectralShape / envelopeCurve) are
// stored as their EchoelDDSP rawValues, which are Capitalized ("Dark", "Bell",
// "Pink", "Exponential"). A lowercase string silently fails the enum lookup in
// SynthPatch.apply(to:) and the param is left unchanged — so these MUST match.
// `GenrePatchesTests` guards exactly that.
//
// Constructed in the SynthPatch declared argument order (id, name, attack, decay,
// sustain, release, envelopeCurve, harmonicity, harmonicLevel, brightness,
// noiseLevel, noiseColor, spectralShape, filterCutoff, filterResonance,
// lfoToFilterDepth, filterLFORate, filterLFODepth, reverbMix, reverbDecay,
// vibratoRate, vibratoDepth) — the Xcode iOS archive compiler rejects any other
// order even though macOS swift-build may not.

import Foundation

public extension MusicStyle {

    /// The synth voice sound this genre is generated through. Applied to the
    /// polyphonic voice on Generate so the take sounds like its reference.
    var synthPatch: SynthPatch {
        switch self {
        case .dubTechno:
            return SynthPatch(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1") ?? UUID(),
                name: "Dub Chord",
                attack: 0.04, decay: 0.6, sustain: 0.30, release: 2.5,
                envelopeCurve: "Exponential",
                harmonicity: 0.85, harmonicLevel: 0.70, brightness: 0.18,
                noiseLevel: 0.02, noiseColor: "Pink", spectralShape: "Dark",
                filterCutoff: 800, filterResonance: 0.12, lfoToFilterDepth: 0.20,
                filterLFORate: 0.15, filterLFODepth: 0.35,
                reverbMix: 0.50, reverbDecay: 4.0,
                vibratoRate: 0, vibratoDepth: 0
            )
        case .trap:
            return SynthPatch(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D2") ?? UUID(),
                name: "Trap Bell",
                attack: 0.005, decay: 1.2, sustain: 0.15, release: 1.5,
                envelopeCurve: "Exponential",
                harmonicity: 0.60, harmonicLevel: 0.75, brightness: 0.70,
                noiseLevel: 0.0, noiseColor: "Pink", spectralShape: "Bell",
                filterCutoff: 5000, filterResonance: 0.12, lfoToFilterDepth: 0.10,
                filterLFORate: 0.20, filterLFODepth: 0.20,
                reverbMix: 0.40, reverbDecay: 2.8,
                vibratoRate: 4, vibratoDepth: 0.10
            )
        case .selfObservation:
            return SynthPatch(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D3") ?? UUID(),
                name: "Calm Pad",
                attack: 0.8, decay: 1.0, sustain: 0.85, release: 3.5,
                envelopeCurve: "Exponential",
                harmonicity: 0.90, harmonicLevel: 0.80, brightness: 0.22,
                noiseLevel: 0.015, noiseColor: "Pink", spectralShape: "Natural",
                filterCutoff: 1200, filterResonance: 0.08, lfoToFilterDepth: 0.12,
                filterLFORate: 0.10, filterLFODepth: 0.30,
                reverbMix: 0.50, reverbDecay: 4.5,
                vibratoRate: 0, vibratoDepth: 0
            )
        }
    }
}
