# CLAUDE.md — Echoel v10 (Bio · Audio · Video · Light · Broadcast)

## IDENTITY

Repository: https://github.com/vibrationalforce/Echoelmusic
Developer: Echoel (Michael Terbuyken) @ Studio Hamburg
App Apple ID: 6757957358 · SKU: Simsalabimbam · Team ID: via `APPLE_TEAM_ID` secret
Bundle prefix: `com.echoelmusic` · App Group: `group.com.echoelmusic`
Bundles: `.app` (main, universal) · `.app.auv3` · `.app.watchkitapp` · `.app.widgets` · `.app.clip` (deferred) · `.app.notification-service` (deferred)

**Canonical identity map:** `docs/dev/APP_STORE_CONNECT.md` · **Cross-platform plan:** `scratchpads/PLAN_MULTIPLATFORM_LINKING.md`

**Echoel — Physical Computing · Biofeedback · Multimedial & Multidimensional.**
An immersive, iPhone-first instrument and production platform where the body — heart, breath, motion, brain rhythm — drives sound, image, light, and broadcast in real time.

Built for: **Installation · Event · Content · Cinema · Theater · Performance · Live Broadcast.**

Capabilities (all routed through one typed bus): **Beat Maker** (16-step × 8-track sequencer + sampler) · **Multi-track Recorder** (mic over beats) · **Video Capture & Trim** · **RTMP Live Stream** (YouTube / Twitch / Facebook / custom) · **bio-reactive synthesis** · **OSC / MIDI / MPE I/O** · **generative visuals + lighting**.

---

## CURRENT STATE

