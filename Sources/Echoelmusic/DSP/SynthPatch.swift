// SynthPatch.swift
// Echoel — a named, savable snapshot of the DDSP synth's timbre params, so a
// user can design and recall "their own instrument". Pure value type (Codable),
// so it persists and round-trips independent of any audio framework. The
// capture/apply bridge to EchoelDDSP lives in an Accelerate-guarded extension.
//
// Pitch (frequency) and amplitude are intentionally NOT part of a patch — those
// come from the note path (piano roll / MIDI), not the sound design.

import Foundation

/// A recallable synth sound. Enum-valued params (noise color / spectral shape /
/// envelope curve) are stored as their String rawValue for stable Codable.
public struct SynthPatch: Codable, Sendable, Equatable, Identifiable {

    public var id: UUID
    public var name: String

    // Envelope
    public var attack: Float
    public var decay: Float
    public var sustain: Float
    public var release: Float
    public var envelopeCurve: String

    // Tone
    public var harmonicity: Float
    public var harmonicLevel: Float
    public var brightness: Float
    public var noiseLevel: Float
    public var noiseColor: String
    public var spectralShape: String

    // Filter
    public var filterCutoff: Float
    public var filterResonance: Float
    public var lfoToFilterDepth: Float
    public var filterLFORate: Float
    public var filterLFODepth: Float

    // Space
    public var reverbMix: Float
    public var reverbDecay: Float

    // Vibrato
    public var vibratoRate: Float
    public var vibratoDepth: Float

    // Unison — stacked detuned voices per note for a thicker, ensemble sound.
    // Optional so patches saved before unison existed still decode (nil = off).
    public var unisonVoices: Int?        // 1 / nil = off (max EchoelPolyDDSP.maxUnison)
    public var unisonDetuneCents: Float? // total spread in cents (0 = none)

    // Acoustic timbre transfer — a built-in instrument spectral profile blended over
    // the synth's own spectrum for a naturally voiced character (violin, flute, …).
    public var timbreProfile: String   // EchoelDDSP.InstrumentTimbre rawValue, or "" = none
    public var timbreBlend: Float      // 0 = pure synth shape · 1 = full instrument spectrum

    // Per-instrument output level (loudness trim), 1.0 = unity. Optional so patches
    // saved before it existed decode (nil = unity). Normalises one sound's overall
    // loudness against the others (founder 2026-07-11: "Play surface sounds … teils zu
    // laut oder zu leise … Level pro Instrument") — applied as a voice gain, NOT a
    // note-velocity change. The factory patches auto-calibrate this (see
    // `loudnessNormalized()`); users can trim it in the editor.
    public var outputLevel: Float?

    /// Effective output level (nil → unity).
    public var level: Float { outputLevel ?? 1.0 }

    // Analog-warmth drive — a gentle pre-filter soft-saturation that gives the pure
    // additive sine stack harmonic BODY so it stops sounding cold/"plastic" (founder
    // 2026-07-11 sound north-star: warm · organic · dubbig, "kein kaltes überladenes
    // Plastik synthie gedudel"). Optional so patches saved before it existed decode
    // (nil = clean, bit-identical). A mild default warms the whole out-of-box sound;
    // the brightest/most piercing factory leads carry a touch more.
    public var warmthDrive: Float?

    /// Effective warmth drive (nil → clean).
    public var warmth: Float { warmthDrive ?? 0 }

