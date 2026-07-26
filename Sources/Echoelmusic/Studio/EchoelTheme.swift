//
//  EchoelTheme.swift
//  Echoelmusic — Studio
//
//  App design tokens that MIRROR the website CI (docs/shared.css :root), so the
//  app and echoelmusic.com share one visual language: black ground, muted
//  #e0e0e0 text, subtle borders, small radii, a single bio-green accent.
//  Plus size-class-aware metrics so the interface scales on every device
//  (compact iPhone ↔ regular iPad) and stays legible.
//

#if canImport(SwiftUI)
import SwiftUI

enum EchoelTheme {
    // MARK: Palette (matches docs/shared.css :root)
    static let bg      = Color.black                                          // --bg #000
    static let surface = Color(red: surfaceComponent, green: surfaceComponent, blue: 0.070)
    static let text    = Color(red: 0.878, green: 0.878, blue: 0.878)         // --text #e0e0e0
    // --dim: lifted 0.55 → 0.65 for WCAG AA. `dim` is light-on-dark everywhere
    // (secondary/unit labels), so more opacity = more contrast — no usage regresses.
    // On panel fills (surface #0e0e12) this moves secondary text from ~5:1 to ~6.5:1,
    // clearing the 4.5:1 AA floor with margin. Deliberately a touch more opaque than the
    // site's --dim (accessibility-first in the app; still reads muted, not bright).
    static let dim     = Color(red: 0.878, green: 0.878, blue: 0.878).opacity(dimOpacity)

    /// The grey every neutral token is a translucent slice of (#e0e0e0), and the opacities
    /// of the two boundary tokens + the control fill — named so `ThemeContrastTests` can do
    /// the WCAG maths on THE SAME numbers the colours below are built from. Not a
    /// convenience: this repo already has a safety ceiling (2.5 Hz flash) whose test
    /// validates a hand-COPIED literal, so the renderer can drift while the suite stays
    /// green. Contrast does not get that hole.
    nonisolated static let textComponent: Double       = 0.878
    nonisolated static let borderOpacity: Double       = 0.10
    nonisolated static let borderStrongOpacity: Double = 0.45
    nonisolated static let fillOpacity: Double         = 0.06
    nonisolated static let dimOpacity: Double          = 0.65
    /// `surface`'s R/G channel. Its blue is 0.070, so treating the panel fill as a NEUTRAL
    /// 0.055 grey is the darker, stricter ground for the light-on-dark text that sits on it.
    nonisolated static let surfaceComponent: Double     = 0.055

    /// DECORATIVE boundary — hairlines, dividers, the outline of a panel card. 1.16:1
    /// against black, which is fine: WCAG 1.4.11 covers the boundary of a CONTROL, not
    /// ornament. Do not use it on anything tappable.
    static let border  = Color(red: 0.878, green: 0.878, blue: 0.878).opacity(borderOpacity)

    /// INTERACTIVE boundary — the outline that says "this is a control".
    ///
    /// AS RENDERED (`.background(fill)` then `.overlay(strokeBorder)`, so the stroke lies
    /// OVER the control's own fill): **3.70:1** against that fill, 4.01:1 against the page,
    /// and it holds through every real nesting — 3.67:1 inside an `EchoelPanel`, 3.50:1 at
    /// the deepest fill-on-surface stack. `ThemeContrastTests` also asserts a deliberately
    /// PESSIMISTIC variant that models the stroke over black (3.31:1 vs fill, 3.59:1 vs
    /// page) as a lower bound; blending in linear space instead would give 7.70:1, so sRGB
    /// compositing is the conservative choice, not a flattering one.
    ///
    /// Applied to: the front-plate tab chips, the Notes chip, `EchoelValueField` and its
    /// fader capsule, `EchoelNumberPad`'s keys, the three always-on header tiles, the
    /// header overflow-menu button, and `masterDoorButton`. NOT to panel-card outlines or
    /// dividers — see `border`. (This list is the contract: an earlier version of it named
    /// door buttons before they were converted, which is the exact drift class most of
    /// CLAUDE.md's corrections are about.)
    ///
    /// Why it exists: every control in the app declared itself with the 0.10 `border`, i.e.
    /// **1.16:1** — labels read at 15.9:1 while the boundaries were invisible. Worse, the
    /// ACTIVE state uses `accent` at 11.6:1, so a control only became visible once you had
    /// already found it. Three accessibility passes each fixed something real and none
    /// caught this, because they read text contrast.
    static let borderStrong = Color(red: 0.878, green: 0.878, blue: 0.878)
        .opacity(borderStrongOpacity)

