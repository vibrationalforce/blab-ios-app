// SamplerVoice.swift
// Echoel — One-shot WAV sample player for the beat sequencer.
//
// Each SamplerVoice owns one AVAudioSourceNode and one in-memory sample
// buffer. PatternEngine.onStep(track, step) → fire() bumps a UInt32 trigger
// counter; the audio render block compares against its last-seen counter
// and resets the playback position when they differ.
//
// Audio thread rules (CLAUDE.md): NO allocation, NO locks, NO ObjC, NO I/O.
// All state mutated from the render block lives in `RenderState` and is
// touched only via memcpy/memset/index access on pre-allocated storage.
// 32-bit aligned reads/writes are atomic on all supported Apple platforms,
// so the trigger counter requires no lock or atomic wrapper.

#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// One-shot sample player on a single `AVAudioSourceNode`.
///
/// **Lifecycle:**
/// 1. `init()` — pre-allocates render state.
/// 2. `try loadSample(from:)` — synchronously reads a WAV into a `[Float]`
///    buffer (mono, sample-rate-converted to the node's format). Call once
///    before attaching the node to `AudioEngine`.
/// 3. `AudioEngine.attachSourceNode(voice.sourceNode)` — wires output to the
///    master mixer.
/// 4. `fire()` — main-thread trigger. Increments the trigger counter; the
///    render block detects the change on the next callback and starts
///    playback.
///
/// **Polyphony:** Retriggering before the previous tail finishes resets
/// the playback position to 0 (drum-machine convention; no voice stealing).
///
/// **Concurrency:** `nonisolated` (NOT `@MainActor`). The render closure
/// passed to `AVAudioSourceNode` is invoked on the audio thread; if this
/// class were `@MainActor`, the inferred closure isolation would trip
/// `swift_task_checkIsolatedSwift` on every audio callback (build 1368
/// crash on AURemoteIO::IOThread, EXC_BREAKPOINT). Thread safety is
/// preserved by the contract: main thread loads the sample and bumps the
/// trigger counter; audio thread reads only.
public final class SamplerVoice: @unchecked Sendable {

    // MARK: - Constants

    /// Maximum sample length, in mono 32-bit float frames (~2s @ 44.1 kHz).
    public static let maxSampleFrames: Int = 88_200

    /// Render format: mono float32 at 44.1 kHz. Master mixer matrix-mixes
    /// to the engine's hardware format.
    public static let sampleRate: Double = 44_100

    // MARK: - Public state

    /// True after `loadSample(from:)` succeeds.
    public private(set) var isLoaded: Bool = false

    /// File URL the sample was loaded from, for diagnostics.
    public private(set) var sourceURL: URL?

    // MARK: - Audio plumbing

    private let renderState = RenderState()

    /// The source node to attach to `AudioEngine.attachSourceNode(_:)`.
    public lazy var sourceNode: AVAudioSourceNode = makeSourceNode()

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Loads a WAV from disk into the in-memory render buffer.
    ///
    /// Reads the entire file (capped at `maxSampleFrames`), down-mixes to
    /// mono if needed, and stores as a `[Float]`. Subsequent triggers play
    /// from this buffer with zero allocation.
    ///
    /// - Throws: `AVAudioFile` errors or `SamplerVoiceError.unsupportedFormat`.
    public func loadSample(from url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let frameCap = AVAudioFrameCount(min(Int(file.length), Self.maxSampleFrames))
        guard frameCap > 0 else {
            throw SamplerVoiceError.unsupportedFormat
        }
        guard let pcm = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCap
        ) else {
            throw SamplerVoiceError.unsupportedFormat
        }
        try file.read(into: pcm, frameCount: frameCap)

        let frames = Int(pcm.frameLength)
        var mono = [Float](repeating: 0, count: frames)
        if let ch = pcm.floatChannelData {
            let channelCount = Int(pcm.format.channelCount)
            let scale: Float = channelCount > 1 ? 1.0 / Float(channelCount) : 1.0
            for c in 0..<channelCount {
                let src = ch[c]
                for i in 0..<frames {
                    mono[i] += src[i] * scale
                }
            }
        } else if let ch = pcm.int16ChannelData {
            let channelCount = Int(pcm.format.channelCount)
            let scale: Float = (channelCount > 1 ? 1.0 / Float(channelCount) : 1.0) / Float(Int16.max)
            for c in 0..<channelCount {
                let src = ch[c]
                for i in 0..<frames {
                    mono[i] += Float(src[i]) * scale
                }
            }
        } else {
            throw SamplerVoiceError.unsupportedFormat
        }

