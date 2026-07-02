#if canImport(SwiftUI)
import SwiftUI

// BioSourceView.swift
// Echoel — the Bio SOURCE page. Biofeedback's "good place": the body as ONE
// modulation source among many (Arrange · Clips · Compose · Mix · Bio), NOT the
// app's always-on center. Arming the source starts the camera pulse publishing to
// the EngineBus, which the synth timbre, the immersive visual, and the brainwave
// entrainment all ride. You HEAR the body once you PLAY the instrument (Compose /
// transport) — so Bio is the source/lane you configure, not a self-contained
// instrument. Shares the one `CameraRPPGBioPublisher` with Compose (start/stop are
// idempotent → `isRunning` is the single source of truth), so arming here and there
// stays coherent. Uncodixfy: solid fills, ≤8px radius, colour/opacity feedback only.

@MainActor
struct BioSourceView: View {

    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif
    @Environment(EngineBus.self) private var bus
    @Environment(PolySynthVoice.self) private var synth

    /// Guards the async camera start so a rapid arm/disarm can't overlap.
    @State private var armTask: Task<Void, Never>?
    @State private var showBreath = false

    /// LOW-frequency read only (flips on start/stop) — never the ~10 Hz waveform/BPM
    /// (freeze rule): those live inside the leaf views (BioStripView / PulseMeasurementView).
    private var isRunning: Bool {
        #if canImport(AVFoundation)
        return cameraRPPG.isRunning
        #else
        return false
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                armCard
                #if canImport(AVFoundation)
                // Live numbers — a Picker-free leaf that reads the high-frequency bio
                // itself, so its churn never reaches this page's controls.
                BioStripView(measuring: isRunning, onStartPulse: { arm(true) })
                    .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radius))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
                if isRunning {
                    PulseMeasurementView()
                }
                #endif
                routingSection
                entrainmentSection
                breathButton
            }
            .padding(16)
        }
        .background(EchoelTheme.bg.ignoresSafeArea())
        .fullScreenCover(isPresented: $showBreath) { BreathGuideView() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bio Source")
                .font(EchoelTheme.font(20, .semibold)).foregroundStyle(EchoelTheme.text)
            Text("Your body as a modulation source — heart, breath and coherence drive the sound, the visual and the entrainment. One source among many.")
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Arm

    /// The primary control: arm/disarm the body as a live source. Green = live.
    private var armCard: some View {
        Button { arm(!isRunning) } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isRunning ? EchoelTheme.onPrimary : EchoelTheme.text)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isRunning ? "Bio input armed" : "Arm bio input")
                        .font(EchoelTheme.font(15, .semibold))
                        .foregroundStyle(isRunning ? EchoelTheme.onPrimary : EchoelTheme.text)
                    Text(isRunning ? "Cover the rear camera + flash with a fingertip"
                                   : "Reads your pulse with the camera")
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(isRunning ? EchoelTheme.onPrimary.opacity(0.85) : EchoelTheme.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .fill(isRunning ? EchoelTheme.accent : EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(isRunning ? Color.clear : EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRunning ? "Disarm bio input" : "Arm bio input")
        .accessibilityAddTraits(isRunning ? .isSelected : [])
    }

    // MARK: - Routing (what the body drives)

    private var routingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Routing").font(EchoelTheme.font(11, .medium)).foregroundStyle(EchoelTheme.dim)
            Toggle(isOn: Binding(get: { synth.bioModulationEnabled },
                                 set: { synth.bioModulationEnabled = $0 })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Body → sound").font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
                    Text("HRV and pulse shape the synth timbre while you play")
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                }
            }
            .tint(EchoelTheme.accent)

            Toggle(isOn: Binding(get: { synth.bioMappingHarmonic },
                                 set: { synth.bioMappingHarmonic = $0 })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Harmonic mapping").font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
                    Text("The body drives the overtones directly — HRV opens the harmonic richness, breath swells the amplitude")
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                }
            }
            .tint(EchoelTheme.accent)
            .disabled(!synth.bioModulationEnabled)
            .opacity(synth.bioModulationEnabled ? 1 : 0.5)

            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(EchoelTheme.dim)
                Text("Body → visual reacts automatically in the immersive view")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    // MARK: - Entrainment (body-driven brainwave stimulus)

    private var entrainmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { synth.entrainmentEnabled },
                                 set: { synth.entrainmentEnabled = $0 })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Entrainment").font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
                    Text("Body-driven brainwave stimulus (isochronic)")
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                }
            }
            .tint(EchoelTheme.accent)

            Text("Band").font(EchoelTheme.font(10, .medium)).foregroundStyle(EchoelTheme.dim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    bandChip("Auto", nil)
                    ForEach(BrainwaveBand.allCases, id: \.self) { band in
                        bandChip("\(band.rawValue) · \(Int(band.centerFrequency)) Hz", band)
                    }
                }
            }

            Text("The body's HRV coherence selects the band (aroused → Beta, relaxed → Alpha, settled → Theta); the stimulus deepens only on a good pulse lock. Audio uses isochronic amplitude pulses; the on-screen pulse stays under the 3 Hz flash-safety limit.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)

            Text("Safety: not while driving or operating machinery; not under the influence of alcohol or drugs; coordinate any therapeutic use with your provider. For self-observation, not medical diagnosis. Max 3 Hz visual flash.")
                .font(EchoelTheme.font(11, .medium)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    private func bandChip(_ label: String, _ band: BrainwaveBand?) -> some View {
        let selected = synth.entrainmentManualBand == band
        return Button { synth.entrainmentManualBand = band } label: {
            Text(label)
                .font(EchoelTheme.font(12, .semibold))
                .foregroundStyle(selected ? EchoelTheme.onPrimary : EchoelTheme.text)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? EchoelTheme.accent : EchoelTheme.fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(band == nil ? "Auto band, bio-selected" : "Pin \(label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Breath

    private var breathButton: some View {
        Button { showBreath = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "wind").font(.system(size: 14))
                Text("Breath guide").font(EchoelTheme.font(13, .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)
            }
            .foregroundStyle(EchoelTheme.text)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    /// Arm/disarm the shared camera source + timbre modulation. `start`/`stop` are
    /// idempotent on the publisher, so this stays coherent with Compose's own control.
    private func arm(_ on: Bool) {
        #if canImport(AVFoundation)
        armTask?.cancel()
        if on {
            armTask = Task { @MainActor in
                await cameraRPPG.start(publishing: bus)
                guard !Task.isCancelled else { return }
                synth.bioModulationEnabled = true
            }
        } else {
            cameraRPPG.stop()
            synth.bioModulationEnabled = false
        }
        #endif
    }
}
#endif
