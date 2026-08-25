//
//  PolySynthVoice.swift
//  Echoelmusic
//
//  Polyphonic note instrument for the piano roll (and the patch-editor preview).
//  Wraps one EchoelPolyDDSP (voice pool + stealing + bio-reactive + stereo mix
//  with tanh soft-limiting) behind one stereo AVAudioSourceNode that mixes into
//  AudioEngine.masterMixer.
//
//  Why a separate voice from BioReactiveSynthVoice: EngineBus.controllerEvents is
//  a single-consumer queue already drained by BioReactiveSynthVoice (external
//  MIDI + breath, monophonic). PolySynthVoice is driven DIRECTLY by the piano
//  roll (noteOn/noteOff calls) so chords play without contending for that queue.
//  It only READS bus.latestBio (a multi-reader snapshot) at 10 Hz to fan bio
//  modulation across all active voices.
//
//  Threading mirrors BioReactiveSynthVoice exactly: control plane on MainActor
//  (10 Hz poll + note gating), render closure on the audio thread. EchoelPolyDDSP
//  params are Float-width (atomic on Apple); worst case a render block reads
//  slightly-stale params. `hasEverSounded` guarantees pure-zero output until the
//  first user-initiated note, so nothing sounds on launch.
//

#if canImport(Observation)
import Observation
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

@MainActor
@Observable
public final class PolySynthVoice {

    // MARK: - Synth + audio output

    /// Underlying polyphonic engine. `nonisolated let` so the audio-thread
    /// render closure may touch it (same pattern as BioReactiveSynthVoice.synth).
    @ObservationIgnored
    nonisolated public let poly: EchoelPolyDDSP

    /// Per-voice effects (delay / chorus / phaser / limiter). The generated
    /// melody runs through this so a genre's signature space (e.g. the long dub
    /// delay) is audible. Audio-thread-safe; all stages bypassed by default
    /// except the safety limiter, so launch behaviour is unchanged.
    @ObservationIgnored
    nonisolated public let fxChain: EchoelFXChain

    /// Lock-free note-event queue: produced on the control thread (noteOn/Off),
    /// consumed (applied to `poly`) on the audio thread in the render block, so
    /// voice-state mutation never races the render. SPSC: one producer (main), one
    /// consumer (audio).
    @ObservationIgnored
    nonisolated(unsafe) private let noteCommands = SPSCQueue<NoteCommand>(capacity: 128)

    /// Lock-free patch-recall queue, drained on the audio thread (same discipline
    /// as noteCommands). `apply(_:)` previously ran `patch.apply(to:)` on the MAIN
    /// thread, which (via brightness/spectralShape didSet → updateSpectralEnvelope)
    /// rewrote each voice's `harmonicAmplitudes` array while the audio thread read
    /// it → the same cross-thread array race as the note bug. Applying on the audio
    /// thread removes it. SPSC: one producer (main), one consumer (audio).
    ///
    /// Carries `ResolvedPatch`, NOT `SynthPatch`: the queue element is dequeued ON the
    /// render thread, so it must be plain old data. A `SynthPatch` brought its Strings
    /// and UUID (ARC traffic) and its `apply(to:)` brought `allCases` allocations,
    /// `caseInsensitiveCompare` ObjC messaging and a fresh 64-tap timbre array — all
    /// forbidden here. `ResolvedPatch` does that work on the control thread instead.
    @ObservationIgnored
    nonisolated(unsafe) private let patchCommands = SPSCQueue<ResolvedPatch>(capacity: 8)

    /// Per-bus insert FX for the MELODIC bus (Module 2) — SEPARATE from the genre-owned
    /// master `fxChain` above, placed AFTER it, so a user filter/drive on the melody never
    /// fights the genre character. Two mono `ChannelInsertFX` (independent L/R biquad state)
    /// fed from the control thread via `fxCommands` (same lock-free discipline as
    /// `patchCommands`). Default `.off` = an EXACT passthrough → bit-identical until dialed.
    @ObservationIgnored
    nonisolated(unsafe) private let fxCommands = SPSCQueue<TrackFX>(capacity: 8)
    @ObservationIgnored
    nonisolated(unsafe) private var insertL = ChannelInsertFX(sampleRate: Float(PolySynthVoice.sampleRate))
    @ObservationIgnored
    nonisolated(unsafe) private var insertR = ChannelInsertFX(sampleRate: Float(PolySynthVoice.sampleRate))
    @ObservationIgnored
    nonisolated(unsafe) private var insertActive = false

    /// Lock-free bio-modulation queue, drained on the audio thread (same discipline
    /// as `patchCommands`). The bio path formerly ran `poly.applyBioReactive(...)`
    /// straight from the MainActor 10 Hz poll (`applyLatestIfFresh`), which — via
    /// each voice's brightness/spectralShape → `updateSpectralEnvelope` → rewrote
    /// `harmonicAmplitudes` (a Swift `[Float]`) while the audio thread read that same
    /// array in `render` → a cross-thread array data race (COW heap-copy / torn read
    /// / envelope glitch). Notes and patch recall were already moved onto the audio
    /// thread to kill exactly this class of race; the bio path was the last one that
    /// wasn't. Enqueue on the main poll, apply on the one audio thread.
    /// SPSC: one producer (main), one consumer (audio).
    @ObservationIgnored
    nonisolated(unsafe) private let bioCommands = SPSCQueue<PolyBioParams>(capacity: 8)

    @ObservationIgnored
    public lazy var sourceNode: AVAudioSourceNode = makeSourceNode()

    /// Number of voices currently sounding (for UI display).
    public var activeVoiceCount: Int { poly.activeVoiceCount }

    /// When false (default) the designed patch fully defines the timbre and bio
    /// never modulates it — so "your own instrument" sounds stable. Enable to let
    /// the body modulate the polyphonic voice too. (BioReactiveSynthVoice remains
    /// the always-bio-reactive breath instrument.)
    public var bioModulationEnabled = false {
        didSet { poly.bioModulationEnabled = bioModulationEnabled }
    }

    /// Bio→timbre mapping character. `false` (default) = the established `.natural`
    /// mapping (unchanged sound). `true` = `.harmonicSeries` — HRV opens the overtone
    /// richness and the breath swells the amplitude ("harmonic mapping of physiological
    /// rhythms"). Low-rate user toggle → safe as a tracked `@Observable` property.
    public var bioMappingHarmonic = false

    // MARK: - Brainwave entrainment (biofeedback-driven)

    /// Arm the isochronic brainwave-entrainment stimulus. OFF by default (silent-until-
    /// armed). When on, the body's coherence + pulse-lock quality drive the band + depth
    /// via `BioEntrainmentDirector`, applied to every voice's existing `EchoelEntrainment`.
    /// Low-rate (user toggle) so it is safe as a tracked `@Observable` property.
    public var entrainmentEnabled = false {
        didSet { if !entrainmentEnabled { clearEntrainment() } }
    }

    /// Pinned band, or `nil` for auto (bio-selected). Manual lets the user hold e.g. Theta.
    public var entrainmentManualBand: BrainwaveBand?

    /// Last computed target — telemetry only. `@ObservationIgnored`: it changes on every
    /// NEW bio frame, and reading it in a view body would be the "menus freeze while
    /// playing" class. ⚠️ The rate used to be written here as "~10 Hz" and that is the POLL,
    /// not the change rate: `applyLatestIfFresh` dedupes on `frame.timestamp`, and every
    /// wired publisher emits at ~1 Hz (`CameraRPPGBioPublisher` `tick % 10` in a 100 ms
    /// loop; Polar 1 s; simulator 1 s). Do NOT read the corrected figure as permission to
    /// drop `@ObservationIgnored` — the poll is the CEILING, a faster publisher raises the
    /// rate to it without touching this line, and 1 Hz in a root body is churn either way.
    @ObservationIgnored public private(set) var entrainmentTarget: BioEntrainmentTarget = .inactive

    // MARK: - Bus subscription state

    public private(set) var isSubscribed = false

    /// Diagnostic counter, bumped once per NEW bio frame (~1 Hz today — the poll is 10 Hz
    /// but `applyLatestIfFresh` dedupes on `frame.timestamp`, and every wired publisher
    /// emits at ~1 Hz). MUST stay `@ObservationIgnored` regardless: as a tracked
    /// `@Observable` it would invalidate any view that reads it on every frame — the exact
    /// "menus freeze while playing" class — and the 10 Hz poll is the ceiling a faster
    /// publisher would reach without this line changing. Nothing reads it for UI.
    @ObservationIgnored public private(set) var framesApplied: UInt64 = 0

    @ObservationIgnored
    private weak var bus: EngineBus?

    @ObservationIgnored
    private let loop = PollingLoop()

    @ObservationIgnored
    private var lastTimestamp: TimeInterval = -1

    // MARK: - Audio render scratch (audio-thread only after attach)

    @ObservationIgnored
    nonisolated private static let maxBlockFrames = 4096

    @ObservationIgnored
    nonisolated public static let sampleRate: Double = 48_000

    /// Pre-allocated stereo scratch. The audio thread renders into these via
    /// `poly.renderStereo(...)`, then copies into the AudioBufferList. Never
    /// re-allocated after init.
    @ObservationIgnored
    nonisolated(unsafe) private var scratchL: [Float]
    @ObservationIgnored
    nonisolated(unsafe) private var scratchR: [Float]

