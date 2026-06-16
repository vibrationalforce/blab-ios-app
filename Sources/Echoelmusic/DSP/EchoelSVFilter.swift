import Foundation

/// Chamberlin State Variable Filter (SVF)
/// Provides lowpass, highpass, bandpass, notch simultaneously.
/// Zero allocation, no branching — safe for audio render thread.
///
/// Reference: Hal Chamberlin, "Musical Applications of Microprocessors" (1985)
public final class EchoelSVFilter: @unchecked Sendable {

    // MARK: - Filter Mode

    public enum Mode: String, CaseIterable, Sendable {
        case lowpass
        case highpass
        case bandpass
        case notch
    }

    // MARK: - Parameters

    /// Filter cutoff frequency in Hz [20-20000]
    public var cutoff: Float = 2000.0 {
        didSet { updateCoefficients() }
    }

    /// Resonance [0-1] (0.7 = musical, 0.95 = near self-oscillation)
    public var resonance: Float = 0.3 {      // Gentle — no harsh peaking
        didSet { updateCoefficients() }
    }

    /// Active filter mode
    public var mode: Mode = .lowpass

    // MARK: - Internal State

    private var sampleRate: Float
    private var f: Float = 0     // Frequency coefficient
    private var q: Float = 1     // Damping (1/resonance)
    private var low: Float = 0   // Lowpass output state
    private var band: Float = 0  // Bandpass output state
    private var high: Float = 0  // Highpass output (computed)
    private var notchOut: Float = 0 // Notch output (computed)

    // MARK: - Init

    public init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate
        updateCoefficients()
    }

    // MARK: - Coefficient Update

    private func updateCoefficients() {
        // Chamberlin SVF coefficient: f = 2 * sin(π * cutoff / sampleRate).
        // The Chamberlin topology is only numerically stable while cutoff ≤ SR/6
        // (Hal Chamberlin, 1985). Above that the two integrators accumulate energy
        // and self-oscillate into a harsh, scratchy high-pitched whine — the worst
        // audible artifact in the synth. Clamp the normalized cutoff to 1/6, where
        // f reaches its safe maximum of 2·sin(π/6) = 1.0. (Was 0.45 ≈ SR/2 → f≈1.95,
        // right at the blow-up boundary.)
        let normalizedCutoff = min(cutoff / sampleRate, 1.0 / 6.0)
        f = 2.0 * sinf(Float.pi * normalizedCutoff)

        // q is the damping factor (1 - resonance). Keep a minimum damping of 0.05 so
        // the resonant peak can't run away into near-self-oscillation ringing (the
        // other harshness source); 0.95 stays expressive without screaming.
        let clampedRes = max(0.01, min(resonance, 0.95))
        q = 1.0 - clampedRes
    }

    // MARK: - Process

    /// Process a single sample through the filter. Audio-thread safe.
    @inline(__always)
    public func process(_ input: Float) -> Float {
        // Chamberlin SVF topology (2 integrators + feedback)
        // No branching, no allocation, SIMD-friendly
        low += f * band
        high = input - low - q * band
        band += f * high
        notchOut = high + low

        // Select output based on mode
        switch mode {
        case .lowpass:  return low
        case .highpass: return high
        case .bandpass: return band
        case .notch:    return notchOut
        }
    }

    /// Process a buffer of samples in-place
    public func processBuffer(_ buffer: inout [Float], frameCount: Int) {
        for i in 0..<frameCount {
            buffer[i] = process(buffer[i])
        }
    }

    /// Reset filter state (call when changing notes to avoid clicks)
    public func reset() {
        low = 0
        band = 0
        high = 0
        notchOut = 0
    }
}
