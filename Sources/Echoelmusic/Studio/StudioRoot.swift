#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct StudioRoot: View {

    @Environment(EngineBus.self) private var bus

    #if DEBUG
    @State private var simulator = BioSimulator()
    #endif

    var body: some View {
        VStack(spacing: 0) {
            BioStripView()
            TabView {
                BeatTab()
                    .tabItem { Label("Tools", systemImage: "square.grid.4x3.fill") }

                RecordTabPlaceholder()
                    .tabItem { Label("Works", systemImage: "waveform") }

                VideoTabPlaceholder()
                    .tabItem { Label("Sync", systemImage: "link") }

                ShareTabPlaceholder()
                    .tabItem { Label("Well", systemImage: "heart.fill") }
            }
        }
        #if DEBUG
        .task {
            simulator.start(publishing: bus)
        }
        #endif
    }
}

private struct RecordTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(
            symbol: "waveform",
            title: "Works",
            subtitle: "Sessions · Recordings · DAW handoff"
        )
    }
}

private struct VideoTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(
            symbol: "link",
            title: "Sync",
            subtitle: "OSC · MIDI · MPE · Air controllers"
        )
    }
}

private struct ShareTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(
            symbol: "heart.fill",
            title: "Well",
            subtitle: "Evidence-based breath & coherence"
        )
    }
}

private struct TabPlaceholder: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
