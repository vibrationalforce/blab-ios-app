#if canImport(SwiftUI)
import SwiftUI

/// "Works" tab — record bio sessions and review their summaries. Captures
/// HR/HRV/coherence averages over a session and persists them across launches.
/// (Multi-track audio recording + DAW handoff land in later cycles; this is
/// the session ledger that anchors the tab.)
///
/// Reads the EngineBus snapshot via SessionRecorder. House UI: solid fills,
/// legible numbers first, no glow.
@MainActor
struct WorksView: View {

    @Environment(EngineBus.self) private var bus
    @State private var recorder = SessionRecorder()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    recordControl
                } header: {
                    Text("Session")
                } footer: {
                    Text("Records HR, HRV and coherence averages over the session. Enable a bio source (or Demo) in the strip first.")
                }

                Section("History") {
                    if recorder.sessions.isEmpty {
                        Text("No sessions yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(recorder.sessions) { SessionRow(summary: $0) }
                            .onDelete { recorder.deleteSessions(at: $0) }
                    }
                }
            }
            .navigationTitle("Works")
        }
    }

    private var recordControl: some View {
        VStack(spacing: 12) {
            if recorder.isRecording {
                HStack {
                    Text(timeString(recorder.elapsedSeconds))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    liveMetric("Coh", bus.latestBio?.coherence)
                    liveMetric("HRV", bus.latestBio?.hrvNormalized)
                }
            }
            Button {
                if recorder.isRecording { recorder.stop() } else { recorder.start(subscribing: bus) }
            } label: {
                Label(recorder.isRecording ? "Stop" : "Record Session",
                      systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(recorder.isRecording ? .red : .green)
        }
        .padding(.vertical, 4)
    }

    private func liveMetric(_ label: String, _ value: Float?) -> some View {
        VStack(spacing: 1) {
            Text(value.map { String(format: "%.3f", $0) } ?? "—")
                .font(.callout.monospacedDigit().weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct SessionRow: View {
    let summary: BioSessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(summary.date, format: .dateTime.month().day().hour().minute())
                    .font(.callout.weight(.medium))
                Spacer()
                Text(durationString).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                stat("HR", String(format: "%.1f", summary.avgHeartRate))
                stat("HRV", String(format: "%.3f", summary.avgHRV))
                stat("Coh", String(format: "%.3f", summary.avgCoherence))
                stat("Peak", String(format: "%.3f", summary.peakCoherence))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) { Text(label).opacity(0.6); Text(value) }
    }

    private var durationString: String {
        String(format: "%02d:%02d", summary.durationSeconds / 60, summary.durationSeconds % 60)
    }
}
#endif
