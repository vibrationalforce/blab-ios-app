#if canImport(SwiftUI)
import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// SampleBrowserView.swift
// Echoel — browse samples and click to preview before loading one onto a pad.
// Built-in samples audition on a dedicated preview voice (the kit is untouched);
// "Use" assigns the sample to the target pad. External files import via the
// system Files browser, auditioned on pick.

@MainActor
struct SampleBrowserView: View {

    let track: Int
    @Environment(BeatPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var importerPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section("Built-in") {
                    ForEach(BeatPlayer.bundledSampleNames, id: \.self) { name in
                        row(name)
                    }
                }
                Section {
                    Button {
                        importerPresented = true
                    } label: {
                        Label("Import from Files…", systemImage: "folder")
                            .foregroundStyle(EchoelTheme.accent)
                    }
                } footer: {
                    Text("Imported files preview on pick, then load onto this pad.")
                }
            }
            .navigationTitle("Samples · \(BeatPlayer.trackNames[track])")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            #if canImport(UniformTypeIdentifiers)
            .fileImporter(
                isPresented: $importerPresented,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    player.audition(url: url)
                    player.importSample(track: track, from: url)
                    dismiss()
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private func row(_ name: String) -> some View {
        HStack(spacing: 12) {
            Button {
                player.auditionBundled(name)
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(EchoelTheme.accent)
            }
            .buttonStyle(.plain)

            Text(name)
                .font(.system(size: 14))
                .foregroundStyle(EchoelTheme.text)

            Spacer()

            Button {
                player.assignBundled(track: track, name: name)
                dismiss()
            } label: {
                Text("Use")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EchoelTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { player.auditionBundled(name) }
    }
}
#endif