- **Branch:** `claude/piano-roll-clip-view-wozlie` (current dev branch; prior cycles auto-merged to `main`)
- **Mode:** RALPH WIGGUM LAMBDA — one feature/fix per cycle, build → test → ship → loop
- **Positioning:** "The first bio-reactive performance instrument" — and, per the 2026-06-06 deep-research roadmap, the **bio-reactive object source for accessible immersive multidimensional media art** (open standards: ADM-OSC, MIDI 2.0, OSC, BLE HRS; no SDK lock-in). See `scratchpads/STRATEGY_STATE_OF_THE_ART_2026-06-06.md`.
- **Architecture (audited 2026-06-09 — `scratchpads/ARCHITECTURE_AUDIT_2026-06-09.md`):** `EngineBus` = `@MainActor @Observable` control plane (snapshots) + lock-free `SPSCQueue`. 3 topics — `bioFrames` / `controllerEvents` / `bioEvents`. **Bio flows over the `latestBio`/`latestBioEvent` snapshot (10 Hz poll); the SPSC queue is drained only for `controllerEvents` (MIDI).** `bioFrames`/`bioEvents` queues are reserved/undrained (snapshot is the correct path for slow bio). Modules couple only via the bus.
- **Live pipeline:** HealthKit + **universal BLE Heart Rate** (any 0x180D device) + **camera rPPG (live, locks on device)** + Demo → bio snapshot → BioReactiveSynthVoice (EchoelDDSP; **silent until user-armed**) + OSCSender (`/echoelmusic/bio/*`) + **ADMOSCSender** (`/adm/obj/{n}/*` immersive object out). CoreMIDI MPE → controllerEvents → synth notes (performer priority). BioEventGraph → breath/motion onsets. ModulationEngine wired (bio→tempo). EchoelBeat: velocity/accent + swing + per-pad sample import.
- **Protected DSP triad (READ-ONLY, now implemented):** BioSignalDeconvolver (detrend·notch·validity), HilbertSensorMapper (1D→2D Hilbert curve), BioEventGraph (heartbeat/breath/motion detectors). Pure value types, SKILL.md contracts under `.claude/skills/`.
- **SDK:** iOS 18 deployment floor (Package.swift + project.yml + Resources/iOS/Info.plist synced). Xcode 26.2 in `testflight.yml`. App Group `group.com.echoelmusic`.
- **Root view (SHELL FLIP 2026-07-06 — founder "Ja" on the two-stream strategy synthesis, `scratchpads/STRATEGY_OPTIMAL_FORM_2026-07-06.md`): the calm breathing SESSION is the app HOME.** `WorkspaceView` body = `SessionView(presentStudio:)` (brand header + Studio door + start/light/pace leaves) + ONE `fullScreenCover` presenting `StudioShellView` (the entire former shell: studio topBar + `TransportBar` + `EchoelStudioView` + `FloatingVisualWindow`). Opening the Studio ends the session (camera/torch must not run underneath); closing the Studio stops the pattern clock (no music bleeding under the calm home). The studio's "Breathing Session" card now RETURNS home (dismisses the cover). Launch never constructs the studio → calm + smaller first-render metadata. Do NOT "fix" the home back to the studio — that inversion was the root quality complaint (audit 2026-07-06). The pre-flip note below is kept for the studio's internals:
- **Studio shell internals (pre-flip note, still accurate INSIDE `StudioShellView`):** brand header (`topBar`) + persistent `TransportBar` (Play/Stop + tempo-lock button + `TransportPositionView` loop/position leaf; NO tempo number in the chrome since v10.79.64 — the one musical-tempo control is `BodyTempoField` in the Composition panel, the one live pulse number is in the bio strip) + `EchoelStudioView` (the instrument) + the floating immersive visual (`FloatingVisualWindow`, toggled from the header monitor). **The former 6-surface bottom bar (Arrange · Clips · Compose · Mix · Bio · Browse) is REMOVED from navigation** — those surfaces still exist in code (ClipView/ArrangementView/ChannelRackView/BioSourceView/BrowserView; reversible by restoring the bottom bar) but are not reachable from the shell today. Do not "restore" them without a founder ask. **Video page = designed + DEFERRED** (`scratchpads/PLAN_VIDEO_PAGE.md`). The old `StudioRoot` Tools/Works/Sync/Well TabView is long gone.
- **Presentation (stability, as-shipped — corrected 10.76.38):** the device-confirmed-launching `EchoelStudioView` uses **MANY `AnyView`-wrapped `.sheet`/`.fullScreenCover` modifiers** chained on the body (~16 sheets + 3 covers), each with its own `isPresented:`/`item:` binding and an `AnyView(...)`-erased content closure. This is the baseline that launches — the earlier "ONE `.sheet(item:)` + ONE `.fullScreenCover(item:)` via computed bindings" note was **aspirational, never the shipping code**, and is removed to stop a future session "fixing" the launching code into a regression. **THE REAL RULE (learned the hard way, 10.76.34/build 2068 black screen): do NOT keep GROWING this modifier chain.** Adding sheets pushed the body's aggregate generic type past the SwiftUI metadata-decoder stack limit → SIGSEGV at first render, before any view appears (presents as a black screen, or "Safe Mode oder Black Screen" alternating once the self-healing net catches every other launch). The chain was "just under" the limit at 10.76.9/21; three sheets added 10.76.25/27/29 tipped it over (an `AnyView`-split of the chain did NOT save it — 10.76.35 still crashed; only reverting to the 10.76.21 body did). To add a NEW modal: **reuse/replace an existing slot, or consolidate the whole chain into a single `.sheet(item:)` enum FIRST** — never just append another `.sheet`. (Separately: never drive two modals true at once — that installs an invisible tap-blocking layer, the "can't click anything" hang.) **Also (10.76.41, "Tonart-Menü friert ein / kann plötzlich nicht mehr auswählen"): never read a HIGH-FREQUENCY `@Observable` (the ~10 Hz `CameraRPPGBioPublisher` finger/confidence/waveform, any bio snapshot, a playhead) directly in `EchoelStudioView.body` or in a computed `var` that `body` evaluates — `AnyView(...)` is NOT an observation boundary, so those reads register the WHOLE root body as a 10 Hz observer and every rebuild tears down any open `.menu` Picker popover (the freeze; worse while playing). Confine such reads to their own small leaf `View` struct (e.g. `BioStripView`, `PulseMeasurementView`) so only that view churns; the Picker-hosting body stays still.** **AND (10.76.48, "Sobald Biofeedback läuft kann ich nicht mehr auswählen"): the camera-freeze had a SECOND, non-SwiftUI cause — a high-frequency producer on a background queue must NOT hop to `@MainActor` per item. `CameraRPPGBioPublisher.onFrame` did a `Task { @MainActor }` PER captured frame (~30/s before the analyzer's frame-skip); that flood of tiny main-actor task submissions starved the SwiftUI executor → the open `.menu` Picker stopped responding while bio ran. Fix pattern: the background closure pushes into a lock-protected `RGBSampleQueue` (`@unchecked Sendable`, `NSLock`, capped) with ZERO actor hop; the EXISTING 10 Hz `publishTask` drains+feeds the `@MainActor` analyzer in one batch (carry a `timestamp` so rate maths is unchanged). Rule: never `Task { @MainActor }` per frame from a 30 fps source — batch into an existing low-rate main-actor poll via a Sendable queue.** **AND (10.76.50, the ACTUAL recurring menu-freeze cause — found after 41/43/47/48 each fixed a real-but-insufficient cause): the churn was in `WorkspaceView` (the ROOT, ABOVE every surface), NOT in `EchoelStudioView`. `WorkspaceView.topBar` read `cameraRPPG.waveform`/`detectedBPM`/`isLocked` directly to feed the header `PulseMonitorMini` — `waveform` updates ~10 Hz during biofeedback, so `WorkspaceView.body` rebuilt 10×/s and tore down any open `.menu` Picker in the surface BELOW it. Every prior audit scoped to `EchoelStudioView` and correctly found it clean — the 10 Hz read was one level up. FIX: confine the live reads to a leaf (`PulseMonitorMiniLive` reads the publisher in its OWN body); `WorkspaceView` only reads `isRunning` (start/stop). **RULE: when a freeze/churn persists after the obvious view is proven clean, AUDIT THE PARENT/ROOT (`WorkspaceView`, any always-on header/HUD that reads live bio) — a 10 Hz read in ANY ancestor of the menu host rebuilds the whole subtree. Header/monitor tiles that show live bio MUST read it in their own leaf, never via values passed down from a parent body.**
- **✅ TESTFLIGHT PIPELINE: GREEN (verified 2026-05-30).** Prior "deploy blocker" note is resolved — `testflight.yml` runs #1404–#1407 on `main` all succeeded across every platform (iOS upload + Summary), preflight confirms App Store Connect secrets are present and valid. Dispatch + poll from the sandbox via `bash scripts/check-testflight.sh dispatch` (token in gitignored `.claude/settings.local.json`). Push the feature branch's newer work (bio synth / OSC / Polar) to TestFlight with a full `build_only=false` run once a branch verification run is green.
- **Latest work (2026-06-23, on branch, gates green):** **Adaptive Quality** (AdaptiveQuality core + ResourceGovernor: thermal/battery/measured-FPS → tier → MetalBioView FPS/detail/reduce-motion — Akku/CPU/GPU) · **camera-session resilience** (runtime-error/interruption observers + frame-stall watchdog — fixes the silent ~68–200 s rPPG freeze) · **rPPG saturation-hold** · **composition cohesion** (BioComposer structure/detail RNG split — "homogener klingen") · **master −1 dBFS true-peak trim** · **EchoelFX bio-reactive modulation** (FXModulation core in `Core/` + FXBioModulator ~30 Hz; body→FX-param routing, UI section) · **EchoelFX Bitcrush + Stereo Widener** stages (wired chain/VM/UI/FXPreset/bio-mod) · **VJ visuals** (live in-fullscreen control overlay + shader hue/saturation palette, physical-colour default preserved). EchoelFX deepening = 4 workstreams (1 bio-mod + 2 algorithms shipped; 3 macro-morph + 4 CI-polish pending).
- **Prior TestFlight ship (2026-06-18):** rPPG fix (torch + exposure lock), real frequency-domain HRV coherence (Lomb-Scargle + Welch), resonance breath guide, tap-to-learn bio metrics, Art-Net flash-safety. Base build 1543 (app + Widget + AUv3, camera rPPG, universal BLE, ADM-OSC, EchoelLux Art-Net, launch silence).
- **Absent (not wired — do not claim as shipping):** RTMP/streaming (BroadcastPublisher is a compile-safe scaffold behind `#if canImport(HaishinKit)`; HaishinKit not integrated), video capture/edit, multitrack audio. **EchoelStore** (`Core/EchoelStore.swift`) = DORMANT StoreKit-2 scaffold — instantiated in `EchoelmusicApp` but ZERO consumers; its legacy subscription product IDs contradict the one-time-unlock positioning (`scratchpads/MASTERPLAN_2026-07.md` §2); nothing is purchasable today. **Push:** zero in-app code (no registration, no `aps-environment` entitlement) — the founder's APNs key (LBY89HTN2C) has no receiver; the dead `send-push.yml` CI sender was deleted 2026-07-04. **Art-Net + sACN (unicast) are live.** **VocoderCore / BioModulation** = pure tested cores, **not yet wired** (foundations). **FeedbackGuard** (audio-input live monitoring) and **BioVisualParams** (immersive flash-safe pulse) are **wired**. See `docs/dev/FEATURE_MATRIX.md`.
- **P1 "Sound complete" — ALREADY BUILT (audited 2026-07-01; corrects the old "Clips/Arrangement UI not wired" note):** the melodic/DAW core is done and wired — **polyphonic synth** (`PolySynthVoice`) + **bass** (`SubBassVoice`) + **hybrid sample/synth drums** (`BeatPlayer` + `DrumSynthVoice`); **full patch editor + presets** (`SynthPatch`/`PatchStore`/`PatchEditorView`, reachable from `EchoelStudioView`, favorites/community/save-as, live-apply, tested); **breakbeat loop-cut** (`LoopCutter`/`LoopBarLength` in the Studio UI); **MIDI export** (`exportMIDI()` + `ShareSheet`); **Clips + Arrangement UI wired** (`ClipView`/`ArrangementView` as `WorkspaceView` surfaces, `ClipStore`/`ArrangementStore`/`AutomationLane`). Music theory is fully in-house. The real remaining frontier is **P3 Video** (no recorder/trim/export yet) and **P4 Broadcast**. See `scratchpads/PLAN_PRODUCT_STRUCTURE_2026-07-01.md`.
- **Files:** ~212 Swift (Sources) + 1 Metal (`Video/Shaders/ChromaKey.metal`; `MetalBioView` compiles its shader inline at runtime) | **Swift 100%** | current directory map in `docs/AUDIT_2026-07.md`. NOTE: the "four pillars" (EchoelTools/Works/Sync/Well) referenced by older vision docs were **never built as modules** — `EngineBus` is the one real coupling spine; `Views/` now holds only `MetalBioView` + `OnboardingView` (its long deprecated list is gone).

