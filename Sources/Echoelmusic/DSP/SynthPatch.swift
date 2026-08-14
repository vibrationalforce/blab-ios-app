// SynthPatch.swift
// Echoel — a named, savable snapshot of the DDSP synth's timbre params, so a
// user can design and recall "their own instrument". Pure value type (Codable),
// so it persists and round-trips independent of any audio framework. The
// capture/apply bridge to EchoelDDSP lives in an Accelerate-guarded extension.
//
// ⚠️ "independent of any audio framework" stopped being literally true with #441:
// `Bounds.filterCutoff` chains to `EchoelDDSP.cutoffRange`, and that type is inside
// `#if canImport(Accelerate)`. Nothing else in this file leaves the guard. The trade
// and the escape route are written out at `Bounds` itself rather than here.
//
// Pitch (frequency) and amplitude are intentionally NOT part of a patch — those
// come from the note path (piano roll / MIDI), not the sound design.

import Foundation

/// A recallable synth sound. Enum-valued params (noise color / spectral shape /
/// envelope curve) are stored as their String rawValue for stable Codable.
public struct SynthPatch: Codable, Sendable, Equatable, Identifiable {

    /// 1 = the shape as of 2026-07-29 (#189 slice 5). This is the user's own timbre
    /// library, and the one type here with a PROVEN loss history — see the WHY on
    /// `init(from:)` below: a non-optional field added 2026-07-11 made every older patch
    /// unreadable and `PatchStore`'s `try?` turned that into an empty library (#95). The
    /// defensive decoder bounded that; this stamp is what a later migration branches on.
    ///
    /// Same shape as `Clip`/`TrackFX` — never decoded, never assigned, so the SYNTHESIZED
    /// encoder writes the current version by construction and no future field can go
    /// missing from a hand-written one. `PatchStore` persists a bare `[SynthPatch]`, so
    /// like `Clip` the stamp is PER PATCH; nothing versions the array itself.
    public static let currentSchemaVersion = 1

    /// ⚠️ Deliberately never read by `init(from:)` — the key exists so the ENCODER writes
    /// it. A migration reads the file's own value into a local inside the decoder. While
    /// nothing assigns it, every instance holds the same constant and the synthesized `==`
    /// gains a term that cannot change a result; the day a migration DOES assign a decoded
    /// version here, that stops being true.
    public private(set) var schemaVersion: Int = SynthPatch.currentSchemaVersion

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

    // MEASURED voice timbre (EchoelVoice #593) — the harmonic envelope a player
    // captured with the Sound panel's "Voice timbre" row, embedded so a saved patch
    // carries "their tone" and (later) travels when shared. All three nil = the patch
    // has no voice half — every patch ever saved before #593 decodes unchanged.
    // NO AUDIO is persisted here: the taps are ~64 floats of max-normalized spectral
    // envelope (`VoiceTimbreProfiler.profile()`), engine-shaped on decode (finite, ≥0).
    // `voiceProfileLabel` is the SHARE-LABEL law from the EchoelVoice boundaries: a
    // patch that carries a measured voice must be able to SAY so wherever it is
    // listed. It is mandatory at SAVE time (the save flow refuses an empty label);
    // the decoder only DEFAULTS a missing one ("Voice") so third-party or truncated
    // JSON degrades to a labeled profile rather than to silent data loss.
    public var voiceProfileTaps: [Float]?
    public var voiceProfileLabel: String?
    public var voiceProfileBlend: Float?   // nil = full (1); clamped 0…1 on decode

    // Per-instrument output level (loudness trim), 1.0 = unity. Optional so patches
    // saved before it existed decode (nil = unity). Normalises one sound's overall
    // loudness against the others (founder 2026-07-11: "Play surface sounds … teils zu
    // laut oder zu leise … Level pro Instrument") — applied as a voice gain, NOT a
    // note-velocity change. The factory patches auto-calibrate this (see
    // `loudnessNormalized()`); users trim it from there in the Sound panel's "Output" row,
    // under the "Level" header. (Naming the ROW matters: while `PatchEditorView.swift` still
    // existed, a grep for "Level" found ITS `section("Level")` first. That file is deleted
    // (#132 Slice 6), so the ambiguity is gone — but the pointer keeps naming "Output" because
    // "Level" is a group header here and headers move.)
    // The two do not fight: `loudnessNormalized()` is applied exactly once, building the
    // `static let factory` roster, and nothing re-runs it over a patch a user has touched.
    // That sentence is here because its absence cost the row its door for a month — the
    // Sound-panel note read the pairing as a conflict and deferred the port on it (#286).
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

