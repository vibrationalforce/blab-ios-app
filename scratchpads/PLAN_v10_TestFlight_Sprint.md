# Echoel v10 — TestFlight Sprint (3 Wochen)

**Status:** AUTHORITATIVE — supersedes PLAN_PIVOT_LIVE_STUDIO, PLAN_DAW_VIDEO_MVP, PLAN_EchoelStudio, PLAN_ARCHITECTURE_MAXIMUM, PLAN_MISSING_SYSTEMS.
**Decided:** 2026-04-26
**Branch:** `claude/unified-production-app-Qdm6b`
**Deadline:** TestFlight upload 2026-05-17 (3 Wochen ab heute), iOS 26 SDK Compliance 2026-04-28.

---

## Vision (User, wörtlich)

> „FL Studio Mobile auf iPhone → Ableton auf Mac → iPhone-Kamera → InShot. Im Prinzip möchte ich das alles in einem Programm. Live-Stream RTMP für Insta, YouTube, TikTok. Wir wollen besser sein als Reaper, Logic, CapCut, OBS Studio und DaVinci Resolve in einer Software."

Der Nordstern ist ein Mehrjahresprodukt. Der erste TestFlight ist ein **dünner, polierter Vertikalschnitt** durch alle drei Säulen.

---

## Strategische Entscheidung: Hybrid

Weder Ground-Up-Rewrite (zu lang, killt 3-Wochen-Deadline) noch Crash-Fixing der bio-zentrischen Architektur (falsche Abstraktion für DAW). Stattdessen:

| Behalten | Status | Begründung |
|---|---|---|
| `Audio/AudioEngine.swift` | KEEP | Solides AVAudioEngine-Fundament, getestet |
| `Audio/RetroCapture.swift` | KEEP | 30 s Ring-Buffer + REC, funktioniert |
| `Audio/AutoMixChain.swift` | KEEP | Master-Bus EQ/Comp/Limiter |
| `Audio/SingleExport.swift` | KEEP | LUFS-Mastering + WAV/AAC-Export |
| `Audio/MIDIInput.swift` | KEEP | CoreMIDI-Listener |
| `Core/EchoelStore.swift` | KEEP | StoreKit 2 |
| `Core/SPSCQueue.swift` | KEEP | Lock-freie Queue für Audio-Thread |
| `Core/PlatformAvailability.swift`, `NumericExtensions.swift`, `ProfessionalLogger.swift`, `MemoryPressureHandler.swift` | KEEP | Infrastruktur |
| `DSP/EchoelDDSP.swift` | KEEP | Wiederverwendet als Synth-Voice |
| `DSP/EchoelCellular.swift` | KEEP | Wiederverwendet als Texture-FX |
| `Bio/BioEventGraph`, `HilbertSensorMapper`, `BioSignalDeconvolver` | **PROTECTED** | Nicht ohne explizite Freigabe modifizieren |
| `MicrophoneManager.swift` | KEEP | |

| Deprecaten (raus aus Haupt-Flow, nicht löschen) | Begründung |
|---|---|
| `Core/SoundscapeEngine.swift` | Bio-reaktiver Ambient-Hub. Im neuen Modell wird Audio von Tracks erzeugt, nicht von einer Hub-Klasse. |
| `Core/ClipEngine.swift` | „Scene"-Metapher passt nicht zu DAW-Track/Clip-Modell. Ersetzt durch `Sequencer/PatternEngine`. |
| `Views/MomentCaptureView.swift` (aktueller `@main`-Inhalt) | Fullscreen-Bio-Visualizer ist nicht der DAW-Einstieg. |
| `Views/SoundscapeView.swift`, `MetalBioView.swift`, `BioVisualRenderer.swift` | Nur in optionalem „Creative Mode" weiterführen. |
| `Bio/MotionActivityProvider`, `OuraRingClient`, `EEGSensorBridge`, BioSourceManager | Nicht im MVP-Pfad. Bleiben kompilierbar, werden aber nicht initialisiert in `EchoelmusicApp`. |
| `Views/CameraMeasurementView.swift` (rPPG) | Optional, nicht im MVP. |

| Neu zu bauen | Modul |
|---|---|
| `Sequencer/PatternEngine.swift` | 16-Step × 8-Track Drum-Sequencer, Tempo-Clock |
| `Sequencer/SamplerVoice.swift` | One-Shot WAV-Player mit pitch + gain |
| `Audio/MultiTrackRecorder.swift` | Mehrspur-Recorder über `AVAudioEngine.installTap` |
| `Video/CameraSession.swift` | Erweitert bestehendes `CameraCapture.swift` mit Recording |
| `Video/VideoRecorder.swift` | `AVAssetWriter` H.264 + AAC |
| `Video/ClipTrimmer.swift` | In/Out-Points für Einzelclip |
| `Stream/RTMPPublisher.swift` | HaishinKit-Wrapper |
| `Studio/StudioRoot.swift` | Neuer `@main`-Einstiegspunkt mit 4 Tabs |
| `Studio/BeatTab.swift` | Drum-Pads + Step-Sequencer-UI |
| `Studio/RecordTab.swift` | Mic + Master-Mixer + REC |
| `Studio/VideoTab.swift` | Kamera + Trim + Export |
| `Studio/ShareTab.swift` | RTMP-URL/Key + Stream-Start + Export-Buttons |

