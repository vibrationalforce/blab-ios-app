//
//  StudioCaptionView.swift
//  Echoelmusic — Studio
//
//  The live "EchoelAI" caption under the controls while a take plays — a plain-English
//  narration of how the body is shaping the sound, refreshed on every re-seed.
//
//  WHY A SEPARATE @Observable + leaf view: the caption text changes on every composition
//  re-seed. When it lived as `@State` on EchoelStudioView, each change invalidated the
//  WHOLE root body — and because the panels are `AnyView`-wrapped (launch metadata-overflow
//  guard), a body rebuild loses the open Tonart/Genre `.menu` Picker's identity and closes
//  it ("dropdown am Anfang noch nicht stabil"). Holding the text in a tiny @Observable that
//  only THIS leaf view reads confines the re-seed invalidation here, so the Picker-hosting
//  body stays mounted and the menus stay selectable.
//

#if canImport(SwiftUI)
import SwiftUI
#if canImport(Observation)
import Observation
#endif

/// Minimal observable box for the live caption text. Mutating `text` invalidates only the
/// views that READ it (here, `StudioCaptionView`) — never the root studio body.
@MainActor
@Observable
final class StudioCaption {
    var text = ""

    /// Who this narration is about, for the heading above it (#644).
    ///
    /// ⭐ IT LIVES ON THE CAPTION, not on a second read, so the HEADING above the paragraph and
    /// the paragraph itself answer from the same instant. `BioExplanation.text(for:tempo:)` has
    /// marked its own provenance since #627 — while the demo drives it opens "EchoelAI (demo
    /// signal) — " — and the disclosure row above it claimed a body unconditionally. Two answers
    /// on one card, which is the #640/#641 collision on a third surface.
    ///
    /// ⛔ IT WAS A `Bool` FOR ONE COMMIT. `synthetic == false` meant BOTH "a real body" and
    /// "nothing was measured", so the heading said "What your body is doing to the sound" over
    /// a paragraph opening "no pulse measured yet" — and the doc on `BioExplanation.text`
    /// records that as the COMMON case (device log 2494: `body=0` in every generate breadcrumb
    /// for ~475 s). `BioNarrationDriver` has the third value; `.nothingMeasured` drops the
    /// possessive rather than inventing a subject.
    ///
    /// ⚠️ WRITTEN AT THE SAME STATEMENT AS `text`, from the same `frame`, and that adjacency is
    /// the whole guarantee. A separate read anywhere else could observe a different instant, and
    /// then the heading and the paragraph disagree exactly the way #641 had to be fixed twice.
    var driver: BioNarrationDriver = .nothingMeasured
}

@MainActor
struct StudioCaptionView: View {
    let caption: StudioCaption

    var body: some View {
        // ⛔ THE PLACEHOLDER MADE A PROVENANCE CLAIM IT CANNOT CHECK (#634b). It read
        // "The music is arising from your live signal — every control shapes it as it
        // plays." This view holds a `StudioCaption`, which is a single `String`; it has no
        // frame, no bus and no way to know whether a body is connected — so the sentence
        // was true only by luck, and false outright while the Simulation source runs.
        //
        // ⭐ REWORDED RATHER THAN MADE CONDITIONAL, deliberately. Threading a bio read in
        // here would put a live `@Observable` read into a view that `EchoelStudioView.body`
        // evaluates (the 10.76.41/50 freeze law), to qualify a string shown only BEFORE any
        // narration exists. The second half was always true on its own; dropping the first
        // half costs nothing and removes the claim entirely. The real sentence, once there
        // is one, names its own source — `BioExplanation.text(for:tempo:)`.
        Text(caption.text.isEmpty
             ? "Every control shapes the music as it plays."
             : caption.text)
            .font(EchoelTheme.font(11))
            .foregroundStyle(EchoelTheme.dim)
            .animation(.easeInOut(duration: 0.18), value: caption.text)
    }
}
#endif