    /// Launch-silence guarantee: emit pure zero until the first user-initiated
    /// note. Set once, never reset, so it never cuts a release tail.
    @ObservationIgnored
    nonisolated(unsafe) private var hasEverSounded = false

    // P1 idle-skip (FL "Smart Disable" / REAPER lesson, 2026-07-12 sweep):
    // once every voice and every FX tail has fully decayed, the render emits
    // silence WITHOUT running the poly engine + FX chain — measurable CPU/
    // battery/thermal headroom whenever the instrument is quiet. Audio-thread-
    // only state (no locks needed); a note command wakes it in the SAME block
    // (commands drain before the gate), so the attack is never clipped.
    /// Consecutive FRAMES whose rendered peak stayed below the idle floor.
    /// Frames, not blocks — the window must not shrink when LatencyMode.low
    /// halves the buffer size (audio-thread-review finding, 2026-07-12).
    @ObservationIgnored
    nonisolated(unsafe) private var idleQuietFrames = 0
    /// True while the render is skipped. Cleared by any note-on/slide command
    /// and whenever the entrainment stimulus is armed.
    @ObservationIgnored
    nonisolated(unsafe) private var renderIdle = false
    /// Main-thread mirror of "the entrainment stimulus is armed": the
    /// entrainment writes voice state DIRECTLY (not via the command queues).
    /// The stimulus is MULTIPLICATIVE (silent voices stay silent), so this
    /// flag only protects the CPU saving from mis-engaging around the arm
    /// moment — it fails safe in both directions. Bool is atomic-width (same
    /// contract as the other nonisolated(unsafe) mirrors in this file).
    @ObservationIgnored
    nonisolated(unsafe) private var audioEntrainmentActive = false
    /// Peak below this counts as digital silence (≈ −100 dBFS).
    nonisolated private static let idlePeakFloor: Float = 1e-5
    /// Quiet frames before the render sleeps: 2.5 s — LONGER than the maximum
    /// EchoelDelay gap (maxDelaySeconds = 2.0), because a sparse dub-echo
    /// train sits at exact zero BETWEEN repeats. If no repeat exceeds the
    /// floor within one full max gap, every later repeat is that peak ×
    /// feedback (≤ 0.95) × damping — strictly quieter — so sleeping is
    /// genuinely safe and no echo train is ever cut or frozen mid-ring.
    nonisolated private static let idleFrameThreshold = Int(2.5 * sampleRate)

    /// One-time guard so the control-thread note breadcrumb fires only once.
    nonisolated(unsafe) fileprivate static var noteTraced = false

    /// Master insert-FX gate. The melody always ran through `fxChain` (gentle
    /// saturation + chorus for warmth); this lets the user bypass the WHOLE chain
    /// from the Effects panel. Audio-thread mirror (read in the render block) +
    /// observable mirror for the UI — same cross-thread contract as
    /// BioReactiveSynthVoice. Default ON, so launch behaviour is unchanged.
    @ObservationIgnored
    nonisolated(unsafe) private var fxEnabled = true

    /// Observable mirror of `fxEnabled` for SwiftUI binding.
    public private(set) var isFXEnabled = true

    /// Enable or bypass the whole insert chain. Individual stages are toggled
    /// directly on `fxChain` (e.g. `fxChain.delayEnabled = true`).
    /// The stale-glide problem this gate creates is handled on the RENDER side, not here:
    /// see `fxChain.noteRenderSkipped()` at the three skip paths in `renderOnAudioThread`.
    /// A snap on this rising edge would have covered only ONE of them — `hasEverSounded`
    /// and the 2.5 s `renderIdle` skip both decide on the audio thread and have no
    /// control-plane setter to hook.
    public func setFXEnabled(_ on: Bool) {
        // #397 — the SWITCH-CRACKLE RULE applied to the one WHOLE-chain bypass switch.
        // Every per-stage flag in `EchoelFXChain` that owns STATE resets its stage on the
        // rising edge, because a skipped stage freezes holding old audio and bursts it on
        // resume. (Fourteen of the fifteen `*Enabled` flags; `saturationEnabled` has no
        // `willSet` because a waveshaper is stateless. The first version of this line said
        // "every per-stage flag" without that qualifier — one of fifteen is a small error,
        // but it is the sentence a later session would cite when adding the sixteenth.)
        //
        // ⛔ #693 — AND THAT PARENTHESIS PREDICTED ITS OWN DEATH AND STILL DIED. It said
        // "the sentence a later session would cite when adding the fifteenth"; #687 added the
        // fifteenth (granular) and did not walk this line. Worse, #692 corrected the IDENTICAL
        // sentence in `BypassingTheChainEmptiesItOnTheWayBackTests` and stopped there, so for
        // one commit the repo carried two spellings of one fact (#416). Walking "the" prose
        // home is not walking EVERY prose home. Re-measure, never re-quote:
        //   grep -c "public var [a-zA-Z]*Enabled: Bool" Sources/Echoelmusic/DSP/EchoelFXChain.swift
        // This gate skips ALL of them at once, so it owed the same debt: bypass mid-take,
        // wait, re-enable, and the delay line and reverb tank walk out audio from before
        // the bypass. #389 fixed the audio-thread twin of this (the 2.5 s idle sleep) and
        // named this one as the remaining hole.
        //
        // BEFORE the flag goes up, and only on the RISING edge — that is the rule's own
        // timing, not a detail. While `fxEnabled` is still false the render block is
        // skipping the chain (`fxChain.noteRenderSkipped()` below), so the audio thread is
        // not in the chain and this control-plane drain does not meet it. On the FALLING
        // edge the audio thread IS inside `processBuffer`, so draining there would be
        // exactly the race the rule exists to avoid — and would also cut a tail the user
        // can still hear.
        //
        // ⛔ TWO CORRECTIONS TO THE FIRST VERSION OF THIS PARAGRAPH, both worth their space.
        // (1) It named `processBufferMono`. This voice calls `processBuffer(left:right:)`;
        // the mono path belongs to `BioReactiveSynthVoice`. The argument survives the
        // substitution, but a wrong method name is what a later session reads as evidence.
        // (2) It said the drain "provably cannot race the audio thread". There is no proof
        // available: `fxEnabled` is a plain non-atomic `Bool` with no fence on either side,
        // so nothing establishes happens-before between this store and the render block's
        // read. That is equally true of every `willSet` in `EchoelFXChain` — the whole
        // SWITCH-CRACKLE RULE rests on source order, not on the memory model — so this is
        // the house standard, not a weaker variant of it. Do NOT "strengthen" this by
        // converting `fxEnabled` to a `willSet` property: that lowers to the same plain
        // store after the same call and would buy nothing but false confidence. A real
        // guarantee means release/acquire on the enable flags chain-wide, which is its own
        // slice.
        //
        // `noteRenderSleeping()` is the right method and not an approximation: it drains
        // only the ENABLED stages (keeping both threads' reset sets disjoint) and re-arms
        // `renderSkipped` so the tone-filter glide LANDS on resume instead of sweeping out
        // of a value from before the bypass.
        if on && !fxEnabled { fxChain.noteRenderSleeping() }
        fxEnabled = on
        isFXEnabled = on
    }

    // MARK: - Breath swell (0.1 Hz coherence pacing — the medical core)

    /// A slow amplitude swell at 6 breaths/min (0.1 Hz). Applied to the whole voice
    /// output, it paces the listener's breathing toward the cardiorespiratory
    /// resonance frequency — the single most evidence-backed lever for raising HRV
    /// and parasympathetic tone (Shaffer & Meehan 2020; Leslie/Picard 2019 showed a
    /// 0.1 Hz amplitude modulation measurably slows breathing and lowers arousal).
    /// See scratchpads/RESEARCH_MEDITATION_ALGORITHM_2026-07-07.md.
    /// 6 breaths/min = 0.1 Hz = a 10 s cycle.
    @ObservationIgnored
    nonisolated public static let breathSwellHz: Float = 0.1
    /// TARGET swell depth [0…0.6]; 0 = off. The render ramps toward it (click-free).
    @ObservationIgnored
    nonisolated(unsafe) private var breathSwellTargetDepth: Float = 0
    /// Smoothed depth actually applied on the audio thread.
    @ObservationIgnored
    nonisolated(unsafe) private var breathSwellDepth: Float = 0
    /// Breath phase accumulator (radians) — audio-thread only, wrapped each block.
    @ObservationIgnored
    nonisolated(unsafe) private var breathPhase: Float = 0
    /// Observable mirror for the UI ("the sound is breathing with you").
    public private(set) var isBreathSwellActive = false

    /// Set the breath-swell depth (0 = off). Low-rate control call (per generate /
    /// mode change). The audio thread ramps to it, so changing it never clicks.
    public func setBreathSwell(depth: Float) {
        let d = Swift.min(Swift.max(depth, 0), 0.6)
        breathSwellTargetDepth = d
        isBreathSwellActive = d > 0
    }

