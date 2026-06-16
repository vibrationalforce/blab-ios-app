import Foundation

/// Freeverb-style algorithmic reverb — eight parallel damped feedback-comb
/// filters into four series allpass filters per channel, the classic Schroeder/
/// Moorer topology popularised by Jezar's "Freeverb". Cheap, stable, and the
/// reference cheap-reverb sound; gives the additive synth the room/hall space
/// that makes it read as produced rather than thin and dry.
///
/// Audio-thread safe: every delay buffer is pre-allocated in `init` (sized from
/// the sample rate). The hot loop only reads/writes indices and does scalar
/// arithmetic — no allocation, locks, ObjC, GCD, or I/O.
///
/// Reference: M. R. Schroeder, "Natural Sounding Artificial Reverberation"
/// (1962); Jezar at Dreampoint, "Freeverb" (public domain).
public final class EchoelReverb: @unchecked Sendable {

    // MARK: - Control-plane parameters

    /// Tail length / feedback [0…1]. Higher = longer decay.
    public var roomSize: Float = 0.72 { didSet { updateDamping() } }
    /// High-frequency damping [0…1]. Higher = darker, faster HF decay.
    public var damping: Float = 0.5 { didSet { updateDamping() } }
    /// Wet/dry blend [0…1]. 0 = dry, 1 = fully wet.
    public var mix: Float = 0.25
    /// Stereo width of the wet signal [0…1].
    public var width: Float = 1.0

    // MARK: - Freeverb tuning (samples at 44.1 kHz, scaled to the real SR)

    private static let combTuning: [Int]   = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    private static let allpassTuning: [Int] = [556, 441, 341, 225]
    private static let stereoSpread = 23
    private static let fixedGain: Float = 0.015
    private static let roomScale: Float = 0.28
    private static let roomOffset: Float = 0.7
    private static let allpassFeedback: Float = 0.5

    // MARK: - Comb state (per channel)

    private var combBufL: [[Float]]
    private var combBufR: [[Float]]
    private var combIdxL: [Int]
    private var combIdxR: [Int]
    private var combStoreL: [Float]
    private var combStoreR: [Float]
    private var combFeedback: Float = 0
    private var combDamp1: Float = 0
    private var combDamp2: Float = 0

    // MARK: - Allpass state (per channel)

    private var apBufL: [[Float]]
    private var apBufR: [[Float]]
    private var apIdxL: [Int]
    private var apIdxR: [Int]

    private let combCount: Int
    private let apCount: Int

    public init(sampleRate: Float = 48000) {
        let scale = sampleRate / 44100.0
        func scaled(_ n: Int) -> Int { Swift.max(1, Int(Float(n) * scale)) }

        combCount = Self.combTuning.count
        apCount = Self.allpassTuning.count

        combBufL = Self.combTuning.map { [Float](repeating: 0, count: scaled($0)) }
        combBufR = Self.combTuning.map { [Float](repeating: 0, count: scaled($0 + Self.stereoSpread)) }
        combIdxL = [Int](repeating: 0, count: combCount)
        combIdxR = [Int](repeating: 0, count: combCount)
        combStoreL = [Float](repeating: 0, count: combCount)
        combStoreR = [Float](repeating: 0, count: combCount)

        apBufL = Self.allpassTuning.map { [Float](repeating: 0, count: scaled($0)) }
        apBufR = Self.allpassTuning.map { [Float](repeating: 0, count: scaled($0 + Self.stereoSpread)) }
        apIdxL = [Int](repeating: 0, count: apCount)
        apIdxR = [Int](repeating: 0, count: apCount)

        updateDamping()
    }

    private func updateDamping() {
        combFeedback = roomSize * Self.roomScale + Self.roomOffset
        combDamp1 = damping
        combDamp2 = 1.0 - damping
    }

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        let m = Swift.min(Swift.max(mix, 0.0), 1.0)
        if m <= 0 { return (inL, inR) }

        // Mono excitation into the tank (Freeverb feeds the sum, scaled).
        let input = (inL + inR) * Self.fixedGain

        var outL: Float = 0
        var outR: Float = 0

        // Parallel damped feedback combs.
        for i in 0..<combCount {
            outL += comb(input, buf: &combBufL[i], idx: &combIdxL[i], store: &combStoreL[i])
            outR += comb(input, buf: &combBufR[i], idx: &combIdxR[i], store: &combStoreR[i])
        }
        // Series allpass diffusers.
        for i in 0..<apCount {
            outL = allpass(outL, buf: &apBufL[i], idx: &apIdxL[i])
            outR = allpass(outR, buf: &apBufR[i], idx: &apIdxR[i])
        }

        // Stereo spread of the wet signal.
        let w = Swift.min(Swift.max(width, 0.0), 1.0)
        let wet1 = w * 0.5 + 0.5
        let wet2 = (1.0 - w) * 0.5
        let wetL = outL * wet1 + outR * wet2
        let wetR = outR * wet1 + outL * wet2

        let dry = 1.0 - m
        return (inL * dry + wetL * m, inR * dry + wetR * m)
    }

    public func reset() {
        for i in 0..<combCount {
            for j in 0..<combBufL[i].count { combBufL[i][j] = 0 }
            for j in 0..<combBufR[i].count { combBufR[i][j] = 0 }
            combIdxL[i] = 0; combIdxR[i] = 0
            combStoreL[i] = 0; combStoreR[i] = 0
        }
        for i in 0..<apCount {
            for j in 0..<apBufL[i].count { apBufL[i][j] = 0 }
            for j in 0..<apBufR[i].count { apBufR[i][j] = 0 }
            apIdxL[i] = 0; apIdxR[i] = 0
        }
    }

    // MARK: - Filter primitives

    /// Lowpass-feedback comb filter (Freeverb's `comb`).
    @inline(__always)
    private func comb(_ input: Float, buf: inout [Float], idx: inout Int, store: inout Float) -> Float {
        let output = buf[idx]
        // + tiny DC keeps the decaying feedback state out of the denormal range
        // (< ~1e-38), where each sample would trigger a CPU stall → audible crackle
        // on the reverb tail. 1e-20 is inaudible (steady-state DC ≈ 1e-19).
        store = output * combDamp2 + store * combDamp1 + 1.0e-20
        buf[idx] = input + store * combFeedback
        idx += 1
        if idx >= buf.count { idx = 0 }
        return output
    }

    /// Schroeder allpass diffuser (Freeverb's `allpass`).
    @inline(__always)
    private func allpass(_ input: Float, buf: inout [Float], idx: inout Int) -> Float {
        let bufout = buf[idx]
        let output = -input + bufout
        buf[idx] = input + bufout * Self.allpassFeedback
        idx += 1
        if idx >= buf.count { idx = 0 }
        return output
    }
}
