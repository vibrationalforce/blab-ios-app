// VoiceTimbreProfiler.swift
// Echoelmusic — DSP (voice → timbre profile)
//
// The one pure core of the EchoelVoice plan (`scratchpads/PLAN_ECHOEL_VOICE.md`, #590):
// a voice is MEASURED and distilled, never recorded. Per analysis frame it samples the
// magnitude spectrum at k·F0 (k = 1…harmonicCount, linear bin interpolation, 0 above
// Nyquist); over a take it keeps the MEDIAN per harmonic across voiced frames only, and
// max-normalizes into the tap vector the engine's custom-timbre socket accepts — the
// SHIPPED path is `PolySynthVoice.applyVoiceProfile` → `EchoelPolyDDSP.setCustomTimbre`
// (#591a staging); `EchoelDDSP.loadTimbreProfile` shares the same contract but has
// zero production callers (kept deliberately, its own doc says for whom).
// What leaves this type is a spectral envelope — parameters, not audio — which is what
// lets the capture flow ship under the mic-permission promise "Audio is not recorded".
// It cannot store or replay speech: no phases, no time structure, one envelope.
//
// Inputs come from the two existing halves it joins: `EchoelRealFFT.forward` (whose
// `magnitudes` array is `size/2` bins at `sampleRate/size` Hz spacing — the bin maths
// below derives `fftSize = 2 × magnitudes.count` from exactly that contract) and
// `VoiceAnalyzer` (F0 + voicing). CONTROL THREAD ONLY: `add` appends to an array; this
// type must never be called from a render block.
//
// ⛔ The sentence that stood here — "the default tap count mirrors `EchoelDDSP.init`'s
// default (64) … the defaults are kept equal" — was the false-rationale comment class
// (#593c review F6): the CONSUMING engine is the poly pool at `harmonicCount: 32`
// (the 10.76.49 cap), not the DDSP default. The true relationship is an INEQUALITY,
// not equality: the profiler must measure AT LEAST the socket's count (64 ≥ 32 —
// `applyVoiceProfile` refuses shorter, accepts longer and reads the first 32), and
// the drift guard is behavioral on real instances
// (`TheVoiceProfileIsMeasuredNotRecordedTests.testTheProfileFitsTheEngineSocket`).
// Raising the ENGINE's count is the dangerous direction — it silently shortens every
// already-saved 32-tap voice patch under the socket; the save flow's floor check
// (`voiceProfileTapFloor`, #593c) keeps such halves inert-but-preserved.

import Foundation

public struct VoiceTimbreProfiler: Sendable {

    /// Number of harmonic taps measured — must be ≥ the consuming engine's
    /// `harmonicCount` (the socket refuses a shorter vector, accepts a longer one and
    /// reads its first `harmonicCount` taps). An INEQUALITY, not equality — the header
    /// ⛔ has the full retraction: profiler default 64 ≥ the poly socket's 32. (⛔ This
    /// line said "the defaults are kept equal" for two commits AFTER that header
    /// retraction landed — the second spelling at the declaration, the exact class
    /// the retraction itself names. Found by the pre-release sweep.)
    public let harmonicCount: Int

    /// Frames accepted so far (voiced AND measurable). Drives a capture progress UI.
    public private(set) var voicedFrameCount: Int = 0

    /// Hard memory cap on accumulated frames (~4096 × 64 floats ≈ 1 MB). A 10 s take at
    /// a 30 Hz control rate is ~300 frames; hitting the cap means a runaway caller, and
    /// further frames are ignored rather than growing without bound.
    public static let maxFrames = 4096

    private var frames: [[Float]] = []

    public init(harmonicCount: Int = 64) {
        self.harmonicCount = max(1, harmonicCount)
    }

    /// Sample the magnitude spectrum at k·f0 (k = 1…harmonicCount) with linear bin
    /// interpolation. Taps at or above Nyquist (or past the last interpolable bin pair)
    /// are 0 — present, never missing, so the vector length is always `harmonicCount`.
    /// Returns nil when the frame cannot be measured at all (non-finite or non-positive
    /// f0/sampleRate, a fundamental at or above Nyquist, or a degenerate spectrum).
    /// A non-finite magnitude BIN is read as 0 (the engineering.md boundary rule): one
    /// bad bin must not poison the whole profile.
    public static func harmonicAmplitudes(
        magnitudes: [Float], f0: Float, sampleRate: Float, harmonicCount: Int
    ) -> [Float]? {
        let count = magnitudes.count
        guard count >= 8, harmonicCount >= 1,
              f0.isFinite, f0 > 0,
              sampleRate.isFinite, sampleRate > 0,
              f0 < sampleRate * 0.5 else { return nil }

        // EchoelRealFFT contract: `magnitudes` is size/2 bins, bin i at i·sr/size Hz.
        let binHz = sampleRate / Float(2 * count)
        var out = [Float](repeating: 0, count: harmonicCount)
        for k in 1...harmonicCount {
            let binF = (f0 * Float(k)) / binHz
            // Needs bins ⌊binF⌋ and ⌊binF⌋+1; past the last pair the tap stays 0
            // (this bound also lands just under Nyquist, matching "0 above Nyquist").
            // Index safety relies on Float(count-1) being exact, true for count ≤ 2^24 —
            // comfortably above any real FFT size here.
            guard binF >= 0, binF < Float(count - 1) else { continue }
            let lower = Int(binF)
            let frac = binF - Float(lower)
            let a = magnitudes[lower], b = magnitudes[lower + 1]
            // NaN-safe by the isFinite guard; max is spelled in the NaN-safe argument
            // order anyway (`max(0, NaN)` is 0) so the banned order is never modelled.
            let sa = a.isFinite ? Swift.max(0, a) : 0
            let sb = b.isFinite ? Swift.max(0, b) : 0
            out[k - 1] = sa + (sb - sa) * frac
        }
        return out
    }

    /// Accumulate one analysis frame. Only frames that are BOTH voiced and measurable
    /// count — breath gaps and consonants are part of toning, and averaging unvoiced
    /// noise in would drag every harmonic toward the noise floor.
    public mutating func add(magnitudes: [Float], f0: Float, voiced: Bool, sampleRate: Float) {
        guard voiced, frames.count < Self.maxFrames,
              let amps = Self.harmonicAmplitudes(magnitudes: magnitudes, f0: f0,
                                                 sampleRate: sampleRate,
                                                 harmonicCount: harmonicCount)
        else { return }
        frames.append(amps)
        voicedFrameCount = frames.count
    }

    /// The distilled profile: median per harmonic over the voiced frames (robust against
    /// glitch frames — one outlier cannot re-scale the envelope the way a mean would),
    /// max-normalized to 1 at the strongest tap. Returns nil while nothing voiced was
    /// added, or when every tap is 0 — silence is not a timbre.
    public func profile() -> [Float]? {
        guard !frames.isEmpty else { return nil }
        var out = [Float](repeating: 0, count: harmonicCount)
        var column = [Float](repeating: 0, count: frames.count)
        for h in 0..<harmonicCount {
            for (i, frame) in frames.enumerated() { column[i] = frame[h] }
            column.sort()
            let n = column.count
            out[h] = n % 2 == 1
                ? column[n / 2]
                : (column[n / 2 - 1] + column[n / 2]) * 0.5
        }
        guard let peak = out.max(), peak > 0 else { return nil }
        for i in 0..<harmonicCount { out[i] /= peak }
        return out
    }

    /// Discard all accumulated frames (a new take starts clean).
    public mutating func reset() {
        frames.removeAll(keepingCapacity: true)
        voicedFrameCount = 0
    }
}
