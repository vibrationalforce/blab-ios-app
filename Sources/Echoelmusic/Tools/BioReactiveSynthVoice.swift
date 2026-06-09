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
//  Threading: applyBioReactive() runs on MainActor (10 Hz). The
//  AVAudioSourceNode render closure runs on the audio thread
//  (sub-millisecond). Both touch EchoelDDSP simultaneously — same
//  pattern SoundscapeEngine uses. Properties are Float-width
//  (atomic on Apple platforms), so worst case is one render block
//  reads slightly-stale params. Acceptable for v1; a future cycle
//  can introduce snapshot double-buffering if needed.
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

    public private(set) var framesApplied: UInt64 = 0

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

    public init() {
        self.synth = EchoelDDSP(sampleRate: Float(Self.sampleRate))
        self.scratchBuffer = Array(repeating: 0, count: Self.maxBlockFrames)
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

    /// Standard A440 equal temperament: midi 69 = 440 Hz.
    public nonisolated static func frequency(forMIDINote note: UInt8) -> Float {
        440 * powf(2, (Float(note) - 69) / 12)
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
        }
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
            playNote(frequency: Self.frequency(forMIDINote: event.note))
        case .noteOff:
            heldByController = false
            releaseNote()
        case .pitchBend:
            let semis = event.value * 2.0
            let base = Self.frequency(forMIDINote: event.note > 0 ? event.note : 69)
            synth.frequency = base * powf(2, semis / 12)
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
        synth.applyBioReactive(
            coherence: clampUnit(frame.coherence),
            hrvVariability: clampUnit(frame.hrvNormalized),
            heartRate: hrNormalized,
            breathPhase: clampUnit(frame.breathPhase),
            breathDepth: 0.5,
            lfHfRatio: 0.5,
            coherenceTrend: 0
        )
    }

    private func clampUnit(_ x: Float) -> Float {
        min(max(x, 0), 1)
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
        // Launch-silence guarantee: never emit anything until the first
        // user-initiated trigger. Pure zero out of this node on app open.
        guard hasEverSounded else {
            Self.silence(audioBufferList: audioBufferList, frameCount: frameCount)
            return
        }
        let count = min(frameCount, Self.maxBlockFrames)
        synth.render(buffer: &scratchBuffer, frameCount: count, stereo: false)
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
