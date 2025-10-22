import Foundation
import AVFoundation
import Accelerate

/// A lightweight biquad filter that can operate on mono or stereo buffers. The
/// implementation is intentionally simple so it can run both in the audio graph
/// and inside off-line analysis tools.
public struct BiquadFilter {
    public enum FilterType {
        case lowPass
        case highPass
        case bandPass
        case notch
        case peaking(gain: Float)
    }

    private var b0: Float = 1
    private var b1: Float = 0
    private var b2: Float = 0
    private var a1: Float = 0
    private var a2: Float = 0

    private var z1: Float = 0
    private var z2: Float = 0

    public init(type: FilterType, cutoff: Float, q: Float, sampleRate: Double) {
        configure(type: type, cutoff: cutoff, q: q, sampleRate: sampleRate)
    }

    public mutating func configure(type: FilterType, cutoff: Float, q: Float, sampleRate: Double) {
        let omega = 2 * Float.pi * cutoff / Float(sampleRate)
        let sinOmega = sinf(omega)
        let cosOmega = cosf(omega)
        let alpha = sinOmega / (2 * max(0.001, q))

        switch type {
        case .lowPass:
            let norm = 1 / (1 + alpha)
            b0 = ((1 - cosOmega) / 2) * norm
            b1 = (1 - cosOmega) * norm
            b2 = b0
            a1 = (-2 * cosOmega) * norm
            a2 = (1 - alpha) * norm
        case .highPass:
            let norm = 1 / (1 + alpha)
            b0 = ((1 + cosOmega) / 2) * norm
            b1 = -(1 + cosOmega) * norm
            b2 = b0
            a1 = (-2 * cosOmega) * norm
            a2 = (1 - alpha) * norm
        case .bandPass:
            let norm = 1 / (1 + alpha)
            b0 = alpha * norm
            b1 = 0
            b2 = -alpha * norm
            a1 = (-2 * cosOmega) * norm
            a2 = (1 - alpha) * norm
        case .notch:
            let norm = 1 / (1 + alpha)
            b0 = norm
            b1 = (-2 * cosOmega) * norm
            b2 = norm
            a1 = (-2 * cosOmega) * norm
            a2 = (1 - alpha) * norm
        case .peaking(let gain):
            let a = powf(10, gain / 40)
            let norm = 1 / (1 + alpha / a)
            b0 = (1 + alpha * a) * norm
            b1 = (-2 * cosOmega) * norm
            b2 = (1 - alpha * a) * norm
            a1 = (-2 * cosOmega) * norm
            a2 = (1 - alpha / a) * norm
        }
    }

    public mutating func process(sample: Float) -> Float {
        let result = b0 * sample + z1
        z1 = b1 * sample - a1 * result + z2
        z2 = b2 * sample - a2 * result
        return result
    }

    public mutating func reset() {
        z1 = 0
        z2 = 0
    }
}

/// A resonant filter bank that can emulate formant filtering or harmonic
/// emphasis for vocal synthesis.
public final class ResonantFilterBank {
    private var filters: [BiquadFilter]

    public init(formantFrequencies: [Float], q: Float = 10, sampleRate: Double) {
        filters = formantFrequencies.map { freq in
            BiquadFilter(type: .bandPass, cutoff: freq, q: q, sampleRate: sampleRate)
        }
    }

    public func process(sample: Float) -> Float {
        var output = sample
        for index in filters.indices {
            var filter = filters[index]
            output = filter.process(sample: output)
            filters[index] = filter
        }
        return output
    }
}

/// Spectral tilt filter used to control brightness or warmth of a signal. The
/// implementation is based on an IIR shelving filter.
public struct SpectralTilt {
    private var filter: BiquadFilter

    public init(tilt: Float, sampleRate: Double) {
        // Positive tilt adds brightness (high-shelf), negative tilt darkens.
        let gain = max(-12, min(12, tilt * 12))
        let cutoff: Float = tilt >= 0 ? 6_000 : 1_500
        filter = BiquadFilter(type: .peaking(gain: gain), cutoff: cutoff, q: 0.707, sampleRate: sampleRate)
    }

    public mutating func process(sample: Float) -> Float {
        filter.process(sample: sample)
    }
}

/// Utility for processing interleaved stereo buffers with a closure.
public func processStereoBuffer(_ buffer: AVAudioPCMBuffer, processor: (inout Float, inout Float) -> Void) {
    guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
    let left = data[0]
    let right = data[1]
    let frameCount = Int(buffer.frameLength)

    for index in 0..<frameCount {
        var leftSample = left[index]
        var rightSample = right[index]
        processor(&leftSample, &rightSample)
        left[index] = leftSample
        right[index] = rightSample
    }
}
