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
            // ⛔ #1027 — a `.readableWidth()` cap stood here (#1025) and is removed on
            // founder order: he wants every view to FILL the screen. A sheet gets its
            // width from its presentation, and this modifier no longer takes any of it
            // away. The real portrait overflow was three rows inside `PatchbayView`,
            // repaired there (#1026).
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
