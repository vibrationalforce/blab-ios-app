//
//  AlwaysOnBioRow.swift
//  Echoelmusic — Studio
//
//  ONE ROW, TWO CONTAINERS (#553). This type was `private` inside `EchoelFXView.swift` and is
//  moved here UNCHANGED except for its access level, so the four always-on channels can be
//  read in the FX sheet AND in the Bio panel without a second rendering drifting from the
//  first. The model was already shared (`AlwaysOnBioChannel`); the ROW was not, and a
//  second hand-built copy in the panel is exactly the two-spellings-of-one-decision defect
//  (#416) — with the extra edge that a readout copy can drift in what it CLAIMS about the
//  body, not just in how it looks.
//
//  ⚠️ WHY A MOVE AND NOT A WRAPPER: the row body was already container-agnostic (a `VStack`
//  of `Text` + a bar, no `List`-only API). Only its former wrapper `AlwaysOnBioView` is
//  `List`-shaped — it keeps its `Section` and `.listRowBackground` in `EchoelFXView`, and the
//  Bio panel's `AlwaysOnBioPanelStrip` below wraps the same rows in a `VStack`. The container
//  differs because the hosts differ; the row does not.
//
//  ⚠️ THE FREEZE LAW IS THE REASON THE STRIP IS ITS OWN `View` STRUCT, not tidiness. `bioPanel`
//  is reached through `dropdownContent`, which `EchoelStudioView.body` evaluates PERMANENTLY —
//  and that body hosts every `.menu` Picker of the instrument. A `bus.latestBio` read inlined
//  there would register the root as an observer of the bio publisher and tear an open Picker
//  down on every publish (10.76.41/50). `AnyView(...)` is not an observation boundary; a
//  `View` struct is. Same construction as the two leaves already in that panel
//  (`BioStripView`, `BreathCoachStrip`) and stated here because the tempting later
//  simplification — "it is only four rows, inline them" — IS the regression.
//

#if canImport(SwiftUI)
import SwiftUI

/// One always-on channel: name, what it shapes, the value the engine receives, a bar, and —
/// since #500 — whether that value is still ARRIVING.
///
/// Same honesty rule as `BioModContributionRow` and for the same reason: an unmeasured channel
/// shows "—" and draws NO bar. Printing "0.50" with a half-full bar would read as a
/// measurement sitting mid-scale, which is precisely the confusion the neutral creates.
///
/// ⚠️ THE `TimelineView` IS LOAD-BEARING, NOT DECORATION, and removing it is the obvious later
/// "it's only four static rows" simplification. `isHeld` flips on the passage of TIME, and the
/// event that makes it true — a source that STOPPED publishing — is by definition the event
/// that stops invalidating this body. Without a tick the row would freeze at its last
/// evaluation, which is the instant the frame arrived, and therefore assert liveness forever:
/// worse than the state #500 is about. 1 Hz is chosen against the shortest window it has to
/// resolve (`BioSource.freshnessWindow` = 5 s for `.fallback`); it costs one small redraw per
/// second while the FX sheet is open, and it stays INSIDE the row so nothing above it churns.
///
/// ⚠️ AND IT MUST STAY IN THE ROW rather than wrap the `ForEach` in either host: in
/// `AlwaysOnBioView` the rows are `Section` children in a `List`, so a `TimelineView` around
/// all four would put one container where four list rows belong. Four 1 Hz tickers are the
/// cheap half of that trade. (⛔ That sentence named ONE host until #553 and now there are two.
/// In `AlwaysOnBioPanelStrip`'s `VStack` a single wrapper would lay out fine — the reason there
/// is the other one: the tick has to travel WITH the row, or the second host silently gets a
/// row that asserts liveness forever. One row, one ticker, both containers.)
@MainActor
struct AlwaysOnBioRow: View {
    let channel: AlwaysOnBioChannel
    let frame: BioSampleFrame?

