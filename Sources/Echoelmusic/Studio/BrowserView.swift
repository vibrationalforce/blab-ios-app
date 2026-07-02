#if canImport(SwiftUI)
import SwiftUI

// BrowserView.swift
// Echoel — the Browser surface (Ableton's left column): recall synth SOUNDS
// (presets) and audition SAMPLES before they're used. A production staple in the
// DAW-look reorg. Pure browsing/recall — no high-frequency bio reads, so its
// segmented Picker is freeze-safe. Uncodixfy: solid fills, ≤8px radius, list rows
// with subtle hover/selected state, colour/opacity feedback only.

@MainActor
struct BrowserView: View {

    @Environment(PatchStore.self) private var patchStore
    @Environment(PolySynthVoice.self) private var synth
    @Environment(BeatPlayer.self) private var player

    private enum Tab: String, CaseIterable, Identifiable {
        case presets = "Presets"
        case samples = "Samples"
        var id: String { rawValue }
    }
    @State private var tab: Tab = .presets
    /// The last patch loaded to the synth (row highlight; recall confirmation).
    @State private var loadedPatchID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("Browser", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.bottom, 8)

            switch tab {
            case .presets: presetsList
            case .samples: samplesList
            }
        }
        .background(EchoelTheme.bg.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Browser")
                .font(EchoelTheme.font(20, .semibold)).foregroundStyle(EchoelTheme.text)
            Text("Recall a sound or audition a sample. Loading a preset applies it to the instrument you play.")
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
    }

    // MARK: - Presets

    private var presetsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(patchStore.sortedPatches) { patch in
                    presetRow(patch)
                }
            }
            .padding(16)
        }
    }

    private func presetRow(_ patch: SynthPatch) -> some View {
        let isLoaded = loadedPatchID == patch.id
        let isFav = patchStore.isFavorite(id: patch.id)
        return HStack(spacing: 12) {
            Button { toggleFavorite(patch) } label: {
                Image(systemName: isFav ? "star.fill" : "star")
                    .font(.system(size: 16))
                    .foregroundStyle(isFav ? EchoelTheme.accent : EchoelTheme.dim)
                    .frame(width: 44, height: 44)   // ≥44pt tap target (a11y)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFav ? "Unfavorite \(patch.name)" : "Favorite \(patch.name)")

            VStack(alignment: .leading, spacing: 1) {
                Text(patch.name)
                    .font(EchoelTheme.font(14, .medium)).foregroundStyle(EchoelTheme.text)
                    .lineLimit(1).truncationMode(.middle)
                if patchStore.isFactory(patch) {
                    Text("Factory").font(EchoelTheme.font(10)).foregroundStyle(EchoelTheme.dim)
                }
            }
            Spacer(minLength: 0)

            Button { load(patch) } label: {
                Text(isLoaded ? "Loaded" : "Load")
                    .font(EchoelTheme.font(13, .semibold))
                    .foregroundStyle(isLoaded ? EchoelTheme.onPrimary : EchoelTheme.accent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(isLoaded ? EchoelTheme.accent : EchoelTheme.fill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Load \(patch.name)")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .fill(isLoaded ? EchoelTheme.accent.opacity(0.12) : EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(isLoaded ? EchoelTheme.accent : EchoelTheme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { load(patch) }
    }

    // MARK: - Samples

    private var samplesList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(BeatPlayer.bundledSampleNames, id: \.self) { name in
                    sampleRow(name)
                }
            }
            .padding(16)
        }
    }

    private func sampleRow(_ name: String) -> some View {
        HStack(spacing: 12) {
            Button { player.auditionBundled(name) } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 22)).foregroundStyle(EchoelTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(name)")

            Text(name).font(EchoelTheme.font(14)).foregroundStyle(EchoelTheme.text)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(EchoelTheme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { player.auditionBundled(name) }
    }

    // MARK: - Actions

    private func load(_ patch: SynthPatch) {
        synth.apply(patch)
        patchStore.markUsed(id: patch.id)
        loadedPatchID = patch.id
    }

    private func toggleFavorite(_ patch: SynthPatch) {
        patchStore.toggleFavorite(id: patch.id)
    }
}
#endif
