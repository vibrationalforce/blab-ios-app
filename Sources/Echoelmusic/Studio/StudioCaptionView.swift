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
}

@MainActor
struct StudioCaptionView: View {
    let caption: StudioCaption

    var body: some View {
        Text(caption.text.isEmpty
             ? "The music is arising from your live signal — every control shapes it as it plays."
             : caption.text)
            .font(EchoelTheme.font(11))
            .foregroundStyle(EchoelTheme.dim)
            .animation(.easeInOut(duration: 0.18), value: caption.text)
    }
}
#endif
