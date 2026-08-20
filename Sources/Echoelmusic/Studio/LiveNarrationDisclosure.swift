//  LiveNarrationDisclosure.swift
//  Echoel — #644: the narration's HEADING stops claiming a body the paragraph does not name.
//
//  ⚠️ THE SURFACE IS PARKED BY FOUNDER DECISION AND NOBODY CAN READ IT TODAY. `memory/
//  decisions.md` (2026-07-12) records it verbatim: "Die Erklärung da brauchen wir erstmal nicht.
//  Das kommt später in nem richtig funktionierenden EchoelAI…", executed as "liveNarrationBanner
//  aus dem EchoelStudioView-Flow entfernt (Builder bleibt compiled, reversibel)". So this is the
//  `moodPadsSection` shape — decided — not an orphan drifting toward task #326, and re-dooring
//  it is a founder call rather than a refactor. Measured: `liveNarrationBanner` has ONE
//  occurrence in `Sources/`, its own declaration. Of the three surfaces this honesty family has
//  touched it is the LEAST read, not the most: `BodyShapesThisSoundLine()` and
//  `AlwaysOnBioPanelStrip()` are mounted once each, this chain zero times.
//
//  WHAT THIS FIXES — on that parked surface, so the door a real EchoelAI command layer
//  eventually brings does not arrive carrying a false claim. `BioExplanation.text(for:tempo:)`
//  has named its own subject since #627: under the demo it opens "EchoelAI (demo signal) — ",
//  and with nothing read it opens "tempo holds at N BPM; no pulse measured yet" and DROPS the
//  phrase " from your live signal,". The disclosure row above it said "What your body is doing
//  to the sound" in all three states. Same defect as #640, #641/#642 and #643.
//
//  ⛔ AND THE FIRST CUT USED A `Bool`, WHICH CLOSED ONLY HALF OF IT. "Not synthetic" meant both
//  "a real body" and "nothing was measured", so the heading still said "your body" over "no
//  pulse measured yet" — and `BioExplanation`'s own doc records THAT as the common case (device
//  log 2494: `body=0` in every generate breadcrumb for ~475 s). Both mandatory reviewers found
//  it independently, and the register in `TheMetricSheetRowsSayWhoseBodyTests` had written the
//  defect down one slice in advance. `BioNarrationDriver` has the third case.
//
//  ⭐ WHY A LEAF. The heading needs the fact the paragraph used, and it lives on `StudioCaption`.
//  ⛔ THE FIRST DRAFT JUSTIFIED THE MOVE WITH A PRESENT-TENSE FREEZE HAZARD — "reading it in
//  `liveNarrationBanner` would put an `@Observable` read into a body `EchoelStudioView.body`
//  evaluates" — and the paragraph above refutes it (#425): nothing mounts that property, so a
//  read there today reaches no body. The construction is still right for a PROSPECTIVE reason —
//  the day this is doored, that read WOULD sit in the Picker-hosting body (10.76.41/50), and a
//  leaf is what re-dooring needs anyway. `BodyShapesThisSoundLine` (#640) and
//  `AlwaysOnBioPanelStrip` (#643) are the same construction.
//
//  ⚠️ IT OWNS THE WHOLE DISCLOSURE, not just the label: heading and paragraph are emitted by ONE
//  body from ONE object, so they cannot answer different questions. #641 spent two follow-ups
//  learning that a heading and its rows derived through different paths WILL disagree.
//
//  ⚠️ THE PAIR CAN BE STALE, AND THE DIRECTION IS THE UNSAFE ONE — said plainly because the
//  house standard next door (`BodyShapesThisSoundLine`) ends on "over-marking, never
//  under-marking" and this inverts it. `caption.driver` is written only inside `generate()`, so
//  between a source switch and the next re-seed the card describes the PREVIOUS take: switching
//  Camera → Simulation leaves a running demo narrated as "your body" until the next generate.
//  The paragraph has had exactly this since #634b and the heading now inherits it, so the two
//  stay consistent with each other — which is what this slice guarantees, and it is not the same
//  as being current. Fixing it means re-deriving on a source change, which is a separate slice.
//
//  ⚠️ THE TAP TARGET IS LOAD-BEARING, not styling. ~16 pt of intrinsic label height was the whole
//  hit area (a `.plain` Button hit-tests its label bounds) — under WCAG 2.5.8's 24, let alone
//  HIG's 44. `minHeight` (never `height` — the #353 clipping class) plus a −5 outset reaches ≥44:
//  the bleed lands in the card's own 12 pt padding above and, when open, in the 10 pt gap to the
//  non-interactive caption below. Carried over verbatim from `EchoelStudioView`; pinned by
//  `TapTargetFloorTests`, re-anchored to this file in the same commit (§4).

#if canImport(SwiftUI)
import SwiftUI

/// The "what is happening to the sound" disclosure: one heading that names its own driver, and
/// the paragraph it introduces.
@MainActor
struct LiveNarrationDisclosure: View {
    let caption: StudioCaption
    @Binding var isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { isOpen.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 12))
                        .foregroundStyle(EchoelTheme.dim)
                    Text(caption.driver.heading)
                        .font(EchoelTheme.font(12, .semibold))
                        .foregroundStyle(EchoelTheme.dim)
                    Spacer(minLength: 8)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(EchoelTheme.dim)
                }
                .frame(minHeight: 34)
                .contentShape(Rectangle().inset(by: -5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(caption.driver.voiceOverLabel)
            .accessibilityHint("Shows or hides the plain-language description of what is "
                               + "shaping the music")
            if isOpen {
                StudioCaptionView(caption: caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
#endif
