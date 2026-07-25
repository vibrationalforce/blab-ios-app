#if canImport(SwiftUI)
import SwiftUI

// SurfaceSwitcher.swift
// Echoel — SurfaceHost is THE one main view. It hosted the Ableton-style Arrange
// timeline over the instrument zone until the pure-instrument verdict (#121,
// founder 2026-07-24: "keine Timeline etc nur das alte Interface mit create from
// within") removed the timeline — SurfaceHost now mounts only EchoelStudioView.
// The former 4-chip surface switching (SurfaceSwitcherBar) and the WorkspaceSurface
// enum stay in code (the @AppStorage raw values are still written by
// ArrangementView's legacy navigation), unmounted, reversible.
//
// Render safety: SurfaceHost reads NO @Observable models and no @AppStorage — it
// is a static wrapper, so it never rebuilds (freeze-rule trivially safe).

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

/// THE one main view. Once (founder 2026-07-10) this hosted the Ableton-style
/// arrangement (timeline on top, instrument below); the pure-instrument verdict
/// (#121, founder 2026-07-24 "keine Timeline etc nur das alte Interface mit create
/// from within") removed the timeline entirely — SurfaceHost is now a thin wrapper
/// that mounts `EchoelStudioView` (the "create from within" instrument) as the
/// whole screen. The pure-instrument epic (#121, Slice 4) is deleting the
/// now-unreachable DAW surfaces one by one (`ClipView` and
/// `ArrangeTimelineView` already removed); `SurfaceSwitcherBar` still stands,
/// unmounted, while `ChannelRackView` remains LIVE — embedded in
/// `EchoelStudioView`'s Mix panel, not a timeline surface. The v136 size
/// contract (fill + clipped) is preserved so nothing inflates past the screen.
@MainActor
struct SurfaceHost: View {
    /// PURE INSTRUMENT (founder 2026-07-24, verbatim "keine Timeline etc nur das
    /// alte Interface mit create from within"): the Arrange timeline is GONE from
    /// the home — `EchoelStudioView` (the "create from within" generative
    /// instrument) IS the whole main view. This is Slice H3 of the instrument-home
    /// revert and converges with the pure-instrument verdict (#121, Slice 4
    /// "DAW-UI-Removal"): the per-track DAW features are being removed, so the
    /// timeline that used to be the front door (the 2026-07-13 "tracks are home"
    /// default, H2 already folded) has no reason to mount — `ArrangeTimelineView`
    /// itself was deleted in Slice 4 (4b); the former fold bar still stands,
    /// unmounted.
    ///
    /// Render safety: dropping the timeline branch + the fold bar SHRINKS the
    /// composed tree, so it can only EASE the SwiftUI metadata budget, never grow
    /// it (black-screen law). H7 invariant holds trivially — `EchoelStudioView` is
    /// now the SOLE child at ONE structural position, so its identity (and any live
    /// bio / camera / transport session) is stable across every rebuild.
    var body: some View {
        EchoelStudioView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
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
