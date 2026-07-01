#if canImport(SwiftUI)
import SwiftUI

// WorkspaceView.swift
// Echoel — the workstation HOME. A persistent surface switcher with the
// Arrangement/Clips timeline in the FOREGROUND (pro-DAW IA, like FL/Ableton),
// and the bio-compose instrument as one surface among them. Per the founder
// (2026-06-21): "die Arrangement View bzw. Clips muss im Vordergrund sein… das
// ganze Biofeedback Teil ist eigentlich nur ein Tool." See docs/dev/DMMW_ARCHITECTURE.md.
//
// All three surfaces stay MOUNTED (ZStack + opacity), so switching never unmounts
// the Compose instrument and its audio lifecycle (.task in EchoelmusicApp,
// onDisappear { stopEverything() }) is untouched — only one surface is visible
// and interactive at a time.

@MainActor
struct WorkspaceView: View {

    /// The foreground surfaces. Arrange/Clips are the home (the song); Compose is
    /// the bio-generative instrument, now one tool rather than the whole app.
    enum Surface: String, CaseIterable, Identifiable {
        case arrange, clips, compose, mix, bio
        var id: String { rawValue }
        var title: String {
            switch self {
            case .arrange: return "Arrange"
            case .clips:   return "Clips"
            case .compose: return "Compose"
            case .mix:     return "Mix"
            case .bio:     return "Bio"
            }
        }
        var systemImage: String {
            switch self {
            case .arrange: return "rectangle.split.3x1"
            case .clips:   return "square.grid.2x2"
            case .compose: return "waveform.path.ecg"
            case .mix:     return "slider.vertical.3"
            case .bio:     return "heart.fill"
            }
        }
    }

    /// Persisted so the workstation reopens on the surface you left it on. Defaults
    /// to Arrange — the timeline is the foreground.
    @AppStorage("workspace.surface") private var surfaceRaw = Surface.arrange.rawValue
    private var surface: Surface { Surface(rawValue: surfaceRaw) ?? .arrange }

    /// The persistent header's live monitors (founder idea): left EKG pulse, right
    /// immersive visual. Tapping a mini opens it full screen.
    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif
    @State private var expandedMonitor: ExpandedMonitor?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(EchoelTheme.border)
            TransportBar()
            Divider().overlay(EchoelTheme.border)
            ZStack {
                surfaceLayer(.arrange) { ArrangementView(embedded: true) }
                surfaceLayer(.clips)   { ClipView(embedded: true) }
                surfaceLayer(.compose) { EchoelStudioView() }
                surfaceLayer(.mix)     { ChannelRackView(embedded: true) }
                surfaceLayer(.bio)     { BioSourceView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(EchoelTheme.border)
            bottomBar
        }
        .background(EchoelTheme.bg.ignoresSafeArea())
        .fullScreenCover(item: $expandedMonitor) { ExpandedMonitorView(kind: $0) }
    }

    /// Persistent brand header — always on screen, every surface (founder: "oben die
    /// Leiste soll immer sichtbar sein … egal welche Ansicht"). Left: the E-with-waves
    /// app mark; right: "Echoelmusic" in the CI face + the running version/build, so
    /// you always know which build you're on. Uncodixfy-compliant (solid bg, 1px
    /// border, no glow).
    private var topBar: some View {
        ZStack {
            // Centred brand with the small version directly beneath it (founder), so
            // both header corners are free for the live monitors.
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
                // LEFT (founder red-1): app mark + live EKG pulse monitor.
                EchoelLogoMark().frame(width: 22, height: 22)
                #if canImport(AVFoundation)
                Button { expandedMonitor = .pulse } label: {
                    // Live reads live in PulseMonitorMiniLive (a leaf) — NOT here. Reading
                    // cameraRPPG.waveform/detectedBPM/isLocked in this body subscribed
                    // WorkspaceView (parent of every surface) to the 10 Hz pulse signal, so
                    // the whole surface tree rebuilt 10×/s during biofeedback and tore down
                    // any open dropdown menu in the active surface (the recurring freeze).
                    PulseMonitorMiniLive()
                }
                .buttonStyle(.plain)
                #endif
                Spacer(minLength: 0)
                // RIGHT (founder red-2): live immersive-visual monitor (full corner).
                #if canImport(AVFoundation)
                Button { expandedMonitor = .immersive } label: {
                    ImmersiveMonitorMini(active: cameraRPPG.isRunning)
                }
                .buttonStyle(.plain)
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

    /// Keep every surface mounted; show/enable only the selected one. This preserves
    /// the Compose instrument's lifecycle across switches (no unmount → no audio stop).
    @ViewBuilder
    private func surfaceLayer<Content: View>(_ s: Surface,
                                             @ViewBuilder content: () -> Content) -> some View {
        let active = surface == s
        content()
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
    }

    /// Persistent bottom navigation — always visible ("durchgehend zu sehen"), one
    /// equal-width tab per surface (icon over label). Chrome-only: surfaces stay
    /// mounted in the ZStack above, so switching never touches the Compose audio
    /// lifecycle. Uncodixfy-compliant (EchoelTheme, top border, no glow/scale).
    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(Surface.allCases) { s in
                Button { surfaceRaw = s.rawValue } label: {
                    VStack(spacing: 3) {
                        Image(systemName: s.systemImage).font(.system(size: 17, weight: .medium))
                        Text(s.title).font(EchoelTheme.font(10, .medium))
                    }
                    .foregroundStyle(surface == s ? EchoelTheme.accent : EchoelTheme.dim)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.title)
                .accessibilityAddTraits(surface == s ? .isSelected : [])
            }
        }
        .background(EchoelTheme.bg)
    }
}

// MARK: - Persistent transport bar (DAW chrome)

/// Always-on transport across every surface (Ableton/Logic-style): Play/Stop on the
/// left, the Tempo field, and a bars.beats.sixteenths position readout on the right.
/// A LEAF view (sibling of the surfaces, not an ancestor) so its reads never rebuild
/// the surface tree. It reads only the LOW-frequency Transport state (isPlaying,
/// tempo); the ~10 Hz position lives in its own `TransportPositionView` leaf so the
/// buttons/field don't churn (freeze rule). Play/Stop drives PatternEngine — the
/// clock that RELAYS into Transport — so the position/tempo shown stay authoritative.
@MainActor
private struct TransportBar: View {
    @Environment(Transport.self) private var transport
    @Environment(BeatPlayer.self) private var player

    /// Writes tempo through PatternEngine.setTempo (which clamps AND relays into
    /// Transport), reads back the authoritative Transport tempo.
    private var tempoBinding: Binding<Double> {
        Binding(get: { transport.tempo },
                set: { player.pattern.setTempo($0) })
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
/// buttons/field or (crucially) any surface above/below. Monospaced so width is steady.
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
