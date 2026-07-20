//
//  BodyVibeSurfaceView.swift
//  Echoelmusic
//
//  EchoelBodyVibe — the bio-generative INSTRUMENT surface for a track whose
//  built-in instrument is `.bioVoice`. Founder 2026-07-20: "Man wählt das ganz
//  normal als Instrument aus" — BodyVibe is an instrument among instruments (it
//  unites what Echoelmusic was as an instrument BEFORE the DMMW pivot, plus the
//  mimik/body-recognition work added since), and its editor door lands HERE.
//
//  FIRST SLICE: the live body strip (BioStripView leaf, "Read pulse" arms the
//  camera source) + this lane's OWN composition controls (Genre / Mood /
//  Variation via LaneCompositionSection) — delivering the founder's "Genre
//  Auswahl kommt auch in EchoelBodyVibe". Later slices fold in the sound/mood
//  panels, generate/evolve, the immersive visual surface and the Face-camera
//  source (A5, founder-gated Info.plist string).
//
//  Freeze law: this host body reads only LOW-frequency state (lane identity, the
//  camera start/stop flag) — every ~10 Hz bio read stays inside the BioStripView
//  leaf, never this host body.
//

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct BodyVibeSurfaceView: View {
    let laneID: UUID
    let laneName: String

    /// Document-level reads only (freeze law) — the lane name, for the header.
    @Environment(TimelineStore.self) private var timeline
    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif
    @Environment(EngineBus.self) private var bus
    @Environment(PolySynthVoice.self) private var synth
    @Environment(\.dismiss) private var dismiss

    /// Guards the async camera start so a rapid arm can't overlap (pattern:
    /// BioSourceView.armTask).
    @State private var armTask: Task<Void, Never>?

    private var displayName: String {
        let live = timeline.document.lanes.first(where: { $0.id == laneID })?.name ?? laneName
        return live.isEmpty ? "EchoelBodyVibe" : live
    }

    /// LOW-frequency read only (flips on start/stop) — never the ~10 Hz
    /// waveform/BPM (freeze rule): those live inside BioStripView's leaf body.
    private var isRunning: Bool {
        #if canImport(AVFoundation)
        return cameraRPPG.isRunning
        #else
        return false
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    // Live body — its OWN leaf (freeze rule). "Read pulse" arms the
                    // shared camera source; tap-to-learn explains the numbers.
                    BioStripView(measuring: isRunning, onStartPulse: { arm() })
                        .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radius))
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .strokeBorder(EchoelTheme.border, lineWidth: 1))
                    // This lane's OWN generative composition — Genre / Mood /
                    // Variation (the "Genre auch in EchoelBodyVibe" ask). The same
                    // one control the per-track Sound & FX editor hosts, re-used
                    // here so BodyVibe never grows a parallel genre picker.
                    LaneCompositionSection(laneName: displayName, laneID: laneID)
                    footer
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(EchoelTheme.bg.ignoresSafeArea())
            .navigationTitle("EchoelBodyVibe")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(EchoelTheme.accent)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your body plays the voice")
                .font(EchoelTheme.font(15, .semibold)).foregroundStyle(EchoelTheme.text)
            Text("Read your pulse, then choose a genre and mood — the generative composition follows your body.")
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        Text("Genre, mood and variation here are this track's own — saved with the song, they steer the next Generate/Evolve without changing your other tracks.")
            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Arm the shared camera pulse source + timbre modulation — idempotent on the
    /// publisher, so it stays coherent with Compose's own control (pattern:
    /// BioSourceView.arm). First slice offers start only; stop stays with the
    /// header pill / Compose, which own the shared source's lifecycle.
    private func arm() {
        #if canImport(AVFoundation)
        armTask?.cancel()
        armTask = Task { @MainActor in
            await cameraRPPG.start(publishing: bus)
            guard !Task.isCancelled else { return }
            synth.bioModulationEnabled = true
        }
        #endif
    }
}
#endif
