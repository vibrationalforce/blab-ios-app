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
    @Environment(BioEventPublisher.self) private var events
    @Environment(BioSimulator.self) private var demoSource
    #if canImport(CoreBluetooth)
    @Environment(PolarH10BioPublisher.self) private var ble
    #endif
    #if canImport(CoreMIDI)
    @Environment(MIDIBusPublisher.self) private var midi
    #endif
    #if canImport(Network)
    @Environment(OSCSender.self) private var osc
    #endif

    var body: some View {
        HStack(spacing: 10) {
            metric(label: "HR",  value: hrString,        unit: "bpm")
            divider
            metric(label: "HRV", value: hrvString,       unit: nil)
            divider
            metric(label: "Br",  value: breathString,    unit: "/min")
            divider
            metric(label: "Coh", value: coherenceString, unit: nil)
            Spacer(minLength: 4)
            eventDot
            midiDot
            oscDot
            playButton
            sourceTag
        }
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

    // MARK: - Discrete bio-event indicator

    /// Amber dot — brightens for ~1 s after BioEventGraph publishes a
    /// discrete event (breath onset / motion peak) onto the bus.
    @ViewBuilder
    private var eventDot: some View {
        let now = CFAbsoluteTimeGetCurrent()
        let fresh = events.lastEventTimestamp > 0 && (now - events.lastEventTimestamp) < 1.0
        Circle()
            .fill(fresh ? Color.orange : Color.white.opacity(0.15))
            .frame(width: 6, height: 6)
            .accessibilityLabel(fresh ? "Bio event detected" : "No recent bio event")
    }

    // MARK: - OSC activity indicator

    /// Blue dot — bright while OSC is sending bus updates outbound,
    /// dim white when the sender is idle / not yet started.
    @ViewBuilder
    private var oscDot: some View {
        #if canImport(Network)
        let now = CFAbsoluteTimeGetCurrent()
        let fresh = osc.isActive && osc.lastSentTimestamp > 0 && (now - osc.lastSentTimestamp) < 1.0
        Circle()
            .fill(fresh ? Color.blue : Color.white.opacity(0.15))
            .frame(width: 6, height: 6)
            .accessibilityLabel(fresh ? "OSC streaming" : "OSC idle")
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

    /// Tappable source tag. Shows the live source label; when no real sensor
    /// is connected, tapping starts/stops the explicit "Demo" source so the
    /// instrument is playable without hardware.
    private var sourceTag: some View {
        Button {
            toggleDemo()
        } label: {
            Text(sourceText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(demoSource.isRunning ? Color.green.opacity(0.22) : Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(demoSource.isRunning ? Color.green : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bio source: \(sourceText). Tap to toggle demo source.")
    }

    /// Real sensor frames win; otherwise reflect demo state with a tap hint.
    private var sourceText: String {
        if let bio = bus.latestBio, bio.source != .fallback {
            #if canImport(CoreBluetooth)
            // Show the actual connected device (e.g. "Polar H10", "TICKR")
            // instead of the generic "BLE" so the user sees what's live.
            if bio.source == .ble, !ble.connectedDeviceName.isEmpty {
                return ble.connectedDeviceName
            }
            #endif
            return sourceLabel(bio.source)
        }
        return demoSource.isRunning ? "Demo" : "Demo ▷"
    }

    private func toggleDemo() {
        if demoSource.isRunning {
            demoSource.stop()
        } else {
            demoSource.start(publishing: bus)
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
