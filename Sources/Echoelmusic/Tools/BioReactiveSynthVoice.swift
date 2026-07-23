//
//  BioReactiveSynthVoice.swift
//  Echoelmusic
//
//  First EngineBus subscriber AND first bio-driven audio voice in the
//  master audio graph. Hosts one EchoelDDSP, polls bus.latestBio at
//  10 Hz on MainActor and forwards each fresh frame into the synth's
//  applyBioReactive(...) surface. The same EchoelDDSP also feeds an
//  AVAudioSourceNode that mixes into AudioEngine.masterMixer, so
//  every bio change is now audible: heart rate drives vibrato, HRV
//  drives brightness, coherence drives harmonicity, etc.
//
//  Default state is SILENT and DISARMED. Nothing sounds on launch — not
//  even when a bio source (incl. the auto-demo) is streaming. The user
//  must arm the voice (UI: play toggle on BioStripView) before the breath
//  drives the envelope. An external MIDI/MPE note always plays (explicit
//  performer action) regardless of arm state. releaseNote() closes the
//  envelope; ambient release tail fades over ~2s.
//
//  Threading: the 10 Hz MainActor poll no longer mutates the synth directly.
//  It enqueues bio parameters onto a lock-free SPSC queue; the audio-thread
//  render block drains the queue and calls synth.applyBioReactive(...) itself.
//  This keeps ALL synth state mutation (including the spectral-envelope array
//  rewrite inside applyBioReactive) on the one audio thread, so it never races
//  the render's read of those arrays — the same SPSC discipline PolySynthVoice
//  uses for notes/patches. Scalar note/frequency control (playNote/releaseNote/
//  pitch bend) remains Float-width-atomic and is tolerated as before.
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
public final class BioReactiveSynthVoice {

    // MARK: - Synth + audio output

    /// Underlying synthesizer.
    @ObservationIgnored
    nonisolated public let synth: EchoelDDSP

    /// Insert FX chain (delay / modulation / dynamics) applied to this voice's
    /// output on the audio thread. Inert until `setFXEnabled(true)`.
    @ObservationIgnored
    nonisolated public let fxChain: EchoelFXChain

    @ObservationIgnored
    public lazy var sourceNode: AVAudioSourceNode = makeSourceNode()

    /// Whether the note envelope is currently open (audible) or
    /// released (silent / fading).
    public private(set) var isPlayingNote = false

    /// Master arm switch for bio-driven sound. DEFAULT FALSE: until the
    /// user arms the voice (play toggle), bio/breath events never open the
    /// envelope, so the instrument is silent on launch even while the demo
    /// bio source streams. An external MIDI/MPE note bypasses this (explicit
    /// performer action always sounds).
    public private(set) var isArmed = false

    /// When true, breath inhale/exhale onsets from the bus drive the
    /// envelope (the synth breathes with you) whenever the voice is armed
    /// and no external controller note is held. Toggle off for pure manual play.
    public var breathPlayEnabled = true

    // MARK: - Bus subscription state

    public private(set) var isSubscribed = false

    @ObservationIgnored
    private var heldByController = false

    @ObservationIgnored
    private var lastBioEventTimestamp: TimeInterval = -1

    public private(set) var lastApplied: BioSampleFrame?

    /// Diagnostic frame counter, bumped ~10 Hz. Kept `@ObservationIgnored` so it can never
    /// invalidate an observing view 10×/s (the "menus freeze while playing" class).
    @ObservationIgnored public private(set) var framesApplied: UInt64 = 0

    @ObservationIgnored
    private weak var bus: EngineBus?

    @ObservationIgnored
    private let loop = PollingLoop()

    /// BodyVibe B1: invoked once per 10 Hz poll tick, AFTER this voice's own
    /// bio/controller work. Lets the app fan the SAME tick into the rack's lane
    /// bio units (LaneVoiceRack.feedBio) without a second timer — the "no new
    /// timer, no per-frame MainActor hop" law. nil (default) ⇒ zero cost.
    @ObservationIgnored
    public var onPollTick: (@MainActor () -> Void)?