    /// Pure per-sample breath gain from the accumulator phase — a raised-cosine
    /// swell riding between `(1 - depth)` and `1` across each cycle (phase 0 = full,
    /// phase π = the trough). `depth` 0 → always 1.0 (no-op). Audio-thread safe
    /// (one cosf, no allocation). Pure → unit-tested on Linux.
    nonisolated public static func breathGain(phase: Float, depth: Float) -> Float {
        let swell = (1 - cosf(phase)) * 0.5          // ∈ [0,1]
        return 1 - depth * swell                     // ∈ [1-depth, 1]
    }

    public init(maxVoices: Int = 8) {
        // Performance regulation (10.76.49 — "Audio Aussetzer / Kratzen vermeiden"):
        // worst-case additive cost is voices × harmonics. Capping voices 12→8 and
        // harmonics 64→32 cuts the ceiling from 768 to 256 partials/sample (~3×),
        // which — together with the larger IO buffer (see AudioConfiguration) — pulls
        // dense chords back inside the real-time render deadline so they stop dropping
        // out. 32 harmonics is still rich (most perceptual energy is in the first ~16);
        // the nyquist trim already discarded most of the upper 32 on all but bass notes.
        self.poly = EchoelPolyDDSP(maxVoices: maxVoices, harmonicCount: 32,
                                   sampleRate: Float(Self.sampleRate))
        self.fxChain = EchoelFXChain(sampleRate: Float(Self.sampleRate))
        self.scratchL = Array(repeating: 0, count: Self.maxBlockFrames)
        self.scratchR = Array(repeating: 0, count: Self.maxBlockFrames)
    }

    // MARK: - Audio engine attachment

    /// Attach the voice's source node to the master audio graph. MUST be called
    /// BEFORE `audioEngine.start()` (build-1363 hot-attach rule).
    public func attach(to audioEngine: AudioEngine) {
        audioEngine.attachSourceNode(sourceNode)
    }

    // MARK: - Note gating (control plane)

    /// Sound a note. `pitch` is a MIDI note number, `velocity` is [0...1].
    ///
    /// THE `NoteVoice` WITNESS, and why it cannot just be a default argument. Swift
    /// identifies a method by its full parameter list, not by how it can be called: adding
    /// `cutoffScale:` — even with a default — renamed the only entry point to
    /// `noteOn(pitch:velocity:cutoffScale:)`, which stopped witnessing the protocol's
    /// `noteOn(pitch:velocity:)` and broke `extension PolySynthVoice: NoteVoice`
    /// (declared in `PianoRollView.swift`, next to `protocol NoteVoice` — NAMED, not by
    /// line, because #475 removed 1020 lines from that file and every number in it moved.
    /// ⛔ This said "deleted 1013 lines" and no measurement produces that: `git show --stat`
    /// on the deletion commit reads 54 insertions / 1020 deletions, i.e. **966 net** — the
    /// file went 2291 → 1325. Neither figure is 1013. The POINT of the sentence — name the
    /// neighbour, never cite its line — survives intact; the number was decoration, and a
    /// decorative number in a sentence arguing against numbers is the whole joke.)
    /// The Xcode gate caught it on 4655323; this two-parameter
    /// entry point is the witness, not a redundant convenience. Do not merge the two back
    /// together by re-defaulting `cutoffScale` below.
    public func noteOn(pitch: Int, velocity: Float = 0.8) {
        noteOn(pitch: pitch, velocity: velocity, cutoffScale: 1)
    }

    /// Sound a note with per-note filter expression (the play surface's MPE-style morph).
    /// `cutoffScale` multiplies THIS note's filter cutoff; 1 = the patch's own value.
    ///
    /// `cutoffScale` deliberately has NO default — that is what keeps this unambiguous
    /// against the two-parameter witness above.
    public func noteOn(pitch: Int, velocity: Float = 0.8, cutoffScale: Float) {
        if !Self.noteTraced {
            Self.noteTraced = true
            EchoelCrashLog.breadcrumb("polyVoice.noteOn#1 enqueue pitch=\(pitch)")
        }
        // Enqueue only — the AUDIO thread applies it (drains in the render block).
        // This is the fix for the first-note crash: previously noteOn mutated the
        // poly engine's voice arrays (phases/envelope/filter) on the MAIN thread
        // while the audio thread was rendering those same Swift arrays →
        // copy-on-write refcount race → heap corruption → EXC_BAD_ACCESS. Routing
        // note events through a lock-free SPSC queue means ALL voice-state
        // mutation happens on the one audio thread, never racing the render.
        _ = noteCommands.tryEnqueue(
            // NaN-safe clamp — `min(max(v, 0), 1)` passes NaN through (CLAUDE.md's
            // argument-order law). This is DEFENCE IN DEPTH, not the only guard: the
            // consumer on the other side of the queue, `EchoelPolyDDSP.noteOn`, already
            // clamps in the SAFE order and `velocityGain` is `.isFinite`-guarded. Said
            // explicitly because the first version of this comment called this "the last
            // gate", which would invite a later session to delete those as redundant.
            NoteCommand(kind: .on, pitch: Int32(pitch), velocity: velocity.clamped(to: 0...1),
                        cutoff: cutoffScale.clamped(to: 0.1...8))   // NaN-safe, same law as the engine
        )
    }

    /// Release a sounding note (no-op if that pitch isn't held).
    public func noteOff(pitch: Int) {
        _ = noteCommands.tryEnqueue(NoteCommand(kind: .off, pitch: Int32(pitch), velocity: 0))
    }

    /// GLIDE a held note to a new pitch WITHOUT retriggering (founder 2026-07-08:
    /// "Glide bzw. Portamento … kann man auch einstellen"). The voice(s) holding
    /// `oldPitch` keep their running envelope and slide to the new frequency at the
    /// portamento time set via `setPortamento(seconds:)` — true legato under a
    /// travelling finger. If the old note is already gone, a normal noteOn fires.
    public func slide(from oldPitch: Int, to newPitch: Int, velocity: Float = 0.8,
                      cutoffScale: Float = 1) {
        _ = noteCommands.tryEnqueue(NoteCommand(kind: .slide, pitch: Int32(newPitch),
                                                velocity: velocity.clamped(to: 0...1),  // NaN-safe
                                                pitch2: Int32(oldPitch),
                                                cutoff: cutoffScale.clamped(to: 0.1...8)))
    }

    /// PER-NOTE filter expression for a note that is already sounding — the finger still
    /// down, moving (founder 2026-07-27: "mehr MPE vibes … je nach Position ein bisschen
    /// anders klingen"). Distinct from `setCutoffScale`, which is the GLOBAL automation
    /// scale for the whole instrument: that one is why three fingers at three heights all
    /// used to get the LAST finger's filter. The two multiply in the render.
    ///
    /// Enqueued like every other note event so the write lands on the audio thread and
    /// never races the render — the same first-note-crash discipline as `noteOn`.
    /// Returns whether the update was actually queued. The caller throttles on "last value
    /// SENT", so it must not record a value the queue rejected — a rejected update with a
    /// finger that then stops moving would leave that note's colour permanently wrong, with
    /// no further delta to heal it. This is the one note API whose result is worth reading:
    /// a dropped note-on/off is a different (worse) problem with a different fix.
    @discardableResult
    public func setNoteCutoffScale(pitch: Int, scale: Float) -> Bool {
        noteCommands.tryEnqueue(NoteCommand(kind: .expression, pitch: Int32(pitch),
                                            velocity: 0,
                                            cutoff: scale.clamped(to: 0.1...8)))
    }

    /// Portamento/glide time in seconds for slid notes (0 = the legacy ~2 ms
    /// micro-glide, i.e. effectively off). Atomic fan-out to the poly engine.
    public func setPortamento(seconds: Float) {
        poly.setPortamento(seconds: seconds)
    }

    /// Switch on the per-voice expression level trim (#230) and tell the engine which pitch is
    /// its neutral point, or pass `nil` to switch it off (the default for every other voice).
    ///
    /// ONLY THE PLAY SURFACE SHOULD CALL THIS, and only with its own middle band. The trim
    /// exists because that surface's vertical axis picks octave AND filter together; the
    /// generated take has no such axis, so enabling it there would silently re-balance every
    /// generated note against a reference nobody chose. See `ExpressionLevelTrim`.
    ///
    /// ⚠️ AND THAT SEPARATION IS AN INJECTION FACT, NOT A TYPE BOUNDARY. `FloatingVisualWindow`
    /// hands the surface `touchSynth ?? synth` — the second being the SHARED take voice. Today
    /// `touchSynth` is always non-nil (`EchoelmusicApp` constructs and injects it
    /// unconditionally), so the fallback cannot fire; but the guarantee above is one deleted
    /// `.environment` line deep. If that fallback ever becomes reachable, this setter would run
    /// on the take voice — which is the exact outcome the paragraph above forbids.
    ///
    /// Atomic fan-out, not a queued note command: it is a setting, not an event, and a
    /// setting that lands one block late is correct — the alternative (a queue slot per key
    /// change) would compete with note-ons for a bounded queue.
    public func setExpressionTrimReference(pitch: Int?) {
        poly.expressionTrimReferencePitch = pitch.map { Int32(clamping: $0) } ?? -1
    }

    // MARK: - Slide expression (touch-performance gesture)

