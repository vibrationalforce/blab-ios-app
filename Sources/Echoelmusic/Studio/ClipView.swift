#if canImport(SwiftUI)
import SwiftUI

// ClipView.swift
// Echoel — the session grid: capture the current drum pattern + melody into a
// launchable cell, then fire any cell to swap the live pattern (Ableton-session
// style). Drums load into PatternEngine, melody into the shared PianoRollModel
// (wired to the transport app-wide), so a launched clip plays immediately.

@MainActor
struct ClipView: View {

    @Environment(BeatPlayer.self) private var player
    @Environment(PianoRollModel.self) private var pianoRoll
    @Environment(ClipStore.self) private var store
    @Environment(LaunchQuantizer.self) private var quantizer

    @State private var renameTarget: Int?
    @State private var renameText = ""

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    /// Muted clip colors (no neon, per UI rules).
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
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(0..<ClipStore.slotCount, id: \.self) { i in cell(i) }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EchoelTheme.bg)
        .alert("Rename clip", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let i = renameTarget { store.rename(at: i, to: renameText.isEmpty ? "Clip" : renameText) }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
    }

    // MARK: - Header / transport

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                if player.pattern.isPlaying { player.pattern.stop(); pianoRoll.allNotesOff() }
                else { player.pattern.play() }
            } label: {
                Image(systemName: player.pattern.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 36)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(player.pattern.isPlaying ? EchoelTheme.danger : EchoelTheme.accent))
            }
            .buttonStyle(.plain)

            Text("Clips")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EchoelTheme.text)
            Spacer(minLength: 0)
            Button { quantizer.quantizeEnabled.toggle() } label: {
                Label("Quantize", systemImage: quantizer.quantizeEnabled ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(quantizer.quantizeEnabled ? EchoelTheme.accent : EchoelTheme.dim)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Cells

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        if let clip = store.slots[index] {
            filledCell(index, clip)
        } else {
            emptyCell(index)
        }
    }

    private func filledCell(_ index: Int, _ clip: Clip) -> some View {
        let color = palette[clip.colorIndex % palette.count]
        let isQueued = quantizer.pendingClipID == clip.id
        return Button {
            launch(clip)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: isQueued ? "clock.fill" : "play.fill").font(.system(size: 11))
                    Text(clip.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(isQueued ? EchoelTheme.accent : EchoelTheme.text)
                HStack(spacing: 8) {
                    if clip.drums != nil {
                        Label("Beat", systemImage: "square.grid.3x3.fill")
                    }
                    if let m = clip.melody, !m.notes.isEmpty {
                        Label("\(m.notes.count)", systemImage: "music.note")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(EchoelTheme.dim)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(color.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(isQueued ? EchoelTheme.accent : color, lineWidth: isQueued ? 2 : 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { launch(clip) } label: { Label("Launch", systemImage: "play") }
            Button { capture(index) } label: { Label("Recapture", systemImage: "arrow.clockwise") }
            Button { renameText = clip.name; renameTarget = index } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { store.clear(at: index) } label: { Label("Clear", systemImage: "trash") }
        }
    }

    private func emptyCell(_ index: Int) -> some View {
        Button {
            capture(index)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle").font(.system(size: 18))
                Text("Capture").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(EchoelTheme.dim)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(EchoelTheme.border, style: StrokeStyle(lineWidth: 1, dash: [4])))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Capture / launch

    private func capture(_ index: Int) {
        let drums = DrumPattern(steps: player.pattern.steps, accents: player.pattern.accents)
        let melody = MelodyClip(notes: pianoRoll.notes)
        let clip = Clip(
            name: "Clip \(index + 1)",
            colorIndex: index % palette.count,
            drums: drums,
            melody: melody
        )
        store.setClip(at: index, clip)
    }

    private func launch(_ clip: Clip) {
        // Bar-quantized while playing (queued until the next bar); immediate when
        // stopped. The quantizer owns the load + transport start.
        quantizer.request(clip, pattern: player.pattern, pianoRoll: pianoRoll)
    }
}
#endif
