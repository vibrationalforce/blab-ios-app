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
// the 4-surface workspace: `SurfaceSwitcherBar` was the LAST writer and the ONLY
// reader of `@AppStorage("workspace.surface")` (its chip body did `surfaceRaw =
// surface.rawValue`) once `ArrangementView` went with the timeline, and it was never
// mounted again after the pure-instrument verdict. So with it gone the key has no
// writer and no reader. (⛔ An earlier version of this note said `ArrangementView`
// was "the only thing that ever WROTE" the key. It was not — the bar wrote it too.
// The conclusion is unchanged, but this comment is positioned as the record the next
// deletion pass reads, and an incorrect ownership model is exactly what it must not
// teach.)
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

// ⛔ `SurfaceVisibility` (a `ViewModifier` that hid an inactive surface while keeping
// its state) was DELETED here too, 2026-07-28. It was the last piece of the 4-surface
// machinery and had been orphaned BEFORE this slice — `private`, so this file was the
// only place it could be used, and it was used nowhere in it. Its doc described a
// world of "every surface" and a ZStack union that has not existed since the timeline
// went, so leaving it would have been a map to a screen the app no longer has.
//
// Its one durable lesson is kept because it can bite the surviving `SurfaceHost`: a
// ZStack sizes to the UNION of its children, so a single child reporting
// wider-than-screen inflates the whole workspace VStack — header and transport
// included — past the display (the v136 founder screenshots, clipped at BOTH edges).
// That is why `SurfaceHost.body` still pins `maxWidth/maxHeight: .infinity` and
// `.clipped()`; those two lines are a size CONTRACT, not decoration.
#endif
