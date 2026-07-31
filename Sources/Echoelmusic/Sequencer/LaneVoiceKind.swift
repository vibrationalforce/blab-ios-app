// LaneVoiceKind.swift
// Multi-Roll (B10) — the PURE decision layer: which concrete Echoel voice CLASS a
// lane's built-in instrument plays through. The device LaneVoiceRack reads this to
// instantiate the right voice per slot (PolySynthVoice / SamplerVoice / SubBassVoice /
// BioReactiveSynthVoice) instead of always a PolySynthVoice. No engine, no audio —
// a pure classifier, unit-tested on every platform.
// (⛔ `DrumSynthVoice` was in that list until #167, founder 2026-07-27.)

import Foundation

/// The concrete voice family a lane plays through. Each maps to ONE real voice class
/// the app already ships. Raw values are stable (may persist in routing state).
public enum LaneVoiceKind: String, Sendable, CaseIterable, Equatable {
    case poly       // PolySynthVoice — pads / chords / lead
    // ⛔ #167 (founder 2026-07-27, "erstmal gar nicht mehr rein"): the drum voices are
    //    DELETED and `.drums` allocates to poly like any unit-less kind.
    //    ⚠️ AN EARLIER VERSION OF THIS COMMENT SAID "it is a persisted rawValue, an unknown
    //    one discards the whole lane — do NOT remove it". BOTH HALVES WERE FALSE, and a
    //    "Do NOT remove" a future session cannot disprove is worse than no comment at all.
    //    `LaneVoiceKind` is NOT `Codable` (see the declaration above — String-raw, but no
    //    Codable conformance) and never reaches disk; `Timeline.swift` says so itself in the
    //    schemaVersion doc. The ONE persisted lane enum carrying `.drums` is
    //    `TrackInstrument`, in a different file.
    //    THE TRUTH ABOUT THIS CASE: nothing in `Sources/` constructs it any more —
    //    `TrackInstrument.drums.voiceKind` returns `.poly` (below), and `MultiRollFanout`
    //    is the only production producer feeding `setKind`. It is a DEAD case, kept
    //    pending an explicit decision (#167 follow-up), not protected by any rule.
    //    Deleting it is safe and is a separate, gate-verified slice — not a reason to keep.
    case drums      // dead: no voice, no producer; allocator falls back to poly
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
    /// ⛔ "the enum is persisted in places" stood here and is FALSE — `LaneVoiceKind` has no
    /// `Codable` conformance and never reaches disk. `LaneVoiceKind.drums` still EXISTS, but
    /// this switch is why nothing produces it: every `TrackInstrument` maps away from it.
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
