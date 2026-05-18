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
                    .tabItem { Label("Beat", systemImage: "square.grid.4x3.fill") }

                RecordTabPlaceholder()
                    .tabItem { Label("Record", systemImage: "mic.fill") }

                VideoTabPlaceholder()
                    .tabItem { Label("Video", systemImage: "video.fill") }

                ShareTabPlaceholder()
                    .tabItem { Label("Share", systemImage: "antenna.radiowaves.left.and.right") }
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
            symbol: "mic.fill",
            title: "Record",
            subtitle: "Coming in v1.1"
        )
    }
}

private struct VideoTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(
            symbol: "video.fill",
            title: "Video",
            subtitle: "Coming in v1.1"
        )
    }
}

private struct ShareTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(
            symbol: "antenna.radiowaves.left.and.right",
            title: "Share",
            subtitle: "Coming in v1.1"
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
