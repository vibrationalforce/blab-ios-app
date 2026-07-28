#if canImport(SwiftUI)
import SwiftUI
import Combine   // NotificationCenter.publisher for the chrome pulse-button toggle
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
// Echoel — a tab strip on a front plate, with ONE button under it.
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
    @Environment(PolySynthVoice.self) private var synth
    /// The global one-button bio voice (owned by the app) — read here only to push the
    /// concert pitch to it alongside the other voices, so an external-MIDI note into it
    /// also honors Kammerton. Method calls in event handlers only; never read in body.
    @Environment(BioReactiveSynthVoice.self) private var bioVoice
    /// The PLAY-SURFACE voice (fullscreen visual touch instrument) — its own instance,
    /// so its patch/morph never re-timbre the generative bed and vice versa.
    @Environment(\.touchSynth) private var touchSynth
    @Environment(\.leadSynth) private var leadSynth
    /// Patch id for the play surface: "" = follow the take's sound (default).
    @AppStorage("touch.patchID") private var touchPatchID = ""
    /// How much sliding UP the play surface brightens the tone (0 = off … 1 = ±1 octave).
    @AppStorage(StudioDefaultKeys.touchMorphDepth.key) private var touchMorphDepth = StudioDefaultKeys.touchMorphDepth.value
    /// Slide-expression depths + glide for the play surface (founder 2026-07-08:
    /// "hin und her sliden verändert den Sound: Filter, ein bisschen Vibrato,
    /// Chorus … Glide bzw. Portamento kann man auch einstellen"). Same keys +
    /// defaults as FloatingVisualWindow, which passes them into the surface.
    @AppStorage(StudioDefaultKeys.touchSlideVibrato.key) private var touchSlideVibrato = StudioDefaultKeys.touchSlideVibrato.value
    @AppStorage(StudioDefaultKeys.touchSlideChorus.key) private var touchSlideChorus = StudioDefaultKeys.touchSlideChorus.value
    @AppStorage(StudioDefaultKeys.touchGlide.key) private var touchGlide = StudioDefaultKeys.touchGlide.value
    @AppStorage(StudioDefaultKeys.touchLevel.key) private var touchLevel = StudioDefaultKeys.touchLevel.value
    @AppStorage(StudioDefaultKeys.touchLife.key) private var touchLife = StudioDefaultKeys.touchLife.value
    @Environment(SubBassVoice.self) private var subBass
    /// S2-W1: the Multi-Roll slot voices — the Melodic insert must reach them
    /// too, or a secondary lane's "Sound & FX" edit changes nothing it plays.
    @Environment(LaneVoiceRack.self) private var laneVoiceRack
    @Environment(MetronomeVoice.self) private var metronome
    /// #22 follow-up: Start heals a silenced roll slot (founder log v255).
    @Environment(TimelineStore.self) private var timelineStore
    /// Per-lane composition Slice A: the composer writes an override lane's take
    /// into that lane's composer-OWNED clip (never a user clip). Read only inside
    /// `generate()` — never in `body` (no observation churn).
    @Environment(ClipStore.self) private var clipStore
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
    @AppStorage(StudioDefaultKeys.weatherEnabled.key) private var weatherEnabled = StudioDefaultKeys.weatherEnabled.value
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
    // The two alternative bio sources the header pill's long-press dropdown can select
    // (founder 2026-07-15): a Bluetooth heart-rate strap (universal 0x180D) and the
    // Simulation demo. Camera (above) is the default. All three are injected by the app;
    // `selectBioSource` switches the live one, `startBioSource` honours the selection.
    #if canImport(CoreBluetooth)
    @Environment(PolarH10BioPublisher.self) private var polarH10
    #endif
    @Environment(BioSimulator.self) private var demoSource
    #if canImport(AVFoundation) && canImport(Metal)
    @Environment(VisualRecorder.self) private var visualRecorder
    #endif

    // The single live-state flag: biofeedback running or not.
    @State private var running = false

    /// Which bio input the header pill's long-press dropdown selected (founder
    /// 2026-07-15). Camera by default; `startBioSource` brings up whichever is set,
    /// `selectBioSource` switches it live. Persisted so the choice survives relaunch.
    @AppStorage("bio.sourceKind") private var bioSourceRaw = BioSourceKind.camera.rawValue
    /// Guards the async live source-switch so a rapid re-pick can't overlap.
    @State private var sourceSwitchTask: Task<Void, Never>?

    /// The three bio inputs the header pill's long-press dropdown offers.
    private enum BioSourceKind: String { case camera, ble, sim }

    /// Drives Siri/Shortcuts intent consumption (start/stop/keep loop) when the
    /// app becomes active after an intent opens it.
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    // HealthKitWriter is read by `HealthWriteOptInRow`, its own leaf — not here. The
    // root struct's @Environment for it had no use left once the Tools grid went.
    // Note: the removed HealthKit guard NESTED this one, so haptics was conditioned on
    // HealthKit being importable — accidental, and moot on iOS where both always are.
    // It now stands on its own condition, which is what it always meant.
    #if canImport(CoreHaptics)
    @Environment(HapticController.self) private var haptics
    #endif

    // The live, fully-editable timbre is `currentPatch` (single source of truth).
    // Every control below — XY pad, sliders and 2-decimal numeric fields — reads and
    // writes its fields directly, so any value can be dialed OR typed exactly.

    // Optional locked tempo for tight, DAW-ready loops. When off, the tempo follows
    // the body (flowFree); when on, the loop runs at exactly `lockedBPM`.
    @AppStorage(StudioDefaultKeys.lockBPM.key) private var lockBPM = StudioDefaultKeys.lockBPM.value
    @AppStorage(StudioDefaultKeys.lockedBPM.key) private var lockedBPM: Double = StudioDefaultKeys.lockedBPM.value
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
    /// R1 (2026-07-10): the Session card — place · weather (the name preview
    /// moved to the header CompositionHeaderStrip in step 2c).
    @AppStorage("studio.showSession") private var showSession = false
    @AppStorage("studio.showExport") private var showExport = false
    @State private var showMood = false
    @State private var showSound = false
    @State private var showEffects = false
    @State private var showMaster = false
    /// Video window (DMMW menu, 2026-07-12) — only read by the panel's
    /// disclosure fallback; in the dropdown it renders force-open anyway.
    @State private var showVideoLibrary = false
    /// Delivery loudness target (shared key with MasterLoudnessGrid's colour-coding).
    @AppStorage(StudioDefaultKeys.loudnessTarget.key) private var loudnessTargetRaw = StudioDefaultKeys.loudnessTarget.value
    /// Immersive visual mode: the spectrum→visible donut visual (default) vs the bio rings.
    @AppStorage("visual.spectralDonuts") private var spectralDonuts = true
    /// MetalBioView style when NOT in donut mode: 0 rings · 1 Chladni · 2 plasma · 3 water
    /// · 4 Prism · 5 Aurora · 6 Lissajous · 7 Depth Caustics · 8 Oscilloscope · 9 Fractal.
    /// Default 5 (Aurora) — a richer look out of the box; MUST match FloatingVisualWindow.
    @AppStorage(StudioDefaultKeys.visualStyle.key) private var visualStyle = StudioDefaultKeys.visualStyle.value
    /// Secondary style to blend with `visualStyle` (same index space). 0…9 as above.
    @AppStorage(StudioDefaultKeys.visualStyleB.key) private var visualStyleB = StudioDefaultKeys.visualStyleB.value
    /// Mix ratio A↔B [0…1]: 0 = pure primary look, 1 = pure blend look. The "mischend" control.
    @AppStorage(StudioDefaultKeys.visualBlend.key) private var visualBlend = StudioDefaultKeys.visualBlend.value
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

    // (noteNames moved with the Key picker into CompositionHeaderStrip, step 2b.)

    /// Max BPM the take tempo may drift toward the body per evolve tick (~every 30 s), glided.
    /// Small enough that the beat never lurches, large enough that a stale startup seed
    /// (e.g. 98 from an elevated launch pulse) converges to the settled pulse within ~2 min.
    private static let tempoConvergeStep: Double = 8

    // `appVersionString` lived here only for the deleted Tools footer. The version the
    // founder reads off a screenshot still renders: WorkspaceView.versionString computes
    // it independently from the same two bundle keys, so nothing was lost.

    // Derived / persisted musical state. Genre, key and scale survive relaunch so
    // the studio reopens on the setup you left it in (MusicStyle / Scale are
    // String-backed enums → @AppStorage stores the rawValue directly).
    // Default identity (founder 2026-07-07: "Tendenziell alles eher ohne Beat und
    // reine meditative Flächen"): the app opens as breath-paced ambient TEXTURES —
    // Self-Observation genre, no drums, pad articulation. Every genre/beat remains
    // one tap away; users who already changed these keep their stored choice.
    @AppStorage(StudioDefaultKeys.genre.key) private var style: MusicStyle = StudioDefaultKeys.genre.value
    @AppStorage(StudioDefaultKeys.rootIndex.key) private var rootIndex = StudioDefaultKeys.rootIndex.value
    @AppStorage(StudioDefaultKeys.scale.key) private var scale: Scale = StudioDefaultKeys.scale.value
    /// Selected tone system (microtonal). "edo12" = standard 12-TET (default, no retune).
    /// Persisted so a chosen world tuning survives relaunch.
    @AppStorage("toneSystemID") private var tuningID = "edo12"
    @AppStorage("studio.fxCharacter") private var fxCharacter: FXCharacter = .auto
    // Founder 2026-07-13 ("8 Takte vollständig und dann wiederholt es sich — sinnvolle
    // Loops sind am besten zum Musik produzieren"): an 8-bar phrase is the produce-able
    // default. Still fully flexible (2/4/8/16/32) via the loop-length picker + free-longer
    // in the arrangement; this only sets the STARTING length for a fresh install.
    @AppStorage(StudioDefaultKeys.loopBars.key) private var loopBars: LoopBarLength = StudioDefaultKeys.loopBars.value
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
    /// Founder v287/v288 "Es wird kein midi Clip erzeugt": true when the last user
    /// Generate could NOT give the generated take its visible MIDI clip because the
    /// 8-slot clip grid is full. Honest, VISIBLE feedback (never a silent no-op) —
    /// the live sound is unaffected either way; only the clip TILE is withheld until
    /// a slot frees. A plain low-frequency Bool (flips on a user Generate), read only
    /// in a small leaf Text, never near a `.menu` (freeze rule).
    @State private var composerClipGridFull = false
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

    // Modal slots. `compose.toolsExpanded` went with the Tools grid it folded — zero
    // readers, zero writers. Its persisted UserDefaults key is deliberately NOT migrated
    // or cleared: a stale bool costs nothing, a delete-on-launch is a destructive write
    // for no gain.
    @State private var showInput = false
    @State private var showRouting = false
    @State private var showLearn = false
    // Dead-duplicate sheets removed (v10.79.207): PianoRoll / PatchEditor / Automation
    // / AudioClip / AUv3 plugins were opened from the timeline lane-head doors
    // (ArrangeTimelineView's ArrangeModal), and Broadcast is a non-functional RTMP
    // scaffold. Their EchoelStudioView-level slots were fed only by the unmounted
    // toolsSection grid — pure dead weight on the 21-modal metadata chain. Removed to
    // buy headroom for the bottom-bar dissolve (PLAN_DISSOLVE_BOTTOM_BAR_2026-07-14).
    // ⚠ CORRECTED 2026-07-25 (#131): the timeline itself is GONE (pure-instrument epic
    // #121, Slice 4), so "opened from the lane-head doors" no longer describes anything.
    // ⚠ CORRECTED AGAIN 2026-07-26: the piano roll's door is gone for good (founder:
    // "Pianoroll soll raus"), and the one-slot `craftEditor` sheet went with it — the
    // chain is 15 modifiers, not 16. `PianoRollModel` is NOT part of that removal; it
    // is the note engine behind every generated take. AudioClip / AUv3 /
    // Broadcast are deliberately NOT coming back (docs/dev/PRODUCT_DEFINITION.md CUT
    // column names all three); the automation editors are gone because Slice 4d
    // (36a8468) deleted them as unreachable, which that doc does not itself discuss.
    // The patch editor the product definition KEEPS is `soundPanel` (Sound chip) —
    // that panel IS the live timbre editor, so it needs no sheet. Caveat for whoever
    // retires PatchEditorView.swift: three SynthPatch fields (`outputLevel`,
    // `unisonVoices`, `unisonDetuneCents`) and its preview keyboard have NO editor
    // anywhere else — port those rows into `soundPanel` first, or the deletion is a
    // silent capability loss, not a cleanup.
    /// Would present a file picker to import a Standard MIDI File onto the roll. NOTHING
    /// SETS THIS — its only writer was `openTool`, deleted 2026-07-26 (`f371d27`), and the
    /// roll it imported into has no door any more either. Kept as a reusable slot on the
    /// "a free slot beats two saved lines at the metadata ceiling" trade — which holds here
    /// because `importMIDI(_:)` still exists and would work the moment something sets this.
    /// (The sample-browser slot did NOT survive that same test: its view is deleted, so its
    /// slot pointed at nothing. See the note where it used to stand.) Do not read this
    /// declaration as evidence MIDI import ships.
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
    // The sample-browser slot (`sampleBrowserTrack` + its `.sheet(item:)` + `TrackRef`)
    // is GONE with `SampleBrowserView` itself (#167, founder "Drums sollen erstmal gar
    // nicht mehr rein"). The previous session kept it as a "reusable slot" because the
    // chain sits at the metadata ceiling — a defensible trade WHILE the view still
    // existed. It stops being a trade once the view is deleted: a slot whose content
    // closure names a type that no longer compiles is not reusable, and the next editor
    // rewrites that closure anyway.
    //
    // CHAIN LENGTH — ONE number, kept here so nobody reads two: the body carries
    // **14** presentation modifiers today (8 `.sheet` + 2 `.fullScreenCover` +
    // 3 `.alert` + 1 `.fileImporter`). It got there by shrinking twice, which is the
    // only safe direction under the black-screen metadata law: 16 → 15 when the piano
    // roll's craft-editor slot went (founder 2026-07-26, "Pianoroll soll raus" — it
    // held exactly one case, so removing the roll's door would have left an undoored
    // enum, the lying-`toolItems` trap), then 15 → 14 with this sample-browser slot.
    // Three un-settable flags remain (`showVisual`, `showMeditation`,
    // `midiImportPresented`) — reuse one of those before ever appending a 15th.
    // Whoever adds the next craft editor re-introduces its slot as a
    // `.sheet(item:)` + enum + out-of-body content builder, never a bare `.sheet`.

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// DMMW production shell (founder 2026-07-12): which menu-bar dropdown is
    /// open. ONE slot for ALL settings panels — nil = main window unobstructed.
    /// Low-frequency @State (user taps only), so the root body never churns.
    @State private var activeMenu: StudioMenu?

    /// The menu-bar entries. Each case reuses an EXISTING panel builder as its
    /// dropdown content — no new surfaces, the card pile just moved into menus.
    private enum StudioMenu: String, CaseIterable, Identifiable {
        case bio, composition, session, sound, mix, effects, master, mood, export, synth, video
        var id: String { rawValue }
        /// Short chip label (DAW-style small buttons — Uncodixfy 12 pt chips).
        var label: String {
            switch self {
            case .bio:         return "Bio"
            case .composition: return "Tempo"
            case .session:     return "Session"
            case .sound:       return "Sound"
            case .mix:         return "Mix"
            case .effects:     return "FX"
            case .master:      return "Master"
            case .mood:        return "Mood"
            case .export:      return "Export"
            case .synth:       return "Synth"
            case .video:       return "Video"
            }
        }
        /// Full name for VoiceOver (the chip text is abbreviated).
        var fullName: String {
            switch self {
            case .bio:         return "Bio — pulse, HRV, coherence, source"
            case .composition: return "Tempo and variations — tap tempo, metronome, haptic beat, variation ideas"
            case .session:     return "Session — place, weather"
            case .sound:       return "Sound and texture"
            case .mix:         return "Mix — level per part"
            case .effects:     return "Effects"
            case .master:      return "Master"
            case .mood:        return "Mood"
            case .export:      return "Export — WAV loop"
            case .synth:       return "EchoelSynth — immersive visual window"
            case .video:       return "Video — recorded clips library"
            }
        }
    }

    /// Persisted in-app zoom level (index into StudioZoom.ladder). `-1` = follow the
    /// system text size; once the user pinch-zooms it becomes an explicit level.
    @AppStorage("ui.zoomStep") private var zoomStep: Int = -1

    // Transpose deleted (founder net-architecture 2026-07-14): it was already removed
    // from the chip bar and unreachable, so its value was always 0 — deletion is
    // behavior-preserving. The one musical-pitch controls are Key/Scale + Kammerton.

    // Variation maze (#19) — the bio-curated idea-maze made auditionable. Explore
    // stores a ranked snapshot (NOT a live read — these @State values change only on
    // a user tap, so hosting them in the Tempo & variations dropdown never churns the
    // root body). `mazeBase` keeps the exact Input the board was scored from, so applying a
    // candidate replays the picked skeleton + detail seed precisely.
    @State private var mazeBoard: BioVariationMaze.Leaderboard?
    @State private var mazeBase: BioComposer.Input?
    @State private var mazeAppliedSeed: UInt64?

    // Immersive-visual controls. Now @AppStorage (Double) so they are the SHARED single
    // source of truth read by BOTH this panel AND the floating visual window (founder
    // 2026-07-02: "Visual Design muss möglich sein" — every tweak must show in the window,
    // live). All clamped so the WCAG flash ceiling (≤3 Hz) can never be exceeded — see
    // MetalBioView. Stored as Double (@AppStorage has no Float); passed to the renderer as
    // Float(...). EchoelValueField is generic over BinaryFloatingPoint, so the fields bind
    // to Double directly.
    @AppStorage(StudioDefaultKeys.visualIntensity.key) private var visualIntensity = StudioDefaultKeys.visualIntensity.value
    @AppStorage(StudioDefaultKeys.visualDetail.key) private var visualDetail = StudioDefaultKeys.visualDetail.value   // ring density
    @AppStorage(StudioDefaultKeys.visualMotion.key) private var visualMotion = StudioDefaultKeys.visualMotion.value    // animation speed (flash-clamped)
    @AppStorage(StudioDefaultKeys.visualSpread.key) private var visualSpread = StudioDefaultKeys.visualSpread.value
    /// VJ palette: hue rotation [0…1] (0 = physical tone colour) + saturation [0…2].
    /// Default saturation 0.82 (professional, not neon); MUST match FloatingVisualWindow.
    @AppStorage(StudioDefaultKeys.visualHue.key) private var visualHue = StudioDefaultKeys.visualHue.value
    @AppStorage(StudioDefaultKeys.visualSaturation.key) private var visualSaturation = StudioDefaultKeys.visualSaturation.value
    /// The floating visual window's show/hide state — SHARED with WorkspaceView's header
    /// monitor button and the window's own close button, so the Visual panel can toggle it
    /// directly (founder: everything user-optimized; don't make the header the only way in).
    @AppStorage(StudioDefaultKeys.floatingVisualVisible.key) private var floatingVisualVisible = StudioDefaultKeys.floatingVisualVisible.value
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

    /// The instrument's current tonic frequency (Hz) at the chosen Kammerton — fed to
    /// the immersive visual, which transposes it up into visible light, so the colour
    /// tracks key + concert pitch.
    private var currentToneHz: Double {
        session.a4Hz * pow(2.0, (Double(60 + rootIndex) - 69.0) / 12.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            // DMMW PRODUCTION SHELL (founder 2026-07-12: "wie in einer richtigen
            // DAW/VideoEditing/Visual/light/Laser Software. Die Buttons werden
            // kleiner und verteilen sich sinnvoll auf den Spuren der Timeline und
            // oben im Menü. Alles bleibt im Hauptfenster es gehen nur dropdown
            // Menüs auf für die Einstellungen."): the stacked settings cards left
            // the scroll flow — a small menu bar opens ONE anchored dropdown over
            // the zone instead. Metadata note: this REMOVED five AnyView branches
            // from the flow and added one menu row + one overlay branch — the
            // body's aggregate type SHRANK (black-screen law: never grow the
            // sheet chain; consolidate). The ~18-modal chain is untouched.
            // AnyView: keep the menu row's generics OUT of the root body type
            // (review M1) — same discipline as every other heavy branch here.
            // B3 (2026-07-12): the always-on BioStripView below the menu FELL —
            // the header pulse monitor is the at-a-glance replacement (founder:
            // "Ein Hinweis kommt ja über das Monitor Fenster oben rechts"), and
            // the numbers + tap-to-learn + source control live in the new Bio
            // dropdown (menu host — no new modal). The chrome-notification
            // receivers moved onto the menu bar (still an INNER row — the
            // root's modifier chain / metadata type is untouched).
            AnyView(menuBar
                // The header pulse pill (next to the E-logo — founder 2026-07-15 video)
                // starts/stops the instrument through this notification (TAP). The old
                // transport pulse button that posted this is gone ("einer reicht").
                .onReceive(NotificationCenter.default.publisher(for: .echoelToggleBio)) { _ in
                    toggleBiofeedback()
                }
                // Header pill long-press → pick the bio input source (camera · BLE · sim).
                .onReceive(NotificationCenter.default.publisher(for: .echoelSelectBioSource)) { note in
                    selectBioSource(note.object as? String)
                }
                // Chrome doors (shell v3): Master/Export open their dropdown;
                // Live/Learn their existing sheets.
                .onReceive(NotificationCenter.default.publisher(for: .echoelChromeDoor)) { note in
                    switch note.object as? String {
                    case "master": activeMenu = .master
                    case "export": activeMenu = .export
                    case "learn":  showLearn = true
                    #if canImport(MultipeerConnectivity)
                    case "live":   showLiveColabo = true
                    #endif
                    // Header output monitors (founder 2026-07-12): the
                    // EchoelVideo tile opens the clips library panel, the
                    // EchoelLux tile the routing sheet (existing slot —
                    // slot reuse, no new modal).
                    case "video":   activeMenu = .video; showVideoLibrary = true
                    case "routing": showRouting = true
                    // The header pulse monitor opens the Bio dropdown (B3).
                    case "bio":     activeMenu = .bio
                    // Step 2b: the Comp chip fell — the residual tempo tools +
                    // variation maze open through the transport "•••" door.
                    case "tempo":   activeMenu = .composition
                    // Step 2c: the Session chip fell — the name preview lives in
                    // the header strip; place/weather open through this door.
                    case "session": activeMenu = .session
                    default: break
                    }
                }
                // Step 2b (bottom-bar dissolve): the header CompositionHeaderStrip +
                // the transport BodyTempoField own the musical-identity CONTROLS now;
                // this receiver applies their audible side effects (retune ·
                // recompose) — the strip posts only on USER edits, so a programmatic
                // write (project open) can never trigger these and clobber the
                // loaded patch. Same chrome↔studio decoupling as the doors above.
                .onReceive(NotificationCenter.default.publisher(for: .echoelCompositionEdited)) { note in
                    handleCompositionEdit(note.object as? String)
                })
            // The rare session card, above the plate. Static content — no live bio read
            // (freeze rule). Bounded so it can never push the front plate off-screen.
            if let presentSession {
                AnyView(ScrollView { sessionEntryCard(presentSession).padding(16) }
                            .frame(maxHeight: 260))
            }
            // THE FRONT PLATE — always visible, fills the window (founder 2026-07-26:
            // "Alles soll mehr so aussehen wie früher also im hauptfenster sinnvoll
            // angeordnet"). This replaces the CONDITIONAL zone that had rendered only
            // while a dropdown was open: since the timeline went away (#130) the idle
            // main window was a chip bar, one button and a black void, and every control
            // sat behind a menu and a scrim — the opposite of an instrument.
            // METADATA: adding this plate took the root VStack from 3 children to 4, so the
            // body's generic type grew by one TupleView element — cheaply (a type-erased
            // sibling, not a ModifiedContent re-wrapping the whole body like a .sheet
            // would), and with no presentation modifier added, but it GREW. Do not read
            // this block as licence to append a fifth; see menuPanelHost's METADATA note.
            // (It is the THIRD child in source order since #157 moved startButton below it.
            // The count is what costs metadata; the position does not — but the ordinal
            // stood here as "FOURTH" and would have been read as the count.)
            AnyView(menuPanelHost)
            // H1 (founder 2026-07-24: "nur das alte Interface mit create from within"):
            // the signature generate control — tap it and the body composes and plays.
            //
            // MOVED BELOW THE PLATE (#157, founder 2026-07-27 "alles vereinfachen und
            // schöner"). It used to sit BETWEEN the chip bar and the plate, which is what
            // made the window read as "a menu bar, then a button, then a form": the chips
            // and the panel they switch are one object, and a full-width primary button
            // wedged between them cut that object in half. Below the plate it anchors the
            // surface instead of splitting it — and lands in thumb reach on a phone held
            // one-handed, which is how this instrument is actually played.
            //
            // A plain Button: NO new .sheet (metadata/black-screen law — the modal chain
            // is untouched), and it reads only `running` (discrete @State) — NOT a live
            // 10 Hz bio observable, so the menu-freeze law holds. AnyView keeps its
            // generics out of the root body type, same discipline as menuBar. Reordering
            // siblings does not change the root VStack's child COUNT, so the aggregate
            // generic type is the same size as before — this is a move, not a fifth child.
            AnyView(startButton
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 10))
        }
        // Pinch anywhere to zoom the whole interface (persists); honours the system
        // text size until the user explicitly zooms. For users who need larger text.
        .modifier(StudioZoom(step: $zoomStep))
        .background(EchoelTheme.bg)
        .onAppear {
            // FIRST, before anything reads `style`. The genre roster was re-curated
            // (#125): `MusicStyle.offered` is a hand-picked subset, not every case. A
            // style persisted before that is still a valid enum case — nothing crashes —
            // but it is not in the picker: no row is selected, the user cannot see or
            // change what they are hearing, and it keeps composing every take.
            // Ordering is load-bearing: `currentPatch` two lines down falls back to
            // `style.synthPatch`, so clamping afterwards would leave the TIMBRE on the
            // de-curated genre while the picker showed the default — the same mismatch,
            // moved into the sound.
            // MIGRATION IS DESTRUCTIVE: this overwrites the persisted `studio.genre`.
            // Re-widening `MusicStyle.offered` later restores the CHOICE for new users
            // but cannot give this user their old pick back. Accepted deliberately —
            // an unreachable selection is worse than a reset one.
            if !MusicStyle.offered.contains(style) {
                style = StudioDefaultKeys.genre.value
            }
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
            // (The genre-roster clamp that belongs next to this visual-look snap runs at
            // the TOP of this closure instead — `currentPatch` reads `style` before here.)
            surfacePriorCrashIfAny()
            handlePendingIntent()
            // Apply the persisted per-track inserts at launch (bass → sub; melodic → both
            // the pad/harmony and lead voices). The two drum restores that stood here — the
            // persisted Mixer "Drums" level into `BeatPlayer.masterLevel`, and the persisted
            // drums insert fanned across all 8 channels — are gone with the drums themselves;
            // as of #167 `masterLevel` is not even a symbol any more, so do not grep for it.
            subBass.setInsert(trackFX.bass)
            laneVoiceRack.setBassInsert(trackFX.bass)  // S2-W2-5: lane subs too
            // …and the persisted Mixer BASS LEVEL, which until now reached nothing audible:
            // the mixer applies levels as a compose-time velocity scale, and the felt sub
            // has no per-note velocity, so the one fader the founder reached for was the
            // one that did nothing (2026-07-27). Restoring it here matters as much as the
            // live push in `mixBinding`: a value pulled to 0 last session must still be 0
            // after relaunch, or the fader would silently spring back on every launch.
            subBass.mixLevel = mixer.bass
            laneVoiceRack.setBassMixLevel(mixer.bass)   // lane subs share the Bass bus
            synth.setInsert(trackFX.melodic)
            leadSynth?.setInsert(trackFX.melodic)
            laneVoiceRack.setInsert(trackFX.melodic)   // S2-W1: rack lanes too
            // The persisted play-surface LEVEL is restored in `EchoelmusicApp`'s startup
            // task, right after `touchVoice.attach(to:)`. It briefly lived HERE and that
            // was wrong: this `onAppear` runs in the first SYNCHRONOUS appear pass, before
            // the async startup task attaches the node, so the write landed on an
            // unattached `sourceNode`. Do not move it back.
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
        // recurse. (The old closing line, "to only WATCH the pulse without music, arm the body
        // on the Bio page", was FALSE: every reachable arm goes through startBiofeedback(), i.e.
        // a full take. The camera-only arms live in the doorless BioSourceView/SessionView.)
        .onChange(of: transport.isPlaying) { _, playing in
            // CONSUME FIRST, before any guard. This line order is the whole correctness of
            // #161: the first version read the flag *after* `guard running`, so a pause
            // requested while no take was live stayed outstanding and downgraded the next REAL
            // Stop to a pause — music off, camera and torch still on, `running` still true, and
            // the ■ already flipped back to ▶ so the user had no obvious way out. It used to be
            // reachable in four taps from a cold launch (Notes → ▶ → ⏸ → close → Start → ■).
            // ⚠ THAT REPRO IS GONE, and the mechanism with it: the piano roll's door was removed
            // 2026-07-26 ("Pianoroll soll raus"), and `requestPlaybackOnlyStop()` has exactly one
            // producer — `PianoRollView.transport` — which nothing mounts any more. So this read
            // now always returns false, `.pausePlayback` is unreachable, and behaviour is exactly
            // pre-#161. DO NOT read that as "the ordering was over-engineering" and inline it:
            // the ordering IS the fix, and it becomes load-bearing again the instant anything
            // re-acquires the ability to request a playback-only stop. Retiring the mechanism
            // outright is a separate slice (#180), not a comment-cleanup side effect.
            let pauseRequested = pianoRoll.consumePlaybackOnlyStopRequest()
            switch TransportTransition.decide(isPlaying: playing,
                                              running: running,
                                              pauseRequested: pauseRequested) {
            case .ignore:
                break
            case .resume:
                resumeAfterPause()
            case .pausePlayback:
                pausePlaybackKeepingSession()
            case .endSession:
                stopEverything(reason: "transport-stopped")
            }
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
        .onDisappear { stopEverything(reason: "unmount"); disableKeepAwake() }
        // Sheet/cover contents are AnyView-erased too — same reason as the scroll
        // content above: keep the root view's aggregate generic type shallow so the
        // launch-time metadata decode can never overflow the stack again.
        .sheet(isPresented: $showOpen) { AnyView(openSheet) }
        .sheet(item: $share) { AnyView(ShareSheet(url: $0.url)) }
        .sheet(item: $diagnostics) { report in AnyView(diagnosticsSheet(report.text)) }
        .sheet(isPresented: $showAllFX) {
            AnyView(EchoelFXView(chain: synth.fxChain, bpm: currentTempo,
                         fxEnabled: { synth.isFXEnabled },
                         setFXEnabled: { synth.setFXEnabled($0) })
                .echoelSheetPanel())
        }
        .sheet(isPresented: $showInput) { AnyView(AudioInputPickerView().echoelSheetPanel()) }
        .sheet(isPresented: $showRouting) { AnyView(PatchbayView().echoelSheetPanel()) }
        .sheet(isPresented: $showLearn) { AnyView(LearnView()) }   // self-manages its detents
        #if canImport(UniformTypeIdentifiers)
        .fileImporter(isPresented: $midiImportPresented,
                      allowedContentTypes: [.midi],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { importMIDI(url) }
        }
        #endif
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

    // MARK: - Tools (deep editors) — REMOVED 2026-07-26
    //
    // The whole Tools catalog lived here: `ToolCat`, `ToolItem`, `toolItems`, `openTool`,
    // `toolsSection`, `toolGroup`, `gridChip`, `gridChipLabel` — 187 lines with ZERO mounts.
    // `toolsSection` was the only caller of `openTool`, and nothing has rendered
    // `toolsSection` since the 2026-07-02 grid removal.
    //
    // It was not inert, which is why it went rather than staying as harmless dead weight:
    //
    // 1. It CAMOUFLAGED three unreachable modals. `openTool` assigned `showVisual`,
    //    `midiImportPresented` and `showMeditation`, so a grep for each flag found a
    //    writer and every audit concluded the slot was live. It was not: with the only
    //    caller unmounted, `.fullScreenCover($showVisual)`, `.fileImporter($midiImportPresented)`
    //    and `.fullScreenCover($showMeditation)` can never open. That is how CLAUDE.md came
    //    to certify `SpectralDonutView` as reachable (it renders ONLY inside the first of
    //    those covers) and MIDI import as wired. Three of the body's presentation modifiers
    //    are therefore free headroom at the metadata ceiling the black-screen law is
    //    fighting over — reuse those slots, never append a new one. (⛔ The chain LENGTH is
    //    deliberately not repeated here: this block said "15" while the pinned line said
    //    "14", which is exactly the two-numbers problem that line exists to prevent. The
    //    one number lives at the `craftEditor` note above; go read it there.)
    // 2. It was the LYING-`toolItems` TRAP in the flesh: the catalog declared 13 tools,
    //    `openTool` handled 7. `pianoroll`, `sound`, `automation`, `audioclip`, `plugins`
    //    and `broadcast` fell through `default: break` — six chips that would have rendered
    //    and done nothing the moment anyone re-mounted the grid, which is exactly the
    //    failure mode CLAUDE.md warns about and this block's own comment denied
    //    ("a tool never appears without a live action").
    //
    // Nothing referenced these symbols from outside the block, in Sources/ or Tests/.
    // The capabilities the dead slots pointed at are NOT deleted with it: `SpectralDonutView`,
    // the MIDI `fileImporter` + `importMIDI()` still exist and need a real door or a
    // deliberate cut — a founder call, not a side effect of tidying. `exportMIDI()` was on
    // that list too ("no caller at all"); it got its door back in #188 (a Button in the
    // Export panel, through the existing `share` slot), so it is off the list.

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
                    .foregroundStyle(EchoelTheme.text)
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
                .strokeBorder(EchoelTheme.border, lineWidth: 1))
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

    // MARK: - DMMW menu bar + dropdown host (founder 2026-07-12)

    /// The production-shell menu bar: one horizontal row of SMALL chips at the top
    /// of the studio zone (DAW feeling — "Die Buttons werden kleiner … oben im
    /// Menü"). Settings chips toggle the ONE dropdown; Live/Learn are direct doors
    /// to their existing sheet slots. Reads only low-frequency @State.
    /// Shell v3 (founder 2026-07-12): the studio bar keeps only the INSTRUMENT
    /// panels. Master/Export/Live/Learn moved to the chrome next to the lock
    /// (TransportBar door buttons); the Plugins chip dissolved — AUv3 access
    /// lives on the track doors (ArrangeTimelineView, since 07810ba). The
    /// .master/.export dropdown cases stay: the chrome doors open them.
    // Chip-bar simplification (founder 2026-07-14, red-pen pass):
    //  · .bio     → the Bio section's home is now the HEADER leaf (tap = full detail);
    //               it no longer lives as a bottom chip too (no double home).
    //  · .transpose → DELETED (founder net-architecture 2026-07-14): the case, panel
    //               and state are gone (it was already unreachable / always 0).
    //  · .composition → chip REMOVED (step 2b, 2026-07-17): genre/key/scale/tone
    //               system/A4 live in the header CompositionHeaderStrip, THE tempo
    //               control in the TransportBar; the residual tempo tools +
    //               variation maze open via the transport "•••" door ("tempo"),
    //               same chrome-door-only pattern as Master/Export.
    //  · .session → chip REMOVED (step 2c, 2026-07-17): the live name preview
    //               (SessionNamePreviewLeaf) rides at the end of the header
    //               CompositionHeaderStrip; the place/weather toggles that feed
    //               the name open via the transport "•••" door ("session") —
    //               chrome-door-only, same pattern as Master/Export/Tempo.
    // Master/Export were already chrome-door-only.
    // Dissolving the bottom chip bar (founder 2026-07-20: "die untere Leiste komplett
    // auflösen … Video kann gelöscht werden"). S1: drop `.video` — the recordings library
    // is founder-deleted from navigation; the immersive visual window stays reachable via
    // the header monitor button. The `.video` case + videoPanel stay compiling (unreferenced
    // now) so the removal is reversible; a later slice deletes the dead panel. Following
    // slices retire mix/effects/synth/sound as each function is verified reachable per-track,
    // then the bar goes entirely (PLAN_LEISTE_DISSOLVE_2026-07-20).
    private static let studioChips: [StudioMenu] =
        StudioMenu.allCases.filter { $0 != .master && $0 != .export && $0 != .bio
                                     && $0 != .composition && $0 != .session
                                     && $0 != .video }

    /// The tab strip: the five instrument tabs, PLUS whatever the plate currently shows if
    /// a chrome door selected one of the menus the strip normally hides (Master · Export ·
    /// Bio · Tempo · Session · Video reach the plate through the header/transport, not
    /// through a chip). Without this, `displayedMenu` matches no chip, so all five render
    /// inactive: a tab strip that claims to be the selector while showing no selection, and
    /// a VoiceOver tab list with no selected tab — with nothing on screen naming the panel
    /// the user is looking at. Harmless while the panel was a transient dropdown over a
    /// scrim; a lying control now that the strip is permanent. Appended rather than always
    /// present, so the strip stays short.
    private var visibleChips: [StudioMenu] {
        Self.studioChips.contains(displayedMenu)
            ? Self.studioChips
            : Self.studioChips + [displayedMenu]
    }

    private var menuBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // The "Notes" chip (the piano roll's door) is GONE — founder
                // 2026-07-26, "Pianoroll soll raus". `PianoRollModel` deliberately
                // stays: it is not the editor, it is the note ENGINE that plays the
                // generated take and publishes `MusicalFrame` to the visual/light
                // output stage. Removing the model with the door would have silenced
                // the instrument and greyed out the very visuals the same message
                // asked to improve.
                ForEach(visibleChips) { m in
                    menuChip(m)
                }
            }
            .padding(.horizontal, 10)
            // No vertical padding any more: each chip now carries its own 44 pt HIG
            // tap frame (see `chipTapTarget`), whose transparent margin IS the
            // breathing room the 6 pt padding used to provide. Net bar height
            // 38 → 44 (+6). (That clause used to end "clearance above the 1 px bottom
            // border goes 6 → 9 pt" — there is no bottom border any more, see below.)
            // The PILLS are pixel-identical, but a narrow one ("FX") now sits in a
            // 44 pt-wide frame instead of ~38, so the visible GAP between pills grows
            // by up to ~6 pt and the scroll content is slightly wider. Deliberate —
            // don't "fix" it back.
        }
        .background(EchoelTheme.bg)
        // The 1 px bottom rule is GONE (#157, founder 2026-07-27 "alles vereinfachen
        // und schöner"). It was correct while the panel was a transient dropdown: the
        // line was the bottom edge of a MENU BAR, and what lay under it changed. Since
        // #130 the panel is permanent and the chips SELECT it, so the line drew a border
        // between a tab strip and its own content — the visual grammar of "a bar above a
        // form", which is exactly the reading this slice removes.
        //
        // What carries the separation instead — stated precisely, because the obvious
        // version of this sentence is FALSE for one tab: `menuPanelHost` pads 8 pt, and
        // TEN of the eleven panels go through `panel(...)` → `EchoelPanel`, whose card
        // draws its own 1 px `EchoelTheme.border`. `bioPanel` is the exception (a raw
        // `VStack`, see menuPanelHost's FREEZE LAW note), so on the Bio tab there is now
        // neither a rule nor a card edge under the strip. That is survivable rather than
        // invisible: every chip — active AND inactive — carries a solid fill plus a
        // `borderStrong` stroke (3.70:1) in `menuChip`, so the strip is anchored by the
        // chips themselves, not by anything drawn beneath them. The deleted rule used
        // `EchoelTheme.border` at 0.10 opacity — 1.16:1 on black, the decorative token —
        // so almost nothing was lost visually and the grammar was.
        // Uncodixfy: one border per object, not a border per stacked band.
    }

    /// Accessibility (founder axis "accessible", 2026-07-25): give a small chip the
    /// 44 × 44 pt tap target Apple's HIG requires, WITHOUT changing how it looks.
    /// The 26 pt pill stays exactly as designed (Uncodixfy); this only wraps it in a
    /// transparent 44 pt frame and moves hit-testing to that frame via
    /// `contentShape`. Same fix #113 applied to the header monitor tiles — the chip
    /// bar is the app's primary navigation and was 26 pt, i.e. 40 % under the
    /// minimum, which is the single most-touched control in the instrument.
    ///
    /// ONE DELIBERATE DIVERGENCE from #113: that fix is vertical-only, because the
    /// header's 8 pt tile spacing forbids horizontal growth (`HeaderMonitors.swift:391`).
    /// Here `minWidth: 44` is added too — HIG is 44 × 44, not 44 tall — and it is safe
    /// because these chips are `HStack` SIBLINGS, so a wider frame spreads them apart
    /// instead of overlapping. Note `contentShape` is NOT outset here (no
    /// `Rectangle().inset(by: -6)` as in `WorkspaceView.swift:328`), so the targets
    /// stay strictly disjoint with a 6 pt dead gap.
    private func chipTapTarget<Content: View>(@ViewBuilder _ pill: () -> Content) -> some View {
        pill()
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    /// One front-plate tab: tap SELECTS its panel. Deliberately not a toggle any more —
    /// tapping the active chip used to close the dropdown and leave the main window
    /// empty, which is the "everything is hidden behind a menu" feel the founder asked
    /// to be rid of. There is always a panel on the plate (see `displayedMenu`).
    private func menuChip(_ menu: StudioMenu) -> some View {
        let isActive = displayedMenu == menu
        return Button {
            activeMenu = menu
        } label: {
            chipTapTarget {
                Text(menu.label)
                    .font(EchoelTheme.font(12, .semibold))
                    .foregroundStyle(isActive ? EchoelTheme.onPrimary : EchoelTheme.text)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                        .fill(isActive ? EchoelTheme.text : EchoelTheme.fill))
                    // The INACTIVE tab is the case that matters: the active one is a solid
                    // `text` fill and unmissable, so at 1.16:1 the other tabs were invisible
                    // until you found them. borderStrong makes the whole strip readable.
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                        .strokeBorder(EchoelTheme.borderStrong, lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(menu.fullName)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // `directChip` went with the piano roll's door — it had exactly one caller and
    // Swift does not warn about an unused private method, so leaving it would have
    // been invisible dead code in the file that is hardest to keep honest.

    /// THE FRONT PLATE — the instrument's controls, in the main window, always visible.
    ///
    /// Was an anchored dropdown over a 45 % black scrim, capped at 480 pt, marked
    /// `.isModal`. That is what made the app read as a settings sheet rather than an
    /// instrument (founder 2026-07-26: "mehr wie ein Instrument wahrgenommen"): a control
    /// you must first summon, behind a curtain, that then hides everything behind it.
    /// Now the same panel builders sit IN the flow and FILL the space the removed timeline
    /// left (#130) — the chip row above became a tab strip, not a menu.
    ///
    /// What went away and why it is safe:
    /// · the scrim + its `ZStack` branch — nothing to dismiss any more, so the tap-to-close
    ///   target it existed for is meaningless (and a permanent scrim would dim the app).
    /// · `.accessibilityAddTraits(.isModal)` — MUST go with the scrim. Trapping VoiceOver
    ///   focus in a panel that can never be closed would strand the user away from the
    ///   header, transport and chip row.
    /// · the 480 cap + `fixedSize` pair — a front plate should use the window, not hug its
    ///   content and leave a void below it.
    ///
    /// METADATA (black-screen law): NO presentation modifier is added, removed or moved —
    /// the body's count stays at 14 (8 sheet + 2 cover + 3 alert + 1 fileImporter; counted
    /// again 2026-07-28, and the `.sheet(item: $visualShare)` at :881 is deliberately NOT
    /// in it — it sits INSIDE the fullScreenCover's content, not on the body chain). The
    /// figure said 16 here until today, and its own parts summed to 16 only because the
    /// sheet term had drifted to 10; two of those went with `SampleBrowserView` and the
    /// craft-editor slot. Overstating the count is the safe direction for a WARNING but the
    /// dangerous one for a BUDGET, and this line is read as a budget. 14 is the iOS-DEVICE
    /// figure — three of them are behind `#if canImport` (UniformTypeIdentifiers, MetalKit +
    /// UIKit, MultipeerConnectivity), so a SwiftPM/Linux compile sees 11 and cannot reproduce
    /// the ceiling this number exists to protect. But
    /// the root `VStack` goes from 3 children to 4, so the aggregate generic type GROWS by
    /// one `TupleView` element. An earlier version of this comment claimed it shrinks; that
    /// was wrong, and wrong in the dangerous direction — CLAUDE.md's black-screen history is
    /// a body that sat "just under" the limit and was tipped over by additions made on the
    /// strength of a comment. It grows cheaply (a type-erased sibling slot, not a
    /// `ModifiedContent` re-wrapping the whole prior body the way `.sheet` does), which is
    /// why it is acceptable — not because it is free. Panels still render always-open inside
    /// via `echoelPanelForceOpen`.
    ///
    /// FREEZE LAW, now permanent: panel content is evaluated in the root body ALWAYS, not
    /// only while a dropdown is open, so the "live readouts live in a leaf" rule is now
    /// load-bearing rather than a convention.
    /// WHAT ACTUALLY ENFORCES IT (do not mistake this for panel-author discipline): the
    /// `panel(...)` helper wraps content in `EchoelPanel`, which stores the body as an
    /// `@escaping @ViewBuilder` closure and invokes it in ITS OWN `body` — a real
    /// observation boundary, unlike `AnyView`. Ten of the eleven panels go through it, so
    /// this view only evaluates their `init`. `bioPanel` is the ONE raw `VStack` evaluated
    /// directly here; its only live readout is the `BioStripView` leaf, so it is clean —
    /// but it is also the template a future panel could copy. RULE for the next panel:
    /// build it through `panel(...)`, or keep every live read inside a leaf `View` struct.
    private var menuPanelHost: some View {
        // No card of its own: the plate's fill would be `EchoelTheme.bg`, the same black as
        // the root body's background, so it contributed zero contrast — a rounded outline
        // around an `EchoelPanel` card, i.e. the banned panel-in-panel with a purely
        // decorative outer container. It was justified while the card floated over a 45 %
        // scrim; with the scrim gone the panel card is the only container that earns its
        // keep (Uncodixfy: no nested panel types).
        ScrollView {
            dropdownContent
                .padding(2)
        }
        .environment(\.echoelPanelForceOpen, true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    /// Front-plate content = the EXISTING panel builders, one per tab.
    /// Returns AnyView per case so this switch never grows the host's generic
    /// type (type-checker + metadata discipline).
    /// FREEZE RULE (10.76.41/50): this is now evaluated in the ROOT body PERMANENTLY, not
    /// only while a dropdown is open — see `menuPanelHost` for what enforces safety here
    /// (`EchoelPanel`'s deferred `@ViewBuilder`, not author discipline) and for the rule any
    /// new panel must follow.
    private var dropdownContent: AnyView {
        switch displayedMenu {
        case .bio:         return AnyView(bioPanel)
        case .composition: return AnyView(tempoToolsPanel)
        case .session:     return AnyView(sessionPanel)
        case .sound:       return AnyView(soundPanel)
        case .mix:         return AnyView(mixerPanel)
        case .effects:     return AnyView(effectsPanel)
        case .master:      return AnyView(masterPanel)
        case .mood:        return AnyView(moodPanel)
        case .export:      return AnyView(utilityRow)
        case .synth:       return AnyView(visualPanel)
        case .video:       return AnyView(videoPanel)
        }
    }

    /// The panel the front plate shows. A front plate has no "nothing" state — the
    /// instrument's controls are always ON it (founder 2026-07-26: "Alles soll mehr so
    /// aussehen wie früher also im hauptfenster sinnvoll angeordnet"). Sound — the timbre
    /// panel, i.e. the instrument itself — is what an untouched launch shows.
    ///
    /// `activeMenu` stays OPTIONAL only to carry that initial state. NOTHING sets it back to
    /// nil any more: the nine `activeMenu = nil` calls that used to close the dropdown
    /// before opening a sheet are GONE, because the plate is no longer an overlay and cannot
    /// install the invisible tap-blocking layer the two-modals law guards against — so
    /// closing it achieved nothing, while the tab reset was a real side effect. It made
    /// "Master → Routing → dismiss" land the user on Sound with Master gone.
    private var displayedMenu: StudioMenu { activeMenu ?? .sound }

    /// B3: the bio strip's new home. The live numbers (HR/HRV/Br/Coh),
    /// tap-to-learn and the source control render UNCHANGED inside the
    /// dropdown — BioStripView stays the leaf that reads the 10 Hz camera
    /// state (freeze rule), so opening this panel never churns the root body.
    /// Sources: camera pulse starts right here; the BLE strap's ONE door is the
    /// pulse-pill dropdown (BLE-3 single owner); Watch via Health.
    private var bioPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            BioStripView(measuring: running, onStartPulse: { startBiofeedback() })
            Text("Camera pulse starts here. For a BLE chest strap, touch and hold the pulse pill in the header and pick \u{201C}Search for Bluetooth device\u{201D}; Apple Watch feeds in through Health.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showRouting = true
            } label: {
                Label("Open Routing", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.text)
                    .padding(.horizontal, 12).frame(height: 34)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Routing to connect a BLE heart-rate strap")
            // The Apple Health WRITE opt-in belongs here, with the bio data it writes.
            // Its only switch used to live in the Tools grid, which stopped rendering on
            // 2026-07-02 and was deleted 2026-07-26 — but the flag is PERSISTED
            // (`health.write.enabled`) and `start(reading:)` runs unconditionally, so
            // anyone who enabled it in an older build kept writing heart and respiratory
            // samples to Health with no way to stop. A persisted health-data opt-in must
            // always have a reachable off-switch; that is not a nice-to-have.
            #if canImport(HealthKit)
            HealthWriteOptInRow()
            #endif
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    /// The Video window (founder 2026-07-12): the durable recordings library —
    /// clips recorded in the visual window (visual + master mix), inline
    /// playback, share via the studio's ONE existing share slot, delete.
    private var videoPanel: some View {
        panel("Video", "Recorded clips — visual + master mix", isExpanded: $showVideoLibrary) {
            #if canImport(AVKit) && canImport(AVFoundation)
            VideoLibraryPanelContent(
                onShare: { url in share = ExportedFile(url: url) },
                onOpenVisual: {
                    floatingVisualVisible = true
                })
            #else
            Text("Video recording is available on iPhone.")
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
            #endif
        }
    }

    private var soundControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Essentials first, advanced (Mood) last — the view reads top-down from
            // "what most people touch" to "deep tweaks". (Step 2b: the Composition
            // panel dissolved — genre/key/scale/tuning/A4 live in the header
            // CompositionHeaderStrip, its residue in tempoToolsPanel.)
            tempoToolsPanel
            sessionPanel
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
            // The mix as per-part STRIPS, so the whole Mix panel reads as ONE board
            // (founder: "Mix Level sollten auf dem Hackbrett landen … alles an Ort und
            // Stelle"). Each strip co-locates a part's LEVEL with its own bus FX (filter +
            // drive); grouping follows the TWO remaining FX buses, bass and melodic.
            // NO DRUMS (founder 2026-07-26, "es soll keine Drums geben. Auch nicht im
            // Mixer."): the third "Drums" strip and the 8-channel `ChannelRackView`
            // Hackbrett below the reset button are gone with the drum sound itself, along
            // with their bindings and the `setDrumsFX` fan-out. `mixer.drums` /
            // `trackFX.drums` stay in their stores so a user's dialed value is not silently
            // dropped — both are plain UserDefaults keys read with a fallback, so there was
            // never a decode to break. Neither is read for sound again (`mixer.drums` is
            // still WRITTEN by `resetToUnity()`, which is harmless and has no reader).
            // Both strips reflow to 2 columns in landscape / iPad (leaf reads the size
            // class, not the root body → render-safe).
            AdaptiveCardGrid {
                mixStripCard("Bass") {
                    // range 0...1, NOT `MixerStore.range` (which runs to 1.5). Above unity
                    // these faders do nothing at all — the velocity path caps at unity
                    // (`MixerStore.combined`) and the felt sub caps its own gain product.
                    // A field that shows "1.35" to two decimals, persists it, and changes
                    // nothing is the most explicit possible promise that a control works;
                    // #164's "lügende Controls" at maximum visibility. `MixerStore.range`
                    // stays as the PERSISTENCE tolerance, so a value saved at 1.35 before
                    // this still loads and still means unity — no migration needed.
                    // Widen this again only together with #196 (per-role output gain).
                    EchoelValueField(label: "Level", value: mixBinding(\.bass),
                                     range: 0...1, unit: "", decimals: 2)
                    EchoelValueField(label: "Filter", value: bassCutoffBinding,
                                     range: TrackFXStore.cutoffRange, unit: "Hz", decimals: 0)
                    EchoelValueField(label: "Drive", value: bassDriveBinding,
                                     range: TrackFXStore.driveRange, unit: "", decimals: 2)
                }
                // Pad + Lead share the melodic FX bus → one strip. The melodic filter tames
                // a shrill lead directly.
                mixStripCard("Melodic · Pad + Lead") {
                    EchoelValueField(label: "Pad", value: mixBinding(\.pad),
                                     range: 0...1, unit: "", decimals: 2)   // see Bass Level
                    EchoelValueField(label: "Lead", value: mixBinding(\.lead),
                                     range: 0...1, unit: "", decimals: 2)
                    EchoelValueField(label: "Filter", value: melodicCutoffBinding,
                                     range: TrackFXStore.cutoffRange, unit: "Hz", decimals: 0)
                    EchoelValueField(label: "Drive", value: melodicDriveBinding,
                                     range: TrackFXStore.driveRange, unit: "", decimals: 2)
                }
            }

            Button {
                mixer.resetToUnity()
                // Reset writes the store DIRECTLY, so it bypasses `mixBinding` and would
                // leave the sub at the old level while every other part jumped to unity —
                // the same "one owner updates, the other doesn't" split that made this
                // fader inert in the first place. Third of three MUTATORS; `MixerStore.init`
                // is a fourth writer but is covered by the launch restore in `.onAppear`.
                // A new mutator must push both lines below.
                subBass.mixLevel = mixer.bass
                laneVoiceRack.setBassMixLevel(mixer.bass)
                setBassFX(.off)
                setMelodicFX(.off)
                recomposeIfRunning()
            } label: {
                Text("Reset to genre balance")
                    .font(EchoelTheme.font(12, .medium))
                    .foregroundStyle(EchoelTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Sets every part back to the genre's own balance")
        }
    }

    /// A per-part mix STRIP — a titled group (Level + its bus FX). The styling was inherited
    /// from the per-drum-channel strips it used to sit beside; those are gone (no drums), so
    /// this is now simply the mixer's one strip style.
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
        laneVoiceRack.setBassInsert(fx)   // S2-W2-5: bus insert → lane subs too
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

    /// Persist the melodic insert AND push it to ALL melodic voices: pad/harmony `synth`,
    /// the dedicated `leadSynth`, and every Multi-Roll rack slot voice (S2-W1) — so the
    /// whole melody, secondary lanes included, is covered by one "Melodic" control.
    private func setMelodicFX(_ fx: TrackFX) {
        trackFX.set(fx, for: .melodic)
        synth.setInsert(fx)
        leadSynth?.setInsert(fx)
        laneVoiceRack.setInsert(fx)
    }

    // NO DRUMS (founder 2026-07-26): `drumsBinding`, `drumsCutoffBinding`,
    // `drumsDriveBinding` and `setDrumsFX(_:)` lived here. They were the only REACHABLE
    // writers of `trackFX.drums`, `BeatPlayer.masterLevel`/`setFX` and
    // `laneVoiceRack.setDrumsInsert`. `BeatPlayer.setFX` and `BeatPlayer.masterLevel` are
    // not symbols any more at all — #167 deleted the Channel Rack, then the mixer state,
    // then the whole drum kit (2026-07-27). Do not grep for them. `trackFX.drums` still
    // has one writer, `TrackFXStore.resetToClean()` (no production caller, one test
    // caller). Do not read this block as "the symbols have no writers" without grepping,
    // and grep names that still exist: two earlier versions of this line cited
    // `TrackFXStore.reset()` and a live `BeatPlayer.setFX`, neither of which was real.

    /// A binding to one mixer level that re-balances the running take when changed.
    private func mixBinding(_ keyPath: ReferenceWritableKeyPath<MixerStore, Float>) -> Binding<Float> {
        Binding(get: { mixer[keyPath: keyPath] },
                set: {
                    mixer[keyPath: keyPath] = $0
                    // The felt sub takes its level on the AUDIO side, because it has no
                    // per-note velocity for the compose-time path to scale (see
                    // `SubBassVoice.mixLevel`). Pushed unconditionally rather than gated on
                    // `keyPath == \.bass`: the assignment is a clamped Float store into a
                    // mirror, cheaper than the comparison would be worth, and a gate is one
                    // more place to forget when a fader is added.
                    subBass.mixLevel = mixer.bass
                    laneVoiceRack.setBassMixLevel(mixer.bass)
                    recomposeIfRunning()
                })
    }

    /// Step 2b (2026-07-17, PLAN_DISSOLVE_BOTTOM_BAR): the Composition panel's
    /// musical identity moved UP into the chrome — genre/key/scale/tone system/A4
    /// live in `CompositionHeaderStrip` (WorkspaceView), THE tempo control in the
    /// TransportBar's `BodyTempoField` (their edits arrive via
    /// `.echoelCompositionEdited` → `handleCompositionEdit`). What remains here
    /// are the tempo TOOLS (tap · metronome · haptic beat) and the variation
    /// maze — reachable via the transport "•••" door (chrome door "tempo"),
    /// exactly like Master/Export. The full-width BodyTempoField row is NOT
    /// duplicated here (one tempo control app-wide, founder "einer reicht").
    // (Historical, unchanged: beatModeRow removed 2026-07-07 "Schmeiß den Beat
    // komplett raus" — stays defined below, unpresented, reversible. placeRow/
    // weatherRow live in the Session dropdown — chrome-door "session" since
    // step 2c; its name preview moved to the header strip.)
    private var tempoToolsPanel: some View {
        panel("Tempo & variations", "Tap · metronome · haptic beat · ideas",
              isExpanded: $showComposition) {
            tapTempoRow
            metronomeRow
            #if canImport(CoreHaptics)
            hapticsRow
            #endif
            variationsCard
        }
    }

    // MARK: Variation maze audition (#19)

    /// The bio-curated idea-maze, made auditionable INSIDE the Tempo & variations
    /// dropdown (since step 2b; previously the Composition dropdown — no new sheet,
    /// the EchoelStudioView modal chain is at its metadata ceiling).
    /// Reads only @State snapshots (board/appliedSeed), so hosting it in the root-body
    /// dropdown never churns (freeze rule). "Explore" ranks 6 variations of the same
    /// groove by how close each sits to what the body is asking for; tapping one plays
    /// it — the picked skeleton + detail seed reproduce exactly, the live body still
    /// colours tempo/dynamics. Honest score: closeness of realized density to the
    /// body's requested busy-ness (a number, not a health claim).
    private var variationsCard: some View {
        mixStripCard("Variations") {
            HStack(spacing: 8) {
                Text(mazeBoard == nil
                     ? "Variations of the same groove — your body curates, you pick."
                     : "Ideas from your pulse — tap to keep. Your body wants \(densityWord(mazeBoard?.targetDensity ?? 0)).")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(mazeBoard == nil ? "Explore" : "New") { exploreVariations() }
                    .buttonStyle(.plain)
                    .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.text)
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.bg))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
                    .accessibilityLabel(mazeBoard == nil ? "Explore variations" : "Explore new variations")
            }
            if let board = mazeBoard {
                ForEach(Array(board.candidates.enumerated()), id: \.offset) { idx, cand in
                    variationRow(cand, rank: idx)
                }
            }
        }
    }

    /// One ranked idea: rank · density bar · match% · play/applied glyph. Selected =
    /// neutral text emphasis + a faint fill (accent green stays reserved for live bio).
    private func variationRow(_ cand: BioVariationMaze.Candidate, rank: Int) -> some View {
        let isOn = cand.seed == mazeAppliedSeed
        let pct = Int((cand.score * 100).rounded())
        return Button { applyVariation(cand) } label: {
            HStack(spacing: 10) {
                Text("\(rank + 1)")
                    .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.dim)
                    .frame(width: 16, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(EchoelTheme.border.opacity(0.5))
                        Capsule().fill(EchoelTheme.text.opacity(isOn ? 0.85 : 0.5))
                            .frame(width: max(3, geo.size.width * CGFloat(cand.realizedDensity)))
                    }
                }
                .frame(height: 6)
                Text("\(pct)%")
                    .font(EchoelTheme.font(12, isOn ? .semibold : .medium))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 40, alignment: .trailing)
                Image(systemName: isOn ? "checkmark.circle.fill" : "play.circle")
                    .font(.system(size: 15)).foregroundStyle(EchoelTheme.dim)
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .fill(isOn ? EchoelTheme.text.opacity(0.08) : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Variation \(rank + 1), \(pct) percent match\(isOn ? ", playing" : "")")
        .accessibilityHint("Play this idea")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// Plain-language word for a 0…1 groove density — so the board's target reads as
    /// meaning, not a bare number.
    private func densityWord(_ d: Double) -> String {
        switch d {
        case ..<0.25: return "something sparse"
        case ..<0.5:  return "a calm groove"
        case ..<0.75: return "a full groove"
        default:      return "something dense"
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

    // MARK: Panel 1b — Session (place · weather)

    /// The two opt-in toggles that FEED the session name (place token · weather
    /// flavour). Step 2c: the live name preview itself (SessionNamePreviewLeaf)
    /// moved into the header CompositionHeaderStrip — always visible, so the
    /// city still shows itself in the name the moment it resolves. This panel
    /// is chrome-door-only (transport "•••" → "Session"), the exact
    /// Master/Export/Tempo pattern; its Session chip fell with it.
    private var sessionPanel: some View {
        panel("Session", "Place · weather — stamped into the name",
              isExpanded: $showSession) {
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
            .accessibilityHint("Stamps your city into session and export names. Used only for the city name and, if you enable weather, an Apple Weather lookup — never stored by Echoel.")
            // Manual override (founder 2026-07-14: "auch manuell eingeben … oder der
            // Standort nicht funktioniert"): type a place yourself. Works with or
            // without GPS and overrides the resolved city. Text (not a number) → a
            // plain TextField is correct; EchoelValueField is for numeric params only.
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12)).foregroundStyle(EchoelTheme.dim)
                TextField("Ort manuell (optional)", text: $locationNamer.manualPlace)
                    .font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .accessibilityLabel("Manual place name")
                if !locationNamer.manualPlace.isEmpty {
                    Button { locationNamer.manualPlace = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14)).foregroundStyle(EchoelTheme.dim)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear manual place")
                }
            }
            .padding(.horizontal, 10).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(EchoelTheme.border, lineWidth: 1))
            // Always say what this does; once on, say clearly what happened.
            Text(placeStatusLine)
                .font(EchoelTheme.font(11))
                .foregroundStyle(EchoelTheme.dim)
        }
    }

    /// One clear line for the place row in every state (manual / off / looking up /
    /// resolved / denied) — so it's never ambiguous what the location does.
    private var placeStatusLine: String {
        // A manual entry wins in every state (works even with location off/denied).
        let manual = locationNamer.manualPlace.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty {
            return "In the name: \(manual) (manual)"
        }
        guard locationNamer.enabled else {
            return "Adds your city to the name — never stored by Echoel. Or type one above."
        }
        if locationNamer.denied {
            return "Location is off for Echoel in Settings — type a place above instead."
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
                // what it changes; 0 = off (no change), 1 = fully the weather. The two
                // groups sit side by side in landscape / on iPad.
                AdaptiveCardGrid {
                    weatherMixGroup("Sound · Klang", params: WeatherMood.Param.allCases.filter { $0.domain == .sound })
                    weatherMixGroup("Image · Bild", params: WeatherMood.Param.allCases.filter { $0.domain == .visual })
                }

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

    // (Step 2b: tuningRow / genrePicker / tonartRow / kammertonRow / tempoRow moved
    // verbatim into the chrome — CompositionHeaderStrip owns the Pickers/A4 field,
    // the TransportBar's BodyTempoField the tempo; their audible side effects run in
    // handleCompositionEdit below. tuningRow's conditional retune hint text fell
    // with it; nonStandardTuningBanner below keeps the full explainer, unpresented
    // since 2026-07-09, reversible.)

    /// Push the selected tone system's per-pitch-class retune table to the synth
    /// (relative to the current key root). 12-TET → all zeros → identical playback.
    private func applyTuning() {
        let cents = TuningSystem.named(tuningID).pitchClassCents(root: rootIndex).map { Float($0) }
        synth.setTuningCents(cents)
        // The touch instrument plays the same tone system — and its note→colour
        // mapping reads this table, so the colour follows the SOUNDING pitch.
        touchSynth?.setTuningCents(cents)
    }

    /// Step 2b: applies the audible side effects of a USER edit in the chrome's
    /// musical-identity controls (CompositionHeaderStrip Pickers/A4 field, transport
    /// BodyTempoField lock) — posted as `.echoelCompositionEdited`. Each case is the
    /// verbatim onChange/onCommit body of the row it replaces (genrePicker ·
    /// tonartRow · kammertonRow · tuningRow · tempoRow's BodyTempoField), so the
    /// behavior is unchanged; only the control's home moved. The strip posts on
    /// user interaction ONLY (Picker binding set / field commit) — programmatic
    /// writes of the shared keys (e.g. `open(_:)` restoring a project) do NOT
    /// arrive here, exactly like the old panel whose Pickers were unmounted
    /// while a project loaded.
    private func handleCompositionEdit(_ field: String?) {
        switch field {
        case "genre":
            scale = style.scale
            presetIndex = -1
            currentPatch = style.synthPatch   // load the genre's timbre as a starting point
            // …then re-impose the persisted Pluck↔Pad macro, exactly like the "Genre
            // default" menu button, the post-delete path and launch. Without it the
            // picker was the ONE character-load path that skipped the macro, so the same
            // genre had a different envelope depending on how you reached it — and
            // relaunching swapped it again.
            applyArticulation()
            recomposeIfRunning()
        case "key":
            applyTuning()
            recomposeIfRunning()
        case "scale":
            recomposeIfRunning()
        case "tuning":
            applyTuning()
        case "a4":
            synth.setTuning(a4Hz: session.a4Hz); subBass.setTuning(a4Hz: session.a4Hz); touchSynth?.setTuning(a4Hz: session.a4Hz); laneVoiceRack.setTuning(a4Hz: session.a4Hz); bioVoice.setTuning(a4Hz: session.a4Hz)
            // Note grids recolour with the concert pitch (founder
            // 2026-07-12) — push the new A4 to the roll immediately,
            // not only on the next compose, so an open/soon-opened
            // piano roll paints the raster in the NEW tone colours.
            pianoRoll.musicalA4Hz = session.a4Hz
            recomposeIfRunning()
        case "tempoLock":
            // Lock adoption happens INSIDE BodyTempoField (it glides the clock, and
            // everything that sounds or shows the tempo follows the clock);
            // this is the recompose hook the panel's full field used to pass.
            recomposeIfRunning()
        default:
            break
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
                    // ALWAYS push the clock (not only while running): the mode/lock binding
                    // (`WorkspaceView.modeBinding`) freezes at the CLOCK's current tempo,
                    // so the clock must already carry the tapped value when that fires — otherwise tapping while
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

            // LABEL IS A RELEASE, NOT A MUTE (review 2026-07-26). "Silence" over-promised:
            // this button releases every held note, but it does not stop the transport, so the
            // roll re-attacks on its next step and the bio arm re-opens on the next inhale.
            // The accessibility hint below always said "release"; the label now agrees.
            Button { panicAllNotesOff() } label: {
                Label("Release all notes", systemImage: "speaker.slash")
                    .font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Immediately release every sounding note on every voice")

            // Re-doors (deep audit 2026-07-12): AudioInputPickerView carries the
            // FeedbackGuard monitoring toggle, PatchbayView the OSC/ADM/Art-Net/
            // sACN routes — both lost their only trigger when the Tools grid left
            // the body (2026-07-02). SLOT-REUSE: these set the EXISTING dead
            // sheet slots (showInput/showRouting) — no new modal in the chain.
            // No close-first needed: the plate is not an overlay, so only the sheet is
            // ever a presented layer.
            HStack(spacing: 8) {
                masterDoorButton("Audio input", icon: "mic",
                                 hint: "Microphone monitoring with feedback protection") {
                    showInput = true
                }
                masterDoorButton("Routing", icon: "app.connected.to.app.below.fill",
                                 hint: "OSC, immersive object, and lighting outputs") {
                    showRouting = true
                }
            }
        }
    }

    /// Compact secondary door row used by the Master panel (Uncodixfy: solid
    /// fill, 1 px border, ≤12 px radius, no decoration).
    private func masterDoorButton(_ title: String, icon: String, hint: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(EchoelTheme.font(12, .medium)).foregroundStyle(EchoelTheme.text)
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }

    /// Performance panic — release every sounding note on EVERY voice this view can reach,
    /// plus MIDI out. Kills stuck notes live.
    ///
    /// The list used to be `synth`, `subBass`, `midiOut` — three of the eight releases below.
    /// `leadSynth`, `touchSynth` (both `PolySynthVoice`, the play surfaces), `bioVoice`
    /// (monophonic, driven by incoming MIDI note-on/off via `drainControllerEvents`), every
    /// voice in `laneVoiceRack`, and the piano roll's own active-note table all produce or hold
    /// notes and all survived the panic, while the button's accessibility hint promised "every
    /// sounding note on every voice". A stuck note on the lead or the play surface is a *more*
    /// likely reason to reach for this than one on the composer's synth, so the button failed
    /// precisely in the case it exists for.
    ///
    /// NOT COVERED BY A TEST: this method is `private` on a `View` struct, so XCTest cannot
    /// reach it — nothing fails if a release is dropped from this list. Task #168 is the seam.
    ///
    /// `pianoRoll.allNotesOff()` comes FIRST and is not redundant with the direct releases
    /// below: it also CLEARS the roll's `active` note table. Without it the roll still
    /// believes those notes are held, and its next tick issues a pitch-matched
    /// `noteOff(pitch:)` — which on the monophonic `SubBassVoice` releases whatever is
    /// sounding at that pitch, i.e. it can cut a note the user has just retriggered AFTER
    /// the panic. `stopEverything(reason:)` has always called both in this order, though its
    /// own comment gave a different reason ("in case a voice ref falls out of sync") — the
    /// stale-`active` hazard above is the one that actually bites, and either way the panic
    /// button must match Stop or it is a weaker Stop wearing an "every voice" label.
    ///
    /// If a new note-producing voice is added to this view, it belongs here in the same edit.
    /// Nothing in the type system enforces that — this comment is the enforcement.
    private func panicAllNotesOff() {
        pianoRoll.allNotesOff()     // releases poly/lead/sub/kind/MIDI AND clears `active`
        synth.allNotesOff()
        subBass.allNotesOff()
        leadSynth?.allNotesOff()
        touchSynth?.allNotesOff()
        bioVoice.panic()            // mono release + clears a stuck controller-held latch
        laneVoiceRack.allNotesOff()
        midiOut.allNotesOff()
    }

    // MARK: Panel — Visual (immersive sound→light)

    private var visualPanel: some View {
        // No subtitle, on purpose (founder 2026-07-27: "Das kann weg: ist denkerisch
        // selbst erklärend"). It was the one panel header in the Studio that EXPLAINED
        // instead of labelling — every other one is a terse noun phrase ("Level per
        // part", "Production character"). A window you can already see, drag and resize
        // does not need a sentence telling you that you can drag and resize it.
        panel("EchoelSynth", isExpanded: $showVisualSettings) {
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
                    .fill(floatingVisualVisible ? EchoelTheme.text : EchoelTheme.fill))
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
            Text("Colour defaults to the heard tone octave-transposed into visible light (its frequency doubled until it reaches the visible band, rendered via CIE 1931); Hue/Saturation rotate the palette for VJ/performance use. Motion is capped so the flash rate always stays under the 3 Hz safety limit.")
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
            // LEVEL — a real gain on the touch voice's output (`PolySynthVoice.setGain`),
            // NOT a velocity trim. Until now the surface had no level at all: its place in
            // the mix sat hardcoded in `TouchPitchMap.velocity`'s 0.45…0.95 range, widened
            // by hand in July so played notes would cut through. Velocity is how HARD you
            // played; level is how loud the instrument is. Conflating them is what made
            // three other faders in this app lie (see MixerStore).
            EchoelValueField(label: "Level", value: $touchLevel,
                             range: 0...1.5, unit: "", decimals: 2)
                .onChange(of: touchLevel) { _, v in touchSynth?.setGain(Float(v)) }
            EchoelValueField(label: "Position morph", value: $touchMorphDepth,
                             range: 0...1, unit: "", decimals: 2)
            // LIFE — per-note micro-variation in brightness and attack, so two identical
            // taps never produce two identical notes (founder 2026-07-27: "leben wie ein
            // echtes Instrument mit micro changes"). 0 = off and bit-identical.
            EchoelValueField(label: "Life", value: $touchLife,
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
                    .fill(selected ? EchoelTheme.text : EchoelTheme.fill))
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
                                    .fill(selected ? EchoelTheme.text : EchoelTheme.fill))
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
                    // Selected chips fill with .text (the app-wide menuChip law) —
                    // accent stays exclusive to the LIVE BIO SIGNAL.
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(spectralDonuts ? EchoelTheme.text : EchoelTheme.fill))
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
                                .fill(on ? EchoelTheme.text : EchoelTheme.fill))
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
                                .foregroundStyle(selected ? EchoelTheme.onPrimary : EchoelTheme.text)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(selected ? EchoelTheme.text : EchoelTheme.fill))
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
            // Sub character (founder "sub culture" 2026-07-16, in-house SubCharacter
            // DSP): presence = octave-harmonic read on small speakers; heat =
            // loudness-compensated saturation. 0.50/0.50 = the previous fixed sound.
            EchoelValueField(label: "Sub presence", value: Binding(
                get: { subBass.subPresence },
                set: { subBass.subPresence = min(max($0, 0), 1) }
            ), range: Float(0)...Float(1))
            EchoelValueField(label: "Sub heat", value: Binding(
                get: { subBass.subHeat },
                set: { subBass.subHeat = min(max($0, 0), 1) }
            ), range: Float(0)...Float(1))
            Text("Reinforces the bass an octave below — feel it on a sub, in headphones, or as haptics. Presence makes it read on small speakers (octaves only, always in key); heat saturates without getting louder.")
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
    /// `subtitle` defaults to empty — `EchoelPanel` already omits the line entirely when
    /// it is, so a panel whose title says everything renders as a clean single-line
    /// header rather than a title with a gap under it.
    private func panel<Content: View>(_ title: String, _ subtitle: String = "",
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
        // The reason is threaded INTO the task and stamped only when generate()
        // actually runs (T2, log 2361: stamping at SCHEDULE time left a stale
        // "evolve" behind when stopEverything cancelled the task — the founder's
        // four post-stop variation taps then logged as a phantom zombie evolve).
        // Coalescing still means the LAST scheduled reason wins: each call
        // cancels the pending task, so only the last task (and reason) survives.
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
            generate(startTransport: false, reason: reason)
        }
    }

    // MARK: - Utilities (export · projects)

    /// Export lives behind ONE compact header (minimal-but-works, 2026-07-06E):
    /// the default page shows only Bio strip · Start · pads; capturing a loop is
    /// a deliberate act, one tap away.
    private var utilityRow: some View {
        // Subtitle names MIDI too (#188) — it is the only place the door is visible before
        // the panel is opened, and a restored feature nobody can find is a removed feature.
        panel("Export", "WAV loop · MIDI for your DAW · keep what just played", isExpanded: $showExport) {
        VStack(spacing: 10) {
            if !hasComposed {
                // The export/keep/save buttons below are disabled until there's a take —
                // say WHY, so a first-run user doesn't read the greyed buttons as broken.
                // Name the REAL button (audit 2026-07-09: no "Generate" exists — first-run
                // users hunted for it and read the greyed buttons as broken). Video
                // recording lives in the floating visual window, not here.
                Text("Start with the pulse button (next to Play) first — then you can export the loop as a WAV or as MIDI.")
                    .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if composerClipGridFull {
                // Founder v287/v288: the generated take could not get its own MIDI clip
                // because the 8-slot clip grid is full. Honest + visible (the sound still
                // plays) — mirror of the Arrange track panel's gridFullWarning.
                // The old wording told the user to "clear a slot … on the timeline". Both
                // the clip grid UI and the timeline were deleted with #121 Slice 4, so it
                // named a surface that does not exist and an action nobody can take. State
                // the consequence instead: nothing is lost, only the internal slot.
                Text("Internal clip slots are full (\(ClipStore.slotCount)) — the generated take still plays and still exports.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.warning)
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

            // MIDI export — RESTORED (#188, founder 2026-07-27). It was removed 2026-07-02
            // ("Midi Quatsch kann auch weg"); the exporter itself was never deleted and
            // stayed tested, so `exportMIDI()` sat here with no caller while the App Store
            // text still promised it. Export is explicitly inside the product boundary
            // (unlike arrangement / multitrack / video), and carrying a bio-take into a DAW
            // is what separates an instrument from a toy.
            //
            // ⛔ NO NEW `.sheet`. This flows through the SAME `share` slot the WAV export
            // already uses (`exportMIDI` ends in `share = ExportedFile(url:)`), so the
            // presentation-modifier chain on this body does not grow by one — that chain is
            // the metadata ceiling the app already crashed into (black screen, 10.76.34).
            // Zero new state, zero new modifier: a button, nothing else.
            // ⛔ NO bar count in this label. `loopBars` drives the WAV capture length, but
            // the MIDI region length comes from `pianoRoll.arrangementForExport()`, and
            // after `open(_:)` those disagree: `PianoRollView.load(_:)` clears
            // `arrangementBars`, so `arrangementForExport()` returns 1 bar while `loopBars`
            // still reads 8 — a label promising "8 bars" over a 1-bar file. Naming no number
            // is honest; naming the wrong one is the lying-control class again.
            Button { exportMIDI() } label: {
                Label("Export MIDI for your DAW", systemImage: "pianokeys")
                    .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            // `isExporting` is a WAV concern, but both writers land in the ONE `share` slot,
            // so a MIDI export mid-record would silently replace the WAV the user is waiting
            // for. Disabled together for that reason, not because MIDI export is slow.
            .disabled(isExporting || !hasComposed)
            .accessibilityHint("Exports the take as a MIDI file to open in a DAW, with tempo and key")

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
        if running { stopEverything(reason: "user-stop") } else { startBiofeedback() }
    }

    /// Consume a Siri/Shortcuts request deposited by an App Intent, routing it to
    /// the same handlers the on-screen buttons use. Read-once, so it fires exactly
    /// once per request; unknown/absent actions are a no-op.
    private func handlePendingIntent() {
        #if canImport(AppIntents)
        guard let action = EchoelIntentInbox.take() else { return }
        switch action {
        case .start:    if !running { startBiofeedback() }
        case .stop:     if running { stopEverything(reason: "intent-stop") }
        case .keepLoop: Task { await keepLastLoop() }
        }
        #endif
    }

    private func startBiofeedback() {
        EchoelCrashLog.breadcrumb("Start tapped")
        // #22 follow-up (founder log v255: rollMixGain=0.00 → 15 s silence →
        // exit): an explicit Start expresses "I want to HEAR it" — heal a
        // persisted-silent roll slot (mute / zero level / stale solo) before
        // the first generate. Automatic paths (evolve/re-seed) never do this.
        // Name WHICH of the three causes it was. `rollSlotSilenceReason` was built for
        // exactly this and had zero production readers until now — the founder iterates
        // from pasted diag logs, so "healed" alone tells him a rescue happened but not
        // what had gone wrong, and a persisted mute is a different story from a stale
        // solo left by another lane. ONE call, not read-then-heal: the reason is nil
        // after the heal, so the two-step form is order-dependent and fails silently.
        if let cause = timelineStore.healRollSlotNamingCause() {
            EchoelCrashLog.breadcrumb("start: silent roll slot healed (cause: \(cause.rawValue))")
        }
        running = true
        bus.setInstrumentRunning(true)   // chrome mirror (TransportBar pulse button)
        // NO forced visual anymore (founder 2026-07-12: "Visuals Fenster muss
        // nicht direkt angehen beim Biofeedback. Ein Hinweis kommt ja über das
        // Monitor Fenster oben rechts."): Start no longer stages the fullscreen
        // visual — the header monitor is the living hint, the user opens the
        // window when they want it. goImmersiveForTake()/restorePreTakeVisual()
        // stay in code (reversible); the restore call is a no-op while nothing
        // stages. This supersedes the 2026-07-06B auto-fullscreen behaviour.
        // One fresh musical identity PER TAKE: the pre-lock (no-body) structure seed is
        // drawn here once and then held, so warm-up recomposes/edits stay the same piece.
        takeFallbackSeed = UInt64.random(in: 1...UInt64.max)
        #if canImport(WeatherKit) && canImport(CoreLocation)
        fetchWeatherFlavour()   // E3b: non-blocking; salt lands on the next re-seed
        #endif
        startTask?.cancel()
        startTask = Task { @MainActor in
            // SOUND FIRST, bio source second. The order is the whole point.
            //
            // `startBioSource()` awaits `AVCaptureDevice.requestAccess`, which on a FIRST RUN
            // suspends until the user answers the permission dialog — indefinitely if they
            // ignore it or background the app. Composing after that await meant the very first
            // "Create from Within" tap flipped the button to "Stop" and then produced nothing:
            // no audio, no transport, no visual reaction. The old comment here even claimed
            // "immediate first sound — no lock-wait stall", which was true of the pulse LOCK
            // and false of the permission grant. First impression of the instrument, so it is
            // worth the reorder rather than a caveat.
            //
            // Nothing below depends on the bio source being up: `generate` composes from
            // whatever bio is on the bus (`EngineBus.usableBio()` returns nil until a frame
            // arrives) and falls back to real neutral values — HR 70, coherence 0.5, the
            // take's own random structure seed, a genre-clamped tempo — so the first sound is
            // musical, not degenerate. The real heartbeat arrives later via
            // `snapToLockWhenReady()`, which is also what latches the body tempo.
            //
            // `bioModulationEnabled` is armed here and is NOT inert: with no frames on the
            // bus, `EchoelDDSP` note-on applies its NEUTRAL reading (0.5 across the board),
            // which centres the timbre on the patch but does overwrite the velocity-derived
            // per-note amplitude — see the guard at `EchoelDDSP.applyBioToVoice`'s call site.
            // Unchanged by this reorder (the flag was already set on this side of `generate`),
            // but do not "simplify" it on the belief that it does nothing.
            synth.bioModulationEnabled = true
            generate(reason: "start")
            startEvolving()

            // Now bring the body in. Anything that must wait for the camera dialog — when
            // there IS one — stays below this await. Note this only holds for the camera
            // branch: the BLE branch's `start` is synchronous, so CoreBluetooth's own prompt
            // can still coincide with the HealthKit ask below (pre-existing).
            await startBioSource()
            guard running, !Task.isCancelled else { return }
            // The user just STARTED a bio take and any camera permission dialog is
            // answered (startBioSource awaited it) — this is the honest moment for
            // the app layer to run its deferred HealthKit ask (UX-3), sequentially,
            // never stacked on another system sheet.
            NotificationCenter.default.post(name: .echoelBioSourceStarted, object: nil)
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

    /// Re-arm what a roll PAUSE cancelled (#161). Anything the pause stopped and this does not
    /// restart is a capability the take loses silently for the rest of its life.
    ///
    /// NOTE 2026-07-26: no roll pause can occur any more (the roll's door is gone, so nothing
    /// mounts the only view that requests one). This function is NOT dead, though — it also runs
    /// on `.resume`, i.e. every ordinary Start. Only the "roll" in its name is now historical.
    ///
    /// Both calls cancel their own predecessor, so this is safe on the NORMAL Start path too
    /// (which runs `startEvolving()` and `snapToLockWhenReady()` itself, synchronously, in the
    /// same turn as the transport flip — it can never end up with two loops or two watchers).
    private func resumeAfterPause() {
        if evolveTask == nil { startEvolving() }
        // The lock-snap watcher is the one-shot that waits for the pulse to SETTLE and then
        // re-seeds the take from the real heartbeat. Pausing inside its window — which is
        // exactly the ~20 s finger-on-lens window this whole fix exists to protect — used to
        // drop it for good: the body tempo was then only recovered if some later evolve tick
        // happened to catch a trustworthy frame. Re-arm while the take has never latched a body
        // tempo; once `tempoSeededFromBody` is true there is nothing left to snap to.
        if !tempoSeededFromBody { snapToLockWhenReady() }
    }

    /// PAUSE (#161) — stop the clock and every sounding note, but KEEP the body session.
    ///
    /// The ONE-Stop law exists so nothing is left ARMED behind a stopped clock. This honours
    /// that where it matters and departs from it where it hurt: every generative DRIVER that
    /// would keep working against a stopped transport is cancelled (evolve, regen, the
    /// lock-snap re-seed — the last one also protects the user's roll edits, which a mid-pause
    /// regenerate would silently overwrite, since `regenTask`'s own guard is `running` and that
    /// stays true here), while the SENSOR keeps running. `stopBioSource()` costs another
    /// finger-on-lens re-lock, ~20 s, to undo — that cost is what made the Notes editor
    /// unusable during a take. (That editor has no door since 2026-07-26, so this whole
    /// function is currently unreachable; it is kept because the reasoning is the design of
    /// the pause state, and deleting it is a deliberate slice, not a comment cleanup.)
    ///
    /// BE HONEST ABOUT WHAT THIS IS: "camera live, no music" is a NEW state, introduced here.
    /// An earlier version of this comment called it "the state the Bio panel's own arm already
    /// puts the app in" — false. Every reachable arm (`BioStripView`'s pulse start, the source
    /// picker when idle) goes through `startBiofeedback()`, i.e. a full take; the camera-only
    /// arms live in `BioSourceView`/`SessionView`, both doorless. So this is a product decision,
    /// not a precedent — worth a founder look, not a citation.
    ///
    /// `running` deliberately stays TRUE: the take is paused, not ended. The chrome's ■ is
    /// still the one full Stop.
    ///
    /// KNOWN, ACCEPTED LIMITS of calling this a "pause": `keepAwake` keys on `running`, so the
    /// screen will not sleep during an indefinitely long pause (defensible — the camera is up
    /// anyway); the transport's own stop subscribers still fire and are not resumable
    /// (`RecordController` commits an in-flight recording, `TimelineRegionPlayer` drops
    /// follow-state); and a cancelled `regenTask` silently drops a pending user-edit recompose.
    /// None of these leaves a driver armed behind a stopped clock, which is what the law is for.
    private func pausePlaybackKeepingSession() {
        evolveTask?.cancel(); evolveTask = nil
        regenTask?.cancel(); regenTask = nil
        lockSnapTask?.cancel(); lockSnapTask = nil
        // The roll already released its own notes before stopping the clock; this covers the
        // other seven voices, which a bare `pattern.stop()` does not touch.
        panicAllNotesOff()
        EchoelCrashLog.breadcrumb("pausePlaybackKeepingSession: clock + voices stopped, bio kept")
    }

    /// `reason` lands in the diagnostic breadcrumb — the founder's device logs
    /// showed bare "stopEverything" lines with no way to tell a user stop from a
    /// programmatic kill (the H7 fold-unmount hid behind exactly that ambiguity).
    private func stopEverything(reason: String) {
        // SAFETY BELT for the #161 pause flag: every other stop path lands here without going
        // through the transport `onChange` that normally consumes it. Dropping it here makes a
        // LATCHED flag impossible — otherwise a request raised by the roll but never consumed
        // (a stop routed around that observer) would downgrade the NEXT real Stop to a pause,
        // i.e. a session that refuses to end with the camera still live. Cheap and total.
        _ = pianoRoll.consumePlaybackOnlyStopRequest()
        running = false
        bus.setInstrumentRunning(false)  // chrome mirror (TransportBar pulse button)
        tempoSeededFromBody = false      // next take re-seeds tempo from a fresh pulse
        lastGenBody = nil                // next Start re-captures a fresh body baseline (evolve hold)
        startTask?.cancel(); startTask = nil
        sourceSwitchTask?.cancel(); sourceSwitchTask = nil   // no source hot-swap after Stop
        evolveTask?.cancel(); evolveTask = nil
        regenTask?.cancel(); regenTask = nil
        lockSnapTask?.cancel(); lockSnapTask = nil
        beatPlayer.pattern.stop()       // stops the transport (→ onStop flush)
        // Force-silence EVERY voice explicitly — never rely on the onStop callback
        // wiring alone. `panicAllNotesOff()` now leads with `pianoRoll.allNotesOff()` itself,
        // so the explicit call below is redundant — kept as a cheap explicit guarantee for the
        // ROLL specifically. It buys nothing for the other seven releases: Stop is still
        // wholly dependent on the helper for synth / subBass / lead / touch / bio / rack /
        // MIDI. Both calls are idempotent, so doubling up can never leave a note ringing
        // ("Sound bleibt hängen" fix).
        pianoRoll.allNotesOff()
        panicAllNotesOff()
        synth.bioModulationEnabled = false   // stop the 10 Hz timbre drive too
        synth.setBreathSwell(depth: 0)       // stop the 0.1 Hz breath pacing
        stopBioSource()
        restorePreTakeVisual()
        EchoelCrashLog.breadcrumb("stopEverything(\(reason)): transport + all voices released")
    }

    /// Stage the immersive fullscreen visual for a take (Start). Remembers the prior
    /// window state so Stop can put it back.
    private func goImmersiveForTake() {
        #if canImport(MetalKit) && canImport(UIKit)
        let d = UserDefaults.standard
        // Key + default via the namespace (H15-KEYSTORE): these programmatic reads
        // must fall back to the SAME canonical default as every @AppStorage site.
        preTakeVisualVisible = d.object(forKey: StudioDefaultKeys.floatingVisualVisible.key)
            as? Bool ?? StudioDefaultKeys.floatingVisualVisible.value
        preTakeVisualSize = d.object(forKey: "visual.floating.size") as? Int
        d.set(true, forKey: StudioDefaultKeys.floatingVisualVisible.key)
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
        let visibleNow = d.object(forKey: StudioDefaultKeys.floatingVisualVisible.key)
            as? Bool ?? StudioDefaultKeys.floatingVisualVisible.value
        let sizeNow = d.object(forKey: "visual.floating.size") as? Int
        guard visibleNow, sizeNow == FloatingVisualWindow.WindowSize.fullscreen.rawValue else { return }
        if let v = preTakeVisualVisible { d.set(v, forKey: StudioDefaultKeys.floatingVisualVisible.key) }
        d.set(preTakeVisualSize ?? FloatingVisualWindow.WindowSize.small.rawValue,
              forKey: "visual.floating.size")
        #endif
    }

    /// Begin publishing a bio signal from the SELECTED source (header pill dropdown,
    /// founder 2026-07-15). Camera rPPG by default (cover the lens); a Bluetooth strap
    /// (universal 0x180D) or the deterministic Simulation demo if the user picked those,
    /// so the instrument always plays. Failures are swallowed — generation falls back to
    /// neutral defaults.
    private func startBioSource() async {
        switch BioSourceKind(rawValue: bioSourceRaw) ?? .camera {
        case .camera:
            #if canImport(AVFoundation)
            EchoelCrashLog.breadcrumb("camera starting")
            await cameraRPPG.start(publishing: bus)
            EchoelCrashLog.breadcrumb("camera started (running=\(cameraRPPG.isRunning))")
            // Returns as soon as the camera is publishing — NO lock-wait here. Sound
            // starts immediately (composed from neutral defaults if no pulse yet) and
            // snapToLockWhenReady() re-seeds from the real heartbeat the moment it locks.
            #endif
        case .ble:
            #if canImport(CoreBluetooth)
            EchoelCrashLog.breadcrumb("BLE HR strap starting (scan)")
            polarH10.start(publishing: bus)   // idempotent; opens the Bluetooth scan
            #endif
        case .sim:
            EchoelCrashLog.breadcrumb("bio simulation starting")
            demoSource.start(publishing: bus) // deterministic demo frames; source == .fallback
        }
    }

    /// Stop EVERY bio publisher (idempotent) so no source keeps feeding the bus after
    /// Stop or a source switch.
    private func stopBioSource() {
        #if canImport(AVFoundation)
        cameraRPPG.stop()
        #endif
        #if canImport(CoreBluetooth)
        polarH10.stop()
        #endif
        demoSource.stop()
    }

    /// Switch the live BIO INPUT source from the header pill's long-press dropdown
    /// (founder 2026-07-15: "camera light · Search for Bluetooth Device · Simulation").
    /// Only ONE source feeds the bus at a time. If the instrument is already running we
    /// hot-swap (drop the old publisher, bring up the new one, keeping the music going);
    /// if it's idle, picking a source activates the instrument with it — same as a tap.
    private func selectBioSource(_ id: String?) {
        guard let id, let kind = BioSourceKind(rawValue: id) else { return }
        bioSourceRaw = kind.rawValue
        if running {
            // Supersede any IN-FLIGHT start before switching. The camera's
            // `await cameraRPPG.start(publishing:)` can stay suspended for seconds (the
            // first-launch permission dialog). If we stopped + restarted synchronously,
            // that suspended camera start would resume AFTER our stop and keep the camera
            // publishing alongside the newly-picked source — two sources fighting over the
            // bus snapshot (reviewer-caught race). So: cancel both the initial start and
            // any prior switch, let them DRAIN, then stop-all and bring up the new source.
            let priorStart = startTask
            let priorSwitch = sourceSwitchTask
            startTask?.cancel(); startTask = nil
            sourceSwitchTask?.cancel()
            sourceSwitchTask = Task { @MainActor in
                _ = await priorStart?.value       // an in-flight camera.start finishes first
                _ = await priorSwitch?.value      // and any prior switch drains
                guard running, !Task.isCancelled else { return }
                stopBioSource()                   // now safe — nothing is mid-start
                await startBioSource()            // bring up the newly-selected one
            }
        } else {
            startBiofeedback()                    // idle → activate with the chosen source
        }
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

    /// Build the composer `Input` from the CURRENT body + settings — the ONE source
    /// of truth shared by `generate()` and the variation-maze audition, so what you
    /// audition is EXACTLY what plays (no duplicated composition logic).
    ///
    /// - `advanceEvolution`: `true` for a real take (moves the melody nonce so the
    ///   next take is a fresh variation); `false` for a read-only preview (the maze
    ///   reads the body without perturbing the evolve cursor).
    /// - `detailSeedOverride` / `structureSeedOverride`: when set (the maze REPLAYING a
    ///   chosen candidate), they replace the body-derived seeds so the picked idea is
    ///   reproduced exactly — the live body still colours tempo/dynamics, but the
    ///   groove skeleton + melodic detail are the ones you auditioned. Both `nil`
    ///   (every existing caller) ⇒ the original behaviour, bit-identical.
    ///
    /// Returns the `Input` plus the derived seeds/phase and the frame it read, so
    /// `generate()` reuses the SAME frame downstream (tempo trust · caption · body hold).
    private func makeComposerInput(advanceEvolution: Bool,
                                   detailSeedOverride: UInt64? = nil,
                                   structureSeedOverride: UInt64? = nil)
        -> (input: BioComposer.Input, frame: BioSampleFrame?,
            evolvingSeed: UInt64, structureSeed: UInt64, basePhase: Int) {
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
        if advanceEvolution { evolution &+= 1 }
        // Cohesion: the STRUCTURE seed is the body-only seed (no evolution nonce), so
        // the harmonic skeleton / register / density stay stable while the DETAIL seed
        // (with the nonce) evolves the melody — consecutive takes feel like the same
        // piece breathing, not a new random one ("homogener klingen"). When the body
        // shifts, the structure evolves with it; with no signal both are random.
        // An explicit override (maze replay) pins the skeleton to the audition's.
        var structureSeed = structureSeedOverride ?? bioSeed(frame)
        // E3b: the sky flavours the SKELETON only (structure seed) — the detail
        // seed below stays body+evolution, so weather never outweighs the body.
        // P5: the salt is now one mixable influence — applied only while the
        // "Structure" weather mixer is up (0 = off = bit-identical). Skipped when the
        // skeleton is an explicit override (the audition already resolved it).
        #if canImport(WeatherKit) && canImport(CoreLocation)
        if structureSeedOverride == nil,
           weatherEnabled, let wx = weatherContribution, wx.structureSalt != 0,
           WeatherMood.Param.structure.currentIntensity() > 0 {
            structureSeed ^= wx.structureSalt
        }
        #endif
        // Detail seed: the picked candidate's seed when replaying the maze, else the
        // evolving body seed as before.
        let evolvingSeed = detailSeedOverride ?? (structureSeed ^ (evolution &* 0x9E3779B97F4A7C15))
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
        // (the 8-min "stuck at 6 notes" after a pulse episode).
        //
        // Deliberately NOT `frame.coherenceForSound`, which is the same rule with a
        // hardcoded 0.5: here a HELD body's last real coherence is available and is a
        // strictly better neutral than the generic one, so it must win the fallback.
        // Routing this through the shared property would throw that away.
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
            // `hrvForSound`, not the raw value: `fin`'s fallback only fires for nil or
            // non-finite, so a REAL 0 (= not measured yet) went straight through — and in
            // BioComposer low HRV means high sympathetic load, so the composer answered
            // "I know nothing about this body" with maximum arousal and a busier take.
            hrvNormalized: fin(frame?.hrvForSound, 0.5),
            coherence: liveCoh,
            breathPhase: fin(frame?.breathPhase, 0),
            breathDepth: dynamicDepth,
            key: key,
            style: style,
            // M1 Flow/Loop: the transport intent follows the tempo lock — Loop
            // (lockBPM) = studioLocked for production, Flow = flowFree (follows the
            // body). Was hardcoded .flowFree (the split-brain: locking the BPM left
            // the composer intent + saved project permanently flowFree).
            // NOT purely a label change (reviewer 2026-07-25): `input.mode` also feeds
            // `tempo(for:)` INSIDE compose(), which drives `tempoDensityScale` — so a
            // locked take now scales its note density for `lockedBPM` instead of the
            // resting-heart tempo. That is the INTENDED fix (a 124 BPM loop should be
            // scaled for 124, not for ~66 — the old "auf 132 zu hektisch" mismatch),
            // not a regression; the downstream transport tempo still comes from
            // `lockedBPM` (see the tempo block below). NEEDS-FOUNDER-VERIFY on device.
            mode: ComposerMode(locked: lockBPM),
            lockedTempo: lockBPM ? lockedBPM : 90,
            mood: moodForInput,
            seed: evolvingSeed,
            structureSeed: structureSeed,
            progressionPhase: basePhase,
            // H1 DEFAULT-ON (Modus-Lehre 2026-07-17: kein Verify-Gate ohne
            // erreichbaren Schalter — der Founder-Hörtest IST das Verify):
            // echte Stimmführung statt Blockshift; Kohärenz führt die Strenge,
            // Atemtiefe die Lage. Rollback = dieses eine Wort auf false.
            voiceLeading: true,
            // H3 DEFAULT-ON (gleiche Lehre): die ECHTE HRV des Spielers ist die
            // Amplitude der finalen Velocity-Mikrovariabilität — variables Herz
            // löst den Take, starres Herz lässt ihn maschinen-eng; hrv 0 ⇒ exakt
            // null Jitter. Rollback = dieses eine Wort auf false.
            humanize: true,
            // H2 DEFAULT-ON (gleiche Lehre): funktionsgerankte Akkord-Journey
            // statt Legacy-Progression — die KOHÄRENZ wählt die Spannung
            // (gesettelt → erwartete Fortsetzung, unruhig → Borrowings).
            // Rollback = dieses eine Wort auf false.
            suggestJourney: true
        )
        return (input, frame, evolvingSeed, structureSeed, basePhase)
    }

    /// - Parameter startTransport: when `true` (the user-initiated first generate) this
    ///   starts the transport if it isn't already running. Background/onChange re-seeds
    ///   pass `false` so they only swap notes into an ALREADY-playing transport — they
    ///   must never resurrect a transport the user stopped from the persistent transport
    ///   bar (the bar's Stop calls `pattern.stop()` directly, leaving the Compose session
    ///   `running` but silent; without this the ~25–45 s evolve tick would restart it).
    /// - Parameters `detailSeedOverride`/`structureSeedOverride`: the variation maze
    ///   REPLAYING a chosen candidate — the picked groove skeleton + melodic detail are
    ///   reproduced exactly while the live body still colours tempo/dynamics. Both `nil`
    ///   (every other caller) ⇒ the body-driven seeds, unchanged.
    private func generate(startTransport: Bool = true,
                          detailSeedOverride: UInt64? = nil,
                          structureSeedOverride: UInt64? = nil,
                          reason: String? = nil) {
        // Honest breadcrumb label (T2): callers name themselves at RUN time; nil
        // keeps whatever an earlier direct caller stamped (legacy paths).
        if let reason { pendingGenerateReason = reason }
        lastSeedAt = Date()   // floor for the next automatic re-seed (anti-flood invariant)
        // ONE composer-input builder (shared with the variation-maze audition): the
        // real take advances the evolve cursor; the maze previewed read-only.
        let (input, frame, evolvingSeed, _, basePhase) =
            makeComposerInput(advanceEvolution: true,
                              detailSeedOverride: detailSeedOverride,
                              structureSeedOverride: structureSeedOverride)
        let composition = BioComposer.compose(input)
        // Honor the user's concert pitch + live timbre on the next notes.
        synth.setTuning(a4Hz: session.a4Hz)
        subBass.setTuning(a4Hz: session.a4Hz)
        laneVoiceRack.setTuning(a4Hz: session.a4Hz)   // S2-W2-5: lane subs in tune too
        touchSynth?.setTuning(a4Hz: session.a4Hz)
        bioVoice.setTuning(a4Hz: session.a4Hz)        // the global bio voice tunes too
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
        // Per-genre MIX GLUE: nudge relative role levels so each genre sits right
        // (lead forward in synth genres, bass firmer in dub/heavy, pad back in
        // dense takes). Velocity scales each voice's amplitude, so this is a pure,
        // audio-thread-safe level move at the one point all notes exist as an array.
        let mix = style.mixLevels
        // Turn one raw composed bar into final notes: the per-genre mix glue.
        func finish(_ raw: [Note]) -> [Note] {
            return raw.map { n in
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
        // Per-lane composition Slice A (founder 2026-07-17 "Genre, Sound, Mix, FX,
        // Mood, Synth kommt alles in ein Instrument"): AFTER the primary take, fan
        // out to every override-carrying SECONDARY MIDI lane with the SAME input
        // (pre bar-loop mutations — shared skeleton = cohesion). Writes are gated
        // to composer-OWNED clips only; no overrides anywhere ⇒ this composes
        // nothing and today's take stays bit-identical. Every re-seed path funnels
        // through generate(), so evolve ticks refresh the lane takes too.
        applyLaneOverrides(input: input)
        // FOUNDER v287/v288 "Es wird kein midi Clip erzeugt": make the generated take a
        // VISIBLE, editable MIDI clip on the PRIMARY roll lane's timeline. Purely
        // ADDITIVE — the live-loop path above (pattern.play + pianoRoll.loadArrangement)
        // is untouched and still drives the sound; this only MIRRORS the same finished
        // bars into a composer-OWNED clip+region so a tile shows on the Arrange
        // timeline, the clip is editable, and every Evolve keeps rewriting it (ownership
        // = composerOwned, so a re-seed may fortschreiben the take but never a user clip).
        // `startTransport` is the user's OWN Generate — only that creates the clip once;
        // background evolve re-seeds only feed the existing one (no duplicate, no undo spam).
        syncPrimaryRollClip(bars: bars, createIfNeeded: startTransport)
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
            beatPlayer.pattern.play(cause: .generate)
            metronome.resync()   // align the click's downbeat to the start
        }
        // SILENCE DIAG (founder "alles ist still", 2026-07-14): the melody only sounds
        // when the roll-slot lane is audible — pianoRoll.mixGain mirrors the first MIDI
        // lane's mute/solo/level (Timeline.rollSlotGain). mixGain≈0 ⇒ every noteOn is
        // gated off (PianoRollView:529 `laneAudible`) → total silence even though notes
        // generate + the transport plays. Logging it makes the cause pastable.
        EchoelCrashLog.breadcrumb("generate[\(pendingGenerateReason)]: \(composition.notes.count) notes, playing=\(beatPlayer.pattern.isPlaying), rollMixGain=\(String(format: "%.2f", pianoRoll.mixGain))")
    }

    /// Per-lane composition fan-out (Slice A): compose each override-carrying
    /// SECONDARY MIDI lane in its own genre/mood/variation against the SAME body
    /// input as the primary take (LaneComposerInput pins the shared skeleton →
    /// same piece, different voice), then write each result ONLY into a
    /// composer-OWNED clip that lane places inside the active loop window.
    ///
    /// OWNERSHIP LAW (Council-Skeptic): `ClipStore.updateComposerMelody` refuses
    /// any clip with `composerOwned == false`, so a user-captured/imported clip
    /// can never be clobbered by an automatic re-seed. A lane with an override
    /// but no composer-owned region simply stays as-is — CREATING the
    /// composer-owned clip+region is the track panel's explicit act (Slice A2);
    /// generate() never invents regions (and never touches the region undo
    /// history). @MainActor generate-time only — never the audio thread.
    private func applyLaneOverrides(input: BioComposer.Input) {
        let doc = timelineStore.document
        let rollLaneID = doc.lanes.first(where: { $0.kind == .midi && !$0.isBio })?.id
        let overrides = LaneComposerInput.composeLaneOverrides(base: input,
                                                               lanes: doc.lanes,
                                                               rollLane: rollLaneID)
        guard !overrides.isEmpty else { return }
        // The generative instrument cycles bars 0..<loopBars — the active window.
        let windowTicks = max(1, loopBars.rawValue) * TimelineTime.ticksPerBar
        for (laneID, notes) in overrides {
            // Same mix glue the primary take's finish() applies, but with THIS
            // lane's genre (its override) so its roles balance like that style.
            let genre = doc.lanes.first(where: { $0.id == laneID })?.genreOverride ?? style
            let mix = genre.mixLevels
            let glued = notes.map { n -> Note in
                var m = n
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
            var wrote = false
            for region in doc.regions(in: laneID) where region.startTick < windowTicks {
                // Ownership guard lives in the store — a user clip returns false.
                if clipStore.updateComposerMelody(id: region.clipID, notes: glued) {
                    wrote = true
                }
            }
            if wrote {
                log.log(.info, category: .audio,
                        "Lane override take: \(glued.count) notes → lane \(laneID.uuidString.prefix(8)) (\(genre.rawValue))")
            }
        }
    }

    /// Founder v287/v288 "Es wird kein midi Clip erzeugt": mirror the just-composed
    /// loop into the PRIMARY roll lane's composer-OWNED clip, so the generated take
    /// shows as a visible + editable MIDI clip on the Arrange timeline. The primary
    /// roll lane = the FIRST non-bio MIDI lane (same ownership rule as
    /// `TimelineDocument.rollSlotGain` / `rollLaneID`).
    ///
    /// OWNERSHIP DECISION (Council-Skeptic): `composerOwned == true`. Generate CREATES
    /// the clip and the user may edit it (the H11 clip editor writes via
    /// `updateMelody`, which is ownership-agnostic), but every Evolve is allowed to
    /// FORTSCHREIBEN it — exactly the founder's model "Generate erzeugt, Evolve
    /// entwickelt weiter". A user-captured/imported clip on the lane stays untouched:
    /// `updateComposerMelody` refuses any non-composer clip (the never-clobber law).
    ///
    /// - `createIfNeeded` (the user's OWN Generate, `startTransport == true`) lazily
    ///   creates the clip+region ONCE via `ensureComposerRegion` (idempotent — repeat
    ///   Generates add nothing, no undo spam). A full 8-slot grid ⇒ honest VISIBLE
    ///   flag; the live sound is unaffected.
    /// - Background evolve re-seeds (`false`) only FEED the existing clip, so the
    ///   visible tile always carries the latest take.
    ///
    /// Additive to the silence-critical generate path — never starts/stops the
    /// transport, never touches the audio thread. @MainActor generate-time only.
    private func syncPrimaryRollClip(bars: [[Note]], createIfNeeded: Bool) {
        guard let laneID = timelineStore.document.lanes
                .first(where: { $0.kind == .midi && !$0.isBio })?.id else { return }
        if createIfNeeded {
            // true when a composer region already exists (idempotent) OR was created;
            // false ONLY on a full grid — the one honest, visible failure.
            composerClipGridFull = !timelineStore.ensureComposerRegion(
                for: laneID, clipStore: clipStore, loopBars: max(1, loopBars.rawValue))
        }
        // Flatten the loop's per-bar (bar-relative) notes into clip-absolute ticks so
        // RegionNoteWindow.barSlices reproduces exactly these bars on region playback.
        let flat = MelodyClip.flatten(loopBars: bars)
        let windowTicks = max(1, loopBars.rawValue) * TimelineTime.ticksPerBar
        for region in timelineStore.document.regions(in: laneID)
        where region.startTick < windowTicks {
            // Ownership guard lives in the store — a user clip returns false, untouched.
            _ = clipStore.updateComposerMelody(id: region.clipID, notes: flat)
        }
    }

    // MARK: - Variation maze (#19)

    /// Explore N deterministic variations of the CURRENT groove and store the ranked
    /// board (read-only — `advanceEvolution: false` doesn't perturb the evolve cursor).
    /// The base is captured so a later apply replays the exact skeleton it scored.
    private func exploreVariations() {
        let base = makeComposerInput(advanceEvolution: false).input
        mazeBase = base
        mazeAppliedSeed = nil
        mazeBoard = BioVariationMaze.explore(base: base, count: 6)
        log.log(.info, category: .ui, "Variation maze: \(mazeBoard?.candidates.count ?? 0) ideas, target \(mazeBoard?.targetDensity ?? 0)")
    }

    /// Play the chosen idea now: its detail + structure seed are forced into the real
    /// take, so what plays IS what was auditioned (the live body still colours
    /// tempo/dynamics). Highlights the applied candidate in the board.
    private func applyVariation(_ candidate: BioVariationMaze.Candidate) {
        guard let base = mazeBase else { return }
        let skeleton = base.structureSeed ?? base.seed
        mazeAppliedSeed = candidate.seed
        generate(startTransport: true,
                 detailSeedOverride: candidate.seed,
                 structureSeedOverride: skeleton,
                 reason: "variation")
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
        // Level is pushed here too, not only from the field's onChange: a persisted value
        // must survive relaunch. This is the same "restore what was saved" step the Mix
        // faders needed, and its absence is what made the Bass fader spring back to unity
        // on every launch until 2026-07-27.
        touchSynth.setGain(Float(touchLevel))
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
    /// Master panel (Streaming −14 / Podcast −16 / Broadcast −23 / Cinema −24), or nil
    /// for "No target", which now really means NO normalisation.
    ///
    /// The old note here said "No target keeps the established −14 default so existing
    /// behaviour is unchanged", which described the bug rather than a decision: the
    /// picker offered "No target" and the export then did exactly what "Streaming (−14)"
    /// does. The resolution moved into `LoudnessTarget.resolvedLUFS(rawValue:)` so
    /// the two nils it used to conflate — user chose off vs. setting unreadable — are
    /// separable and unit-tested.
    ///
    /// This changes nothing for anyone who did not explicitly pick "No target": the
    /// canonical fresh-install default is `.streaming` (`StudioDefaultKeys` — nothing calls
    /// `UserDefaults.register(defaults:)`, so the `??` fallback does the work), and an unreadable
    /// value still falls back to it.
    private var resolvedLUFS: Float? {
        LoudnessTarget.resolvedLUFS(rawValue: loudnessTargetRaw)
    }

    private func exportWav() async {
        if let url = await exporter.exportWav(engine: audioEngine, beatPlayer: beatPlayer,
                                              bars: loopBars.rawValue, targetLUFS: resolvedLUFS) {
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
                                                     bars: loopBars.rawValue, targetLUFS: resolvedLUFS) {
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
        // MELODY ONLY — `steps`/`accents` are deliberately empty, because nothing renders
        // that grid since the drums were deleted (#166/#167): it is a bar clock now, not a
        // beat. Exporting it would hand a DAW a drum track the user never heard in the app —
        // the lying-control class, and the opposite of "keine Drums".
        //
        // ⛔ CORRECTED (reviewer): the first version of this comment justified the change
        // with "the composer still fills `pattern.steps`". It does NOT — `generate()` calls
        // `BioComposer.silentBeat()`, which returns two all-false grids (the beat was cut
        // 2026-07-07, "Schmeiß den Beat komplett raus"). On the GENERATED path the old code
        // already produced zero drum events, so for a fresh take this change is byte-identical.
        // The path where it actually bites is `open(_:)`: it restores `p.drumSteps` /
        // `p.drumAccents` into the pattern, so a project SAVED BEFORE the drum removal puts a
        // real groove back into that grid — inaudible in the app, and the old code would have
        // written it into the .mid. That legacy-project case is the whole reason for the
        // change, and it is the one a future session must not "simplify" away.
        // `exportCombined` (not the Type-0 melody `export`) is still the right engine: it is
        // what writes tempo + 4/4 + KEY SIGNATURE and anchors End-of-Track to bars × 4
        // quarters, which is the whole point of "in der DAW weiterarbeiten". It emits an
        // empty, named Drums track — inert in any DAW, and honest, because it is empty.
        guard !arrangedNotes.isEmpty else {
            // The button is enabled on `hasComposed`, which can be true with an empty roll
            // (open a project whose notes did not survive, then tap). Silent return = a
            // control that looks like it worked. No alert — the sheet chain may not grow —
            // but the diag log must be able to say what happened.
            EchoelCrashLog.breadcrumb("MIDI export skipped: no notes in the roll")
            return
        }
        let data = MIDIFileExporter.exportCombined(
            notes: arrangedNotes, steps: [], accents: [],
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
            bpm: beatPlayer.pattern.tempo, modeRaw: ComposerMode(locked: lockBPM).rawValue,
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
        // Same clamp as launch: a project saved before the genre re-curation (#125) can
        // carry a style that is no longer offered, which would leave the picker showing
        // nothing selected while that genre composed every take. Bound ONCE and reused
        // below — the FX room must be built from the same genre the picker and the
        // composer use, or opening such a project produces a split that exists nowhere
        // else. (Unlike launch this does not rewrite the stored project; only an
        // explicit save does.)
        let openStyle = MusicStyle.offered.contains(p.style) ? p.style : StudioDefaultKeys.genre.value
        style = openStyle
        rootIndex = p.keyRoot
        scale = p.scale
        fxCharacter = p.fxCharacter
        // Fallback matches the founder's 8-bar default (H15-LOOPBARS review LOW:
        // this was the last .four literal — an invalid saved rawValue would have
        // silently written 4 into the shared key).
        loopBars = LoopBarLength(rawValue: p.loopBars) ?? .eight
        currentPatch = p.patch          // every control reads this, so the UI matches
        presetIndex = -1                // a saved patch is "custom", not a factory preset
        session.adopt(key: p.key)
        session.a4Hz = p.a4Hz
        synth.setTuning(a4Hz: p.a4Hz)
        subBass.setTuning(a4Hz: p.a4Hz)
        laneVoiceRack.setTuning(a4Hz: p.a4Hz)   // S2-W2-5: lane subs in tune too
        touchSynth?.setTuning(a4Hz: p.a4Hz)
        bioVoice.setTuning(a4Hz: p.a4Hz)        // the global bio voice tunes too
        synth.apply(p.patch)
        syncTouchSound()
        fxCharacter.apply(to: synth.fxChain, bpm: p.bpm, genre: openStyle)
        if let touchSynth { fxCharacter.apply(to: touchSynth.fxChain, bpm: p.bpm, genre: openStyle) }   // same room for played notes
        pianoRoll.load(p.notes)
        beatPlayer.pattern.load(steps: p.drumSteps, accents: p.drumAccents)
        beatPlayer.pattern.setTempo(p.bpm)
        // Everything that mirrors tempo must follow a loaded take, or the visual/OSC
        // frame keeps the OLD project's BPM (Finding F). Route through the authoritative
        // clock value (clamped) so all readers show one number. The click is NOT pushed
        // here — it subscribes to the transport and has already followed the setTempo above.
        let loadedTempo = beatPlayer.pattern.tempo
        pianoRoll.musicalTempoBPM = loadedTempo
        lockedBPM = loadedTempo
        hasComposed = true
        // Re-push the microtonal retune for the restored root. Programmatic writes
        // of rootIndex never post .echoelCompositionEdited (step 2b — by design, so
        // this very function can't be clobbered by strip side effects), so do it
        // explicitly — otherwise a non-12-TET system would play against the
        // previous root.
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
        // GM channel-10 hits still land on the 8×16 grid — but THERE IS NO KIT any more
        // (#167): the grid is a bar/step CLOCK, nothing turns a step into sound. This
        // block is inert, kept only because `PatternEngine` still carries the step data;
        // it does not import "drums" in any audible sense. (`importMIDI` itself has no
        // caller either — `midiImportPresented` has no setter.)
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

/// Lays its cards in ONE column in portrait and TWO in landscape / on iPad, so the
/// wide layouts don't waste horizontal space (founder: "passendes adaptives Design
/// für horizontal und Vertikal"). A LEAF that reads the size classes in its OWN body
/// — size-class changes are rare (rotation / resize), never per-frame, and confining
/// the read here keeps it off the churny root body (freeze rule). The rule came from
/// `ChannelRackView.rackColumns` (v170), which mixed the drum channels; that view is
/// deleted (#167) and this is now the only place the rule lives.
/// Layout-only: identical content, just columns.
@MainActor
private struct AdaptiveCardGrid<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    @ViewBuilder let content: () -> Content

    private var columns: Int { (hSize == .regular || vSize == .compact) ? 2 : 1 }

    var body: some View {
        if columns > 1 {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
                                     count: columns), spacing: 10) {
                content()
            }
        } else {
            VStack(spacing: 10) { content() }
        }
    }
}

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

// (Step 2c: SessionNamePreviewLeaf moved verbatim into WorkspaceView.swift —
//  it now rides at the end of the header CompositionHeaderStrip, still its own
//  leaf so the body-following BPM churns only that label, never the chrome.)

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
/// piano roll as a MusicalFrame) mapped through SpectralColor — the PHYSICAL colour
/// (octave transposition → CIE 1931), amplitude-weighted and mixed in OKLab. The hue
/// is no longer OKLab-synthesized; it comes from the wavelength. Proves the promise —
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
                Text(sounding ? "Live chord, mapped by pitch" : "Plays when the music is sounding")
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
        let rgb = SpectralColor.physicalColor(forChord: frame.notes.map { (hz: $0.frequencyHz, amplitude: $0.amplitude) })
        return Color(.sRGBLinear, red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

// MARK: - Apple Health write opt-in (leaf)

/// The reachable off-switch for writing bio samples to Apple Health.
///
/// A LEAF `View`: it owns the `HealthKitWriter` read itself, so `bioPanel` — which is the
/// one panel evaluated directly in `EchoelStudioView.body` rather than through
/// `EchoelPanel`'s deferred builder — never registers the root body as an observer of the
/// writer. Cheap here (the flag changes only on a tap), but the front plate is permanent
/// now, so the leaf discipline is the rule rather than a judgement call.
///
/// Why this exists at all: `HealthKitWriter.enabled` persists to `health.write.enabled`
/// and `start(reading:)` is called unconditionally at launch, while the switch that used to
/// set it lived in the Tools grid — unmounted since 2026-07-02, deleted 2026-07-26. Anyone
/// who turned it on in an older build kept writing heart-rate and respiratory samples with
/// no way to revoke it inside the app. Restoring the switch is the fix; removing the
/// persisted flag instead would silently discard a consent the user did give.
///
/// Copy stays factual — this writes measurements, it does not diagnose anything.
#if canImport(HealthKit)
private struct HealthWriteOptInRow: View {
    @Environment(HealthKitWriter.self) private var healthWriter

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { healthWriter.enabled },
                                 set: { healthWriter.enabled = $0 })) {
                Text("Save to Apple Health")
                    .font(EchoelTheme.font(12, .semibold))
                    .foregroundStyle(EchoelTheme.text)
            }
            .toggleStyle(.switch)
            .tint(EchoelTheme.accent)
            .frame(minHeight: 44)
            .accessibilityHint("Writes measured heart rate and breathing rate to Apple Health")
            Text(healthWriter.enabled && !healthWriter.isAuthorized
                 ? "Waiting for permission in Health."
                 : "Off by default. Heart and breathing measurements only.")
                .font(EchoelTheme.font(10))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif

#endif