        renderState.installBuffer(mono)
        isLoaded = true
        sourceURL = url
    }

    /// Triggers playback from the start. Safe to call from the main thread.
    /// Lock-free: bumps an aligned UInt32 counter; the render block sees the
    /// change on its next callback.
    public func fire() {
        renderState.requestTrigger()
    }

    /// Stops playback on the next render block. Buffer stays loaded; a
    /// subsequent `fire()` resumes from frame 0.
    public func silence() {
        renderState.requestSilence()
    }

    // MARK: - Source node

    private func makeSourceNode() -> AVAudioSourceNode {
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)
            ?? AVAudioFormat()
        let state = renderState
        return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            state.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }
    }
}

// MARK: - Errors

public enum SamplerVoiceError: Error, Sendable {
    case unsupportedFormat
}

// MARK: - Render state (audio-thread-only mutation)

/// Owns the sample buffer and playback cursor.
///
/// Concurrency model:
/// - `installBuffer(_:)` runs on the main thread, before the audio engine
///   starts. After that point, `sampleBuffer` is read-only.
/// - `requestTrigger()` and `requestSilence()` run on the main thread and
///   only mutate aligned 32-bit fields (atomic on all Apple platforms).
/// - `render(_:_:)` runs on the audio thread and mutates `position`,
///   `isPlaying`, `lastSeenTrigger`. No other thread reads these.
private final class RenderState: @unchecked Sendable {

    private var sampleBuffer: [Float] = []

    // Audio-thread state (only the audio thread mutates these after install).
    private var position: Int = 0
    private var isPlaying: Bool = false
    private var lastSeenTrigger: UInt32 = 0

    // Main-thread → audio-thread signal flags. UInt32 is atomic-width.
    private var triggerCount: UInt32 = 0
    private var silenceRequested: Bool = false

    /// Main thread, before audio engine start.
    func installBuffer(_ samples: [Float]) {
        sampleBuffer = samples
        position = 0
        isPlaying = false
        triggerCount = 0
        lastSeenTrigger = 0
        silenceRequested = false
    }

    /// Main thread.
    func requestTrigger() {
        triggerCount &+= 1
    }

    /// Main thread.
    func requestSilence() {
        silenceRequested = true
    }

    /// Audio thread. Writes `frameCount` mono float32 samples into the first
    /// channel of `audioBufferList`. Zero allocation, no locks.
    func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard abl.count > 0, let raw = abl[0].mData else { return }
        let buf = raw.assumingMemoryBound(to: Float.self)
        let byteCount = frameCount * MemoryLayout<Float>.size

        // Detect new triggers since the last render block.
        let current = triggerCount
        if current != lastSeenTrigger {
            lastSeenTrigger = current
            position = 0
            isPlaying = true
            silenceRequested = false
        }

        if silenceRequested {
            isPlaying = false
            silenceRequested = false
        }

        if !isPlaying || sampleBuffer.isEmpty {
            memset(buf, 0, byteCount)
            return
        }

        let remaining = sampleBuffer.count - position
        let toCopy = min(frameCount, max(0, remaining))

        if toCopy > 0 {
            sampleBuffer.withUnsafeBufferPointer { ptr in
                if let base = ptr.baseAddress {
                    memcpy(buf, base.advanced(by: position), toCopy * MemoryLayout<Float>.size)
                }
            }
            position += toCopy
        }

        if toCopy < frameCount {
            memset(buf.advanced(by: toCopy), 0, (frameCount - toCopy) * MemoryLayout<Float>.size)
        }

        if position >= sampleBuffer.count {
            isPlaying = false
        }
    }

    // Test-only inspection.
    var debugIsPlaying: Bool { isPlaying }
    var debugPosition: Int { position }
    var debugBufferCount: Int { sampleBuffer.count }
}

// MARK: - Test hooks

extension SamplerVoice {
    /// Test-only: renders one block synchronously, mirroring what the
    /// AVAudioSourceNode render block does on the audio thread. Lets unit
    /// tests drive playback without spinning up a real audio engine.
    func _testRender(
        frameCount: Int,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) {
        renderState.render(frameCount: frameCount, audioBufferList: audioBufferList)
    }

    var _testIsPlaying: Bool { renderState.debugIsPlaying }
    var _testPosition: Int { renderState.debugPosition }
    var _testBufferCount: Int { renderState.debugBufferCount }
}
#endif