---

## Dependency-Entscheidung

**Genau eine externe Dependency: HaishinKit (RTMP/RTMPS, MIT, Swift-nativ).**

- Begründung: RTMP-Implementierung from-scratch sind 2–3 Wochen, killt Sprint
- Pin auf exakten Tag (z. B. `1.10.0`)
- In `Package.swift` als `.package(url: "https://github.com/shogo4405/HaishinKit.swift", exact: "1.10.0")`

Alles andere first-party Apple (AVFoundation, CoreMIDI, Accelerate, Metal, VideoToolbox, SwiftData).

---

## 3-Wochen-Sprint (Ralph-Wiggum-Lambda: ein Fix/Feature pro Cycle)

### Woche 1 — Fundament + Beat-Tab (2026-04-27 → 2026-05-03)

**Tag 1 (Mo):** Compile-Baseline herstellen. `swift build` muss grün sein. Falls nicht: nur diese Fixes, nichts anderes.
**Tag 2 (Di):** `Sequencer/PatternEngine.swift` — 16-Step × 8-Track-Modell, Tempo-Clock via `AVAudioSourceNode` Sample-Counting (audio-thread-safe). Test-File `SequencerTests.swift`.
**Tag 3 (Mi):** `Sequencer/SamplerVoice.swift` — One-Shot-WAV-Player. 8 Default-Samples in `Resources/Drums/` (Kick/Snare/Hat/OpenHat/Clap/Perc/Bass/Lead-FX, royalty-free).
**Tag 4 (Do):** `Studio/BeatTab.swift` — 8 Pads (LazyVGrid), 16 Step-Buttons, Tempo-Slider, Play/Stop. Pure SwiftUI.
**Tag 5 (Fr):** `Studio/StudioRoot.swift` — `TabView` mit Beat (live), Record/Video/Share (Placeholder). Neuer `@main` in `EchoelmusicApp.swift`. Alter Bio-Auto-Play wird nicht mehr aufgerufen.
**Sa/So:** Polish + Smoke-Test auf Device.

**Exit-Kriterium W1:** Beat-Tab spielt 16-Step-Patterns auf Device, Tempo regelbar, Tabs umschaltbar.

### Woche 2 — Record + Video (2026-05-04 → 2026-05-10)

**Tag 1:** `Audio/MultiTrackRecorder.swift` — Mic-Aufnahme während Beat läuft, Sync via Sample-Frames. Output: `.caf`.
**Tag 2:** `Studio/RecordTab.swift` — Mic-Pegel-Meter, REC-Button, Track-Liste (Beat-Spur + Mic-Spur), Master-Volume.
**Tag 3:** `Video/CameraSession.swift` + `Video/VideoRecorder.swift` — `AVCaptureSession` 1080p30, `AVAssetWriter` H.264 + AAC. Audio kommt vom Master-Bus, nicht von Mic-Direkt-Input (sync mit Beat).
**Tag 4:** `Studio/VideoTab.swift` — Kamera-Preview (`AVCaptureVideoPreviewLayer` via `UIViewRepresentable`), REC-Button, Front/Back-Toggle.
**Tag 5:** `Video/ClipTrimmer.swift` + Trim-UI im Video-Tab — In/Out-Slider, Preview-Scrubber.
**Sa/So:** Polish + iOS-26-Permission-Flows (Camera, Mic, Photo Library).

**Exit-Kriterium W2:** Beat läuft → Mic-Aufnahme darüber → Video-Clip mit gemischtem Audio aufgenommen → Trim → Save.

### Woche 3 — Share + Polish + TestFlight (2026-05-11 → 2026-05-17)

