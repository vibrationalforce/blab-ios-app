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
            // ⭐ #1025 — every sheet inherits the readable ceiling here, which is why the
            // fix is two sites and not twenty. The founder's clip shows the Routing sheet
            // (`PatchbayView`) cut on BOTH sides after a rotation: a sheet centres in its
            // canvas, so a canvas wider than the content expects loses the same amount at
            // each edge. Capping and re-centring turns that into margins.
            //
            // The doubled `frame` is the same idiom as `WorkspaceView`'s: cap, then reclaim
            // the full width so the capped content is centred rather than leading-aligned.
            // It binds on no iPhone in portrait (see `readableContentWidth`).
            //
            // ⚠️ THIS MODIFIER IS NOT UNIVERSAL, and a session repairing a wide sheet has to
            // check which one it has: this file's own header says views that manage their
            // OWN `presentationDetents` (LearnView) must not wear it, so they do not get the
            // ceiling from here either. The guard counts the wearers rather than assuming.
            .frame(maxWidth: EchoelTheme.readableContentWidth)
            .frame(maxWidth: .infinity)
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
}
#endif
