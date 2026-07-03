#if canImport(SwiftUI)
import SwiftUI

// WorkspaceView.swift
// Echoel — the app HOME. Founder pivot (2026-07-02): "radikal reduzieren auf qualitative
// Biofeedback Musik … eine adaptive Ansicht ohne weitere Untermenüs." So the shell is now
// ONE adaptive view — the bio-generative instrument (EchoelStudioView) — with only the
// always-on chrome above it (brand header + transport) and the immersive visual as a
// FLOATING window. The former 6-surface tab bar (Arrange/Clips/Mix/Bio/Browse) and the
// "Studio" door are removed from navigation: those surfaces still exist in code (reversible
// — restore the bottom bar to bring them back), they are simply no longer front-and-centre.
// The body arms itself and generates from within EchoelStudioView (Start → camera → music);
// the visual toggles from the header monitor.

@MainActor
struct WorkspaceView: View {

    /// Header pulse/visual monitors read the publisher only for a LOW-frequency flag
    /// (isRunning). The live ~10 Hz waveform stays inside the PulseMonitorMiniLive leaf
    /// (never this body) so the instrument below never rebuilds at 10 Hz (freeze rule).
    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif

    /// The immersive visual rides along as a FLOATING, resizable, show/hide window
    /// (founder 2026-07-02) — toggled from the header monitor, persisted across launches.
    @AppStorage("visual.floating.visible") private var floatingVisualVisible = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(EchoelTheme.border)
            TransportBar()
            Divider().overlay(EchoelTheme.border)
            // The ONE adaptive view: the bio-generative instrument. The floating visual
            // rides OVER its content area only (never the chrome), so it can't block the
            // transport. One Metal path app-wide (GPU rule).
            EchoelStudioView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    #if canImport(MetalKit) && canImport(UIKit)
                    if floatingVisualVisible {
                        FloatingVisualWindow(isPresented: $floatingVisualVisible)
                    }
                    #endif
                }
        }
        .background(EchoelTheme.bg.ignoresSafeArea())
    }

    /// Persistent brand header — always on screen (founder: "oben die Leiste soll immer
    /// sichtbar sein"). Centre: "Echoelmusic" + the running version/build. Left: app mark +
    /// glanceable live pulse. Right: the immersive-visual monitor, which shows/hides the
    /// floating visual. Uncodixfy-compliant (solid bg, 1px border, no glow).
    private var topBar: some View {
        ZStack {
            VStack(spacing: 1) {
                Text("Echoelmusic")
                    .font(EchoelTheme.font(14, .semibold))
                    .foregroundStyle(EchoelTheme.text)
                Text(Self.versionString)
                    .font(EchoelTheme.font(9))
                    .foregroundStyle(EchoelTheme.dim)
                    .accessibilityLabel("Version \(Self.versionString)")
            }
            HStack(spacing: 8) {
                // LEFT: app mark + glanceable live pulse (status only — arming happens in
                // the instrument's Start flow, so no separate navigation is needed).
                EchoelLogoMark().frame(width: 22, height: 22)
                #if canImport(AVFoundation)
                PulseMonitorMiniLive()
                #endif
                Spacer(minLength: 0)
                // RIGHT: immersive-visual monitor — tap to show/hide the floating visual.
                // `isRunning` is a LOW-frequency read (start/stop), safe in this body; the
                // live waveform stays in its own leaf.
                #if canImport(AVFoundation)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { floatingVisualVisible.toggle() }
                } label: {
                    ImmersiveMonitorMini(active: cameraRPPG.isRunning)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(floatingVisualVisible ? "Hide floating visual" : "Show floating visual")
                #endif
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(EchoelTheme.bg)
    }

    /// Short version + build, e.g. "v10.35.2 (1550)" — from the bundle, so it always
    /// reflects the actual installed build.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "—"
        let b = info?["CFBundleVersion"] as? String ?? "—"
        return "v\(v) (\(b))"
    }
}

// MARK: - Persistent transport bar (DAW chrome)

/// Always-on transport across the instrument: Play/Stop on the left, the Tempo field, and
/// a bars.beats.sixteenths position readout on the right. A LEAF view so its reads never
/// rebuild the instrument tree. It reads only the LOW-frequency Transport state (isPlaying,
/// tempo); the ~10 Hz position lives in its own `TransportPositionView` leaf so the
/// buttons/field don't churn (freeze rule). Play/Stop drives PatternEngine — the clock that
/// RELAYS into Transport — so the position/tempo shown stay authoritative.
@MainActor
private struct TransportBar: View {
    @Environment(Transport.self) private var transport
    @Environment(BeatPlayer.self) private var player
    @Environment(MetronomeVoice.self) private var metronome
    // Shared with the Compose panel (same @AppStorage keys + defaults). Read here so a
    // transport-bar tempo edit while LOCKED also persists the locked value — otherwise the
    // next generate() would snap the clock back to the stale lockedBPM.
    @AppStorage("studio.lockBPM") private var lockBPM = false
    @AppStorage("studio.lockedBPM") private var lockedBPM: Double = 70

    /// Writes tempo through PatternEngine.setTempo (which clamps AND relays into
    /// Transport), reads back the authoritative Transport tempo, and keeps the
    /// metronome click in time — otherwise a tempo change from the bar would leave an
    /// armed click running at the old BPM (Compose only synced the click on generate /
    /// lockBPM, never on a raw transport-bar tempo edit).
    private var tempoBinding: Binding<Double> {
        Binding(get: { transport.tempo },
                set: {
                    player.pattern.setTempo($0)
                    metronome.bpm = transport.tempo   // clamped, authoritative value
                    if lockBPM { lockedBPM = transport.tempo }   // keep the locked copy in step
                })
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { toggle() } label: {
                Image(systemName: transport.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.text)
                    .frame(width: 38, height: 32)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(transport.isPlaying ? "Stop" : "Play")

            EchoelValueField(label: "Tempo", value: tempoBinding,
                             range: Transport.minTempo...Transport.maxTempo,
                             unit: "BPM", decimals: 0, boxWidth: 78)

            Spacer(minLength: 0)

            TransportPositionView()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(EchoelTheme.bg)
    }

    private func toggle() {
        if transport.isPlaying { player.pattern.stop() }
        else { player.pattern.play() }
    }
}

/// The moving playhead — bars.beats.sixteenths (1-based, DAW convention). Isolated in
/// its OWN leaf because `transport.position` updates on every step (~10 Hz at 120 BPM);
/// keeping the read here means only this tiny label rebuilds, never the transport bar's
/// buttons/field or (crucially) the instrument below. Monospaced so width is steady.
@MainActor
private struct TransportPositionView: View {
    @Environment(Transport.self) private var transport

    var body: some View {
        let pos = transport.position
        let sixteenth = pos.step % Transport.stepsPerBeat
        Text(String(format: "%d.%d.%d", pos.bar + 1, pos.beat + 1, sixteenth + 1))
            .font(EchoelTheme.font(14, .medium).monospacedDigit())
            .foregroundStyle(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.dim)
            .accessibilityLabel("Position")
            .accessibilityValue("Bar \(pos.bar + 1), beat \(pos.beat + 1)")
    }
}
#endif
