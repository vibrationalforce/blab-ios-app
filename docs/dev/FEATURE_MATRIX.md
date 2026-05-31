# FEATURE MATRIX — Echoelmusic v10 (the "second brain")

**Canonical map: marketing tool ↔ real code ↔ status ↔ TestFlight acceptance.**

This is the single source of truth that ties the *website* (the 12 "Echoel\*"
tools, which are conceptual groupings — **not** Swift types) to the *code* (real
modules) and to *TestFlight readiness*. Read this first when building toward a
TestFlight release: locate the tool, jump to its files, check its status and
acceptance line.

- **Public mirror:** `docs/architecture.html` (LIVE vs ROADMAP) and `docs/tools.html`.
- **Truth-source for status:** this file + the code. If the website disagrees, the code wins.
- **Status legend:** `LIVE` = ships in build #1 · `PARTIAL` = some live, rest roadmap · `ROADMAP` = no code yet.

> The "12 tools" are a taxonomy over the real modules. E.g. *EchoelSynth* is the
> group {EchoelDDSP, EchoelCellular, EchoelModalBank, EchoelPolyDDSP, SamplerVoice}.
> There is no `EchoelSynth` type.

---

## Spine & infrastructure (not a "tool", but everything routes through it)

| Module | File | Notes |
|---|---|---|
| EngineBus | `Sources/Echoelmusic/Core/EngineBus.swift` | `@MainActor @Observable` control plane + lock-free `SPSCQueue` data plane. 3 topics: `bioFrames` / `controllerEvents` / `bioEvents`. Modules produce/consume here, never couple directly. |
| SPSCQueue | `Sources/Echoelmusic/Core/SPSCQueue.swift` | Lock-free single-producer/single-consumer ring; audio-thread safe. |
| AudioEngine | `Sources/Echoelmusic/Audio/AudioEngine.swift` | `AVAudioEngine` master bus. Attach source nodes **before** `start()`. |
| Store / Logger | `Core/EchoelStore.swift`, `Core/ProfessionalLogger.swift` (`EchoelLogger`) | Persistence; `os_log` wrapper (never `print`). |

---

## The 12 tools

### 1. EchoelSynth — `LIVE`
- **Code:** `DSP/EchoelDDSP.swift`, `DSP/EchoelCellular.swift`, `DSP/EchoelModalBank.swift`, `EchoelPolyDDSP`, `Sequencer/SamplerVoice.swift`, `Tools/BioReactiveSynthVoice.swift`
- **Live:** DDSP / modal / cellular synthesis; one-shot sampler; bio-reactive voice (HR→vibrato, HRV→brightness, coherence→harmonicity, breath→envelope), audible via `AVAudioSourceNode` → master mixer.
- **Roadmap:** EchoelBeat, breakbeat chopper, spectral morph.
- **TestFlight acceptance:** tapping play on `BioStripView` opens the envelope and produces sound; bio frames audibly modulate timbre.

### 2. EchoelFX — `PARTIAL`
- **Code:** `DSP/EchoelSVFilter.swift`, `DSP/EchoelLFO.swift`, `EchoelConvolution` (reverb, in EchoelDDSP), `Audio/AutoMixChain.swift`, `DSP/EchoelVDSPKit.swift`
- **Live:** convolution reverb (HRV-reactive), 4-band EQ + LUFS auto-gain (−14 LUFS, 4 presets), LFO-swept SVF, soft `tanh` saturation.
- **Roadmap:** delay, chorus/flanger/phaser/tremolo, dedicated compressor/limiter, analog (VCA/Opto/FET/VariMu/Tube) emulations.
- **TestFlight acceptance:** export path applies AutoMix to −14 LUFS without clipping.

### 3. EchoelMix — `PARTIAL`
- **Code:** `Audio/AudioEngine.swift`, `Audio/AutoMixChain.swift`, `Audio/SingleExport.swift`, `Audio/RetroCapture.swift`, `MicrophoneManager.swift`
- **Live:** master bus, mic FFT (1024-pt), 30 s stereo pre-roll ring (`.caf`), LUFS-normalized WAV/AAC export.
- **Roadmap:** `Audio/MultiTrackRecorder.swift` (skeleton), console UI, FLAC/ALAC, stem export.
- **TestFlight acceptance:** SingleExport writes a valid −14 LUFS WAV/AAC.

### 4. EchoelSeq — `LIVE`
- **Code:** `Sequencer/PatternEngine.swift`, `Sequencer/BeatPlayer.swift`, `Sequencer/SamplerVoice.swift`
- **Live:** 8 tracks × 16 steps, 30–300 BPM, 16th-note clock (`step = (60/BPM)/4 s`), on/off steps.
- **Roadmap:** per-step velocity/probability, automation, Euclidean / polyrhythm.
- **TestFlight acceptance:** `BeatTab` plays a pattern at the set BPM; play/stop responds.

### 5. EchoelMIDI — `LIVE`
- **Code:** `Audio/MIDIInput.swift`, `Sync/MIDIBusPublisher.swift` → `EngineBus.controllerEvents`
- **Live:** MIDI 2.0 + MPE input (per-note bend, slide/CC74, air-CC) → bio-modulated synth notes (performer priority over breath).
- **Roadmap:** Standard MIDI File I/O, MIDI output, touch instruments, audio-to-MIDI.
- **TestFlight acceptance:** an external MPE controller triggers synth notes.
- **Fixed:** `MIDIInput.swift:94` force-cast (`as! UInt32`) → crash-safe `compactMap { as? UInt32 }` (behavior-preserving; the word tuple is homogeneous UInt32).

