// GenreFX.swift
// Echoel — the *space* behind each genre. GenrePatches gives a take the right
// timbre; this gives it the right effects: the long tempo-synced dub delay, the
// vaporwave chorus wash, the psytrance ping-pong roll, the sci-fi phaser sweep.
// Applied to the melody voice's EchoelFXChain on Generate so a take sounds like
// its reference out of the box, then stays fully editable in the FX tool.
//
// LOCATION: Sequencer/ (not DSP/) on purpose — it depends on MusicStyle, which
// the AUv3 target does not glob. See GenrePatches.swift for the same constraint.
//
// Pure value type: delay time is a musical NoteDivision (via TempoSyncOption), so
// the echo locks to the take's BPM. `apply(to:bpm:)` is the only side-effecting
// call and it just writes already-clamped scalars onto the (audio-thread-safe)
// chain — no allocation, no locks.

import Foundation

/// The effect colour for one genre: a tempo-synced delay plus optional chorus and
/// phaser. Resolved against a BPM at apply time.
public struct GenreFXPreset: Sendable, Equatable {

    // Filter — tone colour (underwater low-pass, telephone band-pass, lo-fi).
    public var filterEnabled: Bool
    public var filterMode: EchoelSVFilter.Mode
    public var filterCutoff: Float
    public var filterResonance: Float

    // Delay — the defining space (dub, psy, Berlin-school sequencer echo).
    public var delayEnabled: Bool
    public var delayMode: EchoelDelay.Mode
    /// Echo time as a note division, resolved to seconds at the take's BPM.
    public var delaySync: TempoSyncOption
    public var delayMix: Float
    public var delayFeedback: Float
    public var delayTone: Float        // 0 dark … 1 bright
    public var delaySpread: Float      // stereo width on the right tap
    public var delayWow: Float         // tape pitch wobble (only audible in .tape)
    public var delayDrive: Float       // tape feedback saturation (.tape)

    // Chorus — width / shimmer (80s, vaporwave, synthwave).
    public var chorusEnabled: Bool
    public var chorusRate: Float
    public var chorusDepth: Float
    public var chorusMix: Float

    // Phaser — sweep / motion (sci-fi).
    public var phaserEnabled: Bool
    public var phaserRate: Float
    public var phaserDepth: Float
    public var phaserMix: Float

    // Saturation — analog warmth. The additive synth is a clean sine stack; a
    // little drive gives it harmonic body so a take sounds professional, not
    // thin and digital. 0 disables (a truly dry "Clean").
    public var saturation: Float

    // Harmonizer — pitch-shifted harmony voices. Off in every genre preset; the
    // `.harmonizer` character turns it on. Carried here so every preset apply
    // explicitly settles the harmonizer state (no sticky-on when switching).
    public var harmonizerEnabled: Bool
    public var harmonizerInterval1: Float
    public var harmonizerInterval2: Float
    public var harmonizerVoice2: Bool
    public var harmonizerMix: Float

    // Reverb — real algorithmic room/hall space. The additive source has no
    // reverb of its own, so this is where a take gets its "produced" depth.
    public var reverbEnabled: Bool
    public var reverbMix: Float
    public var reverbRoom: Float
    public var reverbDamping: Float