---

## BRAND

**Echoel — Physical Computing · Biofeedback · Multimedial & Multidimensional.**

An immersive multimedia instrument and production platform for **Installation · Event · Content · Cinema · Theater · Performance · Live Broadcast.** The body is the controller: heart, breath, motion, and brain rhythm drive sound, image, light, and stream in real time.

Concrete capabilities span beat-making, multi-track recording, video capture/edit, RTMP live streaming, bio-reactive synthesis, generative visuals, and OSC/MIDI/MPE integration — but the identity is **the instrument**, not any single competitor it replaces.

**Biofeedback is core, not wellness.** Echoel treats physiology as a first-class, science-based modulation source (HRV resonance, peer-reviewed bio-signal processing). It is NOT a wellness, soundscape, or therapy product.

NEVER use "BLAB", "Vibrational Force", legacy bio-wellness/soundscape branding, or esoteric terminology ("healing frequencies", chakras, Solfeggio) in user-facing copy.

---

## ARCHITECTURE (original v10 target — SUPERSEDED; see CURRENT STATE for as-built)

> ⚠️ **This tree is the ORIGINAL v10 plan, NOT what shipped.** The as-built app is a
> single `EchoelStudioView` (see "CURRENT STATE" above and "Studio sections" below) —
> there is **no `StudioRoot` TabView**, and Record/Video/Share were never built
> (RTMP / video capture / multitrack = roadmap). Kept here only as the audio-foundation
> reuse map.

