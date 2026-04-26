# Echoel

**Make Beats. Record Video. Stream Live.**

A unified iPhone studio that combines a mobile DAW, a video editor, and an RTMP live streamer in one app — built for creators who today juggle FL Studio Mobile, Ableton, the iPhone Camera, InShot, and OBS.

[![iOS](https://img.shields.io/badge/iOS-26+-black.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![TestFlight](https://img.shields.io/badge/TestFlight-2026--05--17-blue.svg)](https://testflight.apple.com/)

> Status: v10 sprint in progress — TestFlight upload target **2026-05-17**.

---

## What it does

| Tab | What you do |
|---|---|
| **Beat** | 16-step × 8-track drum sequencer with sampler pads. Tap pads, paint steps, set tempo, hit play. |
| **Record** | Sing, rap, or record an instrument over the beat. Multi-track with sample-accurate sync. |
| **Video** | Capture 1080p30 video on the iPhone camera with the beat as audio bed. Trim in/out. |
| **Share** | Live-stream RTMP to YouTube / Twitch / Facebook / any custom URL. Or export MP4 + WAV. |

---

## Why one app

Today's mobile creator workflow:

```
FL Studio Mobile → AirDrop → Ableton (Mac) → AirDrop → iPhone Camera → InShot → Upload
                ↓                                                              ↑
              OBS (Mac)  ─────────── stream ──────────────────────────────────┘
```

Echoel collapses this into one iPhone app. No file shuffling, no app switching.

---

## Tech

| Layer | Choice |
|---|---|
| Platform | iOS 26 (iPhone-only for v10 MVP) |
| Audio | AVAudioEngine, AVAudioSourceNode, Accelerate |
| Sequencer | Sample-accurate tempo clock via audio-thread tick counting |
| Video | AVCaptureSession (1080p30), AVAssetWriter (H.264 + AAC), Metal filters |
| Streaming | HaishinKit (RTMP/RTMPS) — sole external dependency |
| MIDI | CoreMIDI |
| Persistence | SwiftData |
| UI | SwiftUI + `@Observable` (Swift 6 strict concurrency) |
| Build | Xcode 26.2, SPM, Fastlane (TestFlight upload) |

---

## Build

Requires Xcode 26.2+ on macOS 15+.

```bash
git clone https://github.com/vibrationalforce/Echoelmusic.git
cd Echoelmusic
swift build                    # SPM build (CLI verification)
xcodebuild -scheme Echoelmusic -sdk iphonesimulator   # Xcode build
```

For TestFlight builds, see `.github/workflows/testflight.yml` — triggered via:

```bash
gh workflow run testflight.yml -f platform=ios -f build_only=false
```

---

## Project structure

```
Sources/Echoelmusic/
  Audio/         AVAudioEngine, RetroCapture, AutoMixChain, SingleExport
  Sequencer/     PatternEngine, SamplerVoice         (built in W1 of sprint)
  Video/         CameraSession, VideoRecorder, ClipTrimmer  (W2)
  Stream/        RTMPPublisher                        (W3)
  Studio/        StudioRoot, BeatTab, RecordTab, VideoTab, ShareTab  (W1–W3)
  Core/          EchoelStore, SPSCQueue, ProfessionalLogger
  DSP/           EchoelDDSP, EchoelCellular  (reused as synth voices)
  Bio/           Protected algorithms (BioEventGraph, HilbertSensorMapper, BioSignalDeconvolver)
```

See [`CLAUDE.md`](./CLAUDE.md) for the full project doctrine and [`scratchpads/PLAN_v10_TestFlight_Sprint.md`](./scratchpads/PLAN_v10_TestFlight_Sprint.md) for the active sprint plan.

---

## License

MIT. See [LICENSE](./LICENSE).

---

## Author

[Michael Terbuyken](https://github.com/vibrationalforce) · Studio Hamburg