    /// User depths for the slide gesture (set from the Play-surface-sound menu;
    /// low-rate writes). 0 disables the respective dimension.
    @ObservationIgnored public var slideVibratoDepth: Float = 0.35
    @ObservationIgnored public var slideChorusDepth: Float = 0.30
    @ObservationIgnored private var slideEnergy: Float = 0
    @ObservationIgnored private var slideStamp: CFAbsoluteTime = 0

    /// Push slide-gesture energy (called from touch-move events on the main
    /// thread). The main-side accumulator decays lazily between pushes; the
    /// ENGINE-side values additionally settle on the audio clock every render
    /// block (~0.45 s tau, see EchoelPolyDDSP.renderStereo) — so a resting
    /// finger truly lets the expression fade even though it fires no events.
    public func pushSlideExpression(_ amount: Float) {
        let now = CFAbsoluteTimeGetCurrent()
        if slideStamp > 0 {
            slideEnergy *= Float(exp(-(now - slideStamp) / 0.45))
        }
        slideStamp = now
        slideEnergy = min(1, slideEnergy + max(0, min(amount, 0.5)))
        poly.setSlideExpression(vibrato: slideEnergy * slideVibratoDepth,
                                chorus: slideEnergy * slideChorusDepth)
    }

    /// Release the slide expression (all fingers lifted / surface dismissed).
    /// Only the main-side energy resets; the engine's live values FADE on the
    /// audio clock (renderStereo's ~0.45 s decay) instead of stepping to zero —
    /// an instant cut could tick ringing release tails by up to ~28 cents.
    public func clearSlideExpression() {
        slideEnergy = 0
        slideStamp = 0
    }

    /// Release every held note (release tails fade naturally).
    public func allNotesOff() {
        _ = noteCommands.tryEnqueue(NoteCommand(kind: .allOff, pitch: 0, velocity: 0))
    }

    /// Standard A440 equal temperament: midi 69 = 440 Hz.
    public nonisolated static func frequency(forMIDINote note: Int) -> Float {
        440 * powf(2, (Float(note) - 69) / 12)
    }

    #if DEBUG
    /// TEST SEAM (Debug-only): last concert pitch fanned in, so the lane-rack
    /// setTuning fan can be pinned to the poly voices without an engine (mirrors
    /// SubBassVoice.lastTuningForTests).
    @ObservationIgnored internal private(set) var lastTuningForTests: Double?
    #endif

    /// Set the concert pitch (Kammerton) the voices tune to. A4 in Hz, clamped to
    /// a musical range so a stray value can't detune into inaudibility. Takes effect
    /// on the next note (and is safe to call while a loop plays).
    public func setTuning(a4Hz: Double) {
        poly.a4Hz = Float(min(max(a4Hz, 380), 500))
        #if DEBUG
        lastTuningForTests = a4Hz
        #endif
    }

    /// Per-instrument TRANSPOSE (founder 2026-07-14): shift this voice's pitch by whole
    /// semitones, clamped to ±48 (±4 octaves) so a stray value can't detune out of the
    /// audible range. Takes effect on the next note; safe to call while a loop plays
    /// (atomic Float write, read at the next noteOn — same discipline as `setTuning`).
    public func setTranspose(semitones: Int) {
        poly.transposeSemitones = Float(min(max(semitones, -48), 48))
    }

    /// Per-instrument DETUNE (founder 2026-07-14 "transpose detune"): offset this voice's
    /// pitch by a fraction of a semitone, in cents, clamped ±100 (±1 semitone). Takes
    /// effect on the next note; safe to call while a loop plays (atomic Float write, read
    /// at the next noteOn — same discipline as `setTranspose`/`setTuning`).
    public func setDetune(cents: Float) {
        poly.detuneCents = min(max(cents.isFinite ? cents : 0, -100), 100)
    }

    /// Per-instrument OKTAVER (founder 2026-07-14 "transpose detune und Oktaver"):
    /// double every played note with ONE extra voice an octave up (+1) or down (−1)
    /// at `mix` level (0…1). Direction 0 = off (default, bit-identical; mix itself
    /// defaults to 0.5 and is inert while off). Takes effect on the
    /// next note; safe to call while a loop plays (atomic writes read at the next
    /// noteOn — same discipline as `setTranspose`/`setDetune`). Control-path only:
    /// the extra voice rides the existing poly voice pool, no render-thread change.
    /// Callers that only steer the direction omit `mix` — the ONE engine default
    /// applies (no drifting magic numbers at the call sites; code-review LOW).
    public func setOctaver(direction: Int, mix: Float = EchoelPolyDDSP.defaultOctaveMix) {
        poly.setOctaver(direction: direction, mix: mix)
    }

    /// Main-actor mirror of the active retune table so UI code (the touch
    /// instrument's note→colour mapping) can compute the SOUNDING frequency of a
    /// pitch — including Pythagorean/just/maqām offsets — without touching the
    /// audio-thread table. Rare writes (tone-system change), imperative reads.
    @ObservationIgnored public private(set) var uiTuningCents: [Float] = Array(repeating: 0, count: 12)

    /// Install a microtonal pitch-class retune table (12 entries, cents from 12-TET).
    /// All zeros = standard equal temperament. Safe to call while a loop plays;
    /// takes effect on the next note.
    public func setTuningCents(_ cents: [Float]) {
        poly.setTuningCents(cents)
        if cents.count == 12 { uiTuningCents = cents }
    }

    // MARK: - Patch recall

    /// Recall a sound: enqueue the patch; the audio thread fans it across every
    /// voice in its render drain (so the spectral-envelope array rewrite never
    /// races the render).
    public func apply(_ patch: SynthPatch) {
        // Unison is a poly-engine property (it spawns extra detuned voices per note),
        // not a per-voice timbre param — set it directly (atomic write, read at the
        // next noteOn, same discipline as setTuning).
        //
        // RICHNESS DEFAULT (sound overhaul, Phase 2): when a patch doesn't specify
        // unison (old/blank patches, and every generative genre patch), default to a
        // GENTLE 2-voice / ~7¢ unison so leads & pads have ensemble body instead of a
        // single thin voice — the #1 "thin/rudimentary" cause (research: subtle
        // detune/unison is the thin→rich lever). Explicit patch values — including an
        // explicit mono `1` — are always honoured, so this never overrides intent.
        poly.setUnison(count: patch.unisonVoices ?? 2, detuneCents: patch.unisonDetuneCents ?? 7)
        // Resolve HERE (control thread) — see `patchCommands`. `resolved()` is the
        // only place the String→enum lookups run.
        _ = patchCommands.tryEnqueue(patch.resolved())
        appliedPatch = patch
        // EchoelVoice #593 — a patch that CARRIES a measured voice applies it through
        // the #591a staging, which re-fans AFTER this very recall's drain (trap 1), so
        // the order here cannot lose it. A patch WITHOUT one deliberately leaves any
        // live captured profile alone: the capture survives patch recalls by design
        // (#591a), and `clearVoiceProfile()` stays the one remover.
        if let taps = patch.voiceProfileTaps {
            if applyVoiceProfile(taps, blend: patch.voiceProfileBlend ?? 1) {
                // Provenance (#593c review F1): an embedded profile carries its own
                // label+blend into the memory — set AFTER the accepted apply, because
                // a REFUSED short half must not stamp its label onto whatever profile
                // is actually live (F2: the guard above keeps the OLD taps then).
                appliedVoiceProfileLabel = patch.voiceProfileLabel
                appliedVoiceProfileBlend = patch.voiceProfileBlend
            }
        }
    }

    /// The last patch handed to `apply(_:)` — the voice's patch MEMORY, so any
    /// door (studio panel, timeline lane) can open the editor on the sound
    /// that is actually playing instead of a blank Init. Control-plane only.
    public private(set) var appliedPatch: SynthPatch?

    // MARK: - Measured voice timbre (EchoelVoice #591)

    /// The last measured profile handed to `applyVoiceProfile(_:blend:)` — control-plane
    /// MEMORY (the `appliedPatch`/`appliedInsert` idea), so a door or test can read what
    /// the instrument was given. Observation-ignored: read once on open, never reactively.
    @ObservationIgnored public private(set) var appliedVoiceProfile: [Float]?

    /// PROVENANCE of the live profile (#593c review F1): the label + blend it ARRIVED
    /// with when it came embedded in a patch; nil = a fresh capture this launch.
    /// Without this memory, "whose voice is live?" was answered by comparing taps
    /// against the CURRENT base patch — a proxy that broke the moment the player
    /// switched patches under a surviving profile: the next save relabeled artist X's
    /// embedded voice as the current player (the misattribution the share-label law
    /// exists to prevent). Written beside `appliedVoiceProfile`, nil'd with it.
    @ObservationIgnored public private(set) var appliedVoiceProfileLabel: String?
    @ObservationIgnored public private(set) var appliedVoiceProfileBlend: Float?

    /// The engine's harmonic socket — the minimum tap count `applyVoiceProfile`
    /// accepts, from the ONE definition (#416: the poly engine itself). Public so the
    /// save flow can tell "player cleared the profile" from "the engine refused a
    /// short third-party half" (#593c review F2) — stripping the latter would destroy
    /// a shared voice the player never even heard.
    public var voiceProfileTapFloor: Int { poly.harmonicCount }

