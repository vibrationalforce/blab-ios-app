// BioColorGradeParams.swift
// Echoelmusic — Studio
//
// PURE bio→colour-grade uniform mapping (science-first, flash-safe). Maps a bio
// snapshot to a small set of grade uniforms consumed by the generative-visual grade
// pass (MetalBioView compiles its shader inline at runtime). All Foundation math — no
// Metal, no AVFoundation — so the mapping + its flash-rate clamp are unit-tested on
// every platform. The struct layout must match the shader's uniform struct byte-for-byte.

import Foundation

/// Grade uniforms fed to the Metal pass. Neutral (identity) defaults so an un-graded
/// clip looks untouched.
public struct BioColorGradeParams: Sendable, Equatable {
    /// Exposure multiplier (0.5…1.5, 1 = neutral).
    public var exposure: Float
    /// Saturation (0…2, 1 = neutral).
    public var saturation: Float
    /// Contrast (0.5…1.5, 1 = neutral).
    public var contrast: Float
    /// White-balance temperature shift (−1 cool … +1 warm, 0 = neutral).
    public var temperature: Float
    /// Hue rotation in turns (−0.5…0.5, 0 = neutral).
    public var hue: Float
    /// Vignette strength (0…1, 0 = off) — the slow pulse channel.
    public var vignette: Float

    public static let neutral = BioColorGradeParams(
        exposure: 1, saturation: 1, contrast: 1, temperature: 0, hue: 0, vignette: 0)

    public init(exposure: Float, saturation: Float, contrast: Float,
                temperature: Float, hue: Float, vignette: Float) {
        self.exposure = exposure
        self.saturation = saturation
        self.contrast = contrast
        self.temperature = temperature
        self.hue = hue
        self.vignette = vignette
    }

    /// Map a bio snapshot to grade uniforms, scaled by `intensity` (0 = neutral, 1 =
    /// full). Coherence→saturation/warmth, HRV→exposure/contrast, breath phase→gentle
    /// brightness, heart rate→vignette pulse depth. All outputs clamped neutral-safe.
    public static func from(coherence: Float, hrvNormalized: Float,
                            breathPhase: Float, heartRateBPM: Float,
                            intensity: Float = 1) -> BioColorGradeParams {
        let k = clampf(intensity, 0, 1)
        let coh = clampf(coherence, 0, 1)
        let hrv = clampf(hrvNormalized, 0, 1)
        let breath = clampf(breathPhase, 0, 1)

        // Coherence lifts saturation + warmth; HRV lifts exposure + contrast.
        let saturation = mix(1, 0.7 + 0.6 * coh, k)               // 0.7…1.3
        let temperature = mix(0, (coh - 0.5) * 0.8, k)            // −0.4…+0.4
        let exposure = mix(1, 0.9 + 0.3 * hrv, k)                 // 0.9…1.2
        let contrast = mix(1, 0.9 + 0.25 * hrv, k)               // 0.9…1.15
        // Breath phase → slow brightness breathing (0…1 → small +/- on exposure).
        let breathLift = sin(breath * 2 * Float.pi) * 0.05 * k
        // Heart rate → vignette pulse DEPTH only (the pulse rate itself is applied
        // on-device at ≤3 Hz; here we only set how deep it can go).
        let hr = clampf((heartRateBPM - 50) / 100, 0, 1)          // 50…150 bpm → 0…1
        let vignette = mix(0, 0.15 + 0.25 * hr, k)               // 0…0.4

        return BioColorGradeParams(
            exposure: clampf(exposure + breathLift, 0.5, 1.5),
            saturation: clampf(saturation, 0, 2),
            contrast: clampf(contrast, 0.5, 1.5),
            temperature: clampf(temperature, -1, 1),
            hue: 0,
            vignette: clampf(vignette, 0, 1))
    }

    /// Flash-safety clamp (W3C WCAG epilepsy ≤ 3 Hz): limit how far any channel may
    /// move from the previous frame given the frame interval, so no luminance-
    /// affecting parameter oscillates faster than `maxHz`. Pure — the device pass
    /// feeds `previous` + real `dt`; here it's deterministic and testable.
    public func flashLimited(from previous: BioColorGradeParams,
                             dt: Float, maxHz: Float = 3) -> BioColorGradeParams {
        guard dt > 0, maxHz > 0 else { return self }
        // One full swing takes ≥ 1/(2·maxHz) s, so cap |Δ| per frame accordingly.
        let maxDelta = dt * 2 * maxHz
        func lim(_ target: Float, _ prev: Float) -> Float {
            let d = target - prev
            return prev + Swift.max(-maxDelta, Swift.min(maxDelta, d))
        }
        return BioColorGradeParams(
            exposure: lim(exposure, previous.exposure),
            saturation: lim(saturation, previous.saturation),
            contrast: lim(contrast, previous.contrast),
            temperature: lim(temperature, previous.temperature),
            hue: lim(hue, previous.hue),
            vignette: lim(vignette, previous.vignette))
    }

    // MARK: - Pure math
    private static func clampf(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        Swift.max(lo, Swift.min(hi, v.isFinite ? v : lo))
    }
    private static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
}
