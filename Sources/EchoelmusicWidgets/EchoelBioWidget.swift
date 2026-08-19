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
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date())
            ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [makeEntry()], policy: .after(next)))
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

    /// Deliberately `.secondary` with a hairline outline — NOT an accent or a warning
    /// colour. Green would read as "a body is connected" (the exact claim being denied)
    /// and red/orange would read as a fault, when running the demo is a normal choice.
    /// It is plain `Text`, so VoiceOver speaks it without a separate label.
    private var demoTag: some View {
        Text("Demo")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
            )
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
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(bpm)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
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
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(bpm)")
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .monospacedDigit()
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

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium)).monospacedDigit().foregroundStyle(.primary)
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
