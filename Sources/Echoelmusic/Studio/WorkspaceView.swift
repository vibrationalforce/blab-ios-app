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
        case arrange, clips, compose
        var id: String { rawValue }
        var title: String {
            switch self {
            case .arrange: return "Arrange"
            case .clips:   return "Clips"
            case .compose: return "Compose"
            }
        }
        var systemImage: String {
            switch self {
            case .arrange: return "rectangle.split.3x1"
            case .clips:   return "square.grid.2x2"
            case .compose: return "waveform.path.ecg"
            }
        }
    }

    /// Persisted so the workstation reopens on the surface you left it on. Defaults
    /// to Arrange — the timeline is the foreground.
    @AppStorage("workspace.surface") private var surfaceRaw = Surface.arrange.rawValue
    private var surface: Surface { Surface(rawValue: surfaceRaw) ?? .arrange }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(EchoelTheme.border)
            ZStack {
                surfaceLayer(.arrange) { ArrangementView(embedded: true) }
                surfaceLayer(.clips)   { ClipView(embedded: true) }
                surfaceLayer(.compose) { EchoelStudioView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(EchoelTheme.border)
            bottomBar
        }
        .background(EchoelTheme.bg.ignoresSafeArea())
    }

    /// Persistent brand header — always on screen, every surface (founder: "oben die
    /// Leiste soll immer sichtbar sein … egal welche Ansicht"). Left: the E-with-waves
    /// app mark; right: "Echoelmusic" in the CI face + the running version/build, so
    /// you always know which build you're on. Uncodixfy-compliant (solid bg, 1px
    /// border, no glow).
    private var topBar: some View {
        HStack(spacing: 10) {
            EchoelLogoMark().frame(width: 26, height: 26)
            Spacer(minLength: 0)
            Text("Echoelmusic")
                .font(EchoelTheme.font(15, .semibold))
                .foregroundStyle(EchoelTheme.text)
            Text(Self.versionString)
                .font(EchoelTheme.font(11))
                .foregroundStyle(EchoelTheme.dim)
                .accessibilityLabel("Version \(Self.versionString)")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
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
#endif
