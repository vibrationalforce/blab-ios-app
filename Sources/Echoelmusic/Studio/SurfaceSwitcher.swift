#if canImport(SwiftUI)
import SwiftUI

// SurfaceSwitcher.swift
// Echoel — SurfaceHost is THE one main view. It hosted the Ableton-style Arrange
// timeline over the instrument zone until the pure-instrument verdict (#121,
// founder 2026-07-24: "keine Timeline etc nur das alte Interface mit create from
// within") removed the timeline — SurfaceHost now mounts only EchoelStudioView.
// The former 4-chip surface switching and its enum are gone — see the note below.
//
// Render safety: SurfaceHost reads NO @Observable models and no @AppStorage — it
// is a static wrapper, so it never rebuilds (freeze-rule trivially safe).

// ⛔ `WorkspaceSurface` (the 4-case enum) and `SurfaceSwitcherBar` (its chip row)
// were DELETED here on 2026-07-28, #132 Slice 5. Both were unmounted leftovers of
// the 4-surface workspace: `ArrangementView`, the only thing that ever WROTE the
// persisted raw values, went with the timeline, and `SurfaceSwitcherBar` — the only
// reader of `@AppStorage("workspace.surface")` — was never mounted again after the
// pure-instrument verdict. So the key had no writer and no reader.
//
// The stored `@AppStorage` key is deliberately NOT migrated or cleared: an unread
// UserDefaults string costs nothing, and a deletion pass is exactly the wrong place
// to start touching persisted user state.
//
// ⚠ WHAT ALMOST WENT WRONG, recorded because the next deletion will face it again:
// an audit reported this file as "3 grep hits, all inside itself — free deletion".
// That was wrong twice. It missed `Tests/EchoelmusicTests/WorkspaceSurfaceTests.swift`
// (deleted with this change, since it pinned raw values nothing persists any more),
// and — much worse — the file ALSO contains `SurfaceHost`, which `WorkspaceView`
// mounts as the app's entire main view. Deleting "the file" would have deleted the
// screen. Grep the TYPE, never the file.

/// THE one main view. Once (founder 2026-07-10) this hosted the Ableton-style
/// arrangement (timeline on top, instrument below); the pure-instrument verdict
/// (#121, founder 2026-07-24 "keine Timeline etc nur das alte Interface mit create
/// from within") removed the timeline entirely — SurfaceHost is now a thin wrapper
/// that mounts `EchoelStudioView` (the "create from within" instrument) as the
/// whole screen. The pure-instrument epic (#121, Slice 4) is deleting the
/// now-unreachable DAW surfaces one by one (`ClipView`, `ArrangeTimelineView` and,
/// as of Slice 5, the chip bar and its enum from this very file — see the note at
/// the top). `ChannelRackView` used to be the one exception — LIVE, embedded in
/// `EchoelStudioView`'s Mix panel — but the drum removal (founder 2026-07-26,
/// "es soll keine Drums geben. Auch nicht im Mixer.") unmounted it: it mixed
/// the 8 drum channels, and there are none. It is now DELETED (#167, 2026-07-27),
/// which is why this paragraph is history rather than a map. The v136 size contract (fill +
/// clipped) is preserved so nothing inflates past the screen.
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
    /// itself was deleted in Slice 4 (4b), and the former fold bar in Slice 5.
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
