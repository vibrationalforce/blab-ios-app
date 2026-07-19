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
                Button("Done") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(EchoelTheme.accent)
            }

            Text(metric.summary)
                .font(EchoelTheme.font(15, .medium))
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
    /// now" bars in the shaping section. Safe under the 10 Hz menu-freeze law: the
    /// only view that reads `latestBio` in its body is this sheet, which has no
    /// Picker to tear down, and the studio body underneath never observes it.
    @Environment(EngineBus.self) private var bus

    /// The metrics actually shown in the strip, in display order (RMSSD/SDNN/pNN50 are
    /// sub-measures of HRV, not separate cells, so they stay out of the overview).
    private let shown: [BioMetric] = [.heartRate, .hrv, .coherence, .breath]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("What your body is showing")
                    .font(EchoelTheme.font(18, .semibold))
                    .foregroundStyle(EchoelTheme.text)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
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
                        if liveBio == nil {
                            Text("read your pulse to see it move")
                                .font(EchoelTheme.font(10))
                                .foregroundStyle(EchoelTheme.dim)
                        }
                    }
                    ForEach(BioSoundMapping.all) { m in
                        let amount = liveBio.map { BioModulationMap.amount(forMappingID: m.id, in: $0) }
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
                                Text(amount.map { String(format: "%.2f", $0) } ?? "—")
                                    .font(EchoelTheme.font(11, .semibold).monospacedDigit())
                                    .foregroundStyle(amount == nil ? EchoelTheme.dim : EchoelTheme.accent)
                            }
                            liveBar(amount ?? 0, live: amount != nil)
                            Text(m.direction)
                                .font(EchoelTheme.font(12))
                                .foregroundStyle(EchoelTheme.text.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(m.source) shapes \(m.target). \(m.direction)."
                            + (amount.map { " Currently \(Int(($0 * 100).rounded())) percent." } ?? ""))
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

    /// A FRESH bio frame or nil — a stale/expired reading stops the bars moving
    /// (honest: "nothing live is driving the sound"), matching the strip's freshness.
    private var liveBio: BioSampleFrame? { bus.freshBio() }

    /// The moving "right now" bar for a shaping row. `live == false` (no fresh
    /// signal) draws only the muted track. Fill is clamped ≥ 2 pt so a tiny live
    /// value is still visible. No animation beyond SwiftUI's implicit value change
    /// (well under 3 Hz — the 10 Hz frame only nudges a width).
    private func liveBar(_ amount: Float, live: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(EchoelTheme.text.opacity(0.12))
                if live {
                    Capsule()
                        .fill(EchoelTheme.accent)
                        .frame(width: max(2, geo.size.width * CGFloat(min(1, max(0, amount)))))
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}
#endif
