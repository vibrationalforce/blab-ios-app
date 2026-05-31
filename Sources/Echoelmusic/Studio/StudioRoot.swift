#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct StudioRoot: View {

    @Environment(EngineBus.self) private var bus

    /// Opt-in demo bio source (labeled "Demo"). Owned here, toggled from the
    /// bio strip's source tag so the instrument is playable without hardware.
    @State private var demoSource = BioSimulator()

    var body: some View {
        VStack(spacing: 0) {
            BioStripView()
                .environment(demoSource)
            TabView {
                BeatTab()
                    .tabItem { Label("Tools", systemImage: "square.grid.4x3.fill") }

                RecordTabPlaceholder()
                    .tabItem { Label("Works", systemImage: "waveform") }

                ModulationView()
                    .tabItem { Label("Sync", systemImage: "link") }

                WellView()
                    .tabItem { Label("Well", systemImage: "heart.fill") }
            }
        }
        #if DEBUG
        // Dev convenience: auto-start the demo so the bus is live in the
        // simulator/Xcode. Release requires an explicit tap on the source tag.
        .task {
            demoSource.start(publishing: bus)
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
