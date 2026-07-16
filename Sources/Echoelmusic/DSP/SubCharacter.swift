//
//  SubCharacter.swift
//  Echoelmusic — DSP
//
//  The EchoelBass "sub culture" shaper (founder 2026-07-16: "Sowas wie Subculture
//  von Babyaud.io in den EchoelBass"): a pure, per-sample psychoacoustic sub
//  character — IN-HOUSE, no third-party plugin/dependency (the Echoel way, like
//  the stretch engine). Two macro parameters:
//
//    presence [0…1] — how strongly OCTAVE harmonics (2f, and above the default
//                     midpoint also 4f) are stacked on the fundamental so the sub
//                     READS on phone/laptop speakers while the fundamental is FELT.
//    heat     [0…1] — tanh saturation drive, loudness-compensated so it changes
//                     CHARACTER, not level.
//
//  LAWS: octave harmonics ONLY (2f/4f) — never the 3rd (an octave-plus-fifth that
//  fought the chord: the "komische Töne" regression). Defaults (0.5/0.5) reproduce
//  the previously hard-coded SubBassVoice shaping EXACTLY (h2 0.32 · drive 1.05 ·
//  post 0.6), so an un-touched sub stays bit-identical. Pure Float math (sinf/
//  tanhf/expf-free) — audio-thread-safe, no alloc, testable on any CI host.
//  DSP/ placement rule: Foundation only, no Core/Sequencer types (AUv3-isolated).
//

import Foundation

public enum SubCharacter {

    /// Neutral defaults — exactly the sound SubBassVoice shipped before this
    /// existed (see mapping laws in `coefficients`).
    public static let defaultPresence: Float = 0.5
    public static let defaultHeat: Float = 0.5

    /// The derived per-sample coefficients for a (presence, heat) setting.
    /// Split out so the render can compute them ONCE per block (they change at
    /// control rate) and the tests can pin the mapping laws directly.
    public struct Coefficients: Equatable {
        public let h2Amp: Float    // 2nd harmonic (octave) amplitude
        public let h4Amp: Float    // 4th harmonic (double octave) amplitude
        public let drive: Float    // tanh input gain
        public let post: Float     // output scale (loudness-compensated)
    }

    /// Mapping laws (all pinned by tests):
    ///  - h2Amp = 0.64·presence            → 0.32 at the 0.5 default (today's value)
    ///  - h4Amp joins only ABOVE the default midpoint: 0.6·(presence−0.5)² for
    ///    presence > 0.5, else 0 — the default stays bit-identical, more "read"
    ///    is opt-in upward.
    ///  - drive = 0.6 + 0.9·heat           → 1.05 at the 0.5 default (today's value)
    ///  - post  = 0.6·tanhf(1.05)/tanhf(drive) → 0.6 at default; compensates the
    ///    saturation's peak growth so heat shifts harmonics, not loudness.
    /// Non-finite inputs clamp to the defaults' neutral behaviour.
    public static func coefficients(presence: Float, heat: Float) -> Coefficients {
        let p = presence.isFinite ? min(max(presence, 0), 1) : defaultPresence
        let h = heat.isFinite ? min(max(heat, 0), 1) : defaultHeat
        let h2 = 0.64 * p
        let over = max(0, p - 0.5)
        let h4 = 0.6 * over * over
        let drive = 0.6 + 0.9 * h
        let post = 0.6 * tanhf(1.05) / tanhf(drive)
        return Coefficients(h2Amp: h2, h4Amp: h4, drive: drive, post: post)
    }

    /// Shape ONE sub sample from the fundamental's phase accumulator (radians).
    /// Pure arithmetic + sinf/tanhf — safe inside a render block. `phase` may be
    /// any finite value; a non-finite phase yields silence (0), never NaN out.
    @inline(__always)
    public static func sample(phase: Float, coefficients c: Coefficients) -> Float {
        guard phase.isFinite else { return 0 }
        let h1 = sinf(phase)
        let h2 = sinf(2 * phase) * c.h2Amp
        let h4 = sinf(4 * phase) * c.h4Amp
        return tanhf((h1 + h2 + h4) * c.drive) * c.post
    }
}
