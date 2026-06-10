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

    init(sampleRate: Float) {
        self.modalBank = EchoelModalBank(sampleRate: sampleRate)
        self.scratch = [Float](repeating: 0, count: 4096)
        self.modalBank.material = .drum
        self.modalBank.frequency = 90
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
    }
}

#endif
