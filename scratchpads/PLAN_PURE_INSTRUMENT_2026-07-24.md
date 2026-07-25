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
  - **2d — Model + Persistenz + Entitlement + Tests + CI (in 4 Sub-Slices, Map 2026-07-25).**
    **PERSISTENZ-KORREKTUR (kritisch):** ein persistiertes Feld zu ENTFERNEN ist inhärent sicher —
    Swift-Keyed-Decoding IGNORIERT unbekannte Keys. Ein alt-gespeichertes `TimelineDocument` mit noch
    vorhandenen `instrument`/`effects`-Keys decodet fehlerlos gegen ein Struct ohne diese Felder. Das
    decodeIfPresent-GESETZ schützt nur die GEGENrichtung (hartes decode eines ABWESENDEN Keys). Also:
    Props + Init-Params + die 2 decodeIfPresent-Zeilen droppen, KEIN CodingKey-Retain nötig, NIE in ein
    hartes `try decode` verwandeln. Reihenfolge hart 2d-1 → 2d-2 (Consumer VOR dem gekoppelten Trio).
    - ✅ **2d-1 — Consumer der persistierten Felder weg GESHIPPT (e280a1f, Gates grün):** `ArrangeTimelineView`
      (pluginAssignmentSummary + Puzzle-Icon + a11y-Klausel raus; Spurkopf-Caption jetzt
      `lane.builtinInstrument?.displayName`), `LaneInstrumentLabel.swift` + Test gelöscht (Zweck war
      AUv3-Belegungs-Legibilität), `MultiRollFanout.instrument(forSlot:)` + Test raus (kein Live-Caller).
      Modell (`AUPluginRef`, `TimelineLane.instrument/effects`, `TimelineStore.setLaneX`) BLIEB → grün,
      Null-Persistenz-Risiko. code + ui-state-reviewer.
    - ✅ **2d-2 — das gekoppelte Trio GESHIPPT (304f750, DATA-LOSS-kritisch, CI/CD grün = der echte Beweis):**
      `TimelineLane.instrument/effects` Props/Init/decode raus (Legacy-JSON-Roundtrip-Test ZUERST in
      TimelineDecodeTests — decode ignoriert unbekannte Keys, nie hartes `try decode`), `TimelineStore.setLaneInstrument/
      setLaneEffects` raus, `AUPluginRef.swift` + `AUParameterMapping.swift` + `AUParameterBridge.swift` gelöscht
      (`EchoelParameterRegistry`/`ParameterApplyRouter` BLIEBEN — sauberer Split verifiziert), Tests
      AUParameterMapping/Bridge + TimelineLaneAUAssignment (3 Klassen). Persistence-Steward.
    - ✅ **2d-3a — toter AudioEngine-AU-Code GESHIPPT (0315f9a, beide Gates grün):** 10 tote AU-Graph-Methoden
      (attachInstrument-Graph-Pfad, attach/detachAU, connect/disconnect-Varianten, effects-Format-Prüfer,
      auChainFormat/masterFXFormat/rewireMasterFX) via Python-Range-Delete raus (183 del/0 add). KEEP:
      attach/detachSourceNode, beide attach/detachPlayerNode-Overloads, captureRecentMixAudio, prepareGraph.
    - ✅ **2d-3b — write-only HostMusicalState-Mirror + App-@State GESHIPPT (c3b3666, Gates laufen):**
      `HostMusicalState.swift` (+`HostBeatMath`) + Test gelöscht (AUHostContext war einziger Leser, in 2c-ii weg);
      `Transport.hostStateMirror`/didSet/`syncHostMirror`/alle Mirror-Writes aus setTempo/play/stop/seek/tick
      (inkl. `oldAbsoluteStep` + Sample-Position-Akkumulation) raus — `tick()` byte-verhaltensgleich minus Mirror,
      `stepSubs`/`stopSubs` unangetastet; `AudioEngine`-`sampleRate`-Write + `EchoelmusicApp`-`.shared`-Wire +
      totes `parameterRegistry`-@State raus. audio-thread-reviewer CLEAN (0 Nicht-Mirror-Leser der Sample-Position).
    - **2d-4 — Entitlement + CI (LETZTE Sub-Slice, geplant 07:27Z-Trigger):** `inter-app-audio` aus
      Echoelmusic.entitlements (verwaist, kein Signing-Bruch; project.yml unberührt), tote
      testflight.yml-AUv3-Diagnose-Steps (~458-509, 634-692). security-agent (Signing). → schließt Slice 2.
  - Schutz (ERLEDIGT): `attachInstrument(_:AVAudioUnit)` (in 2d-3a raus) + `HostMusicalState` (in 2d-3b raus)
    waren die zwei Stellen, wo ein Hosting-Schnitt in Eigen-Sound hätte bluten können — beide sauber
    entfernt, Rest-Nutzer per Grep + audio-thread-reviewer als null bestätigt. Kein Eigen-Sound-Pfad berührt.

