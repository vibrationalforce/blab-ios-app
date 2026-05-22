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
//  Default state is silent. User must call playNote() (UI: play
//  toggle on BioStripView) to open the envelope. releaseNote() closes
//  it; ambient release tail fades over ~2s.
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
    public let synth: EchoelDDSP

    @ObservationIgnored
    public lazy var sourceNode: AVAudioSourceNode = makeSourceNode()

    /// Whether the note envelope is currently open (audible) or
    /// released (silent / fading).
    public private(set) var isPlayingNote = false

    // MARK: - Bus subscription state

    public private(set) var isSubscribed = false

    public private(set) var lastApplied: BioSampleFrame?

    public private(set) var framesApplied: UInt64 = 0

    @ObservationIgnored
    private weak var bus: EngineBus?

    @ObservationIgnored
    private var task: Task<Void, Never>?

    @ObservationIgnored
    private var lastTimestamp: TimeInterval = -1

    // MARK: - Audio render scratch (audio-thread only after attach)

    @ObservationIgnored
    private static let maxBlockFrames = 4096

    @ObservationIgnored
    private static let sampleRate: Double = 48_000

    /// Pre-allocated mono buffer, sized to the max plausible block.
    /// Audio thread writes into this via `synth.render(...)` and then
    /// memcpys into the AudioBufferList. Never re-allocated after init.
    @ObservationIgnored
    private var scratchBuffer: [Float]

    public init() {
        self.synth = EchoelDDSP(sampleRate: Self.sampleRate)
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

    public func playNote() {
        guard !isPlayingNote else { return }
        synth.noteOn()
        isPlayingNote = true
    }

    public func releaseNote() {
        guard isPlayingNote else { return }
        synth.noteOff()
        isPlayingNote = false
    }

    // MARK: - Bus subscription

    /// Begin polling bus.latestBio at 10 Hz and forwarding fresh
    /// frames into synth.applyBioReactive(...). Idempotent.
    public func start(subscribing to bus: EngineBus) {
        guard !isSubscribed else { return }
        self.bus = bus
        isSubscribed = true
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let bus = self.bus else { break }
                self.applyLatestIfFresh(from: bus)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
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
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)
            ?? AVAudioFormat()
        // Capture self weakly to keep the render closure from retaining the
        // MainActor-bound voice. nonisolated(unsafe) is acceptable because
        // the render closure runs on the audio thread and only touches
        // the synth (Float-atomic params) and the scratch buffer
        // (audio-thread-only after first render).
        nonisolated(unsafe) let weakSelf = WeakBox(self)
        return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            guard let voice = weakSelf.value else {
                BioReactiveSynthVoice.silence(audioBufferList: audioBufferList, frameCount: Int(frameCount))
                return noErr
            }
            voice.renderOnAudioThread(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }
    }

    /// Audio thread. Reads (potentially racy) synth params and writes
    /// `frameCount` mono samples into the first channel of `abl`.
    /// nonisolated(unsafe) — see threading note in the file header.
    nonisolated(unsafe) private func renderOnAudioThread(
        frameCount: Int,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) {
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
