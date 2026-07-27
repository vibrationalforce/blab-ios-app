// BeatPlayer.swift
// Echoel — WAS the drum orchestrator: owned 8 SamplerVoices, wired them to
// PatternEngine.onStep, attached them to AudioEngine. All three clauses are false
// since the founder removed the drums (2026-07-26) and #167 began tearing the
// apparatus out: `attach(to:)` attaches ONLY `previewVoice`, installs no `onStep`,
// and no path can fire a pad any more.
//
// What the class still genuinely is, and why it is not a leftover:
//   · `pattern` — the PatternEngine, i.e. the app's TRANSPORT (tempo, play/stop,
//     the bar/step position the chrome reads, and the tick on which
//     `PianoRollModel` publishes `MusicalFrame` to visuals/light/space),
//   · `previewVoice` + the region `auditionSink` — audition playback,
//   · the two static REF helpers (`resolveSampleRef`, `sampleRefDisplayName`) the
//     lane sampler uses.
// The pad voices, their per-pad state and their persistence are dead code awaiting
// the remaining #167 slices. Do not build anything new on them.
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

    /// Master drum level (the Mixer's "Drums" fader), 1.0 = unity. Multiplied into every
    /// triggered hit's gain. Written from the main actor (Mixer UI), read on the pattern's
    /// main-queue trigger timer — never the audio thread — so a plain Float is safe.
    public var masterLevel: Float = 1.0

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

    // MARK: - Channel Rack mixer — DELETED 2026-07-27 (#167)
    //
    // `ChannelFX`, the `fx`/`mutes`/`solos` arrays, `setFX`/`applyFX`/`setMute`/
    // `setSolo`/`clearSolos`, their three UserDefaults keys and `restoreMix()` lived
    // here. `ChannelRackView` was their only surface and their only caller; it was
    // deleted with the drums, leaving this block writable by nobody.
    //
    // The persisted keys (`echoel.beat.mute|solo|fx.<n>`) are NOT migrated or erased.
    // Nothing reads them any more — `restoreMix()` was reachable only from
    // `loadDefaultSamples()`, which itself lost its caller when it was dropped from app
    // start the same day — so they are inert bytes in UserDefaults, not stuck state.
    //
    // `shouldSound` (below) deliberately SURVIVES this removal: it is a pure static
    // function taking the arrays as arguments, and `ChannelRackTests` pins it with six
    // tests. It has no production caller now. That is the honest end state for this
    // half-torn-down class, not an oversight — the function goes when the drum voices
    // it gated go.

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
    }

    private static func shapeKey(_ track: Int) -> String { "echoel.beat.shape.\(track)" }
    private static func modeKey(_ track: Int) -> String { "echoel.beat.mode.\(track)" }
    private static func synthKey(_ track: Int) -> String { "echoel.beat.synth.\(track)" }

    /// Pure mixer rule (testable, no audio): a track sounds when it is not muted
    /// AND (nothing is soloed, OR this track is one of the soloed ones).
    ///
    /// TEST-ONLY since 2026-07-27 (#167) — the mute/solo state it read, and the
    /// `trigger` gate that called it, are both gone. Kept because `ChannelRackTests`
    /// pins the rule; it takes its inputs as arguments, so it needs no stored state.
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

    // MARK: - Pad trigger — DELETED 2026-07-27 (#167)
    //
    // `trigger(track:gain:)`, `playPad`, `preview` and `humanizeDepth` (the downward-only
    // velocity jitter, founder inspiration 2026-07-10 "why your sounds feel fake") were
    // the pad-firing path. NOTHING could reach it: `attach(to:)` stopped installing
    // `pattern.onStep` with the drum removal, so no step ever arrived, and `playPad` /
    // `preview` have no call site anywhere in the repo.
    //
    // This is also where the mute/solo gate lived. Removing that gate left the remaining
    // flag describing only humanization, so the same commit renamed it `respectMix` →
    // `sequenced` — and the reviewer correctly called that trading one lying name for
    // another, since no sequencer path existed either. Deleting the whole path is the
    // honest answer; renaming a parameter on an unreachable function is not.

    /// True when track `i` is playing a user-imported sample (not the default).
    public func isCustom(_ track: Int) -> Bool {
        sampleLabels.indices.contains(track) && sampleLabels[track] != Self.trackNames[track]
    }

    private static func bookmarkKey(_ track: Int) -> String { "echoel.beat.sample.bookmark.\(track)" }
    /// Persists a BUNDLED assignment (built-in drum or category-library sample) so a
    /// pad chosen in the browser survives relaunch — bundle files have no security-
    /// scoped bookmark, so they need their own tiny reference. Value scheme:
    /// "drum:<Name>" (Resources/Drums). A second scheme, "lib:<Category>/<Name>"
    /// (Resources/Samples), existed until 2026-07-27 — those assets and their browser
    /// are deleted, so a stored "lib:" value can no longer resolve. It is INERT rather
    /// than cleaned up: the cleanup path (`restoreBundledAssignment`) hangs off
    /// `loadDefaultSamples()`, which has had no caller since it was dropped from app
    /// start the same day. A stale key therefore just sits in UserDefaults.
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
        // `restoreMix()` was the fourth call here — deleted with the Channel Rack (#167).
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

    /// Attaches the preview source node to the engine. Idempotent — safe to call
    /// multiple times.
    ///
    /// **NO DRUMS** (founder 2026-07-26: *"es soll keine Drums geben. Auch nicht im
    /// Mixer."*). This method used to attach all 8 pad voices plus their synth twins and
    /// install `pattern.onStep`, which is what turned every sequencer step into a drum hit.
    /// Both are gone, so the instrument produces no percussion at all.
    ///
    /// What deliberately REMAINS is `pattern` itself — `PatternEngine` is not the drum
    /// machine, it is the app's TRANSPORT: it owns tempo, play/stop, the bar/step position the
    /// chrome reads, and the tick on which `PianoRollModel` publishes `MusicalFrame` (the spine
    /// that drives visuals, light and space). Deleting it to remove drums would sever that.
    /// The step grid survives as a clock; nothing listens to it for sound any more.
    ///
    /// The pad voices are therefore no longer attached to the audio graph, and as of #167
    /// there is no longer even a way to ask them to sound: `trigger`/`playPad`/`preview`
    /// are deleted. The voices themselves are dead code awaiting a further removal slice.
    /// Their INIT path is dead too since
    /// 2026-07-27: `loadDefaultSamples()` was dropped from app start (`EchoelmusicApp`
    /// startup stage 1) and now has no caller at all, so those 8 WAVs are no longer even
    /// decoded. (An earlier version of this comment said it "still runs at launch" — that
    /// was true for one day.) Left in place so the removal stays small and reversible; do
    /// not build anything new on it.
    public func attach(to engine: AudioEngine) {
        guard attachedSourceNodes.isEmpty else { return }
        audioEngine = engine
        engine.attachSourceNode(previewVoice.sourceNode)
        attachedSourceNodes.append(previewVoice.sourceNode)
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

    /// H13/A2: the offset-aware REGION audition sink. An AVAudioPlayerNode that
    /// STREAMS a segment of the file (scheduleSegment) — unlike `previewVoice`
    /// (SamplerVoice: ~2 s buffer cap, always from frame 0; right for drum
    /// samples, wrong for a region window). Lazily created on the first region
    /// audition: the caller's plan law (`AudioRegionPlayback.auditionWindow`)
    /// only permits auditioning while the transport is STOPPED, so the one-time
    /// attach pause is inaudible by construction.
    @ObservationIgnored private var auditionSink: TimelineAudioSink?

    /// Audition a REGION window: play `url` from `fromSeconds` for
    /// `lengthSeconds` (the region's own content — pro-DAW tap behavior).
    /// Callers derive the window via `AudioRegionPlayback.auditionWindow`,
    /// which refuses while the transport plays (double-sound hazard).
    public func audition(url: URL, fromSeconds: Double, lengthSeconds: Double) {
        guard let engine = audioEngine else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if auditionSink == nil { auditionSink = TimelineAudioSink(engine: engine) }
        auditionSink?.play(url: url, fromSeconds: fromSeconds,
                           lengthSeconds: lengthSeconds, gain: 1,
                           stretch: .unstretched)
    }

    /// Stop a running region audition (transport start / user action).
    public func stopAudition() {
        auditionSink?.stop()
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

    // MARK: - Categorized library — DELETED 2026-07-27 (#167)
    //
    // `LibrarySample`, `samplesRoot()`, the `library` index, `auditionLibrary` and
    // `assignLibrary` browsed `Resources/Samples/<Category>/*.wav` (5.4 MB, ~15
    // categories). Their only surface was `SampleBrowserView`, deleted the same day
    // because no door could open it; the assets themselves are deleted with this
    // change. Nothing outside this file ever referenced the API — verified by grep
    // over `Sources/` and `Tests/` before removal.

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

    /// Resolve a stored bundled reference ("drum:<Name>") to a bundle URL. Pure
    /// lookup — nil when the asset no longer exists.
    ///
    /// The "lib:<Category>/<Name>" branch went with the sample library (#167). A
    /// value persisted under the old scheme now returns nil, which is the SAME
    /// answer this function already gave for a renamed or removed asset, and both
    /// callers were written for it. Only ONE of the two can actually run today:
    /// `resolveSampleRef` (live, via the lane sampler) falls through to
    /// `MediaLibrary.resolveRef` and leaves the slot unloaded — the nil path its own
    /// test pins. `restoreBundledAssignment` would drop the stale key, but it hangs
    /// off the callerless `loadDefaultSamples()`, so it never runs. Neither treats
    /// nil as an error, so nothing is lost beyond a sound that no longer ships.
    private static func bundledAssignmentURL(_ ref: String) -> URL? {
        if let name = ref.stripping(prefix: "drum:") {
            return bundledSampleURL(name)
        }
        return nil
    }

    // MARK: - Persisted sample refs (shared with the EchoelSampler lane, S2-W3)

    /// Resolve a persisted sample REF string to a playable file URL — THE one
    /// lookup for every surface that stores a sample choice as a string (the
    /// EchoelSampler lane's `TimelineLane.samplePath` today). Two conventions,
    /// both already established: "drum:<Name>" bundle refs (this class's own
    /// pad-persistence format — resolved by NAME, so they survive app updates;
    /// the "lib:" sibling died with the sample library, #167), and everything
    /// else as a `Clip.mediaRef`-style
    /// absolute path (`MediaLibrary.resolveRef`, incl. H6 container re-rooting).
    /// nil for empty/vanished refs — the caller's sampler simply stays unloaded.
    public static func resolveSampleRef(_ ref: String?) -> URL? {
        guard let ref, !ref.isEmpty else { return nil }
        if let url = bundledAssignmentURL(ref) { return url }
        return MediaLibrary.resolveRef(ref)
    }

    /// Human-readable name for a persisted sample REF ("drum:Kick" → "Kick",
    /// "lib:Bass/808" → "808", a media path → its file stem). nil for nil/empty —
    /// the UI shows its own "No sample" placeholder then. Pure string math.
    ///
    /// The "lib:" case is KEPT although no such ref can be written any more (#167
    /// deleted the library) — but be honest about why: this function has NO
    /// production caller today, only `LaneVoiceRackTests`. It is kept as the
    /// already-written reader for persisted refs, ready for the lane-sampler UI that
    /// would display them; it is not currently showing anyone anything.
    public static func sampleRefDisplayName(_ ref: String?) -> String? {
        guard let ref, !ref.isEmpty else { return nil }
        if let name = ref.stripping(prefix: "drum:") { return name }
        if let id = ref.stripping(prefix: "lib:") {
            return id.components(separatedBy: "/").last ?? id
        }
        return URL(fileURLWithPath: ref).deletingPathExtension().lastPathComponent
    }
}

private extension String {
    /// The remainder after `prefix`, or nil when the string doesn't start with it.
    func stripping(prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
#endif
