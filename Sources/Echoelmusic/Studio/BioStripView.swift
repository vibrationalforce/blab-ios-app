//
//  BioStripView.swift
//  Echoelmusic
//
//  Thin readout strip showing the latest BioSampleFrame published to
//  EngineBus — the body's live numbers (HR / HRV / breath / coherence) plus a
//  source tag. Deliberately minimal: legible numbers first, no extra controls
//  (transport, FX and panels live on the main screen, not here).
//

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct BioStripView: View {

    @Environment(EngineBus.self) private var bus

    /// Tapped metric → its plain-language explanation sheet ("app as a school").
    @State private var explain: BioMetric?

    var body: some View {
        HStack(spacing: 10) {
            metricButton(label: "HR",  value: hrString,        unit: "bpm",   metric: .heartRate)
            divider
            metricButton(label: "HRV", value: hrvString,       unit: hrvUnit, metric: .hrv)
            divider
            metricButton(label: "Br",  value: breathString,    unit: "/min",  metric: .breath)
            divider
            metricButton(label: "Coh", value: coherenceString, unit: nil,     metric: .coherence)
            Spacer(minLength: 4)
            sourceTag
        }
        .sheet(item: $explain) { BioMetricInfoView(metric: $0) }
        .lineLimit(1)
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .foregroundStyle(.primary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    // MARK: - Metric cells

    /// A metric cell you can tap to learn what it means. Plain button style keeps
    /// the compact strip look; carries an explicit VoiceOver label + hint.
    private func metricButton(label: String, value: String, unit: String?, metric m: BioMetric) -> some View {
        Button { explain = m } label: {
            metric(label: label, value: value, unit: unit)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(m.title), \(value)\(unit.map { " " + $0 } ?? "")")
        .accessibilityHint("Double tap to learn what this means")
    }

    private func metric(label: String, value: String, unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
            if let unit {
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 10)
    }

    // MARK: - Source tag

    /// Non-interactive source tag. Shows the live sensor label (green = a real
    /// body signal is publishing) or "No signal" — no synthetic demo source.
    private var sourceTag: some View {
        Text(sourceText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(hasLiveSignal ? Color.green.opacity(0.22) : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(hasLiveSignal ? Color.green : Color.secondary)
            .accessibilityLabel("Bio source: \(sourceText)")
    }

    /// A real sensor (camera PPG / HealthKit / BLE / Watch / Oura) is publishing
    /// FRESH frames. A frozen reading (dropped strap, lifted finger, stalled Watch)
    /// expires after the freshness window, so the strip stops claiming a live body.
    private var hasLiveSignal: Bool {
        if let bio = bus.freshBio(), bio.source != .fallback { return true }
        return false
    }

    private var sourceText: String {
        if let bio = bus.freshBio(), bio.source != .fallback {
            return sourceLabel(bio.source)
        }
        return "No signal"
    }

    // MARK: - Formatting

    private var hrString: String {
        guard let v = bus.latestBio?.heartRateBPM else { return "—" }
        return String(format: "%.1f", v)
    }

    /// True RMSSD in ms when the source provides it; otherwise the normalized
    /// [0..1] value at higher precision.
    private var hrvString: String {
        guard let bio = bus.latestBio else { return "—" }
        if bio.hrvRMSSDms > 0 { return String(format: "%.1f", bio.hrvRMSSDms) }
        return String(format: "%.3f", bio.hrvNormalized)
    }

    private var hrvUnit: String? {
        guard let bio = bus.latestBio, bio.hrvRMSSDms > 0 else { return nil }
        return "ms"
    }

    private var breathString: String {
        guard let v = bus.latestBio?.breathRate else { return "—" }
        return String(format: "%.1f", v)
    }

    /// Coherence is real only on sources with beat-to-beat RR (BLE / camera);
    /// HealthKit publishes 0 ("not available"). Show a measured value only for a
    /// FRESH frame whose coherence is > 0 — otherwise "—" (never "0.000", which
    /// would read as "incoherent" rather than "not yet / not available").
    private var coherenceString: String {
        guard let bio = bus.freshBio(), bio.coherence > 0 else { return "—" }
        return String(format: "%.2f", bio.coherence)
    }

    private func sourceLabel(_ source: BioSource) -> String {
        switch source {
        case .oura:       return "Oura"
        case .healthKit:  return "Health"
        case .ble:        return "BLE"
        case .watch:      return "Watch"
        case .cameraPPG:  return "PPG"
        case .fallback:   return "—"
        }
    }
}
#endif
