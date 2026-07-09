// EchoelSpaceReverb.swift
// Echoel — the "room-in-room" convolution space (the 4D depth dimension). An inner
// EARLY-REFLECTION impulse (a small, intimate room: the direct hit + a few sparse
// decaying reflections in the first tens of ms) sits inside an outer diffuse TAIL
// impulse (a large enclosing room: dense exponentially-decaying reverberation).
// They sum in PARALLEL under ONE bio-mappable `blend` knob — intimate (ER only) →
// large (ER + full tail) — so the founder's "Raum-im-Raum Faltungshall" is a single
// continuous control the body can drive (coherence → intimate/close).
//
// SCOPE (slice 1): a PURE, deterministic, unit-tested DSP core built on the audited
// `EchoelConvolution` overlap-save primitive, with synthetic impulse responses. It
// is NOT yet in the live render path — `process(_:)` allocates and is for offline /
// test use. Wiring it into the master graph lock-free (and swapping the long tail to
// a partitioned-FFT convolution for real-time CPU) is the next slice, gated by the
// audio-thread reviewer. Building + proving the core first keeps the founder-approved
// live sound untouched while the room-in-room model is validated.

#if canImport(Accelerate)
import Foundation
import Accelerate

public final class EchoelSpaceReverb: @unchecked Sendable {

    private let er: EchoelConvolution      // inner small room (early reflections)
    private let tail: EchoelConvolution    // outer large room (diffuse tail)
    /// Pre-allocated wet scratch (sized to maxBlock) so `processInPlace` never
    /// allocates — the audio-thread-safe path.
    private var erScratch: [Float]
    private var tailScratch: [Float]
    private let maxBlock: Int

    /// Dry→wet amount, 0…1.
    public private(set) var mix: Float
    /// Room-in-room blend: 0 = intimate (early reflections only), 1 = large
    /// enclosing room (early reflections + full diffuse tail). Bio-mappable.
    public private(set) var blend: Float

    public init(sampleRate: Float = 48_000, maxBlock: Int = 2048,
                erMillis: Float = 80, tailSeconds: Float = 1.8,
                mix: Float = 0.25, blend: Float = 0.5, seed: UInt64 = 0xEC0E1) {
        let block = Swift.max(1, maxBlock)
        self.maxBlock = block
        self.erScratch = [Float](repeating: 0, count: block)
        self.tailScratch = [Float](repeating: 0, count: block)
        self.mix = EchoelSpaceReverb.clamp01(mix)
        self.blend = EchoelSpaceReverb.clamp01(blend)
        let erTaps = Swift.max(1, Int(sampleRate * erMillis / 1000))
        let tailTaps = Swift.max(1, Int(sampleRate * tailSeconds))
        self.er = EchoelConvolution(kernel: EchoelSpaceReverb.earlyReflectionIR(taps: erTaps, seed: seed),
                                    maxInputLength: block)
        self.tail = EchoelConvolution(kernel: EchoelSpaceReverb.tailIR(taps: tailTaps, seed: seed &+ 1),
                                      maxInputLength: block)
    }

    /// Live macro: dry/wet + room-in-room blend (both clamped). Control-rate.
    public func setSpace(mix: Float, blend: Float) {
        self.mix = EchoelSpaceReverb.clamp01(mix)
        self.blend = EchoelSpaceReverb.clamp01(blend)
    }

    /// Process a dry block → a wet block of the same length. ALLOCATES — offline /
    /// non-audio-thread only (the real-time wiring is a later, reviewed slice).
    public func process(_ dry: [Float]) -> [Float] {
        let n = dry.count
        guard n > 0 else { return [] }
        let erOut = er.process(dry)
        let tailOut = tail.process(dry)
        var out = [Float](repeating: 0, count: n)
        let erGain: Float = 0.7                 // inner room always present
        let tailGain: Float = 0.9 * blend       // outer room scales with the blend
        let wet = EchoelSpaceReverb.clamp01(mix)
        for i in 0..<n {
            let e = i < erOut.count ? erOut[i] : 0
            let t = i < tailOut.count ? tailOut[i] : 0
            let w = erGain * e + tailGain * t
            let v = dry[i] * (1 - wet) + w * wet
            out[i] = v.isFinite ? v : 0
        }
        return out
    }

    /// Real-time-safe variant: processes `buffer` IN PLACE (dry → wet) using the
    /// pre-allocated scratch, so it never allocates. `buffer.count` must be
    /// ≤ `maxBlock` (extra samples beyond the scratch are passed through dry).
    /// This is the path the live render will call once wired (reviewed slice);
    /// it produces bit-identical output to `process(_:)` for the same instance.
    public func processInPlace(_ buffer: inout [Float]) {
        let n = Swift.min(buffer.count, maxBlock)
        guard n > 0 else { return }
        er.process(buffer, into: &erScratch)
        tail.process(buffer, into: &tailScratch)
        let erGain: Float = 0.7
        let tailGain: Float = 0.9 * blend
        let wet = EchoelSpaceReverb.clamp01(mix)
        for i in 0..<n {
            let w = erGain * erScratch[i] + tailGain * tailScratch[i]
            let v = buffer[i] * (1 - wet) + w * wet
            buffer[i] = v.isFinite ? v : 0
        }
    }

    // MARK: - Deterministic synthetic impulse responses (pure, testable)

    static func clamp01(_ x: Float) -> Float { Swift.min(1, Swift.max(0, x)) }

    /// Early reflections (the inner, small room): the direct hit at tap 0 plus a
    /// handful of sparse, alternating-sign reflections weighted to arrive early and
    /// fade — the acoustic signature of a small space. Deterministic from `seed`.
    public static func earlyReflectionIR(taps: Int, seed: UInt64, reflections: Int = 8) -> [Float] {
        let n = Swift.max(1, taps)
        var ir = [Float](repeating: 0, count: n)
        ir[0] = 1                                          // direct sound
        var rng = seed | 1
        @inline(__always) func nextUnit() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float(rng >> 40) / Float(1 << 24)       // [0,1)
        }
        for _ in 0..<Swift.max(0, reflections) {
            let pos = Swift.min(n - 1, 1 + Int(nextUnit() * Float(n - 1)))
            let fall = 1 - Float(pos) / Float(n)           // earlier = louder
            let gain = (0.3 + 0.5 * nextUnit()) * fall
            ir[pos] += (nextUnit() < 0.5 ? -gain : gain)
        }
        return ir
    }

    /// Diffuse tail (the outer, large room): dense noise under an exponential energy
    /// envelope (RT60-ish), with the very first sample attenuated so the tail reads
    /// as reflected space, not a second direct hit. Deterministic from `seed`.
    public static func tailIR(taps: Int, seed: UInt64, decay: Float = 5.0) -> [Float] {
        let n = Swift.max(1, taps)
        var ir = [Float](repeating: 0, count: n)
        var rng = seed | 1
        @inline(__always) func nextBipolar() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int32(truncatingIfNeeded: rng >> 32)) / Float(Int32.max)   // [-1,1]
        }
        for i in 0..<n {
            let env = expf(-decay * Float(i) / Float(n))
            ir[i] = nextBipolar() * env
        }
        ir[0] *= 0.2
        return ir
    }
}
#endif
