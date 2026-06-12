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

    public init(
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
        phaserMix: Float = 0.4
    ) {
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
    }

    /// Delay-line capacity in the chain (EchoelDelay default). The synced time is
    /// clamped to this so a whole note at a slow tempo never overruns the buffer.
    private static let maxDelaySeconds: Float = 2.0

    /// Write this preset onto a live chain, resolving the synced delay time at
    /// `bpm`. Safe to call from the main actor; the chain reads are audio-thread
    /// atomic-width scalars.
    public func apply(to chain: EchoelFXChain, bpm: Double) {
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
    }
}

public extension MusicStyle {

    /// The effect space this genre is generated through. Applied to the melody
    /// voice on Generate, then editable in the FX tool.
    var fxPreset: GenreFXPreset {
        switch self {
        case .dubTechno:
            // The signature: a long, dark, swung dub delay with high feedback,
            // plus a slow chorus wobble on the chord.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .pingPong,
                delaySync: TempoSyncOption(.quarter, .dotted),
                delayMix: 0.42, delayFeedback: 0.58, delayTone: 0.22, delaySpread: 0.45,
                chorusEnabled: true, chorusRate: 0.35, chorusDepth: 0.5, chorusMix: 0.4)
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
                chorusEnabled: true, chorusRate: 0.28, chorusDepth: 0.7, chorusMix: 0.5)
        case .eighties:
            // Big chorus, bright dotted-eighth delay.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.eighth, .dotted),
                delayMix: 0.24, delayFeedback: 0.28, delayTone: 0.62, delaySpread: 0.35,
                chorusEnabled: true, chorusRate: 0.6, chorusDepth: 0.7, chorusMix: 0.5)
        case .disco:
            // Light chorus, short tight delay.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.sixteenth),
                delayMix: 0.15, delayFeedback: 0.16, delayTone: 0.6, delaySpread: 0.25,
                chorusEnabled: true, chorusRate: 0.5, chorusDepth: 0.4, chorusMix: 0.3)
        case .synthwave:
            // Wide ping-pong dotted-eighth + chorus — neon-night drive.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .pingPong,
                delaySync: TempoSyncOption(.eighth, .dotted),
                delayMix: 0.30, delayFeedback: 0.38, delayTone: 0.62, delaySpread: 0.55,
                chorusEnabled: true, chorusRate: 0.4, chorusDepth: 0.6, chorusMix: 0.4)
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
                chorusEnabled: true, chorusRate: 0.25, chorusDepth: 0.5, chorusMix: 0.3)
        case .sciFi:
            // Slow phaser sweep over a long, dark tape delay — deep space.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.half),
                delayMix: 0.45, delayFeedback: 0.50, delayTone: 0.4, delaySpread: 0.5,
                delayWow: 0.4, delayDrive: 0.15,
                phaserEnabled: true, phaserRate: 0.12, phaserDepth: 0.7, phaserMix: 0.5)
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
                chorusEnabled: true, chorusRate: 0.15, chorusDepth: 0.5, chorusMix: 0.35)
        case .selfObservation:
            // Subtle and clean — a calm quarter-note space, gentle width.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.quarter),
                delayMix: 0.24, delayFeedback: 0.30, delayTone: 0.35, delaySpread: 0.3,
                chorusEnabled: true, chorusRate: 0.2, chorusDepth: 0.4, chorusMix: 0.3)
        }
    }
}
