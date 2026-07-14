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
        case .bioVoice: return "Bio voice"
        }
    }
}

public extension TrackInstrument {
    /// The voice class this instrument plays through. `breakLoop` has no dedicated
    /// voice class (it is a breakbeat technique over the drum kit), so it resolves to
    /// `.drums` — a reversible default; change here if a dedicated break voice ships.
    var voiceKind: LaneVoiceKind {
        switch self {
        case .polySynth: return .poly
        case .drums:     return .drums
        case .breakLoop: return .drums
        case .sampler:   return .sampler
        case .subBass:   return .subBass
        case .bioVoice:  return .bioVoice
        }
    }
}
