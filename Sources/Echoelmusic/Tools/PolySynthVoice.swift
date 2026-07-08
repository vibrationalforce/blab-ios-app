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
    @ObservationIgnored
    nonisolated(unsafe) private let patchCommands = SPSCQueue<SynthPatch>(capacity: 8)

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

    /// Last computed target — telemetry only. `@ObservationIgnored`: it changes ~10 Hz, so
    /// reading it in a view body would be the "menus freeze while playing" class.
    @ObservationIgnored public private(set) var entrainmentTarget: BioEntrainmentTarget = .inactive

    // MARK: - Bus subscription state

    public private(set) var isSubscribed = false

    /// Diagnostic frame counter, bumped ~10 Hz by the bio-modulation poll. MUST stay
    /// `@ObservationIgnored`: as a tracked `@Observable` it would invalidate any view that
    /// reads it 10×/s — the exact "menus freeze while playing" class. Nothing reads it for
    /// UI; keep it non-observed.
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
    public func noteOn(pitch: Int, velocity: Float = 0.8) {
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
            NoteCommand(kind: .on, pitch: Int32(pitch), velocity: min(max(velocity, 0), 1))
        )
    }

    /// Release a sounding note (no-op if that pitch isn't held).
    public func noteOff(pitch: Int) {
        _ = noteCommands.tryEnqueue(NoteCommand(kind: .off, pitch: Int32(pitch), velocity: 0))
    }

    /// Release every held note (release tails fade naturally).
    public func allNotesOff() {
        _ = noteCommands.tryEnqueue(NoteCommand(kind: .allOff, pitch: 0, velocity: 0))
    }

    /// Standard A440 equal temperament: midi 69 = 440 Hz.
    public nonisolated static func frequency(forMIDINote note: Int) -> Float {
        440 * powf(2, (Float(note) - 69) / 12)
    }

    /// Set the concert pitch (Kammerton) the voices tune to. A4 in Hz, clamped to
    /// a musical range so a stray value can't detune into inaudibility. Takes effect
    /// on the next note (and is safe to call while a loop plays).
    public func setTuning(a4Hz: Double) {
        poly.a4Hz = Float(min(max(a4Hz, 380), 500))
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
        _ = patchCommands.tryEnqueue(patch)
    }

    /// Set unison directly (live, outside a patch) — count 1 = off.
    public func setUnison(count: Int, detuneCents: Float) {
        poly.setUnison(count: count, detuneCents: detuneCents)
    }

    /// Global filter-cutoff multiplier (1 = no change), driven by parameter
    /// automation. Atomic write; takes effect on the next render block.
    public func setCutoffScale(_ scale: Float) {
        poly.setCutoffScale(scale)
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
        poly.applyBioReactive(
            coherence: liveCoherence(frame.coherence),
            hrvVariability: clampUnit(frame.hrvNormalized),
            heartRate: hrNormalized,
            breathPhase: clampUnit(frame.breathPhase),
            breathDepth: 0.5,
            lfHfRatio: 0.5,
            coherenceTrend: 0,
            profile: bioMappingHarmonic ? .harmonicSeries : .natural
        )
        applyEntrainment(coherence: frame.coherence,
                         heartRateBPM: frame.heartRateBPM,
                         motionEnergy: frame.motionEnergy)
    }

    /// Drive the isochronic entrainment from the body. Quality gates the depth: a frame
    /// only carries `heartRateBPM > 0` on a confident pulse lock (the camera publisher
    /// gates on its lock threshold), and motion degrades it — so a noisy/absent signal
    /// can never push a strong stimulus. Writes band/depth to every voice's existing
    /// `EchoelEntrainment` (same main-poll→audio-read path as `applyBioReactive`).
    private func applyEntrainment(coherence: Float, heartRateBPM: Float, motionEnergy: Float) {
        guard entrainmentEnabled else { return }
        let quality: Float = heartRateBPM > 0 ? clampUnit(1 - motionEnergy) : 0
        let target = BioEntrainmentDirector(manualBand: entrainmentManualBand)
            .target(coherence: liveCoherence(coherence), quality: quality)
        entrainmentTarget = target
        poly.forEachVoice { voice in
            voice.entrainment.band = target.band
            voice.entrainment.depth = target.depth
        }
    }

    /// Silence the stimulus on every voice (called when entrainment is disarmed).
    private func clearEntrainment() {
        poly.forEachVoice { $0.entrainment.depth = 0 }
        entrainmentTarget = .inactive
    }

    private func clampUnit(_ x: Float) -> Float { min(max(x, 0), 1) }
    /// Coherence of exactly 0 means "no coherence data" (camera until enough beats;
    /// HealthKit never measures it) — NOT "maximally incoherent". The synth maps
    /// coherence→filter cutoff (200 Hz at 0 → muffled), so a literal 0 muffled every
    /// resting/unmeasured take. Treat 0 as neutral so the baseline tone is open.
    private func liveCoherence(_ c: Float) -> Float { c > 0 ? clampUnit(c) : 0.5 }

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
        // Drain note commands HERE (audio thread) so all voice mutation is on this
        // one thread — never racing the render. Must run before the silence guard
        // so the first note both flips hasEverSounded and is applied atomically wrt
        // rendering.
        while let cmd = noteCommands.dequeue() {
            switch cmd.kind {
            case .on:
                hasEverSounded = true
                poly.noteOn(note: Int(cmd.pitch), velocity: cmd.velocity)
            case .off:
                poly.noteOff(note: Int(cmd.pitch))
            case .allOff:
                poly.allNotesOff()
            }
        }
        guard hasEverSounded else {
            Self.silence(audioBufferList: audioBufferList, frameCount: frameCount)
            return
        }
        let count = min(frameCount, Self.maxBlockFrames)
        poly.renderStereo(left: &scratchL, right: &scratchR, frameCount: count)
        // Genre/effect colour (long dub delay, vapor chorus, …). Audio-thread
        // safe: pre-allocated stages, no work for bypassed effects. The master gate
        // lets the Effects panel bypass the entire chain.
        if fxEnabled {
            fxChain.processBuffer(left: &scratchL, right: &scratchR, frameCount: count)
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

        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard abl.count > 0 else { return }
        // Channel 0 (left). For a deinterleaved stereo format there are 2 buffers;
        // a mono downstream graph may present 1 — handle both.
        copy(&scratchL, to: abl[0], count: count, total: frameCount)
        if abl.count > 1 {
            copy(&scratchR, to: abl[1], count: count, total: frameCount)
        }
    }

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
            dst.update(from: base, count: count)
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
    enum Kind: UInt8 { case on, off, allOff }
    let kind: Kind
    let pitch: Int32
    let velocity: Float
}
