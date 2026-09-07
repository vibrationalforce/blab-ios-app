// VisualEnergy.swift
// Echoel — #228 ("Ein Bedienelement statt neun Reglern für die Visuals").
//
// ONE number, 0…1, that walks the immersive visual from its calmest curated world to
// its most energetic one. It is a PURE mapping, not a stored setting: the Field panel
// binds it as a DERIVED binding over the live Intensity/Motion values, so there is no
// second source of truth to drift, nothing new on disk, and no "the dial says 0.4 but
// the picture is Zentrifuge" lie after a hand edit in the fine-tune rows.
//
// WHY THE ENDPOINTS ARE NOT INVENTED NUMBERS. They are read off `VisualPreset.factory`
// — the set the founder curated down to five stops ("weniger ist mehr", 2026-07-08). So
// t = 0 is exactly the calmest curated energy the app ships and t = 1 exactly the most
// energetic one; the dial can never leave the world the presets already define, and it
// cannot silently diverge from that set when a preset is retuned.
//
// ⚠️ THE HARD PART OF THIS FILE IS WHAT IS *NOT* ON THE DIAL. Two of the four energy
// parameters were excluded on measured grounds, not taste — putting a weak or inert
// parameter on the ONE control is exactly how a control starts lying:
//
//   · **Detail** (`ringDensity`) does nothing on the look set that ships by default.
//     Traced 2026-07-31: `MetalBioView.swift:1637` clamps it into the shader's `density`,
//     and `styleField` (`:1591`) hands `density` to `fieldRings` — style 0 — and to no
//     other field function. The default primary style is 5 (Aurora) and the default slider
//     sequence is `[3,5,7]` (Water · Aurora · Depth, `LookBlendMap.defaultSequence`), none
//     of which is Rings.
//     ⛔ THE FIRST DRAFT OF THIS BULLET CALLED THAT "inert … a real defect", AND THAT IS
//     TOO BROAD — the reviewer refuted it and the refutation checks out. `Rings` is in
//     `LookBlendMap.library` (`:35`) and `visualLookCustomizer` can toggle it into the
//     sequence from the row directly above this dial, at which point Detail is fully live.
//     So Detail is CONDITIONAL, not broken. That is still disqualifying for a single dial —
//     a control whose effect depends on a choice made in another row is not the thing one
//     number should move — but the honest word is conditional. (`visualDetail` has a second
//     consumer too, `SpectralDonutView(bandCount:)`.)
//     ⛔ "on a doorless path" stood at the end of that parenthesis and expired TWICE without
//     anyone noticing (#1062). #747 gave the fullscreen cover a door, so the donut became
//     reachable; #1043 then ported the donut branch into `FloatingVisualWindow`, so it has
//     TWO reachable surfaces — measured: `git grep -n "SpectralDonutView(" -- Sources` returns
//     two production sites. The phrase mattered because it was an ARGUMENT: a second consumer
//     nobody can reach does not rescue a conditional dial, and a second consumer on the app's
//     FIRST SCREEN does. The bullet's verdict ("conditional, not broken") is unchanged; what
//     changed is that the parenthesis was quietly making the opposite case.
//   · **Spread** is NOT what its curated values suggest. ⛔ The first draft said "only
//     softens the vignette frame", citing `vEdge = 0.9 + 0.5 * spread`
//     (`MetalBioView.swift:1589`) — that is the only use inside `styleField`, but the same
//     shader-local `spread` also scales `bloomEdge` (`:1681`) and the tone-cloud radius
//     (`:1348` via `:1691`), and it is not even the user's raw value: `:1639` mixes it with
//     breath. The surviving reason, which IS verified and is pinned by a test: across the
//     curated set spread runs 1.35 · 1.35 · 1.20 · 1.00 · 1.20 while that set is ordered
//     softest→most energetic. It goes DOWN and back UP; a monotonic dial may only carry
//     monotonic parameters.
//
// Hue and Saturation are palette, deliberately orthogonal ("the colour is the heard
// tone") — they were never energy and stay fine-tune rows.
//
// Nothing here imports SwiftUI or Metal: it is a value mapping, testable in the
// blocking CISmoke bundle without a renderer.

import Foundation

/// The single-control mapping for the immersive visual's energy.
public enum VisualEnergy {