    public init(
        id: UUID = UUID(),
        name: String,
        attack: Float = 0.5, decay: Float = 0.5, sustain: Float = 0.8, release: Float = 2.0,
        envelopeCurve: String = "exponential",
        harmonicity: Float = 0.88, harmonicLevel: Float = 0.8, brightness: Float = 0.25,
        noiseLevel: Float = 0.01, noiseColor: String = "pink", spectralShape: String = "dark",
        filterCutoff: Float = 220, filterResonance: Float = 0.1, lfoToFilterDepth: Float = 0.15,
        filterLFORate: Float = 0.2, filterLFODepth: Float = 0.3,
        reverbMix: Float = 0.25, reverbDecay: Float = 2.0,
        vibratoRate: Float = 0, vibratoDepth: Float = 0,
        timbreProfile: String = "", timbreBlend: Float = 0,
        unisonVoices: Int? = nil, unisonDetuneCents: Float? = nil,
        outputLevel: Float? = nil,
        warmthDrive: Float? = 0.22
    ) {
        self.id = id
        self.name = name
        self.attack = attack; self.decay = decay; self.sustain = sustain; self.release = release
        self.envelopeCurve = envelopeCurve
        self.harmonicity = harmonicity; self.harmonicLevel = harmonicLevel
        self.brightness = brightness; self.noiseLevel = noiseLevel
        self.noiseColor = noiseColor; self.spectralShape = spectralShape
        self.filterCutoff = filterCutoff; self.filterResonance = filterResonance
        self.lfoToFilterDepth = lfoToFilterDepth
        self.filterLFORate = filterLFORate; self.filterLFODepth = filterLFODepth
        self.reverbMix = reverbMix; self.reverbDecay = reverbDecay
        self.vibratoRate = vibratoRate; self.vibratoDepth = vibratoDepth
        self.timbreProfile = timbreProfile; self.timbreBlend = timbreBlend
        self.unisonVoices = unisonVoices; self.unisonDetuneCents = unisonDetuneCents
        self.outputLevel = outputLevel
        self.warmthDrive = warmthDrive
    }

    // MARK: - Loudness normalisation (founder 2026-07-11 "angleichen")

    /// A rough PERCEPTUAL-loudness estimate from the level-driving params — brighter,
    /// more-harmonic, higher-sustain, unison-stacked sounds read louder; dark/short
    /// ones quieter. A heuristic (not a rendered RMS — that needs Accelerate + a device
    /// pass), but enough to stop one instrument being "teils zu laut oder zu leise"
    /// against the next. Pure → unit-testable.
    public static func loudnessEstimate(harmonicLevel: Float, brightness: Float,
                                        sustain: Float, noiseLevel: Float,
                                        unisonVoices: Int?) -> Float {
        let uni = Float(Swift.max(unisonVoices ?? 1, 1))
        let unisonFactor = uni.squareRoot()            // detuned stack sums ~incoherently
        let harmonic = harmonicLevel * (0.6 + 0.8 * brightness) * (0.5 + 0.5 * sustain)
        return harmonic * unisonFactor + noiseLevel * 0.5
    }

    /// The reference loudness the factory patches are matched to (≈ the Warm-Pad
    /// default estimate), so a normalised default lands near unity.
    static let loudnessReference: Float = 0.58

    /// A copy of this patch with `outputLevel` set so its estimated loudness matches
    /// `loudnessReference` — clamped to a musical trim range so nothing is silenced or
    /// wildly boosted. Used to auto-calibrate the factory roster.
    public func loudnessNormalized() -> SynthPatch {
        let est = Swift.max(SynthPatch.loudnessEstimate(
            harmonicLevel: harmonicLevel, brightness: brightness, sustain: sustain,
            noiseLevel: noiseLevel, unisonVoices: unisonVoices), 0.0001)
        let trim = Swift.min(Swift.max(SynthPatch.loudnessReference / est, 0.45), 1.4)
        var copy = self
        copy.outputLevel = trim
        return copy
    }

    /// A stable id from a fixed string (factory presets need identity that
    /// survives relaunch so user patches can be told apart from built-ins).
    private static func stableID(_ s: String) -> UUID { UUID(uuidString: s) ?? UUID() }

    /// Case-insensitive rawValue lookup. The DSP enums use display rawValues
    /// ("Bright", "Pink", "Exponential") but patches store lowercase ("bright",
    /// "pink", "exponential"); an exact `init?(rawValue:)` returned nil and the
    /// preset's spectral shape / noise color / curve were silently dropped — every
    /// character fell back to the synth default and sounded blander than designed.
    private static func match<C: Collection>(_ s: String, _ all: C) -> C.Element?
        where C.Element: RawRepresentable, C.Element.RawValue == String {
        all.first { $0.rawValue.caseInsensitiveCompare(s) == .orderedSame }
    }

