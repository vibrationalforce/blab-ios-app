# Architecture Audit — 2026-06-09 (full overhaul pass)

Method: 3 parallel read-only audits (core wiring · UI state · feature inventory) + direct grep verification.
Scope: entire architecture, all connections, feature matrix — reconciled against the actual code.
Verdict headline: **the app is coherent and crash-free, but two documentation claims were false and are corrected here** — (1) the bio "lock-free SPSC data plane" is not wired (snapshot is the real path), (2) RTMP/video/multitrack are absent, not present.

---

## 1. Startup sequence (truth)

`App.init()` (`EchoelmusicApp.swift:41-72`) — pure construction, no audio I/O. Creates: MicrophoneManager → AudioEngine → EchoelStore → BeatPlayer → EngineBus → HealthKitBioPublisher → PolarH10BioPublisher → BioReactiveSynthVoice → BioEventPublisher → BioFeedbackPublisher → MIDIInput+MIDIBusPublisher → OSCSender → ModulationEngine. Plus property-init `cameraRPPG`, `admOSC`.

`.task` boot (`EchoelmusicApp.swift:107-168`): `prepareGraph()` → `loadDefaultSamples()` → attach beat voices + bio voice → `audioEngine.start()` → store products → start publishers (health, polar, bioVoice subscribe, bioEvents, bioFeedback, midiPub, osc) → modulation register(tempo)+start+outputTap→osc.

`BioSimulator` (Demo) is owned by `StudioRoot`, not the app; auto-starts (DEBUG: immediately; Release: after 4s grace if no real frame). As of this pass, `.environment(demoSource)` is hoisted to the StudioRoot container (was strip-only).

## 2. EngineBus — producer → consumer truth (THE correction)

| Topic | SPSC queue drained? | Real path | Producers | Consumers |
|---|---|---|---|---|
| **bioFrames** | ❌ **NEVER dequeued** | `@MainActor latestBio` snapshot, 10 Hz polling | HealthKit, PolarH10(BLE), BioSimulator, CameraRPPG | synth, BioEventPublisher, ModulationEngine, SessionRecorder, OSCSender, ADMOSCSender, BioFeedbackPublisher, UI |
| **controllerEvents** | ✅ **drained** | SPSC queue (correct) | MIDIBusPublisher | BioReactiveSynthVoice (`dequeue()` loop) |
| **bioEvents** | ❌ **never dequeued** | `latestBioEvent` snapshot | BioEventPublisher (breath/motion), PolarH10 (per-RR heartbeat) | synth (breath only), OSCSender |

**Consequence:** the bio data plane is the snapshot, not the queue. This is actually FINE — bio is a slow (≤4 Hz) control signal that updates synth params on the MainActor at 10 Hz; it never needs to cross to the audio thread via a lock-free queue (the audio render reads already-set Float params). The SPSCQueue is genuinely load-bearing only for **controllerEvents** (MIDI, which the audio-adjacent synth drains).

**Honest doctrine restatement:** EngineBus = `@MainActor @Observable` control plane (snapshots) for bio + a lock-free SPSC queue for real-time controller events. The bio SPSC queues (`bioFrames`/`bioEvents`) are currently **reserved/unused** — present but not drained.

**Known cost (logged, not yet fixed):** PolarH10 per-RR heartbeat events are published to `bioEvents` but the single-slot snapshot loses sub-100 ms beats, and the synth ignores `.heartbeat` anyway → the low-latency RR beat-sync path has no working sink today. Not breaking a shipped feature; flagged for the beat-sync cycle.

Dead snapshot: `latestControllerEvent` written (`EngineBus:229`), read by no one — harmless.

## 3. Audio graph (truth)

```
masterPlayerNode ─┐
8× SamplerVoice.sourceNode (BeatPlayer) ─┤
BioReactiveSynthVoice.sourceNode ────────┼─→ masterMixer ─[AutoMixChain: EQ → gain]→ mainMixerNode → outputNode → hardware
```
- AutoMixChain (EQ→gain) is inserted between masterMixer and mainMixer (`AudioEngine.swift:137-142`). The old log line "playerNode → masterMixer → mainMixer" omitted it — cosmetic doc drift, corrected.
- RetroCapture / AutoMixChain / SingleExport are instantiated inside AudioEngine (so the chain exists) but **SingleExport/RetroCapture have no UI trigger** → dormant.
- **Launch silence is guaranteed at the audio-thread level**: BioReactiveSynthVoice emits pure zero until first user trigger (`hasEverSounded`). DDSP idle = `sample·amplitude·envelopeValue(0)` = silence. Mic monitoring off by default + not routed to output.

