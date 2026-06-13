// GenrePatches.swift
// Echoel — the sound character behind each genre. The generative core writes the
// right notes; this gives them the right *timbre* so a take is usable starting
// material in its genre.
//
// LOCATION: this file lives in Sequencer/ (not DSP/) on purpose. The AUv3 target
// globs Sources/Echoelmusic/DSP, and this file depends on MusicStyle (Sequencer/)
// which the AUv3 target does NOT include — putting it in DSP/ breaks the AUv3
// compile ("cannot find type 'MusicStyle'"). The macOS SwiftPM build is one
// module so it would not catch that; the Xcode simulator build does.
//
// IMPORTANT: enum-valued params (noiseColor / spectralShape / envelopeCurve) are
// stored as their EchoelDDSP rawValues, which are Capitalized ("Dark", "Bell",
// "Pink", "Exponential", "Metallic", "Violet"). A lowercase string silently fails
// the enum lookup in SynthPatch.apply(to:) and the param is left unchanged — so
// these MUST match. `GenrePatchesTests` guards exactly that.
//
// Every SynthPatch is constructed in the declared argument order (id, name,
// attack, decay, sustain, release, envelopeCurve, harmonicity, harmonicLevel,
// brightness, noiseLevel, noiseColor, spectralShape, filterCutoff,
// filterResonance, lfoToFilterDepth, filterLFORate, filterLFODepth, reverbMix,
// reverbDecay, vibratoRate, vibratoDepth) — the Xcode iOS archive compiler
// rejects any other order even though macOS swift-build may not.

import Foundation

public extension MusicStyle {

