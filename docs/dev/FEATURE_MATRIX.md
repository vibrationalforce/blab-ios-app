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

> **UPDATE (2026-06-18) — reconciled to code (corrects stale notes below):**
> - **EchoelVis is LIVE** — `Views/MetalBioView.swift` is the live full-screen bio visual (HR→pulse ≤2.5 Hz WCAG, coherence→hue, breath→spread, honours Reduce Motion). NOT dormant/deprecated. **EchoelSeq = 23 genres** (not 12). **sACN unicast is LIVE** beside Art-Net.
> - **Real HRV coherence** (`Bio/HRVCoherence.swift`, Lomb-Scargle + Welch) replaced the placeholder; **resonance breath guide**, **tap-to-learn** bio metrics (`Studio/BioMetricInfo.swift` wired into BioStripView) + the "app as a school" layer (`Studio/MusicTheoryPrimer.swift`, `Studio/LearnLibrary.swift`).
> - **rPPG hardened** (`Bio/CameraRPPGBioPublisher.swift` + `Video/CameraCapture.swift`): session-device torch + exposure lock → reliable lock; peak scan throttled off the main actor (UI no longer stalls).
> - **New pure tested CORES, built but NOT yet wired** (do NOT claim as shipping): `Studio/BioVisualParams.swift`, `Studio/VocoderCore.swift` (the flagship audiovisual vocoder: voice→sound+visual+light, flash-safe), `Studio/FeedbackGuard.swift` (howlround duck+notch brain), `Studio/BioModulation.swift` (universal `BoundParameter` bio-binding spine + `ClockSource` heartbeat-vs-BPM-lock), `Core/CloudSync.swift` (zero references outside its own file as of the 2026-06-20 obstacle audit — wire or remove before it rots), `Bio/ResonanceFinder.swift` (personalized resonance-frequency core; host orchestration + UI pending).
> - **Clips/Arrangement:** domain (`Clip`/`Arrangement`/`ArrangementPlayer`/`LaunchQuantizer` + stores) + tests EXIST; the **UI is the open gap** (#1).
> - **Legal/privacy:** ONE worldwide policy (GDPR/UK + CCPA/CPRA) in American English; `privacy.html` / `impressum.html` / `health.html` corrected to match shipped features. **~214 Swift (Sources) + 1 Metal** (count drifts every cycle — verify with `find Sources -name '*.swift' | wc -l`; corrected 2026-07-04, was "~133 + 2 Metal").

> **UPDATE (2026-06-12) — USP focus + bio-generative composer:** the iPhone app
> is now **Simple-by-default**, reduced to the USP × broad-audience intersection
> — *"your heartbeat makes music: to calm down or for your track."* First-time
> users see only 3 core tabs (**Create · Meditate · Songs**); the pro/installation
> surfaces (Sessions recorder + Connect = OSC/ADM-OSC/Art-Net/sACN) are hidden
> behind an **Advanced tools** toggle (nothing removed). New: the **bio-generative
> composer** ("Generate from Body" — key selection, Studio/BPM-lock vs Flow/
> sync-free, on-device prompt sound-design, 25-preset library; see EchoelSeq #4 +
> EchoelAI #12). **TestFlight status: archive + signing verified; upload pending**
> (Apple daily upload limit hit during build verification — re-dispatch after ~24 h,
> no code change). **Still NOT shipping (do not claim):** video capture/edit, RTMP/
> live-streaming, multitrack, waveform editing.
>
> **CURRENT SHIPPING STATE (2026-06-09):** TestFlight **build 1535 VALID** — app +
> **EchoelmusicWidgets** (live bio glance) + **AUv3 plugin** embedded, driven by
> live bio via `BioFeedbackPublisher` → App Group (CX). New since 1469:
> **camera rPPG is LIVE** (finger-on-lens, locks on device); **BLE source is
> universal** (any standard Heart Rate Service device, not just Polar);
> **ADM-OSC** immersive object output (Sync tab); EchoelBeat gained
> **velocity/accent + swing + per-pad sample import (Files)**; **launch is
> guaranteed silent** (bio voice emits zero until first user trigger). Audited
> 2026-06-09 (`scratchpads/ARCHITECTURE_AUDIT_2026-06-09.md`). Watch companion
> compile-verified, not embedded (export blocked — needs local Xcode).
>
> **Architecture correction (audit):** the EngineBus bio path runs over the
> `@MainActor latestBio` **snapshot** (10 Hz), NOT the SPSC queue. The lock-free
> SPSCQueue is load-bearing only for `controllerEvents` (MIDI). `bioFrames`/
> `bioEvents` queues are present but **not drained** (reserved). RTMP/video/
> multitrack are **absent** (no wired code), not shipping — see each tool below.

> The "12 tools" are a taxonomy over the real modules. E.g. *EchoelSynth* is the
> group {EchoelDDSP, EchoelCellular, EchoelModalBank, EchoelPolyDDSP, SamplerVoice}.
> There is no `EchoelSynth` type.

---

## Spine & infrastructure (not a "tool", but everything routes through it)

| Module | File | Notes |
|---|---|---|
| EngineBus | `Sources/Echoelmusic/Core/EngineBus.swift` | `@MainActor @Observable` control plane (snapshots) + lock-free `SPSCQueue`. 3 topics: `bioFrames` / `controllerEvents` / `bioEvents`. **Audit truth:** bio flows over the `latestBio`/`latestBioEvent` snapshots (10 Hz poll); the SPSC queue is actually drained only for `controllerEvents` (MIDI). `bioFrames`/`bioEvents` queues are reserved/undrained. Modules produce/consume via the bus, never couple directly. |
| SPSCQueue | `Sources/Echoelmusic/Core/SPSCQueue.swift` | Lock-free single-producer/single-consumer ring; audio-thread safe. Live use: `controllerEvents`. |
| AudioEngine | `Sources/Echoelmusic/Audio/AudioEngine.swift` | `AVAudioEngine` master bus. Graph: source nodes → masterMixer → **AutoMixChain (EQ→gain)** → mainMixer → output. Attach source nodes **before** `start()`. |
| Store / Logger | `Core/EchoelStore.swift`, `Core/ProfessionalLogger.swift` (`EchoelLogger`) | Persistence; `os_log` wrapper (never `print`). |
| ModulationMatrix | `Core/ModulationMatrix.swift`, `Core/ModulationEngine.swift` | Freely-routable bio→parameter mapping. Per-route `live` or `hold(value,drift)`. **LIVE (wired):** `ModulationEngine.start(subscribing:)` runs; `tempo` destination registered; edited in the Sync tab (`ModulationView`); outputs tapped to OSC `/echoelmusic/mod/*`. |

---

## The 12 tools

### 1. EchoelSynth — `LIVE`
- **Code:** `DSP/EchoelDDSP.swift`, `DSP/EchoelCellular.swift`, `DSP/EchoelModalBank.swift`, `EchoelPolyDDSP`, `Sequencer/SamplerVoice.swift`, `Tools/BioReactiveSynthVoice.swift`
- **Live:** DDSP / modal / cellular synthesis; one-shot sampler; bio-reactive voice (HR→vibrato, HRV→brightness, coherence→harmonicity, breath→envelope), audible via `AVAudioSourceNode` → master mixer.
- **Roadmap:** EchoelBeat, breakbeat chopper, spectral morph.
- **TestFlight acceptance:** tapping play on `BioStripView` opens the envelope and produces sound; bio frames audibly modulate timbre.

### 2. EchoelFX — `PARTIAL` (deepened 2026-06-10; FX characters 2026-06-12)
- **Code:** `DSP/EchoelDelayLine.swift`, `DSP/EchoelDelay.swift`, `DSP/EchoelModFX.swift`, `DSP/EchoelDynamics.swift`, `DSP/EchoelFXChain.swift` (insert chain, **stereo tone filter first stage**), `DSP/EchoelSVFilter.swift`, `DSP/EchoelLFO.swift`, `DSP/TempoSyncOption.swift`, `Sequencer/GenreFX.swift` (`GenreFXPreset` + `FXCharacter`), `EchoelConvolution` (reverb, in EchoelDDSP), `Audio/AutoMixChain.swift`, `DSP/EchoelVDSPKit.swift` · UI: `Studio/EchoelFXView.swift`
- **Live:** **insert FX chain** (filter → modulation → delay → dynamics → safety limiter), driven from the `FX` panel (BioStripView) and applied to the melody voice on generate:
  - **Filter** — stereo Chamberlin SVF, low/high/band/notch, cutoff + resonance (the basis of muffled/lo-fi colours). Off by default.
  - **Delay** — fractional delay line (linear + allpass interpolation), digital / **tape** (wow+flutter+saturation) / **ping-pong**, one-pole feedback tone, stability-clamped feedback. **Tempo-synced** (studio calculator: note division → time at the live BPM).
  - **Modulation** — chorus, flanger (feedback), phaser (cascaded allpass), tremolo / auto-pan; rates also tempo-syncable.
  - **Dynamics** — soft-knee compressor + brick-wall limiter (hard ceiling guarantee).
  - **Production FX characters** (`FXCharacter`): one-tap **Underwater** (deep low-pass + watery chorus + tape wobble), **Telephone**/**Megaphone** (band-pass), **Cassette**/**Vinyl** (warm low-pass), **Dream** (wide bright ping-pong), **Clean** (dry reset). Stampable in the FX tool *and* the Compose **Effects** picker. `Auto` defers to the genre's own space (see per-genre presets below).
  - **Per-genre FX presets** — each of the 12 genres carries a signature space (long dub ping-pong delay, vapor chorus, psy roll), tempo-synced, auto-applied on "Generate from Body".
  - convolution reverb (HRV-reactive), 4-band EQ + LUFS auto-gain (−14 LUFS, 4 presets), soft `tanh` saturation.
  - Audio-thread-safe (no alloc/locks in render; `audio-thread-reviewer`-audited each change); gated by `fxEnabled` (default off → bit-identical to prior builds until engaged).
- **Roadmap:** **master-FX bus** (so the whole beat/loop, not just the melody, can go Underwater — needs an AVAudioUnit insert on the master mixer), analog (VCA/Opto/FET/VariMu/Tube) emulations, spatial/Atmos 3D panning, stereo synth voice, AUv3-wrapped FX, ring-mod.
- **TestFlight acceptance:** FX panel toggles the insert chain audibly; filter/delay/chorus/flanger/phaser/tremolo/comp/limiter each change the sound; stamping **Underwater** muffles + adds watery movement, **Clean** resets to dry; export path applies AutoMix to −14 LUFS without clipping.

### 3. EchoelMix — `PARTIAL`
- **Code:** `Audio/AudioEngine.swift`, `Audio/AutoMixChain.swift`, `Audio/SingleExport.swift`, `Audio/RetroCapture.swift`, `MicrophoneManager.swift`
- **Live:** master bus, mic FFT (1024-pt), 30 s stereo pre-roll ring (`.caf`), LUFS-normalized WAV/AAC export.
- **Roadmap:** `Audio/MultiTrackRecorder.swift` (skeleton), console UI, FLAC/ALAC, stem export.
- **TestFlight acceptance:** SingleExport writes a valid −14 LUFS WAV/AAC.

### 4. EchoelSeq — `LIVE`
- **Code:** `Sequencer/PatternEngine.swift`, `Sequencer/BeatPlayer.swift`, `Sequencer/SamplerVoice.swift`, `Sequencer/MIDIFileExporter.swift`, `scripts/generate_drums.py`
- **Live:** 8 tracks × 16 steps, 30–300 BPM; **velocity/accent** (tap cycles off→on→accent, gain 0.82/1.0); **swing** (self-rescheduling 16th clock, off-beat delay, tempo-preserving); **per-pad custom sample import** from Files (security-scoped bookmark, persists); upgraded procedural default drum kit; randomize/shift; SMF Type-0 MIDI export.
- **Polyphonic piano roll — LIVE** (`Studio/PianoRollView.swift`): per-note length/velocity roll → `PolySynthVoice`; reachable from the Tools menu.
- **Session clips + linear Arrangement — ROADMAP (NOT built):** `Clip.swift`/`Arrangement.swift`/`ArrangementPlayer.swift`/`LaunchQuantizer.swift` do **not** exist. The take is one re-seeded 16-step loop. "Arrangement + video edit in one view" is the planned multi-cycle build (`scratchpads/PLAN_ARRANGEMENT_VIDEO_ONE_VIEW.md`). Do NOT claim as shipping.
- **MIDI/MPE OUT — LIVE (2026-06-17):** `Audio/MIDIOutput.swift` — virtual "Echoelmusic" CoreMIDI source (UMP/MIDI 1.0) mirrors played notes to any DAW; standard + MPE modes; Tools-menu toggle.
- **Character params — LIVE (2026-06-17):** `MoodProfile` now 8 dims (… + **virtuosity, syncopation, humanize**), all consumed in the lead generator. **23 genres** in `MusicStyle.swift` (not 12).
- **EchoelBeat-pro sampler — LIVE engine (2026-06-17):** `SamplerVoice` per-pad start/end trim, reverse, pitch (interpolated, lock-free). UI exposure + folder/waveform browser = next cycles.
- **Bio-generative composer ("your heartbeat composes"):** `Sequencer/MusicalKey.swift` (set your own key/scale, 10 scales) + `Sequencer/MusicStyle.swift` (**12 genres** — dub techno, trap, vaporwave, 80s, disco, synthwave, early synth, futuristic, sci-fi, psytrance, esoteric meditation, self-observation; dub/trap beat-driven, the rest pads/chords/leads) + `Sequencer/BioComposer.swift` (bio → in-key melody + heartbeat rhythm + tempo, SplitMix64-seeded → reproducible) + `Sequencer/GenrePatches.swift` (per-genre synth timbre), surfaced as **"Generate from Body"** (`Studio/ComposeView.swift`). Two modes: **Studio** (BPM-locked, for Ableton/FL handoff) and **Flow** (sync-free, follows the heart — for meditation). Each take gets its genre timbre + genre/character FX space. Generated **melody exports as MIDI** (real durations + velocity). *Archive-verified + on TestFlight (build #1657, 2026-06-12).*
- **Studio precision & loop tools:** two-decimal **BPM + Kammerton** (`DSP/TuningReference.swift`, A4 432–444, default 440, user-changeable), tempo-synced FX/LFO via the **studio calculator** (`DSP/StudioCalculator.swift`, `DSP/TempoSyncOption.swift`), **loop/stem cutting** at 2/4/8/16/32 bars (`Sequencer/LoopCutter.swift`), **tight-grid vs humanized** feel (`Sequencer/Humanizer.swift`).
- **Auto session name + export filename** (`Core/SessionNaming.swift`, `Core/SessionContext.swift`): every session and exported `.mid` is stamped `Artist_Date_Key_BPM_Kammerton[_Part]`, e.g. `Echoel_2026-06-12_Cm_124bpm_A440_Melody-4bar.mid` — persisted artist/key/Kammerton, previewed live in Compose, shown on saved bio sessions in Works.
- **Roadmap:** per-step probability, automation lanes, Euclidean / polyrhythm; multi-bar generated "pieces" via the arrangement; WAV stem bounce (needs offline-render harness).
- **TestFlight acceptance:** `BeatTab` plays a pattern at the set BPM; accent louder; swing audible; a loaded sample replaces a pad and survives relaunch; **"Generate from Body" writes an in-key melody in the chosen genre + key, applies the genre/character FX, and exports a stamped MIDI filename; Studio locks the BPM, Flow follows the heart.**

### 5. EchoelMIDI — `LIVE`
- **Code:** `Audio/MIDIInput.swift`, `Sync/MIDIBusPublisher.swift` → `EngineBus.controllerEvents`
- **Live:** MIDI 2.0 + MPE input (per-note bend, slide/CC74, air-CC) → bio-modulated synth notes (performer priority over breath).
- **Roadmap:** Standard MIDI File I/O, MIDI output, touch instruments, audio-to-MIDI.
- **TestFlight acceptance:** an external MPE controller triggers synth notes.
- **Fixed:** `MIDIInput.swift:94` force-cast (`as! UInt32`) → crash-safe `compactMap { as? UInt32 }` (behavior-preserving; the word tuple is homogeneous UInt32).

### 6. EchoelBio — `LIVE`
- **Code:** `Core/EngineBus.swift` (`BioSampleFrame`), `Bio/HealthKitBioPublisher.swift`, `Bio/PolarH10BioPublisher.swift`, `Bio/BioSimulator.swift`, `Bio/EchoelBioEngine.swift`, `Bio/BioEventPublisher.swift`
- **Protected DSP triad (read-only, do not simplify):** `Bio/BioEventGraph.swift`, `Bio/HilbertSensorMapper.swift`, `Bio/BioSignalDeconvolver.swift`
- **Live:** **Universal BLE Heart Rate** (`PolarH10BioPublisher` connects to ANY standard 0x180D/0x2A37 device — Polar/Wahoo/Garmin/CooSpo straps, watches in broadcast; RR→RMSSD; shows device name) + HealthKit (Apple Watch + **Oura via Apple Health**) + **camera rPPG (`Bio/CameraRPPGBioPublisher.swift` → `Video/CameraAnalyzer.swift`, finger-on-lens + torch, locks on device, live waveform)** + Demo → bus snapshot; breath/motion onset events via BioEventGraph. **CX:** `Core/BioFeedbackPublisher.swift` mirrors vitals to App Group (~1 Hz) → Widget/Watch glance.
- **Honest limits:** Oura exposes no real-time third-party BLE (only via Apple Health, delayed). Camera rPPG is motion-sensitive (use a BLE strap for loud/active performance). PolarH10 per-RR `.heartbeat` events are published but currently have no working sink (snapshot loses sub-100 ms beats) — beat-sync cycle will drain `bioEvents`.
- **Roadmap:** face tracking (ARKit); raw PPG/ECG waveform; EEG band-power (LSL).
- **TestFlight acceptance:** `BioStripView` shows live HR/HRV/Br/Coh; camera pulse locks (PPG); BLE strap shows its name; Demo works on Simulator; Widget mirrors vitals.

### 7. EchoelVis — `LIVE` (corrected 2026-07-04; the old PARTIAL entry named deleted files)
- **Code (live):** `Views/MetalBioView.swift` (Metal bio visual, inline-compiled shader, AdaptiveQuality FPS/detail tiers, flash-safe ≤3 Hz, Reduce Motion) inside `Studio/FloatingVisualWindow.swift` — the floating/fullscreen window toggled from the WorkspaceView header, with in-fullscreen VJ controls + palette.
- **Code (live, capture):** `Video/VisualRecorder.swift` + `Video/VideoMuxer.swift` — records the visual to stamped **MP4 clips** (share-ready) from the floating window.
- **Gone:** `BioVisualView` / `BioVisualRenderer` / `MomentCaptureView` were deleted in cleanup — do not reference them.
- **Roadmap:** external-display output window; more looks; AR worlds.
- **TestFlight acceptance:** header monitor toggles the floating visual; it reacts to bio; fullscreen + record work.

### 8. EchoelVid — `ROADMAP`
- **Code:** `Video/CameraCapture.swift` (used ONLY by camera rPPG), `Video/CameraAnalyzer.swift` (rPPG). **Audit:** `CameraSession` / `VideoRecorder` / `ClipTrimmer` = 0 instantiations; `ShortContentRenderer` not wired. **No video recording/editing is shipping.**
- **Roadmap:** the CameraHub fan-out (`SPEC_CAMERA_PIPELINE.md`) so one capture serves rPPG + video + visuals; H.264/HEVC short-form record, NLE, ProRes.
- **TestFlight:** out of scope — video capture/edit is not wired today.

### 9. EchoelLux — `LIVE`
- **Code:** `Sync/ArtNetSender.swift`, `Sync/SACNSender.swift` (+ `ArtNetSenderTests`, `SACNSenderTests`)
- **Live:** native **Art-Net** (ArtDMX/UDP 6454, build 1543) **+ sACN / E1.31** (Data Packet/UDP 5568, **unicast** — iOS gates multicast behind the special entitlement; `multicastHost(universe:)` ready for when granted). Both zero-dependency, hand-built on Network.framework, sharing the bio→DMX mapping: dimmer←coherence, R←heart rate, G←HRV, B←breath. Smooth fades, no strobing (WCAG 3 Hz safe by construction). Opt-in from the Sync tab (host/universe per standard). Packet + mapping kernels unit-tested. Verification recipe: `scratchpads/SPEC_LIGHT_OSC_VERIFICATION.md`.
- **Roadmap:** sACN multicast (entitlement), fixture profiles, cue lists, HomeKit.
- **TestFlight acceptance:** an Art-Net node and/or an sACN receiver (sACNView/QLC+) shows the bio-reactive fixture move.

### 10. EchoelStage — `ROADMAP`
- **Code:** none. **Vision:** external displays, projection mapping (warp/edge-blend), multi-screen, NDI/Syphon, AirPlay.
- **TestFlight:** out of scope for build #1.

### 11. EchoelNet — `LIVE` (partial)
- **Code:** `Sync/OSCSender.swift`, `Sync/ADMOSCSender.swift`, `Sync/MIDIBusPublisher.swift`
- **Live:** OSC 1.0 over UDP — 6 continuous `/echoelmusic/bio/*` + 6 discrete `/echoelmusic/bio/event/*` + `/echoelmusic/mod/*` (modulation), default `localhost:8000`. **ADM-OSC** immersive object output (`/adm/obj/{n}/position/{azimuth|elevation|distance}` + `/gain`, bio→object) into FletcherMachine/L-ISA/d&b — opt-in from the Sync tab. MIDI 2.0/MPE in.
- **Beat-sync (audit fix 2026-06-09):** OSCSender now DRAINS the `bioEvents` SPSC queue (sole consumer) → every PolarH10 per-RR `.heartbeat` (+ breath/motion) event is sent at full resolution, no longer lost to the 100 ms snapshot. The synth's breath path still uses the independent `latestBioEvent` snapshot.
- **Roadmap:** Ableton Link tempo/phase, bidirectional OSC, RTP-MIDI, ADM-OSC native-protocol fallback lane.
- **TestFlight acceptance:** OSC frames reach a LAN receiver; ADM-OSC `/adm/obj/1/*` visible on an OSC monitor; heartbeat events arrive per-beat.

### 12. EchoelAI — `PARTIAL` (on-device generative, no cloud)
- **Code:** `Sequencer/BioComposer.swift` (deterministic bio→music generation), `DSP/SoundPrompt.swift` (semantic prompt→sound-design), `DSP/PatchLibrary.swift` (25-preset library).
- **Live:** **generative, not "AI" hype** — `BioComposer` turns biodata into an in-key melody + heartbeat rhythm + tempo (seeded → reproducible). **Prompt-based sound design** (`SoundPrompt`): a curated 24-descriptor vocabulary + intensity modifiers maps natural words ("warm lush pad", "bright glassy pluck") onto `SynthPatch` params — **fully on-device, deterministic, offline, private** (owner decision 2026-06-12: smartest *independent* variant + suggestions + a large preset DB; **no API, no LLM, no cloud**). `PatchLibrary` = 25 tagged factory presets across 8 categories as prompt starting points.
- **Roadmap:** on-device CoreML timbre transfer, stem separation; optional (opt-in) natural-language expansion — still local-first.
- **TestFlight acceptance:** a prompt ("warm lush pad") audibly shapes the synth; the preset library browses; generated melodies are in the chosen key.

---

## Ecosystem surfaces (the instrument extended across Apple platforms)

| Surface | Bundle | Status | Notes |
|---|---|---|---|
| **AUv3 plugin** | `…app.auv3` | `LIVE` (shipped build 1467/1469) | Generator AU — Echoel-as-plugin in Logic/GarageBand/AUM. SDKROOT fixed (was macOS-only); embedded + signed via `xcodebuild -allowProvisioningUpdates`. |
| **Widgets** | `…app.widgets` | `LIVE` (shipped 1454→1469) | WidgetKit live bio glance, reads App Group via `BioFeedbackManager`. |
| **watchOS** | `…app.watchkitapp` | `COMPILE-VERIFIED, not embedded` | Bio glance; embed export-blocked (needs `WKCompanionAppBundleIdentifier` + Embed-Watch-Content phase verified in local Xcode). |
| **macOS (Catalyst)** | `com.echoelmusic.app` | `ROADMAP` (decided path) | Catalyst-first; native AppKit deferred. See `SPEC_ECOSYSTEM_TARGETS.md`. |
| **visionOS / tvOS** | `com.echoelmusic.app` | `ROADMAP` | Immersive / big-screen output. Separate-platform archive lanes (now cert-race-free). |
| **App Clip / Notification Service** | `…app.clip` / `…notification-service` | `ROADMAP` | Per `SPEC_ECOSYSTEM_TARGETS.md`. |

**Orientation (the Fahrplan):** THIS file is the spine — code-grounded status,
sequenced by value ÷ signing-risk. The **website mirrors** it (architecture.html /
tools.html), never the other way round ("if the website disagrees, the code wins").
Companion plans: `SPEC_ECOSYSTEM_TARGETS.md` (surfaces), `SPEC_CAMERA_PIPELINE.md`
(camera fan-out), `decisions.csv` (SDK doctrine, Oura-via-HealthKit, RTP-MIDI+Link).

---

## TestFlight build #1 — acceptance scope (the LIVE/PARTIAL set)

Ship only what is `LIVE` or the `LIVE` part of `PARTIAL`. Build #1 = a working
**bio-reactive performance instrument** on iPhone / iOS 18:

1. Synth is audible and bio-modulated (EchoelSynth) — silent until armed.
2. Beat sequencer plays with velocity/accent + swing; pads load custom samples (EchoelSeq).
3. Bio strip shows live HR/HRV/coherence; camera pulse locks; BLE strap shows name (EchoelBio).
4. MPE controller plays the synth (EchoelMIDI).
5. OSC + ADM-OSC stream bio/object out over UDP (EchoelNet).
6. Modulation matrix routes bio→tempo (Sync tab).
7. Well immersive visual reacts to bio (EchoelVis, BioVisualView).

**Not wired / not shipping** (re-corrected 2026-07-04): multitrack audio export, CAMERA video recording/editing (EchoelVid), RTMP streaming. **Now LIVE (the 2026-06-09 list was stale on these):** MP4 clips of the VISUAL (`VisualRecorder`), the Metal visual itself (MetalBioView, floating window), and lighting (`EchoelLux` Art-Net + sACN unicast). `EchoelStage`, `EchoelAI`, and all `Roadmap` rows remain out.

### Build/signing config of record (verify before each TestFlight run)
- **Target:** iOS 18, iPhone. `project.yml` + `Resources/iOS/Info.plist` + `Package.swift` all iOS 18. `MARKETING_VERSION 10.0.0`.
- **Info.plist source:** XcodeGen generates it from `project.yml` `info.properties` — keep it synced with `Resources/iOS/Info.plist`.
- **Entitlements:** HealthKit + App Group `group.com.echoelmusic` only. iCloud/CloudKit **disabled** (no code uses it; it blocks provisioning until the container is registered).
- **Signing (CI):** automatic, via App Store Connect API key secrets `APP_STORE_CONNECT_KEY_ID / ISSUER_ID / PRIVATE_KEY` + `APPLE_TEAM_ID`, `-allowProvisioningUpdates`. If archive succeeds but upload fails → check these secrets first (key created Dec may be expired).
- **AUv3 extension:** ✅ ENABLED + SHIPPED (build 1467/1469). Compile-verified via the `EchoelmusicAUv3` scheme in `compile_check`; signed/uploaded via `-allowProvisioningUpdates`. (Widget likewise embedded + shipped. Watch dependency kept OFF — export-blocked.)

---

*Keep this file current: when a `ROADMAP` item gains code, move it to `PARTIAL`/`LIVE`,
add the file path, and mirror the change on `docs/architecture.html`.*
