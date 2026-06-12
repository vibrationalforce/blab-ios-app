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
        switch self {
        case .dubTechno:
            return patch("D1", "Dub Chord",
                a: 0.04, d: 0.6, s: 0.30, r: 2.5,
                harm: 0.85, hl: 0.70, bright: 0.18, noise: 0.02, color: "Pink", shape: "Dark",
                cutoff: 800, res: 0.12, lfoAmt: 0.20, lfoRate: 0.15, lfoDepth: 0.35,
                revMix: 0.50, revDecay: 4.0, vibRate: 0, vibDepth: 0)
        case .trap:
            return patch("D2", "Trap Bell",
                a: 0.005, d: 1.2, s: 0.15, r: 1.5,
                harm: 0.60, hl: 0.75, bright: 0.70, noise: 0.0, color: "Pink", shape: "Bell",
                cutoff: 5000, res: 0.12, lfoAmt: 0.10, lfoRate: 0.20, lfoDepth: 0.20,
                revMix: 0.40, revDecay: 2.8, vibRate: 4, vibDepth: 0.10)
        case .vaporwave:
            return patch("D4", "Vapor Pad",
                a: 0.6, d: 1.2, s: 0.80, r: 3.5,
                harm: 0.85, hl: 0.80, bright: 0.30, noise: 0.01, color: "Pink", shape: "Natural",
                cutoff: 1500, res: 0.10, lfoAmt: 0.15, lfoRate: 0.10, lfoDepth: 0.30,
                revMix: 0.55, revDecay: 4.5, vibRate: 0, vibDepth: 0)
        case .eighties:
            return patch("D5", "Neon Keys",
                a: 0.02, d: 0.4, s: 0.70, r: 1.2,
                harm: 0.92, hl: 0.80, bright: 0.60, noise: 0.0, color: "Pink", shape: "Bright",
                cutoff: 4500, res: 0.18, lfoAmt: 0.10, lfoRate: 0.25, lfoDepth: 0.20,
                revMix: 0.35, revDecay: 2.0, vibRate: 5, vibDepth: 0.12)
        case .disco:
            return patch("D6", "String Stab",
                a: 0.04, d: 0.5, s: 0.60, r: 1.0,
                harm: 0.90, hl: 0.82, bright: 0.55, noise: 0.0, color: "Pink", shape: "Bright",
                cutoff: 4000, res: 0.20, lfoAmt: 0.12, lfoRate: 0.30, lfoDepth: 0.25,
                revMix: 0.30, revDecay: 1.8, vibRate: 5.5, vibDepth: 0.10)
        case .synthwave:
            return patch("D7", "Neon Lead",
                a: 0.01, d: 0.3, s: 0.65, r: 0.8,
                harm: 0.95, hl: 0.80, bright: 0.72, noise: 0.0, color: "Pink", shape: "Bright",
                cutoff: 5000, res: 0.25, lfoAmt: 0.20, lfoRate: 0.20, lfoDepth: 0.30,
                revMix: 0.30, revDecay: 2.2, vibRate: 5, vibDepth: 0.15)
        case .earlySynth:
            return patch("D8", "Berlin Seq",
                a: 0.005, d: 0.35, s: 0.40, r: 0.6,
                harm: 0.90, hl: 0.78, bright: 0.50, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 2600, res: 0.30, lfoAmt: 0.35, lfoRate: 0.50, lfoDepth: 0.50,
                revMix: 0.35, revDecay: 2.5, vibRate: 0, vibDepth: 0)
        case .futuristic:
            return patch("D9", "Crystal Air",
                a: 0.05, d: 0.8, s: 0.60, r: 2.5,
                harm: 0.70, hl: 0.78, bright: 0.80, noise: 0.0, color: "Pink", shape: "Bright",
                cutoff: 6000, res: 0.12, lfoAmt: 0.12, lfoRate: 0.15, lfoDepth: 0.25,
                revMix: 0.50, revDecay: 3.8, vibRate: 0, vibDepth: 0)
        case .sciFi:
            return patch("DA", "Nebula",
                a: 0.3, d: 1.0, s: 0.70, r: 3.0,
                harm: 0.65, hl: 0.80, bright: 0.40, noise: 0.03, color: "Violet", shape: "Metallic",
                cutoff: 2200, res: 0.18, lfoAmt: 0.25, lfoRate: 0.12, lfoDepth: 0.45,
                revMix: 0.55, revDecay: 5.0, vibRate: 0, vibDepth: 0)
        case .psytrance:
            return patch("DB", "Psy Roll",
                a: 0.005, d: 0.2, s: 0.50, r: 0.4,
                harm: 0.95, hl: 0.80, bright: 0.70, noise: 0.0, color: "Pink", shape: "Bright",
                cutoff: 4800, res: 0.35, lfoAmt: 0.30, lfoRate: 0.60, lfoDepth: 0.50,
                revMix: 0.25, revDecay: 1.5, vibRate: 0, vibDepth: 0)
        case .esotericMeditation:
            return patch("DC", "Esoteric Drone",
                a: 1.2, d: 1.5, s: 0.90, r: 5.0,
                harm: 0.80, hl: 0.85, bright: 0.20, noise: 0.02, color: "Pink", shape: "Dark",
                cutoff: 1000, res: 0.07, lfoAmt: 0.10, lfoRate: 0.06, lfoDepth: 0.40,
                revMix: 0.60, revDecay: 6.0, vibRate: 0, vibDepth: 0)
        case .selfObservation:
            return patch("D3", "Calm Pad",
                a: 0.8, d: 1.0, s: 0.85, r: 3.5,
                harm: 0.90, hl: 0.80, bright: 0.22, noise: 0.015, color: "Pink", shape: "Natural",
                cutoff: 1200, res: 0.08, lfoAmt: 0.12, lfoRate: 0.10, lfoDepth: 0.30,
                revMix: 0.50, revDecay: 4.5, vibRate: 0, vibDepth: 0)
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
