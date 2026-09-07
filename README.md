# Echoelmusic

**Physical Computing · Biofeedback · Multimedial & Multidimensional.**

An immersive, iPhone-first instrument for **Installation · Event · Content · Cinema · Theater · Performance.** Your body plays it: heart and breath drive sound, image, light and immersive space in real time, through a typed pub/sub bus that external controllers and stage tools can subscribe to.

[![iOS](https://img.shields.io/badge/iOS-18+-black.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.10%20tools%20%C2%B7%20strict%20concurrency-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> Shipping to TestFlight. Development happens on a feature branch — run `git branch --show-current` rather than trusting a name written here; the pinned literal in this file was wrong for months. Project doctrine, current state and the open-work ledger live in [`CLAUDE.md`](./CLAUDE.md).

---

## Positioning

This is not a DAW, and catching one on its own axis is not possible solo. Echoelmusic is an **instrument**: it is about the sound being made *now*, not about arranging material over time. The timeline, the clip/arrangement UI and video editing were built and then deliberately removed in July 2026 to keep that boundary sharp. Multitrack recording is a different case and worth stating precisely: it is *built*, but feature-flagged off with no door, so it is not part of the app you install.

What it does have, structurally, is **biofeedback as a first-class modulation source on a typed bus**:

- **Bio is input.** Heart rate, HRV (RMSSD normalized), breath rate + phase, and coherence (HRV spectrum) are published as `BioSampleFrame` onto `EngineBus`. Sources: HealthKit, camera rPPG (on-device), any BLE chest strap speaking standard Heart Rate Service (0x180D), plus a simulation you can pick by hand when you have no sensor.
- **MIDI is input here.** CoreMIDI notes, per-channel pitch bend, CC 74 and CC 21–31 (air controllers) arrive as `ControllerEvent`. Those events reach ONE monophonic performer voice, and all three of MPE's continuous dimensions now move it — pitch bend, Press (channel pressure, #939) and Slide (CC 74, #942). It is still **not MPE input**: master/member disambiguation and RPN 6,6 zone detection are absent, so there is no member channel to tell apart, and it is ONE monophonic voice. See the header of `Sync/MIDIBusPublisher.swift`. This bullet is about the BUS: MIDI note OUT and MIDI file export exist and are listed under the output stage below. Outbound expression (pitch bend, CC 74, channel pressure) is gated behind `mpeEnabled`/`expressionEnabled`, and since #713 both flags are written by `MIDIOutput.applyOutputPreferences()`, which reads the two persisted keys the routing panel's "MPE note layout" and "Per-note expression" switches set. Both default OFF, so a fresh install is note-only MIDI 1.0 — but **MPE out is reachable and real**: the zone is announced, notes are spread over member channels 2–16, and each carries Glide, Slide (CC 74) and Press. The *input* half is the one that is not MPE: the dimensions arrive and sound, the ZONE does not.
- **DSP, visuals, lighting and network out are subscribers.** Anything reading from the bus can be bio- or controller-modulated without point-to-point coupling.
- **Science-only.** No "healing frequencies", no chakras, no Solfeggio mythology. Mappings reference peer-reviewed sources (Lehrer/Vaschillo HRV resonance frequency, Polar H10 validation, DELLY / Tracy bio-signal processing). Data is for self-observation, not medical diagnosis.

---

## One screen, one bus

The root view is `WorkspaceView` — brand header and one surface below it, `EchoelStudioView` (the transport controls live inside the instrument). Not a TabView. The front plate carries the single **Create from Within** button: the bio-generative flow that writes in-key melody, harmony, rhythm and tempo from your body across curated genres. Everything else is a panel.

**Eight chips render in the tab strip** (`EchoelStudioView.studioChips`, in strip order):

| Chip | What it does |
|---|---|
| **Sound** | Patch editor — presets, tone/filter/envelope/space and vibrato, randomize, save-as |
| **FX** | EchoelFX chain — stamp a character, then per-stage panels; presets with search and favorites |
| **Mix** | Level per part |
| **Master** | Master target and tone, and the routing patchbay door |
| **Mood** | Production character |
| **Tempo** | Tempo and variations — tap tempo, metronome, haptic beat, variation ideas |
| **Field** | The immersive visual's look controls, plus the touch-playable surface below them — quantized with micro-timing, and able to play itself (self-play + arpeggiator) |
| **Save/Export** | Save/open the project, loop length, WAV loop render, Standard MIDI File (.mid) export, reset sound, and the diagnostics log (share it after a device problem) |

**Two more panels open without a chip:** Bio (HR · HRV · Breath · Coherence with tap-to-learn — tap the pulse pill in the header, or long-press it) and Video (recorded clips, inline playback, mp4 share — the header tile). The immersive visual itself is the floating window toggled from the header monitor, with a full-screen door inside the Field panel.

Network routing (OSC · ADM-OSC · Art-Net · sACN · MIDI out) is a patchbay reached from the Master panel, the Bio panel and the header lighting tile.

`BioStripView` lives inside the Bio panel, not as an always-on strip. That is deliberate: a ~10 Hz reading in an always-mounted ancestor — `WorkspaceView` or any permanent header — rebuilds the whole view tree and tears down any open menu. See the freeze law in `CLAUDE.md`.

**Not planned, not roadmap** — RTMP / live streaming, video editing, and the Clips/Arrangement UI. Video editing and the Clips/Arrangement UI were built and removed in July 2026; RTMP was never built — `BroadcastPublisher` is a compile-guarded scaffold and HaishinKit is not a dependency. A broadcast stack would be a second product. See [`docs/dev/FEATURE_MATRIX.md`](./docs/dev/FEATURE_MATRIX.md).

---

## What ships today

- **`EngineBus`** (`Core/EngineBus.swift`) — hybrid isolation: `@MainActor @Observable` control plane for SwiftUI snapshots; lock-free `SPSCQueue` data plane for audio-thread consumers. Three typed topics: `bioFrames`, `controllerEvents`, `bioEvents`. Bio flows over the `latestBio` snapshot polled at 10 Hz; `controllerEvents` is the queue that is drained and consumed (MIDI). `bioEvents` is drained by exactly one consumer, `OSCSender.drainAndSendEvents` (OSC egress only — no synth reads it), and `bioFrames` is never drained at all: the snapshot is the correct path for a slow signal.
- **Bio publishers**, all pushing source-tagged `BioSampleFrame`:
  - `HealthKitBioPublisher` — polls `EchoelBioEngine.snapshot`.
  - `CameraRPPGBioPublisher` — on-device photoplethysmography from the rear camera; locks a pulse without extra hardware.
  - `PolarH10BioPublisher` — CoreBluetooth direct, no vendor SDK, parses BLE HR Measurement (0x180D / 0x2A37) including RR intervals.
  - `BioSimulator` — a walk around 72 BPM, offered in the pulse pill's menu as "Play with the simulation" so the instrument is playable with no sensor at all. It ships in Release; only its *automatic* start is DEBUG-gated, and it defers the moment a real source publishes.
- **Synthesis** — `EchoelDDSP` (harmonic + noise, bio-reactive), `PolySynthVoice`, `SubBassVoice`, `EchoelFX` chain, master `AutoMixChain` with true-peak trim.
- **Output stage** — generative Metal visuals, Art-Net and sACN lighting, ADM-OSC immersive object positions, OSC bio egress, MIDI out and MIDI file export.
- **Protected DSP triad** — `BioEventGraph`, `HilbertSensorMapper`, `BioSignalDeconvolver`. Read-only contracts under `.claude/skills/`; do not simplify.

Known gaps are tracked honestly in `CLAUDE.md` rather than implied here.

---

## Build

Requires Xcode 26.2 and a recent macOS (CI runs `macos-26`). iPhone-only for v10 (other Apple platforms compile-clean but are not deliverables). Zero external dependencies.

**There is no `.xcodeproj` in the repository** — it is generated by [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`, so that step is not optional:

```bash
git clone https://github.com/vibrationalforce/Echoelmusic.git
cd Echoelmusic
xcodegen generate --spec project.yml                     # required first
xcodebuild -scheme Echoelmusic -sdk iphonesimulator      # the iOS app
swift build                                              # SPM library only
```

`swift test` builds `Tests/EchoelmusicTests`, which is the large exploratory suite and is *not* what gates a merge — no workflow runs it under SwiftPM, and it is allowed to be red. The blocking bundle is `Tests/CISmoke`, built and run by the `Echoelmusic CI/CD Pipeline` workflow through the Xcode scheme.

TestFlight runs from `.github/workflows/testflight.yml`, two ways:

```bash
# Explicit dispatch
gh workflow run testflight.yml -f platform=ios -f build_only=false

# Or tokenless: bumping `.deploy/release` on any branch triggers an iOS deploy.
# Ordinary code pushes never deploy — only an explicit bump of that file.
```

---

## Project structure

```
Sources/Echoelmusic/
  Core/          EngineBus, SPSCQueue, ProfessionalLogger, MemoryPressureHandler,
                 FloatingPointClamp, EchoelDecimalText, ModulationEngine, EchoelStore,
                 EchoelParameterRegistry, CloudSync
  Bio/           EchoelBioEngine (HealthKit), HealthKitBioPublisher,
                 CameraRPPGBioPublisher, PolarH10BioPublisher, BioSimulator,
                 BreathPacer, ResonanceFinder, HRVCoherence, HRVMetrics,
                 BioEventGraph / HilbertSensorMapper / BioSignalDeconvolver (protected)
  DSP/           EchoelDDSP, EchoelCellular, EchoelModalBank, EchoelVDSPKit,
                 EchoelSVFilter, EchoelLFO, EchoelEntrainment, EchoelDynamics
  Audio/         AudioEngine, AudioConfiguration, MIDIInput, RetroCapture,
                 AutoMixChain, SingleExport, MultiTrackRecorder (flag-gated off)
  Sequencer/     PatternEngine (transport clock), FieldAutoPlay, ArpFigure,
                 RoleRhythm, NoteNaming, SamplerVoice, BeatPlayer
  Tools/         PolySynthVoice, SubBassVoice, BioReactiveSynthVoice, breath/vocal tools
  Video/         CameraCapture, CameraAnalyzer, RPPGConditioning (the rPPG path),
                 VideoRecorder, VisualRecorder, VideoMuxer  — capture only, no editing
  Sync/          OSCSender, ADMOSCSender, ArtNetSender, SACNSender, MIDIBusPublisher
  Studio/        WorkspaceView (root), EchoelStudioView (the surface), BioStripView,
                 EchoelFXView,
                 TouchInstrumentView, FloatingVisualWindow, PatchbayView, EchoelTheme
  Views/         MetalBioView, OnboardingView
  EchoelAI/      BrainBackend, FoundationModelsBrain, ParameterToolCore — three files,
                 no production caller today (the echoelAI flag has zero readers); the parameter registry itself lives in Core/
  Stream/        BroadcastPublisher — a compile guard only; HaishinKit is not a dependency
  Resources/     bundled assets
  (plus the two loose files EchoelmusicApp.swift and MicrophoneManager.swift)
Sources/EchoelmusicWidgets/  WidgetKit extension, embedded in the app
Sources/EchoelmusicWatch/    watchOS app — present but NOT embedded (dependency off in project.yml)
Tests/CISmoke/               the blocking gate bundle
Tests/EchoelmusicTests/      the large exploratory suite (runs non-blocking)
```

See [`CLAUDE.md`](./CLAUDE.md) for project doctrine, current state and the open-work ledger, and [`docs/dev/FEATURE_MATRIX.md`](./docs/dev/FEATURE_MATRIX.md) for the per-feature shipping status.

---

## License

MIT. See [LICENSE](./LICENSE).

---

## Author

[Michael Terbuyken](https://github.com/vibrationalforce) · Studio Hamburg
