#if canImport(SwiftUI)
import SwiftUI

// ArrangementView.swift
// Echoel — the linear SONG timeline. Where the Session grid (ClipView) is a
// palette of launchable clips, the Arrangement is an ORDERED chain of sections:
// each section references a Session clip and plays for N bars, then the song
// advances. Plays back over the one shared transport via ArrangementPlayer
// (rides PatternEngine; loads each section's clip on the bar boundary).
//
// Pure-data store (ArrangementStore) + pure cursor (ArrangementCursor) already
// exist + are tested; this view is the editor + transport on top of them.

@MainActor
struct ArrangementView: View {

    @Environment(ArrangementStore.self) private var store
    @Environment(ArrangementPlayer.self) private var player
    @Environment(ClipStore.self) private var clips
    @Environment(BeatPlayer.self) private var beatPlayer
    @Environment(PianoRollModel.self) private var pianoRoll
    /// The authoritative clock — read here for the live song-position playhead.
    @Environment(Transport.self) private var transport
    @Environment(\.dismiss) private var dismiss

    /// `true` when hosted as a foreground workspace surface (WorkspaceView): drop the
    /// sheet's NavigationStack + "Done", since the surface switcher owns the chrome.
    var embedded = false

    @State private var renaming: UUID?
    @State private var renameText = ""

