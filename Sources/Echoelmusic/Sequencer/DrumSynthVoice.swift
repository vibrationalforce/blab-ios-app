// DrumSynthVoice.swift
// Echoel — a synthesized percussion voice for the beat sequencer, wrapping one
// EchoelModalBank (physics-based membrane/bell/bar resonator) behind a single
// AVAudioSourceNode. The sample-based SamplerVoice and this synth voice are the
// two layers a pad can use (sample / synth / blend).
//
// Triggering: PatternEngine.onStep fires on the MAIN thread, so `fire(gain:)`
// strikes the modal bank on the main thread (how EchoelModalBank is designed to
// be driven). render() runs on the audio thread and only advances the mode
// decay — the same control-thread-strike / audio-thread-render split used by
// SoundscapeEngine. Mode params are Float-width (atomic on Apple).

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

    /// Apply editable params to the modal bank. Main thread only.
    public func configure(_ params: DrumSynthParams) {
        let bank = state.modalBank
        if let material = EchoelModalBank.MaterialPreset(rawValue: params.material) {
            bank.material = material
        }
        bank.frequency = params.frequency
        bank.damping = params.damping
        bank.stiffness = params.stiffness
        bank.brightness = params.brightness
        bank.strikePosition = params.strikePosition
        bank.size = params.size
        state.level = max(0, params.level)
    }

    /// Strike the drum. Main thread only (called from PatternEngine.onStep).
    public func fire(gain: Float = 1.0) {
        state.modalBank.noteOn(velocity: min(max(gain, 0), 1))
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
