#if canImport(SwiftUI)
import SwiftUI

// EchoelStudioView.swift
// Echoel — the whole app in ONE window: biofeedback → loop → .wav.
// Generate from the body, set Tonart / BPM / sound character, design the sound,
// shape the effects, save/open projects, and export a .wav to send. No tabs, no
// detours — the single screen does everything.

@MainActor
struct EchoelStudioView: View {

    @Environment(EngineBus.self) private var bus
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(BeatPlayer.self) private var beatPlayer
    @Environment(PianoRollModel.self) private var pianoRoll
    @Environment(PolySynthVoice.self) private var synth
    @Environment(SessionContext.self) private var session
    @Environment(LoopExporter.self) private var exporter
    @Environment(ProjectStore.self) private var projects

    @State private var style: MusicStyle = .dubTechno
    @State private var rootIndex = 0
    @State private var scale: Scale = .dorian
    @State private var mode: ComposerMode = .studioLocked
    @State private var lockedBPM: Double = 124
    @State private var fxCharacter: FXCharacter = .auto
    @State private var loopBars: LoopBarLength = .four
    @State private var currentPatch = SynthPatch(name: "Init")
    @State private var lastNoteCount: Int?

    // Sheets / dialogs
    @State private var showSoundDesign = false
    @State private var showOpen = false
    @State private var showSaveDialog = false
    @State private var saveName = ""
    @State private var share: ExportedFile?

    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private var key: MusicalKey { MusicalKey(root: rootIndex, scale: scale) }

