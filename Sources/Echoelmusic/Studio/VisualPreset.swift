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
    /// OPTIONAL palette — hue rotation [0…1] (0 = physical tone colour) and
    /// saturation [0…2]. `nil` (the default for every science-first preset) keeps
    /// the physical tone→light colour untouched, so "the colour is the heard tone"
    /// still holds everywhere. A preset that DOES define these is a deliberate
    /// palette LOOK (e.g. "Vapor" — the dreamy magenta/cyan vaporwave world the
    /// founder asked for, 2026-07-07: "mehr kitschige Vaporwave-Ästhetik … Brand
    /// fit"), applied as one coherent tap so sound + visual read as one world.
    public let hue: Float?
    public let saturation: Float?
    /// One-line character note for the picker.
    public let blurb: String

    public init(id: String, name: String, intensity: Float, detail: Float,
                motion: Float, spread: Float, blurb: String,
                hue: Float? = nil, saturation: Float? = nil) {
        self.id = id
        self.name = name
        self.intensity = Swift.min(1.5, Swift.max(0, intensity))
        self.detail = Swift.min(90, Swift.max(8, detail))
        self.motion = Swift.min(1.5, Swift.max(0, motion))
        self.spread = Swift.min(1.5, Swift.max(0.5, spread))
        self.hue = hue.map { Swift.min(1, Swift.max(0, $0)) }
        self.saturation = saturation.map { Swift.min(2, Swift.max(0, $0)) }
        self.blurb = blurb
    }

    /// Curated set spanning the calm/sparse → intense/dense range the founder framed
    /// as "von Aura bis Zentrifuge". Ordered from softest to most energetic.
    /// CURATION 2026-07-08 (founder: "Weniger ist mehr … wir brauchen auch nicht so
    /// viel verschiedene Presets"): 10 → 5, one clear stop per energy register.
    /// RETIRED (reversible by re-adding a row; a persisted retired id simply shows
    /// no selection, the applied values stay editable): Drift (≈Aura), Halo, Cinder,
    /// Nebula, Vortex — mid-range near-duplicates that made the strip a search task.
    public static let factory: [VisualPreset] = [
        VisualPreset(id: "aura", name: "Aura", intensity: 0.8, detail: 14, motion: 0.45,
                     spread: 1.35, blurb: "soft, sparse, slow aura"),
        // Vapor — the coherent dreamy vaporwave world (founder 2026-07-07: "mehr
        // kitschige Vaporwave-Ästhetik … Brand fit"). Soft, slow and wide like Aura,
        // but it ALSO sets a dreamy palette: a hue rotation toward magenta/purple +
        // a gentle saturation lift for the kitschy (yet graded, not neon) vaporwave
        // glow. One tap = sound (drone + tape + hall) and picture read as one
        // nostalgic world. Flash-safe (low motion). Sits in the calm cluster by
        // energy, so the "softest→most energetic" order still holds.
        VisualPreset(id: "vapor", name: "Vapor", intensity: 0.95, detail: 24, motion: 0.42,
                     spread: 1.35, blurb: "dreamy nostalgic vaporwave glow",
                     hue: 0.82, saturation: 1.12),
        VisualPreset(id: "bloom", name: "Bloom", intensity: 1.1, detail: 28, motion: 0.7,
                     spread: 1.2, blurb: "blossoming mid-density"),
        VisualPreset(id: "pulse", name: "Pulse", intensity: 1.2, detail: 32, motion: 1.1,
                     spread: 1.0, blurb: "heartbeat-forward"),
        VisualPreset(id: "zentrifuge", name: "Zentrifuge", intensity: 1.4, detail: 86, motion: 1.4,
                     spread: 1.2, blurb: "maximal — dense, fast, centrifugal")
    ]
}