### 6. EchoelBio — `LIVE`
- **Code:** `Core/EngineBus.swift` (`BioSampleFrame`), `Bio/HealthKitBioPublisher.swift`, `Bio/PolarH10BioPublisher.swift`, `Bio/BioSimulator.swift`, `Bio/EchoelBioEngine.swift`, `Bio/BioEventPublisher.swift`
- **Protected DSP triad (read-only, do not simplify):** `Bio/BioEventGraph.swift`, `Bio/HilbertSensorMapper.swift`, `Bio/BioSignalDeconvolver.swift`
- **Live:** HealthKit + Polar H10 (BLE direct, 0x2A37 + RR→RMSSD) + Demo → `bioFrames`; breath/motion onset events via BioEventGraph.
- **Roadmap:** face tracking (ARKit), raw PPG/ECG waveform → real `.heartbeat` events (Polar PMD service).
- **TestFlight acceptance:** `BioStripView` shows live HR/HRV/Br/Coh; Demo source works on Simulator (HealthKit/BLE need device).

### 7. EchoelVis — `PARTIAL`
- **Code:** `Video/Shaders/VisualRendererKernels.metal`, `Video/Shaders/ChromaKey.metal`, `Views/MetalBioView.swift`, `Views/BioVisualRenderer.swift`
- **Live:** Metal render at 120 fps, 5 visual modes, 6-pass chroma key.
- **Roadmap:** generative & AR worlds, Hilbert-map display, flow field, kaleidoscope, nebula.
- **TestFlight acceptance:** a Metal visual renders without GPU validation errors at ≥60 fps.

### 8. EchoelVid — `PARTIAL`
- **Code:** `Video/CameraCapture.swift`, `Video/CameraAnalyzer.swift`, `Video/ShortContentRenderer.swift`
- **Live:** camera capture; short-form H.264 MP4 720×1280 (9:16), 30 fps, 15/30/60 s.
- **Roadmap:** NLE editor, multi-cam, H.265/ProRes, 1080p/4K, LUT color grading, RTMP streaming.
- **TestFlight acceptance:** records a valid short-form MP4 to the photo library (needs `NSPhotoLibraryAddUsageDescription` — present).

### 9. EchoelLux — `ROADMAP`
- **Code:** none. **Vision:** DMX-512, Art-Net 4 (UDP 6454), HomeKit, fixture profiles, cue lists.
- **TestFlight:** out of scope for build #1. (`NSLocalNetworkUsageDescription` + Bonjour `_artnet._udp` already declared for the future.)

### 10. EchoelStage — `ROADMAP`
- **Code:** none. **Vision:** external displays, projection mapping (warp/edge-blend), multi-screen, NDI/Syphon, AirPlay.
- **TestFlight:** out of scope for build #1.

### 11. EchoelNet — `PARTIAL`
- **Code:** `Sync/OSCSender.swift` (EchoelSync)
- **Live:** OSC 1.0 over UDP, big-endian floats, ~100 ms cadence, 6 continuous bio addresses `/echoelmusic/bio/*` + 6 discrete bio-event addresses `/echoelmusic/bio/event/*` (heartbeat/breath/motion/coherence/eeg, args `[confidence, aux]`), default `localhost:8000`.
- **Roadmap:** Ableton Link tempo/phase, bidirectional OSC, OSC for controller events.
- **TestFlight acceptance:** OSC frames reach a LAN receiver (Resolume/TouchDesigner/Sonic Pi).

### 12. EchoelAI — `ROADMAP`
- **Code:** none. **Vision:** on-device CoreML, stem separation. Private, no cloud.
- **TestFlight:** out of scope for build #1.

---

## TestFlight build #1 — acceptance scope (the LIVE/PARTIAL set)

Ship only what is `LIVE` or the `LIVE` part of `PARTIAL`. Build #1 = a working
**bio-reactive performance instrument** on iPhone / iOS 18:

1. Synth is audible and bio-modulated (EchoelSynth).
2. Beat sequencer plays (EchoelSeq).
3. Bio strip shows live HR/HRV/coherence (EchoelBio) — Demo source on Simulator.
4. MPE controller plays the synth (EchoelMIDI).
5. OSC streams bio out over UDP (EchoelNet).
6. Export writes a −14 LUFS WAV/AAC (EchoelMix/FX).
7. A Metal visual renders ≥60 fps (EchoelVis).
8. Short-form MP4 records (EchoelVid).

`EchoelLux`, `EchoelStage`, `EchoelAI` and all `Roadmap` rows are **not** in build #1.

### Build/signing config of record (verify before each TestFlight run)
- **Target:** iOS 18, iPhone. `project.yml` + `Resources/iOS/Info.plist` + `Package.swift` all iOS 18. `MARKETING_VERSION 10.0.0`.
- **Info.plist source:** XcodeGen generates it from `project.yml` `info.properties` — keep it synced with `Resources/iOS/Info.plist`.
- **Entitlements:** HealthKit + App Group `group.com.echoelmusic` only. iCloud/CloudKit **disabled** (no code uses it; it blocks provisioning until the container is registered).
- **Signing (CI):** automatic, via App Store Connect API key secrets `APP_STORE_CONNECT_KEY_ID / ISSUER_ID / PRIVATE_KEY` + `APPLE_TEAM_ID`, `-allowProvisioningUpdates`. If archive succeeds but upload fails → check these secrets first (key created Dec may be expired).
- **AUv3 extension:** target dependency currently disabled in `project.yml`; re-enable only **after** the main app archives green and `com.echoelmusic.app.auv3` provisioning is confirmed.

---

*Keep this file current: when a `ROADMAP` item gains code, move it to `PARTIAL`/`LIVE`,
add the file path, and mirror the change on `docs/architecture.html`.*
