#if canImport(SwiftUI)
import SwiftUI

// ClipView.swift
// Echoel — the session grid: launchable cells, each a saved drum pattern and/or
// melody. Capture the current take into an empty slot; tap a filled slot to fire
// it into the live transport (Ableton-session style). Launch is immediate for
// v1 — quantize-to-bar is a later cycle (LaunchQuantizer already exists).
//
// The store is pure data; capture/launch live here because this view holds the
// live PatternEngine + PianoRollModel in the environment.

@MainActor
struct ClipView: View {

    @Environment(ClipStore.self) private var clips
    @Environment(BeatPlayer.self) private var beatPlayer
    @Environment(PianoRollModel.self) private var pianoRoll
    @Environment(\.dismiss) private var dismiss

    /// `true` when hosted as a foreground workspace surface (WorkspaceView): drop the
    /// sheet's NavigationStack + "Done", since the surface switcher owns the chrome.
    var embedded = false

    @State private var renaming: Int?
    @State private var renameText = ""

    /// Muted slot tints — accent-green is reserved for live bio signal, so clip
    /// colours stay desaturated chrome (CLAUDE.md: no neon).
    private static let palette: [Color] = [
        Color(red: 0.30, green: 0.45, blue: 0.65),
        Color(red: 0.55, green: 0.40, blue: 0.60),
        Color(red: 0.60, green: 0.50, blue: 0.35),
        Color(red: 0.35, green: 0.55, blue: 0.50),
        Color(red: 0.60, green: 0.40, blue: 0.40),
        Color(red: 0.45, green: 0.55, blue: 0.40),
        Color(red: 0.40, green: 0.45, blue: 0.60),
        Color(red: 0.55, green: 0.45, blue: 0.50)
    ]

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .navigationTitle("Clips")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    }
            }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<ClipStore.slotCount, id: \.self) { index in
                    slot(index)
                }
            }
            .padding(16)

            Text("Tap an empty cell to capture the current beat + melody. Tap a filled cell to launch it. Hold for more.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
        }
        .background(EchoelTheme.bg)
        .alert("Rename clip", isPresented: renamingBinding) {
            TextField("Name", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    // MARK: - Slot

    @ViewBuilder
    private func slot(_ index: Int) -> some View {
        if let clip = clips.slots[index] {
            filledSlot(index, clip)
        } else {
            emptySlot(index)
        }
    }

    private func emptySlot(_ index: Int) -> some View {
        Button { capture(into: index) } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.title3).foregroundStyle(EchoelTheme.dim)
                Text("Capture")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            }
            .frame(maxWidth: .infinity).frame(height: 88)
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(EchoelTheme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Empty clip \(index + 1)")
        .accessibilityHint("Captures the current beat and melody into this slot")
    }

    private func filledSlot(_ index: Int, _ clip: Clip) -> some View {
        let tint = Self.palette[clip.colorIndex % Self.palette.count]
        return Button { launch(clip) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    // Leading badge = the clip KIND (Audio · MIDI · Video · Visual), so
                    // the typed timeline reads at a glance. Playable kinds also show a
                    // play glyph; non-playable lanes don't pretend (isPlayable).
                    Image(systemName: clip.kind.systemImage).font(.caption2).foregroundStyle(tint)
                    Text(clip.name)
                        .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                        .lineLimit(1)
                    Spacer()
                    if clip.kind.isPlayable {
                        Image(systemName: "play.fill").font(.caption2).foregroundStyle(tint.opacity(0.8))
                    }
                }
                Text(contentSummary(clip))
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 88)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(tint.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(tint.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { launch(clip) } label: { Label("Launch", systemImage: "play.fill") }
            Button { capture(into: index) } label: { Label("Re-capture current", systemImage: "arrow.clockwise") }
            Button { beginRename(index, clip) } label: { Label("Rename", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { clips.clear(at: index) } label: { Label("Clear", systemImage: "trash") }
        }
        .accessibilityLabel("Clip \(clip.name). \(contentSummary(clip))")
        .accessibilityHint("Launches this clip into the transport")
    }

    private func contentSummary(_ clip: Clip) -> String {
        switch clip.kind {
        case .midi:
            var parts: [String] = []
            if let d = clip.drums, d.steps.flatMap({ $0 }).contains(true) {
                let hits = d.steps.flatMap { $0 }.filter { $0 }.count
                parts.append("\(hits) drum hits")
            }
            if let m = clip.melody, !m.notes.isEmpty {
                parts.append("\(m.notes.count) notes")
            }
            return parts.isEmpty ? "MIDI · empty" : "MIDI · " + parts.joined(separator: " · ")
        case .audio, .video, .visual:
            if let ref = clip.mediaRef, !ref.isEmpty {
                let name = ref.split(separator: "/").last.map(String.init) ?? ref
                return "\(clip.kind.displayName) · \(name)"
            }
            // Honest: these lanes are typed scaffolding until their engine ships.
            return "\(clip.kind.displayName) · engine coming"
        }
    }

    // MARK: - Capture / launch

    /// Snapshot the live beat + melody into a slot.
    private func capture(into index: Int) {
        let drums = DrumPattern(steps: beatPlayer.pattern.steps, accents: beatPlayer.pattern.accents)
        let melody = MelodyClip(notes: pianoRoll.notes)
        let existing = clips.slots[index]
        let clip = Clip(
            name: existing?.name ?? "Clip \(index + 1)",
            colorIndex: existing?.colorIndex ?? (index % Self.palette.count),
            drums: drums,
            melody: melody,
            automation: existing?.automation ?? []   // re-capture keeps authored clip lanes (cycle 4)
        )
        clips.setClip(at: index, clip)
    }

    /// Load a clip into the live transport. Immediate (no bar-quantize) for v1.
    private func launch(_ clip: Clip) {
        if let d = clip.drums {
            beatPlayer.pattern.load(steps: d.steps, accents: d.accents)
        }
        if let m = clip.melody {
            pianoRoll.load(m.notes)
        }
        // Clip automation travels + plays with the clip (cycle 4); installed even
        // when the clip has no melody, and [] clears a previous clip's lanes.
        pianoRoll.setClipAutomation(clip.automation)
    }

    // MARK: - Rename

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func beginRename(_ index: Int, _ clip: Clip) {
        renameText = clip.name
        renaming = index
    }

    private func commitRename() {
        guard let index = renaming else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { clips.rename(at: index, to: trimmed) }
        renaming = nil
    }
}
#endif