    /// CONTROL THREAD. Install a measured voice-timbre profile (from
    /// `VoiceTimbreProfiler.profile()`) across the poly pool. It is staged in the engine
    /// and fanned on the audio thread — AND re-fanned after every patch recall, because
    /// the recall drain's unconditional `applyTimbre` would otherwise wipe it (trap 1 of
    /// `scratchpads/PLAN_ECHOEL_VOICE.md`). The measured voice survives patch changes
    /// until `clearVoiceProfile()`. Returns whether the profile was ACCEPTED — false =
    /// too short for the socket, nothing changed (`apply(_:)` keys provenance on this).
    @discardableResult
    public func applyVoiceProfile(_ taps: [Float], blend: Float = 1) -> Bool {
        guard taps.count >= poly.harmonicCount else { return false }
        // Remember the ENGINE-SHAPED values (NaN→0, negatives clamped — the same
        // sanitize `setCustomTimbre` applies), so a door reading this memory can never
        // display a tap the engine does not carry (review #591a).
        appliedVoiceProfile = taps.prefix(poly.harmonicCount)
            .map { $0.isFinite ? Swift.max(0, $0) : 0 }
        // A DIRECT call is the capture path: provenance is "this player, unlabeled
        // until saved". `apply(_:)` overwrites both right after an accepted embed.
        appliedVoiceProfileLabel = nil
        appliedVoiceProfileBlend = nil
        poly.setCustomTimbre(taps, blend: blend)
        return true
    }

    /// CONTROL THREAD. Hand timbre back to the patch pathway: re-applies the remembered
    /// patch so its own instrument spectrum (or pure shape) is restored by the normal
    /// recall drain — the engine's deactivation edge is gated so this same-block pair
    /// cannot wipe what the patch just restored. (Pathological edge, accepted: if the
    /// 8-deep patch queue is FULL this block, the re-apply is dropped and the voices
    /// fall to the pure shape until the next recall — self-healing, not worth code.)
    public func clearVoiceProfile() {
        appliedVoiceProfile = nil
        appliedVoiceProfileLabel = nil
        appliedVoiceProfileBlend = nil
        poly.clearCustomTimbre()
        // #593: strip the voice half from the patch MEMORY before re-applying — an
        // embedded-profile patch would otherwise re-apply its own profile on the next
        // line and Clear could never clear (the Council's sharpest concern on this
        // slice). For such a patch "Clear" MEANS "this patch, without its voice";
        // the stripped copy lives only in memory — nothing here writes the store.
        if var p = appliedPatch {
            p.voiceProfileTaps = nil
            p.voiceProfileLabel = nil
            p.voiceProfileBlend = nil
            apply(p)
        }
    }

    /// Set unison directly (live, outside a patch) — count 1 = off.
    public func setUnison(count: Int, detuneCents: Float) {
        poly.setUnison(count: count, detuneCents: detuneCents)
    }

    /// Install the melodic bus's per-track insert FX (control thread). `.off`/passthrough
    /// removes it. Enqueued lock-free; applied on the audio thread at the next render block.
    /// Off by default → bit-identical until dialed.
    public func setInsert(_ fx: TrackFX) {
        appliedInsert = fx
        _ = fxCommands.tryEnqueue(fx)
    }

    /// The last insert handed to `setInsert(_:)` — control-plane MEMORY (same idea as
    /// `appliedPatch`), so doors and tests can read what the voice was given without
    /// touching the render-side queue. Never read by the render block. Observation-
    /// ignored (review-hardened): written at UI drag rate, and no view is meant to
    /// live-track it — a future door reads it once on open, not reactively.
    @ObservationIgnored public private(set) var appliedInsert: TrackFX?

    /// Global filter-cutoff multiplier (1 = no change), driven by parameter
    /// automation. Atomic write; takes effect on the next render block.
    public func setCutoffScale(_ scale: Float) {
        poly.setCutoffScale(scale)
    }

    /// Bind this voice's bio-INDEPENDENT, render-effective DDSP parameters into the
    /// shared automation router, so a drawn/recorded automation lane (and the tool
    /// path) moves them live — the "all parameters automatable" wiring. Each closure
    /// fans an atomic Float across the voice pool via `forEachVoice` (the same
    /// control-plane discipline as entrainment/tuning; the render reads each var
    /// lock-free). Ranges match `DDSPParameterCatalog`. Called once at app wiring
    /// time, exactly like the AUv3 host binds a loaded plugin's knobs.
    ///
    /// DELIBERATELY EXCLUDED **AS DIRECT WRITES** (bio-contested / unsafe — see
    /// scratchpads/PLAN_DAW_EPIC): harmonicity · noiseLevel · reverbMix/decay · raw filter
    /// base · vibrato · brightness · raw amplitude — the bio loop overwrites them on every new bio frame
    /// (~1 Hz today, at most the 10 Hz poll rate; it was written "~10 Hz" here and that is
    /// the poll, not the apply) or the write races a shared spectral table / is gated off.
    /// The rate is not what disqualifies them — the OVERWRITE is — so automating them needs a
    /// separate automation×bio composition (write the `bioBase*` centers), not a
    /// direct write. `ddsp.amp.level` therefore targets the UNCONTESTED
    /// `patchOutputLevel` (which the render reads and neither bio nor noteOn touch),
    /// NOT `amplitude`. Filter automation stays on the existing scale-based lane
    /// (`setCutoffScale`), so the raw Hz `ddsp.filter.cutoff` is not bound here.
    ///
    /// ⚠️ READ "AS DIRECT WRITES" LITERALLY — four names on that list are now bound, through
    /// the very mechanism the paragraph prescribes. `harmonicity` and `noiseLevel` (#557) and
    /// the `vibrato` pair (#558) are automatable via their `bioBase*` centre, which is
    /// composition, not an overwrite. The list stayed as written because it is still exactly
    /// right about the DIRECT write; #557 bound two of its names without qualifying it, and a
    /// doc block that forbids on one line what the list below it does is the shape #425 names.
    ///
    /// ⛔ AND THE FILTER SENTENCE IS THE REASON `ddsp.filter.cutoff` IS STILL OUT — a reason
    /// #557 missed. Its ⛔ note called that keyPath "bindable on its own merits" because the
    /// only hazard it checked was the sentinel (unreachable, min 20 Hz). But this file already
    /// said, fifteen lines up, that filter automation HAS an address: the enum target
    /// `ddsp.filter.cutoffScale`, a ×-multiplier with its own reset-to-neutral lifecycle in
    /// `AutomationPlayer.applyStep`. Binding the Hz keyPath too would put one audible parameter
    /// behind two automation addresses in one picker — "Filter Cutoff" in Hz and "Filter Cutoff"
    /// in ×, with no way for a player to tell which is the filter (#416). Correcting my own
    /// claim rather than the older sentence, because the older sentence was right.
    /// The base engine keyPaths this voice can automate. SINGLE SOURCE OF TRUTH for
    /// both the global router binding (`bindAutomatable`) and the per-track dispatch
    /// (`applyAutomatable`). Bio-contested params are intentionally excluded — they need
    /// automation×bio composition (write the `bioBase*` centre), not a direct write.
    /// `nonisolated` so a picker / contract test may read it off the main actor.
    ///
    /// ⛔ THE EXCLUSION SAID "(filter/brightness)" AND THE CONTESTED SET IS SIX (#556).
    /// Measured by brace-extracting `EchoelDDSP.applyBioReactive` and looking for
    /// assignments: `brightness` · `filterCutoff` · `harmonicity` · `noiseLevel` ·
    /// `vibratoDepth` · `vibratoRate` are all recomputed from their `bioBase*` anchor on
    /// the RENDER thread. Naming two of six is the shape this repo keeps paying for —
    /// a parenthetical reads as the full list, so the next session adds
    /// `ddsp.osc.harmonicity`, sees the value move in the debugger, and ships a control
    /// the body overwrites within one render block. Worse than the dead-stage placebo
    /// (#546), because it works for a few milliseconds.
    ///
    /// ⭐ AND THE POSITIVE HALF WAS NEVER WRITTEN DOWN, which is why the list reads
    /// arbitrary: the six entries below are EXACTLY the parameters `applyBioReactive`
    /// does not assign — zero hits each. The rule is not "these six felt safe", it is
    /// **automation may own a parameter only where it is the ONLY writer; everywhere else
    /// it owns the ANCHOR.** `TheAutomatableSetHasOneWriterTests` makes that executable,
    /// so adding a contested base goes red with the anchor named instead of shipping.
    ///
    /// ⚠️ FOR WHOEVER BINDS THE ANCHORS LATER: `applyBioReactive` runs on the audio RENDER
    /// thread and READS them, so an anchor setter is a cross-thread write. It is the same
    /// write `SynthPatch.apply(to:)` already performs off the render thread (`Float`,
    /// atomic width) — follow that precedent, do not invent a second mechanism, and do not
    /// take a lock.
    /// ⭐ THE FIRST TWO ANCHORS ARE BOUND (#557) — `ddsp.osc.harmonicity` and
    /// `ddsp.osc.noiseLevel` write `bioBaseHarmonicity` / `bioBaseNoiseLevel`, the centres
    /// the bio path modulates AROUND, never the live properties it recomputes. They are the
    /// two contested parameters whose anchor carries NO sentinel: `applyBioReactive` reads
    /// both unconditionally, so every value in their 0…1 descriptor range means exactly what
    /// it says.
    ///
    /// ⛔ AND THAT IS NOT TRUE OF ALL SIX — the anchors are not uniformly bindable, which is
    /// the fact #556's rule did not yet cover. THREE of them are read behind a sentinel
    /// comparison, and for ONE the sentinel sits INSIDE the descriptor's range:
    ///   · `bioBaseBrightness` WAS read behind `> 0` while `ddsp.osc.brightness` has **min 0**.
    ///     An automation lane touching exactly 0 would not just make the sound dark — it would
    ///     flip `applyBioReactive` out of its anchored branch into the legacy one, mid-take,
    ///     silently. **#564 fixed the SENTINEL rather than working around it** (−1, read `>= 0`,
    ///     the vibrato trio's discipline) and bound the parameter in the same commit. The hazard
    ///     was never automation-only: the Brightness field in `soundPanel` reaches 0 by hand, so
    ///     the mode change shipped to players who never drew a lane.
    ///     ⛔ AND THE NOTE HERE CITED `TheAnchorSentinelsAreOutOfReachTests` AS WHAT "KEEPS IT
    ///     OUT". No such file has ever existed in this repo (`git grep` finds this line and
    ///     nothing else) — the guard doing the work was `TheAutomatableSetHasOneWriterTests`
    ///     claim 5 all along. A prose citation of a guard that does not exist is worse than no
    ///     citation: it reads as a safety net, so the next reader stops looking for one.
    ///   · `bioBaseFilterCutoff` is read behind `> 0` and `ddsp.filter.cutoff` starts at 20 Hz,
    ///     so the SENTINEL is unreachable — but the parameter stays out for a different reason
    ///     this note originally missed: filter automation already has an address
    ///     (`ddsp.filter.cutoffScale`). See the ⛔ correction above the list.
    ///   · `bioBaseVibratoDepth` / `bioBaseVibratoRate` are read behind `>= 0` with a −1
    ///     sentinel, unreachable from a 0…1 / 0…12 range, and neither has a competing
    ///     address — **bound since #558.**
    /// Still excluded for their own reasons: the two reverb parameters (stage gated off, #546)
    /// and `ddsp.osc.frequency` (owned per note by the note engine).
    public nonisolated static let automatableBases: [String] = [
        "ddsp.warmth.drive", "ddsp.env.attack", "ddsp.env.decay",
        "ddsp.env.sustain", "ddsp.env.release", "ddsp.amp.level",
        "ddsp.osc.harmonicity", "ddsp.osc.noiseLevel",
        "ddsp.mod.vibratoDepth", "ddsp.mod.vibratoRate",
        "ddsp.osc.brightness"
    ]

