// VisualPreset.swift
// Echoel — named starting points for the immersive sound→light visual ("von Aura
// bis Zentrifuge"). A preset is a PURE value type that sets the four live ENERGY
// controls the user already tweaks — Intensity, Detail (ring density), Motion
// (flash-safe speed) and Spread. Selecting one is a launch point; the controls then
// stay live for hands-on play. Every preset's values sit inside the existing clamped,
// WCAG flash-safe ranges, so a preset can never exceed the 3 Hz safety ceiling.
//
// A preset shapes ENERGY/FORM only — it does NOT pick the renderer (Donuts vs the
// Metal fields) nor the Look. The "Look" strip owns the renderer/style and a preset
// composes ON TOP of whatever Look is active, so the two never fight (this fixed the
// "a preset silently swapped the chosen Look's renderer" bug). The COLOUR is always
// the physically-correct tone→light mapping (Echoel CI via EchoelTheme + SpectralColor),
// so presets shape FORM/ENERGY, not hue — keeping the "the colour is the heard tone"
// promise intact.

import Foundation

public struct VisualPreset: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    /// Brightness, 0…1.5 (matches the Intensity slider range).
    public let intensity: Float
    /// Ring density, 8…90 (matches the Detail slider range).
    public let detail: Float
    /// Animation speed, 0…1.5 — flash-capped downstream so it stays ≤3 Hz.
    public let motion: Float
    /// Field spread, 0.5…1.5 (matches the Spread slider range).
    public let spread: Float
    /// One-line character note for the picker.
    public let blurb: String

    public init(id: String, name: String, intensity: Float, detail: Float,
                motion: Float, spread: Float, blurb: String) {
        self.id = id
        self.name = name
        self.intensity = Swift.min(1.5, Swift.max(0, intensity))
        self.detail = Swift.min(90, Swift.max(8, detail))
        self.motion = Swift.min(1.5, Swift.max(0, motion))
        self.spread = Swift.min(1.5, Swift.max(0.5, spread))
        self.blurb = blurb
    }

    /// Curated set spanning the calm/sparse → intense/dense range the founder framed
    /// as "von Aura bis Zentrifuge". Ordered from softest to most energetic.
    public static let factory: [VisualPreset] = [
        VisualPreset(id: "aura", name: "Aura", intensity: 0.8, detail: 14, motion: 0.45,
                     spread: 1.35, blurb: "soft, sparse, slow aura"),
        VisualPreset(id: "drift", name: "Drift", intensity: 0.75, detail: 20, motion: 0.4,
                     spread: 1.4, blurb: "calm, wide and gentle"),
        VisualPreset(id: "bloom", name: "Bloom", intensity: 1.1, detail: 28, motion: 0.7,
                     spread: 1.2, blurb: "blossoming mid-density"),
        VisualPreset(id: "halo", name: "Halo", intensity: 1.3, detail: 24, motion: 0.6,
                     spread: 0.85, blurb: "bright, tight, focused"),
        VisualPreset(id: "cinder", name: "Cinder", intensity: 1.2, detail: 50, motion: 0.9,
                     spread: 0.95, blurb: "warm, dense, close embers"),
        VisualPreset(id: "pulse", name: "Pulse", intensity: 1.2, detail: 32, motion: 1.1,
                     spread: 1.0, blurb: "heartbeat-forward"),
        VisualPreset(id: "nebula", name: "Nebula", intensity: 1.0, detail: 72, motion: 0.6,
                     spread: 1.5, blurb: "vast, finely detailed field"),
        VisualPreset(id: "vortex", name: "Vortex", intensity: 1.15, detail: 60, motion: 1.3,
                     spread: 1.1, blurb: "fast, swirling, energetic"),
        VisualPreset(id: "zentrifuge", name: "Zentrifuge", intensity: 1.4, detail: 86, motion: 1.4,
                     spread: 1.2, blurb: "maximal — dense, fast, centrifugal")
    ]
}
