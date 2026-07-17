// StretchMode.swift
// Echoelmusic — Sequencer
//
// The selectable algorithm/character for the Echoel stretch engine. ONE enum chosen
// per clip (and, over time, per sampler voice / loop / video-sound) — the single facade
// every time-stretch consumer routes through, so quality/character choice is uniform
// app-wide. Each case names a FREE, App-Store-clean executor; the paid/copyleft engines
// surveyed in the #54 deep-research (every zplane élastique tier, Rubber Band GPL,
// SoundTouch LGPL) are excluded by the zero-paid-dependency rule and are NOT cases here.
//
// Pure value type — no AVFoundation. The executor that actually renders each mode lives
// on the audio graph (an AVAudioUnit node); this enum only declares intent.

import Foundation

public enum StretchMode: String, CaseIterable, Codable, Sendable {
    /// Apple spectral phase-vocoder (`AVAudioUnitTimePitch`): tempo conforms, PITCH
    /// PRESERVED. The clean, transparent-ish default. LIVE (wired since #54 Slice A).
    case clean
    /// Tape/turntable character: tempo AND pitch move together. WIRED — rendered on the
    /// same `AVAudioUnitTimePitch` node by compensating pitch to ride the tempo
    /// (`pitch = 1200·log₂(rate)`, see `StretchPlan.tapePitchCents`), so zero graph change.
    /// (An authentic-resampling `AVAudioUnitVarispeed` variant with tape grit is a later
    /// refinement; this delivers the defining pitch-follows-tempo behaviour now.)
    case tape
    /// In-house WSOLA transient-preserving (Ableton "Beats"-style): best on
    /// drums/loops, patent-free own code (`EchoelWSOLA`). Executor: OFFLINE
    /// pre-render in the editor-preview consumer (AudioClipPlayer); the timeline
    /// keeps the honest `.clean` fallback until its own executor slice (see
    /// per-consumer `capabilities` on `StretchPlan.resolve`).
    case beats
    /// Signalsmith Stretch (MIT C++): highest transient fidelity — FOUNDER-GATED
    /// dependency (first C++ in the tree, contained bridge). Executor: approved slice only.
    case studio

    /// Human label for the picker.
    public var displayName: String {
        switch self {
        case .clean:  return "Clean"
        case .tape:   return "Tape"
        case .beats:  return "Beats"
        case .studio: return "Studio"
        }
    }

    /// One-line character description (UI subtitle / tap-to-learn).
    public var characterHint: String {
        switch self {
        case .clean:  return "Pitch preserved — transparent (Apple spectral)."
        case .tape:   return "Pitch follows tempo — tape/turntable feel."
        case .beats:  return "Transient-locked — best on drums & loops."
        case .studio: return "Highest-fidelity transient stretch (Signalsmith)."
        }
    }

    /// Whether pitch is held constant when the tempo is stretched. Only `.tape` lets
    /// pitch move with tempo; the rest are pitch-preserving. NOTE: this is the RAW mode's
    /// property — for what actually renders, read it off `effectiveMode` or (preferably)
    /// take `StretchPlan.resolve(...).preservesPitch`, which already applies the `.clean`
    /// fallback for modes the CALLING CONSUMER can't execute. Configuring an executor
    /// off the raw value would mis-set pitch for a mode that consumer doesn't render.
    public var preservesPitch: Bool { self != .tape }

    /// Executors wired in AT LEAST ONE consumer today. UI MUST offer only these
    /// (a mode no consumer executes would be a lying selector). Which consumer
    /// actually renders a mode is decided per call via `StretchPlan.resolve`'s
    /// `capabilities` — a consumer that can't execute a mode gets the honest
    /// `.clean` fallback, never silence, never a broken control.
    public var isImplemented: Bool {
        switch self {
        case .clean, .tape: return true      // tape = pitch-follows-tempo on the spectral node
        case .beats:        return true      // WSOLA offline pre-render (editor preview)
        case .studio:       return false     // Signalsmith — founder-gated dependency slice
        }
    }

    /// The BASE capability set — what every realtime consumer (timeline lanes,
    /// audition sink) executes on the always-in-chain spectral node.
    public static let baseCapabilities: Set<StretchMode> = [.clean, .tape]
    /// The editor-preview consumer's set: it can additionally pre-render Beats
    /// offline (`AudioClipPlayer` — no realtime constraint on the audition path).
    public static let previewCapabilities: Set<StretchMode> = [.clean, .tape, .beats]

    /// The mode the BASE (realtime) path renders: itself when base-capable, else
    /// the `.clean` baseline. Kept for callers without a capability context;
    /// prefer `StretchPlan.resolve(..., capabilities:)`.
    public var effectiveMode: StretchMode { StretchMode.baseCapabilities.contains(self) ? self : .clean }

    /// The subset a picker should show today (implemented in ≥1 consumer).
    public static var selectable: [StretchMode] { allCases.filter(\.isImplemented) }
}
