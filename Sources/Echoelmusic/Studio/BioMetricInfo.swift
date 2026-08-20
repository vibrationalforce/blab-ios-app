// BioMetricInfo.swift
// Echoel — plain-language explanations for every bio readout. Tap a value (HR,
// HRV, coherence, RMSSD…) and learn what it means. Science-first, accessible, and
// explicit that this is for music + self-observation, NOT medical diagnosis.
// This is the "app as a school" layer: every number teaches what it means.
//
// The content model is pure Foundation (no SwiftUI) so the copy is unit-tested;
// the small presentation view lives behind a SwiftUI guard below.

import Foundation

/// A bio metric the app displays and can explain on tap.
public enum BioMetric: String, CaseIterable, Identifiable, Sendable {
    case heartRate, hrv, rmssd, sdnn, pnn50, coherence, breath

    public var id: String { rawValue }

    /// Full title, e.g. "Heart-Rate Variability".
    public var title: String {
        switch self {
        case .heartRate: return "Heart Rate"
        case .hrv:       return "Heart-Rate Variability"
        case .rmssd:     return "RMSSD"
        case .sdnn:      return "SDNN"
        case .pnn50:     return "pNN50"
        case .coherence: return "Coherence"
        case .breath:    return "Breathing Rate"
        }
    }

    /// Unit shown next to the value.
    public var unit: String {
        switch self {
        case .heartRate: return "bpm"
        case .hrv:       return "ms"
        case .rmssd, .sdnn: return "ms"
        case .pnn50:     return "%"
        case .coherence: return "0–1"
        case .breath:    return "breaths/min"
        }
    }

    /// One-line summary.
    public var summary: String {
        switch self {
        case .heartRate: return "How fast your heart is beating right now."
        case .hrv:       return "The natural beat-to-beat variation in your heartbeat."
        case .rmssd:     return "A short-term HRV measure of moment-to-moment change."
        case .sdnn:      return "Overall HRV across the whole reading."
        case .pnn50:     return "How often consecutive beats differ by more than 50 ms."
        case .coherence: return "How much of your heartbeat gathers into one slow rhythm."
        case .breath:    return "How many breaths you take per minute."
        }
    }

    /// A short, plain-language paragraph.
    public var detail: String {
        switch self {
        case .heartRate:
            return "Beats per minute. It rises with effort, excitement or stress and falls with rest. In Echoelmusic your heart rate sets the energy and tempo of the music."
        case .hrv:
            return "The tiny differences in time between one heartbeat and the next. Higher variability generally reflects a relaxed, adaptable state; lower variability often goes with stress or fatigue. Echoelmusic uses it to open or close the timbre. Reliable beat-to-beat HRV needs a chest strap; the camera shows it only when the reading is physiologically plausible, otherwise “—”."
        case .rmssd:
            return "Root mean square of successive differences between heartbeats — a standard short-term HRV measure that mostly reflects your parasympathetic ‘rest-and-digest’ activity. Higher values often go with a more relaxed moment."
        case .sdnn:
            return "Standard deviation of the time between normal heartbeats across the whole reading. It captures your total heart-rate variability from many sources at once."
        case .pnn50:
            return "The percentage of consecutive heartbeats that differ by more than 50 milliseconds — another marker of parasympathetic activity. Higher values usually accompany a more relaxed moment."
        case .coherence:
            return "How much of your heart-rate variability gathers into a single slow rhythm. Echoelmusic measures it as a real frequency spectrum of your heartbeat (most accurate with a chest strap), peaking around 0.1 Hz — roughly six breaths a minute. It tends to be highest during slow, steady breathing; higher coherence makes the music calmer and more spacious."
        case .breath:
            return "Your breathing rate. Slow breathing (about five to six breaths a minute) tends to raise coherence. Echoelmusic’s optional breathing guide paces it for you, and your breath phase shapes how the music moves."
        }
    }

    /// Shown under every explanation — the safety/scope disclaimer.
    public static let disclaimer =
        "For music and self-observation only — not a medical device and not for diagnosis. Readings are approximate; don’t use them for health decisions."

