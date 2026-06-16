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

    // The live, fully-editable timbre is `currentPatch` (single source of truth).
    // Every control below — XY pad, sliders and 2-decimal numeric fields — reads and
    // writes its fields directly, so any value can be dialed OR typed exactly.

    // Optional locked tempo for tight, DAW-ready loops. When off, the tempo follows
    // the body (flowFree); when on, the loop runs at exactly `lockedBPM`.
    @State private var lockBPM = false
    @State private var lockedBPM: Double = 70

    // Collapsible control-panel state ("aufklappen") + timbre preset.
    @State private var showComposition = true
    @State private var showSound = true
    /// Timbre base: -1 = the genre's own patch, else an index into SynthPatch.factory.
    @State private var presetIndex = -1

    private static let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    // Derived / persisted musical state (no direct UI — set by sliders + bio).
    @State private var style: MusicStyle = .vaporwave
    @State private var rootIndex = 0
    @State private var scale: Scale = .minor
    @State private var fxCharacter: FXCharacter = .auto
    @State private var loopBars: LoopBarLength = .four
    @State private var currentPatch = SynthPatch(name: "Init")
    @State private var lastNoteCount: Int?
    /// Ever-advancing evolution counter folded into every seed so the composition
    /// keeps developing and never repeats, even when the body holds steady.
    @State private var evolution: UInt64 = 0

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
        .onAppear {
            currentPatch = style.synthPatch   // controls reflect a real sound from the start
            surfacePriorCrashIfAny()
        }
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

    // MARK: - Sound controls (one morph pad + genre + fine sliders)

    private var soundControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            compositionPanel
            soundPanel
            if running {
                Text("The music is arising from your live signal — every control shapes it as it plays.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            }
        }
    }

    // MARK: Panel 1 — Composition (genre · key · tuning · tempo)

    private var compositionPanel: some View {
        panel("Composition", "Genre · key · tuning · tempo", isExpanded: $showComposition) {
            genrePicker
            tonartRow
            kammertonRow
            tempoRow
        }
    }

    private var genrePicker: some View {
        labeledRow("Genre") {
            Picker("Genre", selection: $style) {
                ForEach(MusicStyle.allCases) { s in Text(s.displayName).tag(s) }
            }
            .pickerStyle(.menu).tint(EchoelTheme.text)
            .onChange(of: style) { _, s in
                scale = s.scale
                presetIndex = -1
                currentPatch = s.synthPatch   // load the genre's timbre as a starting point
                recomposeIfRunning()
            }
            .accessibilityLabel("Genre")
        }
    }

    private var tonartRow: some View {
        HStack(spacing: 12) {
            labeledRow("Key") {
                Picker("Key", selection: $rootIndex) {
                    ForEach(0..<12, id: \.self) { i in Text(Self.noteNames[i]).tag(i) }
                }
                .pickerStyle(.menu).tint(EchoelTheme.text)
                .onChange(of: rootIndex) { _, _ in recomposeIfRunning() }
                .accessibilityLabel("Key root")
            }
            labeledRow("Scale") {
                Picker("Scale", selection: $scale) {
                    ForEach(Scale.allCases, id: \.self) { sc in Text(sc.displayName).tag(sc) }
                }
                .pickerStyle(.menu).tint(EchoelTheme.text)
                .onChange(of: scale) { _, _ in recomposeIfRunning() }
                .accessibilityLabel("Scale")
            }
        }
    }

    private var kammertonRow: some View {
        @Bindable var session = session
        // Concert pitch, exact to 0.01 Hz (380–500). Common references one tap away.
        return VStack(alignment: .leading, spacing: 6) {
            ParamControl(label: "Kammerton", value: $session.a4Hz, range: 380...500, unit: "Hz",
                         onChange: { synth.setTuning(a4Hz: session.a4Hz) },
                         onCommit: { recomposeIfRunning() })
            HStack(spacing: 6) {
                ForEach(TuningReference.presets, id: \.self) { hz in
                    Button("\(Int(hz))") {
                        session.a4Hz = hz
                        synth.setTuning(a4Hz: hz)
                        recomposeIfRunning()
                    }
                    .font(EchoelTheme.font(11, .medium))
                    .foregroundStyle(abs(session.a4Hz - hz) < 0.005 ? .black : EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(abs(session.a4Hz - hz) < 0.005 ? EchoelTheme.text : EchoelTheme.fill))
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set concert pitch A\(Int(hz)) hertz")
                }
            }
        }
    }

    private var tempoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $lockBPM) {
                Text("Lock BPM (tight loops)").font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
            }
            .tint(EchoelTheme.accent)
            .onChange(of: lockBPM) { _, _ in recomposeIfRunning() }
            .accessibilityHint("When on, the loop runs at exactly the set tempo instead of following your heart")

            if lockBPM {
                ParamControl(label: "Tempo", value: $lockedBPM, range: 40...240, unit: "BPM",
                             onChange: { if running { beatPlayer.pattern.setTempo(lockedBPM) } },
                             onCommit: { recomposeIfRunning() })
            }
        }
    }

    // MARK: Panel 2 — Sound & texture (XY pad · preset · sliders · randomize)

    private var soundPanel: some View {
        panel("Sound & texture", "Shape the timbre — exact to 0.01", isExpanded: $showSound) {
            soundPad
            presetRow
            randomizeButton

            groupHeader("Tone")
            param("Brightness", $currentPatch.brightness, 0...1)
            param("Harmonicity", $currentPatch.harmonicity, 0...1)
            param("Harmonic level", $currentPatch.harmonicLevel, 0...1)
            param("Noise", $currentPatch.noiseLevel, 0...1)

            groupHeader("Filter")
            param("Cutoff", $currentPatch.filterCutoff, 20...18000, unit: "Hz")
            param("Resonance", $currentPatch.filterResonance, 0...1)
            param("LFO → filter", $currentPatch.lfoToFilterDepth, 0...1)
            param("Filter LFO rate", $currentPatch.filterLFORate, 0...20, unit: "Hz")
            param("Filter LFO depth", $currentPatch.filterLFODepth, 0...1)

            groupHeader("Envelope")
            param("Attack", $currentPatch.attack, 0...5, unit: "s")
            param("Decay", $currentPatch.decay, 0...5, unit: "s")
            param("Sustain", $currentPatch.sustain, 0...1)
            param("Release", $currentPatch.release, 0...10, unit: "s")

            groupHeader("Space & vibrato")
            param("Reverb mix", $currentPatch.reverbMix, 0...1)
            param("Reverb decay", $currentPatch.reverbDecay, 0...10, unit: "s")
            param("Vibrato rate", $currentPatch.vibratoRate, 0...12, unit: "Hz")
            param("Vibrato depth", $currentPatch.vibratoDepth, 0...1)
        }
    }

    /// A precise parameter row bound to a live patch field: slider + a 2-decimal
    /// numeric field. `applySoundLive` runs continuously so edits are heard at once.
    private func param(_ label: String, _ value: Binding<Float>,
                       _ range: ClosedRange<Float>, unit: String = "") -> some View {
        ParamControl(label: label, value: value, range: range, unit: unit,
                     onChange: { applySoundLive() })
    }

    private func groupHeader(_ t: String) -> some View {
        Text(t).font(EchoelTheme.font(11, .semibold)).foregroundStyle(EchoelTheme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private var presetRow: some View {
        labeledRow("Character") {
            Picker("Character", selection: $presetIndex) {
                Text("Genre default").tag(-1)
                ForEach(SynthPatch.factory.indices, id: \.self) { i in
                    Text(SynthPatch.factory[i].name).tag(i)
                }
            }
            .pickerStyle(.menu).tint(EchoelTheme.text)
            .onChange(of: presetIndex) { _, i in
                currentPatch = (i >= 0 && i < SynthPatch.factory.count) ? SynthPatch.factory[i] : style.synthPatch
                applySoundLive()
            }
            .accessibilityLabel("Timbre character preset")
        }
    }

    private var randomizeButton: some View {
        Button {
            // Fresh timbre colour: start from a random character, then jitter a few
            // expressive fields so each press genuinely differs. (Don't touch
            // presetIndex — that would retrigger the picker's loader and clobber this.)
            var p = SynthPatch.factory.randomElement() ?? currentPatch
            p.brightness = Float.random(in: 0.25...0.85)
            p.reverbMix = Float.random(in: 0.2...0.7)
            p.filterCutoff = Float.random(in: 400...6000)
            p.filterResonance = Float.random(in: 0...0.5)
            currentPatch = p
            applySoundLive()
        } label: {
            Label("Randomize timbre", systemImage: "dice")
                .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Picks a new sound character and timbre for variety")
    }

    // MARK: Panel chrome

    /// A collapsible, accessibility-first panel ("aufklappen"): a titled
    /// DisclosureGroup wrapped as a bordered card so the whole window is one
    /// scrollable stack of expandable sections.
    private func panel<Content: View>(_ title: String, _ subtitle: String,
                                      isExpanded: Binding<Bool>,
                                      @ViewBuilder content: () -> Content) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                Text(subtitle).font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            }
        }
        .tint(EchoelTheme.dim)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    /// A label-above-control row (forms: labels above inputs — per UI rules).
    private func labeledRow<Content: View>(_ label: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(EchoelTheme.font(12, .medium)).foregroundStyle(EchoelTheme.dim)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Recompose now if playing (key/tuning/tempo affect the notes); otherwise just
    /// refresh the live timbre so the change is reflected when playback begins.
    private func recomposeIfRunning() {
        if running { generate() } else { applySoundLive() }
    }

    /// One 2D morph pad replacing the timbre sliders. X = tone (dark → bright),
    /// Y = space & motion (intimate/still → open/moving). Two markers: the WHITE dot
    /// is your hand (the sound you set); the GREEN dot is your live body
    /// (coherence → X, HRV → Y) — so physiology and sound read in one place.
    /// Bottom-left = warm, still, intimate (most meditative); top-right = bright,
    /// spacious, moving. Mapping uses existing EchoelDDSP params — no new DSP.
    private var soundPad: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tone → Space").font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
                Spacer(minLength: 0)
                Text("dark·still → bright·open").font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            }
            GeometryReader { geo in
                let w = Swift.max(geo.size.width, 1)
                let h = Swift.max(geo.size.height, 1)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(EchoelTheme.fill)
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .strokeBorder(EchoelTheme.border, lineWidth: 1))
                    // Live body marker (green) — coherence→X, HRV→Y. Display only.
                    if let p = bioPadPoint {
                        Circle().fill(EchoelTheme.accent.opacity(0.9))
                            .frame(width: 14, height: 14)
                            .position(x: p.x * w, y: (1 - p.y) * h)
                            .accessibilityHidden(true)
                    }
                    // Sound marker (white) — your current setting.
                    Circle().fill(EchoelTheme.text)
                        .frame(width: 22, height: 22)
                        .position(x: CGFloat(currentPatch.brightness) * w,
                                  y: (1 - CGFloat(currentPatch.reverbMix)) * h)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let x = Swift.min(Swift.max(v.location.x / w, 0), 1)
                            let y = Swift.min(Swift.max(1 - v.location.y / h, 0), 1)
                            currentPatch.brightness = Float(x)
                            currentPatch.reverbMix = Float(y)
                            applySoundLive()
                        }
                )
            }
            .frame(height: 200)
            .accessibilityElement()
            .accessibilityLabel("Sound morph pad. Horizontal sets tone, vertical sets space and motion.")
        }
    }

    /// Live body position on the pad (coherence → X, HRV → Y); nil with no signal.
    private var bioPadPoint: CGPoint? {
        guard let bio = bus.latestBio else { return nil }
        let x = CGFloat(Swift.min(Swift.max(bio.coherence.isFinite ? bio.coherence : 0.5, 0), 1))
        let y = CGFloat(Swift.min(Swift.max(bio.hrvNormalized.isFinite ? bio.hrvNormalized : 0.5, 0), 1))
        return CGPoint(x: x, y: y)
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
        // The body sets the CHARACTER (density, tempo, contour) via the Input fields;
        // the seed picks the specific notes. Fold an advancing nonce into the bio seed
        // so each take is a fresh individual variation — the music keeps evolving and
        // never repeats, even when the readings hold steady — while the body's
        // signature still dominates the feel.
        evolution &+= 1
        let evolvingSeed = bioSeed(frame) ^ (evolution &* 0x9E3779B97F4A7C15)
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
            seed: evolvingSeed
        )
        let composition = BioComposer.compose(input)
        // Honor the user's Kammerton (concert pitch) + live timbre on the next notes.
        synth.setTuning(a4Hz: session.a4Hz)
        synth.apply(currentPatch)
        // Locked tempo wins for tight loops; otherwise the body sets the pace.
        let tempo = lockBPM ? min(max(lockedBPM, 40), 240) : composition.suggestedTempo
        fxCharacter.apply(to: synth.fxChain, bpm: tempo, genre: style)
        pianoRoll.load(composition.notes)
        // Drum-free: clear every cell; the transport only clocks the melody.
        let silentDrums = composition.drumSteps.map { $0.map { _ in false } }
        beatPlayer.pattern.load(steps: silentDrums, accents: silentDrums)
        beatPlayer.pattern.setTempo(tempo)
        session.adopt(key: key)
        lastNoteCount = composition.notes.count
        if !beatPlayer.pattern.isPlaying { beatPlayer.pattern.play() }
        EchoelCrashLog.breadcrumb("generate: \(composition.notes.count) notes, playing")
    }

    /// Apply the live timbre (`currentPatch`) to the running synth without
    /// recomposing. Safe to call at any time; the audio thread fans the patch
    /// across every voice in its render drain.
    private func applySoundLive() {
        synth.apply(currentPatch)
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
        currentPatch = p.patch          // every control reads this, so the UI matches
        presetIndex = -1                // a saved patch is "custom", not a factory preset
        session.adopt(key: p.key)
        session.a4Hz = p.a4Hz
        synth.setTuning(a4Hz: p.a4Hz)
        synth.apply(p.patch)
        fxCharacter.apply(to: synth.fxChain, bpm: p.bpm, genre: p.style)
        pianoRoll.load(p.notes)
        beatPlayer.pattern.load(steps: p.drumSteps, accents: p.drumAccents)
        beatPlayer.pattern.setTempo(p.bpm)
        lastNoteCount = p.notes.count
    }

    // MARK: - Helpers

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

