//
//  BioVisualParams.swift
//  Echoelmusic — Studio (visual)
//
//  Rebuilt-new foundation for the bio-reactive visual engine (the honest
//  realization of the old "VisualForge" intent — science-visual, not esoterica).
//  ONE pure value type centralizes the body→image mapping so every renderer
//  (the live Metal ring view, and the richer Cymatics/Mandala GPU kernels next)
//  reads the SAME flash-safe parameters. Pure, Sendable, deterministic, fully
//  unit-tested — no Metal, no SwiftUI here.
//
//  Flash safety is baked in: pulse frequency is routed through FlashGuard (≤3 Hz
//  WCAG, 0 under Reduce Motion), so no renderer can strobe by construction.
//

import Foundation

/// The visual pattern a renderer draws. Each maps the same bio params differently.
public enum BioVisualPattern: String, CaseIterable, Sendable, Identifiable {
    /// Concentric heartbeat rings (the current live look).
    case rings
    /// Chladni / cymatics plate — sound made visible (real physics).
    case cymatics
    /// Radial mandala symmetry.
    case mandala

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rings:    return "Rings"
        case .cymatics: return "Cymatics"
        case .mandala:  return "Mandala"
        }
    }
}

/// Flash-safe visual parameters derived from one bio frame. Ranges are documented
/// per field; all are stable and renderer-agnostic.
public struct BioVisualParams: Sendable, Equatable {

    /// Which pattern to draw.
    public var pattern: BioVisualPattern
    /// Heartbeat pulse frequency in Hz — already flash-clamped (0…3 Hz; 0 = still).
    public var pulseHz: Double
    /// Hue [0…1]; coherence shifts red→cyan (calmer = cooler).
    ///
    /// ⛔ NO CONSUMER (#1116, measured). `MetalBioView` reads only `pulseHz` off this
    /// struct — it says so at both its `BioVisualParams.from` call and its `update()`
    /// call — and it takes its hue from the sounding TONE plus the VJ `hueShift`
    /// slider instead. So this value is computed on every frame and used by nothing.
    /// It is kept, not deleted, for the #527 reason: the struct is the ONE pure
    /// bio→visual mapping and a future surface (the external stage, a second renderer)
    /// is the natural consumer. **Do not quote it as a shipping mapping** — six website
    /// lines did exactly that until #1116 took them back.
    public var hue: Double
    /// Pattern complexity [0…1]; HRV drives ring count / Chladni order.
    public var complexity: Double
    /// Breath spread factor [~0.85…1.15]; the figure expands on the inhale.
    public var spread: Double
    /// Overall brightness/intensity [0…1]; coherence makes it fuller.
    public var intensity: Double

    public init(pattern: BioVisualPattern, pulseHz: Double, hue: Double,
                complexity: Double, spread: Double, intensity: Double) {
        self.pattern = pattern
        self.pulseHz = pulseHz
        self.hue = hue
        self.complexity = complexity
        self.spread = spread
        self.intensity = intensity
    }

    /// Neutral, still defaults (used when there is no live bio frame).
    public static let neutral = BioVisualParams(
        pattern: .rings, pulseHz: 0, hue: 0.2, complexity: 0.5, spread: 1.0, intensity: 0.5
    )

    /// Pure bio→visual mapping. `reduceMotion` forces a still frame (pulseHz 0).
    /// `autoAttuned` is #609 (Auto mode's visual half): a continuous, capped deepening
    /// of the coherence coupling — settled calms the figure and fills it slightly,
    /// an unsettled body busies it. The cap is the SAME gentleness number as the
    /// sound half (`AutoAttune.maxTargetDelta`, one definition, #416). The default
    /// `false` keeps every existing caller byte-identical (the Golden law).
    public static func from(_ frame: BioSampleFrame?,
                            pattern: BioVisualPattern = .rings,
                            reduceMotion: Bool = false,
                            autoAttuned: Bool = false) -> BioVisualParams {
        let hr = Double(frame?.heartRateBPM ?? 60)
        // Heartbeat → pulse, bounded to a calm [0.5, 2.0] Hz then flash-clamped.
        let bounded = Swift.min(Swift.max(hr / 60.0, 0.5), 2.0)
        let pulse = FlashGuard.safeFrequency(bounded, reduceMotion: reduceMotion)

        // Coherence now falls back mid-scale like its two neighbours instead of to 0.
        // It was the odd one out, and 0 is this mapping's extreme: full red at floor
        // intensity, i.e. the most alarmed-looking frame the renderer can draw, shown
        // precisely when nothing is known. `coherenceForSound` extends the same rule
        // to a frame that EXISTS but has not measured coherence (HealthKit never does).
        // `from(nil)` still does NOT equal `.neutral` — it lands on hue 0.225 /
        // complexity 0.6 / intensity 0.7 / pulse 1.0 against that constant's 0.2 / 0.5
        // / 0.5 / 0. Four of six fields differ; only hue moved closer. `.neutral` is a
        // hand-picked still frame, not this mapping evaluated at mid-scale.
        let coherence = clamp01(Double(frame?.coherenceForSound ?? 0.5))
        let hrv = clamp01(Double(frame?.hrvForSound ?? 0.5))
        let breath = clamp01(Double(frame?.breathPhase ?? 0.5))

        // #609 — see `autoTerm(_:enabled:)`, the ONE definition. Deliberately NOT
        // touching `pulseHz` (the flash-safety path stays byte-identical under
        // auto), `hue` (physical colour is the science-first promise) or `spread`
        // (breath owns it).
        let auto = autoTerm(frame, enabled: autoAttuned)

        return BioVisualParams(
            pattern: pattern,
            pulseHz: pulse,
            hue: coherence * 0.45,                 // red → cyan with coherence
            complexity: clamp01(0.2 + hrv * 0.8 - auto),   // settled → calmer figure
            spread: 0.85 + breath * 0.30,          // inhale expands the figure
            intensity: clamp01(0.4 + coherence * 0.6 + auto * 0.5)  // settled → a touch fuller
        )
    }

    /// #609/#609b — Auto mode's visual term, the ONE definition (#416): signed,
    /// continuous on the coherence axis, range ±`AutoAttune.maxTargetDelta` (the
    /// same gentleness cap as the sound half). Centred at 0.5, which is exactly
    /// `coherenceForSound`'s "not measured" fallback — an unmeasured body returns
    /// EXACTLY 0 and steers nothing. Two consumers, deliberately: `from(_:)` above
    /// (the field mapping, for any future renderer that reads those fields) and the
    /// LIVE ring renderer's look products (`MetalBioView.draw`), because the shipped
    /// shader reads `vp.pulseHz` ONLY — `TheVoiceTintsTheVisualTests` documents that
    /// writing other `vp` fields alone is the wired-but-dead trap, and the first
    /// #609 version fell exactly into it (caught by review, not by me).
    public static func autoTerm(_ frame: BioSampleFrame?, enabled: Bool) -> Double {
        guard enabled else { return 0 }
        let coherence = clamp01(Double(frame?.coherenceForSound ?? 0.5))
        return Double(AutoAttune.maxTargetDelta) * 2 * (coherence - 0.5)
    }

    private static func clamp01(_ x: Double) -> Double { Swift.min(Swift.max(x, 0), 1) }
}
