// EchoelIconTile.swift
// Echoel — ONE chrome action chip, so a row of them cannot become a row of near-misses.

#if canImport(SwiftUI)
import SwiftUI

/// The one "Button Format" the founder named.
///
/// ⭐ FOUNDER 2026-08-07, two screenshots: *"Die größe der Buttons anpassen, die sollen immer
/// gleichgroß sein. Orientiere dich an denen oben rechts. außerdem soll alles aus dem zweiten
/// Bild was rot markiert ist, intelligent und übersichtlich im selben Button Format in eine
/// Reihe unter dem Play etc zusammengefasst werden."*
///
/// #481 answered the first sentence by pointing every chrome control at
/// `EchoelTheme.controlHeight` / `controlTapHeight` — but a shared HEIGHT is not a shared
/// FORMAT: fill, border, radius, glyph weight and tap floor were still spelled once per call
/// site, which is how the transport row ended up with three heights in the first place. This
/// type is the whole chip in one declaration, so the row #482 builds is uniform by
/// construction rather than by six edits agreeing with each other (#416).
///
/// ⚠️ THE TAP FLOOR IS A FRAME, NOT THE `-6` OUTSET the header tiles and the tempo lock use,
/// and the divergence is deliberate. An outset grows the hit rectangle INTO the neighbouring
/// gap. That is safe for a control with a `Spacer` beside it — which is exactly the geometry
/// `TapTargetFloorTests` measured for the old "•••" — and unsafe the moment two chips sit
/// adjacent at 8 pt spacing, where two −6 outsets overlap by 4 pt and a tap near the seam can
/// fire the wrong action. A frame pushes siblings apart instead of overlapping them, so it is
/// the only form that survives being repeated six times in one row.
///
/// ⭐ AND FOR A `Menu` IT IS THE ONLY FORM THAT WORKS AT ALL. `TapTargetFloorTests` records
/// that `contentShape` applied INSIDE a `Menu`'s `label:` closure is "almost certainly a
/// no-op" — a Menu presents from its OWN bounds and a descendant cannot widen them. A frame
/// changes those bounds, because the label's layout size IS the Menu's size. So the "•••"
/// gains a real 44 pt target here, where it previously carried a modifier that was pinned by
/// a test and probably doing nothing.
///
/// ⚠️ THE GLYPH DOES NOT SCALE WITH DYNAMIC TYPE, and that is honest rather than good. The
/// chip height is a hard `EchoelTheme.controlHeight` because "immer gleichgroß" is the ask; a
/// `@ScaledMetric` glyph inside a fixed 32 pt box overflows its own chip at the larger
/// accessibility sizes. Every neighbour in this chrome band has the same property today (the
/// old "•••" at 13, the header tiles at 12/11/11), so this matches the surface it joins
/// instead of being the one control that clips. Making the band scale is #353's job and needs
/// the height to become a `minHeight` — which reopens precisely the question #481 closed, so
/// it is a founder-visible decision and not a tidy-up.
///
/// ⚠️ ICON-ONLY IS A REAL COST AND IT IS PAID, NOT WAVED AWAY. A glyph cannot say "Keep last:
/// 8 bars or fewer at this tempo". Every caller therefore MUST supply an
/// `accessibilityLabel`, and where the old full-width button carried an explanation the panel
/// keeps that explanation as text (see `utilityRow`). A mute disabled chip with its reason
/// deleted would be the lying-control class this repo keeps paying for.
@MainActor
struct EchoelIconTile: View {
    let systemImage: String
    /// `true` = the off-white primary fill the website CI reserves for the main action; the
    /// default is the bordered chip the three header tiles wear.
    var prominent: Bool = false
    /// `true` = take an equal share of an `HStack`'s width. Off by default because the "•••"
    /// sits next to a `Spacer` and would otherwise swallow the whole line.
    var expands: Bool = false
    /// Callers pass their own `.disabled(...)`; SwiftUI does not dim a `.plain` label for us,
    /// and the dim state must track `.disabled` EXACTLY — a bright inert chip is the same lie
    /// the full-width Record button already had to be fixed for.
    var enabled: Bool = true

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(minWidth: 38, maxWidth: expands ? CGFloat.infinity : nil)
            .frame(height: EchoelTheme.controlHeight)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .fill(prominent && enabled ? EchoelTheme.text : EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(prominent && enabled ? Color.clear : EchoelTheme.borderStrong,
                              lineWidth: 1))
            // AFTER the paint, exactly as the header tiles spell it. Before it, the rounded
            // rect would be PAINTED 44 tall — the picture grows and the hit area does not,
            // which is the opposite of the #113 idiom and reads like a fix in a diff.
            .frame(minWidth: EchoelTheme.controlTapHeight,
                   minHeight: EchoelTheme.controlTapHeight)
            .contentShape(Rectangle())
    }

    private var tint: Color {
        guard enabled else { return EchoelTheme.dim }
        return prominent ? Color.black : EchoelTheme.text
    }
}
#endif