    public init(
        filterEnabled: Bool = false,
        filterMode: EchoelSVFilter.Mode = .lowpass,
        filterCutoff: Float = 20_000,
        filterResonance: Float = 0.2,
        delayEnabled: Bool = false,
        delayMode: EchoelDelay.Mode = .digital,
        delaySync: TempoSyncOption = TempoSyncOption(.quarter),
        delayMix: Float = 0.25,
        delayFeedback: Float = 0.30,
        delayTone: Float = 0.5,
        delaySpread: Float = 0.0,
        delayWow: Float = 0.0,
        delayDrive: Float = 0.0,
        chorusEnabled: Bool = false,
        chorusRate: Float = 0.4,
        chorusDepth: Float = 0.5,
        chorusMix: Float = 0.4,
        phaserEnabled: Bool = false,
        phaserRate: Float = 0.2,
        phaserDepth: Float = 0.6,
        phaserMix: Float = 0.4,
        saturation: Float = 0.30,
        harmonizerEnabled: Bool = false,
        harmonizerInterval1: Float = 4,
        harmonizerInterval2: Float = 7,
        harmonizerVoice2: Bool = true,
        harmonizerMix: Float = 0.5,
        reverbEnabled: Bool = false,
        reverbMix: Float = 0.0,
        reverbRoom: Float = 0.72,
        reverbDamping: Float = 0.5
    ) {
        self.filterEnabled = filterEnabled
        self.filterMode = filterMode
        self.filterCutoff = filterCutoff
        self.filterResonance = filterResonance
        self.delayEnabled = delayEnabled
        self.delayMode = delayMode
        self.delaySync = delaySync
        self.delayMix = delayMix
        self.delayFeedback = delayFeedback
        self.delayTone = delayTone
        self.delaySpread = delaySpread
        self.delayWow = delayWow
        self.delayDrive = delayDrive
        self.chorusEnabled = chorusEnabled
        self.chorusRate = chorusRate
        self.chorusDepth = chorusDepth
        self.chorusMix = chorusMix
        self.phaserEnabled = phaserEnabled
        self.phaserRate = phaserRate
        self.phaserDepth = phaserDepth
        self.phaserMix = phaserMix
        self.saturation = saturation
        self.harmonizerEnabled = harmonizerEnabled
        self.harmonizerInterval1 = harmonizerInterval1
        self.harmonizerInterval2 = harmonizerInterval2
        self.harmonizerVoice2 = harmonizerVoice2
        self.harmonizerMix = harmonizerMix
        self.reverbEnabled = reverbEnabled
        self.reverbMix = reverbMix
        self.reverbRoom = reverbRoom
        self.reverbDamping = reverbDamping
    }

    /// Delay-line capacity in the chain (EchoelDelay default). The synced time is
    /// clamped to this so a whole note at a slow tempo never overruns the buffer.
    private static let maxDelaySeconds: Float = 2.0

    /// Write this preset onto a live chain, resolving the synced delay time at
    /// `bpm`. Safe to call from the main actor; the chain reads are audio-thread
    /// atomic-width scalars.
    public func apply(to chain: EchoelFXChain, bpm: Double) {
        chain.filterEnabled = filterEnabled
        chain.setFilter(mode: filterMode, cutoff: filterCutoff, resonance: filterResonance)

        chain.delayEnabled = delayEnabled
        chain.delay.mode = delayMode
        chain.delay.timeSeconds = delaySync.clampedSeconds(bpm: bpm, in: 0.001...Self.maxDelaySeconds)
        chain.delay.mix = delayMix
        chain.delay.feedback = delayFeedback
        chain.delay.tone = delayTone
        chain.delay.spread = delaySpread
        chain.delay.wow = delayWow
        chain.delay.drive = delayDrive

        chain.chorusEnabled = chorusEnabled
        chain.chorus.rate = chorusRate
        chain.chorus.depth = chorusDepth
        chain.chorus.mix = chorusMix

        chain.phaserEnabled = phaserEnabled
        chain.phaser.rate = phaserRate
        chain.phaser.depth = phaserDepth
        chain.phaser.mix = phaserMix

        chain.saturationEnabled = saturation > 0
        chain.saturationDrive = saturation

        chain.harmonizerEnabled = harmonizerEnabled
        chain.harmonizer.interval1 = harmonizerInterval1
        chain.harmonizer.interval2 = harmonizerInterval2
        chain.harmonizer.voice2Enabled = harmonizerVoice2
        chain.harmonizer.mix = harmonizerMix

        chain.reverbEnabled = reverbEnabled
        chain.reverb.mix = reverbMix
        chain.reverb.roomSize = reverbRoom
        chain.reverb.damping = reverbDamping
    }
}

public extension MusicStyle {

