#if canImport(SwiftUI)
import SwiftUI

// SurfaceSwitcher.swift
// Echoel — SurfaceHost is THE one main view (founder 2026-07-10: "Musik und
// Video Composing Ansicht als einzige Hauptansicht wie in Ableton die
// Arrangement View… Wo bist du falsch abgebogen?"): the Arrange timeline over
// the instrument zone, one screen, portrait AND landscape. The former 4-chip
// surface switching (Stage 0) is REMOVED from navigation — the founder's
// "kein View-Springen" was the plan all along; SurfaceSwitcherBar and the
// WorkspaceSurface enum stay in code (the @AppStorage raw values are still
// written by ArrangementView's legacy navigation), unmounted, reversible.
//
// Render safety: SurfaceHost reads no observables (geometry only).

/// The workspace surfaces. Raw values are PERSISTED via @AppStorage and must
/// stay stable — `compose` and `clips` are the values `ArrangementView`'s
/// empty-state navigation already writes (do not rename).
enum WorkspaceSurface: String, CaseIterable {
    case arrange, clips, compose, mix

    /// Default surface. "Studio" (compose) until the Arrange timeline is real
    /// (plan Stage 2 flips this to `.arrange`) — never ship an empty home.
    static let initial: WorkspaceSurface = .compose

    var title: String {
        switch self {
        case .arrange: return "Arrange"
        case .clips:   return "Clips"
        case .compose: return "Studio"
        case .mix:     return "Mix"
        }
    }

    var systemImage: String {
        switch self {
        case .arrange: return "rectangle.split.3x1"
        case .clips:   return "square.grid.3x3"
        case .compose: return "music.note"
        case .mix:     return "slider.horizontal.3"
        }
    }
}

/// Compact chip row under the transport bar — one tap switches the working
/// surface. Selected chip = text-on-fill (accent green stays reserved for the
/// live bio/playing state, per the theme rule).
@MainActor
struct SurfaceSwitcherBar: View {
    @AppStorage("workspace.surface") private var surfaceRaw = WorkspaceSurface.initial.rawValue

    private var selected: WorkspaceSurface {
        WorkspaceSurface(rawValue: surfaceRaw) ?? .compose
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WorkspaceSurface.allCases, id: \.self) { surface in
                chip(surface)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(EchoelTheme.bg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace")
    }

    private func chip(_ surface: WorkspaceSurface) -> some View {
        let isOn = surface == selected
        return Button {
            // Breadcrumb: device logs must show WHAT was switched WHEN — the
            // crackle report ("knistert beim Umschalten") was untriageable
            // without it.
            log.log(.info, category: .ui, "Surface switch → \(surface.rawValue)")
            surfaceRaw = surface.rawValue
        } label: {
            HStack(spacing: 5) {
                Image(systemName: surface.systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(surface.title)
                    .font(EchoelTheme.font(12, isOn ? .semibold : .regular))
            }
            .foregroundStyle(isOn ? EchoelTheme.text : EchoelTheme.dim)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .fill(isOn ? EchoelTheme.fill : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(isOn ? EchoelTheme.text.opacity(0.35) : EchoelTheme.border,
                              lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle().inset(by: -5))   // 38 pt-class touch target
        .accessibilityLabel(surface.title)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// NOTBETRIEB Plan B (v10.79.146): v144 AND the v145 AnyView-erasure fix both
/// crash at first render on device (metadata class, CI-green) — so this is the
/// pre-agreed fallback, NOT a third blind fix: the EXACT v143 tree, which
/// demonstrably launched. Byte-identical structure to 12922ca~1 (flat ZStack,
/// all four surfaces mounted via SurfaceVisibility opacity swap) with ONE
/// difference: `selected` is pinned to `.compose` (the @AppStorage read is
/// dropped) so nobody strands on a persisted "arrange" value now that
/// SurfaceSwitcherBar is unmounted. Effective UI: EchoelStudioView fullscreen.
///
/// The one-main-view Ableton split (timeline over instrument) returns as v147+
/// ONLY after the founder's Analysedaten screenshots show the real crash frame
/// — see .deploy/release v146 notes. The founder's one-main-view direction is
/// unchanged; this is launch-first sequencing, not a scope revert.
@MainActor
struct SurfaceHost: View {
    /// Pinned to Studio (see header). v143's @AppStorage selection stays out —
    /// with the chip bar unmounted there is no way back from another surface.
    private var selected: WorkspaceSurface { .compose }

    var body: some View {
        ZStack {
            EchoelStudioView()
                .modifier(SurfaceVisibility(on: selected == .compose))
            // The beat-grid timeline — mounted-invisible exactly as in v143
            // (which launched); it returns to the foreground with v147+.
            ArrangeTimelineView()
                .modifier(SurfaceVisibility(on: selected == .arrange))
            ClipView(embedded: true)
                .modifier(SurfaceVisibility(on: selected == .clips))
            ChannelRackView(embedded: true)
                .modifier(SurfaceVisibility(on: selected == .mix))
        }
    }
}

/// Show/hide a mounted surface: invisible surfaces take no touches and are
/// silent for VoiceOver, but keep their state (no teardown churn).
///
/// SIZE CONTRACT (v136 regression fix — founder screenshots: chrome + content
/// clipped at BOTH edges on every surface): a ZStack sizes to the UNION of its
/// children, so ONE sheet-era surface reporting wider-than-screen inflated the
/// whole workspace VStack (header/transport included) past the display. Pinning
/// every child to exactly the proposed size (maxWidth/maxHeight .infinity =
/// adopt the proposal) caps the union at screen size — the modifier the old
/// shell applied to EchoelStudioView directly. `.clipped()` keeps any internal
/// overflow inside the surface instead of painting over the chrome.
private struct SurfaceVisibility: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .opacity(on ? 1 : 0)
            .allowsHitTesting(on)
            .accessibilityHidden(!on)
            .zIndex(on ? 1 : 0)
    }
}
#endif
