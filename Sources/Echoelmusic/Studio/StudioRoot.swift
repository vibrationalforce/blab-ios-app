#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct StudioRoot: View {
    var body: some View {
        TabView {
            BeatTabPlaceholder()
                .tabItem { Label("Beat", systemImage: "square.grid.4x3.fill") }

            RecordTabPlaceholder()
                .tabItem { Label("Record", systemImage: "mic.fill") }

            VideoTabPlaceholder()
                .tabItem { Label("Video", systemImage: "video.fill") }

            ShareTabPlaceholder()
                .tabItem { Label("Share", systemImage: "antenna.radiowaves.left.and.right") }
        }
    }
}

private struct BeatTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(
            symbol: "square.grid.4x3.fill",
            title: "Beat",
            subtitle: "16-step sequencer · wires up W1-Day-3"
        )
    }
}

private struct RecordTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(
            symbol: "mic.fill",
            title: "Record",
            subtitle: "Multi-track recorder · W2"
        )
    }
}

private struct VideoTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(
            symbol: "video.fill",
            title: "Video",
            subtitle: "Camera + trim · W2"
        )
    }
}

private struct ShareTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(
            symbol: "antenna.radiowaves.left.and.right",
            title: "Share",
            subtitle: "RTMP stream + export · W3"
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