    /// The effect space this genre is generated through. Applied to the melody
    /// voice on Generate, then editable in the FX tool.
    ///
    /// ROOM FLOOR (audit A3 — "instrument is bone dry, in a box"): every REAL production
    /// happens in SOME space; 12 of the genre presets specified no reverb at all, which
    /// left jazz/klezmer/rock playing in a vacuum — the "buzzy/flat" additive fingerprint.
    /// Genres that DESIGN their reverb keep it exactly; the dry ones get a subtle room
    /// (mix 0.10 — felt as depth, not heard as hall). Character presets (telephone,
    /// cassette …) are a different path and stay intentionally dry.
    var fxPreset: GenreFXPreset {
        var p = rawFXPreset
        if !p.reverbEnabled {
            p.reverbEnabled = true
            p.reverbMix = 0.10
            p.reverbRoom = 0.48
            p.reverbDamping = 0.55
        }
        return p
    }

    private var rawFXPreset: GenreFXPreset {
        switch self {
        case .dubTechno:
            // The signature: a long, dark, swung dub delay with high feedback,
            // plus a slow chorus wobble on the chord.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .pingPong,
                delaySync: TempoSyncOption(.quarter, .dotted),
                delayMix: 0.42, delayFeedback: 0.58, delayTone: 0.22, delaySpread: 0.45,
                chorusEnabled: true, chorusRate: 0.35, chorusDepth: 0.5, chorusMix: 0.4,
                reverbEnabled: true, reverbMix: 0.22, reverbRoom: 0.82, reverbDamping: 0.60)
        case .trap:
            // Mostly dry; just a short triplet slap for depth.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.eighth, .triplet),
                delayMix: 0.16, delayFeedback: 0.20, delayTone: 0.70, delaySpread: 0.2)
        case .vaporwave:
            // Tape echo + lush slow chorus — washed-out and nostalgic.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.quarter),
                delayMix: 0.36, delayFeedback: 0.42, delayTone: 0.34, delaySpread: 0.4,
                delayWow: 0.5, delayDrive: 0.2,
                chorusEnabled: true, chorusRate: 0.28, chorusDepth: 0.7, chorusMix: 0.5,
                reverbEnabled: true, reverbMix: 0.28, reverbRoom: 0.80, reverbDamping: 0.50)
        case .eighties:
            // Big chorus, bright dotted-eighth delay.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.eighth, .dotted),
                delayMix: 0.24, delayFeedback: 0.28, delayTone: 0.62, delaySpread: 0.35,
                chorusEnabled: true, chorusRate: 0.6, chorusDepth: 0.7, chorusMix: 0.5,
                reverbEnabled: true, reverbMix: 0.16, reverbRoom: 0.70, reverbDamping: 0.45)
        case .disco:
            // Light chorus, short tight delay.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.sixteenth),
                delayMix: 0.15, delayFeedback: 0.16, delayTone: 0.6, delaySpread: 0.25,
                chorusEnabled: true, chorusRate: 0.5, chorusDepth: 0.4, chorusMix: 0.3,
                reverbEnabled: true, reverbMix: 0.12, reverbRoom: 0.65, reverbDamping: 0.45)
        case .synthwave:
            // Wide ping-pong dotted-eighth + chorus — neon-night drive.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .pingPong,
                delaySync: TempoSyncOption(.eighth, .dotted),
                delayMix: 0.30, delayFeedback: 0.38, delayTone: 0.62, delaySpread: 0.55,
                chorusEnabled: true, chorusRate: 0.4, chorusDepth: 0.6, chorusMix: 0.4,
                reverbEnabled: true, reverbMix: 0.18, reverbRoom: 0.74, reverbDamping: 0.40)
        case .earlySynth:
            // Berlin-school sequencer echo: ping-pong straight eighths.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .pingPong,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.30, delayFeedback: 0.46, delayTone: 0.5, delaySpread: 0.6)
        case .futuristic:
            // Bright shimmering long delay + subtle chorus.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.quarter, .dotted),
                delayMix: 0.40, delayFeedback: 0.42, delayTone: 0.82, delaySpread: 0.5,
                chorusEnabled: true, chorusRate: 0.25, chorusDepth: 0.5, chorusMix: 0.3,
                reverbEnabled: true, reverbMix: 0.26, reverbRoom: 0.82, reverbDamping: 0.35)
        case .sciFi:
            // Slow phaser sweep over a long, dark tape delay — deep space.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.half),
                delayMix: 0.45, delayFeedback: 0.50, delayTone: 0.4, delaySpread: 0.5,
                delayWow: 0.4, delayDrive: 0.15,
                phaserEnabled: true, phaserRate: 0.12, phaserDepth: 0.7, phaserMix: 0.5,
                reverbEnabled: true, reverbMix: 0.30, reverbRoom: 0.86, reverbDamping: 0.50)
        case .psytrance:
            // The psy roll: fast ping-pong sixteenth echo.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .pingPong,
                delaySync: TempoSyncOption(.sixteenth),
                delayMix: 0.30, delayFeedback: 0.46, delayTone: 0.6, delaySpread: 0.5)
        case .esotericMeditation:
            // Long, dark, spacious half-note delay + very slow chorus.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.half),
                delayMix: 0.40, delayFeedback: 0.45, delayTone: 0.30, delaySpread: 0.4,
                chorusEnabled: true, chorusRate: 0.15, chorusDepth: 0.5, chorusMix: 0.35,
                reverbEnabled: true, reverbMix: 0.34, reverbRoom: 0.88, reverbDamping: 0.60)
        case .classical:
            // Pristine — almost no drive, so the chamber tone stays clean.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.quarter),
                delayMix: 0.20, delayFeedback: 0.25, delayTone: 0.45, delaySpread: 0.30,
                saturation: 0.10,
                reverbEnabled: true, reverbMix: 0.26, reverbRoom: 0.82, reverbDamping: 0.45)
        case .jazz:
            // Warm but clean — a touch of tube glue on the Rhodes.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.16, delayFeedback: 0.20, delayTone: 0.55, delaySpread: 0.25,
                chorusEnabled: true, chorusRate: 0.30, chorusDepth: 0.3, chorusMix: 0.20,
                saturation: 0.20)
        case .klezmer:
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.18, delayFeedback: 0.22, delayTone: 0.60, delaySpread: 0.30)
        case .oriental:
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.quarter),
                delayMix: 0.30, delayFeedback: 0.40, delayTone: 0.40, delaySpread: 0.40,
                delayWow: 0.40, delayDrive: 0.15,
                reverbEnabled: true, reverbMix: 0.20, reverbRoom: 0.76, reverbDamping: 0.50)
        case .punk:
            // Raw and driven — heavy saturation for buzzsaw bite.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.sixteenth),
                delayMix: 0.10, delayFeedback: 0.12, delayTone: 0.60, delaySpread: 0.15,
                saturation: 0.60)
        case .rocknroll:
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.18, delayFeedback: 0.20, delayTone: 0.55, delaySpread: 0.20,
                delayWow: 0.30, delayDrive: 0.20,
                saturation: 0.45)
        case .rock:
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.eighth, .dotted),
                delayMix: 0.20, delayFeedback: 0.26, delayTone: 0.55, delaySpread: 0.35,
                saturation: 0.50)
        case .ska:
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.sixteenth),
                delayMix: 0.12, delayFeedback: 0.14, delayTone: 0.60, delaySpread: 0.20,
                saturation: 0.32)
        case .rocksteady:
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.20, delayFeedback: 0.28, delayTone: 0.45, delaySpread: 0.25,
                delayWow: 0.35, delayDrive: 0.10)
        case .heavyMetal:
            // High-gain rig — the most driven preset.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.sixteenth),
                delayMix: 0.12, delayFeedback: 0.18, delayTone: 0.50, delaySpread: 0.20,
                saturation: 0.68)
        case .doom:
            // Thick, slow wall of drive.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.half),
                delayMix: 0.40, delayFeedback: 0.50, delayTone: 0.30, delaySpread: 0.40,
                delayWow: 0.40, delayDrive: 0.30,
                saturation: 0.55,
                reverbEnabled: true, reverbMix: 0.24, reverbRoom: 0.86, reverbDamping: 0.62)
        case .selfObservation:
            // THE Fläche (founder 2026-07-07: "Mehr atmosphärische Stimmung durch
            // Hall und Tape Delay, langsamere Vibes"): a slow, wide TAPE echo —
            // half note at ~58 BPM ≈ 2 s, gentle wow so the repeats breathe like
            // tape, a touch of drive for warmth — blooming into a big, dark hall.
            // Feedback stays < 0.5 so the tail washes without ever building up;
            // the slow chorus keeps the pad's stereo width alive between echoes.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.half),
                delayMix: 0.34, delayFeedback: 0.45, delayTone: 0.28, delaySpread: 0.45,
                delayWow: 0.25, delayDrive: 0.15,
                chorusEnabled: true, chorusRate: 0.12, chorusDepth: 0.35, chorusMix: 0.25,
                reverbEnabled: true, reverbMix: 0.44, reverbRoom: 0.94, reverbDamping: 0.42)
        }
    }
}