    /// Built-in starting points, LOUDNESS-MATCHED (founder 2026-07-11 "angleichen"):
    /// each is auto-calibrated via `loudnessNormalized()` so no factory sound is much
    /// louder/quieter than the next. The first is the warm default pad.
    public static let factory: [SynthPatch] = rawFactory.map { $0.loudnessNormalized() }

    /// The un-normalised factory definitions (timbre design only; output level is
    /// applied by `factory`).
    private static let rawFactory: [SynthPatch] = [
        SynthPatch(id: stableID("00000000-0000-0000-0000-0000000000A1"), name: "Warm Pad"),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000A2"),
            name: "Bright Lead",
            attack: 0.02, decay: 0.3, sustain: 0.7, release: 0.6,
            harmonicity: 0.95, brightness: 0.7, noiseLevel: 0.0,
            spectralShape: "bright", filterCutoff: 4000, filterResonance: 0.2,
            reverbMix: 0.15, reverbDecay: 1.2, vibratoRate: 5, vibratoDepth: 0.15,
            unisonVoices: 2, unisonDetuneCents: 10,
            warmthDrive: 0.30   // extra body — the "schrille hohe Melodie" offender
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000A3"),
            name: "Pluck",
            attack: 0.005, decay: 0.25, sustain: 0.0, release: 0.4,
            harmonicity: 0.9, brightness: 0.5, noiseLevel: 0.02,
            spectralShape: "natural", filterCutoff: 2200, filterResonance: 0.15,
            reverbMix: 0.2, reverbDecay: 1.0
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000A4"),
            name: "Glass Bell",
            attack: 0.01, decay: 1.5, sustain: 0.2, release: 3.0,
            harmonicity: 0.6, brightness: 0.8, noiseLevel: 0.0,
            spectralShape: "bell", filterCutoff: 6000, filterResonance: 0.1,
            reverbMix: 0.45, reverbDecay: 3.5,
            warmthDrive: 0.28   // rounds the glassy top
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000A5"),
            name: "Soft Keys",
            attack: 0.01, decay: 0.6, sustain: 0.5, release: 0.9,
            harmonicity: 0.85, harmonicLevel: 0.75, brightness: 0.4, noiseLevel: 0.0,
            spectralShape: "natural", filterCutoff: 3000, filterResonance: 0.12,
            reverbMix: 0.3, reverbDecay: 1.8
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000A6"),
            name: "Warm Strings",
            attack: 0.18, decay: 0.8, sustain: 0.75, release: 1.8,
            harmonicity: 0.92, harmonicLevel: 0.9, brightness: 0.45, noiseLevel: 0.0,
            spectralShape: "natural", filterCutoff: 3500, filterResonance: 0.1,
            reverbMix: 0.5, reverbDecay: 2.6, vibratoRate: 5, vibratoDepth: 0.1
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000A7"),
            name: "Choir Vox",
            attack: 0.15, decay: 0.7, sustain: 0.8, release: 1.6,
            harmonicity: 0.8, harmonicLevel: 0.85, brightness: 0.5, noiseLevel: 0.03,
            spectralShape: "formant", filterCutoff: 3000, filterResonance: 0.1,
            reverbMix: 0.55, reverbDecay: 3.0, vibratoRate: 4.5, vibratoDepth: 0.12
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000A8"),
            name: "Hollow Reed",
            attack: 0.04, decay: 0.4, sustain: 0.6, release: 0.8,
            harmonicity: 0.85, harmonicLevel: 0.8, brightness: 0.55, noiseLevel: 0.02,
            spectralShape: "hollow", filterCutoff: 2800, filterResonance: 0.18,
            reverbMix: 0.25, reverbDecay: 1.4
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000A9"),
            name: "Metallic",
            attack: 0.008, decay: 0.9, sustain: 0.3, release: 1.6,
            harmonicity: 0.7, harmonicLevel: 0.85, brightness: 0.75, noiseLevel: 0.0,
            spectralShape: "metallic", filterCutoff: 6500, filterResonance: 0.2,
            reverbMix: 0.4, reverbDecay: 2.8,
            warmthDrive: 0.30   // tames the clangy upper partials
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000AA"),
            name: "Deep Sub",
            attack: 0.02, decay: 0.5, sustain: 0.7, release: 0.7,
            harmonicity: 0.5, harmonicLevel: 0.55, brightness: 0.1, noiseLevel: 0.0,
            spectralShape: "dark", filterCutoff: 800, filterResonance: 0.08,
            reverbMix: 0.12, reverbDecay: 1.0
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000AB"),
            name: "Vapor Lead",
            attack: 0.03, decay: 0.5, sustain: 0.7, release: 1.4,
            harmonicity: 0.9, harmonicLevel: 0.85, brightness: 0.65, noiseLevel: 0.01,
            spectralShape: "bright", filterCutoff: 5000, filterResonance: 0.22,
            reverbMix: 0.6, reverbDecay: 3.2, vibratoRate: 5.5, vibratoDepth: 0.2,
            unisonVoices: 3, unisonDetuneCents: 12,
            warmthDrive: 0.30   // dubby/vapor lead — keep it thick, not thin
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000AC"),
            name: "Brass Tuba",
            attack: 0.06, decay: 0.5, sustain: 0.8, release: 0.9,
            harmonicity: 0.9, harmonicLevel: 0.9, brightness: 0.4, noiseLevel: 0.02,
            spectralShape: "formant", filterCutoff: 2400, filterResonance: 0.12,
            reverbMix: 0.3, reverbDecay: 1.6
        ),
        // ── Acoustic instruments (timbre transfer — real per-harmonic spectra) ──
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000AD"),
            name: "Violin",
            attack: 0.12, decay: 0.4, sustain: 0.85, release: 0.6,
            harmonicity: 0.95, harmonicLevel: 0.85, brightness: 0.5, noiseLevel: 0.01,
            spectralShape: "natural", filterCutoff: 4500, filterResonance: 0.1,
            reverbMix: 0.4, reverbDecay: 2.2, vibratoRate: 5.5, vibratoDepth: 0.15,
            timbreProfile: "Violin", timbreBlend: 0.9
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000AE"),
            name: "Flute",
            attack: 0.08, decay: 0.3, sustain: 0.9, release: 0.5,
            harmonicity: 0.97, harmonicLevel: 0.8, brightness: 0.5, noiseLevel: 0.04,
            spectralShape: "natural", filterCutoff: 5000, filterResonance: 0.08,
            reverbMix: 0.35, reverbDecay: 2.0, vibratoRate: 5, vibratoDepth: 0.1,
            timbreProfile: "Flute", timbreBlend: 0.9
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000AF"),
            name: "Trumpet",
            attack: 0.05, decay: 0.3, sustain: 0.85, release: 0.5,
            harmonicity: 0.95, harmonicLevel: 0.9, brightness: 0.6, noiseLevel: 0.01,
            spectralShape: "bright", filterCutoff: 5500, filterResonance: 0.12,
            reverbMix: 0.3, reverbDecay: 1.8, vibratoRate: 5, vibratoDepth: 0.08,
            timbreProfile: "Trumpet", timbreBlend: 0.9
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000B0"),
            name: "Cello",
            attack: 0.14, decay: 0.5, sustain: 0.85, release: 0.8,
            harmonicity: 0.95, harmonicLevel: 0.88, brightness: 0.4, noiseLevel: 0.01,
            spectralShape: "natural", filterCutoff: 3500, filterResonance: 0.1,
            reverbMix: 0.45, reverbDecay: 2.6, vibratoRate: 5, vibratoDepth: 0.12,
            timbreProfile: "Cello", timbreBlend: 0.9
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000B1"),
            name: "Clarinet",
            attack: 0.07, decay: 0.3, sustain: 0.9, release: 0.5,
            harmonicity: 0.96, harmonicLevel: 0.82, brightness: 0.45, noiseLevel: 0.02,
            spectralShape: "hollow", filterCutoff: 3800, filterResonance: 0.1,
            reverbMix: 0.3, reverbDecay: 1.8, vibratoRate: 0, vibratoDepth: 0,
            timbreProfile: "Clarinet", timbreBlend: 0.9
        ),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000B2"),
            name: "Oboe",
            attack: 0.07, decay: 0.3, sustain: 0.88, release: 0.5,
            harmonicity: 0.95, harmonicLevel: 0.85, brightness: 0.55, noiseLevel: 0.02,
            spectralShape: "formant", filterCutoff: 4200, filterResonance: 0.12,
            reverbMix: 0.32, reverbDecay: 1.9, vibratoRate: 5, vibratoDepth: 0.1,
            timbreProfile: "Oboe", timbreBlend: 0.9
        ),
        // Ambient drone: notes bloom in over seconds and take just as long to
        // leave, while a very slow LFO drifts the low-pass cutoff — the classic
        // pad/drone recipe (3–6 s attack, long release, slow filter motion).
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000B3"),
            name: "Drone",
            attack: 3.5, decay: 1.0, sustain: 0.9, release: 6.0,
            harmonicity: 0.9, harmonicLevel: 0.85, brightness: 0.35, noiseLevel: 0.03,
            spectralShape: "dark", filterCutoff: 1800, filterResonance: 0.15,
            filterLFORate: 0.07, filterLFODepth: 0.5,
            reverbMix: 0.6, reverbDecay: 4.5, vibratoRate: 0, vibratoDepth: 0,
            unisonVoices: 2, unisonDetuneCents: 7
        ),
        // ── The play-surface default (founder 2026-07-09: "Den Synth vom Visual
        // Touch Instrument auch optimieren"). The touch voice used to launch on
        // "Warm Pad" (0.5 s attack) — mushy/unresponsive under a finger. This is a
        // pad you can PLAY: a quick but soft attack so taps answer immediately, a
        // little unison detune for organic width (the founder's "organisch"), a
        // gentle filter-LFO drift so held notes breathe, and enough reverb to sit in
        // the immersive space without washing out. Brand-named per the Echoel* CI.
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000B4"),
            name: "Echoel Synth",
            attack: 0.03, decay: 0.4, sustain: 0.72, release: 1.3,
            harmonicity: 0.9, harmonicLevel: 0.82, brightness: 0.42, noiseLevel: 0.006,
            spectralShape: "natural", filterCutoff: 3200, filterResonance: 0.12,
            filterLFORate: 0.12, filterLFODepth: 0.18,
            reverbMix: 0.34, reverbDecay: 2.2, vibratoRate: 0, vibratoDepth: 0,
            unisonVoices: 2, unisonDetuneCents: 8
        )
    ]

    /// Stable id of the play-surface default patch ("Echoel Synth", ex "Echoel Touch"
    /// — id unchanged so saved selections survive), picked by identity at launch.
    public static let touchDefaultID = stableID("00000000-0000-0000-0000-0000000000B4")
}

