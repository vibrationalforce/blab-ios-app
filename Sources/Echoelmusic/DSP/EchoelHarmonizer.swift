import Foundation

/// Real-time pitch-shifting harmonizer — adds up to two fixed-interval harmony
/// voices above (or below) the dry signal. Audio-thread safe: pre-allocated
/// delay lines, no allocation or locks in the hot loop.
///
/// Method: the classic two-tap crossfading delay-line pitch shifter (Dattorro;
/// Smith, "Physical Audio Signal Processing"). Each harmony voice owns a delay
/// line whose read position drifts linearly at `(1 - ratio)` samples per sample,
/// producing a constant pitch ratio. A second tap, offset by half the window,
/// is crossfaded against the first with a raised-cosine window so the wrap
/// discontinuity (when a tap sweeps off the window edge) is masked. The two
/// windows sum to unity, so amplitude stays constant through the wrap.
///
/// This is a granular/delay-line shifter, not PSOLA — it is glitch-free and
/// cheap, with the mild "chorusing" smear characteristic of the technique,
/// which actually flatters a harmonizer (the harmony voices read as an ensemble
/// rather than sterile clones).
public final class EchoelHarmonizer: @unchecked Sendable {

    // MARK: - Control-plane parameters

    /// First harmony interval in semitones (default major third).
    public var interval1: Float = 4 { didSet { ratio1 = ratio(for: interval1) } }
    /// Second harmony interval in semitones (default perfect fifth).
    public var interval2: Float = 7 { didSet { ratio2 = ratio(for: interval2) } }
    /// Enable the second harmony voice.
    public var voice2Enabled: Bool = true
    /// Wet blend of the harmony voices into the output [0…1]. The dry signal is
    /// always passed at full level; this scales the *added* harmonies.
    public var mix: Float = 0.5

    // MARK: - State

    private let sr: Float
    private let windowSamples: Float
    private let halfWindow: Float
    private let dl1L: EchoelDelayLine
    private let dl1R: EchoelDelayLine
    private let dl2L: EchoelDelayLine
    private let dl2R: EchoelDelayLine
    private var phase1: Float = 0
    private var phase2: Float = 0
    private var ratio1: Float = 1
    private var ratio2: Float = 1

    public init(sampleRate: Float = 48000) {
        self.sr = sampleRate
        // ~50 ms window: long enough to keep the pitch artefacts low, short
        // enough to keep latency/smearing modest.
        let w = Swift.max(64.0, 0.050 * sampleRate)
        self.windowSamples = w
        self.halfWindow = w * 0.5
        // Line must hold the window plus a guard; 0.12 s is comfortably above 50 ms.
        self.dl1L = EchoelDelayLine(maxDelaySeconds: 0.12, sampleRate: sampleRate)
        self.dl1R = EchoelDelayLine(maxDelaySeconds: 0.12, sampleRate: sampleRate)
        self.dl2L = EchoelDelayLine(maxDelaySeconds: 0.12, sampleRate: sampleRate)
        self.dl2R = EchoelDelayLine(maxDelaySeconds: 0.12, sampleRate: sampleRate)
        self.ratio1 = ratio(for: interval1)
        self.ratio2 = ratio(for: interval2)
    }

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        // Write dry into every voice's line.
        dl1L.write(inL); dl1R.write(inR)
        dl2L.write(inL); dl2R.write(inR)

        let m = Swift.min(Swift.max(mix, 0.0), 1.0)
        let (v1L, v1R) = shiftVoice(ratio1, phase: &phase1, lL: dl1L, lR: dl1R)
        var harmL = v1L
        var harmR = v1R
        if voice2Enabled {
            let (v2L, v2R) = shiftVoice(ratio2, phase: &phase2, lL: dl2L, lR: dl2R)
            harmL += v2L
            harmR += v2R
        }
        // Dry stays full; harmonies added and scaled. The chain limiter (last
        // stage) catches the rare peak on dense material.
        let g = m * 0.5
        return (inL + harmL * g, inR + harmR * g)
    }

    public func reset() {
        dl1L.reset(); dl1R.reset(); dl2L.reset(); dl2R.reset()
        phase1 = 0; phase2 = 0
    }

    // MARK: - Helpers

    /// One pitch-shifted voice via two crossfaded taps. `phase` is the position
    /// of tap 1 within [0, window); tap 2 is half a window ahead.
    @inline(__always)
    private func shiftVoice(_ ratio: Float, phase: inout Float,
                            lL: EchoelDelayLine, lR: EchoelDelayLine) -> (Float, Float) {
        // Advance read position. ratio > 1 (up) → delay shrinks → step negative.
        phase += (1.0 - ratio)
        if phase >= windowSamples { phase -= windowSamples }
        if phase < 0 { phase += windowSamples }

        var phase2pos = phase + halfWindow
        if phase2pos >= windowSamples { phase2pos -= windowSamples }

        // Raised-cosine windows (0 at tap edges, 1 mid-window). g1 + g2 == 1.
        let g1 = 0.5 - 0.5 * cosf(2.0 * Float.pi * phase / windowSamples)
        let g2 = 1.0 - g1

        let d1 = phase + 1.0
        let d2 = phase2pos + 1.0
        let yL = lL.read(delaySamples: d1) * g1 + lL.read(delaySamples: d2) * g2
        let yR = lR.read(delaySamples: d1) * g1 + lR.read(delaySamples: d2) * g2
        return (yL, yR)
    }

    @inline(__always)
    private func ratio(for semitones: Float) -> Float {
        powf(2.0, semitones / 12.0)
    }
}