    /// The synth voice sound this genre is generated through. Applied to the
    /// polyphonic voice on Generate so the take sounds like its reference.
    var synthPatch: SynthPatch {
        // Sound-design philosophy (2026-06-12, "make it beautiful"): warm, clean,
        // spacious — built for production-ready loops, not harsh demos. Universal
        // rules: zero noise (it reads as cheap/hiss), Natural/Dark spectral shapes
        // (Metallic/Hollow sound digital), brightness kept moderate, gentle filter
        // resonance, generous reverb for professional space, softer attacks so
        // pads bloom instead of click. Each genre keeps its character, cleaner.
        switch self {
        case .dubTechno:
            return patch("D1", "Dub Chord",
                a: 0.06, d: 0.9, s: 0.45, r: 3.8,
                harm: 0.93, hl: 0.72, bright: 0.16, noise: 0.0, color: "Pink", shape: "Dark",
                cutoff: 720, res: 0.10, lfoAmt: 0.18, lfoRate: 0.12, lfoDepth: 0.30,
                revMix: 0.58, revDecay: 5.5, vibRate: 0, vibDepth: 0)
        case .trap:
            return patch("D2", "Trap Keys",
                a: 0.01, d: 1.0, s: 0.30, r: 2.4,
                harm: 0.90, hl: 0.74, bright: 0.42, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 3200, res: 0.10, lfoAmt: 0.08, lfoRate: 0.18, lfoDepth: 0.18,
                revMix: 0.52, revDecay: 3.6, vibRate: 4, vibDepth: 0.07)
        case .vaporwave:
            return patch("D4", "Vapor Pad",
                a: 0.8, d: 1.6, s: 0.88, r: 4.5,
                harm: 0.92, hl: 0.80, bright: 0.26, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 1500, res: 0.08, lfoAmt: 0.14, lfoRate: 0.08, lfoDepth: 0.30,
                revMix: 0.62, revDecay: 5.5, vibRate: 0, vibDepth: 0)
        case .eighties:
            return patch("D5", "Neon Keys",
                a: 0.04, d: 0.6, s: 0.78, r: 2.2,
                harm: 0.93, hl: 0.78, bright: 0.48, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 3200, res: 0.12, lfoAmt: 0.10, lfoRate: 0.22, lfoDepth: 0.18,
                revMix: 0.48, revDecay: 3.2, vibRate: 4.5, vibDepth: 0.08)
        case .disco:
            return patch("D6", "Velvet Strings",
                a: 0.10, d: 0.8, s: 0.72, r: 2.0,
                harm: 0.92, hl: 0.80, bright: 0.42, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 2800, res: 0.12, lfoAmt: 0.10, lfoRate: 0.24, lfoDepth: 0.22,
                revMix: 0.46, revDecay: 3.0, vibRate: 5, vibDepth: 0.07)
        case .synthwave:
            return patch("D7", "Neon Lead",
                a: 0.02, d: 0.5, s: 0.72, r: 1.8,
                harm: 0.94, hl: 0.78, bright: 0.56, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 3600, res: 0.16, lfoAmt: 0.18, lfoRate: 0.18, lfoDepth: 0.28,
                revMix: 0.44, revDecay: 3.4, vibRate: 4.5, vibDepth: 0.10)
        case .earlySynth:
            return patch("D8", "Berlin Seq",
                a: 0.02, d: 0.5, s: 0.55, r: 1.6,
                harm: 0.92, hl: 0.76, bright: 0.40, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 2200, res: 0.18, lfoAmt: 0.30, lfoRate: 0.45, lfoDepth: 0.45,
                revMix: 0.46, revDecay: 3.6, vibRate: 0, vibDepth: 0)
        case .futuristic:
            return patch("D9", "Crystal Air",
                a: 0.10, d: 1.0, s: 0.70, r: 3.2,
                harm: 0.88, hl: 0.78, bright: 0.58, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 3800, res: 0.10, lfoAmt: 0.12, lfoRate: 0.12, lfoDepth: 0.22,
                revMix: 0.58, revDecay: 4.8, vibRate: 0, vibDepth: 0)
        case .sciFi:
            return patch("DA", "Nebula",
                a: 0.5, d: 1.4, s: 0.78, r: 4.0,
                harm: 0.86, hl: 0.80, bright: 0.34, noise: 0.0, color: "Pink", shape: "Dark",
                cutoff: 1900, res: 0.12, lfoAmt: 0.22, lfoRate: 0.10, lfoDepth: 0.40,
                revMix: 0.62, revDecay: 6.0, vibRate: 0, vibDepth: 0)
        case .psytrance:
            return patch("DB", "Psy Pluck",
                a: 0.01, d: 0.4, s: 0.55, r: 1.0,
                harm: 0.94, hl: 0.78, bright: 0.56, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 3400, res: 0.22, lfoAmt: 0.26, lfoRate: 0.55, lfoDepth: 0.45,
                revMix: 0.40, revDecay: 2.6, vibRate: 0, vibDepth: 0)
        case .esotericMeditation:
            return patch("DC", "Deep Drone",
                a: 1.4, d: 1.8, s: 0.92, r: 6.0,
                harm: 0.90, hl: 0.84, bright: 0.18, noise: 0.0, color: "Pink", shape: "Dark",
                cutoff: 950, res: 0.06, lfoAmt: 0.10, lfoRate: 0.05, lfoDepth: 0.35,
                revMix: 0.66, revDecay: 7.0, vibRate: 0, vibDepth: 0)
        case .selfObservation:
            return patch("D3", "Calm Pad",
                a: 1.0, d: 1.3, s: 0.88, r: 4.2,
                harm: 0.92, hl: 0.80, bright: 0.22, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 1300, res: 0.07, lfoAmt: 0.12, lfoRate: 0.08, lfoDepth: 0.30,
                revMix: 0.58, revDecay: 5.5, vibRate: 0, vibDepth: 0)
        }
    }

    /// Builds a SynthPatch in the strict declared argument order. The short
    /// `suffix` becomes a stable UUID so a genre's patch identity survives
    /// relaunch (and is distinct per genre).
    private func patch(_ suffix: String, _ name: String,
                       a: Float, d: Float, s: Float, r: Float,
                       harm: Float, hl: Float, bright: Float, noise: Float,
                       color: String, shape: String,
                       cutoff: Float, res: Float, lfoAmt: Float, lfoRate: Float, lfoDepth: Float,
                       revMix: Float, revDecay: Float, vibRate: Float, vibDepth: Float) -> SynthPatch {
        SynthPatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(suffix)") ?? UUID(),
            name: name,
            attack: a, decay: d, sustain: s, release: r,
            envelopeCurve: "Exponential",
            harmonicity: harm, harmonicLevel: hl, brightness: bright,
            noiseLevel: noise, noiseColor: color, spectralShape: shape,
            filterCutoff: cutoff, filterResonance: res, lfoToFilterDepth: lfoAmt,
            filterLFORate: lfoRate, filterLFODepth: lfoDepth,
            reverbMix: revMix, reverbDecay: revDecay,
            vibratoRate: vibRate, vibratoDepth: vibDepth
        )
    }
}