    /// Muted section tints — accent-green is reserved for live bio signal.
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

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .navigationTitle("Arrangement")
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
            VStack(alignment: .leading, spacing: 12) {
                transportBar

                if store.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(store.sections.enumerated()), id: \.element.id) { index, section in
                        sectionRow(index, section)
                    }
                }

                Button { addSection() } label: {
                    Label("Add section", systemImage: "plus")
                        .font(EchoelTheme.font(13, .semibold))
                        .foregroundStyle(EchoelTheme.text)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .strokeBorder(EchoelTheme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)

                Text("Each section plays a Session clip for its bar length, then the song advances. Capture clips in Tools → Clips first.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(EchoelTheme.bg)
        .alert("Rename section", isPresented: renamingBinding) {
            TextField("Name", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    // MARK: - Transport

    private var transportBar: some View {
        HStack(spacing: 12) {
            Button { togglePlay() } label: {
                Label(player.isPlaying ? "Stop" : "Play song",
                      systemImage: player.isPlaying ? "stop.fill" : "play.fill")
                    .font(EchoelTheme.font(13, .semibold))
                    .foregroundStyle(EchoelTheme.onPrimary)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(player.isPlaying ? EchoelTheme.danger : EchoelTheme.text))
            }
            .buttonStyle(.plain)
            .disabled(store.isEmpty)
            .opacity(store.isEmpty ? 0.4 : 1)

            Button { player.loopEnabled.toggle() } label: {
                Image(systemName: player.loopEnabled ? "repeat" : "repeat.1")
                    .font(.system(size: 16))
                    .foregroundStyle(player.loopEnabled ? EchoelTheme.text : EchoelTheme.dim)
                    .frame(width: 36, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.loopEnabled ? "Looping on" : "Looping off")

            Spacer()

            // Live playhead, fed by the authoritative Transport (1-based bar·beat).
            // Monospaced digits so the readout doesn't jitter as it counts.
            if transport.isPlaying {
                Text(positionLabel)
                    .font(EchoelTheme.font(12, .semibold).monospacedDigit())
                    .foregroundStyle(EchoelTheme.text)
                    .accessibilityLabel("Position bar \(transport.position.bar + 1), beat \(transport.position.beat + 1)")
            }

            Text("\(store.totalBars) bars")
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
        }
    }

    /// 1-based "bar·beat" string from the Transport position.
    private var positionLabel: String {
        "\(transport.position.bar + 1)·\(transport.position.beat + 1)"
    }

    private var emptyState: some View {
        Text("No sections yet. Add one and point it at a clip.")
            .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    // MARK: - Section row

    private func sectionRow(_ index: Int, _ section: ArrangementSection) -> some View {
        let tint = Self.palette[section.colorIndex % Self.palette.count]
        let isPlaying = player.isPlaying && player.currentIndex == index
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isPlaying ? "play.fill" : "rectangle.fill")
                    .font(.system(size: 11)).foregroundStyle(tint)
                Text(section.name)
                    .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                    .lineLimit(1)
                Spacer()
                clipMenu(section)
            }

            HStack(spacing: 10) {
                EchoelValueField(
                    label: "Bars",
                    value: lengthBinding(section),
                    range: Float(1)...Float(64),
                    unit: "",
                    decimals: 0
                )
                Spacer(minLength: 0)
                Button { store.move(at: index, by: -1) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 13)).foregroundStyle(EchoelTheme.dim)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain).disabled(index == 0).accessibilityLabel("Move up")
                Button { store.move(at: index, by: 1) } label: {
                    Image(systemName: "arrow.down").font(.system(size: 13)).foregroundStyle(EchoelTheme.dim)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain).disabled(index == store.sections.count - 1).accessibilityLabel("Move down")
                Button { beginRename(section) } label: {
                    Image(systemName: "pencil").font(.system(size: 13)).foregroundStyle(EchoelTheme.dim)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain).accessibilityLabel("Rename section")
                Button(role: .destructive) { store.remove(at: index) } label: {
                    Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(EchoelTheme.danger)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain).accessibilityLabel("Delete section")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(tint.opacity(isPlaying ? 0.22 : 0.12)))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(tint.opacity(isPlaying ? 0.8 : 0.4), lineWidth: isPlaying ? 1.5 : 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Section \(section.name), \(section.lengthBars) bars\(isPlaying ? ", playing" : "")")
    }

    /// Pick which captured clip this section references (or a silent gap).
    private func clipMenu(_ section: ArrangementSection) -> some View {
        let filled = filledClips
        let currentName = section.clipID.flatMap { id in filled.first { $0.id == id }?.name } ?? "Silent gap"
        return Menu {
            Button { store.setClip(id: section.id, clipID: nil, name: "Gap") } label: {
                Label("Silent gap", systemImage: section.clipID == nil ? "checkmark" : "minus")
            }
            if filled.isEmpty {
                Text("No clips captured yet")
            } else {
                ForEach(filled) { clip in
                    Button {
                        store.setClip(id: section.id, clipID: clip.id, name: clip.name, colorIndex: clip.colorIndex)
                    } label: {
                        if section.clipID == clip.id { Label(clip.name, systemImage: "checkmark") }
                        else { Text(clip.name) }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentName).font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.text).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(EchoelTheme.dim)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .accessibilityLabel("Clip for this section: \(currentName)")
    }

    // MARK: - Helpers

    private var filledClips: [Clip] {
        clips.slots.compactMap { $0 }
    }

    private func lengthBinding(_ section: ArrangementSection) -> Binding<Float> {
        Binding(
            get: { Float(section.lengthBars) },
            set: { store.setLength(id: section.id, bars: Int($0.rounded())) }
        )
    }

    private func addSection() {
        let first = filledClips.first
        store.addSection(
            clipID: first?.id,
            name: first?.name ?? "Section \(store.sections.count + 1)",
            colorIndex: first?.colorIndex ?? (store.sections.count % Self.palette.count),
            lengthBars: 4
        )
    }

    private func togglePlay() {
        if player.isPlaying {
            player.stop()
        } else {
            player.play(store: store, clips: clips, pattern: beatPlayer.pattern, pianoRoll: pianoRoll)
        }
    }

    // MARK: - Rename

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func beginRename(_ section: ArrangementSection) {
        renameText = section.name
        renaming = section.id
    }

    private func commitRename() {
        guard let id = renaming else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { store.rename(id: id, to: trimmed) }
        renaming = nil
    }
}
#endif