    /// The origin note that belongs beside a heading claiming the body is showing something,
    /// or `nil` when a real body genuinely is (#646).
    ///
    /// ⛔ THE GUIDE SHEET HAD ONE MARKED HEADING AND ONE UNMARKED, WHICH IS WORSE THAN NEITHER.
    /// `"How your body shapes the sound"` carried a conditional note; the sheet's TOP heading,
    /// `"What your body is showing"`, carried none — and it is the first line a reader sees
    /// after tapping a metric cell. #636's law in one line: half-marked teaches the reader that
    /// an unmarked claim is the real one, so the marked sibling actively made the unmarked title
    /// more convincing.
    ///
    /// ⭐ ONE DEFINITION, TWO CALLERS (#416). Both strings were inlined at a single site; a
    /// second heading needing them is exactly the moment a third spelling grows. It asks
    /// `BioSource.isSynthetic` rather than re-writing `== .fallback` — that comparison is the
    /// one definition (#639), and this file spelled it out twice.
    ///
    /// ⚠️ THE TITLE KEEPS ITS WORDS. A heading that rewrites itself as the source changes is
    /// disorienting where a suffix is not, and the sibling section header already established
    /// the suffix shape in this sheet. (⛔ "the sibling 54 lines down" stood here: that gap was
    /// the PARENT's, and this very commit made it 73. A distance between two lines is a date,
    /// not a fact, and it is deleted rather than refreshed — the same handling this repo chose
    /// for #642's line-distance and #473's mis-attached line count.) The stronger reason to
    /// keep the words: a per-source retitle would make the sheet's LOUDEST type flicker at the
    /// freshness boundary, which is the straddle the rest of this slice is closing.
    ///
    /// ⚠️ ONE DOCTRINE TENSION, RESOLVED IN THE OPEN rather than silently. The three-spelling
    /// positional rule further down says a whole-ELEMENT label takes the "Bio source: simulated
    /// demo, not your body" form, and a sheet title labels a whole element — but
    /// `TheMetricSheetRowsSayWhoseBodyTests` bans that spelling in this file. The suffix form
    /// wins because the sibling heading in the same sheet already uses it and a reader compares
    /// the two headings, not this file against the doctrine.
    ///
    /// ⭐ SIGNATURE DIVERGES FROM ITS THREE SIBLINGS ON PURPOSE. `alwaysOnSentence(synthetic:)`,
    /// `bioPanelSentence(synthetic:)` and `soundPanelSentence(synthetic:)` all take a `Bool`.
    /// This takes the frame and returns `String?` because it must express THREE states, and
    /// #644 paid a cycle for exactly the `Bool` that could not (it said "your body" over "no
    /// pulse measured yet"). Same family, one state more.
    public static func originNote(for frame: BioSampleFrame?) -> String? {
        guard let frame else { return "read your pulse to see it move" }
        return frame.source.isSynthetic ? "demo values, not your body" : nil
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// A small explanation sheet for a tapped bio metric.
struct BioMetricInfoView: View {
    let metric: BioMetric
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.title)
                        .font(EchoelTheme.font(20, .semibold))
                        .foregroundStyle(EchoelTheme.text)
                    Text(metric.unit)
                        .font(EchoelTheme.font(12))
                        .foregroundStyle(EchoelTheme.dim)
                }
                Spacer()
                // `EchoelTheme.font`, not `.system(size:)` — #353f. Every other string in this
                // sheet grows with Larger Text; an absolute point size does not participate in
                // Dynamic Type at all, so at an accessibility size the explanation swelled and
                // the only way OUT of it stayed at 15 pt. A sheet whose escape hatch is the
                // smallest thing on screen is worse than one that never grew.
                Button("Done") { dismiss() }
                    .font(EchoelTheme.font(15, .semibold))
                    .foregroundStyle(EchoelTheme.accent)
            }

            Text(metric.summary)
                .font(EchoelTheme.font(15))
                .foregroundStyle(EchoelTheme.text)

            Text(metric.detail)
                .font(EchoelTheme.font(14))
                .foregroundStyle(EchoelTheme.text)   // legible prose (was dim = 0.55 opacity, too faint)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(EchoelTheme.border)

            Text(BioMetric.disclaimer)
                .font(EchoelTheme.font(12))
                .foregroundStyle(EchoelTheme.text.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .lineLimit(nil)   // hard override: never inherit a lineLimit(1) from the presenter
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EchoelTheme.bg)
        .presentationDetents([.medium])
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title). \(metric.detail). \(BioMetric.disclaimer)")
    }
}