    /// THE range of every patch parameter that BOTH the Sound panel and `SoundPrompt` touch —
    /// one definition, read by the row that shows the number AND by the writer that clamps into it.
    ///
    /// ⚠️ NOT "every parameter the panel renders", which is what this line first said. Three rows
    /// of the same panel are absent here on purpose because `SoundPrompt.clamp` does not write
    /// them, so they have only ever had ONE definition and folding them in would buy nothing:
    /// `unisonVoices`, `unisonDetuneCents` and `outputLevel` still spell their ranges at the call
    /// site. A session adding a fourth row should read this as an inventory of the OVERLAP, not of
    /// the panel.
    ///
    /// ⛔ IT USED TO BE THREE DEFINITIONS OF EACH RANGE, AND TWO OF THEM DISAGREED (#441).
    /// The `param(…)`/`knob(…)` call site in `EchoelStudioView.soundPanel` spelled a literal;
    /// `SoundPrompt.clamp` spelled its own; and `SoundRowsCanReachTheShippedPatchesTests` keeps
    /// a hand-written model table (that third one is DELIBERATE and stays — a guard that reads
    /// the constant it is guarding cannot catch a wrong constant). "Describe it" writes straight
    /// back into `currentPatch` from the SAME panel as the rows, so a prompt bound NARROWER than
    /// its row silently destroys a value the user set with a finger, and one WIDER produces a
    /// value the row rewrites on first touch. #430 already paid this once (`decay` clamped to 5
    /// while its row spans 0…10, cutting `Drone Bed`'s shipped 6.0 s) and its own follow-up note
    /// said single-sourcing was "registered, not done here". This is that.
    ///
    /// ⭐ THE DIRECTION IS FIXED, NOT CHOSEN CASE BY CASE: where the two disagreed, the ROW wins
    /// and the prompt WIDENS. A prompt that refuses what a finger can already set is the
    /// lying-control class, and widening can never cut a shipped value — which is exactly the
    /// invariant that made #430's `decay` fix safe. Two disagreements existed and both widen:
    ///   · `filterLFORate` — the prompt clamped to 12 while the row spans 0…20. This is a REAL
    ///     defect, the `Drone Bed` shape one field over: scrub the row to 19, type any recognised
    ///     descriptor, and the value is rewritten as 12. Nothing shipped is above 1.2, so it is a
    ///     USER-set value that was being destroyed — which is the harder kind to notice.
    ///   · `attack` — the prompt floored at 0.001 while the row starts at 0. Cosmetic, and the
    ///     reason is measured rather than assumed: `EchoelDDSP`'s envelope enforces a ~3 ms
    ///     minimum attack ramp in the `.attack` stage (`minAttackSamples`), so 0 and 0.001 are
    ///     the same sound. The old floor's stated purpose ("a musical minimum below every shipped
    ///     onset") was already served by that ramp. Nothing here creates a zero-length onset.
    ///
    /// `filterCutoff` is CHAINED rather than restated — `EchoelDDSP.cutoffRange` is where the
    /// engine already decides that question, and its own doc records the last time a second
    /// spelling of it drifted (a "[20-20000 Hz]" comment against an 18000 clamp).
    ///
    /// ⚠️ THE CHAIN COSTS A PLATFORM, AND THAT IS A CHOICE RATHER THAN AN OVERSIGHT: all of
    /// `EchoelDDSP.swift` sits inside `#if canImport(Accelerate)`, so this line makes `SynthPatch`
    /// — and transitively `SoundPrompt` — Accelerate-only. Every earlier reference to `EchoelDDSP`
    /// from this file was already inside its own Accelerate-guarded extension further down; this
    /// one is not. Taken because the shipped platform set is the Apple ecosystem (CLAUDE.md's
    /// platform ladder) and no workflow in `.github/workflows/` compiles Swift anywhere else —
    /// `quick-test.yml` says so about itself. The day a non-Apple build matters, the escape is a
    /// literal here plus the value assertion in
    /// `Tests/CISmoke/OneDefinitionOfAParameterRangeTests.swift`, which is the #426 form and is
    /// already written; it is weaker than the chain, which is why it is not taken pre-emptively.
    public enum Bounds {
        public static let attack: ClosedRange<Float> = 0...5
        public static let decay: ClosedRange<Float> = 0...10
        public static let sustain: ClosedRange<Float> = 0...1
        public static let release: ClosedRange<Float> = 0...10