    /// One parameter's curated span, taken from `VisualPreset.factory`.
    public struct Span: Sendable, Equatable {
        public let lo: Double
        public let hi: Double

        /// Degenerate-input-safe construction: an empty or single-valued factory must not
        /// produce a zero-width span — the inverse divides by that width.
        init(lo: Double, hi: Double, fallbackLo: Double, fallbackHi: Double) {
            let l = lo.isFinite ? lo : fallbackLo
            let h = hi.isFinite ? hi : fallbackHi
            if h - l > 1e-9 {
                self.lo = l
                self.hi = h
            } else {
                self.lo = fallbackLo
                self.hi = fallbackHi
            }
        }

        /// Value at position `t` (assumed already clamped to 0…1).
        func value(at t: Double) -> Double { lo + (hi - lo) * t }

        /// Position of `v` on this span, clamped — the exact inverse of `value(at:)`.
        func position(of v: Double) -> Double {
            let x = v.isFinite ? v : lo
            return Swift.min(1, Swift.max(0, (x - lo) / (hi - lo)))
        }
    }

    private static func span(_ pick: (VisualPreset) -> Float,
                             fallbackLo: Double, fallbackHi: Double) -> Span {
        let values = VisualPreset.factory.map { Double(pick($0)) }
        return Span(lo: values.min() ?? fallbackLo, hi: values.max() ?? fallbackHi,
                    fallbackLo: fallbackLo, fallbackHi: fallbackHi)
    }

    /// Brightness span — the factory's calmest…most energetic intensity.
    /// It reaches the shader (`col *= clamp(u.intensity, …)`, `MetalBioView.swift:1745`) but
    /// NOT untouched: on the one reachable renderer it first passes the weather blend in
    /// `FloatingVisualWindow.weatheredVisuals()` and then the renderer's easing. The word
    /// "directly" stood here and was wrong — with weather on, this dial sets a base value
    /// that is then mixed toward a sky target, and a reader who trusted "directly" would
    /// stop looking exactly where the surprise lives.
    public static let intensity = span({ $0.intensity }, fallbackLo: 0.8, fallbackHi: 1.4)

    /// Pulse-speed span. This is the *requested* heartbeat rate multiplier; the renderer
    /// still hard-caps the result at `FlashGuard.maxPulseRateHz`, so this dial can never
    /// raise the safety ceiling — only approach it.
    public static let motion = span({ $0.motion }, fallbackLo: 0.42, fallbackHi: 1.4)

    /// The two live values for a dial position. NaN-safe: a non-finite `t` reads as the
    /// calm end, never as an unclamped write into the renderer's uniforms.
    public static func look(at t: Double) -> (intensity: Double, motion: Double) {
        let c = clamp(t)
        return (intensity.value(at: c), motion.value(at: c))
    }

    /// Where the dial sits for a given pair of live values — the inverse of `look(at:)`.
    ///
    /// Averaging the two per-parameter positions is what keeps the control honest after a
    /// hand edit: they can disagree (that IS what "custom" means), and the dial then shows
    /// their centre instead of pretending one of them is the truth. The round trip
    /// `position(matching: look(at: t)) == t` holds exactly **for t in 0…1**, because both
    /// agree whenever the values came from this mapping. Outside 0…1 `look` clamps and the
    /// identity necessarily fails — correct behaviour, and the scope the test covers.
    ///
    /// Because both positions are CLAMPED before averaging, values above a span's top read
    /// identically: a hand-edited Intensity of 1.5 and of 1.4 both sit at position 1. Moving
    /// the dial from such an off-curve state pulls both values back onto the curve, so a small
    /// dial nudge can be a large parameter change. That is the macro-control contract rather
    /// than a bug, and `VisualEnergyTests` pins the off-curve case so it stays deliberate.
    public static func position(matching intensityValue: Double,
                                motion motionValue: Double) -> Double {
        let p = intensity.position(of: intensityValue) + motion.position(of: motionValue)
        return clamp(p / 2)
    }

    private static func clamp(_ t: Double) -> Double {
        // Argument order is deliberate (CLAUDE.md): `max(0, NaN)` returns 0, so a
        // non-finite position degrades to the calm end instead of propagating.
        Swift.min(1, Swift.max(0, t))
    }
}