    /// Lock-free bio-modulation queue: produced on the MainActor 10 Hz poll,
    /// consumed (applied to `synth`) on the audio thread in the render block.
    /// Bio modulation rewrites the synth's spectral-envelope arrays; doing that
    /// on the audio thread (not the MainActor poll) keeps it from racing the
    /// render's read of those same arrays. Same discipline PolySynthVoice uses
    /// for notes/patches. SPSC: one producer (main), one consumer (audio).
    @ObservationIgnored
    nonisolated(unsafe) private let bioCommands = SPSCQueue<BioParams>(capacity: 8)

    @ObservationIgnored
    private var lastTimestamp: TimeInterval = -1

    // MARK: - Audio render scratch (audio-thread only after attach)

    @ObservationIgnored
    nonisolated private static let maxBlockFrames = 4096

    @ObservationIgnored
    private static let sampleRate: Double = 48_000

    /// Pre-allocated mono buffer, sized to the max plausible block.
    /// Audio thread writes into this via `synth.render(...)` and then
    /// memcpys into the AudioBufferList. Never re-allocated after init.
    @ObservationIgnored
    nonisolated(unsafe) private var scratchBuffer: [Float]

    /// Hard launch-silence guarantee: the render block emits PURE ZERO until the
    /// user triggers the voice for the first time (arm / MIDI note). This makes
    /// "nothing sounds on app open" true at the audio-thread level, independent
    /// of envelope state — set once on the first `playNote`, never reset, so it
    /// never cuts a release tail. Bool is atomic-width; written on the main
    /// thread, read on the audio thread.
    @ObservationIgnored
    nonisolated(unsafe) private var hasEverSounded = false

    /// Master FX gate. DEFAULT FALSE → the FX chain is fully inert (true bypass,
    /// zero cost in the render block) until the user enables it, so existing
    /// builds sound bit-identical. Atomic-width Bool: written on the main thread,
    /// read on the audio thread (same contract as `hasEverSounded`).
    @ObservationIgnored
    nonisolated(unsafe) private var fxEnabled = false

    /// Observable mirror of `fxEnabled` for SwiftUI binding.
    public private(set) var isFXEnabled = false

    public init() {
        self.synth = EchoelDDSP(sampleRate: Float(Self.sampleRate))
        self.fxChain = EchoelFXChain(sampleRate: Float(Self.sampleRate))
        self.scratchBuffer = Array(repeating: 0, count: Self.maxBlockFrames)
    }

    /// Enable or bypass the insert FX chain. Updates both the audio-thread gate
    /// and the observable mirror. Individual stages are toggled directly on
    /// `fxChain` (e.g. `fxChain.delayEnabled = true`).
    public func setFXEnabled(_ on: Bool) {
        fxEnabled = on
        isFXEnabled = on
    }

    // MARK: - Audio engine attachment

    /// Attach the voice's source node to the master audio graph.
    /// MUST be called BEFORE `audioEngine.start()` to avoid the
    /// build-1363 hot-attach launch crash documented in CLAUDE.md.
    public func attach(to audioEngine: AudioEngine) {
        audioEngine.attachSourceNode(sourceNode)
    }

    // MARK: - Note gating (UI control plane)

    /// Open the envelope at the synth's current frequency (or, if
    /// supplied, retune to `frequency` first). Re-entrant: a second
    /// `playNote` while already playing retriggers — monophonic,
    /// last-note-wins.
    public func playNote(frequency: Float? = nil) {
        hasEverSounded = true
        synth.noteOn(frequency: frequency)
        isPlayingNote = true
    }

    public func releaseNote() {
        guard isPlayingNote else { return }
        synth.noteOff()
        isPlayingNote = false
    }

    /// Arm the bio-reactive voice and give immediate audible feedback. Once
    /// armed, breath onsets (if `breathPlayEnabled`) drive the envelope.
    public func arm() {
        isArmed = true
        playNote()
    }

    /// Disarm and silence the voice (closes the envelope; bio events ignored).
    public func disarm() {
        isArmed = false
        releaseNote()
    }

