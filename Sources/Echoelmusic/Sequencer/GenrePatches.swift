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
// these MUST match. `GenrePatchesTests` guards exactly that. The same applies to
// `timbre` — it must equal an `EchoelDDSP.InstrumentTimbre` rawValue exactly
// ("Violin", "Cello", "Clarinet", "Oboe", "Flute", "Trumpet") or the profile is
// silently ignored.
//
// Every SynthPatch is constructed in the declared argument order (id, name,
// attack, decay, sustain, release, envelopeCurve, harmonicity, harmonicLevel,
// brightness, noiseLevel, noiseColor, spectralShape, filterCutoff,
// filterResonance, lfoToFilterDepth, filterLFORate, filterLFODepth, reverbMix,
// reverbDecay, vibratoRate, vibratoDepth) — the Xcode iOS archive compiler
// rejects any other order even though macOS swift-build may not.
//
// SOUND CYCLE 1 (2026-07-02, "klingt nicht nach richtiger Musik"): the engine
// already ships real per-harmonic instrument spectra (EchoelDDSP.instrumentProfile
// — violin/cello/clarinet/oboe/flute/trumpet) that ONLY the acoustic factory
// patches used; NO genre tapped them, so every genre was the same clean sine
// stack. This cycle (a) routes the acoustic-leaning genres through those real
// instrument spectra (moderate blend so the genre character survives), (b) adds a
// UNISON stack (thicker/ensemble, the classic thin→wide lever) to the pad/lead
// genres, and (c) adds a small breath/air NOISE floor to acoustic + pad voices
// (real strings/reeds/flutes have one; leads stay clean so noise doesn't read as
// hiss). All pure data — no DSP or audio-thread changes.

import Foundation

public extension MusicStyle {

