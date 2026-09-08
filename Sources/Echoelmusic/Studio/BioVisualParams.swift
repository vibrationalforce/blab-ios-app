//
//  BioVisualParams.swift
//  Echoelmusic — Studio (visual)
//
//  Rebuilt-new foundation for the bio-reactive visual engine (the honest
//  realization of the old "VisualForge" intent — science-visual, not esoterica).
//  ONE pure value type centralizes the body→image mapping so every renderer
//  reads the SAME flash-safe parameters. Pure, Sendable, deterministic, fully
//  unit-tested — no Metal, no SwiftUI here.
//
//  ⛔ THIS HEADER PROMISED TWO RICHER GPU KERNELS AS THE NEXT STEP — a cymatics one and a
//  mandala one — AND THAT PLAN WAS OVERTAKEN, NOT ABANDONED (#1147, measured). The struck
//  sentence is deliberately PARAPHRASED and not quoted: `TheLookSystemHasOneHomeTests`
//  claim 3 scans this file for its absence, and a verbatim quotation here would be the only
//  remaining match — the retraction would refute itself. That trap has now fired three times
//  in this repo (#1142 header, #1144 chip comment, here) and it fired again during this very
//  edit, caught by driving the guard instead of trusting it. Cymatics SHIPPED — as
//  `fieldDish` at shader style index 2, driven by `Core/FaradayDish` (a real Faraday
//  instability model, pinned before a pixel depended on it, #1100/#1101). It did NOT
//  arrive through this file, and nothing here was involved. A session sent here by the
//  word "Cymatics" would build a second one against a dead enum.
//
//  ⭐ WHERE THE LIVE LOOK SYSTEM ACTUALLY IS, so the next reader goes to the right place
//  on the first try: `Studio/LookBlendMap.library` is the curated roster the user can
//  select — five entries, `(0, "Rings") (2, "Dish") (3, "Water") (5, "Aurora")
//  (7, "Depth")` — the indices are the shader's `styleField` branches in
//  `Views/MetalBioView.swift`, and `Core/FlashGuard.fieldBudgets` carries one flash
//  budget per selectable look. Adding a look means a shader branch plus a row in each of
//  those two, never a case in the enum below.
//
//  Flash safety is baked in: pulse frequency is routed through FlashGuard (≤3 Hz
//  WCAG, 0 under Reduce Motion), so no renderer can strobe by construction.
//

import Foundation

/// The visual pattern a renderer draws. Each maps the same bio params differently.
///
/// ⛔ NO CONSUMER (#1147, measured) — the same defect #1116 took back on `hue` and #1131 on
/// three more fields, one level up: this is a whole parallel LOOK SYSTEM that nothing renders.
/// `git grep -n "BioVisualPattern" -- Sources` returns only this file, and `.pattern` below is
/// read nowhere outside it. Its three cases do not correspond to the five shipped looks either
/// — `mandala` was never built at all, and `cymatics` names a capability that exists under a
/// different name in a different file (see the header).
///
/// ⚠️ NOT DELETED, AND THE REASON IS NOT SENTIMENT: the enum is `String`-backed and
/// `BioVisualParams` is a public value type, so a persisted document or a future decoder could
/// still carry one of these raw values. Removing a case is a schema decision, not a cleanup.
/// What IS a defect is claiming it is the way to add a look — that claim is retracted above.
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
    ///
    /// ⛔ NO CONSUMER (#1147, measured) — see the enum's own note. This was the ONE field of
    /// this struct without such a marker while its four neighbours all carried one, which is
    /// why the dead look-system survived two consumer audits: #1116 and #1131 both walked the
    /// FIELDS and neither asked what the first field's TYPE was.
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
    /// Pattern complexity [0…1]; HRV would drive ring count / Chladni order.
    ///
    /// ⛔ NO CONSUMER (#1131, measured) — THE SAME DEFECT #1116 TOOK BACK ON `hue`, LEFT
    /// STANDING ON ITS THREE NEIGHBOURS. `git grep -nE "\bvp\.[a-z]" -- Sources` returns
    /// **exactly one** line in the whole repo (`vp.pulseHz`, `MetalBioView.swift:1156`), so
    /// this value is computed on every frame and read by nothing. The doc said "HRV drives
    /// ring count" in the present tense; it now says "would".
    ///
    /// ⚠️ AND THIS IS THE ONE THAT MATTERS MOST OF THE THREE, because it is the app's ONLY
    /// HRV→picture mapping. The body has four measured channels; the sound uses all four
    /// (`hrvForSound` → brightness), the picture receives three — heart rate through
    /// `pulseHz`, breath and coherence through the shader's OWN terms — and HRV's single
    /// path ends here. Wiring it is a real slice with a real hazard (`BioUniforms` ↔ the
    /// MSL `Uniforms` are hand-mirrored by BYTE LAYOUT, 99 fields, no compiler check, #1119
    /// — only END appends are safe), which is why this commit tells the truth instead of
    /// reaching for the shader in the same breath.
    ///
    /// ⚠️ "Chladni order" names style 1, RETIRED from `LookBlendMap.library`. Kept, not
    /// deleted, for the #527 reason: this struct is the ONE pure bio→visual mapping and a
    /// future surface is its natural consumer. **Do not quote it as a shipping mapping.**
    public var complexity: Double
    /// Breath spread factor [~0.85…1.15]; the figure would expand on the inhale.
    ///
    /// ⛔ NO CONSUMER (#1131, measured) — see `complexity`.
    /// ⚠️ BUT DO NOT READ THIS AS "BREATH DOES NOT REACH THE PICTURE". It does, through the
    /// shader's own term (`float spread = (0.85 + u.breath * 0.35) * clamp(u.spread, …)`),
    /// fed by the `breath:` argument of `update()`. What is dead is this FIELD, not the
    /// capability — and stating the stronger, wrong version would be the mirror of the
    /// error #1130 corrected on the other side.
    public var spread: Double
    /// Overall brightness/intensity [0…1]; coherence would make it fuller.
    ///
    /// ⛔ NO CONSUMER (#1131, measured) — see `complexity`. Coherence itself DOES reach the
    /// picture (the `coherence:` argument of `update()`, which every field function reads);
    /// what is dead is this field.
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
