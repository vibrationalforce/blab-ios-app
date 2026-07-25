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
    public static func from(_ frame: BioSampleFrame?,
                            pattern: BioVisualPattern = .rings,
                            reduceMotion: Bool = false) -> BioVisualParams {
        let hr = Double(frame?.heartRateBPM ?? 60)
        // Heartbeat → pulse, bounded to a calm [0.5, 2.0] Hz then flash-clamped.
        let bounded = Swift.min(Swift.max(hr / 60.0, 0.5), 2.0)
        let pulse = FlashGuard.safeFrequency(bounded, reduceMotion: reduceMotion)

        let coherence = clamp01(Double(frame?.coherence ?? 0))
        let hrv = clamp01(Double(frame?.hrvForSound ?? 0.5))   // 0 = unmeasured → neutral
        let breath = clamp01(Double(frame?.breathPhase ?? 0.5))

        return BioVisualParams(
            pattern: pattern,
            pulseHz: pulse,
            hue: coherence * 0.45,                 // red → cyan with coherence
            complexity: 0.2 + hrv * 0.8,           // more HRV → richer figure
            spread: 0.85 + breath * 0.30,          // inhale expands the figure
            intensity: 0.4 + coherence * 0.6       // coherent → fuller
        )
    }

    private static func clamp01(_ x: Double) -> Double { Swift.min(Swift.max(x, 0), 1) }
}