```
EchoelmusicApp (@main)
└── StudioRoot                     ← TabView with 4 tabs (NEW)
    ├── BeatTab                    ← drum pads + 16-step sequencer (NEW)
    │   └── PatternEngine          ← 8-track × 16-step + tempo clock (NEW)
    │       └── SamplerVoice       ← one-shot WAV player (NEW)
    ├── RecordTab                  ← mic + master mixer + REC (NEW)
    │   ├── MultiTrackRecorder     ← mic over beats, sample-accurate sync (NEW)
    │   ├── RetroCapture           ← 30s pre-roll ring buffer (KEEP)
    │   └── AutoMixChain           ← EQ → Comp → Limiter → LUFS (KEEP)
    ├── VideoTab                   ← camera capture + trim (NEW)
    │   ├── CameraSession          ← AVCaptureSession 1080p30 (NEW)
    │   ├── VideoRecorder          ← AVAssetWriter H.264+AAC (NEW)
    │   └── ClipTrimmer            ← in/out points (NEW)
    └── ShareTab                   ← RTMP stream + export (NEW)
        ├── RTMPPublisher          ← HaishinKit wrapper (NEW)
        └── SingleExport           ← LUFS mastering → WAV/AAC/MP4 (KEEP)

Audio Foundation (KEEP):
  AudioEngine (AVAudioEngine master bus) · MicrophoneManager · SPSCQueue ·
  EchoelDDSP (reused as synth voice) · EchoelCellular (reused as FX texture)
```

Deprecated from main flow: the old SoundscapeEngine, ClipEngine, MomentCaptureView,
  BioSourceManager, Oura/EEG bridges, WeatherProvider, CircadianClock files have all
  been REMOVED in cleanup (2026-06-19 audit) — they no longer exist. (HealthKit + rPPG
  are now LIVE, not deprecated.) The real "built but app-unwired" cores remaining are
  test-only foundations: BioModulation, BioVisualParams, FeedbackGuard, VocoderCore,
  LearnLibrary, CloudSync, EchoelFXView/FXViewModel.

Protected (do not modify without explicit user approval):
  BioEventGraph, HilbertSensorMapper, BioSignalDeconvolver.

### EchoelStudioView (actual, as shipped — corrected 2026-07-04)

**The single Compose instrument, NOT a section shell.** Since the 2026-07-02 founder
pivot ("Alles weg außer visuals"), the section Picker and the Tools grid are REMOVED
from the UI — `EchoelStudioView` is the one-button bio-generative flow: always-on
`BioStripView` (HR·HRV·Br·Coh leaf, tap-to-learn, MIDI/OSC/event dots) above the
Composition panel (Tonart · Genre · Kammerton · `BodyTempoField` tempo lock ·
loop size), generate + play, FX character, and the deeper editors reachable only via
their remaining sheet slots (Piano Roll / patch editor / sample browser / audio clip /
AUv3 — the `toolsSection` builder + sheets remain in code, reversible, unpresented).
The old Section/Tools table stood here until 2026-07-04; do not resurrect it as fact.

---

## TECH STACK — Zero Dependencies Today

| Layer | Framework |
|---|---|
| Apple (iPhone) | AVFoundation + Accelerate + Metal + CoreMIDI + VideoToolbox + SwiftData |
| RTMP/RTMPS | HaishinKit = **PLANNED** dep for P4 Broadcast — NOT linked (`Package.swift` `dependencies: []`; `BroadcastPublisher` is a `#if canImport(HaishinKit)` scaffold) |
| Build | XcodeGen (`project.yml`) + Fastlane (TestFlight upload) + GitHub Actions |
| DSP | Swift (audio-thread-safe, lock-free SPSC queues) |

iPhone-only for v10 MVP. iPad / Mac / Watch / Vision deferred to v1.1+.

---

## REPO STRUCTURE (v10)

