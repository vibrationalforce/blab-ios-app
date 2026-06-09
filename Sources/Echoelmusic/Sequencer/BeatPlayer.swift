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

    /// Per-pad amp-envelope shape (user-editable sound design).
    public struct PadShape: Codable, Sendable, Equatable {
        public var level: Float = 1.0     // gain multiplier (0…2)
        public var attackMs: Float = 0     // fade-in (0…200)
        public var lengthMs: Float = 0     // 0 = full sample; >0 caps length (20…2000)
    }

    public let pattern: PatternEngine
    public let voices: [SamplerVoice]

    /// Per-track display label: the role name (Kick/Snare/…) by default, or the
    /// imported sample's filename once the user loads a custom sample.
    public private(set) var sampleLabels: [String]

    /// Per-track amp-envelope shapes (Level/Attack/Length), persisted.
    public private(set) var shapes: [PadShape]

    @ObservationIgnored private weak var audioEngine: AudioEngine?
    @ObservationIgnored private var attachedSourceNodes: [AVAudioSourceNode] = []

    public init() {
        self.pattern = PatternEngine()
        self.voices = Self.trackNames.map { _ in SamplerVoice() }
        self.sampleLabels = Self.trackNames
        self.shapes = Self.trackNames.map { _ in PadShape() }
    }

    private static func shapeKey(_ track: Int) -> String { "echoel.beat.shape.\(track)" }

    /// Apply a track's shape to its voice (audio thread reads it on next render).
    private func applyShape(_ track: Int) {
        guard voices.indices.contains(track) else { return }
        let s = shapes[track]
        voices[track].configureShape(level: s.level, attackMs: s.attackMs, lengthMs: s.lengthMs)
    }

    /// Update a pad's sound shape, apply it live, and persist it.
    public func setShape(track: Int, _ shape: PadShape) {
        guard shapes.indices.contains(track) else { return }
        shapes[track] = shape
        applyShape(track)
        if let data = try? JSONEncoder().encode(shape) {
            UserDefaults.standard.set(data, forKey: Self.shapeKey(track))
        }
    }

    /// Audition a pad (one-shot), e.g. from the sound editor's Preview button.
    public func preview(_ track: Int) { playPad(track) }

    /// Restore persisted shapes and apply them. Called after samples load.
    private func restoreShapes() {
        for i in Self.trackNames.indices {
            if let data = UserDefaults.standard.data(forKey: Self.shapeKey(i)),
               let s = try? JSONDecoder().decode(PadShape.self, from: data) {
                shapes[i] = s
            }
            applyShape(i)
        }
    }

    /// True when track `i` is playing a user-imported sample (not the default).
    public func isCustom(_ track: Int) -> Bool {
        sampleLabels.indices.contains(track) && sampleLabels[track] != Self.trackNames[track]
    }

    private static func bookmarkKey(_ track: Int) -> String { "echoel.beat.sample.bookmark.\(track)" }

    /// Resource bundle for the drum WAVs. `Bundle.module` exists only when
    /// built via SwiftPM (`SWIFT_PACKAGE` is defined). The XcodeGen-built
    /// target (used by `testflight.yml`) bundles resources into the main
    /// app bundle instead.
    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    /// Loads `Resources/Drums/<TrackName>.wav` into each voice. Missing
    /// files are silently skipped — that voice stays silent until a sample
    /// is loaded explicitly via `voices[i].loadSample(from:)`.
    public func loadDefaultSamples() {
        let bundle = Self.resourceBundle
        for (i, name) in Self.trackNames.enumerated() {
            let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "Drums")
                ?? bundle.url(forResource: name, withExtension: "wav")
            guard let url else {
                log.log(.warning, category: .audio, "BeatPlayer: missing drum sample \(name).wav")
                continue
            }
            do {
                try voices[i].loadSample(from: url)
            } catch {
                log.log(.error, category: .audio, "BeatPlayer: failed to load \(name).wav: \(error)")
            }
        }
        restoreCustomSamples()
        restoreShapes()
    }

    /// Re-loads any user-imported samples saved as security-scoped bookmarks on
    /// a previous launch, so custom pads persist across app restarts.
    private func restoreCustomSamples() {
        for i in Self.trackNames.indices {
            guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey(i)) else { continue }
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale
            ) else { continue }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if (try? voices[i].loadSample(from: url)) != nil {
                sampleLabels[i] = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    /// Imports a user-chosen audio file into track `track` (from the Files
    /// browser). Handles security-scoped access, loads the sample, and persists
    /// a bookmark so it survives relaunch. Returns true on success.
    @discardableResult
    public func importSample(track: Int, from url: URL) -> Bool {
        guard voices.indices.contains(track) else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try voices[track].loadSample(from: url)
            if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(data, forKey: Self.bookmarkKey(track))
            }
            sampleLabels[track] = url.deletingPathExtension().lastPathComponent
            return true
        } catch {
            log.log(.error, category: .audio, "BeatPlayer: import failed for track \(track): \(error)")
            return false
        }
    }

    /// Restores track `track` to its built-in default sample and clears the
    /// saved bookmark.
    public func resetSample(track: Int) {
        guard voices.indices.contains(track) else { return }
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey(track))
        let name = Self.trackNames[track]
        let bundle = Self.resourceBundle
        if let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "Drums")
            ?? bundle.url(forResource: name, withExtension: "wav") {
            try? voices[track].loadSample(from: url)
        }
        sampleLabels[track] = name
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
        pattern.onStep = { [weak self] track, step in
            guard let self, self.voices.indices.contains(track) else { return }
            self.voices[track].fire(gain: self.pattern.velocity(track: track, step: step))
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
