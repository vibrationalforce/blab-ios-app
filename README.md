# Echoelmusic

**Physical Computing · Biofeedback · Multimedial & Multidimensional.**

An immersive, iPhone-first instrument for **Installation · Event · Content · Cinema · Theater · Performance.** Your body plays it: heart and breath drive sound, image, light and immersive space in real time, through a typed pub/sub bus that external controllers and stage tools can subscribe to.

[![iOS](https://img.shields.io/badge/iOS-18+-black.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> Shipping to TestFlight. Development happens on a feature branch — run `git branch --show-current` rather than trusting a name written here; the pinned literal in this file was wrong for months. Project doctrine, current state and the open-work ledger live in [`CLAUDE.md`](./CLAUDE.md).

---

## Positioning

This is not a DAW, and catching one on its own axis is not possible solo. Echoelmusic is an **instrument**: it is about the sound being made *now*, not about arranging material over time. Timeline, clips, multitrack and video editing were built and then deliberately removed in July 2026 to keep that boundary sharp.

What it does have, structurally, is **biofeedback as a first-class modulation source on a typed bus**:

- **Bio is input.** Heart rate, HRV (RMSSD normalized), breath rate + phase, and coherence (HRV spectrum) are published as `BioSampleFrame` onto `EngineBus`. Sources: HealthKit, camera rPPG (on-device), any BLE chest strap speaking standard Heart Rate Service (0x180D), plus a DEBUG simulator.
- **MIDI is input.** CoreMIDI notes, per-channel pitch bend and CC 74 arrive as `ControllerEvent`. Full MPE (master/member disambiguation, RPN 6,6 zones, channel pressure) is *not* wired — see the header of `Sync/MIDIBusPublisher.swift`.
- **DSP, visuals, lighting and network out are subscribers.** Anything reading from the bus can be bio- or controller-modulated without point-to-point coupling.
- **Science-only.** No "healing frequencies", no chakras, no Solfeggio mythology. Mappings reference peer-reviewed sources (Lehrer/Vaschillo HRV resonance frequency, Polar H10 validation, DELLY / Tracy bio-signal processing). Data is for self-observation, not medical diagnosis.

---

## One screen, one bus

The app is **one** `EchoelStudioView` — not a TabView. A menu bar of chips opens one panel each, over a one-button bio-generative flow.

| Surface | What it does |
|---|---|
| **Compose** | Bio-generative one-button flow — in-key melody, harmony, rhythm and tempo from the body, across curated genres |
| **Sound** | Patch editor — presets, tone/filter/envelope/space, randomize, save-as |
| **FX** | EchoelFX chain — stamp a character, then per-stage panels; presets with search and favorites |
| **Field** | Touch-playable surface, quantized with micro-timing; can also play itself (self-play + arpeggiator) |
| **Mix** | Level per part |
| **Bio** | HR · HRV · Breath · Coherence, tap-to-learn, source picker, resonance breath pacer |
| **Video** | Recorded clips from the immersive visual window — inline playback, mp4 share |
| **Export** | Loop render to WAV, MIDI file export |

Network routing (OSC · ADM-OSC · Art-Net · sACN · MIDI out) is a patchbay reached from the Master and Bio panels, not its own chip.

`BioStripView` lives inside the Bio panel, not as an always-on strip. That is deliberate: a ~10 Hz reading in an always-mounted ancestor rebuilds the whole view tree and tears down any open menu. See the freeze law in `CLAUDE.md`.

**Not planned, not roadmap** — RTMP / live streaming, video editing, multitrack audio, and the Clips/Arrangement UI. Most were built and removed in July 2026. A broadcast stack would be a second product. See [`docs/dev/FEATURE_MATRIX.md`](./docs/dev/FEATURE_MATRIX.md).

---

## What ships today

- **`EngineBus`** (`Core/EngineBus.swift`) — hybrid isolation: `@MainActor @Observable` control plane for SwiftUI snapshots; lock-free `SPSCQueue` data plane for audio-thread consumers. Three typed topics: `bioFrames`, `controllerEvents`, `bioEvents`. Bio flows over the `latestBio` snapshot at 10 Hz; the SPSC queue is drained for MIDI.
- **Bio publishers**, all pushing source-tagged `BioSampleFrame`:
  - `HealthKitBioPublisher` — polls `EchoelBioEngine.snapshot`.
  - `CameraRPPGBioPublisher` — on-device photoplethysmography from the rear camera; locks a pulse without extra hardware.
  - `PolarH10BioPublisher` — CoreBluetooth direct, no vendor SDK, parses BLE HR Measurement (0x180D / 0x2A37) including RR intervals.
  - `BioSimulator` — DEBUG only; compiled out of Release, defers when a real source publishes.
- **Synthesis** — `EchoelDDSP` (harmonic + noise, bio-reactive), `PolySynthVoice`, `SubBassVoice`, `EchoelFX` chain, master `AutoMixChain` with true-peak trim.
- **Output stage** — generative Metal visuals, Art-Net and sACN lighting, ADM-OSC immersive object positions, OSC bio egress, MIDI out and MIDI file export.
- **Protected DSP triad** — `BioEventGraph`, `HilbertSensorMapper`, `BioSignalDeconvolver`. Read-only contracts under `.claude/skills/`; do not simplify.

Known gaps are tracked honestly in `CLAUDE.md` rather than implied here.

---

## Build

Requires Xcode 26.2+ on macOS 15+. iPhone-only for v10 (other Apple platforms compile-clean but are not deliverables). Zero external dependencies.

```bash
git clone https://github.com/vibrationalforce/Echoelmusic.git
cd Echoelmusic
swift build                                              # SPM build
xcodebuild -scheme Echoelmusic -sdk iphonesimulator      # Xcode build
swift test                                               # test suite
```

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
                 FloatingPointClamp, EchoelDecimalText, ModulationEngine, EchoelStore
  Bio/           EchoelBioEngine (HealthKit), HealthKitBioPublisher,
                 CameraRPPGBioPublisher, PolarH10BioPublisher, BioSimulator (DEBUG),
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
  Sync/          OSCSender, ADMOSCSender, ArtNetSender, SACNSender, CloudSync
  Studio/        EchoelStudioView (root), WorkspaceView, BioStripView, EchoelFXView,
                 TouchInstrumentView, FloatingVisualWindow, PatchbayView, EchoelTheme
  Views/         MetalBioView, OnboardingView
  EchoelAI/      Parameter registry + model-free tool logic (flag-gated off by default)
  Stream/        BroadcastPublisher — a compile guard only; HaishinKit is not a dependency
Tests/CISmoke/          the blocking gate bundle
Tests/EchoelmusicTests/ the full suite (runs non-blocking)
```

See [`CLAUDE.md`](./CLAUDE.md) for project doctrine, current state and the open-work ledger, and [`docs/dev/FEATURE_MATRIX.md`](./docs/dev/FEATURE_MATRIX.md) for the per-feature shipping status.

---

## License

MIT. See [LICENSE](./LICENSE).

---

## Author

[Michael Terbuyken](https://github.com/vibrationalforce) · Studio Hamburg