        public static let harmonicity: ClosedRange<Float> = 0...1
        public static let harmonicLevel: ClosedRange<Float> = 0...1
        public static let brightness: ClosedRange<Float> = 0...1
        public static let noiseLevel: ClosedRange<Float> = 0...1

        /// Chained to the engine's own cutoff domain — see the note above.
        public static let filterCutoff: ClosedRange<Float> = EchoelDDSP.cutoffRange
        public static let filterResonance: ClosedRange<Float> = 0...1
        public static let lfoToFilterDepth: ClosedRange<Float> = 0...1
        public static let filterLFORate: ClosedRange<Float> = 0...20
        public static let filterLFODepth: ClosedRange<Float> = 0...1

        public static let reverbMix: ClosedRange<Float> = 0...1
        public static let reverbDecay: ClosedRange<Float> = 0...10

        public static let vibratoRate: ClosedRange<Float> = 0...12
        public static let vibratoDepth: ClosedRange<Float> = 0...1
    }

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
        warmthDrive: Float? = 0.22,
        voiceProfileTaps: [Float]? = nil, voiceProfileLabel: String? = nil,
        voiceProfileBlend: Float? = nil
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
        self.voiceProfileTaps = voiceProfileTaps
        self.voiceProfileLabel = voiceProfileLabel
        self.voiceProfileBlend = voiceProfileBlend
    }

    // MARK: - Defensive decoding (forward/backward-compatible)

    /// Custom decoder so a patch saved by an OLDER build — one that predates a field — still
    /// loads instead of throwing `keyNotFound`. Every field tolerates absence: non-optionals
    /// fall back to the memberwise-init default, optionals stay `nil` (bit-identical to the
    /// synthesized decoder for JSON that DOES contain them). Encoding stays synthesized.
    ///
    /// WHY (the bug this fixes): `timbreProfile`/`timbreBlend` were added 2026-07-11 as
    /// NON-optional. The synthesized decoder then threw `keyNotFound` on any patch saved
    /// before that date — and because `PatchStore` does `(try? …) ?? []` and a project loads
    /// via `try? …`, one old patch silently NUKED the user's WHOLE patch library or collapsed
    /// a whole project to an empty document. This is the `decodeIfPresent` law: every new
    /// field must decode defensively. Kept exhaustive (not just the two culprits) so the NEXT
    /// field addition can never reintroduce the same data-loss.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        attack = try c.decodeIfPresent(Float.self, forKey: .attack) ?? 0.5
        decay = try c.decodeIfPresent(Float.self, forKey: .decay) ?? 0.5
        sustain = try c.decodeIfPresent(Float.self, forKey: .sustain) ?? 0.8
        release = try c.decodeIfPresent(Float.self, forKey: .release) ?? 2.0
        envelopeCurve = try c.decodeIfPresent(String.self, forKey: .envelopeCurve) ?? "exponential"
        harmonicity = try c.decodeIfPresent(Float.self, forKey: .harmonicity) ?? 0.88
        harmonicLevel = try c.decodeIfPresent(Float.self, forKey: .harmonicLevel) ?? 0.8
        brightness = try c.decodeIfPresent(Float.self, forKey: .brightness) ?? 0.25
        noiseLevel = try c.decodeIfPresent(Float.self, forKey: .noiseLevel) ?? 0.01
        noiseColor = try c.decodeIfPresent(String.self, forKey: .noiseColor) ?? "pink"
        spectralShape = try c.decodeIfPresent(String.self, forKey: .spectralShape) ?? "dark"
        filterCutoff = try c.decodeIfPresent(Float.self, forKey: .filterCutoff) ?? 220
        filterResonance = try c.decodeIfPresent(Float.self, forKey: .filterResonance) ?? 0.1
        lfoToFilterDepth = try c.decodeIfPresent(Float.self, forKey: .lfoToFilterDepth) ?? 0.15
        filterLFORate = try c.decodeIfPresent(Float.self, forKey: .filterLFORate) ?? 0.2
        filterLFODepth = try c.decodeIfPresent(Float.self, forKey: .filterLFODepth) ?? 0.3
        reverbMix = try c.decodeIfPresent(Float.self, forKey: .reverbMix) ?? 0.25
        reverbDecay = try c.decodeIfPresent(Float.self, forKey: .reverbDecay) ?? 2.0
        vibratoRate = try c.decodeIfPresent(Float.self, forKey: .vibratoRate) ?? 0
        vibratoDepth = try c.decodeIfPresent(Float.self, forKey: .vibratoDepth) ?? 0
        timbreProfile = try c.decodeIfPresent(String.self, forKey: .timbreProfile) ?? ""
        timbreBlend = try c.decodeIfPresent(Float.self, forKey: .timbreBlend) ?? 0
        unisonVoices = try c.decodeIfPresent(Int.self, forKey: .unisonVoices)
        unisonDetuneCents = try c.decodeIfPresent(Float.self, forKey: .unisonDetuneCents)
        outputLevel = try c.decodeIfPresent(Float.self, forKey: .outputLevel)
        warmthDrive = try c.decodeIfPresent(Float.self, forKey: .warmthDrive)
        // EchoelVoice #593 — the voice half decodes as a UNIT keyed on the taps:
        // taps present → engine-shape the values (finite, ≥0 — the same sanitize
        // `setCustomTimbre` applies, done here too so a patch FILE can never hold a
        // value the engine would refuse to carry), default a missing label, clamp
        // the blend; taps absent or empty → the whole half is nil, so a label
        // without a profile cannot claim a voice that is not there.
        // ⚠️ RESIDUAL (steward #593a, on record rather than papered over): a half
        // with 1…63 taps decodes as present but the engine refuses anything under
        // its `harmonicCount` (64 default) — the same claim-without-a-voice, at
        // short lengths instead of zero. This layer cannot know the engine's count
        // without a second spelling of it (#416), and the in-app producer
        // (`VoiceTimbreProfiler`) always emits a full set — so the LENGTH guarantee
        // belongs to the #593b save flow, and only third-party/truncated JSON can
        // hit the silent no-op until then.
        if let rawTaps = try c.decodeIfPresent([Float].self, forKey: .voiceProfileTaps),
           !rawTaps.isEmpty {
            voiceProfileTaps = rawTaps.map { $0.isFinite ? Swift.max(0, $0) : 0 }
            let label = try c.decodeIfPresent(String.self, forKey: .voiceProfileLabel)
            voiceProfileLabel = (label?.isEmpty == false) ? label : "Voice"
            let blend = try c.decodeIfPresent(Float.self, forKey: .voiceProfileBlend) ?? 1
            voiceProfileBlend = blend.isFinite ? Swift.min(Swift.max(blend, 0), 1) : 1
        } else {
            voiceProfileTaps = nil
            voiceProfileLabel = nil
            voiceProfileBlend = nil
        }
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
            // "Echoel Field" since 2026-07-29. It was "Echoel Synth", and that was the ONE
            // string that visibly contradicted the surface rename: this patch is applied at
            // launch and renders as the selected chip on the panel titled "Field", under the
            // heading "Voice" — so a fresh install showed the removed word right where the
            // new one had just been introduced. Display name only; the id is untouched
            // (`touchDefaultID`) and `touch.patchID` stores the UUID, never the name, so
            // every saved selection survives. Second rename of this patch on those terms.
            name: "Echoel Field",
            attack: 0.03, decay: 0.4, sustain: 0.72, release: 1.3,
            harmonicity: 0.9, harmonicLevel: 0.82, brightness: 0.42, noiseLevel: 0.006,
            spectralShape: "natural", filterCutoff: 3200, filterResonance: 0.12,
            filterLFORate: 0.12, filterLFODepth: 0.18,
            reverbMix: 0.34, reverbDecay: 2.2, vibratoRate: 0, vibratoDepth: 0,
            unisonVoices: 2, unisonDetuneCents: 8
        )
    ]

    /// Stable id of the play-surface default patch ("Echoel Field", ex "Echoel Synth", ex
    /// "Echoel Touch" — id unchanged through every rename so saved selections survive),
    /// picked by identity at launch.
    public static let touchDefaultID = stableID("00000000-0000-0000-0000-0000000000B4")

    /// ⭐ WHICH PATCH THE PLAY SURFACE SHOULD WAKE UP ON, before any take exists.
    ///
    /// #402. The app's async startup task used to apply `touchDefaultID` here unconditionally —
    /// and `EchoelStudioView.onAppear` applies the user's stored Field patch in the first
    /// SYNCHRONOUS appear pass, which the repo itself documents as running BEFORE that task. So
    /// the default always landed second and replaced the user's choice: a chosen Field sound
    /// never survived a relaunch. The comment beside that apply claimed "or the user's own touch
    /// patch overrides", which is why it stood unexamined for so long.
    ///
    /// ⛔ THIS IS NOT `syncTouchSound()`'s QUESTION, and routing that one through here would be a
    /// regression — stated because the tempting "single answer for the Field patch" reading is
    /// wrong. `syncTouchSound()` asks *what should the Field play NOW*, and its answer for an
    /// EMPTY selection is the current TAKE's patch (follow-the-take, by design). This asks *what
    /// should it wake up on*, where no take exists yet, so an empty selection means the factory
    /// Field default. Two questions, two answers.
    ///
    /// ⭐ AND THE FIX IS CORRECT WHICHEVER PATH RUNS FIRST — its strongest property, and the
    /// first version of this note failed to state it while leaning on the weaker order-dependent
    /// story. What it buys is AGREEMENT in the one case that was broken: a non-empty stored id.
    /// `onAppear` only calls `syncTouchSound()` when the id is non-empty, and both paths then
    /// resolve that same id to that same patch. Order stops mattering.
    ///
    /// ⚠️ ONE case remains order-dependent, and it is the only claim here resting on framework
    /// behaviour nobody in this repo can read: a STALE id. `syncTouchSound()` falls back to the
    /// take, this falls back to the factory default, and *at launch* this one lands last — which
    /// is the better place for a play surface with no take yet, and is what shipped before. Two
    /// limits on that sentence, both found in review rather than assumed: SwiftUI's delivery
    /// order between an ancestor's `.task` and a descendant's `onAppear` is inferred, not proven;
    /// and it is a LAUNCH-only statement, because the startup task is latched to run once per
    /// process while `onAppear` is not — on any later re-appear `syncTouchSound()` is the sole
    /// writer and the take wins.
    ///
    /// ⚠️ TAKES THE STORED ID AS A STRING, and does not read `UserDefaults` itself — for two
    /// reasons, neither of which is the one the first version gave. It claimed `DSP/` "compiles
    /// in isolation for the AUv3 target"; **there is no AUv3 target** (removed 2026-07-24,
    /// `project.yml` says so and adds that `DSP/` stays Foundation-only "by hygiene even though
    /// the isolated-AUv3-compile that mandated it is retired"). Landing a dead compile mandate
    /// in the commit that exists to punish false rationales is exactly the trap it names. The
    /// real reasons: (1) that hygiene rule still stands on its own, and (2) a `String` parameter
    /// is what lets every branch below be tested without `UserDefaults`, a view or a simulator —
    /// which is the whole reason `FieldSoundSurvivesRelaunchTests` can exist.
    ///
    /// Order: the user's explicit choice · else the factory play-surface default · else anything
    /// at all · else nothing. The last two rungs are DEFENSIVE, not live: `PatchStore` always
    /// prepends `SynthPatch.factory`, so the production call site can never reach them.
    public static func launchTouchPatch(storedID: String, in library: [SynthPatch]) -> SynthPatch? {
        if let id = UUID(uuidString: storedID),
           let chosen = library.first(where: { $0.id == id }) {
            return chosen
        }
        return library.first(where: { $0.id == touchDefaultID }) ?? library.first
    }
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

    /// Resolve every String→enum lookup ONCE, on the calling (control) thread.
    ///
    /// This is the only place `match` runs, and `match` is the reason the split
    /// exists: it evaluates `allCases` (a fresh array) and `caseInsensitiveCompare`
    /// (ObjC messaging on a bridged String) — both forbidden on the audio thread,
    /// and `apply(to:)` is drained inside `PolySynthVoice`'s render block.
    public func resolved() -> ResolvedPatch {
        ResolvedPatch(
            attack: attack, decay: decay, sustain: sustain, release: release,
            envelopeCurve: SynthPatch.match(envelopeCurve, EchoelDDSP.EnvelopeCurve.allCases),
            harmonicity: harmonicity, harmonicLevel: harmonicLevel,
            brightness: brightness, noiseLevel: noiseLevel,
            noiseColor: SynthPatch.match(noiseColor, EchoelDDSP.NoiseColor.allCases),
            spectralShape: SynthPatch.match(spectralShape, EchoelDDSP.SpectralShape.allCases),
            timbre: SynthPatch.match(timbreProfile, EchoelDDSP.InstrumentTimbre.allCases),
            timbreBlend: timbreBlend,
            filterCutoff: filterCutoff, filterResonance: filterResonance,
            lfoToFilterDepth: lfoToFilterDepth,
            filterLFORate: filterLFORate, filterLFODepth: filterLFODepth,
            reverbMix: reverbMix, reverbDecay: reverbDecay,
            vibratoRate: vibratoRate, vibratoDepth: vibratoDepth,
            outputLevel: level, warmthDrive: warmth
        )
    }

    /// Recall this patch onto a synth voice. Unknown enum rawValues fall back to
    /// the voice's current setting (forward/backward compatible).
    ///
    /// Control-thread convenience — it resolves and then applies. The audio-thread
    /// drain must NOT call this; it carries a pre-`resolved()` value instead.
    public func apply(to synth: EchoelDDSP) { resolved().apply(to: synth) }
}

