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
        let srcFormat = file.processingFormat
        guard srcFormat.sampleRate > 0, file.length > 0 else {
            throw SamplerVoiceError.unsupportedFormat
        }

        // Read up to ~2s of SOURCE audio (the buffer is later capped at
        // maxSampleFrames of TARGET-rate audio after conversion).
        let maxSrcFrames = max(1, Int(srcFormat.sampleRate * 2.05))
        let frameCap = AVAudioFrameCount(min(Int(file.length), maxSrcFrames))
        guard let pcm = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCap) else {
            throw SamplerVoiceError.unsupportedFormat
        }
        try file.read(into: pcm, frameCount: frameCap)

        // Convert to mono float32 at the node's fixed 44.1 kHz. Without this a
        // 48 kHz WAV played ~8.8% flat — the node format is constant 44.1 kHz.
        var mono = try Self.resampleToMono(pcm, targetRate: Self.sampleRate)
        if mono.count > Self.maxSampleFrames {
            mono = Array(mono[0..<Self.maxSampleFrames])
        }

        renderState.installBuffer(mono)
        isLoaded = true
        sourceURL = url
    }

    /// Down-mixes + sample-rate-converts a PCM buffer to mono float32 at
    /// `targetRate`, returning the raw samples. Uses `AVAudioConverter`, which
    /// handles both channel down-mix and resampling. Main thread, load-time only.
    private static func resampleToMono(_ src: AVAudioPCMBuffer, targetRate: Double) throws -> [Float] {
        // Fast path: already mono at the target rate — copy directly.
        if src.format.sampleRate == targetRate, src.format.channelCount == 1,
           let ch = src.floatChannelData {
            return Array(UnsafeBufferPointer(start: ch[0], count: Int(src.frameLength)))
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: targetRate,
            channels: 1, interleaved: false
        ), let converter = AVAudioConverter(from: src.format, to: targetFormat) else {
            throw SamplerVoiceError.unsupportedFormat
        }

        let ratio = targetRate / src.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(src.frameLength) * ratio) + 2048
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            throw SamplerVoiceError.unsupportedFormat
        }

        var supplied = false
        var convError: NSError?
        let status = converter.convert(to: out, error: &convError) { _, outStatus in
            if supplied { outStatus.pointee = .noDataNow; return nil }
            supplied = true
            outStatus.pointee = .haveData
            return src
        }
        if status == .error { throw convError ?? SamplerVoiceError.unsupportedFormat }

        guard let ch = out.floatChannelData else { throw SamplerVoiceError.unsupportedFormat }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    /// Triggers playback from the start. Safe to call from the main thread.
    /// Lock-free: stores the gain, then bumps an aligned UInt32 counter; the
    /// render block sees the change on its next callback. `gain` (0...1) scales
    /// the hit for velocity/accent (default 1.0 = full).
    public func fire(gain: Float = 1.0) {
        renderState.requestTrigger(gain: gain)
    }

    /// Stops playback on the next render block. Buffer stays loaded; a
    /// subsequent `fire()` resumes from frame 0.
    public func silence() {
        renderState.requestSilence()
    }

    /// Set the per-pad amp envelope. `level` is a gain multiplier (1.0 = unity);
    /// `attackMs` fades the hit in; `lengthMs` caps playback length (0 = full
    /// sample) with an automatic anti-click release. Main-thread only.
    public func configureShape(level: Float, attackMs: Float, lengthMs: Float) {
        let sr = Float(Self.sampleRate)
        renderState.configureShape(
            level: level,
            attackFrames: Int(max(0, attackMs) * 0.001 * sr),
            lengthFrames: Int(max(0, lengthMs) * 0.001 * sr)
        )
    }

    /// Set per-pad playback: region trim (`start`/`end` as 0…1 of the sample),
    /// `reverse`, and `pitchSemitones` (−24…+24, realised as a playback-rate
    /// change with linear interpolation). Main-thread only. FL/Ableton-style
    /// one-shot shaping with zero audio-thread allocation.
    public func configurePlayback(start: Float = 0, end: Float = 1,
                                  reverse: Bool = false, pitchSemitones: Float = 0) {
        let rate = powf(2.0, max(-24, min(24, pitchSemitones)) / 12.0)
        renderState.configurePlayback(startFrac: start, endFrac: end, reverse: reverse, rate: rate)
    }

    // MARK: - Source node

    /// Set the per-channel insert FX (filter type + cutoff + resonance + drive).
    /// Main-thread only; the audio thread reads atomic-width mirrors.
    public func configureInsertFX(type: Int, cutoff: Float, resonance: Float, drive: Float) {
        renderState.configureInsertFX(type: type, cutoff: cutoff, resonance: resonance, drive: drive)
    }

    private func makeSourceNode() -> AVAudioSourceNode {
        let state = renderState
        let renderBlock: AVAudioSourceNodeRenderBlock = { _, _, frameCount, audioBufferList in
            state.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
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
}

// MARK: - Errors

public enum SamplerVoiceError: Error, Sendable {
    case unsupportedFormat
}

// MARK: - Render state (audio-thread-only mutation)

/// Owns the sample buffer and playback cursor.
///
/// Concurrency model:
/// - `installBuffer(_:)` runs on the main thread — AT ANY TIME. The instrument
///   became a DAW (pad import / browser preview hot-swap samples while the
///   engine renders), so the old "before engine start, then read-only" contract
///   was a live use-after-free (deep audit 2026-07-15, verified CRITICAL). The
///   buffer now travels through a lock-free SPSC handshake: main ALLOCATES a
///   slab and enqueues it (`installQueue`); the render block ADOPTS the newest
///   slab at a block boundary (pointer moves only — no retain/release/malloc/
///   free on the audio thread) and hands the previous one back (`retireQueue`);
///   main FREES retired slabs on the next install. Memory is allocated and
///   deallocated on the main thread exclusively.
/// - `requestTrigger()` and `requestSilence()` run on the main thread and
///   only mutate aligned 32-bit fields (atomic on all Apple platforms).
/// - `render(_:_:)` runs on the audio thread and mutates `position`,
///   `isPlaying`, `lastSeenTrigger`. No other thread reads these.
private final class RenderState: @unchecked Sendable {

    /// One installed sample buffer travelling between threads. The pointer is
    /// the payload — ownership passes main→render (install) and render→main
    /// (retire); allocate/free happen on the main thread only.
    private struct SampleSlab {
        var ptr: UnsafeMutablePointer<Float>?
        var count: Int
        /// `triggerCount` snapshot at install time. Adoption absorbs triggers only
        /// UP TO this value — a `fire()` issued after `installBuffer` (the
        /// loadSample→fire audition flow) must still play the NEW sample; setting
        /// `lastSeenTrigger = triggerCount` at adoption instead would swallow it,
        /// making every browser preview silent (review HIGH on the slab handshake).
        /// Main is the sole writer of `triggerCount`, so the snapshot is exact.
        var trigAtInstall: UInt32 = 0
    }

    /// AUDIO-THREAD-owned after adoption (main never dereferences these).
    private var activeBuf: UnsafeMutablePointer<Float>?
    private var activeCount: Int = 0

    /// main → render: freshly installed slabs (newest wins at adoption).
    /// INVARIANT: install and retire capacities must stay EQUAL and installBuffer
    /// must drain retires before every enqueue — a capacity-8 ring holds 7 usable
    /// slots, and adopting k slabs retires exactly k pointers (previous active +
    /// k−1 superseded) ≤ 7, so the retire queue can never overflow (= never leak).
    /// Changing one capacity without the other silently breaks this proof.
    private let installQueue = SPSCQueue<SampleSlab>(capacity: 8)
    /// render → main: superseded slabs awaiting a main-thread free.
    private let retireQueue = SPSCQueue<SampleSlab>(capacity: 8)
    /// Main-thread mirror of the last installed length (test/UI inspection —
    /// the audio-side `activeCount` must never be read cross-thread).
    private var mainInstalledCount: Int = 0

    // Audio-thread state (only the audio thread mutates these after install).
    private var posF: Float = 0           // fractional playback cursor (rate/reverse aware)
    private var playedOut: Int = 0        // output frames since trigger (for attack fade)
    private var isPlaying: Bool = false
    private var lastSeenTrigger: UInt32 = 0
    private var currentGain: Float = 1.0

    // Main-thread → audio-thread signal flags. UInt32/Float are atomic-width.
    private var triggerCount: UInt32 = 0
    private var triggerGain: Float = 1.0
    private var silenceRequested: Bool = false

    // Per-pad amp-envelope shape (main-thread set, audio-thread read; atomic-width).
    private var level: Float = 1.0        // base gain multiplier
    private var attackFrames: Int = 0     // fade-in length
    private var lengthFrames: Int = 0     // 0 = play full sample; >0 = cap length

    // Per-pad playback: region (start/end as 0…1 of the buffer), direction, rate.
    // FL/Ableton-style: trim the hit, reverse it, pitch it (rate). Atomic-width
    // scalars set on the main thread, read on the audio thread.
    private var startFrac: Float = 0      // region start (0…1)
    private var endFrac: Float = 1        // region end (0…1)
    private var reverse: Bool = false     // play the region backwards
    private var rate: Float = 1.0         // playback speed = pitch (0.25…4, 1 = original)

    // Per-channel INSERT FX params (main-thread set, audio-thread read; atomic-width
    // scalars). The filter STATE lives only on the audio thread (`insertFX`); the
    // render applies the params (recomputing coefficients at most once per block when
    // they change), so there is no cross-thread mutation of the biquad memory.
    private var fxType: Int = 0           // ChannelInsertFX.FilterType.rawValue (0 = off)
    private var fxCutoff: Float = 1200
    private var fxRes: Float = 0.707
    private var fxDrive: Float = 0

    // Audio-thread-only effect instance + last-applied params (change detection).
    private var insertFX = ChannelInsertFX(sampleRate: Float(SamplerVoice.sampleRate))
    private var lastFxType: Int = -1
    private var lastFxCutoff: Float = .nan
    private var lastFxRes: Float = .nan
    private var lastFxDrive: Float = .nan

    /// Main thread — safe at ANY time, including while the engine renders.
    /// Copies `samples` into a fresh slab and hands it to the render thread via
    /// the SPSC handshake; the cursor/trigger reset happens ON ADOPTION (render
    /// side), so the sounding sample is never cut by a half-applied reset.
    func installBuffer(_ samples: [Float]) {
        drainRetired()
        let count = samples.count
        let ptr = UnsafeMutablePointer<Float>.allocate(capacity: Swift.max(1, count))
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress, count > 0 {
                ptr.update(from: base, count: count)
            }
        }
        if installQueue.tryEnqueue(SampleSlab(ptr: ptr, count: count, trigAtInstall: triggerCount)) {
            mainInstalledCount = count
        } else {
            // Pathological install burst filled the queue — drop THIS install and
            // keep the current sample. Freeing here is safe: render never saw it.
            // (Requires ≥7 un-adopted installs inside one render block; the UI may
            // briefly label the new sample while the old one keeps sounding.)
            ptr.deallocate()
            log.log(.error, category: .audio,
                    "SamplerVoice: install queue full — dropped a sample install")
        }
    }

    /// Main thread. Free every slab the render thread has retired.
    private func drainRetired() {
        while let slab = retireQueue.dequeue() { slab.ptr?.deallocate() }
    }

    deinit {
        // Safe regardless of teardown order: the AVAudioSourceNode's render block
        // captures this RenderState STRONGLY (deliberate — do not weaken it), so
        // deinit can only run once no render callback can ever execute again.
        while let slab = installQueue.dequeue() { slab.ptr?.deallocate() }
        while let slab = retireQueue.dequeue() { slab.ptr?.deallocate() }
        activeBuf?.deallocate()
    }

    /// Main thread. Set gain BEFORE bumping the counter so the audio thread
    /// reads a consistent gain when it observes the new trigger.
    func requestTrigger(gain: Float = 1.0) {
        drainRetired()   // free superseded slabs promptly, not only at the next install
        triggerGain = gain
        triggerCount &+= 1
    }

    /// Main thread.
    func requestSilence() {
        silenceRequested = true
    }

    /// Main thread. Set the per-pad amp-envelope shape.
    func configureShape(level: Float, attackFrames: Int, lengthFrames: Int) {
        self.level = max(0, level)
        self.attackFrames = max(0, attackFrames)
        self.lengthFrames = max(0, lengthFrames)
    }

    /// Main thread. Set the per-pad playback region, direction and rate (pitch).
    /// `startFrac`/`endFrac` are 0…1 of the loaded sample; `rate` is the playback
    /// speed (and thus pitch), clamped to a musical 0.25…4 range.
    func configurePlayback(startFrac: Float, endFrac: Float, reverse: Bool, rate: Float) {
        let s = Swift.min(Swift.max(startFrac, 0), 0.999)
        self.startFrac = s
        self.endFrac = Swift.min(Swift.max(endFrac, s + 0.001), 1)
        self.reverse = reverse
        self.rate = Swift.min(Swift.max(rate, 0.25), 4)
    }

    /// Main thread. Set the per-channel insert-FX params (atomic-width scalars; the
    /// audio thread recomputes the biquad at most once per block when they change).
    func configureInsertFX(type: Int, cutoff: Float, resonance: Float, drive: Float) {
        fxType = type
        fxCutoff = cutoff
        fxRes = resonance
        fxDrive = drive
    }

    /// Audio thread. Apply the current insert-FX params (recomputing coefficients
    /// only when a param changed) and run the buffer through the biquad + drive.
    private func applyInsertFX(buf: UnsafeMutablePointer<Float>, frameCount: Int) {
        // Nothing to do when the channel is clean.
        if fxType == 0 && fxDrive <= 0 { return }
        if fxType != lastFxType || fxCutoff != lastFxCutoff
            || fxRes != lastFxRes || fxDrive != lastFxDrive {
            let t = ChannelInsertFX.FilterType(rawValue: fxType) ?? .off
            insertFX.setParams(type: t, cutoffHz: fxCutoff, resonance: fxRes, drive: fxDrive)
            lastFxType = fxType; lastFxCutoff = fxCutoff
            lastFxRes = fxRes; lastFxDrive = fxDrive
        }
        for i in 0..<frameCount { buf[i] = insertFX.process(buf[i]) }
    }

    /// Audio thread. Writes `frameCount` mono float32 samples into the first
    /// channel of `audioBufferList`. Zero allocation, no locks.
    func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard abl.count > 0, let raw = abl[0].mData else { return }
        let buf = raw.assumingMemoryBound(to: Float.self)
        let byteCount = frameCount * MemoryLayout<Float>.size

        // Adopt the newest installed slab at the block boundary: pointer moves
        // only (no retain/release/alloc/free here); the superseded slab goes back
        // to main for disposal. If the retire queue were ever full the old pointer
        // is dropped (bounded leak) rather than freed on the audio thread —
        // unreachable in practice (main drains on every install).
        while let slab = installQueue.dequeue() {
            if let old = activeBuf {
                _ = retireQueue.tryEnqueue(SampleSlab(ptr: old, count: activeCount))
            }
            activeBuf = slab.ptr
            activeCount = slab.count
            posF = 0
            playedOut = 0
            isPlaying = false
            // Absorb only triggers issued BEFORE this install (aimed at the old
            // sample). A fire() issued after installBuffer — the audition flow —
            // stays pending and plays the new sample in this same block below.
            lastSeenTrigger = slab.trigAtInstall
            silenceRequested = false
        }

        let count = activeCount

        // Playback region from the 0…1 fractions, clamped to a valid [start,end).
        var playStart = Int(startFrac * Float(count))
        var playEnd = Int(endFrac * Float(count))
        playStart = Swift.max(0, Swift.min(playStart, Swift.max(0, count - 1)))
        playEnd = Swift.max(playStart + 1, Swift.min(playEnd, count))
        if lengthFrames > 0 { playEnd = Swift.min(playEnd, playStart + lengthFrames) }

        // Detect new triggers since the last render block.
        let current = triggerCount
        if current != lastSeenTrigger {
            lastSeenTrigger = current
            isPlaying = true
            silenceRequested = false
            currentGain = triggerGain
            posF = reverse ? Float(playEnd - 1) : Float(playStart)   // start at the right edge
            playedOut = 0
            insertFX.reset()   // clear filter memory so a new hit starts clean
        }

        if silenceRequested {
            isPlaying = false
            silenceRequested = false
        }

        if !isPlaying || count == 0 || playEnd <= playStart {
            memset(buf, 0, byteCount)
            return
        }

        // Per-sample resampled playback: advance a fractional cursor by ±rate and
        // linearly interpolate. Direction = reverse. Amp envelope: base gain
        // (level × velocity), linear attack fade-in, release fade at the region
        // edge in the direction of travel (anti-click). Arithmetic + pointer reads
        // only — no allocation, no locks: audio-thread-safe.
        let step: Float = Swift.max(0.001, rate) * (reverse ? -1 : 1)
        let regionLen = playEnd - playStart
        let rel = Swift.min(512, Swift.max(64, regionLen / 8))
        let base = currentGain * level
        let startF = Float(playStart)
        let endF = Float(playEnd)

        var produced = 0
        if let b = activeBuf {
            while produced < frameCount {
                let i0 = Int(posF)
                if posF < startF || posF >= endF || i0 < 0 || i0 >= count { break }
                let frac = posF - Float(i0)
                let s0 = b[i0]
                let s1 = (i0 + 1 < count) ? b[i0 + 1] : s0
                var amp = base
                if attackFrames > 0 && playedOut < attackFrames {
                    amp *= Float(playedOut) / Float(attackFrames)
                }
                let distEnd = reverse ? (posF - startF) : (endF - posF)
                if distEnd < Float(rel) { amp *= Swift.max(0, distEnd) / Float(rel) }
                var v = (s0 + (s1 - s0) * frac) * amp
                if v > -1e-15 && v < 1e-15 { v = 0 }   // flush denormals (edge ramps)
                buf[produced] = v
                posF += step
                produced += 1
                playedOut += 1
            }
        }

        if produced < frameCount {
            memset(buf.advanced(by: produced), 0, (frameCount - produced) * MemoryLayout<Float>.size)
        }

        // Per-channel insert FX (filter + drive) on the channel's output, over the whole
        // block including the zero-padded tail after `produced`.
        // NOT across silent blocks, though: the `!isPlaying` early return above bails
        // before reaching here, so once the cursor leaves the region the biquad stops
        // being clocked until the next trigger resets it. A high-resonance tail is
        // therefore truncated at the block edge rather than ringing out. That is the
        // deliberate trade — clocking an idle voice's filter forever is exactly what the
        // idle-voice skip exists to avoid — and the region-edge release ramp already
        // tapers the filter INPUT toward zero before the region ends — that bounds the
        // filter's INPUT, not its stored state, so at high resonance the cut is not
        // provably small. Not device-verified. (The earlier wording claimed ring-out
        // "across the silent tail"; true of the intra-block tail, never across blocks.)
        applyInsertFX(buf: buf, frameCount: frameCount)
        // Source-node output boundary — last, because `applyInsertFX` writes the
        // hardware buffer in place. Unconditional, since that call returns early on
        // a clean channel, and this voice plays USER-IMPORTED audio: the sample slab
        // is a non-finite source no internal hardening can reach. Nothing on the
        // import path checks finiteness, and the flush at the interpolation
        // (`v > -1e-15 && v < 1e-15`) is false for both NaN and +inf, so a float32
        // file carrying those bit patterns reaches here intact. Finite audio is
        // bit-identical. See `AudioOutputGuard`.
        AudioOutputGuard.sweepNonFinite(buf, count: frameCount)

        if posF < startF || posF >= endF { isPlaying = false }
    }

    // Test-only inspection. `debugBufferCount` reads the MAIN-side mirror (an
    // install is visible immediately, before the render adopts it); the other
    // two read audio-side state — tests drive `render` synchronously.
    var debugIsPlaying: Bool { isPlaying }
    var debugPosition: Int { Int(posF) }
    var debugBufferCount: Int { mainInstalledCount }
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