    /// Concert pitch (Kammerton), A4 in Hz. The mono `EchoelDDSP` this voice drives has
    /// no tuning field (only `EchoelPolyDDSP` does), and `playNote(frequency:)` sets the
    /// oscillator to an explicit Hz, so the voice resolves the note→Hz itself from this
    /// value. Control-path only (written in `setTuning`, read in `soundingFrequency`, both
    /// on the MainActor) — never touched by the render block, so no atomic needed.
    @ObservationIgnored private var tuningA4Hz: Float = 440

    /// This voice's SOUNDING frequency for a MIDI note, honoring the concert pitch
    /// (Kammerton) set via `setTuning`, so external-MIDI and lane-gate notes stay in tune
    /// with the rest of the instrument instead of pinning to 440. (Was a hardcoded-440
    /// static that made the bio voices ignore the user's Kammerton.)
    public func soundingFrequency(forMIDINote note: UInt8) -> Float {
        tuningA4Hz * powf(2, (Float(note) - 69) / 12)
    }

    /// Set the concert pitch (Kammerton) this voice tunes to — A4 in Hz, clamped to a
    /// musical range so a stray value can't detune into inaudibility. Read at the next
    /// note (same discipline as `PolySynthVoice.setTuning`); safe while a loop plays.
    public func setTuning(a4Hz: Double) {
        // Sanitize the tuning boundary: a NaN slips through min/max (NaN comparisons are
        // false) and would poison the frequency → a stuck, silent oscillator (same
        // failure class as the pitch-bend isFinite guard).
        guard a4Hz.isFinite else { return }
        tuningA4Hz = Float(Swift.min(Swift.max(a4Hz, 380), 500))
    }

    // MARK: - Lane mixer stage (BodyVibe B1 — rack-unit use)

    /// Lane gain: this voice's whole-output level at the mixer, 0…2 (1 = unity —
    /// the default, so the global voice is bit-identical). Control-plane only,
    /// exactly the PolySynthVoice pattern: `sourceNode` conforms to
    /// `AVAudioMixing`, the ENGINE scales downstream of the render block.
    /// Non-finite fails SILENT (0) per app convention.
    public func setGain(_ gain: Float) {
        sourceNode.volume = Swift.max(0, Swift.min(2, gain.isFinite ? gain : 0))
    }

    /// Lane pan, −1…1 (0 = center — the default). Same AVAudioMixing engine
    /// path as `setGain`; non-finite is ignored as center.
    public func setPan(_ pan: Float) {
        sourceNode.pan = Swift.max(-1, Swift.min(1, pan.isFinite ? pan : 0))
    }

    // MARK: - Bus subscription

    /// Begin polling bus.latestBio at 10 Hz and forwarding fresh
    /// frames into synth.applyBioReactive(...). Idempotent.
    public func start(subscribing bus: EngineBus) {
        guard !isSubscribed else { return }
        self.bus = bus
        isSubscribed = true
        loop.start(interval: .milliseconds(100)) { [weak self] in
            guard let self, let bus = self.bus else { return }
            self.applyLatestIfFresh(from: bus)
            self.drainControllerEvents(from: bus)
            self.consumeBioEventsIfFresh(from: bus)
            self.onPollTick?()
        }
    }

    /// BodyVibe B1 — the LANE-UNIT bio feed: forward the bus's latest bio
    /// snapshot into this voice's timbre WITHOUT subscribing. A rack bio unit
    /// must never call `start(subscribing:)`: that would (a) spin a second
    /// PollingLoop and (b) drain the SHARED `bus.controllerEvents` SPSC queue —
    /// single-consumer contract; a second consumer steals MIDI events from the
    /// global armed voice — and (c) let breath onsets open the envelope outside
    /// the sequencer gate. This method is timbre-only: the envelope stays owned
    /// by the caller (playNote/releaseNote from the sequencer note gate).
    /// Called from the global voice's existing 10 Hz tick via `onPollTick`.
    public func applyBioFrame(from bus: EngineBus) {
        applyLatestIfFresh(from: bus)
    }

