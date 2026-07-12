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
            return "\(safe.isEmpty ? "Echoelmusic Session" : safe).echoel.json"
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

    /// Returns to the calm bio-paced Session — the app HOME since the shell flip
    /// (2026-07-06): the studio host wires this so setting it true dismisses the
    /// studio cover. Optional so previews/other hosts still compile; the Session
    /// card is only shown when a host is wired. (The studio's own sheet chain never
    /// grows — render-safety rule.)
    var presentSession: Binding<Bool>? = nil

    @Environment(EngineBus.self) private var bus
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(BeatPlayer.self) private var beatPlayer
    @Environment(PianoRollModel.self) private var pianoRoll
    @Environment(MIDIOutput.self) private var midiOut
    @Environment(AUv3Host.self) private var auHost
    @Environment(PolySynthVoice.self) private var synth
    /// The PLAY-SURFACE voice (fullscreen visual touch instrument) — its own instance,
    /// so its patch/morph never re-timbre the generative bed and vice versa.
    @Environment(\.touchSynth) private var touchSynth
    @Environment(\.leadSynth) private var leadSynth
    /// Patch id for the play surface: "" = follow the take's sound (default).
    @AppStorage("touch.patchID") private var touchPatchID = ""
    /// How much sliding UP the play surface brightens the tone (0 = off … 1 = ±1 octave).
    @AppStorage("touch.morphDepth") private var touchMorphDepth = 0.6
    /// Slide-expression depths + glide for the play surface (founder 2026-07-08:
    /// "hin und her sliden verändert den Sound: Filter, ein bisschen Vibrato,
    /// Chorus … Glide bzw. Portamento kann man auch einstellen"). Same keys +
    /// defaults as FloatingVisualWindow, which passes them into the surface.
    @AppStorage("touch.slideVibrato") private var touchSlideVibrato = 0.35
    @AppStorage("touch.slideChorus") private var touchSlideChorus = 0.30
    @AppStorage("touch.glide") private var touchGlide = 0.0
    @Environment(SubBassVoice.self) private var subBass
    @Environment(MetronomeVoice.self) private var metronome
    // The one shared transport. Read ONLY via `.onChange(of: transport.isPlaying)` (a
    // LOW-frequency flag — flips on play/stop, never 10 Hz) so the global transport bar's
    // Stop can end the whole bio session; NOT read in `body` (freeze rule).
    @Environment(Transport.self) private var transport
    @Environment(SessionContext.self) private var session
    /// Opt-in place token (E2). Low-frequency reads only (toggle/one-shot token).
    #if canImport(CoreLocation)
    @Environment(LocationNamer.self) private var locationNamer
    #endif
    /// Opt-in weather flavour (E3b): one coarse fetch at Start salts the
    /// STRUCTURE seed — the sky colours the skeleton, the body stays the
    /// primary driver. Low-frequency reads only.
    #if canImport(WeatherKit) && canImport(CoreLocation)
    @Environment(WeatherProvider.self) private var weatherProvider
    @AppStorage("weather.enabled") private var weatherEnabled = false
    /// This session's full weather flavour (nil = none yet). Carries the skeleton
    /// salt PLUS the per-parameter sound/visual targets; lands on the next re-seed.
    @State private var weatherContribution: WeatherMood.Contribution?
    private var weatherDescriptor: String { weatherContribution?.descriptor ?? "" }
    #endif
    @Environment(LoopExporter.self) private var exporter
    @Environment(ProjectStore.self) private var projects
    @Environment(PatchStore.self) private var patchStore
    @Environment(MixerStore.self) private var mixer
    @Environment(TrackFXStore.self) private var trackFX
    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif
    #if canImport(AVFoundation) && canImport(Metal)
    @Environment(VisualRecorder.self) private var visualRecorder
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

    // Collapsible control-panel state ("aufklappen"). Feinschliff 3/4 (founder: "eine
    // adaptive Ansicht ohne weitere Untermenüs … nur das Wesentliche sichtbar"): the view
    // now opens CALM — only Composition (genre/key/tempo) expanded; every other panel is
    // one tap away, nothing removed (function preserved, reversible).
    /// Panels start COLLAPSED (founder 2026-07-06E: "Das soll natürlich alles
    /// minimal sein aber trotzdem funktionieren") — the default view is Bio strip ·
    /// Start · the two mood pads; everything else is one tap away behind its
    /// compact header. Persisted so a user who opens a panel keeps it open.
    @AppStorage("studio.showComposition") private var showComposition = false
    @AppStorage("studio.showMix") private var showMix = false
    /// R1 (2026-07-10): the Session card — name preview · place · weather.
    @AppStorage("studio.showSession") private var showSession = false
    @AppStorage("studio.showExport") private var showExport = false
    @State private var showMood = false
    @State private var showSound = false
    @State private var showEffects = false
    @State private var showMaster = false
    /// Delivery loudness target (shared key with MasterLoudnessGrid's colour-coding).
    @AppStorage("studio.loudnessTarget") private var loudnessTargetRaw = LoudnessTarget.streaming.rawValue
    /// Immersive visual mode: the spectrum→visible donut visual (default) vs the bio rings.
    @AppStorage("visual.spectralDonuts") private var spectralDonuts = true
    /// MetalBioView style when NOT in donut mode: 0 rings · 1 Chladni · 2 plasma · 3 water
    /// · 4 Prism · 5 Aurora · 6 Lissajous · 7 Depth Caustics · 8 Oscilloscope · 9 Fractal.
    /// Default 5 (Aurora) — a richer look out of the box; MUST match FloatingVisualWindow.
    @AppStorage("visual.style") private var visualStyle = 5
    /// Secondary style to blend with `visualStyle` (same index space). 0…9 as above.
    @AppStorage("visual.styleB") private var visualStyleB = 0
    /// Mix ratio A↔B [0…1]: 0 = pure primary look, 1 = pure blend look. The "mischend" control.
    @AppStorage("visual.blend") private var visualBlend = 0.0
    /// The user-customizable SEQUENCE the look slider fades through (founder 2026-07-08:
    /// "man soll das was im slider passiert selbst customizen … mehr Optionen"). Persisted
    /// as a compact "3,5,7" string, SHARED with FloatingVisualWindow, parsed by LookBlendMap.
    /// Same key + default in both views so an absent key resolves identically. Replaces the
    /// old fixed `calmMetalStyles` list — the surfaced looks are now whatever the user picks.
    @AppStorage(LookBlendMap.storageKey) private var sliderLooksRaw = "3,5,7"
    private var sliderLooks: [Int] { LookBlendMap.sequence(from: sliderLooksRaw) }

    /// User-chosen tempo-synced delay note value ("studio calculator in the FX"),
    /// re-applied after genre/character FX so the pick is never clobbered.
    @State private var delaySync = TempoSyncOption(.eighth, .dotted)

    /// Continuous mood/character controls that shape the composition (blend with bio).
    @State private var mood = MoodProfile()
    /// The SOUND mood pad's position (persisted). X right = brighter (darkness = 1−x),
    /// Y up = more movement (liveliness = y). Written on drag END only — one
    /// invalidation + one coalesced recompose per gesture (ultraleichte Steuerung).
    @AppStorage("mood.sound.x") private var soundMoodX = 0.5
    @AppStorage("mood.sound.y") private var soundMoodY = 0.5
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

    /// Max BPM the take tempo may drift toward the body per evolve tick (~every 30 s), glided.
    /// Small enough that the beat never lurches, large enough that a stale startup seed
    /// (e.g. 98 from an elevated launch pulse) converges to the settled pulse within ~2 min.
    private static let tempoConvergeStep: Double = 8

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
    // Default identity (founder 2026-07-07: "Tendenziell alles eher ohne Beat und
    // reine meditative Flächen"): the app opens as breath-paced ambient TEXTURES —
    // Self-Observation genre, no drums, pad articulation. Every genre/beat remains
    // one tap away; users who already changed these keep their stored choice.
    @AppStorage("studio.genre") private var style: MusicStyle = .selfObservation
    @AppStorage("studio.rootIndex") private var rootIndex = 0
    @AppStorage("studio.scale") private var scale: Scale = .minor
    /// Selected tone system (microtonal). "edo12" = standard 12-TET (default, no retune).
    /// Persisted so a chosen world tuning survives relaunch.
    @AppStorage("toneSystemID") private var tuningID = "edo12"
    @AppStorage("studio.fxCharacter") private var fxCharacter: FXCharacter = .auto
    @AppStorage("studio.loopBars") private var loopBars: LoopBarLength = .four
    /// Drum layer: Off = pure Flächen (DEFAULT — founder 2026-07-07: "Tendenziell
    /// alles eher ohne Beat und reine meditative Flächen"), Pulse = the deep
    /// shamanic heartbeat drum (2026-07-06C), Genre = the style's archetypal groove.
    @AppStorage("studio.beatMode") private var beatMode: BeatMode = .off
    /// Global articulation macro: 0 = pad (slow swell), 1 = pluck (struck/short). Owns
    /// the envelope for EVERY character (genre/preset = timbre, this = onset/dynamics).
    /// Persisted; re-imposed whenever a character or genre loads. Drives the per-note
    /// velocity sensitivity automatically (short attack ⇒ percussive ⇒ touch-responsive).
    /// Default 0.15 = clearly PAD (slow swell, long release) — the meditative-Fläche
    /// identity (2026-07-07); was 0.4. Pluckier characters stay one drag away.
    @AppStorage("studio.articulation") private var articulation: Double = 0.15
    @State private var currentPatch = SynthPatch(name: "Init")
    /// Whether anything has been composed yet (gates the export/save buttons). A plain
    /// Bool that only ever flips false→true ONCE — it used to be `lastNoteCount: Int?`
    /// re-set to the note count on every re-seed, and since `@State` invalidates the WHOLE
    /// body, that rebuilt the root view each re-seed and tore down any open Tonart/Genre
    /// `.menu` Picker (the "dropdown am Anfang nicht stabil" freeze; AnyView-wrapped panels
    /// lose menu identity on rebuild). The buttons only ever read it as `== nil`, so a Bool
    /// is equivalent and stops the re-seed churn.
    @State private var hasComposed = false
    /// Ever-advancing evolution counter folded into every seed so the composition
    /// keeps developing and never repeats, even when the body holds steady.
    @State private var evolution: UInt64 = 0

    /// EchoelAI's plain-English narration of how the live body is shaping the sound,
    /// refreshed each time the composition re-seeds. Held in a tiny `@Observable` so its
    /// per-re-seed text change is observed ONLY by the leaf `StudioCaptionView` — not the
    /// root body — so re-seeding never rebuilds (and closes) the selection menus.
    @State private var caption = StudioCaption()
    /// EchoelAI speaks only when ASKED (founder 2026-07-09: "Echoel AI soll
    /// interaktiver werden und nicht ungefragt Dinge anzeigen"). Default OFF —
    /// the narration paragraph never appears unprompted; the user opens it via
    /// the quiet disclosure row and the choice persists.
    @AppStorage("studio.liveNarration") private var showLiveNarration = false

    // Background evolution + bio acquisition.
    @State private var evolveTask: Task<Void, Never>?
    /// Debounce handle that coalesces rapid recompose requests (see scheduleGenerate).
    @State private var regenTask: Task<Void, Never>?
    @State private var startTask: Task<Void, Never>?
    /// Non-blocking watcher that re-seeds once the rPPG pulse first locks (see snapToLockWhenReady).
    @State private var lockSnapTask: Task<Void, Never>?
    /// When the last take was composed — the floor for automatic re-seeds.
    @State private var lastSeedAt: Date = .distantPast
    /// WHY the next generate() runs ("start" · "user-edit" · "lock-snap" · "evolve") —
    /// carried into the generate breadcrumb so device logs can attribute every re-seed
    /// (log 1783370283 had a mid-take thinning nobody could explain).
    @State private var pendingGenerateReason = "start"
    /// True once the body has seeded the tempo for THIS take (a real bio frame arrived).
    /// After that the beat HOLDS — evolve/re-seed ticks evolve only the melody, so a noisy
    /// rPPG octave-error (≈196 ≈ 2×98) can never slam the tempo to double-time mid-take.
    /// Reset on stop so the next take re-seeds from a fresh pulse. (See generate() tempo block.)
    @State private var tempoSeededFromBody = false
    /// The no-body structure seed for THIS take — drawn once per Start, stable until the
    /// next take. Keeps the piece coherent through the pre-lock warm-up (see bioSeed).
    @State private var takeFallbackSeed: UInt64 = 1
    /// The body state (HR·coherence) captured at the last take — the baseline the evolve
    /// HOLD compares against (founder 2026-07-04 "halten wenn eingerastet"): a settled,
    /// unchanged body holds its phrase instead of re-rolling every ~30 s. nil = the last
    /// take had no usable body (neutral/demo), so evolve keeps it gently alive.
    @State private var lastGenBody: (bpm: Double, coherence: Double)? = nil
    /// Minimum seconds between AUTOMATIC re-seeds (evolve/lock). User edits bypass it.
    /// Raised 3.5 → 6 s (device-log feedback): lets a take settle into a phrase and
    /// makes overlapping auto triggers (lock-snap + evolve) collapse into one re-seed.
    private let minAutoSeedGap: TimeInterval = 6.0
    /// The floating-visual state (visible/size) before Start staged the immersive
    /// fullscreen take, so Stop can restore exactly what the user had. nil = no take
    /// staging in flight. (The keys are @AppStorage-backed in WorkspaceView /
    /// FloatingVisualWindow; writes here go through the same UserDefaults.)
    @State private var preTakeVisualVisible: Bool?
    @State private var preTakeVisualSize: Int?
    // (Tempo-latch gating moved into CameraRPPGBioPublisher.isSettled — confident + FLAT,
    //  because confidence alone latches on the falling warm-up tail. See bodyTempoTrustworthy.)

    // Sheets / dialogs
    @State private var showOpen = false
    @State private var showSaveDialog = false
    @State private var saveName = ""
    @State private var share: ExportedFile?
    /// Finished visual recording, presented via a cover-scoped share sheet (kept
    /// separate from `share` so it never competes with the root-body share modal).
    @State private var visualShare: ExportedFile?
    @State private var diagnostics: DiagReport?

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
    // (showChannelRack removed — the Channel Rack is now the first-class "Mix" workspace surface.)
    @State private var showAutomation = false
    @State private var showAudioClip = false
    /// Presents a file picker to import a Standard MIDI File onto the piano roll.
    @State private var midiImportPresented = false
    /// Drives the project-import file picker in the Open-project sheet.
    @State private var projectImportPresented = false
    @State private var showVisual = false
    /// Remembers whether the floating visual was showing before the fullscreen cover took over,
    /// so dismissing the cover restores it (single-MetalBioView / GPU rule — see onChange).
    @State private var floatingWasVisible = false
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

    // Immersive-visual controls. Now @AppStorage (Double) so they are the SHARED single
    // source of truth read by BOTH this panel AND the floating visual window (founder
    // 2026-07-02: "Visual Design muss möglich sein" — every tweak must show in the window,
    // live). All clamped so the WCAG flash ceiling (≤3 Hz) can never be exceeded — see
    // MetalBioView. Stored as Double (@AppStorage has no Float); passed to the renderer as
    // Float(...). EchoelValueField is generic over BinaryFloatingPoint, so the fields bind
    // to Double directly.
    @AppStorage("visual.intensity") private var visualIntensity = 1.0
    @AppStorage("visual.detail") private var visualDetail = 40.0   // ring density
    @AppStorage("visual.motion") private var visualMotion = 1.0    // animation speed (flash-clamped)
    @AppStorage("visual.spread") private var visualSpread = 1.0
    /// VJ palette: hue rotation [0…1] (0 = physical tone colour) + saturation [0…2].
    /// Default saturation 0.82 (professional, not neon); MUST match FloatingVisualWindow.
    @AppStorage("visual.hue") private var visualHue = 0.0
    @AppStorage("visual.saturation") private var visualSaturation = 0.82
    /// The floating visual window's show/hide state — SHARED with WorkspaceView's header
    /// monitor button and the window's own close button, so the Visual panel can toggle it
    /// directly (founder: everything user-optimized; don't make the header the only way in).
    @AppStorage("visual.floating.visible") private var floatingVisualVisible = false
    @State private var showVisualSettings = false
    /// VJ control overlay visible over the fullscreen visual (tap canvas to toggle).
    @State private var showVisualControls = true
    /// Last-picked immersive visual preset (persisted) — a launch point for the
    /// four live sliders below; "" = none/custom after a manual tweak. DEFAULT
    /// "vapor" (founder 2026-07-07: "mehr kitschige Vaporwave-Ästhetik … alles soll
    /// zueinander passen"): a fresh install opens on the coherent dreamy vaporwave
    /// world (applied in onAppear), so sound + picture read as ONE nostalgic mood
    /// out of the box. A user who tweaks any field clears this back to "" (custom),
    /// and picking another look — or setting Hue 0 — restores the physical tone
    /// colour, so the science-first palette is always one tap away.
    @AppStorage("visual.preset") private var visualPresetID = "vapor"

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
            // NOTE: do NOT pass the camera's `fingerDetected` (10 Hz) down from here —
            // reading it in this root body re-evaluated the whole view 10×/s while a take
            // played, collapsing any open Tonart/Genre `.menu` Picker (the "can't select
            // anymore" freeze). BioStripView now reads it itself (a Picker-free leaf view).
            BioStripView(measuring: running,
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
                    // Session first (founder: "wow in den ersten 10 Sekunden ·
                    // meditativ"): the calm bio-paced breathing Session is the
                    // unmissable entry ABOVE the studio instrument. Reversible — a
                    // static card, no live bio read here (freeze rule); the studio
                    // stays right below.
                    if let presentSession { AnyView(sessionEntryCard(presentSession)) }
                    AnyView(startButton)
                    // Mood pads REMOVED from the surface (founder 2026-07-07:
                    // "Xy Pads komplett wieder herausnehmen"). The builder +
                    // MoodPads.swift stay in code, unpresented (reversible).
                    // nonStandardTuningBanner REMOVED from presentation (founder
                    // 2026-07-09: "nicht ungefragt Dinge anzeigen") — the current
                    // tuning + the way back to 12-TET live where the user set it,
                    // in the Composition panel's tuning row. Builder stays defined
                    // below, unpresented (reversible). Removing a body branch only
                    // SHRINKS the aggregate type (metadata-safe).
                    #if canImport(AVFoundation)
                    if running { AnyView(PulseMeasurementView()) }
                    #endif
                    // EchoelAI's live narration sits right under the bio, next to the
                    // numbers it explains (moved up 2026-07-07 from between Mood/Export).
                    AnyView(liveNarrationBanner)
                    AnyView(soundControls)
                    AnyView(utilityRow)
                    // R2 (2026-07-10): Live Colabo entry — the sheet existed but
                    // nothing presented it after the tools grid was removed.
                    #if canImport(MultipeerConnectivity)
                    AnyView(liveColaboRow)
                    #endif
                    // Visual Touch Instrument sits at the very bottom of the page
                    // (founder 2026-07-07: "das müsste ganz nach unten").
                    AnyView(visualPanel)
                    // R3 (2026-07-10): Learn & News entry — reaches the school
                    // content AND the opt-in announcements toggle (E4).
                    AnyView(learnRow)
                    // Tools grid removed (founder 2026-07-02: "Alles weg außer visuals").
                    // The whole editors/utilities pile is gone from the one adaptive view;
                    // the Visual stays as the floating window (header monitor toggle). The
                    // `toolsSection` builder + its sheets remain in code (reversible); they
                    // are just no longer mounted. Removing a body branch only SHRINKS the
                    // aggregate type (safer re: the launch metadata limit), never grows it.
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
            // Restore the last-picked immersive visual look so an installation /
            // performance setup survives relaunch (the live params aren't persisted
            // individually, but the chosen scene is).
            if !visualPresetID.isEmpty,
               let p = VisualPreset.factory.first(where: { $0.id == visualPresetID }) {
                applyVisualPreset(p)
            }
            // Visual minimize (founder 2026-07-07): retire the busy looks from the
            // surface — snap a persisted busy style (e.g. Prism) to a calm one so
            // nobody relaunches stuck on it. Blend is NOT cleared any more: the
            // stufenlos look slider drives style/styleB/blend as one control, and a
            // mid-blend position must survive relaunch (clearing it here would snap
            // the slider back to a stop on every appear). A blend onto a retired
            // B-style is reset along with the A-snap.
            // If the persisted primary style is no longer in the user's slider sequence
            // (retired look, or the sequence was edited), snap to the first look of the
            // active sequence so the slider is never stuck on an unreachable stop. Also
            // clear a stale blend onto a now-absent B-style (review L5) so the renderer
            // matches the slider immediately, not only after the first drag.
            if !spectralDonuts, !sliderLooks.contains(visualStyle) {
                visualStyle = sliderLooks.first ?? 3   // → first look (default Water)
                visualStyleB = 0
                visualBlend = 0
            } else if !spectralDonuts, visualBlend > 0, !sliderLooks.contains(visualStyleB) {
                visualStyleB = 0
                visualBlend = 0
            }
            // (Founder 2026-07-11 "Alles rein. Logisch sortiert.": every genre is now
            // offered, grouped by category in the picker — the old curation migration
            // that snapped retired styles to Self-Observation is removed. A persisted
            // style is always a valid case now.)
            surfacePriorCrashIfAny()
            handlePendingIntent()
            // Apply the persisted Mixer "Drums" level to the beat engine at launch.
            beatPlayer.masterLevel = mixer.drums
            // Apply the persisted per-track inserts at launch (bass → sub; melodic → both
            // the pad/harmony and lead voices).
            subBass.setInsert(trackFX.bass)
            synth.setInsert(trackFX.melodic)
            leadSynth?.setInsert(trackFX.melodic)
            // Drums bus master → fan the persisted insert across all 8 channels.
            setDrumsFX(trackFX.drums)
            // Restore a CUSTOM play-surface patch across relaunch. Follow-the-take needs
            // no action here (currentPatch is still the Init placeholder pre-generate —
            // the app startup already gave both voices the warm default).
            if !touchPatchID.isEmpty { syncTouchSound() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { handlePendingIntent(); updateKeepAwake() }
        }
        // Keep the screen awake while performing or projecting — an installation, a
        // projected immersive visual, or a hands-off guided session must NOT auto-lock
        // mid-show. Recomputed from the combined state so any one toggle is correct;
        // re-enabled (battery) the moment nothing needs it.
        .onChange(of: running) { _, _ in updateKeepAwake() }
        // ONE Stop for the whole app: when the transport stops from ANYWHERE (the global
        // transport bar, an arrangement finishing), end the bio session too — don't leave
        // the camera/evolve armed behind a stopped clock (founder: one accessible solution,
        // no duplicate paths). Guarded by `running` so stopEverything()'s own pattern.stop()
        // (which flips transport.isPlaying false after already setting running=false) can't
        // recurse. To only WATCH the pulse without music, arm the body on the Bio page.
        .onChange(of: transport.isPlaying) { _, playing in
            if !playing && running { stopEverything() }
        }
        .onChange(of: showVisual) { _, isUp in
            updateKeepAwake()
            // GPU rule: only ONE MetalBioView may render at a time. The fullscreen visual
            // cover mounts its own MetalBioView, so HIDE the floating window while it's up
            // (otherwise both MTKViews drive CADisplayLinks → GPU starvation / black immersive,
            // AND both feed the recorder → double-capture). Restore the floating window's prior
            // state on dismiss so the user gets back exactly what they had.
            if isUp {
                floatingWasVisible = floatingVisualVisible
                floatingVisualVisible = false
            } else {
                floatingVisualVisible = floatingWasVisible
            }
        }
        .onChange(of: showMeditation) { _, _ in updateKeepAwake() }
        .onDisappear { stopEverything(); disableKeepAwake() }
        // Sheet/cover contents are AnyView-erased too — same reason as the scroll
        // content above: keep the root view's aggregate generic type shallow so the
        // launch-time metadata decode can never overflow the stack again.
        .sheet(isPresented: $showOpen) { AnyView(openSheet) }
        .sheet(item: $share) { AnyView(ShareSheet(url: $0.url)) }
        .sheet(item: $diagnostics) { report in AnyView(diagnosticsSheet(report.text)) }
        .sheet(isPresented: $showPianoRoll) {
            AnyView(PianoRollView(pattern: beatPlayer.pattern, model: pianoRoll).echoelSheetPanel())
        }
        .sheet(isPresented: $showAllFX) {
            AnyView(EchoelFXView(chain: synth.fxChain, bpm: currentTempo,
                         fxEnabled: { synth.isFXEnabled },
                         setFXEnabled: { synth.setFXEnabled($0) })
                .echoelSheetPanel())
        }
        .sheet(isPresented: $showInput) { AnyView(AudioInputPickerView().echoelSheetPanel()) }
        .sheet(isPresented: $showRouting) { AnyView(PatchbayView().echoelSheetPanel()) }
        .sheet(isPresented: $showPlugins) { AnyView(AUv3BrowserView().echoelSheetPanel()) }
        .sheet(isPresented: $showLearn) { AnyView(LearnView()) }   // self-manages its detents
        .sheet(isPresented: $showAutomation) { AnyView(AutomationView().echoelSheetPanel()) }
        .sheet(isPresented: $showAudioClip) { AnyView(AudioClipView().echoelSheetPanel()) }
        #if canImport(UniformTypeIdentifiers)
        .fileImporter(isPresented: $midiImportPresented,
                      allowedContentTypes: [.midi],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { importMIDI(url) }
        }
        #endif
        .sheet(isPresented: $showBroadcast) { AnyView(BroadcastView().echoelSheetPanel()) }
        .sheet(item: $sampleBrowserTrack) { ref in AnyView(SampleBrowserView(track: ref.id).echoelSheetPanel()) }
        .sheet(isPresented: $showPatchEditor) {
            AnyView(PatchEditorView(initial: currentPatch) { p in
                currentPatch = p
                synth.apply(p)   // editor changes hit the live voice immediately
                syncTouchSound() // play surface follows unless it has its own patch
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
                    MetalBioView(capturesVideo: true, reduceMotion: reduceMotion, toneHz: currentToneHz,
                                 intensity: Float(visualIntensity), ringDensity: Float(visualDetail),
                                 motion: Float(visualMotion), spread: Float(visualSpread),
                                 hueShift: Float(visualHue), saturation: Float(visualSaturation),
                                 style: visualStyle, styleB: visualStyleB,
                                 blend: Float(visualBlend),
                                 entrainmentPulseHz: entrainmentVisualPulseHz).ignoresSafeArea()
                }
                // Tap the canvas to hide/show the VJ control PANEL — clean for
                // projection, hands-on for performance. Controls are a solid panel.
                Color.clear.contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { showVisualControls.toggle() } }
                if showVisualControls {
                    visualVJOverlay
                        .transition(.opacity)   // Uncodixfy: opacity only, no translation
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
                    #if canImport(AVFoundation) && canImport(Metal)
                    // Record the bio-reactive visual to an .mp4 (rings/prism only — the
                    // spectrum-donut Canvas isn't Metal, so no capture there yet).
                    if !spectralDonuts {
                        Button {
                            if visualRecorder.isRecording {
                                Task {
                                    if let url = await visualRecorder.stop() {
                                        visualShare = ExportedFile(url: url)
                                    }
                                }
                            } else {
                                visualRecorder.start(audio: audioEngine)
                            }
                        } label: {
                            Image(systemName: visualRecorder.isRecording ? "stop.circle.fill" : "record.circle")
                                .font(.title2)
                                .foregroundStyle(visualRecorder.isRecording ? Color.red : .white.opacity(0.85))
                        }
                        .accessibilityLabel(visualRecorder.isRecording ? "Stop recording" : "Record video")
                    }
                    #endif
                    Button { showVisual = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2).foregroundStyle(.white.opacity(0.85))
                    }
                    .accessibilityLabel("Close visual")
                }
                .padding()
            }
            .statusBarHidden(true)
            .sheet(item: $visualShare) { AnyView(ShareSheet(url: $0.url)) }
        }
        #endif
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

    // MARK: - Tools catalog (ONE source of truth for the grid + the HUD)

    /// Which group a tool belongs to. Both the Tools grid and the bottom HUD menu are
    /// rendered from `toolItems` filtered by this — so adding a tool ONCE surfaces it in
    /// BOTH places (fixes the old drift where the HUD silently lacked several tools).
    private enum ToolCat: CaseIterable { case editors, audioBio, connect, visualLearn }

    /// One simple, single-action tool destination. (The two menu-based tools — Drum
    /// Samples and MIDI/Health — are inherently sub-menus, so they stay inline in both
    /// surfaces; everything else flows from this list.)
    private struct ToolItem: Identifiable { let id: String; let title: String; let icon: String; let cat: ToolCat }

    /// The single catalog. Platform-gated tools are appended under the same `#if` that
    /// guards their action in `openTool`, so a tool never appears without a live action.
    private var toolItems: [ToolItem] {
        var items: [ToolItem] = [
            ToolItem(id: "pianoroll", title: "Piano Roll", icon: "pianokeys", cat: .editors),
            ToolItem(id: "sound", title: "Sound", icon: "dial.medium", cat: .editors),
            // "Channels" is now the first-class Mix workspace surface — not duplicated here.
            ToolItem(id: "automation", title: "Automation",
                     icon: "point.topleft.down.curvedto.point.bottomright.up", cat: .editors),
            ToolItem(id: "audioin", title: "Audio In", icon: "mic", cat: .audioBio),
            ToolItem(id: "audioclip", title: "Audio Clip", icon: "waveform", cat: .audioBio),
            // "Breathing" lives on the Bio surface (the one body/breath home) — not duplicated here.
            ToolItem(id: "meditation", title: "Coherence", icon: "waveform.path.ecg", cat: .audioBio),
            ToolItem(id: "routing", title: "Routing",
                     icon: "point.3.connected.trianglepath.dotted", cat: .connect),
            ToolItem(id: "plugins", title: "Plugins", icon: "puzzlepiece.extension", cat: .connect),
            ToolItem(id: "broadcast", title: "Broadcast",
                     icon: "dot.radiowaves.left.and.right", cat: .connect),
        ]
        #if canImport(UniformTypeIdentifiers)
        items.append(ToolItem(id: "importmidi", title: "Import MIDI", icon: "square.and.arrow.down", cat: .editors))
        #endif
        #if canImport(MultipeerConnectivity)
        items.append(ToolItem(id: "livecolabo", title: "Live Colabo", icon: "person.2.wave.2", cat: .connect))
        #endif
        #if canImport(MetalKit) && canImport(UIKit)
        items.append(ToolItem(id: "visual", title: "Visual", icon: "sparkles", cat: .visualLearn))
        #endif
        items.append(ToolItem(id: "learn", title: "Learn", icon: "book", cat: .visualLearn))
        return items
    }

    /// Central action mapping — the one place a tool id opens its editor. Called by both
    /// the grid chips and the HUD menu rows.
    private func openTool(_ id: String) {
        switch id {
        case "pianoroll": showPianoRoll = true
        case "sound": showPatchEditor = true
        case "automation": showAutomation = true
        case "audioin": showInput = true
        case "audioclip": showAudioClip = true
        case "meditation": showMeditation = true
        case "routing": showRouting = true
        case "plugins": showPlugins = true
        case "broadcast": showBroadcast = true
        case "learn": showLearn = true
        #if canImport(UniformTypeIdentifiers)
        case "importmidi": midiImportPresented = true
        #endif
        #if canImport(MultipeerConnectivity)
        case "livecolabo": showLiveColabo = true
        #endif
        #if canImport(MetalKit) && canImport(UIKit)
        case "visual": showVisual = true
        #endif
        default: break
        }
    }

    private func toolItems(_ cat: ToolCat) -> [ToolItem] { toolItems.filter { $0.cat == cat } }

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
                    ForEach(toolItems(.editors)) { t in
                        gridChip(t.title, t.icon) { openTool(t.id) }
                    }
                    Menu {
                        ForEach(Array(BeatPlayer.trackNames.enumerated()), id: \.offset) { idx, name in
                            Button(name) { sampleBrowserTrack = TrackRef(id: idx) }
                        }
                    } label: { gridChipLabel("Drum Samples", "waveform") }
                }
                toolGroup("Audio & Bio") {
                    ForEach(toolItems(.audioBio)) { t in
                        gridChip(t.title, t.icon) { openTool(t.id) }
                    }
                }
                toolGroup("Connect") {
                    ForEach(toolItems(.connect)) { t in
                        gridChip(t.title, t.icon) { openTool(t.id) }
                    }
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
                    ForEach(toolItems(.visualLearn)) { t in
                        gridChip(t.title, t.icon) { openTool(t.id) }
                    }
                }
                Text("Echoelmusic \(Self.appVersionString)")
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

    /// The Session card — since the shell flip (2026-07-06) the Session IS the app
    /// home and this card RETURNS to it: the host (StudioShellView) wires the binding
    /// so setting it true dismisses the studio cover. Same muscle memory, inverted
    /// shell. Static card, no live bio read here (freeze rule).
    private func sessionEntryCard(_ present: Binding<Bool>) -> some View {
        Button { present.wrappedValue = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "circle.circle")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(EchoelTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Breathing Session")
                        .font(EchoelTheme.font(17, .semibold))
                        .foregroundStyle(EchoelTheme.text)
                    Text("The light breathes with you toward your resonance pace")
                        .font(EchoelTheme.font(12))
                        .foregroundStyle(EchoelTheme.dim)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EchoelTheme.dim)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radiusLarge).fill(EchoelTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusLarge)
                .strokeBorder(EchoelTheme.accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to the breathing session")
        .accessibilityHint("Closes the studio and returns to the calm session.")
    }

    /// UNPRESENTED (founder 2026-07-07: "Xy Pads komplett wieder herausnehmen") —
    /// kept compiling for reversibility, no body branch mounts it. The two mood
    /// pads, side by side — SOUND (composition mood; recomposes at the loop
    /// boundary on release) and VISUAL (palette + energy, live via its own leaf).
    private var moodPadsSection: some View {
        HStack(alignment: .top, spacing: 12) {
            MoodXYPad(title: "Sound",
                      xCaption: "dark · bright",
                      yCaption: "still · moving",
                      live: false,
                      x: $soundMoodX, y: $soundMoodY,
                      // LINKED (founder 2026-07-07: "Xy Sound und visuals
                      // verknüpfen"): while the finger moves, the VISUAL mood
                      // follows live (hue/motion/intensity + the visual pad's
                      // dot); the SOUND itself commits on release, at the loop
                      // boundary — one gesture moves the whole atmosphere.
                      onChanged: { x, y in
                          VisualMoodMap.apply(x: x, y: y)
                      },
                      onEnded: { x, y in
                          VisualMoodMap.apply(x: x, y: y)
                          mood.darkness = Float(1 - x)
                          mood.liveliness = Float(y)
                          // A pad gesture is a custom edit — the loaded preset no
                          // longer describes the sound (same rule as the mood editor).
                          moodPresetID = nil
                          moodPresetName = "Custom"
                          recomposeIfRunning()
                      })
            VisualMoodPadLeaf()
        }
    }

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
            // Essentials first (Composition open by default), advanced (Mood) last — the
            // view reads top-down from "what most people touch" to "deep tweaks".
            compositionPanel
            sessionPanel
            transposePanel
            soundPanel
            mixerPanel
            effectsPanel
            masterPanel
            moodPanel
            // visualPanel moved to the very bottom of the page (founder 2026-07-07:
            // "Visual … das müsste ganz nach unten") — rendered after utilityRow.
            // Entrainment now lives on the Bio page (its home) — not duplicated here.
            // The EchoelAI live caption used to sit HERE — a bare paragraph wedged
            // between the Mood and Export cards (founder 2026-07-07: "Das ist hier
            // ungeschickt platziert"). It now lives at the TOP, right under the live
            // bio (`liveNarrationBanner`), where a "what your body is doing to the
            // sound" line belongs — paired with the numbers it explains, in a proper
            // container instead of orphaned between two cards.
        }
    }

    /// EchoelAI's narration of the live bio→sound mapping — ON REQUEST ONLY
    /// (founder 2026-07-09: "Echoel AI soll interaktiver werden und nicht
    /// ungefragt Dinge anzeigen"). While a take plays, a single quiet disclosure
    /// row is the only chrome; the plain-English paragraph appears when the user
    /// opens it (Apple-native disclosure — content on request, never pushed) and
    /// the choice persists. The changing text is still observed ONLY by the
    /// `StudioCaptionView` leaf (freeze rule); the chevron swaps symbols instead
    /// of rotating (no transform animations — Uncodixfy).
    @ViewBuilder private var liveNarrationBanner: some View {
        if running {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    showLiveNarration.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 12))
                            .foregroundStyle(EchoelTheme.dim)
                        Text("What your body is doing to the sound")
                            .font(EchoelTheme.font(12, .semibold))
                            .foregroundStyle(EchoelTheme.dim)
                        Spacer(minLength: 8)
                        Image(systemName: showLiveNarration ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(EchoelTheme.dim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Live narration")
                .accessibilityHint("Shows or hides the plain-language description of how your body shapes the music")
                if showLiveNarration {
                    StudioCaptionView(caption: caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .stroke(EchoelTheme.border, lineWidth: 1))
        }
    }

    // MARK: Panel 1 — Composition (genre · key · tuning · tempo)

    /// Module 1 of the comprehensive interface: the per-part MIXER. Each generated
    /// role (bass · pad · lead) gets a user level layered over the genre balance —
    /// pull the lead down when a genre's melody is too forward, lift the bass, etc.
    /// Applied at compose time (velocity scale), so a change re-balances the take on
    /// the next generate/evolve. A menu-free leaf reading only low-frequency stores.
    private var mixerPanel: some View {
        panel("Mix", "Level per part", isExpanded: $showMix) {
            // The master mix as per-part STRIPS — the same visual language as the drum
            // channel strips below, so the whole Mix panel reads as ONE board (founder:
            // "Mix Level sollten auf dem Hackbrett landen … alles an Ort und Stelle").
            // Each strip co-locates a part's LEVEL with its own bus FX (filter + drive);
            // grouping follows the three real FX buses (bass / melodic / drums). Every
            // binding is the existing one — no new audio wiring. FX default full-open /
            // drive 0 = bit-identical until moved.
            mixStripCard("Bass") {
                EchoelValueField(label: "Level", value: mixBinding(\.bass),
                                 range: MixerStore.range, unit: "", decimals: 2)
                EchoelValueField(label: "Filter", value: bassCutoffBinding,
                                 range: TrackFXStore.cutoffRange, unit: "Hz", decimals: 0)
                EchoelValueField(label: "Drive", value: bassDriveBinding,
                                 range: TrackFXStore.driveRange, unit: "", decimals: 2)
            }
            // Pad + Lead share the melodic FX bus → one strip. The melodic filter tames
            // a shrill lead directly.
            mixStripCard("Melodic · Pad + Lead") {
                EchoelValueField(label: "Pad", value: mixBinding(\.pad),
                                 range: MixerStore.range, unit: "", decimals: 2)
                EchoelValueField(label: "Lead", value: mixBinding(\.lead),
                                 range: MixerStore.range, unit: "", decimals: 2)
                EchoelValueField(label: "Filter", value: melodicCutoffBinding,
                                 range: TrackFXStore.cutoffRange, unit: "Hz", decimals: 0)
                EchoelValueField(label: "Drive", value: melodicDriveBinding,
                                 range: TrackFXStore.driveRange, unit: "", decimals: 2)
            }
            mixStripCard("Drums") {
                EchoelValueField(label: "Level", value: drumsBinding,
                                 range: MixerStore.range, unit: "", decimals: 2)
                EchoelValueField(label: "Filter", value: drumsCutoffBinding,
                                 range: TrackFXStore.cutoffRange, unit: "Hz", decimals: 0)
                EchoelValueField(label: "Drive", value: drumsDriveBinding,
                                 range: TrackFXStore.driveRange, unit: "", decimals: 2)
            }

            Button {
                mixer.resetToUnity()
                beatPlayer.masterLevel = mixer.drums
                setBassFX(.off)
                setMelodicFX(.off)
                setDrumsFX(.off)
                recomposeIfRunning()
            } label: {
                Text("Reset to genre balance")
                    .font(EchoelTheme.font(12, .medium))
                    .foregroundStyle(EchoelTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Sets every part back to the genre's own balance")

            // The Hackbrett — per-drum-channel strips (level · mute/solo · insert FX),
            // co-located here so every mixable channel lives in ONE place (founder:
            // "Mix Level sollten auf dem Hackbrett landen"). Reuses the tested
            // ChannelRackView against BeatPlayer; embedded = no nested scroll, flows in
            // the studio's own ScrollView. No new modal — render-safe.
            Divider().overlay(EchoelTheme.border).padding(.vertical, 2)
            ChannelRackView(embedded: true)
        }
    }

    /// A per-part mix STRIP — a titled group (Level + its bus FX) styled like the drum
    /// channel strips, so the master voices and the drum channels read as one Hackbrett.
    /// Pure layout over existing bindings; reads only low-frequency stores → render-safe.
    @ViewBuilder
    private func mixStripCard<Content: View>(_ title: String,
                                             @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(EchoelTheme.font(13, .semibold))
                .foregroundStyle(EchoelTheme.text)
            content()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    /// Bass-bus filter cutoff. Full-open (max) disengages the filter; lower engages a
    /// low-pass. Applied LIVE to the sub voice via the lock-free insert path.
    private var bassCutoffBinding: Binding<Float> {
        Binding(get: { trackFX.bass.cutoffHz },
                set: { v in
                    let open = v >= TrackFXStore.cutoffRange.upperBound
                    setBassFX(TrackFX(filter: open ? .off : .lowPass, cutoffHz: v,
                                      resonance: trackFX.bass.resonance, drive: trackFX.bass.drive))
                })
    }

    /// Bass-bus saturation drive (0 = clean).
    private var bassDriveBinding: Binding<Float> {
        Binding(get: { trackFX.bass.drive },
                set: { v in
                    setBassFX(TrackFX(filter: trackFX.bass.filter, cutoffHz: trackFX.bass.cutoffHz,
                                      resonance: trackFX.bass.resonance, drive: v))
                })
    }

    /// Persist the bass insert (survives relaunch) AND push it to the audio voice.
    private func setBassFX(_ fx: TrackFX) {
        trackFX.set(fx, for: .bass)
        subBass.setInsert(fx)
    }

    /// Melodic-bus filter cutoff. Full-open (max) disengages; lower engages a low-pass.
    private var melodicCutoffBinding: Binding<Float> {
        Binding(get: { trackFX.melodic.cutoffHz },
                set: { v in
                    let open = v >= TrackFXStore.cutoffRange.upperBound
                    setMelodicFX(TrackFX(filter: open ? .off : .lowPass, cutoffHz: v,
                                         resonance: trackFX.melodic.resonance, drive: trackFX.melodic.drive))
                })
    }

    /// Melodic-bus saturation drive (0 = clean).
    private var melodicDriveBinding: Binding<Float> {
        Binding(get: { trackFX.melodic.drive },
                set: { v in
                    setMelodicFX(TrackFX(filter: trackFX.melodic.filter, cutoffHz: trackFX.melodic.cutoffHz,
                                         resonance: trackFX.melodic.resonance, drive: v))
                })
    }

    /// Persist the melodic insert AND push it to BOTH melodic voices (pad/harmony `synth`
    /// and the dedicated `leadSynth`), so the whole melody — the shrill lead included — is
    /// covered by one "Melodic" control.
    private func setMelodicFX(_ fx: TrackFX) {
        trackFX.set(fx, for: .melodic)
        synth.setInsert(fx)
        leadSynth?.setInsert(fx)
    }

    /// Drums-bus filter cutoff. Full-open (max) disengages; lower engages a low-pass
    /// fanned across all 8 drum channels (a low-pass this way == a true bus filter).
    private var drumsCutoffBinding: Binding<Float> {
        Binding(get: { trackFX.drums.cutoffHz },
                set: { v in
                    let open = v >= TrackFXStore.cutoffRange.upperBound
                    setDrumsFX(TrackFX(filter: open ? .off : .lowPass, cutoffHz: v,
                                       resonance: trackFX.drums.resonance, drive: trackFX.drums.drive))
                })
    }

    /// Drums-bus saturation drive (0 = clean). Applied per drum channel — each hit
    /// saturates independently, preserving transients.
    private var drumsDriveBinding: Binding<Float> {
        Binding(get: { trackFX.drums.drive },
                set: { v in
                    setDrumsFX(TrackFX(filter: trackFX.drums.filter, cutoffHz: trackFX.drums.cutoffHz,
                                       resonance: trackFX.drums.resonance, drive: v))
                })
    }

    /// Persist the drums insert AND fan it across all 8 `BeatPlayer` channels. There is no
    /// single drums-bus node (the 8 voices attach individually), so the whole-kit control
    /// writes every channel's insert via the existing tested `setFX` path — no new audio
    /// code. `trackFX.drums` is the bus master; the (currently unpresented) Channel Rack is
    /// the per-channel override. Off (`.off`) = full-open + drive 0 = bit-identical to before.
    private func setDrumsFX(_ fx: TrackFX) {
        trackFX.set(fx, for: .drums)
        var ch = BeatPlayer.ChannelFX()
        ch.type = fx.filter.rawValue
        ch.cutoff = fx.cutoffHz
        ch.resonance = fx.resonance
        ch.drive = fx.drive
        for i in BeatPlayer.trackNames.indices {
            beatPlayer.setFX(track: i, ch)
        }
    }

    /// A binding to one mixer level that re-balances the running take when changed.
    private func mixBinding(_ keyPath: ReferenceWritableKeyPath<MixerStore, Float>) -> Binding<Float> {
        Binding(get: { mixer[keyPath: keyPath] },
                set: { mixer[keyPath: keyPath] = $0; recomposeIfRunning() })
    }

    /// The Drums fader drives BeatPlayer's master level LIVE — it multiplies each hit as
    /// it fires, so no recompose is needed (the change is heard on the next beat).
    private var drumsBinding: Binding<Float> {
        Binding(get: { mixer.drums },
                set: { mixer.drums = $0; beatPlayer.masterLevel = $0 })
    }

    private var compositionPanel: some View {
        panel("Composition", "Genre · key · tuning · tempo", isExpanded: $showComposition) {
            genrePicker
            // beatModeRow REMOVED (founder 2026-07-07: "Schmeiß den Beat komplett
            // raus") — pure meditative Flächen only. The row stays defined below,
            // just unpresented (reversible).
            // soundSourceRow REMOVED (founder 2026-07-07: "Real Instruments komplett
            // raus. Also auch den Schalter weg") — pure warm synth, no Real/Synth
            // switch and no sampled-instrument path anywhere.
            tonartRow
            kammertonRow
            tuningRow
            tempoRow
            // placeRow/weatherRow moved to the SESSION card (R1 2026-07-10):
            // buried at the bottom of this card, the founder couldn't find them.
        }
    }

    // MARK: - Entry rows (R2/R3 2026-07-10 — visible doors to existing sheets)

    #if canImport(MultipeerConnectivity)
    /// Live Colabo door: play together nearby — share the session, see each
    /// person's own pulse side by side. Presents the EXISTING sheet slot.
    private var liveColaboRow: some View {
        entryRow("Live Colabo", "Play together, nearby — session share · pulse side by side",
                 icon: "dot.radiowaves.left.and.right") { showLiveColabo = true }
    }
    #endif

    /// Learn & News door: the school content plus the opt-in "News & live
    /// events" push toggle (E4). Presents the EXISTING sheet slot.
    private var learnRow: some View {
        entryRow("Learn & News", "How it works · safety · stay in the loop",
                 icon: "book") { showLearn = true }
    }

    /// Shared chrome for a full-width door row (matches the card look:
    /// solid fill, 1 px border, chevron — Uncodixfy).
    private func entryRow(_ title: String, _ subtitle: String, icon: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(EchoelTheme.dim)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(EchoelTheme.font(15, .semibold)).foregroundStyle(EchoelTheme.text)
                    Text(subtitle)
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12)).foregroundStyle(EchoelTheme.dim)
            }
            .padding(14)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    // MARK: Panel 1b — Session (name preview · place · weather)

    /// The session's identity, made VISIBLE: the live stamped name (the value
    /// of the place/weather features shows itself — the city appears in the
    /// name the moment it resolves) plus the two opt-in toggles that feed it.
    private var sessionPanel: some View {
        panel("Session", "Name · place · weather", isExpanded: $showSession) {
            SessionNamePreviewLeaf()
            #if canImport(CoreLocation)
            placeRow
            #endif
            #if canImport(WeatherKit) && canImport(CoreLocation)
            weatherRow
            #endif
        }
    }

    #if canImport(CoreLocation)
    /// Opt-in place token in the session name (E2, default OFF). One coarse
    /// city lookup on device; the token lands after the date in every
    /// session/export name (Echoel_2026-07-10_Hamburg_Am_72bpm_A440).
    private var placeRow: some View {
        @Bindable var locationNamer = locationNamer
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $locationNamer.enabled) {
                Text("Place in session name")
                    .font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
            }
            .tint(EchoelTheme.accent)
            .accessibilityHint("Stamps your city into session and export names. Resolved on this device, never stored or sent anywhere.")
            // Always say what this does; once on, say clearly what happened.
            Text(placeStatusLine)
                .font(EchoelTheme.font(11))
                .foregroundStyle(EchoelTheme.dim)
        }
    }

    /// One clear line for the place row in every state (off / looking up /
    /// resolved / denied) — so it's never ambiguous what the location does.
    private var placeStatusLine: String {
        guard locationNamer.enabled else {
            return "Adds your city to the name — resolved on device, never sent."
        }
        if locationNamer.denied {
            return "Location is off for Echoel in Settings — names stay without a place."
        }
        if locationNamer.placeToken.isEmpty {
            return "Looking up your city…"
        }
        return "In the name: \(locationNamer.placeToken)"
    }
    #endif

    #if canImport(WeatherKit) && canImport(CoreLocation)
    /// E3b: opt-in weather flavour (default OFF). One coarse fetch at Start
    /// salts the structural skeleton — the body stays the primary driver.
    /// Carries the Apple-required Weather attribution.
    private var weatherRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $weatherEnabled) {
                Text("Weather shapes the music")
                    .font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
            }
            .tint(EchoelTheme.accent)
            .accessibilityHint("One coarse weather lookup per session flavours sound and image. Each influence has its own intensity — mix it in or out. The body stays the main driver.")
            if weatherEnabled {
                Text(!locationNamer.enabled
                     ? "Needs \"Place in session name\" for a coarse location."
                     : (weatherDescriptor.isEmpty ? "Sky reading arrives at Start."
                                                  : "Now: \(weatherDescriptor)"))
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.dim)

                // Separate, individually-mixable influences (founder: "Klang und
                // Bild aber getrennte und mehrere Parameter" + an intensity slider
                // "damit man das Wetter rein und rausmischen kann"). Each row says
                // what it changes; 0 = off (no change), 1 = fully the weather.
                weatherMixGroup("Sound · Klang", params: WeatherMood.Param.allCases.filter { $0.domain == .sound })
                weatherMixGroup("Image · Bild", params: WeatherMood.Param.allCases.filter { $0.domain == .visual })

                // Apple WeatherKit attribution requirement.
                if let attributionURL = URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/") {
                    Link(" Weather", destination: attributionURL)
                        .font(EchoelTheme.font(10))
                        .foregroundStyle(EchoelTheme.dim)
                        .accessibilityLabel("Apple Weather data attribution")
                }
            }
        }
    }

    /// One titled block of weather mixers (Sound or Image), in the mix-strip look.
    @ViewBuilder
    private func weatherMixGroup(_ title: String, params: [WeatherMood.Param]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.dim)
            ForEach(params) { param in
                WeatherMixRow(param: param)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    /// E3b: one coarse fetch per session start; the salt lands on the NEXT
    /// re-seed (evolve/lock-snap) — never blocks the first sound.
    private func fetchWeatherFlavour() {
        weatherContribution = nil
        guard weatherEnabled, let fix = locationNamer.lastFix else { return }
        Task { @MainActor in
            guard let snap = await weatherProvider.snapshot(for: fix), running else { return }
            weatherContribution = WeatherMood.contribution(for: snap)
        }
    }
    #endif

    /// The drum layer, one segmented choice (founder: "Beat soll ausschaltbar sein
    /// und tendenziell eher schamanisch ur-rhythmisch"). Off = pure Flächen; Pulse =
    /// the deep, steady shamanic heartbeat drum (default); Genre = the style's own
    /// groove. Takes musical effect at the next loop boundary (never a mid-bar cut).
    private var beatModeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            labeledRow("Beat") {
                Picker("Beat", selection: $beatMode) {
                    ForEach(BeatMode.allCases) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.segmented)
                .onChange(of: beatMode) { _, _ in recomposeIfRunning() }
                .accessibilityLabel("Beat mode")
                .accessibilityHint("Off is pure textures, Pulse is a deep steady heartbeat drum, Genre is the style's own rhythm")
            }
            if beatMode == .pulse {
                Text("A deep, steady drum — it thins out as your body settles.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        // The touch instrument plays the same tone system — and its note→colour
        // mapping reads this table, so the colour follows the SOUNDING pitch.
        touchSynth?.setTuningCents(cents)
    }

    private var genrePicker: some View {
        labeledRow("Genre") {
            Picker("Genre", selection: $style) {
                // Founder 2026-07-11 "Alles rein. Logisch sortiert. Gehe tief rein":
                // every genre offered, grouped by sound-world so the calm meditative
                // set stays first and rock/electronic/acoustic worlds open up. `.menu`
                // Picker renders each Section as a grouped header — no new sheet, no
                // high-frequency bio read, so the render-safety rules hold.
                ForEach(MusicStyle.Category.allCases) { cat in
                    Section(cat.title) {
                        ForEach(cat.genres) { s in Text(s.displayName).tag(s) }
                    }
                }
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
        return EchoelValueField(label: "Concert pitch A4", value: $session.a4Hz, range: 380...500, unit: "Hz",
                                onCommit: { synth.setTuning(a4Hz: session.a4Hz); subBass.setTuning(a4Hz: session.a4Hz); touchSynth?.setTuning(a4Hz: session.a4Hz); recomposeIfRunning() })
    }

    private var tempoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            // THE tempo control (founder 2026-07-04: "zwei Anzeigen irritieren immernoch"):
            // one Kammerton-style row whose number RUNS ALONG with the live biofeedback BPM
            // (4 decimals) and freezes on lock — see BodyTempoField. The transport bar shows
            // NO tempo number anymore; the strip's pulse is the one live number in the chrome.
            // BodyTempoField is a LEAF so its ~10 Hz pulse read never rebuilds this panel
            // (freeze rule — the genre/key Pickers above must stay stable).
            // NOTE: lock adoption now happens INSIDE the controls (BodyTempoField, transport
            // lock button, tap tempo) — the old onChange here would have overwritten a
            // body-value lock with the clock tempo an instant later.
            BodyTempoField(onLockChanged: { recomposeIfRunning() })

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
                    lockedBPM = (bpm * 10).rounded() / 10
                    metronome.bpm = lockedBPM
                    // ALWAYS push the clock (not only while running): the lockBPM onChange
                    // below freezes at the CLOCK's current tempo, so the clock must already
                    // carry the tapped value when that fires — otherwise tapping while
                    // stopped would freeze a stale tempo instead of the tap. setTempo while
                    // stopped just stores the value (no tick scheduling), safe.
                    beatPlayer.pattern.setTempo(lockedBPM)
                    lockBPM = true   // AFTER the clock carries the tap (onChange adopts clock)
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
            // Master volume lives in its own view (MasterVolumeField) so an automation
            // lane rewriting audioEngine.masterVolume re-renders only that field, not the
            // menu-hosting studio body. (Was the remaining take-time Picker-freeze source.)
            MasterVolumeField()

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
        panel("EchoelSynth", "Play it with your fingers — immersive sound↔light in a floating window you can move + resize", isExpanded: $showVisualSettings) {
            Button {
                floatingVisualVisible.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: floatingVisualVisible ? "eye.slash" : "eye")
                    Text(floatingVisualVisible ? "Hide visual window" : "Show visual window")
                        .font(EchoelTheme.font(13, .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(floatingVisualVisible ? EchoelTheme.onPrimary : EchoelTheme.text)
                .padding(.horizontal, 12).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(floatingVisualVisible ? EchoelTheme.accent : EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .accessibilityLabel(floatingVisualVisible ? "Hide the floating visual window" : "Show the floating visual window")
            Text("Look").font(EchoelTheme.font(10, .medium)).foregroundStyle(EchoelTheme.dim)
            visualLookStrip
            visualLookCustomizer
            // visualBlendControls REMOVED from the surface (founder 2026-07-07:
            // minimize — the A/B "mischend" mix was extra clicking). Still defined
            // below, reversible; the migration in onAppear clears any lingering blend.
            visualPresetRow
            MusicColourRowView()
            visualAdjustFields
            Text("Colour defaults to the heard tone octave-transposed into visible light (after Hans Cousto's Cosmic Octave, rendered via CIE 1931); Hue/Saturation rotate the palette for VJ/performance use. Motion is capped so the flash rate always stays under the 3 Hz safety limit.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            touchSoundSection
        }
    }

    /// PLAY-SURFACE SOUND (founder 2026-07-08: "man soll auch Presets bzw. Sound-
    /// Charakter … individuell einstellen können" + "morphbar … je nachdem wo man
    /// sich befindet"). The fullscreen visual is a touch instrument with its OWN
    /// voice: pick its sound here (default: follow the take), and set how much
    /// sliding up the surface opens the tone (the position morph). Inline — no new
    /// sheet (the modifier-chain metadata rule).
    private var touchSoundSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Play surface sound")
                .font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
                .padding(.top, 4)
            Text("What your fingers sound like on the fullscreen visual. Take sound follows the generated music; pick a patch to give the surface its own voice.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    touchPatchChip(name: "Take sound", selected: touchPatchID.isEmpty) {
                        touchPatchID = ""
                        syncTouchSound()
                    }
                    ForEach(patchStore.patches) { p in
                        touchPatchChip(name: p.name, selected: touchPatchID == p.id.uuidString) {
                            touchPatchID = p.id.uuidString
                            touchSynth?.apply(p)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            EchoelValueField(label: "Position morph", value: $touchMorphDepth,
                             range: 0...1, unit: "", decimals: 2)
            // SLIDE EXPRESSION (founder 2026-07-08: "Auf dem Gitter hin und her
            // sliden verändert den Sound: Filter, ein bisschen Vibrato, Chorus …
            // Glide bzw. Portamento kann man auch einstellen"): a travelling
            // finger opens vibrato + ensemble on the touch voice (decays when the
            // finger rests); Glide > 0 turns fret-crossing retriggers into a
            // singing portamento. All per-take live values, flash/audio-safe.
            Text("Sliding the finger opens vibrato and ensemble width; Glide makes slides sing between notes instead of re-striking.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            EchoelValueField(label: "Slide vibrato", value: $touchSlideVibrato,
                             range: 0...1, unit: "", decimals: 2)
            EchoelValueField(label: "Slide ensemble", value: $touchSlideChorus,
                             range: 0...1, unit: "", decimals: 2)
            EchoelValueField(label: "Glide", value: $touchGlide,
                             range: 0...0.4, unit: "s", decimals: 2)
        }
    }

    private func touchPatchChip(name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(EchoelTheme.font(12, .medium))
                .foregroundStyle(selected ? EchoelTheme.onPrimary : EchoelTheme.text)
                .padding(.horizontal, 11).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(selected ? EchoelTheme.accent : EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) play-surface sound")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Panel — Entrainment (biofeedback-driven brainwave stimulus)

    /// Flash-safe (≤3 Hz) visual pulse for the armed entrainment, else 0. Only MANUAL band
    /// mode couples the visual — a stable, LOW-frequency read (`entrainmentEnabled` +
    /// `entrainmentManualBand`), so it never reads the 10 Hz auto target in the body (the
    /// freeze rule). Auto mode keeps the HR-derived pulse.
    private var entrainmentVisualPulseHz: Double {
        guard synth.entrainmentEnabled, let band = synth.entrainmentManualBand else { return 0 }
        return BioEntrainmentDirector.visualHz(for: band)
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
                        // Tapping the ACTIVE preset again DESELECTS it (clears the
                        // highlight; the applied Intensity/Detail/Motion/Spread stay,
                        // still editable). Fixes the founder's "klickt man an und geht
                        // nicht mehr weg" — the Blend strip already toggles this way,
                        // the Preset strip was the one selection that never cleared.
                        Button {
                            if selected { visualPresetID = "" }
                            else { applyVisualPreset(preset) }
                        } label: {
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
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .accessibilityHint(selected ? "Double tap to clear" : "Double tap to apply")
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
        // ALIGNED with the Visual window's top-bar slider (founder 2026-07-07: "das
        // hauptmenü dementsprechend angleichen"): a Donuts pill (a different renderer) +
        // a slider that scrubs the calm metal looks — SAME handling in both places, fewer
        // buttons than the old labelled strip. The busy/technical looks (Rings/Cymatics/
        // Prism/Lissajous/Scope/Fractal) stay in the shader (indices unchanged, reversible)
        // but aren't surfaced here, so nobody has to tap past Prism to reach calm. Writes
        // the shared visual.style / visual.spectralDonuts keys (single source of truth).
        HStack(spacing: 10) {
            Button { spectralDonuts = true } label: {
                Text("Donuts")
                    .font(EchoelTheme.font(12, .semibold))
                    .foregroundStyle(spectralDonuts ? EchoelTheme.onPrimary : EchoelTheme.text)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(spectralDonuts ? EchoelTheme.accent : EchoelTheme.fill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Donuts visual look")
            .accessibilityAddTraits(spectralDonuts ? [.isSelected] : [])

            // Dragging the slider morphs STUFENLOS between the looks (continuous crossfade
            // via style/styleB/blend, mapping in LookBlendMap) AND turns Donuts off (see
            // setter), so the two controls never both claim "active".
            if LookBlendMap.maxPosition(for: sliderLooks) > 0 {
                Slider(value: lookScrub, in: 0...LookBlendMap.maxPosition(for: sliderLooks))
                    .tint(EchoelTheme.accent)
                    .accessibilityLabel("Visual look")
                    .accessibilityValue(currentLookName)
            }

            Text(spectralDonuts ? "Donuts" : currentLookName)
                .font(EchoelTheme.font(12, .medium))
                .foregroundStyle(EchoelTheme.dim)
                .lineLimit(1)
                .frame(width: 54, alignment: .trailing)
        }
    }

    /// CUSTOMIZE what the slider fades through (founder 2026-07-08: "das menü überarbeiten
    /// damit man das was im slider passiert selbst customizen kann … mehr Optionen"). Every
    /// look in the full library is a toggle chip; selected chips form the slider's sequence
    /// (canonical order), persisted in the shared `visual.sliderLooks` key so BOTH sliders
    /// (this menu + the fullscreen window bar) fade through the same custom set. At least one
    /// look always stays on (LookBlendMap.toggling refuses to empty the set). The little
    /// index badge shows the fade ORDER so the user reads left→right what the slider will do.
    private var visualLookCustomizer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Slider looks — tap to add or remove; the slider fades through these in order")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LookBlendMap.library, id: \.index) { look in
                        let pos = sliderLooks.firstIndex(of: look.index)
                        let on = pos != nil
                        Button {
                            let next = LookBlendMap.toggling(look.index, in: sliderLooks)
                            sliderLooksRaw = LookBlendMap.string(from: next)
                            // If the removed look was the one on screen, snap the visual to a
                            // look still in the sequence right away (don't wait for a drag), so
                            // the customizer feels live. Donuts stays whatever it was.
                            if !spectralDonuts, !next.contains(visualStyle) {
                                visualStyle = next.first ?? visualStyle
                                visualStyleB = 0
                                visualBlend = 0
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if let pos { Text("\(pos + 1)").font(EchoelTheme.font(10, .bold).monospacedDigit()) }
                                Text(look.name).font(EchoelTheme.font(12, .medium))
                            }
                            .foregroundStyle(on ? EchoelTheme.onPrimary : EchoelTheme.text)
                            .padding(.horizontal, 11).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                                .fill(on ? EchoelTheme.accent : EchoelTheme.fill))
                            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                                .strokeBorder(EchoelTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(look.name) look")
                        .accessibilityValue(on ? "in the slider, position \((pos ?? 0) + 1)" : "not in the slider")
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                        .accessibilityHint(on ? "Double tap to remove from the slider" : "Double tap to add to the slider")
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    /// Slider position ⇄ current look state, mirroring FloatingVisualWindow.lookScrub
    /// (same LookBlendMap, same shared keys — the two sliders are one control). The
    /// setter also clears Donuts so scrubbing the look always lands on a metal field.
    private var lookScrub: Binding<Double> {
        Binding(
            get: { LookBlendMap.position(a: visualStyle, b: visualStyleB, frac: Float(visualBlend), sequence: sliderLooks) },
            set: { v in
                spectralDonuts = false
                let m = LookBlendMap.blend(at: v, sequence: sliderLooks)
                if visualStyle != m.a { visualStyle = m.a }
                if visualStyleB != m.b { visualStyleB = m.b }
                visualBlend = Double(m.frac)
            }
        )
    }

    /// Display name of the look nearest the slider position (no per-stop labels).
    private var currentLookName: String {
        LookBlendMap.nearestName(
            at: LookBlendMap.position(a: visualStyle, b: visualStyleB, frac: Float(visualBlend), sequence: sliderLooks),
            sequence: sliderLooks)
    }

    /// The "mischend" controls: a SECOND look to overlap with the primary, plus a Mix
    /// ratio (0 = pure primary, 1 = pure secondary). Only shown for the Metal field
    /// looks (Donuts is a different renderer that can't blend yet — next cycle). Tapping
    /// the already-selected B clears the blend back to pure A (Mix → 0), so the strip
    /// itself is the on/off too.
    @ViewBuilder
    private var visualBlendControls: some View {
        if !spectralDonuts {
            // ONE source of truth for the look roster: LookBlendMap.library (curated,
            // founder 2026-07-08 "weniger ist mehr") — this strip can never drift from
            // the slider/customizer again.
            let bLooks: [(String, Int)] = LookBlendMap.library.map { ($0.name, $0.index) }
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
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .accessibilityHint(selected ? "Double tap to remove the blend" : "Double tap to blend")
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
                    // visualBlendControls REMOVED here too (founder 2026-07-07 minimize) —
                    // the fullscreen VJ overlay mirrors the inline panel, so both drop the
                    // A/B blend. SAME definitions as the inline panel (visualPresetRow +
                    // visualAdjustFields) so the two surfaces can never drift apart.
                    visualPresetRow
                    visualAdjustFields
                    // Projection output: this chrome-free, keep-awake canvas IS the beamer
                    // image — mirror it to a projector/TV via AirPlay (Control Center →
                    // Screen Mirroring). Tap the canvas to hide these controls for a clean
                    // projected picture. (Dedicated dual-screen — device = controls, beamer
                    // = visual only — needs an Info.plist scene manifest + device check, a
                    // separate cycle.) Only shown while the panel is open, so it never
                    // appears in the projected image.
                    Label("Project: mirror to a screen via AirPlay", systemImage: "airplayvideo")
                        .font(EchoelTheme.font(10, .medium))
                        .foregroundStyle(EchoelTheme.dim)
                        .padding(.top, 2)
                        .accessibilityHint("Use Control Center Screen Mirroring to project this visual")
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
            running || showVisual || showMeditation
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
        visualIntensity = Double(p.intensity)
        visualDetail = Double(p.detail)
        visualMotion = Double(p.motion)
        visualSpread = Double(p.spread)
        // A palette LOOK (e.g. Vapor) carries hue/saturation and applies them too, so
        // one tap sets a full coherent world. Presets that leave these nil keep the
        // physical tone→light colour untouched ("the colour is the heard tone").
        if let h = p.hue { visualHue = Double(h) }
        if let s = p.saturation { visualSaturation = Double(s) }
        visualPresetID = p.id
    }

    /// The six live visual adjust fields — ONE definition, used by BOTH the inline Visual
    /// panel and the fullscreen VJ overlay so the controls are identical everywhere
    /// (founder: "easy to understand/control" — no drift, one place to change). The energy
    /// fields (Intensity/Detail/Motion/Spread) clear the preset selection on edit since they
    /// then diverge from it; Hue/Saturation are palette-only and leave the preset intact.
    @ViewBuilder private var visualAdjustFields: some View {
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

    // musicColourRow now lives in its OWN leaf (`MusicColourRowView`, end of file):
    // it reads the bus's MusicalFrame, which republishes on EVERY sequencer step
    // (~5-8 Hz while playing) — read here it made the whole Visual panel subtree
    // re-evaluate at that rate (Ruckeln while dragging the look slider mid-take).
    // THE freeze rule: high-frequency @Observable reads only in leaf bodies.

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

    /// Current effective tempo. ALWAYS the authoritative clock (`pattern.tempo`, relayed to
    /// Transport) — never a parallel `lockedBPM` copy. `lockBPM` only decides whether
    /// `generate()` re-locks the clock to the saved tempo or follows the body; while locked,
    /// every edit path keeps `lockedBPM` in lockstep with `pattern.tempo`, so this single
    /// reader matches the transport bar, the compose field, the click, the export and the
    /// filename — the fix for "die BPM ist nicht überall konsistent".
    private var currentTempo: Double { beatPlayer.pattern.tempo }

    /// Stamp the chosen effect character on the live FX chain (independent of genre).
    private func applyFX() {
        fxCharacter.apply(to: synth.fxChain, bpm: currentTempo, genre: style)
        if let touchSynth { fxCharacter.apply(to: touchSynth.fxChain, bpm: currentTempo, genre: style) }   // same room for played notes
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
        if running { scheduleGenerate(reason: "user-edit") } else { applySoundLive() }
    }

    /// Coalesce rapid recompose requests into a single `generate()` after a short
    /// quiet window, so a cascade of control changes reloads the pattern just once.
    ///
    /// `auto` re-seeds (the evolve loop and the lock-snap) are additionally
    /// RATE-LIMITED to one per `minAutoSeedGap`: the music can never re-seed faster
    /// than a musical phrase, no matter how many automatic triggers fire. A user
    /// edit (`auto: false`) stays instant (140 ms). This makes a re-seed "flood"
    /// structurally impossible rather than merely unlikely.
    private func scheduleGenerate(auto: Bool = false, reason: String) {
        // Remember WHY for the breadcrumb (device log 1783370283: an unexplained
        // "generate: 8 notes" mid-take — the log could not say what triggered it).
        // Coalescing means the LAST scheduled reason wins, which is also the one
        // whose parameters the generate actually uses.
        pendingGenerateReason = reason
        regenTask?.cancel()
        // 0.45 s quiet window for user edits: one decisive tap still lands fast, but
        // SCROLLING through a Picker (each highlighted option fires onChange) coalesces
        // into ONE recompose after the hand settles — device log 1783177585: five
        // generates in four seconds while browsing the genre menu, audible chaos.
        var delay = 0.45
        if auto {
            let since = Date().timeIntervalSince(lastSeedAt)
            if since < minAutoSeedGap { delay = max(delay, minAutoSeedGap - since) }
            // Claim the anti-flood floor at SCHEDULE time, not only when generate()
            // runs: several auto triggers can fire within one window (lock-snap +
            // evolve tick land together the moment a pulse locks). Advancing the
            // floor to this reseed's run time makes the next auto trigger compute a
            // full gap and collapse into it — no rapid burst of re-seeds.
            lastSeedAt = Date().addingTimeInterval(delay)
        } else {
            // User edits get their own gentler floor: at most one recompose every ~2 s.
            // Taps 0.7–1.5 s apart (browsing options) would slip past the quiet window
            // alone — the same log shows they did. The LAST edit always wins (each call
            // cancels the pending task), so the sound lands on what the user chose.
            let since = Date().timeIntervalSince(lastSeedAt)
            let minUserGap = 2.0
            if since < minUserGap { delay = max(delay, minUserGap - since) }
        }
        regenTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, running else { return }
            // Re-seeds swap notes into a playing transport; they never restart a
            // transport the user stopped from the transport bar (see generate()).
            generate(startTransport: false)
        }
    }

    // MARK: - Utilities (export · projects)

    /// Export lives behind ONE compact header (minimal-but-works, 2026-07-06E):
    /// the default page shows only Bio strip · Start · pads; capturing a loop is
    /// a deliberate act, one tap away.
    private var utilityRow: some View {
        panel("Export", "WAV loop · keep what just played", isExpanded: $showExport) {
        VStack(spacing: 10) {
            if !hasComposed {
                // The export/keep/save buttons below are disabled until there's a take —
                // say WHY, so a first-run user doesn't read the greyed buttons as broken.
                // Name the REAL button (audit 2026-07-09: no "Generate" exists — first-run
                // users hunted for it and read the greyed buttons as broken). Video
                // recording lives in the floating visual window, not here.
                Text("Tap 'Create from Within' first — then you can export the loop as a WAV.")
                    .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            .disabled(isExporting || !hasComposed)
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
            .disabled(isExporting || !hasComposed)
            .accessibilityHint("Keeps the last bars you just heard as a WAV loop, without replaying them")

            // MIDI export removed (founder 2026-07-02: "Midi Quatsch kann auch weg").
            // The WAV export below now carries the key/tempo/tuning/genre in its name.

            HStack(spacing: 10) {
                Button { saveName = session.sessionName(bpm: beatPlayer.pattern.tempo); showSaveDialog = true } label: {
                    Label("Save", systemImage: "tray.and.arrow.down")
                        .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                }
                .buttonStyle(.plain)
                .disabled(!hasComposed)
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
        }   // panel("Export")
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
            // Changing the loop size rebuilds the arrangement to that many bars so the change
            // takes musical effect at once AND the audio stays in sync with the "bar N/M"
            // indicator (which switches to the new N immediately). No-op when not playing.
            .onChange(of: loopBars) { _, _ in recomposeIfRunning() }
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

    // MARK: - Camera pulse readout
    //
    // Extracted to `PulseMeasurementView` (its own `View` struct) so its ~10 Hz
    // `cameraRPPG` reads no longer register the root `body` as an observer — that 10 Hz
    // invalidation was tearing down open Tonart/Genre `.menu` Pickers while playing.

    // MARK: - Open projects sheet

    private var openSheet: some View {
        NavigationStack {
            List {
                if projects.projects.isEmpty {
                    Text("No saved projects yet.").foregroundStyle(EchoelTheme.dim)
                }
                ForEach(projects.projects) { p in
                    HStack(spacing: 8) {
                        Button { open(p); showOpen = false } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.callout.weight(.medium)).foregroundStyle(EchoelTheme.text)
                                Text("\(p.style.displayName) · \(p.key.shortName) · \(String(format: "%.0f", p.bpm)) BPM")
                                    .font(.caption).foregroundStyle(EchoelTheme.dim)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        ShareLink(item: SharedEchoelProject(project: p),
                                  preview: SharePreview(p.name)) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15)).foregroundStyle(EchoelTheme.dim)
                                .frame(width: 44, height: 44)   // ≥44pt tap target (a11y)
                                .contentShape(Rectangle())
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
        // THE PERFORMANCE MOMENT (founder 2026-07-06B: "wow", music + visual as ONE
        // experience): Start takes the immersive visual FULLSCREEN for the take.
        // Stop restores what the user had before — unless they changed the window
        // themselves mid-take (their in-take choice is respected, see stop path).
        // The fullscreen overlay's size button is the obvious one-tap way out.
        goImmersiveForTake()
        // One fresh musical identity PER TAKE: the pre-lock (no-body) structure seed is
        // drawn here once and then held, so warm-up recomposes/edits stay the same piece.
        takeFallbackSeed = UInt64.random(in: 1...UInt64.max)
        #if canImport(WeatherKit) && canImport(CoreLocation)
        fetchWeatherFlavour()   // E3b: non-blocking; salt lands on the next re-seed
        #endif
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
            pendingGenerateReason = "start"
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
            // Wait until the pulse is SETTLED — confident AND flat for ~3 s — so the body
            // re-seed (which latches the take tempo) uses a reading whose warm-up descent has
            // actually FINISHED. Confidence alone fires on the falling tail (device log:
            // locked 87 → pulse kept dropping to 69 → "springt nach oben"). Generous timeout:
            // settling can take ~25 s on a slow lock; past that we keep the current take.
            while !cameraRPPG.isSettled {
                guard running, !Task.isCancelled else { return }
                if Date().timeIntervalSince(start) > 45 { return }   // never settled → keep current take
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard running, !Task.isCancelled else { return }
            EchoelCrashLog.breadcrumb("rPPG settled → snap re-seed bpm=\(Int(cameraRPPG.displayBPM))")
            scheduleGenerate(auto: true, reason: "lock-snap")   // re-seed (rate-limited; coalesces with the evolve tick)
        }
        #endif
    }

    private func stopEverything() {
        running = false
        tempoSeededFromBody = false      // next take re-seeds tempo from a fresh pulse
        lastGenBody = nil                // next Start re-captures a fresh body baseline (evolve hold)
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
        synth.setBreathSwell(depth: 0)       // stop the 0.1 Hz breath pacing
        stopBioSource()
        restorePreTakeVisual()
        EchoelCrashLog.breadcrumb("stopEverything: transport + all voices released")
    }

    /// Stage the immersive fullscreen visual for a take (Start). Remembers the prior
    /// window state so Stop can put it back.
    private func goImmersiveForTake() {
        #if canImport(MetalKit) && canImport(UIKit)
        let d = UserDefaults.standard
        preTakeVisualVisible = d.object(forKey: "visual.floating.visible") as? Bool ?? true
        preTakeVisualSize = d.object(forKey: "visual.floating.size") as? Int
        d.set(true, forKey: "visual.floating.visible")
        d.set(FloatingVisualWindow.WindowSize.fullscreen.rawValue, forKey: "visual.floating.size")
        #endif
    }

    /// Restore the pre-take window — but ONLY if the take ended still in the exact
    /// state Start staged (visible + fullscreen). A user who exited fullscreen or hid
    /// the window mid-take made a choice; Stop must not override it.
    private func restorePreTakeVisual() {
        #if canImport(MetalKit) && canImport(UIKit)
        defer { preTakeVisualVisible = nil; preTakeVisualSize = nil }
        guard preTakeVisualVisible != nil || preTakeVisualSize != nil else { return }
        let d = UserDefaults.standard
        let visibleNow = d.object(forKey: "visual.floating.visible") as? Bool ?? true
        let sizeNow = d.object(forKey: "visual.floating.size") as? Int
        guard visibleNow, sizeNow == FloatingVisualWindow.WindowSize.fullscreen.rawValue else { return }
        if let v = preTakeVisualVisible { d.set(v, forKey: "visual.floating.visible") }
        d.set(preTakeVisualSize ?? FloatingVisualWindow.WindowSize.small.rawValue,
              forKey: "visual.floating.size")
        #endif
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
                // Re-seed roughly every ~8 bars at the current tempo so the music keeps
                // hugging the live body but is given GENEROUS room to settle into a phrase
                // instead of re-rolling restlessly. Device feedback (10.76.36): re-seeding
                // every ~8 s with a jumpy rPPG made the take — and the visual colour that
                // follows the tonic — change too often ("nicht smooth … Visuals springen").
                // Clamped 25…45 s: long enough to feel like a settled phrase, still alive.
                let beats = 32.0  // eight 4/4 bars
                let barSpan = min(45.0, max(25.0, beats * 60.0 / max(40.0, beatPlayer.pattern.tempo)))
                try? await Task.sleep(for: .seconds(barSpan))
                guard running, !Task.isCancelled else { break }
                // HOLD when the body is locked-in (founder "halten wenn eingerastet"):
                // a settled, unchanged pulse keeps its phrase instead of re-rolling
                // every tick. Only a meaningful body change (or the pre-lock/no-body
                // case) re-seeds. User edits + the first lock-snap bypass this entirely.
                if evolveShouldReseed() {
                    scheduleGenerate(auto: true, reason: "evolve")   // rate-limited — coalesces with any lock-snap/onChange recompose
                } else {
                    EchoelCrashLog.breadcrumb("evolve: HOLD (settled + stable body)")
                }
            }
        }
    }

    /// Decide whether the automatic evolve tick should re-seed or HOLD the take.
    /// No usable body → keep a demo/neutral loop gently evolving; otherwise defer to
    /// the pure, tested rule (settled + unchanged body → hold). Only the auto evolve
    /// path calls this — user edits and the first lock-snap always re-seed.
    private func evolveShouldReseed() -> Bool {
        // The BEAT IS GONE (founder 2026-07-07: "Schmeiß den Beat komplett raus") —
        // the product is nothing but pure meditative Flächen now, so a take ALWAYS
        // breathes gently onward ("Es soll sich natürlich auch was verändern"): the
        // ~30 s boundary re-seed IS the natural evolution — the STRUCTURE seed keeps
        // it the same piece, the advancing detail seed moves the clouds. (The old
        // HOLD-when-settled law only ever guarded a groove; with no groove there is
        // nothing to protect. StudioCalculator.shouldReseedOnEvolve stays for reuse.)
        return true
    }

    // MARK: - The individual algorithm: bio → music

    /// A stable-but-individual seed derived from the live body. The same body state
    /// yields the same musical signature; as HRV/heart/breath drift, the music
    /// evolves. Uses wrapping arithmetic so it can never overflow-trap.
    ///
    /// NO-BODY CASE (device log 1783177486, "generate 4× in 11 s = 4 fremde Stücke"):
    /// before the pulse locks (the common first ~15 s), `usableBio()` is nil. Returning a
    /// FRESH random here made every warm-up generate — including each control tap, which
    /// recomposes — a completely different piece (new structure/harmony), breaking the
    /// "same piece breathing" cohesion right at the start of every take. Now the fallback
    /// seed is drawn ONCE per take (`takeFallbackSeed`, re-rolled in startEverything), so
    /// the piece stays ITSELF until the real body takes over — edits refine, never re-roll.
    private func bioSeed(_ f: BioSampleFrame?) -> UInt64 {
        guard let f = f else { return takeFallbackSeed }
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

    /// - Parameter startTransport: when `true` (the user-initiated first generate) this
    ///   starts the transport if it isn't already running. Background/onChange re-seeds
    ///   pass `false` so they only swap notes into an ALREADY-playing transport — they
    ///   must never resurrect a transport the user stopped from the persistent transport
    ///   bar (the bar's Stop calls `pattern.stop()` directly, leaving the Compose session
    ///   `running` but silent; without this the ~25–45 s evolve tick would restart it).
    private func generate(startTransport: Bool = true) {
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
        var structureSeed = bioSeed(frame)
        // E3b: the sky flavours the SKELETON only (structure seed) — the detail
        // seed below stays body+evolution, so weather never outweighs the body.
        // P5: the salt is now one mixable influence — applied only while the
        // "Structure" weather mixer is up (0 = off = bit-identical).
        #if canImport(WeatherKit) && canImport(CoreLocation)
        if weatherEnabled, let wx = weatherContribution, wx.structureSalt != 0,
           WeatherMood.Param.structure.currentIntensity() > 0 {
            structureSeed ^= wx.structureSalt
        }
        #endif
        let evolvingSeed = structureSeed ^ (evolution &* 0x9E3779B97F4A7C15)
        // WEITERGEHEN (founder 2026-07-11: "es soll ja weitergehen und sich mit dem
        // Herzschlag weiterentwickeln"). The progression cursor advances with every
        // evolve tick (the bio-cadenced ~30 s re-seed), so a sustained Fläche TRAVELS
        // through its chord journey over time instead of holding one chord forever.
        // Bounded + positive so the composer's modulo indexing stays well-defined.
        let basePhase = Int(evolution % 1_000_000)
        // BODY CONTINUITY (founder 2026-07-08: "Wenn ich ein Genre auswähle, ändert
        // sich eine Weile der entspannte Vibe zu angestrengtem Gedödel"): operating
        // a menu usually means LIFTING the finger off the camera, so at the moment a
        // genre-change re-seed fires, `usableBio()` is often nil — and the composer
        // used to fall back to a NEUTRAL body (HR 70, coherence 0.5), audibly faster
        // and denser than the real resting body (e.g. HR 55, coh 0.9), until the
        // pulse re-locked ("eine Weile"). Fall back to the LAST TAKE'S measured body
        // instead: the music stays in the register the body actually earned through
        // any brief signal gap. Neutral defaults remain the last resort (no body at
        // all this session); Stop clears the held body, so a new session re-baselines.
        let heldBody = lastGenBody
        // Dynamic depth from the body (was a flat 0.5, which left velocity dead):
        // a calm, coherent state breathes fuller/louder, an aroused one lighter, so
        // dynamics actually track the live signal instead of sitting constant.
        // A coherence of exactly 0 means "no coherence data" — HealthKit never
        // measures it, and the camera path reports 0 until enough beats accrue. The
        // composer reads coherence as calmness, so a literal 0 would be misread as
        // "maximally incoherent" and pin the arrangement to a sparse, frozen take
        // (the 8-min "stuck at 6 notes" after a pulse episode). Treat 0 as neutral —
        // preferring the held body's coherence over the hardcoded 0.5 when we have one.
        let heldCoh: Float? = heldBody.flatMap { $0.coherence > 0 ? Float($0.coherence) : nil }
        let rawCoh = fin(frame?.coherence, heldCoh ?? 0.5)
        let liveCoh = rawCoh > 0 ? rawCoh : (heldCoh ?? 0.5)
        let dynamicDepth = min(1, max(0.2, 0.3 + 0.5 * liveCoh))
        // P5: weather flavours the SOUND mood on top of the user's own knobs —
        // each influence crossfades toward its weather target by its own intensity
        // mixer (0 = the user's value unchanged). The body still dominates: this
        // only nudges darkness/liveliness/tension, which then blend with the live
        // signal inside the composer as before.
        #if canImport(WeatherKit) && canImport(CoreLocation)
        var moodForInput = mood
        if weatherEnabled, let wx = weatherContribution {
            moodForInput.darkness = WeatherMood.blend(
                base: moodForInput.darkness, target: wx.darknessTarget,
                intensity: WeatherMood.Param.warmth.currentIntensity())
            moodForInput.liveliness = WeatherMood.blend(
                base: moodForInput.liveliness, target: wx.livelinessTarget,
                intensity: WeatherMood.Param.energy.currentIntensity())
            moodForInput.tension = WeatherMood.blend(
                base: moodForInput.tension, target: wx.tensionTarget,
                intensity: WeatherMood.Param.drama.currentIntensity())
        }
        #else
        let moodForInput = mood
        #endif
        let input = BioComposer.Input(
            heartRateBPM: fin(frame?.heartRateBPM, heldBody.map { Float($0.bpm) } ?? 70),
            hrvNormalized: fin(frame?.hrvNormalized, 0.5),
            coherence: liveCoh,
            breathPhase: fin(frame?.breathPhase, 0),
            breathDepth: dynamicDepth,
            key: key,
            style: style,
            mode: .flowFree,          // tempo always follows the body
            lockedTempo: 90,
            mood: moodForInput,
            seed: evolvingSeed,
            structureSeed: structureSeed,
            progressionPhase: basePhase
        )
        let composition = BioComposer.compose(input)
        // Honor the user's concert pitch + live timbre on the next notes.
        synth.setTuning(a4Hz: session.a4Hz)
        subBass.setTuning(a4Hz: session.a4Hz)
        touchSynth?.setTuning(a4Hz: session.a4Hz)
        synth.apply(currentPatch)
        syncTouchSound()
        // TEMPO — bio-reactive but never jumpy. The body seeds the tempo once the pulse is
        // trustworthy, then the beat GENTLY CONVERGES toward the body's live trend on each
        // evolve tick (founder circled "98 bpm vs Puls 66": the first seed captured an elevated
        // STARTUP pulse (~124) and the old code FROZE it forever while the body settled much
        // lower). Convergence is safe against the original "springt auf 196" fear by three
        // independent guards: only a TRUSTWORTHY (settled) reading moves it, each step is capped
        // to ±`tempoConvergeStep` BPM, and `glideTempo` slides it in over ~2 s — so a noisy rPPG
        // octave error can never slam the beat, yet the tempo no longer holds a stale value.
        let tempo: Double
        if lockBPM {
            tempo = min(max(lockedBPM, 40), 240).rounded()
        } else if tempoSeededFromBody {
            // Ease toward the current body-mapped tempo (octave-folded INTO the genre's
            // window, B4 — the pulse drives the beat at the genre's rhythmic level, so
            // Trap really runs 130–150 and Punk 160+), at most ±step per tick.
            if bodyTempoTrustworthy(frame) {
                let target = StudioCalculator.genreTempo(composition.suggestedTempo,
                                                         into: style.tempoRange).rounded()
                let current = beatPlayer.pattern.tempo
                let delta = max(-Self.tempoConvergeStep, min(Self.tempoConvergeStep, target - current))
                tempo = (current + delta).rounded()
            } else {
                tempo = beatPlayer.pattern.tempo      // no trustworthy body → hold this tick
            }
        } else {
            // Not yet locked to the body for this take. Seed the tempo from the body's musical
            // mapping (octave-folded so a doubled pulse 196 ≈ 2×98 can't set a runaway tempo) —
            // but only LOCK it (hold for the rest of the take) once the reading is TRUSTWORTHY.
            // Camera rPPG is noisy for the first ~13 s; locking on the first 0.35-confidence
            // frame would freeze a too-fast beat. Until the pulse is confidently settled we hold
            // a steady tempo instead of chasing the noise; once confident we seed from the
            // settled body and lock. (Bio still MODULATES timbre throughout — only TEMPO holds.)
            let bodySeed = StudioCalculator.genreTempo(composition.suggestedTempo,
                                                       into: style.tempoRange).rounded()
            if bodyTempoTrustworthy(frame) {
                tempo = bodySeed
                tempoSeededFromBody = true
            } else if frame != nil {
                // Pulse present but still settling → hold current tempo, don't chase rPPG noise.
                tempo = beatPlayer.pattern.tempo >= 50 ? beatPlayer.pattern.tempo : bodySeed
            } else {
                // No body yet → neutral body-mapped seed (~72).
                tempo = bodySeed
            }
        }
        // Push the live musical context so the roll's per-tick MusicalFrame carries the
        // current key/scale/tempo/concert-pitch → renderers colour by the right key.
        pianoRoll.musicalA4Hz = session.a4Hz
        pianoRoll.musicalRootPitchClass = rootIndex
        pianoRoll.musicalScaleName = scale.rawValue
        pianoRoll.musicalTempoBPM = tempo
        fxCharacter.apply(to: synth.fxChain, bpm: tempo, genre: style)
        if let touchSynth { fxCharacter.apply(to: touchSynth.fxChain, bpm: tempo, genre: style) }   // same room for played notes
        applyDelaySync(bpm: tempo)   // keep the user's delay note value across re-seeds
        // Global transpose: shift every generated pitch by the user's semitones at the
        // single point where all notes exist as one array (main actor, not the audio
        // thread). The sub-bass follows automatically — it derives from note.pitch-12
        // in the trigger — so synth + sub stay locked an octave apart. Clamp to MIDI.
        let semis = Int(transposeSemitones.rounded())
        // Per-genre MIX GLUE: nudge relative role levels so each genre sits right
        // (lead forward in synth genres, bass firmer in dub/heavy, pad back in
        // dense takes). Velocity scales each voice's amplitude, so this is a pure,
        // audio-thread-safe level move at the one point all notes exist as an array.
        let mix = style.mixLevels
        // Turn one raw composed bar into final notes: global transpose THEN the mix glue.
        func finish(_ raw: [Note]) -> [Note] {
            let shifted = semis == 0 ? raw : raw.map {
                var n = $0; n.pitch = min(127, max(0, n.pitch + semis)); return n
            }
            return shifted.map { n in
                var m = n
                // Genre mix glue × the user's per-part MIXER level (Module 1). Unity
                // mixer = the genre balance unchanged; the user can pull e.g. a shrill
                // lead down. Still a pure velocity scale — no audio-thread change.
                let genreF: Float
                switch n.role {
                case .bass:    genreF = mix.bass
                case .lead:    genreF = mix.lead
                case .harmony: genreF = mix.harmony
                }
                let f = MixerStore.combined(genre: genreF, user: mixer.level(for: n.role))
                m.velocity = min(1, max(0, n.velocity * f))
                return m
            }
        }
        // LOOP-CONFORM ARRANGEMENT (1b, founder: "je nachdem wie groß der Loop umgestellt
        // ist"): build `loopBars` distinct bars that the roll cycles through — a different
        // bar each loop. Every bar shares the STRUCTURE seed (cohesive — "same piece
        // breathing") but uses a per-bar DETAIL seed (distinct), so a 4-bar loop really is
        // four bars, not one repeated. bar 0 = the take just composed. barCount 1 = classic.
        let barCount = max(1, loopBars.rawValue)
        var bars: [[Note]] = [finish(composition.notes)]
        if barCount > 1 {
            bars.reserveCapacity(barCount)
            for b in 1..<barCount {
                var barInput = input
                barInput.seed = evolvingSeed &+ UInt64(b)
                // Each bar of the loop sits one step further along the chord journey,
                // so a multi-bar Fläche moves through its progression WITHIN the loop
                // (a different held chord per bar), not just across evolves.
                barInput.progressionPhase = basePhase + b
                bars.append(finish(BioComposer.compose(barInput).notes))
            }
        }
        // Playing → hot-swap at the seamless boundary (no cut); stopped → load bar 0 now so
        // it's present before playback starts. The cycler advances one bar per loop, in sync
        // with the transport's "bar N/M" indicator.
        pianoRoll.loadArrangement(bars, playing: running && beatPlayer.pattern.isPlaying)
        // GENRE DRUMS (audit B5, founder 2026-07-04 "Weiter mit B4/B5"): load the
        // composer's groove — every beat-driven genre carries its defining rhythm
        // (four-on-floor/backbeat/offbeat/half-time archetypes + the dub/trap
        // signatures); classical/meditation/self-observation return empty grids and
        // stay drum-free by design. This supersedes the 2026-06-13 "drum-free"
        // decision (a8c2bc9) at the founder's explicit ask.
        // Boundary-staged while playing (2026-07-06B "organisch und professionell"):
        // the melody already hot-swaps at the loop boundary, but the drum grid used
        // to cut over IMMEDIATELY — every evolve/lock re-seed chopped the groove
        // mid-bar while the melody waited for the downbeat (an audible "holprig"
        // seam). Now drums stage at the same boundary, so the whole re-seed lands
        // musically, together, on the downbeat. Stopped → loads instantly as before.
        //
        // BEAT MODE (founder 2026-07-06C): Off = pure Flächen; Pulse (default) = the
        // shamanic ur-rhythm — seeded from the STRUCTURE seed (body-only, no
        // evolution nonce) so the drum holds its walk across evolve re-seeds while
        // melody detail evolves above it; Genre = the style's archetypal groove.
        // BEAT REMOVED (founder 2026-07-07: "Schmeiß den Beat komplett raus"). The
        // product is pure meditative Flächen — NO drum layer, ever, whatever the
        // stored beatMode or the genre says. The BeatMode enum, the beatModeRow
        // control and the shamanic/genre groove builders stay compiling (reversible),
        // but generation is unconditionally silent. This also removes the shamanic
        // pulse drum that a stale stored beatMode = .pulse was still playing under
        // the Fläche (device log 1783426400).
        let groove: (steps: [[Bool]], accents: [[Bool]]) = BioComposer.silentBeat()
        beatPlayer.pattern.loadAtBoundary(steps: groove.steps, accents: groove.accents)
        // BREATH SWELL (0.1 Hz medical coherence pacer): arm it for the sustained
        // meditative Flächen (where the whole point is to pace the breath toward
        // resonance), off for the other genres. The synth ramps to it click-free.
        synth.setBreathSwell(depth: style.harmonicProfile.sustained ? 0.22 : 0)
        // GLIDE the tempo (not snap) so a body re-seed eases in instead of jumping ("bpm
        // springt plötzlich"). glideTempo now eases whether the take is PLAYING (advance()
        // ticks) OR STOPPED (a small main-queue timer) — a re-seed landing on a paused take no
        // longer snaps the transport number. The initial generate holds the current tempo
        // (unchanged value → arrives at once), so it never lags. lockBPM already resolved
        // `tempo` to the locked value above, so a locked take just glides to/holds it.
        beatPlayer.pattern.glideTempo(to: tempo)
        // GROOVE CYCLE 2: apply the genre's swing so odd 16ths land late for a
        // rolling, human feel (jazz/rock'n'roll shuffle, reggae bounce, dance push,
        // straight genres stay 0). Melody + any drums ride the same clock, so the
        // whole take swings together instead of sitting dead-on-grid.
        // Pulse/Off modes run STRAIGHT: the shamanic pulse must walk evenly (a swung
        // ur-drum reads as a genre shuffle), and pure Flächen have nothing to swing.
        beatPlayer.pattern.setSwing(0)   // no beat → nothing to swing (pure Flächen run straight)
        // MULTITIMBRAL Step 2b: give the LEAD voice a genre-appropriate timbre so
        // the lead line reads as its own instrument (synth lead vs jazz Rhodes vs
        // klezmer clarinet) over the pad/bass. Falls back to "Bright Lead".
        let leadPatch = SynthPatch.factory.first { $0.name == style.leadPatchName }
            ?? SynthPatch.factory.first { $0.name == "Bright Lead" }
        if let leadPatch { pianoRoll.applyLeadPatch(leadPatch) }
        metronome.bpm = tempo   // keep the click on the live transport tempo
        session.adopt(key: key)
        hasComposed = true
        // Capture the body baseline for the evolve HOLD (founder "halten wenn
        // eingerastet"): the next evolve tick compares the live body against THIS
        // and only re-seeds if it moved meaningfully. nil frame → no body this take,
        // so the evolve loop keeps a demo/neutral loop gently alive instead.
        // Keep the last MEASURED body through signal gaps (finger lifted to use a
        // menu): a nil frame no longer erases the baseline — the body-continuity
        // fallback above needs it. Stop() still clears it, so sessions re-baseline.
        lastGenBody = frame.map { (bpm: Double($0.heartRateBPM), coherence: Double($0.coherence)) } ?? lastGenBody
        // EchoelAI narrates the live bio→sound mapping in plain technical English.
        if let frame { caption.text = BioExplanation.text(for: frame, tempo: tempo) }
        let wasPlaying = beatPlayer.pattern.isPlaying
        // Start playback only for the user-initiated first generate; a background/onChange
        // re-seed must not restart a transport the user stopped from the transport bar.
        if !wasPlaying && startTransport {
            beatPlayer.pattern.play()
            metronome.resync()   // align the click's downbeat to the start
        }
        EchoelCrashLog.breadcrumb("generate[\(pendingGenerateReason)]: \(composition.notes.count) notes, playing=\(beatPlayer.pattern.isPlaying)")
    }

    /// Apply the live timbre (`currentPatch`) to the running synth without
    /// recomposing. Safe to call at any time; the audio thread fans the patch
    /// across every voice in its render drain.
    private func applySoundLive() {
        synth.apply(currentPatch)
        syncTouchSound()
    }

    /// Keep the play surface's voice in sync with the take sound — unless the user
    /// picked a dedicated touch patch ("touch.patchID"), which always wins. Called
    /// wherever the take patch changes (generate / editor / preset recall).
    private func syncTouchSound() {
        guard let touchSynth else { return }
        if touchPatchID.isEmpty {
            touchSynth.apply(currentPatch)
        } else if let id = UUID(uuidString: touchPatchID),
                  let p = patchStore.patches.first(where: { $0.id == id }) {
            touchSynth.apply(p)
        } else {
            touchSynth.apply(currentPatch)   // stale selection → follow the take again
        }
    }

    // seedTempo moved to StudioCalculator.seedTempo (Foundation-only home → Linux CI
    // actually EXECUTES its tests; pure musical maths doesn't belong on a SwiftUI view).

    /// Whether a body reading may LOCK the take tempo. Camera rPPG must be confidently locked
    /// (its raw bpm is noisy while the pulse settles); other sources (BLE/HealthKit/demo) are
    /// stable enough to trust on the first frame. A nil frame = no body yet → not trustworthy.
    private func bodyTempoTrustworthy(_ frame: BioSampleFrame?) -> Bool {
        guard let frame else { return false }
        // Camera rPPG must be SETTLED (confident + flat ~3 s), not merely confident: the
        // first confidence crossing lands on the falling warm-up tail (device log: latched 87
        // while the pulse was still descending to 69 — the "lock springt nach oben" bug).
        if frame.source == .cameraPPG { return cameraRPPG.isSettled }
        return true
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
            share = ExportedFile(url: renamedForShare(url))
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
            share = ExportedFile(url: renamedForShare(url))
        }
        exporter.reset()
    }

    /// Copy the exported loop to a share-ready file whose NAME carries the musical
    /// context (founder 2026-07-02: "das Exportieren soll gleich die Tonart etc mit drin
    /// haben"). `sessionName` already yields `Echoel_<date>_<Key>_<bpm>_A440` (key + tempo
    /// + tuning); we append the genre. E.g. `Echoel_2026-07-02_Dm_120bpm_A440_Dub-Techno.wav`.
    /// Falls back to the original URL if the copy fails, so an export can never be lost.
    private func renamedForShare(_ url: URL) -> URL {
        let base = session.sessionName(bpm: beatPlayer.pattern.tempo)
        let genre = style.displayName
        let raw = "\(base)_\(genre)"
        let safe = raw.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>| "))
            .filter { !$0.isEmpty }.joined(separator: "-")
        let ext = url.pathExtension.isEmpty ? "wav" : url.pathExtension
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).\(ext)")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            EchoelCrashLog.breadcrumb("export rename failed: \(error.localizedDescription)")
            return url
        }
    }

    /// Export the generated melody as a standard MIDI file (in-key notes, real
    /// tempo) so it opens with pitch + timing in any DAW. Engine already exists
    /// (MIDIFileExporter); this writes it to a temp file and opens the share sheet.
    private func exportMIDI() {
        // Export the WHOLE take as a bar-aligned N-bar region (founder: "8/16-Takt-Loop …
        // in der DAW weiterarbeiten"). The melody is the full arrangement (N distinct bars,
        // not just the one sounding bar); the 1-bar drum grid is tiled to the same N bars so
        // melody and drums line up. The exporter anchors End-of-Track to N×4 quarters and
        // writes tempo + 4/4 + key-signature so the clip drops onto the DAW grid in the right
        // Tonart and loops seamlessly.
        let (arrangedNotes, bars) = pianoRoll.arrangementForExport()
        let steps = LoopCutter.tile(grid: beatPlayer.pattern.steps, bars: bars)
        let accents = LoopCutter.tile(grid: beatPlayer.pattern.accents, bars: bars)
        guard !arrangedNotes.isEmpty || steps.contains(where: { $0.contains(true) }) else { return }
        let data = MIDIFileExporter.exportCombined(
            notes: arrangedNotes, steps: steps, accents: accents,
            tempo: beatPlayer.pattern.tempo, bars: bars,
            keyRootPitchClass: rootIndex, keyIsMinor: scale.isMinorTonality)
        // Name carries key + tempo + tuning + genre, like the WAV export.
        let stem = "\(session.sessionName(bpm: beatPlayer.pattern.tempo))_\(style.displayName)"
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>| "))
            .filter { !$0.isEmpty }.joined(separator: "-")
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
        touchSynth?.setTuning(a4Hz: p.a4Hz)
        synth.apply(p.patch)
        syncTouchSound()
        fxCharacter.apply(to: synth.fxChain, bpm: p.bpm, genre: p.style)
        if let touchSynth { fxCharacter.apply(to: touchSynth.fxChain, bpm: p.bpm, genre: p.style) }   // same room for played notes
        pianoRoll.load(p.notes)
        beatPlayer.pattern.load(steps: p.drumSteps, accents: p.drumAccents)
        beatPlayer.pattern.setTempo(p.bpm)
        // Everything that mirrors tempo must follow a loaded take, or the click and the
        // visual/OSC frame keep the OLD project's BPM (Finding F). Route through the
        // authoritative clock value (clamped) so all readers show one number.
        let loadedTempo = beatPlayer.pattern.tempo
        metronome.bpm = loadedTempo
        pianoRoll.musicalTempoBPM = loadedTempo
        lockedBPM = loadedTempo
        hasComposed = true
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
        hasComposed = true
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

/// One weather-influence mixer row: the app-wide parameter control (EchoelValueField,
/// 0…1) plus a one-line explanation of what it changes. A LEAF that owns its own
/// `@AppStorage` (keyed by the parameter) so the churny root body never re-renders on
/// a mixer edit — and so the intensity persists identically to how the wiring reads it
/// (`WeatherMood.Param.currentIntensity`). 0 = off (no change), 1 = fully the weather.
@MainActor
private struct WeatherMixRow: View {
    let param: WeatherMood.Param
    @AppStorage private var intensity: Double

    init(param: WeatherMood.Param) {
        self.param = param
        _intensity = AppStorage(wrappedValue: param.defaultIntensity, param.mixKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            EchoelValueField(label: param.label, value: $intensity,
                             range: 0...1, unit: "", decimals: 2)
            Text(param.explanation)
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// R1: the live stamped session name (artist · date · [place] · key · BPM ·
/// Kammerton) — its OWN leaf because the tempo runs along with the body
/// (freeze rule: only this label churns, never the Session card's toggles).
@MainActor
private struct SessionNamePreviewLeaf: View {
    @Environment(SessionContext.self) private var session
    @Environment(Transport.self) private var transport

    /// The name as READABLE fields in the founder's order (E · date · place ·
    /// key · BPM · Kammerton) instead of the raw underscore filename. Place is
    /// shown only once it resolves, so the line never carries an empty slot.
    private var readableFields: [String] {
        var f: [String] = []
        let artist = session.artistName.trimmingCharacters(in: .whitespaces)
        f.append(artist.isEmpty ? "Echoel" : artist)                       // E…
        f.append(Date().formatted(date: .abbreviated, time: .omitted))     // date
        if !session.placeToken.isEmpty { f.append(session.placeToken) }    // place
        f.append(session.key.name)                                         // Tonart, spelled out
        f.append("\(Int(transport.tempo.rounded())) BPM")                  // tempo
        f.append("\(Int(session.a4Hz.rounded())) Hz")                      // Kammerton
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Human-readable identity — the value of the whole card, made legible.
            Text(readableFields.joined(separator: "  ·  "))
                .font(EchoelTheme.font(13, .medium))
                .foregroundStyle(EchoelTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            // The exact export/save filename, kept for reference but de-emphasised.
            Text("Datei: \(session.sessionName(bpm: transport.tempo.rounded()))")
                .font(EchoelTheme.font(10).monospacedDigit())
                .foregroundStyle(EchoelTheme.dim)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session: \(readableFields.joined(separator: ", "))")
    }
}

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

/// Live "music → colour": the chord sounding now (published on the bus by the
/// piano roll as a MusicalFrame) mapped through SpectralColor (OKLab, octave-
/// equivalent hue, amplitude-weighted chord mix). Proves the DMMW promise —
/// visuals shaped BY musical parameters — and feeds the immersive visual + light.
///
/// OWN LEAF on purpose (freeze rule, audit 2026-07-09): `freshMusical` republishes
/// on every sequencer step (~5-8 Hz while playing). Reading it here confines the
/// churn to this one row — read inside the Visual panel's closure it re-evaluated
/// the whole panel subtree (look slider, chips, value fields) at step rate.
private struct MusicColourRowView: View {
    @Environment(EngineBus.self) private var bus

    var body: some View {
        let frame = bus.freshMusical(maxAge: 1.5)
        let sounding = frame?.isSounding ?? false
        let swatch = musicColour(frame) ?? EchoelTheme.fill
        HStack(spacing: 10) {
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
}

#endif
