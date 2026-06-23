import Foundation

// EchoelLoFiFX.swift
// Two pro EchoelFX stages added in the "more algorithms" workstream:
//
//   • EchoelBitcrush     — digital lo-fi: bit-depth quantisation + sample-rate
//                          reduction (sample-and-hold), parallel wet/dry. The sound
//                          of vintage samplers / chiptune / crushed textures.
//   • EchoelStereoWidener— M/S stereo width: 0 = mono … 1 = unchanged … 2 = wide.
//
// Same contract as the other stages (EchoelModFX): `final class … @unchecked
// Sendable`, plain Float params (atomic-width, lock-free), pure C-math in the hot
// loop — no allocation, no locks, no ObjC, audio-thread safe. Self-contained
// (Foundation only) so the AUv3/DSP target compiles them without Core.

// MARK: - Bitcrush (digital lo-fi)

public final class EchoelBitcrush: @unchecked Sendable {

    /// Effective bit depth [1…16]. 16 ≈ transparent; lower = coarser quantisation.
    /// Cached into `levels` so the hot loop does no `powf`.
    public var bits: Float = 16 { didSet { levels = Self.levels(forBits: bits) } }
    /// Sample-rate reduction factor [1…64]. 1 = full rate; N holds each input for N
    /// samples (downsamples by N). Cached into an integer `step`.
    public var downsample: Float = 1 { didSet { step = Self.step(forDownsample: downsample) } }
    /// Parallel wet/dry blend [0…1].
    public var mix: Float = 1.0

    private var levels: Float = 65535
    private var step: Int = 1
    // Sample-and-hold state per channel.
    private var heldL: Float = 0
    private var heldR: Float = 0
    private var counter: Int = 0

    public init(sampleRate: Float = 48000) {
        levels = Self.levels(forBits: bits)
        step = Self.step(forDownsample: downsample)
    }

    private static func levels(forBits b: Float) -> Float {
        let clamped = Swift.min(Swift.max(b, 1), 16)
        return powf(2, clamped) - 1     // e.g. bits 8 → 255 quantisation steps
    }
    private static func step(forDownsample d: Float) -> Int {
        Int(Swift.min(Swift.max(d, 1), 64).rounded())
    }

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        // Sample-rate reduction: refresh the held sample every `step` inputs.
        if counter <= 0 {
            heldL = inL
            heldR = inR
            counter = step
        }
        counter -= 1
        // Bit-depth quantisation of the held sample (symmetric around 0).
        let q = levels
        let crushedL = q > 0 ? roundf(heldL * q) / q : heldL
        let crushedR = q > 0 ? roundf(heldR * q) / q : heldR
        let m = Swift.min(Swift.max(mix, 0), 1)
        return (inL * (1 - m) + crushedL * m,
                inR * (1 - m) + crushedR * m)
    }

    public func reset() { heldL = 0; heldR = 0; counter = 0 }
}

// MARK: - Stereo Widener (M/S)

public final class EchoelStereoWidener: @unchecked Sendable {

    /// Stereo width [0…2]: 0 = mono (sum), 1 = unchanged, 2 = doubled side energy.
    public var width: Float = 1.0

    public init(sampleRate: Float = 48000) {}

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        let w = Swift.min(Swift.max(width, 0), 2)
        let mid = (inL + inR) * 0.5
        let side = (inL - inR) * 0.5 * w
        return (mid + side, mid - side)
    }

    public func reset() {}
}