    /// The live setter for an automatable base keyPath, or nil if the base is not
    /// automatable on this voice. Used by BOTH bind paths so the global router and
    /// the per-track dispatch can never drift.
    private func automatableSetter(forBase base: String) -> ((Float) -> Void)? {
        switch base {
        case "ddsp.warmth.drive": return { [weak self] v in self?.poly.forEachVoice { $0.warmthDrive = v } }
        case "ddsp.env.attack":   return { [weak self] v in self?.poly.forEachVoice { $0.attack = v } }
        case "ddsp.env.decay":    return { [weak self] v in self?.poly.forEachVoice { $0.decay = v } }
        case "ddsp.env.sustain":  return { [weak self] v in self?.poly.forEachVoice { $0.sustain = v } }
        case "ddsp.env.release":  return { [weak self] v in self?.poly.forEachVoice { $0.release = v } }
        case "ddsp.amp.level":    return { [weak self] v in self?.poly.forEachVoice { $0.patchOutputLevel = v } }
        // ANCHORS, not live properties (#556/#557). `applyBioReactive` recomputes
        // `harmonicity` and `noiseLevel` from these two centres on the render thread every
        // block, so writing the live property here would be overwritten within one block —
        // a control that moves in a debugger and cannot be heard. Writing the centre lets
        // automation and the body compose: automation says where the parameter sits, the
        // body swings around it, exactly as a patch already does.
        //
        // ⚠️ CROSS-THREAD, and deliberately the SAME write `SynthPatch.apply(to:)` already
        // performs: a plain `Float` store of atomic width, off the render thread, no lock.
        // Do not "make this safe" with a queue or a lock — the render side reads these as
        // plain values by design, and adding synchronisation here would put a blocking
        // primitive one hop from the audio path.
        case "ddsp.osc.harmonicity": return { [weak self] v in
            self?.poly.forEachVoice { $0.bioBaseHarmonicity = v } }
        case "ddsp.osc.noiseLevel":  return { [weak self] v in
            self?.poly.forEachVoice { $0.bioBaseNoiseLevel = v } }
        // The vibrato pair (#558), same anchor discipline. Their sentinel is −1 and the
        // descriptor ranges start at 0, so automation can never write it — the anchored
        // branch stays chosen for every value a lane can produce, and depth 0 means "no
        // vibrato" rather than "fall back to the legacy curve".
        case "ddsp.mod.vibratoDepth": return { [weak self] v in
            self?.poly.forEachVoice { $0.bioBaseVibratoDepth = v } }
        case "ddsp.mod.vibratoRate":  return { [weak self] v in
            self?.poly.forEachVoice { $0.bioBaseVibratoRate = v } }
        // Brightness (#564), the anchor whose sentinel used to sit inside its own range. It is
        // bound only because the sentinel MOVED to −1 — binding it against `> 0` would have made
        // the bottom of the lane a mode change rather than a dark sound. Nothing here is special:
        // it is the same plain `Float` store the four anchors above perform.
        case "ddsp.osc.brightness":   return { [weak self] v in
            self?.poly.forEachVoice { $0.bioBaseBrightness = v } }
        default: return nil
        }
    }

    public func bindAutomatable(into router: ParameterApplyRouter) {
        for base in Self.automatableBases {
            if let setter = automatableSetter(forBase: base) { router.bind(base, setter) }
        }
    }

    /// Apply a REAL (already-in-range) value to a base param on THIS voice — the
    /// per-track automation dispatch target (L2/L4 S2b). Returns whether `base` is
    /// automatable here (false = silent no-op, never a wrong-param write).
    @discardableResult
    public func applyAutomatable(base: String, real: Float) -> Bool {
        guard let setter = automatableSetter(forBase: base) else { return false }
        setter(real)
        return true
    }

    /// B2 lane pan: stereo position of this voice's whole output, −1…1 (0 =
    /// center). Control-plane only — `sourceNode` conforms to `AVAudioMixing`
    /// and is connected into the master mixer, so the ENGINE pans downstream;
    /// nothing here runs on the render block.
    public func setPan(_ pan: Float) {
        sourceNode.pan = max(-1, min(1, pan))
    }

    /// H4 lane gain: this voice's whole-output level at the mixer, 0…2 (1 = unity;
    /// the lane fader's `effectiveGain` — mute/solo land here as 0, silencing even
    /// already-ringing notes). Control-plane only, like `setPan`: `sourceNode`
    /// conforms to `AVAudioMixing`, the ENGINE scales downstream of the render.
    public func setGain(_ gain: Float) {
        sourceNode.volume = max(0, min(2, gain.isFinite ? gain : 0))   // non-finite ⇒ silent
    }

    // MARK: - Bus subscription (bio modulation only — reads latestBio snapshot)

    /// Begin polling `bus.latestBio` at 10 Hz and fanning bio modulation across
    /// all active voices. Idempotent. Does NOT drain controllerEvents.
    public func start(subscribing bus: EngineBus) {
        guard !isSubscribed else { return }
        self.bus = bus
        isSubscribed = true
        loop.start(interval: .milliseconds(100)) { [weak self] in
            guard let self, let bus = self.bus else { return }
            self.applyLatestIfFresh(from: bus)
        }
    }

    public func stop() {
        loop.stop()
        isSubscribed = false
    }


    /// #813 — one per voice, main-actor only. Two independent trackers over the same frame
    /// sequence produce the same output, which is why the trend is NOT a field on
    /// `BioSampleFrame`: keeping it here leaves the six frame construction sites, the OSC
    /// egress and the wire contract untouched.
    private var coherenceTrend = CoherenceTrend()

