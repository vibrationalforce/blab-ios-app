// ChannelInsertFX.swift
// Echoel — a small, audio-thread-safe per-channel insert effect: a resonant
// biquad filter (low-pass / high-pass / off) followed by a soft saturator
// (drive). Pure value type, Foundation-only, ZERO allocation in `process` — so it
// is unit-testable off the audio thread AND safe to run inside a voice render
// block (no malloc / locks / ObjC / GCD). One instance holds the two-sample
// biquad state per channel.
//
// Coefficients use the RBJ "Audio EQ Cookbook" forms. `setParams` recomputes the
// coefficients (call from the control thread or once per block — NOT per sample).
// `process` is the hot path: a handful of multiply-adds + one tanhf.

import Foundation

public struct ChannelInsertFX: Sendable, Equatable {

    public enum FilterType: Int, Codable, Sendable, CaseIterable {
        case off, lowPass, highPass
        public var label: String {
            switch self {
            case .off:      return "Off"
            case .lowPass:  return "Low-pass"
            case .highPass: return "High-pass"
            }
        }
    }

    // MARK: Parameters (control plane)
    public private(set) var type: FilterType
    public private(set) var cutoffHz: Float
    public private(set) var resonance: Float   // Q, ~0.5…8
    public private(set) var drive: Float        // 0 = clean … 1 = full saturation
    public private(set) var sampleRate: Float

    // MARK: Biquad coefficients (normalized, a0 == 1)
    private var b0: Float = 1, b1: Float = 0, b2: Float = 0
    private var a1: Float = 0, a2: Float = 0

    // MARK: Biquad state (Direct Form I)
    private var x1: Float = 0, x2: Float = 0
    private var y1: Float = 0, y2: Float = 0

    public init(type: FilterType = .off, cutoffHz: Float = 1200,
                resonance: Float = 0.707, drive: Float = 0,
                sampleRate: Float = 48_000) {
        self.type = type
        self.cutoffHz = cutoffHz
        self.resonance = resonance
        self.drive = drive
        self.sampleRate = sampleRate
        recompute()
    }

    // MARK: Control-plane updates

    public mutating func setParams(type: FilterType, cutoffHz: Float,
                                   resonance: Float, drive: Float) {
        self.type = type
        self.cutoffHz = cutoffHz
        self.resonance = resonance
        self.drive = drive
        recompute()
    }

    public mutating func setSampleRate(_ sr: Float) {
        guard sr > 0, sr.isFinite, sr != sampleRate else { return }
        sampleRate = sr
        recompute()
    }

    /// Clear the filter memory (e.g. when a channel restarts) to avoid a tail.
    public mutating func reset() { x1 = 0; x2 = 0; y1 = 0; y2 = 0 }

    private mutating func recompute() {
        // Clamp to a sane, stable range.
        let sr = sampleRate > 0 && sampleRate.isFinite ? sampleRate : 48_000
        let nyq = sr * 0.5
        let fc = Swift.min(Swift.max(cutoffHz.isFinite ? cutoffHz : 1000, 20), nyq * 0.99)
        let q  = Swift.min(Swift.max(resonance.isFinite ? resonance : 0.707, 0.3), 12)

        guard type != .off else { b0 = 1; b1 = 0; b2 = 0; a1 = 0; a2 = 0; return }

        let w0 = 2 * Float.pi * fc / sr
        let cosw = cosf(w0)
        let sinw = sinf(w0)
        let alpha = sinw / (2 * q)
        let a0 = 1 + alpha

        switch type {
        case .lowPass:
            b0 = (1 - cosw) / 2
            b1 = 1 - cosw
            b2 = (1 - cosw) / 2
        case .highPass:
            b0 = (1 + cosw) / 2
            b1 = -(1 + cosw)
            b2 = (1 + cosw) / 2
        case .off:
            break
        }
        let na1: Float = -2 * cosw
        let na2: Float = 1 - alpha
        // Normalize by a0.
        b0 /= a0; b1 /= a0; b2 /= a0
        a1 = na1 / a0; a2 = na2 / a0
    }

    // MARK: Hot path (audio thread) — process one sample, no allocation.

    public mutating func process(_ x: Float) -> Float {
        var y = x
        if type != .off {
            // Direct Form I biquad.
            y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            if y.isFinite {
                // Flush denormals in the recursive state.
                if y1 > -1e-20 && y1 < 1e-20 { y1 = 0 }
                if y2 > -1e-20 && y2 < 1e-20 { y2 = 0 }
            } else {
                // SELF-HEAL. A biquad is a recursive accumulator, so one NaN or ±inf
                // otherwise latches this filter forever. The denormal test above
                // cannot clear it: every comparison against NaN is false, and ±inf
                // fails both bounds too.
                //
                // Defence-in-depth, not a fix for a known live bug. Of the three
                // owners — `PolySynthVoice`, `SubBassVoice`, `SamplerVoice` — only
                // `SamplerVoice` has an input that can actually arrive non-finite
                // (user-imported audio, unchecked on the import path), and it already
                // resets per trigger, so it would have recovered at the next hit.
                // (⛔ A fourth owner, `DrumSynthVoice`, was named here and could NOT
                // recover; it was deleted with #167, founder 2026-07-27.)
                // What this DOES change is
                // `PolySynthVoice` and `SubBassVoice`, which reset only on an
                // off→on FX transition — there a latched filter would have survived
                // until the user toggled the effect off and back on.
                //
                // Zeroing the INPUT history as well is the point: `x` itself may be
                // the non-finite value, and leaving it in `x1`/`x2` would re-poison
                // the next two samples through the feed-forward path. Note that
                // half-fixing this (clearing only `y1`/`y2`) does NOT show up as a
                // non-finite output — the branch simply re-fires and emits 0 — so
                // the test for it asserts sample VALUES against a fresh filter.
                x1 = 0; x2 = 0; y1 = 0; y2 = 0
                y = 0
            }
        }
        if drive > 0 {
            // Soft saturation: blend dry→tanh by drive; pre-gain adds harmonics.
            let d = Swift.min(Swift.max(drive, 0), 1)
            let pre = 1 + d * 4
            let sat = tanhf(y * pre)
            y = y * (1 - d) + sat * d
        }
        return y
    }
}
