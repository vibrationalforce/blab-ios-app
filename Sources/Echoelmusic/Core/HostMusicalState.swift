// HostMusicalState.swift
// Echoelmusic — Core
//
// H9b (PLAN_H9_AU_EFFECT_INSERTS_2026-07-15 §H9b): the lock-free host-state
// MIRROR that feeds hosted AUv3 plugins their musical context. AUv3 hosts hand
// plugins two callback blocks — `musicalContextBlock` (tempo, beat position,
// time signature) and `transportStateBlock` (moving?, sample position) — and
// plugins call them FROM THE RENDER THREAD. The render thread must never take
// a lock or touch @MainActor state, so the blocks read this plain mirror:
//
//   Writers (all @MainActor, control plane): Transport writes tempo /
//   isPlaying / beatPosition on its existing setTempo/play/stop/seek/tick
//   paths (PatternEngine relays every pulse there — the ONE clock);
//   AudioEngine writes sampleRate once at graph setup.
//
//   Readers (render thread): the context blocks installed by AUHostContext —
//   plain reads of word-width values, no locks, no allocation, no ObjC.
//
// Torn reads are a non-issue in practice: iOS 18 floor = arm64, where aligned
// 8-byte loads/stores are single-copy atomic; and every field is advisory
// display/sync data (a beat position one step stale is the documented
// granularity anyway — beatPosition advances per TRANSPORT STEP, a 16th note,
// not per sample; plugins interpolate or simply read tempo).
//
// Foundation-only so the beat maths (`HostBeatMath`) is Linux-CI-tested.

import Foundation

/// The process-wide musical-state mirror. A single shared instance (not
/// injected) is deliberate: its readers are render-thread C blocks installed
/// on many AUs across two hosts — threading an instance through every attach
/// path buys no testability (the maths lives in `HostBeatMath`, pure) and
/// multiplies wiring surface. Writers stay few and named (Transport, engine).
public final class HostMusicalState: @unchecked Sendable {

    public static let shared = HostMusicalState()

    /// Beats per minute (Transport-clamped 30…300). Main-actor written.
    public var tempo: Double = 120
    /// Transport running? (drives the `.moving` transport-state flag).
    public var isPlaying: Bool = false
    /// Beats since play(), quarter-note units, advancing once per transport
    /// step (16th) — the honest granularity of our clock relay.
    public var beatPosition: Double = 0
    /// Hardware sample rate of the master graph (engine-written at setup).
    public var sampleRate: Double = 48_000

    public init() {}
}

/// Pure beat/tempo arithmetic for the host context blocks — Linux-tested.
public enum HostBeatMath {

    /// Transport steps are 16ths (4 per quarter): absolute step → beats.
    public static func beats(fromAbsoluteStep step: Int, stepsPerBeat: Int = 4) -> Double {
        guard stepsPerBeat > 0 else { return 0 }
        return Double(step) / Double(stepsPerBeat)
    }

    /// The beat position of the current measure's downbeat (4/4 default).
    public static func measureDownbeat(beat: Double, beatsPerBar: Double = 4) -> Double {
        guard beatsPerBar > 0, beat.isFinite else { return 0 }
        return (beat / beatsPerBar).rounded(.down) * beatsPerBar
    }

    /// Estimated sample position for a beat position at a tempo — what
    /// `transportStateBlock` reports (an estimate at step granularity; honest,
    /// monotone while playing, never negative).
    public static func samplePosition(beat: Double, tempo: Double, sampleRate: Double) -> Double {
        guard tempo > 0, sampleRate > 0, beat.isFinite, beat >= 0 else { return 0 }
        return beat * (60.0 / tempo) * sampleRate
    }
}
