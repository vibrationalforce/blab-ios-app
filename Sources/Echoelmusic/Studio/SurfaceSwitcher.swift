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
// Render safety: SurfaceHost reads no @Observable models — only the
// @AppStorage fold toggle (user-tap frequency, freeze-rule safe).

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
    /// TRACKS ARE HOME (founder 2026-07-13, verbatim "Ich wollte alles über die
    /// Spuren machen" + AskUserQuestion → "Spuren/Timeline als Zuhause"): the
    /// arrangement/tracks surface is the DEFAULT front door, not the second room.
    /// The founder tested the 2026-07-11 "instrument first, timeline folded" default
    /// and found the per-track features (Piano Roll, Sound & FX, AUv3 assign,
    /// Automation, audio clips) effectively INVISIBLE — "die Sachen sind nicht da"
    /// was really "the tracks are folded away." So the timeline now opens by default
    /// and takes the dominant share; the calm instrument lives BELOW it, still one
    /// glance away (and scrollable). This SUPERSEDES the 07-11 PLAY-ENTRY default —
    /// do not revert to `false` without a fresh founder ask. Persisted, so anyone who
    /// folds it keeps it folded.
    /// REVERTED to `false` 2026-07-24 on the founder's fresh ask ("keine Timeline etc
    /// nur das alte Interface mit create from within"): the pure-instrument verdict (#121)
    /// removes the per-track features whose folded-away invisibility made tracks the home,
    /// so that objection is gone — the instrument ("create from within") is the front door
    /// again; the timeline is one tap away via the bar until the DAW-UI slice removes it.
    @AppStorage("workspace.timelineExpanded") private var timelineExpanded = false

    private static let collapsedBarHeight: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            // The collapse/expand bar — a leaf (no observable reads), always on
            // top so the timeline is one glanceable tap away in both states.
            timelineBar
            Divider().overlay(EchoelTheme.border)
            // AnyView-ERASED children (v10.79.144 launch-crash fix): erasing here cuts
            // the composed ROOT tree's generic depth back below the metadata limit;
            // effective because the overweight is in the COMPOSITION, not the bodies.
            //
            // ADAPTIVE SPLIT (founder 2026-07-14: "integriere alles im adaptiven Design …
            // alles greift ineinander"): when the timeline is shown it is the LIVING
            // canvas that FILLS the height (tracks are home), and the instrument shrinks
            // to its slim chip bar below — no black void. EchoelStudioView's zone is
            // itself conditional (it renders only with an open dropdown), so its "natural
            // height" here is just the chip bar when idle. Collapse the timeline and the
            // instrument takes the full height instead. Same surfaces, no duplicate
            // controls — the space just meshes.
            if timelineExpanded {
                AnyView(
                    ArrangeTimelineView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                )
                Divider().overlay(EchoelTheme.border)
            }
            // ONE EchoelStudioView at ONE structural position (H7, audit
            // CRITICAL): both branches used to create their own copy, so the
            // fold/unfold toggle changed the view's IDENTITY — SwiftUI tore the
            // whole instrument zone down and its `.onDisappear` ran
            // stopEverything(), killing a LIVE session (bio, camera, transport)
            // on a pure layout toggle, and dropping every open dropdown/@State.
            // The conditional timeline above is one structural slot; the studio
            // stays the LAST slot in both states, so identity — and the running
            // session — survives the fold. Only the frame flexes (value change,
            // not structure): timeline shown ⇒ natural height (chip bar when
            // idle); timeline folded ⇒ the instrument takes the full height.
            AnyView(
                EchoelStudioView()
                    .frame(maxWidth: .infinity,
                           maxHeight: timelineExpanded ? nil : .infinity)
                    .clipped()
            )
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