    /// The synth voice sound this genre is generated through. Applied to the
    /// polyphonic voice on Generate so the take sounds like its reference.
    var synthPatch: SynthPatch {
        // Sound-design philosophy (2026-06-12, "make it beautiful"): warm, clean,
        // spacious — built for production-ready loops, not harsh demos. Universal
        // rules: Natural/Dark spectral shapes (Metallic/Hollow sound digital),
        // brightness kept moderate, gentle filter resonance, generous reverb for
        // professional space, softer attacks so pads bloom instead of click. Each
        // genre keeps its character, cleaner. SOUND CYCLE 1 layers real instrument
        // spectra + unison width + a breath/air noise floor on top (see header).
        switch self {
        case .dubTechno:
            return patch("D1", "Dub Chord",
                a: 0.06, d: 0.9, s: 0.45, r: 3.8,
                harm: 0.93, hl: 0.72, bright: 0.16, noise: 0.0, color: "Pink", shape: "Dark",
                cutoff: 720, res: 0.10, lfoAmt: 0.18, lfoRate: 0.12, lfoDepth: 0.30,
                revMix: 0.58, revDecay: 5.5, vibRate: 0, vibDepth: 0,
                uni: 2, det: 8)                                  // subtle width on the dub stab
        case .trap:
            return patch("D2", "Trap Keys",
                a: 0.01, d: 1.0, s: 0.30, r: 2.4,
                harm: 0.90, hl: 0.74, bright: 0.42, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 3200, res: 0.10, lfoAmt: 0.08, lfoRate: 0.18, lfoDepth: 0.18,
                revMix: 0.52, revDecay: 3.6, vibRate: 4, vibDepth: 0.07)  // kept tight (trap = mono-ish keys)
        case .vaporwave:
            return patch("D4", "Vapor Pad",
                a: 0.8, d: 1.6, s: 0.88, r: 4.5,
                harm: 0.92, hl: 0.80, bright: 0.26, noise: 0.01, color: "Pink", shape: "Natural",
                cutoff: 1500, res: 0.08, lfoAmt: 0.14, lfoRate: 0.08, lfoDepth: 0.30,
                revMix: 0.62, revDecay: 5.5, vibRate: 0, vibDepth: 0,
                uni: 3, det: 12)                                 // lush wide pad
        case .eighties:
            return patch("D5", "Neon Keys",
                a: 0.04, d: 0.6, s: 0.78, r: 2.2,
                harm: 0.93, hl: 0.78, bright: 0.48, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 3200, res: 0.12, lfoAmt: 0.10, lfoRate: 0.22, lfoDepth: 0.18,
                revMix: 0.48, revDecay: 3.2, vibRate: 4.5, vibDepth: 0.08,
                uni: 2, det: 10)
        case .disco:
            return patch("D6", "Velvet Strings",
                a: 0.10, d: 0.8, s: 0.72, r: 2.0,
                harm: 0.92, hl: 0.80, bright: 0.46, noise: 0.015, color: "Pink", shape: "Natural",
                cutoff: 3050, res: 0.12, lfoAmt: 0.10, lfoRate: 0.24, lfoDepth: 0.26,
                revMix: 0.46, revDecay: 3.0, vibRate: 5, vibDepth: 0.07,
                uni: 3, det: 15)   // lush wide shimmer — the bright-warm ensemble pole (ultrascan step 1)
        case .synthwave:
            return patch("D7", "Neon Lead",
                a: 0.02, d: 0.5, s: 0.72, r: 1.8,
                harm: 0.94, hl: 0.78, bright: 0.48, noise: 0.0, color: "Pink", shape: "Natural",  // warmth pass 2
                cutoff: 3300, res: 0.16, lfoAmt: 0.18, lfoRate: 0.18, lfoDepth: 0.28,
                revMix: 0.44, revDecay: 3.4, vibRate: 4.5, vibDepth: 0.10,
                uni: 2, det: 11)
        case .earlySynth:
            return patch("D8", "Berlin Seq",
                a: 0.02, d: 0.5, s: 0.55, r: 1.6,
                harm: 0.92, hl: 0.76, bright: 0.40, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 2200, res: 0.18, lfoAmt: 0.30, lfoRate: 0.45, lfoDepth: 0.45,
                revMix: 0.46, revDecay: 3.6, vibRate: 0, vibDepth: 0,
                uni: 2, det: 8)
        case .futuristic:
            return patch("D9", "Crystal Air",
                a: 0.10, d: 1.0, s: 0.70, r: 3.2,
                harm: 0.88, hl: 0.78, bright: 0.48, noise: 0.01, color: "Pink", shape: "Natural",  // warmth pass 2
                cutoff: 3200, res: 0.10, lfoAmt: 0.12, lfoRate: 0.12, lfoDepth: 0.22,
                revMix: 0.58, revDecay: 4.8, vibRate: 0, vibDepth: 0,
                uni: 2, det: 10)
        case .sciFi:
            return patch("DA", "Nebula",
                a: 0.5, d: 1.4, s: 0.78, r: 4.0,
                harm: 0.86, hl: 0.80, bright: 0.34, noise: 0.01, color: "Pink", shape: "Dark",
                cutoff: 1900, res: 0.12, lfoAmt: 0.22, lfoRate: 0.10, lfoDepth: 0.40,
                revMix: 0.62, revDecay: 6.0, vibRate: 0, vibDepth: 0,
                uni: 3, det: 14)                                 // widest — deep-space pad
        case .psytrance:
            return patch("DB", "Psy Pluck",
                a: 0.015, d: 0.4, s: 0.55, r: 1.0,
                harm: 0.94, hl: 0.78, bright: 0.48, noise: 0.0, color: "Pink", shape: "Natural",  // warmth pass 2
                cutoff: 3200, res: 0.16, lfoAmt: 0.26, lfoRate: 0.55, lfoDepth: 0.45,
                revMix: 0.40, revDecay: 2.6, vibRate: 0, vibDepth: 0,
                uni: 2, det: 8)
        case .esotericMeditation:
            return patch("DC", "Deep Drone",
                a: 1.4, d: 1.8, s: 0.92, r: 6.0,
                harm: 0.90, hl: 0.84, bright: 0.18, noise: 0.008, color: "Pink", shape: "Dark",
                cutoff: 950, res: 0.06, lfoAmt: 0.10, lfoRate: 0.05, lfoDepth: 0.35,
                revMix: 0.66, revDecay: 7.0, vibRate: 0, vibDepth: 0,
                uni: 2, det: 8)
        case .classical:
            return patch("E1", "Chamber Strings",
                a: 0.35, d: 1.0, s: 0.80, r: 3.2,
                harm: 0.90, hl: 0.82, bright: 0.31, noise: 0.02, color: "Pink", shape: "Natural",
                cutoff: 2450, res: 0.08, lfoAmt: 0.06, lfoRate: 0.10, lfoDepth: 0.15,
                revMix: 0.52, revDecay: 4.0, vibRate: 5, vibDepth: 0.10,
                uni: 4, det: 16)   // slow orchestral bloom, widest section — the strings pole (ultrascan step 1)
        case .jazz:
            return patch("E2", "Warm Rhodes",
                a: 0.02, d: 0.9, s: 0.60, r: 1.8,
                harm: 0.90, hl: 0.78, bright: 0.33, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 2250, res: 0.10, lfoAmt: 0.08, lfoRate: 0.20, lfoDepth: 0.20,
                revMix: 0.40, revDecay: 2.6, vibRate: 4, vibDepth: 0.06,
                uni: 2, det: 6)   // dark, round Rhodes — the mellow-keys pole (ultrascan step 1)
        case .klezmer:
            return patch("E3", "Clarinet Reed",
                a: 0.04, d: 0.5, s: 0.70, r: 1.4,
                harm: 0.92, hl: 0.80, bright: 0.38, noise: 0.02, color: "Pink", shape: "Natural",  // warmth pass 2
                cutoff: 2600, res: 0.12, lfoAmt: 0.10, lfoRate: 0.25, lfoDepth: 0.20,
                revMix: 0.38, revDecay: 2.4, vibRate: 6.2, vibDepth: 0.15)   // solo woody reed, most expressive vibrato, no unison (ultrascan step 1)
        case .oriental:
            return patch("E4", "Reed Strings",
                a: 0.08, d: 0.8, s: 0.72, r: 2.2,
                harm: 0.90, hl: 0.80, bright: 0.44, noise: 0.02, color: "Pink", shape: "Natural",
                cutoff: 2650, res: 0.12, lfoAmt: 0.10, lfoRate: 0.30, lfoDepth: 0.25,
                revMix: 0.46, revDecay: 3.2, vibRate: 6, vibDepth: 0.14,
                uni: 2, det: 9)   // reedy waver — expressive vibrato + faster movement (ultrascan step 1)
        case .punk:
            return patch("E5", "Buzz Saw",
                a: 0.010, d: 0.3, s: 0.60, r: 0.6,   // softer attack (was 0.005) — no cold stab
                harm: 0.95, hl: 0.80, bright: 0.52, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 3400, res: 0.22, lfoAmt: 0.05, lfoRate: 0.20, lfoDepth: 0.10,
                revMix: 0.22, revDecay: 1.2, vibRate: 0, vibDepth: 0,
                uni: 2, det: 10)                                 // wide buzzsaw
        case .rocknroll:
            return patch("E6", "Twang",
                a: 0.012, d: 0.4, s: 0.50, r: 0.9,
                harm: 0.93, hl: 0.78, bright: 0.48, noise: 0.0, color: "Pink", shape: "Natural",  // warmth pass 2
                cutoff: 3200, res: 0.18, lfoAmt: 0.06, lfoRate: 0.20, lfoDepth: 0.12,
                revMix: 0.30, revDecay: 1.6, vibRate: 0, vibDepth: 0,
                uni: 2, det: 8)
        case .rock:
            return patch("E7", "Driven Lead",
                a: 0.012, d: 0.4, s: 0.60, r: 1.0,
                harm: 0.94, hl: 0.80, bright: 0.48, noise: 0.0, color: "Pink", shape: "Natural",  // warmth pass 2
                cutoff: 3300, res: 0.20, lfoAmt: 0.06, lfoRate: 0.20, lfoDepth: 0.12,
                revMix: 0.30, revDecay: 1.8, vibRate: 0, vibDepth: 0,
                uni: 2, det: 9)
        case .ska:
            return patch("E8", "Skank Organ",
                a: 0.012, d: 0.25, s: 0.40, r: 0.5,
                harm: 0.92, hl: 0.78, bright: 0.46, noise: 0.0, color: "Pink", shape: "Natural",  // warmth pass 2
                cutoff: 3100, res: 0.16, lfoAmt: 0.06, lfoRate: 0.20, lfoDepth: 0.12,
                revMix: 0.28, revDecay: 1.4, vibRate: 0, vibDepth: 0,
                uni: 2, det: 8)                                  // organ needs ensemble body
        case .rocksteady:
            return patch("E9", "Warm Organ",
                a: 0.02, d: 0.5, s: 0.78, r: 1.4,
                harm: 0.90, hl: 0.80, bright: 0.30, noise: 0.0, color: "Pink", shape: "Natural",
                cutoff: 2050, res: 0.10, lfoAmt: 0.12, lfoRate: 0.30, lfoDepth: 0.22,
                revMix: 0.36, revDecay: 2.2, vibRate: 0, vibDepth: 0,
                uni: 2, det: 8)   // dark drawbar organ, flat sustain + rotary LFO, no vibrato (ultrascan step 1)
        case .heavyMetal:
            return patch("EA", "Metal Rig",
                a: 0.010, d: 0.4, s: 0.55, r: 0.8,   // softer attack (was 0.004) — tame the stab
                harm: 0.95, hl: 0.82, bright: 0.50, noise: 0.0, color: "Pink", shape: "Dark",
                cutoff: 3000, res: 0.18, lfoAmt: 0.06, lfoRate: 0.20, lfoDepth: 0.12,
                revMix: 0.26, revDecay: 1.6, vibRate: 0, vibDepth: 0,
                uni: 2, det: 9)                                  // wide detuned guitar wall
        case .doom:
            return patch("EB", "Doom Wall",
                a: 0.02, d: 1.2, s: 0.70, r: 3.0,
                harm: 0.90, hl: 0.84, bright: 0.28, noise: 0.0, color: "Pink", shape: "Dark",
                cutoff: 1400, res: 0.18, lfoAmt: 0.10, lfoRate: 0.08, lfoDepth: 0.30,
                revMix: 0.50, revDecay: 4.5, vibRate: 0, vibDepth: 0,
                uni: 2, det: 10)
        case .selfObservation:
            return patch("D3", "Calm Pad",
                a: 1.0, d: 1.3, s: 0.88, r: 4.2,
                harm: 0.92, hl: 0.80, bright: 0.22, noise: 0.01, color: "Pink", shape: "Natural",
                cutoff: 1300, res: 0.07, lfoAmt: 0.12, lfoRate: 0.08, lfoDepth: 0.30,
                revMix: 0.58, revDecay: 5.5, vibRate: 0, vibDepth: 0,
                uni: 2, det: 8)
        case .drift:
            // G2 airy Fläche: floats a register above Deep Drone / Calm Pad — a touch
            // brighter top (0.30) + a wider unison shimmer (3/12) + a very slow, deep
            // filter drift (rate 0.06, depth 0.42) and the biggest space of the three,
            // so it reads weightless rather than dark. Distinct timbre from both
            // sibling Flächen (guarded by GenrePatchesTests uniqueness).
            return patch("DD", "Drift Pad",
                a: 1.6, d: 1.8, s: 0.90, r: 6.5,
                harm: 0.91, hl: 0.82, bright: 0.30, noise: 0.012, color: "Pink", shape: "Natural",
                cutoff: 1650, res: 0.06, lfoAmt: 0.14, lfoRate: 0.06, lfoDepth: 0.42,
                revMix: 0.64, revDecay: 7.5, vibRate: 0, vibDepth: 0,
                uni: 3, det: 12)
        case .contemplation:
            // G2 grounded Fläche: the DARK, LOW pole of the ambient family — the
            // slowest bloom, lowest cutoff and darkest spectral shape of the three,
            // with the longest reverb tail. Sits under Deep Drone / Calm Pad / Drift
            // so the family spans airy→grounded. Distinct timbre (name + id unique).
            return patch("DE", "Still Pad",
                a: 1.8, d: 2.0, s: 0.92, r: 7.0,
                harm: 0.90, hl: 0.83, bright: 0.16, noise: 0.01, color: "Pink", shape: "Dark",
                cutoff: 1050, res: 0.05, lfoAmt: 0.10, lfoRate: 0.05, lfoDepth: 0.32,
                revMix: 0.62, revDecay: 8.0, vibRate: 0, vibDepth: 0,
                uni: 2, det: 7)
        }
    }

