// DiatonicHarmonyFollower.swift
// Echoelmusic — Tools (the key-aware harmonizer, VL2 wired — #599b)
//
// The founder's "an die Tonart gekoppelt" question, answered where it is musically
// true: NOT the feedback notch (room physics, never key-coupled — see
// AudioEngine's guard-tick doc) but the HARMONIZER. With "Follow the key" on, the
// two harmony voices stop being fixed semitone offsets and become the diatonic
// third and fifth ABOVE THE NOTE SOUNDING NOW — a third above E in C major is G
// (+3), not G# (+4). The maths is `VoiceHarmony` (Sequencer/, pure, shipped with
// #599's guard pinning it); this type is only the ~10 Hz control-plane bridge:
// `EngineBus.latestMusical` (the loudest sounding note + the key the studio
// publishes) → `VoiceHarmony.interval` → `EchoelHarmonizer.interval1/2` on every
// attached chain. No audio-thread work — interval writes are the same
// control-plane didSet the FX panel's own rows use.
//
// OWNERSHIP (the FXBioModulator lesson, simplified): while ON, this follower
// overwrites the chains' intervals every tick, so the panel HIDES its two
// interval rows (a control that lies is worse than none). On turning OFF, the
// RESTORE is owned by the toggle's own action in EchoelFXView — it re-fans the
// view-model's stored intervals (the user's source of truth, which this type
// never touches), so a preset recalled mid-follow restores to ITS values, not to
// a stale baseline captured at enable time. This type deliberately holds NO
// baseline state.
//
// NOT persisted, same law as monitoring/Tune-to-key: following is a performance
// act. Fresh launch starts with fixed intervals.

import Foundation

@MainActor
@Observable
public final class DiatonicHarmonyFollower {

    /// Whether the harmony voices follow the key. Flipping this starts/stops the
    /// ~10 Hz tick; turning it OFF does NOT restore intervals — the FX panel's
    /// toggle action owns that (see header).
    public var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            if enabled { startTicking() } else { stopTicking() }
        }
    }

    @ObservationIgnored private var chains: [EchoelFXChain] = []
    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private var a4Provider: (@MainActor () -> Double)?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    public init() {}

    /// Same chain inventory as `FXBioModulator.attach` — every chain the character
    /// menu configures, or one body's harmony follows while the other's stands still
    /// (the #386 split-reach defect, one system over).
    public func attach(chains: [EchoelFXChain], bus: EngineBus,
                       a4Hz: @escaping @MainActor () -> Double) {
        self.chains = chains
        self.bus = bus
        self.a4Provider = a4Hz
    }

    /// The pure decision, exposed for the guard's END-TO-END tests: given the
    /// sounding lead and the published key, the semitone offsets for a diatonic
    /// third and fifth above it. nil when the frame carries no usable key/lead
    /// (unknown scale, no root, unvoiced) — the harmonizer then keeps its last
    /// intervals rather than snapping to a guess.
    nonisolated public static func diatonicIntervals(leadHz: Double, a4Hz: Double,
                                                     rootPitchClass: Int,
                                                     scaleName: String) -> (third: Int, fifth: Int)? {
        guard leadHz.isFinite, leadHz > 0, a4Hz.isFinite, a4Hz > 0,
              rootPitchClass >= 0, let scale = Scale(rawValue: scaleName)
        else { return nil }
        let fracMidi = 69.0 + 12.0 * log2(leadHz / a4Hz)
        guard fracMidi.isFinite, fracMidi > 0, fracMidi < 128 else { return nil }
        let midi = Int(fracMidi.rounded())
        let key = MusicalKey(root: rootPitchClass, scale: scale)
        return (VoiceHarmony.interval(from: midi, degreesUp: 2, key: key),
                VoiceHarmony.interval(from: midi, degreesUp: 4, key: key))
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 100_000_000)   // ~10 Hz
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick() {
        guard enabled, let frame = bus?.latestMusical,
              let a4 = a4Provider?(),
              let lead = frame.notes.max(by: { $0.amplitude < $1.amplitude }),
              let iv = Self.diatonicIntervals(leadHz: lead.frequencyHz, a4Hz: a4,
                                              rootPitchClass: frame.rootPitchClass,
                                              scaleName: frame.scaleName)
        else { return }
        for c in chains {
            c.harmonizer.interval1 = Float(iv.third)
            c.harmonizer.interval2 = Float(iv.fifth)
        }
    }
}