## 4. UI / environment (verified — no crash risk)

Tabs (StudioRoot): **Tools→BeatTab · Works→WorksView · Sync→ModulationView · Well→WellView**, with always-on BioStripView above. Every `@Environment(T.self)` resolves to an injection; `#if` guards line up. No missing-environment crash. Every tab does real work (no placeholders): Tools = full sequencer (velocity/swing/sample-import/MIDI export); Works = bio-session recorder + history; Sync = modulation matrix + ADM-OSC config; Well = coherence + breath pacer + camera rPPG + immersive visual.

Dead/deprecated views (kept compilable, not reachable): BioVisualRenderer, CameraMeasurementView, MasterView, MetalBioView, MomentCaptureView (its `ShareSheet` is reused), SessionGridView, SessionHistoryView, SettingsView, SoundDesignView, SoundscapeView.

## 5. Feature inventory (LIVE / DORMANT / ABSENT) — feeds FEATURE_MATRIX

**LIVE (instantiated + wired + reachable):**
- Audio: AudioEngine, masterMixer chain, AutoMixChain (in-graph)
- Synthesis: **EchoelDDSP** (the bio-reactive voice) — only live synth
- Sequencer: PatternEngine + BeatPlayer + 8× SamplerVoice — steps, tempo, **velocity/accent, swing, per-pad sample import, MIDI export, randomize/shift**
- Bio sources: HealthKit, **universal BLE Heart Rate** (PolarH10BioPublisher, any 0x180D device), **camera rPPG** (locks on device), Demo
- Bio DSP: BioEventGraph (via BioEventPublisher, live) ; HilbertSensorMapper / BioSignalDeconvolver referenced via EchoelBioEngine
- Modulation: ModulationEngine + matrix (tempo destination registered)
- IO: OSCSender (`/echoelmusic/bio/*` + events + mod), **ADMOSCSender** (immersive object out), MIDIBusPublisher (MPE/MIDI 2.0)
- Bio→synth mappings (coherence→harmonicity, HRV→brightness, HR→vibrato, breath→envelope)
- Visual: BioVisualView (Well → fullScreenCover)
- Extensions: EchoelmusicWidgets (live bio glance, App Group), EchoelmusicAUv3 (generator plugin)

**DORMANT (code exists, compiles, not wired to UI/bus):**
- RetroCapture, AutoMixChain export path, SingleExport (in AudioEngine, no UI trigger)
- EchoelCellular (only in deprecated SoundscapeEngine), EchoelModalBank (0 refs), EchoelVDSPKit
- MetalBioView / BioVisualRenderer (only in deprecated MomentCaptureView)
- WatchKit app (compile-verified, embed BLOCKED in sandbox)

**ABSENT (claimed-or-planned but no working code):**
- **RTMP / live streaming**: `RTMPPublisher` = 0 instantiations; HaishinKit not wired. (Website/CLAUDE imply it — correct to roadmap.)
- **Video capture/edit**: CameraSession/VideoRecorder/ClipTrimmer = 0 instantiations
- **MultiTrackRecorder** = 0 (Works records bio-session averages, not multitrack audio)
- **Light / DMX / Art-Net**: absent — the next doctrine-win cycle

## 6. Overhaul action list

Done this pass:
- ✅ Hoist `.environment(demoSource)` to StudioRoot container (UI hardening).
- ✅ This audit doc (durable connections map).
- ✅ FEATURE_MATRIX + CLAUDE.md CURRENT STATE rewritten to the honest state (tabs, LIVE/dormant/absent, corrected SPSC-data-plane claim, RTMP/video/light = roadmap).

Logged decisions / deferred (not blind-fixed):
- Bio SPSC queues `bioFrames`/`bioEvents` are reserved/undrained — keep (snapshot is correct for slow bio) and document honestly, OR drain `bioEvents` when a beat-sync consumer lands. Decision logged.
- PolarH10 RR beat-sync needs a real sink (drain `bioEvents`) — do in the beat-sync cycle.
- Dead `latestControllerEvent` snapshot — leave (harmless) or remove in a cleanup cycle.

Next build cycle (per roadmap): **native Art-Net/sACN light output** (EchoelLux) — zero-dependency doctrine win.
