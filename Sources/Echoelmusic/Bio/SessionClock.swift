//
//  SessionClock.swift
//  Echoelmusic — Bio
//
//  The latency-compensated timing core of the bio-paced Session (warm-restart
//  cycle 3) — the "Latenzausgleich" that makes the tone and the light feel
//  instant AND land together.
//
//  The realtime feeling does NOT come from chasing the sensor (rPPG needs a
//  multi-second window; that only sets the SLOW target). It comes from a locally
//  generated, phase-locked cue: the pulse phase is pure math off ONE shared host
//  clock, zero sensor round-trip. The cue LEADS, the body follows, the sensor
//  slowly confirms — immediate, and never jittery.
//
//  Compensation, per modality, against that one clock:
//   • Everything the user PERCEIVES arrives after a known output delay — audio
//     after `AVAudioSession.outputLatency` + the IO buffer; light after the
//     display pipeline (the CADisplayLink frame is shown in the near future).
//   • So each layer renders the phase it should have at the moment of PERCEPTION:
//     evaluate the shared clock at `now + perceptualDelay`. The acoustic peak and
//     the visible peak then both land on the intended grid instant → they coincide.
//   • Bluetooth audio (150–250 ms) is the one large offender: the caller measures
//     it via `outputLatency` and either compensates it here or steers to the
//     speaker; either way the math below is unchanged.
//
//  Pure functions over `EntrainmentEngine.phase/gate` (themselves render-thread
//  safe): no state, no allocation, fully unit-tested. Measured latencies are
//  clamped to a sane range so a bogus reading can never shove the phase wildly.
//

import Foundation

/// Measured output delays for the two perceived layers, seconds. Both are clamped
/// into a safe range on read via `SessionClock.safeDelay`.
public struct LatencyProfile: Sendable, Equatable {
    /// Audio path: `AVAudioSession.outputLatency` + `ioBufferDuration` (wired ~5–15 ms,
    /// Bluetooth ~150–250 ms).
    public var audioOutputSeconds: Double
    /// Visual path: how far in the future the next frame is actually shown
    /// (`CADisplayLink.targetTimestamp − CACurrentMediaTime()`), typically 1–2 frames.
    public var visualOutputSeconds: Double

    public init(audioOutputSeconds: Double, visualOutputSeconds: Double) {
        self.audioOutputSeconds = audioOutputSeconds
        self.visualOutputSeconds = visualOutputSeconds
    }

    /// A safe default when nothing is measured yet: a couple of ms of audio, one
    /// 60 Hz frame of video.
    public static let unknown = LatencyProfile(audioOutputSeconds: 0.005,
                                               visualOutputSeconds: 1.0 / 60.0)
}

public enum SessionClock {

    /// Largest compensation we will apply — a guard so a bogus/huge measured latency
    /// (or a stale Bluetooth reading) can never throw the phase across many cycles.
    /// 0.5 s covers even worst-case Bluetooth output latency.
    public static let maxCompensationSeconds: Double = 0.5

    /// Clamp a measured delay into [0, maxCompensationSeconds]; NaN/negative → 0.
    public static func safeDelay(_ seconds: Double) -> Double {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Swift.min(maxCompensationSeconds, seconds)
    }

    /// Normalized phase [0,1) to RENDER NOW so the PERCEIVED pulse lands on the grid:
    /// evaluate the shared clock `perceptualDelay` seconds ahead. Pure; render-safe.
    public static func renderPhase(hostSeconds now: Double, hz: Double,
                                   perceptualDelaySeconds: Double,
                                   phaseOffset: Double = 0) -> Double {
        EntrainmentEngine.phase(atSeconds: now + safeDelay(perceptualDelaySeconds),
                                hz: hz, phaseOffset: phaseOffset)
    }

    /// Raised-cosine gate [0,1] to RENDER NOW, latency-compensated. For the audio
    /// isochronic amplitude gate and the visual brightness envelope alike.
    public static func renderGate(hostSeconds now: Double, hz: Double,
                                  perceptualDelaySeconds: Double,
                                  phaseOffset: Double = 0) -> Double {
        EntrainmentEngine.gate(atSeconds: now + safeDelay(perceptualDelaySeconds),
                               hz: hz, phaseOffset: phaseOffset)
    }

    /// The residual perceptual skew (seconds) between the audio peak and the light
    /// peak. Compensated → ~0 (both scheduled to arrive on the grid). Uncompensated
    /// (both rendered at raw `now`) → `|audioLatency − visualLatency|`. This is the
    /// number the Latenzausgleich drives to zero, and what the tests assert.
    public static func perceivedSkewSeconds(_ profile: LatencyProfile,
                                            compensated: Bool) -> Double {
        guard compensated else {
            return abs(safeDelay(profile.audioOutputSeconds) - safeDelay(profile.visualOutputSeconds))
        }
        return 0
    }
}
