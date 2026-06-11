//
//  EchoelMixView.swift
//  Echoelmusic — Studio
//
//  Control surface for EchoelMix: master metering (peak / true-peak / LUFS) and
//  the microphone-over-beats recorder (MultiTrackRecorder). Reads live values
//  from AudioEngine (published from the master tap) — no audio-thread work here.
//
//  Honors master prompt §UI: legible numbers first, solid dark surface, subtle
//  borders, ≤12px radius, no glow/glass. The REC indicator is a steady dot
//  (no flashing) — well within the 3 Hz epilepsy limit.
//

#if canImport(SwiftUI) && canImport(AVFoundation)
import SwiftUI

@MainActor
struct EchoelMixView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AudioEngine.self) private var audio

    private var recorder: MultiTrackRecorder { audio.multiTrackRecorder }

    var body: some View {
        NavigationStack {
            Form {
                meteringSection
                recordSection
                if !recorder.trackURLs.isEmpty { takesSection }
            }
            .navigationTitle("EchoelMix")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await recorder.requestPermission() }
        }
    }

    // MARK: - Master metering

    private var meteringSection: some View {
        Section {
            HStack(spacing: 18) {
                readout("PEAK", dbString(audio.masterPeakDb), tint: .primary)
                readout("TRUE-PK", dbString(audio.masterTruePeakDb),
                        tint: audio.masterTruePeakDb > -1.0 ? EchoelTheme.danger : .primary)
                readout("LUFS-M", lufsString(audio.masterLUFS), tint: .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            levelBar(audio.masterLevel)
            levelBar(audio.masterLevelR)
        } header: {
            Text("Master")
        } footer: {
            Text("Sample peak (dBFS), inter-sample true-peak (dBTP), and momentary loudness (LUFS, BS.1770 K-weighted). True-peak turns red above −1 dBTP — back off the master to avoid inter-sample clipping.")
        }
    }

    private func readout(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
        }
    }

    /// Horizontal level bar, 0…1 linear (RMS-scaled). Solid fill, no glow.
    private func levelBar(_ level: Float) -> some View {
        GeometryReader { geo in
            let w = geo.size.width * CGFloat(max(0, min(1, level)))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(EchoelTheme.fill)
                RoundedRectangle(cornerRadius: 3)
                    .fill(level > 0.92 ? EchoelTheme.danger : EchoelTheme.accent)
                    .frame(width: w)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    // MARK: - Recorder

    private var recordSection: some View {
        Section {
            Button {
                toggleRecording()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle")
                        .font(.system(size: 18, weight: .semibold))
                    Text(recorder.isRecording ? "Stop" : "Record")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(timeString(recorder.recordingSeconds))
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(recorder.isRecording ? EchoelTheme.danger : EchoelTheme.text)
            }
            .buttonStyle(.plain)

            if let error = recorder.lastError {
                Text(errorString(error))
                    .font(.system(size: 12))
                    .foregroundStyle(EchoelTheme.danger)
            }
        } header: {
            Text("Record — mic over beats")
        } footer: {
            Text("Captures the microphone in sync with the beat playing on the master bus, written to a .caf in Documents/Recordings. Needs microphone permission and a running engine.")
        }
    }

    private var takesSection: some View {
        Section("Takes") {
            ForEach(recorder.trackURLs, id: \.self) { url in
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                    Text(url.lastPathComponent)
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleRecording() {
        if recorder.isRecording {
            Task { _ = await recorder.stopRecording() }
        } else {
            recorder.startRecording()
        }
    }

    // MARK: - Formatting

    private func dbString(_ db: Float) -> String {
        guard db > EchoelMeter.floorDb + 0.5 else { return "−∞" }
        return String(format: "%.1f", db)
    }

    private func lufsString(_ lufs: Float) -> String {
        guard lufs > EchoelLoudnessMeter.floorLUFS + 0.5 else { return "−∞" }
        return String(format: "%.1f", lufs)
    }

    private func timeString(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%01d:%02d", s / 60, s % 60)
    }

    private func errorString(_ error: MultiTrackRecorderError) -> String {
        switch error {
        case .permissionDenied:  return "Microphone permission denied — enable it in Settings."
        case .engineNotReady:    return "Audio engine not running."
        case .diskSpaceLow:      return "Not enough free disk space."
        case .fileCreationFailed: return "Could not create the recording file."
        }
    }
}
#endif