    /// Pulls every queued ControllerEvent since the last tick and
    /// applies the music-meaningful ones to the synth envelope:
    ///   .noteOn      → playNote(frequency: midiNote→Hz)
    ///   .noteOff     → releaseNote()
    ///   .pitchBend   → instantaneous frequency offset (±2 semitones)
    /// .slide, .airCC, .channelPressure are reserved for later cycles
    /// when modulation matrix consumes them.
    private func drainControllerEvents(from bus: EngineBus) {
        while let event = bus.controllerEvents.dequeue() {
            apply(controller: event)
        }
    }

    private func apply(controller event: ControllerEvent) {
        switch event.kind {
        case .noteOn:
            heldByController = true
            playNote(frequency: soundingFrequency(forMIDINote: event.note))
        case .noteOff:
            heldByController = false
            releaseNote()
        case .pitchBend:
            let semis = event.value * 2.0
            let base = soundingFrequency(forMIDINote: event.note > 0 ? event.note : 69)
            let bent = base * powf(2, semis / 12)
            // A NaN/inf controller value would set synth.frequency to NaN, which the
            // audio thread reads in render() → a permanently stuck/silent oscillator
            // (same failure class as the bio-param NaN guarded by clampUnit). Ignore a
            // bend that isn't a finite pitch rather than poison the voice.
            if bent.isFinite { synth.frequency = bent }
        case .slide, .airCC, .channelPressure:
            break
        }
    }

    /// When no external controller note is held, the breath drives the
    /// envelope: inhale onset opens it, exhale onset releases it — the
    /// synth breathes with you. A held MIDI/MPE note takes priority and
    /// suppresses breath triggering so the performer always leads.
    private func consumeBioEventsIfFresh(from bus: EngineBus) {
        guard let event = bus.latestBioEvent else { return }
        guard event.timestamp != lastBioEventTimestamp else { return }
        lastBioEventTimestamp = event.timestamp
        // Silent until the user arms the voice — this is what stops a tone
        // from appearing on launch while the demo bio source streams.
        guard isArmed, breathPlayEnabled, !heldByController else { return }

        switch event.kind {
        case .breathInhaleOnset:
            playNote()
        case .breathExhaleOnset:
            releaseNote()
        case .heartbeat, .motionPeak, .coherenceShift, .eegBurst:
            break
        }
    }

    public func stop() {
        loop.stop()
        isSubscribed = false
    }

    // MARK: - Bio → Synth mapping

    private func applyLatestIfFresh(from bus: EngineBus) {
        guard let frame = bus.latestBio else { return }
        guard frame.timestamp != lastTimestamp else { return }
        lastTimestamp = frame.timestamp
        lastApplied = frame
        framesApplied &+= 1

        let hrNormalized = clampUnit((frame.heartRateBPM - 40) / 160)
        // Hand the parameters to the AUDIO thread instead of mutating the synth
        // here. Previously this ran `synth.applyBioReactive(...)` on the MainActor
        // poll, which rewrote the synth's spectral-envelope Swift arrays while the
        // audio thread read them in render() — a cross-thread array data race (the
        // same class fixed for notes/patches in PolySynthVoice). The render block
        // drains this queue and applies it on the one audio thread.
        _ = bioCommands.tryEnqueue(BioParams(
            // coherence 0 = "no data" (camera until enough beats; HealthKit never),
            // not "maximally dark filter" — treat as neutral so resting tone stays open.
            coherence: frame.coherence > 0 ? clampUnit(frame.coherence) : 0.5,
            hrv: clampUnit(frame.hrvNormalized),
            heartRate: hrNormalized,
            breathPhase: clampUnit(frame.breathPhase),
            breathDepth: 0.5,
            lfHf: 0.5,
            coherenceTrend: 0
        ))
    }

    /// Clamp a bio value into 0…1, sanitizing NaN/inf to 0. A NaN here (e.g. a bad
    /// heart-rate frame) would otherwise pass the plain `min(max())` clamp unchanged
    /// and poison the audio thread's filter/envelope state → a permanently silent
    /// voice. Fail quiet (0) instead. Runs on the MainActor poll, never in render.
    private func clampUnit(_ x: Float) -> Float {
        guard x.isFinite else { return 0 }
        return min(max(x, 0), 1)
    }

