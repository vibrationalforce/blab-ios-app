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
///
/// ⛔ THIS CLOSURE USED TO END IN `?? Data()` (#519), and that is worse than any silent
/// failure in this repo so far. An empty `Data` is not an error — the closure RETURNS, the
/// share sheet completes, and a 0-byte file goes out carrying the take's real name. The
/// sender is told nothing; the failure surfaces on the RECIPIENT's device, days later, as
/// `ProjectStore.importProject` returning `nil` on empty bytes. A fabricated artefact that
/// looks like success is the one outcome worse than a button that visibly does nothing
/// (#518, the same encode failure one door over).
///
/// ⭐ `DataRepresentation`'s exporting closure is `async throws`, so the honest form was
/// always available: let it throw and the system reports a failed export instead of
/// delivering a corrupt document. The encoder itself is NOT spelled here any more — see
/// `Project.sharedDocumentData()`, which owns the format and the failure policy for exactly
/// one thing: a Project as a shared DOCUMENT.
@available(iOS 16.0, *)
struct SharedEchoelProject: Transferable {
    let project: Project
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { shared in
            try shared.project.sharedDocumentData()
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
    /// #581 — the pad's chord SHAPE. See `StudioDefaultKeys.padGate` for why the defaults are
    /// the composer's old literals and why the rows disable themselves on "Genre".
    @AppStorage(StudioDefaultKeys.padGate.key)
    private var padGate = StudioDefaultKeys.padGate.value
    @AppStorage(StudioDefaultKeys.padAccent.key)
    private var padAccent = StudioDefaultKeys.padAccent.value
    @AppStorage(StudioDefaultKeys.padEvolve.key)
    private var padEvolve = StudioDefaultKeys.padEvolve.value
    // #275 slice 1 — the STORAGE half of `mood` below. The eight dials live in `@State` because
    // eight `EchoelValueField`s bind into them individually; this key is the one place their
    // value is written down, restored in `onAppear` and re-encoded from the single
    // `.onChange(of: mood)` on the body. See `MoodStorage` for why one JSON string and not
    // eight scalar keys.
    @AppStorage(StudioDefaultKeys.mood.key)
    private var moodRaw = StudioDefaultKeys.mood.value
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
    /// Only `isRunning` is read here, and only for keep-awake (#486) — it flips twice per
    /// session. The ~30 Hz `guidance` read stays inside `BreathCoachStrip`, which is why
    /// that is a `View` struct.
    @Environment(BreathPacer.self) private var breathPacer
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
    /// #608 Scheibe 1 — the Auto-mode switch (H15: second reader is `AutoModeRow`,
    /// the door in `bioPanel`). Event-rate: written only by the toggle. The fold in
    /// `makeComposerInput` reads it per evolve tick, never per frame.
    @AppStorage(StudioDefaultKeys.autoMode.key) private var autoMode = StudioDefaultKeys.autoMode.value
    /// AutoAttune's hysteresis/hold/pause state, carried across evolve ticks. Written
    /// only inside `makeComposerInput` (an event path, ~25–45 s), never in `body`.
    @State private var autoAttuneState = AutoAttune.State()
    @Environment(LoopExporter.self) private var exporter
    @Environment(ProjectStore.self) private var projects
    @Environment(PatchStore.self) private var patchStore
    @Environment(MixerStore.self) private var mixer
    @Environment(TrackFXStore.self) private var trackFX
    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif
    // The two alternative bio sources the chooser can select (founder 2026-07-15) — the
    // pill's long-press menu and, since #616, the visible "Bio source" row in `bioPanel`:
    // a Bluetooth heart-rate strap (universal 0x180D) and the Simulation demo. Camera
    // (above) is the default. All three are injected by the app; `selectBioSource`
    // switches the live one, `startBioSource` honours the selection.
    #if canImport(CoreBluetooth)
    @Environment(PolarH10BioPublisher.self) private var polarH10
    #endif
    @Environment(BioSimulator.self) private var demoSource
    #if canImport(AVFoundation) && canImport(Metal)
    @Environment(VisualRecorder.self) private var visualRecorder
    #endif

    // The single live-state flag: biofeedback running or not.
    @State private var running = false

    /// Which bio input the chooser selected (founder 2026-07-15; pill long-press or,
    /// since #616, the bioPanel "Bio source" row). Camera by default; `startBioSource`
    /// brings up whichever is set, `selectBioSource` switches it live. Persisted so the
    /// choice survives relaunch.
    @AppStorage("bio.sourceKind") private var bioSourceRaw = BioSourceKind.camera.rawValue
    /// Guards the async live source-switch so a rapid re-pick can't overlap.
    @State private var sourceSwitchTask: Task<Void, Never>?

    /// The three bio inputs the chooser offers. The implicit raw values are the
    /// on-the-wire ids `BioSourceOption` mirrors (#616) — a case added here needs its
    /// twin there, or the new source has no menu entry.
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
    /// #603 B1 — the guide switch state (overlay mounts in WorkspaceView; H15-KEYSTORE).
    @AppStorage(StudioDefaultKeys.guideVisible.key) private var guideVisible = StudioDefaultKeys.guideVisible.value
    /// #604 — the instrument hint's retire flag; `startBioSource()` writes it (lesson
    /// learned). The overlay in FloatingVisualWindow is the reader (H15-KEYSTORE).
    @AppStorage(StudioDefaultKeys.instrumentHintSeen.key) private var instrumentHintSeen = StudioDefaultKeys.instrumentHintSeen.value
    @AppStorage(StudioDefaultKeys.lockedBPM.key) private var lockedBPM: Double = StudioDefaultKeys.lockedBPM.value
    /// Tap-tempo estimator (performance staple) + the last value it produced for display.
    @State private var tapTempo = TapTempo()
    @State private var lastTappedBPM: Double? = nil
    /// EchoelVoice #592b — owned HERE (not in the row) so a capture survives the
    /// sound panel closing and reopening mid-take; the leaf row reads it, this body
    /// only passes the reference (no observable property is read at panel level).
    @State private var voiceCapture = VoiceCaptureController()

    // #596 — the app-wide plug-in watcher (USB mic / interface / wired headset →
    // invitation, never auto-arm). View-owned like `voiceCapture`; only the
    // `PlugInInviteRow` leaf reads it (freeze law), this body passes the reference.
    #if os(iOS) && canImport(AVFoundation)
    @State private var plugInWatcher = RoutePlugInWatcher()
    #endif

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
    // ⛔ `studio.showSession` WAS DELETED HERE (#359 step 3), AND THE FIRST VERSION OF THIS
    // NOTE GAVE A REASON THAT IS FACTUALLY WRONG — corrected rather than dropped, because
    // CLAUDE.md's own rule is that a wrong justification is worse than none: the next
    // session cannot refute it. It said "every device that ever opened that panel carries a
    // `true` for it". No device does. `sessionPanel` was rendered ONLY from
    // `dropdownContent`, and `menuPanelHost` puts `.environment(\.echoelPanelForceOpen,
    // true)` over that host; `EchoelPanel.body` then builds a plain `VStack` with NO
    // `DisclosureGroup`, so the `isExpanded` binding is never mutated. The key was almost
    // certainly never written at all. This file already documents that mechanism twice (the
    // chrome-door `onReceive` block, and `SaveDoorNamingTests` for `showExport`) — I had
    // both and reasoned from the general shape of an `@AppStorage` instead.
    //
    // The CONCLUSION is unchanged and is the part worth keeping: whatever is or is not on
    // disk under that key, nothing will read it again, and it is not a persisted CONSENT
    // (`locationNamer.enabled` is, and it survives untouched in `placeRow`, which moved into
    // "Save & Export"). Naming the orphan is the point — a future `UserDefaults` sweep
    // should know it is expected, and should not go hunting for a stored `true` that was
    // never written.
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
    /// #736 — the master-bus tonal character. Labelled "Tone", NOT "Character": this file
    /// already has two `labeledRow("Character")` rows (the sound preset row and the Effects
    /// picker), and a third meaning of one word in one app is a worse defect than a longer
    /// label. The accessibility label spells it out for VoiceOver.
    ///
    /// ⛔ AND #736 COUNTED THE WORD IT REJECTED WITHOUT COUNTING THE WORD IT CHOSE (#737).
    /// `groupHeader("Tone")` already exists in this same file — the synth-timbre group in the
    /// Sound panel (Brightness / Harmonics / Noise / Shape). The pick STANDS: different panel,
    /// a group HEADER rather than a row label, and on the master row the word is unambiguous
    /// in place. But it is a SECOND "Tone", i.e. weaker than the collision it avoided, and the
    /// paragraph above asserted a measurement it had not run on its own choice. **A rationale
    /// that counts the alternatives must count the choice** — one `grep` either way.
    @AppStorage(StudioDefaultKeys.masterCharacter.key) private var masterCharacterRaw = StudioDefaultKeys.masterCharacter.value
    /// Immersive visual mode: the spectrum→visible donut renderer vs the Metal field.
    /// **Default stays `false`, and since #747 that is a CHOICE rather than a limitation.** The
    /// reachable control is the donut toggle in the fullscreen cover's top bar, reached through
    /// the "Full screen" button in `visualPanel`. From #227 until then nothing could turn it on,
    /// which is why a launch-time normaliser existed; that function is deleted — see the
    /// tombstone where it stood. A fresh install opens on the Metal field because that is the
    /// identity look, not because donuts are unreachable.
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
    ///
    /// ⚠️ `@State`, but PERSISTED SINCE #275 — through `moodRaw`/`MoodStorage`, not through
    /// `@AppStorage` on this property. It stays `@State` because eight knobs, the mood pad and
    /// `MoodPreset` all bind into individual FIELDS of it (`$mood.liveliness`, …), which a
    /// `@AppStorage`-backed value of a non-scalar type cannot offer. Restored once in
    /// `onAppear`, written back from the single `.onChange(of: mood)` on the body — one
    /// storage decision, one write site (#416).
    @State private var mood = MoodProfile()
    // The SOUND mood pad's persisted position ("mood.sound.x"/"y") moved into
    // `SoundMoodPadLeaf` with #322 — same keys, same defaults, so an existing device
    // keeps its position; it is simply no longer stored on the root, where a drag
    // would have re-evaluated this whole body per move.
    /// Saved/curated moods (factory + user + community), same library pattern as FX/sound.
    @State private var moodStore = MoodPresetStore()
    /// Identity of the currently-loaded mood (nil = an unsaved "Custom" edit).
    @State private var moodPresetID: UUID? = nil
    @State private var moodPresetName = "Custom"
    @State private var showSaveMoodAs = false
    @State private var moodAsName = ""
    @State private var showSavePatchAs = false
    @State private var patchSaveName = ""
    /// The patch as it was immediately before the last wholesale timbre change in the Sound
    /// panel, so that change can be taken back in one tap. Nil = nothing to undo.
    ///
    /// ⛔ IT WAS CALLED `patchBeforePrompt` AND ONLY THE PROMPT WROTE IT, while
    /// `randomizeButton` — one row BELOW the Undo arrow, same panel — replaced `currentPatch`
    /// outright with no snapshot at all. Two neighbouring controls that do the same thing to the
    /// same value, one undoable and one not, and nothing on screen said which was which. The
    /// name is part of the fix: a snapshot that covers two writers must not be named after one
    /// of them, or the next writer reads the name and assumes it does not apply to it. (This
    /// repo has paid for a stale name before — #374 renamed a whole guard file for it.)
    ///
    /// ⚠️ STILL EXACTLY ONE STEP, deliberately, and the reason is unchanged: a deeper history
    /// would have to be invalidated by the seven other places that assign `currentPatch`
    /// wholesale, and an undo that silently points at a patch from before a preset load is worse
    /// than no undo.
    ///
    /// ⭐ EVERY WHOLESALE REPLACE OF `currentPatch` MUST CLEAR THIS, and that is a standing
    /// obligation on the next writer, not a nicety. The slot holds ONE step; if a control that
    /// replaces the timbre by other means leaves it armed, the arrow stays lit and restores a
    /// patch from BEFORE that replacement — silently skipping past the thing the user most
    /// recently chose. Cleared today at: the genre picker (`handleCompositionEdit`), the "Genre
    /// default" menu row, the Delete that falls back to the genre patch, the Undo-delete that
    /// restores a user patch, `applySoundPatch` (the Character menu — the one a user hits most),
    /// and `open(_:)`. NOT cleared, deliberately, at two places: the "Save as new sound…" alert,
    /// because saving a copy does not change the SOUND (the values are identical, only id and
    /// name differ), and `.onAppear`, where a fresh `@State` is already nil and a clear would be
    /// a line that cannot do anything. #593c added two more `currentPatch` writers that likewise
    /// do NOT clear this, deliberately: the "Save changes" enrichment (voice half only — the
    /// audible sound is unchanged, same reasoning as save-as) and the Voice-timbre Clear strip
    /// (which instead strips THIS slot's voice half through the row's onClear — the snapshot
    /// stays armed for its SOUND, but the Undo arrow can no longer resurrect a cleared voice,
    /// the #593c review's F3).
    ///
    /// ⚠️ THE TYPED TEXT IS DELIBERATELY *NOT* HERE. It lives in `SoundPromptRow`'s own
    /// `@State`, because state on THIS view re-evaluates a ~500-line body on every keystroke.
    /// This one is safe at root level for the opposite reason: it changes only when a timbre is
    /// replaced or restored — a tap, not a character.
    @State private var patchBeforeSoundChange: SynthPatch?

    /// The user sound / mood removed by the last Delete in its overflow menu, kept so the
    /// removal can be taken back from that same menu. Nil = nothing to restore.
    ///
    /// ⭐ WHY A SNAPSHOT AND NOT A CONFIRMATION. Both Deletes sit in a `Menu` as
    /// `Button(role: .destructive)`, which SwiftUI only COLOURS red — nothing asks. Both are
    /// gated on `!isFactory`, so the only thing they can remove is a preset the user made
    /// themselves: the irreplaceable kind. Meanwhile SAVING the same sound goes through an
    /// alert. A `.confirmationDialog` could only ever warn; keeping the removed preset gives it
    /// back. That is the whole argument, and it is enough.
    ///
    /// ⛔ IT WAS SHIPPED WITH A SECOND REASON THAT DOES NOT HOLD HERE — "it would grow the
    /// presentation chain the black-screen law forbids growing". That law is scoped to
    /// `EchoelStudioView.body`'s OWN modifier chain, the counted 14 (CLAUDE.md), and these two
    /// menus are not on it: `soundPanel` and `moodPanel` reach the body only through
    /// `dropdownContent: AnyView`, which erases their types before the body's aggregate type is
    /// formed. A dialog attached in here would have added nothing to that type and left the
    /// count at 14. The claim was checkable and false, which in this file is worse than no
    /// reason at all — a later session weighing a real dialog would have refused it on a law
    /// that does not reach this code. Reversible beats confirmed on its own merits.
    ///
    /// ⚠️ THE FAVOURITE FLAG HAS TO TRAVEL WITH IT. `PatchStore.delete` / `MoodPresetStore.delete`
    /// also drop the id from `favorites` and `recents`, and `save(_:)` does not restore either —
    /// so an undo that only re-saved the preset would silently un-star it. The star is carried
    /// here and re-applied; `recents` is deliberately NOT, because a restored preset genuinely
    /// has not been recalled since, and re-inserting it at the top of the ranking would reorder
    /// the library behind the user's back.
    ///
    /// ⚠️ HONEST LIMIT — THE WAY BACK IS NOT ANNOUNCED. A `Menu` closes on any tap, so after a
    /// Delete the user sees no toast and no arrow: they have to REOPEN the same overflow menu
    /// to find "Undo delete of …". That is worse than a banner and better than today's nothing,
    /// and it is the shape that costs no presentation slot. It is also why the row names the
    /// preset rather than saying "Undo" — reopened minutes later, the row has to say what it
    /// would bring back. ONE step per surface: a second Delete replaces the first snapshot.
    ///
    /// ⚠️ AND IT DOES NOT SURVIVE A RELAUNCH. `@State`, not persisted — deliberately: a restore
    /// offer that outlives the session would resurrect a preset the user deleted a week ago from
    /// a menu they opened for something else. The undo is for the tap you just made.
    @State private var deletedPatch: (patch: SynthPatch, wasFavorite: Bool)?
    @State private var deletedMood: (mood: MoodPreset, wasFavorite: Bool)?
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
    // ⛔ `@AppStorage("studio.beatMode")` STOOD HERE AND IS DELETED (#323). Its only readers
    // were `beatModeRow`'s Picker and hint text, and that row has been unmounted since the
    // founder's 2026-07-07 "Schmeiß den Beat komplett raus"; the drums it selected between
    // were deleted outright by #166/#167. Generation calls `BioComposer.silentBeat()`
    // unconditionally, so the stored value has had no effect on any sound for weeks — which
    // is exactly why the key is safe to strand rather than migrate: a leftover
    // `.pulse` in UserDefaults cannot make a drum appear. (The doctor rule this satisfies:
    // check what a deleted UI block writes as its SOLE writer before deleting it. Here the
    // answer is "a value nothing reads".) `BeatMode` itself stays in `BioComposer.swift`
    // (`:43`) together with `shamanicBeat()` and the six private genre-groove builders;
    // deciding their fate is a separate call, not a side effect of removing a doorless
    // control. (⛔ This line named a `genreBeat()` that does not exist — see the tombstone
    // where the row used to be for the six real names and why the invention was dangerous.)
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
    /// When a take was ACTUALLY composed. Written only by `generate(…)`, at run time.
    ///
    /// ⛔ #398: THIS IS ONE FACT AND IT USED TO CARRY TWO. `scheduleGenerate` also wrote the
    /// FUTURE instant an automatic re-seed was claimed for into this same property, and then
    /// every reader subtracted it as though it always meant "a take happened at T". Two defects
    /// followed (see `RegenSchedule`), and a third landed in the DIAGNOSTIC: `generate(…)` prints
    /// `sinceLast=` from here (#390), so while a claim could live in it the log reported the
    /// distance to a re-seed that had not happened. Claims now live in `seedFloor`.
    @State private var lastSeedAt: Date = .distantPast
    /// The instant an AUTOMATIC re-seed is already claimed for — the anti-flood floor, claimed at
    /// SCHEDULE time so several auto triggers inside one window (lock-snap + evolve tick land
    /// together the moment a pulse locks) COLLAPSE onto the same instant instead of each
    /// computing a fresh gap. `.distantPast` = no claim stands.
    ///
    /// Deliberately NOT written by a user edit: `scheduleGenerate` cancels the pending task on
    /// its first line, so a standing claim belongs to something that will never run, and
    /// `generate(…)` re-stamps `lastSeedAt` on its own when a take is really produced.
    @State private var seedFloor: Date = .distantPast
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
    /// #403 Slice 1 — the slowly-learned fingerprint of THIS performer, folded into the
    /// STRUCTURE seed so the same preset opens on a different skeleton for a different body.
    /// Loaded once at view construction and written back only when a take actually taught it
    /// something (see `makeComposerInput`). `.unknown` ⇒ `seedSalt == 0` ⇒ bit-identical to
    /// before the signature existed.
    @State private var performerSignature = PerformerSignature.load(from: .standard)
    /// The body state (HR·coherence) captured at the last take — the baseline the evolve
    /// HOLD compares against (founder 2026-07-04 "halten wenn eingerastet"): a settled,
    /// unchanged body holds its phrase instead of re-rolling every ~30 s. nil = the last
    /// take had no usable body (neutral/demo), so evolve keeps it gently alive.
    @State private var lastGenBody: (bpm: Double, coherence: Double)? = nil
    // ⛔ `minAutoSeedGap` USED TO BE DECLARED HERE (6.0 s, raised from 3.5 on device-log feedback:
    // it lets a take settle into a phrase and makes overlapping auto triggers collapse into one
    // re-seed). It moved to `RegenSchedule.minAutoSeedGap` with #398, next to the only arithmetic
    // that ever read it, so one test can pin the number and the rule that uses it together. Kept
    // as a note rather than an unused alias: a computed forwarder with no callers is dead code,
    // and this repo's engineering rules say so — but a grep for the old name must not land on
    // nothing, or the next reader concludes the floor was deleted rather than moved.
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

    /// #400 — the sound reset is armed by a first tap and performed by a second, INSTEAD of an
    /// `.alert`. That is not a style preference: this body already carries 14 presentation
    /// modifiers, and the black-screen SIGSEGV of 10.76.34 was caused by growing exactly that
    /// chain past the SwiftUI metadata-decoder limit. A destructive action still needs a
    /// confirmation step, so the confirmation goes inline where it costs no generic depth.
    ///
    /// ⛔ THE FIRST VERSION OF THIS NOTE SAID "Not persisted — an armed reset must never survive
    /// putting the phone in a pocket", AND IT WAS FALSE IN EXACTLY THE DIRECTION THAT MATTERS.
    /// `@State` here survives backgrounding: `WorkspaceView` keeps `EchoelStudioView` mounted for
    /// the whole app lifetime, so non-persistence only means the flag dies on process
    /// TERMINATION — the pocket is the case the sentence claimed to cover and did not. It also
    /// survived switching to another dropdown panel, because this state lives on the ROOT view
    /// and not on the row. A reader checking whether the arm can go stale would have found that
    /// sentence and stopped looking. It is TRUE NOW because two disarms make it true:
    /// `.onDisappear` on `soundResetRow` (panel switch) and the `scenePhase` branch in the body
    /// (backgrounding). Found in review, before any device saw it.
    @State private var soundResetArmed = false

    // Modal slots. `compose.toolsExpanded` went with the Tools grid it folded — zero
    // readers, zero writers. Its persisted UserDefaults key is deliberately NOT migrated
    // or cleared: a stale bool costs nothing, a delete-on-launch is a destructive write
    // for no gain.
    @State private var showInput = false
    /// #485, since #601 written from `engageInputMonitoring()`'s answer. Set when the
    /// monitor enable REFUSED (mic permission denied — at the dialog or previously in
    /// Settings — or the route publishes no valid input format). Not decoration, not only a
    /// message: `isInputMonitoring` is `private(set)` and stays false on refusal, so with
    /// nothing else mutating observable state the Mix board's `Toggle` would keep SHOWING
    /// "on" — a lying control (#135/#164/#227) on the one row where "it says it is
    /// listening" is the worst thing in the app to be wrong about. Writing this `@State`
    /// invalidates the body, the binding re-reads the engine, and the toggle falls back.
    /// (`AudioInputPickerView`'s toggle gets the same invalidation for free from the
    /// `inputs.refresh()` it calls for a different reason — worth knowing before anyone
    /// "simplifies" this away by copying that call site.)
    @State private var micMonitorRefused = false
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
    /// What the last import could not do, shown as a row in the Open-project sheet.
    ///
    /// ⛔ A ROW, NOT AN `.alert` — and that is the black-screen law (10.76.34), not taste.
    /// The body chain is at 14 presentation modifiers and the FILE is at 16; `#479`
    /// (`ResetSoundClearsWhatTheLaunchLineReportsTests`) pins BOTH numbers, the file-wide one
    /// as an equality. A new `.alert` anywhere in this file — including inside `openSheet`,
    /// where the importer this reports on already sits as one of the two nested modifiers —
    /// makes that guard red AND grows the aggregate generic type this app has already
    /// SIGSEGV'd on once. An inline row costs zero modifiers and is the house pattern for a
    /// status the user is already looking at (Live Colabo's status line, #518).
    @State private var importNote: String?
    @State private var showVisual = false
    /// Remembers whether the floating visual was showing before the fullscreen cover took over,
    /// so dismissing the cover restores it (single-MetalBioView / GPU rule — see onChange).
    @State private var floatingWasVisible = false
    @State private var showMeditation = false
    @State private var showLiveColabo = false
    /// Presents the full per-stage FX panel (every parameter exposed).
    /// ⛔ Said "as a slider" until #480. `EchoelFXView` declares zero `Slider(` — measured, and
    /// the comment above its own door said so while this line and the VoiceOver hint went on
    /// claiming it. See the ⛔ block at the `showAllFX` button in `effectsPanel`.
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
    // TWO un-settable flags remain (`showMeditation`, `midiImportPresented`) — reuse one of
    // those before ever appending a 15th. ⭐ It said THREE until #747, which gave `showVisual`
    // a real setter (the "Full screen" button in `visualPanel`). That slot is now a LIVE
    // surface, not spare headroom: taking it over would delete the fullscreen field, the VJ
    // overlay and the donut renderer, which is ship-gate 4's second half.
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
        //
        // ⭐ `session` WAS REMOVED (#359 step 3). Deleting a case from THIS enum is only safe
        // because of the paragraph above — the raw value reaches no persisted store and no
        // door string. The panel behind it held exactly one control after step 1 moved the
        // weather out, and that control (`placeRow`) now sits in "Save & Export", directly
        // above the Save button whose file name it shapes. This also closes filed task #284:
        // a chip called "Session" that saved no session, one chip from a panel that does.
        case bio, composition, sound, mix, effects, master, mood, export, field, video
        var id: String { rawValue }
        /// Short chip label (DAW-style small buttons — Uncodixfy 12 pt chips).
        var label: String {
            switch self {
            case .bio:         return "Bio"
            case .composition: return "Tempo"
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
            case .sound:       return "Sound and texture"
            case .mix:         return "Mix — level per part"
            case .effects:     return "Effects"
            case .master:      return "Master"
            // #202/#59, INHERITED FROM THE DELETED `.session` CASE and not dropped with it.
            // The founder listed "weather, Standort" among the things he was MISSING while
            // both were built, wired and reachable — because every string that advertised
            // them said "in the name". Weather is not a naming gimmick: it salts the
            // harmonic skeleton and blends darkness/liveliness/tension into the composer's
            // mood. Since #359 step 1 that is literally what this panel holds, so the
            // sentence finally sits on the door it describes. (The picture half — hue,
            // saturation, glow, movement — went to Field in step 2 and is named there.)
            case .mood:        return "Mood — character, and the weather that colours it"
            // #272: named only the export half for months, and the founder reported
            // "Session speichern und Loops aufnehmen fehlt" about controls that are IN
            // this panel. Save and Open go first because those are the two words he used.
            // #359 step 3 added the place toggle to this panel — it shapes the very file
            // name the Save button writes — so the spoken name has to carry it too, or the
            // control is once again behind a door that does not mention it.
            //
            // ⛔ AND #482 MADE THAT WHOLE PARAGRAPH FALSE WITHOUT TOUCHING THIS LINE. The
            // five controls it promised — Save, Open, Record, keep-last, MIDI — moved OUT
            // to `quickActionRow`, permanently visible one line under the transport. #482
            // rewrote the panel's VISIBLE subtitle for exactly that reason and left the
            // SPOKEN name of the same door saying "Save, record and export — sessions, WAV
            // loop, MIDI, and the city in the name". So a sighted user was told the truth
            // and a VoiceOver user was sent into a panel to look for four controls that are
            // not in it — the #272 report, inverted, on the one surface with no visual
            // fallback. Found by the #482 reviewer. The name now lists what the panel
            // actually holds; `SaveDoorNamingTests` moved with it in the same commit,
            // because until then that guard REQUIRED the false words.
            case .export:      return "Save and export settings — loop length, place in the name, reset sound, diagnostics"
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
    /// Who the board's target density came from (#645). Written in the SAME statement group as
    /// `mazeBoard`, from the same frame the composer input was built from — the adjacency is the
    /// whole guarantee, exactly as for `StudioCaption.driver` (#644). A separate read could
    /// describe a different exploration than the one on screen.
    @State private var mazeDriver: BioNarrationDriver = .nothingMeasured
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
    /// Default saturation lives in `StudioDefaultKeys.visualSaturation` (1.05 since #578 —
    /// the founder asked for "Bunter"; the old 0.82 and its "professional, not neon"
    /// reasoning are retracted at that declaration). ⚠️ The old wording here RESTATED the
    /// number, which is #416: three surfaces already share the key, and a fourth spelling of
    /// the value is how they drift. Ask the constant. "MUST match FloatingVisualWindow" is
    /// satisfied by construction — both read the same `StudioDefault`.
    @AppStorage(StudioDefaultKeys.visualHue.key) private var visualHue = StudioDefaultKeys.visualHue.value
    @AppStorage(StudioDefaultKeys.visualSaturation.key) private var visualSaturation = StudioDefaultKeys.visualSaturation.value
    /// Texture (grain depth) + Glitter (twinkle amount) — the #578 finishing stages, made
    /// user-dialable (#853). Shared keys, same three-surface pattern as hue/saturation.
    @AppStorage(StudioDefaultKeys.visualTexture.key) private var visualTexture = StudioDefaultKeys.visualTexture.value
    @AppStorage(StudioDefaultKeys.visualGlitter.key) private var visualGlitter = StudioDefaultKeys.visualGlitter.value
    /// Structure (#853B): static domain-warp depth, 0 = off (the pre-dial picture).
    @AppStorage(StudioDefaultKeys.visualStructure.key) private var visualStructure = StudioDefaultKeys.visualStructure.value
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

    /// #379 — what the last energy edit CLEARED out of `visualPresetID`, so an edit that
    /// puts the numbers back can put the chip back.
    ///
    /// WHY A MEMO AND NOT A GUARD. `visualEnergy` already guarded its clear on "did anything
    /// actually move", which covers a no-op write (a clamped drag at a range end, a VoiceOver
    /// adjust past the bound) — but not the case #379 is about. A CANCELLED drag does move the
    /// value first, so the chip is already gone by the time #378's revert puts the number back;
    /// there is nothing left to guard, only something to restore. And since #378 that loss has
    /// no symptom: the numbers read exactly as before while the named selection is gone.
    ///
    /// ⛔ WHAT THIS BUG IS NOT, and the first version of this note said otherwise IN SIX PLACES
    /// (here, the guard file's header, its `@State` test's failure message, two sibling guards,
    /// the commit message and the deploy note): it claimed the four energy values are not
    /// persisted individually, so that a lost chip meant a lost picture. **They are.**
    /// `visualIntensity` · `visualDetail` · `visualMotion` · `visualSpread` are `@AppStorage`
    /// twenty-odd lines above this one (`StudioDefaultKeys.visual*`), and they have to be —
    /// `FloatingVisualWindow` and `ExternalDisplayScene` read the same four keys. A relaunch
    /// therefore restores the PICTURE regardless; what a cancelled drag lost is the chip's
    /// highlight and its NAME. Still worth fixing — a strip that reads "nothing selected" over
    /// values that are exactly a preset's is a lying control, the class this repo removed in
    /// #135/#164 — but not "an installation setup". Found by the #379 reviewer, one commit
    /// after the claim shipped. It is written out here rather than quietly deleted because the
    /// false version was the STATED REASON the guard file exists.
    ///
    /// Deliberately NOT persisted, and the reason is the honest one: the memo is scoped to a
    /// single edit chain. One that outlived a launch would put a chip back onto values the user
    /// may have changed in between — a selection nobody made.
    @State private var clearedVisualPresetID = ""

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
                // Chrome doors: the header monitors reach the plate without touching studio
                // state directly. (⛔ This line named the "•••" overflow as a second producer
                // for two cycles — first as chrome, then as a same-view round trip after #456.
                // Both readings are dead with #492: the overflow is gone and its two doors are
                // tiles in `quickDoorRow` that set their own `@State`. The sentence is true
                // again as written, with the header monitors as the ONLY producers, which is
                // the whole reason this notification still exists.)
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
                    // ⛔ `"learn"` AND `"live"` WERE DELETED HERE (#492), for the same reason
                    // the four before them were: their only producer went away in the same
                    // commit. The "•••" overflow is dissolved into two tiles in
                    // `quickDoorRow`, and those tiles own the `@State` they set — they are in
                    // this view, so a notification would have been a message from the studio
                    // to itself. A `case` with no poster compiles silently and reads like a
                    // live hook; that is the shape this file has been burned by more than
                    // once. The notification keeps its REAL producers below (the header
                    // monitor tiles), which is why it is not deleted outright.
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
            // #596 — arm the app-wide plug-in watcher from the ROOT, which always
            // renders (the invite row itself is conditionally empty, and `.onAppear`
            // on empty content does not reliably fire). `start()` is idempotent, and
            // it reads NO musical state — the genre clamp below is still "FIRST,
            // before anything reads `style`", exactly as its comment claims.
            #if os(iOS) && canImport(AVFoundation)
            plugInWatcher.start()
            #endif
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
            // …and the eight MOOD dials, which until #275 were the only composer input with no
            // persistence at all: `mood` is `@State`, so every cold start silently reset
            // density, register, dissonance, chord colour, leaps, ornaments, placement and
            // velocity feel to factory while every one of their siblings above (genre, scale,
            // root, tuning, A4, articulation, both rhythm characters) came back.
            //
            // ⚠️ MUST PRECEDE `logLaunchMusicalIdentity()` at the end of this closure — that
            // line reports `mood=` now, and reporting the value the view was CONSTRUCTED with
            // instead of the one it woke up with would make the launch breadcrumb lie about
            // exactly the class of state it exists to expose.
            //
            // The `.onChange(of: mood)` on the body sees this assignment and re-encodes. That
            // is deliberate and idempotent: on a fresh install `decode("")` equals the current
            // value, so the comparison never fires and no key is written; on a restore it
            // writes back the same (normalised) string.
            mood = MoodStorage.decode(moodRaw)
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
            // ⛔ `normaliseUnreachableDonutMode()` STOOD HERE AND IS DELETED (#747), on the
            // instruction its own doc comment carried: "DELETE THIS TOGETHER WITH THE LINE THAT
            // CALLS IT, IN THE SAME COMMIT THAT GIVES `showVisual` A SETTER AGAIN (#227)". That
            // setter is the "Full screen" button in `visualPanel`. Keeping the line would have
            // turned an honest normalisation into a silent state-eater: it stamped
            // `visual.spectralDonuts` back to `false` on EVERY launch, so a player who chose
            // donut mode in the cover would find it gone the next time the app opened.
            // `normaliseDoorlessLeadMix()` below is UNAFFECTED — different store, different
            // expiry condition, and `MixerStore.lead` still has no door.
            // #255: same shape, one store down — the Mix board's "Lead" field was the only
            // door to the persisted `mixer.lead`, so a value dialled before its removal would
            // silently attenuate the first lead a future genre produces.
            normaliseDoorlessLeadMix()
            // #743: same shape again, one failure mode over — a stored master character that
            // no longer PARSES. The engine falls back to `.balanced` on its own, but nothing
            // rewrites the store, so the `@AppStorage`-bound Picker holds a raw value matching
            // no `.tag(...)` and SwiftUI renders no selection at all. Engine plays Balanced,
            // control reads blank, and the two disagree — which is the one thing #736's
            // one-owner design exists to prevent.
            normaliseUnparseableMasterCharacter()
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
            // Restore a CUSTOM play-surface patch across relaunch. Follow-the-take needs no
            // action here: with an empty selection `syncTouchSound()` would apply the take
            // patch, and the startup task's own Field default is the better landing before
            // any take exists (`SynthPatch.launchTouchPatch`).
            //
            // ⛔ WHAT STOOD HERE WAS FALSE TWICE OVER, and one of the two halves contradicted
            // the comment SIX LINES ABOVE IT — found by review during #402, in the very
            // commit whose thesis is that a comment with a wrong rationale is worse than none.
            // It read: "currentPatch is still the Init placeholder pre-generate — the app
            // startup already gave both voices the warm default."
            //   · `currentPatch` is NOT the placeholder here. It is assigned ~75 lines earlier
            //     in this same closure, from `presetIndex` or `style.synthPatch`.
            //   · "the app startup ALREADY gave" asserts the async startup task ran FIRST.
            //     The level-restore note just above says the opposite, and that one is the
            //     one backed by an observed symptom. Two comments, eight lines apart, in one
            //     closure, claiming opposite orderings.
            // Neither half is replaced by a new ordering claim, because #402 does not need
            // one: both launch paths now resolve a stored id to the SAME patch, so the fix
            // holds whichever runs first. Only the STALE-id case is order-dependent, and it
            // is written down where it lives (`SynthPatch.launchTouchPatch`).
            if !touchPatchID.isEmpty { syncTouchSound() }
            logLaunchMusicalIdentity()
        }
        .onChange(of: scenePhase) { old, phase in
            if phase == .active { handlePendingIntent(); updateKeepAwake() }
            // #400 — DISARM THE SOUND RESET ON THE WAY OUT. `soundResetArmed` is `@State` on a
            // view `WorkspaceView` never unmounts, so without this an arm survives a phone call
            // or a pocket and the NEXT tap is the destructive one. It rides this EXISTING
            // handler on purpose: a `.task`, a timer or a second `.onChange` would each be a new
            // modifier on the body, which is the one thing the black-screen law forbids.
            if phase != .active { soundResetArmed = false }
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
        // #275 — the ONE place a mood edit is written down, whichever control made it: the eight
        // knobs, the mood pad's drag, or applying a `MoodPreset`. Persisting at each of those
        // three sites instead would be three copies of one storage decision (#416), and the pad
        // is the one that would be forgotten — it writes two fields from inside a drag gesture.
        //
        // ⚠️ THIS IS NOT A PRESENTATION MODIFIER, and that distinction is the whole reason it is
        // allowed here. The black-screen law (10.76.34) is about the `.sheet`/`.fullScreenCover`/
        // `.alert`/`.fileImporter` chain, pinned at 14 on this body and 16 file-wide by
        // `ResetSoundClearsWhatTheLaunchLineReportsTests`; this adds none of those and leaves both
        // numbers untouched. Nor is it the freeze law (10.76.41/50): that one is about READING a
        // ~10 Hz `@Observable` in an ancestor body. `mood` changes at finger speed and is already
        // read here — this observes the value the body already depends on.
        .onChange(of: mood) { _, m in moodRaw = MoodStorage.encode(m) }
        // #614 Auto-Scheibe 4a — turning Auto OFF clears the steering policy, the hold
        // counters AND the per-parameter session pauses. This is NOT the forbidden
        // auto-resume (the graft law: nothing comes back unbidden): nothing un-pauses
        // by itself, but the Auto toggle is an explicit user gesture, and flipping it
        // off and on again is the ONE sanctioned way to hand a paused dial back to the
        // steering — without it the only reset would be an app relaunch, which no user
        // can discover. (Same #275 justification as the `mood` line above: not a
        // presentation modifier, and `autoMode` changes at toggle speed — an event
        // rate, and a value this body already depends on via @AppStorage.)
        .onChange(of: autoMode) { _, on in
            if !on {
                autoAttuneState = AutoAttune.State()
                log.log(.info, category: .automation,
                        "Auto attune: off — steering state and session pauses cleared")
            }
        }
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
            // playback-only stop". That instant is now: the chrome ■ raises the request
            // (#234/#179 — it lived in `WorkspaceView.TransportBar.toggle()` until #289
            // extracted it into `PlaybackToggleButton`, which is where it is today; the bar
            // itself dissolved with #456).
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
        // ONE modifier for both keep-awake flags, deliberately — the chain does not grow
        // (#486). `showMeditation` alone was dead weight (no setter anywhere); OR-ing the
        // reachable flag in keeps the unreachable one wired for the day it is re-doored,
        // instead of silently dropping it. `isRunning` flips twice per session, so reading
        // it in `body` is nowhere near the 10.76.41/50 freeze law — it is `pacer.guidance`
        // that is ~30 Hz, and that read stays inside `BreathCoachStrip`.
        .onChange(of: showMeditation || breathPacer.isRunning) { _, _ in updateKeepAwake() }
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
            // #318: the deep surface gets the SAME inventory the character menu and the delay
            // picker two rows above its door already use. Derived from `characterFXChains`,
            // never re-listed here — a second list is how #240 happened.
            AnyView(EchoelFXView(chain: synth.fxChain,
                         mirrors: characterFXChains.filter { $0 !== synth.fxChain },
                         pattern: beatPlayer.pattern,
                         // ⚠️ The READ stayed one-sided while the WRITE below became two-sided,
                         // which is the very asymmetry #318 is about. It cannot lie today: both
                         // voices default `isFXEnabled = true` and this closure is the only
                         // production caller of `setFXEnabled` in `Sources/`, so they cannot
                         // diverge. Left as one voice deliberately — a `&&` over the inventory
                         // would report "off" for a mix of states and there is no state that can
                         // produce that mix. If a second writer ever appears, this is the line.
                         fxEnabled: { synth.isFXEnabled },
                         // The gate travels with the parameters, or the take goes dry while the
                         // played notes stay wet — the same split reach, one control higher.
                         setFXEnabled: { synth.setFXEnabled($0); touchSynth?.setFXEnabled($0) })
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
                    MetalBioView(capturesVideo: true, reduceMotion: reduceMotion,
                                 autoAttuned: autoMode, toneHz: currentToneHz,
                                 intensity: Float(visualIntensity), ringDensity: Float(visualDetail),
                                 motion: Float(visualMotion), spread: Float(visualSpread),
                                 hueShift: Float(visualHue), saturation: Float(visualSaturation),
                                 textureAmount: Float(visualTexture), glitterAmount: Float(visualGlitter),
                                 structureAmount: Float(visualStructure),
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
                                .foregroundStyle(visualRecorder.isRecording ? EchoelTheme.recording : .white.opacity(0.85))
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
            // #495 — THE PROMISE HAD TO CATCH UP WITH THE SAVE. "the current sound, key, tempo
            // and generated loop" was written before `Project` carried either tuning axis or the
            // transport mode, and it stayed put through #493 (tone system) and #494 (Flow/Loop) —
            // so the app was quietly saving MORE than it admitted, on the one door that tells the
            // user what a save is. Under-claiming is the friendlier failure, and it is still a
            // false description: a player in Maqām Rāst at A=442 had no way to know that came
            // back. Everything named here is read straight off `currentProject()`.
            //
            // The second sentence is the part that earns its length: the mixer levels live in
            // `MixerStore`, which persists each role straight into `UserDefaults` — a console
            // setting, not a take property — and only the FX CHARACTER travels (`open(_:)`
            // re-stamps every chain from `fxCharacter`), so hand-dialled FX does not. Naming the
            // two omissions costs one line and prevents the far worse discovery that a saved
            // take came back sounding different.
            //
            // ⛔ THE FIRST DRAFT OF THIS COMMENT SAID THE MIXER LEVELS ARE `@AppStorage`, in
            // both places it explains them. They are not — `MixerStore.bass/pad/lead/drums` are
            // plain `Float`s whose `didSet` calls `persist(_:_:)`. The SUBSTANCE survives (same
            // defaults database, same global scope, still absent from `Project`'s CodingKeys),
            // but the mechanism was named from the shape of its neighbours instead of looked up
            // — the #489 class, in the slice whose whole subject is a description that stopped
            // matching what it describes.
            //
            // ⭐ `mood` JOINED IN #275 SLICE 2, and it is named here for the reason the whole
            // #495 law exists: the eight dials had NO persistence at all until slice 1, so a
            // sentence written before that could not have named them — and the moment they
            // started travelling with the take, a sentence that omits them under-claims again.
            // One word, because the user has one mental object ("the mood knobs"), exactly like
            // `tuning` standing for `a4Hz` + `toneSystemID`; the wire case below is what keeps
            // that shorthand honest.
            //
            // ⚠️ WHERE THE `+` BREAKS IS NOT COSMETIC. The #495 guard reads this closure as a
            // literal and asserts two CONTIGUOUS phrases in it; a wrap that lands mid-phrase
            // turns that guard red on correct code. The first draft of this edit split
            // "stay with / the instrument" and did exactly that — caught by measuring, not by
            // the reviewer. Both pinned runs must stay inside one literal each.
            Text("Saves the loop with its genre, key, tuning, tempo, Flow/Loop mode, mood, "
                 + "sound and FX character. Your mixer levels and hand-dialled FX "
                 + "stay with the instrument.")
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
                // #593b/#593c — the voice half of the save is decided by ONE
                // definition, `patchCarryingLiveVoice` (share-label law, the F1
                // misattribution guard, the F2 post-Clear strip — all documented at
                // the helper). Both save doors — this alert and "Save changes" in
                // the sound-actions menu — call it, so the answer to "does my saved
                // sound carry my voice?" cannot depend on which door was used
                // (#593b check 4, the asymmetry a player could never see).
                let saved = patchStore.saveAs(patchCarryingLiveVoice(currentPatch), name: name)
                currentPatch = saved
                presetIndex = -1
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current timbre as a named sound you can recall.")
        }
    }

    // MARK: - The voice half of a save (#593c)

    /// The ONE answer to "what voice half does a saved patch carry?" — all THREE save
    /// doors ("Save as…", "Save changes", and since #600 the project door
    /// `currentProject()` behind Save/autosave/Live Colabo) call this, per #416: a
    /// second spelling was exactly the #593b check-4 asymmetry, where save-as embedded
    /// the live capture and the in-place save silently did not — and the project door
    /// repeated that asymmetry one level up until #600.
    ///
    /// LIVE PROFILE PRESENT → provenance decides, never a proxy. ⛔ TWICE WRONG BEFORE
    /// (#593b F1, then the #593c review's F1): the first version relabeled
    /// UNCONDITIONALLY; the second compared the live taps against the CURRENT base
    /// patch — which broke the moment the player switched patches under a surviving
    /// profile (recall artist X's voice patch, pick a genre default, save: X's taps
    /// no longer compare equal to the tapless base, so X's voice was embedded
    /// relabeled as the current player). The fix is memory, not comparison:
    /// `PolySynthVoice.appliedVoiceProfileLabel` remembers what the live profile
    /// ARRIVED as. Label present = embedded provenance — it travels verbatim, and
    /// when the base ALREADY carries its own half it stays byte-identical (a 64-tap
    /// third-party half is not truncated to the engine's 32). Label nil = a fresh
    /// capture this launch — this player's voice, labeled at this save through
    /// `typedArtistName`, the one definition of "did the user name themselves" (the
    /// stored value is never "": it holds the E~ mark, so a raw isEmpty gate would
    /// mislabel every unnamed player); blend 1, `applyVoiceProfile`'s own default.
    ///
    /// NO LIVE PROFILE → strip, but ONLY a half the engine would have accepted
    /// (`voiceProfileTapFloor`, the socket's own definition). ⛔ F2 (#593b review,
    /// sharpened by the #593c review): "live nil = player cleared" is true only for
    /// an ACCEPTED half — a short third-party half is refused by `applyVoiceProfile`
    /// and was never live, so Clear cannot have cleared it; stripping it would
    /// destroy a shared voice (and its attribution) the player never even heard.
    /// An acceptable half + live nil has exactly one reachable cause — every recall
    /// path applies the patch in the same breath, so only `clearVoiceProfile()` can
    /// nil the memory — and for that state, stripped IS the correct save.
    private func patchCarryingLiveVoice(_ base: SynthPatch) -> SynthPatch {
        var patch = base
        if let taps = synth.appliedVoiceProfile {
            if let label = synth.appliedVoiceProfileLabel {
                if patch.voiceProfileTaps == nil {
                    patch.voiceProfileTaps = taps
                    patch.voiceProfileLabel = label
                    patch.voiceProfileBlend = synth.appliedVoiceProfileBlend ?? 1
                }
                // base already carries its own half: keep it byte-identical.
            } else {
                patch.voiceProfileTaps = taps
                let artist = SessionContext.typedArtistName(fromStored: session.artistName)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                patch.voiceProfileLabel = artist.isEmpty ? "My voice" : artist
                patch.voiceProfileBlend = 1
            }
        } else if let existing = patch.voiceProfileTaps,
                  existing.count >= synth.voiceProfileTapFloor {
            patch.voiceProfileTaps = nil
            patch.voiceProfileLabel = nil
            patch.voiceProfileBlend = nil
        }
        return patch
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

    /// UNPRESENTED BY FOUNDER DECISION (2026-07-07, v10.79.87 `de728a5`: "Xy Pads komplett
    /// wieder herausnehmen") — kept compiling for reversibility, no body branch mounts it.
    /// The two mood pads, side by side: SOUND (composition mood; recomposes at the loop
    /// boundary on release) and VISUAL (palette + energy, live via its own leaf).
    ///
    /// ⛔ #322 RE-MOUNTED THIS AND #329 TOOK IT BACK OUT THE SAME DAY. Worth the space,
    /// because the mistake is the cheapest kind to repeat:
    ///
    /// I cited "founder 2026-07-07: Xy Sound und visuals verknüpfen" as the reason to
    /// restore it. That ask is REAL and it is on the SAME DAY — and it is the EARLIER one.
    /// It shipped as v10.79.85, the founder tested it on device, and v10.79.87 took the
    /// pads out. `scratchpads/SESSION_LOG.md` has both, in order. So the quote I built on
    /// was not stale; it had been ANSWERED, and the answer was no.
    ///
    /// The marker saying so was this line — the property's own first doc line, directly
    /// above the code I edited. I read the block and not its header, which is precisely
    /// what `CLAUDE.md` says about its own H1 twice over: **the heading is part of the
    /// claim.** And I then appended a paragraph below it that asserted the opposite, so
    /// the file stated both at once until the reviewer caught it.
    ///
    /// ⚠️ THEREFORE, BEFORE ANYONE RESTORES THIS: it is not a doorless-capability find,
    /// it is a founder-gated decision, and the founder's answer came AFTER hearing it on
    /// a device. Ask; do not infer it from the 07-06D/07-07 "XY Pad" quotes, which is
    /// exactly the inference that failed. If the answer is yes, two things ride along that
    /// the review surfaced: `MoodXYPad`'s outline uses `EchoelTheme.border` (0.10) against
    /// `surface`, ≈1.1:1 — the same WCAG 1.4.11 failure `EchoelValueField` already fixed
    /// with `borderStrong`; and the sound→visual link writes `visual.*` without clearing
    /// `visualPresetID`, so the Visual panel would keep naming a preset that no longer
    /// describes the output. A third rides along since #614: the pad writes the two
    /// steered dials (darkness · liveliness) — its restore must set the same session
    /// pauses the mood knobs' `pausing:` parameter sets, or the pad becomes the one
    /// mood gesture whose edit Auto mode does NOT yield to.
    ///
    /// What #322 DID leave behind on purpose: the Sound half is now `SoundMoodPadLeaf`
    /// rather than inline state on this view. Same keys, same defaults, same behaviour —
    /// but the drag no longer re-evaluates this ~500-line body, so the parked code is
    /// correct on the freeze law for the day it is asked for.
    private var moodPadsSection: some View {
        HStack(alignment: .top, spacing: 12) {
            SoundMoodPadLeaf { x, y in
                mood.darkness = Float(1 - x)
                mood.liveliness = Float(y)
                // A pad gesture is a custom edit — the loaded preset no longer
                // describes the sound (same rule as the mood editor).
                moodPresetID = nil
                moodPresetName = "Custom"
                recomposeIfRunning()
            }
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
    /// ⭐ #411 — THE TEMPO FIELD JOINED THIS ROW (founder 2026-08-05, screenshot with the
    /// chrome tempo row circled and an arrow pointing down here: *"Die Zeile mit den bpm und
    /// Schloss in rot umrandet soll dort hin wo der rote Pfeil hinzeigt migrieren."*).
    ///
    /// It lands between the transport buttons and the readout, which is the ordering #307
    /// already built this row on — and it is where a musician looks for a tempo, because it is
    /// where every DAW puts it. Nothing about the control changed: same
    /// `BodyTempoField(compact: true)`, same "tempoLock" post, same shared `@AppStorage`
    /// keys as the chrome copy it replaces. There is still exactly ONE musical-tempo control.
    ///
    /// ⚠️ FREEZE LAW, EXTENDED TO A THIRD CHILD. `BodyTempoField` reads the ~10 Hz camera
    /// publisher in its OWN body — that is why it can be mounted here at all. CONSTRUCTING it
    /// registers nothing; only a body that READS state subscribes. The same argument that
    /// admits `PulseMonitorMiniLive` and `PlaybackToggleButton` admits this one, and it is the
    /// reason all three are `struct`s instead of inline `HStack` content.
    ///
    /// ⚠️ THE COST IS WIDTH, AND IT IS PAID BY THE READOUT. The pill is the only flexible
    /// child, so it absorbs the ~114 pt the field and its lock take (76 + 30 + spacing) — on a
    /// 393 pt phone with a session running that leaves it roughly 150 pt instead of 300. The
    /// founder asked for a BIGGER analysis display on 2026-07-31 (#305/#307), so this is two of
    /// his asks pulling against each other and it needs a device look, not a taste argument.
    /// If it reads too cramped, the cheapest answer is to move `TransportPositionView` and the
    /// "•••" overflow OUT of the chrome bar as well and give this row a second line — NOT to
    /// send the tempo back up.
    ///
    /// ⭐ #456 — THAT SENTENCE WAS CARRIED OUT (founder 2026-08-07, screenshot of v10.79.371
    /// with the "•••" and the `1.1.1 / loop 1/32` readout each circled and an arrow drawn INTO
    /// this row). `TransportBar` held exactly those two children after #411 took the tempo
    /// field; both are here now and the bar is deleted. The chrome is two bars, not three.
    ///
    /// ⚠️ TWO LINES, NOT ONE, AND THE REASON IS THE MEASUREMENT ABOVE — not taste. One line
    /// would have to fit ▶ + ⏸ + tempo + lock + "•••" + the readout AND the analysis pill the
    /// founder asked to make BIGGER (#305/#307). ⛔ THE FIRST VERSION CITED "roughly a third of
    /// the pill's width" and attributed it to the paragraph above. That paragraph says
    /// something else — **roughly 150 pt instead of 300** — and it says it about the FOUR-child
    /// row, not this six-child one. The number was invented in the act of quoting a number,
    /// which is the defect this file family keeps paying for. What the source actually
    /// supports: four children already halve the pill; the two migrants add about 30 pt of
    /// chip, ~100 pt of readout and two more 8 pt gaps, so a single line leaves the pill a
    /// fraction of even that 150 — worse than half, and worse than a third.
    ///
    /// **Line 1 is bit-for-bit what it was**, so nothing that
    /// exists today can be squeezed by this change.
    ///
    /// ⚠️ THE HEIGHT ARITHMETIC GOES THE RIGHT WAY, BUT BARELY, and the first version of this
    /// paragraph overstated it by roughly 3×. Removed: the deleted bar's `minHeight: 44` — and
    /// NOT "plus its spacing", because the chrome stack is `VStack(spacing: 0)`. Added: a
    /// ~32 pt second line PLUS this `VStack`'s own 8 pt gap, so ~40 pt. Net ≈ **4 pt**, not
    /// ~12. The direction survives; the margin does not, and a margin that thin is a device
    /// look rather than a claim. If the founder still wants one line, that is also a device
    /// look at the pill's width, not a guess from here.
    ///
    /// ⛔ AND ONE OF THE TWO MIGRANTS LEFT AGAIN (#490, founder 2026-08-07, screenshot of
    /// v10.79.374). `TransportPositionView` now lives in `WorkspaceView.topBar`, where the
    /// colour bars used to be — the founder's arrow ran from the scribbled-out spectrum down to
    /// the circled readout. The "•••" stays. So this row is TWO lines, and the height sum from
    /// #456 has to be read backwards: the ~40 pt that line 3 cost comes back, which is the only
    /// reason the analysis pill is not squeezed by anything in this slice.
    ///
    /// ⚠️ THE FREEZE ARGUMENT MOVED WITH IT AND GOT HARDER, so do not read its absence here as
    /// "no longer relevant". `TransportPositionView` reads `transport.position` (~10 Hz at
    /// 120 BPM) in its OWN body; that is why it was a separate `struct` in the chrome, why it
    /// could be mounted here, and why it can be mounted in the ROOT header now. Its new host is
    /// an ancestor of every surface in the app, so inlining its two labels there would be the
    /// 10.76.50 freeze at full strength. It stopped being `private` for the #456 move and stays
    /// non-`private` for this one. What survives HERE is the same law for the row's own
    /// children: `PulseMonitorMiniLive` and `PlaybackToggleButton` read live state in their own
    /// bodies, and this body must keep reading none of it.
    private var startControlRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            // LINE 1 — unchanged since #411. Do not add to it; that is what makes the claim
            // above ("nothing that exists today can be squeezed") true rather than hopeful.
            HStack(spacing: 8) {
                startButton
                PlaybackToggleButton()
                BodyTempoField(onLockChanged: {
                    NotificationCenter.default.post(name: .echoelCompositionEdited,
                                                    object: "tempoLock")
                }, compact: true)
                #if canImport(AVFoundation)
                PulseMonitorMiniLive()
                #endif
            }
            // #585 — the one visible consequence of `AudioEngine.degraded`, which had no reader
            // at all until now. Renders nothing while audio is healthy, so this row keeps its
            // exact layout in the normal case; it is a `View` of its own so that a live audio
            // object never gets read from this body (freeze law). It sits directly under the
            // Start button because that is where a player looks when pressing Start produced
            // no sound, and it is a banner rather than an alert because the body's presentation
            // chain is at 14 and a 15th is the black-screen SIGSEGV.
            AudioDegradedRow()
            // #596 — the plug-in invitation, same shape as the degraded banner above:
            // renders nothing until a wired/USB device is freshly plugged in, its own
            // leaf `View` (freeze law), no presentation modifier (the tap reuses the
            // existing `showInput` sheet slot — the 10.76.34 black-screen law untouched).
            // ⚠️ The watcher is started from the ROOT `.onAppear`, NOT from a modifier
            // here: this row renders NOTHING while there is no invitation, and
            // `.onAppear` on conditionally-empty content does not reliably fire — a
            // watcher started there would never observe the first plug.
            #if os(iOS) && canImport(AVFoundation)
            PlugInInviteRow(watcher: plugInWatcher) { showInput = true }
            #endif
            // LINE 2 — the actions (#482). See `quickActionRow`.
            quickActionRow
            // FIRST-RUN LINE (GUI-Board Scheibe 5, UX#7): the tiles above are grey until
            // something has composed, and the audit found first-run users reading them as
            // BROKEN — the explaining sentence sat inside the Save & Export panel, behind
            // a chip nobody opens first (#482's "the row has no space for it" judged a
            // PERMANENT sentence; this one renders only while nothing has composed and
            // leaves at the first take, so it spends the plate's height exactly while the
            // plate is idle). NOT the #382 class the quickActionRow doc decides against:
            // that verdict covers a mid-take status line inserting/removing on events the
            // user did not trigger — this is a one-way exit on the user's OWN first Play.
            // `hasComposed` is `@State`, event-rate (freeze law). Wording history (#272,
            // #355b — name the control that actually starts) lives at the panel tombstone.
            if !hasComposed {
                Text("Press Play first — then you can record the loop, save the session, or export a WAV or MIDI file.")
                    .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // LINE 3 — the doors (#492). See `quickDoorRow`. A THIRD line is back, four
            // slices after #456 deleted one, and the honest accounting is that it costs the
            // ~40 pt #490 handed the plate back (the ~32 pt line plus this `VStack`'s 8 pt
            // gap). It is not a free re-add: it is the price of the founder's *"Das mit den
            // drei Punkten als einzelnde Buttons anzeigen"*, and the arithmetic below says
            // there is no one-line version of that ask to buy instead.
            quickDoorRow
            // ⛔ LINE 3 IS GONE (#490, founder 2026-08-07). It held `TransportPositionView`
            // alone — the loop capsule plus `1.1.1 / loop 1/8` — because a ~100 pt monospaced
            // label plus six 44 pt targets does not fit a 375 pt phone (6×44 + 5×8 = 304 of 343
            // usable), so the readout took a line of its own rather than squeezing the row.
            // The founder's arrow moved it into the brand header instead: *"die bunten Balken
            // weg stattdessen die Anzeige für die Loop Länge und der Balken."* It is one
            // readout with one address — a copy here as well would be #416 — so the line is
            // deleted rather than emptied, and the instrument gets ~40 pt of its plate back —
            // the ~32 pt line PLUS this `VStack`'s own 8 pt gap, the same arithmetic the #456
            // note above states in the other direction. (⛔ This read "~32 pt" until #491, which
            // is the LINE and not what the plate recovers; two numbers for one fact, 36 lines
            // apart, both defensible in isolation — exactly the drift this file family keeps
            // retracting. The gap is not optional accounting: removing a child of a spaced
            // `VStack` always removes one gap with it.)
        }
    }

    /// ⭐ THE ROW THE FOUNDER ASKED FOR (#482, 2026-08-07, second screenshot): *"alles aus dem
    /// zweiten Bild was rot markiert ist, intelligent und übersichtlich im selben Button Format
    /// in eine Reihe unter dem Play etc zusammengefasst"*. Red-marked there: the "•••" entries,
    /// the position readout, the "Save & Export" chip and that panel's whole body. What was
    /// scattered over a menu, a chip and a dropdown is now equal chips under the transport,
    /// all `EchoelIconTile` — the "selbe Button Format", literally one declaration.
    ///
    /// Left to right: Record/abort · Keep last · Export MIDI · Save.
    ///
    /// ⛔ IT WAS SIX ON ONE LINE UNTIL #492, and the split is the founder's third ask on the
    /// same screenshot: *"Das mit den drei Punkten als einzelnde Buttons anzeigen."* Dissolving
    /// the "•••" turns six tiles into seven, and seven do not fit one line on the narrowest
    /// phone this app ships to — the arithmetic is in `quickDoorRow`'s doc. Open moved down
    /// with the two new door tiles because the honest boundary is "acts on this take" (here)
    /// versus "leaves this take" (there), not "wherever there happened to be room".
    ///
    /// ⚠️ THEY MOVED, THEY WERE NOT COPIED. The panel does not keep a second Save button; two
    /// doors to one action is the shape this repo keeps paying for (#416), and a row that only
    /// duplicates a panel is not a consolidation. What the panel KEEPS is everything a glyph
    /// cannot say: the loop length these buttons act on, the keep-last availability sentence,
    /// the failure line, the place toggle, Reset sound and Diagnostics.
    ///
    /// ⚠️ THE COST IS THE LABELS, AND IT IS PAID RATHER THAN HIDDEN. "Record 64 bars → send"
    /// and "Keep last: 8 bars or fewer at this tempo" were full-width sentences; they are now
    /// glyphs. Two things carry that weight: every tile carries its sentence as its
    /// `accessibilityLabel` (so VoiceOver loses nothing at all — Save and Open gained wording,
    /// the other four kept theirs), and the panel keeps `KeepLastAvailabilityNote` as text
    /// next to the picker that produces it. A mute disabled chip with its reason deleted
    /// would be the lying-control class.
    ///
    /// ⛔ AND THE FIRST VERSION OF THAT SENTENCE SAID "the two STATEFUL sentences", WHICH IS
    /// WRONG IN BOTH DIRECTIONS. The place-row caption is a STATIC string, not state. And
    /// `exportLabel` — which really does carry four states ("Record 8 bars → send" / "Stop and
    /// discard this take" / "Recording loop…" / "Writing .wav…") — is rendered as text
    /// NOWHERE any more. So a sighted user mid-take sees only a glyph swap to `stop.circle`.
    ///
    /// ⛔ AND THAT PARAGRAPH ENDED ON "and the bar count is gone from the screen entirely",
    /// WHICH WAS TRUE FOR ABOUT AN HOUR. #456 moved `TransportPositionView` out of the chrome
    /// transport bar and #490 gave it the middle of the brand header, where it renders
    /// `loop \(barInLoop + 1)/\(bars)` UNCONDITIONALLY — same `@AppStorage("studio.loopBars")`
    /// key, same `.eight` default, so its `bars` IS the number `loopBars.label` was saying.
    /// The count a user needs before tapping Record is therefore permanently on screen, one
    /// band up, and it was already there when this comment claimed it was gone. Same class as
    /// the retraction in `WorkspaceView` five lines under that readout's own mount: a note
    /// whose subject was fixed by a later slice on the SAME DAY reads as if nothing happened.
    /// `TheBarCountHasACarrierTests` now pins the carrier, so this cannot go stale silently
    /// in the other direction either — deleting the header readout has to notice it is
    /// load-bearing for two things now, not one.
    ///
    /// ⭐ WHAT SURVIVES IS THE SMALLER, REAL HALF: mid-take there are no WORDS. The glyph
    /// carries three states (`square.and.arrow.up` → `stop.circle` → `hourglass`) and VoiceOver
    /// carries all four, but a sighted user cannot read "Writing .wav…". #482 left that as a
    /// founder-visible layout call because a fourth line in this stack is exactly the height
    /// #456 reclaimed. **That call has now been made and the answer is no.** The founder's
    /// second red outline on 2494 (2026-08-08) covers precisely this stack and asks for
    /// *"Usability und kompactheit … aufräumen"* — a permanent fourth line spends the height
    /// the ask is about, and a CONDITIONAL one is the #382 class in the one stack #382 was
    /// written for (it would insert on take start and remove itself on a take END that the
    /// user did not trigger, six seconds after they stopped expecting it). Not deferred,
    /// DECIDED — reopen it only with a founder ask that names the line, not by reading this
    /// paragraph as a to-do.
    ///
    /// ⚠️ FREEZE LAW. Nothing here reads a high-frequency `@Observable` in this body:
    /// `exporter.status` changes at the start and end of a take, `hasComposed` is `@State`,
    /// `projects.projects` is a store. The one tempo-derived value — whether "keep last" fits
    /// in the ring at the current BPM — is read inside `KeepLastLoopButton`'s OWN body, which
    /// is why that control has been a separate `struct` since it was written and stays one.
    /// The Save action reads `beatPlayer.pattern.tempo` inside its CLOSURE, which registers no
    /// observation at all.
    private var quickActionRow: some View {
        HStack(spacing: 8) {
            // ONE button, two jobs — start the take and abort it (founder 2026-07-28,
            // *"wichtig das man die Aufnahme dann auch abbrechen kann"*). `exportIcon` already
            // carried all three states as glyphs before this move
            // (`square.and.arrow.up` → `stop.circle` → `hourglass`), which is the reason this
            // control survives becoming icon-only without inventing anything.
            Button {
                if exporter.isCancellable { exporter.cancel() } else { Task { await exportWav() } }
            } label: {
                EchoelIconTile(systemImage: exportIcon, prominent: true, expands: true,
                               enabled: !isRecordButtonInert)
            }
            .buttonStyle(.plain)
            .disabled(isRecordButtonInert)
            .accessibilityLabel(exportLabel)
            .accessibilityHint(exporter.isCancellable
                ? "Stops this take and discards it. Nothing is saved."
                : "Records one loop and exports a WAV to share")

            KeepLastLoopButton(pattern: beatPlayer.pattern, bars: loopBars,
                               isExporting: isExporting, hasComposed: hasComposed,
                               busyLabel: busyStatusLabel) { Task { await keepLastLoop() } }

            Button { exportMIDI() } label: {
                EchoelIconTile(systemImage: "pianokeys", expands: true,
                               enabled: !isExporting && hasComposed)
            }
            .buttonStyle(.plain)
            // `isExporting` is a WAV concern, but both writers land in the ONE `share` slot, so
            // a MIDI export mid-record would silently replace the WAV the user is waiting for.
            .disabled(isExporting || !hasComposed)
            .accessibilityLabel("Export MIDI for your DAW")
            .accessibilityHint("Exports the take as a MIDI file to open in a DAW, with tempo and key")

            Button {
                saveName = session.sessionName(bpm: beatPlayer.pattern.tempo)
                showSaveDialog = true
            } label: {
                EchoelIconTile(systemImage: "tray.and.arrow.down", expands: true,
                               enabled: hasComposed)
            }
            .buttonStyle(.plain)
            .disabled(!hasComposed)
            .accessibilityLabel("Save this session")
            .accessibilityHint("Names the session and saves it. The place row in Save & Export decides whether your city is in that name")

        }
    }

    /// ⭐ THE DOORS — founder 2026-08-07, third of four asks on the v10.79.374 screenshot:
    /// *"Das mit den drei Punkten als einzelnde Buttons anzeigen."* The "•••" overflow is
    /// dissolved; its two entries are tiles now, in the same `EchoelIconTile` format as
    /// everything else on this plate.
    ///
    /// Left to right: Open a saved session · Live Colabo · Learn and news.
    ///
    /// ⚠️ WHY A SECOND LINE RATHER THAN ONE ROW OF SEVEN, and this is arithmetic, not taste.
    /// Every tile carries a hard 44 pt minimum width (`EchoelTheme.controlTapHeight`, the
    /// #113 floor), the row spaces at 8, and `startControlRow` is padded 16 on each side. So
    /// seven tiles need `7×44 + 6×8 = 356` pt of usable width. A 393 pt phone offers 361 —
    /// five to spare — but a 375 pt phone offers 343 and a 360 pt one (iPhone 12/13 mini, both
    /// on iOS 18) offers 328. On the narrowest phone this app ships to, seven 44 pt targets in
    /// one line overflow by 28 pt. There is no spacing that fixes it honestly: even at 4 pt
    /// gaps the row still needs 332. The ask is answerable in two lines or not at all.
    ///
    /// ⚠️ THE TRAILING `Spacer(minLength: 0)` IS LOAD-BEARING, not tidying. `expands` gives
    /// each flexible child of an `HStack` an equal share, so three tiles alone would be a
    /// third wider than the four above them — in the row whose entire brief is *"die sollen
    /// immer gleichgroß sein"* (#481/#482). A fourth flexible slot that draws nothing makes
    /// both lines four-up, so all seven tiles are one width on every device, and the blank
    /// lands at the END of the LAST line where it reads as a grid rather than as a hole.
    ///
    /// ⚠️ THE SPLIT IS "acts on this take" ABOVE, "leaves this take" HERE. Record · Keep last ·
    /// Export MIDI · Save all stay in the take you are playing; Open loads a DIFFERENT one,
    /// Live Colabo joins other people, Learn is news and docs. Save is above rather than below
    /// on purpose — naming a take does not leave it.
    ///
    /// ⛔ THESE TWO ARE NOT CHIPS, AND THAT REASON SURVIVED THE MENU (#290). Live Colabo and
    /// Learn are the only global doors that are NOT panels — they present full sheets
    /// (`showLiveColabo`, `showLearn`). The chip strip's grammar is "this chip selects what the
    /// plate shows", so a chip that opened a modal would be a lying tab. Buttons in the action
    /// block have no such grammar to break. **No new `.sheet` is added by this slice**: both
    /// sheets already hang on the body, so the presentation chain the black-screen law
    /// (10.76.34) guards is untouched — this changes who taps them, not how many there are.
    ///
    /// ⚠️ AND THEY SET `@State` DIRECTLY INSTEAD OF POSTING `.echoelChromeDoor`, which the
    /// menu did. That round trip was already same-view since #456 (the studio posted and
    /// received), and with the menu gone the notification's `"live"`/`"learn"` cases would
    /// have had NO producer at all — a `case` that compiles silently and reads like a live
    /// hook, which is the exact shape the receiver's own ⛔ block deleted four of in #290. The
    /// notification keeps its real producers (the header monitor tiles post `"video"`,
    /// `"routing"`, `"bio"`); it just stops carrying a message from this view to itself.
    ///
    /// ⚠️ FREEZE LAW. Nothing here reads a high-frequency `@Observable`: `projects.projects`
    /// is a store, and the two door flags are `@State` written from a closure, which registers
    /// no observation at all.
    private var quickDoorRow: some View {
        HStack(spacing: 8) {
            Button { showOpen = true } label: {
                EchoelIconTile(systemImage: "tray.and.arrow.up", expands: true,
                               enabled: !projects.projects.isEmpty)
            }
            .buttonStyle(.plain)
            .disabled(projects.projects.isEmpty)
            .accessibilityLabel("Open a saved session")

            #if canImport(MultipeerConnectivity)
            Button { showLiveColabo = true } label: {
                EchoelIconTile(systemImage: "dot.radiowaves.left.and.right", expands: true)
            }
            .buttonStyle(.plain)
            // The label the menu entry carried, verbatim — an icon-only control must say what
            // it is (#489), and "Live Colabo" alone would not tell a first-time listener that
            // it is about playing WITH someone in the room.
            .accessibilityLabel("Live Colabo — play together nearby")
            .accessibilityHint("Opens the nearby-session sheet to play together on one tempo")
            #endif

            Button { showLearn = true } label: {
                EchoelIconTile(systemImage: "book", expands: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Learn and news")
            .accessibilityHint("Opens the body-science library and release notes")

            // See the property's doc: this draws nothing and exists so all seven tiles are one
            // width. Removing it widens this line's three by a third and breaks the founder's
            // "immer gleichgroß" on the row it was asked for. (⚠️ ONE flexible blank, sized for
            // the three tiles above it. On a platform without MultipeerConnectivity this line
            // is two tiles and the widths diverge — stated rather than branched on, because
            // every target this app ships to has the framework and an untestable `#else` is
            // worse than a named limit.)
            Spacer(minLength: 0)
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
                // ⛔ HEIGHT WAS `FloatingVisualLayout.startButtonHeight` (56) UNTIL #481.
                // Founder 2026-08-07: *"die sollen immer gleichgroß sein. Orientiere dich an
                // denen oben rechts."* The header tiles are 32 visible / 44 tap, so this is
                // too, and the WIDTH stays 64 — a primary transport reads as primary by being
                // wider than its 30–38 pt neighbours, which is exactly the distinction the
                // "64 is a CHOICE, not a fit" paragraph above was making.
                //
                // ⚠️ `FloatingVisualLayout` IS DELIBERATELY NOT CHANGED WITH IT, and that is a
                // decision rather than an oversight. `studioControlBandHeight` (= 56 + 4 + 10)
                // is what `FloatingVisualWindow.defaultCenter` lifts the docked card by; since
                // #288 moved this button to the TOP of the stack, that sum buys a bottom MARGIN
                // and no longer clears anything. Feeding the new 32 into it would slide the
                // docked visual up 24 pt on the founder's device in a commit about button size.
                // Whether the card should drop those points is a look decision that belongs to
                // the founder — it is filed, not taken here. The honest consequence is that the
                // constant's NAME now overstates its job; that note lives at the declaration.
                .frame(height: EchoelTheme.controlHeight)
                // Website CI: primary action = off-white fill, black glyph (.btn-primary).
                // Green is reserved for live bio signal, not chrome. Stop = neutral fill with
                // a border, so the running state still reads as a raised control rather than
                // dissolving into the plate.
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(running ? EchoelTheme.fill : EchoelTheme.text))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(running ? EchoelTheme.borderStrong : Color.clear, lineWidth: 1))
                // The 44 pt tap frame sits AFTER background+overlay, exactly as the header
                // tiles spell it — put it before them and the chip would be PAINTED 44 tall,
                // i.e. the picture would grow instead of the hit area, which is the opposite
                // of the #113 idiom. Vertical only: the row is 8 pt-spaced and horizontal
                // growth would overlap the ⏸ beside it.
                .frame(height: EchoelTheme.controlTapHeight)
                .contentShape(Rectangle())
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

    /// The instrument says when it is not at standard tuning — and #325 is why this
    /// exists at all, doored on 2026-08-02 after sitting unpresented since 2026-07-09.
    ///
    /// ⭐ THE EVIDENCE THAT DECIDED IT, because "should a warning have a door?" is not a
    /// question a taste argument settles. On 2026-08-02 the founder reported "es klingt
    /// sehr unharmonisch" and sent a screen recording in which the concert pitch walks
    /// 440 → 483,4352 → 500,0000 Hz — the header strip's own scroll gesture feeding the
    /// A4 field (#391/#392 closed that cause). The value is PERSISTED, so it survived
    /// relaunch, and for the whole time the instrument was a semitone and a half sharp
    /// there was nothing on screen that said so. The cause is fixed; this is the part
    /// that would have made the SYMPTOM legible while it was happening.
    ///
    /// ⛔ SO IT NOW COVERS TWO THINGS, NOT ONE, and that widening is the point rather
    /// than a bonus. The version that sat here checked only the TONE SYSTEM
    /// (`tuningID != "edo12"`) — it would have been mounted, visible and SILENT through
    /// the founder's entire 500 Hz session, because the tone system was standard the
    /// whole time. Dooring it as written would have shipped a warning that does not
    /// warn about the thing that happened. The concert-pitch half is why it earns a door.
    ///
    /// Both are persisted settings that retune EVERY generated note — a non-12-TET
    /// system reads 15–30¢ off a 12-TET ear, and a 483 Hz reference is 158¢ sharp
    /// wholesale — and both are edited from the header strip, out of the eyeline of the
    /// front plate where the sound is judged.
    ///
    /// Hidden entirely at 12-TET + 440 (the defaults), so it costs zero chrome in normal
    /// use. That is also why it is a permanent line and not a dismissible one: a player
    /// who deliberately works at A=432 or in Maqām Bayātī gets a quiet factual statement
    /// of the frame they chose, which is information; a dismiss button would let the
    /// accidental case be waved away and re-hidden, which is the defect again.
    ///
    /// FREEZE RULE, and the first version of this paragraph was true but glossed the one
    /// case that matters. It said `session.a4Hz` changes "only on a user edit or a project
    /// open", which reads as ONE write. `EchoelValueField`'s drag writes its binding on
    /// every gesture event where the snapped value moves, so a deliberate VERTICAL scrub on
    /// the header A4 box writes it at gesture rate — `horizontalScrub: false` (#391) took
    /// away the sideways axis, not the up/down one. While that drag is in flight this
    /// banner's subtree re-evaluates per frame.
    ///
    /// That is bounded and it is not the 10 Hz law: the writer is a finger, not a sensor;
    /// no menu can be open during the drag, so nothing is torn down; and the read lands on
    /// the `EchoelPanel` node, not on `EchoelStudioView.body` — `panel(…)` hands its content
    /// to `EchoelPanel` as an `@escaping @ViewBuilder`, which is a real observation boundary
    /// (the same one `menuPanelHost` relies on). What it is NOT is free: the Sound panel is
    /// the visible plate while that header drag happens, so its ~24 children re-evaluate for
    /// the duration. Hoisting this banner into its own leaf `View` is the house cure and is
    /// filed as #395 rather than done blind here — the honest statement now, the structural
    /// fix as its own slice.
    ///
    /// Nothing else on `SessionContext` can invalidate this: `@Observable` tracks per
    /// property, and `a4Hz`'s complete writer set in `Sources/` is the header field, project
    /// open, and `resetTuningToStandard` below.
    @ViewBuilder private var nonStandardTuningBanner: some View {
        if toneSystemIsNonStandard || concertPitchIsNonStandard {
            HStack(spacing: 10) {
                Image(systemName: "tuningfork")
                    .foregroundStyle(EchoelTheme.dim)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(nonStandardTuningTitle)
                        .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Every note is retuned to this. Sounds off? Return to standard.")
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // #621 (Ultraaccessible-Audit): `.combine` sits HERE, on the two-Text
                // stack — NOT on the outer HStack, where it stood until this slice and
                // swallowed the "Standard" recovery button into one merged element,
                // dropping its hint and its individual focus. The one control that
                // rescues a wrong-sounding instrument must be its own element for the
                // user who cannot see it. (The glyph above is hidden as decoration.)
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                // "Standard", not "12-TET": the button now returns BOTH dimensions, and the
                // old label named only one of them. It is also the word the sentence above
                // it uses, so the control and its explanation agree.
                Button("Standard") { resetTuningToStandard() }
                .font(EchoelTheme.font(13, .semibold))
                // `EchoelTheme.onPrimary`, not a raw `.black` — the token exists for exactly
                // this shape (a label on a `.text`-filled button) and #364 fixed the same
                // literal on the keypad's OK key. A raw `.black` reads identically today and
                // silently stops tracking the moment the primary fill is retuned.
                .foregroundStyle(EchoelTheme.onPrimary)
                // `minHeight: 44`, not `height: 34`. Two reasons, both of which only became
                // this control's problem when it got a door: 34 is 60 % of the HIG 44×44
                // floor by area (`TapTargetFloorTests` pins the same number on the two preset
                // overflow menus), and a FIXED height clips the label once Dynamic Type grows
                // it — the #353 class. A minimum floors the target without capping the text.
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
                .buttonStyle(.plain)
                .accessibilityHint("Returns to 12-tone equal temperament at A4 = 440 hertz")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .stroke(EchoelTheme.border, lineWidth: 1))
        }
    }

    /// The two halves of "is this instrument at standard tuning", named once so the banner,
    /// its headline and its reset cannot drift apart. Three call sites open-coding
    /// `abs(session.a4Hz - 440) >= 0.05` is how one of them ends up with a different
    /// tolerance than the other two and the banner starts contradicting its own button.
    private var toneSystemIsNonStandard: Bool { tuningID != "edo12" }

    /// Not `!= 440`: `a4Hz` is a `Double`, so an exact comparison would keep the banner up
    /// for a value that is 440 for every audible purpose. 0.05 Hz at A4 is 0.197 cents —
    /// roughly a twenty-fifth of the ~5 cents a trained ear resolves on a sustained tone.
    ///
    /// ⛔ The first version of this line justified the number as "well below the ±0.005 Hz
    /// the keypad can even express". That is backwards twice over: 0.05 is TEN TIMES 0.005,
    /// and the field passes no `decimals:`, so it inherits `EchoelValueField`'s default of
    /// FOUR — the keypad expresses 0.0001 Hz, which is exactly why the founder's recording
    /// could read 483,4352. The threshold is right and unchanged; the reason given for it
    /// was not, and a wrong reason is what lets a later session "correct" a correct number.
    private var concertPitchIsNonStandard: Bool { abs(session.a4Hz - 440) >= 0.05 }

    /// The banner's headline — it names only what is actually off standard, so a player
    /// working in Maqām Bayātī at 440 is not told their concert pitch is unusual.
    ///
    /// The Hz goes through `EchoelDecimalText` like every other user-visible decimal in the
    /// app (#267): a German player reads "443,25", and a hard-coded `%.2f` here would print
    /// a point in a panel where every neighbouring number prints a comma.
    private var nonStandardTuningTitle: String {
        let systemName = TuningSystem.named(tuningID).name
        let hz = EchoelDecimalText.string(session.a4Hz, decimals: 2)
        switch (toneSystemIsNonStandard, concertPitchIsNonStandard) {
        case (true, true):   return "Non-standard tuning: \(systemName), A4 = \(hz) Hz"
        case (true, false):  return "Non-standard tuning: \(systemName)"
        case (false, true):  return "Non-standard concert pitch: A4 = \(hz) Hz"
        // ⛔ Written out rather than left to `default:`. The first version folded this into
        // the pitch case, so a headline read for an all-standard instrument would have said
        // "Non-standard concert pitch: A4 = 440.00 Hz" — a sentence that contradicts its own
        // number. It cannot render today (the banner's `if` is this same pair), but an
        // unreachable branch that states a falsehood is exactly what a later refactor
        // promotes into a reachable one.
        case (false, false): return ""
        }
    }

    /// Both dimensions back to standard in one tap, with exactly the side effects the header
    /// strip's own edits produce — `handleCompositionEdit`'s `"tuning"` case for the system,
    /// its `"a4"` case for the reference.
    ///
    /// ⛔ AND "EXACTLY" IS A LOAD-BEARING WORD I GOT WRONG ONCE. The first version ended with
    /// an unconditional `recomposeIfRunning()` and a doc line claiming that was "ONE recompose
    /// at the end rather than one per dimension". Read the two cases: `"a4"` recomposes,
    /// `"tuning"` does NOT. So there was no per-dimension recompose to consolidate, and the
    /// unconditional call made a tone-system-only reset throw away the running take where the
    /// header's own tuning Picker deliberately keeps it — a button that is more destructive
    /// than the control it mirrors, in the one situation a player reaches for it because
    /// something already sounds wrong. The recompose now rides the pitch half alone, which is
    /// both halves' behaviour verbatim and still only ever fires once.
    ///
    /// The flags are captured BEFORE the writes: `concertPitchIsNonStandard` reads `session.a4Hz`,
    /// and the first branch sets it to 440, so re-reading it afterwards would answer for the
    /// post-reset world.
    private func resetTuningToStandard() {
        let systemWasOff = toneSystemIsNonStandard
        let pitchWasOff = concertPitchIsNonStandard
        if systemWasOff {
            tuningID = "edo12"
            applyTuning()
        }
        if pitchWasOff {
            session.a4Hz = 440
            applyConcertPitch(440)
            // Same reason as the "a4" edit path: the roll's note grid recolours with the
            // concert pitch, so push it now rather than at the next compose.
            pianoRoll.musicalA4Hz = 440
            recomposeIfRunning()
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
    //  · .session → chip REMOVED (step 2c, 2026-07-17), re-added by #290, and the CASE
    //               ITSELF DELETED by #359 step 3 (2026-08-01). The three states are kept
    //               in one line on purpose: this entry has been read as "the chip is gone"
    //               while the chip was in `studioChips`, which is the mistake `sessionPanel`'s
    //               own doc block had to retract. Today there is no case, no panel and no
    //               chip. The live name preview (SessionNamePreviewLeaf) still rides at the
    //               end of the header CompositionHeaderStrip; the place toggle moved into
    //               "Save & Export" and the weather toggles into Mood (step 1) and Field
    //               (step 2). Nothing here opens via the transport "•••" any more.
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
    /// ⭐ WHY THIS WAS A ONE-LINE CHANGE AND NOT A REBUILD, which is the whole reason it was
    /// safe: FOUR of the six overflow entries — Master, Save/Export, Tempo, Session — were
    /// already full `StudioMenu` cases with working panels (`masterPanel`, `utilityRow`,
    /// `tempoToolsPanel`, `sessionPanel`). They were not missing from the app; they were
    /// FILTERED OUT of this array and re-doored through a menu. So no surface is created, no
    /// `.sheet` is added, and the presentation chain is untouched (black-screen law).
    /// (`sessionPanel` is named here as HISTORY — #359 step 3 deleted it, and its one
    /// surviving control moved into `utilityRow`. Left in the sentence rather than edited
    /// out, because the sentence is an argument about #290 and rewriting it to match today
    /// would make it claim something #290 never did.)
    ///
    /// THE ORDER IS THE SIGNAL CHAIN, then context, then what you do when the take is done:
    ///   Sound → FX → Mix → Master   (the voice, what happens to it, the balance, the sum)
    ///   Mood → Tempo                (what drives the generation: character, then time)
    ///   Field                       (the surface you play with your fingers)
    ///   Save/Export                 (what you take away — including the city in the name,
    ///                                which is why the Place chip beside it could go)
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
        [.sound, .effects, .mix, .master, .mood, .composition, .field, .export]

    /// The tab strip: the eight chips above, PLUS whatever the plate currently shows if a
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

    // ⛔ A FIRST-RUN FILTER STOOD HERE FOR ONE BUILD AND THE FOUNDER REJECTED IT ON DEVICE
    // (#568/#571 in, #572 out). It showed the Sound chip alone for the first three launches —
    // the 2026-08-13 handover's C4, built as specified. On a fresh install of v10.79.387 the
    // founder's verdict was one line: *"Du hast mega viel gelöscht. Geh lieber nochmal
    // zurück."* Seven missing chips do not read as a calm beginning; they read as an app that
    // lost its features. Nothing about the implementation was wrong — it was reversible,
    // guarded, and it expired by itself — and none of that mattered, because the thing being
    // measured was a first impression and only one person can measure it.
    //
    // Do NOT re-introduce a maturity-gated strip without a founder ask. If a calmer first run
    // is wanted again, the lever to try first is ORDER or EMPHASIS, not absence.


    /// ⭐ WHY THIS SCROLLS ITSELF (#291). #290 took the strip from five chips to nine, and
    /// `visibleChips` can append one more. #359 step 3 then dissolved "Place" into
    /// "Save & Export", so the standing strip is EIGHT. Nine chips at their real widths — the
    /// labels are Atkinson Hyperlegible **Bold** (`EchoelTheme`), each in a 44 pt minimum tap
    /// frame (`chipTapTarget`), 6 pt apart, plus 20 pt of row padding — measured roughly
    /// 590 pt; dropping one chip removes at least its 44 pt frame plus 6 pt of spacing, so
    /// eight land at ~540 pt or less.
    /// A portrait iPhone is ~393 pt wide, and `EchoelStudioView` is deliberately NOT
    /// Dynamic-Type-clamped (only the chrome is, in `WorkspaceView`) and additionally scales
    /// with `StudioZoom`. So the strip OVERFLOWS, with `showsIndicators: false`.
    ///
    /// Two things broke silently at that moment, and neither shows up in a source-text guard:
    ///   1. `visibleChips`' whole stated purpose. It appends the active menu so the strip
    ///      never shows an unselected state — but it appends it LAST, i.e. off the right
    ///      edge. Opening Bio from the pulse pill selected a chip the user could not see, so
    ///      the strip still read as "nothing selected".
    ///   2. `.export` is the LAST chip (ninth then, eighth since #359 step 3 — its position
    ///      is what matters here, not its index). #290 and #272 both argued a permanent chip names
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
    /// #607 (GUI-Board Scheibe 4, UX audit #5): "content continues past the strip's
    /// trailing edge". Written ONLY by `menuBar`'s edge-triggered geometry reduction,
    /// read ONLY by its fade overlay — see the ⭐ #607 paragraph in `menuBar`'s doc.
    @State private var chipStripHasMoreTrailing = false

    /// ⛔ HONEST LIMIT: the ~590 pt is computed from the constants, not measured on a device.
    /// What is certain is the direction (eight wide chips in one row on a 393 pt phone) and
    /// that scrolling the selection into view is correct whether or not it overflows today.
    ///
    /// ⭐ #607 (GUI-Board Scheibe 4, UX audit #5): the strip now ADMITS it overflows. With
    /// `showsIndicators: false`, the trailing chips (Field · Save & Export) were simply
    /// invisible on a portrait phone — #272's buried-"•••" complaint reborn one layer over.
    /// An `onScrollGeometryChange` (iOS 18 floor) reduces the geometry to ONE Bool —
    /// "content continues past the trailing edge" — and a 24 pt fade to the strip's own
    /// background shows only while that is true, so the fully-scrolled position shows the
    /// last chip UNfaded. Edge-triggered (`action:` fires on CHANGE of the reduced value),
    /// so this is interaction-rate state, not a per-frame publisher — the freeze law is
    /// untouched. The fade is a functional affordance (Uncodixfy's "serve a control
    /// function"), non-interactive, and VoiceOver never needs it (chips are buttons,
    /// swipe navigation reaches them regardless of visual clipping).
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
        // yet. For the eight permanent chips it worked either way; for the pulse-pill path —
        // rationale 1 above, the reason this exists — it was a coin flip. `Task { @MainActor }`
        // is the house pattern for exactly this (CLAUDE.md's async-UI rule) and is safe here
        // for the same reason the freeze law is not in play: this fires on a TAP, not on a
        // clock. Never do this per frame from a 30 fps source — that is the other law.
        .onChange(of: displayedMenu) { _, menu in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(menu.id, anchor: .center) }
            }
        }
        // #607 — the overflow measurement. The transform runs during scrolls, but the
        // `action:` fires only when the REDUCED Bool changes (the documented contract),
        // so the state write is edge-triggered: at the overflow boundary, on a chip
        // append (`visibleChips`), or on a width change — never per frame. The −1 pt
        // tolerance keeps a sub-pixel rest at the end position from flickering the fade.
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.x + geo.containerSize.width < geo.contentSize.width - 1
        } action: { _, hasMore in
            chipStripHasMoreTrailing = hasMore
        }
        // #607 — the hint itself: 24 pt fading to the strip's own background, trailing
        // edge only, rendered ONLY while content actually continues past it. Non-
        // interactive so the last chip stays tappable straight through it (its 44 pt
        // target sits exactly under this overlay). Not a decorative gradient: it signals
        // clipped content, the one job Uncodixfy's "serve a control function" names.
        .overlay(alignment: .trailing) {
            if chipStripHasMoreTrailing {
                LinearGradient(colors: [EchoelTheme.bg.opacity(0), EchoelTheme.bg],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 24)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
                    // ⭐ A MINIMUM, NOT A FIXED HEIGHT (#353b). `EchoelTheme.font` is
                    // `.custom(…, relativeTo: .body)`, and `EchoelStudioView` is the one
                    // surface deliberately NOT Dynamic-Type-clamped (only the chrome is,
                    // `WorkspaceView`'s `.dynamicTypeSize(...accessibility1)`).
                    //
                    // ⛔ AND THE FIRST DRAFT OF THIS BLOCK SAID "on top of which `StudioZoom`
                    // scales it again", WHICH IS FALSE AND UNDERSTATES THE REACH. `StudioZoom`
                    // does not multiply the system size — it OVERRIDES it, writing one rung of
                    // its own ladder (`.large` … `.accessibility5`) downward. So the pinch
                    // gesture alone takes this label to AX5 for a user who never opened Larger
                    // Text, which makes the overflow reachable by ordinary in-app zooming
                    // rather than only by an accessibility setting.
                    //
                    // A 12 pt label therefore draws far taller than 26 pt at the top of that
                    // ladder, and a `.frame(height:)` does NOT clip:
                    // the glyphs simply overhang a pill that stayed 26 pt, because the
                    // `.background`/`.overlay` below size to the FRAME, not to the text.
                    // Same DEFECT as `EchoelValueField.boxHeight` and the three chrome bars in
                    // `WorkspaceView`; this row was missed because its overflow is
                    // horizontal-strip and reads as "the font is a bit big" rather than as
                    // breakage.
                    //
                    // ⚠️ NOT quite the same FIX, and the reviewer was right to make me spell
                    // out the difference rather than write "same fix" — the chrome's is a PAIR,
                    // `.fixedSize(horizontal: false, vertical: true)` + `.frame(minHeight:)`,
                    // and its own note says removing either half would be a regression for
                    // EVERY user. That pairing exists because a vertically FLEXIBLE child (a
                    // bare `Rectangle()` there) otherwise stretches to the proposal and the
                    // minimum becomes an infinity. Here the only child is a `Text`, which never
                    // expands to fill, so bare `minHeight` is complete. Copy the pair, not this
                    // line, onto anything that contains a shape.
                    //
                    // Nothing else has to move: `chipTapTarget`'s 44 pt is already a
                    // `minHeight`, so the pill grows THROUGH it rather than out of it, and
                    // the strip is a horizontal `ScrollView` with no height of its own.
                    // No `lineLimit`/`minimumScaleFactor` is added on purpose — shrinking
                    // text that the user asked to be larger is the anti-fix (the bio
                    // numbers' 0.6 floor was that debt; #606 paid it — at AX sizes the
                    // strip stacks and floors at 1.0), and the labels cannot wrap here anyway: an unconstrained
                    // width in a horizontal scroll gives every chip its ideal width.
                    .frame(minHeight: 26)
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
    /// again 2026-07-28, and TWO modifiers are deliberately NOT in it — they sit INSIDE
    /// another modifier's content, not on the body chain: `.sheet(item: $visualShare)`
    /// inside the `showVisual` fullScreenCover, and `.fileImporter(isPresented:
    /// $projectImportPresented)` inside `openSheet`. ⛔ This line said "at :881" for the
    /// first of them; the actual site is ~500 lines away, because a line NUMBER inside a
    /// file is invalidated by every insertion above it — the same lesson this repo has
    /// already paid for twice. Named, not numbered. File-wide the count is therefore 16,
    /// and `ResetSoundClearsWhatTheLaunchLineReportsTests` now asserts BOTH numbers: the
    /// file-wide 16 and the body-chain ceiling of 14. Only the second one is the metadata
    /// budget, and only the second one catches a modifier being MOVED onto the chain.) The
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
    /// #616 (GUI-Board Zeile 6, UX#4) — the bio-source chooser made VISIBLE. Until
    /// this row the ONLY chooser was the pulse pill's long-press context menu — the
    /// least discoverable gesture we ship (the Routing button's ⛔ block below calls
    /// it that), and hard to perform with a motor impairment (#234). Same entries,
    /// same honesty, ONE definition: `BioSourceOption` feeds both this row and the
    /// pill's menu; every entry routes to `selectBioSource` — idle it STARTS the
    /// music, running it hot-swaps the source (which is why the labels say
    /// "Play with", never a bare sensor name).
    ///
    /// FREEZE LAW: safe inline. A `Menu` builds its content only when opened, and
    /// this row reads only `bioSourceRaw` (@AppStorage, selection-rate) — no live
    /// bio value enters the permanently-evaluated panel body. The `?? .camera`
    /// fallback mirrors `startBioSource`'s own default; display-only.
    private var bioSourceRow: some View {
        let current = BioSourceOption(rawValue: bioSourceRaw) ?? .camera
        return HStack(spacing: 8) {
            Text("Bio source")
                .font(EchoelTheme.font(12, .semibold))
                .foregroundStyle(EchoelTheme.text)
                // #616b: the Menu below carries the SAME accessibilityLabel — without
                // this, VoiceOver stops twice on "Bio source" back to back.
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            Menu {
                ForEach(BioSourceOption.allCases) { option in
                    Button {
                        selectBioSource(option.rawValue)
                    } label: { Label(option.menuLabel, systemImage: option.systemImage) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(current.shortName).font(EchoelTheme.font(13, .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }
                .foregroundStyle(EchoelTheme.text)
                .padding(.horizontal, 12).frame(height: 34)
                // `borderStrong`, DIVERGING from the moodPresetBar Menu and the
                // in-panel "Open Routing" button on purpose (#616b annotates what the
                // review called accident-shaped): this control DECIDES what feeds the
                // instrument, and WCAG 1.4.11 wants 3:1 on non-text controls — the
                // A11y#2 rollout direction is TOWARD borderStrong, not away from it.
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.borderStrong, lineWidth: 1))
            }
            .accessibilityLabel("Bio source")
            .accessibilityValue(current.shortName)
            .accessibilityHint("Choosing a source starts the music when idle, or switches it while playing")
        }
    }

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
            // ⛔ #616: this sentence used to END with a long-press instruction ("For a BLE
            // chest strap, touch and hold the pulse display and pick …") because the
            // pill's context menu was the ONLY chooser. The visible row below IS the
            // chooser now, so the caption stops teaching the least discoverable gesture
            // we ship and points at the row instead. The long-press keeps working as a
            // shortcut (the pill's own accessibilityHint still teaches it).
            Text("Press Play to start — your body then drives the sound. Choose your bio source below; Apple Watch feeds in through Health.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)

            bioSourceRow

            // #486 — the ACTIVE half of the loop, directly under the measured half.
            // `BioStripView` above says what the body is doing; this paces the breathing
            // that moves those numbers. Founder 2026-08-07 asked for "Training für
            // kohärentes Atmen" next to the chanting/humming/toning/singing half that #485
            // put on the mix board.
            //
            // NO DOOR, and that is a decision rather than an omission: the founder's ruling
            // (decisions.csv 2026-07-12) is *"Meditation View nicht extra. Alles findet in
            // der Main View statt und ist Teil des Produktionsprozesses."* A door to a
            // separate breathing screen is the exact thing that was refused, which is why
            // `BreathGuideView` and `MeditationView` stay doorless (#276) and this strip
            // comes into the panel instead.
            //
            // ⚠️ IT IS A `View` STRUCT AND MUST STAY ONE — and here that is not a precaution,
            // it is the only thing standing between this strip and the shipped freeze.
            // `pacer.guidance` is rewritten ~30×/s by its tick loop.
            //
            // ⛔ THE FIRST DRAFT OF THIS NOTE GOT THE MECHANISM WRONG, in the direction that
            // makes the rule sound softer than it is. It said an inlined read "would land on
            // `EchoelPanel`, because `panel(_:_:)`'s builder is `@escaping`". `bioPanel` has
            // NO `panel(...)` wrapper at its top level — measured: the only `panel(` inside
            // this whole declaration was that sentence itself. Its `VStack` is reached through
            // `dropdownContent`, whose own FREEZE RULE note says it plainly: evaluated in the
            // ROOT body PERMANENTLY. So inlining this fragment would put a 30 Hz read directly
            // on `EchoelStudioView.body` — the body that hosts every `.menu` Picker of the
            // instrument — at THREE TIMES the rate that caused 10.76.41/50. Not one hop away
            // from the freeze; the freeze.
            //
            // And the argument that does NOT save it: "this panel hosts no Picker today". True
            // of today's tree, useless as a rule — the read would be on the root body, not on
            // this panel. `AnyView(bioPanel)` is not a boundary either (10.76.50). A separate
            // `View` struct is, which is why the strip is one.

            // ⭐ #542. The line above promises "your body then drives the sound" and then names
            // nothing. WHICH parameters it drives was measured in #496/#498 and put on screen —
            // but in the FX sheet, reachable only via Effects › All parameters › scroll to the
            // bottom. A player who asks the question HERE, where the promise is made, got no
            // answer.
            //
            // ⚠️ ONE DEFINITION, TWO SURFACES (#416): the four channel names come from
            // `AlwaysOnBioChannel`'s own cases, and `TheAlwaysOnBioPathIsNamedTests` binds that
            // sentence to the two `…BioParams(` construction sites — so giving one of the
            // pinned channels a real producer reddens THERE instead of quietly leaving this
            // sentence one channel short. ⭐ THAT IS NOT THEORY: #813 gave `coherenceTrend` a
            // producer, the guard went red, and the decision it forced was recorded rather than
            // patched away. ⛔ It then said the trend "MAY now be named here and deliberately is
            // not, because a fifth channel is a copy decision" — the weaker half (#814). It
            // CANNOT be named: this sentence comes from `AlwaysOnBioChannel.allCases`, every
            // case renders a live reading, and the trend lives in a `private var` inside each
            // voice by design. No surface can read it. Still pinned and still unnameable for the
            // ORIGINAL reason (no producer): `breathDepth` and `lfHf`.
            //
            // ⚠️ THIS LINE IS STATIC TEXT AND OBSERVES NOTHING — that part is unchanged and is
            // the freeze law, not laziness: `bioPanel` is reached through `dropdownContent`,
            // which `EchoelStudioView.body` evaluates PERMANENTLY, and that body hosts the
            // `.menu` Pickers. `AnyView(bioPanel)` is not an observation boundary (10.76.50).
            //
            // ⛔ WHAT THIS COMMENT ADDED TO THAT RULE WAS A SCOPE CLAIM, AND #553 RETIRED IT.
            // It said the live rows "stay in their own leaf inside the FX sheet" — reading as
            // if the FX sheet were the only lawful address for them. The law is about the
            // OBSERVATION BOUNDARY, not the sheet: a `View` struct is one wherever it is
            // mounted, which is exactly why `BioStripView` and `BreathCoachStrip` already read
            // live values two lines from here. `AlwaysOnBioPanelStrip` below is the same
            // construction — its `bus.latestBio` read is in ITS body, never in this one.
            // The sentence stays because it is the one thing a player can read at a glance;
            // the numbers now stand under it instead of three levels away (Effects › All
            // parameters › scroll to the bottom), which is where #542 had to leave them.
            //
            // ⭐ AND SINCE #643 THE SENTENCE IS RENDERED BY THE STRIP, not by this body — same
            // words, same position in the panel, one line further down the view tree. (⚠️ NOT
            // pixel-identical, and saying "same place on screen" would have been a claim nobody
            // measured: this `VStack` spaces at 10, the strip's at 8, so the gap BELOW the
            // sentence tightens by two points while the gap above it is unchanged. Two points
            // between a caption and the rows it introduces is the right direction anyway — they
            // belong together — but it is a difference, and this file does not round differences
            // to zero.) It had to name
            // whose channels it means (while the demo generator drives, "four body channels" is
            // false), and the flag has to be the SAME frame the rows under it answer from. This
            // body may not read live bio at all — the comment above says why — so the sentence
            // moved to where the frame already is. ⛔ AND THE FIRST DRAFT SOLD THAT AS "one bio
            // read FEWER in reach of this body" — FALSE, and flattering in the direction this
            // file is least allowed to be. What stood here before was `Text(AlwaysOnBioChannel
            // .bioPanelSentence)`, a `static let` STRING: zero bio reads. The count went from
            // zero to zero. The true statement is the counterfactual the rest of this paragraph
            // already makes: reading the flag HERE would have been the FIRST bio read in this
            // body. No guard can catch the difference — the one that watches this body asserts
            // the absence of `latestBio`, and that was green before and is green after.
            AlwaysOnBioPanelStrip()

            BreathCoachStrip()

            // #277 — the PLAY half, under the measured half (`BioStripView`) and the
            // practised half (`BreathCoachStrip`). CLAUDE.md's own pipeline line describes
            // `BioReactiveSynthVoice` as "silent until user-armed" — and until this row there
            // was no way to arm it: `arm()` had ZERO callers in `Sources/`, so `isArmed`
            // (default `false`, written only by `arm()`/`disarm()`) could never become true.
            // A built, tested, tuned voice that no surface can switch on.
            //
            // ⚠️ IT IS A `View` STRUCT FOR THE SAME REASON `BreathCoachStrip` IS, and the
            // mechanism is the one #486 had to correct: `bioPanel` has no `panel(...)` host at
            // its top level, it is reached through `dropdownContent`, which is evaluated in the
            // ROOT body PERMANENTLY. This row reads `bus.usableBio()` — a ~1 Hz value — so
            // inlining it would put a 1 Hz read on `EchoelStudioView.body`, the body that hosts
            // every `.menu` Picker of the instrument (10.76.41/50). `AnyView(bioPanel)` is not
            // a boundary either.
            BreathVoiceRow()

            // #608 Scheibe 1 — the Auto-mode door, beside the other body-driven
            // switch. A LEAF struct for the same 10.76.41/50 reason as the two rows
            // above it: it reads `bus.usableBio()` (~1 Hz) for its disabled state.
            AutoModeRow()

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
            // ⛔ #355(c) — THIS LABEL SAID "Open Routing to connect a BLE heart-rate strap",
            // AND ROUTING CANNOT CONNECT ONE. `PatchbayView` pairs Bluetooth MIDI, opens a
            // network MIDI session, sets the OSC/ADM/Art-Net/sACN targets and holds the light
            // master — there is no heart-rate pairing anywhere in it. The strap has exactly ONE
            // owner, `startBioSource`, reached by touch-and-hold on the pulse display, which is
            // what the sentence directly above this button already says.
            //
            // Why it mattered more than an ordinary wrong word: for a sighted user the button
            // reads "Open Routing" and the false promise was invisible, but `accessibilityLabel`
            // REPLACES the visible label, so for a VoiceOver user that sentence was the button's
            // entire identity. The one reader who could not cross-check it was the only one
            // being told.
            //
            // ⛔ AND THE FIRST CORRECTION NAMED TWO THINGS BY NAMES NOTHING CARRIES. Its hint
            // ended "touch and hold the pulse display and pick the Bluetooth strap source" —
            // but VoiceOver announces that tile as "Heart rate" (`HeaderMonitors`), and the menu
            // entry reads "Play with a Bluetooth strap — scans for one"; the word "source"
            // appears in neither. Writing a wrong destination into the fix for a wrong
            // destination is this task's own defect, one level down. It also ran 221 characters
            // against a ~57-character median across the app's ~70 hints, and VoiceOver speaks
            // hints in FULL — while "Speak Hints" is user-suppressible, so the corrective half
            // could be silently dropped anyway. The redirect is DELETED rather than reworded:
            // the visible `Text` a few lines above already carries it, verbatim and correctly,
            // and a VoiceOver user reaches that line immediately BEFORE this button. Saying it
            // three times (Text, hint, comment) is not thoroughness.
            .accessibilityLabel("Open Routing")
            .accessibilityHint("Opens MIDI pairing, the MIDI out switches, the OSC, Art-Net, sACN and spatial-audio targets, and the light master.")
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

    // ⛔ `soundControls` IS GONE (#322). It stacked all seven panels
    // (tempoTools · session · sound · mixer · effects · master · mood) into one scroll —
    // the pre-chip page layout. The chip strip replaced it: `dropdownContent` routes each
    // `StudioMenu` case to the SAME seven panels, one at a time. Nothing was mounting this
    // second copy, so the "top-down from what most people touch to deep tweaks" ordering it
    // documented had not applied to anything for weeks; the live ordering is the chip strip's.
    // Deleted rather than kept as a reference, because a stale layout comment reads as the
    // current design to the next session — the exact failure the tombstone above describes.

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
            // ⭐ #644 MOVED THE WHOLE DISCLOSURE INTO A LEAF, and the heading is why. It read
            // "What your body is doing to the sound" in all three states — including the one
            // where the paragraph beneath it says "no pulse measured yet". The fact it needs
            // lives on `StudioCaption`. ⛔ The first draft justified the move by claiming a read
            // HERE would sit in a Picker-hosting body; this property is UNMOUNTED (founder,
            // 2026-07-12), so that hazard is prospective, not present — it becomes true the day
            // the surface is doored, which is exactly when a leaf is needed anyway.
            LiveNarrationDisclosure(caption: caption, isOpen: $showLiveNarration)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(EchoelTheme.fill))
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
            // The strips reflow to 2 columns in landscape / iPad (leaf reads the size
            // class, not the root body → render-safe). There are FIVE since #485 — Bass,
            // Melodic, Field, Click and Voice — because the founder asked to see all the
            // sounding layers at once, not because the grid needed filling. (It was FOUR
            // from #330 until #485 added the mic; the count is written down only so that
            // adding a strip forces a reader past this paragraph, not as an invariant —
            // `MixBoardOwnsEveryLevelTests` deliberately refuses to pin it, because a test
            // that goes red on an honest addition teaches nothing.)
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
                // The melodic FX bus. It carried Pad AND Lead until #255; the filter still
                // tames a shrill melodic line directly.
                //
                // ⛔ A "Lead" FIELD STOOD HERE AND IS DELETED (#255, founder 2026-07-31:
                // "Lead kann raus aus dem Mix"). It was inert and the founder could see it:
                // every curated genre sets `leadDensity: 0`, so `BioComposer` composes no
                // `.lead`-role note and there was nothing for the fader to scale
                // (`LeadRoleAbsenceTests`, blocking bundle; the full finding is in
                // `RoleRhythm.swift`'s A5 paragraph). The note that stood here named the two
                // honest fixes — give a genre a lead again, or remove the field — and said both
                // were founder calls. The founder made the second one.
                //
                // ⚠️ THE REMOVAL IS NOT COMPLETE WITHOUT `normaliseDoorlessLeadMix()`, and that
                // is the #167 lesson this note itself flagged: `MixerStore.lead` is PERSISTED
                // (`"mixer.lead"`), and this field was its only door. Deleting the door alone
                // would freeze whatever the user last dialled — so an install sitting at 0.30
                // would attenuate the first lead a future genre produces by 70 %, silently,
                // with no control able to undo it. `MixerStore.lead` itself stays: it is still
                // read by `level(for: .lead)` at compose time, and deleting the property would
                // be a second, unrelated decision.
                mixStripCard("Melodic · Pad") {
                    EchoelValueField(label: "Pad", value: mixBinding(\.pad),
                                     range: 0...1, unit: "", decimals: 2)   // see Bass Level
                    EchoelValueField(label: "Filter", value: melodicCutoffBinding,
                                     range: TrackFXStore.cutoffRange, unit: "Hz", decimals: 0)
                    EchoelValueField(label: "Drive", value: melodicDriveBinding,
                                     range: TrackFXStore.driveRange, unit: "", decimals: 2)
                }
                // FIELD — the layer you play with your hands (#330, founder 2026-08-01:
                // "Alles Sound Ebenen übersichtlich zu mixen?"). It was the largest hole in
                // this board: the take's roles were here, the surface you actually perform on
                // was two chips away in the Field panel, and nothing showed the two against
                // each other. It is the SAME value and the SAME voice — `fieldLevelBinding`
                // is the single owner, so a change here reaches the gain exactly as it does
                // there. No second store, no mirror.
                //
                // Range 0…1.5, unlike the roles above: this is an output gain on a voice, not
                // a velocity multiplier. The binding's doc says why the two cannot share a
                // range without one of them lying.
                mixStripCard("Field · your hands") {
                    EchoelValueField(label: "Level", value: fieldLevelBinding,
                                     range: 0...1.5, unit: "", decimals: 2)
                }
                // CLICK — on the board because it SOUNDS, and a board that omits an audible
                // layer is not an overview. The toggle rides along on purpose: a level field
                // for a click that is off would be the "adjustable but inaudible" control
                // this repo keeps removing (#135/#164/#227). Both rows read and write the one
                // `MetronomeVoice` instance, so this is a second DOOR, never a second copy —
                // the Tempo panel's identical rows stay in step by construction.
                mixStripCard("Click") {
                    Toggle("Click", isOn: Binding(get: { metronome.enabled },
                                                  set: { metronome.enabled = $0 }))
                        .font(EchoelTheme.font(12))
                        .tint(EchoelTheme.accent)
                        .accessibilityHint("A steady click at the current tempo")
                    EchoelValueField(label: "Level", value: Binding(
                        get: { Double(metronome.level) },
                        set: { metronome.level = Float($0) }),
                        range: 0...1, unit: "", decimals: 2)
                }
                micMixStrip
            }

            // WHAT IS DELIBERATELY NOT ON THIS BOARD, said out loud rather than left to be
            // discovered: the MASTER (loudness, limiter, output) has its own panel because it
            // is the sum of everything here, not another layer beside them. The bio voice
            // (breath → synth) is absent because it cannot be armed at all today — a strip
            // for it would be a control for silence (#277). Secondary MIDI lanes went with
            // the timeline (#121 Slice 4).
            //
            // ⛔ "THE MIC" STOOD IN THAT LIST UNTIL #485 AND IT WAS THE ONE ENTRY THAT WAS
            // WRONG — not stale, wrong from the start. It is the only layer named here that
            // both SOUNDS today and is switchable today; the reason it was off the board was
            // that its door happened to live behind the master panel, which is a fact about
            // where a sheet was mounted, not about what belongs on a mixer. #330's own
            // charter is "every audible layer on one board", and a board that omits the
            // performer's own voice fails it in exactly the way the founder named.
            Text("Master level lives in the Master panel — it is the sum of these, not one of them.")
                .font(EchoelTheme.font(11))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                mixer.resetToUnity()
                // Reset writes the store DIRECTLY, so it bypasses `mixBinding` and would
                // leave the sub at the old level while every other part jumped to unity —
                // the same "one owner updates, the other doesn't" split that made this
                // fader inert in the first place. Third of FOUR mutators — the fourth is
                // `resetSoundToDefaults()` (#400 slice 2), which pushes the same two lines;
                // `MixerStore.init` is a fifth writer but is covered by the launch restore in
                // `.onAppear`. A new mutator must push both lines below.
                subBass.mixLevel = mixer.bass
                laneVoiceRack.setBassMixLevel(mixer.bass)
                setBassFX(.off)
                setMelodicFX(.off)
                // Same law as a single fader (#174): "reset the balance" restores the
                // genre's levels on the take you are listening to — it does not fetch a
                // different take.
                scheduleRebalance()
            } label: {
                Text("Reset generated parts to genre balance")
                    .font(EchoelTheme.font(12))
                    .foregroundStyle(EchoelTheme.accent)
            }
            .buttonStyle(.plain)
            // The label gained "generated parts" with #330, and that is a correctness fix,
            // not wording: the board now also carries Field and Click, which have no genre
            // balance to return to and which this button does not touch. "Reset to genre
            // balance" on a board with four strips promises four and delivers two.
            // "and lead" dropped with #255 — `resetToUnity()` still writes `lead` (harmless,
            // and it agrees with `normaliseDoorlessLeadMix()`), but the hint describes what
            // the player can SEE change, and the lead fader is gone.
            .accessibilityHint("Sets the generated bass and pad back to the genre's own balance. Field and click are not changed.")
        }
    }

    /// The Field's output level — ONE owner for a value that now has TWO doors (the Field
    /// panel and the Mix board, #330).
    ///
    /// ⚠️ THIS EXISTS TO PREVENT A BUG THIS FILE HAS ALREADY PAID FOR TWICE. The Field row
    /// used to be a plain `$touchLevel` field with an `.onChange` fanning out to
    /// `touchSynth?.setGain`. An `.onChange` fires only in the view that declares it, so a
    /// second field bound to the same `@AppStorage` would have persisted the number and left
    /// the voice at its old gain — the number moves, the sound does not. That is exactly the
    /// split that made the Bass fader inert (`mixerPanel`'s reset button carries the same
    /// warning) and the same class as `subBass.mixLevel`. A binding that performs the fan-out
    /// in its own setter cannot be forgotten by a new door.
    ///
    /// The gain is a REAL output gain on the voice, not a velocity trim — `touch.level` runs
    /// to 1.5 on purpose (see the Field row) whereas the composed roles cap at unity, because
    /// there the multiplier would pin every note's velocity at 1.000 and flatten the dynamics
    /// (`MixerStore.combined`). Two ranges, two different laws, deliberately not unified.
    private var fieldLevelBinding: Binding<Double> {
        Binding(get: { touchLevel },
                set: { v in
                    touchLevel = v
                    touchSynth?.setGain(Float(v))
                })
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

    /// VOICE — the microphone strip on the Mix board (#485, founder 2026-08-07: coherent
    /// breathing plus chanting / humming / toning / singing "braucht einen zusätzlichen
    /// Mixer-Slot für Audio-in").
    ///
    /// ⭐ WHAT WAS ACTUALLY MISSING, because it was NOT the capability. Live monitoring with
    /// the FeedbackGuard duck has been built and reachable since #298/#299 — engine path,
    /// session claim, level, latency advice per route. What was missing is that its only
    /// door sat behind the MASTER panel, i.e. under the sum of the layers rather than beside
    /// them, so the one layer the performer makes with their own body was the only audible
    /// layer absent from the board that #330 built to hold every audible layer. This adds a
    /// DOOR, not a second copy: both rows read and write the one `AudioEngine`, exactly as
    /// the Click strip does with the one `MetronomeVoice`.
    ///
    /// ⚠️ `feedbackGuardActive` IS DELIBERATELY NOT READ HERE. It is assigned from the ~15 Hz
    /// meter poll (gated on change since #298's Nachlese, but a howl toggles it repeatedly),
    /// so a read would enrol a body as a ~15 Hz observer for as long as monitoring runs — and
    /// the five strips of this board carry eight draggable `EchoelValueField`s, which is a
    /// live scrub-anchoring hazard (#375/#376), not just wasted work.
    ///
    /// ⛔ AND THE FIRST VERSION OF THIS PARAGRAPH NAMED THE WRONG BODY — the one mistake this
    /// file already corrects elsewhere, re-acquired here one commit later. It said
    /// `mixStripCard`'s NON-escaping `@ViewBuilder` puts the read "inside the body that hosts
    /// every `.menu` Picker of the instrument … the 10.76.41/50 freeze verbatim". The premise
    /// is true and the conclusion does not follow: TWO escaping boundaries sit above this
    /// content. `mixerPanel` goes through `panel("Mix", …)`, whose builder is
    /// `@escaping` and is invoked in `EchoelPanel`'s OWN body, and the strips sit inside
    /// `AdaptiveCardGrid`, which does the same. The read would land on `AdaptiveCardGrid`,
    /// never on `EchoelStudioView.body`. This panel also hosts NO `Picker` and no `.menu` at
    /// all, and only one panel renders at a time — so there is nothing here for a rebuild to
    /// tear down. The honest size was already written by #298's Nachlese, at
    /// `AudioEngine.updateFeedbackGuard`: *"No `.menu` Picker lives in that sheet, so this was
    /// never the 10.76.50 freeze — but it is the same mechanism."* #485 escalated that into
    /// "the freeze verbatim". Same mechanism, one panel away, one refactor from being the
    /// freeze — that is the true claim, and the DECISION to omit the flag is unchanged.
    /// The live guard indicator stays in `AudioInputPickerView`. Static text here says what
    /// the guard does; it claims no live state.
    ///
    /// ⚠️ WHAT "the toggle cannot lie" DOES AND DOES NOT COVER — narrowed after review,
    /// because the headline was stronger than the code. Verified: no path in
    /// `setInputMonitoring` returns `false` after setting `isInputMonitoring = true`, so the
    /// two cases named below (mic permission denied, no valid input format) really do revert
    /// the switch. But there IS a path that returns `true` without anything being heard:
    /// `wasRunning = masterEngine.isRunning` is captured, and the restart branch is skipped
    /// entirely when the engine was stopped — the graph is connected, `isInputMonitoring`
    /// goes `true`, and nothing is running. Reachable after a failed launch `start()` or a
    /// scene interruption that declined to resume. That is pre-existing in `AudioEngine`, not
    /// introduced here, and it is NOT covered by `micMonitorRefused`.
    ///
    /// ⚠️ THE LEVEL FIELD IS SHOWN WITH MONITORING OFF ON PURPOSE — it is a pre-set, not a
    /// dead control. `inputMonitorGain`'s `didSet` writes the mixer only while
    /// `isInputMonitoring && !feedbackGuardActive` (both conditions — while the guard ducks,
    /// the write is deferred to the next poll, which recomputes from this same stored value),
    /// and `setInputMonitoring(true)` applies the stored value on the way in, so a
    /// number dialled while off IS the level you get when you switch on. It is NOT
    /// persisted, and that is a decision rather than an oversight: a monitor gain is a
    /// feedback risk, so every launch starts at the conservative 0.6 rather than at whatever
    /// a previous room needed. Persisting it is a separate call.
    ///
    /// ⚠️ Choosing WHICH input (built-in / wired / USB / Bluetooth, with its latency advice)
    /// is not duplicated here — the row hands off to the existing `showInput` sheet. That
    /// slot already exists, so this adds NO presentation modifier to the body chain (the
    /// 10.76.34 black-screen law).
    @ViewBuilder
    private var micMixStrip: some View {
        #if os(iOS)
        mixStripCard("Voice · your microphone") {
            Toggle("Monitor", isOn: Binding(
                get: { audioEngine.isInputMonitoring },
                set: { on in
                    if on {
                        // #601: ask for the mic FIRST. The old direct call could never
                        // show the permission dialog (undetermined permission → 0 Hz
                        // input format → silent bail), so on a fresh install this
                        // toggle just flipped back — the founder's "Audio in
                        // funktioniert bisher nicht". Async, so the refusal flag is
                        // written when the answer is real, not before the dialog.
                        Task { @MainActor in
                            let engaged = await audioEngine.engageInputMonitoring()
                            micMonitorRefused = !engaged
                        }
                    } else {
                        _ = audioEngine.setInputMonitoring(false)
                        micMonitorRefused = false
                    }
                }))
                .font(EchoelTheme.font(12))
                .tint(EchoelTheme.accent)
                .accessibilityHint("Hear your own voice through the output while you hum, tone or sing")
            EchoelValueField(label: "Level",
                             value: Binding(get: { audioEngine.inputMonitorGain },
                                            set: { audioEngine.inputMonitorGain = $0 }),
                             range: 0...1, unit: "", decimals: 2)
            // ⛔ THE FLAG ALONE WAS NOT ENOUGH, and the failure was VISIBLE: refuse here →
            // open "Choose input…" → grant and switch monitoring on INSIDE
            // `AudioInputPickerView` (which does not know about this `@State`) → dismiss, and
            // this card rendered the Toggle ON together with "could not start". Two doors onto
            // one engine with one un-shared piece of view state — the exact thing the
            // door-not-a-copy framing above is meant to prevent. Gating on the ENGINE as well
            // is cheaper than sharing the state and keeps the engine the single source of
            // truth for "is it listening"; it also clears the milder staleness where the user
            // grants permission in Settings and comes back.
            if micMonitorRefused && !audioEngine.isInputMonitoring {
                // #613 (sweep WARN 3): every engage failure used to wear the permission
                // costume — the Settings line + door showed even when access IS granted
                // and the failure was a busy session or a format/restart miss, sending
                // the user to a toggle that is already on. The copy now branches on the
                // engine's ONE definition of denial; the non-denial line is honest about
                // what the user can actually do (try again — those failures are the
                // transient kind, and the degraded machinery owns the persistent kind).
                if audioEngine.micPermissionDenied {
                Text("Monitoring could not start — check microphone access in Settings, or pick another input.")
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                // #610 (founder screenshot of 2518, "Wir wollen schon Device microphon Audio
                // Input Live Monitoring haben"): the line above names Settings and opened no
                // door. iOS asks for the mic ONCE — after an OS-level denial the Settings app
                // is the only fix (`engageInputMonitoring`'s `.denied` branch logs exactly
                // that). One tap now takes the user there, through the ONE existing settings
                // door (#416) — the same global function BioStripView's camera door calls.
                // Deliberately NO scenePhase re-check on return: changing a privacy
                // permission in Settings makes iOS relaunch the app, so a stale refusal flag
                // cannot survive the grant — the state heals by relaunch, not by polling.
                Button { openAppSettings() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.slash").font(.system(size: 9))
                        Text("Allow microphone")
                    }
                    .font(EchoelTheme.font(11))
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(EchoelTheme.warning.opacity(0.20))
                    .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall))
                    .foregroundStyle(EchoelTheme.warning)
                    // #610b (review): the visible chip stays small, the HIT area does not —
                    // the bare chip was ~18 pt tall, under WCAG 2.5.8's 24, in the same card
                    // whose "Choose input…" door already carries the 34-pt fix for exactly
                    // this defect. Frame AFTER the chip styling so only the tappable area
                    // grows; pinned in TapTargetFloorTests (the list, not a sweep).
                    .frame(minHeight: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Microphone access is off")
                .accessibilityHint("Opens Settings so you can allow microphone access and hear yourself live")
                } else if !audioEngine.degraded {
                    // #613: access is granted, so Settings is the WRONG advice and the
                    // door would assert "Microphone access is off" over a granted mic.
                    // #613b: `!degraded` is the #605b law applied here — on the
                    // restart-throw path the engage failure and restartOrDegrade's
                    // verdict can land together, and AudioDegradedRow (mounted on
                    // `degraded`) then owns cause + Retry; without the gate this line
                    // and that row sat on screen saying the same thing twice.
                    Text("Monitoring could not start — try again, or pick another input.")
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if audioEngine.isInputMonitoring && !audioEngine.isRunning && !audioEngine.degraded {
                // ⛔ #605b: `!degraded` is load-bearing — the sentence below promises audio
                // "comes back by itself", and `degraded` is exactly the state where that is
                // FALSE (self-heal gave up). Without the gate, this line and AudioDegradedRow
                // ("auto-recovery gave up" + Retry) could sit on screen simultaneously,
                // saying opposite things about the same silence (review of #605). In the
                // degraded state that row owns the message AND the recovery; this line
                // covers only the self-healing interruption window. `degraded` writes are
                // event-rate (give-up + start), same class as the two reads beside it.
                // #605 (UX audit #9): `setInputMonitoring(true)` wires the graph but starts
                // the engine only if it was already running — so this toggle can honestly
                // show ON while a call/Siri/alarm interruption holds the engine paused and
                // nothing sounds. Same #485 shape as the refusal line above: gated on live
                // engine state, so it clears itself the moment audio resumes (the `.active`
                // return). No retry button on purpose — the interruption case heals itself,
                // and the gave-up case sets `degraded`, which `AudioDegradedRow` explains
                // WITH the retry. Freeze law: both reads are event-rate (a handful of
                // changes per session), the same class as `isInputMonitoring` beside them.
                Text("Monitoring is on, but audio is paused — it comes back by itself when the call, alarm or Siri ends.")
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Use headphones. On the speaker the feedback guard ducks a howl automatically.")
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // ⛔ THE FIRST VERSION WAS A BARE `Text` UNDER `.buttonStyle(.plain)`, which gives a
            // hit area of about the text height (~15–17 pt) — under HIG's 44 and under WCAG
            // 2.5.8's 24. The OTHER door to this identical sheet, `masterDoorButton`, has
            // carried `.frame(height: 34)` plus full width all along, so the two doors to one
            // sheet disagreed about whether a finger can hit them. `TapTargetFloorTests` is a
            // pinned list rather than a sweep, so nothing went red — its header asks for a case
            // to be added when an audit finds one, and a review found this one.
            Button { showInput = true } label: {
                Text("Choose input…")
                    .font(EchoelTheme.font(12))
                    .foregroundStyle(EchoelTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Pick the microphone or audio interface, with its monitoring latency")
        }
        #endif
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
    // (Historical: the beat control left this panel 2026-07-07 "Schmeiß den Beat komplett
    // raus". It stayed DEFINED but unpresented until #323 deleted it outright — see the
    // tombstone where it used to live for why "unpresented, reversible" stopped being true
    // once #166/#167 removed the drums it selected between. The sentence that followed here
    // said "placeRow/weatherRow live in the Session dropdown — chrome-door 'session' since
    // step 2c"; #359 dissolved that dropdown entirely — `weatherRow` → Mood, its image half
    // → Field, `placeRow` → "Save & Export". The name preview is still in the header strip.)
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
    /// groove by how close each sits to what the DRIVER is asking for; tapping one plays
    /// it — the picked skeleton + detail seed reproduce exactly, whatever source is live
    /// still colours tempo/dynamics. Honest score: closeness of realized density to the
    /// driver's requested busy-ness (a number, not a health claim).
    ///
    /// ⛔ "the body" TWICE HERE, and this is the doc a session reads before touching this
    /// property (#645 review). The target traces `bus.usableBio()` — the demo generator's
    /// fabricated frame under Simulation, the engine's default with no source. `mazeDriver`
    /// carries which of the three it was; the sentence itself lives in
    /// `BioVariationMaze.boardSentence(driver:density:)`.
    private var variationsCard: some View {
        mixStripCard("Variations") {
            HStack(spacing: 8) {
                // ⚠️ THE no-board BRANCH IS DELIBERATELY NOT MARKED (#645). It renders before
                // any exploration exists, so it claims nothing about a current reading — it says
                // what the control is FOR. Marking it would imply a demo is running when none is,
                // which is the over-correction this family has twice had to retract. The board
                // branch is the one that prints a reading, and it is the one that moved.
                // ⭐ AND THE DECISIVE ARGUMENT IS STRUCTURAL, NOT EDITORIAL (#645 review): there
                // is no event to hang a `@State` write on before the first Explore, so the only
                // way to mark this branch is a fresh `bus.usableBio()` read INSIDE this computed
                // `var` — which the root body evaluates, registering it as an observer of the
                // ~10 Hz publisher. That is the 10.76.50 menu-freeze verbatim. Marking it is not
                // merely over-correction; it is unimplementable without reopening a ship-blocker.
                Text(mazeBoard == nil
                     ? "Variations of the same groove — your body curates, you pick."
                     : BioVariationMaze.boardSentence(
                        driver: mazeDriver,
                        density: densityWord(mazeBoard?.targetDensity ?? 0)))
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                // ⛔ #617b: this WAS `Button("Explore") { … }` with the pill styling
                // chained on the BUTTON — outside the label, so under `.plain` the hit
                // test stayed the ~15 pt title glyph run (#485's measured law) and the
                // grown pill was decoration. The pill now lives INSIDE the label with a
                // `contentShape`, the construction its two sibling chips
                // (`touchPatchChip`, the look chips) already had. `minHeight`, not
                // `height` (#353), 34 = the house in-panel floor (#610b); no outset
                // because tappable variation rows sit directly below.
                Button { exploreVariations() } label: {
                    Text(mazeBoard == nil ? "Explore" : "New")
                        .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.text)
                        .padding(.horizontal, 12).frame(minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.bg))
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .strokeBorder(EchoelTheme.border, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                    .font(EchoelTheme.font(12, isOn ? .semibold : .regular))
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

    // ⛔ THE ENTRY ROWS ARE GONE (#322, and this tombstone matters more than the code did).
    //
    // `liveColaboRow` and `learnRow` (R2/R3, 2026-07-10) were full-width door cards, and
    // `entryRow` was their shared chrome. All three sat here unmounted: the doors they
    // opened MOVED to the chrome-door notification, and nobody removed what they replaced.
    // Both sheets are reachable today — the deletion costs the user nothing.
    // (⛔ This named `case "learn":` / `case "live":` in the `.echoelChromeDoor` receiver as
    // where those doors went. Since #492 they are neither rows NOR notification cases: they
    // are the two tiles in `quickDoorRow`, which set `showLearn` / `showLiveColabo` directly.
    // The tombstone's POINT is unchanged — full-width door cards became something smaller —
    // and pointing at a `case` that no longer exists would read as "the doors are gone".)
    //
    // WHY IT IS WRITTEN DOWN RATHER THAN JUST DELETED: they were found together with
    // `moodPadsSection`, which from a grep of NAMES looked identical — an unmounted `some
    // View` in this file — and is something else entirely: a surface the founder had
    // removed on purpose after testing it on device.
    //
    // ⛔ THE FIRST VERSION OF THIS NOTE SAID "nothing in the source distinguished them",
    // AND THAT WAS FALSE — it is the sentence #329 had to retract. `moodPadsSection`'s own
    // first doc line carries a DATE AND A VERBATIM FOUNDER QUOTE ("UNPRESENTED (founder
    // 2026-07-07: …)"); these three carry no such marker. The source distinguished them
    // perfectly. A grep of names did not, which is a different claim — and writing the
    // stronger one taught the opposite of the cheap lesson.
    //
    // THE CHEAP LESSON: read the property's OWN doc comment before deciding what an
    // unmounted view is. An "UNPRESENTED (founder …)" marker is the distinguisher, and it
    // costs ten seconds. `Tests/CISmoke/NoDoorlessStudioViewsTests.swift` fires on the
    // CLASS so nothing new goes unnoticed — but what it tells you to do is LOOK, not
    // re-door on suspicion.

    // MARK: Panel 1b — Place (the city that names the session)
    //
    // ⛔ `sessionPanel` STOOD HERE AND IS DELETED (#359 step 3). Its doc block is not
    // reproduced, only its conclusion, because that conclusion is what justified deleting
    // it: after step 1 moved `weatherRow` into `moodPanel`, this panel held exactly ONE
    // control. A whole chip, a whole disclosure panel and a persisted expand flag for one
    // toggle — sitting one chip away from "Save & Export", which is the panel a user
    // reasonably opens to save a session. That name collision is filed task #284, and the
    // honest fix is not a better title but no panel: `placeRow` now renders inside
    // `utilityRow`, directly above the Save button whose file name it shapes.
    //
    // The ROW below is untouched and still lives here. Only its container changed.

    #if canImport(CoreLocation)
    /// Opt-in place token in the session name (E2, default OFF). One coarse
    /// city lookup on device; the token lands after the date in every
    /// session/export name (Echoel_2026-07-10_Hamburg_Am_72bpm_A440).
    private var placeRow: some View {
        @Bindable var locationNamer = locationNamer
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $locationNamer.enabled) {
                Text("Place in session name")
                    .font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
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
                            // The GLYPH stays 14 pt; only the target grows — 14×14 to 36×36,
                            // which is this row's own height (`.frame(height: 36)` below), so
                            // the hit area fills the row vertically and takes 36 pt of its
                            // width from the `TextField` beside it. `BioStripView` fixed the
                            // identical pattern after the 2026-07-09 AX audit ("a bare 12 pt
                            // glyph — nearly impossible to hit").
                            //
                            // ⛔ AN OUTSET WOULD HAVE BEEN THE WRONG IDIOM HERE, although it
                            // is the one the transport bar uses two files over. There is NO
                            // gap on the leading side — the `TextField` abuts this button
                            // inside one `HStack` — so `inset(by: -6)` would have pushed the
                            // hit area 6 pt INTO the text field's own tap area and stolen the
                            // taps that place the caret at the end of the name. Growing the
                            // frame moves the field's edge instead of overlapping it.
                            //
                            // Honest limit: 36 < the 44 pt HIG floor. Reaching 44 would make
                            // this control taller than the row that contains it. 36×36 clears
                            // WCAG 2.5.8 (24×24) and is ~6.6× the area it had.
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
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
                    .font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
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
                            .font(EchoelTheme.font(11))
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
                // what it changes; 0 = off (no change), 1 = fully the weather.
                //
                // ⛔ This group read "Sound · Klang" until 2026-07-29 — the English word and
                // its German gloss, side by side, in a bundle that declares one language. A
                // per-string bilingual gloss is not what localization is; it is what
                // localization REPLACES.
                //
                // #359 step 2: the IMAGE group left this row for `visualPanel` (the Field
                // chip), where the picture it tints actually is. The `AdaptiveCardGrid` that
                // held the two side by side left with it — a grid arranges CARDS, and one
                // card has nothing to arrange. That is a real accounting change, not a
                // tidy-up: `weatherRow` was one of only two bare `AdaptiveCardGrid` callers,
                // so `mixerPanel` is now the only one, and every comment that named the pair
                // is corrected in the same commit (`AdaptiveCardGrid`'s own doc block below,
                // `SoundPanelReflowsTests`, CLAUDE.md's reflow count).
                weatherMixGroup("Sound", params: WeatherMood.Param.allCases.filter { $0.domain == .sound })

                // NOT a sentence pointing at another surface. This row's own history is the
                // argument: the location prerequisite above used to name the other toggle and
                // leave the user to hunt for it, and the fix was one tap. Moving the image
                // mixers creates exactly that hazard for anyone who knew where they were, so
                // the pointer carries the user rather than describing the destination.
                Button { activeMenu = .field } label: {
                    Text("Weather's image mixers — Hue, Saturation, Glow, Movement — are in Field")
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.accent)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityHint("Opens the Field panel, where the weather's four image influences are mixed.")

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

    /// The weather's IMAGE half, rendered in `visualPanel` (the Field chip) — #359 step 2,
    /// founder 2026-08-01: "Weather könnte auch eine Rubrik mit slidern in mood, Sound und
    /// Field sein oder?".
    ///
    /// Hue · Saturation · Glow · Movement are read by `FloatingVisualWindow`, so until now
    /// four sliders that change the PICTURE lived on a panel that shows none of it, while the
    /// panel that does had no idea they existed. The split follows the `Domain` enum that
    /// `WeatherMood.Param` already declares — the code knew which half was which long before
    /// the UI did.
    ///
    /// ⚠️ IT ADDS NO PERMANENT CHROME, deliberately. Weather is opt-in and default OFF, so a
    /// standing "turn on weather" line here would be a row every Field user carries forever to
    /// serve the minority who want it — on the one panel already under a chrome budget (#365,
    /// #369). Discovery is covered from the other side: the Mood toggle's own label says
    /// weather shapes "the music AND the image", and the pointer beside it walks you here.
    /// If a device pass shows people never find these, the fix is a line in Mood, not here.
    @ViewBuilder
    private var weatherImageRow: some View {
        if weatherEnabled {
            // Titled "Weather", not "Image": in Mood the two groups had to be told apart from
            // each other, so "Sound"/"Image" was the distinction that mattered. Here the whole
            // panel IS the image, and the only thing worth naming is where these four come from.
            weatherMixGroup("Weather", params: WeatherMood.Param.allCases.filter { $0.domain == .visual })
        }
    }

    /// One titled block of weather mixers, in the mix-strip look. The two live titles are
    /// "Sound" (in `weatherRow`, Mood) and "Weather" (in `weatherImageRow`, Field) — this line
    /// said "(Sound or Image)" until #359 step 2, and "Image" is no longer a title anywhere.
    @ViewBuilder
    private func weatherMixGroup(_ title: String, params: [WeatherMood.Param]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            groupHeader(title)
            ForEach(params) { param in
                // The commit hook pushes the take patch again, so the WARMTH fader is audible
                // while you move it instead of at the next generate. It fires for the image
                // mixers too, where it does no HARM rather than nothing at all: releasing Hue
                // or Glow re-runs `applyTakeSound(currentPatch)`, which re-enqueues the same
                // patch on the voice and re-runs `syncTouchSound()`. Both are idempotent with
                // identical input, so nothing is audible — but it is two engine pushes, not
                // zero, and an earlier version of this comment said "does nothing there",
                // which is a stronger claim than the code earns. Filtering by param would be a
                // second place that has to know which influences are patch-side, and that list
                // is already stated once in `weatherToned`.
                WeatherMixRow(param: param) { applyTakeSound(currentPatch) }
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
            // The TONE half lands NOW, not on the next re-seed. The salt and the mood targets
            // are compose-time inputs and correctly wait for the next generate; the tone is a
            // patch push, and holding it back would mean the sky arrives audibly only after
            // the player happens to regenerate — which is most of why weather read as
            // "nicht bemerkbar" in the first place.
            applyTakeSound(currentPatch)
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

    // ⛔ `beatModeRow` STOOD HERE AND IS DELETED (#323) — a three-way segmented Picker
    // (Off · Pulse · Genre) over the drum layer, plus a hint line promising "a deep, steady
    // drum". The hint line and both non-Off labels were false by the time it was deleted
    // ("Every word of it was false" stood here and was itself an overstatement — `Off`
    // described exactly what generation did). It stayed 25 days because "unmounted but
    // reversible" reads like a safe state.
    //
    // The chain, so nobody restores it from an older revision by mistake:
    //   2026-07-07  founder: "Schmeiß den Beat komplett raus" → the row was unmounted and
    //               `generate` switched to an unconditional `BioComposer.silentBeat()`.
    //   2026-07-26  #166 removed the drum voices from the signal path.
    //   2026-07-31  #167 deleted `DrumSynthVoice`, `LaneDrumKitVoice`, `DrumNoteMap`.
    // So the control did not merely lack a door: neither non-Off option could produce a
    // sound by any path. Restoring it means rebuilding the drum VOICE first — a founder
    // call, not a UI one.
    //
    // ⛔ AND THE FIRST VERSION OF THAT SENTENCE WAS WRONG IN A WAY ITS OWN NEXT PARAGRAPH
    // REFUTED, six lines apart. It read "two of its three options had no IMPLEMENTATION left
    // to select" — while the paragraph below said the builders still compile and are still
    // tested. Both cannot be true. The patterns are all still there: `shamanicBeat`
    // (`BioComposer.swift:793`) and six private genre grooves — `fourOnFloorBeat` (`:835`),
    // `backbeatBeat` (`:942`), `offbeatBeat` (`:982`), `halfTimeBeat` (`:1025`), `dubBeat`
    // (`:1063`), `trapBeat` (`:1146`) — and `compose` still calls them. What #166/#167
    // deleted is the VOICE that would have sounded those grids, and `generate` has fed
    // `silentBeat()` unconditionally since 2026-07-07 regardless. Two independent reasons
    // the control was mute; the first version named a third that was false.
    //
    // What is NOT deleted, deliberately: `BeatMode` (`BioComposer.swift:43`), the public
    // `shamanicBeat()` and those six builders. A doorless CONTROL is debt; a tested pure
    // BUILDER is inventory.
    //
    // ⛔ THE FIRST VERSION CALLED THE SECOND HALF OF THAT PAIR `genreBeat()` — A FUNCTION
    // THAT HAS NEVER EXISTED. It is the most expensive kind of tombstone error: a future
    // session greps `genreBeat`, finds nothing, and concludes the builders were deleted
    // too. A tombstone's whole job is to be checkable; an invented symbol makes it
    // uncheckable in the direction that causes deletion. Names in a tombstone get grepped
    // before they get written.
    //
    // "Still tested" is true and belongs qualified: `ShamanicBeatTests` lives in
    // `Tests/EchoelmusicTests/`, the NON-blocking suite. It covers the walk; it cannot
    // redden a merge.

    // (Step 2b: tuningRow / genrePicker / tonartRow / kammertonRow / tempoRow moved
    // verbatim into the chrome — CompositionHeaderStrip owns the Pickers/A4 field,
    // the TransportBar's BodyTempoField the tempo; their audible side effects run in
    // handleCompositionEdit below. tuningRow's conditional retune hint text fell
    // with it; nonStandardTuningBanner keeps the full explainer — and since #325
    // (2026-08-02) it is MOUNTED again, as the first child of `soundPanel`. It sat
    // unpresented from 2026-07-09 to then, which is the whole point of that task:
    // moving the CONTROLS into the chrome silently moved the WARNING out of the app.)

    /// Push the selected tone system's per-pitch-class retune table to the synth
    /// (relative to the current key root). 12-TET → all zeros → identical playback.
    private func applyTuning() {
        let cents = TuningSystem.named(tuningID).pitchClassCents(root: rootIndex).map { Float($0) }
        synth.setTuningCents(cents)
        // The touch instrument plays the same tone system — and its note→colour
        // mapping reads this table, so the colour follows the SOUNDING pitch.
        touchSynth?.setTuningCents(cents)
        // ⛔ And the LEAD. This was missing until 2026-07-28 and it is the same defect as
        // #114's concert-pitch gap, one function away. With any non-12-TET system selected,
        // the generated melody played 12-TET against a retuned pad and touch surface — a
        // larger error than the 32 cents of the A4 gap for a maqām or just table.
        leadSynth?.setTuningCents(cents)
        // ⛔ AND THE FELT SUB (#312, founder "Bass teilweise nicht in tune"). The line above
        // used to end with "`setTuningCents` exists on exactly three reachable objects (all
        // `PolySynthVoice` — `subBass`/`bioVoice`/`laneVoiceRack` have no such method, so
        // their absence is correct)". That is a fact about the API being used as a reason,
        // and it is the wrong kind of reason: the missing method WAS the defect, exactly as
        // it had been for the lead one sentence earlier. `SubBassVoice` doubles the lowest
        // sounding note an octave down, so it carries that note's PITCH CLASS — and it was
        // the one pitched voice still playing plain 12-TET while everything above it moved.
        // In Maqām Bayātī that is 100 cents of beating on the fundamental, 150 in Gamelan
        // Pélog and 300 — a whole minor third — in Hirajōshi, which is where a sub is least
        // forgiving. (⛔ This said "up to ±50 cents … in Maqām Bayātī or Gamelan Pélog": wrong
        // by 6×, and both named systems exceed it. The figures now come from evaluating
        // `TuningSystem.centsDeviation(forSemitone:)` over `TuningSystem.library`, and a test
        // in the blocking bundle recomputes the maximum so the next added system fails a gate
        // instead of ageing this line.) 12-TET (the default) is an all-zero table and stays
        // bit-identical, so this fan is unconditional.
        subBass.setTuningCents(cents)
        // ⛔ AND THE BIO VOICE, AND THE WHOLE LANE RACK (#338). This fan stopped here, and the
        // reason written down for stopping was: "THIS VIEW's `bioVoice` instance never sounds —
        // nothing calls `arm()` on it (task #277), so its notes stay in launch-silence." The
        // `arm()` fact is TRUE and the conclusion does not follow. (⛔ This sentence used to end
        // "…which makes it the THIRD time in this one function that something checkable stood in
        // for a reason (API surface for the LEAD, API surface for the sub, a latch for this
        // voice)". The lead third is false, and the excuse quoted six lines up says so itself:
        // "exists on exactly three reachable objects (all `PolySynthVoice`)" — `leadSynth` IS a
        // `PolySynthVoice?`, so it was INSIDE that set. `PolySynthVoice.setTuningCents` has
        // always existed; the lead was an omission with no stated reason at all. Honest count:
        // TWO.) `arm()` gates ONLY the
        // BREATH trigger — `consumeBioEventsIfFresh`'s `guard isArmed, …`. The MIDI path is
        // `apply(controller:)` and has no such guard, deliberately, because the performer leads;
        // `bioVoice.start(subscribing: bus)` runs at launch (`EchoelmusicApp`) and installs the
        // controller drain. Plug a keyboard in and the global bio voice sounds today.
        bioVoice.setTuningCents(cents)
        // The RACK is the louder half and was never in doubt: `LaneVoiceRack.noteOn` routes each
        // multi-roll lane note to EXACTLY ONE unit — it is a switch over the slot's binding, not
        // a broadcast — and `feature.multiRoll` is REGISTERED ON, so the poly/sub half is a
        // default install, not a flag hunt. (The BIO units additionally need `voiceKindRouting`
        // and a track the user set to `TrackInstrument.bioVoice`; both flags are registered ON,
        // but that is a condition and it belongs written down.)
        // Its own `setTuning(a4Hz:)` fan has existed all along — only the tone-system axis was
        // missing, which is why the two could drift apart unnoticed.
        //
        // ⚠️ THIS CALL IS A NO-OP AT LAUNCH AND THAT IS HANDLED IN THE RACK, NOT HERE. `onAppear`
        // runs during the first SYNCHRONOUS appear pass; `laneVoiceRack.attachAll` runs later,
        // from `EchoelmusicApp`'s async startup task, so at this instant the rack's three voice
        // arrays are EMPTY and both fans iterate zero times. `LaneVoiceRack` therefore LATCHES
        // the tuning and re-applies it to the voices it creates (see its `tuningCents` doc) —
        // the alternative was a third copy of the `"toneSystemID"` key and its default inside
        // `EchoelmusicApp`, i.e. the same one-decision-three-places split this fan is fixing.
        // The pre-existing `laneVoiceRack.setTuning(a4Hz:)` in `applyConcertPitch` below has
        // always had the identical exposure; the latch covers both axes.
        laneVoiceRack.setTuningCents(cents)
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

    /// ⭐ THE MUSICAL IDENTITY THIS INSTALL WOKE UP WITH — one line, once, at the end of the
    /// launch restore.
    ///
    /// #401. The founder reported the instrument playing "schief" (out of tune), and then that
    /// DELETING AND REINSTALLING the app cured it. Same binary either side of that, so the cause
    /// was a value PERSISTED ON THE DEVICE, not a code path — and the reinstall destroyed the
    /// only copy of the evidence. That is the whole reason this function exists: the question
    /// "which stored value was it" became unanswerable after the fact, and the next occurrence
    /// must not be.
    ///
    /// The existing `generate[…]` breadcrumb could not answer it. It carries four of these
    /// values, it fires only once the user presses Generate, and by then a user who reinstalls
    /// first has already taken the state with them.
    ///
    /// ⚠️ CALLED LAST IN `onAppear`, ON PURPOSE — after `applyArticulation()`, `applyTuning()`,
    /// `applyConcertPitch(_:)`, the genre-roster clamp that can REWRITE `studio.genre`, and
    /// `syncTouchSound()`. Move it earlier and it prints a de-curated genre that the clamp has
    /// already replaced. `Tests/CISmoke/LaunchLogsWhatItWokeUpWithTests` asserts that ordering,
    /// because it is the one property this design rests on and a call-site COUNT cannot see it.
    ///
    /// ⛔ WHAT THIS LINE DOES **NOT** REPORT, and the first version of this comment claimed it did:
    /// "what is driving the voices". It does not, and cannot from here. `EchoelmusicApp`'s async
    /// startup `.task` runs AFTER this synchronous appear pass — the repo says so in its own words
    /// at `EchoelmusicApp.swift` above the play-surface level restore — and that task then applies
    /// patches to `polyVoice`, `touchVoice` and `leadVoice`. So `touchPatch=custom` can print while
    /// the startup default is what ends up sounding (a real defect in its own right, filed as #402;
    /// do NOT patch it from inside a diagnostic). What this line reports honestly is **the
    /// persisted musical identity as restored, after the launch clamp** — which is exactly what the
    /// "schief" investigation needs, and is all it should ever be read as.
    ///
    /// `touchPatchID` is logged as a PRESENCE ("take" vs "custom"), never as its UUID. Which
    /// custom patch is loaded is not the diagnostic question — whether a user-authored patch is
    /// selected at all is — and a UUID in a log the founder pastes into a chat is identifying data
    /// with no payoff.
    ///
    /// TWO READING CAVEATS, because this line's only reader is a human scanning a pasted log:
    /// `key=`'s trailing octave digit is `TuningReference.noteName`'s fixed "4" and carries no
    /// meaning here — the PITCH CLASS is the content (the `generate[…]` site carries the same
    /// caveat). And `preset=-1` is not an error: −1 is the stored value for "no factory preset,
    /// use the genre's own patch".
    ///
    /// ⚠️ THE VALUES ARE HOISTED, NOT INLINED, and that is a constraint rather than a style
    /// preference. A pile of `String(format:)` calls inside one interpolation is exactly the
    /// shape that blew the type-checker in #287 (`3379bb3`) and turned the BLOCKING gate red.
    /// With no local Swift toolchain here, that costs a full CI round-trip to even discover.
    /// The same warning sits on the `generate[…]` breadcrumb for the same reason.
    private func logLaunchMusicalIdentity() {
        let keyText = "\(TuningReference.noteName(forMIDINote: 60 + rootIndex)) \(scale.rawValue)"
        let a4Text = String(format: "%.1f", session.a4Hz)
        let articulationText = String(format: "%.2f", articulation)
        let glideText = String(format: "%.2f", touchGlide)
        let touchText = touchPatchID.isEmpty ? "take" : "custom"
        // `""` is the stored value for "the genre's own rhythm"; printing it as `-` keeps the
        // label readable in a log line where every other field is populated. Both keys override
        // their role's rhythm for EVERY genre, which is why they belong here at all —
        // `StudioDefaultKeys` calls a non-empty `padRhythm` "every genre re-articulating its
        // chords on ONE grid", and the pad is the biggest audible surface since #166/#167.
        let bassRhythmText = bassRhythmRaw.isEmpty ? "-" : bassRhythmRaw
        let padRhythmText = padRhythmRaw.isEmpty ? "-" : padRhythmRaw
        // The user's own fader trim, in the same bass/pad/lead order the Mix panel shows and the
        // `generate[…]` breadcrumb already prints. It belongs on the LAUNCH line too because #399
        // is the same defect as "schief" one layer down: a level persisted at 0.00 mutes a whole
        // role for every take of a session, and nothing else in a log distinguishes that from a
        // broken engine. `drums` is cleared by the reset but NOT printed — there is no door left
        // to show or change it (#166/#167), so a number nobody can act on would only pad the line.
        let mixText = String(format: "%.2f/%.2f/%.2f", mixer.bass, mixer.pad, mixer.lead)
        // ⭐ PRESENCE ONLY — NEVER THE NUMBERS (#403). This line answers "why does this install
        // open on a different skeleton than a fresh one", which needs exactly one bit: has a
        // fingerprint been learned. Printing the learned resting rate, HRV or coherence would
        // put health values into the file the founder pastes into a chat, and would turn a
        // musical handwriting into a readout ABOUT a person — the thing this feature is
        // forbidden from becoming. It is also what lets the value join `SoundReset` at all:
        // that list is keyed by the labels THIS line emits, deliberately, so a value that
        // cannot be reported honestly cannot be quietly half-reset either.
        let signatureText = performerSignature.hasBody ? "learned" : "none"
        // ⭐ THE EIGHT DIALS, IN THE ORDER THE MOOD PANEL SHOWS THEM: liveliness / darkness /
        // tension / romance / weird / virtuosity / syncopation / humanize. They belong on this
        // line for the reason every other entry does — until #275 they had no persistence at
        // all, so a session that "sounded different" had eight invisible reasons and the one
        // line built to answer that question could not name any of them.
        //
        // ⚠️ NUMBERS, NOT PRESENCE — deliberately the opposite call from `signature` above, and
        // the difference is what the value IS. A fingerprint is something the app inferred ABOUT
        // a person and must never be printed; these are eight settings the person chose, and the
        // whole diagnostic value is WHICH ONE is off. One `String(format:)` call, hoisted, for
        // the type-checker reason in this method's doc.
        let moodText = String(format: "%.2f/%.2f/%.2f/%.2f/%.2f/%.2f/%.2f/%.2f",
                              mood.liveliness, mood.darkness, mood.tension, mood.romance,
                              mood.weird, mood.virtuosity, mood.syncopation, mood.humanize)
        // ⭐ THE PAD SHAPE (#584), in the panel's own order: chord length / accent / variation.
        // It is here because the reset now clears it, and the note above is the rule: this list
        // is keyed by the labels THIS line emits, so a value that cannot be reported honestly
        // cannot be quietly half-reset either. Numbers rather than presence, for the mood
        // reason — the diagnostic value is WHICH dial is off, and "the chords are all stabs"
        // is exactly a report that arrives with no other evidence.
        //
        // ⚠️ It is reported even when no pad character is selected, i.e. when the three dials are
        // disabled and inert. That is on purpose and it is the failure this slice is about: a
        // stale shape is invisible precisely while it does nothing, and comes back the moment a
        // character is picked again.
        let padShapeText = String(format: "%.2f/%.2f/%.2f", padGate, padAccent, padEvolve)
        EchoelCrashLog.breadcrumb("launch/musical: key=\(keyText), tuning=\(tuningID), a4=\(a4Text), genre=\(style.rawValue), preset=\(presetIndex), articulation=\(articulationText), bassRhythm=\(bassRhythmText), padRhythm=\(padRhythmText), padShape=\(padShapeText), mood=\(moodText), touchPatch=\(touchText), glide=\(glideText), userMix=\(mixText), signature=\(signatureText)")
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
            patchBeforeSoundChange = nil      // wholesale replace — see the property's doc
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
                Text("Metronome (click)").font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
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
            Text("Haptic beat (feel)").font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
        }
        .tint(EchoelTheme.accent)
        .accessibilityHint("Pulses the phone on each quarter-note so you can keep time eyes-free")
    }
    #endif

    /// Tap a tempo in time — the classic performance way to dial BPM by feel. Tapping
    /// locks the BPM (so the take holds it) and steers the click; a long pause resets.
    /// Locking here reaches the same "tempoLock" hook the other two lock doors reach (the
    /// Flow|Loop picker posts it itself; the transport lock calls `onLockChanged`, and its
    /// one caller posts), so a running take is recomposed instead of left at the old tempo.
    /// "Recomposed" is debounced by ~0.45–2 s — see the consequence spelled out at the post
    /// below. (⛔ This said "and lands on `round(lockedBPM)`". #380 removed that rounding ONE
    /// COMMIT LATER and left this line standing, so the file's most-read entry point for
    /// tap-tempo work described the opposite of its own code. Written by the same session
    /// whose commit message names that defect class by name.)
    private var tapTempoRow: some View {
        HStack(spacing: 12) {
            Button {
                if let bpm = tapTempo.tap(at: ProcessInfo.processInfo.systemUptime) {
                    lastTappedBPM = bpm
                    lockedBPM = (bpm * 10).rounded() / 10
                    // ALWAYS push the clock, not only while running — the click and the
                    // transport read the clock, so a tap has to land there whether or not a
                    // take is playing. `setTempo` while stopped just stores the value (no tick
                    // scheduling), so it is safe.
                    //
                    // ⛔ THE REASON THAT USED TO STAND HERE WAS FALSE, and #356 only found it
                    // because the guard it installed asserts the opposite. It said the clock
                    // "must already carry the tapped value" because `WorkspaceView.modeBinding`
                    // "freezes at the CLOCK's current tempo … when that fires" — but that is a
                    // `Binding`'s `set` closure, and it runs only when the Flow|Loop Picker is
                    // driven. Writing the shared `@AppStorage` key from here goes through the
                    // binding's `get`, never its `set`; it cannot fire from this code path. The
                    // trailing note on the next line said "onChange adopts clock", and
                    // `git grep` finds NO `onChange(of: lockBPM)` or `onChange(of: lockedBPM)`
                    // anywhere under `Sources/`. Both claims were checkable and both were wrong.
                    beatPlayer.pattern.setTempo(lockedBPM, source: .user)
                    lockBPM = true
                    // ⛔ #356: THIS POST WAS MISSING, AND IT IS THE ONLY THING THAT MAKES A TAP
                    // AUDIBLE IN THE TAKE. `lockBPM` has three doors — the Flow|Loop picker
                    // (`WorkspaceView.modeBinding`), the transport lock (`BodyTempoField`, whose
                    // `onLockChanged` callback its one caller turns into this same post) and
                    // this tap. Without the post a tap moved the CLOCK while the take kept the
                    // note density it was generated with — the pattern audibly stopped matching
                    // its own tempo. (It also flipped the composition mode Flow→Loop with no
                    // recompose to explain it; the hint below now says the lock happens.)
                    //
                    // ⚠️ THE WRITE ORDER IS NOT LOAD-BEARING, and saying otherwise was the first
                    // version's mistake — it argued "post is synchronous, so the clock and the
                    // lock must already be settled". `post` IS synchronous, but the one receiver
                    // reads neither: `handleCompositionEdit`'s "tempoLock" case calls only
                    // `recomposeIfRunning()`, and that DEBOUNCES — `scheduleGenerate` cancels the
                    // pending task and sleeps 0.45–2 s before `generate()` reads the clock and
                    // the lock. The statements are ordered to read causally, nothing more.
                    //
                    // ⚠️ ONE CONSEQUENCE A PERFORMER WILL HEAR, NEEDS-FOUNDER-VERIFY: the
                    // recompose runs `makeComposerInput(advanceEvolution: true)`, which bumps the
                    // evolution nonce — so a tap now replaces the take's NOTES, not just its
                    // speed. The other two doors pay the same price, but they are one-shot mode
                    // switches; tapping is a repeated performance gesture.
                    //
                    // ⛔ A SECOND CONSEQUENCE STOOD HERE AND IS FIXED, NOT PENDING. It said
                    // `generate()` resolves the locked tempo as `lockedBPM.rounded()`, that a
                    // 123.4 tap lands the clock on 123, and that this was "tracked separately".
                    // It was — as #380, which landed the very next commit and removed the
                    // rounding, while this paragraph stayed and went on describing it. The
                    // instruction inside it is the part still worth having, so it is kept and
                    // not deleted: DO NOT "fix" a future rounding complaint by rounding the tap
                    // — that throws away the precision the transport field advertises. What is
                    // dead is the claim that the clock still rounds.
                    //
                    // Repeated taps do NOT storm: each post cancels the pending regen task and
                    // the user-edit floor is 2 s, so a burst of taps yields exactly ONE
                    // `generate()`, at the last tapped tempo. While STOPPED the branch is
                    // `applySoundLive()`, which is NOT debounced — once per tap, cheap, unmeasured.
                    NotificationCenter.default.post(name: .echoelCompositionEdited,
                                                    object: "tempoLock")
                }
            } label: {
                Label("Tap tempo", systemImage: "hand.tap")
                    .font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            // The lock is a MODE change (Flow → Loop), not a side note: it is what the doc
            // comment above has always described and what the hint never mentioned. Kept to
            // one sentence past the action — 77 characters against a median of 61.5 (measured
            // over all 62 single-line literal `accessibilityHint`s under `Sources/`, this one
            // included; the longest in the app is 154). #355 paid for a 221-character one,
            // which VoiceOver reads in full with no way to skim.
            .accessibilityHint("Tap in time to set the tempo. This locks the tempo and sets the mode to Loop.")

            if let tapped = lastTappedBPM {
                Text("\(Int(tapped.rounded())) BPM")
                    .font(EchoelTheme.font(13).monospacedDigit()).foregroundStyle(EchoelTheme.dim)
                    .frame(width: 84, alignment: .trailing)
            }
        }
    }

    // MARK: Panel — Master (master level + EBU R128 loudness)   // "output" struck, #316

    /// The mastering readout — master volume plus the live EBU R128 loudness numbers
    /// (short-term + gated-integrated LUFS, max true-peak in dBTP, loudness range in LU).
    /// These are what producers and broadcasters master to. Reset clears the integration +
    /// peak hold to start a fresh measurement.
    ///
    /// ⛔ THIS SAID "loudness of the OUTPUT" until #316 (2026-08-01). It is measured at the
    /// master chain's INPUT — before EQ, auto-gain, limiter and the −1 dB trim.
    /// `MasterLoudnessGrid` now states that on screen and no longer colours the numbers
    /// against the delivery target; its file header carries the reasoning. The Target picker
    /// below is unaffected — it drives the auto-gain and the export, both of which are real.
    private var masterPanel: some View {
        // ⛔ The subtitle said "Output level · …" until #316. `MasterVolumeField` really is an
        // output control (`masterMixer.outputVolume`), so the word was not wrong ABOUT IT —
        // but it sat one line above a meter that does not measure the output, and a reader
        // attaches a subtitle to whatever is under it. "Master level" is true of the control
        // and makes no claim about the numbers.
        panel("Master", "Master level · EBU R128 loudness", isExpanded: $showMaster) {
            // Master volume lives in its own view (MasterVolumeField) so an automation
            // lane rewriting audioEngine.masterVolume re-renders only that field, not the
            // menu-hosting studio body. (Was the remaining take-time Picker-freeze source.)
            MasterVolumeField()

            // #292 Slice 5: the two delivery choices are the panel's only pair of same-height
            // parameter rows, so they reflow to two columns on a wide layout. `spacing: 14`
            // matches `EchoelPanel`'s own content spacing because in ONE column the grid's
            // `VStack` REPLACES the host's rhythm (the `visualAdjustFields` lesson) — the
            // default (10) would silently tighten iPhone portrait, which does not reflow at
            // all. Everything else in this panel stays OUTSIDE the grid on purpose: the
            // volume field and the loudness numbers are churn-isolating leaves, and the
            // caption/button rows want the full measure (`MasterPanelReflowsTests`).
            AdaptiveCardGrid(spacing: 14) {
                labeledRow("Target") {
                    Picker("Target", selection: $loudnessTargetRaw) {
                        ForEach(LoudnessTarget.allCases) { t in Text(t.displayName).tag(t.rawValue) }
                    }
                    .pickerStyle(.menu).tint(EchoelTheme.text)
                    .accessibilityLabel("Loudness delivery target")
                }

                // The `.onChange` calls the SAME method the launch path calls
                // (`configureEQ()` → `applyPersistedPreset()`), rather than mapping the raw value
                // to a `Preset` a second time here. One owner, two callers — the
                // `MIDIOutput.applyOutputPreferences()` shape, and the reason a stored choice and
                // a live tap can never disagree.
                // ⚠️ Since #292 Slice 5 this observer lives in a LAZY grid cell: a write to
                // `masterCharacterRaw` from OUTSIDE this Picker while the cell is off-screen
                // (two-column mode, scrolled away) would not reach the engine until relaunch.
                // Unreachable today — the only other writer is the onAppear migration, which the
                // launch path re-applies anyway (#744). A SECOND programmatic writer must call
                // `applyPersistedPreset()` itself, not rely on this `.onChange`.
                labeledRow("Tone") {
                    Picker("Tone", selection: $masterCharacterRaw) {
                        ForEach(AutoMixChain.Preset.allCases) { p in
                            Text(p.displayName).tag(p.rawValue)
                        }
                    }
                    .pickerStyle(.menu).tint(EchoelTheme.text)
                    .onChange(of: masterCharacterRaw) { _, _ in
                        audioEngine.autoMixChain.applyPersistedPreset()
                    }
                    .accessibilityLabel("Master tonal character")
                    .accessibilityHint("Balanced, warm, bright or transparent — the EQ curve on the master bus")
                }
            }

            // The live numbers live in their own view so the 60 Hz meter refresh
            // re-renders only this small grid, not the whole studio body.
            MasterLoudnessGrid()

            // ⛔ THIS LINE USED TO READ "Streaming targets ≈ −14 LUFS integrated, true peak
            // ≤ −1 dBTP." — and #316's first pass left it standing two lines under its own
            // "measured before the master chain" caption. That is the removed verdict handed
            // back to the reader as an instruction: take the number above, compare it to
            // these figures yourself. Same claim, slower medium. It now says what the target
            // actually governs (the auto-gain and the export), not what the numbers mean.
            HStack {
                Text("The Target above sets the auto-gain and the export; the numbers are the mix, not the delivered file.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                // ⛔ #394 — THIS WAS A BARE TITLE BUTTON WITH NO FRAME AT ALL, i.e. a tap
                // target the size of the word: ~35 × 15 pt at `EchoelTheme.font(12)`. That is
                // under the HIG 44×44 floor AND under WCAG 2.5.8 (AA)'s 24×24 — the only
                // control in this file's audited `Button("literal") { … }` set that failed
                // both, and the same class as the clear-place ✕ that `TapTargetFloorTests`
                // already pins. It sits hard against the panel's right edge behind a
                // `Spacer`, so a thumb that lands ten points low hits nothing at all.
                //
                // The frame goes on the LABEL, not on the `Button`: for a title button the
                // label's bounds are what gets hit-tested, so an outer `.frame` would grow the
                // picture without growing the target. `contentShape` then makes the whole
                // 44 pt-tall rectangle hittable rather than just the glyph run.
                //
                // `minHeight`, never `height`: the sentence to the left wraps and is already
                // taller than 44 in most widths, so on a phone this changes no layout — it
                // guarantees the floor exactly in the cases (wide screen, one-line text) where
                // the row would otherwise collapse to the label's own height. A fixed height
                // would also clip the label at large Dynamic Type sizes (the #353 class).
                //
                // `.buttonStyle(.plain)` is not a look change: `foregroundStyle` already
                // overrode the accent tint, so this only stops the default style from
                // re-asserting its own padding on top of the frame.
                Button {
                    audioEngine.resetMastering()
                } label: {
                    Text("Reset")
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.text)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Clear the integrated loudness and peak hold")
            }

            // #408: the render-timing meter (#193) has existed for a week and speaks only into
            // `echoel_diag.log`, a file the founder has to export and send. The v10.79.369
            // "teilweise extremes Knacken" report arrived without one, leaving six candidate
            // mechanisms unseparated (#407). This row is the same verdict where it can be read
            // AT THE MOMENT the crackle is heard. Its own leaf, per the freeze law — the write
            // is once per 60 s, but the law is about where the observer registers.
            AudioTimingRow(engine: audioEngine)

            // LABEL IS A RELEASE, NOT A MUTE (review 2026-07-26). "Silence" over-promised:
            // this button releases every held note, but it does not stop the transport, so the
            // roll re-attacks on its next step and the bio arm re-opens on the next inhale.
            // The accessibility hint below always said "release"; the label now agrees.
            Button { panicAllNotesOff() } label: {
                Label("Release all notes", systemImage: "speaker.slash")
                    .font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
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
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.text)
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }

    // MARK: - Audio timing readout (#408)

    /// The render-timing verdict as ONE panel row, in its OWN `View` struct.
    ///
    /// ⚠️ THE LEAF IS NOT OPTIONAL EVEN THOUGH THE RATE IS HARMLESS. `lastTimingLine` changes
    /// once per 60 s, which could not freeze anything — but the 10.76.50 law is about WHERE an
    /// observed read registers, not only how fast it fires.
    ///
    /// ⛔ AND THE FIRST VERSION OF THIS PARAGRAPH NAMED THE WRONG "WHERE", WHICH IS THE ONE
    /// MISTAKE THIS FILE ALREADY CORRECTS ELSEWHERE. It said a direct read in `masterPanel`
    /// would enrol THE ROOT BODY as an observer. It would not: `masterPanel` goes through the
    /// `panel(...)` helper into `EchoelPanel`, which stores its content as an `@escaping
    /// @ViewBuilder` closure and invokes it inside ITS OWN `body` — a real observation
    /// boundary, unlike `AnyView`. The note above `dropdownContent` in this same file says
    /// exactly that, 1400 lines up, and a session reading the old wording here would have
    /// re-acquired the misconception that note exists to kill.
    ///
    /// The leaf is still right, for a nearer reason: without it the observer is `EchoelPanel`'s
    /// body, so the WHOLE Master panel re-renders — and this panel hosts a `.pickerStyle(.menu)`
    /// Picker ("Target", the loudness delivery target) whose open popover a rebuild tears down.
    /// Once a minute is a hazard rather than a freeze, and it is one refactor away from being
    /// the freeze again. A leaf costs six lines and closes the class.
    ///
    /// ⚠️ IT READS `isRunning` TOO, AND THAT IS DELIBERATE. `stop()` invalidates the meter poll
    /// timer without clearing `lastTimingLine`, so the string outlives the measurement; the
    /// resolution lives in `RenderGapDetector.Tally.screenText`, which qualifies a pre-stop
    /// verdict instead of presenting it as current. `isRunning` changes only on start/stop, so
    /// observing it here costs nothing.
    ///
    /// ⚠️ THE CAPTION IS UNCONDITIONAL. A clean timing window is not an all-clear for the
    /// founder's report: a voice steal, a parameter step or an un-faded seam clicks with the
    /// audio path perfectly on time, and this meter is blind to all three (`RenderGapDetector`'s
    /// header says so at length). A caveat shown only on dirty windows would let "Nothing late"
    /// read as "the crackling is fixed" — the one sentence this row must never say.
    private struct AudioTimingRow: View {
        let engine: AudioEngine

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Audio timing")
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    Spacer()
                    // ⚠️ `fixedSize` on the VALUE, not only the caption. The longest real
                    // string is "3 late in 60 s · worst 12.8 ms behind"; opposite a label with
                    // a Spacer between, SwiftUI will squeeze a `Text` to its ideal width and
                    // truncate — and the number this whole row exists to deliver is the part
                    // that would be elided. The sibling row eleven lines up does the same.
                    Text(RenderGapDetector.Tally.screenText(line: engine.lastTimingLine,
                                                            isRunning: engine.isRunning))
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(RenderGapDetector.Tally.screenCaption)
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
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
                        .font(EchoelTheme.font(13))
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
            // #747 — THE DOOR TO THE FULLSCREEN FIELD (open task #270, closed here). Everything
            // behind `.fullScreenCover(isPresented: $showVisual)` was already built and polished
            // — the fullscreen `MetalBioView`, the VJ overlay, `SpectralDonutView`, record, close
            // — and `showVisual` had exactly two writers in code, its own `@State` initialiser
            // and the close button, BOTH `false`. Ship-gate 4 ("visual live + contemplative on
            // device") had its second half unreachable.
            //
            // ⚠️ A VISIBLE BUTTON, NOT A GESTURE, and the cover's own top bar is why: it cites
            // WCAG 2.2 against gating controls behind a hidden gesture. A long-press on the
            // header monitor would have been cheaper and would have repeated the defect this
            // code already names. It sits HERE, next to the window toggle, because that is where
            // a player already goes to decide how the field is shown — not a second door to the
            // same thing (#290): the floating window and the fullscreen field are two surfaces.
            //
            // ⚠️ THE MODAL CHAIN DOES NOT GROW. The slot has existed all along; this adds a
            // setter, not a modifier. The black-screen metadata law (10.76.34) is untouched, and
            // the un-settable-flag list above is now TWO, not three.
            //
            // GPU exclusivity is already handled: `.onChange(of: showVisual)` hides the floating
            // window while the cover is up and restores its prior state on dismiss, because only
            // ONE `MetalBioView` may drive a CADisplayLink at a time.
            Button {
                showVisual = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                    Text("Full screen").font(EchoelTheme.font(13))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(EchoelTheme.text)
                .padding(.horizontal, 12).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .accessibilityLabel("Open the visual full screen")
            .accessibilityHint("Fills the display with the bio-reactive field and its performance controls.")
            // ⛔ `signalSection` STOOD HERE AND IS REMOVED (#575, founder 2026-08-13). He
            // circled the whole block on a v10.79.388 screenshot — the wavefront, its
            // paragraph, the spectrum, its paragraph, the `63,0 Hz · B1 +36 ct` readout —
            // and wrote: *"Das Brauch da nicht sein. Wenn dann ins Visual Window
            // übertragen."* The unconditional half is done here. The conditional half
            // ("wenn dann") is NOT done, deliberately: putting a measurement readout over
            // the immersive field is a layout he has not seen, and inventing one would be
            // the same overreach as the 2026-08-02 note that kept two struck views mounted
            // "pending a device look". It is registered as a slice in
            // `scratchpads/PLAN_ONE_VISUALISER.md` instead.
            //
            // `AnalysisWavefrontView` and `AnalysisSpectrumView` are now PARKED — files
            // intact, cores and content guards still running, doorless ON PURPOSE, exactly
            // like `AnalysisScopeView` and `AnalysisPoincareView` since 2026-08-02. All four
            // analysis views are now in that state; the Field panel shows no meters at all.
            // Restoring any of them is one line here plus its caption. Do NOT "fix" the
            // doorlessness by re-mounting, and do NOT delete the files.
            //
            // ⚠️ AND THE VIEWBUILDER NOTE BELOW IS NOW ONE CHILD LOOSER, not obsolete: the
            // ten-child claim it argues against was already struck as false in #359's
            // step-2 nachlese (there is no arity cap since `buildPartialBlock`; the real
            // cost is type-checker time). The `Group` stays because that cost is real.
            // `Group`, and it is NOT decorative: `panel(_:isExpanded:)` takes a `@ViewBuilder`
            // whose type-check cost grows with the child count. A
            // `Group` collapses these three into one child while staying LAYOUT-TRANSPARENT —
            // the enclosing stack still spaces them itself, so nothing moves on screen. That
            // is why it is a `Group` and not a `VStack`: a stack would impose its own spacing
            // and silently re-space three rows that were fine.
            Group {
                groupHeader("Look")
                // `false`: this panel's visual is `FloatingVisualWindow`, which never reads
                // `spectralDonuts` — so claiming donut state here is a claim about another surface.
                visualLookStrip(showsDonutState: false)
                visualLookCustomizer
            }
            // The A/B "Blend with" strip left this surface 2026-07-07 (founder: minimize —
            // the mix was extra clicking) and the view itself is DELETED as of #324. The
            // blend is not gone: the look SLIDER above owns `visual.styleB`/`visual.blend`,
            // and the migration in onAppear still clears a lingering blend on a look that
            // fell out of the slider sequence.
            //
            // ⭐ ORDER IS THE FIX (#369, founder screenshot 2026-08-01 09:00 — the whole
            // block circled in red). "Preset" sat between the look controls and the colour
            // row, and it does not set a look at ALL: `applyVisualPreset` writes intensity ·
            // detail · motion · spread · hue · saturation and never touches `visualStyle`.
            // Those six are Energy plus the preset-backed "Fine tune" rows (since #853 the
            // fine-tune grid also holds Texture/Glitter, which the presets deliberately do
            // NOT write — the exactly-identity broke there on purpose) — and Energy's own
            // caption says "across the same range the presets span" while pointing at a
            // strip the reader has already scrolled past. Two controls describing each
            // other, separated, with an unrelated row wedged between them.
            //
            // So: Preset sits directly above the fields it writes, and `MusicColourRowView`
            // moves down beside the colour caption that explains it (and Hue/Saturation).
            // Three sections instead of one dense stack — what it renders AS, how intense,
            // where the colour comes from. #369 added and removed nothing: the same children
            // in this ViewBuilder, read in the order they are used. (It said "the same EIGHT"
            // and stayed at eight after #359 step 2 made it nine — a present-tense count in a
            // comment about a DIFFERENT change, which is how these go stale. The panel's
            // children are no longer enumerated anywhere: the doc block that held the list
            // went with `signalSection` (#575), and a list in prose is what went stale here
            // twice already. COUNT them if you need the number.) (The
            // presentation-modifier ceiling is a different budget entirely — it counts the
            // `.sheet`/`.fullScreenCover` chain on `EchoelStudioView.body`, which panel
            // children never touched. An earlier draft of this note ran the two together.)
            //
            // NOT done here and worth naming: the colour pair still has no heading of its
            // own, so "Look" and "Preset" head two of three sections. Adding a third would be
            // another top-level child. What that costs is type-check TIME, not an arity
            // error — the false "ten-child cap" is struck at length further down this file,
            // on the `panel(_:isExpanded:)` note. (⛔ This sentence used to point at
            // `signalSection`'s doc block, which #575 removed with the section. A pointer is
            // only as durable as what it points at — #472, the same defect, again.)
            visualPresetRow
            // 14 = `EchoelPanel`'s own content spacing. Passed rather than defaulted so the
            // one-column (portrait) rendering of the grids inside is bit-identical to the
            // stack it replaced — see the ⭐ block on `visualAdjustFields(spacing:)`.
            visualAdjustFields(spacing: 14)
            MusicColourRowView()
            Text("Colour defaults to the heard tone octave-transposed into visible light (its frequency doubled until it reaches the visible band, rendered via CIE 1931); Hue/Saturation rotate the palette for VJ/performance use. Motion is capped so the flash rate always stays under the 3 Hz safety limit.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            // #359 step 2 — directly under the colour caption, because Hue and Saturation are
            // the two words that caption just used, and these four are the weather's pull on
            // exactly those. Renders nothing while weather is off (the default), so the panel
            // is unchanged for anyone who never turns it on.
            #if canImport(WeatherKit) && canImport(CoreLocation)
            weatherImageRow
            #endif
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
            // dim heading it was supposed to pair with. Two headings that claim to be
            // siblings must look like siblings. (#362 took that from "copy the spelling" to
            // "share the builder" — both now call `groupHeader`, so they cannot drift apart
            // again. The size named here was "10 pt"; it is 11 now, and the point of routing
            // it through one helper is that this sentence never has to carry a number.)
            groupHeader("Voice")
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
            EchoelValueField(label: "Level", value: fieldLevelBinding,
                             range: 0...1.5, unit: "", decimals: 2)
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
        groupHeader("Self-play")
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
                .font(EchoelTheme.font(12))
                .foregroundStyle(selected ? EchoelTheme.onPrimary : EchoelTheme.text)
                // `minHeight` 34, not `height` 30 (#617): the fixed pill clipped at AX
                // sizes (#353 class) AND sat under every tap floor. 34 is the house
                // in-panel floor; no outset — the neighbouring chips in the 8 pt row
                // are themselves selectable, and two −5 outsets would overlap by 2 pt.
                .padding(.horizontal, 11).frame(minHeight: 34)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(selected ? EchoelTheme.text : EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) play-surface sound")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Panel — Entrainment (biofeedback-driven isochronic pulsing)

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
    ///
    /// ⭐ THE HEADING IS `groupHeader` AS OF #369, and it was the last inline one in the
    /// studio. It read `font(13)` in `EchoelTheme.text` — bigger AND brighter than the
    /// `groupHeader` ("Look", 11 pt semibold dim) above it, so this strip did not read as a
    /// row inside the look section OR as a peer of it: it read as the panel's dominant
    /// heading, louder than every real section around it. #362 unified seven headings and
    /// missed this one because it grepped for the 10 pt spelling; a fourth spelling nobody
    /// had listed survived the sweep that existed to end exactly that.
    ///
    /// Both mounts get it — the inline Field panel and `visualVJOverlay` — because this is
    /// one shared property. The overlay is doorless (#270), so that half is latent.
    private var visualPresetRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            groupHeader("Preset")
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
                            if selected {
                                visualPresetID = ""
                                // #379 — a DELIBERATE deselect must not be undoable by a later
                                // cancelled drag. `visualPresetDiverged` restores whatever it
                                // itself cleared; this clear is the user's, so it leaves no memo.
                                clearedVisualPresetID = ""
                            } else { applyVisualPreset(preset) }
                        } label: {
                            Text(preset.name)
                                .font(EchoelTheme.font(12))
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
            // also HID `visualBlendControls`. It did not — that view had ZERO mount sites, so
            // nothing was hidden. Writing an unreachable claim into the rationale of the commit
            // that removes unreachable claims is the failure itself. It was introduced and
            // retracted the SAME DAY (`99c9d13` → `4ef5e68`, 2026-07-30) and caught in review.
            // `visualBlendControls` is deleted as of #324; the look slider still owns
            // `visual.styleB`/`visual.blend`, so no reachable capability went with it.
            //
            // ⛔ AND #324's OWN TOMBSTONE THEN OVERSTATED THIS, which is why the retraction is
            // spelled out with commit hashes now. It wrote that the note "did exactly the damage
            // predicted … blocked a legitimate deletion", turning this paragraph's honest
            // counterfactual ("it WOULD have marked a doorless view as live") into an assertion
            // of damage that never occurred. The note existed for one commit on one day, two
            // days before the deletion. What actually kept the view alive for 25 days is duller
            // and worth knowing: two comments recording its removal in the PRESENT TENSE, and no
            // guard enforcing them, until `NoDoorlessStudioViewsTests` (#322) surfaced it.
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
                .font(EchoelTheme.font(12))
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
                                Text(look.name).font(EchoelTheme.font(12))
                            }
                            .foregroundStyle(on ? EchoelTheme.onPrimary : EchoelTheme.text)
                            // Same law as `touchPatchChip` above (#617): min-34 pill,
                            // no outset — adjacent look chips are selectable peers.
                            .padding(.horizontal, 11).frame(minHeight: 34)
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

    // ⛔ `private func normaliseUnreachableDonutMode()` STOOD HERE AND IS DELETED (#747).
    // It cleared a persisted `visual.spectralDonuts == true` on every launch, for the one
    // reason written into its own doc block: while the donut renderer had no door, `true` was
    // a state nothing could undo. #747 gave `showVisual` a setter ("Full screen" in
    // `visualPanel`), so the cover's top-bar donut toggle is reachable and the value is the
    // player's again. The deletion is the instruction, not an inference — the doc block
    // ordered it in this exact commit.
    //
    // ⚠️ WHAT DID *NOT* CHANGE, because the obvious follow-up is wrong: the persisted DEFAULT
    // stays `false` (`StudioDefaultKeys.visualSpectralDonuts`), and
    // `VisualLookTruthTests.testAFreshInstallDoesNotClaimTheDonutRenderer` is NOT flipped. Its
    // failure message invited the flip, but the assertion it makes is still true and now states
    // a design choice instead of a limitation: a fresh install opens on the Metal field, which
    // is the identity look, and donut mode is something a player CHOOSES from the cover. Only
    // that test's PROSE needed correcting.

    /// ⛔ DELETE THIS TOGETHER WITH THE LINE THAT CALLS IT, IN THE SAME COMMIT THAT GIVES
    /// `MixerStore.lead` A DOOR AGAIN (a lead fader, or any other control that writes it).
    /// Same shape and same reason as `normaliseUnreachableDonutMode()` above, one store down.
    ///
    /// #255 deleted the Mix board's "Lead" field on the founder's call. `MixerStore.lead` is
    /// persisted (`"mixer.lead"`) and that field was its ONLY writer besides `resetToUnity()`,
    /// which is itself only reachable from the same panel. So a player who once pulled the
    /// lead down to 0.30 would keep 0.30 forever — and the moment a genre produces a
    /// `.lead`-role note again (#243/#196, or any future genre with `leadDensity > 0`), that
    /// stored value multiplies straight into the velocity via `MixerStore.combined` and
    /// attenuates the new lead by 70 %, with no control able to undo it. That is strictly
    /// worse than the inert fader the slice removes, which is why the two ship together.
    ///
    /// Deliberately NOT a migration flag: while no door exists, the only truthful value is
    /// unity, and re-asserting it each launch costs one comparison. The `!= 1` guard keeps
    /// `didSet` — and therefore the `UserDefaults` write — off the path for everyone already
    /// at unity, which is every fresh install.
    private func normaliseDoorlessLeadMix() {
        guard mixer.lead != 1.0 else { return }
        mixer.lead = 1.0
    }

    /// Rewrite a stored master character that no longer parses, so the Picker and the engine
    /// cannot disagree (#743, closing the last item #737 registered against #736).
    ///
    /// ⚠️ WHEN THIS FIRES: only after a `Preset` case is RENAMED — a rawValue is a persistence
    /// token, and #736's guard pins the four that ship. So this is a corner, not a live bug,
    /// and it is written anyway for the same reason `normaliseUnreachableDonutMode()` was: the
    /// install that hits it has NO control able to undo the state, because the Picker it would
    /// use is the thing showing nothing.
    ///
    /// ⭐ IT RESOLVES THROUGH `Preset.resolved(from:)`, NOT A SECOND `?? .balanced`. That
    /// method is the one owner of token → character (#740); spelling the fallback again here
    /// would be a second mapping of one decision (#416) — precisely the shape #736 removed
    /// from the Picker's `.onChange`. If the fallback ever stops being `.balanced`, this
    /// follows without being touched.
    ///
    /// ⚠️ It does NOT call `applyPersistedPreset()` — and the reason is the OPPOSITE of what
    /// #743 wrote here. That version said "the engine already resolved the same way at launch,
    /// so the EQ is correct before this runs". ⛔ THE ORDER IS REVERSED (#744): this `onAppear`
    /// is the first SYNCHRONOUS appear pass, and `prepareGraph()` → `configureEQ()` →
    /// `applyPersistedPreset()` runs from the ASYNC startup task afterwards. Two comments in
    /// this repo already state that order — one nine lines below this block, one in
    /// `EchoelmusicApp` beside the startup task — and the #743 rationale contradicted both.
    ///
    /// The correct reason is stronger: **the store is corrected FIRST, so the engine never
    /// sees an unparseable token at all** and resolves the already-normalised one. Re-applying
    /// here would write the EQ before the graph exists. Today's outcome is identical either
    /// way (both routes land on `.balanced`), which is exactly why a wrong rationale could sit
    /// in three places without anything going red — the case this file legislates against by
    /// name: a comment with a wrong reason is worse than no comment.
    ///
    /// ⚠️ ONE REAL CONSEQUENCE, worth knowing before someone adds logging: a future
    /// `resolved(from:)` that wanted to LOG or MIGRATE on an unparseable token would never see
    /// one, because the view erased it first. Put such a hook here, not in the engine path.
    private func normaliseUnparseableMasterCharacter() {
        guard AutoMixChain.Preset(rawValue: masterCharacterRaw) == nil else { return }
        masterCharacterRaw = AutoMixChain.Preset.resolved(from: .standard).rawValue
    }

    /// Display name of the look nearest the slider position (no per-stop labels).
    private var currentLookName: String {
        LookBlendMap.nearestName(
            at: LookBlendMap.position(a: visualStyle, b: visualStyleB, frac: Float(visualBlend), sequence: sliderLooks),
            sequence: sliderLooks)
    }

    // ⛔ `visualBlendControls` STOOD HERE AND IS DELETED (#324) — a horizontal strip of
    // "Blend with" look buttons plus a `Mix` value field, a SECOND way to set the A/B look
    // blend.
    //
    // It was removed from BOTH surfaces that ever showed it on 2026-07-07 (founder:
    // minimize) — attested by `scratchpads/SESSION_LOG.md` and by two in-source comments,
    // NOT provable from git here: this clone is shallow-grafted at `24e9420` (2026-07-29),
    // so `git log -S visualBlendControls` bottoms out before that date. Those two comments
    // recorded the removal in the PRESENT TENSE a few hundred lines apart, and nothing
    // enforced them. That — plain doc rot with no guard — is what kept a doorless view in
    // the file for 25 days, until `NoDoorlessStudioViewsTests` (#322) surfaced it.
    //
    // ⛔ THIS TOMBSTONE'S FIRST VERSION BLAMED SOMETHING ELSE, and the commit message put it
    // in the subject line: a note in `StudioDefaultKeys` claiming the donut flag HID this
    // view, which supposedly "blocked the deletion once already" / kept it alive "three
    // weeks". Pickaxe says otherwise — that note was introduced and retracted the SAME DAY
    // (`99c9d13` → `4ef5e68`, 2026-07-30), two days before this deletion, and its own
    // retraction says "FOR ONE COMMIT … Caught in review". A tidy causal story about a
    // villain, invented on top of a boring true cause. The commit subject cannot be edited;
    // this paragraph is the correction of record.
    //
    // NOTHING REACHABLE IS STRANDED, and this is the check that made the deletion safe
    // rather than merely tidy: `visual.styleB` and `visual.blend` are NOT written only here.
    // The look SLIDER owns them — `lookScrub`'s setter writes both through
    // `LookBlendMap.blend(at:sequence:)`, here and in `FloatingVisualWindow`, and
    // `LookBlendMap.position(a:b:frac:sequence:)` reads them back to place the slider;
    // `ExternalDisplayScene` reads them too. (`LookBlendMap` is a pure `enum` of value
    // maths and writes nothing — the first version of this line said "position/nearest
    // reads and writes both", naming a `nearest` that does not exist (it is
    // `nearestName(at:sequence:)`) and crediting a pure function with a side effect.)
    //
    // ⚠️ "REDUNDANT" WAS THE WRONG WORD, though the conclusion survives. `LookBlendMap.blend`
    // can only emit pairs ADJACENT in the user's look sequence; this strip iterated the whole
    // library and wrote `visualStyleB` independently of `visualStyle`. So non-adjacent and
    // reverse-direction A/B pairs are expressible by the deleted code and not by the slider.
    // No shipped capability is lost — with zero mount sites since 2026-07-07 no user could
    // reach those states — but it is a reduction in what the code can express, not a
    // duplicate being tidied away. (Contrast #323, where the persisted key went too because
    // nothing else read it.)

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
                    groupHeader("Look")
                    // `true`: this overlay IS inside the cover that builds `SpectralDonutView`, and
                    // its top bar still toggles donut mode — here the state is real and worth naming.
                    visualLookStrip(showsDonutState: true)
                    // The A/B blend strip left here too (founder 2026-07-07 minimize) — the
                    // fullscreen VJ overlay mirrors the inline panel, so both dropped it, and
                    // #324 deleted the view once both mounts had been comments for weeks.
                    // SAME definitions as the inline panel (visualPresetRow +
                    // visualAdjustFields) so the two surfaces can never drift apart.
                    visualPresetRow
                    // 8 = THIS overlay's own `VStack(spacing: 8)` a few lines up, NOT the
                    // panel's 14. The overlay is height-capped at 360 pt for stage use, so a
                    // wider row rhythm is the wrong trade here — and in one column the grid's
                    // spacing REPLACES the stack's, which is exactly why this is an argument.
                    visualAdjustFields(spacing: 8)
                    // Projection output: this chrome-free, keep-awake canvas IS the beamer
                    // image — mirror it to a projector/TV via AirPlay (Control Center →
                    // Screen Mirroring). Tap the canvas to hide these controls for a clean
                    // projected picture. (Dedicated dual-screen — device = controls, beamer
                    // = visual only — needs an Info.plist scene manifest + device check, a
                    // separate cycle.) Only shown while the panel is open, so it never
                    // appears in the projected image.
                    Label("Project: mirror to a screen via AirPlay", systemImage: "airplayvideo")
                        .font(EchoelTheme.font(10))
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
        // `breathPacer.isRunning` (#486): the repo had ALREADY decided a paced breathing
        // session needs the screen awake — `showMeditation` is in this list — but that flag
        // has no setter, so the decision was only ever applied to an unreachable surface.
        // `BreathCoachStrip` is the reachable one, and a training session with the transport
        // STOPPED is exactly the case where nothing else here is true: the screen would dim
        // and lock mid-session. Read in a method, not in `body`, so nothing is observed here.
        UIApplication.shared.isIdleTimerDisabled =
            running || showVisual || showMeditation || breathPacer.isRunning
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
        // Belt and braces: a fresh pick has nothing left to restore.
        //
        // ⛔ ITS FIRST RATIONALE DESCRIBED AN IMPOSSIBLE STATE — "a later cancelled drag could
        // resurrect the PREVIOUS chip over this one". It cannot: the line above sets
        // `visualPresetID = p.id`, so the next `visualPresetDiverged()` takes the NEW id into the
        // memo before it ever looks at a restore. The line is harmless and stays; the reason it
        // used to give was refutable, and this file's own rule is that such a comment is worse
        // than none.
        clearedVisualPresetID = ""
    }

    /// Called by every control that moves one of the four ENERGY values a preset owns
    /// (Intensity · Detail · Motion · Spread — and the Energy macro that writes two of them).
    /// Hue/Saturation deliberately do not call it: they are palette-only and leave the
    /// selection intact, which is the rule `visualAdjustFields` already documented.
    ///
    /// ⚠️ THE RESTORE COVERS FOUR OF THE FIVE CALLERS, NOT FIVE — named by the #379 reviewer
    /// after the commit claimed the set was covered. The Energy macro binds a DERIVED value:
    /// `EchoelValueField` captures its cancel-reference as `visualEnergy`'s getter output (a
    /// single position `t`) and reverts by writing that number back, which runs
    /// `VisualEnergy.look(at: t)` and lands both parameters ON the curve. But `position(matching:
    /// motion:)` AVERAGES the two per-parameter positions, so the round trip is an identity only
    /// when both already sit at the same position — true for `zentrifuge`, false for the other
    /// four factory presets. A cancelled ENERGY drag therefore restores the dial position, not
    /// the preset's pair, the four-value comparison below correctly refuses, and that chip stays
    /// cleared.
    ///
    /// That is a property of the derived binding (the same "a small dial nudge can be a large
    /// parameter change" contract `VisualEnergy.position` documents), not something this fix
    /// introduced — and fixing it means memoing the pre-drag PAIR, which is its own slice. What
    /// was wrong was claiming coverage that does not exist.
    ///
    /// ONE rule, both directions: moving away from the selected preset clears the chip and
    /// remembers it; landing back on exactly that preset's four values restores it. Written
    /// as clear-then-try-restore rather than as two branches, because that makes a write that
    /// changed NOTHING a provable no-op — the memo is taken and immediately given back — which
    /// is the case `visualEnergy`'s `if changed` guard used to cover on its own.
    ///
    /// "Exactly" means the field's own 4-decimal display grid, not `==` on the raw Double, and
    /// that is the difference between the fix working and looking like it works. A preset
    /// writes `Double(Float)` — Aura's intensity lands on 0.800000011920929 — while every path
    /// through `EchoelValueField.apply` snaps to the grid and produces a clean 0.8. Raw
    /// equality would restore the chip after a CANCELLED drag (which puts the captured start
    /// value back bit-for-bit) but never after the user typed the same number back in, for a
    /// difference of one part in 10^8 that no display in the app can show.
    private func visualPresetDiverged() {
        if !visualPresetID.isEmpty { clearedVisualPresetID = visualPresetID }
        visualPresetID = ""
        guard let p = VisualPreset.factory.first(where: { $0.id == clearedVisualPresetID })
        else { return }
        // NaN cannot survive `rounded()` into an equality, so a poisoned value simply fails
        // to restore rather than matching something.
        guard sameOnDisplayGrid(visualIntensity, Double(p.intensity)),
              sameOnDisplayGrid(visualDetail, Double(p.detail)),
              sameOnDisplayGrid(visualMotion, Double(p.motion)),
              sameOnDisplayGrid(visualSpread, Double(p.spread))
        else { return }
        visualPresetID = clearedVisualPresetID
        clearedVisualPresetID = ""
    }

    /// Equal to four places — which since #427 is FINER than any of these rows can show, and
    /// that is the safe direction. It used to be exactly the display grid (`EchoelValueField`'s
    /// default `decimals: 4`); Intensity/Motion/Spread now pass `decimals: 2` and Detail has
    /// always been `decimals: 0`, so all four are compared on a grid strictly finer than the one
    /// they display on. Stricter never restores a chip it should not: two values that agree to
    /// four places agree on any coarser grid too.
    ///
    /// ⚠️ THE LIVE RISK IS THE ROW, NOT THIS FUNCTION. A future preset carrying a THIRD decimal
    /// would be unreachable from the two-decimal row that is supposed to reach it: the chip would
    /// still apply on tap and could never be restored by hand.
    /// `VisualPresetValuesAreReachableTests` makes that a red test rather than a door that only
    /// opens outward. Every value this function COMPARES is representable at two places today —
    /// intensity 0.8 · 0.95 · 1.1 · 1.2 · 1.4, motion 0.45 · 0.42 · 0.7 · 1.1 · 1.4, spread
    /// 1.35 · 1.2 · 1.0, detail 14 · 24 · 28 · 32 · 86 (already a whole-number row).
    ///
    /// ⛔ THE FIRST VERSION OF THIS PARAGRAPH GOT THE COMPARED SET WRONG IN BOTH DIRECTIONS: it
    /// named Vapor's palette (0.82 / 1.12) and omitted Detail. `visualPresetDiverged` compares
    /// FOUR values — intensity, detail, motion, spread — and never hue or saturation, which are
    /// palette-only and deliberately leave the selection intact (three lines above). The count
    /// that matters here is four, not six; the six is the number of ROWS the panel shows.
    ///
    /// The other direction is the one that cannot happen post-#427 and is written down so nobody
    /// re-derives it: comparing on a grid COARSER than a row can reach would restore the chip
    /// after an edit that genuinely left the preset. Four places is strictly finer than every
    /// participating row (2, 2, 2, 0), so that failure is out of reach — keep it that way.
    private func sameOnDisplayGrid(_ a: Double, _ b: Double) -> Bool {
        (a * 10_000).rounded() == (b * 10_000).rounded()
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
    ///
    /// ⚠️ TWO CONSEQUENCES OF BEING DERIVED, both sharpened by #427's two-decimal grid.
    ///  1. The getter RECOMPUTES rather than reading back what was written, so it returns the
    ///     same number only to within rounding (bit-exact on 39 of the 101 two-decimal
    ///     positions, worst residual 2.2e-16). A scrub's re-seed test therefore has to compare
    ///     what the two sides SHOW — see `ScrubPrecision.carriesTarget`, which exists because
    ///     raw equality stalled this exact row.
    ///  2. The setter writes `visualIntensity`/`visualMotion` straight from the curve, bypassing
    ///     `EchoelValueField.apply`, so those two rows can hold a value off their own grid: an
    ///     Energy position of 0.37 puts intensity near 1.022, which the Intensity row displays
    ///     as 1.02 and quantizes to 1.02 on first touch. That drift was ≤0.00005 before #427 and
    ///     is ≤0.005 now — small, visible only as one step of the picture, and stated here
    ///     rather than discovered.
    private var visualEnergy: Binding<Double> {
        Binding(
            get: { VisualEnergy.position(matching: visualIntensity, motion: visualMotion) },
            set: { t in
                let l = VisualEnergy.look(at: t)
                visualIntensity = l.intensity
                visualMotion = l.motion
                // Moving Energy diverges from whatever preset was tapped — same rule the
                // individual energy fields follow, and since #379 the same CALL. The
                // `if changed` guard that stood here is folded into `visualPresetDiverged`,
                // which is a no-op for a write that moved nothing (it takes the memo and
                // gives it straight back) — the case that mattered, because
                // `EchoelValueField.apply` writes its binding unconditionally after clamping,
                // so a drag or VoiceOver adjust at either end of the range re-writes the same
                // two values. What the old guard could NOT do is undo a clear that had already
                // happened, which is the cancelled drag #379 is about.
                visualPresetDiverged()
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
    /// #292 Slice 4 — the fine-tune rows reflow to two columns in landscape / on a regular
    /// width, on the same `AdaptiveCardGrid` primitive as `soundPanel` and `moodPanel`.
    ///
    /// ⭐ `spacing` IS A PARAMETER AND HAS NO DEFAULT, and that is the whole design of this
    /// slice rather than a detail. This ViewBuilder has TWO hosts with DIFFERENT container
    /// spacings — `visualPanel` renders inside `EchoelPanel` (`spacing: 14`) and
    /// `visualVJOverlay` inside its own `VStack(spacing: 8)`. In ONE column an
    /// `AdaptiveCardGrid` renders a `VStack` whose spacing REPLACES the host's, so any fixed
    /// literal here would silently re-space one of the two surfaces in PORTRAIT — the primary
    /// surface, which does not reflow at all and would therefore pay the whole cost for none
    /// of the benefit. Passing the host's own number keeps both bit-identical in one column.
    /// A DEFAULT would reintroduce exactly that risk invisibly: an argument no call site
    /// writes appears in no diff (#440/#443).
    ///
    /// ⛔ AND THE SECOND HOST HAS NO DOOR, which the paragraph above reads as if it did.
    /// `visualVJOverlay` is mounted only inside `.fullScreenCover(isPresented: $showVisual)`, and
    /// `showVisual` has no writer of `true` anywhere in `Sources/` — word-bounded, its two writers
    /// in code are its own `@State` initialiser and the close button, both `false` (open task
    /// #270; `visualPresetRow` already says "the overlay is doorless, so that half is latent").
    /// So the rule above is ASYMMETRIC rather than weaker: hardcoding **8** re-spaces the
    /// REACHABLE panel — a live cost, today — while hardcoding **14** re-spaces only a surface
    /// nobody can open. The parameter defends something live in exactly ONE direction and is
    /// bookkeeping for the day the door returns in the other. Both halves stay; only one is a
    /// defence, and saying which is the difference between a rule and a ritual.
    /// Pinned by `VisualFineTuneReflowsTests` claim 6, which goes red when the door comes back.
    ///
    /// ⚠️ ENERGY IS DELIBERATELY OUTSIDE THE GRID, and this is the half a grep-for-
    /// `AdaptiveCardGrid` guard cannot see. It is separated from the six by a caption and the
    /// disclosure Button — both full-width prose/controls — so a grid around it would order a
    /// single card, and a grid that orders one card orders nothing (#359 step 2 removed one
    /// for exactly that reason). The Detail caveat caption stays outside too: a sentence in a
    /// half-width cell beside a parameter row is the ragged layout `MoodPanelReflowsTests`
    /// condemns. That is why the six are split across TWO grids with the caption between them.
    ///
    /// ⛔ AND THE FIRST DRAFT PRICED THAT SPLIT AS FREE, WHICH IT IS NOT — it said "the rendered
    /// result is identical to one six-card grid in both column counts", and that is false on a
    /// FRESH INSTALL. The #269 caveat is not an edge case there, it is the default:
    /// `LookBlendMap` says so itself ("With the shipped defaults — primary style 5 (Aurora),
    /// styleB 0, blend 0 — that share is ZERO"), so `detailReach < 0.001` and the paragraph
    /// between the grids RENDERS. Six cards separated by a wrapping paragraph are not identical
    /// to six cards in one grid. What survives is the weaker, true claim: the cards land in the
    /// SAME PAIRS and the same row order a six-card grid would produce, and the seam is
    /// invisible only while the caveat is hidden.
    ///
    /// ⭐ AND EVEN THEN THE SEAM IS INVISIBLE FOR A REASON THE FIRST DRAFT DID NOT NAME. "Two
    /// cards fill exactly one two-column row" is necessary and not sufficient: the gap between
    /// grid 1's row and grid 2's first row is the HOST stack's spacing, while inside a single
    /// six-card grid it would be `LazyVGrid`'s own. They coincide only because the argument
    /// EQUALS the host's spacing. So `spacing == host stack spacing` is doing double duty — it
    /// is what makes portrait bit-identical AND what makes the two-grid split seamless in
    /// landscape. Passing some other number would not merely re-space portrait; it would make
    /// the split visible.
    @ViewBuilder private func visualAdjustFields(spacing: CGFloat) -> some View {
        EchoelValueField(label: "Energy", value: visualEnergy, range: 0...1, decimals: 2)
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
            AdaptiveCardGrid(spacing: spacing) {
                EchoelValueField(label: "Intensity", value: $visualIntensity, range: 0...1.5,
                                 decimals: 2, onChange: { visualPresetDiverged() })
                EchoelValueField(label: "Detail", value: $visualDetail, range: 8...90, decimals: 0,
                                 onChange: { visualPresetDiverged() })
            }
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
            AdaptiveCardGrid(spacing: spacing) {
                EchoelValueField(label: "Motion", value: $visualMotion, range: 0...1.5,
                                 decimals: 2, onChange: { visualPresetDiverged() })
                EchoelValueField(label: "Spread", value: $visualSpread, range: 0.5...1.5,
                                 decimals: 2, onChange: { visualPresetDiverged() })
                EchoelValueField(label: "Hue", value: $visualHue, range: 0...1, decimals: 2)
                EchoelValueField(label: "Saturation", value: $visualSaturation, range: 0...2, decimals: 2)
                // Texture + Glitter (#853, founder "mehr Struktur/Textur Regler"): the two
                // #578 finishing stages, now dialable. 1 = the shipped look, 0 = off, 2 =
                // double. Like Hue/Saturation they are palette-class controls and NOT part
                // of the visual presets — no `visualPresetDiverged()` on purpose.
                EchoelValueField(label: "Texture", value: $visualTexture, range: 0...2, decimals: 2)
                EchoelValueField(label: "Glitter", value: $visualGlitter, range: 0...2, decimals: 2)
                // Structure (#853B, the "Struktur" half of the same ask): a NEW static
                // domain warp that bends the 2D field's geometry. Neutral is 0 — the
                // stage did not exist before, so 0 IS the shipped look. Same
                // palette-class rule: not part of the presets, no divergence call.
                EchoelValueField(label: "Structure", value: $visualStructure, range: 0...2, decimals: 2)
            }
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
            // ⭐ #292 SLICE 3 — the same reflow `soundPanel` got in Slice 2, for the same
            // reason and with the same two exclusions. `EchoelValueField` fills whatever
            // width it is offered and `menuPanelHost` offers `maxWidth: .infinity`, so at any
            // regular width these eight rows put a label against the far left edge and its own
            // value box against the far right — hundreds of points of nothing between a name
            // and the number it names. `spacing: 14` is `EchoelPanel`'s own content spacing, so
            // iPhone PORTRAIT (one column, the primary surface) is byte-for-byte what it is
            // today; only the second column is new. The preset bar above and the weather block
            // and caption below stay OUTSIDE — the house rule that headers, sub-sections and
            // wrapping explanations want the full measure.
            AdaptiveCardGrid(spacing: 14) {
                // #614 — exactly the three dials `AutoAttune` steers carry `pausing:`;
                // the five below have no auto term, so a pause there would be a
                // registered flag nothing reads (see the `moodKnob` doc).
                moodKnob("Liveliness", $mood.liveliness, pausing: \.pausedLiveliness)
                moodKnob("Darkness", $mood.darkness, pausing: \.pausedDarkness)
                moodKnob("Tension", $mood.tension, pausing: \.pausedTension)
                moodKnob("Romance", $mood.romance)
                moodKnob("Weird", $mood.weird)
                moodKnob("Virtuosity", $mood.virtuosity)
                moodKnob("Syncopation", $mood.syncopation)
                moodKnob("Humanize", $mood.humanize)
            }
            // ⛔ A SECOND GRID, NOT TEN ITEMS IN THE FIRST — and with eight (an even number) of
            // knobs above, the two render IDENTICALLY today, so this is a choice about the next
            // edit rather than about this frame. Two reasons it is the right one:
            //   · These are not mood dimensions. `moodSnapshot` captures exactly eight fields and
            //     no `MoodPreset` writes either rhythm (`bassRhythmRow` says so itself) — putting
            //     them in the same container as the eight would imply a symmetry the model does
            //     not have.
            //   · A ninth mood dimension is a plausible edit — this panel has gained characters
            //     before, and `moodSnapshot` right below is the whole cost of adding one. In ONE
            //     grid the ninth would land beside `bassRhythmRow`: an `EchoelValueField` (label
            //     and value on one line) paired with a `labeledRow` (label ABOVE its Picker, so
            //     materially taller), and a `LazyVGrid` row takes its tallest cell. Split, the
            //     worst case is a half-width cell with an empty one beside it, which is already
            //     how "Sub / Bass (felt)" has shipped since Slice 2.
            //     ⚠️ The Tone grid in `soundPanel` mixes exactly those two kinds in ONE grid and
            //     its own ⛔ says "there was never a technical reason" — that is not a
            //     contradiction, it is the same fact from the safe side: Tone holds SIX items, so
            //     its rows pair knob/knob, knob/knob, picker/picker and no mixed row ever occurs.
            //     The next `knob(` added to Tone breaks that, and the split here is what makes
            //     the property permanent instead of arithmetic.
            AdaptiveCardGrid(spacing: 14) {
                bassRhythmRow
                padRhythmRow
                padShapeSection
            }
            // #359 (Founder 2026-08-01, "Weather könnte auch eine Rubrik in mood … sein oder?").
            // Weather is not a naming gimmick and never was: it blends darkness/liveliness/
            // tension into the composer's mood. It therefore belongs among the mood knobs it
            // modulates, not behind a chip about session names. The caption stays LAST — the
            // house rule that headers and captions sit outside the reflow grid.
            #if canImport(WeatherKit) && canImport(CoreLocation)
            weatherRow
            #endif
            // ⭐ #354 — THE CAPTION NAMES THE TWO THAT ARE SWITCHES, because the panel cannot
            // show it any other way. Six of these eight dials are read as gradients by the
            // composer; `Darkness` and `Romance` are read ONCE each, as `> 0.6` (drop the
            // voicing an octave) and `> 0.5` (add the 7th). A user moving Darkness from 0.20 to
            // 0.59 hears nothing and has no way to know why — the library's own preset comment
            // says two moods can differ by 0.43 of darkness and produce the same notes. Saying
            // it costs one clause; the alternative was leaving a control that reads continuous
            // and is not. `MoodKnobsSayWhatTheyDoTests` measures both cliffs and fails if either
            // moves, so this sentence cannot go stale silently.
            Text("Friendly ↔ scary (tension) · sparse ↔ busy (liveliness) · odd leaps (weird). Blends with your live signal. Darkness and Romance switch rather than fade: above 0.60 Darkness drops the voicing an octave, and above 0.50 Romance adds the 7th to genres whose chord does not already have one (7 of the 16 offered).")
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
    /// ⭐ #581 — THE SECTION THE FOUNDER NAMED, and the one `RoleRhythm`'s own docs have been
    /// specifying under the label "A7" for weeks: *"Ich find es fehlt eine Sektion mit slidern
    /// der aus den Pad Sounds rhythmische chords macht … Fehlt noch."* (2026-08-13)
    ///
    /// Nothing here is new machinery. `RoleRhythm.Params` has carried `gate`/`accent`/`evolve`
    /// with measured semantics all along, and `BioComposer.roleRhythmOnsets` hard-coded exactly
    /// these three numbers under a comment reading *"The three dials no role UI exposes"*.
    ///
    /// ⚠️ THREE HONESTY GATES, AND EACH ONE IS WRITTEN DOWN IN `RoleRhythm` RATHER THAN INVENTED
    /// HERE — that file already paid for the version of this UI that guessed:
    ///
    ///  1. **Everything disables on "Genre".** With `padRhythm == ""` the composer never calls
    ///     `roleRhythmOnsets` at all, so all three would sweep their range in silence — the
    ///     lying-control defect (#135/#164/#227).
    ///  2. **Variation reads `Character.usesEvolve`, not a hard-coded list.** `evolve` moves only
    ///     `dynamic` and `flowing`; on the other four it does nothing, `hypnotic` included (its
    ///     bar-to-bar rotation is a pure function of the bar index and consults neither the dial
    ///     nor the seed). ⛔ The FIRST version of this UI hard-coded that list in the view and got
    ///     it wrong — `RoleRhythm`'s doc says so at the flag itself.
    ///  3. **Accent reads `Character.accentIsSubtle`.** The spread at accent 1.0 runs from ≈5.8 dB
    ///     (`dynamic`) to ≈0.5 dB (`flowing`), a 2.6× gap that splits the six cleanly. The same
    ///     earlier attempt hard-coded `hypnotic || flowing` and left out `sparse`, which spreads
    ///     MORE than `hypnotic` — so on Sparse the row swept its whole range with nothing audible
    ///     and nothing on screen explaining why.
    ///
    /// ⚠️ AND ONE CROSS-DIAL INTERACTION THAT ONLY A UI OFFERING BOTH CAN MISLEAD ABOUT: on
    /// `dynamic`, `evolve` is a jitter ADDED TO the accent contour, so `accent == 0` annihilates
    /// it — the bar is bit-identical at Variation 0 and 1. `flowing` is unaffected (its evolve
    /// flips which cells sound, upstream of that multiply). `RoleRhythm.Params.accent`'s doc ends
    /// with "A UI offering both dials must say so", so the caption says so.
    ///
    /// `EchoelValueField`, not `Slider` — these are NUMERIC parameters, which is exactly the half
    /// of the one-control law that applies (the character above stays a `Picker` because its
    /// values have NAMES).
    private var padShapeSection: some View {
        let character = RoleRhythm.Character(rawValue: padRhythmRaw)
        let off = character == nil
        return VStack(alignment: .leading, spacing: 8) {
            EchoelValueField(label: "Chord length", value: $padGate,
                             range: 0.05...1, decimals: 2)
                .disabled(off)
            EchoelValueField(label: "Accent", value: $padAccent, range: 0...1, decimals: 2)
                .disabled(off)
            EchoelValueField(label: "Variation", value: $padEvolve, range: 0...1, decimals: 2)
                .disabled(off || !(character?.usesEvolve ?? false))
            Text(padShapeCaption(character))
                // ⛔ #584 — WAS `.font(.caption2)`, and that made this the ONE line of the phone
                // app rendered in the system face instead of Atkinson Hyperlegible. Not a rule
                // violation anyone would have caught: `.caption2` scales with Dynamic Type, which
                // is the property the accessibility guards check, and it looks fine in isolation.
                // It is only wrong NEXT TO the three rows above it. `EchoelTheme.font` is
                // `.custom(…, relativeTo: .body)`, so this keeps the scaling and takes the face.
                .font(EchoelTheme.font(11))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: padGate) { _, _ in recomposeIfRunning() }
        .onChange(of: padAccent) { _, _ in recomposeIfRunning() }
        .onChange(of: padEvolve) { _, _ in recomposeIfRunning() }
    }

    /// The caption is the honesty half of `padShapeSection`: a disabled row that does not say WHY
    /// is only marginally better than an enabled one that does nothing.
    private func padShapeCaption(_ character: RoleRhythm.Character?) -> String {
        guard let character else {
            return "Pick a pad rhythm above to shape the chord. On Genre the style writes its own "
                + "articulation and these three do not run."
        }
        var parts = ["Chord length is scaled by the rhythm — short shapes stay short at 1.00."]
        if character.accentIsSubtle {
            parts.append("This rhythm accents gently by design, so Accent moves less than on "
                         + "Driving or Dynamic.")
        }
        if character.usesEvolve {
            if !character.accentIsSubtle {
                // Only `dynamic` reaches both branches, and it is the one with the interaction.
                parts.append("Variation rides the accent here, so at Accent 0.00 it does nothing.")
            }
        } else {
            parts.append("Variation is off for this rhythm — its bar-to-bar change is part of its "
                         + "character, not a dial.")
        }
        return parts.joined(separator: " ")
    }

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
    ///
    /// ⭐ #354 — `decimals: 2`, WHICH IS THE APP'S OWN IDIOM AND WAS THE LARGEST ROW SET NOT USING IT.
    /// `EchoelValueField.decimals` defaults to 4, and these eight rows shipped reading `0.5000`
    /// while every FX parameter, the master volume and the weather mixers read `0.50`
    /// (`EchoelValueField`'s own scrub-precision doc names that set as "`0…1, decimals: 2`" —
    /// these rows were silently outside it). Two decimals is also all these controls can mean:
    /// `darkness` and `romance` are read by the composer as SWITCHES (see the caption below), and
    /// the other six feed arithmetic where the third decimal is far under what an ear can separate.
    ///
    /// ⛔ THE FIRST VERSION OF THIS BLOCK SAID "the ONLY `0…1` fields in the app that never passed
    /// a value", IN THREE PLACES AT ONCE. False: `Energy` and `Hue` in the visual panel took the
    /// default 4 as well. They are image controls rather than composer parameters, so they were
    /// not swept in with this slice — but "only" was a superlative nobody had counted, in the doc
    /// block whose whole subject is a count. Registered as its own decision rather than quietly
    /// widened here, and that decision SHIPPED as #427: the six visual rows of that day (Energy ·
    /// Intensity · Motion · Spread · Hue · Saturation) pass `decimals: 2` — Texture and
    /// Glitter (#853) and Structure (#853B) do too — guarded by
    /// `Tests/CISmoke/VisualPresetValuesAreReachableTests`. Ten `EchoelValueField` call sites in
    /// `Sources/` still take the default — and two of them want it (A4 concert pitch and the
    /// locked tempo both say "editable to 0.0001" in their own comments), so this is deliberately
    /// NOT an app-wide rule. Count before writing "only" or "every".
    ///
    /// ⚠️ `decimals` is not only a DISPLAY setting: `EchoelValueField.apply(_:)` snaps the stored
    /// value to the same `10^-decimals` grid, so these eight now persist on 0.01 and a preset's
    /// gradient dial lands on the grid instead of its authored figure. Two consequences, both
    /// checked before shipping: every value in the shipped mood library is already ≤2 decimals, so
    /// nothing on disk changes; and `onCommit` (the recompose) now fires only when a drag actually
    /// crosses a 0.01 boundary, which is the same behaviour every other `0…1` row in the app has.
    ///
    /// ⚠️ WHAT THIS DOES **NOT** FIX, so nobody reads a display change as an engine change: the
    /// two threshold dimensions are still thresholds. The audit that raised this (#354) offered
    /// two ways out — render the control as what it is, or make the composer read it
    /// continuously — and this is the first half of the first one. `romance` is the one of the
    /// two that CAN be made continuous (share of chords carrying the 7th), and that is its own
    /// slice because it changes shipped sound.
    ///
    /// ⚠️ AND ROMANCE IS WEAKER STILL THAN "a switch": its one read is `if mood.romance > 0.5,
    /// !tones.contains(6)`, so on a genre whose chord ALREADY carries the 7th it does nothing at
    /// any setting. That is 9 of the 16 offered genres — `.selfObservation`, THE SHIPPED DEFAULT,
    /// among them. The caption therefore says "to genres whose chord does not already have one
    /// (7 of the 16 offered)" rather than promising the 7th outright; an unqualified promise would
    /// have been false for the genre a first-time user hears. `MoodKnobsSayWhatTheyDoTests` pins
    /// the 7/16 split against `harmonicProfile` itself, so the number in the caption cannot rot.
    ///
    /// `darkness` cannot be made continuous: it moves the register, and
    /// register is quantised by construction (`key.degree(_:octave:)` moves in octaves, and
    /// `VoiceLeader.resolve` re-octaves the voicing anyway), so a "gradient" there would be
    /// invented rather than measured.
    ///
    /// ⚠️ It does not change the DRAG either — `ScrubPrecision.advanced` holds an un-snapped
    /// running target since #376, so the grid stopped gating travel then. What moves is what the
    /// number pad accepts and what the row reads.
    ///
    /// ⛔ THAT SENTENCE IS TRUE FOR THESE ROWS AND WAS NOT TRUE IN GENERAL (#427 review). The
    /// un-snapped target is only carried while it still names the value on screen, and until
    /// #427 that test was raw equality — which holds for a STORED binding like this one and
    /// fails for a DERIVED one, whose getter recomputes. `visualEnergy` is derived, so
    /// coarsening its grid to 2 put it straight back in the pre-#376 dead zone. Fixed in
    /// `ScrubPrecision.carriesTarget`; read that before quoting this paragraph at another row.
    /// #614 Auto-Scheibe 4a — the "user gesture wins" wiring. `pausing` names the
    /// `AutoAttune.State` flag a committed edit on this dial sets: while Auto mode is
    /// ON, dialling a steered parameter yourself pauses ITS steering for the rest of
    /// the session (the door's literal promise, "Your own edits keep priority").
    /// Only the three steered dials pass it — a `pausing:` on an unsteered dial would
    /// register a pause nothing reads, the #135-class lying wiring.
    ///
    /// Three deliberate boundaries, decided here rather than left to drift:
    ///  · The write is gated on `autoMode`: an edit while Auto is OFF must not leave a
    ///    stale pause behind that silently exempts the dial when Auto is later invited.
    ///  · `onCommit` (not `onChange`) is the signal, and `EchoelValueField` fires it
    ///    only when the value actually MOVED — a no-op drag or confirming the same
    ///    number pauses nothing (#375's "confirming what is there is not an edit").
    ///  · The pause is written BEFORE `recomposeIfRunning()`, so the debounced
    ///    regenerate this very gesture schedules already reads the paused registry —
    ///    the first take after the edit is the un-steered one.
    /// A preset load (`applyMood`) deliberately does NOT pause: it rebases all eight
    /// dials, the steer is a capped offset on TOP of the new base and never overwrites
    /// it — ending Auto for the session on a routine library action would be the
    /// surprise, not the priority. Un-pausing has exactly one sanctioned gesture: the
    /// Auto toggle itself (see `.onChange(of: autoMode)` on the body).
    private func moodKnob(_ label: String, _ value: Binding<Float>,
                          pausing pause: WritableKeyPath<AutoAttune.State, Bool>? = nil) -> some View {
        EchoelValueField(label: label, value: value, range: 0...1, decimals: 2,
                         onCommit: {
                             if let pause, autoMode, !autoAttuneState[keyPath: pause] {
                                 autoAttuneState[keyPath: pause] = true
                                 log.log(.info, category: .automation,
                                         "Auto attune: \(label) paused for this session (user edit)")
                             }
                             recomposeIfRunning()
                         })
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
            // #621 (Ultraaccessible-Audit, bar point 3): mirror of the sound-preset value
            // one panel over — the label replaces `Text(moodPresetName)`, so without this
            // the active mood is visible but unhearable.
            .accessibilityValue((moodPresetID.map { moodStore.isFavorite(id: $0) } ?? false)
                ? "\(moodPresetName), favorite" : moodPresetName)

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
                            // Snapshot BEFORE the delete — `moodStore.delete` removes the
                            // preset from `moods`, so reading it afterwards finds nothing.
                            if let doomed = moodStore.moods.first(where: { $0.id == id }) {
                                deletedMood = (doomed, moodStore.isFavorite(id: id))
                            }
                            moodStore.delete(id: id)
                            moodPresetID = nil
                            moodPresetName = "Custom"
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                if let d = deletedMood {
                    Button {
                        moodStore.save(d.mood)
                        if d.wasFavorite, !moodStore.isFavorite(id: d.mood.id) {
                            moodStore.toggleFavorite(id: d.mood.id)
                        }
                        moodPresetID = d.mood.id
                        moodPresetName = d.mood.name
                        deletedMood = nil
                    } label: {
                        Label("Undo delete of \(d.mood.name)", systemImage: "arrow.uturn.backward")
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
            // #358 — 34×34 is 60 % of the HIG 44×44 floor by area, and this is the ONLY door to
            // save / favorite / delete / submit a mood. The house answer is to grow the HIT AREA,
            // not the picture (`contentShape` changes no layout), so the chip still reads as a
            // peer of the 34-high preset menu beside it.
            //
            // ⛔ ON THE `Menu`, NOT INSIDE `label:` — THE FIRST VERSION HAD IT ONE LEVEL DEEPER
            // AND WAS ALMOST CERTAINLY A NO-OP. Both in-repo precedents for this idiom close the
            // label first: `WorkspaceView`'s "•••" (#113) and `BodyTempoField`'s lock. The Menu
            // installs its press interaction over its OWN bounds, which `contentShape` cannot
            // change from a descendant — and the guard could not see the difference, because it
            // scanned a window rather than the position. Placement is now pinned.
            //
            // CLEARANCE, measured, because −6 is only safe against a known gap: leading ≥16 pt
            // (`HStack(spacing: 8)` puts 8 pt on EACH side of the `Spacer`), above 12 pt
            // (`EchoelPanel`'s content `.padding(.top, 12)`), below 14 pt (that stack's row
            // spacing). Trailing is the panel edge.
            .contentShape(Rectangle().inset(by: -6))
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
        // #620 (GUI-Board Zeile 10 / UX#13): the subtitle NAMES "Voice timbre". ⛔ #620b
        // (review W2): the first version of this comment said the name reaches "a player
        // scanning the collapsed chips" — WRONG MECHANISM: this panel mounts only through
        // `dropdownContent` under `echoelPanelForceOpen`, so there IS no collapsed state.
        // The honest gain is one level, not two: the subtitle is the FIRST line of the
        // opened panel, so the feature is named at the top instead of being visible only
        // at the row itself, further down. The words are the ROW's words
        // (`VoiceCaptureRow`'s `Text("Voice timbre")`, #616's vocabulary law: the pointer
        // and the control share one spelling, or the pointer teaches a search that
        // fails). Rename the row → rename this token in the same commit; the guard
        // (`ThePanelSubtitlesNameTheirDeepFeaturesTests`) couples both sites.
        panel("Sound & texture", "Shape the timbre — exact to 0.0001 · Voice timbre",
              isExpanded: $showSound) {
            // #325 — THE TUNING BANNER'S DOOR, and Sound is chosen over the panel the tuning
            // controls live in on purpose. `displayedMenu` falls back to `.sound`, so this is
            // what an untouched launch shows: a player who opens a detuned instrument is told
            // before they play a note. The controls themselves are in the header strip, which
            // is exactly the eyeline the founder's 500 Hz session never crossed.
            //
            // It renders nothing at 12-TET + 440, so on the normal path this adds no row, no
            // spacing and no chrome to the default panel — the cost is paid only by the state
            // it exists to report.
            //
            // METADATA: this is a child of an existing panel builder, NOT a fifth child of the
            // root `VStack` and NOT a presentation modifier. The black-screen law counts the
            // root body's aggregate generic type and the `.sheet` chain; both are untouched.
            nonStandardTuningBanner
            presetRow
            promptRow
            randomizeButton
            // EchoelVoice #592b — the capture door. A child of the existing panel
            // builder: no presentation modifier, no metadata cost (black-screen law
            // untouched). The row is a LEAF because its progress moves ~12 Hz mid-take.
            VoiceCaptureRow(controller: voiceCapture, patch: $currentPatch) {
                // #593c review F3 — the THIRD copy: the prompt/randomize undo snapshot
                // is taken WITH the voice half, so Clear → Undo-arrow would restore
                // the profile Clear just removed. Strip the snapshot's voice half;
                // its SOUND stays undoable.
                patchBeforeSoundChange?.voiceProfileTaps = nil
                patchBeforeSoundChange?.voiceProfileLabel = nil
                patchBeforeSoundChange?.voiceProfileBlend = nil
            }

            // #560 — the OTHER reason a number on this panel moves by itself, and the one that
            // is live on every install: the body. `applyBioReactive` recomputes brightness,
            // harmonics, noise, cutoff and vibrato per render block from their `bioBase*`
            // ANCHORS, so the rows below are what the body moves AROUND, not final values.
            // That is the #556 law in the player's language, said once, where the numbers are.
            //
            // ⛔ A PLAIN `Text` UNTIL #640, AND THE REASON GIVEN HERE WAS SOUND WHILE IT LASTED:
            // the sentence came from `AlwaysOnBioChannel`'s static mapping — a property of the
            // ENGINE, not of any frame — so nothing here read bio and this body observed
            // nothing new (10.76.41/50). What changed is the sentence, not the law: it names a
            // SUBJECT ("Your body"), and that subject is wrong while the demo generator drives.
            // Naming it correctly needs one bio read, and `dropdownContent` is evaluated by
            // `EchoelStudioView.body`, which hosts every `.menu` Picker — so the read went into
            // its own `View` struct instead of into a condition here. `BodyShapesThisSoundLine`
            // carries the whole argument; the ONE thing not to do is inline it back.
            // The LIVE half — the four channels with their current values and whether they are
            // still arriving — is still the Bio panel's strip, which the sentence points at
            // rather than duplicating (#416).
            BodyShapesThisSoundLine()

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
                knob("Brightness", $currentPatch.brightness, SynthPatch.Bounds.brightness, decimals: 2)
                knob("Harmonics", $currentPatch.harmonicity, SynthPatch.Bounds.harmonicity, decimals: 2)
                knob("Harm. level", $currentPatch.harmonicLevel, SynthPatch.Bounds.harmonicLevel, decimals: 2)
                knob("Noise", $currentPatch.noiseLevel, SynthPatch.Bounds.noiseLevel, decimals: 3)
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
                knob("Cutoff", $currentPatch.filterCutoff, SynthPatch.Bounds.filterCutoff, unit: "Hz", decimals: 0)
                knob("Resonance", $currentPatch.filterResonance, SynthPatch.Bounds.filterResonance, decimals: 2)
                knob("LFO→filter", $currentPatch.lfoToFilterDepth, SynthPatch.Bounds.lfoToFilterDepth, decimals: 2)
                knob("LFO rate", $currentPatch.filterLFORate, SynthPatch.Bounds.filterLFORate, unit: "Hz", decimals: 2)
                knob("LFO depth", $currentPatch.filterLFODepth, SynthPatch.Bounds.filterLFODepth, decimals: 2)
            }

            groupHeader("Envelope")
            // Global articulation macro — one control that shapes the ONSET for EVERY
            // character. Not named after an instrument: the same struck onset is a
            // glass bowl, a mallet, a plucked string or a tuba stab depending on the
            // chosen timbre. Writes A/D/S/R below (which stay editable for fine-tuning).
            EchoelValueField(label: "Swell ↔ Strike", value: Binding(
                get: { Float(articulation) },
                set: { articulation = Double(min(1, max(0, $0))) }
            ), range: Float(0)...Float(1), decimals: 2, onChange: { applyArticulation() })
            Text("How each character speaks: 0 = slow swell (bowed strings, glass bowl) · 1 = struck / sharp onset (mallet, plucked, tuba stab). Sets touch response too; click-safe.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            // The Swell↔Strike macro and its explanation stay full-width ABOVE the grid: it
            // WRITES the four fields below it, so pairing it beside one of them would read as
            // a peer of A/D/S/R instead of the control that sets them.
            AdaptiveCardGrid(spacing: 14) {
                param("Attack", $currentPatch.attack, SynthPatch.Bounds.attack, unit: "s", decimals: 3)
                // The 0…10 here (not 0…5) is `SynthPatch.Bounds.decay` since #441, so the number
                // this note explains no longer lives on this line — it is stated once, next to
                // the constant. Kept because the REASON belongs where a session edits the row:
                // `Drone Bed` ships a 6.0 s decay (`GenrePatches.swift:145`) and the field CLAMPS
                // before it rounds, so on the old range one touch rewrote it as 5.0 s — a fifth
                // of the row's span, on a value a designer typed. Widen, never round (#430/#424).
                param("Decay", $currentPatch.decay, SynthPatch.Bounds.decay, unit: "s", decimals: 2)
                param("Sustain", $currentPatch.sustain, SynthPatch.Bounds.sustain, decimals: 2)
                param("Release", $currentPatch.release, SynthPatch.Bounds.release, unit: "s", decimals: 2)
            }

            groupHeader("Space & vibrato")
            AdaptiveCardGrid(spacing: 14) {
                knob("Reverb mix", $currentPatch.reverbMix, SynthPatch.Bounds.reverbMix, decimals: 2)
                knob("Reverb decay", $currentPatch.reverbDecay, SynthPatch.Bounds.reverbDecay, unit: "s", decimals: 2)
                knob("Vibrato rate", $currentPatch.vibratoRate, SynthPatch.Bounds.vibratoRate, unit: "Hz", decimals: 2)
                knob("Vibrato depth", $currentPatch.vibratoDepth, SynthPatch.Bounds.vibratoDepth, decimals: 2)
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
                ), range: Float(0)...Float(1), decimals: 2)
                // Sub character (founder "sub culture" 2026-07-16, in-house SubCharacter
                // DSP): presence = octave-harmonic read on small speakers; heat =
                // loudness-compensated saturation. 0.50/0.50 = the previous fixed sound.
                EchoelValueField(label: "Sub presence", value: Binding(
                    get: { subBass.subPresence },
                    set: { subBass.subPresence = min(max($0, 0), 1) }
                ), range: Float(0)...Float(1), decimals: 2)
                EchoelValueField(label: "Sub heat", value: Binding(
                    get: { subBass.subHeat },
                    set: { subBass.subHeat = min(max($0, 0), 1) }
                ), range: Float(0)...Float(1), decimals: 2)
            }
            Text("Reinforces the bass an octave below — feel it on a sub, in headphones, or as haptics. Presence makes it read on small speakers (octaves only, always in key); heat saturates without getting louder.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)

            // #559 — the automation readout, hosted HERE because this is the panel whose
            // numbers it explains: of the parameters an automation lane can reach today, ten
            // of thirteen are the synth values on the rows above. A player who sees one of
            // them move without touching it asks the question in this panel, so the answer
            // belongs in it.
            //
            // METADATA: a child of an existing panel builder, NOT a presentation modifier and
            // NOT a fifth child of the root `VStack` — the black-screen law counts the root
            // body's aggregate generic type and the `.sheet` chain, and both are untouched
            // (10.76.34). It reads `AutomationPlayer` in its OWN body, never here: this
            // builder is evaluated by the menu-hosting root body (10.76.41/50).
            //
            // The heading is spelled HERE and not in the strip: `groupHeader` is the one
            // section-heading builder (#362) and it is `private` to this view, so a strip in
            // its own file could only re-spell it — a fourth treatment in a file no per-panel
            // review would compare against the other three.
            groupHeader("Automation")
            AutomationStatusStrip()
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
    ///
    /// ⛔ SINCE #375 THAT SENTENCE IS CONDITIONAL: `apply` skips the write when the number does
    /// not move, so an edit landing on the DISPLAYED value no longer materialises the field. It
    /// matters here and only here, because this is the one asymmetric binding in the file — the
    /// getter clamps to `maxUnison` and the setter does not. On the two patches that persist
    /// `uni: 4` against a max of 3, dragging to 3 used to canonicalise storage to 3; now the 4
    /// stays on disk, and if `maxUnison` is ever raised those patches jump to four voices
    /// without the user asking. Not worth a special case today (nothing else re-reads the
    /// stored value), but it must not be found by surprise later.
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
    ///
    /// ⭐ `decimals` HAS NO DEFAULT ON PURPOSE (#430). It is not a display choice — it is the
    /// SNAP GRID (`ScrubPrecision.snapped` rounds every commit to `10^-decimals`), so a value
    /// off the grid cannot be typed and cannot be scrubbed to. These two helpers rendered
    /// SEVENTEEN rows of the Sound panel on `EchoelValueField`'s own `decimals: 4` default,
    /// which meant the app's most-used craft surface showed "0.5000" and "2400.0000 Hz" while
    /// every FX parameter, the master level and the weather mixers sat on 2. A defaulted
    /// argument is how that stayed invisible for a month: it was never written at any call
    /// site, so no diff ever showed it. Requiring it makes each row state its own grid — the
    /// #431 rule (a call is only meaningful together with the argument that gives it meaning),
    /// applied one level up.
    private func param(_ label: String, _ value: Binding<Float>,
                       _ range: ClosedRange<Float>, unit: String = "",
                       decimals: Int) -> some View {
        EchoelValueField(label: label, value: value, range: range, unit: unit,
                         decimals: decimals, onChange: { applySoundLive() })
    }

    /// Alias kept for call-site readability; same scrubbable numeric value as `param`.
    /// `decimals` is required here for the same reason — see `param`.
    private func knob(_ label: String, _ value: Binding<Float>,
                      _ range: ClosedRange<Float>, unit: String = "",
                      decimals: Int) -> some View {
        EchoelValueField(label: label, value: value, range: range, unit: unit,
                         decimals: decimals, onChange: { applySoundLive() })
    }

    /// THE section heading — the only one. Every "a group of rows starts here" label in this
    /// view goes through here, whichever panel it is in.
    ///
    /// ⛔ IT WAS THREE TREATMENTS, ONE PER PANEL FAMILY (#362), and the incoherence was
    /// invisible to every per-file review because each panel was internally consistent. The
    /// Sound panel used this helper (11 pt semibold, dim); the Visual, Bio and Field panels
    /// spelled `font(10, .medium)` + `dim` inline; the Session panel's weather groups spelled
    /// `font(12, .semibold)` + `dim`. Three sizes and three weights for one job, reachable in
    /// three taps of the same chip strip.
    ///
    /// WHY 11 pt SEMIBOLD WON, rather than averaging: it was already the most-used (seven
    /// call sites in `soundPanel` against five and two), and — the deciding half — `.semibold`
    /// is one of the four weights `EchoelTheme.font` actually maps to the Bold face. `.medium`
    /// is NOT: the app ships Regular, Bold and Italic only, so `font(10, .medium)` rendered as
    /// 10 pt REGULAR (#361). The Field panel's own comment below already recorded the symptom —
    /// a heading that "read as a second panel title rather than a peer" — without naming the
    /// cause. Picking the treatment that renders what it says removes a class of bug, not just
    /// a difference.
    ///
    /// ⚠️ NOT A ROW LABEL. `Text("Motion")`/`"Rhythm"`/`"Grid"` sit in an `HStack` beside a
    /// `Picker` and are LABELS; the `maxWidth: .infinity` here would push their picker off the
    /// row. My own first pass at #362 counted them among the "five heading treatments" — they
    /// are a separate question (they read 12 pt against `EchoelValueField`'s 14 pt label two
    /// rows up), and mixing the two would have produced a visibly broken panel.
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
                        patchBeforeSoundChange = nil   // wholesale replace — property doc
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
                // #621 (Ultraaccessible-Audit, bar point 3): the label above REPLACES the
                // visible `Text(currentPatch.name)` for VoiceOver, so the active sound's
                // name was unhearable on the ship-gate-2 surface. Label + value is the
                // house pattern (the bio-source Menu and the look row do exactly this).
                .accessibilityValue(patchStore.isFavorite(id: currentPatch.id)
                    ? "\(currentPatch.name), favorite" : currentPatch.name)

                Menu {
                    Button { patchSaveName = currentPatch.name + " copy"; showSavePatchAs = true } label: {
                        Label("Save as new sound…", systemImage: "plus")
                    }
                    let isFav = patchStore.isFavorite(id: currentPatch.id)
                    Button { patchStore.toggleFavorite(id: currentPatch.id) } label: {
                        Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
                    }
                    if !patchStore.isFactory(currentPatch) {
                        Button {
                            // #593c — the SAME one definition as "Save as…": the live
                            // voice half travels (or, post-Clear, is stripped) on this
                            // door too. The view copy is updated first so the store and
                            // the open editor never disagree about the half (check 4).
                            currentPatch = patchCarryingLiveVoice(currentPatch)
                            patchStore.save(currentPatch)
                        } label: {
                            Label("Save changes", systemImage: "square.and.arrow.down")
                        }
                        Button(role: .destructive) {
                            // Snapshot BEFORE the delete. `currentPatch` is the live copy and
                            // survives the store call, but it is overwritten two lines below —
                            // so the capture has to happen here, not after.
                            deletedPatch = (currentPatch, patchStore.isFavorite(id: currentPatch.id))
                            patchStore.delete(id: currentPatch.id)
                            presetIndex = -1
                            currentPatch = style.synthPatch
                            patchBeforeSoundChange = nil   // wholesale replace — property doc
                            applyArticulation()
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                    if let d = deletedPatch {
                        Button {
                            patchStore.save(d.patch)
                            if d.wasFavorite, !patchStore.isFavorite(id: d.patch.id) {
                                patchStore.toggleFavorite(id: d.patch.id)
                            }
                            // The delete replaced the LIVE sound with the genre's patch, so the
                            // undo has to put the sound back too, not just the library row.
                            // `presetIndex` stays -1: a restored user patch is "custom", which
                            // is what the delete already set it to.
                            currentPatch = d.patch
                            patchBeforeSoundChange = nil   // wholesale replace — property doc
                            applyArticulation()
                            deletedPatch = nil
                        } label: {
                            Label("Undo delete of \(d.patch.name)", systemImage: "arrow.uturn.backward")
                        }
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
                // #358 — same shortfall and same fix as the Mood overflow, and on the `Menu` for
                // the same reason (see there). This is the only door to save / favorite / delete
                // / submit a sound.
                //
                // ⛔ THE GAP HERE IS TIGHTER AND IT DECIDES WHO MAY BE OUTSET. The preset Menu
                // beside it carries `maxWidth: .infinity`, so the two chips are exactly
                // `HStack(spacing: 8)` apart — no `Spacer` widening it as in the Mood row. −6
                // leaves 2 pt. Giving the PRESET menu the same outset would make the two hit
                // areas overlap by 4 pt, and the overlapping half is the destructive one. Only
                // the ellipsis is outset, deliberately. Vertically: 4 pt to the "Character" label
                // above (a `Text`, not hit-testable) and 14 pt to `promptRow` below.
                .contentShape(Rectangle().inset(by: -6))
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
        SoundPromptRow(canUndo: patchBeforeSoundChange != nil,
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
    /// 3. The `patchBeforeSoundChange` snapshot is taken per APPLICATION, so Undo is exactly one
    ///    step. Deliberately not a stack: a deeper history would have to be invalidated by the
    ///    seven other places that assign `currentPatch` wholesale, and an undo that silently
    ///    points at a patch from before a preset load is worse than no undo.
    ///    ⚠️ AND THIS PATH IS NO LONGER THE SNAPSHOT'S ONLY WRITER — `randomizeButton` takes one
    ///    too, into the same single slot. A randomize after a shaping therefore replaces this
    ///    undo point instead of stacking on it, which is what "one step" has to mean once two
    ///    controls in one panel share it.
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
        patchBeforeSoundChange = previous
        applySoundLive()
    }

    /// One step back. Cheap insurance rather than a feature: without it the only ways out of an
    /// over-shaped sound are Randomize and re-picking a character, neither of which reads as
    /// "give me my sound back".
    private func undoSoundPrompt() {
        guard let previous = patchBeforeSoundChange else { return }
        currentPatch = previous
        patchBeforeSoundChange = nil
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
        patchBeforeSoundChange = nil    // wholesale replace — see the property's doc
        presetIndex = SynthPatch.factory.firstIndex { $0.id == p.id } ?? -1
        patchStore.markUsed(id: p.id)
        applyArticulation()   // character = timbre; the global macro owns the envelope
    }

    /// ⭐ IT TAKES A SNAPSHOT NOW, and that is the whole slice. This button threw the live timbre
    /// away outright — no prompt, no dialog, nothing to get it back from — while the row DIRECTLY
    /// ABOVE it kept exactly one undo step for the identical kind of write. A hand-dialled sound
    /// was one accidental tap from gone, and the Undo arrow sat right there looking like it
    /// covered this too. Reversible beats confirmed, same as the project-open rescue: a
    /// `.confirmationDialog` could only ever warn, while writing the snapshot costs one
    /// assignment and makes the tap undoable.
    ///
    /// ⛔ AND THE SHIPPED VERSION PROPPED THAT UP WITH A LAW THAT DOES NOT REACH THIS BUTTON —
    /// "would grow the presentation chain the black-screen law forbids growing". The chain that
    /// law governs is `EchoelStudioView.body`'s own, the counted 14 (CLAUDE.md); this button
    /// lives in `soundPanel`, which reaches the body only through `dropdownContent: AnyView` and
    /// is type-erased before the body's aggregate type exists. A dialog here would have left the
    /// count at 14. Only the other half carries the decision, and it carries it alone: a prompt
    /// warns, an assignment gives the sound back.
    ///
    /// ⚠️ ONE SLOT, SHARED WITH THE PROMPT — so a randomize after a shaping replaces that
    /// shaping's undo point rather than stacking on it. Correct for a one-step history.
    ///
    /// ⚠️ HONEST LIMIT — THE SECOND TAP IS THE ONE THAT COSTS. One slot means Randomize →
    /// Randomize overwrites the snapshot with the FIRST random patch, so the hand-dialled sound
    /// this fix exists to protect is unrecoverable from the second tap on — on a control whose
    /// whole point is to be tapped repeatedly until something sounds right. Not an oversight and
    /// not free: making it survive needs a stack rather than a slot, and how deep a stack and
    /// whether the prompt shares it is a separate decision. As shipped, the arrow protects the
    /// FIRST tap after a hand-dialled sound. Say that out loud rather than letting the arrow
    /// imply more.
    ///
    /// ⛔ AND THE FIRST VERSION OF THIS COMMENT ENDED "the arrow always means 'the sound I had
    /// immediately before the last thing I did here'", WHICH WAS FALSE WHEN WRITTEN. Three more
    /// controls in this same panel replace `currentPatch` wholesale — "Genre default", picking a
    /// preset from the Character menu, and the Delete that falls back to the genre patch — and
    /// none of them touched the snapshot. Randomize, then pick a preset, and the arrow was still
    /// lit: tapping it jumped back past the preset the user had just chosen. That is verbatim
    /// the "undo that silently points at a patch from before a preset load is worse than no
    /// undo" defect that `applySoundPrompt`'s own doc cites as the REASON for the one-step
    /// design. The sentence is true now because every wholesale replace clears the slot — see
    /// the property's doc for the list and the standing obligation on the next writer.
    private var randomizeButton: some View {
        Button {
            patchBeforeSoundChange = currentPatch
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
        // #620 (GUI-Board Zeile 10 / UX#12): the subtitle NAMES "Follow the key" — the
        // harmonizer's in-key toggle sits TWO levels deep (this panel → "All parameters"
        // sheet → Harmonizer section), and no surface above it named it. The words are
        // the TOGGLE's words (`EchoelFXView`'s `Toggle("Follow the key"`, #616's
        // vocabulary law). Rename the toggle → rename this token in the same commit; the
        // guard couples both sites. ⛔ #620b (review W3): the first version claimed
        // `TheFXDoorNamesAControlThatExistsTests` "scans only hint lines" — half wrong
        // (its slider check scans EVERY line of its window). The two reasons this line is
        // actually safe: that guard's `doorWindow` runs FORWARD from the `showAllFX`
        // button, ~68 lines below here, so this line never enters it — and the subtitle
        // contains neither "slider" nor an `effectSection("…")` stage title anyway.
        panel("Effects", "Production character · Follow the key", isExpanded: $showEffects) {
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
            // Full control: open every stage with all parameters exposed.
            //
            // ⛔ AND THE FIRST #480 PASS LEFT THIS VERY LINE FALSE WHILE REWRITING EVERYTHING
            // AROUND IT. It read "open every stage (filter, delay, chorus, flanger, phaser,
            // tremolo, compressor, limiter)" — EIGHT of the `effectSection(` calls in
            // `EchoelFXView`, out of fourteen AT THE TIME. Missing: Saturation · Tape / VHS ·
            // Bitcrush · Harmonizer · Reverb · Stereo Width.
            // ⛔ #693: that count said "the FOURTEEN" in the present tense until #692 added
            // Granular. The MISSING list is what carries the argument and it is still complete
            // for the hint being retracted; the denominator was decoration that had to be
            // re-counted forever. It is now dated instead of dropped, because a subset-of-eight
            // means nothing without knowing what it was eight OF. The live count is derived by
            // `TheFXDoorNamesAControlThatExistsTests.stageNames()` — ask it (#416). So the commit whose whole thesis is "somebody corrected the prose and
            // left the claim" corrected the prose and left THIS claim, three lines above the ⛔
            // that says so. Do not re-enumerate here: a list that names a subset under the word
            // "every" is the same defect in a new shape, and it needs re-counting every time a
            // stage is added. Say "every stage" and let the panel be the inventory.
            //
            // ⛔ THIS COMMENT WAS WRITTEN TO CORRECT THE HINT AT THE BOTTOM OF THIS BUTTON, AND
            // THE HINT WAS LEFT STANDING (#480). It said: NOT "as sliders" — numeric parameters
            // are `EchoelValueField`s, and a parameter whose values have NAMES is a picker
            // (filter mode, delay mode, and since 2026-07-29 the two harmony intervals). Every
            // word of that is true of what this button opens — measured, `Slider(` occurs 0
            // times in `Studio/EchoelFXView.swift` — and the VoiceOver hint below it went on
            // saying "every parameter as a slider". A claim standing next to its own refutation,
            // in the one layer a sighted reviewer never reads.
            //
            // ⛔ AND THE CORRECTION OVERSHOT: "the app has no raw `Slider`", unqualified. There
            // are TWO — the look scrub, here in `visualLookRow` and again in
            // `FloatingVisualWindow` — and both are deliberate. The UI law's own word is "for
            // parameters"; a continuous morph between NAMED looks is not a parameter row, and
            // `FloatingVisualWindow` says exactly that at its site ("a live VJ control over the
            // visual, not a Studio parameter row"). The SCOPED claim survives, the absolute one
            // does not, and `TheFXDoorNamesAControlThatExistsTests` pins both halves.
            //
            // ⚠️ HONEST SIZE — this is copy, not a broken affordance. `EchoelValueField` installs
            // an `accessibilityAdjustableAction`, so swipe-up/down behaves exactly as it would on
            // a `Slider`. What the wrong word hid is the affordance a slider does NOT have:
            // double-tap to type an exact number. Each field states that in its own hint, so this
            // door does not repeat it — one definition per fact (#416).
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
            // ⛔ The first #480 hint read "Open every effect stage — filter, delay, modulation and
            // dynamics, with every parameter exposed". It traded a false CONTROL-TYPE claim for a
            // false COMPLETENESS one: those four categories covered 8 of the 14 stages THEN
            // (#693 dated this — the chain has fifteen since #692; the count is not re-bumped
            // here because it describes a hint that no longer exists), and its
            // order was wrong too (`EchoelFXChain.processStereo` runs modulation BEFORE delay).
            // A sighted user can glance at the sheet; a VoiceOver user has only this sentence.
            // No enumeration here — `TheFXDoorNamesAControlThatExistsTests` derives the stage
            // names from `EchoelFXView` and goes red if any of them reappears in this string.
            .accessibilityHint("Opens every effect stage with all of its parameters")
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
    /// ⚠️ #695 — THIS RE-STAMP DOES NOT REFRESH THE FX PANEL'S MIRRORS, AND TODAY ONLY THE
    /// MODAL SAVES IT. `FXViewModel` mirrors all fifteen chain enables and resyncs solely
    /// through `reseed()`; `EchoelFXView.applyCharacter` calls it, this function does not. So a
    /// character stamped from HERE while a live `EchoelFXView` existed would leave up to
    /// fourteen switches reading ON over a chain that is off — the `applyDelaySync` failure
    /// shape one panel over, multiplied.
    ///
    /// ⭐ IT IS UNREACHABLE TODAY, and the reason is presentation, not design: the character
    /// `Picker` and the "All parameters" door are BOTH in `effectsPanel`, and the panel is
    /// covered by `.sheet(isPresented: $showAllFX)` — a modal cannot be reached past. Generate
    /// and `open(_:)` re-stamp too, and are behind the same modal. Dismissing destroys the
    /// sheet's `@State`, so the next presentation re-seeds from the chain.
    ///
    /// ⛔ THAT GUARANTEE IS ONE UI CHANGE THICK. It breaks the day the FX surface stops being
    /// modal, gains its own character control, or the panel becomes reachable behind it — and
    /// nothing would go red, because the mirrors are `@State` and no test can see a live one.
    /// #694 WIDENED the exposure from seven flags to fourteen (it made `.clean` write the seven
    /// the preset could not), which is why it is written down here rather than left as an
    /// unstated property of a sheet. The repair, on that day, is a call site — not new code.
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
            Text(label).font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
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
    /// The level stays baked into VELOCITY on purpose. `PianoRollModel` reads velocity as
    /// "is this note audible" (the two `audibleVelocityFloor` comparisons — the felt-sub
    /// decision and the `MusicalFrame` publish) and as the note-on amplitude itself, so
    /// moving the user term to trigger time
    /// would light the visual, the light output and the felt sub for notes nobody can
    /// hear. That is exactly #205, and re-deriving from `lastRawTake` avoids it without
    /// re-opening it.
    private func rebalanceTake() {
        // NO RAW TAKE = NO RE-BAKE, so fall back to the OLD behaviour rather than doing
        // nothing. `lastRawTake` is `@State`: nil until this app session's first
        // generate(). ⛔ The clause that followed — "and `open(_:)` restores an
        // already-baked take via `pianoRoll.load(p.notes)` without it" — has been false
        // since #217 gave `open(_:)` its own `lastRawTake = p.rebakeSource`, and #623 also
        // installs those bars there; a LEGACY take with no `rawTake` is what still lands
        // here. The fallback stays exactly as argued. Returning here would have made the fader a
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
        // #622b (review W1): the FOURTH `hasComposed` writer, conditional like open()'s.
        // Without it the flag went stale-false on this path: a take whose `notes`
        // decoded empty but whose `rawTake` survived opened grey (#622's honest flag),
        // then a Mix-fader nudge restored the FULL arrangement right here —
        // ⛔ #623b (review W3): that scenario is now HISTORICAL on the stopped path —
        // #623 installs the arrangement at open, so such a take no longer opens grey
        // there. This writer is still load-bearing, for three cases the install does not
        // cover: a ONE-bar rawTake, a rawTake whose FIRST bar is empty (both skipped by
        // the install's conditions), and the PLAYING branch, where `loadArrangement`
        // leaves `notes` untouched by design. Kept as the record of why it exists — and the
        // export tile, Save and the explainer all kept claiming nothing had composed,
        // while Play would have destroyed the recovery. The flag is a snapshot; every
        // path that LOADS notes must refresh it (the guard counts the writers).
        hasComposed = !pianoRoll.notes.isEmpty
        // `createIfNeeded: false` — a level change must never invent a clip; it only
        // rewrites the composer-owned one if it is already there.
        syncPrimaryRollClip(bars: bars, createIfNeeded: false)
        writeLaneTakes(lastLaneRaw)
        if !running { applySoundLive() }
    }

    /// The AUDIBLE half of a re-bake, run undebounced on every fader event.
    ///
    /// Deliberately a SUBSET of `rebalanceTake()`, not a refactor of it: the debounced
    /// path still calls the full method unchanged, so this can only make the fader land
    /// EARLIER — it can never change where it lands. Staging the same bars twice is
    /// idempotent (`pendingNotes` is overwritten with equal content), and re-deriving
    /// `mixGlued` twice costs a few hundred struct copies.
    ///
    /// Three things are deliberately NOT here, and each omission is why this is safe to
    /// run at gesture rate:
    /// · `syncPrimaryRollClip` / `writeLaneTakes` — the JSON encode + atomic file write.
    ///   That is the whole point of the split.
    /// · the `lastRawTake == nil` fallback to `recomposeIfRunning()`. ⛔ This line read
    ///   "Reached on every opened project (`open(_:)` restores a baked take without raw
    ///   bars)" — false since #217 gave `open(_:)` its own `lastRawTake = p.rebakeSource`,
    ///   and doubly so since #623 installs those bars on the roll. A LEGACY take with no
    ///   `rawTake` is what reaches it now. (#623b review W2: the identical clause was
    ///   corrected one method above in #623 and this copy was missed — the same sentence,
    ///   the same false premise, fifty lines apart.) Wherever it is reached, it would fire
    ///   a generate schedule per drag event. The debounced half keeps that fallback, so
    ///   the no-raw-take case behaves exactly as before this change.
    /// · the stopped branch — see the note on `scheduleRebalance` below.
    private func rebalanceAudibleNow() {
        guard running, beatPlayer.pattern.isPlaying else { return }
        guard let take = lastRawTake, !take.bars.isEmpty else { return }
        // `take.genre`, not `style` — same reason as in `rebalanceTake()`: the take must be
        // re-glued with the genre it was COMPOSED in, not one whose recompose has not
        // landed yet. Using `style` here would make the immediate half and the debounced
        // half disagree for the length of that window, which is worse than being late.
        let bars = take.bars.map { mixGlued($0, genre: take.genre) }
        pianoRoll.rebakeArrangement(bars, playing: true)
    }

    /// Apply the AUDIBLE half of a fader move at once, and coalesce only the expensive
    /// half. Founder 2026-08-01: "Lautstärke fader vom Pad zum Beispiel reagiert versetzt".
    ///
    /// ⭐ THE SPLIT THIS DOES, and why it is the fix rather than a tuning of the number.
    /// The 350 ms was never set by anything musical — the paragraph below already said so,
    /// and even named this split as the next step. A re-bake has two halves with costs
    /// three orders of magnitude apart:
    /// · AUDIBLE — `take.bars.map { mixGlued(…) }` + `rebakeArrangement`. A few hundred
    ///   struct copies and one array assignment. `applySoundLive()` already proves this
    ///   class is affordable at gesture rate: it runs on EVERY drag event, undebounced.
    /// · EXPENSIVE — `syncPrimaryRollClip` → `ClipStore.updateComposerMelody` →
    ///   `persist()` → `AppGroupStore`: a pretty-printed JSON encode of the whole clip
    ///   grid plus an atomic file-protected write, SYNCHRONOUSLY on the actor that also
    ///   hosts this view's `.menu` Pickers. At 120 ms a stepwise drag could fire that
    ///   ~8×/s — the main-actor-starvation class that froze menus in 10.76.48.
    /// Waiting for the cheap half behind the expensive one added 350 ms of pure dead time
    /// in front of a control the founder holds while listening.
    ///
    /// WHAT THIS DOES NOT REMOVE, stated plainly so the next reader does not expect more
    /// than it gives: the roll still swaps the new levels in at the next BAR BOUNDARY
    /// (~2 s at 120 bpm), and that part IS musically required — the alternative is a
    /// mid-bar note-array swap, and `rebakeArrangement`'s own multi-bar branch documents
    /// why it stages instead. So the Pad fader goes from ~2.35 s to ~2.0 s worst case, not
    /// to zero. Making the level itself live (a per-role output gain, so the fader stops
    /// travelling through note VELOCITY at all) is the change that removes the remaining
    /// 2 s — that is #196, a different and much larger slice, and it must answer #205
    /// first (velocity doubles as "is this note audible" for the visual, the light output
    /// and the felt sub).
    ///
    /// The immediate half runs ONLY while playing. Stopped, nothing is sounding, so there
    /// is no lateness to remove — and `rebakeArrangement(_:playing: false)` delegates to
    /// `loadArrangement`, which calls `allNotesOff()` and resets `playedBars`; doing that
    /// per drag event would be churn in exchange for nothing.
    ///
    /// DELIBERATELY NOT cancelled by `stopEverything` / `pausePlaybackKeepingSession`,
    /// unlike `regenTask`. Those cancel WORK GENERATORS — a pending re-bake starts no
    /// clock and arms no driver; it only makes the stopped take (and its MIDI export)
    /// agree with the fader the user just moved, which is the whole point of #174. A
    /// fader nudged just before Stop must not silently leave the old level baked in.
    private func scheduleRebalance() {
        rebalanceAudibleNow()
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
    /// RATE-LIMITED to one per `RegenSchedule.minAutoSeedGap`: the music can never re-seed
    /// faster than a musical phrase, no matter how many automatic triggers fire. A user
    /// edit (`auto: false`) answers only to its own gentler floor, measured from the last take
    /// that ACTUALLY happened. This makes a re-seed "flood" structurally impossible rather than
    /// merely unlikely.
    ///
    /// ⛔ TWO CORRECTIONS TO THIS PARAGRAPH, BOTH FOUND BY READING THE CODE UNDER IT (#398).
    /// (1) It said a user edit "stays instant (140 ms)". There is no 140 ms anywhere in this
    /// function — the quiet window is 0.45 s and the user floor is 2 s. A number that does not
    /// exist is worse than no number: it is what a reader reaches for when deciding whether a
    /// delay they measured is a bug. (⛔ The first version wrote "for a long time" here. That
    /// is unprovable in this repo — it is a shallow clone and `git log -S "140 ms"` bottoms out
    /// at the graft. CLAUDE.md strikes exactly this shape of unbacked "schon immer" claim
    /// elsewhere; the finding stands without it, so the three words are gone.)
    /// (2) The claim that the flood is "structurally impossible" was true only of the direction
    /// it was aimed at. The arithmetic below it could push a re-seed arbitrarily FAR AWAY — the
    /// opposite failure, unbounded, and it made a user's genre tap wait for a trigger that had
    /// already been cancelled. Both are gone; `RegenSchedule`'s header carries the full account.
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
        // ⛔ THE ARITHMETIC LEFT THIS FUNCTION (#398) AND MUST NOT COME BACK. It used to keep
        // ONE date for two facts — "a take was generated at T" and "no automatic re-seed before
        // T" — and subtract it as though it were always the first. With a FUTURE claim in it,
        // `gap - (now - claim)` ADDS the unspent claim to a fresh full gap: two co-firing auto
        // triggers pushed a re-seed claimed for t+5 s out to t+11 s (the opposite of the
        // "collapse into it" this comment used to promise), and a genre tap one second into a
        // claim waited six seconds under a doc line promising it stayed instant. The two facts
        // are now two properties, and the decision is a tested pure value type.
        // See `RegenSchedule` — its header carries the full account.
        let now = Date()
        let decision = RegenSchedule.decide(auto: auto,
                                            sinceLastSeed: now.timeIntervalSince(lastSeedAt),
                                            untilFloor: seedFloor.timeIntervalSince(now))
        let delay = decision.delay
        // Only the automatic branch claims, and it claims into `seedFloor` — never into
        // `lastSeedAt`, which `generate(…)` both reports as `sinceLast=` (#390) and re-stamps
        // when a take is really produced.
        if let claim = decision.claimFloorIn { seedFloor = now.addingTimeInterval(claim) }
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
        // #359 step 3 added the place toggle at the bottom of this panel, so the subtitle
        // names it. It is the LAST clause because it is the smallest of the four and the
        // only optional one — a subtitle that leads with an opt-in naming detail would bury
        // the two words (#272) the founder actually searched for.
        //
        // ⛔ THE #359-STEP-3 REVIEWER RAISED A CEILING THAT DOES NOT EXIST, and it is written
        // down here because this is the panel that keeps accreting controls (#188 MIDI, #216
        // export-failure line, #272 keep-last, #359 place) and it is therefore where the
        // claim will be raised again. The finding: "this `VStack` is now at exactly 10
        // children, the `ViewBuilder.buildBlock` limit — the next control will not compile."
        // The 10 is right; the limit is not. `buildPartialBlock` (iOS 16 SDK, and this app's
        // floor is iOS 18) removed the arity cap — `moodPanel` ships THIRTEEN children
        // through the very same `panel(_:_:isExpanded:)` helper and has compiled for weeks.
        // The same false constraint was struck from `signalSection`'s doc in #359 step 2
        // (that section is gone since #575, so this is now the surviving statement of it);
        // it has been asserted twice by two different readers, so: what is real is
        // type-check COST, not an arity error, and 10 is nowhere near where that bites.
        // The ceiling this file DOES have is the presentation-modifier chain (14) — that one
        // is measured, has crashed a shipped build, and is a different thing entirely.
        // ⛔ THE SUBTITLE PROMISED FIVE BUTTONS THAT LEFT WITH #482 ("Save and open a session ·
        // record the loop as WAV · MIDI for your DAW · keep what just played · put your city
        // in the name"). Four of those five are now tiles in `quickActionRow`, so as written
        // it sent a user INTO a panel to find controls that are permanently visible one line
        // under the transport — the #272 defect inverted. What this panel really is now: the
        // settings and explanations those tiles act on. The title stays, because that is still
        // the topic and `SaveDoorNamingTests` pins the chip, the VoiceOver name and the panel
        // heading as one decision.
        panel("Save & Export",
              "Set the loop length the Record tile uses · see what can be kept · put your city in the name · reset the sound",
              isExpanded: $showExport) {
        VStack(spacing: 10) {
            // ⛔ THE FIRST-RUN SENTENCE THAT STOOD HERE MOVED TO THE PLATE (GUI-Board
            // Scheibe 5, UX#7, 2026-08-16) — it now renders under `quickActionRow`, next
            // to the grey tiles it explains. #482 had left it in this panel with the
            // reasoning "the row has no room for a sentence"; the UX audit found exactly
            // the predicted cost: first-run users never open this panel, stared at the
            // grey tiles and read them as broken. A first-run-only line under the row
            // spends height only while the plate is idle, which re-decides that trade.
            // Its WORDING history stays load-bearing and travels by reference: #272 (the
            // founder searched for "save" and "record" and the line must contain both),
            // #355(b) (name the control that ACTUALLY starts — "Press Play", never the
            // pulse pill, whose tap opens a panel), and the #307/#355 retraction chain
            // behind those calls sits in this file's git history at this site.
            // `CopyNamesTheLiveControlTests` pins wording, uniqueness AND the new
            // placement — reword or move it only with that guard in the same commit.
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
            // ⛔ FIVE BUTTONS LEFT THIS PANEL WITH #482 — Record/abort, Keep last, Export
            // MIDI, Save and Open are now the six-tile row directly under the transport
            // (`quickActionRow`), on the founder's ask *"alles … im selben Button Format in
            // eine Reihe unter dem Play etc zusammengefasst"* (2026-08-07). They MOVED; there
            // is no second copy here, because two doors to one action is the defect this file
            // keeps retracting. Every hint and disabled rule travelled with them unchanged.
            //
            // What stays here is precisely what a 44 pt glyph cannot say. ⛔ The first version
            // called this "the first of the two" stateful sentences; there is only ONE (the
            // place-row caption below is static, and `exportLabel`'s four states are rendered
            // as text nowhere — see the ⛔ block on `quickActionRow`):
            KeepLastAvailabilityNote(pattern: beatPlayer.pattern, bars: loopBars,
                                     isExporting: isExporting, hasComposed: hasComposed,
                                     busyLabel: busyStatusLabel)

            // #522 — THE NAME COMES BEFORE THE PLACE, and that is not a taste call:
            // `SessionNaming.stem(artist:date:key:bpm:a4Hz:place:)` writes the artist first and
            // the place after the date, so the two rows read in the order the file name does.
            // It sits OUTSIDE the `#if canImport(CoreLocation)` guard below on purpose — the
            // place row is optional because a platform may have no location services; a name
            // is not, and folding it inside would make the one door to your own identity
            // depend on a framework that has nothing to do with it.
            ArtistNameRow()

            // #359 step 3 — THE PLACE TOGGLE BELONGS BESIDE THE THING IT NAMES, and that is
            // the whole argument for it living in this panel rather than some other one.
            // `locationNamer` is what puts the city INTO `session.sessionName(bpm:)`, which is
            // the string the Save action opens with.
            //
            // ⛔ THE ADJACENCY ARGUMENT AS WRITTEN IS SPENT, and saying so is the point: it
            // read "the Save button one line down" and "anything under Save/Open is read as an
            // afterthought". #482 moved Save into `quickActionRow`, so there is no button
            // below this row to be above. The PURPOSE of the adjacency — the user sees what
            // shapes the file name before committing to it — is kept by naming the control in
            // the caption below and in Save's own accessibility hint, which is the substitute
            // `WeatherIsAMoodRubricTests` itself proposed when it pinned the ordering.
            #if canImport(CoreLocation)
            placeRow
            // The second of the two sentences a glyph cannot carry. It names the control it
            // feeds, so the connection survives the two now being on different surfaces.
            Text("Included in the name the Save button writes.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            #endif

            // #603 B1 — the guide switch ("an- und ausschaltbarer Guide"). It sits ABOVE
            // the recovery corner (reset/diagnostics): learning aid, not recovery. The
            // overlay itself mounts in `WorkspaceView`'s ZStack — this row only flips the
            // shared `StudioDefaultKeys.guideVisible` key (H15-KEYSTORE: two views read
            // it, so the key + default live in Core, never re-typed here).
            Toggle(isOn: $guideVisible) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Guide").font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
                    Text("Cards that walk you through playing and understanding the app.")
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(EchoelTheme.accent)
            .accessibilityHint("Shows a card overlay explaining the instrument, one surface at a time")

            soundResetRow

            // #916: `diagnosticsExport()`, not `currentLog()`. This run PLUS the retained
            // crash, if one was kept — a crashed run used to live for exactly one launch,
            // and this is the always-reachable door that can still hand it over days later.
            // The export still STARTS with this run byte-for-byte, so nothing that reads the
            // first line for the build number changes.
            Button { diagnostics = DiagReport(text: EchoelCrashLog.diagnosticsExport()) } label: {
                Text("Diagnostics").font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the in-app diagnostic log to share if something crashed")
        }
        }   // panel("Save & Export")
    }

    // MARK: - Sound reset (#400)

    /// ⭐ THE ONLY COMPLETE SOUND RESET THIS APP HAD WAS DELETING IT.
    ///
    /// The founder's "schief" report on 2026-08-05 was cured by deleting and reinstalling —
    /// same binary either side, so the cause was persisted state. Reinstalling also destroys
    /// every saved patch, take and project, which is why nobody should ever have to reach for
    /// it. This row does the sound half and leaves the work alone.
    ///
    /// ⚠️ IT SITS BESIDE "Diagnostics" ON PURPOSE. This is the recovery corner of the panel —
    /// the place a player goes when something is wrong rather than when they want to make
    /// something. Putting it in `soundPanel`, among the controls that SHAPE the sound, would
    /// invite the accidental tap it is least able to survive.
    ///
    /// ⚠️ TWO TAPS, NOT AN `.alert` — see `soundResetArmed`. The body is already carrying 14
    /// presentation modifiers and the 10.76.34 black screen was that chain growing by three.
    /// A destructive action still needs its confirmation; this one just does not spend metadata
    /// depth on it.
    private var soundResetRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if soundResetArmed {
                    resetSoundToDefaults()
                    soundResetArmed = false
                } else {
                    soundResetArmed = true
                }
            } label: {
                Text(soundResetArmed ? "Tap again to reset the sound" : "Reset sound")
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(soundResetArmed ? EchoelTheme.text : EchoelTheme.dim)
                    // ⚠️ `minHeight`, not `height`, and `contentShape` because `.buttonStyle(.plain)`
                    // makes the HIT AREA the glyph run — ~90 × 14 pt without this, under both the
                    // HIG 44 floor and WCAG 2.5.8's 24. Exactly the defect #394 fixed on the Master
                    // panel's loudness Reset, and this control is smaller AND destructive.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // ⚠️ THE HINT HAS TO FLIP WITH THE STATE. The first version was static and ended
            // "Needs a second tap to confirm" — in the ARMED state that is the opposite of the
            // truth, so a VoiceOver user re-focusing an armed control was told a safety step
            // still stood in front of them. A hint that lies about a destructive action is worse
            // than none.
            .accessibilityHint(soundResetArmed ? """
            Tap to reset the sound now. Saved patches, takes and projects are kept.
            """ : """
            Puts key, tuning, concert pitch, genre, preset, articulation, the bass and pad \
            rhythm characters, the Field voice and the generated part levels back to factory. \
            Saved patches, takes and projects are kept. Needs a second tap to confirm.
            """)
            // …and the ARMING itself must be audible. VoiceOver does not re-announce a label
            // change on a control that already holds focus, so without this the experience is
            // "tap · silence · tap · destroyed". A VALUE change it does announce.
            .accessibilityValue(soundResetArmed ? "Armed" : "")

            if soundResetArmed {
                // ⚠️ "generated part levels", NOT "the mix faders" — the Mix board carries four
                // strips (Bass · Melodic·Pad · Field · Click) and this reset moves only the
                // generated ones. The panel's own reset button was corrected for exactly this
                // ("promises four and delivers two"); saying "mix faders" here on a destructive
                // control would re-open the same overclaim one screen away from its correction.
                Text("Key, tuning, genre, preset, the Field voice and the generated part levels go back to factory. Your saved patches, takes and projects are kept.")
                    .font(EchoelTheme.font(10))
                    .foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // ⚠️ DISARM WHEN THE PANEL GOES. `soundResetArmed` lives on the ROOT view, not on this
        // row, so without this it survives switching to another dropdown: arm it, open Sound,
        // come back ten minutes later, and ONE tap resets. `.onDisappear` fires when
        // `dropdownContent` swaps this panel's `AnyView` for another — one line, no timer, no
        // modifier on the root chain. (The backgrounding half is in the body's EXISTING
        // `.onChange(of: scenePhase)`, for the same reason: no new modifier.)
        .onDisappear { soundResetArmed = false }
    }

    /// Clear the musical identity and make the change AUDIBLE NOW.
    ///
    /// ⚠️ CLEARING THE KEYS IS ONLY HALF OF IT, and the missing half is the whole reason this
    /// is a function rather than one call. `SessionContext` caches its three values in stored
    /// properties, and the engine holds the tuning, the concert pitch, the articulation and the
    /// Field patch as applied STATE. A reset that only removed keys would leave the wrong sound
    /// playing until the next launch — the "I had to reinstall" experience again, just quieter.
    ///
    /// ⛔ ONE THING HERE IS NOT PROVEN, and the first version of this comment asserted it as
    /// fact twice ("`@AppStorage` falls back on the next read by itself"). What IS established:
    /// no `register(defaults:)` covers any of these keys — the only three registrations in the
    /// app are `multiRoll`, `voiceKindRouting`, `instrumentHome` — so after the clear the key is
    /// genuinely absent and the declared default is the only fallback; and `SoundReset.clear`
    /// uses `removeObject(forKey:)`, which posts KVO, NOT `removePersistentDomain(forName:)`,
    /// the variant known to leave `@AppStorage` stale. What is NOT established is that
    /// `AppStorage.wrappedValue`'s GETTER, called here from a button action, synchronously
    /// re-reads the store — that is observed behaviour, not documented contract. If it ever does
    /// not, `applyArticulation()` and `applyTuning()` re-apply the values this function just
    /// cleared and the reset silently cures nothing. `currentPatch` is deliberately NOT exposed
    /// to that risk (see below), and no test that can run in this repo settles the rest; the
    /// device pass does.
    ///
    /// ⚠️ THE RE-APPLY IS THE SAME EFFECT AS `onAppear`, NOT THE SAME SEQUENCE — the first
    /// version claimed the stronger thing. `onAppear` also clamps the genre against
    /// `MusicStyle.offered` and branches `currentPatch` on `presetIndex`; both are omitted here
    /// and both are currently harmless, the second ONLY because `studio.presetIndex` happens to
    /// be in `SoundReset.entries`. Take that entry out and the two definitions of "factory"
    /// diverge in silence, which is precisely what the claim was supposed to prevent.
    ///
    /// ⚠️ AND "the launch restore" IS NOT ONLY `onAppear`. The app's startup task also gives
    /// `leadVoice` a warm default before any generate (`EchoelmusicApp`), which this does not
    /// replicate — after a reset the lead keeps the last genre's `leadPatchName`. Left alone
    /// deliberately: copying that patch NAME here would be a second literal for one factory
    /// choice, the duplication `SoundReset`'s own header calls the shape of the defect. Stated
    /// rather than silently accepted, so the next reader knows it is a decision.
    ///
    /// ⚠️ THE SIBLING TO READ FIRST IS `resetTuningToStandard()`, the partial reset behind the
    /// tuning banner. It recomposes only on the PITCH half, deliberately, because a
    /// tone-system-only reset must not throw away a running take. This one always recomposes,
    /// and that is not a divergence: it resets the key, the genre and the preset by definition,
    /// so the running take is no longer the take the settings describe.
    private func resetSoundToDefaults() {
        SoundReset.clear(in: .standard)
        session.resetMusicalIdentity()
        // ⚠️ THE SAME HALF-FIX AS `SessionContext`, one layer down. `MixerStore` reads its four
        // levels once in `init` and holds them in stored properties, so clearing the keys leaves
        // the LIVE store still returning 0.00 for a muted role — and its `didSet` would write that
        // stale value straight back on the next unrelated edit. Assigning unity here is idempotent
        // (each `didSet` re-persists the factory value).
        //
        // ⚠️ A MIX LEVEL REACHES THE EAR BY TWO DIFFERENT ROUTES, and the first version of this
        // comment named only one ("a compose-time velocity multiplier — so the recompose below is
        // what makes it audible"). That is the belief this repo has already paid to correct once:
        //  · bass/pad/lead scale NOTE VELOCITIES at compose time, so they need the take re-baked;
        //  · the FELT SUB has no per-note velocity to scale and takes its level on the AUDIO side
        //    (`SubBassVoice.mixLevel`), so no amount of recomposing moves it. `mixBinding` and the
        //    Mix panel's own reset each push the two lines below IN ADDITION to their re-bake, and
        //    the latter carries the instruction "a new mutator must push both lines below".
        // This is that new mutator, and the first version of it pushed neither: a player with
        // `mixer.bass` persisted at 0.00 (the #399 signature) would have tapped "Reset sound",
        // watched every compose-time role return to unity, and still had a silent sub until the
        // next relaunch — a factory reset leaving behind exactly the class of state it exists to
        // clear. Caught in review, not by the guard, which only saw the `resetToUnity()` call.
        mixer.resetToUnity()
        subBass.mixLevel = mixer.bass
        laneVoiceRack.setBassMixLevel(mixer.bass)

        // ⚠️ THE SAME HALF-FIX A THIRD TIME, and this file's own header names the shape:
        // removing a key is not the same as applying its default when a LIVE object holds the
        // value. `performerSignature` is `@State`, read once at view construction, so
        // `SoundReset.clear` above deletes the stored fingerprint while the in-memory copy
        // keeps salting every take until the next launch — a factory reset that visibly does
        // nothing, which is the "it needed a reinstall" experience returning through the
        // button built to end it. Assigning `.unknown` is idempotent and takes the salt to 0.
        performerSignature = .unknown

        // ⚠️ THE SAME HALF-FIX A FOURTH TIME (#275). `SoundReset.clear` above removes
        // `studio.mood`, but `mood` is `@State` — the eight dials in memory keep shaping every
        // take until the next launch, so a factory reset would leave the instrument composing
        // at the settings it was supposed to clear. Assigning the factory profile is idempotent,
        // and the body's `.onChange(of: mood)` re-encodes it (writing the default string back
        // over a key that was just removed is harmless: `decode` of either resolves to the same
        // profile).
        mood = MoodProfile()

        // ⚠️ READ THE DEFAULT DIRECTLY, not through `style`. This is the identical expression
        // `@AppStorage` declares as `style`'s fresh-install default, so it is the SAME single
        // source — it simply does not depend on the getter semantics the ⛔ block above marks as
        // unproven. The timbre is the most consequential of these values, so it is the one that
        // must not rest on an assumption. Same reasoning as the Field patch below, which passes
        // `storedID: ""` rather than reading the freshly-cleared `touchPatchID`.
        currentPatch = StudioDefaultKeys.genre.value.synthPatch
        // Every other wholesale replace in this file nils the Undo snapshot (six sites, each
        // with the same note). Without it the prompt row still offers Undo after a factory
        // reset, and taking it restores a PRE-RESET patch — the one state this feature exists
        // to get rid of, leaking back through a live control.
        patchBeforeSoundChange = nil
        applyArticulation()
        applyTuning()
        applyConcertPitch(session.a4Hz)

        // ⚠️ THE OUTPUT STAGE HAS TO BE TOLD TOO, and forgetting it is silent. `PianoRollModel`'s
        // tick handler stamps these into every `MusicalFrame` on the shared sequencer tick —
        // installed once at app start, roll mounted or not — so the visual, the light and the
        // ADM-OSC space keep colouring by the OLD concert pitch and the OLD key until the next
        // `generate()` unless they are pushed here. `resetTuningToStandard()` (the sibling
        // partial reset behind the tuning banner) already does exactly this for A4, and the
        // `"a4"` edit path does it "now rather than at the next compose" for the same reason.
        pianoRoll.musicalA4Hz = session.a4Hz
        pianoRoll.musicalRootPitchClass = rootIndex
        pianoRoll.musicalScaleName = scale.rawValue

        // The Field wakes up on the factory play-surface patch when nothing is stored — the
        // launch resolver decides that, not a literal here, so the two cannot disagree (#402).
        if let touchSynth,
           let field = SynthPatch.launchTouchPatch(storedID: "", in: patchStore.patches) {
            touchSynth.apply(field)
        }

        // ⚠️ EXPLICIT, because otherwise it happens BY ACCIDENT. `handleCompositionEdit` ends in
        // `recomposeIfRunning()` for genre, key, scale and a4 — every value this clears. Without
        // it here, a reset while the take is playing leaves the OLD key and OLD genre sounding.
        // Worse, `.onChange(of: bassRhythmRaw)`/`(padRhythmRaw)` each call it too, so a user who
        // had set a rhythm character got a recompose and a user who had not got none: one tap,
        // two behaviours, decided by unrelated prior state.
        recomposeIfRunning()
        // ⚠️ AND WHEN STOPPED, THAT CALL DOES NOT RE-BAKE. `recomposeIfRunning()` falls to
        // `applySoundLive()`, which re-applies the patch and leaves the take's velocities exactly
        // as they were — so the mix levels this function just reset would stay baked into the take
        // that plays next and into its MIDI export. `scheduleRebalance()` is the re-bake, and the
        // Mix panel's own reset calls it for precisely this reason (`scheduleRebalance`'s doc: "A
        // fader nudged just before Stop must not silently leave the old level baked in").
        // Deliberately NOT called while running: the branch above already regenerates the take
        // from scratch, so a re-bake would be re-balancing something that is being replaced.
        if !running { scheduleRebalance() }

        EchoelCrashLog.breadcrumb("reset/sound: musical identity + user mix cleared to factory (#400)")
    }

    // MARK: - Diagnostics

    /// On launch, if the previous run died where the user could see it die, surface the
    /// log so it can be shared in one tap.
    ///
    /// ⛔ #582 — the condition used to be written out here as
    /// `prev.contains("Start tapped") || prev.contains("CRASH")`, and the first arm made this
    /// fire after every ordinary session in which biofeedback was used. It now asks
    /// `EchoelCrashLog.looksLikeUnseenCrash`, which subtracts the sessions that ended in
    /// `background` — i.e. the clean exits. The long rationale, and the one case it
    /// deliberately stops reporting, are at that function.
    ///
    /// It lives THERE and not here for a second reason: as a pure `String → Bool` on a
    /// Foundation-only type it is drivable end-to-end by the blocking bundle, which a
    /// `private func` on a `View` no test can instantiate never was.
    private func surfacePriorCrashIfAny() {
        guard diagnostics == nil else { return }
        let prev = EchoelCrashLog.previousSession
        guard EchoelCrashLog.looksLikeUnseenCrash(prev) else { return }
        diagnostics = DiagReport(text: prev)
    }

    private func diagnosticsSheet(_ text: String) -> some View {
        NavigationStack {
            ScrollView {
                // ⭐ Scales with Dynamic Type, stays monospaced — #353d. See the long rationale
                // at the identical line in `SafeModeView`: this sheet and that screen render the
                // SAME diagnostic log, so they must not disagree about how big it is. The text
                // style `.caption2` is 11 pt at the default setting, so nobody who has changed
                // nothing sees a difference. Do NOT "finish the job" by moving this to
                // `EchoelTheme.font` — the brand face is proportional and a log needs its columns.
                Text(text.isEmpty ? "No diagnostics recorded." : text)
                    .font(.system(.caption2, design: .monospaced))
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
                .font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
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
                if let importNote {
                    // WHY A PLAIN LINE AND NOT AN ALERT — the same reason as `exportFailure`
                    // one screen up (#216), and it binds harder here: the importer this
                    // reports on is itself one of the two NESTED presentation modifiers that
                    // put this file at 16 (#479 pins that as an equality). Same treatment as
                    // that precedent on purpose; a second look for one status is how a house
                    // idiom stops being one.
                    //
                    // ⚠️ IT CARRIES `@State` WHERE THE PRECEDENT COMPUTES FROM A MODEL, and
                    // that difference is forced, not sloppy: `exportFailure` reads
                    // `LoopExporter`, which lives for the app's lifetime. Nothing outlives a
                    // failed import — the URL is gone and `ProjectStore` holds only what it
                    // successfully saved — so there is no model to ask.
                    //
                    // FIRST IN THE LIST because the library can be long and the sheet does not
                    // scroll back on its own; a note under twenty rows is a note nobody reads.
                    // It clears when the picker is opened again, so the Import button is both
                    // the retry and the dismissal, and a stale sentence cannot outlive the
                    // attempt that produced it.
                    Text(importNote)
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Import failed. \(importNote)")
                }
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
                        // ⛔ THIS SENTENCE NAMED ONE TRIGGER AND #357(b) ADDED A SECOND, in the
                        // same slice that argued the gate exists to "keep the row meaning one
                        // thing". It read "Kept automatically when you leave the app." — and
                        // since `open(_:)` also writes the slot, a user reading that would
                        // believe the row holds their last backgrounding when it actually holds
                        // the state from just before their last OPEN. Wrong in the direction
                        // that matters: they would trust it for a recovery it cannot make.
                        // This is the one place anyone learns what the slot is, and it is
                        // pinned by `OpeningAProjectRescuesTheLiveTakeTests` so the next
                        // trigger cannot be added without the sentence.
                        // One line, not a `+` concatenation: the guard matches this sentence
                        // as a single string, and this bundle has been red once on the cost of
                        // concatenated literals (#287).
                        Text("Kept automatically when you leave the app and before you open another take. Overwritten each time.")
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
                    Button {
                        // Clearing HERE makes this button both the retry and the dismissal —
                        // no second control, no timer, no lifecycle modifier. The note can
                        // therefore never outlive the attempt that produced it.
                        importNote = nil
                        projectImportPresented = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
            #if canImport(UniformTypeIdentifiers)
            .fileImporter(isPresented: $projectImportPresented,
                          allowedContentTypes: [.json],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        _ = try projects.importProject(fromDocument: url)
                        importNote = nil
                    } catch {
                        importNote = ProjectStore.importFailureNote(error)
                    }
                case .failure(let error):
                    // ⚠️ CANCELLING IS NOT A FAILURE TO REPORT, and this branch is written to
                    // be right under BOTH readings of SwiftUI's contract. Whether tapping
                    // Cancel arrives here as `CocoaError.userCancelled` or never calls the
                    // completion at all has varied across iOS versions, and no device is
                    // available here to settle it — so the check is a SUPERSET: if
                    // cancellation is delivered we swallow it, and if it is not, the guard is
                    // a no-op. Getting this wrong in the other direction would put "Couldn't
                    // read that file." on screen for a user who deliberately backed out, which
                    // is the lying-control class this whole family of slices removes.
                    if (error as? CocoaError)?.code == .userCancelled { return }
                    importNote = ProjectStore.importFailureNote(error)
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
                    // #521 — the take says who made it, and ONLY when that is not you. The
                    // decision (and every reason for it) lives in `Project.attribution`; this
                    // site owns two things and no more: the reader's own name comes from the
                    // live `SessionContext`, never from a copy, and the label is the neutral
                    // "by <name>" — see that doc for why it must not say "imported".
                    // `.caption`/`dim` deliberately repeats line 2's treatment rather than
                    // introducing a third type size into one row (#362/#363).
                    //
                    // ⚠️⚠️ IT IS REACHABLE SINCE #522, and until then it rendered on nothing —
                    // read `Project.attribution`'s "HONEST REACH" paragraph before concluding
                    // this line is live or dead. `SessionContext.artistName` had no production
                    // writer at all; `ArtistNameRow` in "Save & Export" is now that writer.
                    // What has NOT changed: on an untouched install every device and every take
                    // still says `E~`, so the gate below is still `nil` — the line appears only
                    // once two people have named themselves differently, which is a property of
                    // two devices and not of this one.
                    //
                    // ⚠️ NOT a freeze hazard, and the reason had to be RESTATED when #522
                    // landed rather than left standing: the old argument was "this keypath has
                    // no writer at all, so the read cannot invalidate anything", and that
                    // premise is now false. The surviving reason is the rate — writes are one
                    // per keystroke, user-paced, nowhere near the ~10–30 Hz producer class of
                    // the 10.76.41/50 freeze, and the keyboard is up while they happen, so no
                    // `.menu` popover can be torn down. A reason that outlives its premise is
                    // worse than none: the next session would read it as still measured.
                    if let credit = p.attribution(besideOwnName: session.artistName) {
                        Text("by \(credit)").font(.caption).foregroundStyle(EchoelTheme.dim)
                    }
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
        // #582 — the constant, not the literal: `looksLikeUnseenCrash` matches on this exact
        // string, and a rename here with a literal there would silently disable the report.
        EchoelCrashLog.breadcrumb(EchoelCrashLog.startTappedMarker)
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
    /// puts the app in" — false. Every reachable arm — the pill's long-press picker and, since
    /// #616, the bioPanel "Bio source" row, both through `selectBioSource` —
    /// goes through `startBiofeedback()` when idle, i.e. a full take; the camera-only arms
    /// live in `BioSourceView`/`SessionView`, both doorless. (This sentence used to list
    /// `BioStripView`'s pulse start alongside the picker as a second reachable arm. #234
    /// removed it from the Bio panel, so it now survives only inside `BioSourceView` — the
    /// very view this same sentence calls doorless. Corrected because the conclusion survives
    /// and the evidence did not, which is the worse of the two ways to be stale.) So this is a
    /// product
    /// decision — and as of #234 it is a SHIPPED one, reachable by every user who presses ■
    /// during a take. Flagged to the founder rather than buried: if "■ should end everything"
    /// is what he wants, the change is one line in `PlaybackToggleButton.toggle()`. (⛔ This
    /// pointed at `TransportBar.toggle()` until #456. The method left with #289 and the struct
    /// with #456, so the instruction named a place a session could not go — the expensive kind
    /// of stale note, because it reads as actionable.)
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
        // #604: starting ANY bio source is the instrument hint's lesson, learned — the
        // user found Start, which is step 1 of the hint's own first sentence ("Start the
        // music, then a finger on the back camera"). Retiring it here, at the action,
        // replaced the once-ever display contract that let a missed 4.5 s whisper be the
        // app's only teaching moment (GUI-Board Scheibe 1; keys in StudioDefaultKeys).
        instrumentHintSeen = true
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

    /// Switch the live BIO INPUT source from either chooser surface (founder 2026-07-15:
    /// "camera light · Search for Bluetooth Device · Simulation"): the pill's long-press
    /// menu posts `.echoelSelectBioSource` into the receiver on `menuBar`; `bioPanel`'s
    /// "Bio source" row (#616) calls this directly.
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
        // #403 Slice 1 — the PERSON flavours the SKELETON, the MOMENT flavours the detail.
        // `bioSeed` above is the body RIGHT NOW (fine-quantised, deliberately different every
        // time the body moves); this salt is the slowly-learned fingerprint of the performer,
        // coarse enough to stay the same across sessions. Folded ONCE, here.
        //
        // ⚠️ AND IT REACHES THE DETAIL SEED TOO — stated plainly rather than claiming a
        // separation this code does not have. `evolvingSeed` three statements below is
        // DERIVED from `structureSeed`, so every salt folded here displaces the detail seed
        // as well (the weather salt always has; see the corrected E3b note). What the plan's
        // "not in the detail seed" rule actually guards against — one person always getting
        // the same piece — cannot happen either way: the evolution nonce moves on every take,
        // so the fingerprint shifts WHERE in the space a person's takes live and never
        // collapses them onto one point.
        //
        // Read BEFORE the observation further down, so a take is coloured by the fingerprint
        // as it stood when the user pressed the button. Skipped on an explicit override: the
        // maze audition already resolved its skeleton, and re-salting it would replay
        // something the user never heard.
        //
        // Empty signature ⇒ salt 0 ⇒ XOR is a no-op ⇒ bit-identical to before #403.
        if structureSeedOverride == nil {
            let salt = performerSignature.seedSalt
            if salt != 0 { structureSeed ^= salt }
        }
        // …and this is the learning half, deliberately AFTER the read above. Only a real take
        // teaches (`advanceEvolution`), so a maze audition reads the body without writing to
        // the person, and `PerformerSignature` itself refuses anything inside its 30 s window
        // — a control tap that recomposes must not count as another piece of evidence about
        // who is playing. Writing back only on a real change keeps a settled body from
        // touching the defaults on every generate.
        if advanceEvolution, let f = frame {
            let taught = performerSignature.observing(f)
            if taught != performerSignature {
                performerSignature = taught
                taught.save(to: .standard)
            }
        }
        // E3b: the sky flavours the SKELETON — its salt is folded into the structure seed and
        // is never applied to the detail seed on its own.
        // ⛔ AND THAT IS AS FAR AS THE CLAIM GOES. This comment used to continue "— the detail
        // seed below stays body+evolution, so weather never outweighs the body", and the very
        // next statement falsifies the first half: `evolvingSeed` is DERIVED from
        // `structureSeed`, so whatever is folded here displaces the detail seed too. The
        // "never outweighs" half survives (the body seed is the base and the evolution nonce
        // keeps moving); "never reaches it" was a different, untrue statement. Found while
        // folding the #403 performer salt in above, which lands in exactly the same place —
        // a wrong rationale next to a correct decision is the more expensive of the two.
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
        // ⚠️ #608: `var moodForInput` is HOISTED ABOVE the `#if` on purpose. The old
        // shape declared it `var` inside the WeatherKit branch and `let` in the
        // `#else` — a "sibling block" added below would then silently not exist (or
        // not compile) on non-WeatherKit configs. The auto fold must exist on every
        // config, so the ONE declaration lives here.
        var moodForInput = mood
        #if canImport(WeatherKit) && canImport(CoreLocation)
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
        #endif
        // ONE spelling of the composer's HR/HRV fallback chains (#416) — the auto
        // fold below and the `Input` construction must read the SAME body, so the
        // values are hoisted here instead of spelled twice.
        // `measured`, not the raw value — an unlocked rPPG's finite 0 is not a heart
        // rate. The chain is deliberate: the last take's body first (a momentary loss
        // of lock keeps the register the performer's own pulse set), then 70 as the
        // resting neutral for a body that has never been read.
        let hrForInput = fin(measured(frame?.heartRateBPM)
                                ?? measured(heldBody.map { Float($0.bpm) }), 70)
        // `hrvForSound`, not the raw value: `fin`'s fallback only fires for nil or
        // non-finite, so a REAL 0 (= not measured yet) went straight through — and in
        // BioComposer low HRV means high sympathetic load, so the composer answered
        // "I know nothing about this body" with maximum arousal and a busier take.
        let hrvForInput = fin(frame?.hrvForSound, 0.5)
        // #608 Scheibe 1 — AUTO MODE fold: consult the pure decision core at the ONE
        // choke point every take passes (generate and the variation audition share
        // it), so the cadence is STRUCTURALLY the evolve tick — no timer exists to
        // mis-rate. OFF (default) skips even the state write; a `Steer` at intensity
        // 0 is byte-identical through `WeatherMood.blend` (the Golden law). The body
        // state is `BioComposer.musicalState` reused verbatim (#416 — no second
        // formula), fed the SAME values the `Input` below receives. Tempo is
        // deliberately absent here (T1/T2 — the Flow-Servo stays the only bio→clock
        // path; `AutoModeStartsOffAndOwnsNoTempoTests` scans this fold for it).
        if autoMode {
            let bodyState = BioComposer.musicalState(coherence: liveCoh,
                                                     hrvNormalized: hrvForInput,
                                                     heartRateBPM: Double(hrForInput))
            let (steer, nextState) = AutoAttune.decide(
                calm: bodyState.calm, arousal: bodyState.arousal,
                baseDarkness: moodForInput.darkness,
                baseLiveliness: moodForInput.liveliness,
                baseTension: moodForInput.tension,
                previous: autoAttuneState)
            // #608b, PRECISED by the #614 review — the sentence that stood here
            // ("without this gate, twiddling a dial for a second satisfies a hold")
            // implied dial edits were excluded. They are NOT, and never were: a
            // debounced dial edit reaches this fold via generate(advanceEvolution:
            // true), i.e. as a REAL take — it ages the hold, and since #614 it emits
            // the evolve breadcrumb at edit cadence. That is the AutoAttune header's
            // own law ("a real take — the evolve tick, or a user-triggered
            // regenerate"); do not "fix" the aging away from this comment. What the
            // gate excludes is ONLY the read-only variation audition
            // (advanceEvolution: false): it STEERS with the current policy but
            // neither ages it nor logs — a maze preview narrating takes nobody kept
            // would be the phantom the breadcrumb guard forbids.
            if advanceEvolution {
                // #614 — ONE breadcrumb per evolve DECISION (event-rate: at most one
                // per debounce-floored generate, never per frame, never in body). It
                // is the device-log answer to "what did Auto just do to this take?" —
                // the open 2519 audibility probe reads this line next to the take it
                // describes. Auditions steer but neither age the state nor log: a
                // maze preview writing breadcrumbs would narrate takes nobody kept.
                let paused = [nextState.pausedDarkness ? "D" : nil,
                              nextState.pausedLiveliness ? "L" : nil,
                              nextState.pausedTension ? "T" : nil].compactMap { $0 }
                log.log(.info, category: .automation, String(format:
                    "Auto attune: %@ (calm %.2f, arousal %.2f) steer D %.2f L %.2f T %.2f ×%.2f%@",
                    nextState.policy.rawValue, bodyState.calm, bodyState.arousal,
                    steer.darknessTarget, steer.livelinessTarget, steer.tensionTarget,
                    steer.intensity,
                    paused.isEmpty ? "" : " paused: " + paused.joined(separator: ",")))
                autoAttuneState = nextState
            }
            moodForInput.darkness = WeatherMood.blend(
                base: moodForInput.darkness, target: steer.darknessTarget,
                intensity: steer.intensity)
            moodForInput.liveliness = WeatherMood.blend(
                base: moodForInput.liveliness, target: steer.livelinessTarget,
                intensity: steer.intensity)
            moodForInput.tension = WeatherMood.blend(
                base: moodForInput.tension, target: steer.tensionTarget,
                intensity: steer.intensity)
        }
        let input = BioComposer.Input(
            // Both hoisted above the auto fold (#608/#416) — the rationale for the
            // fallback chains lives at the ONE definition site up there.
            heartRateBPM: hrForInput,
            hrvNormalized: hrvForInput,
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
            padRhythm: RoleRhythm.Character(rawValue: padRhythmRaw),
            // #403 Slice 3 — the PERSON sets how hard the take is played. A fold inside the
            // builder that already exists, not a new surface: `performerSignature` is the same
            // `@State` the seed salt and the pace tilt read, and `dynamicTilt` is exactly 0
            // until an HRV has been learned, so this argument is a no-op on a fresh install.
            signatureDynamicTilt: performerSignature.dynamicTilt,
            // #581 — the pad chord shape rows. These are the ONLY reason `padShapeSection`
            // is not decoration: `roleRhythmOnsets` takes them as required arguments, but
            // `Input` defaults them, so forgetting this line would compile, look complete on
            // screen, and change nothing. That is what the guard's first claim pins.
            padGate: Float(padGate), padAccent: Float(padAccent), padEvolve: Float(padEvolve)
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
        // #390: read the PREVIOUS floor before overwriting it — that difference is the
        // re-seed interval the breadcrumb prints. `.distantPast` is the never-generated
        // sentinel and prints as "first" rather than as an absurd number of seconds.
        let sinceLastSeed: TimeInterval? =
            lastSeedAt == .distantPast ? nil : Date().timeIntervalSince(lastSeedAt)
        // ⛔ #398: THIS COMMENT USED TO READ "floor for the next automatic re-seed (anti-flood
        // invariant)" AND IT NOW NAMES THE WRONG PROPERTY. The anti-flood floor is `seedFloor`.
        // This line records that a take was PRODUCED — the fact `sinceLast=` above reports.
        // Left as a correction rather than a silent rewrite because this is the line a reader
        // lands on when asking "where is the floor set?", and the old wording would have sent
        // them to fold the claim back in here, which is precisely the defect #398 removed.
        lastSeedAt = Date()   // a take really happened, now
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
            // ⛔ #380: THIS LINE WAS `min(max(lockedBPM, 40), 240).rounded()` AND DISAGREED WITH
            // THE FIELD THAT SETS IT, TWICE OVER. `lockedBPM` is a SETTING, not a measurement —
            // #368's whole finding, one layer down. `BodyTempoField` stores it to 1e-4, displays
            // every digit, and clamps to `Transport.minTempo...maxTempo`; tap tempo stores a
            // tenth. Then this line rounded it to a whole BPM and re-clamped it to 40…240, and
            // `glideTempo` below pulled the clock to THAT. Lock 71.2345 and the field kept
            // reading 71,2345 while the beat ran 71; type 280 and it ran 240. The rounding was
            // invisible until #356 made every tap trigger a recompose, which is how it surfaced.
            //
            // The CLOCK's three ranges are now one: the field, this line and the engine all use
            // the `Transport` constants (`PatternEngine.minTempo/maxTempo` ARE those constants),
            // and `LoopExporter`'s bar maths already reasoned in 30…300 — a third party that
            // agreed with the field while this line did not. The 40…240 that stood here matched
            // nothing but `TapTempo`'s OWN defaults; the unlocked branches below were never held
            // to it either (they fold into the genre's window instead). Its provenance cannot be
            // established: this is a shallow clone and `git log -S 'min(max(lockedBPM'` returns
            // only the graft `24e9420`. So "a copied literal" is a reading, not a finding — the
            // rival reading ("copied from `TapTempo` ON PURPOSE, so a tapped take cannot run at
            // 30") is equally available and equally unprovable. What decided it is not the
            // history but the disagreement: whatever the intent, the field accepted a tempo this
            // line refused.
            //
            // ⚠️ AND "the take can no longer be the only party with an opinion" — which is what
            // stood here — WAS TOO STRONG, because a FOURTH opinion is live and this change made
            // its span wider. `generate()` also hands the composer the RAW `lockedBPM` as
            // `lockedTempo`, and `BioComposer.tempo(for:)` clamps THAT into `style.tempoRange`,
            // which is what `tempoDensityScale` reads. So the clock may now run 30…300 while the
            // note density is computed at the genre's window — lock 300 on Contemplation (44…66)
            // and the thinning that exists to stop a fast take sounding hektisch never engages.
            // That divergence predates #380; its reachable span grew from 240→300 at the top and
            // 40→30 at the bottom. Tracked as its own decision, because "should a locked take
            // outside the genre window keep the genre's density?" is a musical question, not a
            // clamp.
            //
            // `clamped(to:)` rather than `min(max(…))` is CONSISTENCY, not a live silence fix,
            // and saying otherwise would be the mistake this file keeps paying for. The nested
            // form does pass NaN through both bounds — but `PatternEngine.glideTempo` (which
            // this value reaches) opens with the NaN-safe `clamped(to:)` against the same
            // bounds and has its own ⛔ block about a comment that overstated exactly this.
            // A NaN was already caught one layer down. It is changed here because a persisted
            // value that reaches the clock should not be guarded by the form CLAUDE.md names
            // as a shipped permanent-silence cause, however well the next layer covers for it.
            tempo = lockedBPM.clamped(to: Transport.minTempo...Transport.maxTempo)
        } else if tempoSeededFromBody {
            // Ease toward the current body-mapped tempo (octave-folded INTO the genre's
            // window, B4 — the pulse drives the beat at the genre's rhythmic level, so
            // Trap really runs 130–150 and Punk 160+), at most ±step per tick.
            if bodyTempoTrustworthy(frame) {
                let target = StudioCalculator.tilted(
                    StudioCalculator.genreTempo(composition.suggestedTempo,
                                                into: style.tempoRange),
                    within: style.tempoRange,
                    by: performerSignature.tempoTilt).rounded()
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
            // #403 Slice 2 — THE PERSON TILTS THE PACE, AFTER THE FOLD. Both genre-tempo call
            // sites in this method get the tilt and the LOCKED branch above deliberately does
            // not: a number the user typed is theirs, and a fingerprint quietly moving it
            // would be a lying control. An unlearned performer tilts by 0, which
            // `StudioCalculator.tilted` returns unchanged — bit-identical to before #403.
            let bodySeed = StudioCalculator.tilted(
                StudioCalculator.genreTempo(composition.suggestedTempo,
                                            into: style.tempoRange),
                within: style.tempoRange,
                by: performerSignature.tempoTilt).rounded()
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
                //
                // ⚠️ #403 Slice 2 made the "66 … walks DOWN to the real pulse" half of the
                // paragraph above genre- AND performer-specific: `bodySeed` now carries the
                // signature's tilt, so a returning performer with a learned calm heart starts
                // BELOW their fold instead of at it, and the convergence can walk up. Still
                // continuous, still no jump — but do not read the two literal numbers as the
                // whole story for anyone the app already knows.
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
        // product is pure meditative Flächen — NO drum layer, ever, whatever the genre
        // says. This also removed the shamanic pulse drum that a stale stored
        // `beatMode = .pulse` was still playing under the Fläche (device log 1783426400).
        // The `BeatMode` enum and the shamanic/genre groove BUILDERS stay compiling; the
        // `beatModeRow` CONTROL and the `studio.beatMode` key are gone (#323, after
        // #166/#167 deleted the voices those options selected between).
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
        beatPlayer.pattern.glideTempo(to: tempo, source: .flowServo)
        // GROOVE CYCLE 2: apply the genre's swing so odd 16ths land late for a
        // rolling, human feel (dance push, dragged vaporwave, straight genres stay 0).
        // The melody rides this clock, so the whole take swings instead of sitting
        // dead-on-grid.
        //
        // ⛔ THIS LINE READ `setSwing(0)` UNTIL #327, with the justification "no beat →
        // nothing to swing (pure Flächen run straight)". Both halves were wrong, and the
        // comment ABOVE it — unchanged since GROOVE CYCLE 2 — said so all along.
        //
        //  · "No beat" is true and irrelevant. A note's onset is decided by WHEN THE TICK
        //    FIRES, and the melody rides the same tick: `pattern.onTick` is installed in
        //    `PianoRollModel.start`, from the unconditional `pianoRoll.start(pattern:…)` at app
        //    start. Drums were never what carried the groove here — killing them (#166/#167)
        //    did not remove anything this line depended on.
        //  · "Pure Flächen run straight" is already what the DATA says: of the 16 genres in
        //    `MusicStyle.offered`, TEN return `swing == 0` — every meditative and ambient
        //    one. The hardwire did not protect them; it silenced the other six.
        //
        // The six that change, re-derived (do not quote — re-run against `offered`):
        // deepHouse 0.16 · vaporwave 0.15 · techHouse 0.12 · detroitTechno 0.10 ·
        // dubTechno 0.08 · minimalTechno 0.04. Jazz (0.34) and the shuffle family are NOT
        // offered, so the reachable maximum is 0.16, not 0.34 — that matters for the
        // collateral, see below.
        //
        // ⚠️ WHAT THIS TURNS FROM THEORETICAL INTO ACTIVE: `Transport`'s tick→time map
        // assumes every step lasts the nominal `60/bpm/4`; under swing the odd step lasts
        // `base × (1 − swing)`. That comment has spelled the consequence out for a while —
        // on a shortened step the clock UNDERSTATES how late a Field touch was, so a touch
        // that earned a nudge falls inside `TouchQuantizer.latenessToleranceTicks` and the
        // echo silently does not fire. It was unreachable while this line said 0. It is
        // reachable now, bounded by the offered maximum: 16 %, not the third that comment's
        // jazz example implies. Filed as #328.
        //
        // TWO CORRECTIONS TO THE FIRST VERSION OF THIS NOTE, both of which sized the damage
        // too small:
        //  · The tolerance is not "12". That is the struct default; the live call site
        //    (`TouchInstrumentUIView.sound`) raises it per note to `max(12, 20 ms/tick)` —
        //    19 ticks at 120 BPM. A wider window absorbs MORE understated lateness.
        //  · It is not "confined to Field touch echo". The same `musicalNow` closure feeds
        //    Field SELF-PLAY (`autoPlayTick` → `FieldAutoPlay.cell(forTick:)` on a 60 Hz
        //    link), so the generator's cell edges ride the same distorted grid — an arp
        //    drifting against the take, which is heard, not merely missing.
        // Unchanged and still worth stating: the generated take does NOT use that map (it
        // rides `PatternEngine`'s own swung gap), so this line's own output is correct.
        beatPlayer.pattern.setSwing(style.swing)
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
        // ⛔ THIS WAS `if let frame { … }`, AND THE GATE DEFEATED THE HONESTY OF THE THING
        // IT CALLS (#506). `BioExplanation.text` was built with great care for exactly the
        // no-body case: it drops every clause it cannot measure, opens with "tempo holds at
        // N BPM; no pulse measured yet", and deliberately REMOVES the phrase " from your
        // live signal," when nothing was read — five tests pin those branches. Gating the
        // call on a frame made all of that unreachable from the app, and left something
        // worse behind: nothing else writes or clears `caption.text`, so a take composed
        // with no body kept narrating the PREVIOUS take's heart rate. That is #503's defect
        // one surface up — a reading that stopped arriving, still presented as live.
        // Unconditional now; nil is the all-unmeasured case the callee already renders.
        caption.text = BioExplanation.text(for: frame, tempo: tempo)
        // #644: the heading above this paragraph has to name the same driver the paragraph
        // does, and `BioExplanation.driver(for:)` is that decision — the SAME "was anything
        // measured" predicate the line above uses to decide whether to print " from your live
        // signal,". Same statement, same `frame`; see `StudioCaption.driver` for why the
        // adjacency is the whole guarantee.
        caption.driver = BioExplanation.driver(for: frame)
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
        // gated off (`PianoRollModel`'s `laneAudible` gate) → total silence even though notes
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
        // ⛔ THE LABEL IS `userMix`, NOT `mix`, AND THE RENAME IS THE WHOLE POINT (#306).
        // Everything else on this line is COMPUTED BY THIS GENERATE — note count, transport
        // state, the roll gain, the finished bar's peak velocity. These three are not: they
        // are the persisted Mix-panel faders, unchanged by generating, printed here only so
        // a low `vMax` can be attributed. `mix=` inside a line that begins `generate[…]`
        // read as an output of the generate, and I diagnosed exactly that from device log
        // 2479 — "the bass mix is re-rolled on every generate and lands on 0.00 in 37 of 49
        // cases". It is not re-rolled. `mixer.bass` has ZERO assignments anywhere in
        // `Sources/` outside `MixerStore` itself (`init` from UserDefaults, `resetToUnity`)
        // and this view's `mixBinding` — i.e. the Mix panel's own field. The 37 zeroes were
        // one persisted fader sitting at zero, and the twelve non-zero readings (0.78, 0.90
        // ×3, 0.56, 0.33, 0.27 ×7) were a finger on that field.
        //
        // THE LESSON IS NOT "ADD A COMMENT" — the paragraph above this one already said a
        // published 0.000 needs a user fader below 0.0118, and it was right. A breadcrumb is
        // read in `echoel_diag.log`, pasted into a chat, with no source file beside it. Its
        // own label is the entire explanation it gets, so the label has to carry the meaning
        // the comment carries. Any value printed here that the caller did not compute needs
        // a name that says so.
        // ⭐ #390 — THE HARMONIC FRAME, because the founder's report "es klingt sehr
        // unharmonisch" (v10.79.366, device log 2483) could NOT be answered from a log that
        // has twenty-seven rPPG lines and not one naming a pitch. Three mechanisms were
        // live candidates and this line could separate none of them:
        //   · the composer's own harmony inside the chosen scale (#314),
        //   · the #312 sub-bass retune, which is bit-identical under 12-TET and only bites
        //     once a non-12-TET system is selected — so the FIRST thing to know is which
        //     system was selected, and the log did not say,
        //   · the re-seed overlap: `loadArrangement` deliberately does NOT `allNotesOff`
        //     while playing (its own doc: "sounding bar keeps playing, new content from the
        //     next boundary"), so every re-seed layers a new chord over the previous one's
        //     tail. Log 2483 shows SEVEN generates in 57 s. `sinceLast` prints that rate so
        //     it stops being something I have to reconstruct by subtracting timestamps.
        // `tuning=edo12` on a bad-sounding take rules the second one out in one glance; a
        // maqām or pélog id makes it the first thing to test. That is the whole point — this
        // is a line read in `echoel_diag.log` with no source beside it, so every value it
        // prints carries its own name (the #306 lesson, one paragraph up).
        // `sinceLastSeed` is captured at the TOP of this function, before `lastSeedAt` is
        // overwritten (`ReSeedIntervalIsMeasuredBeforeItIsResetTests` pins that ordering).
        //
        // ⛔ #398 FALSIFIED THE REST OF THIS PARAGRAPH, AND IT IS THE DANGEROUS KIND OF STALE.
        // It read: "no new `@State`, and deliberately so: `lastSeedAt` is the anti-flood floor
        // and adding a second clock beside it would be a second thing to keep in step." Both
        // halves are now wrong — `lastSeedAt` is NOT the anti-flood floor (`seedFloor` is), and
        // a second clock WAS added, on purpose. Worse than merely stale: as written it argues
        // AGAINST `seedFloor`'s existence, so a later cleanup cycle could read it as the
        // project's standing position and fold the two back together — restoring the exact
        // defect. (CLAUDE.md records this class twice: a "do not change this" note with a false
        // rationale is worse than none, because the next session cannot refute it.)
        //
        // The thing that WAS true and is worth keeping: one clock could not carry both facts.
        // Overloading it is what made this very breadcrumb print `sinceLast=0.0s` on every
        // automatic re-seed — confirmed on device in v10.79.368 build 2485, where all four
        // `evolve` lines read 0.0 s against real gaps of 6.0 · 6.0 · 13.8 · 15.6 s.
        // The root prints via the existing `TuningReference.noteName(forMIDINote:)` on
        // 60+root; the "4" it appends is that helper's fixed octave and carries no meaning
        // here — the PITCH CLASS is the whole content.
        //
        // ⚠️ THE THREE VALUES ARE HOISTED, NOT INLINED, and the reason is a bill this repo
        // has already paid. A `.map { … }` closure plus a fourth `String(format:)` dropped
        // into an interpolation that already carried five of them is exactly the shape that
        // blew the type-checker in #287 (`3379bb3`) and turned the BLOCKING gate red — with
        // no local toolchain, that costs a full CI round-trip to discover. The expression is
        // split where splitting is free.
        let keyText = "\(TuningReference.noteName(forMIDINote: 60 + rootIndex)) \(scale.rawValue)"
        let sinceText: String = sinceLastSeed.map { String(format: "%.1fs", $0) } ?? "first"
        let a4Text = String(format: "%.1f", session.a4Hz)
        // ⭐ #413 — WHAT SET THE NOTE COUNT. Founder device log 2488 shows five automatic
        // re-seeds of the same session reporting 5 → 25 → 13 → 13 → 13 notes, and this line
        // could not attribute a single one of them: it prints the COUNT and nothing that
        // produces it. I spent a whole analysis pass ruling out the obvious suspect by hand
        // (at the 25-note generate the freshest published frame was ~14 s old against the
        // camera's 6 s `freshnessWindow`, so no body reached the composer) and still cannot
        // say what DID move it. That is the #401 situation exactly, one layer over.
        //
        // FIVE VALUES, because the count has five independent drivers and naming fewer would
        // be the same partial answer dressed as an explanation:
        //   · `genre` — `MusicStyle` carries the `harmonicProfile` (progression length, chord
        //     tones per chord, `sustainedDrone`, `arpeggiated`) plus `chordArticulation` and the
        //     bass/pad rhythms, and those are what decide how many notes a bar holds. A genre
        //     change between two generates moves the count with nothing else changing.
        //     ⛔ THE FIRST VERSION OF THIS BULLET SAID "`MusicStyle` picks WHICH MELODY FUNCTION
        //     runs — `trapMelody` 3…6, `ambientMelody` 2…8, `dubMelody` another shape", and it
        //     is FALSE for every genre that ships. All three of those functions are retired
        //     (the founder removed the exposed melodies 2026-07-09, "zu laut und zu
        //     unnatürlich"); `BioComposer.compose`'s switch routes EVERY style, dubTechno and
        //     trap included, into `composeHarmonic`, and their own doc comments say "unused,
        //     reversible". Left as a correction rather than a silent rewrite because a reader
        //     chasing a count anomaly would have opened three dead functions and found numbers
        //     that never reach a take — CLAUDE.md files that as the expensive kind of stale.
        //   · `body` — 1 when `makeComposerInput` found a USABLE frame, 0 when it composed
        //     without one. Deliberately NOT the `bio=` of the visual line: that one asks
        //     `freshBio(maxAge: 5)`, this one is the composer's own per-source window (camera
        //     and BLE 6 s, watch/HealthKit 90 s, Oura 600 s). Two different questions that
        //     have looked like one number in every log so far.
        //   · `busy` — the autonomic density term, recomputed here from the SAME `input` the
        //     composer received, so it is equal to the composer's by construction rather than
        //     by hope. `musicalState` is pure and is the one place that term is defined.
        //   · `tScale` — the tempo thinning, which coarsens the arp step and the inner pulse
        //     gap once `densityScale` drops below 0.8. That happens above **109 BPM**, not the
        //     ~106 the comment at `BioComposer.tempoDensityScale`'s arp call site said: solving
        //     `(84/bpm)^0.85 = 0.8` gives 109.22. Both comments now say 109 — leaving one at 106
        //     would have put the repo in disagreement with itself over a number a reader uses to
        //     decide whether a take was thinned.
        //
        //   · `live=` — the Mood panel's Liveliness knob, which since #418 shifts the THRESHOLD
        //     both of the decisions above compare `busy` against (`BioComposer.densityThreshold`).
        //
        // ⛔ THE HISTORY OF THIS ONE BULLET IS WORTH MORE THAN THE BULLET. It shipped as `live=`,
        // was REMOVED hours later as a number that could not move the count, and is now back —
        // and both of those were right at the time. Removed because every read of
        // `mood.liveliness` sat in the callerless `ambientMelody` or inside
        // `if profile.leadDensity > 0`, and all 33 shipped genres set `leadDensity: 0.0`
        // (`Tests/CISmoke/LeadRoleAbsenceTests.swift` pins it) — a live value on a dead path,
        // which is the subtlest way this line can lie. Back because #418 gave it a reachable
        // reader in the same cycle. **Lehre: a driver list is only true for the commit it was
        // written in — the fix that makes a value matter has to walk back to the diagnostic.**
        //
        // ⚠️ AND `live=` IS NOT A DRIVER ON EVERY GENRE — say so rather than let a log reader
        // infer it. Both decisions it shifts sit behind `!sustained`, and 8 of the 16 offered
        // genres are `sustained: true`, INCLUDING the default `.selfObservation`. On those the
        // number prints and changes nothing. Registered as #419 (the sustained half); until that
        // lands, read `live=` together with `genre=`.
        //
        // ⚠️ BUILT AS ITS OWN STATEMENT, not folded into the breadcrumb literal below. That
        // literal already carried TEN interpolations before this one (count them with
        // `grep -o '\\(' ` on the line, not from memory — this file has paid for guessed
        // counts), three of them inline `String(format:)` calls, and #287 (`3379bb3`) turned
        // the BLOCKING gate red with an expression of exactly this shape — with no local
        // toolchain that costs a full CI round-trip to find out. The paragraph above the
        // `keyText` hoist says the same thing; this is that rule applied, not a new one.
        // ⛔ AND THE FIRST VERSION OF THIS BLOCK BUILT `densityText` AS A FIVE-TERM `+` CHAIN
        // — the exact shape the paragraph above forbids, written directly under the warning
        // against it. Each `+` is its own overload-resolution site; interpolation of already
        // typed `let`s is not. Every value is hoisted and typed first, then ONE literal.
        let genBusy = BioComposer.musicalState(coherence: input.coherence,
                                               hrvNormalized: input.hrvNormalized,
                                               heartRateBPM: Double(input.heartRateBPM)).busy
        let genScale = BioComposer.tempoDensityScale(bpm: BioComposer.tempo(for: input))
        let genreID: String = input.style.rawValue
        let bodyFlag: Int = frame == nil ? 0 : 1
        let busyText: String = String(format: "%.2f", genBusy)
        let scaleText: String = String(format: "%.2f", genScale)
        let liveText: String = String(format: "%.2f", input.mood.liveliness)
        let densityText: String =
            "genre=\(genreID), body=\(bodyFlag), busy=\(busyText), tScale=\(scaleText), live=\(liveText)"
        EchoelCrashLog.breadcrumb("generate[\(pendingGenerateReason)]: \(composition.notes.count) notes, playing=\(beatPlayer.pattern.isPlaying), key=\(keyText), tuning=\(tuningID), a4=\(a4Text), sinceLast=\(sinceText), rollMixGain=\(String(format: "%.2f", pianoRoll.mixGain)), vMax=\(String(format: "%.3f", vMax)), userMix=\(String(format: "%.2f/%.2f/%.2f", mixer.bass, mixer.pad, mixer.lead)), \(densityText)")
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
        let made = makeComposerInput(advanceEvolution: false)
        let base = made.input
        mazeBase = base
        mazeAppliedSeed = nil
        mazeBoard = BioVariationMaze.explore(base: base, count: 6)
        // #645: same statement group, same frame the input was built from. The card's sentence
        // names whose target density it ranked against, and a driver read anywhere else could
        // describe a different exploration than the one on screen.
        mazeDriver = BioExplanation.driver(for: made.frame)
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
        synth.apply(weatherToned(trim.trimmed(patch)))
        syncTouchSound()
    }

    /// The sky's TONE offset, on the same local copy and never written back (identical
    /// discipline to the rhythm trim above — `TimbreTrim.trimmed` multiplies, so a stored
    /// result would compound on every push).
    ///
    /// ⛔ WHY THIS EXISTS AT ALL — founder, 2026-08-01: "Wetter ist nicht bemerkbar bis jetzt
    /// oder?" He was right, and the reason was structural, not a matter of amount.
    /// `Param.warmth` promises "Warm weather brightens the TONE, cold darkens it", and its
    /// only wiring was `MoodProfile.darkness`, whose ONLY two readers in the whole engine are
    /// `mood.darkness > 0.6 ? -1 : 0` (`BioComposer`, the ambient octave and the pad voicing).
    /// A threshold, not a gradient — `MoodPreset.swift` records the same finding in its own
    /// words ("Two moods can therefore differ by 0.43 of darkness and produce the SAME
    /// notes" — quoted exactly; three files carried a tidied-up version of this sentence
    /// inside quotation marks, which is a small lie in the one place a reader trusts most). So the
    /// few hundredths weather moved did nothing at all unless they happened to cross 0.6, and
    /// then they moved a whole octave. Note also which word the label uses: TONE. The engine
    /// implemented REGISTER. This is the parameter the copy was always describing.
    ///
    /// It composes with the rhythm trim rather than replacing it: two independent, bounded,
    /// relative offsets on the same patch. Genre distances are preserved by both.
    private func weatherToned(_ patch: SynthPatch) -> SynthPatch {
        #if canImport(WeatherKit) && canImport(CoreLocation)
        guard weatherEnabled, let wx = weatherContribution else { return patch }
        let tone = wx.toneTrim(intensity: WeatherMood.Param.warmth.currentIntensity())
        guard tone != WeatherMood.ToneTrim.neutral else { return patch }
        // Reuses `TimbreTrim.trimmed` for the clamping rather than re-deriving it — that
        // method's rule ("a clamp bounds where the trim may PUSH a value, never where the
        // input was allowed to BE") took a correction to get right once already, and a second
        // copy is a second chance to get it wrong. Time factors stay 1: weather changes the
        // colour of a note, not its envelope.
        let asTrim = RoleRhythm.TimbreTrim(brightness: tone.brightness,
                                           cutoffFactor: tone.cutoffFactor,
                                           attackFactor: 1, releaseFactor: 1)
        return asTrim.trimmed(patch)
        #else
        return patch
        #endif
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
    ///
    /// ⭐ THE FORMAT TOKEN IS THE FIX, NOT DECORATION (founder 2026-08-13 on a v10.79.388 clip:
    /// *"Midi Export beim Klavier Button stimmt nicht, der will noch wav rausrendern"*). The
    /// MIDI export was CORRECT — the shared file in that clip is **435 bytes**, which is a
    /// Standard MIDI File and could not be a WAV by two orders of magnitude. What was wrong is
    /// that nothing on screen said so: BOTH exports built a byte-identical stem and differed
    /// only in the extension, which the iOS share sheet truncates away, and iOS's own subtitle
    /// for a `.mid` file is "Audioaufnahme" because the MIDI type conforms to `public.audio`.
    /// So the piano button rendered a correct MIDI file and presented it as an audio recording.
    /// That is the lying-control class this file names elsewhere, and the cheapest honest
    /// repair is in the NAME — the exporter never needed touching.
    ///
    /// ⚠️ BOTH sides get the token, not only MIDI. Tagging only the odd one out would leave the
    /// WAV reading "Audioaufnahme" with no format anywhere either (iOS truncates its extension
    /// too), so the pair would still be indistinguishable in the direction the founder was
    /// looking. Symmetric is also the only version a later reader cannot mistake for an
    /// oversight.
    private func shareStem(format: String) -> String {
        let raw = "\(session.sessionName(bpm: beatPlayer.pattern.tempo))"
            + "_\(style.displayName)_\(format.uppercased())"
        return raw.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>| "))
            .filter { !$0.isEmpty }.joined(separator: "-")
    }

    private func renamedForShare(_ url: URL) -> URL {
        let ext = url.pathExtension.isEmpty ? "wav" : url.pathExtension
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(shareStem(format: ext)).\(ext)")
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
            // The button is enabled on `hasComposed`. #622 closed the classic route to
            // "true with an empty roll" (open a lossy-decoded take), so this guard is
            // now the LAST line of defence, not the first — kept because any future
            // writer that arms the flag over an empty roll lands here. Silent return = a
            // control that looks like it worked. No alert — the sheet chain may not grow —
            // but the diag log must be able to say what happened.
            EchoelCrashLog.breadcrumb("MIDI export skipped: no notes in the roll")
            return
        }
        let data = MIDIFileExporter.exportCombined(
            notes: arrangedNotes, steps: [], accents: [],
            tempo: beatPlayer.pattern.tempo, bars: bars,
            keyRootPitchClass: rootIndex, keyIsMinor: scale.isMinorTonality)
        // Name carries key + tempo + tuning + genre AND the format, through the one builder the
        // WAV path uses (#416 — these two were byte-identical duplicates, which is exactly how
        // they came to be indistinguishable on screen). See `shareStem` for the device evidence.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(shareStem(format: "midi")).mid")
        do {
            try data.write(to: url, options: .atomic)
            share = ExportedFile(url: url)
            // A success breadcrumb, because the failure path already had one and the diag log
            // could therefore only ever report this control going WRONG. The founder's clip
            // showed a correct export being misread; the log has to be able to say "it wrote
            // N bytes of MIDI" rather than leaving the question to a share-sheet subtitle.
            EchoelCrashLog.breadcrumb(
                "MIDI export: \(data.count) bytes, \(arrangedNotes.count) notes, \(bars) bars")
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
            // #493 — BOTH tuning axes travel now. `a4Hz` always did; the tone system did not,
            // so a Maqām take reopened under a 12-TET instrument came back as 12-TET. Never
            // `nil` from HERE: a take this build writes always states what it was played in.
            // `nil` is reserved for files written before the field existed.
            a4Hz: session.a4Hz, toneSystemID: tuningID,
            // #275 slice 2 — the eight mood dials travel too. Slice 1 gave them persistence
            // at all; it was GLOBAL, so opening a take restored its genre, key, scale, tempo,
            // tuning, mode and patch and left whatever mood happened to be dialled in.
            // Never `nil` from HERE, for the `toneSystemID` reason one line up: a take this
            // build writes always states the mood it was composed with. `nil` is reserved for
            // files written before the field existed.
            moodFields: MoodStorage.fields(from: mood),
            artist: session.artistName,
            // #600 — the THIRD save door goes through the ONE voice-half definition.
            // Before this, a fresh capture travelled with a patch save but NOT with a
            // take (Save / autosave / Live Colabo) — the #593b check-4 asymmetry one
            // door over: whether "my saved take sounds like me" depended on which door
            // was used, and no player can see the difference. Same provenance and
            // strip semantics as the two patch doors (documented at the helper);
            // Live Colabo therefore shares the voice WITH its label, which is the
            // share-label law, never anonymously.
            patch: patchCarryingLiveVoice(currentPatch), notes: pianoRoll.notes,
            // #217 — the composer's OWN bars travel with the take, so a Mix fader can
            // re-bake it after an open instead of composing a different piece. `nil` when
            // this session has not composed (`lastRawTake` is `@State`, nil until the first
            // `generate()`), which is the honest reading and exactly what a legacy file says.
            // Built through `Project.RawTake` so the bars can never be saved without the
            // genre they were composed in — see `rebalanceTake()`'s "`take.genre`, NOT
            // `style`".
            rawTake: lastRawTake.map { Project.RawTake(styleRaw: $0.genre.rawValue, bars: $0.bars) },
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
    ///   ⛔ #622b: the justification that stood here — "`hasComposed` … is set `true`
    ///   unconditionally by `open()` and is never set back to `false` anywhere" — became
    ///   FALSE the day #622 made open()'s write conditional (`!pianoRoll.notes.isEmpty`,
    ///   which can also set it back to false mid-session). The two-condition guard STAYS
    ///   anyway, for the #343 reason: it is this function's own defence, not a mirror of
    ///   open()'s — a future writer that arms the flag over an empty roll (the importMIDI
    ///   near-miss the #622 review caught) must not overwrite the single autosave slot.
    ///   `exportMIDI()` already says the same thing about `hasComposed` at its own
    ///   empty-notes guard; I did not read it.
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

    /// ⭐ RESCUE BEFORE REPLACE. Nearly every line below overwrites the live take — style, key,
    /// scale, patch, NOTES, tempo, A4 — and until this call there was no prompt and no snapshot
    /// anywhere on the path. Tapping a row in the Open list silently destroyed whatever the
    /// body had just played. `autosaveTake()` existed and was the obvious rescue, but it only
    /// fired on a scene-phase departure (`.onChange(of: scenePhase)`), so it covered
    /// backgrounding and covered nothing the user did inside the app.
    /// (⛔ "EVERY line below" is what the first version wrote, and the very next statement is a
    /// local `let openStyle`. A checkable sentence has to be checkable-TRUE — that is the norm
    /// this file enforces on other people's comments.)
    ///
    /// REVERSIBLE BEATS CONFIRMED, and that is why this is not a `.confirmationDialog`. All a
    /// prompt could ever do is tell the user what they are about to lose — it could not give it
    /// back.
    ///
    /// (⛔ The first version added "a prompt would add a presentation modifier to a chain the
    /// black-screen law says must not grow". Checkable, and false at this location: the row that
    /// calls this sits in `openSheet`, presented as `.sheet(isPresented: $showOpen) {
    /// AnyView(openSheet) }`, so its type never reaches the body's aggregate type and a dialog
    /// in there would leave the counted 14 untouched. The law is about modifiers appended to
    /// `EchoelStudioView.body` itself. The same false half was written into the randomize and
    /// preset-delete rationales and is struck in all three — a borrowed law that does not reach
    /// the code makes a correct decision unfalsifiable, which is how the wrong one survives next
    /// time.)
    ///
    /// ⚠️ IT IS NOT FREE, WHICH THE FIRST VERSION CLAIMED TWICE ("costs no UI at all"). What
    /// costs nothing is the PRESENTATION chain — no modifier, no slot. The call itself runs
    /// `ProjectStore.save` → `persist()` → `AppGroupStore.save`: a synchronous pretty-printed
    /// encode of the WHOLE library plus a protected atomic write, on the main actor. The
    /// scene-phase caller weighed exactly that cost in its own comment; this slice moved it
    /// onto every project open without restating it. Acceptable per tap — the same tap already
    /// re-applies the patch, re-pushes tuning and re-stamps every FX chain — but it is a
    /// per-GESTURE budget, not a free one, and a third caller has to weigh it again.
    ///
    /// ⚠️ AND IT MUST NOT FIRE WHEN THE ROW BEING OPENED **IS** THE AUTOSAVE. There is exactly
    /// ONE reserved slot (`Project.autosaveSlotID`, matched by id in `ProjectStore.save`), so
    /// recovering from it would first overwrite it with the very state the user is discarding.
    /// The open itself would still succeed — `p` is a value copy, already read — but the
    /// recovery row would now hold the discarded take, i.e. a second tap would undo the
    /// recovery. Skipping the write there keeps the row meaning one thing.
    ///
    /// ⚠️ HONEST LIMIT — WHAT COMES BACK IS LESS THAN THE TAKE, and the first version sold the
    /// slot as an undo without saying so. `currentProject()` stores `pianoRoll.notes`, which is
    /// the SOUNDING bar and not the arrangement: `generate()` builds `loopBars` distinct bars
    /// (default eight) and the roll cycles them, while `Project` holds one flat `notes` array.
    /// So the recovery returns one bar in eight — whichever was staged at the moment of the tap.
    /// ⛔ THE CLAUSE THAT FOLLOWED IS HALF RETRACTED BY #623. It read: "and `pianoRoll.load(_:)`
    /// clears `arrangementBars`, so the cycling does not come back either." `load(_:)` still
    /// clears, but `open(_:)` now RE-INSTALLS the arrangement from `Project.rawTake` — which
    /// `currentProject()` has written since #217 — so a slot saved after a generate DOES come
    /// back as all `loopBars` bars, cycling and exporting in full. The one-bar limit now applies
    /// only where `rawTake` is absent: a legacy row, or a session that never composed. Stating
    /// it unconditionally would undersell the recovery, which is the mirror of the overselling
    /// this very paragraph was written to stop. Hand-dialled FX is not in it at all (`Project` carries only `fxCharacterRaw`,
    /// and the loop below re-stamps every chain from the character), and neither are the mixer
    /// levels — `MixerStore` persists each role straight into `UserDefaults`, so they are a
    /// console setting rather than a take property and appear in no `Project` CodingKey.
    ///
    /// ⛔ THIS CLAUSE NAMED `presetIndex` AND `lockedBPM` AS THINGS THAT DO NOT COME BACK, and
    /// both were wrong — checked while writing #495, against lines this same function contains.
    /// `lockedBPM = loadedTempo` runs a few statements down, so the locked tempo IS restored
    /// (derived from the take's `bpm`, which is what the lock wrote into the clock in the first
    /// place); and `presetIndex = -1` is an explicit, deliberate write ("a saved patch is
    /// custom"), not an omission. The distinction matters more since #494: now that the LOCK
    /// itself travels, a reader who believed this clause would conclude the lock's TEMPO does
    /// not — and might "restore" a number that is already there, from a field `Project` has
    /// never had. A named omission that is not one is worse than no list.
    ///
    /// Persisting the raw bars is the real answer and is its own task, already
    /// named at the re-seed site. None of this is new — manual Save has the same hole — but
    /// this is the slice that markets the slot as a way back, so it is the slice that owes the
    /// limit.
    ///
    /// ⚠️ Honest limit 2: ONE slot, not an undo stack. Opening twice in a row leaves only the
    /// state from just before the second open — and that second write is redundant by
    /// construction, because after an open the live state IS the project that was opened and
    /// already sits in the library under its own id. Nor is the rescue "one tap away", as the
    /// first version put it: it is chip → Save & Export → Open → the Autosave row.
    /// `autosaveTake()`'s own `guard hasComposed, !pianoRoll.notes.isEmpty` is load-bearing for
    /// this caller too: without it, opening a project while the roll is empty would write an
    /// EMPTY take over a good recovery point, which is the exact trap that guard was added for.
    private func open(_ p: Project) {
        if p.id != Project.autosaveSlotID { autosaveTake() }
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
        patchBeforeSoundChange = nil    // wholesale replace — see the property's doc
        presetIndex = -1                // a saved patch is "custom", not a factory preset
        // #275 slice 2 — RESTORE THE MOOD, and CONDITIONALLY, which is the opposite of the
        // `lastRawTake` line below. The asymmetry is deliberate and both halves are argued at
        // `Project.moodFields`: leaving stale RAW BARS in place is an active bug (the next
        // fader move re-bakes them over the take just opened, attributing them to it), while
        // nothing re-bakes from mood — it is an input to the NEXT compose, so leaving the
        // instrument's current dials alone on a take that states none is honest rather than
        // stale. `?? MoodProfile()` here would flatten eight dials the player had set on
        // every legacy take, which is inventing a fact about a file (#424/#426/#433/#461).
        //
        // ⚠️ THIS ALSO PERSISTS, via the `.onChange(of: mood)` installed in slice 1 — exactly
        // like `style`, `rootIndex` and `scale` above, which are all `@AppStorage`-backed and
        // adopt the opened take's value as the instrument's. That is the intended reading of
        // "open a take": you continue from it.
        if let m = p.mood { mood = m }
        session.adopt(key: p.key)
        session.a4Hz = p.a4Hz
        applyConcertPitch(p.a4Hz)
        applyTakeSound(p.patch)
        pianoRoll.load(p.notes)
        // #217 — RESTORE THE RE-BAKE SOURCE. One TOTAL assignment, deliberately.
        //
        // Until this line `lastRawTake` was `@State`, i.e. nil on every opened project, so
        // `rebalanceTake()` took its documented fallback and `recomposeIfRunning()` handed
        // the listener a NEW piece when they moved a Mix fader. The fader was a level
        // control everywhere except on a saved take, which is the one place a level control
        // is most obviously what you reach for.
        //
        // ⚠️ ASSIGNING UNCONDITIONALLY IS THE LOAD-BEARING PART, and it is why the
        // three-way decision lives on `Project.rebakeSource` rather than in an `if let`
        // here. Anything that leaves this state untouched on a take with no usable raw
        // bars would keep the SESSION's bars in place, and the first fader move would
        // re-bake THAT piece over the take just opened — a defect this slice would have
        // created, worse than the one it fixes. `rebakeSource` returning `nil` (legacy
        // take, unknown genre, empty bars) therefore CLEARS, by construction.
        //
        // ⛔ THE ⭐ THAT STOOD HERE IS RETRACTED BY #623, and it is retracted rather than
        // deleted because it named the exact trade this slice decided differently. It read:
        // "THE OPEN PATH ITSELF IS UNCHANGED: `pianoRoll.load(p.notes)` above still loads
        // exactly the notes that were saved, so opening a take sounds bit-identical to
        // before. What changes is the FIRST FADER MOVE… That the arrangement (all `loopBars`
        // of it, not the single sounding bar `Project.notes` holds) comes back at that
        // moment is a side effect." Every clause was true when written. But "comes back at
        // that moment" is precisely the defect the Ultra-Audit ranked third: until a fader
        // was nudged, `arrangementBars` stayed EMPTY, so `arrangementForExport()` took its
        // `count > 1` fallback and the founder's eight-bar take exported as ONE bar — and
        // that bar was `IntroAttenuation`'s softened opening, because that is what
        // `Project.notes` holds. Short AND quiet, reported as success. The arrangement was
        // never a side effect of the fader; the fader was just the only door to it.
        lastRawTake = p.rebakeSource
        // #623 (Ultra-Audit MIDI Rank 3) — INSTALL THOSE BARS ON THE ROLL, so an opened
        // take IS its arrangement and not merely the bar that happened to be sounding when
        // it was saved. Same machinery as the fader path (`rebalanceTake()`): re-glue each
        // raw bar at the CURRENT mixer, then hand the whole set to the roll.
        //
        // `loadArrangement`, NOT `rebakeArrangement`: the latter's contract is "the same
        // notes at new LEVELS" and it is reached from a level control. This is an INSTALL,
        // and the install verb is the one that zeroes `arrangementPhaseOffset` and — when
        // stopped — restages bar 0. Stopped, the two are byte-identical anyway
        // (`rebakeArrangement` delegates); using the honest verb costs nothing and keeps
        // one word per operation (#616).
        //
        // ⚠️ `count > 1` IS THE WHOLE CONDITION, not a nil-safety formality. A one-bar
        // rawTake gains nothing here — `arrangementForExport()` returns `(notes, 1)` either
        // way — while `loadArrangement`'s own `guard bars.count > 1` would send it down
        // `load(_:)` and REPLACE the saved sounding notes with bars re-glued at whatever
        // the faders read now. For those takes the retracted ⭐ above still holds exactly:
        // opening them is bit-identical. The change is confined to the takes that have an
        // arrangement to lose.
        //
        // ⏱ ORDER MATTERS AND IS GUARDED: this sits ABOVE the `hasComposed` write below,
        // which is a SNAPSHOT of `pianoRoll.notes` (#622/#622b). Installing after it would
        // leave a take whose `notes` decoded empty but whose `rawTake` survived sitting
        // grey with a full, exportable arrangement loaded — the state #622b had to rescue
        // with a Mix-fader nudge.
        //
        // ⛔ #623b (review W1): the sentence that closed this paragraph — "Here that case
        // now opens armed and correct" — was FALSE ON THE PLAYING BRANCH, without saying
        // so. `loadArrangement(playing: true)` writes `arrangementBars` and `pendingNotes`
        // and deliberately does NOT touch `notes` (the sounding bar is never cut), so the
        // flag below still reads `!p.notes.isEmpty` exactly as it did before #623. The
        // rescue is real when STOPPED — the ordinary case for opening a take — and the
        // running case is unchanged, not fixed. An unqualified claim here is the kind
        // that stops the next reader from noticing the branch at all.
        //
        // ⚠️ #623b (review W4) — `bars.count > 1` GUARDS THE OUTER ARRAY, AND THAT WAS NOT
        // ENOUGH. `Project.rebakeSource` only requires `!rawTake.bars.isEmpty`, while
        // `RawTake`'s decoder keeps bar POSITIONS and drops unreadable notes INSIDE a bar
        // — the same lossy mechanism #622 exists for. So `[[], [x], [y]]` is representable,
        // and the stopped branch would then stage `IntroAttenuation.apply(bars[0])` = `[]`
        // into `notes`, making `hasComposed` FALSE for a take that opened ARMED before
        // #623. The install could disarm a take it had just made exportable — a strict
        // regression, in the one method this slice was meant to repair. Requiring a
        // non-empty FIRST bar is the smallest condition that makes the stopped branch
        // incapable of emptying the roll; a take whose bar 0 really is a rest keeps its
        // pre-#623 behaviour, which is the conservative half of the trade and is stated
        // here rather than silently chosen.
        if let take = p.rebakeSource, take.bars.count > 1,
           take.bars.first?.isEmpty == false {
            pianoRoll.loadArrangement(take.bars.map { mixGlued($0, genre: take.genre) },
                                      playing: running && beatPlayer.pattern.isPlaying)
        }
        beatPlayer.pattern.load(steps: p.drumSteps, accents: p.drumAccents)
        beatPlayer.pattern.setTempo(p.bpm, source: .user)
        // Everything that mirrors tempo must follow a loaded take, or the visual/OSC
        // frame keeps the OLD project's BPM (Finding F). Route through the authoritative
        // clock value (clamped) so all readers show one number. The click is NOT pushed
        // here — it subscribes to the transport and has already followed the setTempo above.
        let loadedTempo = beatPlayer.pattern.tempo
        pianoRoll.musicalTempoBPM = loadedTempo
        lockedBPM = loadedTempo
        // #494 — AND THE LOCK ITSELF, which is the half that did not travel. `Project.modeRaw`
        // has been WRITTEN since this format existed (`currentProject()` stamps
        // `ComposerMode(locked: lockBPM).rawValue`) and `Project.mode` has ZERO readers in
        // `Sources/`: nothing ever restored it. So the line above put a Loop take's tempo back
        // into `lockedBPM` while the instrument stayed in Flow — and in Flow that number is not
        // even consulted (`makeComposerInput` passes `lockedTempo: lockBPM ? lockedBPM : 90`,
        // and `BioComposer.tempo(for:)` follows the heart on `.flowFree`). Half a decision
        // travelled; the half that decides whether it matters did not. Ship gate 3 is "Modi
        // (Flow + Loop)", so this is that gate's save/open leg.
        //
        // ⛔ READ FROM `p.modeRaw`, NEVER FROM `p.mode` — the tempting one-liner is the bug.
        // `Project.mode` is `ComposerMode(rawValue: modeRaw) ?? .studioLocked`, and the decoder's
        // own fallback for an absent key is `""`. A take saved before this field meant anything
        // therefore reads as `.studioLocked` through the accessor, so `lockBPM = (p.mode ==
        // .studioLocked)` would LOCK the instrument on every legacy take — against a persisted
        // default of `false`, i.e. inventing a fact about a file, the same trap #493 avoided one
        // field over. Going through `ComposerMode(rawValue:)` makes "this take states no mode"
        // representable, and then this line deliberately does nothing.
        //
        // ⚠️ Side-effect free, and that is measured, not assumed: `git grep` finds no
        // `onChange(of: lockBPM)` anywhere under `Sources/`, and the binding in
        // `WorkspaceView.modeBinding` reacts only when the Flow|Loop Picker is DRIVEN — writing
        // the shared `@AppStorage` key from here goes through its `get`. Nothing posts
        // `.echoelCompositionEdited`, which is exactly right: `open(_:)` loads the take's SAVED
        // notes and must not recompose them away (the same reason the root/tuning writes below
        // stay silent).
        if let savedMode = ComposerMode(rawValue: p.modeRaw) {
            lockBPM = (savedMode == .studioLocked)
        }
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
        // #622 (Ultra-Audit MIDI Rank 1, founder: "Midi Export geht nicht"): this line
        // was an unconditional `hasComposed = true`, and `Project.notes` can decode
        // EMPTY (lossy decode drops every unreadable note). That armed the whole
        // composed-only chrome — the pianokeys export tile above all — for a take with
        // nothing in the roll: `exportMIDI()` then hits its empty guard and returns
        // with only a breadcrumb, the documented "control that looks like it worked".
        // Worse, the trap self-propagated: Save is also `hasComposed`-gated and writes
        // `pianoRoll.notes`, so an empty take could be saved under a real name and
        // re-opened, forever. Honest flag = the first-run explainer comes back and
        // says what to do (compose), instead of a bright tile that eats the tap.
        // `generate()` keeps its unconditional set — it always loads the bars it just
        // composed. The autosave path has carried this exact second condition since
        // #204 (`guard hasComposed, !pianoRoll.notes.isEmpty`); this is the same law
        // at the third writer.
        hasComposed = !pianoRoll.notes.isEmpty
        // #493 — RESTORE THE TAKE'S TONE SYSTEM, and note the `if let`: it is the whole
        // decision, not a nil-safety formality. A take saved by this build always states one,
        // so opening a Maqām loop puts the instrument back into Maqām — the second tuning
        // axis finally behaving like `a4Hz` three statements up, which has travelled since
        // this format existed. A take saved BEFORE #493 states nothing, and then this line
        // does nothing on purpose: the player's current choice is the only real information
        // in the room, and overwriting it with a default would be inventing a fact about a
        // file. `applyTuning()` below is the single place that pushes the table to every
        // voice, so this only has to move the id.
        if let savedToneSystem = p.toneSystemID { tuningID = savedToneSystem }
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
        // #622b (review W3): "= true" here rested on a false premise — a SUCCESSFUL
        // import of a drums-only SMF yields zero melodic notes (ch10 is excluded, see
        // below), which would have armed the chrome over an empty roll: Rank 1
        // verbatim, through the sanctioned writer. Honest like the other loaders.
        // (This door is currently setterless — the fix is for the day the slot is
        // reused, which the repo documents as headroom.)
        hasComposed = !placed.isEmpty
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
/// is right". The two bare callers WERE `mixerPanel` and `weatherRow` — NOT `sessionPanel`,
/// which merely rendered `weatherRow` and contained no grid at all; someone acting on that name
/// would have grepped `sessionPanel` and found nothing. (Since #359 step 3 that grep finds
/// nothing for a SECOND, unrelated reason — the declaration is deleted. The sentence is kept in
/// the past tense it was already written in, because the lesson is about naming a container from
/// file order, not about which containers exist today.) And only `mixerPanel`'s grid sat
/// directly in `EchoelPanel`'s 14 pt stack: `weatherRow`'s sat in its own local
/// `VStack(alignment: .leading, spacing: 8)`. So NEITHER matched 10 by design. The honest reason
/// the default is 10 is narrower and sufficient: those two shipped at 10 and changing it would
/// re-space panels nobody asked to change.
///
/// ⚠️ SINCE #359 STEP 2 THERE IS ONLY ONE BARE CALLER: `mixerPanel`. `weatherRow`'s grid held the
/// Sound and Image cards side by side; the Image card moved to `visualPanel` and a grid with one
/// card left has nothing to arrange, so it went too. The default still may not change — but the
/// reason is now a single panel, not two, and anyone reading "two callers" anywhere else in the
/// repo is reading a sentence this commit invalidated.
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

    /// ⛔ ACCESSIBILITY SIZES GET ONE COLUMN, whatever the width. The rule stands; its ORIGINAL
    /// justification does not, and leaving that standing would tell the next reader a defect is
    /// open that has been closed. What stood here: `EchoelValueField`'s box is a HARD
    /// `.frame(width:)` driven by `@ScaledMetric(relativeTo: .body) = 150`, so at the top sizes
    /// it wants more than half a landscape phone and two columns would draw over each other —
    /// "(Portrait already overflows at the top sizes today; that is a separate, pre-existing
    /// defect of the fixed box width and is NOT fixed here.)"
    ///
    /// **#353e IS that fix.** Above the accessibility threshold the field now drops the pin
    /// entirely and puts its label above the box. So the reason for one column is no longer
    /// "the box is too wide to share" but the opposite: a stacked label-over-box row WANTS the
    /// full width, and halving it is exactly the wrong move for the user who most needs it.
    /// `EchoelStudioView` is deliberately not Dynamic-Type-clamped and `StudioZoom` reaches
    /// `.accessibility5`, so the threshold is genuinely reachable here.
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
    /// Called when the fader is released — the host re-pushes the take patch so a
    /// patch-side influence (today: Warmth's tone offset) is heard while you set it.
    let onCommit: () -> Void
    @AppStorage private var intensity: Double

    init(param: WeatherMood.Param, onCommit: @escaping () -> Void = {}) {
        self.param = param
        self.onCommit = onCommit
        _intensity = AppStorage(wrappedValue: param.defaultIntensity, param.mixKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            EchoelValueField(label: param.label, value: $intensity,
                             range: 0...1, unit: "", decimals: 2, onCommit: onCommit)
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

    /// ⚠️ AN ICON-ONLY TILE SINCE #482 (founder: *"im selben Button Format in eine Reihe unter
    /// dem Play etc"*). The sentence this control used to WEAR did not disappear — it is the
    /// `accessibilityLabel` here, and it is rendered as text by `KeepLastAvailabilityNote` in
    /// the Save & Export panel, next to the loop-length picker that produces it. One copy of
    /// the wording feeds both (`KeepLastCopy`), so the chip and the sentence cannot disagree.
    ///
    /// ⚠️ IT STAYS A SEPARATE `struct` FOR THE FREEZE LAW, not for tidiness: it reads
    /// `pattern.tempo` in its OWN body. Inlined into `quickActionRow` that read would land in
    /// `EchoelStudioView.body`, which hosts every `.menu` Picker in the instrument.
    var body: some View {
        let bpm = pattern.tempo
        let fits = LoopExporter.canKeepLast(bars: bars.rawValue, bpm: bpm)
        // The dim state must track `.disabled` EXACTLY. A full-brightness chip that is inert
        // is the same lie in a quieter register — it just moves the disappointment to the tap.
        //
        // ⛔ AND IT DID NOT, FOR AS LONG AS THIS COMMENT HAS EXISTED — the divergence was on
        // `isExporting`: `live` was `isExporting || (fits && hasComposed)`, so during a take
        // the chip was lit AND `.disabled(true)`. It was COVERED rather than harmless: the old
        // control rendered `busyLabel` ("Recording loop…") as visible text, so full brightness
        // read as "busy", not "tappable". #482 replaced that text with a glyph and uncovered it.
        // Now it is the exact negation of the `.disabled` expression below — one definition,
        // not two that happen to agree in three of four states. (Found by the #482 reviewer.)
        let inert = isExporting || !hasComposed || !fits
        let live = !inert
        Button(action: action) {
            EchoelIconTile(systemImage: "clock.arrow.circlepath", expands: true, enabled: live)
        }
        .buttonStyle(.plain)
        .disabled(inert)
        .accessibilityLabel(KeepLastCopy.title(bars: bars, bpm: bpm, isExporting: isExporting,
                                               hasComposed: hasComposed, busyLabel: busyLabel))
        .accessibilityHint(fits
            ? "Keeps the last bars you just heard as a WAV loop, without replaying them"
            : "This length is longer than the 30 second capture buffer at the current tempo")
    }
}

/// The sentence the keep-last chip can no longer wear (#482), rendered where the loop-length
/// picker that decides it already lives. Its own `struct` for the same freeze reason as the
/// button: `pattern.tempo` is read HERE, not in the panel's enclosing body.
///
/// ⛔ THE FIRST VERSION PASSED `isExporting: false, busyLabel: ""` AND NO `hasComposed`, which
/// broke the one property it exists for. The commit that added it claimed "one wording
/// definition feeds the chip and the sentence, so they cannot disagree" — they did, in two
/// states at once: mid-take the chip's VoiceOver label read "Recording loop…" while this line
/// still read "Keep last 8 bars (just played)", and on a FIRST RUN it said "(just played)"
/// with nothing ever played, four rows under a hint explaining that nothing has. One
/// definition with two call sites that feed it different facts is not one definition (#416).
/// Both are now forwarded, so the sentence is the chip's label rendered as text.
private struct KeepLastAvailabilityNote: View {
    let pattern: PatternEngine
    let bars: LoopBarLength
    let isExporting: Bool
    let hasComposed: Bool
    let busyLabel: String

    var body: some View {
        Text(KeepLastCopy.title(bars: bars, bpm: pattern.tempo, isExporting: isExporting,
                                hasComposed: hasComposed, busyLabel: busyLabel))
            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// ONE wording for "can we keep the last bars", read by the chip (as its VoiceOver label) and
/// by the panel note (as visible text). Two spellings of the same refusal is the #416 shape,
/// and the refusal is the half a user actually needs.
private enum KeepLastCopy {
    static func title(bars: LoopBarLength, bpm: Double,
                      isExporting: Bool, hasComposed: Bool, busyLabel: String) -> String {
        if isExporting { return busyLabel }
        if LoopExporter.canKeepLast(bars: bars.rawValue, bpm: bpm) {
            // ⛔ "(just played)" WAS UNCONDITIONAL AND SO WAS A FALSE STATEMENT ON EVERY FIRST
            // RUN — rendered four rows under the hint that explains nothing has played yet.
            // On the chip it was covered (the button was `.disabled`, so no one read the label
            // as a claim); #482 rendered the same sentence as free-floating prose and uncovered
            // it. The tempo refusal below is checked FIRST on purpose: it is true whether or
            // not anything has played, and it is the more useful half.
            return hasComposed ? "Keep last \(bars.label) (just played)"
                               : "Keep last \(bars.label) — once something has played"
        }
        // Name a length the PICKER ACTUALLY OFFERS. The raw ring capacity (14 bars at
        // 120 BPM) is not a `LoopBarLength` case, so naming it would send the user hunting
        // for a segment that does not exist — a refusal that lies while refusing.
        // `nil` only when the tempo is unusable; then point at the door that does work.
        //
        // ⛔ "use Record above" WAS TRUE UNTIL #482 AND IS NOT ANY MORE. Record is no longer
        // above this text — it is the first tile in the row under the transport. A refusal
        // that redirects to a control by its old POSITION is the class this file keeps
        // retracting, so it names the control instead of pointing at a place.
        guard let keepable = LoopExporter.longestKeepable(bpm: bpm) else {
            return "Keep last: unavailable — use the Record tile instead"
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
                Text("Music → colour").font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.text)
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

/// #277 — the door that arms `BioReactiveSynthVoice`, the one voice this app describes as
/// "silent until user-armed" and which nothing could arm.
///
/// ⭐ WHAT ARMING ACTUALLY DOES, said the way the row says it rather than the way the task
/// title said it. The task was filed as *"breath plays the synth is not switchable on"*, and
/// that is only the SECOND half. `arm()` is two statements: `isArmed = true` and `playNote()`.
/// So the voice sounds a HELD tone immediately, and its timbre keeps following the body
/// through `applyLatestIfFresh` (coherence → cutoff · brightness · harmonicity · noise;
/// HRV → brightness; heart rate → vibrato; breath phase → the amplitude swell) —
/// (⛔ "· reverb" struck here too, #546/#561: the write lands in a convolution stage whose only
/// read is gated on `EchoelDDSP.useConvolutionReverb`, `false` with no writer in `Sources/`.
/// The user-facing row lost the word in #546; this doc block kept it, which is how a retracted
/// claim comes back — the next reader takes it from the nearest comment.)
/// that path runs whether or not any breath ONSET ever arrives. Only when
/// `BioEventGraph` emits `.breathInhaleOnset` / `.breathExhaleOnset` does breath take over the
/// envelope (`consumeBioEventsIfFresh`).
///
/// ⛔ SO THE OBVIOUS LABEL WOULD HAVE BEEN A LYING CONTROL, and this is the whole reason the
/// row has two sentences instead of one. Naming it "Breath plays the synth" promises that the
/// breath opens and closes it — and on this app's measured reality that is usually false:
/// `PolarH10BioPublisher` and `FaceExpressionBioPublisher` write the literal `breathRate: 0`
/// ALWAYS (neither derives respiration), and `CameraRPPGBioPublisher` withholds breath below
/// its confidence floor (#497 measured all three). With no onsets, nothing ever closes the
/// envelope: the "breath" control would be a permanent drone. That is the class this repo
/// keeps paying for — #435's caption promised silence, #480's hint promised sliders, #491's
/// box promised a pulse. The row therefore states the HELD tone first and the breath gating
/// second, conditional on breath actually being measured.
///
/// ⚠️ AND THE DRONE IS STOPPABLE, which is what makes shipping it honest rather than reckless:
/// the toggle itself, and `panicAllNotesOff()`, which has listed `bioVoice` since #160/#168.
/// ⭐ That entry becomes LOAD-BEARING for the first time here. Until this row, the only way to
/// open this voice's envelope was an external MIDI note-on, so the panic's inclusion of
/// `bioVoice` guarded a path most users could not reach. It now guards the one control in the
/// app that can hold a tone indefinitely. `TheBreathVoiceHasADoorTests` pins it for that
/// reason, not for tidiness.
///
/// ⚠️ NOT PERSISTED, deliberately. `isArmed` has no `UserDefaults`/`@AppStorage` writer and
/// must not get one: a persisted arm would mean the app sounds a held tone on the next launch,
/// before the user has touched anything — a worse first-run than the silence #159 fixed.
/// Arming is a performance act, not a setting.
@MainActor
private struct BreathVoiceRow: View {
    @Environment(BioReactiveSynthVoice.self) private var voice
    @Environment(EngineBus.self) private var bus

    var body: some View {
        // `usableBio()` and not raw `bus.latestBio`: the question this row asks is "is breath
        // ARRIVING", which is exactly the per-source freshness question (#499/#507). A frozen
        // frame would otherwise keep claiming breath long after the finger left the lens.
        // #648: STILL ONE call — the hint and the caption now both come from THIS frame
        // instead of the hint being a fixed string, so the row gained honesty and no read.
        // ⛔ The first draft of this comment said "ONE call, not two" and cited #646's straddle.
        // Measured on the parent: this row already made exactly one call (`breathIsMeasured`),
        // and so did `AutoModeRow`. There was no straddle here to close. Reaching for the
        // previous slice's lesson and fitting the facts to it is the failure this family keeps
        // paying for in miniature — the mechanism has to be measured, not recognised.
        let frame = bus.usableBio()
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { voice.isArmed },
                                 set: { $0 ? voice.arm() : voice.disarm() })) {
                Text("Body voice")
                    .font(EchoelTheme.font(12, .semibold))
                    .foregroundStyle(EchoelTheme.text)
            }
            .toggleStyle(.switch)
            .tint(EchoelTheme.accent)
            .frame(minHeight: 44)
            .accessibilityHint(BioPanelRowCopy.breathVoiceHint(for: frame))
            Text(BioPanelRowCopy.breathVoiceCaption(for: frame))
                .font(EchoelTheme.font(10))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// #608 Scheibe 1 — the Auto-mode door („optionaler Automodus … sanft intervenieren").
/// A plain Toggle in `bioPanel`, the #603 `guideVisible` shape: ZERO presentation
/// modifiers, reached through `dropdownContent`, chain census untouched (14/16).
///
/// ⚠️ A LEAF struct for the 10.76.41/50 reason `BreathVoiceRow` states above: it reads
/// `bus.usableBio()` (~1 Hz) so only this row churns, never the Picker-hosting root.
///
/// ⚠️ NOT A LYING CONTROL (#135/#164/#227 class): with no running bio source the
/// toggle is DISABLED and the caption says why — an enabled switch that audibly does
/// nothing would be the exact defect this register documents. The caption names ONLY
/// channels a producer actually feeds today (coherence · HRV · heart rate — #496:
/// breath depth, LF/HF and any "trend" have no producer and may not be promised).
/// What it steers: the mood dials (darkness · liveliness · tension) through the same
/// crossfade the weather influence uses, over bars. Tempo is NEVER steered (T1/T2 —
/// the Flow-Servo remains the only bio→clock path).
@MainActor
private struct AutoModeRow: View {
    @Environment(EngineBus.self) private var bus
    @AppStorage(StudioDefaultKeys.autoMode.key) private var autoMode = StudioDefaultKeys.autoMode.value

    var body: some View {
        // #648: still ONE call, now feeding the disable, the hint AND the caption — the hint
        // was a fixed string before. See `BreathVoiceRow` for why this is not #646's straddle.
        let frame = bus.usableBio()
        let bioRunning = frame != nil
        // ⛔ A `let caption: String` + `if let frame { caption = … } else { … }` STATEMENT stood
        // here first. A `var body: some View` is a `@ViewBuilder` context, so an `if` statement
        // in it is transformed into VIEW building; branches that assign to a variable instead of
        // producing views are the #643 class of compile failure, and there is no local compiler
        // to find it. A reviewer confirmed the measurement: sweeping every `Sources/` file, NO
        // `var body: some View` in this repo contains an uninitialised `let` followed by branch
        // assignment — all 125 instances of that shape sit in ordinary functions.
        // ⛔ The replacement was a ternary over `BioPanelRowCopy.autoModeCaption(synthetic:)`
        // with the nil sentence stranded HERE — and that `Bool` was the #644 defect returning:
        // "reachable only with a frame in hand, so two states, not three" is true of today's
        // caller and is exactly the argument #644 lost. The caption now takes the frame like its
        // three siblings and owns all three sentences, so this row renders one call.
        // #616b lives on inside that function: the nil branch used to say "touch and hold the
        // pulse display", teaching the long-press three rows BELOW the visible "Bio source" row
        // #616 put in this same panel. Two captions in one panel disagreed on the route.
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $autoMode) {
                Text("Auto mode")
                    .font(EchoelTheme.font(12, .semibold))
                    .foregroundStyle(EchoelTheme.text)
            }
            .toggleStyle(.switch)
            .tint(EchoelTheme.accent)
            .frame(minHeight: 44)
            .disabled(!bioRunning)
            .accessibilityHint(BioPanelRowCopy.autoModeHint(for: frame))
            // #608b: the sentence names the CONDITION — between the hysteresis bands
            // Auto mode deliberately steers nothing, and a caption promising
            // unconditional steering would be the Weather-"nicht bemerkbar" class.
            Text(BioPanelRowCopy.autoModeCaption(for: frame))
                .font(EchoelTheme.font(10))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// EchoelVoice #592b — the capture door ("Voice timbre"). A LEAF on purpose:
/// `controller.progress`/`hearingYou` move at up to ~12 Hz during a take, so only this
/// row may observe them (10.76.41/50 — the panel passes the reference and reads no
/// observable property). Buttons, not a numeric field — the `EchoelValueField` law
/// governs NUMERIC parameters; a capture has none.
///
/// ⚠️ THE CAPTURE STATE IS NOT PERSISTED, same law as `BreathVoiceRow` above: arming a
/// capture is a performance act. The applied PROFILE persists exactly two ways — the
/// player saves it into a patch (#593a/b) or into a take (#600, the project door),
/// both through the ONE definition `patchCarryingLiveVoice`. ⛔ The sentence that
/// stood here ("does not persist yet — that is #593, Council-gated") became false the
/// day #593a shipped and was this file's own refutation for two commits (#425); its
/// successor ("persists exactly one way") aged the same way the day #600 routed the
/// project door — this line changes WITH the door inventory, or it lies.
///
/// `patch` is the panel's `currentPatch` binding, written on ONE event only (Clear —
/// F5a below); the body never reads it, so no parent-state read leaks into this leaf.
@MainActor
private struct VoiceCaptureRow: View {
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(PolySynthVoice.self) private var synth
    let controller: VoiceCaptureController
    @Binding var patch: SynthPatch
    /// #593c review F3: the panel strips its OTHER patch copies (the undo snapshot)
    /// here — the row cannot see them, and Clear must clear EVERY copy or it does
    /// not stick. Called once, inside the Clear action.
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Voice timbre")
                    .font(EchoelTheme.font(12, .semibold))
                    .foregroundStyle(EchoelTheme.text)
                Spacer(minLength: 8)
                switch controller.phase {
                case .capturing:
                    Circle()
                        .fill(controller.hearingYou ? EchoelTheme.accent : EchoelTheme.dim)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text("\(Int(controller.progress * 100)) %")
                        .font(EchoelTheme.font(11).monospacedDigit())
                        .foregroundStyle(EchoelTheme.dim)
                        .accessibilityLabel("Capture progress \(Int(controller.progress * 100)) percent")
                    Button("Cancel") { controller.cancel() }
                        .font(EchoelTheme.font(11))
                        .frame(minHeight: 44)
                default:
                    if synth.appliedVoiceProfile != nil {
                        Button("Clear") {
                            controller.clearApplied(synth: synth)
                            // ⛔ F5a (#593c): strip the VIEW copy too. `clearVoiceProfile`
                            // strips the synth's own patch memory, but the panel's
                            // `currentPatch` is a separate value copy — with taps still
                            // in it, the very next knob tweak re-applies the patch and
                            // silently reinstalls the profile Clear just removed. Clear
                            // must clear BOTH copies or it does not stick.
                            patch.voiceProfileTaps = nil
                            patch.voiceProfileLabel = nil
                            patch.voiceProfileBlend = nil
                            onClear()
                        }
                            .font(EchoelTheme.font(11))
                            .frame(minHeight: 44)
                            .accessibilityHint("Returns the patch's own sound")
                    } else {
                        Button("Capture") {
                            controller.begin(mic: audioEngine.microphoneManager,
                                             synth: synth)
                            // ⛔ #897 — FIVE SLICES MADE THIS FAILURE VISIBLE AND NONE OF THEM
                            // MADE IT PERCEIVABLE. On every abort the take returns to `.idle`,
                            // so this button keeps its label, its hint and its value: for a
                            // VoiceOver user the tap changes NOTHING on the focused control and
                            // the new sentence is an unfocused sibling `Text` that focus never
                            // visits. They were left with exactly the dead button the whole arc
                            // set out to remove — the one class of user for whom it was never
                            // fixed.
                            //
                            // ⭐ THE ANNOUNCED TEXT IS `caption` ITSELF, not a second string.
                            // A hand-written copy would drift from the visible one the first
                            // time either is reworded, and the two would then disagree about
                            // what just happened. Same mechanism as the library's undo offer
                            // (`VideoLibraryPanel`), which exists for the same reason: the
                            // thing worth saying is not where focus is.
                            //
                            // ⚠️ `begin()` is synchronous, so the outcome is already decided on
                            // this line. `.idle` here means it aborted — a take that started
                            // sits on `.capturing`, and there the button is REPLACED by Cancel,
                            // which moves focus and speaks for itself.
                            //
                            // NEEDS-FOUNDER-VERIFY: VoiceOver on, Sound panel → Voice timbre →
                            // Capture with the microphone permission still unanswered or
                            // switched off. Does the reason get SPOKEN? A green test bundle
                            // proves the call is written, never that the system speaks it —
                            // an announcement posted while focus is moving can be dropped.
                            if controller.phase == .idle {
                                AccessibilityNotification.Announcement(caption).post()
                            }
                        }
                        .font(EchoelTheme.font(11, .semibold))
                        .frame(minHeight: 44)
                        .accessibilityHint("Hold a tone; its colour becomes the instrument's timbre")
                    }
                }
            }
            Text(caption)
                .font(EchoelTheme.font(10))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var caption: String {
        switch controller.phase {
        case .capturing:
            return controller.hearingYou
                ? "Keep the tone going — vowels and hums both work."
                : "Hold a steady tone near the microphone. Analyzed live — no audio is recorded."
        default:
            // ⛔ #892 — #891 PUT THE REFUSAL BRANCH FIRST ON A FALSE PREMISE, and two
            // independent reviewers found it the same hour. The premise was: "it can only
            // be true with no profile applied, because Capture is the only button that
            // reaches `begin()`". That argues about the moment the flag is SET and says
            // nothing about the moment it is READ. `begin()` is not the only producer of
            // `appliedVoiceProfile` — `PolySynthVoice.apply(_:)` installs one from any
            // recalled patch that carries `voiceProfileTaps`, which is the #593c pathway,
            // and the preset bar that does it sits directly ABOVE this row. So: capture
            // refuses → load a sound that carries a voice profile → the button is now
            // "Clear" and the caption said "Tap Capture again", naming a control that is
            // not on screen. A row that displays one state and holds another.
            //
            // ⭐ THE ORDER IS THE FIX: what the instrument is DOING NOW outranks a report
            // about a take that did not happen. The flag is additionally cleared by
            // `cancel()` and `clearApplied(synth:)` so it cannot outlive the situation it
            // describes — the branch order alone would still have shown the stale sentence
            // after a Clear.
            if synth.appliedVoiceProfile != nil {
                // #597a — measured before written: the FX door drives `synth.fxChain`,
                // the SAME voice this profile shapes, and the harmonizer is a stage of
                // that chain (in → … → harmonizer → …). "Your tone, harmonized" needs
                // no wiring — only this sentence, so a player can FIND it. The join is
                // pinned by TheVoiceTimbreReachesTheHarmonizerTests.
                return "The instrument plays with your voice's colour — FX → Harmonizer stacks it into harmonies. Clear returns the patch's own sound."
            }
            // ⚠️ NO REMEDY IS PROMISED beyond the one action the user actually has. The
            // #890 cause is a placeholder input format in the window right after the record
            // route is claimed, and whether a second tap lands outside that window is
            // device behaviour nobody here has measured. "Tap Capture again" is true;
            // "wait a moment and it will work" would not be.
            // #895 FIRST among the two failure reports, because it is the only one whose
            // remedy is NOT "tap again": no number of taps changes a denied permission. It
            // is a current-state fact re-derived on every tap, so it cannot go stale behind
            // a refusal count. No Settings PATH is spelled out — it moves between iOS
            // versions, and naming a wrong one is worse than naming none.
            // #896: the system alert is up. Answering it does NOT restart this take —
            // nothing observes the grant — so the honest instruction is the extra tap, not
            // "wait". First of the three because it is the most transient.
            if controller.micAwaitingPermission {
                return "Allow microphone access in the dialog, then tap Capture."
            }
            if controller.micAccessDenied {
                return "Microphone access is off for Echoel — turn it on in Settings, then tap Capture."
            }
            if controller.micRefusals > 0 {
                // #893: the COUNT is the only thing that changes on a repeat, so it carries
                // the whole answer to the probe's "twice in a row". Suppressed at 1 so the
                // ordinary single failure does not read like a tally. The advice does not
                // escalate with the count — after two refusals "tap again" is still the only
                // action the player has, and any stronger suggestion would be invented.
                let streak = controller.micRefusals == 1 ? "" : " (\(controller.micRefusals)× in a row)"
                return "The microphone did not start\(streak) — nothing was captured. Tap Capture again."
            }
            return "Hold a tone for a few seconds; its colour becomes the instrument's. Analyzed live — no audio is recorded."
        }
    }
}

/// #522 — the door that had never existed: a place to say who you are.
///
/// ⭐ WHAT WAS WRONG, and it is the exact shape #521 measured and then had to write down as a
/// limitation. `SessionContext.artistName` is persisted, is stamped onto every saved take, and
/// travels with the file — but its `didSet` is the ONLY writer of the stored value and **Swift
/// does not run `didSet` from an initialiser**, so the one line that would persist a name could
/// never fire. `git grep artistName -- Sources` returned the key, the property, that `didSet`,
/// two `init` assignments and a handful of readers, and NOTHING that assigned it. Every device
/// reported the same `E~`, every take was stamped `E~`, and #521's credit line was therefore
/// correctly silent on every take in existence — a mechanism without a producer (#506).
///
/// ⚠️ IT DOES NOT MAKE LIVE-COLABO PEERS DISTINGUISHABLE, and the v10.79.382 deploy note said
/// it would. Measured: `MCPeerID` is built exactly once, in `MultipeerSession.init()`, from
/// `UIDevice.current.name` — which iOS 16+ returns as the MODEL name ("iPhone") without the
/// user-assigned-device-name entitlement Echoel does not hold. #513 is untouched by this slice
/// and stays open. Two things land here, not three.
///
/// ⭐ WHY A `Binding` OVER A TRANSFORM rather than `$session.artistName` straight through.
/// `unnamedArtist` IS the "no name" state, so a field bound to the raw property would show `E~`
/// as literal text and make every new user select-all-delete a mark they never typed. The
/// transform pair lives on `SessionContext` (pure, `nonisolated`) so the blocking bundle can
/// DRIVE the decision instead of scanning this `private` row — and so `E~` stays one literal
/// rather than three (#416). The invariant it protects is not cosmetic: a live `""` against
/// takes stamped `E~` would make `Project.attribution` fire `by E~` on the user's OWN takes.
///
/// ⚠️ A LEAF `View`, and here that is bookkeeping rather than a fix. `utilityRow` reaches the
/// screen through `dropdownContent`'s `case .export`, which is evaluated in the ROOT body
/// PERMANENTLY — `AnyView(...)` is not an observation boundary (10.76.41/50, corrected by
/// #486). `session.artistName` is ALREADY read in the root body (`projectRow`, since #521), so
/// the root already rebuilds when it changes; what a leaf prevents is the `@State`-style whole-
/// body churn `SoundPromptRow` documents, and it keeps the read where the next audit expects
/// it. The documented harm — a `.menu` popover torn down mid-selection — is unreachable while
/// a keyboard is up, same honest scope as `SoundPromptRow`.
@MainActor
private struct ArtistNameRow: View {
    @Environment(SessionContext.self) private var session

    var body: some View {
        // One read, two uses: the field's text and whether the clear button exists. Reading it
        // twice would be two observation registrations for one fact.
        let typed = SessionContext.typedArtistName(fromStored: session.artistName)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 12)).foregroundStyle(EchoelTheme.dim)
                // Text, not a number → a plain `TextField` is correct; `EchoelValueField` is the
                // law for NUMERIC parameters only. `placeRow` two screens up is the precedent,
                // and this row deliberately wears its chrome: they are the two halves of the
                // same `SessionNaming.stem` and belong in the same panel looking alike.
                TextField("Your name (optional)", text: Binding(
                    get: { SessionContext.typedArtistName(fromStored: session.artistName) },
                    set: { session.artistName = SessionContext.storedArtistName(fromTyped: $0) }))
                    .font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .accessibilityLabel("Your artist name")
                if !typed.isEmpty {
                    // 36×36, the `placeRow` measurement verbatim: the glyph stays 14 pt and only
                    // the target grows, and an outset would eat the taps that place the caret at
                    // the end of the name. Honest limit is the same one — 36 < the 44 pt HIG
                    // floor, above WCAG 2.5.8's 24, and 44 would be taller than the row.
                    Button { session.artistName = SessionContext.storedArtistName(fromTyped: "") } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14)).foregroundStyle(EchoelTheme.dim)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear your artist name")
                }
            }
            .padding(.horizontal, 10).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(EchoelTheme.border, lineWidth: 1))
            // ⚠️ THE CAPTION NAMES WHAT IS TRUE TODAY AND NOTHING MORE. It does NOT promise that
            // other players will see the name — that is #513 and it is not fixed here. It does
            // not promise the credit line appears on your own takes; `Project.attribution`
            // stays quiet there by design.
            Text("Stamped on takes you save, and used in session and export file names. Without a name they are stamped \(SessionContext.unnamedArtist).")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

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
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
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
                        // #621 (Ultraaccessible-Audit, bar point 8): without a label,
                        // VoiceOver falls back to the placeholder and announces the
                        // EXAMPLE phrase as the field's NAME — a value where a name
                        // belongs. The label is the row's visible caption, one vocabulary.
                        .accessibilityLabel("Describe it")

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

                    // ⭐ THE ARROW RESERVES ITS SLOT INSTEAD OF BEING INSERTED. It used to sit
                    // behind `if canUndo`, so the first Shape or Randomize pushed a ≥44 pt
                    // element into this HStack: the TextField narrowed and "Shape" jumped left
                    // under a finger that may still have been typing. Same class as the lock
                    // cue that shoved the Bio controls (#382), and it got worse the moment
                    // Randomize became a second arming control — one more everyday tap that
                    // rearranges a row. Hidden means INERT, not merely transparent: no hit
                    // target, no VoiceOver element. Three modifiers, not one.
                    Group {
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
                        // ⛔ "Undo the last shaping" — true while the prompt was the only writer
                        // of the snapshot, false the moment `randomizeButton` started taking one
                        // too. A VoiceOver user would have heard "shaping" after a randomize and
                        // reasonably concluded the arrow was for something else. It is the same
                        // defect class as a stale caption, only audible instead of visible.
                        .accessibilityLabel("Undo the last sound change")
                    }
                    .opacity(canUndo ? 1 : 0)
                    .allowsHitTesting(canUndo)
                    .accessibilityHidden(!canUndo)
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