    private func applyLatestIfFresh(from bus: EngineBus) {
        guard bioModulationEnabled else { return }
        guard let frame = bus.latestBio else { return }
        guard frame.timestamp != lastTimestamp else { return }
        lastTimestamp = frame.timestamp
        framesApplied &+= 1

        // Hand the parameters to the AUDIO thread instead of mutating the poly engine
        // here. Applying `poly.applyBioReactive(...)` on this MainActor poll rewrote
        // each voice's spectral-envelope array while the audio thread read it in
        // render() — a cross-thread array race. The render block drains this queue and
        // applies it on the one audio thread (after the patch drain, so `bioBase*` is
        // already set). `profile` is resolved here on the main actor (reads the
        // control-plane `bioMappingHarmonic`) and carried in the value.
        // #813 — the coherence TREND, which had no producer until now. `applyBioReactive`'s
        // rising/falling spectral morph reads it and every construction site passed the literal
        // 0, so the whole else-branch was unreachable (#496). Fed from the RAW `frame.coherence`
        // and the house measured-test, NOT from `coherenceForSound`: substituting a neutral for
        // an unmeasured channel is right for a LEVEL and wrong for a DERIVATIVE, because the
        // substitution itself would read as movement. Computed HERE, on the main actor, for the
        // same reason the rest of this value is — only the drain is on the audio thread.
        let trend = coherenceTrend.update(coherence: frame.coherence,
                                          measured: BioModulationMap.isMeasured(.coherence, in: frame),
                                          at: frame.timestamp)

        _ = bioCommands.tryEnqueue(PolyBioParams(
            coherence: frame.coherenceForSound,
            hrv: frame.hrvForSound,   // 0 = unmeasured → neutral; see BioSampleFrame
            // ⛔ These two used to be `clampUnit((frame.heartRateBPM - 40) / 160)` and
            // `clampUnit(frame.breathPhase)` — RAW reads, so an UNMEASURED channel handed
            // the engine an EXTREME instead of the neutral the engine declares (#497).
            // No lock → vibrato 25 % under the patch; no respiration → the whole voice
            // 0.92 dB under it. The neutral now lives on the frame, next to its twins
            // `hrvForSound` / `coherenceForSound`, which is where it always belonged.
            heartRate: frame.heartRateForSound,
            breathPhase: frame.breathPhaseForSound,
            breathDepth: 0.5,
            lfHf: 0.5,
            coherenceTrend: trend,
            profile: bioMappingHarmonic ? .harmonicSeries : .natural
        ))
        applyEntrainment(neutralCoherence: frame.coherenceForSound,
                         heartRateBPM: frame.heartRateBPM,
                         motionEnergy: frame.motionEnergy)
    }

    /// Drive the isochronic entrainment from the body. Quality gates the depth: a frame
    /// only carries `heartRateBPM > 0` on a confident pulse lock (the camera publisher
    /// gates on its lock threshold), and motion degrades it — so a noisy/absent signal
    /// can never push a strong stimulus. Writes band/depth to every voice's existing
    /// `EchoelEntrainment` (same main-poll→audio-read path as `applyBioReactive`).
    /// `neutralCoherence` names a precondition, not a preference: pass
    /// `BioSampleFrame.coherenceForSound`, never the raw field. An unmeasured 0 reaching
    /// `BioEntrainmentDirector` reads as "maximally incoherent" and reinstates the muffle
    /// this whole rule exists to prevent — and a `private func` taking a parameter called
    /// `coherence` is exactly how a second caller would reintroduce it silently.
    private func applyEntrainment(neutralCoherence: Float, heartRateBPM: Float, motionEnergy: Float) {
        guard entrainmentEnabled else { return }
        // Same as `BioTempoDirector`: a loose `Float` parameter, not a frame — the hoisted
        // `BioSampleFrame.hasMeasuredHeartRate` cannot be reached from here (#244).
        let quality: Float = heartRateBPM > 0 ? clampUnit(1 - motionEnergy) : 0
        let target = BioEntrainmentDirector(manualBand: entrainmentManualBand)
            .target(coherence: clampUnit(neutralCoherence), quality: quality)
        entrainmentTarget = target
        audioEntrainmentActive = target.depth > 0   // idle gate must stay open
        poly.forEachVoice { voice in
            voice.entrainment.band = target.band
            voice.entrainment.depth = target.depth
        }
    }

    /// Silence the stimulus on every voice (called when entrainment is disarmed).
    private func clearEntrainment() {
        poly.forEachVoice { $0.entrainment.depth = 0 }
        entrainmentTarget = .inactive
        audioEntrainmentActive = false
    }

    private func clampUnit(_ x: Float) -> Float { min(max(x, 0), 1) }

    // MARK: - Source node (audio thread)

