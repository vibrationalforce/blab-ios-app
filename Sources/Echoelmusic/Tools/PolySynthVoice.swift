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
    /// (`PianoRollView.swift:23`). The Xcode gate caught it on 4655323; this two-parameter
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
    }

    /// The last patch handed to `apply(_:)` — the voice's patch MEMORY, so any
    /// door (studio panel, timeline lane) can open the editor on the sound
    /// that is actually playing instead of a blank Init. Control-plane only.
    public private(set) var appliedPatch: SynthPatch?

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
    /// DELIBERATELY EXCLUDED (bio-contested / unsafe — see scratchpads/PLAN_DAW_EPIC):
    /// harmonicity · noiseLevel · reverbMix/decay · raw filter base · vibrato ·
    /// brightness · raw amplitude — the bio loop overwrites them on every new bio frame
    /// (~1 Hz today, at most the 10 Hz poll rate; it was written "~10 Hz" here and that is
    /// the poll, not the apply) or the write races a shared spectral table / is gated off.
    /// The rate is not what disqualifies them — the OVERWRITE is — so automating them needs a
    /// separate automation×bio composition (write the `bioBase*` centers), not a
    /// direct write. `ddsp.amp.level` therefore targets the UNCONTESTED
    /// `patchOutputLevel` (which the render reads and neither bio nor noteOn touch),
    /// NOT `amplitude`. Filter automation stays on the existing scale-based lane
    /// (`setCutoffScale`), so the raw Hz `ddsp.filter.cutoff` is not bound here.
    /// The base engine keyPaths this voice can automate. SINGLE SOURCE OF TRUTH for
    /// both the global router binding (`bindAutomatable`) and the per-track dispatch
    /// (`applyAutomatable`). Bio-contested params (filter/brightness) are intentionally
    /// excluded — they need automation×bio composition, handled elsewhere.
    /// `nonisolated` so a picker / contract test may read it off the main actor.
    public nonisolated static let automatableBases: [String] = [
        "ddsp.warmth.drive", "ddsp.env.attack", "ddsp.env.decay",
        "ddsp.env.sustain", "ddsp.env.release", "ddsp.amp.level"
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

    private func applyLatestIfFresh(from bus: EngineBus) {
        guard bioModulationEnabled else { return }
        guard let frame = bus.latestBio else { return }
        guard frame.timestamp != lastTimestamp else { return }
        lastTimestamp = frame.timestamp
        framesApplied &+= 1

        let hrNormalized = clampUnit((frame.heartRateBPM - 40) / 160)
        // Hand the parameters to the AUDIO thread instead of mutating the poly engine
        // here. Applying `poly.applyBioReactive(...)` on this MainActor poll rewrote
        // each voice's spectral-envelope array while the audio thread read it in
        // render() — a cross-thread array race. The render block drains this queue and
        // applies it on the one audio thread (after the patch drain, so `bioBase*` is
        // already set). `profile` is resolved here on the main actor (reads the
        // control-plane `bioMappingHarmonic`) and carried in the value.
        _ = bioCommands.tryEnqueue(PolyBioParams(
            coherence: frame.coherenceForSound,
            hrv: frame.hrvForSound,   // 0 = unmeasured → neutral; see BioSampleFrame
            heartRate: hrNormalized,
            breathPhase: clampUnit(frame.breathPhase),
            breathDepth: 0.5,
            lfHf: 0.5,
            coherenceTrend: 0,
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
        while let patch = patchCommands.dequeue() {
            poly.forEachVoice { patch.apply(to: $0) }
        }
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
                    // unreachable again until a note command wakes the voice.
                    fxChain.noteRenderSleeping()
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