/// A `SynthPatch` with every String→enum lookup already done: recalling it costs
/// nothing but scalar stores.
///
/// WHY this type exists. `PolySynthVoice` drains its patch queue INSIDE the render
/// block — deliberately, because applying a patch rewrites each voice's
/// `harmonicAmplitudes`, and doing that from the main actor raced the render (the
/// bug fixed in v337). But the queue used to carry a `SynthPatch`, and that put the
/// race's cure on top of three fresh audio-thread violations:
///   · `allCases` — a heap-allocated array, built four times per voice per recall;
///   · `caseInsensitiveCompare` — ObjC messaging on a bridged `String`, once per case;
///   · `instrumentProfile(_:)` — a fresh 64-tap `[Float]` per voice, plus the `free()`
///     that `clearTimbreProfile()` performed on the other branch.
/// Dequeuing the patch itself was a fourth: its `String`s and `UUID` meant ARC traffic
/// on the render thread.
///
/// So this is deliberately PLAIN OLD DATA — Floats and simple enums only. No String,
/// no Array, no optional-boxing of a reference type. If you are tempted to add one,
/// that is the moment the violation comes back.
public struct ResolvedPatch: Sendable, Equatable {
    public var attack, decay, sustain, release: Float
    /// `nil` = the rawValue did not name a known case → leave the voice's current
    /// setting alone (the forward/backward-compatible fallback `apply(to:)` always had).
    public var envelopeCurve: EchoelDDSP.EnvelopeCurve?
    public var harmonicity, harmonicLevel, brightness, noiseLevel: Float
    public var noiseColor: EchoelDDSP.NoiseColor?
    public var spectralShape: EchoelDDSP.SpectralShape?
    public var timbre: EchoelDDSP.InstrumentTimbre?
    public var timbreBlend: Float
    public var filterCutoff, filterResonance, lfoToFilterDepth: Float
    public var filterLFORate, filterLFODepth: Float
    public var reverbMix, reverbDecay: Float
    public var vibratoRate, vibratoDepth: Float
    /// Already un-optionalised by `SynthPatch.level` / `.warmth` (nil → unity / clean).
    public var outputLevel, warmthDrive: Float

