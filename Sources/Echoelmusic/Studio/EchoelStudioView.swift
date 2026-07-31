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
// The play triangle begins the biofeedback (camera pulse, or the demo
// source where no camera exists). ⛔ It was a full-width button labelled "Start — Create
// from Within" until #307; the founder replaced it with an Ableton-style transport
// ("einfaches Menü mit Playbutton etc wie bei Ableton reicht"). The phrase survives as
// the BRAND tagline — on the website, the app icon and the bio-voice description — and
// none of those are the button. From the live HRV / heart / breath an individual,
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
    @AppStorage(StudioDefaultKeys.touchPatchID.key)
    private var touchPatchID = StudioDefaultKeys.touchPatchID.value
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
    @AppStorage(StudioDefaultKeys.touchSyncStrength.key)
    private var touchSyncStrength = StudioDefaultKeys.touchSyncStrength.value
    // Explicit type annotation on the enum-backed key, matching every other enum
    // `@AppStorage` in this file — `@AppStorage` has overloads for Bool/Int/Double/
    // String/URL/Data as well as RawRepresentable, and spelling the type out is what
    // keeps the resolution unambiguous instead of merely inferable.
    @AppStorage(StudioDefaultKeys.touchSyncGrid.key)
    private var touchSyncGrid: TouchQuantizer.Grid = StudioDefaultKeys.touchSyncGrid.value
    // SELF-PLAY (#224). Stored as the motion's RAW STRING rather than the enum, because "off"
    // is not a case of `FieldAutoPlay.Motion` — the generator's own vocabulary has no word for
    // not running, and inventing a `.off` case would put a non-motion into a type whose whole
    // job is to describe movement. `""` is the off state; `FloatingVisualWindow` turns an
    // unrecognised value into "off" the same way.
    @AppStorage(StudioDefaultKeys.fieldAutoPlayMotion.key)
    private var fieldMotionRaw = StudioDefaultKeys.fieldAutoPlayMotion.value
    @AppStorage(StudioDefaultKeys.fieldAutoPlayDensity.key)
    private var fieldDensity = StudioDefaultKeys.fieldAutoPlayDensity.value
    @AppStorage(StudioDefaultKeys.fieldAutoPlaySpan.key)
    private var fieldSpan = StudioDefaultKeys.fieldAutoPlaySpan.value
    @AppStorage(StudioDefaultKeys.fieldAutoPlayCentre.key)
    private var fieldCentre = StudioDefaultKeys.fieldAutoPlayCentre.value
    @AppStorage(StudioDefaultKeys.fieldAutoPlayBand.key)
    private var fieldBand = StudioDefaultKeys.fieldAutoPlayBand.value
    @AppStorage(StudioDefaultKeys.fieldAutoPlayBandDrift.key)
    private var fieldBandDrift = StudioDefaultKeys.fieldAutoPlayBandDrift.value
    @AppStorage(StudioDefaultKeys.fieldAutoPlayVoices.key)
    private var fieldVoices = StudioDefaultKeys.fieldAutoPlayVoices.value
    @AppStorage(StudioDefaultKeys.fieldAutoPlayPeriod.key)
    private var fieldPeriod = StudioDefaultKeys.fieldAutoPlayPeriod.value
    // #253 A3 — the composed BASS's rhythm character. A raw String and not the enum, because ""
    // (= the genre's own rhythm) is a real state the enum has no case for; see the key's doc.
    @AppStorage(StudioDefaultKeys.bassRhythm.key)
    private var bassRhythmRaw = StudioDefaultKeys.bassRhythm.value
    @AppStorage(StudioDefaultKeys.padRhythm.key)
    private var padRhythmRaw = StudioDefaultKeys.padRhythm.value
    @AppStorage(StudioDefaultKeys.fieldArpRhythmCharacter.key)
    private var fieldArpCharacter: RoleRhythm.Character = StudioDefaultKeys.fieldArpRhythmCharacter.value
    @AppStorage(StudioDefaultKeys.fieldArpRhythmGate.key)
    private var fieldArpGate = StudioDefaultKeys.fieldArpRhythmGate.value
    @AppStorage(StudioDefaultKeys.fieldArpRhythmAccent.key)
    private var fieldArpAccent = StudioDefaultKeys.fieldArpRhythmAccent.value
    @AppStorage(StudioDefaultKeys.fieldArpRhythmEvolve.key)
    private var fieldArpEvolve = StudioDefaultKeys.fieldArpRhythmEvolve.value
    @AppStorage(StudioDefaultKeys.fieldArpRhythmPush.key)
    private var fieldArpPush = StudioDefaultKeys.fieldArpRhythmPush.value
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
    /// Immersive visual mode: the spectrum→visible donut renderer vs the Metal field.
    /// **Default is now `false` and there is no reachable control that turns it on** (#227) —
    /// see `StudioDefaultKeys.visualSpectralDonuts` for why, and `normaliseUnreachableDonutMode()`
    /// below for the one line that has to go when the donut renderer gets a door again.
    @AppStorage(StudioDefaultKeys.visualSpectralDonuts.key)
    private var spectralDonuts = StudioDefaultKeys.visualSpectralDonuts.value
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
    ///
    /// ⛔ DERIVED FROM `LookBlendMap.defaultSequence`, NOT A LITERAL. Both this and
    /// `FloatingVisualWindow`'s copy read `"3,5,7"` until #227's review: three independent
    /// declarations of one default, none coupled, exactly the per-declaration-default bug this
    /// repo built `StudioDefaultKeys` to end. It matters more since #227 — the launch look-snap
    /// below is no longer skipped on a fresh install, so a drift between the shipped default look
    /// and this sequence now silently rewrites the look before the player ever sees it.
    @AppStorage(LookBlendMap.storageKey)
    private var sliderLooksRaw = LookBlendMap.string(from: LookBlendMap.defaultSequence)
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
    /// #320 — the patch as it was immediately before the last prompt application, so a
    /// shaping can be taken back in one tap. Nil = nothing to undo.
    ///
    /// ⚠️ THE TYPED TEXT IS DELIBERATELY *NOT* HERE. It lives in `SoundPromptRow`'s own
    /// `@State`, because state on THIS view re-evaluates a ~500-line body on every keystroke.
    /// This one is safe at root level for the opposite reason: it changes only when a prompt is
    /// applied or undone — a tap, not a character.
    @State private var patchBeforePrompt: SynthPatch?
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
    /// Debounce handle for a mixer re-balance (see scheduleRebalance).
    @State private var rebalanceTask: Task<Void, Never>?
    /// The current take EXACTLY as the composer produced it — before the genre mix glue
    /// and before the user's faders — TOGETHER WITH the genre it was composed in. Kept so
    /// moving a fader can re-bake THIS take (#174) instead of composing a different one.
    /// nil until the first generate().
    ///
    /// The genre travels WITH the bars rather than being read from `style` at re-bake
    /// time, and that pairing is load-bearing, not tidiness: `scheduleGenerate`'s window
    /// runs up to ~2 s while `scheduleRebalance`'s is 120 ms, so a fader touched just
    /// after a genre change would otherwise glue the OLD genre's notes with the NEW
    /// genre's `mixLevels` — and a Stop landing in that window persists the mismatch into
    /// the composer-owned clips, i.e. into the MIDI export. Same shape as `lastLaneRaw`,
    /// which already carried its genre for the same reason.
    @State private var lastRawTake: (genre: MusicStyle, bars: [[Note]])?
    /// The same, per override-carrying secondary lane, with the genre each lane composes
    /// in. Cleared whenever a generate finds no overrides, so a lane whose override the
    /// user removed cannot be re-written from a stale take.
    @State private var lastLaneRaw: [UUID: (genre: MusicStyle, notes: [Note])] = [:]
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
    // chain is 14 modifiers (8 sheet + 2 fullScreenCover + 3 alert + 1 fileImporter), the
    // count CLAUDE.md carries. ⛔ This said "15, not 16" and was stale by one after the
    // sample-browser sheet went with #167 — on the ONE number that governs the black-screen
    // law, where believing in headroom that does not exist is how the SIGSEGV comes back.
    // `PianoRollModel` is NOT part of that removal; it
    // is the note engine behind every generated take. AudioClip / AUv3 /
    // Broadcast are deliberately NOT coming back (docs/dev/PRODUCT_DEFINITION.md CUT
    // column names all three); the automation editors are gone because Slice 4d
    // (36a8468) deleted them as unreachable, which that doc does not itself discuss.
    // The patch editor the product definition KEEPS is `soundPanel` (Sound chip) —
    // that panel IS the live timbre editor, so it needs no sheet.
    // ⚠️ THE CAVEAT BELOW IS NOW DISCHARGED FOR EVERY PERSISTED PARAMETER — and read the ⛔
    // block under it before trusting that sentence, because it is the SECOND time this note has
    // said something like it. #281 ported `unisonVoices` / `unisonDetuneCents` ("Unison"), #286
    // ported `spectralShape` / `noiseColor` (Tone) and now `outputLevel` ("Level"). The
    // difference from the first attempt is checkable rather than rhetorical: each of the five
    // has a RENDERED row in `soundPanel` plus a CISmoke guard pinning it there
    // (`UnisonRowDefaultsTests`), and each guard was written by grepping for the ROW, not for
    // the field.
    //
    // ⛔ AND THE FIRST VERSION OF THIS NOTE DECLARED THE WHOLE CAVEAT DISCHARGED, on the claim
    // that `outputLevel` "never had a row at ALL — `PatchEditorView` declares an
    // `outputLevelBinding` and no view ever uses it". BOTH HALVES ARE FALSE, and the mistake
    // was mine: there is no symbol `outputLevelBinding` anywhere (it is `levelBinding`), and a
    // rendered `section("Level")` row uses it. I grepped for the FIELD, saw a binding, and
    // never looked for the row. Left standing, that sentence would have licensed exactly the
    // deletion this caveat exists to prevent — the caveat destroyed by the commit that claimed
    // to satisfy it.
    //
    // `spectralShape` and `noiseColor` followed in #286 — Shape / Noise colour pickers in the
    // Tone group above, canonicalising through the enum (see `spectralShapeBinding`).
    //
    // `outputLevel` followed too — an "Output" row under a "Level" header, next to Sub/Bass
    // (see `outputLevelBinding`). ⛔ WHAT STOOD HERE — "`outputLevel` is deliberately NOT
    // ported: a manual output trim sits against `loudnessNormalized()`'s auto-calibration …
    // adding one is a founder decision" — WAS WRONG ON ITS FACTS, not merely overtaken.
    // `loudnessNormalized()` runs exactly once, building the `static let factory` roster; it
    // cannot overwrite a trim a user made, so the two never meet. And `SynthPatch.outputLevel`'s
    // own doc had said "users can trim it in the editor" since the field shipped, quoting the
    // founder ask ("Level pro Instrument") that created it. The port restores a door that was
    // lost with `PatchEditorView`; it does not invent a control.
    //
    // ✅ `PatchEditorView.swift` IS DELETED (#132 Slice 6). The last thing it held alone was
    // its preview keyboard, and that was a judgement call rather than a grep result: the play
    // surface covers auditioning a sound, so the keyboard was not ported. Recorded here as a
    // call MADE, so the next reader does not re-open it as an unknown.
    // Its OTHER half — the preset bar (load · favourite · save · save-as · delete · submit) —
    // is NOT missing from `soundPanel`: `presetRow` holds all six today. (⛔ This note first
    // said "has held all six the whole time". Unverifiable here — the working clone is SHALLOW,
    // grafted at 24e9420, so `git log -S` on those call sites returns only the graft commit.
    // The checkable claim is the present-tense one; that history is not in the repo.) Nothing
    // pinned it until now, so `SoundPanelPresetBarTests` does: those six are why the deletion
    // cost nothing, and there is no duplicate left to fall back on if one is dropped.
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
        // ⚠️ `field` was `synth` until 2026-07-29. Safe to rename ONLY because the raw value
        // is not persisted anywhere: `activeMenu` is `@State`, the raw value serves as
        // `Identifiable.id` and nothing else, and the chrome-door string dispatch in
        // `onAppear` never named "synth". Independently re-verified afterwards: no
        // `@SceneStorage`, no `NSUserActivity`, no `onOpenURL`, no widget payload and no
        // Codable anywhere references `StudioMenu`. The `touch.*` AppStorage keys behind this
        // panel are a different matter and are deliberately NOT renamed — those DO persist,
        // and renaming them would silently discard every setting already dialled in.
        //
        // (No line numbers in this comment on purpose: the commit that first wrote it cited
        // three, and shifted the file by +6 in the same diff. CLAUDE.md bans the pattern for
        // exactly that reason.)
        case bio, composition, session, sound, mix, effects, master, mood, export, field, video
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
            // #272 — "Export" alone hid Save/Open/Record, which live in the SAME panel.
            // "Save" leads because that is the word the founder searched for and did not
            // find; the chip is 12 pt, so the export half is carried by the panel title
            // ("Save & Export") and by `fullName` above rather than crammed in here.
            //
            // ⛔ A BARE "Save" WAS WRONG AND THE REVIEWER CAUGHT IT: three sibling alerts read
            // "Save project", "Save mood" and "Save sound", two of them reached from the Mood
            // and Sound chips. A chip saying only "Save" next to those invites exactly the
            // wrong guess. "Save/Export" names both halves, and the 44 pt tap floor makes the
            // width a non-issue.
            //
            // ⛔ THE REST OF THAT NOTE IS NOW FALSE and is corrected rather than dropped. It
            // read: "The chip never appears in the standing strip (`studioChips` filters
            // `.export` out) — only appended when this panel is the one on screen — so it can
            // afford to echo the panel title." Since #290 `.export` IS in the standing strip,
            // permanently. The conclusion survives — the two-word label is still the right one
            // — but the premise it rested on is gone, and a label argument resting on "nobody
            // sees this most of the time" would have licensed shortening it back to "Save".
            case .export:      return "Save/Export"
            case .field:       return "Field"
            case .video:       return "Video"
            }
        }
        /// Full name for VoiceOver (the chip text is abbreviated).
        var fullName: String {
            switch self {
            case .bio:         return "Bio — pulse, HRV, coherence, source"
            case .composition: return "Tempo and variations — tap tempo, metronome, haptic beat, variation ideas"
            // #202/#59: the founder listed "weather, Standort" among the things he was
            // MISSING while both were built, wired and reachable — because every string
            // that advertises them said "in the name". Weather is not a naming gimmick:
            // it salts the harmonic skeleton and blends darkness/liveliness/tension into
            // the composer's mood, and hue/saturation/glow/motion into the live visual.
            // The copy now names the effect; the naming is the smaller half.
            case .session:     return "Weather and place — weather shapes the sound and the image; place names the session"
            case .sound:       return "Sound and texture"
            case .mix:         return "Mix — level per part"
            case .effects:     return "Effects"
            case .master:      return "Master"
            case .mood:        return "Mood"
            // #272: named only the export half for months, and the founder reported
            // "Session speichern und Loops aufnehmen fehlt" about controls that are IN
            // this panel. Save and Open go first because those are the two words he used.
            case .export:      return "Save, record and export — sessions, WAV loop, MIDI"
            // Was "EchoelSynth — immersive visual window", which named the wrong half and
            // collided with the patch editor behind "Sound". This panel governs ONE thing
            // from two sides: the field's look, and the field's voice under your fingers.
            // Nobody could guess from the old string that the picture is playable.
            case .field:       return "Field — the visual surface you play with your fingers"
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
    /// #228 — the six individual visual parameters, folded away under the ONE Energy
    /// control. `@State`, not `@AppStorage`, on purpose: this is a "show me the detail
    /// right now" gesture, not a setting, and a persisted expansion would quietly undo
    /// the simplification for anyone who ever opened it once.
    @State private var showVisualFineTune = false
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
            // H1 (founder 2026-07-24: "nur das alte Interface mit create from within"):
            // the signature generate control — tap it and the body composes and plays.
            //
            // ⬆ MOVED TO THE TOP, ABOVE THE CHIP BAR (#288, founder 2026-07-31, red line drawn
            // between the Genre/Key/Scale strip and the Sound·Mix·FX·Mood·Field chips).
            //
            // ⛔ THIS OVERRIDES #157's REASONING, and that reasoning is left standing below in
            // its own words rather than deleted, because it was not wrong — it was outvoted.
            // #157 moved this button from BETWEEN the chips and the plate to BELOW the plate,
            // for two stated reasons: a full-width primary button wedged between the chips and
            // the panel they switch "cut that object in half", and the bottom is thumb reach on
            // a one-handed phone. The first reason does not apply to the new position: ABOVE
            // the chips the button is not between them and their panel, so the chip-bar +
            // panel object stays whole. The second reason DOES still apply and is the real
            // cost of this move — the primary action is now at the far end of the reach arc.
            // The founder drew the line anyway; that is their call to make about their own
            // instrument, and it is recorded here so nobody "restores" it as a bug fix.
            //
            // A plain Button: NO new .sheet (metadata/black-screen law — the modal chain is
            // untouched), and it reads only `running` (discrete @State) — NOT a live 10 Hz bio
            // observable, so the menu-freeze law holds. AnyView keeps its generics out of the
            // root body type, same discipline as menuBar. Reordering siblings does not change
            // the root VStack's child COUNT, so the aggregate generic type is the same size as
            // before — this is a move, not a fifth child.
            AnyView(startControlRow
                .padding(.horizontal, 16)
                .padding(.top, FloatingVisualLayout.startButtonTopPadding)
                .padding(.bottom, FloatingVisualLayout.startButtonBottomPadding))
            AnyView(menuBar
                // (The `.echoelToggleBio` receiver that stood here is gone with #234 — the
                // header pill and the transport ▶ no longer start the session, so nothing
                // posted it. `toggleBiofeedback()` is now reached only from the front
                // plate's own "Create from Within" button and from the Siri/Shortcuts
                // inbox, both of which call it directly.)
                // Header pill long-press → pick the bio input source (camera · BLE · sim).
                .onReceive(NotificationCenter.default.publisher(for: .echoelSelectBioSource)) { note in
                    selectBioSource(note.object as? String)
                }
                // Chrome doors: the header monitors and the "•••" overflow reach the plate
                // without touching studio state directly.
                //
                // ⛔ FOUR CASES WERE DELETED HERE, NOT LEFT "just in case" (#290): "master",
                // "export", "tempo" and "session". Those four panels are chips now, and a chip
                // sets `activeMenu` directly — so the ONLY producers of those four strings
                // were the "•••" entries that went away in the same commit. A `case` with no
                // poster compiles silently and reads like a live hook; this file has been
                // burned by exactly that shape more than once (the `toolsSection` catalogue,
                // the `echoelToggleBio` wire). If a future chrome control needs one of them
                // back, re-add the case TOGETHER with the control, never ahead of it.
                //
                // What that removal also carried off, recorded so it is not re-derived: the
                // #272 note explaining why `showExport = true` must NOT be paired with the
                // export door. It rested on `menuPanelHost` putting
                // `.environment(\.echoelPanelForceOpen, true)` over `dropdownContent`, which
                // makes `EchoelPanel`'s `isExpanded` binding unreachable for EVERY panel in
                // this dropdown — so the panel already opens expanded and writing the key
                // would only stamp `true` into a persisted value nothing honours. That is
                // still true and still the reason the Video door below is not the precedent
                // it looks like (`showVideoLibrary` is `@State`, not `@AppStorage`).
                .onReceive(NotificationCenter.default.publisher(for: .echoelChromeDoor)) { note in
                    switch note.object as? String {
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
                    // The pulse monitor opens the Bio dropdown (B3). Since #289 that monitor
                    // sits beside "Create from Within" rather than in the header.
                    case "bio":     activeMenu = .bio
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
            // #157's own words for why the button sat here, kept verbatim because they are
            // the argument this move overrides, not a mistake it corrects:
            //   "MOVED BELOW THE PLATE (#157, founder 2026-07-27 'alles vereinfachen und
            //    schöner'). It used to sit BETWEEN the chip bar and the plate, which is what
            //    made the window read as 'a menu bar, then a button, then a form': the chips
            //    and the panel they switch are one object, and a full-width primary button
            //    wedged between them cut that object in half. Below the plate it anchors the
            //    surface instead of splitting it — and lands in thumb reach on a phone held
            //    one-handed, which is how this instrument is actually played."
            // The button is now the FIRST child (see the block above the chip bar). The
            // splitting objection is answered by the new position; the thumb-reach one is
            // not, and is the accepted cost of the founder's 2026-07-31 instruction.
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
            // …and the persisted CONCERT PITCH, which nothing applied at launch until
            // 2026-07-28. `session.a4Hz` restores from UserDefaults, but the only pushes
            // were inside `generate()`, `open(_:)` and the A4 field's own edit — so a user
            // who had saved A=432 and touched the play surface before pressing Generate
            // heard 440 (`EchoelPolyDDSP.a4Hz` defaults to 440). Silent, and exactly the
            // kind of thing only a tuning-sensitive player notices.
            applyConcertPitch(session.a4Hz)
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
            // #227: a stored `true` from before the pill was removed would leave that install with
            // hidden Blend controls, a readout saying "Donuts", and NO control able to undo it —
            // strictly worse than the lie it replaced. Cleared here, BEFORE the snap below, so the
            // snap runs for those installs too.
            normaliseUnreachableDonutMode()
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
        .onChange(of: scenePhase) { old, phase in
            if phase == .active { handlePendingIntent(); updateKeepAwake() }
            // #273 — AUTOSAVE ON THE WAY OUT. `ProjectStore.save` had THREE callers in
            // `Sources/` (the Save alert, the peer receive, and `importProject`'s own
            // `return save(p)` behind the live `.fileImporter`) — all three an explicit tap,
            // and no `scenePhase` observer touched the PROJECT store. Backgrounding or the OS
            // terminating a suspended app lost the take, and a bio-generated take is not
            // reproducible by repeating the inputs.
            //
            // ⛔ TWO CORRECTIONS TO THE FIRST VERSION OF THIS COMMENT, both found in review:
            // it said "exactly two callers" (three) and "neither observer touched a store" —
            // `EchoelmusicApp`'s `.background` branch already calls
            // `timelineStore.flushPendingSave()` for exactly this reason. That line is the
            // HOUSE PRECEDENT for a lifecycle flush, and a reader sent looking for "no
            // precedent" would never find it.
            //
            // `old == .active` is what makes this fire ONCE PER DEPARTURE. `.inactive` is also
            // the first phase on the way BACK (background → inactive → active), so keying on
            // `phase != .active` alone would write twice per round trip.
            //
            // ⚠️ `.inactive` RATHER THAN `.background` BUYS EARLINESS, NOT SAFETY — the first
            // version claimed safety ("covers a call banner or Control Centre, which never
            // reach `.background`"). Those cases return to `.active` and cannot lose a take,
            // so `.background` alone would have been just as safe. The cost is a full
            // synchronous encode of the WHOLE library plus a protected write, on the main
            // actor, at every transient interruption — the app switcher, Control Centre, a
            // call banner, Siri, a system permission alert.
            //
            // ⛔ AND THE COST WAS OVERSTATED IN THE FIRST VERSION, which added "including every
            // share sheet and file importer". Those do NOT qualify: `scenePhase` mirrors the
            // scene's activation state, and presenting a sheet, a share sheet or a document
            // picker INSIDE this scene never leaves `foregroundActive`. Left as a claim it
            // would invite the next session to "optimise" back to `.background` to remove
            // writes that were never happening. UNVERIFIED ON DEVICE either way — the
            // breadcrumb in `EchoelmusicApp`'s own scene-phase observer settles it in a minute.
            // Kept because the write is one small document and the earlier signal is the more
            // conservative one — but kept for THAT reason.
            if old == .active && phase != .active { autosaveTake() }
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
            // ⚠ THE MECHANISM WAS ORPHANED between 2026-07-26 and 2026-07-29: the piano roll's
            // door was removed ("Pianoroll soll raus"), which left `requestPlaybackOnlyStop()`
            // with no producer, so this read always returned false and `.pausePlayback` was
            // unreachable. The comment here said so and added that the ordering "becomes
            // load-bearing again the instant anything re-acquires the ability to request a
            // playback-only stop". That instant is now: the transport bar's ■ raises the
            // request (#234/#179 — `WorkspaceView.TransportBar.toggle()`).
            //
            // What made it urgent rather than tidy: while the request had no producer, the
            // chrome ■ silently ended the whole bio session, camera and all. The founder's
            // log 2475 shows it — `stop source: transport-bar ■` at 828.182 followed 14 ms
            // later by `stopEverything(transport-stopped)`. A second full Stop wearing a
            // different glyph, with a ~20 s pulse re-lock as its hidden price.
            //
            // Both orderings below stay load-bearing: reading the flag BEFORE `guard running`
            // (#161), and the transport bar raising it before `pattern.stop()`.
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
            // The ENGINE, not `currentTempo`: a Double handed over here is a snapshot taken
            // at presentation time, and the sheet then computed every sync division at that
            // frozen tempo for as long as it stayed open. `EchoelFXView` follows the clock
            // itself now, in its own leaf.
            AnyView(EchoelFXView(chain: synth.fxChain, pattern: beatPlayer.pattern,
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

    /// #289 → #307 — ONE control block, now a transport: ▶/■ · ⏸ · the analysis display.
    ///
    /// ⛔ This line read "pulse · Create from Within · playback ■" — the OLD order, naming the
    /// OLD label — while the paragraph #307 appended below it described the new one. The summary
    /// line of a doc block is what a reader trusts before scrolling, and #307 corrected the
    /// paragraphs it was thinking about and left the headline alone. Same failure as the
    /// mount-site doc in `HeaderMonitors`, one commit, two places.
    ///
    /// Founder 2026-07-31, red circle around the header pulse pill and the transport ■:
    /// *"Das was da rot markiert ist könnte ja alles in dem Create From within Button drin
    /// sein oder? Führe intelligent zusammen."* This is the third answer to the same
    /// complaint (2026-07-15 "zu viele Play Knöpfe", 2026-07-29 "3 Knöpfe zum Start", now
    /// this) and the first that puts them in one place instead of deleting one of them.
    ///
    /// ⛔ WHAT "INTELLIGENT" HAD TO MEAN HERE, because the literal reading destroys two
    /// things. Folding all three into one TAP TARGET would have:
    ///   · Deleted the bio-source door. The pill's long-press is the ONLY producer of
    ///     `.echoelSelectBioSource`, and `startBioSource` is the ONLY owner of the BLE
    ///     strap's lifecycle (CLAUDE.md states this explicitly, after a previous session
    ///     wired a second owner and killed the founder's strap mid-performance). As
    ///     decoration inside a button label, that gesture is gone and so is the strap.
    ///   · Re-opened #161. The ■ is a PLAYBACK-only stop: it drops the music and keeps the
    ///     body, because ending the session costs the camera ~20 s to re-lock and a
    ///     performer needs silence between two sections. One tap target cannot mean both
    ///     "pause the music" and "end the session" without lying at the worst moment.
    /// So: ONE ROW, one visual object, three hit areas whose meanings are unchanged. The
    /// pill and the ■ are the SAME views as before — moved, not rebuilt.
    ///
    /// ⚠️ FREEZE LAW. Neither moved control is read in this body. `PulseMonitorMiniLive`
    /// reads the ~10 Hz camera publisher inside its own body (that isolation is what fixed
    /// 10.76.50), and `PlaybackToggleButton` reads `bus.instrumentRunning` /
    /// `transport.isPlaying` inside its own. Inlining either one's state here would put a
    /// subscription on `EchoelStudioView.body` — the body that hosts every `.menu` Picker
    /// in the instrument. That is the whole reason both are `struct`s and not a few lines
    /// of `HStack` content.
    /// ⭐ #307 REORDERED IT INTO A TRANSPORT: controls left, readout right.
    ///
    /// Founder 2026-07-31: *"Create from within can also weg, einfaches Menü mit Playbutton
    /// etc wie bei Ableton reicht."* Ableton's bar reads transport-then-meters, left to right,
    /// and that ordering is the reason the row can now carry both halves of what he asked for
    /// in two consecutive messages: dropping the sentence frees ~205 pt, and the analysis
    /// display — which he wanted bigger — is the only flexible child, so it takes all of it.
    /// The pill moved from first to last for that reason and no other; its behaviour, its tap
    /// (Bio panel) and its long-press (bio source, the BLE strap's ONE owner) are untouched.
    private var startControlRow: some View {
        HStack(spacing: 8) {
            startButton
            PlaybackToggleButton()
            #if canImport(AVFoundation)
            PulseMonitorMiniLive()
            #endif
        }
    }

    /// THE ONE START, and since #307 it is a TRANSPORT GLYPH rather than a sentence.
    ///
    /// Founder 2026-07-31, immediately after the #305 row fix: *"Create from within can also
    /// weg, einfaches Menü mit Playbutton etc wie bei Ableton reicht."*
    ///
    /// ⛔ WHAT THAT OVERTURNS, stated plainly because the previous reasoning was good and is
    /// now simply outranked. #234 kept THIS control out of three candidates precisely because
    /// it was "labelled, unmissable, named after what the instrument does", and dropped the
    /// pill's tap and the transport ▶ as starts on the grounds that a GLYPH cannot say what it
    /// begins. That argument has not become wrong — it has been overruled by the person whose
    /// instrument it is, twice in one day, in favour of a transport people already know. Do not
    /// "restore" the label as a bug fix; if it comes back it comes back on a fresh founder ask.
    ///
    /// ⚠️ THE COST IS DISCOVERABILITY, AND IT IS PAID, NOT WAVED AWAY. A bare ▶ tells a
    /// first-time user nothing about biofeedback. Three things carry that weight now, and all
    /// three had to move in this same commit or the removal would leave a lie behind:
    ///   · the VoiceOver label + hint below (the only description a blind user ever gets),
    ///   · the Bio panel's opening line, which said *Press "Create from Within" to start* —
    ///     an instruction naming a button that no longer exists,
    ///   · `BioStripView`'s accessibility hint, which said the same thing.
    /// `OneStartControlTests` now fails on any line that pairs "Press" with that phrase, so the
    /// next rename cannot leave the instructions pointing at a ghost.
    ///
    /// The Ableton grammar this lands in: ▶ starts, ■ ends, and the ⏸ beside it drops only the
    /// music. Three glyphs, three distinct meanings, no two of them claiming the same thing —
    /// which is the #305 rule this row was just brought under, applied one step further.
    private var startButton: some View {
        Button { toggleBiofeedback() } label: {
            // `stop.fill` is CORRECT here and is the only place on the front plate that may
            // wear it: this control genuinely ends the session, camera included. The twin
            // guard in `OneStartControlTests` bans it from `WorkspaceView.swift`, where the
            // button beside this one only pauses.
            Image(systemName: running ? "stop.fill" : "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(running ? EchoelTheme.text : .black)
                // 64 pt wide is a CHOICE, not a fit: with the label gone there is no width
                // pressure left in this row at all, so the number is set by what a primary
                // transport target should feel like next to a 38 pt secondary — not by what
                // is left over. The freed ~205 pt goes to the analysis display, which is what
                // the founder asked for one message earlier ("etwas größere Anzeige für
                // Analyse"): `PulseMonitorMiniLive` now takes the rest of the row.
                //
                // ⛔ THE WIDTH-BUDGET PARAGRAPH THAT STOOD HERE IS DELETED, NOT UPDATED. It
                // computed how much room the sentence "Create from Within" had against the
                // pulse pill, was wrong once in the alarming direction, was corrected, and was
                // corrected AGAIN eight hours later when the pill grew. There is no sentence
                // any more, so the arithmetic has no subject — keeping a "corrected" version
                // of it would be the third edition of a calculation about something that does
                // not exist. Height still comes from `FloatingVisualLayout` (see that file's
                // control-band block) so the docked visual's lift and this control cannot
                // drift apart; that dependency is real and CI-tested.
                .frame(width: 64)
                .frame(height: FloatingVisualLayout.startButtonHeight)
                // Website CI: primary action = off-white fill, black glyph (.btn-primary).
                // Green is reserved for live bio signal, not chrome. Stop = neutral fill with
                // a border, so the running state still reads as a raised control rather than
                // dissolving into the plate.
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(running ? EchoelTheme.fill : EchoelTheme.text))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(running ? EchoelTheme.borderStrong : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        // Mandatory now that the label is gone — and deliberately NOT the same words as the
        // pause button one place over, because the difference between them (this one takes
        // the camera down with it, ~20 s to re-lock) is exactly what a VoiceOver user cannot
        // see.
        .accessibilityLabel(running ? Text("Stop") : Text("Play"))
        .accessibilityHint(running
            ? Text("Ends the session and the pulse reading. To drop only the music, use pause.")
            : Text("Starts biofeedback; your body then composes and plays the music."))
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
    // is founder-deleted from THIS BAR; the immersive visual window stays reachable via
    // the header monitor button.
    //
    // ⛔ AND THE REST OF THIS SENTENCE WENT STALE: it said the `.video` case + videoPanel
    // are "unreferenced now" and that "a later slice deletes the dead panel". Both are
    // false today — `EchoelClipsMonitorMini` (`HeaderMonitors.swift`) posts the
    // `.echoelChromeDoor` "video" notification, this file's observer sets
    // `activeMenu = .video` + `showVideoLibrary = true`, and `videoPanel` renders
    // `VideoLibraryPanelContent` with mp4 share. **The library is LIVE; do not delete it as
    // dead.** Filtering a case out of `studioChips` removes it from the BAR, never from the
    // app — that is the whole point of the chrome doors, and it is exactly the
    // "unreachable because I cannot see a caller" mistake CLAUDE.md warns about, made in
    // reverse. Following
    // slices retire mix/effects/synth/sound as each function is verified reachable per-track,
    // then the bar goes entirely (PLAN_LEISTE_DISSOLVE_2026-07-20).
    /// #290 — THE STRIP IS NOW AN EXPLICIT, ORDERED LIST, and both halves of that sentence
    /// are the change (founder 2026-07-31, red circle around the "•••" overflow: *"Lässt
    /// sich das alles intelligent unterbringen in der Reihe mit den ganzen Funktionen?
    /// Sortiere intelligent"*).
    ///
    /// ⭐ WHY THIS IS A ONE-LINE CHANGE AND NOT A REBUILD, which is the whole reason it is
    /// safe: FOUR of the six overflow entries — Master, Save/Export, Tempo, Session — were
    /// already full `StudioMenu` cases with working panels (`masterPanel`, `utilityRow`,
    /// `tempoToolsPanel`, `sessionPanel`). They were not missing from the app; they were
    /// FILTERED OUT of this array and re-doored through a menu. So no surface is created, no
    /// `.sheet` is added, and the presentation chain is untouched (black-screen law).
    ///
    /// THE ORDER IS THE SIGNAL CHAIN, then context, then what you do when the take is done:
    ///   Sound → FX → Mix → Master   (the voice, what happens to it, the balance, the sum)
    ///   Mood → Tempo                (what drives the generation: character, then time)
    ///   Field                       (the surface you play with your fingers)
    ///   Session → Save/Export       (what the world adds, then what you take away)
    /// A performer scanning left-to-right walks the audio path in the order it exists. The
    /// old order was not designed at all — it was `allCases` declaration order surviving a
    /// filter, which is exactly how a UI ends up sorted by an implementation detail. Writing
    /// the array out means a future case added to the enum does NOT silently appear in the
    /// bar at whatever position it was declared: it has to be placed here deliberately.
    ///
    /// ⛔ NOT IN THE STRIP, and each for its own reason — do not "complete" this list without
    /// reading them:
    ///   · `.bio` reaches the plate from the pulse pill, which since #289 sits directly left
    ///     of "Create from Within". A chip would be a second door to the same panel, one row
    ///     under a door the user already found.
    ///   · `.video` reaches it from the header clips tile, which also shows REC state — the
    ///     tile carries information a chip cannot.
    ///   · Live Colabo and Learn are NOT panels: they present full sheets (`showLiveColabo`,
    ///     `showLearn`). A chip that opens a modal would be a lying tab in a strip whose
    ///     grammar is "this chip selects what the plate shows", and it would put two more
    ///     entries on the presentation chain's conscience. They stay in the "•••".
    /// `visibleChips` still appends whichever of those is on screen, so the strip never shows
    /// an unselected state while a panel is open.
    private static let studioChips: [StudioMenu] =
        [.sound, .effects, .mix, .master, .mood, .composition, .field, .session, .export]

    /// The tab strip: the nine chips above, PLUS whatever the plate currently shows if a
    /// chrome door selected one of the two menus the strip does NOT carry — `.bio` (pulse
    /// pill) and `.video` (header clips tile).
    ///
    /// ⛔ THIS SENTENCE WAS STALE THE MOMENT #290 LANDED and is corrected rather than
    /// dropped: it read "the five instrument tabs … (Master · Export · Bio · Tempo ·
    /// Session · Video reach the plate through the header/transport, not through a chip)".
    /// Four of those six are chips now, two lines above — and a comment that names the
    /// strip's contents wrongly is exactly what makes the next reader "restore" a door that
    /// already exists.
    ///
    /// ⚠️ THE APPEND ALONE IS NOT ENOUGH SINCE #290, and saying so here is the point: it adds
    /// the active menu as the TENTH chip, past the right edge of an already-overflowing strip.
    /// `menuBar`'s `ScrollViewReader` (#291) is what actually brings it into view — the two are
    /// one mechanism, and removing either leaves a strip that claims to be the selector while
    /// showing no selection. Without this append, `displayedMenu` matches no chip, so all render
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

    /// ⭐ WHY THIS SCROLLS ITSELF (#291). #290 took the strip from five chips to nine, and
    /// `visibleChips` can append a tenth. Nine chips at their real widths — the labels are
    /// Atkinson Hyperlegible **Bold** (`EchoelTheme`), each in a 44 pt minimum tap frame
    /// (`chipTapTarget`), 6 pt apart, plus 20 pt of row padding — measure roughly 590 pt.
    /// A portrait iPhone is ~393 pt wide, and `EchoelStudioView` is deliberately NOT
    /// Dynamic-Type-clamped (only the chrome is, in `WorkspaceView`) and additionally scales
    /// with `StudioZoom`. So the strip OVERFLOWS, with `showsIndicators: false`.
    ///
    /// Two things broke silently at that moment, and neither shows up in a source-text guard:
    ///   1. `visibleChips`' whole stated purpose. It appends the active menu so the strip
    ///      never shows an unselected state — but it appends it LAST, i.e. off the right
    ///      edge. Opening Bio from the pulse pill selected a chip the user could not see, so
    ///      the strip still read as "nothing selected".
    ///   2. `.export` is the ninth chip. #290 and #272 both argued a permanent chip names
    ///      Save/Record more strongly than a buried "•••" entry — true only while the chip is
    ///      ON SCREEN. Behind a hidden-indicator horizontal scroll it is *less* findable than
    ///      the "•••" glyph it replaced, which is #272's own complaint one layer over.
    ///
    /// The fix is the smallest one that makes the claim true: a `ScrollViewReader` scrolls
    /// whatever is selected into view. It does NOT re-sort the strip (the order is the signal
    /// chain, a founder-facing decision) and it does NOT shorten any label.
    ///
    /// FREEZE LAW: `displayedMenu` changes on a TAP, not on a clock — this is nowhere near
    /// the ~10 Hz reads the law is about. No `@Observable` is read here.
    ///
    /// ⛔ HONEST LIMIT: the ~590 pt is computed from the constants, not measured on a device.
    /// What is certain is the direction (nine wide chips in one row on a 393 pt phone) and
    /// that scrolling the selection into view is correct whether or not it overflows today.
    private var menuBar: some View {
        ScrollViewReader { proxy in
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
        // Bring the selected chip into view — see the ⭐ note above. `.center` rather than
        // `.leading`: the selection is usually reached by tapping a NEIGHBOUR, and centring
        // keeps its neighbours visible so the strip still reads as a strip. `ForEach` over
        // `visibleChips` registers each row under its `Identifiable` **id** — so the anchor is
        // `menu.id` (the `String` raw value), NOT the menu itself.
        //
        // ⛔ THE FIRST DRAFT PASSED THE ENUM and it would have compiled and done NOTHING.
        // `StudioMenu` is a `String`-backed enum, so it is `Hashable` and `scrollTo(menu)`
        // type-checks — but `ForEach` over `Identifiable` data registers each row under
        // `element.id`, and `AnyHashable(StudioMenu.export) != AnyHashable("export")`. The
        // lookup would simply miss, forever, with no warning and no gate to catch it: a
        // silent no-op wearing the shape of a fix, which is the failure mode this file has
        // paid for repeatedly.
        //
        // ⛔ AND THE SCROLL IS DEFERRED BY ONE MAIN-ACTOR TURN, which the first version of
        // this slice was not — the reviewer caught that the ONE path the whole fix is
        // justified by is the one it would most likely miss. `visibleChips` appends `.bio`
        // and `.video` in the SAME update in which `displayedMenu` becomes them, so a
        // synchronous `scrollTo` inside `onChange` targets a row SwiftUI has not inserted
        // yet. For the nine permanent chips it worked either way; for the pulse-pill path —
        // rationale 1 above, the reason this exists — it was a coin flip. `Task { @MainActor }`
        // is the house pattern for exactly this (CLAUDE.md's async-UI rule) and is safe here
        // for the same reason the freeze law is not in play: this fires on a TAP, not on a
        // clock. Never do this per frame from a 30 fps source — that is the other law.
        .onChange(of: displayedMenu) { _, menu in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(menu.id, anchor: .center) }
            }
        }
        // ⛔ NO `.onAppear` COMPANION, and the reason is worth writing down because the first
        // draft of this slice had one with a FALSE justification ("a restored `activeMenu`
        // can already point off-screen at launch"). `activeMenu` is `@State`, not
        // `@AppStorage` — nothing restores it — so at first appearance `displayedMenu` is
        // always `.sound`, which is chip one and already at the left edge. The call would be
        // a guaranteed no-op dressed as a safety net. If `activeMenu` ever becomes persisted,
        // add it back THEN, together with that change.
        }
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
        case .field:       return AnyView(visualPanel)
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
            // No `onStartPulse` (#234): this panel used to carry a "Read pulse" button that
            // ran `startBiofeedback()` — a hidden fourth Start, two taps from the header
            // pill, behind a label promising a measurement. The one Start is the front
            // plate's own button, in this same view.
            BioStripView(measuring: running)
            // ⛔ THIS SENTENCE NAMED THE BUTTON, and #307 deleted the button. It read
            // *Press “Create from Within” to start*. With the label gone that is an
            // instruction pointing at a ghost — the worst kind of stale copy, because it
            // reads as help. The play triangle is now the referent, and `OneStartControlTests`
            // fails on any line that pairs "Press" with the old phrase so the next rename
            // cannot re-open this.
            // ⛔ It first said "Press the play triangle", which names a SHAPE — and VoiceOver
            // announces that control as the WORD "Play". A blind reader got a shape they cannot
            // see for a control whose label says something else. `BioStripView`'s sibling hint
            // had it right from the start; this now matches it.
            Text("Press Play to start — your body then drives the sound. For a BLE chest strap, touch and hold the pulse display and pick \u{201C}Play with a Bluetooth strap — scans for one\u{201D}; Apple Watch feeds in through Health.")
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
                //
                // ⛔ THE "Lead" FIELD BELOW IS INERT TODAY AND THE FOUNDER CAN SEE IT. Every curated
                // genre sets `leadDensity: 0`, so `BioComposer` composes no `.lead`-role note and
                // there is nothing for this fader to scale (`LeadRoleAbsenceTests`, blocking bundle;
                // the whole finding is in `RoleRhythm.swift`'s A5 paragraph). It is a lying control
                // by this repo's own #135/#164/#227 standard — LEFT IN DELIBERATELY, because the two
                // honest fixes are both founder calls: give a genre a lead again, or remove the
                // field. Removing it silently would also delete the only door to a PERSISTED value
                // (`MixerStore.lead` → `"mixer.lead"`), which is the #167 lesson.
                // Do not add a caption or grey it out to "explain" it either — that ships an apology
                // instead of a decision.
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
                // Same law as a single fader (#174): "reset the balance" restores the
                // genre's levels on the take you are listening to — it does not fetch a
                // different take.
                scheduleRebalance()
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
    // `laneVoiceRack.setDrumsInsert`. `BeatPlayer.setFX`, `BeatPlayer.masterLevel` and
    // `setDrumsInsert` are not symbols any more at all — #167 deleted the Channel Rack,
    // then the mixer state, then the whole drum kit (2026-07-27). Do not grep for them.
    // `trackFX.drums` still
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
                    // RE-BAKE, never recompose (#174): `recomposeIfRunning()` routes into
                    // generate(), which advances the evolve cursor — so balancing a take
                    // used to replace it with a different one.
                    scheduleRebalance()
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
        // Titled by what it DOES, not by the internal door name. "Session" also
        // collided with session SAVING — a different thing the founder asked for in
        // the same breath (#189) — so the old title actively pointed at the wrong
        // feature. Nothing structural changed: same door, same rows, same panel slot.
        panel("Weather & place", "Weather shapes sound and image · place names the session",
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
                TextField("Place, entered manually (optional)", text: $locationNamer.manualPlace)
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
                // "the music" undersold it by exactly half: the visual half is wired
                // too (hue · saturation · glow · movement, read in FloatingVisualWindow).
                Text("Weather shapes the music and the image")
                    .font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
            }
            .tint(EchoelTheme.accent)
            .accessibilityHint("One coarse weather lookup per session flavours sound and image. Each influence has its own intensity — mix it in or out. The body stays the main driver.")
            if weatherEnabled {
                // The prerequisite used to be a DEAD END: it named the other toggle and
                // left the user to hunt for it — and that toggle is labelled about
                // NAMING, so nothing about it reads as "this is what weather needs".
                // One tap instead. It stays a sentence, not a bare "Fix": turning this
                // on requests location permission, so the button has to say what it does.
                if !locationNamer.enabled {
                    Button { turnLocationOnForWeather() } label: {
                        Text("Weather needs a coarse location — turn on \"Place in session name\"")
                            .font(EchoelTheme.font(11, .medium))
                            .foregroundStyle(EchoelTheme.accent)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    // Without contentShape the hit area is the bare glyph bounds of an
                    // 11 pt wrapped Text: a tap in the line gap does nothing, and the
                    // line reads as the inert sentence it used to be — the exact
                    // perception this change exists to remove. 44 pt is the same HIG
                    // target the "•••" chip and `entryRow` already take.
                    .contentShape(Rectangle())
                    .accessibilityHint("Turns on the place toggle, asks for location permission if it has not been granted yet, and puts your city into session and export names.")
                } else if locationNamer.denied {
                    // This state existed and had no words here: with location denied the
                    // lookup can never run, and the row would have promised a sky reading
                    // at every Start forever.
                    Text("Location is off for Echoel in Settings — weather has nothing to look up.")
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.dim)
                } else {
                    Text(weatherDescriptor.isEmpty ? "Sky reading arrives at Start."
                                                   : "Now: \(weatherDescriptor)")
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.dim)
                }

                // Separate, individually-mixable influences (founder: "Klang und
                // Bild aber getrennte und mehrere Parameter" + an intensity slider
                // "damit man das Wetter rein und rausmischen kann"). Each row says
                // what it changes; 0 = off (no change), 1 = fully the weather. The two
                // groups sit side by side in landscape / on iPad.
                AdaptiveCardGrid {
                    // ⛔ These two read "Sound · Klang" and "Image · Bild" until 2026-07-29 —
                    // the English word and its German gloss, side by side, in a bundle that
                    // declares one language. A per-string bilingual gloss is not what
                    // localization is; it is what localization REPLACES.
                    weatherMixGroup("Sound", params: WeatherMood.Param.allCases.filter { $0.domain == .sound })
                    weatherMixGroup("Image", params: WeatherMood.Param.allCases.filter { $0.domain == .visual })
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

    /// Grants the coarse location the weather lookup needs, from the weather row —
    /// the same write the place toggle performs (`LocationNamer.enabled`), whose
    /// `didSet` requests permission and resolves once. Deliberately NOT a silent
    /// side effect of enabling weather: the user taps a line that says what it does,
    /// so the location opt-in stays an explicit act. (The guard is belt-and-braces —
    /// the button only exists in the `!enabled` branch, which disappears the instant
    /// this runs — and `LocationNamer.enabled`'s own `didSet` no-ops on an unchanged
    /// value anyway. It is NOT guarding a live race; do not read it as one.)
    private func turnLocationOnForWeather() {
        guard !locationNamer.enabled else { return }
        locationNamer.enabled = true
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
        guard weatherEnabled else { return }
        Task { @MainActor in
            // A GPS fix requested SECONDS ago is usually still in flight, and the old
            // code hard-returned on `lastFix == nil` with no retry anywhere: one Start
            // too early and the session had no weather at all, silently, until the next
            // Start. That was survivable while granting location meant hunting for a
            // toggle in another row — the new one-tap grant right above makes
            // "granted, then Start immediately" the COMMON path, so the hole had to
            // close with it. Polling (not observation) because `lastFix` is
            // `@ObservationIgnored` by design; 0.5 s × 12 is a bounded wait that costs
            // nothing when the fix is already there (the first read wins). It cannot
            // delay the first sound — this whole method already runs off the Start
            // path in its own Task, and the salt lands on the NEXT re-seed.
            var fix = locationNamer.lastFix
            var waited = 0.0
            while fix == nil, waited < Self.locationFixWaitSeconds,
                  running, locationNamer.enabled, !locationNamer.denied {
                do { try await Task.sleep(for: .seconds(0.5)) } catch { return }
                waited += 0.5
                fix = locationNamer.lastFix
            }
            guard let fix, let snap = await weatherProvider.snapshot(for: fix), running else { return }
            weatherContribution = WeatherMood.contribution(for: snap)
        }
    }

    /// How long a Start waits for a location fix that was requested moments earlier.
    /// Long enough for a cold first fix after the permission prompt, short enough that
    /// a session which will never get one (indoors, airplane mode) stops asking.
    /// `nonisolated` on purpose: CLAUDE.md records that Xcode and SwiftPM disagree on
    /// SE-0434 inference for a `static let` on a MainActor type, and this repo has no
    /// local compiler to settle it — the explicit marker makes both toolchains agree.
    nonisolated private static let locationFixWaitSeconds = 6.0
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
        // ⛔ And the LEAD. This was missing until 2026-07-28 and it is the same defect as
        // #114's concert-pitch gap, one function away: `setTuningCents` exists on exactly
        // three reachable objects (all `PolySynthVoice` — `subBass`/`bioVoice`/`laneVoiceRack`
        // have no such method, so their absence is correct), and the lead was the one left
        // out. With any non-12-TET system selected, the generated melody played 12-TET
        // against a retuned pad and touch surface — a larger error than the 32 cents of the
        // A4 gap for a maqām or just table.
        leadSynth?.setTuningCents(cents)
    }

    /// Push the concert pitch to every voice that has one. Split out of the three inline
    /// fan-outs (#114) because it also has to run at LAUNCH: `session.a4Hz` restores from
    /// `UserDefaults`, but nothing applied it until the first Generate or a manual A4 edit,
    /// so a user who had saved A=432 and played the touch instrument first heard 440 —
    /// `EchoelPolyDDSP.a4Hz` defaults to 440. Called from `onAppear` beside `applyTuning()`.
    private func applyConcertPitch(_ a4Hz: Double) {
        synth.setTuning(a4Hz: a4Hz)
        subBass.setTuning(a4Hz: a4Hz)
        laneVoiceRack.setTuning(a4Hz: a4Hz)
        touchSynth?.setTuning(a4Hz: a4Hz)
        bioVoice.setTuning(a4Hz: a4Hz)
        leadSynth?.setTuning(a4Hz: a4Hz)
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
            applyConcertPitch(session.a4Hz)
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
    /// TESTED, as of #168 — but only half of it, and the half matters. The fan-out itself now
    /// lives in `PanicFanOut` (`Sequencer/PanicFanOut.swift`), which XCTest can hand spies to,
    /// so dropping a release from the mapping fails a test. What NO test can see is a voice
    /// that never reaches the array BELOW: that inventory is this method's alone, which is why
    /// the last paragraph here is still the only enforcement.
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
        // ORDER IS LOAD-BEARING — `pianoRoll` first, see `PanicFanOut`'s doc. The two
        // optionals are genuinely absent until their surfaces exist; `PanicFanOut` skips
        // nil rather than the caller pre-filtering, so the array reads as the inventory.
        let reached = PanicFanOut([
            pianoRoll,        // releases poly/lead/sub/kind/MIDI AND clears `active`
            synth,
            subBass,
            leadSynth,
            touchSynth,
            bioVoice,         // mono release + clears a stuck controller-held latch
            laneVoiceRack,
            midiOut
        ]).releaseAll()
        // The count is the ONLY thing that distinguishes "panic reached six voices" from
        // "panic reached none because the environment was empty" — and on device those two
        // look identical: silence either way, one because it worked and one because nothing
        // was there. Logging it is what makes the panic button diagnosable from a founder's
        // `echoel_diag.log` instead of guessable. MainActor, once per tap, never a render path.
        log.log(.info, category: .audio, "Panic: released \(reached) voice target(s)")
    }

    // MARK: Panel — Visual (immersive sound→light)

    private var visualPanel: some View {
        // No subtitle, on purpose (founder 2026-07-27: "Das kann weg: ist denkerisch
        // selbst erklärend"). It was the one panel header in the Studio that EXPLAINED
        // instead of labelling — every other one is a terse noun phrase ("Level per
        // part", "Production character"). A window you can already see, drag and resize
        // does not need a sentence telling you that you can drag and resize it.
        panel("Field", isExpanded: $showVisualSettings) {
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
            // `false`: this panel's visual is `FloatingVisualWindow`, which never reads
            // `spectralDonuts` — so claiming donut state here is a claim about another surface.
            visualLookStrip(showsDonutState: false)
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
            // "Voice" — a PEER of the "Look" heading further up, so the panel reads as one
            // surface described from its two sides instead of a visual panel with a sound
            // section bolted to the end. ("Look" already existed; only this one was renamed
            // — an earlier version of this comment claimed the panel "gained two headings",
            // which was simply false and is the kind of sentence that gets cited later.)
            //
            // Typography copied from "Look" EXACTLY, and that is the whole fix: at 13 pt in
            // `EchoelTheme.text` this sat one point under the panel title in the same
            // colour, so on device it read as a SECOND panel title rather than a peer of the
            // 10 pt dim heading it was supposed to pair with. Two headings that claim to be
            // siblings must look like siblings.
            Text("Voice").font(EchoelTheme.font(10, .medium)).foregroundStyle(EchoelTheme.dim)
                .padding(.top, 4)
            Text("What your fingers sound like on the field. Take sound follows the generated music; pick a patch to give the field its own voice.")
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
            // LIFE — per-note micro-variation so two identical taps never produce two
            // identical notes (founder 2026-07-27: "leben wie ein echtes Instrument mit
            // micro changes"): brightness and attack, and — while Sync is on — also the
            // note's placement in time. 0 = off and bit-identical.
            EchoelValueField(label: "Life", value: $touchLife,
                             range: 0...1, unit: "", decimals: 2)
            touchSyncRows
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
            fieldSelfPlaySection
        }
    }

    /// SELF-PLAY (founder 2026-07-29: *"Es soll auch eine Möglichkeit geben wie der Synth
    /// selbst spielt ohne das man Touch bedienen muss. Natürlich mit mehreren Parametern."*).
    ///
    /// A third heading under "Look" and "Voice" — the field's two sides plus what it does on
    /// its own. It is NOT a new panel and NOT a new sheet: the presentation chain does not
    /// grow (black-screen law), and one more panel would be one more place to look for the
    /// same surface.
    ///
    /// The dials only appear once a motion is chosen. That is not tidiness — a screenful of
    /// numeric fields under an "Off" setting is a screenful of controls that provably do
    /// nothing, which is the lying-control class this repo has an open task about. (The count
    /// used to be written out as "seven" here and in `fieldSelfPlayFields`; #253 A7 made both
    /// wrong, and a number in a comment is either maintained or deleted.)
    @ViewBuilder private var fieldSelfPlaySection: some View {
        Text("Self-play").font(EchoelTheme.font(10, .medium)).foregroundStyle(EchoelTheme.dim)
            .padding(.top, 4)
        // Says what it does AND what it does not, in the user's own terms. The hand-wins rule
        // is the one thing a player must know before switching this on, because without it
        // "the field plays itself" reads as "the field takes over".
        // The transport precondition is in the FIRST sentence, not a footnote. Self-play reads
        // the musical clock, and `Transport.currentTick()` returns nothing while stopped — so
        // switching this on with the transport idle produces exact silence. Without the
        // sentence, the obvious reading of that silence is "the feature is broken".
        // One string for all six motions, so it must be true of all six: five travel a point,
        // Arp walks a chord. The old wording promised a travelling point unconditionally and was
        // then contradicted by Arp's own caption thirty lines below.
        Text("The field plays itself while the transport runs: a point travels the surface — or, on Arp, walks your chord — and strikes notes in your key. Press Play to hear it. Put a finger down and it stops instantly — your hand always wins. Its speed follows the Sync grid above, even with Sync itself off.")
            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Text("Motion").font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.text)
            Spacer()
            Picker("Motion", selection: $fieldMotionRaw) {
                Text("Off").tag("")
                ForEach(FieldAutoPlay.Motion.allCases, id: \.rawValue) { m in
                    Text(fieldMotionLabel(m)).tag(m.rawValue)
                }
            }
            .pickerStyle(.menu).tint(EchoelTheme.text)
            .accessibilityLabel("Self-play motion")
        }
        if FieldAutoPlay.Motion(rawValue: fieldMotionRaw) != nil { fieldSelfPlayFields }
    }

    /// Split from `fieldSelfPlaySection` for the same structural reason `touchSyncRows` was:
    /// this file has a black-screen history rooted in aggregate-type growth, and keeping a group
    /// of fields behind one child is the cheap habit. `fieldArpRhythmFields` is the same move one
    /// level further down, which is why the arp's rhythm rows live in their own builder. THIS builder
    /// sits at 7 of the 10; the capacity warning belongs to `fieldArpRhythmFields` and is written on
    /// its own doc comment, where someone adding a row will actually read it.
    @ViewBuilder private var fieldSelfPlayFields: some View {
        EchoelValueField(label: "Density", value: $fieldDensity,
                         range: 0...1, unit: "", decimals: 2)
        // The arp is not a curve across the surface, so three of these dials do not apply to it
        // (see `FieldAutoPlay.Motion.arp`): its x is a specific scale-degree cell, and Span,
        // Centre or a second Voice would move it OFF that cell — a wrong note, not a wider
        // gesture. Hidden rather than shown-and-ignored: this repo has paid four times for a
        // control that is visible and does nothing (#164, #227).
        if FieldAutoPlay.Motion(rawValue: fieldMotionRaw) == .arp {
            // ⚠️ THIS STRING HAS NOW BEEN CORRECTED TWICE, and the second correction UNDID part of
            // the first — worth recording, because the underlying behaviour moved under it:
            //   · #220 S3 review removed "root, third, fifth" (true only in a seven-degree scale —
            //     in Chromatic those degrees are a whole-tone cluster, in Pentatonic Minor
            //     root/fourth/flat-seventh) and replaced "Traverse sets its rate" with "Traverse
            //     where the accent falls", because the Euclidean fire rule was scale-invariant in
            //     the traverse length.
            //   · #253 A7 replaced THAT, because the arp's bar is now a `RoleRhythm` bar: on
            //     `sparse` and `syncopated` the rule divides the bar into four beats, so the
            //     traverse length moves WHICH cells sound and not only where the weight lands.
            //     "Where the accent falls" had become true of the default character and false of
            //     two others.
            // The lesson for the next edit: this caption describes a rule that lives in another
            // file, so check `RoleRhythm.fires` before trusting either version.
            Text("Arp walks upwards through chord degrees of your scale instead of travelling across the field. Density sets how many cells sound, Rhythm how they sit, Band the register. Traverse is the bar the rhythm counts in — on Sparse and Syncopated it also moves which cells sound, and on all six it sets where the accents fall.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            fieldArpRhythmFields
        } else {
            EchoelValueField(label: "Voices", value: $fieldVoices,
                             range: 1...Double(FieldAutoPlay.maxVoices), unit: "", decimals: 0)
        }
        // "Period" in cells of the Sync grid, so the two settings share one vocabulary rather
        // than the generator inventing a second time unit.
        EchoelValueField(label: "Traverse", value: $fieldPeriod,
                         range: 1...64, unit: "cells", decimals: 0)
        if FieldAutoPlay.Motion(rawValue: fieldMotionRaw) != .arp {
            EchoelValueField(label: "Span", value: $fieldSpan,
                             range: 0...1, unit: "", decimals: 2)
            EchoelValueField(label: "Centre", value: $fieldCentre,
                             range: 0...1, unit: "", decimals: 2)
        }
        EchoelValueField(label: "Band", value: $fieldBand,
                         range: 0...1, unit: "", decimals: 2)
        EchoelValueField(label: "Band drift", value: $fieldBandDrift,
                         range: 0...1, unit: "", decimals: 2)
        // The threshold is stated because a control whose first third does nothing AUDIBLE
        // reads as broken unless you say what it is doing instead. `y` picks one of three
        // octave bands, so the wander has to span more than a third to cross a boundary.
        //
        // Two sentences, because the arp behaves DIFFERENTLY here and the difference is not
        // cosmetic: its note snaps to the middle of its register, so a sub-threshold drift moves
        // neither the octave NOR the light. Reusing the travelling wording for it would have
        // promised a visible effect that cannot happen.
        if FieldAutoPlay.Motion(rawValue: fieldMotionRaw) == .arp {
            Text("Band drift only changes the arp when it crosses into the next register — under about 0.35 it does nothing.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Band drift under about 0.35 moves the light on the field without changing the octave.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// THE ARP'S RHYTHM (#253 A7, founder 2026-07-30: *"Alle Soundrubriken … brauchen noch
    /// verschiedene Rhythmus Regler. Verschiedene variablen die interessante, treibende,
    /// hypnotische, dynamische etc. Rhythmus pattern machen"*). Its own builder for the same
    /// structural reason `fieldSelfPlayFields` was split off this file's black-screen history:
    /// small builders, not one growing aggregate type.
    ///
    /// **Five controls, not six.** `RoleRhythm.Params` carries six numbers and exactly ONE is
    /// deliberately absent here: `density`, which is the Field's OWN Density row above —
    /// `FieldAutoPlay.arpTouches` overwrites the stored copy with it, so a second row would be two
    /// dials over one musical dimension.
    ///
    /// `push` was the other absentee until #258 (A2c) and is now the "Laid back" row below. Its
    /// range is HALF the model's: 0…`RoleRhythm.maxPush`, not −0.45…0.45, because
    /// `FieldAutoPlay.pushDelaySeconds` folds everything ≤ 0 to "on the grid" — the consumer
    /// delays an onset with a sleep, and a note that should have sounded EARLIER cannot be
    /// delayed into existence. The character's own bias (`syncopated` late off the beat,
    /// `flowing` a hair behind) still applies and ADDS to whatever the row says — with the
    /// consequences `fieldArpRhythmCaveat` now states to the player.
    ///
    /// ⚠️ **THIS BUILDER IS AT 9 OF THE 10 VIEWS A `@ViewBuilder` ACCEPTS** (#258 added two: the
    /// Laid-back row and its caption). The next row added here does NOT fit — it needs a `Group`,
    /// or a second split, the same way this builder was split from its parent. Counted, not
    /// estimated: HStack · blurb · Note length · its caption · Accent · Laid back · its caption ·
    /// the optional caveat · the optional Evolve row. (This warning stood on `fieldSelfPlayFields`
    /// for one commit — the parent, which is at 7 — where nobody adding an arp row would read it.)
    @ViewBuilder private var fieldArpRhythmFields: some View {
        HStack {
            Text("Rhythm").font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.text)
            Spacer()
            // A Picker and NOT an `EchoelValueField`: these values have NAMES. The one-control law
            // in CLAUDE.md governs NUMERIC parameters, and it says so in as many words — a named
            // choice rendered as a number would be obeying its letter against its purpose.
            Picker("Rhythm", selection: $fieldArpCharacter) {
                ForEach(RoleRhythm.Character.allCases, id: \.rawValue) { c in
                    Text(fieldArpRhythmLabel(c)).tag(c)
                }
            }
            .pickerStyle(.menu).tint(EchoelTheme.text)
            .accessibilityLabel("Arp rhythm")
        }
        Text(fieldArpRhythmBlurb(fieldArpCharacter))
            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            .fixedSize(horizontal: false, vertical: true)
        EchoelValueField(label: "Note length", value: $fieldArpGate,
                         range: Double(RoleRhythm.minGate)...1, unit: "", decimals: 2)
        // Both halves of this sentence are floors the player would otherwise read as a broken dial:
        // the character scales the gate (Driving ×0.45), and the release itself cannot go under
        // `TouchInstrumentUIView.minSelfReleaseSeconds` = 15 ms. On the default 1/16 grid at 120 BPM
        // (125 ms per cell) Driving reaches that floor at about 0.27, so the bottom quarter of the
        // row is flat — and at 300 BPM it is the bottom two thirds. Tempo-dependent, so it is said
        // rather than clipped out of the range.
        //
        // #258 added the THIRD limit named here, and it is a CEILING rather than a floor:
        // `RoleRhythm.hit` computes push first and then caps the gate at `1 - push`, because a note
        // that starts late and still fills its whole cell would ring into the next one. On the two
        // characters whose `gateScale` is 1.0 (`sparse`, `flowing`) that cap binds as soon as Laid
        // back leaves 0; on the others their own scale binds first. Left out of this sentence for
        // one commit, which made the top of the Note length row go quietly flat.
        Text("Note length is a fraction of one cell, scaled by the rhythm — Driving stays short even at 1. Below the instrument's 15 ms minimum nothing gets shorter, and the faster the tempo the sooner that floor is reached; a single note never rings longer than one second. A high Laid back also shortens the longest notes: one that starts late cannot fill its cell as well.")
            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            .fixedSize(horizontal: false, vertical: true)
        EchoelValueField(label: "Accent", value: $fieldArpAccent,
                         range: 0...1, unit: "", decimals: 2)
        // #258 (A2c). ⚠️ THE RANGE IS 0…maxPush AND NOT THE MODEL'S BIPOLAR −0.45…0.45 — see
        // `StudioDefaultKeys.fieldArpRhythmPush`. `FieldAutoPlay.pushDelaySeconds` folds every
        // value ≤ 0 to "on the grid" because the consumer delays an onset with a sleep and there
        // is nothing to sleep for a note that should have sounded EARLIER. Offering the negative
        // half would be a dial whose entire left side does nothing.
        EchoelValueField(label: "Laid back", value: $fieldArpPush,
                         range: 0...Double(RoleRhythm.maxPush), unit: "", decimals: 2)
        Text("How far behind its own step a note lands, as a fraction of one step — 0 is dead on the grid. The rhythm adds its own on top (Syncopated leans back on the off-beats, Flowing everywhere), and the total can never push a note into the next step. Earlier-than-the-grid is not offered: the instrument can hold a note back, not see one coming.")
            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            .fixedSize(horizontal: false, vertical: true)
        if let caveat = fieldArpRhythmCaveat {
            Text(caveat)
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Hidden, not disabled, on the four characters that ignore it — `RoleRhythm.Character`
        // exists to answer exactly this and its own doc requires the row to obey.
        if fieldArpCharacter.usesEvolve {
            EchoelValueField(label: "Evolve", value: $fieldArpEvolve,
                             range: 0...1, unit: "", decimals: 2)
        }
    }

    /// The one thing about the current setting a player would otherwise read as a broken dial, or
    /// `nil` when there is nothing to say. ONE optional string rather than two conditional `Text`s
    /// so this builder stays well inside the ViewBuilder limit as more caveats are learned.
    ///
    /// Both cases are dials that move by too little to hear, which is the #164/#227 shape even
    /// though neither control is strictly inert:
    /// - **Accent on the three subtle characters.** Read off `Character.accentIsSubtle`, NOT a list
    ///   written here. The first version of this row did hard-code the list, and got it wrong by
    ///   omitting `sparse` — whose ≈1.3 dB spread is larger than `hypnotic`'s ≈1.0 dB and was the one
    ///   left unexplained. That is exactly the drift `usesEvolve` exists to prevent, so the sibling
    ///   dial now has its own engine-side flag.
    /// - **Evolve on Dynamic at Accent 0.** `dynamic`'s evolve is a jitter added to the accent
    ///   STRENGTH, and the velocity maths multiplies that by the accent depth — so at Accent 0 the
    ///   bar is bit-identical whatever Evolve says. `flowing` is unaffected: its evolve flips which
    ///   cells sound, upstream of the multiply. The two cases cannot collide (`dynamic` is not
    ///   subtle), which is why this is a single chain and not two independent lines.
    private var fieldArpRhythmCaveat: String? {
        // #258 FIRST, and deliberately ahead of the Accent case: `flowing` is `accentIsSubtle`, so
        // anything after that branch is unreachable for the one character whose lean applies to
        // EVERY note. This case is also the only one keyed to a value the player has just moved.
        //
        // ⛔ WHY IT EXISTS. The row is not the total. `RoleRhythm.hit` adds `pushBias` to it and
        // clamps the SUM at `maxPush`, so on the two characters that carry a lean the top of the
        // row is flat — `flowing` from about 0.40 (its lean applies everywhere), `syncopated` from
        // about 0.33 on the off-beat cells that make the character. Said rather than clipped out of
        // the `range:`, because the flat point is character-dependent and the range is not; a dial
        // that silently stops responding is the #164/#227 shape the rest of this slice avoids.
        // The two numbers are approximate ON PURPOSE — writing them exactly would duplicate
        // `RoleRhythm.pushBias`'s private constants here and invite the two to drift.
        if fieldArpPush > 0 {
            switch fieldArpCharacter {
            case .flowing:
                return "Flowing already sits a hair behind on every note, and Laid back adds to it — the two together stop at the row's own ceiling, so above about 0.40 the timing no longer changes."
            case .syncopated:
                return "Syncopated already leans back on its off-beats, and Laid back adds to it — on those notes the two together stop at the row's ceiling, so above about 0.33 they no longer move."
            case .driving, .hypnotic, .dynamic, .sparse:
                break
            }
        }
        if fieldArpCharacter.accentIsSubtle {
            return "\(fieldArpRhythmLabel(fieldArpCharacter)) is nearly level by design — Accent barely cuts here. Dynamic or Driving give a strong one."
        }
        if fieldArpCharacter == .dynamic && fieldArpAccent <= 0 {
            return "On Dynamic, Evolve moves the accent — with Accent at 0 there is nothing for it to move."
        }
        return nil
    }

    /// Player-facing names for the six rhythm characters. Kept out of `RoleRhythm` for the reason
    /// `fieldMotionLabel` states: the core is pure Foundation, a display string is a UI decision.
    private func fieldArpRhythmLabel(_ c: RoleRhythm.Character) -> String {
        switch c {
        case .driving:    return "Driving"
        case .hypnotic:   return "Hypnotic"
        case .dynamic:    return "Dynamic"
        case .sparse:     return "Sparse"
        case .syncopated: return "Syncopated"
        case .flowing:    return "Flowing"
        }
    }

    /// One line per character, so choosing one is a musical decision and not a guess.
    ///
    /// ⛔ THESE DESCRIBE WHAT **THE ARP** DOES, NOT WHAT `RoleRhythm` CAN DO, and the difference cost
    /// this slice a review HIGH. The first version was written as "a plain-language restatement of
    /// that case's doc comment in `RoleRhythm.Character`" — and the core's docs correctly describe
    /// `pushBias`, the small timing offset each character adds (`syncopated` +0.12 off the beat,
    /// `flowing` +0.05). At the time, `FieldAutoPlay.arpTouches` **DROPPED `pushFraction` ENTIRELY** —
    /// its `Touch` carried x/y/velocity/gateFraction and nothing about when the note falls. So "a hair
    /// late" and "a hair behind the grid" promised the one thing the arp provably could not do, and
    /// this slice kept the Push ROW out of the UI on exactly that reasoning, then re-introduced the
    /// promise as prose. A claim in a caption is as much a lying control as a dial (#164/#227).
    ///
    /// ✅ **#253 A2b LANDED, so the timing words are now earned — for TWO of the six.** `Touch` carries
    /// `pushFraction` and `TouchInstrumentUIView` schedules the onset late by
    /// `FieldAutoPlay.pushDelaySeconds`. `pushBias` gives a bias to `syncopated` (+0.12 off the beat)
    /// and `flowing` (+0.05 everywhere) and **exactly 0 to the other four** — `driving` is deliberately
    /// dead straight and that is the point of it. So a timing word in `hypnotic`, `dynamic`, `sparse`
    /// or `driving` would be the same lie this comment exists to prevent, A2b or no A2b. Verify against
    /// `RoleRhythm.pushBias` before adding one, not against this paragraph.
    private func fieldArpRhythmBlurb(_ c: RoleRhythm.Character) -> String {
        switch c {
        case .driving:
            return "Straight and short, hard on the beat — machine time, with air between the notes for the pulse to be felt."
        case .hypnotic:
            return "Even and long with almost no accent, and the figure rotates a little every bar so it repeats without being repetitive."
        case .dynamic:
            // Two differences, not one: the level contour AND the length (gate ×0.7 vs Driving's
            // ×0.45, so ~55% longer at the same Note length). The length is the more audible of the
            // two, and naming only the contour invited the ear to miss it.
            return "The same notes as Driving but longer, and the level contour moves — the bar breathes. This is where Evolve does the most."
        case .sparse:
            return "Fewer notes than Density asks for, only on the beats, held long. Wide."
        case .syncopated:
            return "Prefers the cells between the beats and accents them, inverting the weight — the off-beats are the loud ones, and they land a touch late."
        case .flowing:
            return "Long and level, filling the cell and sitting a hair behind the beat — it stays under everything else instead of competing with it."
        }
    }

    /// Player-facing names for the motions. Kept out of `FieldAutoPlay` on purpose: that type
    /// is pure and Foundation-only, and a display string is a UI decision that will want to be
    /// localised long before the generator wants to know about language.
    private func fieldMotionLabel(_ m: FieldAutoPlay.Motion) -> String {
        switch m {
        case .rise:     return "Rise"
        case .fall:     return "Fall"
        case .pendulum: return "Pendulum"
        case .drift:    return "Drift"
        case .hold:     return "Hold"
        case .arp:      return "Arp"
        }
    }

    /// ULTRASYNC (founder 2026-07-28: "damit das Touch Instrument immer perfekt im timing
    /// ist auch microtime — somit wird ungeschicktes Spielen auch zum ästhetischen
    /// Ereignis"). The play surface already made a WRONG NOTE impossible; this makes a
    /// wrong MOMENT unlikely. An early touch is held back onto the grid; a late one sounds
    /// where it landed and gets the pulse restored by a quieter echo on the beat — the
    /// mistake is answered rather than erased. Off (0) is bit-identical to the instrument
    /// without it.
    ///
    /// Its own sub-view for a structural reason, not tidiness: `touchSoundSection` was at
    /// 13 direct children and this file has a black-screen history rooted in exactly that
    /// class of aggregate-type growth. Three rows behind one child is the cheap habit.
    @ViewBuilder private var touchSyncRows: some View {
        // The swing caveat is in the user-facing string on purpose. `Transport.currentTick`
        // does not model swing, and eight shipping genres carry real swing values — a
        // control that quietly does something different there is the "lying control" class
        // this repo has an open task about. Better a short honest sentence than a surprise.
        Text("Sync pulls your touches onto the beat while the transport runs — early ones wait for the grid, late ones get a quiet echo on it. Life sets how much the corrected notes breathe. On swung genres the grid it aims at is the straight one.")
            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            .fixedSize(horizontal: false, vertical: true)
        EchoelValueField(label: "Sync", value: $touchSyncStrength,
                         range: 0...1, unit: "", decimals: 2)
        HStack {
            Text("Grid").font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.text)
            Spacer()
            Picker("Grid", selection: $touchSyncGrid) {
                ForEach(TouchQuantizer.Grid.allCases) { g in Text(g.label).tag(g) }
            }
            .pickerStyle(.menu).tint(EchoelTheme.text)
            .accessibilityLabel("Sync grid")
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
    /// - Parameter showsDonutState: whether this mount can actually SHOW the donut renderer.
    ///   `false` for the inline Field panel (whose visual is `FloatingVisualWindow`, which does not
    ///   read `spectralDonuts` at all), `true` for the fullscreen VJ overlay — that overlay lives
    ///   INSIDE the `.fullScreenCover` where `SpectralDonutView` is built, and still carries a
    ///   working donut toggle in its top bar. #227's first cut made the readout unconditional at
    ///   BOTH mounts, which fixed the inline lie and planted the mirror image of it in the overlay:
    ///   the day `showVisual` gets a setter again, that overlay would print "Aurora" over a donut
    ///   field. One parameter instead, so neither mount can drift into claiming the other's state.
    private func visualLookStrip(showsDonutState: Bool) -> some View {
        // ALIGNED with the Visual window's top-bar slider (founder 2026-07-07: "das
        // hauptmenü dementsprechend angleichen"): one slider that scrubs the calm metal
        // looks — SAME handling in both places, fewer buttons than the old labelled strip.
        // The busy/technical looks (Rings/Cymatics/Prism/Lissajous/Scope/Fractal) stay in
        // the shader (indices unchanged, reversible) but aren't surfaced here, so nobody
        // has to tap past Prism to reach calm. Writes the shared `visual.style` key.
        // (It said "a Donuts pill + a slider" and "visual.style / visual.spectralDonuts"
        // until #227 removed the pill — see the block inside the HStack for why.)
        HStack(spacing: 10) {
            // ⛔ THE "DONUTS" PILL STOOD HERE AND WAS REMOVED (#227). It set `spectralDonuts = true`,
            // which the ONE visual a player can reach — `FloatingVisualWindow` — does not read at
            // all: it renders from `visual.style`/`styleB`/`blend` only. `SpectralDonutView` is
            // constructed at exactly one place, inside the `.fullScreenCover(isPresented:
            // $showVisual)` further up this file, and `showVisual`'s only setter was the deleted
            // `openTool`. So the pill filled, the readout to the right said "Donuts", and nothing
            // on screen changed — and because the default was `true`, that was the state of a
            // FRESH INSTALL. It also skipped the launch look-snap (the `if !spectralDonuts` in
            // `.onAppear`) and the customizer's live re-snap, so a persisted look that had fallen
            // out of the slider sequence was never repaired.
            //
            // ⛔ AND ONE THING THIS BLOCK CLAIMED FOR ONE COMMIT AND SHOULD NOT HAVE: that `true`
            // also HID `visualBlendControls`. It did not. That view has ZERO mount sites — the two
            // places that used to compose it are comments recording its removal on 2026-07-07. The
            // guard `if !spectralDonuts` inside it protects something nobody can see either way.
            // Writing an unreachable claim into the rationale of the commit that removes unreachable
            // claims is the failure itself, and it would have taught the next reader that
            // `visualBlendControls` is live — blocking a legitimate deletion.
            //
            // The KEY, the cover's `if spectralDonuts` branch and `SpectralDonutView` all stay:
            // the renderer is not the defect, the unreachable claim was. Bring the pill back in
            // the SAME commit that gives `showVisual` a setter again — and note what else that
            // commit owes: the VJ overlay mounts this strip too, so it must pass
            // `showsDonutState: true` (already the case) AND it has no `visualLookCustomizer`
            // beneath it, so with a one-look sequence the slider disappears and the pill was the
            // overlay's last look control. Restore it there, not only inline.
            //
            // Dragging the slider morphs STUFENLOS between the looks (continuous crossfade
            // via style/styleB/blend, mapping in LookBlendMap). Its setter still clears
            // `spectralDonuts` — harmless now that nothing REACHABLE sets it true (the word
            // matters: the overlay's own toggle and this setter are both still writers), and
            // correct again the day the pill returns.
            if LookBlendMap.maxPosition(for: sliderLooks) > 0 {
                Slider(value: lookScrub, in: 0...LookBlendMap.maxPosition(for: sliderLooks))
                    .tint(EchoelTheme.accent)
                    .accessibilityLabel("Visual look")
                    .accessibilityValue(currentLookName)
            }

            // #227: at a mount that cannot show donuts this names what is actually rendering.
            // The old unconditional ternary printed "Donuts" over a Metal look in the inline panel.
            Text(showsDonutState && spectralDonuts ? "Donuts" : currentLookName)
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

    /// ⛔ DELETE THIS TOGETHER WITH THE LINE THAT CALLS IT, IN THE SAME COMMIT THAT GIVES
    /// `showVisual` A SETTER AGAIN (#227). It exists for exactly one reason and has an expiry
    /// condition written into it, because a permanent forced-off would be its own lying control.
    ///
    /// #227 removed the only reachable control that could set `spectralDonuts` and flipped the
    /// default to `false`. That leaves ONE group unserved: an install that already has `true`
    /// stored. Without this, those players keep the launch look-snap skipped and the customizer's
    /// live re-snap skipped — and now have no reachable control at all able to undo it. That is
    /// strictly worse than the lie the slice removes, which is why the flip and this line have to
    /// ship together. (This note said "keep `visualBlendControls` HIDDEN" for one commit. That view
    /// has no mount sites at all, so nothing was hidden — see `StudioDefaultKeys` for the full
    /// retraction. The remaining reasons stand on their own.)
    ///
    /// Deliberately NOT a "migration flag": there is nothing to remember. While no door exists,
    /// the only truthful value is `false`, and re-asserting it every launch costs one comparison.
    private func normaliseUnreachableDonutMode() {
        guard spectralDonuts else { return }   // untouched for everyone already on `false`
        spectralDonuts = false
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
                    // `true`: this overlay IS inside the cover that builds `SpectralDonutView`, and
                    // its top bar still toggles donut mode — here the state is real and worth naming.
                    visualLookStrip(showsDonutState: true)
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

    /// #228 — THE ONE VISUAL CONTROL ("ein Bedienelement statt neun Reglern").
    ///
    /// A single Energy position, 0 = the calmest curated world, 1 = the most energetic one.
    /// It carries **no state of its own**: `get` derives the position from the live values
    /// and `set` writes them back (`VisualEnergy`, which is where the mapping and the
    /// reasoning live). That is deliberate — a dial with its own stored position would
    /// drift the moment someone edits a fine-tune row, and would then be telling the user
    /// something false about the picture in front of them.
    ///
    /// One behaviour to state plainly rather than discover on device: after a hand edit that
    /// puts Intensity and Motion at *different* positions on the curve, the dial shows their
    /// centre, and the first drag pulls BOTH back onto the curve at the new position. That is
    /// what a macro control is; it is not a bug. The individual values remain one tap away
    /// under Fine tune.
    private var visualEnergy: Binding<Double> {
        Binding(
            get: { VisualEnergy.position(matching: visualIntensity, motion: visualMotion) },
            set: { t in
                let l = VisualEnergy.look(at: t)
                let changed = l.intensity != visualIntensity || l.motion != visualMotion
                visualIntensity = l.intensity
                visualMotion = l.motion
                // Moving Energy diverges from whatever preset was tapped — same rule the
                // individual energy fields already followed. GUARDED on an actual change,
                // because `EchoelValueField.apply` writes its binding unconditionally after
                // clamping: at the 0 or 1 end of the range a further drag (or a VoiceOver
                // adjust) re-writes the same values, and an unguarded clear would drop the
                // user's preset selection although nothing moved.
                if changed { visualPresetID = "" }
            }
        )
    }

    /// The ONE control plus, folded away, the six that were on the surface before it.
    /// ONE definition, used by BOTH the inline Field panel and the fullscreen VJ overlay
    /// so the controls are identical everywhere (founder: "easy to understand/control" —
    /// no drift, one place to change).
    ///
    /// WHY THE SIX ARE FOLDED AND NOT DELETED — and the precise version, because the first
    /// draft of this comment said "no other writer" and that is simply false: `applyVisualPreset`
    /// writes Intensity/Detail/Motion/Spread on every preset tap, and Hue/Saturation too when
    /// the preset carries a palette (only Vapor does today). What a preset CANNOT do is reach an
    /// arbitrary value — it lands on one of five curated points, and four of the five leave
    /// Hue/Saturation exactly where they were. So deleting these rows would strand whatever
    /// value is already on disk with no way back to it. That is the Tools-grid lesson this repo
    /// already paid for once: check what a UI block is the only route to before removing it.
    ///
    /// The energy fields clear the preset selection on edit since they then diverge from it;
    /// Hue/Saturation are palette-only and leave the preset intact.
    @ViewBuilder private var visualAdjustFields: some View {
        EchoelValueField(label: "Energy", value: visualEnergy, range: 0...1)
        Text("Calm ↔ energetic, across the same range the presets span. Fine tune holds the individual parameters.")
            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            .fixedSize(horizontal: false, vertical: true)
        Button {
            showVisualFineTune.toggle()
        } label: {
            HStack(spacing: 8) {
                Text("Fine tune")
                    .font(EchoelTheme.font(12, .semibold))
                    .foregroundStyle(EchoelTheme.dim)
                Spacer(minLength: 8)
                Image(systemName: showVisualFineTune ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(EchoelTheme.dim)
            }
            // ≥44 pt tap target (#113, a11y) BEFORE `contentShape`, or the hit area would be
            // the ~16 pt the 12 pt text and 10 pt chevron actually occupy.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fine tune the visual")
        // Without a VALUE the two states sound identical to VoiceOver — the chevron carries
        // the state visually only, which is exactly the gap #241 closed elsewhere.
        .accessibilityValue(showVisualFineTune ? "Shown" : "Hidden")
        .accessibilityHint("Shows or hides the individual visual parameters")
        if showVisualFineTune {
            EchoelValueField(label: "Intensity", value: $visualIntensity, range: 0...1.5,
                             onChange: { visualPresetID = "" })
            EchoelValueField(label: "Detail", value: $visualDetail, range: 8...90, decimals: 0,
                             onChange: { visualPresetID = "" })
            // #269 — Detail only reaches the Metal field through the Rings look, and Rings is
            // not in the shipped look set. Say so instead of letting the row read as broken.
            //
            // NOT hidden and NOT disabled — and the reason is NOT the one the first draft
            // gave. It cited "the Bass-rhythm row and A7's Evolve", and Evolve is the exact
            // opposite: it IS hidden (`if fieldArpCharacter.usesEvolve`), because a character
            // that ignores it can never use it — a structural fact about the engine. The
            // Bass row's reason does not transfer either: it stays because ITS condition is
            // live-body-driven, and this one is not. The real precedent is
            // `fieldArpRhythmCaveat` — a caption for a dial that is live but inaudible — and
            // the real reason to keep the row is that this condition flips as the LOOK SLIDER
            // is dragged: a row that appears and vanishes under the finger mid-drag, taking
            // the four rows below it up and down with it, is worse than a row plus a sentence.
            //
            // The condition is a plain read of three user-set values — no live-bio churn, and
            // no invalidation source the body did not already have.
            if LookBlendMap.detailReach(style: visualStyle, styleB: visualStyleB,
                                        blend: visualBlend) < 0.001 {
                // TWO steps, and the first version said one. Adding Rings under "Slider looks"
                // only re-snaps the visual when the CURRENT style fell out of the set
                // (`!next.contains(visualStyle)`), which with the shipped default style 5 it
                // does not — so the caption would still be here, having promised otherwise.
                // Naming a fix that does not work, inside the fix for a control that promises
                // more than it does, is the defect eating its own tail.
                Text("Detail shapes the Rings look only. Add Rings under Slider looks above, then drag the look slider onto it.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            EchoelValueField(label: "Motion", value: $visualMotion, range: 0...1.5,
                             onChange: { visualPresetID = "" })
            EchoelValueField(label: "Spread", value: $visualSpread, range: 0.5...1.5,
                             onChange: { visualPresetID = "" })
            EchoelValueField(label: "Hue", value: $visualHue, range: 0...1)
            EchoelValueField(label: "Saturation", value: $visualSaturation, range: 0...2)
        }
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
            bassRhythmRow
            padRhythmRow
            Text("Friendly ↔ scary (tension) · sparse ↔ busy (liveliness) · bright ↔ dark · lush 7ths (romance) · odd leaps (weird). Blends with your live signal.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// #253 A3 — the BASS's rhythm character, in the Mood panel because this panel is exactly
    /// "Character of the composition" and a bassline's feel is character, not timbre or tempo.
    ///
    /// **"Genre" is the first option and the default, and it is not a placeholder** — it means the
    /// bass keeps the rhythm the style was curated with. Every other option OVERRIDES that for all
    /// genres at once, which is why the neutral choice has to be the one you land on and the one you
    /// can always get back to (#81/#125: the founder tuned these genres by ear twice, and "plötzlich
    /// klingt alles gleich" was the defect).
    ///
    /// A `Picker` and not an `EchoelValueField`: named values (the same reading of the one-control
    /// law as the arp's Rhythm row). Recomposes on change like every other row in this panel — it
    /// changes the notes, not the sound.
    ///
    /// ⚠️ WHEN IT DOES NOTHING, and the first version of this note named only half of it. The walk
    /// this row shapes exists only when ALL THREE parts of `appendBass`'s gate hold:
    ///   · the genre is not a sustained drone (and trap's 808 pedal takes its own path),
    ///   · `motion > 0.32` — a composite of `busy` and `calm`, so **a settled body ignores this row
    ///     on EVERY genre**, which is the case a founder is most likely to meet,
    ///   · the chord section is at least 4 steps (a 5-chord progression over 16 gives 3).
    /// That is worth a caption if it ever confuses — but it is deliberately NOT hidden or disabled,
    /// because the gate depends on the live body and a control that vanishes mid-performance is the
    /// worse failure (the same call A7's Evolve caveat made).
    ///
    /// ⚠️ NO `MoodPreset` WRITES THIS, unlike the rows around it in this panel. Picking a mood preset
    /// leaves the chosen bass rhythm in place — correct (it is a per-role rhythm, not a mood), but it
    /// means the row does not "reset" with the rest of the panel and only "Genre" clears it.
    private var bassRhythmRow: some View {
        labeledRow("Bass rhythm") {
            Picker("Bass rhythm", selection: $bassRhythmRaw) {
                Text("Genre").tag("")
                ForEach(RoleRhythm.Character.allCases, id: \.rawValue) { c in
                    Text(fieldArpRhythmLabel(c)).tag(c.rawValue)
                }
            }
            .pickerStyle(.menu).tint(EchoelTheme.text)
            .onChange(of: bassRhythmRaw) { _, _ in recomposeIfRunning() }
            .accessibilityLabel("Bass rhythm")
            .accessibilityHint("Genre keeps the style's own bassline; the other choices override it")
        }
    }

    /// #253 A4 — the PAD's rhythm character. Directly under the bass row, because the two answer the
    /// same question for the two layers a listener actually hears, and reading them as a pair is how
    /// a player builds "driving bass under a hypnotic pad" — the combination this whole task exists
    /// for (founder 2026-07-30: *"Alle Soundrubriken von Pads, Bass bis arp etc."*).
    ///
    /// **"Genre" is the default and it is not a placeholder** — it keeps the articulation each style
    /// was curated with. Overriding it is louder here than on the bass: the pad is the biggest
    /// audible surface since the drums went (#166/#167), so this row is also the fastest way to make
    /// every genre sound the same. That is the player's call to make, not a default to ship.
    ///
    /// ⚠️ WHERE IT REACHES, stated precisely because the bass row's first version was vague about it
    /// and had to be corrected: EVERY non-arpeggiated pad path — the sustained heartbeat Fläche, the
    /// skank/stab/comp chops AND the single held chord. On an ARPEGGIATED genre it changes only WHEN
    /// the arp's notes land, never their pitch order. So unlike the bass row there is no genre where
    /// it does nothing — which is the reason it needs no "may read as dead" caveat.
    ///
    /// ⚠️ WHAT IT DOES *NOT* REACH, so this row is not read as governing every harmonic event: the
    /// inner PULSE layer (chord tones an octave up, `composeHarmonic`) keeps its own fixed 8th/quarter
    /// grid. Choose `sparse` on a busy chop genre and the CHORD thins while the pulse carries on —
    /// audible, correct, and not a bug. Whether the pulse should follow the same character is its own
    /// decision (it is the layer that keeps a take moving) and is deliberately not made here.
    private var padRhythmRow: some View {
        labeledRow("Pad rhythm") {
            Picker("Pad rhythm", selection: $padRhythmRaw) {
                Text("Genre").tag("")
                ForEach(RoleRhythm.Character.allCases, id: \.rawValue) { c in
                    Text(fieldArpRhythmLabel(c)).tag(c.rawValue)
                }
            }
            .pickerStyle(.menu).tint(EchoelTheme.text)
            .onChange(of: padRhythmRaw) { _, _ in recomposeIfRunning() }
            .accessibilityLabel("Pad rhythm")
            // The tone half is stated because it IS what the founder asked for (#253 A6) and
            // because an unannounced timbre change reads as the genre having changed. It says
            // "slightly" on purpose: the trim is bounded to ≤0.05 brightness and ≤12 % cutoff
            // (`RoleRhythm.TimbreTrim`), and a hint promising more than that would be the same
            // overclaim as a dial that does nothing.
            .accessibilityHint("Genre keeps the style's own chord articulation; the other choices override it and also shape the sound slightly — short rhythms brighter, long ones darker")
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
            promptRow
            randomizeButton

            // Every parameter is a scrubbable numeric value, one per row with its unit
            // shown after it (drag = fast/coarse or slow/fine to 0.0001; tap = type
            // exact). Pickers for character. No sliders.
            // ⭐ #292 SLICE 2 — WHY THE ROWS ARE IN A GRID AND THE HEADERS ARE NOT.
            // `EchoelValueField` is `HStack { label; Spacer(minLength: 8); valueBox }`, so it
            // consumes whatever width it is offered — and `menuPanelHost` offers
            // `maxWidth: .infinity`. In landscape (or any regular width) that puts the label
            // at the far left edge and its own value box at the far right, with hundreds of
            // points of nothing between them: the eye has to travel the whole screen to pair
            // a name with its number, and the drag target sits nowhere near its label. That
            // is the concrete defect behind "9 of 11 panels have no reflow" — NOT a narrow
            // column in empty space, which is what #292's first description got wrong.
            // Two columns keep each row at a readable ~305 pt (landscape SE) to ~437 pt (16 Pro
            // Max) — computed from the actual chrome: `menuPanelHost`'s 8 pt, its `.padding(2)`,
            // `EchoelPanel`'s 14 pt and the grid's 10 pt gutter. The first version wrote a
            // device-free "~340 pt" in a file whose culture is to put the command next to the
            // number. It uses the width for MORE
            // parameters instead of more emptiness.
            // Headers and the explanatory `Text` blocks stay OUTSIDE the grid on purpose: a
            // section title in a grid cell would sit beside a parameter row and stop reading
            // as a title, and the wrapping explanations want the full measure.
            // Portrait is unchanged — one column, and `spacing: 14` is `EchoelPanel`'s own
            // content spacing, so the rhythm the founder sees today is preserved exactly.
            groupHeader("Tone")
            AdaptiveCardGrid(spacing: 14) {
                knob("Brightness", $currentPatch.brightness, 0...1)
                knob("Harmonics", $currentPatch.harmonicity, 0...1)
                knob("Harm. level", $currentPatch.harmonicLevel, 0...1)
                knob("Noise", $currentPatch.noiseLevel, 0...1)
                // ⛔ THE TWO PICKERS BELONG IN THIS GRID, and leaving them out was the same
                // defect one level down. The first version put them after it, so Tone rendered
                // as two 2-up rows followed by two FULL-WIDTH picker rows — the exact ragged
                // block `SoundPanelReflowsTests` condemns between groups, reproduced inside
                // one. `labeledRow` is a `VStack` that already pins `maxWidth: .infinity`, so
                // it tiles in a cell like any other row; there was never a technical reason.
                // Six items now read as three clean rows.
                //
                // #286 — THE TWO NAMED TIMBRE CHOICES, ported from `PatchEditorView` for the
                // same reason as the Unison rows below: that file had no door and has since
                // been deleted (#132 Slice 6), and these were the only editors for two
                // engine-consumed fields. `Picker`, not `EchoelValueField` — the numeric law is
                // explicitly about NUMERIC parameters, and a spectral shape stops being a
                // number to decode.
                labeledRow("Shape") {
                    Picker("Spectral shape", selection: spectralShapeBinding) {
                        ForEach(EchoelDDSP.SpectralShape.allCases, id: \.self) { shape in
                            Text(shape.rawValue).tag(shape.rawValue)
                        }
                    }
                    .pickerStyle(.menu).tint(EchoelTheme.text)
                    .onChange(of: currentPatch.spectralShape) { _, _ in applySoundLive() }
                    .accessibilityLabel("Spectral shape")
                }
                labeledRow("Noise colour") {
                    Picker("Noise colour", selection: noiseColorBinding) {
                        ForEach(EchoelDDSP.NoiseColor.allCases, id: \.self) { colour in
                            Text(colour.rawValue).tag(colour.rawValue)
                        }
                    }
                    .pickerStyle(.menu).tint(EchoelTheme.text)
                    .onChange(of: currentPatch.noiseColor) { _, _ in applySoundLive() }
                    .accessibilityLabel("Noise colour")
                }
            }

            // #281 — THE ENSEMBLE ROWS, ported here from `PatchEditorView` so that retiring
            // it (#132 Slice 6, now done) was a cleanup and not a silent capability loss. They were the
            // only editor for `unisonVoices` / `unisonDetuneCents` anywhere in the app, and
            // unison is the single biggest "thin → rich" lever the engine has
            // (`PolySynthVoice.apply` says so at its own default).
            groupHeader("Unison")
            AdaptiveCardGrid(spacing: 14) {
                EchoelValueField(label: "Voices", value: unisonVoicesBinding,
                                 range: Float(1)...Float(EchoelPolyDDSP.maxUnison),
                                 decimals: 0, onChange: { applySoundLive() })
                EchoelValueField(label: "Detune", value: unisonDetuneBinding,
                                 range: Float(0)...Float(50), unit: "cents",
                                 decimals: 0, onChange: { applySoundLive() })
            }
            Text("Each note played as several slightly-detuned copies — the difference between one thin voice and an ensemble. 1 voice = off.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)

            groupHeader("Filter")
            AdaptiveCardGrid(spacing: 14) {
                knob("Cutoff", $currentPatch.filterCutoff, 20...18000, unit: "Hz")
                knob("Resonance", $currentPatch.filterResonance, 0...1)
                knob("LFO→filter", $currentPatch.lfoToFilterDepth, 0...1)
                knob("LFO rate", $currentPatch.filterLFORate, 0...20, unit: "Hz")
                knob("LFO depth", $currentPatch.filterLFODepth, 0...1)
            }

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
            // The Swell↔Strike macro and its explanation stay full-width ABOVE the grid: it
            // WRITES the four fields below it, so pairing it beside one of them would read as
            // a peer of A/D/S/R instead of the control that sets them.
            AdaptiveCardGrid(spacing: 14) {
                param("Attack", $currentPatch.attack, 0...5, unit: "s")
                param("Decay", $currentPatch.decay, 0...5, unit: "s")
                param("Sustain", $currentPatch.sustain, 0...1)
                param("Release", $currentPatch.release, 0...10, unit: "s")
            }

            groupHeader("Space & vibrato")
            AdaptiveCardGrid(spacing: 14) {
                knob("Reverb mix", $currentPatch.reverbMix, 0...1)
                knob("Reverb decay", $currentPatch.reverbDecay, 0...10, unit: "s")
                knob("Vibrato rate", $currentPatch.vibratoRate, 0...12, unit: "Hz")
                knob("Vibrato depth", $currentPatch.vibratoDepth, 0...1)
            }

            // #286 — THE LAST PORTED ROW, and the one that was held back longest. See
            // `outputLevelBinding` for why the "sits against the auto-calibration" objection
            // does not hold. One field in the grid renders as a half-width cell with an empty
            // one beside it; that is already how "Sub / Bass (felt)" (3 items, 2 columns) has
            // shipped, and it is the point of #292 — the row stays at a readable width instead
            // of stretching its label and its value box to opposite screen edges.
            groupHeader("Level")
            AdaptiveCardGrid(spacing: 14) {
                EchoelValueField(label: "Output", value: outputLevelBinding,
                                 range: Float(0.3)...Float(1.5), decimals: 2,
                                 onChange: { applySoundLive() })
            }
            Text("This sound's own loudness, so one instrument does not sit far above or below the others. 1.00 = unity. The built-in sounds arrive pre-matched; this trims from there.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)

            // The "Vibration" dimension: a dedicated sub-octave bass you can push to
            // FEEL the body's bass (sub / headphones / haptics). Silent at 0.
            groupHeader("Sub / Bass (felt)")
            AdaptiveCardGrid(spacing: 14) {
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
            }
            Text("Reinforces the bass an octave below — feel it on a sub, in headphones, or as haptics. Presence makes it read on small speakers (octaves only, always in key); heat saturates without getting louder.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// #286 — CANONICALISING BINDINGS, and without them the ported pickers would be BLANK for
    /// every FACTORY preset, for the `Init` default this view starts on, and for every patch
    /// decoded from an older save.
    ///
    /// ⛔ The first version of this line said "blank for every sound in the app", which is too
    /// wide by more than half: all 33 `GenrePatches` entries spell their values exactly as the
    /// enum does ("Dark", "Pink") and would have displayed correctly. What is lowercase is
    /// `SynthPatch.rawFactory`, the `init` default parameters (`spectralShape: String = "dark"`)
    /// and the decoder's `decodeIfPresent(...) ?? "dark"` fallback — which is also why these
    /// bindings stay necessary even if the roster were ever normalised.
    ///
    /// `SynthPatch.spectralShape` / `.noiseColor` are `String`s, and those values are
    /// lowercase ("dark", "pink") while the enum rawValues the picker lists are capitalised
    /// ("Dark", "Pink"). The engine does not care — `SynthPatch.match` compares
    /// case-INsensitively, which is why those patches sound correct today. A SwiftUI `Picker`
    /// does care: it matches its tag by `==`, so a patch storing "dark" would select none of
    /// the eight rows and show an empty control over a perfectly good sound.
    ///
    /// ⛔ THAT WAS A REAL DEFECT IN `PatchEditorView`, not a hazard I invented: it bound
    /// `$patch.spectralShape` straight to capitalised options, so its pickers read blank for
    /// every factory patch. Doorless, so nobody ever saw it — copying the row unchanged would
    /// have been the first time a user did. (That file is deleted as of #132 Slice 6, so the
    /// defect is gone with it; the reasoning stays because the TRAP is still live — anyone
    /// binding a Picker straight to `SynthPatch`'s stored strings re-creates it.)
    /// The getter maps through the enum so the picker shows the
    /// case the engine will actually resolve; the setter writes the canonical rawValue, which
    /// also quietly migrates the stored string on first edit.
    ///
    /// The `?? .natural` / `?? .pink` fallback is only reachable for a value no shipped path
    /// produces (`SynthPatchValuesResolveTests` proves every factory and genre patch resolves).
    /// If one ever did, the engine's own rule is "unknown → leave the voice alone", so the
    /// picker would be showing a guess — that is the honest cost of a control that must
    /// display exactly one of its rows.
    private var spectralShapeBinding: Binding<String> {
        Binding(get: { (EchoelDDSP.SpectralShape.allCases.first {
                            $0.rawValue.caseInsensitiveCompare(currentPatch.spectralShape) == .orderedSame
                        } ?? .natural).rawValue },
                set: { currentPatch.spectralShape = $0 })
    }

    /// Same rule as `spectralShapeBinding`.
    private var noiseColorBinding: Binding<String> {
        Binding(get: { (EchoelDDSP.NoiseColor.allCases.first {
                            $0.rawValue.caseInsensitiveCompare(currentPatch.noiseColor) == .orderedSame
                        } ?? .pink).rawValue },
                set: { currentPatch.noiseColor = $0 })
    }

    /// `unisonVoices` is `Int?` and the row is a numeric field, so it needs its own binding.
    ///
    /// ⭐ THE FALLBACK IS 2, NOT 1, AND THAT IS THE POINT OF PORTING RATHER THAN COPYING.
    /// `PolySynthVoice.apply` reads `patch.unisonVoices ?? 2`, so a patch that does not specify
    /// unison is PLAYED with two detuned voices. `PatchEditorView` displayed `?? 1`, so its row
    /// read "1 voice / 0 cents" while the engine ran 2 / 7¢: a readout that disagrees with what
    /// you hear, and dragging from that wrong start silently changed the sound before the
    /// number moved. Mirroring the engine's own defaults here is what makes the row honest.
    ///
    /// ⛔ WHICH PATCHES THAT ACTUALLY COVERS — the first version of this note said "every
    /// generative genre patch", and that is wrong by a wide margin: `GenrePatches` passes
    /// explicit `uni:`/`det:` for 29 of its 33 patches (spread over 2–4 voices and 6–16¢).
    /// The fallback governs the OTHER FOUR, plus blank and pre-2026-07 saved sounds. The fix
    /// is unchanged — the two numbers still have to mirror — but a scope claim that large,
    /// stated as a reason, is how a wrong mental model spreads into the next slice.
    ///
    /// ⛔ AND THE GETTER CLAMPS, which the first version did not. Two genre patches persist
    /// `uni: 4` while `EchoelPolyDDSP.maxUnison` is 3 and `setUnison` clamps to it — so an
    /// unclamped row displayed "4" while three voices sounded. That is the very defect this
    /// binding exists to end, one field over, and the row's own range max would not have
    /// caught it: `EchoelValueField` clamps on WRITE, never on display.
    ///
    /// ⚠️ Consequence to state rather than hide: the first edit of this row WRITES the value,
    /// so an unspecified patch becomes an explicit one. That is what makes an explicit mono `1`
    /// reachable at all — `apply` honours an explicit 1 and cannot honour a nil.
    private var unisonVoicesBinding: Binding<Float> {
        Binding(get: { Float(Swift.min(currentPatch.unisonVoices ?? 2,
                                       EchoelPolyDDSP.maxUnison)) },
                // `isFinite` is not defensive decoration: `EchoelValueField` clamps with
                // `min(max(raw, lo), hi)`, which passes NaN straight through (CLAUDE.md's own
                // NaN law), and `Int(Float.nan.rounded())` is a hard TRAP, not a bad value.
                set: { currentPatch.unisonVoices = $0.isFinite
                        ? Swift.max(1, Int($0.rounded()))
                        : currentPatch.unisonVoices })
    }

    /// Same rule as `unisonVoicesBinding`: the engine's own fallback is 7¢, not 0. No clamp on
    /// read — `EchoelDDSP` clamps detune to 0…50, which is exactly the row's range, so no
    /// stored value can display outside it.
    private var unisonDetuneBinding: Binding<Float> {
        Binding(get: { currentPatch.unisonDetuneCents ?? 7 },
                set: { currentPatch.unisonDetuneCents = $0.isFinite ? Swift.max(0, $0) : 0 })
    }

    /// #286 — the LAST field that only `PatchEditorView` could reach, and the reason that
    /// doorless file could not be deleted. This row is what unblocked it; the file is gone
    /// (#132 Slice 6), so this is now the only hand-editable door to `outputLevel`.
    ///
    /// ⭐ WHY THE OBJECTION THAT HELD THIS BACK DOES NOT HOLD. The note above `soundPanel`'s
    /// declaration said a manual trim "sits against `loudnessNormalized()`'s auto-calibration",
    /// so porting it was a founder call. Read the two together and they do not collide:
    /// `loudnessNormalized()` is applied EXACTLY ONCE, building the `static let factory` roster
    /// at type-init, and nothing re-runs it over a patch a user has touched. It sets the
    /// STARTING point; this row trims from there. `SynthPatch.outputLevel`'s own doc has said
    /// so since the field shipped — "The factory patches auto-calibrate this …; users can trim
    /// it in the editor" — quoting a founder ask ("Level pro Instrument") that asked for this
    /// control by name. What was lost in 2026-07-25 was its DOOR, not its mandate.
    /// #196 (per-role output gain) is a different stage in series — patch level, then role
    /// gain, then master — not a competing writer of this field.
    ///
    /// The fallback mirrors the engine exactly: nil means "no trim stored", and
    /// `SynthPatch.level` un-boxes it to 1.0 on the way to `resolved()` — so a patch without
    /// the field sounds at unity and the row must read 1.00. ⛔ The first version justified that
    /// with "a genre or library patch (none of which set the field)", and the LIBRARY half is
    /// false: the library is `SynthPatch.factory + user patches`, and every factory patch sets
    /// `outputLevel` via `loudnessNormalized()`. Only the genre half holds. The fallback is
    /// about the NIL case; who else writes the field is beside the point, and saying otherwise
    /// invites the "second writer found → this guard must be stale" read that the ⛔ block above
    /// `soundPanel` exists to stop.
    ///
    /// The stored values that DO exist are enclosed: factory patches carry 0.45…1.4, inside the
    /// row's 0.3…1.5. So no shipped patch can display a number outside its own control — the
    /// defect `unisonVoicesBinding` exists to prevent one field over. No READ clamp is needed
    /// here, and the difference from that case is worth naming: there the ENGINE clamped
    /// narrower than storage (`maxUnison` 3 vs a stored 4). Here the engine's bound is
    /// `EchoelDDSP.masterGainRange` (0…4), far WIDER than the row, so nothing can be shown that
    /// is not also played.
    ///
    /// The `isFinite` guard is the same non-decorative one as the unison rows:
    /// `EchoelValueField` clamps with `min(max(…))`, which passes NaN straight through, and
    /// this value is PERSISTED. `EchoelDDSP.patchOutputLevel` catches a NaN at the engine
    /// boundary (#295), but only after it has been written into the saved patch — falling back
    /// to unity keeps the poison out of the file, not just out of the render.
    private var outputLevelBinding: Binding<Float> {
        Binding(get: { currentPatch.outputLevel ?? 1.0 },
                set: { currentPatch.outputLevel = $0.isFinite ? $0 : 1.0 })
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

    /// #320 — THE DOOR TO `SoundPrompt`, a finished "word → sound" capability that had ZERO
    /// production callers and a file header claiming an editor that called it.
    ///
    /// Text, not a number, so a plain `TextField` is correct — the `EchoelValueField` law is
    /// explicitly about NUMERIC parameters (the same reasoning as the manual-place field in the
    /// Session panel, and as the `Shape` / `Noise colour` pickers in the Tone group).
    ///
    /// ⭐ WHY THIS IS A ROW AND NOT A SHEET. `EchoelStudioView.body` carries 14 presentation
    /// modifiers and sits at the SwiftUI metadata-decoder limit (the 10.76.34 black screen).
    /// A prompt box needs no modal: it edits the patch every other row in this panel already
    /// edits, so it belongs beside them.
    ///
    /// ⭐ A LEAF, AND THAT IS THE WHOLE POINT — see `SoundPromptRow`'s own header. The first
    /// version of this slice put the `@State` text on `EchoelStudioView`, which re-evaluates
    /// this ~500-line body (14 presentation modifiers, four `AnyView` branches) on EVERY
    /// KEYSTROKE. `menuPanelHost`'s rule says it plainly: *"build it through `panel(...)`, or
    /// keep every live read inside a leaf `View` struct."* Owning the text one level down means
    /// `EchoelStudioView` holds no per-keystroke state at all.
    private var promptRow: some View {
        SoundPromptRow(canUndo: patchBeforePrompt != nil,
                       onShape: { applySoundPrompt($0) },
                       onUndo: { undoSoundPrompt() })
    }

    /// Shape the CURRENT patch by a typed description, then push it to the voice.
    ///
    /// ⚠️ THREE CONSEQUENCES NAMED RATHER THAN HIDDEN.
    /// 1. `applySoundLive()`, NOT `applyArticulation()`. The Swell↔Strike macro WRITES
    ///    attack/decay/sustain/release; calling it here would erase exactly what "plucky" or
    ///    "pad" just set. So after a prompt that touched the envelope, that macro's displayed
    ///    value no longer describes the envelope — the same desync that hand-editing the
    ///    Attack row has always produced (the rows are documented as "editable for
    ///    fine-tuning"). Touching the macro again overwrites, deliberately.
    /// 2. `presetIndex` is left alone, exactly as `randomizeButton` leaves it. The persisted key
    ///    has exactly ONE read in this file — `.onAppear`, where it chooses the starting patch —
    ///    so writing it here would change nothing NOW and only alter what the next appearance
    ///    restores. Neither value restores the prompted sound (`currentPatch` is not persisted),
    ///    so clearing it would trade "you come back to the factory sound you started from" for
    ///    "you come back to the genre patch" — no gain, one more moving part. "Save as new
    ///    sound…" is how a prompted timbre is actually kept.
    /// 3. The `patchBeforePrompt` snapshot is taken per APPLICATION, so Undo is exactly one
    ///    step. Deliberately not a stack: a deeper history would have to be invalidated by the
    ///    seven other places that assign `currentPatch` wholesale, and an undo that silently
    ///    points at a patch from before a preset load is worse than no undo.
    ///
    /// ⛔ VALIDITY IS NOT AUDIBILITY, and reading `SoundPrompt.clamp` as a safety net was my
    /// mistake in the first version of this slice. `apply` is RELATIVE — it shifts the patch it
    /// is given — and the chips invite repetition. "deep" multiplies `filterCutoff` by 0.70,
    /// "dark" by 0.60, so the shipped chip "deep dark drone" multiplies it by **0.42 per tap**:
    /// from 2000 Hz that is 840 → 353 → 148 → 62 → 26 → the core's 20 Hz floor. Six taps of one
    /// chip and the instrument is inaudible with `brightness` pinned at 0. `clamp` guarantees a
    /// VALID value, never an AUDIBLE one — precisely the confusion behind this repo's shipped
    /// permanent-silence bugs. Hence a musical floor HERE rather than in the pure core: the
    /// core's 20 Hz/18 kHz must keep agreeing with the engine's domain (`FilterCutoffClampTests`
    /// pins that), while this floor is a property of the DOOR — a control a player can hold down
    /// must not be able to walk the sound out of earshot. Not unit-tested, because it lives in a
    /// private method of a `View`; said plainly rather than implied.
    private func applySoundPrompt(_ text: String) {
        guard !SoundPrompt.recognizedTerms(in: text).isEmpty else { return }
        let previous = currentPatch
        var shaped = SoundPrompt.apply(text, to: currentPatch)
        shaped.filterCutoff = Swift.max(shaped.filterCutoff, Self.promptCutoffFloor)
        shaped.brightness = Swift.max(shaped.brightness, Self.promptBrightnessFloor)
        currentPatch = shaped
        patchBeforePrompt = previous
        applySoundLive()
    }

    /// One step back. Cheap insurance rather than a feature: without it the only ways out of an
    /// over-shaped sound are Randomize and re-picking a character, neither of which reads as
    /// "give me my sound back".
    private func undoSoundPrompt() {
        guard let previous = patchBeforePrompt else { return }
        currentPatch = previous
        patchBeforePrompt = nil
        applySoundLive()
    }

    /// The musical floor the prompt path may not push past — see `applySoundPrompt`. 120 Hz is
    /// very dark and still clearly present on a phone speaker; 0.05 keeps `brightness` off the
    /// hard zero that reads as "broken" rather than "dark".
    private static let promptCutoffFloor: Float = 120
    private static let promptBrightnessFloor: Float = 0.05

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
                .onChange(of: delaySync) { _, _ in
                    // Reaching into this picker IS a request for delay, so arm it here —
                    // this row has no enable of its own, and a division that silently did
                    // nothing on a dry character would just be the lying control from
                    // `applyDelaySync` moved one row over. The enable belongs on the
                    // GESTURE; the automatic re-stamps (applyFX, re-seed) must not touch
                    // it. See `applyDelaySync(bpm:)`.
                    //
                    // Over the SAME inventory the time write uses, not just `synth`: arming one
                    // chain and timing both would give the Field a delay time it cannot hear
                    // and the generated take a room the played notes do not share — half of
                    // #240 fixed is a new inconsistency, not a smaller one.
                    for chain in characterFXChains { chain.delayEnabled = true }
                    applyDelaySync(bpm: currentTempo)
                }
                .accessibilityLabel("Delay note value")
            }
            // Full control: open every stage (filter, delay, chorus, flanger,
            // phaser, tremolo, compressor, limiter) with all parameters exposed.
            // NOT "as sliders" — the app has no raw `Slider`: numeric parameters are
            // `EchoelValueField`s, and a parameter whose values have NAMES is a picker
            // (filter mode, delay mode, and since 2026-07-29 the two harmony intervals).
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

    /// Every FX chain the chosen character and delay division must reach — the ONE inventory,
    /// so a knob can never land on some of the chains and not the others (#240).
    ///
    /// Before this existed, `applyFX()` listed two chains inline and `applyDelaySync(bpm:)`
    /// listed one, so the composer's synth and the Field agreed on WHETHER delay was on and
    /// disagreed on its TIME: the division picker moved the room for the generated take and
    /// left the played notes echoing at whatever the character had stamped. Two lists that
    /// must agree are one list.
    ///
    /// ⚠️ TWO SOUNDING CHAINS ARE DELIBERATELY NOT HERE, and the difference between them
    /// matters:
    ///  • `leadSynth.fxChain` IS live — `PolySynthVoice.fxEnabled` defaults to `true` and its
    ///    render block processes the chain — but nothing has ever configured it, so the lead
    ///    plays through the chain's DEFAULTS: saturation and the safety limiter only (both
    ///    default on, deliberately, "so every take has body"), no character, no delay time.
    ///    Not "dry" — an earlier draft of this comment said dry, which is wrong and would have
    ///    sent the next reader looking for a bypassed chain. Adding it here would make the lead
    ///    suddenly WET in every genre. That is an audible PRODUCT change, not a bug fix, and it would
    ///    land in the middle of the founder's pending ear-check on the five newly-dry
    ///    characters where they could not attribute what they heard. Tracked separately.
    ///  • `bioVoice.fxChain` is genuinely dead: nothing in `Sources/` calls
    ///    `BioReactiveSynthVoice.setFXEnabled`, so its chain never runs (its own doc says so).
    ///    Configuring it would be writing to a chain that produces no sound.
    ///
    /// If a new SOUNDING voice with its own chain is added, it belongs here in the same edit —
    /// same rule, and same lack of type-system enforcement, as `panicAllNotesOff`'s inventory.
    private var characterFXChains: [EchoelFXChain] {
        // `compactMap` over the optionals rather than pre-filtering, so the literal reads as
        // the inventory it is.
        [synth.fxChain, touchSynth?.fxChain].compactMap { $0 }
    }

    /// Stamp the chosen effect character on every live FX chain (independent of genre).
    private func applyFX() {
        for chain in characterFXChains {
            fxCharacter.apply(to: chain, bpm: currentTempo, genre: style)
        }
        applyDelaySync(bpm: currentTempo)
    }

    /// Re-apply the user's tempo-synced delay note value on top of the genre/character
    /// FX (which also set delay time), so the chosen division is never clobbered.
    ///
    /// ⛔ IT SETS THE TIME AND NOTHING ELSE. It used to end with
    /// `synth.fxChain.delayEnabled = true`, one line past what its own first sentence
    /// promised, and that line made two controls lie:
    ///
    ///  1. **"Clean (dry) — no effects"** was never dry. `FXCharacter.clean`'s preset says
    ///     `delayEnabled: false` under the comment *"Everything off — a dry reset"*
    ///     (`GenreFX.swift`), `applyFX()` stamps that preset, and then called this function
    ///     immediately after, which switched the delay straight back on. FIVE of the twelve
    ///     characters were affected: `.clean`, `.telephone` and `.vinyl` say
    ///     `delayEnabled: false` outright; `.harmonizer` and `.room` get it from
    ///     `GenreFXPreset.init`'s default by omitting the parameter. (NOT the genre presets
    ///     — every `MusicStyle.fxPreset` enables delay, pinned by `GenreFXTests`. An earlier
    ///     draft of this comment said "every genre preset that ships with delay off", which
    ///     described a set that does not exist.)
    ///  2. **The Delay switch in the "All parameters" panel could not stay off.** Turning it
    ///     off writes `chain.delayEnabled = false` (`EchoelFXView`), and the next
    ///     `applyFX()` / re-seed re-enabled it — the switch flipping itself back with no
    ///     input from the user.
    ///
    /// THE RULE: an AUTOMATIC re-stamp may set the delay time, never the enable. A direct
    /// user GESTURE may do both — the Effects panel's delay-division picker arms the effect
    /// in its own `onChange`, because that row carries no enable of its own and a division
    /// that silently did nothing would be the same lying control one row over.
    ///
    /// Two honest limits on that rule, so it is not read as absolute:
    ///  • `FXBioModulator` still force-enables the delay when a bio route targets delay mix
    ///    or feedback. That is a second automatic writer, out of scope here.
    ///  • It used to write ONLY `synth.fxChain` while `applyFX()` stamped the character on the
    ///    Field chain as well — so the two agreed on WHETHER delay was on and disagreed on its
    ///    TIME. That was #240, and it is fixed by both reading the one `characterFXChains`
    ///    inventory rather than by adding a second line here.
    private func applyDelaySync(bpm: Double) {
        let seconds = delaySync.clampedSeconds(bpm: bpm, in: 0.001...2.0)
        for chain in characterFXChains { chain.delay.timeSeconds = seconds }
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

    /// Per-genre MIX GLUE × the user's per-part MIXER level, applied to one bar of the
    /// composer's RAW output. Genre glue nudges relative role levels so each genre sits
    /// right (lead forward in synth genres, bass firmer in dub/heavy, pad back in dense
    /// takes); the user's fader then trims on top. A pure velocity scale at the one point
    /// all notes exist as an array — no audio-thread change.
    ///
    /// ONE copy for both paths: the primary take and the secondary lanes carried two
    /// identical inline versions of this map until #174, and a fix to one would have left
    /// the other on the old law. `genre` is a parameter because a secondary lane composes
    /// in its own `genreOverride`.
    private func mixGlued(_ raw: [Note], genre: MusicStyle) -> [Note] {
        let mix = genre.mixLevels
        return raw.map { n in
            var m = n
            let genreF: Float
            switch n.role {
            case .bass:    genreF = mix.bass
            case .lead:    genreF = mix.lead
            case .harmony: genreF = mix.harmony
            }
            m.velocity = MixerStore.mixedVelocity(n.velocity, genre: genreF,
                                                  user: mixer.level(for: n.role))
            return m
        }
    }

    /// Re-bake the take that already exists at the CURRENT mixer levels — without
    /// composing anything (#174).
    ///
    /// A fader is a level control, not a compositional one, and until now it was both.
    /// While playing, `mixBinding` called `recomposeIfRunning()`, and `generate()` builds
    /// its input with `advanceEvolution: true` — so every touch of a Mix fader handed the
    /// listener a DIFFERENT piece while they were trying to balance the one they had.
    /// While stopped, the opposite failure: nothing re-applied at all, so the stored take
    /// and everything derived from it (the roll clip, `exportMIDI()`) kept whatever level
    /// was baked at compose time. A fader pulled to 0 exported silence, permanently.
    ///
    /// The level stays baked into VELOCITY on purpose. `PianoRollView` reads velocity as
    /// "is this note audible" (the two `audibleVelocityFloor` comparisons — the felt-sub
    /// decision and the `MusicalFrame` publish) and as the note-on amplitude itself, so
    /// moving the user term to trigger time
    /// would light the visual, the light output and the felt sub for notes nobody can
    /// hear. That is exactly #205, and re-deriving from `lastRawTake` avoids it without
    /// re-opening it.
    private func rebalanceTake() {
        // NO RAW TAKE = NO RE-BAKE, so fall back to the OLD behaviour rather than doing
        // nothing. `lastRawTake` is `@State`: nil until this app session's first
        // generate(), and `open(_:)` restores an already-baked take via
        // `pianoRoll.load(p.notes)` without it. Returning here would have made the fader a
        // lying control on every opened project — the number moves, nothing else does
        // (#164's class) — and would have been a REGRESSION, since `recomposeIfRunning()`
        // at least applied the level, if at the price of a new take. Persisting the raw
        // bars into `Project` is the real answer and is its own task; until then the
        // fader always does something.
        guard let take = lastRawTake, !take.bars.isEmpty else { recomposeIfRunning(); return }
        // `take.genre`, NOT `style`: the take must be re-glued with the genre it was
        // COMPOSED in, even if the user has since picked another one whose recompose has
        // not landed yet (see `lastRawTake`).
        let bars = take.bars.map { mixGlued($0, genre: take.genre) }
        // `rebakeArrangement`, NOT `loadArrangement`: the latter routes a SINGLE-bar loop
        // through `load(_:)`, which begins with `allNotesOff()`, so a fader settle would
        // chop the sounding notes. (The loop default is EIGHT bars — `StudioDefaultKeys`
        // — so that is the edge case, not the common one; an earlier version of this
        // comment claimed the opposite and would have sent the next reader to the wrong
        // branch.) Playing → staged at the bar boundary, no cut; stopped → the ordinary
        // load path.
        pianoRoll.rebakeArrangement(bars, playing: running && beatPlayer.pattern.isPlaying)
        // `createIfNeeded: false` — a level change must never invent a clip; it only
        // rewrites the composer-owned one if it is already there.
        syncPrimaryRollClip(bars: bars, createIfNeeded: false)
        writeLaneTakes(lastLaneRaw)
        if !running { applySoundLive() }
    }

    /// Coalesce fader movement into one re-bake.
    ///
    /// 350 ms, and the number is set by the EXPENSIVE half, not the audible one. A
    /// re-bake reaches `ClipStore.updateComposerMelody` → `persist()` → `AppGroupStore`,
    /// i.e. a pretty-printed JSON encode of the whole clip grid plus an atomic
    /// file-protected write — synchronously, on the actor that also hosts this view's
    /// `.menu` Pickers. At 120 ms a stepwise drag could fire that ~8×/s, which is the
    /// main-actor-starvation class that froze menus in 10.76.48. Nothing is LOST by
    /// waiting: the roll swaps the new levels in at the next bar boundary regardless, and
    /// a bar is ~2 s at any usable tempo. Still not free — if a device log ever shows a
    /// hitch while dragging a Mix fader, the next step is to split the clip write onto its
    /// own longer settle and keep only the roll on this one.
    ///
    /// DELIBERATELY NOT cancelled by `stopEverything` / `pausePlaybackKeepingSession`,
    /// unlike `regenTask`. Those cancel WORK GENERATORS — a pending re-bake starts no
    /// clock and arms no driver; it only makes the stopped take (and its MIDI export)
    /// agree with the fader the user just moved, which is the whole point of #174. A
    /// fader nudged just before Stop must not silently leave the old level baked in.
    private func scheduleRebalance() {
        rebalanceTask?.cancel()
        rebalanceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            // No `rebalanceTask = nil` here on purpose: this line is reachable only when
            // the task was NOT cancelled, i.e. only when no successor handle has been
            // stored, so it could never clear a live one — it would buy nothing and cost
            // one more `@State` write (one more root invalidation) per re-bake. The
            // sibling handles are nil'd from the cancel-all blocks, not from inside
            // themselves.
            rebalanceTake()
        }
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
        //
        // #272 — AND THE TITLE HAD THE SAME DEFECT ONE LEVEL UP. It read "Export" while the
        // panel holds Save, Open, Record and keep-last as well, so the founder reported
        // "Session speichern und Loops aufnehmen fehlt" about four controls that were right
        // here. Save leads now because that is the word he searched for; the subtitle names
        // opening too, since a save nobody can reload is not a save.
        panel("Save & Export",
              "Save and open a session · record the loop as WAV · MIDI for your DAW · keep what just played",
              isExpanded: $showExport) {
        VStack(spacing: 10) {
            if !hasComposed {
                // The export/keep/save buttons below are disabled until there's a take —
                // say WHY, so a first-run user doesn't read the greyed buttons as broken.
                // Name the REAL button (audit 2026-07-09: no "Generate" exists — first-run
                // users hunted for it and read the greyed buttons as broken). Video
                // recording lives in the floating visual window, not here.
                // #272: named only exporting, inside a panel that now promises saving and
                // recording as well — the one first-run string here, and it left out both
                // words the founder searched for.
                Text("Start with the pulse button (next to Play) first — then you can record the loop, save the session, or export a WAV or MIDI file.")
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
            if let reason = exportFailure {
                // WHY A PLAIN LINE AND NOT AN ALERT (#216). The body's presentation chain
                // is at 14 modifiers, close under the ceiling this app has already crashed
                // THROUGH (black screen, 10.76.34 — the chain was fine at 10.76.21 and three
                // additions tipped it; 14 is the current count, not a measured limit). A
                // 15th `.alert` is exactly what
                // CLAUDE.md forbids. This costs zero modifiers and zero state, sits where
                // the user is already looking, and mirrors the `composerClipGridFull`
                // warning right above. It clears on the next export ATTEMPT and nothing
                // else — `LoopExporter` lives for the app's lifetime, so a user who fails
                // once and never exports again keeps the line for the session. No timer,
                // nothing to dismiss.
                // Suffix stays neutral rather than "tap Record to try again": one of the
                // six reasons is the too-long message, which already ends with its own
                // instruction ("…or use Record instead"). "Nothing was saved" is the one
                // thing true of all six and the one thing the user actually needs.
                //
                // Joined with a full stop, NOT an em-dash: two of the reasons already carry
                // an em-dash, and " — nothing was saved" made those a run-on with three
                // dashes in one line. Review caught it by reading all six rendered strings.
                Text("\(reason). Nothing was saved.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Export failed. \(reason). Nothing was saved.")
            }
            // ONE button, two jobs: start the take, and abort it — founder 2026-07-28
            // ("wichtig das man die Aufnahme dann auch abbrechen kann, wenn man sich
            // verspielt hat"). Deliberately NOT a second button next to it: the abort is
            // only meaningful while this exact take runs, and a permanent Cancel that is
            // dead 99 % of the time is more clutter than help. Once the capture ends it
            // stops offering the abort — during the rendering seconds it reads "Writing
            // .wav…", disabled, because that pass cannot be interrupted (see
            // `LoopExporter.isCancellable`).
            Button {
                if exporter.isCancellable { exporter.cancel() } else { Task { await exportWav() } }
            } label: {
                Label(exportLabel, systemImage: exportIcon)
                    .font(EchoelTheme.font(15, .semibold)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    // Website CI primary action (off-white fill, black label).
                    // The fill must track `.disabled` EXACTLY — same law the keep-last
                    // button already carries. `!hasComposed` was missing here, so a dead
                    // button sat at full brightness under an inviting "Record 8 bars" label.
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(isRecordButtonInert ? EchoelTheme.dim : EchoelTheme.text))
            }
            .buttonStyle(.plain)
            .disabled(isRecordButtonInert)
            .accessibilityHint(exporter.isCancellable
                ? "Stops this take and discards it. Nothing is saved."
                : "Records one loop and exports a WAV to share")

            KeepLastLoopButton(pattern: beatPlayer.pattern, bars: loopBars,
                               isExporting: isExporting, hasComposed: hasComposed,
                               busyLabel: busyStatusLabel) { Task { await keepLastLoop() } }

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
        }   // panel("Save & Export")
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
    /// ONE expression for "this button does nothing if you tap it", so the dim state and
    /// `.disabled` cannot drift apart. Busy-but-abortable is NOT inert — that is the whole
    /// point of the Cancel state.
    private var isRecordButtonInert: Bool {
        (isExporting && !exporter.isCancellable) || !hasComposed
    }
    private var exportLabel: String {
        switch exporter.status {
        // While the take runs, the button IS the abort — so it must say so. "Recording
        // loop…" read as a progress notice, which is exactly why nobody would think to
        // tap it after a fumbled bar.
        case .capturing: return exporter.isCancellable ? "Stop and discard this take"
                                                       : "Recording loop…"
        case .rendering: return "Writing .wav…"
        default:         return "Record \(loopBars.label) → send"
        }
    }
    private var exportIcon: String {
        if exporter.isCancellable { return "stop.circle" }
        return isExporting ? "hourglass" : "square.and.arrow.up"
    }
    /// What the OTHER export buttons show while this one is busy — status only, never the
    /// abort wording. `exportLabel` now doubles as the Record button's ACTION text, and
    /// handing that to a disabled neighbour would make it announce an action it cannot
    /// perform ("Stop and discard this take" on the keep-last button).
    private var busyStatusLabel: String {
        switch exporter.status {
        case .capturing: return "Recording loop…"
        case .rendering: return "Writing .wav…"
        default:         return ""
        }
    }
    /// The reason the last export attempt failed, or nil. Deliberately NOT folded into
    /// `busyStatusLabel`: that one answers "what is the OTHER button doing while this one
    /// is busy", and a failure is not a busy state — putting it there would have announced
    /// a dead attempt on a neighbouring control instead of at the button that ran it.
    private var exportFailure: String? {
        if case .failed(let reason) = exporter.status { return reason }
        return nil
    }

    // MARK: - Camera pulse readout
    //
    // Extracted to `PulseMeasurementView` (its own `View` struct) so its ~10 Hz
    // `cameraRPPG` reads no longer register the root `body` as an observer — that 10 Hz
    // invalidation was tearing down open Tonart/Genre `.menu` Pickers while playing.

    // MARK: - Open projects sheet

    /// #285 — THE AUTOSAVE HAD TAKEN OVER THE TOP OF THE LIBRARY. `ProjectStore` is
    /// newest-first by contract (`save` does `insert(at: 0)`, `init` sorts by `savedAt`), and
    /// since #273 the app writes one on the way out. So the one row the user never made sat
    /// above the take they did make, and got a fresh timestamp on every departure — it could
    /// not be pushed back down by anything short of saving again.
    ///
    /// ⛔ NOT "every time the app goes to the background", which is what this comment said
    /// first and is exactly the kind of overclaim that gets planned from later. `autosaveTake()`
    /// is guarded by `hasComposed, !pianoRoll.notes.isEmpty` — with nothing composed, no
    /// autosave is written at all. The guard is what makes the FIRST section of this list
    /// non-empty for a user who has only ever saved by hand; it does not change the ordering
    /// problem for anyone who has composed, which is everyone this fix is for.
    ///
    /// The fix is in the LIBRARY VIEW, not the store: the ordering is right for a store (a
    /// recovery slot IS the newest thing on disk) and wrong only for a list a human reads. The
    /// autosave now has its own section, below the user's own saves, named so it reads as a
    /// safety net rather than a document. Nothing about when it is written changed.
    ///
    /// ⚠️ EACH SECTION DELETES OUT OF ITS OWN ARRAY. The single list before this could map its
    /// `IndexSet` straight into `projects.projects` because the ForEach covered the whole
    /// array; two ForEaches over two slices cannot — an index from the lower section would
    /// address the wrong project. That is the one way this split can silently destroy data, so
    /// it is why the two arrays are computed once, above, and each handler indexes only its own.
    private var openSheet: some View {
        let saved = projects.projects.filter { $0.id != Project.autosaveSlotID }
        let autosaved = projects.projects.filter { $0.id == Project.autosaveSlotID }
        return NavigationStack {
            List {
                if projects.projects.isEmpty {
                    Text("No saved projects yet.").foregroundStyle(EchoelTheme.dim)
                }
                // Guarded like the autosave section below it: a `Section` around an empty
                // `ForEach` still draws its own inset block, so on a fresh install — where
                // there is no user save yet but the first app switch has already written an
                // autosave — an empty grey band would sit above the only row in the list.
                if !saved.isEmpty {
                    Section {
                        ForEach(saved) { p in projectRow(p) }
                            .onDelete { idx in
                                idx.map { saved[$0].id }.forEach { projects.delete(id: $0) }
                            }
                    }
                }
                if !autosaved.isEmpty {
                    Section {
                        ForEach(autosaved) { p in projectRow(p) }
                            .onDelete { idx in
                                idx.map { autosaved[$0].id }.forEach { projects.delete(id: $0) }
                            }
                    } header: {
                        Text("Autosave").foregroundStyle(EchoelTheme.dim)
                    } footer: {
                        Text("Kept automatically when you leave the app. Overwritten each time.")
                            .foregroundStyle(EchoelTheme.dim)
                    }
                }
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

    /// One library row. Extracted when #285 split the list in two so the two sections cannot
    /// drift apart — a row that looked different in the autosave section would read as a
    /// different KIND of thing, and it is the same project.
    @ViewBuilder
    private func projectRow(_ p: Project) -> some View {
        HStack(spacing: 8) {
            Button { open(p); showOpen = false } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.callout.weight(.medium)).foregroundStyle(EchoelTheme.text)
                    Text("\(p.style.displayName) · \(p.key.shortName) · \(EchoelDecimalText.string(p.bpm, decimals: 0)) BPM")
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
    /// unusable during a take. (It was unreachable from 2026-07-26, when the Notes editor's
    /// door went, until 2026-07-29, when the transport bar's ■ became its producer — #234.
    /// It is now THE behaviour of the one chrome stop, not a parked design.)
    ///
    /// BE HONEST ABOUT WHAT THIS IS: "camera live, no music" is a NEW state, introduced here.
    /// An earlier version of this comment called it "the state the Bio panel's own arm already
    /// puts the app in" — false. The ONE reachable arm, the pill's long-press source picker,
    /// goes through `startBiofeedback()` when idle, i.e. a full take; the camera-only arms
    /// live in `BioSourceView`/`SessionView`, both doorless. (This sentence used to list
    /// `BioStripView`'s pulse start alongside the picker as a second reachable arm. #234
    /// removed it from the Bio panel, so it now survives only inside `BioSourceView` — the
    /// very view this same sentence calls doorless. Corrected because the conclusion survives
    /// and the evidence did not, which is the worse of the two ways to be stale.) So this is a
    /// product
    /// decision — and as of #234 it is a SHIPPED one, reachable by every user who presses ■
    /// during a take. Flagged to the founder rather than buried: if "■ should end everything"
    /// is what he wants, the change is one line in `TransportBar.toggle()`.
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
        // Releases EVERY voice, the roll included — `panicAllNotesOff` puts `pianoRoll` first
        // in its fan-out precisely because that one clears `active` and releases poly/lead/
        // sub/kind/MIDI. (The old comment here said the roll "already released its own notes
        // before stopping the clock", which was true only of the roll's OWN pause button —
        // the transport bar's ■ does not, and it is the only producer left. Relying on the
        // caller to have done it would have left notes ringing under a stopped clock.)
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
        /// A heart rate only counts as a MEASUREMENT when it is above zero.
        ///
        /// ⛔ THIS IS THE SAME TRAP `fin` DOES NOT CATCH, and it was live on device (log 2476,
        /// v10.79.359): camera rPPG reports `bpm=0` for the first ~13 s and again whenever it
        /// loses lock, and zero is FINITE — so `fin` waved it through as if the performer's heart
        /// had stopped. `heldCoh` above already applies exactly this `> 0` rule to coherence, and
        /// the comment on the `hrvNormalized` line below describes exactly this bug for HRV. Heart
        /// rate was the one field left unguarded, and it is the one that sets the TEMPO.
        ///
        /// What it cost, end to end: `BioComposer.tempo(for:)` computed
        /// `0·(1−calm) + 72·calm` = 0 at coherence 0, clamped up to its floor of 40, and
        /// `StudioCalculator.genreTempo(40, into: 44...66)` folded that to the genre's floor, 44.
        /// The device log reads `transport play (generate) tempo=44` — the app started every take
        /// as slow as the genre allows, and held it there for the whole settling window, because
        /// the `frame != nil` branch only keeps `pattern.tempo` when it is `>= 50`.
        /// It was not only tempo: `musicalState`'s `energy` maps 50…120 bpm, so a zero read as
        /// minimum cardiac drive and the composer built a lower-energy take to match.
        ///
        /// Deliberately `> 0` and not a plausibility floor like 30: zero is the SENTINEL the
        /// sources actually emit, `bodyTempoTrustworthy` already gates whether a reading may LOCK
        /// the tempo, and every downstream stage clamps. A second threshold here would be a second
        /// policy owner for the same question.
        func measured(_ v: Float?) -> Float? {
            guard let v, v.isFinite, v > 0 else { return nil }
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
            // `measured`, not the raw value — an unlocked rPPG's finite 0 is not a heart rate.
            // The fallback chain is deliberate: the last take's body first (so a momentary loss of
            // lock mid-session keeps the tempo the performer's own pulse set), then 70 as the
            // resting neutral for a body that has never been read. Both go through `measured` for
            // the same reason.
            heartRateBPM: fin(measured(frame?.heartRateBPM)
                                ?? measured(heldBody.map { Float($0.bpm) }), 70),
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
            suggestJourney: true,
            // #253 A3: nil (the stored default "") = the genre's own bass rhythm, byte-identical.
            // An unrecognised stored value also reads as nil, for the reason the key states.
            bassRhythm: RoleRhythm.Character(rawValue: bassRhythmRaw),
            padRhythm: RoleRhythm.Character(rawValue: padRhythmRaw)
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
        applyConcertPitch(session.a4Hz)
        applyTakeSound(currentPatch)
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
                // No body yet → the neutral RESTING pulse (70 bpm, set at the `Input`) mapped
                // through the genre's window. Note "~72" used to stand here as if it were the
                // TEMPO: it is the heart rate. On Contemplation (44…66) a 70 bpm pulse folds to
                // 66, and once the real pulse arrives at ~61 the convergence walks it down —
                // continuous, no jump. Before the `measured` guard above, this branch was
                // unreachable in practice anyway: a frame with `bpm=0` existed from the first
                // camera tick, so the app took the `frame != nil` branch with a zero body.
                tempo = bodySeed
            }
        }
        // Push the live musical context so the roll's per-tick MusicalFrame carries the
        // current key/scale/tempo/concert-pitch → renderers colour by the right key.
        pianoRoll.musicalA4Hz = session.a4Hz
        pianoRoll.musicalRootPitchClass = rootIndex
        pianoRoll.musicalScaleName = scale.rawValue
        pianoRoll.musicalTempoBPM = tempo
        // The ONE inventory (`characterFXChains`) — not `applyFX()`, because a re-seed stamps
        // at the JUST-DERIVED `tempo`, which is not yet `currentTempo`.
        for chain in characterFXChains {
            fxCharacter.apply(to: chain, bpm: tempo, genre: style)
        }
        applyDelaySync(bpm: tempo)   // keep the user's delay note value across re-seeds
        // LOOP-CONFORM ARRANGEMENT (1b, founder: "je nachdem wie groß der Loop umgestellt
        // ist"): build `loopBars` distinct bars that the roll cycles through — a different
        // bar each loop. Every bar shares the STRUCTURE seed (cohesive — "same piece
        // breathing") but uses a per-bar DETAIL seed (distinct), so a 4-bar loop really is
        // four bars, not one repeated. bar 0 = the take just composed. barCount 1 = classic.
        let barCount = max(1, loopBars.rawValue)
        var rawBars: [[Note]] = [composition.notes]
        if barCount > 1 {
            rawBars.reserveCapacity(barCount)
            for b in 1..<barCount {
                var barInput = input
                barInput.seed = evolvingSeed &+ UInt64(b)
                // Each bar of the loop sits one step further along the chord journey,
                // so a multi-bar Fläche moves through its progression WITHIN the loop
                // (a different held chord per bar), not just across evolves.
                barInput.progressionPhase = basePhase + b
                rawBars.append(BioComposer.compose(barInput).notes)
            }
        }
        // Keep the composer's OWN bars, paired with the genre they were composed in
        // (#174). Every downstream copy carries the mixer baked into its velocities, so
        // re-balancing has to start again from here — see `rebalanceTake()` for why the
        // level cannot simply move off velocity.
        lastRawTake = (genre: style, bars: rawBars)
        let bars = rawBars.map { mixGlued($0, genre: style) }
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
        // vMax + mix: the two numbers that decide the NEXT device log (#205 follow-up).
        // Device log 2472 showed `mfNotes=5 mfAmp=0.000 level=0.00` for a whole session
        // while this line reported ten notes and `rollMixGain=1.00` — and rollMixGain is
        // a RED HERRING in both directions: it is applied at trigger time and never
        // stored, so it cannot move the published amplitude at all. What CAN is the
        // mixer bake (`mixGlued` → `MixerStore.mixedVelocity`, no longer inline here), the
        // one multiplier in the whole chain with no floor under it: the composer clamps
        // every note to ≥ 0.05 and the genre term never goes below 0.85, so a published
        // 0.000 needs a USER fader below 0.0118 — on a 0.01-grid field that means 0.00
        // or 0.01, nothing else. `vMax` is the max velocity of the FINISHED bar 0, i.e.
        // after the bake. vMax≈0 ⇒ the bake did it, and `mix` names which fader. vMax
        // normal ⇒ the take left here healthy and something downstream publishes other
        // notes — a different investigation entirely. One line, four numbers, no new
        // call site and no new modifier.
        // Read `bars[0]`, NOT `composition.notes`: the latter is the composer's output
        // BEFORE `mixGlued` applies the mixer bake, and the composer's own clamp puts a
        // hard 0.05 floor under it — so it could never print 0.000 and would have been a
        // number that cannot answer the question it was added for.
        let vMax = bars.first?.map(\.velocity).max() ?? 0
        EchoelCrashLog.breadcrumb("generate[\(pendingGenerateReason)]: \(composition.notes.count) notes, playing=\(beatPlayer.pattern.isPlaying), rollMixGain=\(String(format: "%.2f", pianoRoll.mixGain)), vMax=\(String(format: "%.3f", vMax)), mix=\(String(format: "%.2f/%.2f/%.2f", mixer.bass, mixer.pad, mixer.lead))")
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
        // Clearing on the empty case matters: a lane whose override the user has REMOVED
        // must not keep being re-written from a take it no longer owns.
        guard !overrides.isEmpty else { lastLaneRaw = [:]; return }
        var raw: [UUID: (genre: MusicStyle, notes: [Note])] = [:]
        for (laneID, notes) in overrides {
            // THIS lane's genre (its override) so its roles balance like that style.
            raw[laneID] = (genre: doc.lanes.first(where: { $0.id == laneID })?.genreOverride ?? style,
                           notes: notes)
        }
        lastLaneRaw = raw
        // Pass the local, do NOT let this read `lastLaneRaw` back: SwiftUI `State`
        // set-then-get returns the OLD value inside a view update. Correct today only
        // because generate() never runs during body evaluation — a parameter is correct
        // unconditionally, and one refactor safer.
        writeLaneTakes(raw)
    }

    /// Bake the stored lane takes at the CURRENT mixer levels and write them into each
    /// lane's composer-owned clip. Split out of `applyLaneOverrides` (#174) so a fader
    /// move re-bakes the SAME lane notes instead of leaving the secondary lanes on
    /// whatever level happened to be set when they were composed — otherwise the two
    /// paths would end up obeying two different laws, which is the failure mode this
    /// whole change exists to remove.
    private func writeLaneTakes(_ takes: [UUID: (genre: MusicStyle, notes: [Note])]) {
        guard !takes.isEmpty else { return }
        // The generative instrument cycles bars 0..<loopBars — the active window.
        let windowTicks = max(1, loopBars.rawValue) * TimelineTime.ticksPerBar
        for (laneID, take) in takes {
            let glued = mixGlued(take.notes, genre: take.genre)
            var wrote = false
            for region in timelineStore.document.regions(in: laneID)
            where region.startTick < windowTicks {
                // Ownership guard lives in the store — a user clip returns false.
                if clipStore.updateComposerMelody(id: region.clipID, notes: glued) {
                    wrote = true
                }
            }
            if wrote {
                log.log(.info, category: .audio,
                        "Lane override take: \(glued.count) notes → lane \(laneID.uuidString.prefix(8)) (\(take.genre.rawValue))")
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
        applyTakeSound(currentPatch)
    }

    /// The ONE place the take voice is handed a patch (#253 A6).
    ///
    /// ⛔ WHY A HELPER AND NOT THREE CALL SITES. Before this there were three
    /// `synth.apply(…)` + `syncTouchSound()` pairs — here, in `generate()` and on the
    /// open-project path — and A6 had to reach all three or the rhythm's tone would follow
    /// the Sound panel but not a generated or a re-opened take. That is #240 exactly (the
    /// delay that reached one of two chains because two call sites each did their own
    /// stamping), and the fix is the same one: one inventory, not N sites.
    ///
    /// The trim is applied to a LOCAL COPY. `currentPatch` — what every control in the Sound
    /// panel reads — is never written, so the player always sees the patch they CHOSE rather
    /// than the patch plus an invisible offset, and the multiply can never compound across
    /// pushes (see `RoleRhythm.TimbreTrim`'s own warning).
    ///
    /// ⚠️ NAME THE TRADEOFF RATHER THAN CALLING IT AN INVARIANT: once a character IS chosen, the
    /// Brightness / Cutoff / Attack / Release rows display a value up to 12 % / 22 % away from
    /// what the voice was handed. That is the mirror image of the rule `usesEvolve` and
    /// `accentIsSubtle` exist to enforce (a dial that does nothing is worse than a missing one) —
    /// here a dial's READOUT stops matching the engine, and today the only disclosure is the Pad
    /// rhythm row's accessibility hint, which a sighted non-AT user never sees. It is bounded and
    /// small, and writing the trim back would compound; but "every number in the Sound panel
    /// stays honest" — which is how the shipping commit put it — is the wrong way round. If the
    /// founder wants the readout to follow the sound, the fix is a visible per-row offset badge,
    /// not writing into `currentPatch`.
    ///
    /// ⚠️ The touch surface is deliberately NOT trimmed here. `syncTouchSound()` follows
    /// either `currentPatch` or a dedicated touch patch, and the Field has its OWN rhythm
    /// character (`fieldArpCharacter`) — trimming it with the PAD's character would be the
    /// wrong character on the wrong voice. Giving the Field its own trim is a Field slice
    /// (#222/#224), not this one.
    private func applyTakeSound(_ patch: SynthPatch) {
        let trim = takeRhythmCharacter.map(RoleRhythm.timbreTrim(for:))
            ?? RoleRhythm.TimbreTrim.neutral
        synth.apply(trim.trimmed(patch))
        syncTouchSound()
    }

    /// The character whose tone the take voice follows, or `nil`-as-neutral.
    ///
    /// ⛔ NEUTRAL WHEN NOTHING IS CHOSEN, and that is load-bearing: `StudioDefaultKeys.padRhythm`
    /// defaults to `""` meaning "the genre's own grid", and a founder who has never opened the
    /// Pad rhythm row must hear the genre's patch EXACTLY as before this slice. `TimbreTrim.neutral`
    /// makes `trimmed(_:)` an identity, asserted in `RoleTimbreTrimTests`.
    ///
    /// It reads the PAD character rather than the bass one because `synth` is the polyphonic
    /// chord voice — the pad IS this patch's sound. The bass has its own voice and its own
    /// character, and coupling one to the other's tone would be a lie in the UI.
    private var takeRhythmCharacter: RoleRhythm.Character? {
        RoleRhythm.Character(rawValue: padRhythmRaw)
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
        // Clear the busy state so the button can never hang on "Recording…/Writing…" —
        // but NOT a failure. `reset()` stood here and erased `.failed` in this same
        // synchronous turn, so none of the exporter's six failure messages could ever
        // reach the screen (#216). `finishAttempt()` keeps that one status; `exportFailure`
        // and the warning line in `utilityRow` render it.
        exporter.finishAttempt()
    }

    /// Retroactive "keep that" — export the last few bars already heard, no replay.
    private func keepLastLoop() async {
        if let url = await exporter.exportRecentLoop(engine: audioEngine, beatPlayer: beatPlayer,
                                                     bars: loopBars.rawValue, targetLUFS: resolvedLUFS) {
            share = ExportedFile(url: renamedForShare(url))
        }
        exporter.finishAttempt()   // keeps `.failed` readable — see `exportWav` (#216)
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

    /// #273 — write the live take into the ONE reserved library slot as the app leaves the
    /// foreground. Deliberately NOT a new store, a new file or a new timer: the same
    /// `currentProject()` the Save button builds, through the same `ProjectStore`, so an
    /// autosave and a manual save are byte-identical apart from their id and name.
    ///
    /// Three properties this depends on, all load-bearing:
    /// · `Project.autosaveSlotID` is FIXED, and `ProjectStore.save` matches by id — so this
    ///   replaces the previous autosave instead of adding a row per app switch, and it can
    ///   never land on a take the user named and saved (those carry random ids).
    /// · THE GUARD IS TWO CONDITIONS, and the second one was missing in the first cut.
    ///   `hasComposed` alone is NOT enough: it is set `true` unconditionally by `open()` and
    ///   is never set back to `false` anywhere, so opening a legacy take whose notes did not
    ///   survive the lossy decoder leaves it true over an EMPTY roll. The next departure then
    ///   wrote that empty take into the single slot and the good recovery point was gone —
    ///   with no undo, because there is only one slot. `exportMIDI()` already says the same
    ///   thing about `hasComposed` at its own empty-notes guard; I did not read it.
    ///   ⛔ That pointer first read "the Save button's own doc … sixty lines up". There is no
    ///   such doc — the Save button is a bare `Button` with `.disabled(!hasComposed)` and no
    ///   comment at all, so a reader following it would find nothing and conclude the
    ///   precedent was invented. The real one is in `exportMIDI`.
    /// · The name carries `autosaveNamePrefix`, because a row the user did not create has to
    ///   say so in the one place they will meet it, which is the Open list.
    ///   ⛔ The first version justified the guard with "…and would sit above the take the user
    ///   actually made". That reason is FALSE: the library is newest-first, so a NON-empty
    ///   autosave sits on top too, on every app switch. The ordering question is real and
    ///   separate (#285); the guard is about not storing a take that recalls nothing.
    ///
    /// It is a RECOVERY point, not a save: nothing here marks the take as saved, and the Save
    /// button still writes its own row. Deliberate — "the app already saved it" is a claim
    /// that would have to survive the founder deleting the autosave row.
    ///
    /// ⚠️ AND IT DOES NOT SURVIVE A CRASH, which the first version of this comment claimed it
    /// did. A crash delivers no scene-phase transition at all; what this covers is
    /// backgrounding, the app switcher, a call the user answers, and termination by the OS
    /// while suspended. A foreground crash still loses everything since the last departure.
    private func autosaveTake() {
        guard hasComposed, !pianoRoll.notes.isEmpty else { return }
        // Built from `currentProject()` rather than re-deriving the default name: the first
        // version duplicated `saveProject()`'s name expression verbatim, so a change there
        // would have silently drifted the autosave's name away from the manual save's.
        var take = currentProject()
        take.name = Project.autosaveNamePrefix + take.name
        take.id = Project.autosaveSlotID
        projects.save(take)
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
        applyConcertPitch(p.a4Hz)
        applyTakeSound(p.patch)
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
        // The FX room is one more thing that mirrors tempo, so it belongs on the SAME side of
        // that line — and it did not use to be. Both the character stamp and the delay division
        // ran earlier in this function on the RAW `p.bpm`, while `PatternEngine.setTempo` clamps
        // to its own tempo range: a saved take outside that range got tempo-synced delay and
        // character times computed from a tempo the app never actually plays at, wrong for the
        // whole session until something else re-stamped. Same rule the two lines above already
        // invoke — one authoritative number, every reader on it.
        for chain in characterFXChains {
            fxCharacter.apply(to: chain, bpm: loadedTempo, genre: openStyle)
        }
        // ⛔ AND THIS CALL WAS MISSING ENTIRELY — the same lying control on a third path. The
        // character stamp above sets a delay TIME; `delaySync` is `@State` and is NOT part of
        // the saved `Project`, so after opening a take the picker still displayed the session's
        // division while the chain held whatever the character had stamped. The re-seed path
        // already re-applied it; the open path did not. Restoring the SAVED division is a schema
        // change and stays out of this fix — making the chain match what the picker SHOWS is what
        // stops it lying.
        applyDelaySync(bpm: loadedTempo)
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
///
/// ⚠️ `spacing` EXISTS BECAUSE THE PORTRAIT PATH IS NOT A NO-OP. In one column this renders a
/// `VStack`, so its spacing REPLACES whatever rhythm the caller's container had. Wrapping a run
/// of `EchoelValueField` ROWS inside `EchoelPanel` without saying so would tighten them from the
/// panel's own 14 pt (`EchoelPanel.body`) to 10 — a visible change to the iPhone PORTRAIT
/// surface, which is the primary one, in exchange for nothing, because portrait does not reflow
/// at all. Pass the spacing the content already had.
///
/// ⛔ THE FIRST VERSION OF THIS PARAGRAPH NAMED THE WRONG CALLER AND STATED A RULE ITS OWN
/// EXAMPLE BREAKS. It said "the two original callers hold CARDS inside `EchoelPanel`, where 10 pt
/// is right". The two bare callers are `mixerPanel` and **`weatherRow`** — NOT `sessionPanel`,
/// which merely renders `weatherRow` and contains no grid at all; someone acting on that name
/// would have grepped `sessionPanel` and found nothing. And only `mixerPanel`'s grid sits
/// directly in `EchoelPanel`'s 14 pt stack: `weatherRow`'s sits in its own local
/// `VStack(alignment: .leading, spacing: 8)`. So NEITHER matched 10 by design. The honest reason
/// the default is 10 is narrower and sufficient: those two shipped at 10 and changing it would
/// re-space two panels nobody asked to change.
@MainActor
private struct AdaptiveCardGrid<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.dynamicTypeSize) private var typeSize
    private let spacing: CGFloat
    private let content: () -> Content

    init(spacing: CGFloat = 10, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    /// ⛔ ACCESSIBILITY SIZES GET ONE COLUMN, whatever the width. `EchoelValueField`'s value box
    /// is a HARD `.frame(width:)` driven by `@ScaledMetric(relativeTo: .body) = 150`, and it
    /// OVERFLOWS rather than clips (the field says so itself). `EchoelStudioView` is deliberately
    /// not Dynamic-Type-clamped and `StudioZoom` reaches `.accessibility5`, so at the top sizes
    /// that box alone wants more than half a landscape phone — two columns would draw over each
    /// other. Halving the available width is exactly the wrong move for the user who most needs
    /// the width. (Portrait already overflows at the top sizes today; that is a separate,
    /// pre-existing defect of the fixed box width and is NOT fixed here — this only makes sure
    /// this slice does not spend the extra landscape width that was masking it.)
    private var columns: Int {
        guard !typeSize.isAccessibilitySize else { return 1 }
        return (hSize == .regular || vSize == .compact) ? 2 : 1
    }

    var body: some View {
        if columns > 1 {
            // Column gap stays 10 regardless — it is a horizontal gutter, unrelated to the
            // vertical rhythm the caller is preserving.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .topLeading),
                                     count: columns), spacing: spacing) {
                content()
            }
        } else {
            // ⚠️ `.leading`, NOT the `VStack` default `.center`. Inert today — every child is an
            // `EchoelValueField` with a label, which is horizontally greedy, so centre and
            // leading coincide. It stops being inert the moment someone puts a non-greedy child
            // in a grid (a bare `Text`, a `Button`): it would centre in PORTRAIT and sit leading
            // everywhere else, i.e. a difference that only shows on one orientation. Matching
            // `EchoelPanel`'s own `.leading` costs nothing and removes the trap.
            VStack(alignment: .leading, spacing: spacing) { content() }
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

/// The RETROACTIVE loop door ("keep the last N bars you just heard").
///
/// Its own `View` struct for a reason that is a house law, not a style choice: deciding
/// whether the ring can still deliver `bars` requires the LIVE tempo, and tempo moves
/// under bio modulation. Reading `pattern.tempo` from `EchoelStudioView.body` — or from
/// any computed var that body evaluates — would register the whole root as an observer,
/// and every tempo tick would tear down an open `.menu` Picker popover. That is the
/// menu-freeze this app shipped twice (10.76.41, 10.76.50). Confined here, only this
/// button rebuilds. `pattern` is passed as a REFERENCE: capturing an `@Observable` does
/// not register observation — only reading a property does, and that read happens in
/// this body.
///
/// The honesty this buys: before #200 the picker offered lengths the ring could not
/// hold (at 120 BPM anything from ~15 bars up), the tap was accepted, the capture ran,
/// and only then did an alert say no. Now the control refuses in advance and names a
/// length that works. The PLANNED door above is untouched — it records live to a file
/// and has no such limit, which is exactly why 64 bars stays offered there.
private struct KeepLastLoopButton: View {
    let pattern: PatternEngine
    let bars: LoopBarLength
    let isExporting: Bool
    let hasComposed: Bool
    /// The parent's status text ("Recording loop…" / "Writing .wav…"), shown while busy.
    let busyLabel: String
    let action: () -> Void

    var body: some View {
        let bpm = pattern.tempo
        let fits = LoopExporter.canKeepLast(bars: bars.rawValue, bpm: bpm)
        Button(action: action) {
            Label(title(fits: fits, bpm: bpm), systemImage: "clock.arrow.circlepath")
                .font(EchoelTheme.font(14, .semibold))
                // The dim state must track `.disabled` EXACTLY. A full-brightness button
                // carrying the inviting "just played" label while inert is the same lie in
                // a quieter register — it just moves the disappointment to the tap.
                .foregroundStyle(isExporting || (fits && hasComposed) ? EchoelTheme.text : EchoelTheme.dim)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isExporting || !hasComposed || !fits)
        .accessibilityHint(fits
            ? "Keeps the last bars you just heard as a WAV loop, without replaying them"
            : "This length is longer than the 30 second capture buffer at the current tempo")
    }

    private func title(fits: Bool, bpm: Double) -> String {
        if isExporting { return busyLabel }
        if fits { return "Keep last \(bars.label) (just played)" }
        // Name a length the PICKER ABOVE ACTUALLY OFFERS. The raw ring capacity (14 bars
        // at 120 BPM) is not a `LoopBarLength` case, so naming it would send the user
        // hunting for a segment that does not exist — a refusal that lies while refusing.
        // `nil` only when the tempo is unusable; then point at the door that does work.
        guard let keepable = LoopExporter.longestKeepable(bpm: bpm) else {
            return "Keep last: unavailable — use Record above"
        }
        return "Keep last: \(keepable.label) or fewer at this tempo"
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

/// #320 — the door to `SoundPrompt`: describe the sound in words and the timbre moves.
///
/// ⭐ WHY THIS IS A LEAF `View` AND NOT A ROW ON `EchoelStudioView`. The first version of this
/// slice put `@State private var soundPromptText` on the root view. Where a value is READ is
/// what governs `@Observable` observation — it is NOT what governs `@State`: mutating `@State`
/// invalidates the view that DECLARES it, and SwiftUI recomputes that view's body whole. So
/// every keystroke re-evaluated `EchoelStudioView.body` (~500 lines, 14 presentation modifiers,
/// four `AnyView` branches) plus all 22 children of `soundPanel` beneath it. `EchoelPanel`'s
/// escaping builder does not save it either: on re-evaluation the parent hands it a freshly
/// constructed, non-equatable closure. `menuPanelHost` states the rule this file lives by —
/// *"build it through `panel(...)`, or keep every live read inside a leaf `View` struct."*
///
/// ⚠️ HONEST SCOPE: the specific documented harm (a 10 Hz read tearing down an open `.menu`
/// Picker) is not reachable from here, because a menu popover and the keyboard cannot be up at
/// once. Three root-`@State` `TextField`s already exist — but all three are inside `.alert`
/// content, where nothing else is interactive. A text field in the always-evaluated front-plate
/// flow was genuinely new, which is why it moved rather than being argued away.
///
/// ⚠️ AND THE CHIPS ARE NOT SELF-EVIDENTLY SAFE. They are `SoundPrompt.suggestions` verbatim,
/// and `apply` drops out-of-vocabulary words SILENTLY (an unknown word must never garble a
/// patch). Four of the eight shipped phrases contain such a word — "pluck", "lead", "bell",
/// "cinematic" — harmless only because the rest of each phrase still resolves. A phrase where
/// NOTHING resolved would be a chip that does nothing when tapped; `SoundPromptHasADoorTests`
/// forbids that, not the fact that the list is curated. The hint line is the other half: it
/// names what WILL be used, so a dropped word is visible instead of mysterious.
private struct SoundPromptRow: View {
    let canUndo: Bool
    let onShape: (String) -> Void
    let onUndo: () -> Void

    @State private var text = ""

    /// The words in the box the mapper actually understands — a lowercase split over a short
    /// string, re-run only when this leaf rebuilds.
    private var terms: [String] { SoundPrompt.recognizedTerms(in: text) }

    /// Names the recognised DESCRIPTORS, so a word the mapper drops is visible before the player
    /// wonders why nothing moved.
    ///
    /// ⛔ IT DOES NOT LIST INTENSITY WORDS, and the first version of this doc said "states only
    /// what WILL be used" — which is wider than the truth in the one line whose whole job is to
    /// stop the row reading as broken. `recognizedTerms` matches `vocabulary` only, so the
    /// shipped chip "gentle clean bell" reads `Shapes: clean` — while `gentle` IS used
    /// (`SoundPrompt.intensity` → ×0.5, halving `clean`). A player who trusts the line and
    /// deletes `gentle` doubles the effect. The visible sentence below says so explicitly
    /// ("scale the next word") rather than the list pretending to be exhaustive.
    ///
    /// A `String` computed outside the builder rather than a ternary inside `Text(…)`: same
    /// result, and this file's type-checker budget is not somewhere to be casual.
    private var hint: String {
        if terms.isEmpty {
            return "Words like warm · bright · plucky · pad · evolving · huge shape the timbre from where it is now. \"very\" / \"slightly\" scale the next word."
        }
        return "Shapes: " + terms.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Describe it")
                .font(EchoelTheme.font(12, .medium)).foregroundStyle(EchoelTheme.dim)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("warm lush pad", text: $text)
                        .font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { onShape(text) }
                        // 34 pt matches `presetRow`'s Menu directly above — a full-width field
                        // is not the small-target case the 44 pt rule is about. The two SMALL
                        // controls in this row carry the 44 pt hit frame instead.
                        // `minHeight`, never `height`: `EchoelTheme.font` is `.custom(…,
                        // relativeTo: .body)`, so it grows with Dynamic Type and a fixed box
                        // clips the text at accessibility sizes — #262's finding, and CLAUDE.md
                        // now calls a fixed frame "Ökosystem-Schuld" outright.
                        .padding(.horizontal, 12).frame(minHeight: 34)
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .strokeBorder(EchoelTheme.border, lineWidth: 1))
                        // The hint rides on the FIELD, not only as a visual sibling below the
                        // chips: it is the row's honesty mechanism, and a VoiceOver user would
                        // otherwise reach it only by swiping past everything else.
                        .accessibilityHint(hint)

                    Button { onShape(text) } label: {
                        // The `fill` + `contentShape` pair is not decoration: with only a
                        // `strokeBorder`, hit-testing falls back to the glyphs plus a 1 pt
                        // stroke and the padded space between them is dead.
                        Text("Shape").font(EchoelTheme.font(13, .semibold))
                            .foregroundStyle(terms.isEmpty ? EchoelTheme.dim : EchoelTheme.text)
                            .padding(.horizontal, 14).frame(minHeight: 34)
                            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                                .fill(EchoelTheme.fill))
                            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                                .strokeBorder(EchoelTheme.border, lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(terms.isEmpty)
                    .accessibilityLabel("Shape the sound from the description")

                    if canUndo {
                        Button(action: onUndo) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 14)).foregroundStyle(EchoelTheme.text)
                                .frame(minWidth: 34, minHeight: 34)
                                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                                    .fill(EchoelTheme.fill))
                                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Undo the last shaping")
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SoundPrompt.suggestions, id: \.self) { phrase in
                            Button {
                                text = phrase
                                onShape(phrase)
                            } label: {
                                // 44 pt tap target with an explicit fill and `contentShape`,
                                // the same rule `chipTapTarget` applies to the menu bar: the
                                // 28 pt pill it replaced was 36 % under the HIG minimum AND
                                // hit-tested only its glyphs, because a bare `strokeBorder`
                                // leaves the space between text and border dead.
                                Text(phrase).font(EchoelTheme.font(12))
                                    .foregroundStyle(EchoelTheme.text)
                                    .padding(.horizontal, 10).frame(minHeight: 28)
                                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                                        .fill(EchoelTheme.fill))
                                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shapes the sound now")
                        }
                    }
                }

                Text(hint)
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)   // already announced as the field's hint
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