```
Sources/Echoelmusic/
  Audio/               ← AudioEngine, AudioConfiguration, MIDIInput,
                          RetroCapture, AutoMixChain, SingleExport (KEEP)
                       ← MultiTrackRecorder (NEW W2)
  Sequencer/           ← PatternEngine, SamplerVoice (NEW W1)
  Video/               ← CameraSession, VideoRecorder, ClipTrimmer (NEW W2)
                       ← existing CameraCapture/CameraAnalyzer kept compilable
  Stream/              ← RTMPPublisher (NEW W3)
  Studio/              ← EchoelStudioView (root), EchoelFXView, PatchEditorView,
                          SampleBrowserView, ClipView, EchoelTheme (as-built; the old
                          StudioRoot/Beat/Record/Video/ShareTab plan was never built)
  Core/                ← EchoelStore, SPSCQueue, ProfessionalLogger, MemoryPressureHandler,
                          NumericExtensions, SessionStore, ClipStore, ModulationEngine (KEEP)
                       ← (SoundscapeEngine/ClipEngine/WeatherProvider/CircadianClock/PlatformAvailability REMOVED 2026-06-19)
  Bio/                 ← BioEventGraph, HilbertSensorMapper, BioSignalDeconvolver (PROTECTED)
                       ← EchoelBioEngine + HealthKitBioPublisher + CameraRPPGBioPublisher (LIVE)
                       ← (BioSourceManager/OuraRingClient/EEGSensorBridge/MotionActivityProvider REMOVED)
  DSP/                 ← EchoelDDSP, EchoelCellular, EchoelModalBank, EchoelVDSPKit (KEEP, reused as synth voices)
  Sync/                ← OSCSender, ADMOSCSender, Art-Net/sACN (EchoelLux), CloudSync
  Tools/               ← PolySynthVoice, SubBassVoice, breath/vocal tools
  Views/               ← MetalBioView + OnboardingView ONLY (the old deprecated-view list is deleted)
Sources/EchoelmusicAUv3/ ← AUv3 Generator Plugin (deferred, not active in v10)
Tests/EchoelmusicTests/ ← 140 test files (see KEY TESTS)
docs/                  ← Website (GitHub Pages)
.github/workflows/     ← CI/CD (testflight.yml is primary)
```

Existing top-level directories under `Sources/Echoelmusic/`: `Audio/ Bio/ Core/ DSP/ Resources/ Sequencer/ Stream/ Studio/ Sync/ Tools/ Video/ Views/`. No NEW top-level directories without approval.

---

## BIO-SIGNAL DSP — DO NOT SIMPLIFY

| Algorithm | Basis | Function |
|---|---|---|
| BioEventGraph | DELLY (Rausch 2012) | Graph-based event detection, k-means clustering |
| HilbertSensorMapper | Hilbert curves | 1D→2D locality-preserving sensor mapping |
| BioSignalDeconvolver | Tracy (Rausch 2017) | Separates cardiac/respiratory/artifact via adaptive biquad IIR |

### DDSP Bio-Mappings

Coherence → Harmonicity | HRV → Brightness | Heart rate → Vibrato | Breath phase → Envelope | Breath depth → Noise | LF/HF → Spectral tilt | Coherence trend → Shape morphing

---

## PERFORMANCE — Hard Limits

| Metric | Target | FAIL |
|---|---|---|
| Audio Latency | <10ms | >15ms |
| CPU | <30% | >50% |
| Memory | <200MB | >300MB |
| Visual FPS | 120fps | <60fps |
| Bio Loop | 120Hz | <60Hz |

**Audio thread: NO locks, NO malloc, NO ObjC messaging, NO file I/O, NO GCD.**

---

## PLATFORM CONSTRAINTS

- Apple Watch HR: ~4-5 sec latency — NO beat-sync!
- RMSSD: Self-calculate (Apple only gives SDNN)
- Bluetooth Audio: 150-250ms latency
- Flash animations: Max 3 Hz (epilepsy W3C WCAG)

---

## SAFETY WARNINGS (must be in app)

- Brainwave Entrainment: NOT while operating vehicles
- NOT under influence of alcohol/drugs
- Therapeutic use: coordinate medications with provider
- Max 3 Hz visual flash rate
- Data for self-observation, NOT medical diagnosis

---

## RALPH WIGGUM LAMBDA PROTOCOL

```
1. git status && git log --oneline -10
2. swift build 2>&1 | tail -20
3. Identify ONE broken/unclear thing
4. Fix it (minimal change, max 3 files)
5. swift test --filter [relevant]
6. Commit: fix: [description]
7. Deploy to TestFlight
8. Evaluate on device
9. GOTO 1
```

ONE issue per cycle. No batching. Build fails = ONLY priority.
No features during fix cycles. Convergence only.

---

## "CLEAR SOFTWARE" CHECKLIST

1. Every screen does something (no placeholders)
2. Navigation works (tabs respond, back goes back)
3. Bio-feedback visible (HR, HRV, coherence front and center)
4. Audio works (tap synth = hear sound)
5. Buttons respond, states change, loading indicators work
6. No crashes (force unwraps banned, optionals handled)
7. Permission denials handled gracefully
8. Background/foreground transitions stable

---

## SESSION START

```bash
git status
git log --oneline -20
swift build 2>&1 | tail -30
cat .ai/*.md 2>/dev/null
swift test 2>&1 | tail -20
```

Priority: Build errors → Test failures → Crash code → Task → Cleanup

---

## CODE STYLE

- **SwiftUI + MVVM** | `@Observable` (iOS 17+) | async/await + `@MainActor`
- **Swift 6** strict concurrency | SwiftLint enforced
- `os_log` ONLY (never `print`) | Guard-let over if-let
- Conventional commits | One change per commit
- Swift-first; **no PAID frameworks (no JUCE), no CMake**. The original "no C++"
  rule was really "no JUCE licence fees" — C++ is permitted ONLY for a **free,
  well-contained, Council-approved** library kept out of the Swift audio core
  (e.g. Ableton Link / LinkKit, which is free). Default stays Swift; deps stay
  minimal (ZERO external deps shipped today; HaishinKit = the planned RTMP dep, not linked).