    /// AUDIO-THREAD SAFE. Scalar stores plus `applyTimbre`, which fills a
    /// preallocated buffer. No allocation, no ObjC, no lock, no file I/O.
    public func apply(to synth: EchoelDDSP) {
        synth.attack = attack
        synth.decay = decay
        synth.sustain = sustain
        synth.release = release
        if let envelopeCurve { synth.envelopeCurve = envelopeCurve }

        synth.harmonicity = harmonicity
        synth.harmonicLevel = harmonicLevel
        synth.brightness = brightness
        synth.noiseLevel = noiseLevel
        // Capture the patch's designed character as the bio baseline: biofeedback modulates
        // subtly AROUND these instead of overwriting them, so the chosen sound survives.
        synth.bioBaseHarmonicity = harmonicity
        synth.bioBaseNoiseLevel = noiseLevel
        synth.bioBaseReverbMix = reverbMix
        synth.bioBaseBrightness = brightness  // bio modulates AROUND the patch brightness (task #81)
        if let noiseColor { synth.noiseColor = noiseColor }
        if let spectralShape { synth.spectralShape = spectralShape }
        // Acoustic instrument spectrum (timbre transfer). An unresolved name or a zero
        // blend clears it, so switching characters resets — same behaviour as before,
        // now without building or freeing the 64-tap profile array.
        synth.applyTimbre(timbre, blend: timbreBlend)

        synth.filterCutoff = filterCutoff
        synth.bioBaseFilterCutoff = filterCutoff   // bio modulates AROUND this, never overwrites it (task #81)
        synth.filter.resonance = filterResonance
        synth.lfoToFilterDepth = lfoToFilterDepth
        // Bio anchor (#279): keeps this at the patch value instead of letting bio overwrite it
        // ~10×/s. −1 stays "unset", so a voice that never got a patch keeps the legacy absolute
        // mapping.
        // ⛔ The first version added "so a negative from a corrupt JSON falls back to the legacy
        // path rather than inverting the LFO — the safe direction". That guarantee does not
        // exist: the line directly ABOVE writes the raw negative into the live render parameter
        // unconditionally, and `1.0 + lfoMod * lfoToFilterDepth` in the render path does invert
        // with it. The sentinel only decides what a LATER bio frame does; with bio off, or
        // before the first frame, the negative simply stands. Clamping at decode is the real
        // fix and is not this task's.
        synth.bioBaseLFOToFilterDepth = lfoToFilterDepth
        synth.filterLFO.rate = filterLFORate
        synth.filterLFO.depth = filterLFODepth

        synth.reverbMix = reverbMix
        // Convolution reverb is gated off (EchoelDDSP.useConvolutionReverb). This runs in
        // the audio render drain, and updateReverbDecay rebuilds a 4096-tap IR
        // (array alloc + RNG) — a forbidden audio-thread allocation on every patch /
        // character change, for a reverb that never renders. Only rebuild when it's live.
        if EchoelDDSP.useConvolutionReverb { synth.updateReverbDecay(reverbDecay) }

        synth.vibratoRate = vibratoRate
        synth.vibratoDepth = vibratoDepth
        // Bio anchor (#279) — set as a PAIR, and `applyBioReactive` requires BOTH to be ≥ 0
        // before it takes the anchored path. Every preset ships a musical 4.5–5.5 Hz here while
        // the absolute bio mapping wrote 0.05–0.2 Hz, so before this the body did not colour the
        // patch's vibrato, it erased it.
        synth.bioBaseVibratoRate = vibratoRate
        synth.bioBaseVibratoDepth = vibratoDepth

        // Per-instrument loudness trim (founder 2026-07-11 "Level pro Instrument"). 1.0
        // = unity (bit-identical). Folded into the voice's master-gain smoother, so it
        // glides in without a click.
        synth.patchOutputLevel = outputLevel

        // Analog warmth (founder 2026-07-11 "kein kaltes Plastik synthie gedudel"). 0
        // = clean. A plain Float store — safe on the audio-thread apply path.
        synth.warmthDrive = warmthDrive
    }
}
#endif
