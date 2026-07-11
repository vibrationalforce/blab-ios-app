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

/// THE one main view (founder 2026-07-10: "Musik und Video Composing Ansicht
/// als einzige Hauptansicht wie in Ableton die Arrangement View, quer und
/// hochkant") — the Ableton arrangement layout: timeline on top, the instrument
/// / detail zone (EchoelStudioView) below it, one screen, no surface switching.
/// Clips and Mix are no longer separate destinations — their functions dissolve
/// into the track heads (convergence plan K2); ClipView/ChannelRackView stay in
/// code, unpresented (reversible). SurfaceSwitcherBar stays in code, unmounted.
///
/// Orientation: the split adapts — portrait gives the timeline ~1/3 (controls
/// need room), landscape ~1/2 (the arrangement is the star). Both columns keep
/// the v136 size contract (fill + clipped) so nothing inflates past the screen.
@MainActor
struct SurfaceHost: View {
    /// PLAY ENTRY (founder 2026-07-11, UI-survey verdict): the calm instrument is
    /// the front door, the arrangement is the second room. The timeline COLLAPSES
    /// to a thin bar by default so a newcomer lands on EchoelStudioView (which is
    /// already "Bio strip · Start · pads"), not a DAW cockpit. One tap expands the
    /// full Ableton timeline — nothing is lost for producers. Persisted, so a user
    /// who opens the timeline keeps it open. This does NOT undo the 2026-07-10
    /// "one main view = timeline" structure — the timeline is still THE surface,
    /// just folded until wanted (progressive disclosure).
    @AppStorage("workspace.timelineExpanded") private var timelineExpanded = false

    private static let collapsedBarHeight: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            // Min = toolbar(40) + ruler(20) + two 56-pt lanes — never less than
            // a readable arrangement; max keeps the instrument reachable.
            let timelineHeight = max(172, min(380, geo.size.height * (landscape ? 0.5 : 0.34)))
            VStack(spacing: 0) {
                // The collapse/expand bar — a leaf (no observable reads), always on
                // top so the timeline is one glanceable tap away in both states.
                timelineBar
                Divider().overlay(EchoelTheme.border)
                // AnyView-ERASED children (v10.79.144 launch-crash fix): the
                // instrument's body sits AT the SwiftUI metadata-decoder limit
                // (10.76.34 class — SIGSEGV at first render, CI-green, device-
                // dead). Erasing here cuts the composed ROOT tree's generic
                // depth back below the v143 baseline; erasure at this level is
                // effective because the overweight is in the COMPOSITION, not
                // inside the child bodies (unlike 10.76.35, where it wasn't).
                if timelineExpanded {
                    AnyView(
                        ArrangeTimelineView()
                            .frame(height: timelineHeight)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    )
                    Divider().overlay(EchoelTheme.border)
                }
                AnyView(
                    EchoelStudioView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                )
            }
        }
    }

    /// The one control that folds the arrangement in/out. Collapsed: an inviting
    /// "Timeline · arrangieren" row; expanded: a "Timeline" header with a chevron
    /// to fold it away again. Accent green stays reserved for live bio, so this
    /// uses the neutral text/dim tokens.
    private var timelineBar: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { timelineExpanded.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: timelineExpanded ? "chevron.down" : "rectangle.split.3x1")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EchoelTheme.dim)
                Text(timelineExpanded ? "Timeline" : "Timeline · arrangieren")
                    .font(EchoelTheme.font(12, timelineExpanded ? .regular : .medium))
                    .foregroundStyle(timelineExpanded ? EchoelTheme.dim : EchoelTheme.text)
                Spacer(minLength: 0)
                if !timelineExpanded {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(EchoelTheme.dim)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: Self.collapsedBarHeight)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(EchoelTheme.bg)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(timelineExpanded ? "Hide timeline" : "Show timeline to arrange")
        .accessibilityAddTraits(.isButton)
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
