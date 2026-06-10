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
    @Environment(EngineBus.self) private var bus
    @Environment(PolySynthVoice.self) private var polyVoice

    /// Melodic piano-roll lane (drives the DDSP synth on the shared clock).
    @State private var pianoRoll = PianoRollModel()
    @State private var showPianoRoll = false

    /// Holds the exported .mid file URL while the iOS share sheet is presented.
    @State private var exportedMIDI: ExportedMIDIFile?

    /// Drives the per-pad sample importer (Files browser).
    @State private var importerPresented = false
    @State private var importTrack = 0

    /// Drives the per-pad sound (envelope) editor sheet.
    @State private var padEdit: PadEditTarget?

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
            hintRow
                .padding(.horizontal, 16)
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
        .sheet(item: $padEdit) { target in
            PadSoundEditor(track: target.id, player: beatPlayer)
        }
        .sheet(isPresented: $showPianoRoll) {
            PianoRollView(pattern: beatPlayer.pattern, voice: polyVoice, model: pianoRoll)
        }
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
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                toolButton("Randomize", icon: "dice.fill") { randomize(player: player) }
                toolButton("Shift", icon: "arrow.right.to.line") { shiftRight(player: player) }
                toolButton("Piano", icon: "pianokeys") { showPianoRoll = true }
                Spacer(minLength: 0)
            }
            // Swing on its own full-width row so the slider is always visible
            // (it was being clipped off-screen when crammed next to the buttons).
            HStack(spacing: 8) {
                Text("Swing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EchoelTheme.dim)
                    .frame(width: 44, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { player.pattern.swing },
                        set: { player.pattern.setSwing($0) }
                    ),
                    in: 0...0.5
                )
                .tint(EchoelTheme.accent)
                Text("\(Int(player.pattern.swing * 200))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    /// Discoverability hint — the accent (double-tap) and sample-load
    /// (long-press) affordances are otherwise invisible.
    private var hintRow: some View {
        Text("Tap a step: off → on → accent  ·  Long-press a pad to load a sample")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(EchoelTheme.dim)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
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
                let on = Double.random(in: 0...1) < probability
                player.pattern.setStep(track: t, step: s, on: on)
                // Accent downbeats sometimes for groove; clear accents on off cells.
                player.pattern.setAccent(track: t, step: s, on: on && onBeat && Double.random(in: 0...1) < 0.5)
            }
        }
    }

    /// Rotate every track one step to the right (wraps around), steps + accents.
    private func shiftRight(player: BeatPlayer) {
        let old = player.pattern.steps
        let oldAccents = player.pattern.accents
        let n = PatternEngine.stepCount
        guard n > 0 else { return }
        for t in 0..<PatternEngine.trackCount where t < old.count {
            for s in 0..<n {
                player.pattern.setStep(track: t, step: s, on: old[t][(s - 1 + n) % n])
                player.pattern.setAccent(track: t, step: s, on: oldAccents[t][(s - 1 + n) % n])
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
        let isAccent = isOn && player.pattern.accents[track][step]
        let isCurrent = player.pattern.isPlaying && player.pattern.currentStep == step
        Button {
            cycleCell(track: track, step: step, player: player)
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(cellFill(isOn: isOn, isAccent: isAccent, isCurrent: isCurrent))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isCurrent ? EchoelTheme.accent.opacity(0.7) : EchoelTheme.border, lineWidth: 1)
                )
                // A bright bar marks an accented (louder) hit — clearly
                // distinct from a normal on-step at a glance.
                .overlay(alignment: .top) {
                    if isAccent {
                        Capsule().fill(Color.white)
                            .frame(width: 16, height: 3).padding(.top, 3)
                    }
                }
                .frame(height: m.stepCellHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Track \(BeatPlayer.trackNames[track]) step \(step + 1)")
        .accessibilityValue(isAccent ? "accent" : (isOn ? "on" : "off"))
    }

    /// Tap cycles a cell: off → on → accent → off. Keeps the grid editable with
    /// a single gesture while exposing velocity (accent = louder hit).
    private func cycleCell(track: Int, step: Int, player: BeatPlayer) {
        let on = player.pattern.steps[track][step]
        let accent = player.pattern.accents[track][step]
        if !on {
            player.pattern.setStep(track: track, step: step, on: true)
            player.pattern.setAccent(track: track, step: step, on: false)
        } else if !accent {
            player.pattern.setAccent(track: track, step: step, on: true)
        } else {
            player.pattern.setStep(track: track, step: step, on: false)
            player.pattern.setAccent(track: track, step: step, on: false)
        }
    }

    private func cellFill(isOn: Bool, isAccent: Bool, isCurrent: Bool) -> Color {
        if isAccent { return isCurrent ? .white : EchoelTheme.accent }
        switch (isOn, isCurrent) {
        case (true, true):   return EchoelTheme.accent
        case (true, false):  return EchoelTheme.accent.opacity(0.55)
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
            Button { beatPlayer.preview(track) } label: {
                Label("Preview", systemImage: "play.circle")
            }
            Button {
                importTrack = track
                importerPresented = true
            } label: {
                Label("Load sample…", systemImage: "folder")
            }
            Button { padEdit = PadEditTarget(id: track) } label: {
                Label("Edit sound…", systemImage: "slider.horizontal.3")
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

/// Identifiable wrapper (the track index) to drive the sound-editor `.sheet(item:)`.
private struct PadEditTarget: Identifiable { let id: Int }

/// Per-pad sound (amp-envelope) editor: Level / Attack / Length + live Preview.
/// Edits apply live and persist (BeatPlayer.setShape). Full user control over
/// each pad's sound shaping — the sampler-instrument step toward the DAW.
@MainActor
private struct PadSoundEditor: View {
    let track: Int
    let player: BeatPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var shape: BeatPlayer.PadShape

    init(track: Int, player: BeatPlayer) {
        self.track = track
        self.player = player
        _shape = State(initialValue: player.shapes.indices.contains(track) ? player.shapes[track] : .init())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        player.preview(track)
                    } label: {
                        Label("Preview", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(EchoelTheme.accent)
                    .listRowBackground(Color.clear)
                }

                Section("Level") {
                    slider($shape.level, range: 0...2, display: String(format: "%.2f×", shape.level))
                }
                Section("Attack") {
                    slider($shape.attackMs, range: 0...200, display: "\(Int(shape.attackMs)) ms")
                }
                Section {
                    slider($shape.lengthMs, range: 0...2000,
                           display: shape.lengthMs <= 0 ? "full" : "\(Int(shape.lengthMs)) ms")
                } header: {
                    Text("Length")
                } footer: {
                    Text("0 = play the full sample. Higher = tighten the hit (with an anti-click release).")
                }
            }
            .navigationTitle(label)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        shape = .init()
                        player.setShape(track: track, shape)
                    }
                }
            }
            .onChange(of: shape) { _, newValue in
                player.setShape(track: track, newValue)
            }
        }
    }

    private var label: String {
        let name = player.sampleLabels.indices.contains(track) ? player.sampleLabels[track] : "Pad"
        return "\(BeatPlayer.trackNames[track]) · \(name)"
    }

    @ViewBuilder
    private func slider(_ value: Binding<Float>, range: ClosedRange<Float>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer()
                Text(display)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .tint(EchoelTheme.accent)
        }
    }
}
#endif
