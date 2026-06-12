#if canImport(SwiftUI)
import SwiftUI
import Foundation

// ArrangementView.swift
// Echoel — the linear song timeline (the "Arrange" half of the Clips tab). Where
// the Session grid is a palette of launchable clips, the Arrangement chains them
// over song time: a horizontal track of sections, each a Session clip held for N
// bars. Play it and ArrangementPlayer loads each section's clip into the live
// transport at every bar boundary. Tap a section to edit it (clip / length /
// order); "Edit clip" jumps its content into the Tools editor (piano roll + grid).

@MainActor
struct ArrangementView: View {

    @Environment(ArrangementStore.self) private var store
    @Environment(ArrangementPlayer.self) private var player
    @Environment(ClipStore.self) private var clips
    @Environment(BeatPlayer.self) private var beatPlayer
    @Environment(PianoRollModel.self) private var pianoRoll

    @State private var selectedID: UUID?
    @State private var renameTarget: UUID?
    @State private var renameText = ""

    /// Points of timeline width per bar (keeps a 1-bar block tappable).
    private let pointsPerBar: CGFloat = 26
    private let minBlockWidth: CGFloat = 64
    private let blockHeight: CGFloat = 76

    private let palette: [Color] = [
        Color(red: 0.30, green: 0.55, blue: 0.50),
        Color(red: 0.45, green: 0.45, blue: 0.60),
        Color(red: 0.55, green: 0.45, blue: 0.35),
        Color(red: 0.40, green: 0.50, blue: 0.40),
        Color(red: 0.50, green: 0.40, blue: 0.50),
        Color(red: 0.35, green: 0.50, blue: 0.55),
        Color(red: 0.55, green: 0.50, blue: 0.40),
        Color(red: 0.45, green: 0.40, blue: 0.45)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header.padding(16)
            Divider().overlay(EchoelTheme.border)
            timeline
            if let section = selectedSection {
                Divider().overlay(EchoelTheme.border)
                inspector(for: section)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EchoelTheme.bg)
        .alert("Rename section", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let id = renameTarget { store.rename(id: id, to: renameText.isEmpty ? "Section" : renameText) }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
    }

    private var selectedSection: ArrangementSection? {
        guard let id = selectedID else { return nil }
        return store.sections.first { $0.id == id }
    }

    // MARK: - Header / transport

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                if player.isPlaying {
                    player.stop()
                } else {
                    player.play(store: store, clips: clips, pattern: beatPlayer.pattern, pianoRoll: pianoRoll)
                }
            } label: {
                Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 36)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(player.isPlaying ? EchoelTheme.danger : EchoelTheme.accent))
            }
            .buttonStyle(.plain)
            .disabled(store.isEmpty)

            Text("Song")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EchoelTheme.text)
            Text("\(store.totalBars) bars")
                .font(.caption2)
                .foregroundStyle(EchoelTheme.dim)

            Spacer(minLength: 0)

            Button { player.loopEnabled.toggle() } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(player.loopEnabled ? EchoelTheme.accent : EchoelTheme.dim)
                    .frame(width: 36, height: 32)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            }
            .buttonStyle(.plain)

            Button { addSection() } label: {
                Label("Add", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timeline: some View {
        if store.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.3.group").font(.system(size: 26)).foregroundStyle(EchoelTheme.dim)
                Text("Build a song: add sections, assign a clip to each.")
                    .font(.system(size: 12)).foregroundStyle(EchoelTheme.dim)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 36)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 6) {
                    ForEach(Array(store.sections.enumerated()), id: \.element.id) { index, section in
                        block(index, section)
                    }
                }
                .padding(16)
            }
        }
    }

    private func block(_ index: Int, _ section: ArrangementSection) -> some View {
        let color = palette[section.colorIndex % palette.count]
        let isPlayhead = player.isPlaying && player.currentIndex == index
        let isSelected = selectedID == section.id
        let width = max(minBlockWidth, CGFloat(section.lengthBars) * pointsPerBar)
        let clipName = section.clipID.flatMap { id in clips.clip(id: id)?.name }

        return Button {
            selectedID = isSelected ? nil : section.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(section.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoelTheme.text).lineLimit(1)
                Text(clipName ?? "— gap —")
                    .font(.system(size: 10))
                    .foregroundStyle(clipName == nil ? EchoelTheme.dim : EchoelTheme.text.opacity(0.8))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(section.lengthBars) bar\(section.lengthBars == 1 ? "" : "s")")
                    .font(.system(size: 9)).foregroundStyle(EchoelTheme.dim)
            }
            .padding(10)
            .frame(width: width, height: blockHeight, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(color.opacity(isPlayhead ? 0.55 : 0.30)))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(isSelected ? EchoelTheme.accent : color, lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inspector

    private func inspector(for section: ArrangementSection) -> some View {
        let index = store.sections.firstIndex(where: { $0.id == section.id }) ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(section.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(EchoelTheme.text)
                Spacer()
                Button { renameText = section.name; renameTarget = section.id } label: {
                    Image(systemName: "pencil").foregroundStyle(EchoelTheme.dim)
                }.buttonStyle(.plain)
            }

            // Clip assignment
            HStack {
                Text("Clip").font(.system(size: 12)).foregroundStyle(EchoelTheme.dim)
                Spacer()
                Menu {
                    Button("— gap (silence) —") { store.setClip(id: section.id, clipID: nil) }
                    ForEach(clips.filledClips) { clip in
                        Button(clip.name) {
                            store.setClip(id: section.id, clipID: clip.id, name: clip.name, colorIndex: clip.colorIndex)
                        }
                    }
                } label: {
                    let name = section.clipID.flatMap { clips.clip(id: $0)?.name } ?? "gap"
                    Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(EchoelTheme.accent)
                }
            }

            // Length
            HStack {
                Text("Length").font(.system(size: 12)).foregroundStyle(EchoelTheme.dim)
                Spacer()
                Stepper("\(section.lengthBars) bar\(section.lengthBars == 1 ? "" : "s")",
                        value: Binding(
                            get: { section.lengthBars },
                            set: { store.setLength(id: section.id, bars: $0) }
                        ), in: 1...32)
                    .font(.system(size: 12)).foregroundStyle(EchoelTheme.text).fixedSize()
            }

            // Order + edit + delete
            HStack(spacing: 10) {
                iconButton("chevron.left") { store.move(at: index, by: -1) }
                    .disabled(index == 0)
                iconButton("chevron.right") { store.move(at: index, by: 1) }
                    .disabled(index >= store.sections.count - 1)
                Button { editClip(section) } label: {
                    Label("Edit clip", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(EchoelTheme.text)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                }
                .buttonStyle(.plain)
                .disabled(section.clipID == nil)
                Spacer()
                Button(role: .destructive) {
                    store.remove(id: section.id); selectedID = nil
                } label: {
                    Image(systemName: "trash").foregroundStyle(EchoelTheme.danger)
                }.buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private func iconButton(_ system: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(EchoelTheme.text)
                .frame(width: 36, height: 32)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        }.buttonStyle(.plain)
    }

    // MARK: - Actions

    private func addSection() {
        let n = store.sections.count
        // Default the new section to the first available clip, if any.
        let first = clips.filledClips.first
        store.addSection(
            clipID: first?.id,
            name: first?.name ?? "Section \(n + 1)",
            colorIndex: first?.colorIndex ?? (n % palette.count),
            lengthBars: 1
        )
    }

    /// Load the section's clip into the live transport so the Tools tab edits it.
    private func editClip(_ section: ArrangementSection) {
        guard let id = section.clipID, let clip = clips.clip(id: id) else { return }
        if let d = clip.drums { beatPlayer.pattern.load(steps: d.steps, accents: d.accents) }
        pianoRoll.load(clip.melody?.notes ?? [])
    }
}
#endif
