// BeatTab.swift
// Echoel — Beat tab UI: 16-step × 8-track grid + tempo + transport + pads.
//
// All audio lives in the BeatPlayer (injected via .environment). This view
// is purely a control surface — no engine state, no audio thread, no FX.
//
// UI rules per CLAUDE.md:
// - Solid fills only (no glassmorphism, no glow, no neon)
// - Corner radius ≤ 8 pt
// - No transform/scale on tap — opacity/fill only
// - Step-cell flash on currentStep is a fill change, not an animation loop

#if canImport(SwiftUI)
import SwiftUI
import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

@MainActor
struct BeatTab: View {

    @Environment(BeatPlayer.self) private var beatPlayer

    /// Holds the exported .mid file URL while the iOS share sheet is presented.
    @State private var exportedMIDI: ExportedMIDIFile?

    /// Drives the per-pad sample importer (Files browser).
    @State private var importerPresented = false
    @State private var importTrack = 0

    /// Size-class-adaptive metrics (iPhone compact ↔ iPad regular) so the grid,
    /// pads and controls scale and stay visible on every device.
    @Environment(\.horizontalSizeClass) private var hSize
    private var m: EchoelTheme.Metrics { .of(hSize) }

    private let columnsPerGroup = 4
    private let groupCount = 4

