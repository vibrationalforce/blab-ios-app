// BeatPlayer.swift
// Echoel — Orchestrator that owns the 8 SamplerVoices, wires them to
// PatternEngine.onStep, and attaches them to AudioEngine.
//
// One BeatPlayer instance is owned by EchoelmusicApp and injected into
// the view tree via .environment, so audio survives tab switches.

#if canImport(AVFoundation)
import AVFoundation
import Foundation
import Observation

/// Owns 8 drum voices, the pattern engine, and the wiring between them.
@MainActor
@Observable
public final class BeatPlayer {

    /// Default sample order — must match `Resources/Drums/<Name>.wav`.
    public static let trackNames: [String] = [
        "Kick", "Snare", "ClosedHat", "OpenHat",
        "Clap", "Perc",  "Bass",      "LeadFX"
    ]

    public let pattern: PatternEngine
    public let voices: [SamplerVoice]

    @ObservationIgnored private weak var audioEngine: AudioEngine?
    @ObservationIgnored private var attachedSourceNodes: [AVAudioSourceNode] = []

    public init() {
        self.pattern = PatternEngine()
        self.voices = Self.trackNames.map { _ in SamplerVoice() }
    }

    /// Loads `Resources/Drums/<TrackName>.wav` into each voice. Missing
    /// files are silently skipped — that voice stays silent until a sample
    /// is loaded explicitly via `voices[i].loadSample(from:)`.
    public func loadDefaultSamples() {
        let bundle = Bundle.module
        for (i, name) in Self.trackNames.enumerated() {
            let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "Drums")
                ?? bundle.url(forResource: name, withExtension: "wav")
            guard let url else {
                log.log(.warn, category: .audio, "BeatPlayer: missing drum sample \(name).wav")
                continue
            }
            do {
                try voices[i].loadSample(from: url)
            } catch {
                log.log(.error, category: .audio, "BeatPlayer: failed to load \(name).wav: \(error)")
            }
        }
    }

    /// Attaches all 8 source nodes to the engine and wires the pattern
    /// callback. Idempotent — safe to call multiple times.
    public func attach(to engine: AudioEngine) {
        guard attachedSourceNodes.isEmpty else { return }
        audioEngine = engine
        for voice in voices {
            engine.attachSourceNode(voice.sourceNode)
            attachedSourceNodes.append(voice.sourceNode)
        }
        pattern.onStep = { [weak self] track, _ in
            guard let self, self.voices.indices.contains(track) else { return }
            self.voices[track].fire()
        }
    }

    /// Detaches every source node and clears the pattern callback.
    public func detach() {
        guard let engine = audioEngine else { return }
        for node in attachedSourceNodes {
            engine.detachSourceNode(node)
        }
        attachedSourceNodes.removeAll()
        pattern.onStep = nil
        audioEngine = nil
    }

    /// Manually fires one voice — used by drum-pad taps in BeatTab.
    public func playPad(_ track: Int) {
        guard voices.indices.contains(track) else { return }
        voices[track].fire()
    }
}
#endif
