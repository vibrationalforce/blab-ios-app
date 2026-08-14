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
            if enabled {
                // #599b review M1: capture the user's interval truth at the moment
                // following begins — at this instant chain == view-model == user.
                baseline = chains.first.map { ($0.harmonizer.interval1, $0.harmonizer.interval2) }
                startTicking()
            } else {
                stopTicking()
                baseline = nil
            }
        }
    }

    /// The user's interval truth while following (#599b review M1). It exists because
    /// the chains are this type's SCRATCHPAD while ON, yet a REOPENED FX sheet seeds a
    /// fresh view-model from the chains — without this, toggling off after a reopen
    /// re-fanned diatonic scratch values as if the user had chosen them. The view's
    /// `.onAppear` repairs its seed from here; `rebaseline` refreshes it when a
    /// preset/character apply changes the truth mid-follow. The RESTORE path stays the
    /// view's re-fan of its view-model — this baseline only repairs the SEED.
    public private(set) var baseline: (interval1: Float, interval2: Float)?

    /// Refresh the baseline after a preset/character apply while following — the
    /// view-model just took the preset's values (one synchronous MainActor stretch,
    /// no tick can interleave), so THEY are the truth a later seed-repair must show.
    public func rebaseline(interval1: Float, interval2: Float) {
        guard enabled else { return }
        baseline = (interval1, interval2)
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
        // Explicit @MainActor + self-terminating loop (#599b review 3/4, the
        // FXBioModulator shape): `self?.tick()` alone would leave a deallocated
        // follower's loop spinning as a 10 Hz no-op forever — the weak self ends
        // the WORK, not the LOOP; the guard ends both.
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                self.tick()
                try? await Task.sleep(nanoseconds: 100_000_000)   // ~10 Hz
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick() {
        // `latestMusical`, not a freshness-gated read — DELIBERATE hold semantics
        // (review 6): after Stop the follower keeps the last note's intervals
        // rather than snapping anywhere; the next publish retunes it. A key change
        // while stopped lands with the first new frame.
        guard enabled, let frame = bus?.latestMusical,
              let a4 = a4Provider?(),
              let lead = frame.notes.max(by: { $0.amplitude < $1.amplitude }),
              let iv = Self.diatonicIntervals(leadHz: lead.frequencyHz, a4Hz: a4,
                                              rootPitchClass: frame.rootPitchClass,
                                              scaleName: frame.scaleName)
        else { return }
        // Equality-gated (#599b review 5): the didSet recomputes the ratio and
        // stores across to the render thread — on a held note that is a redundant
        // powf + cross-thread store every 100 ms for nothing.
        let t1 = Float(iv.third), t2 = Float(iv.fifth)
        for c in chains {
            if c.harmonizer.interval1 != t1 { c.harmonizer.interval1 = t1 }
            if c.harmonizer.interval2 != t2 { c.harmonizer.interval2 = t2 }
        }
    }
}
