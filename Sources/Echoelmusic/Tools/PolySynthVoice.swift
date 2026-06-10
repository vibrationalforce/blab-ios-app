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

    @ObservationIgnored
    public lazy var sourceNode: AVAudioSourceNode = makeSourceNode()

    /// Number of voices currently sounding (for UI display).
    public var activeVoiceCount: Int { poly.activeVoiceCount }

    // MARK: - Bus subscription state

    public private(set) var isSubscribed = false

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

    public init(maxVoices: Int = 6) {
        self.poly = EchoelPolyDDSP(maxVoices: maxVoices, sampleRate: Float(Self.sampleRate))
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
        hasEverSounded = true
        poly.noteOn(note: pitch, velocity: min(max(velocity, 0), 1))
    }

    /// Release a sounding note (no-op if that pitch isn't held).
    public func noteOff(pitch: Int) {
        poly.noteOff(note: pitch)
    }

    /// Release every held note (release tails fade naturally).
    public func allNotesOff() {
        poly.allNotesOff()
    }

    /// Standard A440 equal temperament: midi 69 = 440 Hz.
    public nonisolated static func frequency(forMIDINote note: Int) -> Float {
        440 * powf(2, (Float(note) - 69) / 12)
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
        guard let frame = bus.latestBio else { return }
        guard frame.timestamp != lastTimestamp else { return }
        lastTimestamp = frame.timestamp
        framesApplied &+= 1

        let hrNormalized = clampUnit((frame.heartRateBPM - 40) / 160)
        poly.applyBioReactive(
            coherence: clampUnit(frame.coherence),
            hrvVariability: clampUnit(frame.hrvNormalized),
            heartRate: hrNormalized,
            breathPhase: clampUnit(frame.breathPhase),
            breathDepth: 0.5,
            lfHfRatio: 0.5,
            coherenceTrend: 0
        )
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
        guard hasEverSounded else {
            Self.silence(audioBufferList: audioBufferList, frameCount: frameCount)
            return
        }
        let count = min(frameCount, Self.maxBlockFrames)
        poly.renderStereo(left: &scratchL, right: &scratchR, frameCount: count)

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
