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
        vibratoRate: Float = 0, vibratoDepth: Float = 0
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
    }

    /// A stable id from a fixed string (factory presets need identity that
    /// survives relaunch so user patches can be told apart from built-ins).
    private static func stableID(_ s: String) -> UUID { UUID(uuidString: s) ?? UUID() }

    /// Built-in starting points. The first is the warm default pad.
    public static let factory: [SynthPatch] = [
        SynthPatch(id: stableID("00000000-0000-0000-0000-0000000000A1"), name: "Warm Pad"),
        SynthPatch(
            id: stableID("00000000-0000-0000-0000-0000000000A2"),
            name: "Bright Lead",
            attack: 0.02, decay: 0.3, sustain: 0.7, release: 0.6,
            harmonicity: 0.95, brightness: 0.7, noiseLevel: 0.0,
            spectralShape: "bright", filterCutoff: 4000, filterResonance: 0.2,
            reverbMix: 0.15, reverbDecay: 1.2, vibratoRate: 5, vibratoDepth: 0.15
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
        )
    ]
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
        if let curve = EchoelDDSP.EnvelopeCurve(rawValue: envelopeCurve) { synth.envelopeCurve = curve }

        synth.harmonicity = harmonicity
        synth.harmonicLevel = harmonicLevel
        synth.brightness = brightness
        synth.noiseLevel = noiseLevel
        if let color = EchoelDDSP.NoiseColor(rawValue: noiseColor) { synth.noiseColor = color }
        if let shape = EchoelDDSP.SpectralShape(rawValue: spectralShape) { synth.spectralShape = shape }

        synth.filterCutoff = filterCutoff
        synth.filter.resonance = filterResonance
        synth.lfoToFilterDepth = lfoToFilterDepth
        synth.filterLFO.rate = filterLFORate
        synth.filterLFO.depth = filterLFODepth

        synth.reverbMix = reverbMix
        synth.updateReverbDecay(reverbDecay)

        synth.vibratoRate = vibratoRate
        synth.vibratoDepth = vibratoDepth
    }
}
#endif