- `///` for public API docs

---

## CRITICAL BUILD ERROR PATTERNS

### Swift Compiler Errors

| Pattern | Fix |
|---------|-----|
| UIKit refs on non-iOS | `#if canImport(UIKit)` |
| @MainActor in Sendable closure | `Task { @MainActor in }` |
| deinit calls @MainActor method | Nonisolated cleanup directly |
| `public let foo: InternalType` | Hard error — match access levels |
| `Color.magenta` | Doesn't exist. Use `Color(red:1,green:0,blue:1)` |
| WeatherKit | `@available(iOS 16.0, *)` AND `#if canImport(WeatherKit)` |
| vDSP overlapping accesses | Copy inputs to temp vars before `vDSP_DFT_Execute` |
| `self` before `super.init()` | Move setup AFTER `super.init()` |
| `inout` + escaping closure | Copy to local var first |
| `@MainActor` property read from a `nonisolated` audio-render block ("main actor-isolated property X can not be referenced from a nonisolated context") | Keep the public `@MainActor` prop for the UI, add an `@ObservationIgnored nonisolated(unsafe)` mirror written in its `didSet`; the render reads the mirror (see SubBassVoice.audioSubGain / PolySynthVoice params) |
| `@Observable` class: a manual stored prop named `_foo` ("invalid redeclaration of '_foo'" / "ambiguous use of '_foo'") | The macro generates `_foo` as `foo`'s backing — never name your own field `_<name>`; use a non-underscore name (e.g. `audioFoo`) |

### Logger Usage (Global `log` is EchoelLogger instance)

```swift
// CORRECT:
log.log(.info, category: .audio, "message")

// WRONG - tries to call logger as function:
log(.info, ...)

// WRONG - instance method, not static:
ProfessionalLogger.log()

// Math log() is shadowed — use:
Foundation.log(value)
```

### API Gotchas

| Type | Correct API |
|------|-------------|
| `SpatialAudioEngine` | `init()`, `setMode()`, `currentMode`, `setPan()`, `setReverbBlend()` |
| `UnifiedHealthKitEngine` | `coherence`, `startStreaming()`, `stopStreaming()` |
| `NormalizedCoherence` | NOT BinaryFloatingPoint — use `.value` for arithmetic |
| `Swift.max/min` | Qualify when struct has static `.max` property |

### Type Conflict Resolution

Always prefix types to avoid conflicts:
- ProSessionEngine: `SessionMonitorMode`, `SessionTrackSend`, `SessionTrackType`
- ProStreamEngine: `StreamMonitorMode`, `StreamTransitionType`, `ProStreamScene`
- ProCueSystem: `CueTransitionType`, `CueSceneTransition`, `CueSourceFilter`
- ProColorGrading: `GradeTransitionType`
- `ChannelStrip`, `ArticulationType`, `SubsystemID` → top-level types, NOT nested

### Other Patterns

- `@escaping` required for `TaskGroup.addTask` closures
- Result builder: `buildBlock(_ components: [T]...)` when using `buildExpression`
- `CXProviderConfiguration.localizedName` is read-only in iOS 14+ (set via Info.plist)

---

## KEY TESTS (140 files under `Tests/EchoelmusicTests/` — corrected 2026-07-04)

Run `swift test` (or rely on the CI gates) before ANY commit. Highest-value areas:
DSP (`EchoelDDSPTests` · `DSPTests` · `VDSPTests`) · protected triad
(`BioEventGraphTests` · `BioSignalDeconvolverTests`) · sequencer/tempo
(`PatternEngineTransportRelayTests` · `TempoStabilityTests` · `SequencerTests`) ·
MIDI export (`MIDIFileImporterTests`) · rPPG trust (`CameraRPPGTrustTests`) ·
FX (`EchoelFXChainTests` · `GenreFXTests`). (The old "15 files, 1,060+ methods"
list named 11 files that never existed — do not reintroduce it.)

---

## CI/CD

### Active Workflows (.github/workflows/)

| Workflow | Purpose |
|----------|---------|
| `testflight.yml` | **PRIMARY** — TestFlight builds (ID: 225043686) |
| `ci.yml` | Main CI (SwiftPM build, test, lint) |
| `xcode-compile-check.yml` | XcodeGen + `xcodebuild` compile gate (catches Xcode/AUv3-only errors) |
| `quick-test.yml` | Fast test suite |
| `pr-check.yml` | PR validation |

> **No JUCE / no CMake / no C++.** Swift 100%, ZERO external dependencies today (`Package.swift` `dependencies: []`; HaishinKit = planned, compile-guarded only).
> The old CMake/JUCE/iPlug2 desktop scaffolding (`CMakeLists.txt`, `setup*.sh`,
> `build.yml`, `desktop_build.yml`, desktop build scripts) was removed 2026-06-19.
> Legacy/contradictory workflows also removed 2026-06-19: `android-build.yml`,
> `phase8000-ci.yml`, `swift.yml`, `release-all-platforms.yml` (Android is disabled;
> these were redundant with `ci.yml`/`testflight.yml`).