public extension SynthPatch {

    /// A pre-filled GitHub "new issue" URL carrying this patch's JSON, for the
    /// in-app "Submit to community" flow — mirrors FXPreset.communityIssueURL.
    /// No backend, no auth: the repo is the community store. Foundation-only.
    func communityIssueURL(owner: String = "vibrationalforce",
                           repo: String = "Echoelmusic") -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else { return nil }
        let body = """
        Thanks for sharing an Echoel sound patch!

        **Name:** \(name)

        The patch JSON is below — a maintainer will review it and, if curated, add \
        it to the sound library.

        ```json
        \(json)
        ```
        """
        var comps = URLComponents(string: "https://github.com/\(owner)/\(repo)/issues/new")
        comps?.queryItems = [
            URLQueryItem(name: "title", value: "Patch submission: \(name)"),
            URLQueryItem(name: "labels", value: "patch-submission"),
            URLQueryItem(name: "body", value: body)
        ]
        return comps?.url
    }

    /// A pre-addressed email carrying this patch's JSON, for the in-app "Submit to
    /// community" flow. Composes a mail to the Echoel curator with the patch
    /// embedded — no GitHub account or app needed, works on any device with Mail.
    /// Curated submissions are bundled into the sound library. Foundation-only.
    func communityMailtoURL(to address: String = "echoel@tropicaldrones.com") -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else { return nil }
        let body = """
        Sharing an Echoel sound patch for the community library.

        Name: \(name)

        Patch JSON below:

        \(json)
        """
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = address
        comps.queryItems = [
            URLQueryItem(name: "subject", value: "Echoelmusic patch: \(name)"),
            URLQueryItem(name: "body", value: body)
        ]
        return comps.url
    }
}

