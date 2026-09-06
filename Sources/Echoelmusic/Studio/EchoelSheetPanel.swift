//
//  EchoelSheetPanel.swift
//  Echoelmusic — Studio
//
//  One consistent NON-MODAL panel presentation for every tool/editor SHEET (Echoel
//  CI = one treatment everywhere). Instead of a hard full-screen modal that hides the
//  instrument, a sheet wearing `.echoelSheetPanel()`:
//    • opens at full height (.large) so editors get their room,
//    • drags down to .medium, where the instrument behind stays VISIBLE and
//      INTERACTIVE (pro-media HUD pattern — keep performing while a panel is open),
//    • shows a grab handle so it reads as draggable/dismissable (WCAG 2.2: a visible
//      affordance, not a hidden gesture),
//    • backs with a semi-transparent solid (NOT glass/blur — Uncodixfy-compliant).
//
//  Evidence base: accessible physical computing + professional media production favour
//  persistent, non-modal, edge-reachable control surfaces over stacked modal screens.
//
//  Apply INSIDE a `.sheet { … }` content closure. Do NOT apply to views that manage
//  their OWN `presentationDetents` (e.g. LearnView) — double-declaring conflicts.
//

#if canImport(SwiftUI)
import SwiftUI

struct EchoelSheetPanelModifier: ViewModifier {
    /// Per-presentation detent; starts full so editors aren't cramped, the user can
    /// pull it down to reveal and operate the instrument behind.
    @State private var detent: PresentationDetent = .large

    func body(content: Content) -> some View {
        content
            // ⭐ #1025 — a sheet wearing this panel also gets the readable ceiling. The
            // founder's clip shows the Routing sheet (`PatchbayView`) cut on BOTH sides
            // after a rotation: a sheet centres in its canvas, so a canvas wider than the
            // content expects loses the same amount at each edge.
            //
            // ⛔ AND THE FIRST VERSION OF THIS COMMENT SAID "every sheet inherits the
            // readable ceiling here, which is why the fix is two sites and not twenty" —
            // MEASURED AND FALSE, before the build reached the founder. `.echoelSheetPanel()`
            // is worn by FOUR sheets (FX · Input · Routing · LiveColabo); Open, Diagnostics
            // and Learn are presented WITHOUT it, and Learn must never wear it because it
            // manages its own detents (this file's own header says so, four lines up, in the
            // sentence the wrong claim sat under). Those three now carry `.readableWidth()`
            // directly, so the ceiling is one DEFINITION applied at seven sites — not one
            // site that magically covers everything. `TheLayoutHasAReadableWidthCeilingTests`
            // counts the wearers rather than trusting this paragraph.
            .readableWidth()
            .presentationDetents([.medium, .large], selection: $detent)
            .presentationDragIndicator(.visible)
            .presentationBackground(EchoelTheme.bg.opacity(0.92))
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

extension View {
    /// Present this sheet content as Echoel's consistent non-modal, draggable panel.
    /// (Not for views that set their own `presentationDetents`.)
    func echoelSheetPanel() -> some View { modifier(EchoelSheetPanelModifier()) }

    /// ⭐ #1025 — cap this content at a readable width and CENTRE it. The ONE definition of
    /// the idiom; every site that needs the ceiling calls this rather than repeating the
    /// pair, so the two `frame`s and their order exist exactly once in the app.
    ///
    /// THE ORDER IS THE WHOLE TRICK. The first `frame` caps the content; the second reclaims
    /// the full width so the capped column is CENTRED. With the cap alone the content hugs
    /// the leading edge and all the empty space piles up on one side — which reads as a bug,
    /// not as a margin.
    ///
    /// ⚠️ IT BINDS ON NO iPHONE IN PORTRAIT (440 pt widest today vs a 560 pt ceiling), so it
    /// changes nothing on the founder's device. It engages only where the canvas is genuinely
    /// too wide to read: landscape, and later iPad · Mac · Vision.
    ///
    /// ⚠️ NOT FOR THE IMMERSIVE VISUAL. `FloatingVisualWindow` and the `showVisual` cover must
    /// keep the FULL screen — "true Vollbild" is a stated rule in `WorkspaceView`. Pinned by
    /// the guard's counterweight.
    func readableWidth() -> some View {
        self
            .frame(maxWidth: EchoelTheme.readableContentWidth)
            .frame(maxWidth: .infinity)
    }
}
#endif