    /// Builds a SynthPatch in the strict declared argument order. The short
    /// `suffix` becomes a stable UUID so a genre's patch identity survives
    /// relaunch (and is distinct per genre).
    ///
    /// `timbre`/`tblend` route the voice through a built-in instrument spectrum
    /// (EchoelDDSP.InstrumentTimbre rawValue; "" = pure synth). `uni`/`det` stack
    /// detuned unison voices for ensemble width (nil = single voice). All default
    /// to "off" so an un-enriched genre is byte-identical to before this cycle.
    private func patch(_ suffix: String, _ name: String,
                       a: Float, d: Float, s: Float, r: Float,
                       harm: Float, hl: Float, bright: Float, noise: Float,
                       color: String, shape: String,
                       cutoff: Float, res: Float, lfoAmt: Float, lfoRate: Float, lfoDepth: Float,
                       revMix: Float, revDecay: Float, vibRate: Float, vibDepth: Float,
                       timbre: String = "", tblend: Float = 0,
                       uni: Int? = nil, det: Float? = nil) -> SynthPatch {
        // Gentle default voicing: lift the per-genre brightness/upper-partial body only
        // ADAPTIVELY (×(1-bright)/×(1-hl)) so a dull genre reads less dull on device while
        // an already-bright genre is barely touched. Coefficients TRIMMED 2026-07-07
        // (founder: "einige Sounds stechen kalt aus dem mix raus vermeide das") from
        // 0.12/0.06 — the earlier "brighter/livelier" lift pushed the top end forward and
        // made some voices read cold; the smaller lift keeps life without the glassy edge.
        let liftedBright = min(1, bright + 0.05 * (1 - bright))
        let liftedHL     = min(1, hl + 0.03 * (1 - hl))
        return SynthPatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(suffix)") ?? UUID(),
            name: name,
            attack: a, decay: d, sustain: s, release: r,
            envelopeCurve: "Exponential",
            harmonicity: harm, harmonicLevel: liftedHL, brightness: liftedBright,
            noiseLevel: noise, noiseColor: color, spectralShape: shape,
            filterCutoff: cutoff, filterResonance: res, lfoToFilterDepth: lfoAmt,
            filterLFORate: lfoRate, filterLFODepth: lfoDepth,
            reverbMix: revMix, reverbDecay: revDecay,
            vibratoRate: vibRate, vibratoDepth: vibDepth,
            timbreProfile: timbre, timbreBlend: tblend,
            unisonVoices: uni, unisonDetuneCents: det
        )
    }
}
