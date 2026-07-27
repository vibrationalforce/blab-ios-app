// BeatPlayer.swift
// Echoel — WAS the drum orchestrator: owned 8 SamplerVoices + 8 DrumSynthVoices, wired
// them to PatternEngine.onStep, attached them to AudioEngine, and loaded 8 bundled WAVs
// into them at launch. ALL OF THAT IS GONE (founder 2026-07-26 "es soll keine Drums
// geben. Auch nicht im Mixer.", then #167 "erstmal gar nicht mehr rein").
//
// What the class still is — and why it is not simply a leftover:
//   · `pattern` — the PatternEngine, i.e. the app's TRANSPORT. It owns tempo, play/stop,
//     the bar/step position the chrome reads, and the tick on which `PianoRollModel`
//     publishes `MusicalFrame` to visuals, light and space. ~90 references repo-wide.
//     Deleting this class today would take play/stop and the visual spine with it.
//   · `previewVoice` + `auditionSink` + `attach(to:)` — the audition path.
//   · `resolveSampleRef` / `sampleRefDisplayName` — the persisted-ref helpers the lane
//     sampler uses (`resolveSampleRef` is called from `EchoelmusicApp`).
//
// The honest end state is NOT "delete BeatPlayer" but "move the transport out, then the
// husk falls away by itself" — the name already lies, no beat plays here. Until that
// slice lands, do not add anything to this class.
//
// One BeatPlayer instance is owned by EchoelmusicApp and injected into
// the view tree via .environment, so audio survives tab switches.

#if canImport(AVFoundation)
import AVFoundation
import Foundation
import Observation

/// Owns the pattern engine (transport) and the audition voices.
@MainActor
@Observable
public final class BeatPlayer {

    /// Row labels of the 8-track step grid `PatternEngine` still keeps as a CLOCK.
    /// These used to name the bundled drum WAVs (`Resources/Drums/<Name>.wav`); those
    /// assets and the voices that played them are deleted (#167), so this is now a
    /// naming/count schema only — nothing here makes a sound.
    public static let trackNames: [String] = [
        "Kick", "Snare", "ClosedHat", "OpenHat",
        "Clap", "Perc",  "Bass",      "LeadFX"
    ]

    // MARK: - Drum kit — DELETED 2026-07-27 (#167)
    //
    // Removed in this slice, after the founder confirmed "Samples, BeatPlayer und Drums
    // brauchen wir nicht mehr": the 8 `SamplerVoice` pads and their 8 `DrumSynthVoice`
    // twins; `PadShape`/`PadMode` and the `sampleLabels`/`shapes`/`modes`/`synthParams`
    // arrays with their setters, appliers and restores; `masterLevel`; the bundled-sample
    // API (`bundledSampleNames`, `bundledSampleURL`, `auditionBundled`, `assignBundled`,
    // `resourceBundle`); user sample import (`importSample`, `resetSample`, `isCustom`,
    // the security-scoped bookmark handling); `loadDefaultSamples` and every restore that
    // hung off it; and `bundledAssignmentURL`. The `Resources/Drums` WAVs go with them.
    //
    // Earlier slices had already removed the pad-trigger path and the Channel-Rack mixer,
    // so none of this could be reached or heard — `attach(to:)` stopped installing
    // `pattern.onStep`, and `loadDefaultSamples()` lost its caller at app start.
    //
    // PERSISTED KEYS ARE LEFT IN PLACE, not migrated: `echoel.beat.shape|mode|synth|
    // mute|solo|fx.<n>` and `echoel.beat.sample.bookmark|bundled.<n>`. Nothing reads them
    // any more, so they are inert bytes rather than state stuck in an un-toggleable
    // position — and erasing them would mean writing to UserDefaults on a launch path for
    // no user-visible gain. Note the bookmarks were security-scoped references to the
    // user's OWN files; the files themselves were never copied or touched by this class.

    public let pattern: PatternEngine

    /// Dedicated voice for auditioning a sample file — the kit it used to audition
    /// "against" no longer exists, so this is now simply the one-shot preview player.
    /// HONEST LIMIT: `audition(url:)` and the region audition below currently have no
    /// production caller either; they are kept as a working, attached audition path for
    /// the sampler lane rather than deleted and rebuilt.
    public let previewVoice: SamplerVoice