    var body: some View {
        VStack(spacing: 0) {
            BioStripView()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    generateSection
                    soundSection
                    effectsSection
                    exportSection
                    projectSection
                }
                .padding(16)
            }
        }
        .background(EchoelTheme.bg)
        .onChange(of: style) { _, s in applyStyle(s) }
        .sheet(isPresented: $showSoundDesign) {
            PatchEditorView(initial: currentPatch) { currentPatch = $0 }
        }
        .sheet(isPresented: $showOpen) { openSheet }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .alert("Save project", isPresented: $showSaveDialog) {
            TextField("Name", text: $saveName)
            Button("Save") { saveProject() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current sound, key, tempo and generated loop.")
        }
    }

    // MARK: - Generate

    private var generateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { generate() } label: {
                Label(lastNoteCount == nil ? "Generate from Body" : "Regenerate",
                      systemImage: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.accent))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Writes an in-key loop from your live biodata and plays it")

            HStack(spacing: 14) {
                let frame = bus.latestBio
                stat("HR", frame.map { "\(Int($0.heartRateBPM))" } ?? "—")
                stat("HRV", frame.map { String(format: "%.2f", $0.hrvNormalized) } ?? "—")
                stat("Coh", frame.map { String(format: "%.2f", $0.coherence) } ?? "—")
                if let n = lastNoteCount {
                    Spacer(minLength: 0)
                    Text("\(n) notes · \(key.name)").font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)
                }
            }
        }
    }

    // MARK: - Sound (genre · key · BPM)

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Sound")
            Picker("Genre", selection: $style) {
                ForEach(MusicStyle.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu).tint(EchoelTheme.accent)
            Text(style.lineage).font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)

            HStack(spacing: 10) {
                Picker("Root", selection: $rootIndex) {
                    ForEach(0..<12, id: \.self) { Text(noteNames[$0]).tag($0) }
                }
                .pickerStyle(.menu).tint(EchoelTheme.accent).accessibilityLabel("Root note")
                Picker("Scale", selection: $scale) {
                    ForEach(Scale.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu).tint(EchoelTheme.accent).accessibilityLabel("Scale")
                Spacer(minLength: 0)
            }

            Picker("Tempo mode", selection: $mode) {
                Text("Studio").tag(ComposerMode.studioLocked)
                Text("Flow").tag(ComposerMode.flowFree)
            }
            .pickerStyle(.segmented)
            if mode == .studioLocked {
                Stepper(value: $lockedBPM, in: style.tempoRange, step: 0.5) {
                    Text("\(String(format: "%.2f", lockedBPM)) BPM · A\(SessionNaming.trimmed(session.a4Hz))")
                        .font(.system(size: 12)).foregroundStyle(EchoelTheme.text)
                }
            }
        }
    }

    // MARK: - Effects (character + sound design)

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Sound character & EFx")
            Picker("Effect", selection: $fxCharacter) {
                ForEach(FXCharacter.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu).tint(EchoelTheme.accent)
            .onChange(of: fxCharacter) { _, _ in
                fxCharacter.apply(to: synth.fxChain, bpm: beatPlayer.pattern.tempo, genre: style)
            }
            Text(fxCharacter.blurb).font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)

            Button { showSoundDesign = true } label: {
                Label("Sound design", systemImage: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loop + export

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Loop → .wav")
            HStack(spacing: 10) {
                Picker("Loop", selection: $loopBars) {
                    ForEach(LoopBarLength.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu).tint(EchoelTheme.accent).accessibilityLabel("Loop length")

                Button { togglePlay() } label: {
                    Image(systemName: beatPlayer.pattern.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 16)).foregroundStyle(EchoelTheme.text)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(beatPlayer.pattern.isPlaying ? "Stop" : "Play")
                Spacer(minLength: 0)
            }

            Button { Task { await exportWav() } } label: {
                Label(exportLabel, systemImage: exportIcon)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(isExporting ? EchoelTheme.dim : EchoelTheme.accent))
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
            .accessibilityHint("Records one loop and exports a WAV to share")
        }
    }

    private var isExporting: Bool {
        exporter.status == .capturing || exporter.status == .rendering
    }
    private var exportLabel: String {
        switch exporter.status {
        case .capturing: return "Capturing loop…"
        case .rendering: return "Writing .wav…"
        default:         return "Export .wav & send"
        }
    }
    private var exportIcon: String { isExporting ? "hourglass" : "square.and.arrow.up" }

    // MARK: - Projects

    private var projectSection: some View {
        HStack(spacing: 10) {
            Button { saveName = session.sessionName(bpm: beatPlayer.pattern.tempo); showSaveDialog = true } label: {
                Label("Save", systemImage: "tray.and.arrow.down")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            }
            .buttonStyle(.plain)
            Button { showOpen = true } label: {
                Label("Open", systemImage: "tray.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            }
            .buttonStyle(.plain)
            .disabled(projects.projects.isEmpty)
        }
    }

    private var openSheet: some View {
        NavigationStack {
            List {
                if projects.projects.isEmpty {
                    Text("No saved projects yet.").foregroundStyle(.secondary)
                }
                ForEach(projects.projects) { p in
                    Button { open(p); showOpen = false } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.callout.weight(.medium)).foregroundStyle(EchoelTheme.text)
                            Text("\(p.style.displayName) · \(p.key.shortName) · \(String(format: "%.0f", p.bpm)) BPM")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in idx.map { projects.projects[$0].id }.forEach { projects.delete(id: $0) } }
            }
            .navigationTitle("Open project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Actions

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(EchoelTheme.text)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(EchoelTheme.dim)
            Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(EchoelTheme.text)
        }
    }

    private func applyStyle(_ s: MusicStyle) {
        scale = s.scale
        mode = s.defaultMode
        lockedBPM = s.defaultTempo
    }

    private func togglePlay() {
        if beatPlayer.pattern.isPlaying { beatPlayer.pattern.stop() } else { beatPlayer.pattern.play() }
    }

    private func generate() {
        let frame = bus.latestBio
        let input = BioComposer.Input(
            heartRateBPM: frame?.heartRateBPM ?? 70,
            hrvNormalized: frame?.hrvNormalized ?? 0.5,
            coherence: frame?.coherence ?? 0.5,
            breathPhase: frame?.breathPhase ?? 0,
            breathDepth: 0.5,
            key: key,
            style: style,
            mode: mode,
            lockedTempo: lockedBPM,
            seed: UInt64.random(in: UInt64.min...UInt64.max)
        )
        let composition = BioComposer.compose(input)
        currentPatch = style.synthPatch
        synth.apply(currentPatch)
        fxCharacter.apply(to: synth.fxChain, bpm: composition.suggestedTempo, genre: style)
        pianoRoll.load(composition.notes)
        beatPlayer.pattern.load(steps: composition.drumSteps, accents: composition.drumAccents)
        beatPlayer.pattern.setTempo(composition.suggestedTempo)
        session.adopt(key: key)
        lastNoteCount = composition.notes.count
        if !beatPlayer.pattern.isPlaying { beatPlayer.pattern.play() }
    }

    private func exportWav() async {
        if let url = await exporter.exportWav(engine: audioEngine, beatPlayer: beatPlayer, bars: loopBars.rawValue) {
            share = ExportedFile(url: url)
        }
    }

    private func saveProject() {
        let name = saveName.isEmpty ? session.sessionName(bpm: beatPlayer.pattern.tempo) : saveName
        let project = Project(
            name: name,
            styleRaw: style.rawValue, keyRoot: rootIndex, scaleRaw: scale.rawValue,
            bpm: beatPlayer.pattern.tempo, modeRaw: mode.rawValue,
            fxCharacterRaw: fxCharacter.rawValue, loopBars: loopBars.rawValue,
            a4Hz: session.a4Hz, artist: session.artistName,
            patch: currentPatch, notes: pianoRoll.notes,
            drumSteps: beatPlayer.pattern.steps, drumAccents: beatPlayer.pattern.accents
        )
        projects.save(project)
    }

    private func open(_ p: Project) {
        style = p.style
        rootIndex = p.keyRoot
        scale = p.scale
        mode = p.mode
        lockedBPM = p.bpm
        fxCharacter = p.fxCharacter
        loopBars = LoopBarLength(rawValue: p.loopBars) ?? .four
        currentPatch = p.patch
        session.adopt(key: p.key)
        synth.apply(p.patch)
        fxCharacter.apply(to: synth.fxChain, bpm: p.bpm, genre: p.style)
        pianoRoll.load(p.notes)
        beatPlayer.pattern.load(steps: p.drumSteps, accents: p.drumAccents)
        beatPlayer.pattern.setTempo(p.bpm)
        lastNoteCount = p.notes.count
    }
}

/// Identifiable wrapper so the share sheet can present an exported file URL.
private struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}
#endif
