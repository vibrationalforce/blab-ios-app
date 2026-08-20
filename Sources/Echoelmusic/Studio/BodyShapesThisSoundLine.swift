//
//  BodyShapesThisSoundLine.swift
//  Echoelmusic — Studio
//
//  #640: the Sound panel's top line said "Your body also shapes this sound while a session
//  runs" — unconditionally, including while the DEMO generator was the thing driving it.
//
//  ⭐ WHY THIS IS A STRUCT AND NOT TWO WORDS IN `soundPanel`. The line it replaces was a plain
//  `Text`, and the comment above that `Text` explained — correctly, at the time — that nothing
//  there read bio, so `EchoelStudioView.body` observed nothing new. Making the sentence
//  source-aware needs a bio read, and `soundPanel` is reached through `dropdownContent`, which
//  that body evaluates PERMANENTLY while hosting every `.menu` Picker of the instrument.
//  `AnyView(...)` is not an observation boundary; a `View` struct is (10.76.41/50). So the read
//  moves into its own body rather than the condition moving into the host's — the same
//  construction as `AlwaysOnBioPanelStrip`, `AutomationStatusStrip` and `BioStripView`.
//
//  ⛔ AND THAT IS WHY THE REGISTER SAID THIS COULD NOT BE DONE. `TheAlwaysOnRowsSayWhoseBody`
//  listed these sentences as fixable only "by changing the noun rather than adding a condition;
//  a condition here would put a live bio read into a property `EchoelStudioView.body`
//  evaluates". The first half of that is true of an INLINE condition and the register quietly
//  assumed no leaf — so a real, cheap option was booked as unavailable, and the alternative it
//  left standing was to weaken "your body" for every real player in order to be correct about
//  the demo. **A constraint recorded without its escape hatch reads as an impossibility**, which
//  is the same shape as the "DMX cannot carry metadata" retraction one slice earlier (#639).
//
//  ⚠️ THE COST, stated rather than assumed. `latestBio` is written when a publisher publishes,
//  and every wired publisher sends at ~1 Hz — CLAUDE.md's own correction: 10 Hz is the POLL,
//  ~1 Hz the applied rate. This leaf therefore re-renders about once a second and draws one
//  `Text`. `usableBio()` and not `latestBio`, because the sentence is a present-tense claim: a
//  frame past its source's freshness window drives nothing, so `nil` reads as "not synthetic"
//  and the wording stays exactly as it shipped.
//
//  ⚠️ ONE HONEST LIMIT, because it is the kind that never announces itself. `usableBio()` reads
//  a WALL CLOCK, but SwiftUI only re-evaluates this body when an OBSERVED value changes — and
//  the only observed value here is `latestBio`. So time passing cannot by itself flip the
//  subject back: if the demo stops publishing entirely, the last rendered sentence keeps saying
//  "the simulated demo source" until something re-renders the leaf. That is bounded and it errs
//  in the SAFE direction — over-marking a demo that has stopped, never under-marking one that
//  is running — and the moment a real source publishes, `latestBio` changes and the subject
//  corrects itself. `AlwaysOnBioRow` documents the same bounded lag against `usableBio()` for
//  the rows next door; naming it in both places beats a footnote in neither.

#if canImport(SwiftUI)
import SwiftUI

/// The Sound panel's "what moves these rows by itself" line, with the driver named honestly.
@MainActor
struct BodyShapesThisSoundLine: View {
    @Environment(EngineBus.self) private var bus

    var body: some View {
        let synthetic = bus.usableBio()?.source.isSynthetic ?? false
        Text(BioShapedParameter.soundPanelSentence(synthetic: synthetic))
            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