    var body: some View {
        // ⛔ THE FIRST VERSION JUSTIFIED THIS CHOICE WITH A CLOCK MISMATCH THAT DOES NOT EXIST,
        // and it said so in three artifacts at once (here, the guard's doc, the guard's failure
        // message). It read: "the same clock `usableBio()` measures age on, never the
        // `TimelineView` context date … the exact two-clock mismatch #434 paid for one file
        // over." BOTH halves are refuted inside this repo. `EngineBus` states verbatim that its
        // stamps are "`CFAbsoluteTime` (seconds since the 2001 reference date, i.e.
        // `CFAbsoluteTimeGetCurrent()` / `Date.timeIntervalSinceReferenceDate`)" — a `Date` from
        // the schedule context is therefore the SAME clock and the SAME epoch, with nothing to
        // convert. And #434's mismatch was `frame.timestamp` (a stamp that stands still exactly
        // when a duration is needed) against the wall clock: a different SOURCE of time. Both
        // candidates here are wall clocks, so #434 does not apply. Left as a retraction rather
        // than deleted, because a "do not do X" note whose stated reason is checkable and false
        // is worse than none — the next session refutes it in one grep and does X.
        //
        // ⭐ THE REAL REASON, and it survives the retraction: a `TimelineSchedule` context date
        // is the SCHEDULED instant, not the redraw instant. This body is rebuilt on every
        // `latestBio` publish, and each rebuild mints a fresh `.periodic(from: .now, by: 1)`
        // with a new phase, so the context date can lag the draw. `CFAbsoluteTimeGetCurrent()`
        // is read when the row actually renders.
        //
        // ⚠️ AND THE HONEST RESIDUE: the CLOCK agrees with `usableBio()`, the INSTANT need not.
        // The row re-evaluates at 1 Hz, so for up to ~1 s after expiry it still renders un-held
        // while `usableBio()` already returns nil. Bounded and harmless — but it is a lag, not
        // an identity, and the earlier "cannot disagree about what 6 s old means" overstated it.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            content(channel.reading(in: frame, now: CFAbsoluteTimeGetCurrent()))
        }
    }

    @ViewBuilder
    private func content(_ reading: AlwaysOnBioReading) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(channel.name)
                    .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.text)
                Text(channel.shapes)
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim).lineLimit(1)
                Spacer(minLength: 0)
                // #634 — origin BEFORE age, because they answer different questions and the
                // origin is the one that decides whether the number describes a person at all.
                // Dim with a hairline outline: not `EchoelTheme.success` (green is reserved for
                // a real body on the wire — the same reservation `BioStripView.demoTag` states)
                // and not `warning` (running the demo is a choice, not a fault).
                if reading.isSynthetic {
                    Text("Demo")
                        .font(EchoelTheme.font(10, .semibold))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                            .strokeBorder(EchoelTheme.text.opacity(0.25), lineWidth: 1))
                        .foregroundStyle(EchoelTheme.dim)
                }
                if reading.isHeld {
                    // The word, not a countdown: a ticking age would be a second live-looking
                    // number on a row whose whole point is that nothing here is live.
                    Text("held")
                        .font(EchoelTheme.font(10, .semibold)).foregroundStyle(EchoelTheme.dim)
                }
                Text(reading.isMeasured
                     ? EchoelDecimalText.string(Double(reading.value), decimals: 2)
                     : "—")
                    .font(EchoelTheme.font(11).monospacedDigit()).foregroundStyle(EchoelTheme.dim)
            }
            signalBar(reading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(reading))
    }

    /// VoiceOver gets the same facts in the same order, and never a percentage for a channel
    /// the body did not report (#484's compliance edge: the SIGNAL is the subject here, never
    /// the body — "not measured" and "no longer arriving" describe the reading, not the
    /// person, and neither sentence may be readable as an observation about a heart).
    private func accessibilityText(_ reading: AlwaysOnBioReading) -> String {
        // #634 — leads, for the same reason the chip sits before "held": a listener who hears
        // "Coherence at 62 percent" has already been told a fact about their body, and a
        // qualifier arriving after it corrects a claim instead of preventing one.
        //
        // ⛔ THIS SAID "same wording as the five sibling surfaces" AND MINTED A SIXTH (#634b).
        // Measured, there are three established spellings, and they differ by POSITION, not by
        // accident: `"Bio source: simulated demo, not your body"` labels a whole ELEMENT
        // (`BioStripView`, the widget, the watch) · `"Simulated demo, "` is a PREFIX on a
        // sentence that continues (`HeaderMonitors`, `LiveColaboView`) · `"demo values, not
        // your body"` is a SECTION header (`BioMetricInfo`). The first draft here grafted the
        // strip's tail onto the pill's prefix — a fourth spelling of one decision (#416),
        // claiming in the same breath to be identical to five.
        //
        // ⭐ RESOLVED BY POSITION: this marker is a prefix on a sentence that continues, so it
        // takes the prefix form. `HeaderMonitors` states the trade for that form — "Simulated
        // demo, 142 beats per minute" cannot be mistaken for a reading — and it holds here.
        //
        // ⚠️ IT IS COMPUTED BEFORE THE `isMeasured` GUARD, not after, because the CHIP is gated
        // on `isSynthetic` alone. Leaving the unmeasured branch bare would put "Demo" on screen
        // and not in the ear — and this method's own doc says VoiceOver gets the same facts in
        // the same order. (`BioSimulator` measures all four channels, so that branch is not
        // reachable under Simulation today; it is written for the law, not for a live case.)
        let origin = reading.isSynthetic ? "Simulated demo, " : ""
        guard reading.isMeasured else {
            return origin
                + "\(channel.name), not measured, shaping \(channel.shapes) at the neutral value"
        }
        let percent = Int((reading.value * 100).rounded())
        guard reading.isHeld else {
            return origin + "\(channel.name) at \(percent) percent, shaping \(channel.shapes)"
        }
        return origin + "\(channel.name) held at \(percent) percent, no longer arriving, "
            + "still shaping \(channel.shapes)"
    }

    private func signalBar(_ reading: AlwaysOnBioReading) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(EchoelTheme.border.opacity(0.4))
                if reading.isMeasured {
                    // Drawn, because the engine really is still being handed this — but dimmed
                    // when held, so a glance separates a moving body from a parked one without
                    // reading the word.
                    //
                    // ⭐ #634: and NOT in the accent when the frame is the demo generator's. The
                    // bar is the loudest thing on the row; painting a fabricated value in the
                    // colour this app reserves for a live body is the same over-claim the lock
                    // accent made on the header pill before #627. Held-and-demo keeps the
                    // held dimming on top — the two facts compose, they do not replace.
                    Capsule().fill((reading.isSynthetic ? EchoelTheme.dim : EchoelTheme.accent)
                                   .opacity(reading.isHeld ? 0.35 : 1))
                        .frame(width: Swift.max(2, geo.size.width
                                                * CGFloat(Swift.min(1, Swift.max(0, reading.value)))))
                }
            }
        }
        .frame(height: 4)
    }
}