/// A hand-built production effect *character* the producer can stamp on a take
/// while making loops/samples/tracks — independent of genre. `.auto` defers to
/// the genre's own `fxPreset`; the others impose a strong, recognisable colour
/// (the muffled "Underwater", a "Telephone" band-pass, tape "Cassette", dusty
/// "Vinyl", wide "Dream", barking "Megaphone").
public enum FXCharacter: String, CaseIterable, Sendable, Identifiable {
    case auto
    case clean
    case underwater
    case telephone
    case cassette
    case vinyl
    case dream
    case megaphone
    case blurry
    case harmonizer
    case room
    case hall

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto:       return "Auto (genre)"
        case .clean:      return "Clean (dry)"
        case .underwater: return "Underwater"
        case .telephone:  return "Telephone"
        case .cassette:   return "Cassette"
        case .vinyl:      return "Vinyl"
        case .dream:      return "Dream"
        case .megaphone:  return "Megaphone"
        case .blurry:     return "Blurry"
        case .harmonizer: return "Harmonizer"
        case .room:       return "Room"
        case .hall:       return "Hall"
        }
    }

    /// One-line description for the picker.
    public var blurb: String {
        switch self {
        case .auto:       return "Use the genre's own effect space"
        case .clean:      return "No effects — reset to a dry signal"
        case .underwater: return "Submerged: deep low-pass + watery chorus + tape wobble"
        case .telephone:  return "Narrow band-pass — old-phone / lo-fi vocal"
        case .cassette:   return "Warm tape: gentle low-pass + wow & flutter"
        case .vinyl:      return "Dusty record: softened highs, subtle width"
        case .dream:      return "Wide and bright: lush chorus + long ping-pong"
        case .megaphone:  return "Barking band-pass + saturated slap"
        case .blurry:     return "Soft-focus wash: low-pass + deep chorus + smeared echo"
        case .harmonizer: return "Adds harmony voices: a third + fifth above the melody"
        case .room:       return "Tight, natural room — adds depth without washing out"
        case .hall:       return "Large, lush concert hall — long, bright reverb tail"
        }
    }

    /// The effect preset for this character. `nil` for `.auto` — the caller
    /// should fall back to the genre's `fxPreset`.
    public var preset: GenreFXPreset? {
        switch self {
        case .auto:
            return nil
        case .clean:
            // Everything off — a dry reset, including saturation. The safety
            // limiter (not touched by a preset) stays on.
            return GenreFXPreset(filterEnabled: false, delayEnabled: false,
                                 chorusEnabled: false, phaserEnabled: false,
                                 saturation: 0)
        case .underwater:
            return GenreFXPreset(
                filterEnabled: true, filterMode: .lowpass, filterCutoff: 650, filterResonance: 0.35,
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.quarter),
                delayMix: 0.35, delayFeedback: 0.45, delayTone: 0.20, delaySpread: 0.45,
                delayWow: 0.6, delayDrive: 0.2,
                chorusEnabled: true, chorusRate: 0.22, chorusDepth: 0.8, chorusMix: 0.5)
        case .telephone:
            return GenreFXPreset(
                filterEnabled: true, filterMode: .bandpass, filterCutoff: 1500, filterResonance: 0.45,
                delayEnabled: false)
        case .cassette:
            return GenreFXPreset(
                filterEnabled: true, filterMode: .lowpass, filterCutoff: 7000, filterResonance: 0.18,
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.16, delayFeedback: 0.30, delayTone: 0.45, delaySpread: 0.25,
                delayWow: 0.45, delayDrive: 0.25)
        case .vinyl:
            return GenreFXPreset(
                filterEnabled: true, filterMode: .lowpass, filterCutoff: 5500, filterResonance: 0.15,
                delayEnabled: false,
                chorusEnabled: true, chorusRate: 0.2, chorusDepth: 0.3, chorusMix: 0.22)
        case .dream:
            return GenreFXPreset(
                delayEnabled: true, delayMode: .pingPong,
                delaySync: TempoSyncOption(.quarter, .dotted),
                delayMix: 0.40, delayFeedback: 0.45, delayTone: 0.82, delaySpread: 0.6,
                chorusEnabled: true, chorusRate: 0.30, chorusDepth: 0.7, chorusMix: 0.5,
                reverbEnabled: true, reverbMix: 0.32, reverbRoom: 0.86, reverbDamping: 0.40)
        case .megaphone:
            return GenreFXPreset(
                filterEnabled: true, filterMode: .bandpass, filterCutoff: 1800, filterResonance: 0.55,
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.sixteenth),
                delayMix: 0.14, delayFeedback: 0.22, delayTone: 0.6, delaySpread: 0.15,
                delayDrive: 0.5,
                saturation: 0.55)
        case .blurry:
            return GenreFXPreset(
                filterEnabled: true, filterMode: .lowpass, filterCutoff: 2200, filterResonance: 0.20,
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.30, delayFeedback: 0.50, delayTone: 0.35, delaySpread: 0.55,
                delayWow: 0.55, delayDrive: 0.15,
                chorusEnabled: true, chorusRate: 0.45, chorusDepth: 0.9, chorusMix: 0.6)
        case .harmonizer:
            // Stacked third + fifth over a lightly-driven dry tone, with a touch
            // of chorus to glue the harmony voices into an ensemble.
            return GenreFXPreset(
                chorusEnabled: true, chorusRate: 0.3, chorusDepth: 0.4, chorusMix: 0.25,
                saturation: 0.25,
                harmonizerEnabled: true,
                harmonizerInterval1: 4, harmonizerInterval2: 7,
                harmonizerVoice2: true, harmonizerMix: 0.55)
        case .room:
            // A tight, natural space — short tail, gentle warmth, no delay wash.
            return GenreFXPreset(
                saturation: 0.22,
                reverbEnabled: true, reverbMix: 0.24, reverbRoom: 0.45, reverbDamping: 0.55)
        case .hall:
            // A large, bright concert hall — long tail over a soft quarter delay.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.quarter),
                delayMix: 0.18, delayFeedback: 0.30, delayTone: 0.6, delaySpread: 0.5,
                saturation: 0.20,
                reverbEnabled: true, reverbMix: 0.38, reverbRoom: 0.90, reverbDamping: 0.30)
        }
    }

    /// Apply this character to a live chain at `bpm`. For `.auto`, applies the
    /// supplied `genre`'s preset instead.
    public func apply(to chain: EchoelFXChain, bpm: Double, genre: MusicStyle) {
        (preset ?? genre.fxPreset).apply(to: chain, bpm: bpm)
    }
}