    @ObservationIgnored private weak var audioEngine: AudioEngine?
    @ObservationIgnored private var attachedSourceNodes: [AVAudioSourceNode] = []

    public init() {
        self.pattern = PatternEngine()
        self.previewVoice = SamplerVoice()
    }

    /// Pure mixer rule (testable, no audio): a track sounds when it is not muted
    /// AND (nothing is soloed, OR this track is one of the soloed ones).
    ///
    /// TEST-ONLY since 2026-07-27 (#167) — the mute/solo state it read, and the trigger
    /// gate that called it, are both gone. Kept because `ChannelRackTests` pins the rule;
    /// it takes its inputs as arguments, so it needs no stored state.
    nonisolated public static func shouldSound(track: Int, mutes: [Bool], solos: [Bool]) -> Bool {
        guard mutes.indices.contains(track), solos.indices.contains(track) else { return true }
        if mutes[track] { return false }
        let anySolo = solos.contains(true)
        return !anySolo || solos[track]
    }

    /// Attaches the preview source node to the engine. Idempotent — safe to call
    /// multiple times.
    ///
    /// **NO DRUMS** (founder 2026-07-26). This method used to attach all 8 pad voices plus
    /// their synth twins and install `pattern.onStep`, which is what turned every
    /// sequencer step into a drum hit. Both are gone, and as of #167 so are the voices
    /// themselves, so the instrument produces no percussion at all.
    ///
    /// What deliberately REMAINS is `pattern` — `PatternEngine` is not the drum machine,
    /// it is the app's TRANSPORT (tempo, play/stop, the bar/step position the chrome
    /// reads, and the tick on which `PianoRollModel` publishes `MusicalFrame`, the spine
    /// that drives visuals, light and space). Deleting it to remove drums would sever
    /// that. The step grid survives as a clock; nothing listens to it for sound.
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

    // MARK: - Audition

    /// Audition an external file on the preview voice (security-scoped).
    public func audition(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if (try? previewVoice.loadSample(from: url)) != nil { previewVoice.fire() }
    }

    /// H13/A2: the offset-aware REGION audition sink. An AVAudioPlayerNode that
    /// STREAMS a segment of the file (scheduleSegment) — unlike `previewVoice`
    /// (SamplerVoice: ~2 s buffer cap, always from frame 0). Lazily created on the first
    /// region audition: the caller's plan law (`AudioRegionPlayback.auditionWindow`)
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

    // MARK: - Persisted sample refs (shared with the EchoelSampler lane, S2-W3)

    /// Resolve a persisted sample REF string to a playable file URL — THE one
    /// lookup for every surface that stores a sample choice as a string (the
    /// EchoelSampler lane's `TimelineLane.samplePath` today). Called from
    /// `EchoelmusicApp` via `laneVoiceRack.setSample`.
    ///
    /// ONE convention survives: a `Clip.mediaRef`-style absolute path
    /// (`MediaLibrary.resolveRef`, incl. H6 container re-rooting). The two BUNDLE
    /// schemes this class used to own are gone with their assets — "lib:" with the
    /// sample library and "drum:" with the drum WAVs (#167). A ref persisted under
    /// either now falls through to `MediaLibrary.resolveRef` and yields nil, which is
    /// the same answer this function already gave for a vanished file: the caller's
    /// sampler simply stays unloaded. `LaneVoiceRackTests` pins that nil path.
    public static func resolveSampleRef(_ ref: String?) -> URL? {
        guard let ref, !ref.isEmpty else { return nil }
        return MediaLibrary.resolveRef(ref)
    }

    /// Human-readable name for a persisted sample REF ("drum:Kick" → "Kick",
    /// "lib:Bass/808" → "808", a media path → its file stem). nil for nil/empty —
    /// the UI shows its own "No sample" placeholder then. Pure string math.
    ///
    /// The two bundle cases are KEPT although no such ref can be written any more —
    /// this is a READER of values persisted by older builds, and showing "Kick" beats
    /// showing "drum:Kick" while the resolver reports the file as gone. Be honest about
    /// its reach, though: the function has no production caller today, only
    /// `LaneVoiceRackTests`. It is the already-written reader for the lane-sampler UI,
    /// not something currently displaying anything.
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
