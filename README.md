# Echoelmusic

**The first bio-reactive performance instrument.**

What Loopy Pro, Bitwig, and TouchDesigner together cannot do: a single iPhone app where every sound, modulation, and visual is driven by your live physiology — heart rate, HRV, breath, motion, brain rhythms — through a typed pub/sub bus that any external controller, DAW, or stage tool can subscribe to.

[![iOS](https://img.shields.io/badge/iOS-18+-black.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Status](https://img.shields.io/badge/Status-Foundation%20%E2%86%92%20Skelett-blue.svg)](./scratchpads/PLAN_FOUNDATION_SEQUENCE.md)

> Pre-TestFlight. Foundation cycles in progress on `claude/audit-echoelmusic-foundation-Q9OYQ`. See `scratchpads/STRATEGY_2026-05-18.md` and `scratchpads/PLAN_FOUNDATION_SEQUENCE.md` for the sequenced roadmap.

---

## Positioning

We are not building a better DAW. Loopy Pro 2.0 is more mature; Bitwig has 231 Grid modules; Ableton has 10,000+ Max-for-Live devices; TouchDesigner is the GPU-visual gold standard. Catching them on their own axis is not possible solo.

What none of them have, structurally, is **biofeedback as a first-class modulation source on a typed bus**. That is the Echoelmusic axis:

- **Bio is input.** Heart rate, HRV (RMSSD normalized), breath rate + phase, coherence (HRV spectrum), motion energy — published as `BioSampleFrame` onto `EngineBus`.
- **MPE + air controllers are input.** ROLI Seaboard 2 and Network-MIDI air-CC dimensions arrive as `ControllerEvent`.
- **DSP, visuals, lighting, OSC out are subscribers.** Anything that reads from the bus can be bio- or controller-modulated without point-to-point coupling.
- **Science-only.** No "healing frequencies", no chakras, no Solfeggio mythology. Mappings reference peer-reviewed sources (Lehrer/Vaschillo HRV resonance frequency, Sensors 2026 Polar H10 validation, DELLY / Tracy bio-signal processing).

---

## Suite (four tabs, one bus)

| Tab | Module | Status |
|---|---|---|
| **Tools** | Bio-reactive synth voices and pattern engines (EchoelDDSP, EchoelCellular, EchoelModalBank, EchoelVDSPKit; PatternEngine + SamplerVoice for the beat lineage) | DSP exists, bus subscription cycle next |
| **Works** | Sessions, recordings, DAW handoff (MultiTrackRecorder, RetroCapture, AutoMixChain, SingleExport) | Modules compile, integration after Tools |
| **Sync** | OSC + MIDI + MPE + air controllers (`MIDIInput`, future `OSCSender`, MPE zone detection, CC 21-31 air dimensions) | MIDIInput parses, bus-publish wiring next |
| **Well** | Evidence-based breath and coherence guidance (Polar H10 ground-truth, HealthKit fallback, breath pacer) | Bio publishers live, guidance UI later |

---

## Foundation status

What ships today on the foundation branch:

- **`EngineBus`** (`Core/EngineBus.swift`) — hybrid isolation: `@MainActor @Observable` control plane for SwiftUI snapshots; lock-free `SPSCQueue` data plane for audio-thread consumers. Three typed topics: `bioFrames`, `controllerEvents`, `bioEvents`.
- **Bio publishers** (all push `BioSampleFrame` onto the bus, source-tagged):
  - `HealthKitBioPublisher` — polls `EchoelBioEngine.snapshot`, source `.healthKit`.
  - `PolarH10BioPublisher` — CoreBluetooth direct, no SDK, parses BLE HR Measurement (0x180D / 0x2A37) including RR intervals, computes RMSSD-normalized HRV, source `.ble`.
  - `BioSimulator` — DEBUG only, walks values around 72 BPM, source `.fallback`. Compiled out of Release; defers when a real source publishes.
- **`BioStripView`** — top strip in StudioRoot showing HR / HRV / Br / Coh + source tag, reading `EngineBus.latestBio`. Honest empty state in Release ("No source" + em-dashes) before a publisher fires.

What is contracted but not yet implemented:

- **Protected DSP triad** — `BioEventGraph`, `HilbertSensorMapper`, `BioSignalDeconvolver`. SKILL.md read-only contracts committed at `.claude/skills/` so future cycles know the boundary before code lands.

What does not exist yet:

- Any subscriber to `EngineBus` (the deep audit at `scratchpads/DEEP_AUDIT_CONNECTION_MAP_2026-05-22.md` lists actionable wiring candidates — `EchoelDDSP.applyBioReactive(…)` is ready, the bus adapter is the missing link)
- OSC out (cycle V1)
- CoreMIDI MPE zone detection + bus publish (cycle S5)
- Modulation matrix (cycle V3)
- EchoelLoop canvas module (planned Q2 2027 per strategy)

---

## Build

Requires Xcode 26.2+ on macOS 15+. iPhone-only for v10 (other Apple platforms compile-clean but are not deliverables).

```bash
git clone https://github.com/vibrationalforce/Echoelmusic.git
cd Echoelmusic
swift build                                              # SPM build
xcodebuild -scheme Echoelmusic -sdk iphonesimulator      # Xcode build
```

TestFlight via `.github/workflows/testflight.yml`:

```bash
gh workflow run testflight.yml -f platform=ios -f build_only=false
```

---

## Project structure

```
Sources/Echoelmusic/
  Core/          EngineBus, EchoelStore, SPSCQueue, ProfessionalLogger,
                 MemoryPressureHandler, PlatformAvailability, SessionStore
  Bio/           EchoelBioEngine (HealthKit), HealthKitBioPublisher,
                 PolarH10BioPublisher, BioSimulator (DEBUG),
                 BioSourceManager / MotionActivityProvider / OuraRingClient (dormant)
  DSP/           EchoelDDSP (1237 LOC, applyBioReactive ready),
                 EchoelCellular, EchoelModalBank, EchoelVDSPKit,
                 EchoelSVFilter, EchoelLFO, EchoelEntrainment
  Audio/         AudioEngine, AudioConfiguration, MIDIInput, RetroCapture,
                 AutoMixChain, SingleExport, MultiTrackRecorder
  Sequencer/     PatternEngine, SamplerVoice, BeatPlayer
  Video/         CameraCapture, CameraAnalyzer, ShortContentRenderer
  Studio/        StudioRoot, BeatTab, BioStripView
  Views/         (deprecated v8/v9 surfaces, compilable but off main flow)
Sources/EchoelmusicAUv3/
                 AUv3 Generator plugin (deferred)
Tests/EchoelmusicTests/
                 EngineBus, PolarH10BioPublisher, plus existing audio
                 / sampler / sequencer / vDSP / DDSP suites
```

See `CLAUDE.md` for project doctrine, `scratchpads/PLAN_FOUNDATION_SEQUENCE.md` for the cycle ledger, `scratchpads/STRATEGY_2026-05-18.md` for the competitive positioning analysis, and `scratchpads/DEEP_AUDIT_CONNECTION_MAP_2026-05-22.md` for the current wiring inventory.

---

## License

MIT. See [LICENSE](./LICENSE).

---

## Author

[Michael Terbuyken](https://github.com/vibrationalforce) · Studio Hamburg
