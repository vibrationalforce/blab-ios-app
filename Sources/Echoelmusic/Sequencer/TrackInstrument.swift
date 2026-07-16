// TrackInstrument.swift
// Echoel — the built-in instrument a track plays, and what a track's record button
// captures (founder 2026-07-13: "EchoelDrums, Echoelbreak, EchoelSampler etc fehlen"
// + "jede Spur soll ein record Button haben der entsprechend verknüpft ist. Audio für
// Audio Inputs, Midi für Midi Input die Biofeedback Instrumente").
//
// PURE value model — no engine, no audio, no SwiftUI. It names the tracks after the
// app's OWN instruments (the voices that already exist: DrumSynthVoice/BeatPlayer,
// LoopCutter break, SamplerVoice, PolySynthVoice, SubBassVoice, BioReactiveSynthVoice)
// and derives each track's record INPUT source from its kind + instrument. The
// per-lane capture engine (audio-in / MIDI-in / bio recorders) rides this rail next,
// device-verified; this is the honest, Linux-CI-tested foundation + the visible menu.

import Foundation

/// A built-in Echoel instrument a MIDI track plays. Raw values persist with the
/// document (@Codable on TimelineLane) — keep them stable.
public enum TrackInstrument: String, Codable, Sendable, CaseIterable, Equatable {
    case drums          // EchoelDrums   — DrumSynthVoice / BeatPlayer kit
    case breakLoop      // EchoelBreak   — LoopCutter breakbeat re-slicing
    case sampler        // EchoelSampler — SamplerVoice one-shots / pitched
    case polySynth      // EchoelSynth   — PolySynthVoice (pad/harmony/lead)
    case subBass        // EchoelBass    — SubBassVoice mono sub
    case bioVoice       // Bio           — BioReactiveSynthVoice (body-driven)

    /// Brand name shown on the track head + Add-Track menu (no wellness/esoteric copy).
    public var displayName: String {
        switch self {
        case .drums:     return "EchoelDrums"
        case .breakLoop: return "EchoelBreak"
        case .sampler:   return "EchoelSampler"
        case .polySynth: return "EchoelSynth"
        case .subBass:   return "EchoelBass"
        case .bioVoice:  return "Bio Instrument"
        }
    }

    /// A one-line description for the menu row (what the instrument is).
    public var subtitle: String {
        switch self {
        case .drums:     return "Drum kit — pads + step sequencer"
        case .breakLoop: return "Breakbeat — loop re-slicing"
        case .sampler:   return "Sampler — your own one-shots"
        case .polySynth: return "Polyphonic synth — pads, chords, lead"
        case .subBass:   return "Sub bass — mono low end"
        case .bioVoice:  return "Bio-reactive voice — driven by your body"
        }
    }

    public var systemImage: String {
        switch self {
        case .drums:     return "square.grid.3x3.fill"
        case .breakLoop: return "waveform.path"
        case .sampler:   return "pianokeys.inverse"
        case .polySynth: return "pianokeys"
        case .subBass:   return "waveform.path.badge.minus"
        case .bioVoice:  return "waveform.path.ecg"
        }
    }

    /// The content kind a track with this instrument carries. Every built-in
    /// instrument is a MIDI-driven voice today (notes/steps → sound), so all are
    /// `.midi` lanes — audio/video are the file-carrying kinds, chosen separately.
    public var clipKind: ClipKind { .midi }

    /// What this instrument's per-track record button captures. Bio instruments
    /// record the biofeedback stream; every other built-in voice records MIDI input.
    public var recordSource: RecordSource {
        switch self {
        case .bioVoice: return .bio
        default:        return .midiInput
        }
    }

    /// The GLOBAL FX bus (TrackFXStore/MixerStore) whose strip HONESTLY reaches
    /// this instrument's voice TODAY (S2, Mix → track heads — founder: "Mix
    /// wird Teil der Spuren in der Timeline"). Review-corrected engine truth
    /// (75e4899 REQUEST_CHANGES): `builtinInstrument` does NOT change the
    /// sound path yet — voiceKind has no consumers; every secondary MIDI lane
    /// plays a rack PolySynthVoice and the primary roll plays synth+leadSynth
    /// WHATEVER its instrument says. So:
    /// - .polySynth → .melodic — and even that is qualified: the melodic
    ///   Filter/Drive reaches the PRIMARY voices (synth+leadSynth) only; the
    ///   rack voices receive no insert yet (S2-W1 wires it), and the pad/lead
    ///   LEVELS bake into the primary take's velocities at compose time.
    /// - drums/breakLoop/sampler/subBass → nil: their buses drive the
    ///   BeatPlayer kit / the primary-roll sub DOUBLING layer — NOT a lane of
    ///   that instrument. A strip there would mute a foreign path while the
    ///   lane keeps sounding (worse than no control). They earn their bus
    ///   only when voiceKind-aware routing ships (S2-W2).
    /// - .bioVoice → nil: no bus touches BioReactiveSynthVoice (verified).
    /// Uses the ONE existing bus enum (FXBus) — no parallel bus type to drift.
    public var fxBus: FXBus? {
        switch self {
        case .polySynth:                             return .melodic
        case .drums, .breakLoop, .sampler, .subBass: return nil
        case .bioVoice:                              return nil
        }
    }
}

/// What a track's record button captures — wired to the track's input (founder:
/// "Audio für Audio Inputs, Midi für Midi Input die Biofeedback Instrumente").
/// Pure classifier; the capture engine per source lands device-verified.
public enum RecordSource: String, Codable, Sendable, CaseIterable, Equatable {
    case audioInput     // a microphone / line-in audio track
    case midiInput      // a MIDI/instrument track (CoreMIDI / on-screen keys)
    case bio            // the biofeedback stream (EngineBus bio frames)
    case videoCapture   // a video track (camera / visual window)
    case none           // nothing to record (e.g. a pure visual lane)

    public var displayName: String {
        switch self {
        case .audioInput:   return "Audio input"
        case .midiInput:    return "MIDI input"
        case .bio:          return "Biofeedback"
        case .videoCapture: return "Video"
        case .none:         return "—"
        }
    }

    public var systemImage: String {
        switch self {
        case .audioInput:   return "mic"
        case .midiInput:    return "pianokeys"
        case .bio:          return "waveform.path.ecg"
        case .videoCapture: return "video"
        case .none:         return "minus"
        }
    }

    /// A record button is only offered where there's a real input to arm.
    public var canRecord: Bool { self != .none }

    /// CLIP-2 (honest arm): the sources TakeRecorder actually CAPTURES today —
    /// MIDI notes and the bio automation lane. Audio (mic) and video capture are
    /// task #13; until their recorders exist, an armed mic/video lane must not
    /// promise a take (pre-fix: the arm lit red, Record ran, Stop committed
    /// NOTHING — silent data loss of a sung performance). Flip a source here
    /// only together with its recorder in `TakeRecorder.begin`.
    public var captureImplemented: Bool {
        self == .midiInput || self == .bio
    }
}