#if canImport(Accelerate)
extension SynthPatch {

    /// Capture the live state of a synth voice into a named patch.
    public init(name: String, from synth: EchoelDDSP) {
        self.init(
            name: name,
            attack: synth.attack, decay: synth.decay, sustain: synth.sustain, release: synth.release,
            envelopeCurve: synth.envelopeCurve.rawValue,
            harmonicity: synth.harmonicity, harmonicLevel: synth.harmonicLevel,
            brightness: synth.brightness, noiseLevel: synth.noiseLevel,
            noiseColor: synth.noiseColor.rawValue, spectralShape: synth.spectralShape.rawValue,
            filterCutoff: synth.filterCutoff, filterResonance: synth.filter.resonance,
            lfoToFilterDepth: synth.lfoToFilterDepth,
            filterLFORate: synth.filterLFO.rate, filterLFODepth: synth.filterLFO.depth,
            reverbMix: synth.reverbMix, reverbDecay: synth.reverbDecay,
            vibratoRate: synth.vibratoRate, vibratoDepth: synth.vibratoDepth,
            warmthDrive: synth.warmthDrive
        )
    }

    /// Recall this patch onto a synth voice. Unknown enum rawValues fall back to
    /// the voice's current setting (forward/backward compatible).
    public func apply(to synth: EchoelDDSP) {
        synth.attack = attack
        synth.decay = decay
        synth.sustain = sustain
        synth.release = release
        if let curve = SynthPatch.match(envelopeCurve, EchoelDDSP.EnvelopeCurve.allCases) { synth.envelopeCurve = curve }

        synth.harmonicity = harmonicity
        synth.harmonicLevel = harmonicLevel
        synth.brightness = brightness
        synth.noiseLevel = noiseLevel
        // Capture the patch's designed character as the bio baseline: biofeedback modulates
        // subtly AROUND these instead of overwriting them, so the chosen sound survives.
        synth.bioBaseHarmonicity = harmonicity
        synth.bioBaseNoiseLevel = noiseLevel
        synth.bioBaseReverbMix = reverbMix
        if let color = SynthPatch.match(noiseColor, EchoelDDSP.NoiseColor.allCases) { synth.noiseColor = color }
        if let shape = SynthPatch.match(spectralShape, EchoelDDSP.SpectralShape.allCases) { synth.spectralShape = shape }
        // Acoustic instrument spectrum (timbre transfer). Case-insensitive name →
        // built-in profile; empty/unknown clears it so switching characters resets.
        if let timbre = SynthPatch.match(timbreProfile, EchoelDDSP.InstrumentTimbre.allCases), timbreBlend > 0 {
            synth.loadTimbreProfile(EchoelDDSP.instrumentProfile(timbre), blend: timbreBlend)
        } else {
            synth.clearTimbreProfile()
        }

        synth.filterCutoff = filterCutoff
        synth.bioBaseFilterCutoff = filterCutoff   // bio modulates AROUND this, never overwrites it (task #81)
        synth.filter.resonance = filterResonance
        synth.lfoToFilterDepth = lfoToFilterDepth
        synth.filterLFO.rate = filterLFORate
        synth.filterLFO.depth = filterLFODepth

        synth.reverbMix = reverbMix
        // Convolution reverb is gated off (EchoelDDSP.useConvolutionReverb). apply(to:)
        // runs in the audio render drain, and updateReverbDecay rebuilds a 4096-tap IR
        // (array alloc + RNG) — a forbidden audio-thread allocation on every patch /
        // character change, for a reverb that never renders. Only rebuild when it's live.
        if EchoelDDSP.useConvolutionReverb { synth.updateReverbDecay(reverbDecay) }

        synth.vibratoRate = vibratoRate
        synth.vibratoDepth = vibratoDepth

        // Per-instrument loudness trim (founder 2026-07-11 "Level pro Instrument"). nil
        // = unity (bit-identical). Folded into the voice's master-gain smoother, so it
        // glides in without a click.
        synth.patchOutputLevel = level

        // Analog warmth (founder 2026-07-11 "kein kaltes Plastik synthie gedudel"). nil
        // = clean. A plain Float store — safe on the audio-thread apply path.
        synth.warmthDrive = warmth
    }
}
#endif
