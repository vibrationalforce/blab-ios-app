#if canImport(SwiftUI)
import SwiftUI

/// "Well" tab — evidence-based breath & coherence. Shows the live coherence
/// score (legible number first), the supporting HR/HRV/breath readouts, and
/// a paced-breathing guide. Resonance breathing near ~6 breaths/min maximizes
/// HRV amplitude (baroreflex resonance) — the pacer guides that rhythm and the
/// coherence number reflects the effect in real time.
///
/// Reads the EngineBus snapshot directly (same pattern as BioStripView). Pure
/// readout + a slow, functional breath animation (≈0.1 Hz — far under the 3 Hz
/// WCAG flash limit). House UI: solid fills, legible numbers first, no glow.
@MainActor
struct WellView: View {

    @Environment(EngineBus.self) private var bus

    @State private var breathsPerMin: Double = 6
    @State private var inhaling = false

    /// Seconds per half-breath (inhale or exhale) at the chosen rate.
    private var halfCycle: Double { 30.0 / max(breathsPerMin, 1) }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                coherenceHeadline
                readoutRow
                pacer
                evidenceNote
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Color.black)
    }

    // MARK: Coherence headline

    private var coherenceHeadline: some View {
        VStack(spacing: 4) {
            Text(coherenceString)
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("Coherence")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(coherenceCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    // MARK: Readouts

    private var readoutRow: some View {
        HStack(spacing: 12) {
            readout("HR", hrString, "bpm")
            readout("HRV", hrvString, nil)
            readout("Breath", breathString, "/min")
        }
    }

    private func readout(_ label: String, _ value: String, _ unit: String?) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title3.monospacedDigit().weight(.semibold))
                if let unit { Text(unit).font(.caption2).foregroundStyle(.secondary) }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Breath pacer

    private var pacer: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 2)
                Circle()
                    .fill(Color.green.opacity(0.16))
                    .scaleEffect(inhaling ? 1.0 : 0.55)
                Text(inhaling ? "Inhale" : "Exhale")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 200, height: 200)
            .animation(.easeInOut(duration: halfCycle), value: inhaling)

            Stepper(value: $breathsPerMin, in: 4...8, step: 0.5) {
                Text("Pace: \(breathsPerMin, format: .number.precision(.fractionLength(1))) breaths/min")
                    .font(.callout)
            }
            .padding(.horizontal, 8)
        }
        .padding(.top, 8)
        // Restarts the breath cycle whenever the pace changes.
        .task(id: breathsPerMin) {
            inhaling = false
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: halfCycle)) { inhaling = true }
                try? await Task.sleep(for: .seconds(halfCycle))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: halfCycle)) { inhaling = false }
                try? await Task.sleep(for: .seconds(halfCycle))
            }
        }
    }

    private var evidenceNote: some View {
        Text("Paced breathing near 6 breaths/min drives baroreflex resonance, which maximizes heart-rate variability. This is for self-observation, not medical diagnosis.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    // MARK: Formatting

    private var coherenceString: String {
        guard let v = bus.latestBio?.coherence else { return "—" }
        return String(format: "%.2f", v)
    }

    private var coherenceCaption: String {
        guard let v = bus.latestBio?.coherence else { return "Connect a sensor or enable Demo in the strip" }
        switch v {
        case ..<0.34: return "Building — let the breath settle"
        case ..<0.67: return "Steadying"
        default:      return "Strong, steady HRV rhythm"
        }
    }

    private var hrString: String {
        guard let v = bus.latestBio?.heartRateBPM else { return "—" }
        return String(format: "%.0f", v)
    }

    private var hrvString: String {
        guard let v = bus.latestBio?.hrvNormalized else { return "—" }
        return String(format: "%.2f", v)
    }

    private var breathString: String {
        guard let v = bus.latestBio?.breathRate else { return "—" }
        return String(format: "%.0f", v)
    }
}
#endif
