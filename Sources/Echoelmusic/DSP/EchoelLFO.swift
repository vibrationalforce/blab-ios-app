import Foundation

/// Free-running Low Frequency Oscillator for modulation.
/// Audio-thread safe — no allocation, no branching.
public final class EchoelLFO: @unchecked Sendable {

    // MARK: - Waveform

    public enum Waveform: String, CaseIterable, Sendable {
        case sine
        case triangle
        case square
        case sawtooth
        case sampleAndHold
    }

    // MARK: - Parameters

    /// LFO rate in Hz [0.01 - 20]
    public var rate: Float = 0.2       // Slow — one sweep every 5 seconds

    /// LFO depth [0 - 1]
    public var depth: Float = 0.3      // Gentle modulation

    /// Waveform shape
    public var waveform: Waveform = .sine

    // MARK: - State

    private var phase: Float = 0
    private var sampleRate: Float
    private var sAndHValue: Float = 0  // Sample & Hold current value

    /// Inline xorshift32 RNG state for Sample & Hold. Replaces `Float.random`,
    /// which pulls from the system RNG (a syscall) and is NOT audio-thread safe.
    /// This keeps `next()` real-time safe even when driven from a render block.
    private var rngState: UInt32 = 0x2545_F491

    // MARK: - Init

    public init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate
    }

    // MARK: - Process

    /// Get next LFO value. Returns [-depth, +depth]. Audio-thread safe.
    @inline(__always)
    public func next() -> Float {
        // Advance phase
        phase += rate / sampleRate
        if phase >= 1.0 {
            phase -= 1.0
            // Update S&H on phase reset — audio-thread-safe inline PRNG.
            sAndHValue = nextRandom()
        }

        let raw: Float
        switch waveform {
        case .sine:
            raw = sinf(phase * Float.pi * 2)

        case .triangle:
            // 0→0.25: rise 0→1, 0.25→0.75: fall 1→-1, 0.75→1: rise -1→0
            if phase < 0.25 {
                raw = phase * 4.0
            } else if phase < 0.75 {
                raw = 1.0 - (phase - 0.25) * 4.0
            } else {
                raw = -1.0 + (phase - 0.75) * 4.0
            }

        case .square:
            raw = phase < 0.5 ? 1.0 : -1.0

        case .sawtooth:
            raw = 2.0 * phase - 1.0

        case .sampleAndHold:
            raw = sAndHValue
        }

        return raw * depth
    }

    /// Get next LFO value as unipolar [0, depth]
    @inline(__always)
    public func nextUnipolar() -> Float {
        return (next() + depth) * 0.5
    }

    /// Reset phase
    public func reset() {
        phase = 0
        sAndHValue = 0
        rngState = 0x2545_F491
    }

    /// Inline xorshift32 — audio-thread safe (no syscall). Returns [-1, 1].
    @inline(__always)
    private func nextRandom() -> Float {
        var x = rngState
        x ^= x << 13
        x ^= x >> 17
        x ^= x << 5
        rngState = x
        return Float(x) / Float(UInt32.max) * 2.0 - 1.0
    }
}