    var body: some View {
        // Cycle 3 restoration: full BeatTab UI — transport + step grid + pads.
        // Pads trigger \`beatPlayer.playPad(track)\` which fires the matching
        // SamplerVoice (lock-free trigger counter on the audio thread).
        VStack(spacing: m.bodySpacing) {
            transportRow(player: beatPlayer)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            patternToolsRow(player: beatPlayer)
                .padding(.horizontal, 16)
            stepGrid(player: beatPlayer)
                .padding(.horizontal, 12)
            padRow
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EchoelTheme.bg)
        #if canImport(UIKit)
        .sheet(item: $exportedMIDI) { file in
            ShareSheet(url: file.url)
        }
        #endif
        #if canImport(UniformTypeIdentifiers)
        .fileImporter(
            isPresented: $importerPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                beatPlayer.importSample(track: importTrack, from: url)
            }
        }
        #endif
    }

    // MARK: - Transport

    @ViewBuilder
    private func transportRow(player: BeatPlayer) -> some View {
        HStack(spacing: 12) {
            Button {
                if player.pattern.isPlaying {
                    player.pattern.stop()
                } else {
                    player.pattern.play()
                }
            } label: {
                Image(systemName: player.pattern.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: m.controlSize, height: m.controlSize)
                    .foregroundStyle(EchoelTheme.bg)
                    .background(
                        RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .fill(player.pattern.isPlaying ? EchoelTheme.danger : EchoelTheme.accent)
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Tempo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { player.pattern.tempo },
                            set: { player.pattern.setTempo($0) }
                        ),
                        in: PatternEngine.minTempo...PatternEngine.maxTempo
                    )
                    Text("\(Int(player.pattern.tempo)) BPM")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(EchoelTheme.text)
                        .frame(width: 80, alignment: .trailing)
                }
            }

            Button {
                player.pattern.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .frame(width: m.controlSize, height: m.controlSize)
                    .foregroundStyle(EchoelTheme.text)
                    .background(
                        RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .fill(EchoelTheme.fill)
                    )
            }
            .buttonStyle(.plain)

            // Export the current pattern as a Standard MIDI File (.mid) and open
            // the iOS share sheet — "take your beat to any DAW". Pure data path
            // (no audio engine, no permission): grid + tempo → MIDIFileExporter.
            Button {
                exportMIDI(player: player)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16))
                    .frame(width: m.controlSize, height: m.controlSize)
                    .foregroundStyle(EchoelTheme.text)
                    .background(
                        RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .fill(EchoelTheme.fill)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Export pattern as MIDI file")
        }
    }

    // MARK: - MIDI export

    private func exportMIDI(player: BeatPlayer) {
        let data = MIDIFileExporter.export(steps: player.pattern.steps, tempo: player.pattern.tempo)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EchoelBeat.mid")
        do {
            try data.write(to: url, options: .atomic)
            exportedMIDI = ExportedMIDIFile(url: url)
        } catch {
            log.log(.warning, category: .system, "MIDI export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pattern tools

    @ViewBuilder
    private func patternToolsRow(player: BeatPlayer) -> some View {
        HStack(spacing: 8) {
            toolButton("Randomize", icon: "dice.fill") { randomize(player: player) }
            toolButton("Shift", icon: "arrow.right.to.line") { shiftRight(player: player) }
            Spacer(minLength: 0)
        }
    }

    private func toolButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EchoelTheme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(EchoelTheme.fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    /// Fill the grid with a musical-ish random pattern (denser on quarter beats).
    private func randomize(player: BeatPlayer) {
        for t in 0..<PatternEngine.trackCount {
            for s in 0..<PatternEngine.stepCount {
                let onBeat = (s % 4 == 0)
                let probability = onBeat ? 0.55 : 0.22
                player.pattern.setStep(track: t, step: s, on: Double.random(in: 0...1) < probability)
            }
        }
    }

    /// Rotate every track one step to the right (wraps around).
    private func shiftRight(player: BeatPlayer) {
        let old = player.pattern.steps
        let n = PatternEngine.stepCount
        guard n > 0 else { return }
        for t in 0..<PatternEngine.trackCount where t < old.count {
            for s in 0..<n {
                player.pattern.setStep(track: t, step: s, on: old[t][(s - 1 + n) % n])
            }
        }
    }

    // MARK: - Step grid

    @ViewBuilder
    private func stepGrid(player: BeatPlayer) -> some View {
        VStack(spacing: 4) {
            ForEach(0..<PatternEngine.trackCount, id: \.self) { track in
                trackRow(track: track, player: player)
            }
        }
    }

    @ViewBuilder
    private func trackRow(track: Int, player: BeatPlayer) -> some View {
        HStack(spacing: 4) {
            Text(BeatPlayer.trackNames[track].prefix(4))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(EchoelTheme.dim)
                .frame(width: m.trackLabelWidth, alignment: .leading)

            ForEach(0..<groupCount, id: \.self) { group in
                HStack(spacing: 3) {
                    ForEach(0..<columnsPerGroup, id: \.self) { col in
                        let step = group * columnsPerGroup + col
                        stepCell(track: track, step: step, player: player)
                    }
                }
                if group < groupCount - 1 {
                    Spacer().frame(width: 6)
                }
            }
        }
    }

    @ViewBuilder
    private func stepCell(track: Int, step: Int, player: BeatPlayer) -> some View {
        let isOn = player.pattern.steps[track][step]
        let isCurrent = player.pattern.isPlaying && player.pattern.currentStep == step
        Button {
            player.pattern.toggleStep(track: track, step: step)
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(cellFill(isOn: isOn, isCurrent: isCurrent))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isCurrent ? EchoelTheme.accent.opacity(0.7) : EchoelTheme.border, lineWidth: 1)
                )
                .frame(height: m.stepCellHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Track \(BeatPlayer.trackNames[track]) step \(step + 1)")
        .accessibilityValue(isOn ? "on" : "off")
    }

    private func cellFill(isOn: Bool, isCurrent: Bool) -> Color {
        switch (isOn, isCurrent) {
        case (true, true):   return EchoelTheme.accent
        case (true, false):  return EchoelTheme.accent.opacity(0.6)
        case (false, true):  return EchoelTheme.text.opacity(0.18)
        case (false, false): return EchoelTheme.fill
        }
    }

    // MARK: - Drum pads

    private var padRow: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: m.padColumns)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<PatternEngine.trackCount, id: \.self) { track in
                pad(track: track)
            }
        }
    }

    @ViewBuilder
    private func pad(track: Int) -> some View {
        let isCustom = beatPlayer.isCustom(track)
        Button {
            beatPlayer.playPad(track)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isCustom ? "waveform" : "circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(EchoelTheme.accent.opacity(0.7))
                Text(BeatPlayer.trackNames[track])
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if isCustom {
                    Text(beatPlayer.sampleLabels[track])
                        .font(.system(size: 8))
                        .foregroundStyle(EchoelTheme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: m.padHeight)
            .background(
                RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(EchoelTheme.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(isCustom ? EchoelTheme.accent.opacity(0.5) : EchoelTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                importTrack = track
                importerPresented = true
            } label: {
                Label("Load sample…", systemImage: "folder")
            }
            if isCustom {
                Button(role: .destructive) {
                    beatPlayer.resetSample(track: track)
                } label: {
                    Label("Reset to default", systemImage: "arrow.uturn.backward")
                }
            }
        }
        .accessibilityLabel("Pad \(BeatPlayer.trackNames[track])\(isCustom ? ", custom sample \(beatPlayer.sampleLabels[track])" : ""). Long press to load a sample.")
    }
}

/// Identifiable wrapper so the exported .mid URL can drive `.sheet(item:)`.
/// (Reuses the existing `ShareSheet(url:)` from MomentCaptureView.swift.)
private struct ExportedMIDIFile: Identifiable {
    let id = UUID()
    let url: URL
}
#endif
