// LaneVoiceKind.swift
// Multi-Roll (B10) — the PURE decision layer: which concrete Echoel voice CLASS a
// lane's built-in instrument plays through. The device LaneVoiceRack reads this to
// instantiate the right voice per slot (PolySynthVoice / DrumSynthVoice / SamplerVoice
// / SubBassVoice / BioReactiveSynthVoice) instead of always a PolySynthVoice. No
// engine, no audio — a pure classifier, unit-tested on every platform.

import Foundation

/// The concrete voice family a lane plays through. Each maps to ONE real voice class
/// the app already ships. Raw values are stable (may persist in routing state).
public enum LaneVoiceKind: String, Sendable, CaseIterable, Equatable {
    case poly       // PolySynthVoice — pads / chords / lead
    case drums      // DrumSynthVoice + BeatPlayer kit (incl. breakbeat re-slicing)
    case sampler    // SamplerVoice — one-shots / pitched samples
    case subBass    // SubBassVoice — mono sub
    case bioVoice   // BioReactiveSynthVoice — body-driven timbre

    public var displayName: String {
        switch self {
        case .poly:     return "Poly synth"
        case .drums:    return "Drums"
        case .sampler:  return "Sampler"
        case .subBass:  return "Sub bass"
        case .bioVoice: return "EchoelBodyVibe"
        }
    }
}

public extension TrackInstrument {
    /// The voice class this instrument plays through.
    ///
    /// NO DRUMS (founder 2026-07-26: *"es soll keine Drums geben. Auch nicht im Mixer."*).
    /// `.drums` and `.breakLoop` used to resolve to `.drums`; both now resolve to `.poly`.
    /// This is the choke point that makes the removal hold for DATA as well as UI: the drum
    /// track type can no longer be created in the app, but a project persisted before this
    /// build can still contain one, and without this it would bind to a drum kit and play
    /// percussion behind a mixer that no longer shows it. Resolving to `.poly` keeps such a
    /// lane audible as a melodic voice instead of silently dropping it — a visible change the
    /// user can hear and re-point, rather than a track that mysteriously stops sounding.
    ///
    /// `LaneVoiceKind.drums` itself still exists (the enum is persisted in places) and
    /// `LaneVoiceRack` no longer creates any kit, so nothing can bind to it.
    var voiceKind: LaneVoiceKind {
        switch self {
        case .polySynth: return .poly
        case .drums:     return .poly
        case .breakLoop: return .poly
        case .sampler:   return .sampler
        case .subBass:   return .subBass
        case .bioVoice:  return .bioVoice
        }
    }
}
