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
            surfacePicker
            Divider().overlay(EchoelTheme.border)
            ZStack {
                surfaceLayer(.arrange) { ArrangementView(embedded: true) }
                surfaceLayer(.clips)   { ClipView(embedded: true) }
                surfaceLayer(.compose) { EchoelStudioView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(EchoelTheme.bg.ignoresSafeArea())
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

    private var surfacePicker: some View {
        HStack(spacing: 8) {
            ForEach(Surface.allCases) { s in
                Button { surfaceRaw = s.rawValue } label: {
                    HStack(spacing: 6) {
                        Image(systemName: s.systemImage).font(.system(size: 13))
                        Text(s.title).font(EchoelTheme.font(13, .semibold))
                    }
                    .foregroundStyle(surface == s ? EchoelTheme.onPrimary : EchoelTheme.text)
                    .padding(.horizontal, 14).frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(surface == s ? EchoelTheme.text : EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: surface == s ? 0 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.title)
                .accessibilityAddTraits(surface == s ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
#endif
