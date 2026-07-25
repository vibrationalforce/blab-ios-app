# PLAN — Echoelmusic wird REINES INSTRUMENT (Founder-Verdikt 2026-07-24)

**Founder, wörtlich:** „Echoelmusic wird reines Instrument. Ohne DAW und Video Schnitt.
Kein auv3 (fliegt komplett)."

Das ist die endgültige Positionierungs-Entscheidung (löst #119; **radikaler** als die
drei Fork-Optionen — nicht „de-emphasize", sondern **entfernen**). Supersedet die
„tracks-as-home"-Ära (#9) und den DMMW-Profi-DAW-Pfad. Echoelmusic = das bio-generative
Instrument + Visuals + Licht/OSC-Performance-Output. Fertig.

## Council-Verdikt (HOW, nicht WHETHER — das WHETHER ist entschieden)
- **Architect:** Grenze läuft DURCH `Sequencer/` + `Video/`. Instrument-Engine (generativ)
  ≠ DAW-Dokument (Timeline/Clip/Automation-Lane). Trennen, nicht Ordner-löschen.
- **DSP-Purist:** AUv3-Wegfall LOCKERT das DSP/-Isolations-Gesetz (DSP/ kompilierte isoliert
  NUR für die AUv3). DSP/ bleibt trotzdem Foundation-only (Hygiene) — aber der Zwang fällt.
- **Skeptic:** größte Gefahr = versehentlich Instrument-kritisches schneiden (rPPG-Kamera,
  BioComposer, PatternEngine, Voices, OSC/Light-Out). Jede Slice muss den Instrument-Kern
  grün lassen (Build + die Kern-Tests: EchoelDDSP/BioEventGraph/Sequencer/Genre/rPPG-Trust).
- **Shipper:** eine sichere, reversible Slice pro Zyklus; AUv3 → Video-Schnitt → DAW
  (self-contained zuerst). Jede Slice: Gates grün + Reviewer.
- **User-Advocate:** Home wird wieder der Instrument-Flow (EchoelStudioView) — existiert
  schon (WorkspaceView-Body); DAW war nur draufgeschichtet. Reversibel via git.
→ **Gate: proceed, PLAN-first, delete-in-slices.**

## KEEP (das Instrument)
- Bio-Pipeline: `Bio/` KOMPLETT (EchoelBioEngine, HealthKit/BLE/rPPG-Publisher, Rausch-Triad).
- **rPPG-Kamera** aus `Video/`: CameraAnalyzer, CameraCapture, PulsePeriodEstimator,
  RPPGConditioning (= Bio-Input, NICHT Video-Schnitt).
- DSP: `DSP/` (EchoelDDSP/Cellular/ModalBank/VDSPKit, SynthPatch, TuningReference …).
- Voices/Tools: `Tools/` (PolySynthVoice, SubBassVoice, BioReactiveSynthVoice, Poly/Sub).
- Generativer Kern aus `Sequencer/`: BioComposer, BioMusicDirector, BioVariationMaze,
  PatternEngine, MusicStyle, MusicalKey, Note(+Operators), DrumSynthVoice, DrumNoteMap,
  GenrePatches, GenreFX, ChordSuggest, Humanizer, MicrotonalTuning, MoodPreset, BreathArp,
  VoiceLeader, LyricsModel, TapTempo, TempoStability. (Instrument-Theorie + Groove.)
- FX: EchoelFX (Chain/VM/View/Presets/bio-mod).
- Visuals: MetalBioView, FloatingVisualWindow, BioVisualParams, shader-Looks.
- Output-Performance: `Sync/` (OSC, ADMOSCSender, Art-Net/sACN EchoelLux) — Instrument-
  Performance-Out, KEIN DAW. CloudSync/Colabo: TBD (eher keep, live-performance).
- Shell: WorkspaceView (Header + TransportBar Play/Stop + EchoelStudioView + FloatingVisual),
  Patch-Editor, Tuning/Key, BioStrip, Onboarding, Learn (science-first).
- Transport: Play/Stop + Tempo (das Instrument spielt/loopt generativ) — KEIN Timeline-Playhead.

## CUT (DAW · Video-Schnitt · AUv3)
### A) AUv3 — „fliegt komplett" (beide Richtungen)
- Target `EchoelmusicAUv3` aus project.yml + Embed aus dem Echoelmusic-Target + Entitlements
  (`EchoelmusicAUv3.entitlements`) + `Resources/EchoelmusicAUv3/Info.plist` + `Sources/EchoelmusicAUv3/`.
- In-App AUv3-HOSTING (Dritt-Plugins): AUv3BrowserView, AVAudioUnit-Lane-Hosting, Discovery/
  Registry-Retry (~59 Refs) — fällt teils mit den DAW-Lanes.
- CI: `xcode-compile-check.yml` baut die AUv3 — anpassen (Founder-Verdikt autorisiert die CI-Änderung).
- Nach Wegfall: DSP/-Isolations-Gesetz entschärft (bleibt freiwillig Foundation-only).

### B) Video-Schnitt (rPPG-Kamera BLEIBT)
- CUT: VideoRecorder, VideoMuxer, VideoMuxAlignment, VideoAudioExtractor, VisualRecorder,
  Shaders/ChromaKey, Video-Timeline-Lanes/Regions (VideoRegionTrim, AudioClipRegion-Video-Teil).
- OFFENER GRENZFALL (nicht blockierend): „Performance als Clip aufnehmen/teilen" (VisualRecorder/
  EchoelPublish #51/#93) = Instrument-Output oder Schnitt? Default: konservativ mit-schneiden
  (reines Instrument), EchoelPublish-Share separat entscheiden. → Founder-Detail bei Bedarf.

### C) DAW-Schicht (die große)
- UI: ArrangeTimelineView, ClipView, ArrangementView, ChannelRackView, AudioClipView,
  ClipAutomationView, AutomationView, PatchbayView(?), Timeline-Chrome.
- Doku/Model: TimelineStore, ClipStore, ArrangementStore, Arrangement, Clip, AudioClipRegion,
  AutomationLane, TimelineRegionPlayer, ArrangementPlayer, AudioLanePlayer/AudioClipPlayer,
  ClipLaunchEngine, LaunchQuantizer, LaneVoiceRack(+Pool/Plan/SlotMap/Kind), MultiRollFanout,
  LoopCutter, MIDIFileExporter/Importer, MIDINoteRecorder, BioAutomationRecorder,
  AutomationGestureRecorder, Undo/Redo(TimelineStore).
- Home-Rewire: WorkspaceView zeigt wieder NUR den Instrument-Flow (EchoelStudioView) —
  Timeline/Spuren-Surfaces raus. (Revert der „tracks-as-home"-Schicht; Instrument-Home existiert.)

## Reihenfolge (eine reversible Slice pro Zyklus, Gates grün + Reviewer je Slice)
1. **AUv3-Target-Removal** (self-contained): project.yml-Target + Embed + Entitlements + Info +
   Sources/EchoelmusicAUv3 + CI-Anpassung. Kein App-Verhalten ändert sich (nur der Plugin-Build).
2. **AUv3-Hosting-Removal** (Dritt-Plugin-Türen/Registry aus dem App-UI).
3. **Video-Schnitt-Removal** (Video/-Editier-Dateien; rPPG-Kamera bleibt; Video-Lanes raus).
4. **DAW-UI-Removal** (Timeline/Clip/Arrangement-Surfaces aus WorkspaceView; Home = Instrument).
5. **DAW-Model-Removal** (Stores/Player/Lane-Rack; generativer Kern bleibt verdrahtet).
6. **Cleanup** (tote Referenzen, project.yml, CLAUDE.md-Architektur, Tests entrümpeln).

## Schutz je Slice (dürfen nie brechen)
Build grün + Kern-Tests: EchoelDDSPTests, BioEventGraphTests, BioSignalDeconvolverTests,
PatternEngineTransportRelayTests, TempoStabilityTests, GenreFXTests, CameraRPPGTrustTests,
MusicalKeyTests. Nach jeder Slice: bio-generatives Spielen muss weiter klingen (device-verify
beim Founder für die großen Slices).

## Risiken / offene Details
- LaneVoiceRack/Multi-Roll: der PER-SPUR-Voice-Pool geht mit dem DAW — aber der GLOBALE
  Instrument-Voice-Pfad (synth/subBass/bioVoice in EchoelStudioView) BLEIBT. Trennen.
- BioVariationMaze/Automation-in-Spur: Maze bleibt (Instrument-Ideen), Automation-Lane-Doc geht.
- Kammerton/Tuning-Verdrahtung bleibt (gerade gefixt).
- #120 Metronom, #104/105/106 Roadmap (Loop/Master-Stem/Video-Export): OBSOLET durch den Cut.
- EchoelStore/Push/CloudKit: unberührt (dormant), separat.

## Status: PLAN gelockt.
- ✅ **Slice 1 (AUv3-Target-Removal) GESHIPPT** — Commit `5ef8856`, beide echten Gates grün
  (Xcode Compile Check #1087 + CI/CD Pipeline #4552). EchoelmusicAUv3-Target + Embed +
  Entitlements + Info + Sources/EchoelmusicAUv3 + Scheme raus; testflight.yml AUv3-compile_scheme
  + Hard-Fail-Embed-Verify raus. build-error-resolver-Reviewer: ZERO real breakers. Kein
  App-Verhalten geändert (nur der Plugin-Build), kein Deploy (TestFlight-Freeze).
  Offene Slice-2-Reste (nicht blockierend, degradieren graceful): testflight.yml 3 non-blocking
  AUv3-Signing/Scan-Diagnose-Steps (exit 0 bei fehlendem appex), `Echoelmusic.entitlements`
  `inter-app-audio` (verwaist, kein Signing-Bruch), `Tests/…/AUv3ScanDiagnosticTests.swift`
  (String-Test, kompiliert weiter). App-Group `group.com.echoelmusic` BLEIBT (Widget braucht sie).
- ▶ **Slice 2 (AUv3-Hosting-Removal) — consumer-first, 4 Sub-Slices** (Karte: read-only Explore-
  Agent 2026-07-24 → ~9 reine Lösch-Dateien + ~10 Chirurgie-Dateien; kein Ein-Commit möglich,
  jeder Commit muss gate-grün sein → Verbraucher zuerst, Host-Dateien zuletzt):
  - ✅ **2a — Tür zu (UI) GESHIPPT** — Commit `ddb1cfb`, beide Gates grün (Xcode Compile #1088 +
    CI/CD #4553), ui-state-reviewer PASS (Switch-Exhaustiveness + Klammern + keine dangling Ref +
    kein Sheet-Wachstum). `ArrangeTimelineView` only: `.plugins`-Case aus dem geteilten Single-
    Sheet + Lane-Menü-Plugin-Section + `@Environment(AUv3Host)` raus; Automation-Button + a11y-
    `pluginAssignmentSummary` bleiben. Datei jetzt AUv3-symbolfrei. Kein Audio-Verhalten geändert.
  - ✅ **2b — Per-Spur-Hosting ab GESHIPPT** — Commits `126172a` + `f372960` (Orphan-Test-Fix),
    beide echten Gates grün. Gelöscht: `LaneAUInstrumentHost.swift`, `AUNoteVoice.swift`,
    `LaneAUAssignmentTests.swift`, `AUNoteMIDITests.swift` (−665 Zeilen). Chirurgie:
    `EchoelmusicApp` (`laneAUHost`-State + ganzes Wiring raus; MultiRoll-Note-Closure + Slot-
    Sinks routen NUR noch `laneVoiceRack`), `AudioEngine` (`attach/detachLaneInstrument` raus;
    `effectsAcceptingChainFormat` BLEIBT — global-host-shared, 2c), `FeatureFlags`
    (`laneAUInstruments` raus), `TimelineStore` (Doc-Kommentar). audio-thread-reviewer: Note-Pfad
    intakt (built-in ist klingender Fallback), keine Audio-Thread-Verletzung, keine Hänge-Noten
    bei Stop, `HostMusicalState`/`effectsAcceptingChainFormat` unberührt. LEHRE (HARNESS_LEDGER):
    beim Löschen einer Datei JEDES darin definierte Symbol greppen (nicht nur den Klassennamen) —
    `AUNoteVoice.swift` beherbergte auch `AUNoteMIDI`, dessen Test blieb sonst verwaist.
  - **2c — Global-Host + Browser + Discovery weg** (in 2 Schritten, weil der Host-Engine-Schnitt
    Note-Routing-Chirurgie in 3 View-Dateien ist):
    - ✅ **2c-i — Browser-UI weg GESHIPPT** — Commit `7ebaa42`. `AUv3BrowserView.swift` +
      `AUv3PluginUIView.swift` gelöscht (seit 2a TOTER Code — kein Sheet präsentiert sie mehr,
      grep-bestätigt null Refs). Null Verhaltensänderung. De-riskt 2c-ii.
    - ✅ **2c-ii — Global-Host-Engine + auHost-Reads weg GESHIPPT** — `AUv3Host.swift` (+`HostedAUInfo`
      +`AUv3ScanDiagnostic`) + `AUHostContext.swift` gelöscht; `auHost`-Chirurgie in `EchoelmusicApp`
      (@State + .environment + use/useParameters/scan/restoreChains/persistState + pianoRoll/midiPub-Args),
      `EchoelStudioView` (@Environment + panic-allNotesOff), `MIDIBusPublisher` (auHost-Param + noteOn/off;
      built-in-Bus-Publish jetzt UNBEDINGT — Ext-Keyboard spielt Echoels Stimme), `PianoRollView`
      (auHost-Param + allNotesOff + noteOn/off + `suppressBuiltIn`→immer built-in + tote midiByte/velocityByte).
      Tests gelöscht: AUv3HostTests, AUv3ManufacturerCodeTests, AUv3ScanDiagnosticTests (letzterer NICHT
      „kompiliert weiter" wie der alte Plan-Text sagte — `AUv3ScanDiagnostic` lebte IN AUv3Host.swift,
      stirbt mit ihm); `testHostedAUInfo_mapsToPluginRef_lossless` aus TimelineLaneAUAssignmentTests chirurgisch
      raus (AUPluginRef + Rest-Tests bleiben). Gefangener Compile-Breaker: `suppressBuiltIn` wurde noch in
      `desiredSub` (PianoRollView) gelesen → mitgefixt. Reste für 2d: unbenutztes `parameterRegistry`-@State,
      tote AudioEngine-AU-Methoden, Kommentar-Referenzen (EchoelmusicApp:211/497, AudioEngine:959,
      HostMusicalState:16, AUPluginRef:12/46), unbenutztes `HostMusicalState` (falls AUHostContext einziger
      Consumer war). −1852/+21 Zeilen. Commit `b26c800` (+ cosmetic `73bb223`). audio-thread + code-reviewer
      BEIDE CLEAN. Xcode Compile Check GREEN auf 73bb223, CI/CD Pipeline GREEN auf b26c800 (b26c800s Compile
      = „cancelled", weil 73bb223 ihn ablöste — normal). NEEDS-FOUNDER-VERIFY (Geräte-Ton, TestFlight-Freeze).
  - **2d — Model + Persistenz + Entitlement + Tests + CI:** `TimelineLane.instrument/effects`
    (decodeIfPresent-sicher: Keys droppen, nie hart decode), `AUPluginRef` löschen,
    `LaneInstrumentLabel`+`pluginAssignmentSummary` Chirurgie, `AUParameterMapping`/`Bridge`
    löschen (Registry BLEIBT), `inter-app-audio`-Entitlement, 8 Hosting-Tests, tote
    testflight.yml-Diagnose-Steps. Persistence-&-Schema-Steward + security-agent (Signing).
  - Schutz: `attachInstrument(_:AVAudioUnit)` (AudioEngine:777) + `HostMusicalState` sind die
    ZWEI Stellen, wo ein Hosting-Schnitt in Eigen-Sound bluten könnte — Restnutzer erst prüfen.
