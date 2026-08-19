//
//  EchoelBioWidget.swift
//  Echoelmusic — Widgets
//
//  WidgetKit extension: glanceable live vitals (HR · HRV · coherence) on the
//  Home and Lock screen, read from the shared App Group via BioFeedbackManager.
//
//  ── DESIGN (CLAUDE.md "SCIENCE-FIRST display") ────────────────────────────
//    • Real biometric data only — legible numbers first, no decoration.
//    • No flashing / animation (WCAG ≤3 Hz; widgets re-render on timeline tick).
//    • Muted fills, no glow/neon, radius ≤12px — matches the in-app BioStrip.
//
//  ── DATA PATH ─────────────────────────────────────────────────────────────
//    main app  --(BioFeedbackManager.publish, ~1 Hz off audio thread)-->
//    App Group (group.com.echoelmusic)  --(refreshFromSharedStore)-->  widget
//
//  This target compiles BioFeedbackManager.swift directly (Foundation-only
//  value types) — no app-module import, mirroring the AUv3 sharing pattern.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline

struct BioEntry: TimelineEntry {
    let date: Date
    let vitals: BioVitals
    /// True when the shared store has never been written (no session yet).
    let isPlaceholder: Bool
}

struct BioProvider: TimelineProvider {
    private let bridge = BioFeedbackManager()

    func placeholder(in context: Context) -> BioEntry {
        BioEntry(date: Date(), vitals: BioVitals(), isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (BioEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BioEntry>) -> Void) {
        // WidgetKit budgets refreshes; ask again in 5 min. The app also nudges
        // the timeline (WidgetCenter.reloadTimelines) when it publishes fresh
        // vitals in the foreground, so live sessions update sooner.
        let now = Date()
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: now)
            ?? now.addingTimeInterval(300)
        let entry = makeEntry()
        var entries = [entry]

        // ⛔ A SECOND ENTRY AT THE MOMENT THE READING STOPS BEING CURRENT — and without it the
        // freshness marker is nearly inert. `entry.date` is stamped when the TIMELINE is built,
        // so with a single entry `isCurrent` is frozen at that instant for the whole life of the
        // timeline. The error is one-directional and lands on the wrong side: `entry.date` is
        // never later than the render, so the widget can only UNDERSTATE age — print a stale
        // payload at full strength — which is the exact defect this marker exists to remove.
        // Nothing forces a reload either: `BioFeedbackPublisher.reloadWidgetsIfDue()` is reached
        // only from a publish tick, and publishing stops when the session does, so after a
        // session ends the only refresh is `.after(next)`, which WidgetKit throttles by daily
        // budget. Scheduling the transition as its own entry is how WidgetKit is meant to
        // express "this changes at time T" and keeps the body a pure function of its entry.
        if !entry.isPlaceholder {
            let expiry = Date(timeIntervalSinceReferenceDate:
                                entry.vitals.timestamp + BioVitals.glanceFreshnessWindow)
            if expiry > now {
                entries.append(BioEntry(date: expiry, vitals: entry.vitals, isPlaceholder: false))
            }
        }
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private func makeEntry() -> BioEntry {
        guard let vitals = bridge.refreshFromSharedStore() else {
            return BioEntry(date: Date(), vitals: BioVitals(), isPlaceholder: true)
        }
        return BioEntry(date: Date(), vitals: vitals, isPlaceholder: false)
    }
}

// MARK: - View

struct EchoelBioWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BioEntry

    private var bpm: Int { Int(entry.vitals.heartRateBPM.rounded()) }

    /// 0 means "not measured" for both of these (a Watch before its first SDNN sample,
    /// any source with no beat-to-beat RR), so they render "—" — the same rule the in-app
    /// bio strip already follows. Printing "HRV 0%" on a glanceable surface would state a
    /// specific and alarming observation about the user's body that nothing measured.
    private var hrvText: String {
        entry.vitals.hrvNormalized > 0 ? "\(Int((entry.vitals.hrvNormalized * 100).rounded()))%" : "—"
    }
    private var coherenceText: String {
        entry.vitals.coherence > 0 ? "\(Int((entry.vitals.coherence * 100).rounded()))%" : "—"
    }

    /// `true` only when the writer SAID the numbers are the demo generator's.
    /// A payload from a build older than #632 carries no `synthetic` key and decodes
    /// to `nil`; that stays unmarked, because branding a real reading "Demo" is the
    /// same kind of lie as printing a fake one as measured (see `BioVitals.synthetic`).
    private var isDemo: Bool { entry.vitals.synthetic == true }

