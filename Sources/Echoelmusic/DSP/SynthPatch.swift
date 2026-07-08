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
        unisonVoices: Int? = nil, unisonDetuneCents: Float? = nil
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

    /// Built-in starting points. The first is the warm default pad.
    public static let factory: [SynthPatch] = [
        SynthPatch(id: stableID("00000000-0000-0000-0000-0000000000A1"), name: "Warm Pad"),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000A2"),
            name: "Bright Lead",
            attack: 0.02, decay: 0.3, sustain: 0.7, release: 0.6,
            harmonicity: 0.95, brightness: 0.7, noiseLevel: 0.0,
            spectralShape: "bright", filterCutoff: 4000, filterResonance: 0.2,
            reverbMix: 0.15, reverbDecay: 1.2, vibratoRate: 5, vibratoDepth: 0.15,
            unisonVoices: 2, unisonDetuneCents: 10
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
            reverbMix: 0.45, reverbDecay: 3.5
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
            reverbMix: 0.4, reverbDecay: 2.8
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
            unisonVoices: 3, unisonDetuneCents: 12
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
        )
    ]
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
            vibratoRate: synth.vibratoRate, vibratoDepth: synth.vibratoDepth
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
    }
}
#endif
