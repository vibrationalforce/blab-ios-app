// BioMetricInfo.swift
// Echoel — plain-language explanations for every bio readout. Tap a value (HR,
// HRV, coherence, RMSSD…) and learn what it means. Science-first, accessible, and
// explicit that this is for music + self-observation, NOT medical diagnosis.
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
        case .coherence: return "How smooth and rhythmic your heart-rate pattern is."
        case .breath:    return "How many breaths you take per minute."
        }
    }

    /// A short, plain-language paragraph.
    public var detail: String {
        switch self {
        case .heartRate:
            return "Beats per minute. It rises with effort, excitement or stress and falls with rest. In Echoel your heart rate sets the energy and tempo of the music."
        case .hrv:
            return "The tiny differences in time between one heartbeat and the next. Higher variability generally reflects a relaxed, adaptable state; lower variability often goes with stress or fatigue. Echoel uses it to open or close the timbre."
        case .rmssd:
            return "Root mean square of successive differences between heartbeats — a standard short-term HRV measure that mostly reflects your parasympathetic ‘rest-and-digest’ activity. Higher values often go with a more relaxed moment."
        case .sdnn:
            return "Standard deviation of the time between normal heartbeats across the whole reading. It captures your total heart-rate variability from many sources at once."
        case .pnn50:
            return "The percentage of consecutive heartbeats that differ by more than 50 milliseconds — another marker of parasympathetic activity. Higher values usually accompany a more relaxed moment."
        case .coherence:
            return "How smooth and wave-like your heart-rate pattern is. It tends to be highest during slow, steady breathing around six breaths a minute. Higher coherence makes Echoel’s music calmer and more spacious."
        case .breath:
            return "Your breathing rate. Slow breathing (about five to six breaths a minute) tends to raise coherence. Echoel uses your breath phase to shape how the music moves."
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
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(EchoelTheme.text)
                    Text(metric.unit)
                        .font(.system(size: 12))
                        .foregroundStyle(EchoelTheme.dim)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(EchoelTheme.accent)
            }

            Text(metric.summary)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(EchoelTheme.text)

            Text(metric.detail)
                .font(.system(size: 14))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(EchoelTheme.border)

            Text(BioMetric.disclaimer)
                .font(.system(size: 12))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EchoelTheme.bg)
        .presentationDetents([.medium])
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title). \(metric.detail). \(BioMetric.disclaimer)")
    }
}
#endif