    // MARK: - Source node (audio thread)

    private func makeSourceNode() -> AVAudioSourceNode {
        // Capture self weakly to keep the render closure from retaining the
        // MainActor-bound voice. nonisolated(unsafe) is acceptable because
        // the render closure runs on the audio thread and only touches
        // the synth (Float-atomic params) and the scratch buffer
        // (audio-thread-only after first render).
        nonisolated(unsafe) let weakSelf = WeakBox(self)
        let renderBlock: AVAudioSourceNodeRenderBlock = { _, _, frameCount, audioBufferList in
            guard let voice = weakSelf.value else {
                BioReactiveSynthVoice.silence(audioBufferList: audioBufferList, frameCount: Int(frameCount))
                return noErr
            }
            voice.renderOnAudioThread(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }
        // A constant sample rate always yields a valid format; if the OS ever
        // returns nil, use the format-inferring initializer rather than the no-arg
        // AVAudioFormat() (an invalid 0 Hz/0 ch format that crashes the node init).
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else {
            return AVAudioSourceNode(renderBlock: renderBlock)
        }
        return AVAudioSourceNode(format: format, renderBlock: renderBlock)
    }

    /// Audio thread. Reads (potentially racy) synth params and writes
    /// `frameCount` mono samples into the first channel of `abl`.
    /// nonisolated(unsafe) — see threading note in the file header.
    nonisolated(unsafe) private func renderOnAudioThread(
        frameCount: Int,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) {
        // Apply any pending bio modulation HERE (audio thread) so the synth's
        // spectral-envelope array rewrite happens on this one thread and never
        // races the render's read below. Drain to the latest queued frame; the
        // queue is empty in most blocks (params update at ~10 Hz), so this is a
        // cheap check. Runs even while silent so the timbre is current when armed.
        var latestBio: BioParams?
        while let p = bioCommands.dequeue() { latestBio = p }
        if let p = latestBio {
            synth.applyBioReactive(
                coherence: p.coherence,
                hrvVariability: p.hrv,
                heartRate: p.heartRate,
                breathPhase: p.breathPhase,
                breathDepth: p.breathDepth,
                lfHfRatio: p.lfHf,
                coherenceTrend: p.coherenceTrend
            )
        }
        // Launch-silence guarantee: never emit anything until the first
        // user-initiated trigger. Pure zero out of this node on app open.
        guard hasEverSounded else {
            Self.silence(audioBufferList: audioBufferList, frameCount: frameCount)
            return
        }
        let count = min(frameCount, Self.maxBlockFrames)
        synth.render(buffer: &scratchBuffer, frameCount: count, stereo: false)
        // Insert FX (mono, in place). Gated so it is a true no-op until enabled.
        if fxEnabled {
            fxChain.processBufferMono(&scratchBuffer, frameCount: count)
        }
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard abl.count > 0, let raw = abl[0].mData else { return }
        let dst = raw.assumingMemoryBound(to: Float.self)
        scratchBuffer.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            dst.update(from: base, count: count)
        }
        if frameCount > count {
            // Defensive: zero-fill anything past our scratch window.
            (dst + count).update(repeating: 0, count: frameCount - count)
        }
    }

    nonisolated private static func silence(
        audioBufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: Int
    ) {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard abl.count > 0, let raw = abl[0].mData else { return }
        let dst = raw.assumingMemoryBound(to: Float.self)
        dst.update(repeating: 0, count: frameCount)
    }
}

/// Trivial weak holder so the audio-thread render closure can capture
/// a reference to a MainActor-bound class without retaining it.
private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

/// Bio-modulation parameters handed from the MainActor poll to the audio thread
/// via a lock-free queue. Trivial value type (no ARC, no heap) → safe to cross
/// threads. Applying it on the audio thread keeps the synth's spectral-array
/// rewrite off the main thread, so it never races render()'s read of that array.
private struct BioParams: Sendable {
    let coherence: Float
    let hrv: Float
    let heartRate: Float
    let breathPhase: Float
    let breathDepth: Float
    let lfHf: Float
    let coherenceTrend: Float
}