/// A precise parameter control: a label, a slider for feel, and a numeric field you
/// can type into — so any value is settable by dragging OR entered exactly to two
/// decimals. Generic over Float (patch fields) and Double (tempo/tuning). `onChange`
/// fires continuously (cheap live updates); `onCommit` fires once on release/submit
/// (use it for heavy work like recomposition).
private struct ParamControl<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let label: String
    @Binding var value: V
    let range: ClosedRange<V>
    var unit: String = ""
    var onChange: () -> Void = {}
    var onCommit: () -> Void = {}

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label).font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
                Spacer(minLength: 0)
                TextField("", text: $text)
                    .multilineTextAlignment(.trailing)
                    .font(EchoelTheme.font(13).monospacedDigit())
                    .foregroundStyle(EchoelTheme.text)
                    .textFieldStyle(.plain)
                    .frame(width: 78)
                    .focused($focused)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .submitLabel(.done)
                    #endif
                    .onSubmit(commitText)
                    .onChange(of: focused) { _, f in if !f { commitText() } }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(EchoelTheme.border, lineWidth: 1))
                    .accessibilityLabel("\(label) value")
                if !unit.isEmpty {
                    Text(unit).font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                        .frame(width: 30, alignment: .leading)
                }
            }
            Slider(value: $value, in: range) { editing in
                if !editing { syncText(); onCommit() }
            }
            .tint(EchoelTheme.accent)
            .onChange(of: value) { _, _ in
                if !focused { syncText() }
                onChange()
            }
            .accessibilityLabel(label)
        }
        .onAppear { syncText() }
    }

    private func syncText() { text = String(format: "%.2f", Double(value)) }

    /// Parse the typed value (accepting comma or dot), clamp to range, write back.
    private func commitText() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        if let d = Double(cleaned) {
            value = V(min(max(d, Double(range.lowerBound)), Double(range.upperBound)))
        }
        syncText()
        onCommit()
    }
}
#endif
