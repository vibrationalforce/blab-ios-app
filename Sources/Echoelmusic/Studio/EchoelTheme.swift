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
    /// fader capsule, `EchoelNumberPad`'s keys, the always-on header tiles (Immersive, Lux,
    /// Clips) AND the pulse monitor beside them, the header overflow-menu button,
    /// `masterDoorButton`, and — since #367 — the primary transport Play/Pause
    /// (`WorkspaceView`) and the tempo lock (`BodyTempoField`).
    /// NOT to panel-card outlines or dividers — see `border`. (This list is the contract: an
    /// earlier version of it named door buttons before they were converted, which is the
    /// exact drift class most of CLAUDE.md's corrections are about.)
    ///
    /// ⚠️ #367 ALSO FIXED THIS LIST'S OWN BLIND SPOT — TWICE, and the second time caught me
    /// mid-commit, which is why it is written out. "The three always-on header tiles" was one
    /// phrase, so it READ as a settled fact. It was wrong in both directions at once: the
    /// third of those tiles (Clips) was still on the decorative `border`, and a FOURTH
    /// always-on element in the same file — `PulseMonitorMini` — was on `borderStrong` and
    /// had never been listed here at all. I then repeated the same "three" in the fix's own
    /// comment before counting the call sites.
    ///
    /// The lesson is narrower than "be careful": a contract that counts its members in prose
    /// cannot be checked by READING it, only by counting call sites — and the count is the
    /// part that rots, because every new control changes it and none of them come back here.
    /// `ControlBoundaryIsInteractiveTests` does the counting now; that is the only reason a
    /// number is allowed to stand in this paragraph.
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
    //
    // ⭐ WHAT THE RULE COVERS, EXACTLY (#364) — because a sweeping reading of it is wrong
    // and I made that reading first. It governs a SOLID GREEN AREA BEHIND A LABEL: a
    // filled button, a filled card, a hero band. It does NOT govern
    //   · a control TINT (`Slider`/`Toggle`/`.tint`) — the switch that is on, the fader
    //     that is being dragged; those ARE "active state", which the sentence above names;
    //   · an ON/OFF foreground on a toggling glyph (grid on, chord-stamp armed);
    //   · a SIGNAL BAR or meter fill (`liveBar`, `signalBar`, `EchoelValueField`'s fader) —
    //     the value itself, which is what the colour is reserved FOR;
    //   · a row-label colour inside a system `List`/`Form` (`EchoelFXView`'s
    //     "Save current sound…", "Add bio modulation…"). In a list, colour is the ONLY
    //     affordance that a row is tappable — repainting those to `.text` would obey the
    //     rule's letter and cost five actions their handle, which is the same failure the
    //     `EchoelValueField` "READ THE WORD NUMERIC" note in CLAUDE.md warns about.
    //
    // ⛔ THE AUDIT FINDING THIS PARAGRAPH ANSWERS WAS MOSTLY WRONG, and that is the point of
    // writing it down. #364 was filed as "bio-green used as page chrome" from a grep of 113
    // `accent` call sites. Reading the CONTAINERS, nearly all of them are the sanctioned
    // cases above. The literal violation — solid green behind a label, on a reachable
    // surface — was exactly ONE: `EchoelNumberPad`'s OK key, now `.text` (the other,
    // `ProUnlockView`'s purchase button, is deliberately doorless until v1.1 and is left
    // alone). Grepping a token and grepping its MEANING are different jobs; the first one
    // produced a plan to repaint an app that was already following its own rule.
    static let accent  = Color(red: 0.30, green: 0.85, blue: 0.55)            // bio-green (signal only)
    static let onPrimary = Color.black                                         // label on a `.text`-filled button
    static let danger  = Color(red: 0.90, green: 0.30, blue: 0.30)
    /// A live/positive bio state (green). Same hue as `accent` — named so status UI reads
    /// by MEANING, and contrast can be tuned in one place.
    static let success = accent
    /// An in-progress / acquiring state (amber). Centralises the ad-hoc `Color.orange` and
    /// the inline `Color(red:0.90,0.62,0.20)` that meant "measuring" in the bio views.
    static let warning = Color(red: 0.90, green: 0.62, blue: 0.20)

    /// A CAPTURE IS RUNNING — the REC dot, the running WAV/video glyph, the header
    /// recording pip. Same components as `danger` today, and deliberately a DIFFERENT NAME
    /// (#363).
    ///
    /// ⛔ THERE WERE THREE REDS FOR THIS ONE STATE, in three files that never sit on screen
    /// together, which is exactly why nobody saw it: `Color.red` (the system red, which
    /// Apple is free to move between OS versions) in `FloatingVisualWindow` and
    /// `EchoelStudioView`; an inline `Color(red: 0.86, green: 0.22, blue: 0.20)` in
    /// `HeaderMonitors`; and `danger` everywhere else that means red at all.
    ///
    /// WHY A SEPARATE NAME RATHER THAN JUST USING `danger`: "a take is running" and
    /// "something is wrong" are different messages that happen to share a colour. If a later
    /// pass retunes the error red — and error reds do get retuned — a shared token would
    /// silently repaint every recording indicator in the app along with it. Two names, one
    /// value, is the cheap way to keep that a decision instead of a side effect.
    ///
    /// WHY THIS VALUE: measured, not preferred. Against the app's black it reads 5.50:1 and
    /// against `surface` 5.05:1; the retired header red reads 4.64 / 4.25. Both clear the
    /// 3:1 WCAG 1.4.11 floor that actually governs a non-text pip, so the header red was not
    /// FAILING — it was simply the weaker of two, and when the choice is free the stronger
    /// one wins. (Saying it that way on purpose: calling it an accessibility fix would have
    /// been the more satisfying sentence and the less true one.)
    static let recording = Color(red: 0.90, green: 0.30, blue: 0.30)

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

    /// ⭐ THIS PARAMETER HAS EXACTLY TWO OUTCOMES, not nine (#361). `Font.Weight` offers
    /// ultraLight · thin · light · regular · medium · semibold · bold · heavy · black; the
    /// switch below folds four of them onto the Bold face and EVERYTHING ELSE onto Regular.
    /// A custom font does not synthesize an intermediate weight from the family — the face
    /// has to be named, and this app bundles three faces (Regular, Bold, Italic;
    /// `Resources/iOS/Info.plist` `UIAppFonts`). So a weight with no face is not "a bit
    /// lighter than bold", it is byte-identical to writing nothing at all.
    ///
    /// ⛔ 62 CALL SITES WROTE `.medium` AND GOT REGULAR. Every one of them was a design
    /// intention — a row label meant to sit a step above its value, a chip meant to read
    /// slightly firmer — that never reached the screen, in an interface where the same file
    /// often had a `.semibold` sibling two lines away. Nobody could see the bug by looking at
    /// the app, because there was nothing to see: the difference the source asked for was
    /// simply absent. They are now spelled without a weight, which renders identically and
    /// says what actually happens. The ONE ternary among them
    /// (`isOn ? .semibold : .medium`) became `isOn ? .semibold : .regular` — there the
    /// contrast between the two branches was always Bold-vs-Regular.
    ///
    /// ⚠️ `.font(.system(size:weight: .medium))` IS NOT THIS BUG and must not be "cleaned up"
    /// with it: SF ships a real medium and renders it. Those sites are a separate question
    /// (they use the system face instead of the brand one at all); do not conflate the two.
    ///
    /// ⚠️ WHY THE SIGNATURE STILL TAKES `Font.Weight` rather than a two-case enum that could
    /// not express the mistake: that is the stronger fix and it touches every call site in
    /// the app including the ~80 correct ones, with no local compiler to catch a slip. The
    /// guard (`Tests/CISmoke/TypeWeightsThatExistTests.swift`) buys the same protection for
    /// the price of a source scan. If a future pass has a reason to open all of these files
    /// anyway, take the type then.
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