- ▶ **Slice 3 (Video-Schnitt-Removal) — GEPLANT 2026-07-25 (planning-agent + Council), consumer-first, 6 Sub-Slices.**
  Boundary-Entscheidungen (gegen echte Call-Sites, `file:line`-belegt):
  - **(A) VisualRecorder BLEIBT (Council: proceed, non-destruktiver Default).** Nimmt das GENERATIVE Visual auf
    (MetalBioView/FloatingVisual-Drawable-Blit, `VisualRecorder.swift:14-17` „does NOT touch the rPPG camera path") =
    Instrument-Performance-Output, NICHT Kamera-Schnitt. Nur 5 funktionale Consumer (alle auf dem Bio-Visual:
    `EchoelmusicApp:164/342`, `MetalBioView:317/416/1067`, `EchoelStudioView:778-792`, `FloatingVisualWindow:634-643`,
    `HeaderMonitors:430-474`); die 3 in `MediaLibrary`/`ClipHighlightSelector`/`VideoClipFactory` sind NUR Kommentare.
    Fundament der pending Founder-Feature **#51 EchoelPublish** (#93 ClipHighlightSelector geshippt). → damit bleiben
    auch `VideoRecorder`/`VideoMuxer`/`VideoMuxAlignment` (die File-Sink-Kette) + `AudioEngine.captureRecentMixAudio`.
    **Beim Freeze-Lift 1 Zeile Founder-Bestätigung** (Plan-§B-Default war „konservativ mit-schneiden"; Evidenz kippt auf
    keep). Contingency 3f-3h (cut VisualRecorder) liegt bereit, falls Founder „alles weg" sagt.
  - **(B) Sequencer/-Video-Lane-Dateien → alle Slice 3** (consumer-first; das generische DAW-Modell hängt NICHT an ihnen).
    **NICHT anfassen:** `ClipKind.video` (`Clip.swift:52`), `TrackInstrumentKind.videoCapture` (`TrackInstrument.swift:112`),
    `Timeline.swift:129`-Mapping, `TimelineDocument.videoLaneIDs` — Enum-Case-Entfernung = Data-Loss (persistierter `.video`-
    Clip decodiert nicht mehr) + DAW-Modell → **Slice 5** mit Migrations-Entscheidung.
  - **(#126 „Video im Loop Takt genau geschnitten") = superseded von #121** — same-day Founder-Detail INNERHALB des Video-
    Editing, das #121 entfernt; moot, sobald Video-Schnitt weg ist. Kein Founder-Question (Supersession, keine Ambiguität).
  - **Sub-Slices (je 1 Ralph-Commit, consumer-first, Gate grün + Reviewer):**
    - **3a-i — Video-Monitor-Tür zu (UI):** `WorkspaceView` `@AppStorage("video.monitor.visible")`:110 + `FloatingVideoMonitor`-
      Präsentation:178-179 + `EchoelVideoMonitorMini`-Toggle:264-265 raus; `HeaderMonitors` `EchoelVideoMonitorMini`-Struct:429 raus
      (VisualRecorder-Indicator:430 BLEIBT). ui-state-reviewer. (UserDefaults-Key, keine Codable-Persistenz.)
    - **3a-ii — `FloatingVideoMonitor.swift` löschen** (`MonitorVideoSink` = einziger `VideoRegionSink`-Impl + `FloatingVideoMonitor`). code-reviewer.
    - **3b — Video-Lane-PLAYBACK-Engine löschen:** `VideoLanePlayer.swift` (+`VideoRegionSink`/`VideoMonitorSelect`), `VideoRegionSync.swift`,
      `VideoResyncPolicy.swift` + Tests (`VideoLanePlayerTests`/`VideoResyncPolicyTests`/`VideoMonitorSelectTests`/`VideoInTracksTests`).
      Bereits app-tot (keine Instanziierung in Sources). code-reviewer (kein Audio-Thread — AVPlayer-Sink ging mit 3a-ii).
    - **3c — Video-Import-Tür zu:** `ArrangeTimelineView:533` `case .video: VideoClipView(...)` → `EmptyView()` (spiegelt `.visual`:534);
      `VideoClipView.swift` löschen. ui-state-reviewer. ⚠ `ClipKind.video`-Case BLEIBT (Data-Loss).
    - **3d — Video-Import/Export-Modell löschen:** `VideoClipFactory.swift`, `VideoRegionTrim.swift`, `VideoExportPlan.swift`,
      `VideoAudioPairing.swift`, `Video/VideoAudioExtractor.swift` + Tests (`VideoExportPlanTests`/`VideoAudioPairingTests`/
      `VideoImportLandingTests`); `ClipNativeDurationTests` chirurgisch (nur die Video-Methoden, Audio-Coverage behalten).
      code-reviewer **+ persistence-steward** (`VideoRegionTrim: Codable` — verifiziert transient, kein Doc-Feld).
    - **3e — `Video/Shaders/ChromaKey.metal` löschen** (loses File, nicht in project.yml/Package.swift; MetalBioView kompiliert eigene
      Shader inline). `BioColorGradeParams` BLEIBT (nur Kommentar-Ref). code-reviewer + Xcode Compile Check.
  - Protection-Gate je Slice: rPPG-Bio-Input (CameraAnalyzer/CameraCapture/PulsePeriodEstimator/RPPGConditioning) +
    Visuals (MetalBioView/FloatingVisual/BioVisualParams) + Rausch-Triad + (rec A) VisualRecorder/VideoRecorder/VideoMuxer UNBERÜHRT.
