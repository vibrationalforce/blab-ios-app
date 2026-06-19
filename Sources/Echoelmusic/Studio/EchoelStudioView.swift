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
    @Environment(MIDIOutput.self) private var midiOut
    @Environment(PolySynthVoice.self) private var synth
    @Environment(SubBassVoice.self) private var subBass
    @Environment(SessionContext.self) private var session
    @Environment(LoopExporter.self) private var exporter
    @Environment(ProjectStore.self) private var projects
    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif

    // The single live-state flag: biofeedback running or not.
    @State private var running = false

    /// Drives Siri/Shortcuts intent consumption (start/stop/keep loop) when the
    /// app becomes active after an intent opens it.
    @Environment(\.scenePhase) private var scenePhase

    // The live, fully-editable timbre is `currentPatch` (single source of truth).
    // Every control below — XY pad, sliders and 2-decimal numeric fields — reads and
    // writes its fields directly, so any value can be dialed OR typed exactly.

    // Optional locked tempo for tight, DAW-ready loops. When off, the tempo follows
    // the body (flowFree); when on, the loop runs at exactly `lockedBPM`.
    @AppStorage("studio.lockBPM") private var lockBPM = false
    @AppStorage("studio.lockedBPM") private var lockedBPM: Double = 70

    // Collapsible control-panel state ("aufklappen") + timbre preset.
    @State private var showComposition = true
    @State private var showMood = false
    @State private var showSound = true
    @State private var showEffects = false

    /// User-chosen tempo-synced delay note value ("studio calculator in the FX"),
    /// re-applied after genre/character FX so the pick is never clobbered.
    @State private var delaySync = TempoSyncOption(.eighth, .dotted)

    /// Continuous mood/character controls that shape the composition (blend with bio).
    @State private var mood = MoodProfile()
    /// Timbre base: -1 = the genre's own patch, else an index into SynthPatch.factory.
    @AppStorage("studio.presetIndex") private var presetIndex = -1

    private static let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    /// "10.24.0 (1920)" — marketing version + build, read from the bundle so the
    /// running app reports exactly which TestFlight build it is.
    static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    // Derived / persisted musical state. Genre, key and scale survive relaunch so
    // the studio reopens on the setup you left it in (MusicStyle / Scale are
    // String-backed enums → @AppStorage stores the rawValue directly).
    @AppStorage("studio.genre") private var style: MusicStyle = .vaporwave
    @AppStorage("studio.rootIndex") private var rootIndex = 0
    @AppStorage("studio.scale") private var scale: Scale = .minor
    /// Selected tone system (microtonal). "edo12" = standard 12-TET (default, no retune).
    /// Persisted so a chosen world tuning survives relaunch.
    @AppStorage("toneSystemID") private var tuningID = "edo12"
    @AppStorage("studio.fxCharacter") private var fxCharacter: FXCharacter = .auto
    @AppStorage("studio.loopBars") private var loopBars: LoopBarLength = .four
    /// Global articulation macro: 0 = pad (slow swell), 1 = pluck (struck/short). Owns
    /// the envelope for EVERY character (genre/preset = timbre, this = onset/dynamics).
    /// Persisted; re-imposed whenever a character or genre loads. Drives the per-note
    /// velocity sensitivity automatically (short attack ⇒ percussive ⇒ touch-responsive).
    @AppStorage("studio.articulation") private var articulation: Double = 0.4
    @State private var currentPatch = SynthPatch(name: "Init")
    @State private var lastNoteCount: Int?
    /// Ever-advancing evolution counter folded into every seed so the composition
    /// keeps developing and never repeats, even when the body holds steady.
    @State private var evolution: UInt64 = 0

    /// EchoelAI's plain-English narration of how the live body is shaping the sound,
    /// refreshed each time the composition re-seeds. Deterministic, on-device.
    @State private var aiExplanation = ""

    // Background evolution + bio acquisition.
    @State private var evolveTask: Task<Void, Never>?
    /// Debounce handle that coalesces rapid recompose requests (see scheduleGenerate).
    @State private var regenTask: Task<Void, Never>?
    @State private var startTask: Task<Void, Never>?
    /// Non-blocking watcher that re-seeds once the rPPG pulse first locks (see snapToLockWhenReady).
    @State private var lockSnapTask: Task<Void, Never>?
    /// When the last take was composed — the floor for automatic re-seeds.
    @State private var lastSeedAt: Date = .distantPast
    /// Minimum seconds between AUTOMATIC re-seeds (evolve/lock). User edits bypass it.
    private let minAutoSeedGap: TimeInterval = 3.5

    // Sheets / dialogs
    @State private var showOpen = false
    @State private var showSaveDialog = false
    @State private var saveName = ""
    @State private var share: ExportedFile?
    @State private var diagnostics: DiagReport?

    // Tools — open the (previously unreachable) editors as sheets.
    @State private var showPianoRoll = false
    @State private var showClips = false
    @State private var showInput = false
    @State private var showPatchEditor = false
    @State private var showVisual = false
    @State private var showBreath = false
    /// Presents the full per-stage FX panel (every parameter as a slider).
    @State private var showAllFX = false
    /// Which drum track's sample browser is open (nil = closed). Identifiable
    /// wrapper so `.sheet(item:)` can carry the track index.
    @State private var sampleBrowserTrack: TrackRef?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Persisted in-app zoom level (index into StudioZoom.ladder). `-1` = follow the
    /// system text size; once the user pinch-zooms it becomes an explicit level.
    @AppStorage("ui.zoomStep") private var zoomStep: Int = -1

    // Transpose — shift the whole take in semitones (octave steps stay in-key).
    @State private var transposeSemitones: Float = 0
    @State private var showTranspose = false

    // Immersive-visual controls (also persisted feel). All clamped so the WCAG flash
    // ceiling (≤3 Hz) can never be exceeded — see MetalBioView.
    @State private var visualIntensity: Float = 1.0
    @State private var visualDetail: Float = 40       // ring density
    @State private var visualMotion: Float = 1.0      // animation speed (flash-clamped)
    @State private var visualSpread: Float = 1.0
    @State private var showVisualSettings = false

    private var key: MusicalKey { MusicalKey(root: rootIndex, scale: scale) }

    /// The instrument's current tonic frequency (Hz) at the chosen Kammerton, shifted
    /// by the global transpose — fed to the immersive visual, which transposes it up
    /// into visible light, so the colour tracks key + concert pitch + transpose.
    private var currentToneHz: Double {
        let semis = Double(Int(transposeSemitones.rounded()))
        return session.a4Hz * pow(2.0, (Double(60 + rootIndex) - 69.0 + semis) / 12.0)
    }

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
                    toolsRow
                }
                .padding(16)
            }
        }
        // Pinch anywhere to zoom the whole interface (persists); honours the system
        // text size until the user explicitly zooms. For users who need larger text.
        .modifier(StudioZoom(step: $zoomStep))
        .background(EchoelTheme.bg)
        .onAppear {
            // Controls reflect a real sound from the start — honor a restored timbre
            // preset, else the genre's own patch.
            currentPatch = (presetIndex >= 0 && presetIndex < SynthPatch.factory.count)
                ? SynthPatch.factory[presetIndex] : style.synthPatch
            applyArticulation()                // impose the persisted Pluck↔Pad envelope
            applyTuning()                      // 12-TET default = no-op; restores any selected system
            surfacePriorCrashIfAny()
            handlePendingIntent()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { handlePendingIntent() }
        }
        .onDisappear { stopEverything() }
        .sheet(isPresented: $showOpen) { openSheet }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .sheet(item: $diagnostics) { report in diagnosticsSheet(report.text) }
        .sheet(isPresented: $showPianoRoll) {
            PianoRollView(pattern: beatPlayer.pattern, model: pianoRoll)
        }
        .sheet(isPresented: $showClips) { ClipView() }
        .sheet(isPresented: $showAllFX) {
            EchoelFXView(chain: synth.fxChain, bpm: currentTempo,
                         fxEnabled: { synth.isFXEnabled },
                         setFXEnabled: { synth.setFXEnabled($0) })
        }
        .sheet(isPresented: $showInput) { AudioInputPickerView() }
        .sheet(item: $sampleBrowserTrack) { ref in SampleBrowserView(track: ref.id) }
        .sheet(isPresented: $showPatchEditor) {
            PatchEditorView(initial: currentPatch) { p in
                currentPatch = p
                synth.apply(p)   // editor changes hit the live voice immediately
            }
        }
        #if canImport(MetalKit) && canImport(UIKit)
        .fullScreenCover(isPresented: $showVisual) {
            ZStack(alignment: .topTrailing) {
                MetalBioView(reduceMotion: reduceMotion, toneHz: currentToneHz,
                             intensity: visualIntensity, ringDensity: visualDetail,
                             motion: visualMotion, spread: visualSpread).ignoresSafeArea()
                Button { showVisual = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundStyle(.white.opacity(0.6)).padding()
                }
            }
        }
        #endif
        .fullScreenCover(isPresented: $showBreath) { BreathGuideView() }
        .alert("Save project", isPresented: $showSaveDialog) {
            TextField("Name", text: $saveName)
            Button("Save") { saveProject() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current sound, key, tempo and generated loop.")
        }
    }

    // MARK: - Tools (deep editors)

    /// Opens the deeper editors — a real piano roll, the synth patch editor, and the
    /// sample browser — without cluttering the one-button flow.
    private var toolsRow: some View {
        @Bindable var midiOut = midiOut
        return Menu {
            Button { showPianoRoll = true } label: { Label("Piano Roll", systemImage: "pianokeys") }
            Button { showClips = true } label: { Label("Clips", systemImage: "square.grid.2x2") }
            Button { showPatchEditor = true } label: { Label("Sound Editor", systemImage: "dial.medium") }
            Menu {
                ForEach(Array(BeatPlayer.trackNames.enumerated()), id: \.offset) { idx, name in
                    Button(name) { sampleBrowserTrack = TrackRef(id: idx) }
                }
            } label: { Label("Drum Samples", systemImage: "waveform") }
            Button { showBreath = true } label: { Label("Breathing Guide", systemImage: "wind") }
            Button { showInput = true } label: { Label("Audio Input", systemImage: "mic") }
            #if canImport(MetalKit) && canImport(UIKit)
            Button { showVisual = true } label: { Label("Immersive Visual", systemImage: "sparkles") }
            #endif
            Divider()
            // Live MIDI / MPE OUT — the body's take streams to a virtual
            // "Echoelmusic" source any DAW can record. Off by default.
            Toggle(isOn: $midiOut.enabled) { Label("MIDI Out (live)", systemImage: "pianokeys.inverse") }
            Toggle(isOn: $midiOut.mpeEnabled) { Label("MPE (per-note channels)", systemImage: "waveform.path") }
                .disabled(!midiOut.enabled)
            Divider()
            // Self-identifying build — confirms at a glance which TestFlight build is running.
            Text("Echoel \(Self.appVersionString)").font(EchoelTheme.font(11))
        } label: {
            Label("Tools", systemImage: "slider.horizontal.3")
                .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                .frame(maxWidth: .infinity).frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .accessibilityLabel("Open tools")
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
            transposePanel
            moodPanel
            soundPanel
            effectsPanel
            visualPanel
            if running {
                Text(aiExplanation.isEmpty
                     ? "The music is arising from your live signal — every control shapes it as it plays."
                     : aiExplanation)
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .animation(.easeInOut(duration: 0.3), value: aiExplanation)
            }
        }
    }

    // MARK: Panel 1 — Composition (genre · key · tuning · tempo)

    private var compositionPanel: some View {
        panel("Composition", "Genre · key · tuning · tempo", isExpanded: $showComposition) {
            genrePicker
            tonartRow
            kammertonRow
            tuningRow
            tempoRow
        }
    }

    /// Tone system — 12-TET by default; selecting just intonation, a maqām, gamelan
    /// etc. retunes the take to that intonation in the current key. Applied live.
    private var tuningRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            labeledRow("Tone system") {
                Picker("Tone system", selection: $tuningID) {
                    ForEach(TuningSystem.library) { t in Text(t.name).tag(t.id) }
                }
                .pickerStyle(.menu).tint(EchoelTheme.text)
                .onChange(of: tuningID) { _, _ in applyTuning() }
                .accessibilityLabel("Tone system")
            }
            if tuningID != "edo12" {
                Text("Notes are retuned to this system in the current key. Choose 12-TET for standard tuning.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Push the selected tone system's per-pitch-class retune table to the synth
    /// (relative to the current key root). 12-TET → all zeros → identical playback.
    private func applyTuning() {
        let cents = TuningSystem.named(tuningID).pitchClassCents(root: rootIndex).map { Float($0) }
        synth.setTuningCents(cents)
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
                .onChange(of: rootIndex) { _, _ in applyTuning(); recomposeIfRunning() }
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
        // Concert pitch A4 — number-pad entry only, exact to 0.01 Hz (380–500).
        // Standard 440.00; the saved preference persists. (Slider + chips removed
        // to save space.)
        return EchoelValueField(label: "Kammerton A4", value: $session.a4Hz, range: 380...500, unit: "Hz",
                                onCommit: { synth.setTuning(a4Hz: session.a4Hz); subBass.setTuning(a4Hz: session.a4Hz); recomposeIfRunning() })
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
                EchoelValueField(label: "Tempo", value: $lockedBPM, range: 40...240, unit: "BPM",
                                 onChange: { if running { beatPlayer.pattern.setTempo(lockedBPM) } },
                                 onCommit: { recomposeIfRunning() })
            }
        }
    }

    // MARK: Panel — Transpose (shift the whole take)

    private var transposePanel: some View {
        panel("Transpose", "Shift the whole take · ±24 semitones", isExpanded: $showTranspose) {
            EchoelValueField(label: "Transpose", value: $transposeSemitones,
                             range: -24...24, unit: "st", decimals: 0,
                             onCommit: { recomposeIfRunning() })
            Text("Octave steps (±12 / ±24) stay in key; other amounts shift the whole take to a new key. The sub-bass and the immersive colour follow automatically.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Panel — Visual (immersive sound→light)

    private var visualPanel: some View {
        panel("Visual", "Immersive sound→light — open from Tools", isExpanded: $showVisualSettings) {
            EchoelValueField(label: "Intensity", value: $visualIntensity, range: 0...1.5)
            EchoelValueField(label: "Detail", value: $visualDetail, range: 8...90, decimals: 0)
            EchoelValueField(label: "Motion", value: $visualMotion, range: 0...1.5)
            EchoelValueField(label: "Spread", value: $visualSpread, range: 0.5...1.5)
            Text("The colour is the heard tone transposed into visible light (physically correct). Motion is capped so the flash rate always stays under the 3 Hz safety limit.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Panel — Mood (character of the composition)

    private var moodPanel: some View {
        panel("Mood", "Character of the composition", isExpanded: $showMood) {
            moodKnob("Liveliness", $mood.liveliness)
            moodKnob("Darkness", $mood.darkness)
            moodKnob("Tension", $mood.tension)
            moodKnob("Romance", $mood.romance)
            moodKnob("Weird", $mood.weird)
            moodKnob("Virtuosity", $mood.virtuosity)
            moodKnob("Syncopation", $mood.syncopation)
            moodKnob("Humanize", $mood.humanize)
            Text("Friendly ↔ scary (tension) · sparse ↔ busy (liveliness) · bright ↔ dark · lush 7ths (romance) · odd leaps (weird). Blends with your live signal.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A mood value recomposes on release (it changes the notes, not the timbre).
    private func moodKnob(_ label: String, _ value: Binding<Float>) -> some View {
        EchoelValueField(label: label, value: value, range: 0...1,
                         onCommit: { recomposeIfRunning() })
    }

    // MARK: Panel 2 — Sound & texture (preset · scrubbable values · randomize)

    private var soundPanel: some View {
        panel("Sound & texture", "Shape the timbre — exact to 0.0001", isExpanded: $showSound) {
            presetRow
            randomizeButton

            // Every parameter is a scrubbable numeric value, one per row with its unit
            // shown after it (drag = fast/coarse or slow/fine to 0.0001; tap = type
            // exact). Pickers for character. No sliders.
            groupHeader("Tone")
            knob("Brightness", $currentPatch.brightness, 0...1)
            knob("Harmonics", $currentPatch.harmonicity, 0...1)
            knob("Harm. level", $currentPatch.harmonicLevel, 0...1)
            knob("Noise", $currentPatch.noiseLevel, 0...1)

            groupHeader("Filter")
            knob("Cutoff", $currentPatch.filterCutoff, 20...18000, unit: "Hz")
            knob("Resonance", $currentPatch.filterResonance, 0...1)
            knob("LFO→filter", $currentPatch.lfoToFilterDepth, 0...1)
            knob("LFO rate", $currentPatch.filterLFORate, 0...20, unit: "Hz")
            knob("LFO depth", $currentPatch.filterLFODepth, 0...1)

            groupHeader("Envelope")
            // Global articulation macro — one control that shapes the ONSET for EVERY
            // character. Not named after an instrument: the same struck onset is a
            // glass bowl, a mallet, a plucked string or a tuba stab depending on the
            // chosen timbre. Writes A/D/S/R below (which stay editable for fine-tuning).
            EchoelValueField(label: "Swell ↔ Strike", value: Binding(
                get: { Float(articulation) },
                set: { articulation = Double(min(1, max(0, $0))) }
            ), range: Float(0)...Float(1), onChange: { applyArticulation() })
            Text("How each character speaks: 0 = slow swell (bowed strings, glass bowl) · 1 = struck / sharp onset (mallet, plucked, tuba stab). Sets touch response too; click-safe.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            param("Attack", $currentPatch.attack, 0...5, unit: "s")
            param("Decay", $currentPatch.decay, 0...5, unit: "s")
            param("Sustain", $currentPatch.sustain, 0...1)
            param("Release", $currentPatch.release, 0...10, unit: "s")

            groupHeader("Space & vibrato")
            knob("Reverb mix", $currentPatch.reverbMix, 0...1)
            knob("Reverb decay", $currentPatch.reverbDecay, 0...10, unit: "s")
            knob("Vibrato rate", $currentPatch.vibratoRate, 0...12, unit: "Hz")
            knob("Vibrato depth", $currentPatch.vibratoDepth, 0...1)

            // The "Vibration" dimension: a dedicated sub-octave bass you can push to
            // FEEL the body's bass (sub / headphones / haptics). Silent at 0.
            groupHeader("Sub / Bass (felt)")
            EchoelValueField(label: "Sub level", value: Binding(
                get: { subBass.subGain },
                set: { subBass.subGain = min(max($0, 0), 1) }
            ), range: Float(0)...Float(1))
            Text("Reinforces the bass an octave below — feel it on a sub, in headphones, or as haptics.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A precise parameter row bound to a live patch field: a scrubbable numeric
    /// value (no slider). `applySoundLive` runs continuously so edits are heard at once.
    private func param(_ label: String, _ value: Binding<Float>,
                       _ range: ClosedRange<Float>, unit: String = "") -> some View {
        EchoelValueField(label: label, value: value, range: range, unit: unit,
                         onChange: { applySoundLive() })
    }

    /// Alias kept for call-site readability; same scrubbable numeric value as `param`.
    private func knob(_ label: String, _ value: Binding<Float>,
                      _ range: ClosedRange<Float>, unit: String = "") -> some View {
        EchoelValueField(label: label, value: value, range: range, unit: unit,
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
                applyArticulation()   // character = timbre; the global macro owns the envelope
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
            applyArticulation()   // keep the global articulation across a timbre shuffle
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

    // MARK: Panel 3 — Effects (production character)

    private var effectsPanel: some View {
        panel("Effects", "Production character", isExpanded: $showEffects) {
            labeledRow("Character") {
                Picker("Effect", selection: $fxCharacter) {
                    ForEach(FXCharacter.allCases) { c in Text(c.displayName).tag(c) }
                }
                .pickerStyle(.menu).tint(EchoelTheme.text)
                .onChange(of: fxCharacter) { _, _ in applyFX() }
                .accessibilityLabel("Effect character")
            }
            Text(fxCharacter.blurb)
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            labeledRow("Delay") {
                Picker("Delay note", selection: $delaySync) {
                    ForEach(TempoSyncOption.common) { opt in Text(opt.label).tag(opt) }
                }
                .pickerStyle(.menu).tint(EchoelTheme.text)
                .onChange(of: delaySync) { _, _ in applyDelaySync(bpm: currentTempo) }
                .accessibilityLabel("Delay note value")
            }
            // Full control: open every stage (filter, delay, chorus, flanger,
            // phaser, tremolo, compressor, limiter) with all parameters as sliders.
            Button { showAllFX = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                    Text("All parameters").font(EchoelTheme.font(13, .semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(EchoelTheme.font(12))
                }
                .foregroundStyle(EchoelTheme.text)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Open the full effects chain — every parameter as a slider")
        }
    }

    /// Current effective tempo (locked BPM or the body-driven pattern tempo).
    private var currentTempo: Double { lockBPM ? min(max(lockedBPM, 40), 240) : beatPlayer.pattern.tempo }

    /// Stamp the chosen effect character on the live FX chain (independent of genre).
    private func applyFX() {
        fxCharacter.apply(to: synth.fxChain, bpm: currentTempo, genre: style)
        applyDelaySync(bpm: currentTempo)
    }

    /// Re-apply the user's tempo-synced delay note value on top of the genre/character
    /// FX (which also set delay time), so the chosen division is never clobbered.
    private func applyDelaySync(bpm: Double) {
        synth.fxChain.delay.timeSeconds = delaySync.clampedSeconds(bpm: bpm, in: 0.001...2.0)
        synth.fxChain.delayEnabled = true
    }

    // MARK: Panel chrome

    /// A collapsible, accessibility-first panel ("aufklappen"): a titled
    /// DisclosureGroup wrapped as a bordered card so the whole window is one
    /// scrollable stack of expandable sections.
    private func panel<Content: View>(_ title: String, _ subtitle: String,
                                      isExpanded: Binding<Bool>,
                                      @ViewBuilder content: @escaping () -> Content) -> some View {
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

    /// Recompose if playing (key/tuning/tempo affect the notes); otherwise just
    /// refresh the live timbre so the change is reflected when playback begins.
    /// Debounced: one genre tap cascades through several @State changes
    /// (style→scale→preset→patch), each firing onChange — without coalescing that
    /// regenerated the whole pattern 2–4× within milliseconds → audible stutter.
    private func recomposeIfRunning() {
        if running { scheduleGenerate() } else { applySoundLive() }
    }

    /// Coalesce rapid recompose requests into a single `generate()` after a short
    /// quiet window, so a cascade of control changes reloads the pattern just once.
    ///
    /// `auto` re-seeds (the evolve loop and the lock-snap) are additionally
    /// RATE-LIMITED to one per `minAutoSeedGap`: the music can never re-seed faster
    /// than a musical phrase, no matter how many automatic triggers fire. A user
    /// edit (`auto: false`) stays instant (140 ms). This makes a re-seed "flood"
    /// structurally impossible rather than merely unlikely.
    private func scheduleGenerate(auto: Bool = false) {
        regenTask?.cancel()
        var delay = 0.140
        if auto {
            let since = Date().timeIntervalSince(lastSeedAt)
            if since < minAutoSeedGap { delay = max(delay, minAutoSeedGap - since) }
            // Claim the anti-flood floor at SCHEDULE time, not only when generate()
            // runs: several auto triggers can fire within one window (lock-snap +
            // evolve tick land together the moment a pulse locks). Advancing the
            // floor to this reseed's run time makes the next auto trigger compute a
            // full gap and collapse into it — no rapid burst of re-seeds.
            lastSeedAt = Date().addingTimeInterval(delay)
        }
        regenTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, running else { return }
            generate()
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

            Button { Task { await keepLastLoop() } } label: {
                Label(isExporting ? exportLabel : "Keep last \(loopBars.label) (just played)",
                      systemImage: "clock.arrow.circlepath")
                    .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isExporting || lastNoteCount == nil)
            .accessibilityHint("Keeps the last bars you just heard as a WAV loop, without replaying them")

            Button { exportMIDI() } label: {
                Label("Send .mid (for your DAW)", systemImage: "pianokeys")
                    .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(lastNoteCount == nil)
            .accessibilityHint("Exports the generated melody as a MIDI file to open in any DAW")

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

    /// Consume a Siri/Shortcuts request deposited by an App Intent, routing it to
    /// the same handlers the on-screen buttons use. Read-once, so it fires exactly
    /// once per request; unknown/absent actions are a no-op.
    private func handlePendingIntent() {
        #if canImport(AppIntents)
        guard let action = EchoelIntentInbox.take() else { return }
        switch action {
        case .start:    if !running { startBiofeedback() }
        case .stop:     if running { stopEverything() }
        case .keepLoop: Task { await keepLastLoop() }
        }
        #endif
    }

    private func startBiofeedback() {
        EchoelCrashLog.breadcrumb("Start tapped")
        running = true
        startTask?.cancel()
        startTask = Task { @MainActor in
            // Start the camera/bio source publishing, but DO NOT block on a pulse
            // lock — sound must begin immediately. We compose now from whatever bio
            // is available (neutral defaults if none) and snap to the real heartbeat
            // the instant the lock arrives (see snapToLockWhenReady()).
            await startBioSource()
            guard running, !Task.isCancelled else { return }
            // Let the body continuously modulate the polyphonic timbre at 10 Hz
            // between re-seeds — the sound hugs the live heartbeat/HRV in realtime
            // instead of staying static until the next ~6 s recompose.
            synth.bioModulationEnabled = true
            generate()              // immediate first sound — no lock-wait stall
            startEvolving()
            snapToLockWhenReady()   // non-blocking re-seed once the heartbeat locks
        }
    }

    /// Non-blocking watcher: poll for the first rPPG pulse lock, then recompose ONCE
    /// from the real heartbeat. This preserves "seed from the live body" without ever
    /// delaying the first sound. Times out quietly if no finger is on the lens.
    private func snapToLockWhenReady() {
        #if canImport(AVFoundation)
        lockSnapTask?.cancel()
        lockSnapTask = Task { @MainActor in
            let start = Date()
            while !cameraRPPG.isLocked {
                guard running, !Task.isCancelled else { return }
                if Date().timeIntervalSince(start) > 8 { return }   // no lock → keep current take
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard running, !Task.isCancelled else { return }
            EchoelCrashLog.breadcrumb("rPPG locked → snap re-seed bpm=\(Int(cameraRPPG.detectedBPM))")
            scheduleGenerate(auto: true)   // re-seed (rate-limited; coalesces with the evolve tick)
        }
        #endif
    }

    private func stopEverything() {
        running = false
        startTask?.cancel(); startTask = nil
        evolveTask?.cancel(); evolveTask = nil
        regenTask?.cancel(); regenTask = nil
        lockSnapTask?.cancel(); lockSnapTask = nil
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
        // Returns as soon as the camera is publishing — NO lock-wait here. Sound
        // starts immediately (composed from neutral defaults if no pulse yet) and
        // snapToLockWhenReady() re-seeds from the real heartbeat the moment it locks.
        #else
        // No camera on this platform and no synthetic demo source — the composer
        // falls back to neutral physiological defaults so the instrument still plays.
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
                // Re-seed roughly every ~2 bars at the current tempo (not a flat 12 s)
                // so the music keeps hugging the live body and feels far less loop-y.
                // Clamped 4…8 s so it never churns too fast or drifts too static.
                let beats = 8.0  // two 4/4 bars
                let barSpan = min(8.0, max(4.0, beats * 60.0 / max(40.0, beatPlayer.pattern.tempo)))
                try? await Task.sleep(for: .seconds(barSpan))
                guard running, !Task.isCancelled else { break }
                scheduleGenerate(auto: true)   // rate-limited — coalesces with any lock-snap/onChange recompose
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
        lastSeedAt = Date()   // floor for the next automatic re-seed (anti-flood invariant)
        // Compose from a USABLE frame, judged per source: a lifted finger or dropped
        // strap (camera/BLE) expires in seconds, but Apple Watch / HealthKit HR is
        // latent and sporadic, so a resting reading from up to ~90 s ago still counts
        // as the live body (otherwise the wrist never drives the music). A truly
        // stalled source still expires → neutral physiological defaults.
        let frame = bus.usableBio()
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
        // Dynamic depth from the body (was a flat 0.5, which left velocity dead):
        // a calm, coherent state breathes fuller/louder, an aroused one lighter, so
        // dynamics actually track the live signal instead of sitting constant.
        // A coherence of exactly 0 means "no coherence data" — HealthKit never
        // measures it, and the camera path reports 0 until enough beats accrue. The
        // composer reads coherence as calmness, so a literal 0 would be misread as
        // "maximally incoherent" and pin the arrangement to a sparse, frozen take
        // (the 8-min "stuck at 6 notes" after a pulse episode). Treat 0 as neutral.
        let rawCoh = fin(frame?.coherence, 0.5)
        let liveCoh = rawCoh > 0 ? rawCoh : 0.5
        let dynamicDepth = min(1, max(0.2, 0.3 + 0.5 * liveCoh))
        let input = BioComposer.Input(
            heartRateBPM: fin(frame?.heartRateBPM, 70),
            hrvNormalized: fin(frame?.hrvNormalized, 0.5),
            coherence: liveCoh,
            breathPhase: fin(frame?.breathPhase, 0),
            breathDepth: dynamicDepth,
            key: key,
            style: style,
            mode: .flowFree,          // tempo always follows the body
            lockedTempo: 90,
            mood: mood,
            seed: evolvingSeed
        )
        let composition = BioComposer.compose(input)
        // Honor the user's Kammerton (concert pitch) + live timbre on the next notes.
        synth.setTuning(a4Hz: session.a4Hz)
        subBass.setTuning(a4Hz: session.a4Hz)
        synth.apply(currentPatch)
        // Locked tempo wins for tight loops; otherwise the body sets the pace.
        let tempo = lockBPM ? min(max(lockedBPM, 40), 240) : composition.suggestedTempo
        fxCharacter.apply(to: synth.fxChain, bpm: tempo, genre: style)
        applyDelaySync(bpm: tempo)   // keep the user's delay note value across re-seeds
        // Global transpose: shift every generated pitch by the user's semitones at the
        // single point where all notes exist as one array (main actor, not the audio
        // thread). The sub-bass follows automatically — it derives from note.pitch-12
        // in the trigger — so synth + sub stay locked an octave apart. Clamp to MIDI.
        let semis = Int(transposeSemitones.rounded())
        let notes: [Note] = semis == 0 ? composition.notes : composition.notes.map {
            var n = $0; n.pitch = min(127, max(0, n.pitch + semis)); return n
        }
        // While the transport is already playing (live evolution), stage the new
        // notes and swap them in at the next loop boundary so a held note is never
        // cut mid-bar (no click). On the first generate (not yet playing) load now
        // so notes are present before playback starts.
        if running, beatPlayer.pattern.isPlaying {
            pianoRoll.loadAtBoundary(notes)
        } else {
            pianoRoll.load(notes)
        }
        // Drum-free: clear every cell; the transport only clocks the melody.
        let silentDrums = composition.drumSteps.map { $0.map { _ in false } }
        beatPlayer.pattern.load(steps: silentDrums, accents: silentDrums)
        beatPlayer.pattern.setTempo(tempo)
        session.adopt(key: key)
        lastNoteCount = composition.notes.count
        // EchoelAI narrates the live bio→sound mapping in plain technical English.
        if let frame { aiExplanation = BioExplanation.text(for: frame, tempo: tempo) }
        if !beatPlayer.pattern.isPlaying { beatPlayer.pattern.play() }
        EchoelCrashLog.breadcrumb("generate: \(composition.notes.count) notes, playing")
    }

    /// Apply the live timbre (`currentPatch`) to the running synth without
    /// recomposing. Safe to call at any time; the audio thread fans the patch
    /// across every voice in its render drain.
    private func applySoundLive() {
        synth.apply(currentPatch)
    }

    /// Impose the global Pluck↔Pad articulation onto the envelope of whatever
    /// character is loaded, then push it live. 0 = pad (slow swell, sustained),
    /// 1 = pluck (struck, short, dies away). Time params interpolate exponentially
    /// (musical). Because the per-note velocity sensitivity is derived from the
    /// attack time in the synth, a pluckier setting is automatically more touch-
    /// responsive — the click-safe 3 ms onset floor keeps even the snappiest hit
    /// free of knacksen.
    private func applyArticulation() {
        let p = Float(min(1, max(0, articulation)))
        currentPatch.attack  = 0.005 * pow(120, 1 - p)   // 0.005 s (pluck) → 0.6 s (pad)
        currentPatch.decay   = 0.25 + (1 - p) * 1.0      // 0.25 s (pluck) → 1.25 s (pad)
        currentPatch.sustain = 0.8 * (1 - p)             // 0.0 (pluck) → 0.8 (pad)
        currentPatch.release = 0.4 + (1 - p) * 2.0       // 0.4 s (pluck) → 2.4 s (pad)
        applySoundLive()
    }

    // MARK: - Export / projects

    private func exportWav() async {
        if let url = await exporter.exportWav(engine: audioEngine, beatPlayer: beatPlayer, bars: loopBars.rawValue) {
            share = ExportedFile(url: url)
        }
        // Always return to idle: a failed/empty export must never leave the button
        // stuck on "Recording…/Writing…" (a "hanging button"). On success the URL is
        // already captured above, so resetting the status here is safe.
        exporter.reset()
    }

    /// Retroactive "keep that" — export the last few bars already heard, no replay.
    private func keepLastLoop() async {
        if let url = await exporter.exportRecentLoop(engine: audioEngine, beatPlayer: beatPlayer, bars: loopBars.rawValue) {
            share = ExportedFile(url: url)
        }
        exporter.reset()
    }

    /// Export the generated melody as a standard MIDI file (in-key notes, real
    /// tempo) so it opens with pitch + timing in any DAW. Engine already exists
    /// (MIDIFileExporter); this writes it to a temp file and opens the share sheet.
    private func exportMIDI() {
        guard !pianoRoll.notes.isEmpty else { return }
        let data = MIDIFileExporter.export(notes: pianoRoll.notes, tempo: beatPlayer.pattern.tempo)
        let stem = session.sessionName(bpm: beatPlayer.pattern.tempo)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(stem).mid")
        do {
            try data.write(to: url, options: .atomic)
            share = ExportedFile(url: url)
        } catch {
            EchoelCrashLog.breadcrumb("MIDI export failed: \(error.localizedDescription)")
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
        subBass.setTuning(a4Hz: p.a4Hz)
        synth.apply(p.patch)
        fxCharacter.apply(to: synth.fxChain, bpm: p.bpm, genre: p.style)
        pianoRoll.load(p.notes)
        beatPlayer.pattern.load(steps: p.drumSteps, accents: p.drumAccents)
        beatPlayer.pattern.setTempo(p.bpm)
        lastNoteCount = p.notes.count
        // Re-push the microtonal retune for the restored root. onChange(of:rootIndex)
        // won't fire if the opened key matches the current one, so do it explicitly
        // — otherwise a non-12-TET system would play against the previous root.
        applyTuning()
    }

    // MARK: - Helpers

}

/// Identifiable wrapper so the share sheet can present an exported file URL.
private struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Identifiable wrapper so `.sheet(item:)` can carry a drum track index.
private struct TrackRef: Identifiable { let id: Int }

/// Identifiable wrapper so the diagnostics sheet can present the log text.
private struct DiagReport: Identifiable {
    let id = UUID()
    let text: String
}

/// App-wide pinch-to-zoom for legibility. Scales the entire interface by driving
/// Dynamic Type (so the bundled Atkinson font, laid out `relativeTo: .body`, and the
/// `@ScaledMetric` widths all grow together). `step < 0` means "follow the system
/// text size"; the first pinch seeds an explicit level from the current system size,
/// then it persists. Pinch is a 2-finger gesture, so it never blocks 1-finger scroll.
private struct StudioZoom: ViewModifier {
    @Binding var step: Int
    @Environment(\.dynamicTypeSize) private var systemSize
    @State private var pinchBase: Int?

    static let ladder: [DynamicTypeSize] = [
        .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
    ]

    private static func systemIndex(_ s: DynamicTypeSize) -> Int {
        ladder.firstIndex(of: s) ?? 0
    }

    func body(content: Content) -> some View {
        Group {
            if step >= 0 {
                content.dynamicTypeSize(Self.ladder[Swift.min(Swift.max(step, 0), Self.ladder.count - 1)])
            } else {
                content   // follow the system text size until the user zooms
            }
        }
        .gesture(
            MagnifyGesture(minimumScaleDelta: 0.05)
                .onChanged { v in
                    if pinchBase == nil { pinchBase = step >= 0 ? step : Self.systemIndex(systemSize) }
                    let base = pinchBase ?? 0
                    // Each ~doubling of the pinch moves a couple of ladder steps.
                    let delta = Int((log2(Swift.max(v.magnification, 0.2)) * 2.5).rounded())
                    step = Swift.min(Swift.max(base + delta, 0), Self.ladder.count - 1)
                }
                .onEnded { _ in pinchBase = nil }
        )
    }
}

#endif
