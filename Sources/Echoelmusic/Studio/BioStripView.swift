//
//  BioStripView.swift
//  Echoelmusic
//
//  Thin readout strip showing the latest BioSampleFrame published to
//  EngineBus. Lives at the top of StudioRoot so the bus is visibly
//  active across all tabs.
//
//  Honors master prompt §UI: solid dark background, legible numbers
//  first, source label tells the truth (Oura / HealthKit / fallback /
//  none). No glow, no glassmorphism, no decorative charts.
//

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct BioStripView: View {

    @Environment(EngineBus.self) private var bus
    @Environment(BioReactiveSynthVoice.self) private var voice
    #if canImport(CoreMIDI)
    @Environment(MIDIBusPublisher.self) private var midi
    #endif

    var body: some View {
        HStack(spacing: 16) {
            metric(label: "HR",  value: hrString,        unit: "bpm")
            divider
            metric(label: "HRV", value: hrvString,       unit: nil)
            divider
            metric(label: "Br",  value: breathString,    unit: "/min")
            divider
            metric(label: "Coh", value: coherenceString, unit: nil)
            divider
            metric(label: "→",   value: synthFramesString, unit: nil)
            Spacer(minLength: 0)
            midiDot
            playButton
            sourceTag
        }
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

    private func metric(label: String, value: String, unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
            if let unit {
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 10)
    }

    // MARK: - MIDI activity indicator

    /// Small dot that brightens for ~1 s after a MIDI controller event
    /// arrives on the bus. Honest "no controller connected" otherwise.
    @ViewBuilder
    private var midiDot: some View {
        #if canImport(CoreMIDI)
        let now = CFAbsoluteTimeGetCurrent()
        let fresh = midi.lastEventTimestamp > 0 && (now - midi.lastEventTimestamp) < 1.0
        Circle()
            .fill(fresh ? Color.green : Color.white.opacity(0.15))
            .frame(width: 6, height: 6)
            .accessibilityLabel(fresh ? "MIDI active" : "MIDI idle")
        #else
        EmptyView()
        #endif
    }

    // MARK: - Play toggle

    private var playButton: some View {
        Button {
            if voice.isPlayingNote {
                voice.releaseNote()
            } else {
                voice.playNote()
            }
        } label: {
            Image(systemName: voice.isPlayingNote ? "stop.fill" : "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(voice.isPlayingNote ? Color.white : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(voice.isPlayingNote ? Color.white.opacity(0.18) : Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voice.isPlayingNote ? "Stop bio-reactive voice" : "Play bio-reactive voice")
    }

    // MARK: - Source tag

    @ViewBuilder
    private var sourceTag: some View {
        if let bio = bus.latestBio {
            Text(sourceLabel(bio.source))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.secondary)
        } else {
            Text("No source")
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Formatting

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

    private var coherenceString: String {
        guard let v = bus.latestBio?.coherence else { return "—" }
        return String(format: "%.2f", v)
    }

    /// Count of frames the BioReactiveSynthVoice has applied to its
    /// EchoelDDSP — visible proof the bus → DSP chain is alive.
    private var synthFramesString: String {
        voice.framesApplied > 0 ? "\(voice.framesApplied)" : "—"
    }

    private func sourceLabel(_ source: BioSource) -> String {
        switch source {
        case .oura:       return "Oura"
        case .healthKit:  return "Health"
        case .ble:        return "BLE"
        case .watch:      return "Watch"
        case .cameraPPG:  return "PPG"
        case .fallback:   return "Demo"
        }
    }
}
#endif