/// One place that explains ALL the live bio numbers at once (founder 2026-07-03:
/// "HRV etc. soll erklärt werden"). Opened from the bio strip's info affordance; the
/// per-cell tap still deep-links to a single metric. Lists exactly the metrics the strip
/// shows (HR · HRV · Coherence · Breath) so the guide matches what's on screen.
@MainActor
struct BioMetricsGuideView: View {
    @Environment(\.dismiss) private var dismiss
    /// Live bio, read HERE (this modal sheet is its own leaf) to drive the "right
    /// now" bars in the shaping section. Safe under the 10 Hz menu-freeze law: this
    /// sheet has no Picker to tear down, and the studio body underneath never
    /// observes it — `EchoelStudioView`'s own `usableBio()` calls sit in an action
    /// path and in leaf row structs, never in its `body`.
    ///
    /// ⛔ THIS NOTE USED TO SAY "the only view that reads `latestBio` in its body is
    /// this sheet", AND THE VIEW THAT OPENS THIS SHEET REFUTES IT: `BioStripView` has
    /// `private var reading: BioSampleFrame? { bus.usableBio() }` and reads it in its
    /// body; so do `LiveColaboView`, `AlwaysOnBioRow` and the header monitor's live
    /// wrapper. All four are correct — the freeze law asks that such a read live in a
    /// LEAF, not that there be only one of them — so the conclusion above survives and
    /// only its reason was false. A "the only X" claim is the kind this repo keeps
    /// retracting: it is falsified by any file except the one you are looking at.
    @Environment(EngineBus.self) private var bus

