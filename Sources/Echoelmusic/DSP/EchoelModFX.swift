import Foundation

/// Modulation effects family, all audio-thread safe (no allocation or locks in
/// the hot loop) and built on the shared `EchoelDelayLine` / `EchoelLFO`
/// primitives. Stereo width comes from driving the right channel with the
/// inverted LFO value — a deterministic 180° offset, no extra LFO state.
///
/// - `EchoelChorus`  — medium modulated delay (thickening, ensemble).
/// - `EchoelFlanger` — short modulated delay with feedback (jet/comb sweep).
/// - `EchoelPhaser`  — cascaded first-order allpass notch sweep with feedback.
/// - `EchoelTremolo` — amplitude modulation with optional auto-pan.
///
/// References: Julius O. Smith III, "Physical Audio Signal Processing"
/// (allpass / comb filters); Pirkle, "Designing Audio Effect Plugins".

// MARK: - Chorus

public final class EchoelChorus: @unchecked Sendable {

    /// LFO rate in Hz [0.05, 8].
    public var rate: Float = 0.6 { didSet { lfo.rate = clampRate(rate) } }
    /// Modulation depth [0, 1].
    public var depth: Float = 0.5
    /// Wet/dry blend [0, 1].
    public var mix: Float = 0.5
    /// Centre delay in milliseconds.
    public var baseDelayMs: Float = 12
    /// Peak modulation excursion in milliseconds at depth 1.
    public var spreadMs: Float = 7

    private let sr: Float
    private let dlL: EchoelDelayLine
    private let dlR: EchoelDelayLine
    private let lfo: EchoelLFO

    public init(sampleRate: Float = 48000) {
        self.sr = sampleRate
        self.dlL = EchoelDelayLine(maxDelaySeconds: 0.05, sampleRate: sampleRate)
        self.dlR = EchoelDelayLine(maxDelaySeconds: 0.05, sampleRate: sampleRate)
        self.lfo = EchoelLFO(sampleRate: sampleRate)
        lfo.rate = 0.6; lfo.depth = 1.0; lfo.waveform = .sine
    }

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        let m = clamp01(mix)
        let v = lfo.next()                       // [-1, 1]
        let exc = depth * spreadMs
        let dL = msToSamples(baseDelayMs + exc * v)
        let dR = msToSamples(baseDelayMs - exc * v)   // inverted → stereo width
        let yL = dlL.readAllpass(delaySamples: dL)
        let yR = dlR.readAllpass(delaySamples: dR)
        dlL.write(inL)
        dlR.write(inR)
        return (inL * (1 - m) + yL * m, inR * (1 - m) + yR * m)
    }

    public func reset() { dlL.reset(); dlR.reset(); lfo.reset() }

    @inline(__always) private func msToSamples(_ ms: Float) -> Float {
        Swift.max(1.0, ms * 0.001 * sr)
    }
}

// MARK: - Flanger

public final class EchoelFlanger: @unchecked Sendable {

    public var rate: Float = 0.25 { didSet { lfo.rate = clampRate(rate) } }
    public var depth: Float = 0.7
    public var mix: Float = 0.5
    /// Feedback (resonance) [-0.95, 0.95].
    public var feedback: Float = 0.5
    public var baseDelayMs: Float = 3
    public var spreadMs: Float = 2

    private let sr: Float
    private let dlL: EchoelDelayLine
    private let dlR: EchoelDelayLine
    private let lfo: EchoelLFO
    private var fbL: Float = 0
    private var fbR: Float = 0

    public init(sampleRate: Float = 48000) {
        self.sr = sampleRate
        self.dlL = EchoelDelayLine(maxDelaySeconds: 0.02, sampleRate: sampleRate)
        self.dlR = EchoelDelayLine(maxDelaySeconds: 0.02, sampleRate: sampleRate)
        self.lfo = EchoelLFO(sampleRate: sampleRate)
        lfo.rate = 0.25; lfo.depth = 1.0; lfo.waveform = .triangle
    }

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        let m = clamp01(mix)
        let fb = Swift.min(Swift.max(feedback, -0.95), 0.95)
        let v = lfo.next()
        let exc = depth * spreadMs
        let dL = msToSamples(baseDelayMs + exc * v)
        let dR = msToSamples(baseDelayMs - exc * v)
        let yL = dlL.readAllpass(delaySamples: dL)
        let yR = dlR.readAllpass(delaySamples: dR)
        dlL.write(inL + yL * fb)
        dlR.write(inR + yR * fb)
        fbL = yL; fbR = yR
        return (inL * (1 - m) + yL * m, inR * (1 - m) + yR * m)
    }

    public func reset() { dlL.reset(); dlR.reset(); lfo.reset(); fbL = 0; fbR = 0 }

    @inline(__always) private func msToSamples(_ ms: Float) -> Float {
        Swift.max(1.0, ms * 0.001 * sr)
    }
}