Android build is disabled. TestFlight needs 60min timeout (30min+ compile).

### GitHub API Access

Token stored in `.claude/settings.local.json` (gitignored, NEVER committed).

**Read token:**
```bash
GITHUB_TOKEN=$(python3 -c "import json; print(json.load(open('.claude/settings.local.json'))['github']['token'])" 2>/dev/null)
```

**Available commands:**
- `/testflight-deploy` — Full pre-flight + deploy to TestFlight
- `/github` — GitHub API operations (PRs, issues, workflow status)

**If token missing:** Ask user to create `.claude/settings.local.json`:
```json
{
  "github": {
    "token_name": "claude-code",
    "token": "ghp_...",
    "owner": "vibrationalforce",
    "repo": "Echoelmusic"
  }
}
```

---

## OSC (EchoelSync)

Actual address set (source of truth: `Sync/OSCSender.swift` — corrected 2026-07-04;
the old list named eeg/{band}, audio/rms, audio/pitch which are NEVER sent):

```
/echoelmusic/bio/heart/bpm       float
/echoelmusic/bio/heart/hrv       float [0-1] (normalized)
/echoelmusic/bio/heart/rmssd     float ms   (only when source provides >0)
/echoelmusic/bio/heart/sdnn      float ms   (   "   )
/echoelmusic/bio/heart/pnn50     float      (   "   )
/echoelmusic/bio/breath/rate     float
/echoelmusic/bio/breath/phase    float [0-1]
/echoelmusic/bio/coherence       float [0-1]
/echoelmusic/bio/motion          float
/echoelmusic/mod/<key>           float      (modulation-matrix outs, e.g. seq.tempo)
/echoelmusic/bio/event/heartbeat | breath/inhale | breath/exhale | motion
                                 | coherence | eeg   (discrete events)
```

Plus ADM-OSC immersive object out via `ADMOSCSender`: `/adm/obj/{n}/*`.
UDP. Target: <5ms LAN.

---

## PLATFORM NOTES

- **Simulator:** No HealthKit, Push 3, head tracking
- **Push 3:** Requires USB
- **DMX:** Requires network 192.168.1.100
- **Linux:** `apt install libasound2-dev`

---

## DEVELOPMENT WORKFLOW

### Persistent Memory (memory/)

The `memory/` directory is **durable knowledge** that persists across all sessions:

| File | Purpose |
|------|---------|
| `decisions.md` | Architectural and strategic decisions with rationale and review dates |
| `people.md` | Key contributors, collaborators, contacts |
| `preferences.md` | User preferences for workflow, communication, tooling |
| `user.md` | User profile, project vision, working style |

**SESSION START (mandatory):**
1. Read ALL files in `memory/` to restore context
2. Read `scratchpads/SESSION_LOG.md` for recent session history
3. Read `memory/decisions.md` for any decisions due for review

**SESSION END (mandatory):**
1. Update `memory/` files with any new discoveries, decisions, or preferences learned during the session
2. Log new decisions to `memory/decisions.md` AND `decisions.csv` (see Decision Logging below)
3. Update `scratchpads/SESSION_LOG.md` with session summary

### Decision Logging (decisions.csv)

Machine-readable decision log at repo root. Format:
```
date,decision,reasoning,expected_outcome,review_date,status
```

- Log every architectural/strategic decision the user describes
- Review dates default to 30 days from decision date
- Run `./review.sh` to surface decisions due for review
- Daily cron job auto-flags overdue decisions with `REVIEW_DUE`

### Long-Term Memory (scratchpads/)

The `scratchpads/` directory is session-specific logs and plans:

| File | Purpose |
|------|---------|
| `SESSION_LOG.md` | **Read first** — session history, key discoveries, commits |
| `ARCHITECTURE_AUDIT_*.md` | Data flow diagrams, env object chains, init sequence |
| `PLAN_*.md` | Feature/fix plans before implementation |

**Start every session** by reading `memory/` first, then `scratchpads/SESSION_LOG.md`.

### 4-Phase Workflow

**Phase 1 — Plan:**
- Read `scratchpads/SESSION_LOG.md` for context
- Break task into atomic steps (max 5 min each)
- Write plan to `scratchpads/PLAN_<feature>.md`
- Include exact file paths, expected changes, test strategy

**Phase 2 — Implement (TDD):**
- Write failing test FIRST when adding new functionality
- Run `swift test` — confirm RED
- Implement minimal code to pass
- Run `swift test` — confirm GREEN
- Refactor while GREEN

**Phase 3 — Verify:**
- `swift build` must pass (remember: `-warnings-as-errors`)
- `swift test` must pass
- No force unwraps, no divide-by-zero, no missing environmentObjects
- Guard all divisions, guard all array access, guard all optionals

**Phase 4 — Ship:**
- Commit with conventional prefix: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`, `perf:`
- Update `scratchpads/SESSION_LOG.md` with session summary
- Push to feature branch

### Parallel Agent Strategy

For large tasks, use 3-agent parallel audits:
```
Agent 1: Core systems (App entry, init sequence, data flow)
Agent 2: UI layer (Views, environment objects, navigation)
Agent 3: Domain logic (Audio, bio, visual, lighting pipelines)
```

### Code Review Checklist

- [ ] No `@EnvironmentObject` without matching `.environmentObject()` injection
- [ ] No division without guard (`.count`, heartRate, etc.)
- [ ] No `#if os()` missing for platform-specific APIs
- [ ] No hardcoded values where real data should flow
- [ ] All Combine subscriptions stored in cancellables
- [ ] `@MainActor` on all `ObservableObject` classes