    private func makeSourceNode() -> AVAudioSourceNode {
        nonisolated(unsafe) let weakSelf = WeakBox(self)
        let renderBlock: AVAudioSourceNodeRenderBlock = { _, _, frameCount, audioBufferList in
            guard let voice = weakSelf.value else {
                PolySynthVoice.silence(audioBufferList: audioBufferList, frameCount: Int(frameCount))
                return noErr
            }
            voice.renderOnAudioThread(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2) else {
            return AVAudioSourceNode(renderBlock: renderBlock)
        }
        return AVAudioSourceNode(format: format, renderBlock: renderBlock)
    }

    /// Audio thread. Renders `frameCount` stereo samples from the poly engine
    /// into the (deinterleaved) AudioBufferList. nonisolated(unsafe) — see header.
    nonisolated(unsafe) private func renderOnAudioThread(
        frameCount: Int,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) {
        // Apply any pending patch recall FIRST (audio thread) so the timbre is set
        // before the notes that follow render — and so the spectral-envelope array
        // write happens on this thread, not racing the render.
        var patchApplied = false
        while let patch = patchCommands.dequeue() {
            poly.forEachVoice { patch.apply(to: $0) }
            patchApplied = true
        }
        // Re-fan a measured voice profile AFTER the patch drain (whose `applyTimbre` is
        // unconditional and just overwrote it) and BEFORE the bio drain below, so the
        // order stays patch → voice timbre → bio, and the body modulates around the
        // measured envelope exactly as it does around a patch's. No-op unless a profile
        // is active or its version moved (EchoelVoice #591).
        poly.drainCustomTimbre(reassert: patchApplied)
        // Apply pending bio modulation HERE (audio thread), AFTER the patch drain so the
        // patch's `bioBase*` anchors are set before the body modulates around them, and
        // so each voice's spectral-envelope array rewrite happens on this one thread and
        // never races the render's read below. Drain to the latest queued frame (bio
        // updates ~1 Hz — the poll is 10 Hz but dedupes on timestamp — so the queue is
        // empty in almost every block; a cheap check, and cheaper than the old note said).
        // Runs even while silent so the timbre is current the instant a note arrives.
        var latestBio: PolyBioParams?
        while let p = bioCommands.dequeue() { latestBio = p }
        if let p = latestBio {
            poly.applyBioReactive(
                coherence: p.coherence,
                hrvVariability: p.hrv,
                heartRate: p.heartRate,
                breathPhase: p.breathPhase,
                breathDepth: p.breathDepth,
                lfHfRatio: p.lfHf,
                coherenceTrend: p.coherenceTrend,
                profile: p.profile
            )
        }
        // Drain per-bus insert-FX commands on the audio thread (params + coefficient
        // recompute here — pure arithmetic, no alloc). Both channels share the params but
        // keep independent biquad state; a fresh activation resets so there is no stale tail.
        while let fx = fxCommands.dequeue() {
            insertL.setParams(type: fx.filter, cutoffHz: fx.cutoffHz, resonance: fx.resonance, drive: fx.drive)
            insertR.setParams(type: fx.filter, cutoffHz: fx.cutoffHz, resonance: fx.resonance, drive: fx.drive)
            let nowActive = !fx.isPassthrough
            if nowActive && !insertActive { insertL.reset(); insertR.reset() }
            insertActive = nowActive
        }
        // Drain note commands HERE (audio thread) so all voice mutation is on this
        // one thread — never racing the render. Must run before the silence guard
        // so the first note both flips hasEverSounded and is applied atomically wrt
        // rendering.
        drainNoteCommands()
        guard hasEverSounded else {
            // #138 Slice 2: the chain is about to be skipped, so its tone-filter glide
            // must LAND on resume rather than sweep out of a value from before the
            // session's first note. Same at the two skip paths below.
            fxChain.noteRenderSkipped()
            Self.silence(audioBufferList: audioBufferList, frameCount: frameCount)
            return
        }
        // P1 idle-skip: everything decayed and no stimulus armed → pure silence
        // without running the engine. Commands above already drained, so params
        // stay current and the next note starts exactly on its block.
        if renderIdle {
            if audioEntrainmentActive {
                renderIdle = false; idleQuietFrames = 0   // stimulus armed → wake
            } else {
                fxChain.noteRenderSkipped()
                Self.silence(audioBufferList: audioBufferList, frameCount: frameCount)
                return
            }
        }
        let count = min(frameCount, Self.maxBlockFrames)
        poly.renderStereo(left: &scratchL, right: &scratchR, frameCount: count)
        // Genre/effect colour (long dub delay, vapor chorus, …). Audio-thread
        // safe: pre-allocated stages, no work for bypassed effects. The master gate
        // lets the Effects panel bypass the entire chain.
        if fxEnabled {
            fxChain.processBuffer(left: &scratchL, right: &scratchR, frameCount: count)
        } else {
            fxChain.noteRenderSkipped()
        }
        // Per-track melodic insert (user filter/drive), AFTER the genre fxChain so the two
        // never fight. Off = untouched (bit-identical). Independent L/R biquad state.
        if insertActive {
            for i in 0..<count {
                scratchL[i] = insertL.process(scratchL[i])
                scratchR[i] = insertR.process(scratchR[i])
            }
        }

        // BREATH SWELL (0.1 Hz coherence pacing — the medical core). Ramp the applied
        // depth toward its target so enabling/disabling never clicks, then multiply a
        // per-frame raised-cosine gain into the block. Pure arithmetic (one cosf per
        // sample) — no allocation, no locks: audio-thread safe. Skipped entirely when
        // off (depth ~0), so it is a true no-op unless the Fläche armed it.
        breathSwellDepth += (breathSwellTargetDepth - breathSwellDepth) * 0.05
        if breathSwellDepth > 0.0005 {
            let inc = 2 * Float.pi * Self.breathSwellHz / Float(Self.sampleRate)
            let depth = breathSwellDepth
            var ph = breathPhase
            for i in 0..<count {
                let g = Self.breathGain(phase: ph, depth: depth)
                scratchL[i] *= g
                scratchR[i] *= g
                ph += inc
            }
            breathPhase = ph.truncatingRemainder(dividingBy: 2 * Float.pi)
        }

        // P1 idle-skip bookkeeping: track the block peak (plain loop, pure
        // arithmetic — audio-thread safe). 2.5 s of consecutive digital
        // silence with no stimulus armed → sleep until the next note command.
        if !audioEntrainmentActive {
            var peak: Float = 0
            for i in 0..<count {
                let l = abs(scratchL[i]), r = abs(scratchR[i])
                if l > peak { peak = l }
                if r > peak { peak = r }
            }
            if peak < Self.idlePeakFloor {
                idleQuietFrames += count
                if idleQuietFrames >= Self.idleFrameThreshold {
                    renderIdle = true
                    // #389: falling asleep EMPTIES the chain. Without this the delay line and
                    // the reverb tank freeze holding the take's last seconds; because the skip
                    // measures the chain OUTPUT, a low `mix` can hide live energy under the
                    // floor, and the next thing that raises that mix — a bio route since #386 —
                    // walks seconds-old audio out. Exactly the stale-audio burst the
                    // SWITCH-CRACKLE RULE in EchoelFXChain.swift resets stages to prevent,
                    // reaching the chain through the idle skip instead of a bypass toggle.
                    //
                    // Runs ONCE per sleep, not per skipped block: the guard at the top of this
                    // render returns as soon as `renderIdle` is true, so this line is
                    // unreachable again until the voice WAKES.
                    //
                    // ⛔ "until a NOTE COMMAND wakes the voice" is what this line said first, and
                    // it names only one of the two wakes. `audioEntrainmentActive` turning true
                    // also clears `renderIdle` at the top guard, with no note involved — and it
                    // is the one that matters here, because it is also the flag that makes the
                    // `if !audioEntrainmentActive` above false, which forces `idleQuietFrames`
                    // to 0. Both paths re-arm the counter, so the once-per-sleep property holds
                    // either way; the sentence was over-precise, not the code.
                    //
                    // ⛔ `if fxEnabled` IS THE OWNERSHIP GATE, NOT AN OPTIMISATION, and leaving
                    // it out was #397's ship blocker. This bookkeeping is OUTSIDE the
                    // `if fxEnabled` branch above — it measures the SYNTH's output, which the
                    // bypass does not affect — so without this guard the voice could fall
                    // asleep and drain while the chain was bypassed, at the same moment the
                    // main thread's rising-edge drain in `setFXEnabled` ran. Two threads in
                    // `EchoelReverb.combBufL`'s zero-fill: the exact failure `noteRenderSleeping`
                    // was rewritten to prevent, re-entered from the other side.
                    //
                    // With the guard the two drains are exactly complementary: the audio thread
                    // owns the drain while the flag is TRUE, the control plane while it is
                    // FALSE. Nothing is lost — a chain that is bypassed when the voice sleeps
                    // gets drained by `setFXEnabled`'s rising edge instead, which is the only
                    // moment it could be heard again.
                    if fxEnabled { fxChain.noteRenderSleeping() }
                }
            } else {
                idleQuietFrames = 0
            }
        } else {
            idleQuietFrames = 0
        }

        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard abl.count > 0 else { return }
        // Channel 0 (left). For a deinterleaved stereo format there are 2 buffers;
        // a mono downstream graph may present 1 — handle both.
        copy(&scratchL, to: abl[0], count: count, total: frameCount)
        if abl.count > 1 {
            copy(&scratchR, to: abl[1], count: count, total: frameCount)
        }
    }

    /// Drain the note-command queue into the poly engine. Extracted verbatim from
    /// the render block so the audio thread and the DEBUG test-pump share ONE code
    /// path — the render path is byte-identical to before (same call site, same
    /// per-command effects). Audio-thread safe: lock-free dequeue + arithmetic voice
    /// state, no alloc. Owned by the one audio thread in production.
    nonisolated(unsafe) private func drainNoteCommands() {
        while let cmd = noteCommands.dequeue() {
            switch cmd.kind {
            case .on:
                hasEverSounded = true
                renderIdle = false; idleQuietFrames = 0   // wake IN this block
                poly.noteOn(note: Int(cmd.pitch), velocity: cmd.velocity, cutoffScale: cmd.cutoff)
            case .off:
                poly.noteOff(note: Int(cmd.pitch))
            case .allOff:
                poly.allNotesOff()
            case .slide:
                hasEverSounded = true   // a slide's noteOn-fallback must not be muted
                renderIdle = false; idleQuietFrames = 0
                poly.slideNote(from: Int(cmd.pitch2), to: Int(cmd.pitch), velocity: cmd.velocity,
                               cutoffScale: cmd.cutoff)
            case .expression:
                // Pure parameter update: must NOT wake `renderIdle` or set `hasEverSounded`.
                // A moving finger over a decayed note would otherwise resurrect the engine
                // to render silence — and an expression event can arrive after the note is
                // gone, where the engine's pitch lookup simply matches nothing.
                poly.setNoteCutoffScale(note: Int(cmd.pitch), scale: cmd.cutoff)
            }
        }
    }

    #if DEBUG
    /// TEST ONLY. Simulate one audio-thread pump of the note-command queue so a
    /// unit test can observe control-plane allocation (`activeVoiceCount`) after
    /// `noteOn`/`noteOff` — which, since the first-note-crash fix, only ENQUEUE and
    /// are applied on the audio thread inside `renderOnAudioThread`. This drains the
    /// SAME queue via the SAME `drainNoteCommands()` the render uses; it does not run
    /// the DSP render. Never call from production code.
    internal func pumpNoteCommandsForTesting() {
        drainNoteCommands()
    }
    #endif

    nonisolated(unsafe) private func copy(
        _ src: inout [Float],
        to buffer: AudioBuffer,
        count: Int,
        total: Int
    ) {
        guard let raw = buffer.mData else { return }
        let dst = raw.assumingMemoryBound(to: Float.self)
        src.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            // Sweep non-finite samples here rather than trusting every DSP stage: the
            // FX chain upstream is a growing list of them, and everything downstream
            // (masterMixer → AutoMixChain EQ → mainMixer) is recursive and would be
            // poisoned by one NaN. See `AudioOutputGuard` — this is the source-node
            // boundary, NOT the last word before the hardware.
            AudioOutputGuard.copySilencingNonFinite(from: base, to: dst, count: count)
        }
        if total > count {
            (dst + count).update(repeating: 0, count: total - count)
        }
    }

    nonisolated private static func silence(
        audioBufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: Int
    ) {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for buffer in abl {
            guard let raw = buffer.mData else { continue }
            raw.assumingMemoryBound(to: Float.self).update(repeating: 0, count: frameCount)
        }
    }
}

/// Weak holder so the audio-thread render closure can reference the
/// MainActor-bound voice without retaining it.
private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

/// A note event passed from the control thread to the audio thread via a
/// lock-free queue. Trivial value type (no ARC) → safe to hand across threads.
private struct NoteCommand: Sendable {
    enum Kind: UInt8 { case on, off, allOff, slide, expression }
    let kind: Kind
    let pitch: Int32
    let velocity: Float
    /// Auxiliary pitch — only used by `.slide` (the note being slid FROM).
    var pitch2: Int32 = 0
    /// PER-NOTE filter expression — where this note's finger is (1 = neutral). Carried on
    /// `.on`/`.slide` so the timbre is set in the same audio-thread step that starts the
    /// note (no one-block window at the wrong colour), and on `.expression` for a finger
    /// that keeps moving while the note sustains. Still a trivial value type: one more
    /// Float, no ARC, safe across the lock-free queue.
    var cutoff: Float = 1
}

/// One bio-modulation frame handed from the control thread (the 10 Hz poll) to the
/// audio thread via a lock-free queue. Trivial value type (all `Float`/enum, no ARC)
/// → safe to hand across threads. Applying it on the audio thread keeps the poly
/// engine's spectral-envelope array rewrite off the main thread, so it never races
/// render()'s read of that array. `profile` is resolved on the main actor at enqueue
/// time (it reads the control-plane `bioMappingHarmonic` flag).
private struct PolyBioParams: Sendable {
    let coherence: Float
    let hrv: Float
    let heartRate: Float
    let breathPhase: Float
    let breathDepth: Float
    let lfHf: Float
    let coherenceTrend: Float
    let profile: BioMapProfile
}
