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
/// ⚠️ THE TAP FLOOR IS A FRAME, NOT THE `-6` OUTSET **the tempo lock** uses, and the
/// divergence is deliberate. An outset grows the hit rectangle INTO the neighbouring gap.
/// That is safe for a control with a `Spacer` beside it — the geometry `WorkspaceView`'s own
/// retracted note measured for the old "•••" — and unsafe the moment two chips sit adjacent
/// at 8 pt spacing, where two −6 outsets overlap by 4 pt and a tap near the seam can fire the
/// wrong action. A frame pushes siblings apart instead of overlapping them, so it is the only
/// form that survives being repeated six times in one row.
///
/// ⛔ THE FIRST VERSION OF THAT SENTENCE PUT THE HEADER TILES IN IT, AND THEY DO NOT BELONG.
/// `HeaderMonitors.swift` reaches 44 with `.frame(height: EchoelTheme.controlTapHeight)` +
/// `.contentShape(Rectangle())` and declares no `inset(by:)` anywhere — the same mechanism
/// this file uses. Only the tempo lock reaches it by outset. The sentence claimed a
/// deliberate divergence from the reference AND (54 lines down) exact conformance to it.
///
/// ⛔ AND THE `Menu` CLAIM WAS OVERSTATED IN THE SAME BREATH. It read "for a `Menu` it is the
/// ONLY form that works at all". A `contentShape` applied to the `Menu` ITSELF — outside the
/// `label:` closure — works too; the repo ships two of them and
/// `TapTargetFloorTests.testBothPresetOverflowMenusCarryTheHitAreaOutset` pins both. What is
/// a no-op is a `contentShape` placed INSIDE the `label:` closure, because a Menu presents
/// from its own bounds and a descendant cannot widen them. Left absolute, the sentence was a
/// standing argument for deleting those two pinned outsets. A frame is CHOSEN here for the
/// adjacency reason above, not because it is the only thing that would work.
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
    /// `true` = take an equal share of an `HStack`'s width. Every child of `quickActionRow`
    /// passes it, including the "•••" — *"die sollen immer gleichgroß sein"* is the ask, and
    /// one fixed-width child among five flexible ones is 44 pt beside five 51.8 pt siblings.
    /// The default stays `false` so a tile placed next to a `Spacer` cannot swallow its line.
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
            // AFTER the paint, in the same ORDER the header tiles spell it (they use
            // `.frame(height:)` and refuse horizontal growth; this one grows). Before it, the rounded
            // rect would be PAINTED 44 tall — the picture grows and the hit area does not,
            // which is the opposite of the #113 idiom and reads like a fix in a diff.
            .frame(minWidth: EchoelTheme.controlTapHeight,
                   minHeight: EchoelTheme.controlTapHeight)
            // ⚠️ LOAD-BEARING FOR THE FIVE `Button`s, AND IT LOOKS REDUNDANT. The frame above
            // creates transparent margin around the painted chip; for a `.plain` Button the
            // hit area is the label's CONTENT shape, so without this line those five tiles
            // fall back to the ~38 × 32 glyph and the 44 pt floor (#113) is decorative. It is
            // genuinely redundant for the `Menu`, whose bounds are its label's LAYOUT size —
            // which is exactly why "the frame already sizes it" reads true and deleting it
            // would be silent. `OneChromeControlHeightTests` asserts it for that reason.
            .contentShape(Rectangle())
    }

    private var tint: Color {
        guard enabled else { return EchoelTheme.dim }
        return prominent ? Color.black : EchoelTheme.text
    }
}
#endif