    /// The metrics actually shown in the strip, in display order (RMSSD/SDNN/pNN50 are
    /// sub-measures of HRV, not separate cells, so they stay out of the overview).
    private let shown: [BioMetric] = [.heartRate, .hrv, .coherence, .breath]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ⚠️ `.firstTextBaseline` + spacing 6, MIRRORING the sibling section header rather
            // than only borrowing its idea (#646 review). A bare `HStack` centres a 10 pt note
            // against an 18 pt semibold title, so the note floats at mid-cap-height instead of
            // sitting on the baseline — and this row, unlike the sibling's, also carries the
            // "Done" button, so the note goes AFTER the `Spacer` to be pushed to the trailing
            // edge instead of competing with the title for width. `.lineLimit(nil)` below means
            // an over-budget row WRAPS rather than truncates, and it wraps harder at large
            // Dynamic Type — which is what `InfoSheetTextScalesTests` exists to protect.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("What your body is showing")
                    .font(EchoelTheme.font(18, .semibold))
                    .foregroundStyle(EchoelTheme.text)
                // #646 — the sheet's TITLE was the only heading here claiming a body with no
                // conditional beside it, while the section header below had carried one since
                // #627b. A reader tapping a metric cell reads this line first.
                // ⚠️ EVALUATION ACCOUNTING, twice corrected, because the obvious sentence here
                // was wrong and so was its first repair. The section
                // header used to call `liveBio` TWICE on its own (`== nil`, then `?.source`);
                // routing it through `originNote(for:)` makes it ONE. Non-row evaluations go
                // "at most 2" → "exactly 2", and the header's INTERNAL straddle is closed. ⛔ The
                // first draft wrote "2 → 2" unconditionally and that is wrong in one case: the
                // parent's `else if` is NOT reached when the first call returns nil, so with no
                // reading the parent evaluated ONCE and the worktree evaluates twice. Worst case
                // is unchanged; the no-reading case goes 1 → 2. The straddle it closes had a real
                // failure mode, since a frame expiring between the two calls made the second
                // return nil and NEITHER branch render, hiding the demo marker outright.
                // What remains is a straddle BETWEEN the title and the section, which is the
                // same hazard the ⚠️ block by the `ForEach` already registers for the rows, and
                // it still needs the same single hoist — blocked on no local compiler and no
                // precedent for a bare ViewBuilder `let`.
                // ⚠️ REGISTERED, NOT FIXED: with no reading the sheet now prints "read your
                // pulse to see it move" TWICE — here and above the mapping rows — and under the
                // demo source "demo values, not your body" twice. At `.large` both can be on
                // screen together. Defensible, because they head different things (what the
                // sheet shows vs. what moves the sound), but it is a real consequence of
                // marking the second heading and it should not be discovered as a surprise.
                Spacer(minLength: 8)
                if let note = BioMetric.originNote(for: liveBio) {
                    Text(note)
                        .font(EchoelTheme.font(10))
                        .foregroundStyle(EchoelTheme.dim)
                }
                // Same change, same reason as the sibling sheet above (#353f). Kept spelled out
                // in both places rather than factored into a shared button: two call sites is
                // below the line where a helper earns its indirection, and the failure this
                // guards against is somebody re-typing `.system(size:)` here — which a helper
                // would not prevent either.
                Button("Done") { dismiss() }
                    .font(EchoelTheme.font(15, .semibold))
                    .foregroundStyle(EchoelTheme.accent)
            }
            .padding(.bottom, 4)

            Text("Tap any value in the strip to revisit its explanation.")
                .font(EchoelTheme.font(12))
                .foregroundStyle(EchoelTheme.text.opacity(0.7))
                .padding(.bottom, 12)

            ScrollView {
                // maxWidth: .infinity is REQUIRED (founder 2026-07-07: "die Infos
                // sind abgeschnitten … wir wollen alles lesen"): a vertical ScrollView
                // proposes an UNSPECIFIED width to its content, so each `Text` lays out
                // on one line at its ideal width and gets clipped to "…" — even with
                // `.fixedSize(vertical: true)`. Pinning the column to the full width
                // gives the Texts a width to wrap against, so every line shows in full.
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(shown) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(m.title)
                                    .font(EchoelTheme.font(15, .semibold))
                                    .foregroundStyle(EchoelTheme.text)
                                Text(m.unit)
                                    .font(EchoelTheme.font(11))
                                    .foregroundStyle(EchoelTheme.dim)
                            }
                            Text(m.detail)
                                .font(EchoelTheme.font(13))
                                .foregroundStyle(EchoelTheme.text)   // legible prose (was dim = 0.55, too faint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(m.title). \(m.detail)")
                    }

                    Divider().overlay(EchoelTheme.border)
                    // Item 2 ("Bio-Modulation live sichtbar"): not only what the
                    // numbers mean, but which SOUND each signal moves — AND how much,
                    // right now. Static routing is BioSoundMapping (single source of
                    // truth); the live bar is BioModulationMap.amount, read from the
                    // sheet leaf (freeze-safe, see the `bus` property above).
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("How your body shapes the sound")
                            .font(EchoelTheme.font(15, .semibold))
                            .foregroundStyle(EchoelTheme.text)
                        Spacer(minLength: 0)
                        // ⛔ #627b: THIS SHEET WAS THE HOLE IN #627, and its door is the very
                        // strip #627 marked — `BioStripView` opens it from any metric cell.
                        // A user saw "Demo" on the strip, tapped through, and got live
                        // percentages plus a VoiceOver "Currently 62 percent" with no marker
                        // at all. Worse than unmarked: under Simulation `liveBio` is non-nil,
                        // so the "read your pulse" hint DISAPPEARS — the sheet actively
                        // asserted a measured body. #627's own scope statement called the set
                        // of rendering surfaces complete and it was not; the enumeration is
                        // corrected in the guard rather than in a second confident sentence.
                        // #646 — the two literals moved to `BioMetric.originNote(for:)` so the
                        // title above cannot grow a third spelling. Behaviour is unchanged: the
                        // nil branch and the `.fallback` branch are the same two, in the same
                        // order, now asking `BioSource.isSynthetic` (the one definition, #639)
                        // instead of re-writing `== .fallback` a second time in this file.
                        if let note = BioMetric.originNote(for: liveBio) {
                            Text(note)
                                .font(EchoelTheme.font(10))
                                .foregroundStyle(EchoelTheme.dim)
                        }
                    }
                    ForEach(BioSoundMapping.all) { m in
                        // `measuredAmount`, not `amount`: this panel exists to explain the
                        // bio→sound mapping, so "HRV → brightness 0.00" on a body whose HRV
                        // was never measured is the one number it must not print. The "—"
                        // and dimmed-bar affordance below already existed for "no body";
                        // it now also covers "body present, this field not measured".
                        // ⚠️ ONE frame for the whole row, and the binding is the point. #637's
                        // first version read `liveBio` twice — once for the amount, once for the
                        // origin — and both reviewers found the same hole. `liveBio` is
                        // `bus.usableBio()`, and that call re-reads the wall clock every time it
                        // is evaluated: `latestBio` cannot change mid-body, but TIME can cross the
                        // frame's freshness window between the two calls. The straddle lands in
                        // the worst order (amount first), so the row could print a non-nil demo
                        // value with `synthetic == false` — a demo number at full strength, spoken
                        // as measured. Exactly the defect this slice exists to remove, put back by
                        // the fix for it.
                        let frame = liveBio
                        let amount = frame.flatMap { BioModulationMap.measuredAmount(forMappingID: m.id, in: $0) }
                        // #637 — the row's OWN provenance. The section header above already says
                        // "demo values, not your body", and that was the whole marking: every row
                        // below it still drew a full-strength accent number, a full-strength
                        // accent bar, and spoke "Currently 62 percent" with no origin at all. A
                        // VoiceOver user landing on a row never hears the header, and a sighted
                        // user reads the loudest thing on the row, which was unmarked. #636's law
                        // in one line: half-marked is worse than unmarked, because the reader
                        // learns that an unmarked number is the real one.
                        //
                        // ⚠️ WHAT THIS BINDING DOES **NOT** FIX, stated plainly rather than left
                        // to read as closed: the ROW is now internally consistent, the SECTION is
                        // not. ⛔ "The header above still evaluates `liveBio` twice on its own"
                        // STOOD HERE AND #646 MADE IT FALSE — `originNote(for:)` takes one frame,
                        // so the header now evaluates once and its internal straddle is closed.
                        // The sheet TITLE evaluates once too, so the count above the rows is
                        // "exactly two" where it used to be "at most two" — one, not two, when
                        // there was no reading at all, because the old `else if` was skipped.
                        // Each row evaluates it once more, so at the freshness
                        // boundary a marked row can still sit under an unmarked header. Closing
                        // that needs one binding
                        // above the `ForEach` — a bare `let` directly inside a `VStack`
                        // ViewBuilder, a shape this repo has NO precedent for and no local
                        // compiler to settle. Registered, not guessed at.
                        let synthetic = frame?.source == .fallback
                        // ⚠️ HOISTED into two `let`s instead of one three-term `+` chain, and that
                        // is the house idiom at three of the four sibling surfaces
                        // (`HeaderMonitors`, `EchoelFXView`, `AlwaysOnBioRow`). Not taste: a single
                        // expression mixing a ternary, two string interpolations and an
                        // `Optional.map` closure is the shape that took this blocking bundle red on
                        // "unable to type-check this expression in reasonable time" (#287), and
                        // there is no local compiler here to find that out cheaply.
                        let origin = synthetic ? "Simulated demo, " : ""
                        let measured = amount.map { " Currently \(Int(($0 * 100).rounded())) percent." } ?? ""
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(m.source)
                                    .font(EchoelTheme.font(13, .semibold))
                                    .foregroundStyle(EchoelTheme.text)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(EchoelTheme.dim)
                                Text(m.target)
                                    .font(EchoelTheme.font(13, .semibold))
                                    .foregroundStyle(EchoelTheme.accent)
                                Spacer(minLength: 4)
                                Text(amount.map { EchoelDecimalText.string($0, decimals: 2) } ?? "—")
                                    .font(EchoelTheme.font(11, .semibold).monospacedDigit())
                                    .foregroundStyle(amount == nil || synthetic
                                                     ? EchoelTheme.dim : EchoelTheme.accent)
                            }
                            liveBar(amount ?? 0, live: amount != nil, synthetic: synthetic)
                            Text(m.direction)
                                .font(EchoelTheme.font(12))
                                .foregroundStyle(EchoelTheme.text.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        // ⚠️ THE PREFIX SPELLING, chosen by POSITION and not by taste (#416/#634b).
                        // Three forms are established and they differ by where they sit:
                        // `"Bio source: simulated demo, not your body"` labels a whole element
                        // (strip, widget, watch) · `"Simulated demo, "` PREFIXES a sentence that
                        // continues (header pill, Live-Colabo, always-on rows, FX routes) ·
                        // `"demo values, not your body"` HEADS a section — which is exactly the
                        // form used in the section header of THIS section, and it stays there.
                        // This label is a sentence that continues ("Heart rate shapes …"), so it
                        // takes the prefix. Minting a fourth spelling of one decision is what
                        // #634b had to retract. After this slice the file holds TWO of the three
                        // forms, in one section, and that is correct rather than inconsistent:
                        // they mark different THINGS — a section, and an element inside it. (No
                        // line distance is quoted here on purpose; this repo has paid twice for
                        // a comment whose line count the next edit invalidated.)
                        .accessibilityLabel(
                            origin + "\(m.source) shapes \(m.target). \(m.direction)." + measured)
                    }

                    Divider().overlay(EchoelTheme.border)
                    Text(BioMetric.disclaimer)
                        .font(EchoelTheme.font(12))
                        .foregroundStyle(EchoelTheme.text.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
        }
        .lineLimit(nil)   // hard override: never inherit a lineLimit(1) from the presenter
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EchoelTheme.bg)
        .presentationDetents([.medium, .large])
    }

    /// A USABLE bio frame or nil — the SAME gate the sound engine asks
    /// (`ModulationEngine.tick` → `usableBio()`), so "how your body shapes the
    /// sound" shows amounts EXACTLY when the body is actually shaping it. Using the
    /// fixed 5 s `freshBio()` here under-reported for latent sources: a wrist/Watch
    /// reading stays usable for 90 s and keeps driving the music, but the bars
    /// blanked to "—" after 5 s — a false "your body isn't driving" while it was.
    /// `usableBio()` honours each source's own window (BLE/rPPG 6 s, Watch 90 s),
    /// still blanks a truly frozen source, and reads `latestBio` so the freeze-law
    /// note above still holds.
    ///
    /// ⛔ "this sheet leaf is the only body observing it" STOOD HERE and the ⛔ block ~200 lines
    /// up already retracts it by name (#646 review, #425 — a file must not carry a claim and
    /// its own refutation). Measured: `BioStripView`, `AutomationStatusStrip`,
    /// `BodyShapesThisSoundLine` and `AlwaysOnBioRow` all read it too. The freeze-law argument
    /// does NOT depend on exclusivity — it depends on each read living in its own leaf `View`
    /// rather than in an ancestor of a menu host — so the conclusion survives and only the
    /// (false, and never necessary) uniqueness premise is withdrawn.
    private var liveBio: BioSampleFrame? { bus.usableBio() }

    /// The moving "right now" bar for a shaping row. `live == false` (no fresh
    /// signal) draws only the muted track. Fill is clamped ≥ 2 pt so a tiny live
    /// value is still visible. No animation beyond SwiftUI's implicit value change
    /// (well under 3 Hz — the 10 Hz frame only nudges a width).
    ///
    /// ⚠️ `synthetic` has NO DEFAULT, deliberately (#431/#440/#443): a defaulted argument that
    /// no call site writes never shows up in a diff, and this bar is the LOUDEST element on the
    /// row — a full-strength accent fill beside a dimmed number would be a headline
    /// contradicting its own footnote. There is exactly one call site, so the cost is one edit.
    private func liveBar(_ amount: Float, live: Bool, synthetic: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(EchoelTheme.text.opacity(0.12))
                if live {
                    Capsule()
                        .fill(synthetic ? EchoelTheme.dim : EchoelTheme.accent)
                        .frame(width: max(2, geo.size.width * CGFloat(min(1, max(0, amount)))))
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}
#endif
