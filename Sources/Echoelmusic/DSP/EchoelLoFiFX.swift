import Foundation

// EchoelLoFiFX.swift
// Three pro EchoelFX stages added in the "more algorithms" workstream:
//
//   • EchoelBitcrush     — digital lo-fi: bit-depth quantisation + sample-rate
//                          reduction (sample-and-hold), parallel wet/dry. The sound
//                          of vintage samplers / chiptune / crushed textures.
//   • EchoelStereoWidener— M/S stereo width: 0 = mono … 1 = unchanged … 2 = wide.
//   • EchoelTape         — analog tape / Bandmaschine / VHS character on the DRY
//                          through-signal: wow & flutter pitch warble + tape
//                          saturation + high-frequency loss (the "worn tape" dull).
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

// MARK: - Tape / Bandmaschine / VHS (analog character on the through-signal)

/// Analog tape / VHS character applied to the DRY signal (not an echo — unlike
/// `EchoelDelay.tape`, which wobbles the *repeats*). Three ingredients recreate
/// the sound of a worn Bandmaschine or VHS transport:
///
///   1. **Wow & flutter** — the pitch warble of an imperfect capstan: a short
///      fractional-delay read modulated by a slow "wow" LFO (0.6 Hz) + a fast
///      "flutter" LFO (6.5 Hz), exactly the two-LFO recipe `EchoelDelay` uses,
///      but on the through-signal so the note itself warbles.
///   2. **Saturation** — soft tanh drive: tape/heads compress and add harmonics.
///   3. **HF loss** — a one-pole low-pass: tape and VHS can't hold the top end,
///      so worn transports sound progressively duller.
///
/// The read tap sits at a ~6 ms base so the ±4.6 ms modulation can never drive it
/// negative. A constant ~6 ms latency is part of the character (and it is not
/// summed with a dry path here — the chain replaces the signal — so there is no
/// comb-filtering). Plain Float params, pure C-math, no allocation or locks:
/// audio-thread safe.
public final class EchoelTape: @unchecked Sendable {

    /// Wow & flutter depth [0…1]. 0 = no pitch warble (the tap still reads at the
    /// fixed base, so toggling depth never clicks the latency).
    public var depth: Float = 0.35
    /// Tape saturation drive [0…1]. 0 = clean; higher folds in harmonics + glue.
    public var saturation: Float = 0.25
    /// High-frequency retention [0…1]: 1 = bright (transparent), 0 = dull worn
    /// tape (~1 kHz low-pass). Cached into a one-pole coefficient via `didSet`.
    public var tone: Float = 0.8 { didSet { toneG = Self.toneCoefficient(tone, sr) } }

    private let sr: Float
    private let left: EchoelDelayLine
    private let right: EchoelDelayLine
    private let wowLFO: EchoelLFO
    private let flutterLFO: EchoelLFO
    private let baseSamples: Float
    private let maxWowSamples: Float
    private let maxFlutterSamples: Float
    private var lpL: Float = 0
    private var lpR: Float = 0
    private var toneG: Float = 1

    public init(sampleRate: Float = 48000) {
        self.sr = sampleRate
        // 50 ms line comfortably holds the 6 ms base + ±4.6 ms modulation.
        self.left = EchoelDelayLine(maxDelaySeconds: 0.05, sampleRate: sampleRate)
        self.right = EchoelDelayLine(maxDelaySeconds: 0.05, sampleRate: sampleRate)
        self.wowLFO = EchoelLFO(sampleRate: sampleRate)
        self.flutterLFO = EchoelLFO(sampleRate: sampleRate)
        wowLFO.rate = 0.6;     wowLFO.depth = 1.0;     wowLFO.waveform = .sine
        flutterLFO.rate = 6.5; flutterLFO.depth = 1.0; flutterLFO.waveform = .triangle
        self.baseSamples = 0.006 * sampleRate          // ~6 ms read tap
        self.maxWowSamples = 0.004 * sampleRate        // ±4 ms slow drift
        self.maxFlutterSamples = 0.0006 * sampleRate   // ±0.6 ms fast jitter
        self.toneG = Self.toneCoefficient(tone, sampleRate)
    }

    /// Map `tone` [0…1] → one-pole low-pass coefficient. 1 → ~16 kHz (≈bright),
    /// 0 → ~1 kHz (dull). Same shape family as `EchoelDelay.toneCoefficient`.
    private static func toneCoefficient(_ tone: Float, _ sr: Float) -> Float {
        let t = Swift.min(Swift.max(tone, 0), 1)
        let fc = 1000.0 * powf(16.0, t)
        let g = 1.0 - expf(-2.0 * Float.pi * fc / sr)
        return Swift.min(Swift.max(g, 0), 1)
    }

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        left.write(inL)
        right.write(inR)

        // Wow & flutter: modulate the read tap around the fixed base.
        let d = Swift.min(Swift.max(depth, 0), 1)
        var mod: Float = 0
        if d > 0 {
            mod = (wowLFO.next() * maxWowSamples + flutterLFO.next() * maxFlutterSamples) * d
        }
        let tap = Swift.max(1.0, baseSamples + mod)
        var yL = left.read(delaySamples: tap)
        var yR = right.read(delaySamples: tap)

        // Tape saturation (soft tanh with makeup so level stays roughly constant).
        let sat = Swift.min(Swift.max(saturation, 0), 1)
        if sat > 0 {
            let k = 1.0 + sat * 3.0
            let comp = 1.0 / (1.0 + sat * 1.2)
            yL = tanhf(yL * k) * comp
            yR = tanhf(yR * k) * comp
        }

        // High-frequency loss (worn-tape dull). Tiny DC keeps the decaying state
        // out of the denormal range (crackle on silence), inaudible at 1e-20.
        let g = toneG
        if g < 0.999 {
            lpL += g * (yL - lpL) + 1.0e-20
            lpR += g * (yR - lpR) + 1.0e-20
            yL = lpL
            yR = lpR
        }
        return (yL, yR)
    }

    public func reset() {
        left.reset()
        right.reset()
        wowLFO.reset()
        flutterLFO.reset()
        lpL = 0; lpR = 0
    }
}