---

## UI DESIGN CONSTRAINTS (Uncodixfy)

When generating SwiftUI views, follow clean design principles. Avoid AI-default patterns.

**Reference aesthetic:** Linear, Raycast, Stripe, GitHub — functional, minimal, precise.

**BANNED patterns:**
- Border radii > 16px (no pill shapes, no 20-32px radii)
- Glassmorphism, frosted panels, blur hazes, soft gradients
- Decorative KPI card grids, fake charts, hero sections inside dashboards
- "Eyebrow" labels (tiny uppercase with letter-spacing above headings)
- Glow effects, neon accents, shadow layers > 8px blur
- Transform/scale animations on hover/tap (use opacity/color only)
- Nested panel types (card-in-card, panel-in-panel)
- Decorative copy ("Live Pulse", "Neural Sync", "Quantum Flow")
- Floating cards with large shadows

**REQUIRED patterns:**
- Solid fills or borders on buttons, 8-12px radius max
- Subtle borders (1px, muted color), max 8px shadow blur
- Sidebars: 240-260px fixed, solid background, 1px border
- Forms: labels above inputs, no floating labels, simple focus ring
- Tables: left-aligned text, subtle row hover, clean grid
- Color: use existing palette, dark muted backgrounds, avoid neon
- Transitions: 100-200ms, opacity/color only
- Bio-signal displays: legible numbers first, visualization second
- Flash rate: max 3 Hz (W3C WCAG epilepsy compliance)
- **Parameter rows — ONE control everywhere:** every adjustable numeric parameter (FX, synth
  patch, mix, bio, future modules) uses `EchoelValueField` (label + value + unit, adjusted by a
  vertical-fader drag / tap-to-type). **No raw SwiftUI `Slider`/`Stepper` for parameters.** Tap-to-type
  opens `EchoelNumberPad` — our OWN keypad (the iOS decimal pad can't carry a sign key), with − / +
  at the bottom-left where **− makes the value negative, + positive** (logical for Transpose); − is
  disabled where the range can't go below zero (10.76.44). One keypad app-wide — don't reintroduce the
  system `.decimalPad`/keyboard-toolbar sign buttons. This
  keeps reading + interaction identical app-wide and is science-first (number, not a knob). Dimensionless
  values show as raw decimals (e.g. `0.50`), not `%`. New parameter UI MUST use it; if it can't, raise it
  in The Council before diverging. **Scope:** the main `Echoelmusic` app target. The standalone
  `EchoelmusicAUv3` plugin target is exempt (it compiles `DSP/` only and cannot see `EchoelValueField`,
  a Studio view bound to `EchoelTheme`); its host UI may use plain controls.

**SCIENCE-FIRST display:**
- Real biometric data only — no decorative visualizations
- HR, HRV, coherence: large legible numbers, small trend sparklines
- No "control room cosplay" or "premium dashboard" aesthetic
- Every visual element must reflect actual data or serve a control function

---

## DO NOT

- Restructure project without approval
- Add dependencies without asking
- Create new targets or top-level dirs
- Modify Info.plist / CI config without asking
- Use force unwrap, `print()`, `ObservableObject`, `UIScreen.main`
- Simplify Rausch DSP algorithms
- Allocate memory on audio thread
- Batch unrelated fixes
- Add features during fix cycles
- Use esoteric terminology

---

## THE COUNCIL (always-on, optimized)

Before any **significant or hard-to-reverse** decision — architecture, scope
changes, >1 file, audio-thread / protected Rausch triad, user-facing copy,
ambiguous founder asks, or deploy/delete/publish — **convene The Council**
(`.claude/skills/the-council/SKILL.md`). Fixed seats (Architect · DSP Purist ·
Vision-Keeper · Shipper · Skeptic · User-Advocate) each give a one-line position
+ sharpest concern; dissent is surfaced, not smoothed; synthesize ONE cheapest
next step + a gate (proceed / mitigate / hold-for-founder). **Skip trivial
reversible actions** — convening on trivia is the failure mode. Composes with
`vision-gate` and the Ralph Wiggum loop; never overrides explicit founder
instructions or the hard rules above.

**Marketing:** to market Echoel (App Store/ASO, website `docs/`, launch, pricing,
social, PR, SEO), use the `echoel-marketing` skill — the Echoel-tuned front door
over the vendored MIT pack at `.claude/skills/marketing/` (Corey Haines, 45
skills). It enforces brand guardrails (no wellness/esoteric/overclaim, claim only
what ships) and is **PIPELINE only — never shipped in-app, never touches `Sources/`**.

## ACTIVATION

```
ECHOEL MODE ACTIVE
Branch: [branch]  Build: [number]
Priority: [errors | failures | task]
Mode: Ralph Wiggum Lambda — Fix → Build → Test → Ship → Loop
```

No intro. Audit → Fix → Build → Loop.