// MARK: - Phaser

public final class EchoelPhaser: @unchecked Sendable {

    public var rate: Float = 0.4 { didSet { lfo.rate = clampRate(rate) } }
    public var depth: Float = 0.7
    public var mix: Float = 0.5
    public var feedback: Float = 0.3
    /// Sweep range in Hz.
    public var minHz: Float = 300
    public var maxHz: Float = 2200

    private let sr: Float
    private let stages: Int
    private var zL: [Float]
    private var zR: [Float]
    private var lastL: Float = 0
    private var lastR: Float = 0
    private let lfo: EchoelLFO

    public init(sampleRate: Float = 48000, stages: Int = 6) {
        self.sr = sampleRate
        self.stages = Swift.max(2, stages)
        self.zL = [Float](repeating: 0, count: self.stages)
        self.zR = [Float](repeating: 0, count: self.stages)
        self.lfo = EchoelLFO(sampleRate: sampleRate)
        lfo.rate = 0.4; lfo.depth = 1.0; lfo.waveform = .sine
    }

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        let m = clamp01(mix)
        let fb = Swift.min(Swift.max(feedback, 0.0), 0.95)
        // One LFO value, inverted for the right channel.
        let u = (lfo.next() * 0.5 + 0.5)         // [0, 1]
        let uR = 1.0 - u
        let aL = allpassCoeff(forUnipolar: u)
        let aR = allpassCoeff(forUnipolar: uR)

        let wetL = processChannel(inL, coeff: aL, fb: fb, z: &zL, last: &lastL)
        let wetR = processChannel(inR, coeff: aR, fb: fb, z: &zR, last: &lastR)
        return (inL * (1 - m) + wetL * m, inR * (1 - m) + wetR * m)
    }

    public func reset() {
        for i in 0..<stages { zL[i] = 0; zR[i] = 0 }
        lastL = 0; lastR = 0; lfo.reset()
    }

    @inline(__always)
    private func processChannel(_ x: Float, coeff a: Float, fb: Float,
                                z: inout [Float], last: inout Float) -> Float {
        var s = x + last * fb
        for i in 0..<stages {
            let y = a * s + z[i]
            z[i] = s - a * y
            s = y
        }
        last = s
        return s
    }

    /// First-order allpass coefficient for a break frequency set by the sweep.
    @inline(__always)
    private func allpassCoeff(forUnipolar u: Float) -> Float {
        let lo = Swift.max(20.0, minHz)
        let hi = Swift.min(sr * 0.45, Swift.max(lo + 1, maxHz))
        let modDepth = clamp01(depth)
        let fc = lo + (hi - lo) * (u * modDepth + (1 - modDepth) * 0.5)
        let t = tanf(Float.pi * fc / sr)
        return (t - 1.0) / (t + 1.0)
    }
}

// MARK: - Tremolo

public final class EchoelTremolo: @unchecked Sendable {

    public var rate: Float = 5.0 { didSet { lfo.rate = clampRate(rate) } }
    /// Modulation depth [0, 1] (0 = no effect, 1 = full on/off).
    public var depth: Float = 0.5
    /// When true, L and R modulate in anti-phase (auto-pan).
    public var stereoPan: Bool = false

    private let lfo: EchoelLFO

    public init(sampleRate: Float = 48000) {
        self.lfo = EchoelLFO(sampleRate: sampleRate)
        lfo.rate = 5.0; lfo.depth = 1.0; lfo.waveform = .sine
    }

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        let d = clamp01(depth)
        let u = lfo.next() * 0.5 + 0.5           // [0, 1]
        let gL = 1.0 - d * (1.0 - u)
        let gR = stereoPan ? (1.0 - d * u) : gL
        return (inL * gL, inR * gR)
    }

    public func reset() { lfo.reset() }
}

// MARK: - Shared helpers

@inline(__always) private func clamp01(_ x: Float) -> Float {
    Swift.min(Swift.max(x, 0.0), 1.0)
}
@inline(__always) private func clampRate(_ x: Float) -> Float {
    Swift.min(Swift.max(x, 0.05), 8.0)
}