    /// Whether the payload is still one the ENGINE would act on. `BioVitals.isFresh`
    /// existed with ZERO production callers, so this glance printed a 40-point "142 bpm"
    /// for a payload of any age — a session that ended three hours ago read exactly like
    /// a heart beating now. The window is derived, not chosen: see
    /// `BioVitals.glanceFreshnessWindow`.
    ///
    /// ⚠️ `entry.date`, not `Date()`. WidgetKit renders a timeline entry at a moment it
    /// chooses, and a view body must be a pure function of its entry — reading the wall
    /// clock here would make the same entry render differently on every redraw and make
    /// the state untestable. The entry's own date is when this reading was taken for.
    private var isCurrent: Bool {
        entry.vitals.isFresh(within: BioVitals.glanceFreshnessWindow,
                             now: entry.date.timeIntervalSinceReferenceDate)
    }

    /// A TIME qualifier, so plain secondary text — deliberately NOT the boxed chip form
    /// `demoTag` uses. The two answer different questions ("whose body" vs "when"), and
    /// giving both a badge would read as two labels of one class. ⛔ The first draft of this
    /// comment then said the corner-radius count "is unchanged at four" — four is the VALUE of
    /// the single literal in this file, not a count of them; `grep -c cornerRadius` is 1. The
    /// true statement is the one that matters anyway: this marker adds no rounded surface, so
    /// `RadiusHasOneSpellingTests`' extension list is untouched — nothing was skipped to keep
    /// a guard green, the marker simply is not a box.
    private var staleTag: some View {
        Text("Last session")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityLabel(Text("Reading from an earlier session, not current"))
    }

    /// Deliberately `.secondary` with a hairline outline — NOT an accent or a warning
    /// colour. Green would read as "a body is connected" (the exact claim being denied)
    /// and red/orange would read as a fault, when running the demo is a normal choice.
    /// It is plain `Text`, so VoiceOver speaks it without a separate label.
    private var demoTag: some View {
        Text("Demo")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            // ⚠️ #629b's law, and this is the surface it matters most on: without these two the
            // tag is the one element in the row that cannot shrink, so at accessibility text
            // sizes it takes its full width out of the label beside it — unconditionally, on a
            // host-sized rectangle the app does not own and cannot scroll.
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            // `.strokeBorder`, not `.stroke`: a centred 1 pt line puts half its width outside the
            // padded frame. The app's reference form (`BioStripView.demoTag`) insets too.
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
            )
            // The three sibling tags say it in words; a glance with no surrounding context is
            // the last place to leave VoiceOver reading the bare label.
            .accessibilityLabel(Text("Bio source: simulated demo, not your body"))
    }

    var body: some View {
        Group {
            if entry.isPlaceholder {
                placeholder
            } else if family == .systemSmall {
                small
            } else {
                medium
            }
        }
        .containerBackground(for: .widget) { Color.black }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Echoelmusic").font(.headline).foregroundStyle(.primary)
            Spacer(minLength: 0)
            Text("No session yet")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Open Echoelmusic to start.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("HR").font(.caption2).foregroundStyle(.secondary)
                if isDemo { demoTag }
                if !isCurrent { staleTag }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(bpm)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    // The number is the loudest thing on the glance; a caption beside a
                    // full-strength number is a footnote under a headline that contradicts it.
                    .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                Text("bpm").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                metric("HRV", hrvText)
                metric("Coh", coherenceText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("Heart rate").font(.caption2).foregroundStyle(.secondary)
                    if isDemo { demoTag }
                    if !isCurrent { staleTag }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(bpm)")
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                    Text("bpm").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                metric("HRV", hrvText)
                metric("Coherence", coherenceText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// ⚠️ HRV AND COHERENCE DIM WITH THE HEART RATE, because they come from the SAME payload
    /// and the same timestamp. The first draft of #636 marked only the pulse and left these
    /// two at full strength — a half-marked card, which is worse than an unmarked one: the
    /// reader learns that an unmarked number is current. The widget's own App Store subtitle
    /// names all three ("Live heart rate, HRV, and coherence from your session").
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium)).monospacedDigit()
                .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
        }
    }
}

// MARK: - Widget

struct EchoelBioWidget: Widget {
    let kind = "EchoelBioWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BioProvider()) { entry in
            EchoelBioWidgetView(entry: entry)
        }
        .configurationDisplayName("Echoelmusic Bio")
        .description("Live heart rate, HRV, and coherence from your session.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct EchoelWidgetBundle: WidgetBundle {
    var body: some Widget {
        EchoelBioWidget()
    }
}
