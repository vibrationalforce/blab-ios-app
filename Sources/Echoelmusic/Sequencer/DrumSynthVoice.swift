// DrumSynthVoice.swift
// Echoel — a synthesized percussion voice for the beat sequencer, wrapping one
// EchoelModalBank (physics-based membrane/bell/bar resonator) behind a single
// AVAudioSourceNode. The sample-based SamplerVoice and this synth voice are the
// two layers a pad can use (sample / synth / blend).
//
// Triggering: PatternEngine.onStep fires on the MAIN thread. `fire(gain:)` and
// `configure(_:)` do NOT touch the modal bank directly — they record a lock-free
// request (an atomic-width counter + scalar fields, the SamplerVoice pattern) and
// the AUDIO thread applies it inside render() before generating the block. This
// keeps every read-modify-write of the modal-bank mode arrays (excite / material
// reconfigure — both in-place, allocation-free) on the audio thread, so the main
// thread never mutates render state concurrently (audit 2026-07-02 P0.2 race fix).

#if canImport(AVFoundation) && canImport(Accelerate)
import AVFoundation
import Foundation

/// Editable parameters for a synth drum pad (pure value type, persistable).
public struct DrumSynthParams: Codable, Sendable, Equatable {
    public var material: String = "Drum"   // EchoelModalBank.MaterialPreset rawValue
    public var frequency: Float = 90       // base pitch (Hz)
    public var damping: Float = 0.4        // decay rate (short = tight)
    public var stiffness: Float = 0.0      // inharmonicity
    public var brightness: Float = 0.5
    public var strikePosition: Float = 0.2
    public var size: Float = 1.0
    public var level: Float = 1.0          // output gain

    public init() {}
}

/// One synthesized percussion voice on a single `AVAudioSourceNode`.
public final class DrumSynthVoice: @unchecked Sendable {

    public static let sampleRate: Double = 48_000

    private let state: DrumRenderState
    public lazy var sourceNode: AVAudioSourceNode = makeSourceNode()

    public init() {
        self.state = DrumRenderState(sampleRate: Float(Self.sampleRate))
    }

    /// Request editable params. Main thread; the audio thread applies them (the
    /// modal-bank reconfigure runs there, never concurrently with render).
    public func configure(_ params: DrumSynthParams) {
        state.requestConfig(params)
    }

    /// Strike the drum. Main thread (called from PatternEngine.onStep). Lock-free:
    /// records the hit; the audio thread performs the excite on its next callback.
    public func fire(gain: Float = 1.0) {
        state.requestStrike(gain: gain)
    }

    /// Set the per-channel insert FX (filter type + cutoff + resonance + drive).
    /// Main-thread only; the audio thread reads atomic-width mirrors.
    public func configureInsertFX(type: Int, cutoff: Float, resonance: Float, drive: Float) {
        state.fxType = type
        state.fxCutoff = cutoff
        state.fxRes = resonance
        state.fxDrive = drive
    }

    private func makeSourceNode() -> AVAudioSourceNode {
        let state = self.state
        let renderBlock: AVAudioSourceNodeRenderBlock = { _, _, frameCount, audioBufferList in
            state.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else {
            return AVAudioSourceNode(renderBlock: renderBlock)
        }
        return AVAudioSourceNode(format: format, renderBlock: renderBlock)
    }
}

/// Owns the modal bank + render scratch. Strike happens on the main thread;
/// render advances decay on the audio thread.
private final class DrumRenderState: @unchecked Sendable {

    let modalBank: EchoelModalBank
    private var scratch: [Float]
    /// Output gain (main-thread set, audio-thread read; atomic-width).
    var level: Float = 1.0

    // Strike request (main thread → audio thread). A UInt32 counter + a Float gain,
    // both atomic-width on Apple platforms, so no lock. The audio thread compares the
    // counter to `lastSeenStrike` and, on a change, performs the in-place excite.
    private var strikeCount: UInt32 = 0
    private var lastSeenStrike: UInt32 = 0
    private var strikeGain: Float = 1.0

    // Config request (main thread → audio thread). A version counter + scalar fields
    // (the MaterialPreset is a simple String-raw enum → an atomic-width tag). On a
    // version change the audio thread applies them, so the modal-bank array reconfigure
    // (in-place, allocation-free) never races the render read.
    private var cfgVersion: UInt32 = 0
    private var lastSeenCfg: UInt32 = 0
    private var cfgMaterial: EchoelModalBank.MaterialPreset = .drum
    private var cfgFrequency: Float = 90
    private var cfgDamping: Float = 0.4
    private var cfgStiffness: Float = 0
    private var cfgBrightness: Float = 0.5
    private var cfgStrikePosition: Float = 0.2
    private var cfgSize: Float = 1.0