/// The Bio-panel form of the always-on readout: the same four rows the FX sheet shows, at the
/// place where the panel's own sentence PROMISES that the body drives the sound (#553).
///
/// ⭐ WHY IT IS HERE AT ALL. #542 put the four channel NAMES in the Bio panel and left the live
/// numbers three levels away — Effects › All parameters › scroll to the bottom. A player who
/// asks "is my body actually reaching the engine right now?" asks it where the promise is
/// made, and the honest answer (a value, and whether that value is a measurement) already
/// existed; only its address was wrong.
///
/// ⚠️ IT READS `latestBio`, LIKE `AlwaysOnBioView`, AND FOR THE SAME REASON: the always-on
/// channels are polled raw by both sound producers, with no freshness gate. A readout of that
/// path must show what the SOUND path sees, or it would report a channel as gone while the
/// engine is still being handed it. Do not "fix" this to `usableBio()` — that gate belongs to
/// the FX ROUTES, and the disagreement between the two is registered, not accidental.
///
/// ⚠️ NO `Section`, NO `.listRowBackground`: this strip lives in a `VStack`, not a `List`.
/// Adding either is what makes a row render as a stray inset inside the panel.
@MainActor
struct AlwaysOnBioPanelStrip: View {
    @Environment(EngineBus.self) private var bus

    var body: some View {
        let frame = bus.latestBio
        VStack(alignment: .leading, spacing: 8) {
            ForEach(AlwaysOnBioChannel.allCases) { channel in
                AlwaysOnBioRow(channel: channel, frame: frame)
            }
        }
    }
}
#endif
