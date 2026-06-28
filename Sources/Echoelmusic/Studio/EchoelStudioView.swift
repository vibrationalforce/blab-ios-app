#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit   // UIApplication.isIdleTimerDisabled (keep screen awake while projecting)
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(CoreTransferable)
import CoreTransferable

/// Lazy `Transferable` wrapper so `ShareLink` exports a saved session as a
/// portable `.json` document ONLY when the user actually shares it (the JSON is
/// encoded on demand, not on every list render). Shared as `<name>.echoel.json`.
@available(iOS 16.0, *)
struct SharedEchoelProject: Transferable {
    let project: Project
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { shared in
            (try? JSONEncoder().encode(shared.project)) ?? Data()
        }
        .suggestedFileName { shared in
            let safe = shared.project.name
                .replacingOccurrences(of: "/", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(safe.isEmpty ? "Echoel Session" : safe).echoel.json"
        }
    }
}
#endif

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
    @Environment(AUv3Host.self) private var auHost
    @Environment(PolySynthVoice.self) private var synth
    @Environment(SubBassVoice.self) private var subBass
    @Environment(MetronomeVoice.self) private var metronome
    @Environment(SessionContext.self) private var session
    @Environment(LoopExporter.self) private var exporter
    @Environment(ProjectStore.self) private var projects
    @Environment(PatchStore.self) private var patchStore
    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif

    // The single live-state flag: biofeedback running or not.
    @State private var running = false

    /// Drives Siri/Shortcuts intent consumption (start/stop/keep loop) when the
    /// app becomes active after an intent opens it.
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    #if canImport(HealthKit)
    @Environment(HealthKitWriter.self) private var healthWriter
    #if canImport(CoreHaptics)
    @Environment(HapticController.self) private var haptics
    #endif
    #endif

    // The live, fully-editable timbre is `currentPatch` (single source of truth).
    // Every control below — XY pad, sliders and 2-decimal numeric fields — reads and
    // writes its fields directly, so any value can be dialed OR typed exactly.

    // Optional locked tempo for tight, DAW-ready loops. When off, the tempo follows
    // the body (flowFree); when on, the loop runs at exactly `lockedBPM`.
    @AppStorage("studio.lockBPM") private var lockBPM = false
    @AppStorage("studio.lockedBPM") private var lockedBPM: Double = 70
    /// Tap-tempo estimator (performance staple) + the last value it produced for display.
    @State private var tapTempo = TapTempo()
    @State private var lastTappedBPM: Double? = nil

    // Collapsible control-panel state ("aufklappen") + timbre preset.
    @State private var showComposition = true
    @State private var showMood = false
    @State private var showSound = true
    @State private var showEffects = false
    @State private var showMaster = false
    /// Delivery loudness target (shared key with MasterLoudnessGrid's colour-coding).
    @AppStorage("studio.loudnessTarget") private var loudnessTargetRaw = LoudnessTarget.streaming.rawValue
    /// Immersive visual mode: the spectrum→visible donut visual (default) vs the bio rings.
    @AppStorage("visual.spectralDonuts") private var spectralDonuts = true
    /// MetalBioView style when NOT in donut mode: 0 rings · 1 Chladni · 2 plasma · 3 water · 4 Prism.
    @AppStorage("visual.style") private var visualStyle = 0
    /// Secondary style to blend with `visualStyle` (same index space). 0 rings · 1 Chladni · 2 plasma · 3 water · 4 Prism.
    @AppStorage("visual.styleB") private var visualStyleB = 0
    /// Mix ratio A↔B [0…1]: 0 = pure primary look, 1 = pure blend look. The "mischend" control.
    @AppStorage("visual.blend") private var visualBlend = 0.0

    /// User-chosen tempo-synced delay note value ("studio calculator in the FX"),
    /// re-applied after genre/character FX so the pick is never clobbered.
    @State private var delaySync = TempoSyncOption(.eighth, .dotted)

    /// Continuous mood/character controls that shape the composition (blend with bio).
    @State private var mood = MoodProfile()
    /// Saved/curated moods (factory + user + community), same library pattern as FX/sound.
    @State private var moodStore = MoodPresetStore()
    /// Identity of the currently-loaded mood (nil = an unsaved "Custom" edit).
    @State private var moodPresetID: UUID? = nil
    @State private var moodPresetName = "Custom"
    @State private var showSaveMoodAs = false
    @State private var moodAsName = ""
    @State private var showSavePatchAs = false
    @State private var patchSaveName = ""
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
    /// Selected Cousto planetary tone ("" = off). Sets the Kammerton so the instrument
    /// plays in tune with the planet's tone. Creative tuning — astronomy, no claims.
    @AppStorage("planet.tone") private var planetID = ""
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
    /// Raised 3.5 → 6 s (device-log feedback): lets a take settle into a phrase and
    /// makes overlapping auto triggers (lock-snap + evolve) collapse into one re-seed.
    private let minAutoSeedGap: TimeInterval = 6.0

    // Sheets / dialogs
    @State private var showOpen = false
    @State private var showSaveDialog = false
    @State private var saveName = ""
    @State private var share: ExportedFile?
    @State private var diagnostics: DiagReport?
    @State private var showAcknowledgments = false

    // Tools — open the (previously unreachable) editors as sheets.
    /// Whether the categorized Tools panel is unfolded. Persisted so it reopens the
    /// way you left it. Default expanded so every editor is visible at a glance.
    @AppStorage("compose.toolsExpanded") private var toolsExpanded = true
    @State private var showPianoRoll = false
    @State private var showInput = false
    @State private var showRouting = false
    @State private var showPlugins = false
    @State private var showLearn = false
    @State private var showBroadcast = false
    @State private var showPatchEditor = false
    @State private var showChannelRack = false
    @State private var showAutomation = false
    @State private var showAudioClip = false
    /// Presents a file picker to import a Standard MIDI File onto the piano roll.
    @State private var midiImportPresented = false
    /// Drives the project-import file picker in the Open-project sheet.
    @State private var projectImportPresented = false
    @State private var showVisual = false
    @State private var showBreath = false
    @State private var showMeditation = false
    @State private var showLiveColabo = false
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
    /// VJ palette: hue rotation [0…1] (0 = physical tone colour) + saturation [0…2].
    @State private var visualHue: Float = 0
    @State private var visualSaturation: Float = 1
    @State private var showVisualSettings = false
    /// VJ control overlay visible over the fullscreen visual (tap canvas to toggle).
    @State private var showVisualControls = true
    /// Bio→Visual routing: the body shapes the immersive visual non-destructively
    /// (base values stay editable; the modulator returns the shaped values to render).
    /// The editor lives in a LAZY sheet (built only when opened) — never in the eager
    /// launch scroll — so it cannot affect launch.
    @State private var visualMod = VisualBioModulator()
    @State private var showBioVisual = false
    /// The reworked, categorized visuals menu (looks by category + Farboktave wheel).
    /// LAZY sheet — built only when opened, never in the eager launch scroll.
    @State private var showVisualMenu = false
    /// Last-picked immersive visual preset (persisted) — a launch point for the
    /// four live sliders below; "" = none/custom after a manual tweak.
    @AppStorage("visual.preset") private var visualPresetID = ""

    private var key: MusicalKey { MusicalKey(root: rootIndex, scale: scale) }

    /// The instrument's current tonic frequency (Hz) at the chosen Kammerton, shifted
    /// by the global transpose — fed to the immersive visual, which transposes it up
    /// into visible light, so the colour tracks key + concert pitch + transpose.
    private var currentToneHz: Double {
        let semis = Double(Int(transposeSemitones.rounded()))
        return session.a4Hz * pow(2.0, (Double(60 + rootIndex) - 69.0 + semis) / 12.0)
    }

    /// Whether the rear camera currently sees a finger/face — drives the strip's
    /// "Cover camera" vs "Reading…" hint. False where there is no camera.
    private var pulseFingerOnLens: Bool {
        #if canImport(AVFoundation)
        return cameraRPPG.fingerDetected
        #else
        return false
        #endif
    }

    // The root screen + ALL its presentations were one ~30-deep modifier chain
    // (lifecycle + 24 .sheet/.fullScreenCover). At launch the Swift runtime decodes
    // that aggregate generic type and, past a threshold, the metadata decoder
    // recurses until it overflows the main-thread stack → SIGSEGV / black screen
    // BEFORE any view renders (build 2068: "Safe Mode oder Black Screen"). The fix is
    // to split the chain into AnyView-bounded groups so each view's static type stays
    // shallow — the decoder stops at each AnyView boundary. screenBase → screenSheets1
    // → screenSheets2 → body, each adding a handful of modifiers on a shallow base.
    private var screenBase: AnyView {
        AnyView(
        VStack(spacing: 0) {
            BioStripView(measuring: running,
                         fingerOnLens: pulseFingerOnLens,
                         onStartPulse: { startBiofeedback() })
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Type-erased on purpose: `body` had grown into a single, very
                    // deeply-nested generic type (each `some View` panel expands its
                    // whole sub-tree into the parent's type metadata). At launch the
                    // Swift runtime decodes that type and, past a threshold, the
                    // metadata decoder recurses until it overflows the main-thread
                    // stack → SIGSEGV in the Stack Guard region (a compile-clean crash
                    // we hit on 10.76.3 / build 2037). AnyView puts a concrete,
                    // non-generic boundary at each heavy branch so the decoder never
                    // recurses into the sub-tree. The cost is negligible here (these
                    // are page-level containers, not tight-loop rows).
                    AnyView(startButton)
                    AnyView(nonStandardTuningBanner)
                    #if canImport(AVFoundation)
                    if running { AnyView(measurementControl) }
                    #endif
                    AnyView(soundControls)
                    AnyView(utilityRow)
                    AnyView(toolsSection)
                }
                .padding(16)
            }
            AnyView(quickAccessHUD)
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
            // Restore the last-picked immersive visual look so an installation /
            // performance setup survives relaunch (the live params aren't persisted
            // individually, but the chosen scene is).
            if !visualPresetID.isEmpty,
               let p = VisualPreset.factory.first(where: { $0.id == visualPresetID }) {
                applyVisualPreset(p)
            }
            surfacePriorCrashIfAny()
            handlePendingIntent()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { handlePendingIntent(); updateKeepAwake() }
        }
        // Keep the screen awake while performing or projecting — an installation, a
        // projected immersive visual, or a hands-off guided session must NOT auto-lock
        // mid-show. Recomputed from the combined state so any one toggle is correct;
        // re-enabled (battery) the moment nothing needs it.
        .onChange(of: running) { _, _ in updateKeepAwake() }
        .onChange(of: showVisual) { _, _ in updateKeepAwake() }
        .onChange(of: showBreath) { _, _ in updateKeepAwake() }
        .onChange(of: showMeditation) { _, _ in updateKeepAwake() }
        .onDisappear { stopEverything(); disableKeepAwake() }
        )
    }

    /// First presentation group, stacked on the type-erased `screenBase`. Splitting
    /// the presentations across AnyView boundaries is what keeps the launch-time
    /// metadata decode from overflowing (see `screenBase`).
    private var screenSheets1: AnyView {
        AnyView(
        screenBase
        // Sheet/cover contents are AnyView-erased too — same reason as the scroll
        // content above: keep the root view's aggregate generic type shallow so the
        // launch-time metadata decode can never overflow the stack again.
        .sheet(isPresented: $showOpen) { AnyView(openSheet) }
        .sheet(item: $share) { AnyView(ShareSheet(url: $0.url)) }
        .sheet(item: $diagnostics) { report in AnyView(diagnosticsSheet(report.text)) }
        .sheet(isPresented: $showAcknowledgments) { AnyView(acknowledgmentsSheet) }
        .sheet(isPresented: $showBioVisual) { AnyView(BioVisualEditorView(modulator: visualMod).echoelSheetPanel()) }
        .sheet(isPresented: $showVisualMenu) { AnyView(VisualMenuView(spectralDonuts: $spectralDonuts, visualStyle: $visualStyle, liveToneHz: Double(currentToneHz)).echoelSheetPanel()) }
        .sheet(isPresented: $showPianoRoll) {
            AnyView(PianoRollView(pattern: beatPlayer.pattern, model: pianoRoll).echoelSheetPanel())
        }
        .sheet(isPresented: $showAllFX) {
            AnyView(EchoelFXView(chain: synth.fxChain, bpm: currentTempo,
                         fxEnabled: { synth.isFXEnabled },
                         setFXEnabled: { synth.setFXEnabled($0) })
                .echoelSheetPanel())
        }
        )
    }

    /// Second presentation group, stacked on the type-erased `screenSheets1`.
    private var screenSheets2: AnyView {
        AnyView(
        screenSheets1
        .sheet(isPresented: $showInput) { AnyView(AudioInputPickerView().echoelSheetPanel()) }
        .sheet(isPresented: $showRouting) { AnyView(PatchbayView().echoelSheetPanel()) }
        .sheet(isPresented: $showPlugins) { AnyView(AUv3BrowserView().echoelSheetPanel()) }
        .sheet(isPresented: $showLearn) { AnyView(LearnView()) }   // self-manages its detents
        .sheet(isPresented: $showChannelRack) { AnyView(ChannelRackView().echoelSheetPanel()) }
        .sheet(isPresented: $showAutomation) { AnyView(AutomationView().echoelSheetPanel()) }
        .sheet(isPresented: $showAudioClip) { AnyView(AudioClipView().echoelSheetPanel()) }
        #if canImport(UniformTypeIdentifiers)
        .fileImporter(isPresented: $midiImportPresented,
                      allowedContentTypes: [.midi],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { importMIDI(url) }
        }
        #endif
        )
    }

    var body: some View {
        screenSheets2
        .sheet(isPresented: $showBroadcast) { AnyView(BroadcastView().echoelSheetPanel()) }
        .sheet(item: $sampleBrowserTrack) { ref in AnyView(SampleBrowserView(track: ref.id).echoelSheetPanel()) }
        .sheet(isPresented: $showPatchEditor) {
            AnyView(PatchEditorView(initial: currentPatch) { p in
                currentPatch = p
                synth.apply(p)   // editor changes hit the live voice immediately
            }
            .echoelSheetPanel())
        }
        #if canImport(MetalKit) && canImport(UIKit)
        .fullScreenCover(isPresented: $showVisual) {
            // NOT AnyView-wrapped: this cover builds lazily on present (it never
            // contributed to the launch-time metadata overflow), and wrapping the live
            // MTKView in AnyView defeats SwiftUI identity → the view can be torn down
            // and recreated, which shows as a stutter. Keep the concrete type here.
            ZStack(alignment: .topTrailing) {
                if spectralDonuts {
                    // The spectrum→visible-light donut visual: one ring per frequency
                    // band, thickness ∝ loudness, colour = band frequency → visible.
                    SpectralDonutView(reduceMotion: reduceMotion,
                                      bandCount: max(8, Int(visualDetail))).ignoresSafeArea()
                } else {
                    // Bio→Visual: the body shapes the user's BASE params non-destructively.
                    // Reading bus.latestBio + visualMod.routes here tracks them, so the
                    // cover re-renders as the body changes; MetalBioView eases between
                    // updates. No-op (returns base) when no routes are enabled.
                    let eff = effectiveVisualParams()
                    MetalBioView(reduceMotion: reduceMotion, toneHz: currentToneHz,
                                 intensity: eff.intensity, ringDensity: eff.detail,
                                 motion: eff.motion, spread: eff.spread,
                                 hueShift: eff.hue, saturation: eff.saturation,
                                 style: visualStyle, styleB: visualStyleB,
                                 blend: eff.blend).ignoresSafeArea()
                }
                // Tap the canvas to hide/show the VJ control PANEL — clean for
                // projection, hands-on for performance. Controls are a solid panel.
                Color.clear.contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { showVisualControls.toggle() } }
                if showVisualControls {
                    visualVJOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // ALWAYS-ON top bar — drawn LAST so it is never covered by the panel.
                // fullScreenCover has no swipe-to-dismiss, so a persistent Close is the
                // only guaranteed escape (device feedback: the view trapped the user and
                // forced an app kill). Kept subtle for clean projection output.
                HStack(spacing: 14) {
                    // Persistent, VISIBLE controls handle — replaces the undiscoverable
                    // "tap the canvas" reveal (WCAG 2.2: don't gate controls behind a
                    // hidden gesture). The panel still toggles, but the affordance to
                    // summon it is always on screen.
                    Button { withAnimation(.easeInOut(duration: 0.15)) { showVisualControls.toggle() } } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title2).foregroundStyle(.white.opacity(showVisualControls ? 0.85 : 0.5))
                    }
                    .accessibilityLabel(showVisualControls ? "Hide visual controls" : "Show visual controls")
                    Button { spectralDonuts.toggle() } label: {
                        Image(systemName: spectralDonuts ? "circle.hexagongrid.fill" : "circle.circle")
                            .font(.title2).foregroundStyle(.white.opacity(0.6))
                    }
                    .accessibilityLabel(spectralDonuts ? "Switch to bio rings" : "Switch to spectrum donuts")
                    Button { showVisual = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2).foregroundStyle(.white.opacity(0.85))
                    }
                    .accessibilityLabel("Close visual")
                }
                .padding()
            }
            .statusBarHidden(true)
        }
        #endif
        .fullScreenCover(isPresented: $showBreath) { BreathGuideView() }
        .fullScreenCover(isPresented: $showMeditation) { MeditationView() }
        #if canImport(MultipeerConnectivity)
        .sheet(isPresented: $showLiveColabo) {
            AnyView(LiveColaboView(currentSession: { currentProject(named: "Shared session") },
                           onLoadShared: { open($0) })
                .echoelSheetPanel())
        }
        #endif
        .alert("Save project", isPresented: $showSaveDialog) {
            TextField("Name", text: $saveName)
            Button("Save") { saveProject() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current sound, key, tempo and generated loop.")
        }
        .alert("Save mood", isPresented: $showSaveMoodAs) {
            TextField("Name", text: $moodAsName)
            Button("Save") {
                let name = moodAsName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let saved = moodStore.saveAs(moodSnapshot(name: name), name: name)
                moodPresetID = saved.id
                moodPresetName = saved.name
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the 8 mood dimensions as a named mood you can recall.")
        }
        .alert("Save sound", isPresented: $showSavePatchAs) {
            TextField("Name", text: $patchSaveName)
            Button("Save") {
                let name = patchSaveName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let saved = patchStore.saveAs(currentPatch, name: name)
                currentPatch = saved
                presetIndex = -1
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current timbre as a named sound you can recall.")
        }
    }

    // MARK: - Tools (deep editors)

    /// The deeper editors, grouped into a CLEAR, collapsible panel (founder: "besser
    /// strukturiert, übersichtlicher … sich aufklappen lässt"). A header with a
    /// chevron unfolds/folds the whole set; inside, tools are grouped by purpose
    /// (Editors · Audio & Bio · Connect · Visual & Learn) in wrapping grids so every
    /// tool is visible at a glance instead of hidden off the side of a scroll row.
    /// Clips + Arrangement live on the workspace's bottom surface bar, so they are
    /// not duplicated here — a name means ONE thing.
    private var toolsSection: some View {
        @Bindable var midiOut = midiOut
        #if canImport(HealthKit)
        @Bindable var healthWriter = healthWriter
        #endif
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { toolsExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver").font(.system(size: 13))
                    Text("Tools").font(EchoelTheme.font(13, .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: toolsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(EchoelTheme.dim)
                }
                .foregroundStyle(EchoelTheme.text)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(toolsExpanded ? "Collapse tools" : "Expand tools")
            .accessibilityAddTraits(.isButton)

            if toolsExpanded {
                toolGroup("Editors") {
                    gridChip("Piano Roll", "pianokeys") { showPianoRoll = true }
                    gridChip("Sound", "dial.medium") { showPatchEditor = true }
                    Menu {
                        ForEach(Array(BeatPlayer.trackNames.enumerated()), id: \.offset) { idx, name in
                            Button(name) { sampleBrowserTrack = TrackRef(id: idx) }
                        }
                    } label: { gridChipLabel("Drum Samples", "waveform") }
                    gridChip("Channels", "slider.vertical.3") { showChannelRack = true }
                    gridChip("Automation", "point.topleft.down.curvedto.point.bottomright.up") { showAutomation = true }
                    #if canImport(UniformTypeIdentifiers)
                    gridChip("Import MIDI", "square.and.arrow.down") { midiImportPresented = true }
                    #endif
                }
                toolGroup("Audio & Bio") {
                    gridChip("Audio In", "mic") { showInput = true }
                    gridChip("Audio Clip", "waveform") { showAudioClip = true }
                    gridChip("Breathing", "wind") { showBreath = true }
                    gridChip("Meditation", "figure.mind.and.body") { showMeditation = true }
                }
                toolGroup("Connect") {
                    gridChip("Routing", "point.3.connected.trianglepath.dotted") { showRouting = true }
                    gridChip("Plugins", "puzzlepiece.extension") { showPlugins = true }
                    gridChip("Broadcast", "dot.radiowaves.left.and.right") { showBroadcast = true }
                    #if canImport(MultipeerConnectivity)
                    gridChip("Live Colabo", "person.2.wave.2") { showLiveColabo = true }
                    #endif
                    Menu {
                        // Live MIDI / MPE OUT — the body's take streams to a virtual
                        // "Echoelmusic" source any DAW can record. Off by default.
                        Toggle(isOn: $midiOut.enabled) { Label("MIDI Out (live)", systemImage: "pianokeys.inverse") }
                        Toggle(isOn: $midiOut.mpeEnabled) { Label("MPE (per-note channels)", systemImage: "waveform.path") }
                            .disabled(!midiOut.enabled)
                        // Stream the body's live 5D expression (Glide/Slide/Press) per
                        // note — the ROLI-Seaboard-style multidimensional take out to any
                        // MPE rig. Needs MPE on; off by default.
                        Toggle(isOn: $midiOut.expressionEnabled) { Label("5D Expression (body)", systemImage: "hand.draw") }
                            .disabled(!midiOut.enabled || !midiOut.mpeEnabled)
                        #if canImport(HealthKit)
                        // Opt-in: write the HR / respiratory rate Echoel measures (camera rPPG /
                        // BLE) into Apple Health. Off by default; never writes HRV.
                        Toggle(isOn: $healthWriter.enabled) { Label("Save to Apple Health", systemImage: "heart.text.square") }
                        #endif
                    } label: { gridChipLabel("MIDI / Health", "pianokeys.inverse") }
                }
                toolGroup("Visual & Learn") {
                    #if canImport(MetalKit) && canImport(UIKit)
                    gridChip("Visual", "sparkles") { showVisual = true }
                    #endif
                    gridChip("Learn", "book") { showLearn = true }
                }
                Text("Echoel \(Self.appVersionString)")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            }
        }
    }

    /// A titled group of tool chips in a wrapping 2-column grid (everything visible,
    /// no horizontal hiding). Plain title (no eyebrow/uppercase per Uncodixfy).
    private func toolGroup<Content: View>(_ title: String,
                                          @ViewBuilder _ chips: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)], spacing: 8) {
                chips()
            }
        }
    }

    /// A full-width tool chip (fills its grid cell, left-aligned) opening an editor.
    private func gridChip(_ title: String, _ systemImage: String,
                          _ action: @escaping () -> Void) -> some View {
        Button(action: action) { gridChipLabel(title, systemImage) }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
    }

    /// The chip label content — shared by plain-button and Menu-label chips.
    private func gridChipLabel(_ title: String, _ systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 13))
            Text(title).font(EchoelTheme.font(12, .semibold)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(EchoelTheme.text)
        .padding(.horizontal, 12).frame(height: 40)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    // MARK: - The one button

    /// Persistent quick-access HUD pinned to the bottom edge — every key destination
    /// reachable from ANYWHERE without scrolling (the tools otherwise live at the
    /// bottom of the scroll). Evidence-grounded: edge-anchored thumb zone (Fitts),
    /// visible permanent affordances not hidden gestures (WCAG 2.2), non-modal. Solid
    /// semi-transparent fill + 1px border (Uncodixfy — no glass/blur).
    private var quickAccessHUD: some View {
        HStack(spacing: 10) {
            hudButton(running ? "Stop" : "Play", running ? "stop.fill" : "play.fill",
                      tint: running ? EchoelTheme.text : EchoelTheme.accent) { toggleBiofeedback() }
            #if canImport(MetalKit) && canImport(UIKit)
            hudButton("Visual", "sparkles") { showVisual = true }
            #endif
            Menu {
                Section("Editors") {
                    hudButtonLabelMenu("Piano Roll", "pianokeys") { showPianoRoll = true }
                    hudButtonLabelMenu("Sound", "dial.medium") { showPatchEditor = true }
                    hudButtonLabelMenu("Channels", "slider.vertical.3") { showChannelRack = true }
                    hudButtonLabelMenu("Automation", "point.topleft.down.curvedto.point.bottomright.up") { showAutomation = true }
                }
                Section("Audio & Bio") {
                    hudButtonLabelMenu("Audio In", "mic") { showInput = true }
                    hudButtonLabelMenu("Audio Clip", "waveform") { showAudioClip = true }
                    hudButtonLabelMenu("Breathing", "wind") { showBreath = true }
                    hudButtonLabelMenu("Meditation", "figure.mind.and.body") { showMeditation = true }
                }
                Section("Connect") {
                    hudButtonLabelMenu("Routing", "point.3.connected.trianglepath.dotted") { showRouting = true }
                    hudButtonLabelMenu("Plugins", "puzzlepiece.extension") { showPlugins = true }
                    hudButtonLabelMenu("Broadcast", "dot.radiowaves.left.and.right") { showBroadcast = true }
                    hudButtonLabelMenu("Learn", "book") { showLearn = true }
                }
            } label: {
                hudLabel("Tools", "square.grid.2x2")
            }
            .accessibilityLabel("Tools — open any editor from anywhere")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(EchoelTheme.bg.opacity(0.92))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(EchoelTheme.border), alignment: .top)
    }

    private func hudButton(_ title: String, _ icon: String,
                           tint: Color = EchoelTheme.text, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { hudLabel(title, icon).foregroundStyle(tint) }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(title)
    }

    private func hudLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 17))
            Text(title).font(EchoelTheme.font(10, .medium))
        }
        .foregroundStyle(EchoelTheme.text)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }

    private func hudButtonLabelMenu(_ title: String, _ icon: String,
                                    _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon) }
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

    /// Unmissable, on the hero path: when a non-standard tone system is active it
    /// retunes EVERY generated note (e.g. just intonation reads 15–30¢ flat), which
    /// sounds "off" to an ear expecting standard pitch. The setting is persisted, so
    /// without this it can silently colour every session. One tap returns to 12-TET.
    /// Hidden entirely at 12-TET (the default) so it never adds chrome in normal use.
    @ViewBuilder private var nonStandardTuningBanner: some View {
        if tuningID != "edo12" {
            HStack(spacing: 10) {
                Image(systemName: "tuningfork")
                    .foregroundStyle(EchoelTheme.dim)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Non-standard tuning: \(TuningSystem.named(tuningID).name)")
                        .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                    Text("Every note is retuned to this system. Sounds off? Return to standard.")
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("12-TET") {
                    tuningID = "edo12"
                    applyTuning()
                    recomposeIfRunning()
                }
                .font(EchoelTheme.font(13, .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(EchoelTheme.text))
                .buttonStyle(.plain)
                .accessibilityHint("Switches to standard 12-tone equal temperament")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .stroke(EchoelTheme.border, lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Sound controls (one morph pad + genre + fine sliders)

    private var soundControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            compositionPanel
            transposePanel
            moodPanel
            soundPanel
            effectsPanel
            masterPanel
            visualPanel
            if running {
                Text(aiExplanation.isEmpty
                     ? "The music is arising from your live signal — every control shapes it as it plays."
                     : aiExplanation)
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .animation(.easeInOut(duration: 0.18), value: aiExplanation)
            }
        }
    }

    // MARK: Panel 1 — Composition (genre · key · tuning · tempo)

    private var compositionPanel: some View {
        panel("Composition", "Genre · key · tuning · tempo", isExpanded: $showComposition) {
            genrePicker
            tonartRow
            kammertonRow
            planetRow
            tuningRow
            tempoRow
        }
    }

    /// Cousto planetary tone — selecting one tunes the Kammerton so the instrument plays
    /// in tune with that planet's tone (e.g. Earth-year → A4 ≈ 432 Hz). Same proven
    /// Picker pattern as the tone-system row. Astronomy-derived creative tuning, no claims.
    private var planetRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            labeledRow("Planet tone") {
                Picker("Planet tone", selection: $planetID) {
                    Text("Off").tag("")
                    ForEach(PlanetTones.all) { p in Text(p.name).tag(p.id) }
                }
                .pickerStyle(.menu).tint(EchoelTheme.text)
                .onChange(of: planetID) { _, id in applyPlanetTone(id) }
                .accessibilityLabel("Planet tone")
            }
            if let p = PlanetTones.named(planetID) {
                Text("Tuned to \(p.name): A4 ≈ \(String(format: "%.1f", p.a4Hz)) Hz (root note \(p.nearestNoteName)). Astronomy-derived creative tuning.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Apply a planet tone by setting the Kammerton (same path as the Kammerton field).
    /// "Off" (empty id) leaves the current concert pitch untouched.
    private func applyPlanetTone(_ id: String) {
        guard let p = PlanetTones.named(id) else { return }
        session.a4Hz = p.a4Hz
        synth.setTuning(a4Hz: session.a4Hz)
        subBass.setTuning(a4Hz: session.a4Hz)
        recomposeIfRunning()
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
            .onChange(of: lockBPM) { _, on in
                // Enabling the lock ADOPTS the body's current tempo instead of
                // snapping to a stale value — so the take (and the tempo-driven
                // immersive circles) stay continuous through the toggle. Falls back
                // to the existing lockedBPM when no fresh bio frame is available.
                if on, let hr = bus.freshBio()?.heartRateBPM, hr >= 40, hr <= 240 {
                    lockedBPM = (Double(hr) * 10).rounded() / 10
                    if running { beatPlayer.pattern.setTempo(lockedBPM); metronome.bpm = lockedBPM }
                }
                recomposeIfRunning()
            }
            .accessibilityHint("When on, the loop locks to your current heart-rate tempo for tight loops")

            if lockBPM {
                EchoelValueField(label: "Tempo", value: $lockedBPM, range: 40...240, unit: "BPM",
                                 onChange: { if running { beatPlayer.pattern.setTempo(lockedBPM); metronome.bpm = lockedBPM } },
                                 onCommit: { recomposeIfRunning() })
            }

            tapTempoRow
            metronomeRow
            #if canImport(CoreHaptics)
            hapticsRow
            #endif
        }
    }

    /// Steady click track — a production/performance metronome. Self-driving so it
    /// stays in time even when nothing is playing (practice click); when the take
    /// starts it re-aligns to the downbeat. Silent until armed.
    private var metronomeRow: some View {
        @Bindable var metronome = metronome
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $metronome.enabled) {
                Text("Metronome (click)").font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
            }
            .tint(EchoelTheme.accent)
            .onChange(of: metronome.enabled) { _, on in if on { metronome.bpm = currentTempo } }
            .accessibilityHint("A steady click at the current tempo to play in time")

            if metronome.enabled {
                EchoelValueField(label: "Beats per bar", value: Binding(
                    get: { Double(metronome.beatsPerBar) },
                    set: { metronome.beatsPerBar = Int($0.rounded()) }),
                    range: 1...12, unit: "", decimals: 0)
                EchoelValueField(label: "Click level", value: Binding(
                    get: { Double(metronome.level) },
                    set: { metronome.level = Float($0) }),
                    range: 0...1, unit: "", decimals: 2)
            }
        }
    }

    #if canImport(CoreHaptics)
    /// Eyes-free transport pulse — the body feels each quarter-note (down-beat
    /// strongest) so a performer can hold time without watching the screen. Off
    /// until armed, exactly like the click.
    @ViewBuilder private var hapticsRow: some View {
        @Bindable var haptics = haptics
        Toggle(isOn: $haptics.isEnabled) {
            Text("Haptic beat (feel)").font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
        }
        .tint(EchoelTheme.accent)
        .accessibilityHint("Pulses the phone on each quarter-note so you can keep time eyes-free")
    }
    #endif

    /// Tap a tempo in time — the classic performance way to dial BPM by feel. Tapping
    /// locks the BPM (so the take holds it) and steers the click; a long pause resets.
    private var tapTempoRow: some View {
        HStack(spacing: 12) {
            Button {
                if let bpm = tapTempo.tap(at: ProcessInfo.processInfo.systemUptime) {
                    lastTappedBPM = bpm
                    lockBPM = true
                    lockedBPM = (bpm * 10).rounded() / 10
                    metronome.bpm = lockedBPM
                    if running { beatPlayer.pattern.setTempo(lockedBPM) }
                }
            } label: {
                Label("Tap tempo", systemImage: "hand.tap")
                    .font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Tap in time to set the tempo")

            if let tapped = lastTappedBPM {
                Text("\(Int(tapped.rounded())) BPM")
                    .font(EchoelTheme.font(13).monospacedDigit()).foregroundStyle(EchoelTheme.dim)
                    .frame(width: 84, alignment: .trailing)
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

    // MARK: Panel — Master (output level + EBU R128 loudness)

    /// The mastering readout — master volume plus the live EBU R128 loudness of the
    /// output (short-term + gated-integrated LUFS, max true-peak in dBTP, loudness
    /// range in LU). These numbers are what producers and broadcasters master to;
    /// they were already computed on the master tap but never shown. Reset clears the
    /// integration + peak hold to start a fresh measurement.
    private var masterPanel: some View {
        panel("Master", "Output level · EBU R128 loudness", isExpanded: $showMaster) {
            EchoelValueField(label: "Master volume", value: Binding(
                get: { Double(audioEngine.masterVolume) },
                set: { audioEngine.masterVolume = Float($0) }),
                range: 0...1, unit: "", decimals: 2)

            labeledRow("Target") {
                Picker("Target", selection: $loudnessTargetRaw) {
                    ForEach(LoudnessTarget.allCases) { t in Text(t.displayName).tag(t.rawValue) }
                }
                .pickerStyle(.menu).tint(EchoelTheme.text)
                .accessibilityLabel("Loudness delivery target")
            }

            // The live numbers live in their own view so the 60 Hz meter refresh
            // re-renders only this small grid, not the whole studio body.
            MasterLoudnessGrid()

            HStack {
                Text("Streaming targets ≈ −14 LUFS integrated, true peak ≤ −1 dBTP.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Reset") { audioEngine.resetMastering() }
                    .font(EchoelTheme.font(12, .medium)).foregroundStyle(EchoelTheme.text)
                    .accessibilityHint("Clear the integrated loudness and peak hold")
            }

            Button { panicAllNotesOff() } label: {
                Label("Silence — all notes off", systemImage: "speaker.slash")
                    .font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Immediately release every sounding note on every voice")
        }
    }

    /// Performance panic — release every sounding note on every voice at once (built-in
    /// poly + sub, any hosted AUv3 instrument, and MIDI out). Kills stuck notes live.
    private func panicAllNotesOff() {
        synth.allNotesOff()
        subBass.allNotesOff()
        auHost.allNotesOff()
        midiOut.allNotesOff()
    }

    // MARK: Panel — Visual (immersive sound→light)

    private var visualPanel: some View {
        panel("Visual", "Immersive sound→light — open from Tools", isExpanded: $showVisualSettings) {
            // Reworked menu: a categorized look browser + the Farboktave (Cousto)
            // reference wheel, opened lazily. Trivial button here so the eager launch
            // scroll stays light; the quick strip below stays for one-tap switching.
            Button { showVisualMenu = true } label: {
                Label("Looks & Farboktave…", systemImage: "paintpalette")
                    .font(EchoelTheme.font(13, .semibold))
                    .foregroundStyle(EchoelTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Browse visual looks by category and the colour-octave wheel")
            Text("Look").font(EchoelTheme.font(10, .medium)).foregroundStyle(EchoelTheme.dim)
            visualLookStrip
            visualBlendControls
            visualPresetRow
            musicColourRow
            EchoelValueField(label: "Intensity", value: $visualIntensity, range: 0...1.5,
                             onChange: { visualPresetID = "" })
            EchoelValueField(label: "Detail", value: $visualDetail, range: 8...90, decimals: 0,
                             onChange: { visualPresetID = "" })
            EchoelValueField(label: "Motion", value: $visualMotion, range: 0...1.5,
                             onChange: { visualPresetID = "" })
            EchoelValueField(label: "Spread", value: $visualSpread, range: 0.5...1.5,
                             onChange: { visualPresetID = "" })
            EchoelValueField(label: "Hue", value: $visualHue, range: 0...1)
            EchoelValueField(label: "Saturation", value: $visualSaturation, range: 0...2)
            Text("Colour defaults to the heard tone transposed into visible light (physically correct); Hue/Saturation rotate the palette for VJ/performance use. Motion is capped so the flash rate always stays under the 3 Hz safety limit.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            // Bio→Visual: opens a LAZY sheet (built only on tap). Just a button here so
            // the eager launch scroll stays trivial — the heavy editor never builds at launch.
            Button { showBioVisual = true } label: {
                Label(visualMod.isActive ? "Bio → Visual (active)" : "Bio → Visual…",
                      systemImage: "waveform.path.ecg")
                    .font(EchoelTheme.font(13, .semibold))
                    .foregroundStyle(visualMod.isActive ? EchoelTheme.accent : EchoelTheme.text)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Let the body shape the immersive visual")
        }
    }

    /// The visual parameters to render: the user's base values shaped non-destructively
    /// by the live body through `visualMod`. Reads `bus.latestBio` (via freshBio) and
    /// `visualMod.routes` so the caller re-renders when either changes. Returns the base
    /// unchanged when no routes are enabled.
    private func effectiveVisualParams() -> VisualParams {
        let base = VisualParams(intensity: visualIntensity, detail: visualDetail,
                                motion: visualMotion, spread: visualSpread,
                                hue: visualHue, saturation: visualSaturation,
                                blend: Float(visualBlend))
        return visualMod.effective(base: base, bio: bus.freshBio())
    }

    /// Named immersive-visual starting points ("von Aura bis Zentrifuge"). Tapping
    /// one loads its look into the four live sliders below (which stay editable for
    /// hands-on play); a manual slider tweak clears the selection back to custom.
    private var visualPresetRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preset").font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VisualPreset.factory) { preset in
                        let selected = visualPresetID == preset.id
                        Button { applyVisualPreset(preset) } label: {
                            Text(preset.name)
                                .font(EchoelTheme.font(12, .medium))
                                .foregroundStyle(selected ? EchoelTheme.onPrimary : EchoelTheme.text)
                                .padding(.horizontal, 12).frame(height: 32)
                                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                                    .fill(selected ? EchoelTheme.accent : EchoelTheme.fill))
                                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
                        }
                        .accessibilityLabel("\(preset.name) visual preset — \(preset.blurb)")
                    }
                }
            }
        }
    }

    /// One LOOK selector for the immersive visual — Donuts (spectrum→light) plus the
    /// three physically/analytically grounded Metal fields (Rings = wave interference,
    /// Chladni = plate eigenmodes from the tone, Plasma = superposed waves). One strip
    /// instead of two scattered toggles (clearer design); persists via @AppStorage.
    private var visualLookStrip: some View {
        // (label, isDonuts, metalStyle)
        let looks: [(String, Bool, Int)] = [
            ("Donuts", true, -1), ("Rings", false, 0), ("Chladni", false, 1),
            ("Plasma", false, 2), ("Water", false, 3), ("Prism", false, 4)
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(looks.indices, id: \.self) { i in
                    let look = looks[i]
                    let selected = look.1 ? spectralDonuts : (!spectralDonuts && visualStyle == look.2)
                    Button {
                        if look.1 { spectralDonuts = true }
                        else { spectralDonuts = false; visualStyle = look.2 }
                    } label: {
                        Text(look.0)
                            .font(EchoelTheme.font(12, .semibold))
                            .foregroundStyle(selected ? EchoelTheme.bg : EchoelTheme.text)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(selected ? EchoelTheme.accent : EchoelTheme.fill))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(look.0) visual look")
                }
            }
        }
    }

    /// The "mischend" controls: a SECOND look to overlap with the primary, plus a Mix
    /// ratio (0 = pure primary, 1 = pure secondary). Only shown for the Metal field
    /// looks (Donuts is a different renderer that can't blend yet — next cycle). Tapping
    /// the already-selected B clears the blend back to pure A (Mix → 0), so the strip
    /// itself is the on/off too.
    @ViewBuilder
    private var visualBlendControls: some View {
        if !spectralDonuts {
            let bLooks: [(String, Int)] = [
                ("Rings", 0), ("Chladni", 1), ("Plasma", 2), ("Water", 3), ("Prism", 4)
            ]
            Text("Blend with").font(EchoelTheme.font(10, .medium)).foregroundStyle(EchoelTheme.dim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(bLooks.indices, id: \.self) { i in
                        let b = bLooks[i]
                        // "Selected" means this B is active AND the mix is actually open.
                        let selected = visualStyleB == b.1 && visualBlend > 0.001
                        Button {
                            if visualStyleB == b.1 && visualBlend > 0.001 {
                                visualBlend = 0            // tap again → back to pure primary
                            } else {
                                visualStyleB = b.1
                                if visualBlend < 0.001 { visualBlend = 0.5 }   // open the mix
                            }
                        } label: {
                            Text(b.0)
                                .font(EchoelTheme.font(12, .semibold))
                                .foregroundStyle(selected ? EchoelTheme.bg : EchoelTheme.text)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(selected ? EchoelTheme.accent : EchoelTheme.fill))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Blend with \(b.0)")
                    }
                }
            }
            EchoelValueField(label: "Mix", value: $visualBlend, range: 0...1)
        }
    }

    #if canImport(MetalKit) && canImport(UIKit)
    /// The hands-on VJ control panel that floats over the fullscreen visual: the four
    /// live parameters + a quick scene strip, on the app-wide value-field vocabulary,
    /// in a solid (non-glass) bottom panel sized for stage use. Tap the canvas to hide.
    private var visualVJOverlay: some View {
        VStack {
            Spacer(minLength: 0)
            // Scrollable + height-capped so the panel stays in the LOWER portion: the
            // top stays canvas + the always-on Close bar, and many params never grow
            // the panel to full height (which previously covered the Close button).
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    // Pick the visual LOOK (engine), then the scene preset (parameters).
                    Text("Look").font(EchoelTheme.font(10, .medium)).foregroundStyle(EchoelTheme.dim)
                    visualLookStrip
                    visualBlendControls
                    // Quick scene strip — launch a look in one tap during a performance.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(VisualPreset.factory) { preset in
                                let selected = visualPresetID == preset.id
                                Button { applyVisualPreset(preset) } label: {
                                    Text(preset.name)
                                        .font(EchoelTheme.font(12, .semibold))
                                        .foregroundStyle(selected ? EchoelTheme.bg : EchoelTheme.text)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(RoundedRectangle(cornerRadius: 8)
                                            .fill(selected ? EchoelTheme.accent : EchoelTheme.fill))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(preset.name) scene")
                            }
                        }
                    }
                    EchoelValueField(label: "Intensity", value: $visualIntensity, range: 0...1.5,
                                     onChange: { visualPresetID = "" })
                    EchoelValueField(label: "Detail", value: $visualDetail, range: 8...90, decimals: 0,
                                     onChange: { visualPresetID = "" })
                    EchoelValueField(label: "Motion", value: $visualMotion, range: 0...1.5,
                                     onChange: { visualPresetID = "" })
                    EchoelValueField(label: "Spread", value: $visualSpread, range: 0.5...1.5,
                                     onChange: { visualPresetID = "" })
                    EchoelValueField(label: "Hue", value: $visualHue, range: 0...1)
                    EchoelValueField(label: "Saturation", value: $visualSaturation, range: 0...2)
                }
                .padding(14)
            }
            .frame(maxHeight: 360)
            .background(EchoelTheme.bg.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radius))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            .padding(.horizontal, 12).padding(.bottom, 12)
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
    #endif

    /// Hold the screen on while the instrument is performing or projecting; otherwise
    /// let it sleep (battery). iOS resets `isIdleTimerDisabled` on background, so this
    /// is re-applied on scene-active too. No-op off UIKit.
    private func updateKeepAwake() {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled =
            running || showVisual || showBreath || showMeditation
        #endif
    }

    private func disableKeepAwake() {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }

    /// Load a preset's ENERGY into the live visual controls (Intensity/Detail/Motion/
    /// Spread). Controls remain editable; values stay within the flash-safe clamps
    /// (enforced in VisualPreset.init). A preset deliberately does NOT change the
    /// renderer or Look — the Look strip owns that — so the two never fight and every
    /// preset composes on top of whatever Look is active.
    private func applyVisualPreset(_ p: VisualPreset) {
        visualIntensity = p.intensity
        visualDetail = p.detail
        visualMotion = p.motion
        visualSpread = p.spread
        visualPresetID = p.id
    }

    /// Live "music → colour": the chord sounding now (published on the bus by the
    /// piano roll as a MusicalFrame) mapped through SpectralColor (OKLab, octave-
    /// equivalent hue, amplitude-weighted chord mix). Proves the DMMW promise —
    /// visuals shaped BY musical parameters — and feeds the immersive visual + light.
    private var musicColourRow: some View {
        let frame = bus.freshMusical(maxAge: 1.5)
        let sounding = frame?.isSounding ?? false
        let swatch = musicColour(frame) ?? EchoelTheme.fill
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(swatch)
                .frame(width: 44, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(EchoelTheme.border, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text("Music → colour").font(EchoelTheme.font(12, .medium)).foregroundStyle(EchoelTheme.text)
                Text(sounding ? "Live chord, mapped by pitch + loudness" : "Plays when the music is sounding")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Music colour, \(sounding ? "live" : "idle")")
    }

    /// Bridge the bus's latest MusicalFrame to a SwiftUI colour via SpectralColor.
    /// Output is LINEAR sRGB, so it's handed to SwiftUI as `.sRGBLinear`.
    private func musicColour(_ frame: MusicalFrame?) -> Color? {
        guard let frame, frame.isSounding else { return nil }
        let rgb = SpectralColor.color(forChord: frame.notes.map { (hz: $0.frequencyHz, amplitude: $0.amplitude) })
        return Color(.sRGBLinear, red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    // MARK: Panel — Mood (character of the composition)

    private var moodPanel: some View {
        panel("Mood", "Character of the composition", isExpanded: $showMood) {
            moodPresetBar
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

    // MARK: Mood presets (same library pattern as FX / sound)

    /// Load / save / favorite / share named moods — identical idiom to the sound
    /// and FX preset bars (one library behaviour app-wide).
    private var moodPresetBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(moodStore.sortedMoods) { m in
                    Button {
                        applyMood(m)
                    } label: {
                        if moodStore.isFavorite(id: m.id) {
                            Label(m.name, systemImage: "star.fill")
                        } else {
                            Text(m.name)
                        }
                    }
                }
                if !MoodPreset.community.isEmpty {
                    Section("Community") {
                        ForEach(MoodPreset.community) { m in
                            Button(m.name) { applyMood(m) }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if let id = moodPresetID, moodStore.isFavorite(id: id) {
                        Image(systemName: "star.fill").font(.system(size: 10))
                            .foregroundStyle(EchoelTheme.accent)
                    }
                    Text(moodPresetName).font(EchoelTheme.font(13, .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }
                .foregroundStyle(EchoelTheme.text)
                .padding(.horizontal, 12).frame(height: 34)
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .accessibilityLabel("Mood preset")

            Spacer(minLength: 0)

            // Management actions in one compact overflow menu so the row always fits
            // on iPhone width (Save as… / favorite / save / submit / delete).
            Menu {
                Button { moodAsName = moodPresetName + " copy"; showSaveMoodAs = true } label: {
                    Label("Save as new mood…", systemImage: "plus")
                }
                if let id = moodPresetID {
                    let isFav = moodStore.isFavorite(id: id)
                    Button { moodStore.toggleFavorite(id: id) } label: {
                        Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
                    }
                    if !moodStore.isFactory(moodSnapshot(id: id, name: moodPresetName)) {
                        Button { moodStore.save(moodSnapshot(id: id, name: moodPresetName)) } label: {
                            Label("Save changes", systemImage: "square.and.arrow.down")
                        }
                        Button(role: .destructive) {
                            moodStore.delete(id: id)
                            moodPresetID = nil
                            moodPresetName = "Custom"
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                Divider()
                Button {
                    if let url = moodSnapshot(name: moodPresetName).communityMailtoURL() { openURL(url) }
                } label: { Label("Submit to community", systemImage: "paperplane") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .accessibilityLabel("Mood actions")
        }
    }

    /// Apply a saved mood to the live controls and recompose.
    private func applyMood(_ preset: MoodPreset) {
        mood = preset.profile
        moodPresetID = preset.id
        moodPresetName = preset.name
        moodStore.markUsed(id: preset.id)
        recomposeIfRunning()
    }

    /// Snapshot the live 8 mood dimensions into a named/identified preset.
    private func moodSnapshot(id: UUID? = nil, name: String) -> MoodPreset {
        MoodPreset(id: id ?? UUID(), name: name,
                   liveliness: mood.liveliness, darkness: mood.darkness,
                   tension: mood.tension, romance: mood.romance,
                   weird: mood.weird, virtuosity: mood.virtuosity,
                   syncopation: mood.syncopation, humanize: mood.humanize)
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

    /// The sound library bar — same idiom as the Mood and FX preset bars: one Menu
    /// for load (genre default · your saved + factory sounds, favorites first ·
    /// community) plus a compact overflow for save/favorite/delete/submit. Wired to
    /// the shared `PatchStore` so favorites/recents match the deep Sound Editor.
    private var presetRow: some View {
        labeledRow("Character") {
            HStack(spacing: 8) {
                Menu {
                    Button {
                        presetIndex = -1
                        currentPatch = style.synthPatch
                        applyArticulation()
                    } label: { Text("Genre default") }
                    Section("Sounds") {
                        ForEach(patchStore.sortedPatches) { p in
                            Button { applySoundPatch(p) } label: {
                                if patchStore.isFavorite(id: p.id) {
                                    Label(p.name, systemImage: "star.fill")
                                } else { Text(p.name) }
                            }
                        }
                    }
                    if !CommunityLibrary.patches.isEmpty {
                        Section("Community") {
                            ForEach(CommunityLibrary.patches) { p in
                                Button(p.name) { applySoundPatch(p) }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if patchStore.isFavorite(id: currentPatch.id) {
                            Image(systemName: "star.fill").font(.system(size: 10))
                                .foregroundStyle(EchoelTheme.accent)
                        }
                        Text(currentPatch.name).font(EchoelTheme.font(13, .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                    .foregroundStyle(EchoelTheme.text)
                    .padding(.horizontal, 12).frame(height: 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
                }
                .accessibilityLabel("Timbre character / sound preset")

                Menu {
                    Button { patchSaveName = currentPatch.name + " copy"; showSavePatchAs = true } label: {
                        Label("Save as new sound…", systemImage: "plus")
                    }
                    let isFav = patchStore.isFavorite(id: currentPatch.id)
                    Button { patchStore.toggleFavorite(id: currentPatch.id) } label: {
                        Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
                    }
                    if !patchStore.isFactory(currentPatch) {
                        Button { patchStore.save(currentPatch) } label: {
                            Label("Save changes", systemImage: "square.and.arrow.down")
                        }
                        Button(role: .destructive) {
                            patchStore.delete(id: currentPatch.id)
                            presetIndex = -1
                            currentPatch = style.synthPatch
                            applyArticulation()
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                    Divider()
                    Button {
                        if let url = currentPatch.communityMailtoURL() { openURL(url) }
                    } label: { Label("Submit to community", systemImage: "paperplane") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(EchoelTheme.text)
                        .frame(width: 34, height: 34)
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .strokeBorder(EchoelTheme.border, lineWidth: 1))
                }
                .accessibilityLabel("Sound actions")
            }
        }
    }

    /// Load a patch from the library into the live sound. Keeps `presetIndex` in
    /// sync (factory index, else -1 = "custom") so the persisted quick-pick and
    /// the randomize button keep working.
    private func applySoundPatch(_ p: SynthPatch) {
        currentPatch = p
        presetIndex = SynthPatch.factory.firstIndex { $0.id == p.id } ?? -1
        patchStore.markUsed(id: p.id)
        applyArticulation()   // character = timbre; the global macro owns the envelope
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
        // Delegates to the shared EchoelPanel so Studio, EFX and the coming workspace
        // all render the identical panel (one CI vocabulary, one place to evolve it).
        EchoelPanel(title, subtitle, isExpanded: isExpanded, content: content)
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

            HStack(spacing: 16) {
                Button { diagnostics = DiagReport(text: EchoelCrashLog.currentLog()) } label: {
                    Text("Diagnostics").font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the in-app diagnostic log to share if something crashed")

                Button { showAcknowledgments = true } label: {
                    Text("Licenses & Credits").font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open-source licenses and attributions")
            }
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

    // MARK: - Acknowledgments / Licenses

    /// One credit section: a bold title + a body paragraph. Plain `Text` only —
    /// deliberately the simplest possible view tree (no Menu, no @Observable
    /// bindings, no ForEach over projected state) so this screen can never be a
    /// launch-time metadata or runtime-crash risk.
    private func creditSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(EchoelTheme.font(14, .semibold))
                .foregroundStyle(EchoelTheme.text)
            Text(body)
                .font(EchoelTheme.font(12))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// In-app open-source attributions / acknowledgments. Surfaces the same
    /// information as `THIRD_PARTY_NOTICES.md` in a form users can read on device
    /// (App Store hygiene; the font's OFL 1.1 prefers the license travel with the
    /// app). Static content, computed once — safe for the root view's shallow type.
    private var acknowledgmentsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Echoel is built with open standards and a few generously-licensed works. Thank you to their authors.")
                        .font(EchoelTheme.font(12))
                        .foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)

                    creditSection(
                        "Atkinson Hyperlegible — SIL Open Font License 1.1",
                        "© 2020 Braille Institute of America, Inc., with Reserved Font Name “Atkinson Hyperlegible”. Designed by Applied Design Works (Elliott Scott, Megan Eiswerth, Linus Boman, Theodore Petrosky). Used under the SIL OFL 1.1 — the full license ships in the app (Resources/Fonts/OFL.txt) and is available at scripts.sil.org/OFL.")

                    creditSection(
                        "Cosmic Octave — Hans Cousto (concept)",
                        "The colour-octave (tone → visible light by octave transposition) and the planetary tunings use the octave-transposition method and frequency values described by Hans Cousto, “The Cosmic Octave” (1978). Presented as creative tuning / acoustics / astronomy — no health, healing, chakra or Solfeggio claims.")

                    creditSection(
                        "Drum samples — original work",
                        "All bundled drum sounds are procedurally synthesised by Echoel’s own DSP. No third-party samples are used.")

                    creditSection(
                        "Apple frameworks",
                        "Built with AVFoundation, Accelerate, Metal, CoreMIDI, HealthKit, CoreBluetooth, SwiftUI and SwiftData, under the Apple developer-program terms.")

                    creditSection(
                        "Echoel",
                        "© 2024–2026 Echoelmusic (Michael Terbuyken). The Echoel source is MIT-licensed. No third-party Swift packages ship in this build.")

                    Text("Full notices: THIRD_PARTY_NOTICES.md in the project repository.")
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .background(EchoelTheme.bg)
            .navigationTitle("Licenses & Credits")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showAcknowledgments = false }
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
        // Specific, live coaching ("Press lighter" / "Hold still…") instead of a
        // flat "Acquiring…", so a placed-but-unlockable finger gets actionable help.
        let statusText = cameraRPPG.coachingHint
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
        .background(RoundedRectangle(cornerRadius: 6).fill(EchoelTheme.bg.opacity(0.35)))
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
                    HStack(spacing: 8) {
                        Button { open(p); showOpen = false } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.callout.weight(.medium)).foregroundStyle(EchoelTheme.text)
                                Text("\(p.style.displayName) · \(p.key.shortName) · \(String(format: "%.0f", p.bpm)) BPM")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        ShareLink(item: SharedEchoelProject(project: p),
                                  preview: SharePreview(p.name)) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15)).foregroundStyle(EchoelTheme.dim)
                                .frame(width: 34, height: 34)
                        }
                        .accessibilityLabel("Share \(p.name)")
                    }
                }
                .onDelete { idx in idx.map { projects.projects[$0].id }.forEach { projects.delete(id: $0) } }
            }
            .navigationTitle("Open project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { projectImportPresented = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
            #if canImport(UniformTypeIdentifiers)
            .fileImporter(isPresented: $projectImportPresented,
                          allowedContentTypes: [.json],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    projects.importProject(from: url)
                }
            }
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
        beatPlayer.pattern.stop()       // stops the transport (→ onStop flush)
        // Force-silence EVERY voice explicitly — never rely on the onStop callback
        // wiring alone. pianoRoll.allNotesOff() clears its active-note tracking and
        // releases poly/sub/MIDI/AUv3; panicAllNotesOff() is the belt-and-suspenders
        // direct release in case a voice ref ever falls out of sync. Idempotent, so
        // doubling up can never leave a note ringing ("Sound bleibt hängen" fix).
        pianoRoll.allNotesOff()
        panicAllNotesOff()
        synth.bioModulationEnabled = false   // stop the 10 Hz timbre drive too
        stopBioSource()
        EchoelCrashLog.breadcrumb("stopEverything: transport + all voices released")
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
                // Re-seed roughly every ~4 bars at the current tempo (not a flat 12 s)
                // so the music keeps hugging the live body but is given room to SETTLE
                // into a phrase instead of re-rolling restlessly (device-log feedback:
                // takes changed every ~2-4 s and never settled). Clamped 8…16 s so it
                // never churns too fast or drifts too static.
                let beats = 16.0  // four 4/4 bars
                let barSpan = min(16.0, max(8.0, beats * 60.0 / max(40.0, beatPlayer.pattern.tempo)))
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
        // Cohesion: the STRUCTURE seed is the body-only seed (no evolution nonce), so
        // the harmonic skeleton / register / density stay stable while the DETAIL seed
        // (with the nonce) evolves the melody — consecutive takes feel like the same
        // piece breathing, not a new random one ("homogener klingen"). When the body
        // shifts, the structure evolves with it; with no signal both are random.
        let structureSeed = bioSeed(frame)
        let evolvingSeed = structureSeed ^ (evolution &* 0x9E3779B97F4A7C15)
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
            seed: evolvingSeed,
            structureSeed: structureSeed
        )
        let composition = BioComposer.compose(input)
        // Honor the user's Kammerton (concert pitch) + live timbre on the next notes.
        synth.setTuning(a4Hz: session.a4Hz)
        subBass.setTuning(a4Hz: session.a4Hz)
        synth.apply(currentPatch)
        // Locked tempo wins for tight loops; otherwise the body sets the pace.
        let tempo = lockBPM ? min(max(lockedBPM, 40), 240) : composition.suggestedTempo
        // Push the live musical context so the roll's per-tick MusicalFrame carries the
        // current key/scale/tempo/concert-pitch → renderers colour by the right key.
        pianoRoll.musicalA4Hz = session.a4Hz
        pianoRoll.musicalRootPitchClass = rootIndex
        pianoRoll.musicalScaleName = scale.rawValue
        pianoRoll.musicalTempoBPM = tempo
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
        metronome.bpm = tempo   // keep the click on the live transport tempo
        session.adopt(key: key)
        lastNoteCount = composition.notes.count
        // EchoelAI narrates the live bio→sound mapping in plain technical English.
        if let frame { aiExplanation = BioExplanation.text(for: frame, tempo: tempo) }
        let wasPlaying = beatPlayer.pattern.isPlaying
        if !wasPlaying { beatPlayer.pattern.play() }
        if !wasPlaying { metronome.resync() }   // align the click's downbeat to the start
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

    /// The loudness the export normalises to — the same delivery target chosen in the
    /// Master panel (Streaming −14 / Podcast −16 / Broadcast −23 / Cinema −24). "No
    /// target" keeps the established −14 default so existing behaviour is unchanged.
    private var exportTargetLUFS: Float {
        LoudnessTarget(rawValue: loudnessTargetRaw)?.integratedLUFS ?? -14
    }

    private func exportWav() async {
        if let url = await exporter.exportWav(engine: audioEngine, beatPlayer: beatPlayer,
                                              bars: loopBars.rawValue, targetLUFS: exportTargetLUFS) {
            share = ExportedFile(url: url)
        }
        // Always return to idle: a failed/empty export must never leave the button
        // stuck on "Recording…/Writing…" (a "hanging button"). On success the URL is
        // already captured above, so resetting the status here is safe.
        exporter.reset()
    }

    /// Retroactive "keep that" — export the last few bars already heard, no replay.
    private func keepLastLoop() async {
        if let url = await exporter.exportRecentLoop(engine: audioEngine, beatPlayer: beatPlayer,
                                                     bars: loopBars.rawValue, targetLUFS: exportTargetLUFS) {
            share = ExportedFile(url: url)
        }
        exporter.reset()
    }

    /// Export the generated melody as a standard MIDI file (in-key notes, real
    /// tempo) so it opens with pitch + timing in any DAW. Engine already exists
    /// (MIDIFileExporter); this writes it to a temp file and opens the share sheet.
    private func exportMIDI() {
        let notes = pianoRoll.notes
        let steps = beatPlayer.pattern.steps
        // Export the WHOLE take (melody ch.1 + drums ch.10) as one multi-track SMF,
        // so nothing is dropped when it opens in a DAW.
        guard !notes.isEmpty || steps.contains(where: { $0.contains(true) }) else { return }
        let data = MIDIFileExporter.exportCombined(notes: notes, steps: steps,
                                                   tempo: beatPlayer.pattern.tempo)
        let stem = session.sessionName(bpm: beatPlayer.pattern.tempo)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(stem).mid")
        do {
            try data.write(to: url, options: .atomic)
            share = ExportedFile(url: url)
        } catch {
            EchoelCrashLog.breadcrumb("MIDI export failed: \(error.localizedDescription)")
        }
    }

    /// Snapshot the live session as a Project — shared by Save and Live Colabo so
    /// "what you share" is byte-identical to "what you save".
    private func currentProject(named name: String? = nil) -> Project {
        let n = name ?? (saveName.isEmpty ? session.sessionName(bpm: beatPlayer.pattern.tempo) : saveName)
        return Project(
            name: n,
            styleRaw: style.rawValue, keyRoot: rootIndex, scaleRaw: scale.rawValue,
            bpm: beatPlayer.pattern.tempo, modeRaw: ComposerMode.flowFree.rawValue,
            fxCharacterRaw: fxCharacter.rawValue, loopBars: loopBars.rawValue,
            a4Hz: session.a4Hz, artist: session.artistName,
            patch: currentPatch, notes: pianoRoll.notes,
            drumSteps: beatPlayer.pattern.steps, drumAccents: beatPlayer.pattern.accents
        )
    }

    private func saveProject() {
        projects.save(currentProject())
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

    #if canImport(UniformTypeIdentifiers)
    /// Import a Standard MIDI File onto the piano roll. Reads via a security-scoped
    /// URL, parses melodic notes (drums on ch10 excluded), folds them into the
    /// single visible bar, and loads them — replacing the current take.
    private func importMIDI(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let imported = try? MIDIFileImporter.notes(from: data) else {
            EchoelCrashLog.breadcrumb("MIDI import failed: \(url.lastPathComponent)")
            return
        }
        let placed = pianoRoll.importNotes(imported)
        lastNoteCount = placed.count
        // Drums: if the file has GM channel-10 hits, load them onto the beat grid too
        // (so one import brings both melody and drums). No hits → leave the kit alone.
        if let grid = try? MIDIFileImporter.drumGrid(from: data,
                                                     trackCount: BeatPlayer.trackNames.count,
                                                     stepCount: PatternEngine.stepCount),
           grid.steps.contains(where: { $0.contains(true) }) {
            beatPlayer.pattern.load(steps: grid.steps, accents: grid.accents)
        }
        EchoelCrashLog.breadcrumb("MIDI import: \(imported.count) parsed → \(placed.count) on grid")
    }
    #endif

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
