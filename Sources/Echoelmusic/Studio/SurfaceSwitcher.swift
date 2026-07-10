#if canImport(SwiftUI)
import SwiftUI

// SurfaceSwitcher.swift
// Echoel — the workspace surface switcher (founder 2026-07-09: "strukturiere so
// um, dass alles in dieser Arrange-View als Hauptansicht stattfindet"; approved
// Arrange-timeline plan, Stage 0). The `embedded:` surfaces (ArrangementView,
// ClipView, ChannelRackView) were built for exactly this host and coordinate via
// the SAME `@AppStorage("workspace.surface")` key they already read/write — this
// file adds the missing switcher; WorkspaceView adds the missing mount.
//
// Render safety: the bar reads ONLY the @AppStorage selection (changes on user
// tap, never per-frame). No bio/transport reads here.

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

/// Hosts all four surfaces, keeping every surface MOUNTED (opacity swap, the
/// pattern `ArrangementView` documents at its playhead leaf) so switching is
/// instant and store/leaf state survives. Hidden surfaces don't hit-test and are
/// hidden from VoiceOver.
@MainActor
struct SurfaceHost: View {
    @AppStorage("workspace.surface") private var surfaceRaw = WorkspaceSurface.initial.rawValue

    private var selected: WorkspaceSurface {
        WorkspaceSurface(rawValue: surfaceRaw) ?? .compose
    }

    var body: some View {
        ZStack {
            EchoelStudioView()
                .modifier(SurfaceVisibility(on: selected == .compose))
            // The beat-grid timeline (Stage 1c) — supersedes the section-list
            // ArrangementView as the Arrange surface (which stays in code).
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
