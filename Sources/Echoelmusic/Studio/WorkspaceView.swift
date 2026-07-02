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
        case arrange, clips, compose, mix, bio, browser
        var id: String { rawValue }
        var title: String {
            switch self {
            case .arrange: return "Arrange"
            case .clips:   return "Clips"
            case .compose: return "Compose"
            case .mix:     return "Mix"
            case .bio:     return "Bio"
            case .browser: return "Browse"
            }
        }
        var systemImage: String {
            switch self {
            case .arrange: return "rectangle.split.3x1"
            case .clips:   return "square.grid.2x2"
            case .compose: return "waveform.path.ecg"
            case .mix:     return "slider.vertical.3"
            case .bio:     return "heart.fill"
            case .browser: return "folder"
            }
        }

        /// Front-door surfaces — the calm bio-session flow (founder pivot 2026-07-02:
        /// reduce the surface, keep the engine). The body + the instrument are the home.
        static let primary: [Surface] = [.bio, .compose]
        /// DAW/advanced surfaces — one "Studio" door away, not deleted (reversible).
        static let advanced: [Surface] = [.arrange, .clips, .mix, .browser]
    }

    /// Persisted so the workstation reopens on the surface you left it on. Defaults
    /// to Compose — the bio-generative instrument is the front door now.
    @AppStorage("workspace.surface") private var surfaceRaw = Surface.compose.rawValue
    private var surface: Surface { Surface(rawValue: surfaceRaw) ?? .compose }

    /// Presents the Studio door — one sheet listing the advanced surfaces. The ONLY
    /// modal on WorkspaceView (the floating visual is an `.overlay`, not a sheet; well
    /// under any metadata limit — the sheet-chain ceiling is EchoelStudioView's, not this
    /// view's).
    @State private var showStudioDoor = false

    /// The persistent header's live monitors (founder idea): left EKG pulse, right
    /// immersive visual. Tapping a mini opens it full screen.
    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif

    /// The immersive visual now rides along as a FLOATING, resizable, show/hide window
    /// (founder 2026-07-02) instead of a fullscreen-only cover. Persisted so it reopens
    /// as you left it. Toggled from the header monitor.
    @AppStorage("visual.floating.visible") private var floatingVisualVisible = false

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
                surfaceLayer(.browser) { BrowserView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The floating visual window rides OVER the surface area only (not the chrome),
            // so it never blocks the transport or bottom nav. One Metal path at the root.
            .overlay {
                #if canImport(MetalKit) && canImport(UIKit)
                if floatingVisualVisible {
                    FloatingVisualWindow(isPresented: $floatingVisualVisible)
                }
                #endif
            }
            Divider().overlay(EchoelTheme.border)
            bottomBar
        }
        .background(EchoelTheme.bg.ignoresSafeArea())
        .sheet(isPresented: $showStudioDoor) {
            StudioDoorView(current: surface) { picked in
                surfaceRaw = picked.rawValue
                showStudioDoor = false
            }
        }
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
                // The pulse mini is glanceable STATUS; tapping it opens the ONE bio home
                // (the Bio surface), not a separate fullscreen pulse view — one place for
                // the body (founder: no duplicate paths). Live reads stay in the
                // PulseMonitorMiniLive leaf (NOT this body): reading cameraRPPG.waveform/
                // detectedBPM/isLocked here would subscribe WorkspaceView (parent of every
                // surface) to the 10 Hz pulse and rebuild the whole tree, tearing down any
                // open dropdown in the active surface (the recurring freeze).
                Button { surfaceRaw = Surface.bio.rawValue } label: {
                    // PulseMonitorMiniLive (leaf) owns the accessibility element (live BPM +
                    // "Opens the Bio page"); no label here, so VoiceOver reads one element.
                    PulseMonitorMiniLive()
                }
                .buttonStyle(.plain)
                #endif
                Spacer(minLength: 0)
                // RIGHT (founder red-2): live immersive-visual monitor. Tapping now shows/
                // hides the FLOATING visual window (founder 2026-07-02) rather than a
                // fullscreen cover. `isRunning` is a LOW-frequency read (start/stop), so it
                // is safe in this header body; the live waveform stays in its own leaf.
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

    /// Persistent bottom navigation — always visible ("durchgehend zu sehen"). Reduced
    /// to the calm bio-session flow (founder pivot): the PRIMARY surfaces + one
    /// **Studio** door to the advanced DAW surfaces. Chrome-only: every surface stays
    /// mounted in the ZStack above, so switching (and the Studio door) never touches the
    /// Compose audio lifecycle. Uncodixfy-compliant (EchoelTheme, top border, no glow).
    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(Surface.primary) { s in
                tabButton(icon: s.systemImage, label: s.title,
                          selected: surface == s) { surfaceRaw = s.rawValue }
            }
            // The Studio door — selected whenever an advanced surface is showing, so
            // there's always a visible "you are in Studio" state and a way back (tap a
            // primary tab). Opens ONE sheet listing the advanced surfaces.
            tabButton(icon: "square.stack.3d.up", label: "Studio",
                      selected: Surface.advanced.contains(surface)) { showStudioDoor = true }
        }
        .background(EchoelTheme.bg)
    }

    /// One equal-width bottom tab (icon over label). Shared by the primary tabs and the
    /// Studio door so both read identically.
    @ViewBuilder
    private func tabButton(icon: String, label: String,
                           selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium))
                Text(label).font(EchoelTheme.font(10, .medium))
            }
            .foregroundStyle(selected ? EchoelTheme.accent : EchoelTheme.dim)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Studio door (advanced surfaces, one sheet away)

/// The single entry to the advanced DAW surfaces (Arrange · Clips · Mix · Browse),
/// kept out of the calm front-door flow but NOT deleted (founder pivot 2026-07-02:
/// reduce the surface, keep the engine — reversible). A plain list; picking a row
/// switches the mounted surface and dismisses. Uncodixfy: solid bg, 1px borders,
/// ≤8px radius, no glow.
@MainActor
private struct StudioDoorView: View {
    let current: WorkspaceView.Surface
    let onPick: (WorkspaceView.Surface) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Text("The full production surfaces. The calm bio-session flow stays a tap away in the bar below.")
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(WorkspaceView.Surface.advanced) { s in
                        Button { onPick(s) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: s.systemImage)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(current == s ? EchoelTheme.accent : EchoelTheme.text)
                                    .frame(width: 24)
                                Text(s.title)
                                    .font(EchoelTheme.font(15, .medium))
                                    .foregroundStyle(EchoelTheme.text)
                                Spacer(minLength: 0)
                                if current == s {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(EchoelTheme.accent)
                                }
                                Image(systemName: "chevron.right").font(.system(size: 11))
                                    .foregroundStyle(EchoelTheme.dim)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                                .strokeBorder(EchoelTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(s.title)
                        .accessibilityAddTraits(current == s ? .isSelected : [])
                    }
                }
                .padding(16)
            }
            .background(EchoelTheme.bg.ignoresSafeArea())
            .navigationTitle("Studio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(EchoelTheme.accent)
                }
            }
        }
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
    @Environment(MetronomeVoice.self) private var metronome

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
