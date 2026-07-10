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

    /// How a pad produces sound: the loaded sample, the synth (modal) voice, or
    /// a blend of the two (`blend` in 0…1 — 0 = all sample, 1 = all synth).
    public enum PadMode: Codable, Sendable, Equatable {
        case sample
        case synth
        case blend(Float)
    }

    public let pattern: PatternEngine
    public let voices: [SamplerVoice]
    /// Parallel synthesized-drum voices (EchoelModalBank), one per pad.
    public let synthVoices: [DrumSynthVoice]
    /// Dedicated voice for auditioning samples in the browser (does not disturb
    /// the kit — auditions play here, not on a pad).
    public let previewVoice: SamplerVoice

    /// Per-track display label: the role name (Kick/Snare/…) by default, or the
    /// imported sample's filename once the user loads a custom sample.
    public private(set) var sampleLabels: [String]

    /// Per-track amp-envelope shapes (Level/Attack/Length), persisted.
    public private(set) var shapes: [PadShape]

    /// Per-track sound source (sample / synth / blend), persisted.
    public private(set) var modes: [PadMode]

    /// Per-track synth (modal) drum params, persisted.
    public private(set) var synthParams: [DrumSynthParams]

    /// Per-channel insert-FX settings (filter + drive), persisted (Channel Rack).
    /// `type` is `ChannelInsertFX.FilterType.rawValue` (0 = off).
    public struct ChannelFX: Codable, Sendable, Equatable {
        public var type: Int = 0
        public var cutoff: Float = 1200
        public var resonance: Float = 0.707
        public var drive: Float = 0
        public init() {}
    }

    /// Per-track insert FX, persisted (Channel Rack). Applied to the sample voice.
    public private(set) var fx: [ChannelFX]

    /// Per-track MUTE — a muted channel never sounds. Persisted (Channel Rack).
    public private(set) var mutes: [Bool]

    /// Per-track SOLO — if ANY channel is soloed, only soloed channels sound.
    /// Persisted (Channel Rack).
    public private(set) var solos: [Bool]

    @ObservationIgnored private weak var audioEngine: AudioEngine?
    @ObservationIgnored private var attachedSourceNodes: [AVAudioSourceNode] = []

    public init() {
        self.pattern = PatternEngine()
        self.voices = Self.trackNames.map { _ in SamplerVoice() }
        self.synthVoices = Self.trackNames.map { _ in DrumSynthVoice() }
        self.previewVoice = SamplerVoice()
        self.sampleLabels = Self.trackNames
        self.shapes = Self.trackNames.map { _ in PadShape() }
        self.modes = Self.trackNames.map { _ in .sample }
        self.synthParams = Self.trackNames.map { _ in DrumSynthParams() }
        self.fx = Self.trackNames.map { _ in ChannelFX() }
        self.mutes = Self.trackNames.map { _ in false }
        self.solos = Self.trackNames.map { _ in false }
    }

    private static func shapeKey(_ track: Int) -> String { "echoel.beat.shape.\(track)" }
    private static func modeKey(_ track: Int) -> String { "echoel.beat.mode.\(track)" }
    private static func synthKey(_ track: Int) -> String { "echoel.beat.synth.\(track)" }
    private static func muteKey(_ track: Int) -> String { "echoel.beat.mute.\(track)" }
    private static func soloKey(_ track: Int) -> String { "echoel.beat.solo.\(track)" }
    private static func fxKey(_ track: Int) -> String { "echoel.beat.fx.\(track)" }

    /// Push a channel's insert-FX params to both its sample and synth voices
    /// (audio thread reads them) so the FX applies regardless of pad mode.
    private func applyFX(_ track: Int) {
        guard fx.indices.contains(track) else { return }
        let f = fx[track]
        if voices.indices.contains(track) {
            voices[track].configureInsertFX(type: f.type, cutoff: f.cutoff,
                                            resonance: f.resonance, drive: f.drive)
        }
        if synthVoices.indices.contains(track) {
            synthVoices[track].configureInsertFX(type: f.type, cutoff: f.cutoff,
                                                 resonance: f.resonance, drive: f.drive)
        }
    }

    /// Update a channel's insert FX, apply it live, and persist (Channel Rack).
    public func setFX(track: Int, _ value: ChannelFX) {
        guard fx.indices.contains(track) else { return }
        fx[track] = value
        applyFX(track)
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: Self.fxKey(track))
        }
    }

    /// Pure mixer rule (testable, no audio): a track sounds when it is not muted
    /// AND (nothing is soloed, OR this track is one of the soloed ones).
    nonisolated public static func shouldSound(track: Int, mutes: [Bool], solos: [Bool]) -> Bool {
        guard mutes.indices.contains(track), solos.indices.contains(track) else { return true }
        if mutes[track] { return false }
        let anySolo = solos.contains(true)
        return !anySolo || solos[track]
    }

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

    /// Set a channel's MUTE and persist it (Channel Rack).
    public func setMute(track: Int, _ on: Bool) {
        guard mutes.indices.contains(track) else { return }
        mutes[track] = on
        UserDefaults.standard.set(on, forKey: Self.muteKey(track))
    }

    /// Set a channel's SOLO and persist it (Channel Rack).
    public func setSolo(track: Int, _ on: Bool) {
        guard solos.indices.contains(track) else { return }
        solos[track] = on
        UserDefaults.standard.set(on, forKey: Self.soloKey(track))
    }

    /// Clear every solo (Channel Rack "exit solo").
    public func clearSolos() {
        for i in solos.indices where solos[i] {
            solos[i] = false
            UserDefaults.standard.set(false, forKey: Self.soloKey(i))
        }
    }

    /// Audition a pad (one-shot), e.g. from the sound editor's Preview button.
    public func preview(_ track: Int) { playPad(track) }

    /// Apply a track's synth params to its synth voice. Main-thread only.
    private func applySynth(_ track: Int) {
        guard synthVoices.indices.contains(track) else { return }
        synthVoices[track].configure(synthParams[track])
    }

    /// Set a pad's sound source (sample / synth / blend) and persist it.
    public func setMode(track: Int, _ mode: PadMode) {
        guard modes.indices.contains(track) else { return }
        modes[track] = mode
        if let data = try? JSONEncoder().encode(mode) {
            UserDefaults.standard.set(data, forKey: Self.modeKey(track))
        }
    }

    /// Update a pad's synth params, apply them live, and persist.
    public func setSynthParams(track: Int, _ params: DrumSynthParams) {
        guard synthParams.indices.contains(track) else { return }
        synthParams[track] = params
        applySynth(track)
        if let data = try? JSONEncoder().encode(params) {
            UserDefaults.standard.set(data, forKey: Self.synthKey(track))
        }
    }

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

    /// Restore persisted modes + synth params and apply them. Called after load.
    private func restoreModesAndSynth() {
        for i in Self.trackNames.indices {
            if let data = UserDefaults.standard.data(forKey: Self.modeKey(i)),
               let m = try? JSONDecoder().decode(PadMode.self, from: data) {
                modes[i] = m
            }
            if let data = UserDefaults.standard.data(forKey: Self.synthKey(i)),
               let p = try? JSONDecoder().decode(DrumSynthParams.self, from: data) {
                synthParams[i] = p
            }
            applySynth(i)
        }
    }

    /// Trigger a pad through its current sound source (sample / synth / blend).
    /// `respectMix` gates on the Channel Rack mute/solo state (sequencer playback);
    /// manual pad auditions pass `false` so an explicit tap always sounds.
    private func trigger(track: Int, gain: Float, respectMix: Bool = true) {
        guard voices.indices.contains(track) else { return }
        // Channel Rack: a muted channel — or a non-soloed one while any solo is
        // active — does not sound. Pure control-plane gate (no audio-graph change).
        if respectMix, !Self.shouldSound(track: track, mutes: mutes, solos: solos) { return }
        switch modes[track] {
        case .sample:
            voices[track].fire(gain: gain)
        case .synth:
            synthVoices[track].fire(gain: gain)
        case .blend(let b):
            let bb = min(max(b, 0), 1)
            voices[track].fire(gain: gain * (1 - bb))
            synthVoices[track].fire(gain: gain * bb)
        }
    }

    /// True when track `i` is playing a user-imported sample (not the default).
    public func isCustom(_ track: Int) -> Bool {
        sampleLabels.indices.contains(track) && sampleLabels[track] != Self.trackNames[track]
    }

    private static func bookmarkKey(_ track: Int) -> String { "echoel.beat.sample.bookmark.\(track)" }
    /// Persists a BUNDLED assignment (built-in drum or category-library sample) so a
    /// pad chosen in the browser survives relaunch — bundle files have no security-
    /// scoped bookmark, so they need their own tiny reference. Value scheme:
    /// "drum:<Name>" (Resources/Drums) or "lib:<Category>/<Name>" (Resources/Samples).
    private static func bundledKey(_ track: Int) -> String { "echoel.beat.sample.bundled.\(track)" }

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
        restoreModesAndSynth()
        restoreMix()
    }

    /// Restore persisted Channel-Rack mute/solo + insert-FX state and apply the FX.
    private func restoreMix() {
        for i in Self.trackNames.indices {
            mutes[i] = UserDefaults.standard.bool(forKey: Self.muteKey(i))
            solos[i] = UserDefaults.standard.bool(forKey: Self.soloKey(i))
            if let data = UserDefaults.standard.data(forKey: Self.fxKey(i)),
               let f = try? JSONDecoder().decode(ChannelFX.self, from: data) {
                fx[i] = f
            }
            applyFX(i)
        }
    }

    /// Re-loads any user-imported samples saved as security-scoped bookmarks on
    /// a previous launch, so custom pads persist across app restarts.
    private func restoreCustomSamples() {
        for i in Self.trackNames.indices {
            guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey(i)) else {
                // No user-imported bookmark → maybe a bundled (browser) assignment.
                restoreBundledAssignment(i)
                continue
            }
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale
            ) else { continue }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if (try? voices[i].loadSample(from: url)) != nil {
                sampleLabels[i] = url.deletingPathExtension().lastPathComponent
                // Refresh a stale bookmark so the sample keeps loading on future
                // launches instead of silently disappearing.
                if stale,
                   let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey(i))
                }
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
            // A user import overrides any bundled assignment on this pad.
            UserDefaults.standard.removeObject(forKey: Self.bundledKey(track))
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
        UserDefaults.standard.removeObject(forKey: Self.bundledKey(track))
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
        for synth in synthVoices {
            engine.attachSourceNode(synth.sourceNode)
            attachedSourceNodes.append(synth.sourceNode)
        }
        engine.attachSourceNode(previewVoice.sourceNode)
        attachedSourceNodes.append(previewVoice.sourceNode)
        pattern.onStep = { [weak self] track, step in
            guard let self else { return }
            self.trigger(track: track, gain: self.pattern.velocity(track: track, step: step))
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

    /// Manually fires one pad — used by drum-pad taps in BeatTab. Routes through
    /// the pad's current sound source (sample / synth / blend).
    public func playPad(_ track: Int) {
        trigger(track: track, gain: 1.0, respectMix: false)
    }

    // MARK: - Sample browser support

    /// The built-in drum samples available to assign to any pad.
    public static let bundledSampleNames: [String] = trackNames

    /// URL for a built-in sample WAV by name (e.g. "Kick").
    public static func bundledSampleURL(_ name: String) -> URL? {
        let bundle = resourceBundle
        return bundle.url(forResource: name, withExtension: "wav", subdirectory: "Drums")
            ?? bundle.url(forResource: name, withExtension: "wav")
    }

    /// Audition a built-in sample on the preview voice (does not touch the kit).
    public func auditionBundled(_ name: String) {
        guard let url = Self.bundledSampleURL(name) else { return }
        if (try? previewVoice.loadSample(from: url)) != nil { previewVoice.fire() }
    }

    /// Audition an external file on the preview voice (security-scoped).
    public func audition(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if (try? previewVoice.loadSample(from: url)) != nil { previewVoice.fire() }
    }

    /// Assign a built-in sample to a pad (clears any custom bookmark).
    public func assignBundled(track: Int, name: String) {
        guard voices.indices.contains(track), let url = Self.bundledSampleURL(name) else { return }
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey(track))
        if (try? voices[track].loadSample(from: url)) != nil {
            sampleLabels[track] = name
            UserDefaults.standard.set("drum:\(name)", forKey: Self.bundledKey(track))
        }
    }

    // MARK: - Categorized library (Resources/Samples/<Category>/*.wav)

    /// One browsable bundled sample, grouped by its category folder. Value type so
    /// the browser can `ForEach` it directly; `url` points into the app bundle
    /// (not security-scoped → no bookmark needed to audition/assign).
    public struct LibrarySample: Identifiable, Hashable, Sendable {
        public let category: String
        public let name: String
        public let url: URL
        public var id: String { "\(category)/\(name)" }
    }

    /// The `Samples` resource directory root, resolved for both the SwiftPM
    /// (`Bundle.module`) and Xcode (folder-ref in `.main`) builds.
    private static func samplesRoot() -> URL? {
        let b = resourceBundle
        if let u = b.url(forResource: "Samples", withExtension: nil) { return u }
        return b.resourceURL?.appendingPathComponent("Samples")
    }

    /// All bundled library samples grouped by category (Bass · Stab · Keys · …),
    /// each sorted by name, categories sorted alphabetically. Computed once
    /// (static let) so browsing never re-scans the disk — render-safe.
    public static let library: [(category: String, samples: [LibrarySample])] = {
        guard let root = samplesRoot() else { return [] }
        let fm = FileManager.default
        guard let cats = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var out: [(String, [LibrarySample])] = []
        for catURL in cats.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDir = (try? catURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            let cat = catURL.lastPathComponent
            guard let files = try? fm.contentsOfDirectory(
                at: catURL, includingPropertiesForKeys: nil) else { continue }
            let samples = files
                .filter { $0.pathExtension.lowercased() == "wav" }
                .map { LibrarySample(category: cat,
                                     name: $0.deletingPathExtension().lastPathComponent,
                                     url: $0) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if !samples.isEmpty { out.append((cat, samples)) }
        }
        return out
    }()

    /// Audition a library sample on the preview voice (does not touch the kit).
    public func auditionLibrary(_ sample: LibrarySample) {
        if (try? previewVoice.loadSample(from: sample.url)) != nil { previewVoice.fire() }
    }

    /// Assign a library sample to a pad (clears any custom bookmark, like
    /// `assignBundled`). Bundle URL → no security scope needed. Persists a bundled
    /// reference so the choice survives relaunch.
    public func assignLibrary(track: Int, _ sample: LibrarySample) {
        guard voices.indices.contains(track) else { return }
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey(track))
        if (try? voices[track].loadSample(from: sample.url)) != nil {
            sampleLabels[track] = sample.name
            UserDefaults.standard.set("lib:\(sample.id)", forKey: Self.bundledKey(track))
        }
    }

    /// Re-load a persisted bundled assignment (built-in drum or library sample)
    /// on launch. No-op when none is stored or it no longer resolves.
    private func restoreBundledAssignment(_ track: Int) {
        guard let ref = UserDefaults.standard.string(forKey: Self.bundledKey(track)) else { return }
        if let url = Self.bundledAssignmentURL(ref) {
            if (try? voices[track].loadSample(from: url)) != nil {
                sampleLabels[track] = url.deletingPathExtension().lastPathComponent
            }
        } else {
            // Stale reference (renamed/removed asset) — drop it so we stop retrying.
            UserDefaults.standard.removeObject(forKey: Self.bundledKey(track))
        }
    }

    /// Resolve a stored bundled reference ("drum:<Name>" or "lib:<Category>/<Name>")
    /// to a bundle URL. Pure lookup — nil when the asset no longer exists.
    private static func bundledAssignmentURL(_ ref: String) -> URL? {
        if let name = ref.stripping(prefix: "drum:") {
            return bundledSampleURL(name)
        }
        if let id = ref.stripping(prefix: "lib:") {
            return library.flatMap { $0.samples }.first { $0.id == id }?.url
        }
        return nil
    }
}

private extension String {
    /// The remainder after `prefix`, or nil when the string doesn't start with it.
    func stripping(prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
#endif
