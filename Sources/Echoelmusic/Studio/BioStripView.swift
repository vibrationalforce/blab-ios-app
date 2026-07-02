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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Read the finger-on-lens flag HERE (this small leaf view), not in the parent
    /// `EchoelStudioView.body`. `fingerDetected` is rewritten ~10 Hz while reading; if the
    /// root body subscribed to it (the old `fingerOnLens:` argument), it re-evaluated 10×/s
    /// and tore down any open `.menu` Picker popover in the Composition panel — the "can't
    /// select the Tonart anymore" freeze. Confining the read to this Picker-free strip keeps
    /// the high-frequency invalidation off the selection menus.
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG

    /// True while a camera pulse-read is in progress but no real signal has locked
    /// yet — the strip shows live "reading…" feedback instead of a dead "No signal".
    var measuring: Bool = false
    /// One-tap entry from the otherwise-dead strip: bring the body's pulse in.
    var onStartPulse: () -> Void = {}

    /// Tapped metric → its plain-language explanation sheet ("app as a school").
    @State private var explain: BioMetric?

    var body: some View {
        // Equal-width metric cells that always fit the screen — no left-packing, so a
        // value changing digit-count (or the source tag toggling width) can't reflow
        // its neighbours or overflow the edge (the old "wobble"). The source tag sits
        // in a bounded slot; everything scales down on narrow phones (adaptive).
        HStack(spacing: 6) {
            metricButton(label: "HR",  value: hrString,        unit: "bpm",   metric: .heartRate)
                .frame(maxWidth: .infinity)
            divider
            metricButton(label: "HRV", value: hrvString,       unit: hrvUnit, metric: .hrv)
                .frame(maxWidth: .infinity)
            divider
            metricButton(label: "Br",  value: breathString,    unit: "/min",  metric: .breath)
                .frame(maxWidth: .infinity)
            divider
            metricButton(label: "Coh", value: coherenceString, unit: nil,     metric: .coherence)
                .frame(maxWidth: .infinity)
            sourceControl
                .frame(width: 96, alignment: .trailing)
        }
        .sheet(item: $explain) { BioMetricInfoView(metric: $0) }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .foregroundStyle(EchoelTheme.text)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EchoelTheme.text.opacity(0.08))
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
                .foregroundStyle(EchoelTheme.dim)
            Text(value)
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .foregroundStyle(EchoelTheme.dim)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(EchoelTheme.text.opacity(0.1))
            .frame(width: 1, height: 10)
    }

    // MARK: - Source control (live tag · measuring · one-tap pulse entry)

    /// The right end of the strip. Three honest states, no synthetic data ever:
    /// • a real signal is live → green source tag (HR / PPG / BLE…);
    /// • a pulse read is in progress → live "Reading… / Cover camera" feedback;
    /// • nothing yet → a one-tap button that brings the body in (camera rPPG),
    ///   so the most bio-looking element is the gateway to the instrument, not a
    ///   dead end. Only a real, fresh signal turns it green.
    @ViewBuilder private var sourceControl: some View {
        if hasLiveSignal {
            liveTag
        } else if measuring {
            measuringTag
        } else {
            startPulseButton
        }
    }

    private var liveTag: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill").font(.system(size: 9))
            Text(sourceText)
        }
        .lineLimit(1)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.green.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(Color.green)
        .accessibilityLabel("Bio source: \(sourceText)")
    }

    private var measuringTag: some View {
        let amber = Color(red: 0.90, green: 0.62, blue: 0.20)
        let finger = cameraRPPG.fingerDetected
        return HStack(spacing: 4) {
            Image(systemName: "heart.fill").font(.system(size: 9))
                .symbolEffect(.pulse, isActive: !reduceMotion)
            Text(finger ? "Reading…" : "Cover camera")
        }
        .lineLimit(1)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(amber.opacity(0.20))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(amber)
        .accessibilityLabel(finger ? "Reading your pulse" : "Cover the rear camera and flash to read your pulse")
    }

    /// The old dead "No signal" becomes the one-tap gateway to the live body.
    private var startPulseButton: some View {
        Button(action: onStartPulse) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").font(.system(size: 9))
                Text("Read pulse")
            }
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(EchoelTheme.text.opacity(0.25), lineWidth: 1))
            .foregroundStyle(EchoelTheme.dim)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read your pulse")
        .accessibilityHint("Starts the camera to read your heartbeat so your body drives the sound")
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

    /// Physiologically plausible RMSSD window (ms). Camera rPPG's beat-to-beat
    /// timing is noisy and can inflate RMSSD to impossible values (e.g. 500+ ms,
    /// above the mean RR interval) — science-first, we show a real number only
    /// inside this window and "—" otherwise, rather than print a wrong figure.
    private static let plausibleHRVms: ClosedRange<Float> = 3...300

    /// True RMSSD in ms when the source provides a plausible reading; the
    /// normalized [0..1] value for sources that only publish that (HealthKit);
    /// "—" when the ms reading is physiologically impossible (noisy rPPG).
    private var hrvString: String {
        guard let bio = bus.latestBio else { return "—" }
        if Self.plausibleHRVms.contains(bio.hrvRMSSDms) { return String(format: "%.1f", bio.hrvRMSSDms) }
        if bio.hrvRMSSDms == 0 && bio.hrvNormalized > 0 { return String(format: "%.3f", bio.hrvNormalized) }
        return "—"
    }

    private var hrvUnit: String? {
        guard let bio = bus.latestBio, Self.plausibleHRVms.contains(bio.hrvRMSSDms) else { return nil }
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
