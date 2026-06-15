#if canImport(SwiftUI)
import SwiftUI

// EchoelStudioView.swift
// Echoel — ONE button, then sliders.
//
// "Start — Create from Within" begins the biofeedback (camera pulse, or the demo
// source where no camera exists). From the live HRV / heart / breath an individual,
// seeded algorithm composes music that keeps evolving from the body while it runs.
// The remaining controls are sliders that shape the sound in real time. Export the
// loop to a .wav, save/open projects. No other buttons, no detours.

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
    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif

    // The single live-state flag: biofeedback running or not.
    @State private var running = false

    // Sound sliders — all normalized 0…1, so they can never index or scale out of range.
    @State private var soundBlend: Double = 0.0   // sweeps the genres
    @State private var brightness: Double = 0.5
    @State private var space: Double = 0.4
    @State private var movement: Double = 0.3

    // Derived / persisted musical state (no direct UI — set by sliders + bio).
    @State private var style: MusicStyle = .vaporwave
    @State private var rootIndex = 0
    @State private var scale: Scale = .minor
    @State private var fxCharacter: FXCharacter = .auto
    @State private var loopBars: LoopBarLength = .four
    @State private var currentPatch = SynthPatch(name: "Init")
    @State private var lastNoteCount: Int?

    // Background evolution + bio acquisition.
    @State private var evolveTask: Task<Void, Never>?
    @State private var startTask: Task<Void, Never>?

    // Sheets / dialogs
    @State private var showOpen = false
    @State private var showSaveDialog = false
    @State private var saveName = ""
    @State private var share: ExportedFile?
    @State private var diagnostics: DiagReport?

    private var key: MusicalKey { MusicalKey(root: rootIndex, scale: scale) }

    var body: some View {
        VStack(spacing: 0) {
            BioStripView()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    startButton
                    #if canImport(AVFoundation)
                    if running { measurementControl }
                    #endif
                    soundControls
                    utilityRow
                }
                .padding(16)
            }
        }
        .background(EchoelTheme.bg)
        .onAppear { surfacePriorCrashIfAny() }
        .onDisappear { stopEverything() }
        .sheet(isPresented: $showOpen) { openSheet }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .sheet(item: $diagnostics) { report in diagnosticsSheet(report.text) }
        .alert("Save project", isPresented: $showSaveDialog) {
            TextField("Name", text: $saveName)
            Button("Save") { saveProject() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current sound, key, tempo and generated loop.")
        }
    }

    // MARK: - The one button

    private var startButton: some View {
        Button { toggleBiofeedback() } label: {
            Label(running ? "Stop" : "Create from Within",
                  systemImage: running ? "stop.circle.fill" : "waveform.path.ecg")
                .font(EchoelTheme.font(17, .semibold))
                .foregroundStyle(running ? EchoelTheme.text : .black)
                .frame(maxWidth: .infinity).frame(height: 56)
                // Website CI: primary action = off-white fill, black label (.btn-primary).
                // Green is reserved for live bio signal, not chrome. Stop = neutral fill.
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(running ? EchoelTheme.fill : EchoelTheme.text))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Starts biofeedback; your body composes and plays music. Tap again to stop.")
    }

    // MARK: - Sound sliders (shape the music in real time)

    private var soundControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Shape the sound")

            slider("Sound", value: $soundBlend, caption: style.displayName) { _ in
                applySoundBlend()
            }
            slider("Brightness", value: $brightness) { _ in applySoundLive() }
            slider("Space", value: $space) { _ in applySoundLive() }
            slider("Movement", value: $movement) { _ in applySoundLive() }

            if running {
                Text("Music is arising from your live signal — move the sliders to shape it.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            }
        }
    }

    private func slider(_ label: String, value: Binding<Double>, caption: String? = nil,
                        onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
                Spacer(minLength: 0)
                if let caption {
                    Text(caption).font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                }
            }
            Slider(value: value, in: 0...1)
                .tint(EchoelTheme.accent)
                .onChange(of: value.wrappedValue) { _, v in onChange(v) }
                .accessibilityLabel(label)
        }
    }

    // MARK: - Utilities (export · projects)

    private var utilityRow: some View {
        VStack(spacing: 10) {
            loopLengthSelector
            Button { Task { await exportWav() } } label: {
                Label(exportLabel, systemImage: exportIcon)
                    .font(EchoelTheme.font(15, .semibold)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    // Website CI primary action (off-white fill, black label).
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(isExporting ? EchoelTheme.dim : EchoelTheme.text))
            }
            .buttonStyle(.plain)
            .disabled(isExporting || lastNoteCount == nil)
            .accessibilityHint("Records one loop and exports a WAV to share")

            HStack(spacing: 10) {
                Button { saveName = session.sessionName(bpm: beatPlayer.pattern.tempo); showSaveDialog = true } label: {
                    Label("Save", systemImage: "tray.and.arrow.down")
                        .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                }
                .buttonStyle(.plain)
                .disabled(lastNoteCount == nil)
                Button { showOpen = true } label: {
                    Label("Open", systemImage: "tray.and.arrow.up")
                        .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                }
                .buttonStyle(.plain)
                .disabled(projects.projects.isEmpty)
            }

            Button { diagnostics = DiagReport(text: EchoelCrashLog.currentLog()) } label: {
                Text("Diagnostics").font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the in-app diagnostic log to share if something crashed")
        }
    }

    // MARK: - Diagnostics

    /// On launch, if the previous run reached biofeedback start (or recorded a
    /// crash) but the app is back at square one, it almost certainly crashed —
    /// surface the log so it can be shared in one tap.
    private func surfacePriorCrashIfAny() {
        guard diagnostics == nil else { return }
        let prev = EchoelCrashLog.previousSession
        guard prev.contains("Start tapped") || prev.contains("CRASH") else { return }
        diagnostics = DiagReport(text: prev)
    }

    private func diagnosticsSheet(_ text: String) -> some View {
        NavigationStack {
            ScrollView {
                Text(text.isEmpty ? "No diagnostics recorded." : text)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .navigationTitle("Diagnostics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: text) { Text("Share") }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { diagnostics = nil }
                }
            }
        }
    }

    /// Loop length in bars (Takt). The capture is bar-aligned — it plays from the
    /// downbeat and records exactly this many whole bars — so the .wav is a clean,
    /// seamless loop. Disabled mid-capture so the length can't change underfoot.
    private var loopLengthSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Loop length (Takt)")
                .font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
            Picker("Loop length", selection: $loopBars) {
                ForEach(LoopBarLength.allCases) { len in
                    Text(len.shortLabel).tag(len)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isExporting)
            .accessibilityLabel("Loop length in bars")
        }
    }

    private var isExporting: Bool {
        exporter.status == .capturing || exporter.status == .rendering
    }
    private var exportLabel: String {
        switch exporter.status {
        case .capturing: return "Recording loop…"
        case .rendering: return "Writing .wav…"
        default:         return "Record \(loopBars.label) → send"
        }
    }
    private var exportIcon: String { isExporting ? "hourglass" : "square.and.arrow.up" }

    // MARK: - Camera pulse readout (visible acquisition feedback)

    #if canImport(AVFoundation)
    private var measurementControl: some View {
        let locked = cameraRPPG.isLocked
        let lightColor: Color = !cameraRPPG.fingerDetected ? EchoelTheme.dim
            : (locked ? EchoelTheme.accent : Color.orange)
        let statusText = !cameraRPPG.fingerDetected ? "Cover the rear camera + flash"
            : (locked ? "Locked" : "Acquiring…")
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Circle().fill(lightColor).frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(EchoelTheme.border, lineWidth: 1))
                Text(statusText).font(.caption.weight(.semibold)).foregroundStyle(EchoelTheme.text)
                Spacer(minLength: 0)
                if cameraRPPG.detectedBPM > 0, cameraRPPG.detectedBPM.isFinite {
                    // .isFinite guard: Int(Float) traps on NaN/+Inf, which an rPPG
                    // BPM can briefly be before lock (upstream divide-by-zero).
                    Text("\(Int(cameraRPPG.detectedBPM)) bpm")
                        .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(EchoelTheme.text)
                }
            }
            pulseWaveform
            ProgressView(value: locked ? 1 : min(max(cameraRPPG.confidence, 0), 1))
                .tint(locked ? EchoelTheme.accent : Color.orange)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    private var pulseWaveform: some View {
        Canvas { ctx, size in
            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height / 2))
            base.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(base, with: .color(EchoelTheme.border), lineWidth: 1)
            let w = cameraRPPG.waveform
            guard w.count > 1 else { return }
            let dx = size.width / CGFloat(w.count - 1)
            let amp = size.height / 2 - 3
            var path = Path()
            for (i, v) in w.enumerated() {
                let x = CGFloat(i) * dx
                // A NaN/Inf sample (rPPG can emit one before lock) would feed a NaN
                // point to CoreGraphics → hard crash. Clamp non-finite to the centre
                // line and bound the sample so the path is always drawable.
                let sample = v.isFinite ? CGFloat(min(max(v, -1), 1)) : 0
                let y = size.height / 2 - sample * amp
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(EchoelTheme.accent), lineWidth: 2)
        }
        .frame(height: 52).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)))
    }
    #endif

    // MARK: - Open projects sheet

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

    // MARK: - Biofeedback lifecycle

    private func toggleBiofeedback() {
        if running { stopEverything() } else { startBiofeedback() }
    }

    private func startBiofeedback() {
        EchoelCrashLog.breadcrumb("Start tapped")
        running = true
        startTask?.cancel()
        startTask = Task { @MainActor in
            await startBioSource()
            guard running, !Task.isCancelled else { return }
            generate()
            startEvolving()
        }
    }

    private func stopEverything() {
        running = false
        startTask?.cancel(); startTask = nil
        evolveTask?.cancel(); evolveTask = nil
        beatPlayer.pattern.stop()
        stopBioSource()
    }

    /// Begin publishing a bio signal. Camera rPPG on devices that have it (cover
    /// the lens), otherwise the deterministic demo source so the instrument always
    /// plays. Failures are swallowed — generation falls back to neutral defaults.
    private func startBioSource() async {
        #if canImport(AVFoundation)
        EchoelCrashLog.breadcrumb("camera starting")
        await cameraRPPG.start(publishing: bus)
        EchoelCrashLog.breadcrumb("camera started (running=\(cameraRPPG.isRunning))")
        try? await Task.sleep(for: .seconds(2))   // let the optical pulse lock
        #else
        // No camera on this platform and no synthetic demo source — the composer
        // falls back to neutral physiological defaults so the instrument still plays.
        try? await Task.sleep(for: .seconds(1))
        #endif
    }

    private func stopBioSource() {
        #if canImport(AVFoundation)
        cameraRPPG.stop()
        #endif
    }

    /// Gentle continuous evolution: every ~12 s, recompose from the *current* body
    /// state while the transport keeps running (no restart) — music that keeps
    /// arising from the live HRV.
    private func startEvolving() {
        evolveTask?.cancel()
        evolveTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                guard running, !Task.isCancelled else { break }
                generate()
            }
        }
    }

    // MARK: - The individual algorithm: bio → music

    /// A stable-but-individual seed derived from the live body. The same body state
    /// yields the same musical signature; as HRV/heart/breath drift, the music
    /// evolves. Uses wrapping arithmetic so it can never overflow-trap.
    private func bioSeed(_ f: BioSampleFrame?) -> UInt64 {
        guard let f = f else { return UInt64.random(in: UInt64.min...UInt64.max) }
        // NaN/Inf must be dropped to 0 BEFORE clamping: a clamp via max/min passes
        // NaN through unchanged, and UInt64(Float.nan) TRAPS. rPPG/BLE sources can
        // legitimately emit NaN (dropped lock, upstream divide-by-zero), so guard
        // every component with .isFinite (false for both NaN and ±Inf).
        func comp(_ v: Float, _ hi: Float, _ scale: Float) -> UInt64 {
            let safe = v.isFinite ? v : 0
            return UInt64((Swift.max(0, Swift.min(hi, safe)) * scale).rounded())
        }
        let hr  = comp(f.heartRateBPM, 300, 100)
        let hrv = comp(f.hrvNormalized, 1, 100_000)
        let coh = comp(f.coherence, 1, 100_000)
        let br  = comp(f.breathPhase, 1, 100_000)
        var s: UInt64 = 0x9E3779B97F4A7C15
        s = (s ^ hr)  &* 0xC2B2AE3D27D4EB4F
        s = (s ^ hrv) &* 0x165667B19E3779F9
        s = (s ^ coh) &* 0x27D4EB2F165667C5
        s = (s ^ br)  &+ 0x9E3779B97F4A7C15
        return s == 0 ? 1 : s
    }

    private func generate() {
        let frame = bus.latestBio
        // Finite-guard every bio value before it reaches the composer: a NaN/Inf
        // (possible from rPPG/BLE) would otherwise survive clamp01 and trap an
        // Int(nan) conversion deep in BioComposer. fin(_:_:) substitutes a neutral
        // default for any non-finite reading.
        func fin(_ v: Float?, _ d: Float) -> Float {
            guard let v, v.isFinite else { return d }
            return v
        }
        let input = BioComposer.Input(
            heartRateBPM: fin(frame?.heartRateBPM, 70),
            hrvNormalized: fin(frame?.hrvNormalized, 0.5),
            coherence: fin(frame?.coherence, 0.5),
            breathPhase: fin(frame?.breathPhase, 0),
            breathDepth: 0.5,
            key: key,
            style: style,
            mode: .flowFree,          // tempo always follows the body
            lockedTempo: 90,
            seed: bioSeed(frame)
        )
        let composition = BioComposer.compose(input)
        currentPatch = currentSoundPatch()
        synth.apply(currentPatch)
        fxCharacter.apply(to: synth.fxChain, bpm: composition.suggestedTempo, genre: style)
        pianoRoll.load(composition.notes)
        // Drum-free: clear every cell; the transport only clocks the melody.
        let silentDrums = composition.drumSteps.map { $0.map { _ in false } }
        beatPlayer.pattern.load(steps: silentDrums, accents: silentDrums)
        beatPlayer.pattern.setTempo(composition.suggestedTempo)
        session.adopt(key: key)
        lastNoteCount = composition.notes.count
        if !beatPlayer.pattern.isPlaying { beatPlayer.pattern.play() }
        EchoelCrashLog.breadcrumb("generate: \(composition.notes.count) notes, playing")
    }

    /// Build the synth patch from the chosen genre, overridden by the live sliders.
    /// All inputs are clamped, so this can never produce an out-of-range value.
    private func currentSoundPatch() -> SynthPatch {
        var p = style.synthPatch
        p.brightness = Float(min(max(brightness, 0), 1))
        p.reverbMix = Float(min(max(space, 0), 1))
        let mv = Float(min(max(movement, 0), 1))
        p.vibratoDepth = mv * 0.5
        p.lfoToFilterDepth = mv
        return p
    }

    /// Live sound change (Brightness/Space/Movement) — apply to the running synth
    /// without recomposing. Safe to call at any time; reverb updates in place.
    private func applySoundLive() {
        currentPatch = currentSoundPatch()
        synth.apply(currentPatch)
    }

    /// The Sound slider sweeps the genres. Pick the style by index, then recompose
    /// if we're running so the change is heard immediately.
    private func applySoundBlend() {
        let all = MusicStyle.allCases
        guard !all.isEmpty else { return }
        let idx = min(all.count - 1, max(0, Int((soundBlend * Double(all.count - 1)).rounded())))
        let newStyle = all[idx]
        // The Sound slider sweeps in genre STEPS. A continuous drag fires onChange
        // ~100×/sec; recomposing on every tick (full compose + synth/fx reapply +
        // pattern reload) floods the audio graph and main thread until the watchdog
        // kills the app. Only act when the genre actually crosses a boundary — within
        // one genre's band the drag is a no-op.
        guard newStyle != style else { return }
        style = newStyle
        scale = newStyle.scale
        if running { generate() } else { applySoundLive() }
    }

    // MARK: - Export / projects

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
            bpm: beatPlayer.pattern.tempo, modeRaw: ComposerMode.flowFree.rawValue,
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
        fxCharacter = p.fxCharacter
        loopBars = LoopBarLength(rawValue: p.loopBars) ?? .four
        currentPatch = p.patch
        // Reflect the patch back into the sliders so the UI matches the sound.
        brightness = Double(min(max(p.patch.brightness, 0), 1))
        space = Double(min(max(p.patch.reverbMix, 0), 1))
        movement = Double(min(max(p.patch.lfoToFilterDepth, 0), 1))
        if let i = MusicStyle.allCases.firstIndex(of: p.style), MusicStyle.allCases.count > 1 {
            soundBlend = Double(i) / Double(MusicStyle.allCases.count - 1)
        }
        session.adopt(key: p.key)
        synth.apply(p.patch)
        fxCharacter.apply(to: synth.fxChain, bpm: p.bpm, genre: p.style)
        pianoRoll.load(p.notes)
        beatPlayer.pattern.load(steps: p.drumSteps, accents: p.drumAccents)
        beatPlayer.pattern.setTempo(p.bpm)
        lastNoteCount = p.notes.count
    }

    // MARK: - Helpers

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.text)
    }
}

/// Identifiable wrapper so the share sheet can present an exported file URL.
private struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Identifiable wrapper so the diagnostics sheet can present the log text.
private struct DiagReport: Identifiable {
    let id = UUID()
    let text: String
}
#endif