    // Per-channel INSERT FX params (main-thread set, audio-thread read; atomic-width).
    // Filter state lives only on the audio thread; coefficients recompute ≤1×/block.
    var fxType: Int = 0
    var fxCutoff: Float = 1200
    var fxRes: Float = 0.707
    var fxDrive: Float = 0
    private var insertFX: ChannelInsertFX
    private var lastFxType: Int = -1
    private var lastFxCutoff: Float = .nan
    private var lastFxRes: Float = .nan
    private var lastFxDrive: Float = .nan

    init(sampleRate: Float) {
        self.modalBank = EchoelModalBank(sampleRate: sampleRate)
        self.scratch = [Float](repeating: 0, count: 4096)
        self.insertFX = ChannelInsertFX(sampleRate: sampleRate)
        self.modalBank.material = .drum
        self.modalBank.frequency = 90
    }

    /// Main thread. Record a strike; the audio thread excites the bank on its next block.
    func requestStrike(gain: Float) {
        strikeGain = min(max(gain, 0), 1)
        strikeCount &+= 1
    }

    /// Main thread. Record new params; the audio thread applies them on its next block.
    /// Resolve the material string here (main thread) into the atomic-width enum tag.
    func requestConfig(_ params: DrumSynthParams) {
        if let m = EchoelModalBank.MaterialPreset(rawValue: params.material) { cfgMaterial = m }
        cfgFrequency = params.frequency
        cfgDamping = params.damping
        cfgStiffness = params.stiffness
        cfgBrightness = params.brightness
        cfgStrikePosition = params.strikePosition
        cfgSize = params.size
        level = max(0, params.level)
        cfgVersion &+= 1
    }

    /// Audio thread. Apply any pending config, then any pending strike — both do the
    /// modal-bank read-modify-write here so it never races the render read below.
    private func applyPendingRequests() {
        let cfg = cfgVersion
        if cfg != lastSeenCfg {
            lastSeenCfg = cfg
            modalBank.material = cfgMaterial     // in-place reconfigure (allocation-free)
            modalBank.frequency = cfgFrequency
            modalBank.damping = cfgDamping
            modalBank.stiffness = cfgStiffness
            modalBank.brightness = cfgBrightness
            modalBank.strikePosition = cfgStrikePosition
            modalBank.size = cfgSize
        }
        let strike = strikeCount
        if strike != lastSeenStrike {
            lastSeenStrike = strike
            modalBank.noteOn(velocity: strikeGain)   // in-place excite
        }
    }

    /// Audio thread. Apply the insert-FX params (recompute coeffs only on change)
    /// and run the buffer through the biquad + drive.
    private func applyInsertFX(_ dst: UnsafeMutablePointer<Float>, _ frameCount: Int) {
        if fxType == 0 && fxDrive <= 0 { return }
        if fxType != lastFxType || fxCutoff != lastFxCutoff
            || fxRes != lastFxRes || fxDrive != lastFxDrive {
            let t = ChannelInsertFX.FilterType(rawValue: fxType) ?? .off
            insertFX.setParams(type: t, cutoffHz: fxCutoff, resonance: fxRes, drive: fxDrive)
            lastFxType = fxType; lastFxCutoff = fxCutoff
            lastFxRes = fxRes; lastFxDrive = fxDrive
        }
        for i in 0..<frameCount { dst[i] = insertFX.process(dst[i]) }
    }

    func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard abl.count > 0, let raw = abl[0].mData else { return }
        let dst = raw.assumingMemoryBound(to: Float.self)
        let count = min(frameCount, scratch.count)

        applyPendingRequests()   // audio-thread: apply config + strike before rendering
        modalBank.render(buffer: &scratch, frameCount: count)

        let g = level
        scratch.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            for i in 0..<count { dst[i] = base[i] * g }
        }
        if frameCount > count {
            memset(dst.advanced(by: count), 0, (frameCount - count) * MemoryLayout<Float>.size)
        }
        // Per-channel insert FX over the whole block (resonance rings into the tail).
        applyInsertFX(dst, frameCount)
    }
}

#endif