    static let fill    = Color(red: 0.878, green: 0.878, blue: 0.878).opacity(fillOpacity) // --glass-ish
    // CI rule (mirrors echoelmusic.com): the site is MONOCHROME — every primary
    // action is off-white fill + black label (`.btn-primary { background: var(--text) }`).
    // So in-app PRIMARY buttons fill with `.text`, NOT `.accent`. The bio-green
    // `accent` is reserved for the body's live signal (HR/coherence, active/playing
    // state, sliders that shape bio-driven sound) — never as page chrome. Using
    // green as a hero fill is what made the UI read as a generic generated app.
    static let accent  = Color(red: 0.30, green: 0.85, blue: 0.55)            // bio-green (signal only)
    static let onPrimary = Color.black                                         // label on a `.text`-filled button
    static let danger  = Color(red: 0.90, green: 0.30, blue: 0.30)
    /// A live/positive bio state (green). Same hue as `accent` — named so status UI reads
    /// by MEANING, and contrast can be tuned in one place.
    static let success = accent
    /// An in-progress / acquiring state (amber). Centralises the ad-hoc `Color.orange` and
    /// the inline `Color(red:0.90,0.62,0.20)` that meant "measuring" in the bio views.
    static let warning = Color(red: 0.90, green: 0.62, blue: 0.20)

    // MARK: Radii (≤ 12 per CLAUDE.md UI constraints)
    static let radiusSmall: CGFloat = 4
    static let radius:      CGFloat = 8
    static let radiusLarge: CGFloat = 12

    // MARK: Brand typography — Atkinson Hyperlegible (mirrors echoelmusic.com)
    // The site uses this accessibility-first typeface; the app now bundles it
    // (Resources/Fonts + UIAppFonts). Atkinson ships Regular / Bold / Italic only,
    // so map any heavy weight onto the Bold face (custom fonts don't synthesize a
    // weight from the family — the correct face must be named explicitly). Falls
    // back to the system font automatically if the resource is ever missing.
    static let fontFamily = "Atkinson Hyperlegible"
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let face: String
        switch weight {
        case .semibold, .bold, .heavy, .black: face = "AtkinsonHyperlegible-Bold"
        default:                                face = "AtkinsonHyperlegible-Regular"
        }
        // `relativeTo: .body` makes the bundled custom font scale with Dynamic Type
        // AND with the app's pinch-to-zoom (`.dynamicTypeSize(...)`), so the whole
        // interface grows for users who need larger text — accessibility-first.
        return .custom(face, size: size, relativeTo: .body)
    }

    // MARK: Size-class-adaptive metrics — so everything is visible on all devices
    /// Pass `horizontalSizeClass`; `.regular` (iPad / large) gets the bigger set.
    struct Metrics {
        let stepCellHeight: CGFloat
        let trackLabelWidth: CGFloat
        let controlSize: CGFloat
        let padHeight: CGFloat
        let padColumns: Int
        let bodySpacing: CGFloat

        /// - Parameters:
        ///   - h: horizontal size class (`.regular` = iPad / large → bigger set).
        ///   - v: vertical size class. `.compact` on a phone means **landscape**,
        ///        where vertical room is scarce — tighten heights/spacing and
        ///        lay the pads out in a single wide row to use the width.
        static func of(_ h: UserInterfaceSizeClass?, _ v: UserInterfaceSizeClass? = nil) -> Metrics {
            let regular = (h == .regular)
            // Compact height on a non-iPad device = landscape phone.
            let landscapePhone = (v == .compact && !regular)
            return Metrics(
                stepCellHeight:  regular ? 44 : (landscapePhone ? 24 : 30),
                trackLabelWidth: regular ? 56 : 38,
                controlSize:     regular ? 56 : (landscapePhone ? 38 : 44),
                padHeight:       regular ? 96 : (landscapePhone ? 50 : 64),
                padColumns:      regular ? 8  : (landscapePhone ? 8  : 4),
                bodySpacing:     regular ? 22 : (landscapePhone ? 8  : 14)
            )
        }
    }
}
#endif
