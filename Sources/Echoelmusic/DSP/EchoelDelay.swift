import Foundation

/// Musical stereo delay built on `EchoelDelayLine`. Three voicings share one
/// signal path:
/// - `.digital`  — clean repeats.
/// - `.tape`     — wow/flutter pitch modulation + soft saturation in the
///                 feedback path (Echoplex/Space-Echo character).
/// - `.pingPong` — feedback crosses L↔R for a bouncing stereo image.
///
/// A one-pole low-pass in the feedback loop ("tone") darkens successive repeats
/// the way analog delays do, and keeps high feedback stable. No allocation,
/// no locks — audio-thread safe.
public final class EchoelDelay: @unchecked Sendable {

    // MARK: - Mode

    public enum Mode: String, CaseIterable, Sendable {
        case digital
        case tape
        case pingPong
    }

    // MARK: - Parameters

    /// Voicing of the delay.
    public var mode: Mode = .digital

    /// Wet/dry blend [0 = dry, 1 = wet].
    public var mix: Float = 0.30

    /// Feedback amount [0, 0.95] (clamped for stability).
    public var feedback: Float = 0.40

    /// Delay time in seconds [0.001, maxDelaySeconds].
    public var timeSeconds: Float = 0.375

    /// Stereo time offset [0, 1] — right tap detunes up to ±25 ms for width.
    public var spread: Float = 0.0

    /// Feedback tone [0 = dark, 1 = bright].
    public var tone: Float = 0.6

    /// Tape wow/flutter depth [0, 1] (only audible in `.tape`).
    public var wow: Float = 0.0

    /// Tape feedback saturation [0, 1] (only audible in `.tape`).
    public var drive: Float = 0.0

    // MARK: - State

    private let sr: Float
    private let left: EchoelDelayLine
    private let right: EchoelDelayLine

    /// Smoothed delay time (seconds). `timeSeconds` is the control-plane target;
    /// the audio path glides toward it (~40 ms one-pole) so a preset/character
    /// switch slides the read tap instead of jumping it — a jump is a click,
    /// the glide is the analog "repitch" a tape delay makes. Snapped to the
    /// target on `reset()` (fresh/empty line has nothing to repitch).
    private var timeSmoothed: Float = 0.375
    private let timeGlide: Float

    // one-pole feedback dampers (per channel)
    private var lpL: Float = 0
    private var lpR: Float = 0

    // tape modulators
    private let wowLFO: EchoelLFO
    private let flutterLFO: EchoelLFO
    private let maxWowSamples: Float
    private let maxFlutterSamples: Float

    // MARK: - Init

    public init(maxDelaySeconds: Float = 2.0, sampleRate: Float = 48000) {
        self.sr = sampleRate
        self.left  = EchoelDelayLine(maxDelaySeconds: maxDelaySeconds, sampleRate: sampleRate)
        self.right = EchoelDelayLine(maxDelaySeconds: maxDelaySeconds, sampleRate: sampleRate)

        self.wowLFO = EchoelLFO(sampleRate: sampleRate)
        self.flutterLFO = EchoelLFO(sampleRate: sampleRate)
        wowLFO.rate = 0.6;    wowLFO.depth = 1.0;    wowLFO.waveform = .sine
        flutterLFO.rate = 6.5; flutterLFO.depth = 1.0; flutterLFO.waveform = .triangle

        self.maxWowSamples = 0.004 * sampleRate      // ±4 ms slow drift
        self.maxFlutterSamples = 0.0006 * sampleRate // ±0.6 ms fast jitter

        // One-pole coefficient for a ~40 ms time-glide constant.
        self.timeGlide = 1.0 - expf(-1.0 / (0.040 * sampleRate))
        self.timeSmoothed = timeSeconds
    }

    // MARK: - Process

    /// Process one stereo frame. Audio-thread safe.
    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        let fb = Swift.min(Swift.max(feedback, 0.0), 0.95)
        let m  = Swift.min(Swift.max(mix, 0.0), 1.0)

        // Glide the audible time toward the control-plane target (declick).
        timeSmoothed += timeGlide * (timeSeconds - timeSmoothed)

        // Base delay in samples, with optional stereo spread on the right tap.
        let baseL = Swift.max(1.0, timeSmoothed * sr)
        let spreadSamples = spread * 0.025 * sr
        let baseR = Swift.max(1.0, baseL + spreadSamples)

        // Tape pitch modulation (skip work entirely when not in tape mode).
        var modSamples: Float = 0
        if mode == .tape && wow > 0 {
            modSamples = (wowLFO.next() * maxWowSamples + flutterLFO.next() * maxFlutterSamples) * wow
        }

        let yL = left.read(delaySamples: baseL + modSamples)
        let yR = right.read(delaySamples: baseR + modSamples)

        // Feedback routing: ping-pong crosses channels.
        let rawFbL: Float
        let rawFbR: Float
        if mode == .pingPong {
            rawFbL = yR
            rawFbR = yL
        } else {
            rawFbL = yL
            rawFbR = yR
        }

        // One-pole low-pass damping in the feedback path ("tone").
        // + tiny DC keeps the decaying state out of the denormal range (crackle on
        // the delay tail when input goes silent); 1e-20 is inaudible.
        let g = toneCoefficient()
        lpL += g * (rawFbL - lpL) + 1.0e-20
        lpR += g * (rawFbR - lpR) + 1.0e-20

        var wL = inL + lpL * fb
        var wR = inR + lpR * fb

        // Tape saturation in the feedback path.
        if mode == .tape && drive > 0 {
            let k = 1.0 + drive * 3.0
            wL = tanhf(wL * k)
            wR = tanhf(wR * k)
        }

        left.write(wL)
        right.write(wR)

        let outL = inL * (1.0 - m) + yL * m
        let outR = inR * (1.0 - m) + yR * m
        return (outL, outR)
    }

    /// Process separate L/R buffers in place.
    public func processBuffer(left bufL: inout [Float], right bufR: inout [Float], frameCount: Int) {
        let n = Swift.min(frameCount, Swift.min(bufL.count, bufR.count))
        for i in 0..<n {
            let (l, r) = processStereo(bufL[i], bufR[i])
            bufL[i] = l
            bufR[i] = r
        }
    }

    // MARK: - Reset

    public func reset() {
        left.reset()
        right.reset()
        lpL = 0; lpR = 0
        wowLFO.reset()
        flutterLFO.reset()
        timeSmoothed = timeSeconds   // empty line: snap, don't glide
    }

    // MARK: - Helpers

    /// Map `tone` [0,1] → one-pole low-pass coefficient. 0 → ~800 Hz (dark),
    /// 1 → ~16 kHz (bright).
    @inline(__always)
    private func toneCoefficient() -> Float {
        let fc = 800.0 * powf(20.0, Swift.min(Swift.max(tone, 0.0), 1.0))
        let g = 1.0 - expf(-2.0 * Float.pi * fc / sr)
        return Swift.min(Swift.max(g, 0.0), 1.0)
    }
}
