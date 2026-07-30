// BioTempoDirector.swift
// Echoel — the BIO-TEMPO LANE model (founder "BPM both": musical time is the master,
// BPM-lock is the default, and an OPTIONAL lane lets the transport tempo breathe with the
// live pulse). Q5 of the comprehensive interface.
//
// This is the PURE, deterministic model only — it computes the next transport tempo from
// the live body; a later cycle feeds its output into `Transport.tempo` (device pass). It is
// deliberately NOT wired to playback yet, so it carries zero regression risk.
//
// Two axes are kept separate on purpose:
//   • TransportClockSource (internal/midi/link) = WHO is the timing master (sync topology).
//   • TempoMode (locked/bioFollow)              = WHAT sets the tempo value (this file).
// They compose: a bio-follow tempo can still be the internal clock's tempo.

import Foundation

/// Whether the transport tempo is a fixed musical lock or follows the body.
public enum TempoMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The founder's default — a fixed musical tempo; the body speaks through
    /// composition/FX/visuals, not by dragging the grid around.
    case locked
    /// The transport tempo GLIDES toward the live heartbeat (optional lane). As
    /// coherence rises it is drawn toward the resonance band, so a settling body
    /// pulls the groove into entrainment instead of merely mirroring a racing pulse.
    case bioFollow

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .locked:    return "BPM lock"
        case .bioFollow: return "Follow pulse"
        }
    }
}

/// Pure, deterministic resolver for the transport tempo. Holds the mode + the locked
/// tempo; `nextTempo` glides from the previous tempo toward the mode's target so the beat
/// never lurches on a single noisy heart-rate reading.
public struct BioTempoDirector: Sendable, Equatable, Codable {

    public var mode: TempoMode
    /// The musical BPM used in `.locked` (and the resting value bio-follow starts from).
    public var lockedTempo: Double
    /// Glide time constant in seconds — how fast the tempo eases toward its target. Larger
    /// = smoother/slower (the beat won't chase every heartbeat wobble). ~4 s is musical.
    public var glideSeconds: Double

    /// Musical tempo bounds — reference Transport (the single owner of the range),
    /// not a hand-copied literal, so the three tempo sites can never drift.
    public static let minTempo: Double = Transport.minTempo
    public static let maxTempo: Double = Transport.maxTempo
    /// The parasympathetic resonance target (6 breaths/min × 12) the pulse is pulled
    /// toward as coherence rises — the same band the composer entrains to.
    public static let resonanceBPM: Double = 72

    public init(mode: TempoMode = .locked,
                lockedTempo: Double = 120,
                glideSeconds: Double = 4) {
        self.mode = mode
        self.lockedTempo = Self.clampTempo(lockedTempo)
        self.glideSeconds = Swift.max(0, glideSeconds)
    }

    /// The instantaneous TARGET tempo for the current body state (before glide).
    /// `.locked` ignores the body. `.bioFollow` uses the clamped heartbeat, pulled toward
    /// the resonance band by coherence (0 → pure heartbeat, 1 → full resonance).
    public func targetTempo(heartRateBPM: Double, coherence: Double) -> Double {
        switch mode {
        case .locked:
            return Self.clampTempo(lockedTempo)
        case .bioFollow:
            // NOT `frame.hasMeasuredHeartRate`: this type takes a loose `heartRateBPM`
            // parameter, not a `BioSampleFrame`, so the hoisted predicate is out of reach here.
            // Left as the literal deliberately (#244) rather than widening the signature.
            let hr = Self.clampTempo(heartRateBPM > 0 ? heartRateBPM : lockedTempo)
            let c = Swift.min(Swift.max(coherence, 0), 1)
            let pulled = hr * (1 - c) + Self.resonanceBPM * c
            return Self.clampTempo(pulled)
        }
    }

    /// The next transport tempo: one-pole glide from `previous` toward the current target
    /// over `glideSeconds`, advanced by `dt` seconds. `dt <= 0` or `glideSeconds == 0`
    /// snaps to the target. Deterministic and allocation-free — safe to call anywhere.
    public func nextTempo(previous: Double,
                          heartRateBPM: Double,
                          coherence: Double,
                          dt: Double) -> Double {
        let target = targetTempo(heartRateBPM: heartRateBPM, coherence: coherence)
        guard glideSeconds > 0, dt > 0 else { return target }
        // One-pole: fraction of the remaining distance closed this step.
        let alpha = 1 - exp(-dt / glideSeconds)
        let prev = Self.clampTempo(previous)
        return Self.clampTempo(prev + (target - prev) * alpha)
    }

    public static func clampTempo(_ bpm: Double) -> Double {
        guard bpm.isFinite else { return minTempo }
        return Swift.min(Swift.max(bpm, minTempo), maxTempo)
    }
}