**Tag 1:** HaishinKit-Dependency in `Package.swift`. `Stream/RTMPPublisher.swift` — minimaler Wrapper.
**Tag 2:** `Studio/ShareTab.swift` — URL+Key-Eingabe (Key in Keychain), Bitrate-Picker (3/4.5/6 Mbps), Start/Stop-Stream-Button, `StreamHealth`-Status.
**Tag 3:** Stream-End-to-End-Test gegen YouTube-Test-Stream (oder lokalen nginx-rtmp). Audio-Video-Sync via gemeinsamer `CMClock`.
**Tag 4:** Export-Buttons im Share-Tab — WAV (Audio-only) + MP4 (Video+Audio gemuxt).
**Tag 5:** App-Icon, Launch-Screen, Onboarding (3 Slides: „Make Beats / Record Video / Stream Live"), Dark-Theme-Pass.
**Sa:** TestFlight-Upload via `testflight.yml` (`workflow_dispatch`, `platform: ios`).
**So:** Externe Tester einladen, erstes Feedback-Window.

**Exit-Kriterium W3:** TestFlight-Build live, alle 4 Tabs interaktiv, Stream-zu-YouTube funktioniert, Export-MP4 spielt extern.

---

## Was NICHT im MVP ist (v1.1+ Backlog)

Piano-Roll, Synths (Subtractive/FM/Wavetable), Multi-Clip-Video-Timeline, Transitions, Color-Grading, Automation-Lanes, MIDI-Quantize, AUv3-Host-Mode, Bluetooth-MIDI, iCloud-Sync, iPad-Layout, Mac-Catalyst, Bio-Creative-Mode, EEG, Oura, rPPG, HealthKit, Apple-Watch.

Alles sauber dokumentiert in `scratchpads/BACKLOG_v1.1.md` nach Ship.

---

## Kritische Datei-Pfade (Referenz)

**Behalten/erweitern:**
- `/home/user/Echoelmusic/Sources/Echoelmusic/Audio/AudioEngine.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Audio/RetroCapture.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Audio/AutoMixChain.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Audio/SingleExport.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Core/SPSCQueue.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Core/EchoelStore.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/DSP/EchoelDDSP.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/DSP/EchoelCellular.swift`

**Neu:**
- `/home/user/Echoelmusic/Sources/Echoelmusic/Sequencer/PatternEngine.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Sequencer/SamplerVoice.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Audio/MultiTrackRecorder.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Video/CameraSession.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Video/VideoRecorder.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Video/ClipTrimmer.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Stream/RTMPPublisher.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Studio/StudioRoot.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Studio/BeatTab.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Studio/RecordTab.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Studio/VideoTab.swift`
- `/home/user/Echoelmusic/Sources/Echoelmusic/Studio/ShareTab.swift`

**Modifiziert:**
- `/home/user/Echoelmusic/Sources/Echoelmusic/EchoelmusicApp.swift` (neuer Root: `StudioRoot`, kein Bio-Auto-Play mehr)
- `/home/user/Echoelmusic/Package.swift` (HaishinKit-Dependency, Sources/Sequencer + Sources/Stream + Sources/Studio aufnehmen)
- `/home/user/Echoelmusic/CLAUDE.md` (Identity-Update)

---

## Risiken & Mitigation

1. **App-Review wegen 3rd-Party-Streaming.** Mitigation: Generic-RTMP-URL-Feld, kein YouTube/Twitch-Branding im UI, Disclaimer. Präzedenz: Streamlabs, Larix.
2. **A/V-Sync im Stream.** Mitigation: gemeinsame `CMClock` (Host-Time) als Master, Audio via `AVAudioSinkNode` mit Host-Timestamps.
3. **Realtime-Audio + Swift 6.** Mitigation: nonisolated C-Closure im Render-Block, `SPSCQueue` für Cross-Thread, Lint-Regel verbietet `Dispatch`-Import in Sequencer-Files.
4. **Thermal beim Streaming.** Mitigation: 720p30-Fallback, `ProcessInfo.thermalState`-Watch, Auto-Bitrate-Reduce.
5. **Scope-Creep.** Mitigation: User hat zugestimmt, Backlog-Disziplin halten. Jedes „aber wir könnten auch…" → `BACKLOG_v1.1.md`.

---

## Verifikation (pro Woche)

- `swift build` grün (Cmdline)
- Xcode 26.2 Build grün, Archive signiert
- `swift test` grün für alle neuen Module mit Tests
- TestFlight-Upload via `gh workflow run testflight.yml -f platform=ios` (oder UI-Trigger)
- Manueller Device-Test gegen Exit-Kriterium der jeweiligen Woche

---

## Was diese Session (Sandbox ohne Toolchain) liefern kann

Diese Sandbox hat **kein Swift** und kein Xcode → keine Code-Änderungen, da nicht verifizierbar. Konkrete Deliverables hier:

1. ✅ Diese Plan-Datei (`PLAN_v10_TestFlight_Sprint.md`)
2. ⏭ Decision-Log-Eintrag in `memory/decisions.md`
3. ⏭ Identity-Update in `CLAUDE.md` (kleine, präzise Edits)
4. ⏭ Commit + Push auf `claude/unified-production-app-Qdm6b`

**Nächste Session auf Mac mit Toolchain:** Tag-1-Aufgaben starten. `swift build` → grün → Tag 2.
