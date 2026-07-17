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
    /// LANE mode (S2-W3, the EchoelSampler track door): when set, "Use" hands the
    /// caller a persistable sample REF ("drum:<Name>" / "lib:<Category>/<Name>",
    /// or — for a Files pick — the absolute path of its MediaLibrary copy)
    /// instead of assigning BeatPlayer pad `track`. Audition still runs on the
    /// shared preview voice; the pad-specific Current/Reset section is hidden.
    /// nil (default) = the original pad-assign behavior, call sites unchanged.
    var onUse: ((String) -> Void)? = nil
    @Environment(BeatPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var importerPresented = false
    /// A file picked from the device, held so the user can audition it
    /// repeatedly BEFORE committing it to the pad (preview-before-assign).
    @State private var pickedURL: URL?

    private var pickedName: String { pickedURL?.deletingPathExtension().lastPathComponent ?? "" }

    var body: some View {
        NavigationStack {
            List {
                if onUse == nil, player.isCustom(track) {
                    Section("Current") {
                        HStack(spacing: 12) {
                            Text(player.sampleLabels[track])
                                .font(EchoelTheme.font(14)).foregroundStyle(EchoelTheme.text)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { player.resetSample(track: track) } label: {
                                Text("Reset to \(BeatPlayer.trackNames[track])")
                                    .font(EchoelTheme.font(13, .semibold))
                                    .foregroundStyle(EchoelTheme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Built-in") {
                    ForEach(BeatPlayer.bundledSampleNames, id: \.self) { name in
                        row(name)
                    }
                }
                // Categorized library (Resources/Samples/<Category>/*.wav) — the
                // big browsable selection: Bass · Stab · Keys · Pad · Tone · Tom ·
                // Conga · FX · drum variations. Audition ▶ before Use, like above.
                ForEach(BeatPlayer.library, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.samples) { sample in
                            libraryRow(sample)
                        }
                    }
                }
                if let url = pickedURL {
                    Section("Selected from Files") {
                        HStack(spacing: 12) {
                            Button { player.audition(url: url) } label: {
                                Image(systemName: "play.circle")
                                    .font(.system(size: 20)).foregroundStyle(EchoelTheme.accent)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Preview \(pickedName)")

                            Text(pickedName)
                                .font(EchoelTheme.font(14)).foregroundStyle(EchoelTheme.text)
                                .lineLimit(1).truncationMode(.middle)

                            Spacer()

                            Button {
                                usePickedFile(url)
                            } label: {
                                Text("Use").font(EchoelTheme.font(13, .semibold))
                                    .foregroundStyle(EchoelTheme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { player.audition(url: url) }
                    }
                }
                Section {
                    Button {
                        importerPresented = true
                    } label: {
                        Label(pickedURL == nil ? "Import from Files…" : "Pick a different file…",
                              systemImage: "folder")
                            .foregroundStyle(EchoelTheme.accent)
                    }
                } footer: {
                    Text(onUse == nil
                         ? "Imported files preview first — tap ▶ to audition, then Use to load it onto this pad."
                         : "Imported files preview first — tap ▶ to audition, then Use to put it on this track.")
                }
            }
            .navigationTitle(onUse == nil ? "Samples · \(BeatPlayer.trackNames[track])" : "Samples")
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
                    pickedURL = url
                    player.audition(url: url)   // immediate first preview; assign only on "Use"
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
                .font(EchoelTheme.font(14))
                .foregroundStyle(EchoelTheme.text)

            Spacer()

            Button {
                if let onUse {
                    onUse("drum:\(name)")   // BeatPlayer's persisted bundled-ref format
                } else {
                    player.assignBundled(track: track, name: name)
                }
                dismiss()
            } label: {
                Text("Use")
                    .font(EchoelTheme.font(13, .semibold))
                    .foregroundStyle(EchoelTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { player.auditionBundled(name) }
    }

    /// LANE mode "Use" for a Files pick: copy the file into the App-Group media
    /// home (the timeline `mediaRef` convention — a MediaLibrary path survives
    /// relaunch AND app updates via H6 name re-rooting; a raw Files URL would die
    /// with its security scope) and hand the copy's absolute path to the caller.
    /// PAD mode keeps BeatPlayer's own bookmark-based import.
    private func usePickedFile(_ url: URL) {
        if let onUse {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let dest = try MediaLibrary.importAudio(from: url)
                onUse(dest.path)
            } catch {
                log.log(.error, category: .audio,
                        "SampleBrowser: lane sample import failed: \(error)")
                return   // keep the sheet open — nothing was assigned
            }
        } else {
            _ = player.importSample(track: track, from: url)
        }
        dismiss()
    }

    @ViewBuilder
    private func libraryRow(_ sample: BeatPlayer.LibrarySample) -> some View {
        HStack(spacing: 12) {
            Button {
                player.auditionLibrary(sample)
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(EchoelTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(sample.name)")

            Text(sample.name)
                .font(EchoelTheme.font(14))
                .foregroundStyle(EchoelTheme.text)
                .lineLimit(1).truncationMode(.middle)

            Spacer()

            Button {
                if let onUse {
                    onUse("lib:\(sample.id)")   // BeatPlayer's persisted library-ref format
                } else {
                    player.assignLibrary(track: track, sample)
                }
                dismiss()
            } label: {
                Text("Use")
                    .font(EchoelTheme.font(13, .semibold))
                    .foregroundStyle(EchoelTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { player.auditionLibrary(sample) }
    }
}
#endif
