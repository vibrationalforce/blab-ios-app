import Foundation

/// Fractional-delay ring buffer — the shared foundation for every delay-based
/// effect (delay, chorus, flanger). Zero allocation in the audio path, no
/// branching in the hot loop: capacity is rounded up to a power of two so the
/// wrap is a single bitmask.
///
/// Indexing contract: `write(_:)` stores at the head and advances; a `read`
/// with `delaySamples == 1` returns the most recently written sample, `2`
/// returns the one before it, and so on. Negative wrap is handled by the mask
/// (two's-complement `& mask` == modulo for power-of-two capacity).
///
/// Reference: Julius O. Smith III, "Physical Audio Signal Processing" —
/// delay-line interpolation (linear & first-order allpass).
public final class EchoelDelayLine: @unchecked Sendable {

    // MARK: - Storage

    private var buffer: [Float]
    private let capacity: Int       // power of two
    private let mask: Int
    private var writeIndex: Int = 0

    /// First-order allpass interpolation state (single-tap use only).
    private var apPrev: Float = 0

    public let sampleRate: Float
    public let maxDelaySamples: Int

    // MARK: - Init

    public init(maxDelaySeconds: Float = 2.0, sampleRate: Float = 48000) {
        self.sampleRate = sampleRate
        let wanted = Swift.max(4, Int((maxDelaySeconds * sampleRate).rounded(.up)) + 4)
        self.capacity = EchoelDelayLine.nextPowerOfTwo(wanted)
        self.mask = capacity - 1
        self.maxDelaySamples = capacity - 2
        self.buffer = [Float](repeating: 0, count: capacity)
    }

    // MARK: - Write

    /// Push one sample into the line. Audio-thread safe.
    @inline(__always)
    public func write(_ x: Float) {
        buffer[writeIndex] = x
        writeIndex = (writeIndex &+ 1) & mask
    }

    // MARK: - Read (linear interpolation)

    /// Read the line `delaySamples` in the past with linear interpolation.
    /// `delaySamples` is clamped to `[1, maxDelaySamples]`. Audio-thread safe.
    @inline(__always)
    public func read(delaySamples: Float) -> Float {
        // NaN-safe. `Swift.min(Swift.max(x, 1), max)` is a no-op for NaN (every
        // comparison against NaN is false), and the very next line is `Int(d)`, which
        // TRAPS on NaN — a crash on the audio thread, not a degradation.
        let d = delaySamples.clamped(to: 1.0...Float(maxDelaySamples))
        let i0 = Int(d)
        let frac = d - Float(i0)
        let idx0 = (writeIndex &- i0) & mask
        let idx1 = (idx0 &- 1) & mask
        return buffer[idx0] * (1.0 - frac) + buffer[idx1] * frac
    }

    // MARK: - Read (first-order allpass interpolation)

    /// Read with first-order allpass interpolation — flatter magnitude response
    /// than linear, preferred for smoothly modulated taps (flanger/chorus).
    /// Assumes a single modulated read tap (keeps one filter state).
    @inline(__always)
    public func readAllpass(delaySamples: Float) -> Float {
        // NaN-safe. `Swift.min(Swift.max(x, 1), max)` is a no-op for NaN (every
        // comparison against NaN is false), and the very next line is `Int(d)`, which
        // TRAPS on NaN — a crash on the audio thread, not a degradation.
        let d = delaySamples.clamped(to: 1.0...Float(maxDelaySamples))
        let i0 = Int(d)
        let frac = d - Float(i0)
        let idx0 = (writeIndex &- i0) & mask
        let idx1 = (idx0 &- 1) & mask
        // eta in [0,1); coefficient for the allpass interpolator
        let eta = (1.0 - frac) / (1.0 + frac)
        let s0 = buffer[idx0]
        let s1 = buffer[idx1]
        let out = s1 + eta * (s0 - apPrev)
        apPrev = out
        return out
    }

    // MARK: - Reset

    public func reset() {
        for i in 0..<capacity { buffer[i] = 0 }
        writeIndex = 0
        apPrev = 0
    }

    // MARK: - Helpers

    @inline(__always)
    private static func nextPowerOfTwo(_ n: Int) -> Int {
        var p = 1
        while p < n { p <<= 1 }
        return p
    }
}
