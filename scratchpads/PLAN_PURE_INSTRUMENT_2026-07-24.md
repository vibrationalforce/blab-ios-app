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

## SLICE-6-ZUSATZ (Fund aus dem #131-Sheet-Audit 2026-07-25) — die LÜGENDE Tool-Liste

`EchoelStudioView` trägt noch einen TOTEN Tür-Mechanismus, der aktiv in die Irre führt:
- `toolsSection` (`:926`) existiert als View-Builder (`gridChip { openTool(t.id) }`), ist aber NICHT
  im Body komponiert (Kommentar `:365`: „pure dead weight on the 21-modal metadata chain").
- `toolItems` (`:866`) bewirbt weiter **`pianoroll`**, **`sound`** (= Patch-Editor), `automation`,
  `audioclip`, `plugins`, `broadcast`.
- `openTool` (`:898`) hat für KEINEN dieser sechs einen Case → `default: break`.
- Der selbst dokumentierte Invariant `:865` („guards their action in `openTool`, so a tool never
  appears without a live action") ist damit **VERLETZT**. Ein Re-Mount der Grid würde sechs Chips
  zeigen, die stumm nichts tun.
→ Slice 6: entweder löschen (toolItems/openTool/toolsSection/ToolItem/ToolCat/gridChip) ODER den
Invariant wiederherstellen. **NICHT** die Grid re-mounten, um #131 zu lösen — #131 nutzt den LEBENDEN
`.echoelChromeDoor`-Router (Plan: `scratchpads/PLAN_REDOOR_CRAFT_TOOLS_2026-07-25.md`).

## SLICE-6-LISTE (kumuliert aus den 4b/4c/4d-Reviews — nichts still verwaisen lassen)

Von den Slice-4-Löschungen verwaist, alle Workstation-Rest (kein Keeper):
- `Studio/SurfaceSwitcherBar` + `WorkspaceSurface`-Enum (Chips ohne Fläche)
- `Studio/ClipLaunchGlyph.swift`
- `Studio/WaveformView.swift` (BEIDE Typen) **+ `Audio/WaveformCache.swift`** (`WaveformCache`/`WaveformData`,
  Consumer war nur `WaveformView.swift:80`) — 4c-Review-Fund
- `Sequencer/ClipAutomationEdit.swift` **+ `Tests/…/ClipAutomationEditTests.swift`** — 4d-Review-Fund
  (reines, getestetes Enum; einziger Prod-Consumer war `ClipAutomationView`)
- die VIEW-Structs in `Studio/TimelineAutomationRow.swift` (`TimelineAutomationRow`,
  `TimelineAutomationHeadCell`, `TimelineAutomationTargetOption`)

⚠ **GUARDS für Slice 6 (sonst bricht der Build oder es stirbt ein Keeper):**
- **`TimelineAutomationRowMath` MUSS bleiben** — `Core/TimelineStore.swift:718` ruft `sameParameter`.
  Also die View-Structs aus der Datei entfernen, NICHT die Datei löschen.
- **`AutomationTarget` (`Core/AutomationPlayer.swift`) NICHT mitnehmen:** sein einziger Consumer außerhalb
  der eigenen Datei ist `TimelineAutomationRow.swift` — Zeilen 116/117 liegen INNERHALB des Keepers
  `TimelineAutomationRowMath.sameParameter`, nur Zeile 146 im doomed `catalog`. Nimmt man `AutomationTarget`
  mit, bricht `TimelineStore.swift:718`.
- **`AutomationCanvasMath` BLEIBT** (KEEP, getestet) — behält nach dem `ClipAutomationEdit`-Wegfall noch
  6 lebende Consumer über `TimelineAutomationRowMath`.
- **`DSP/WaveformReducer.swift` BLEIBT** — reiner, testgedeckter Core.
- Kommentar-Sweep: `Studio/EchoelStudioView.swift:361-366` behauptet noch, Piano-Roll/PatchEditor würden
  „von den Timeline-Spur-Türen (ArrangeTimelineView's ArrangeModal)" geöffnet — die Timeline ist seit 4b weg.
  Genau die Sorte Kommentar, die eine künftige Session auf eine nicht existierende Tür jagt; zusammen mit
  Task #131 (Re-Dooring) korrigieren.

## ⚠ SLICE-5-VORBEFUND (2026-07-25, exakt lokalisiert — korrigiert die pauschale Data-Loss-Warnung)

Die bisherige Plan-Zeile „Enum-Case-Entfernung = Data-Loss (persistierter `.video`-Clip decodiert nicht
mehr)" war RICHTIG im Alarm, aber ZU PAUSCHAL. Die zwei Decode-Stellen verhalten sich UNTERSCHIEDLICH:

- ✅ **`Clip.kind` (`Sequencer/Clip.swift:172`) ist SCHON SICHER:**
  `kind = (try? c.decode(ClipKind.self, forKey: .kind)) ?? .midi` — `try?` schluckt den Fehlschlag.
  Fällt `ClipKind.video` weg, decodiert ein persistierter `"video"`-Clip als `.midi` weiter.
  **Kein Crash, kein Dokumentverlust** (der verwaiste `mediaRef` ist harmlos, es spielt nichts mehr Video).
- ⚠ **`TimelineLane.kind` (`Sequencer/Timeline.swift:145`) ist die Falle — Mechanismus bestätigt,
  SCHADENSRADIUS von mir zu hoch angesetzt (Persistence-Steward-Audit 2026-07-25 korrigiert mich):**
  `kind = try c.decodeIfPresent(ClipKind.self, forKey: .kind) ?? .midi` — `decodeIfPresent` liefert nur
  bei FEHLENDEM/`null` Key `nil`; bei VORHANDENEM, aber unbekanntem Wert **wirft** es (`dataCorrupted`).
  **ABER es GIBT ein umschließendes `try?`:** `TimelineDocument` decodiert seine Arrays über den
  `Lossy<T>`-Wrapper (`Timeline.swift:392-395`, `lossyArray` :400-405, angewandt :413-418), der pro
  ELEMENT fängt — belegt durch den existierenden Test `TimelineDecodeTests.swift:118`
  („corruptLaneElement_isDropped_restSurvive"). `TimelineStore.swift:32` ist die einzige Decode-Stelle,
  es gibt keinen ungeschützten Pfad.
  **Korrigierte Folge: KEIN Projektverlust (nicht CRITICAL), sondern HIGH —** die `"video"`-Spur
  **verschwindet still**, ihre `TimelineRegion`s überleben aber (Regionen decodieren eigenständig :416 und
  tragen kein `kind`) → **verwaiste, unsichtbare, unspielbare Regionen bleiben in der Datei.** Symptom für
  den Nutzer: eine Spur ist ohne Fehlermeldung aus dem Song verschwunden.
  **Der Fix bleibt trotzdem Pflicht** — eine still gelöschte Spur verletzt das Gesetz genauso, und der
  Kommentar `Timeline.swift:138-142` behauptet ausdrücklich, `kind` sei „nach dem decodeIfPresent-LAW"
  verteidigt, was für Wert-Änderungen falsch ist. Die Herabstufung darf den Fix NICHT abbestellen.
- ⛔ **Slice 5a muss DREI Zeilen fixen, nicht eine** (Steward-Fund, alle in `TimelineLane.init(from:)`,
  alle nach Haus-Idiom A `(try? c.decode(...)) ?? default`, Fallback unverändert → Round-trip bit-identisch):
  - `:145` `kind` (`ClipKind`) · `:154` `builtinInstrument` (`TrackInstrument`, Fallback ist schon `nil`)
  - `:160` `genreOverride` (`MusicStyle`) — **relevant, weil die Genre-Kuration (#125) Genres streichen
    könnte**; degradiert zu `nil` = „folge der globalen Auswahl", exakt der dokumentierte Default.
  - optional `:161` `mood` (`MoodProfile`, `BioComposer.swift:78-99`) — **synthetisiertes** `Codable`, alle
    acht `Float` sind PFLICHT-Keys → ein partielles Mood-Objekt wirft und die Spur fällt weg. Nicht von der
    Enum-Entfernung getriggert, aber die letzte ungeschützte Stelle und der billigste Begleit-Fix.
  - Plus: Kommentar `:138-142` korrigieren + Decode-Tests in `TimelineDecodeTests.swift`. Der Test muss
    prüfen, dass die Spur **erhalten** bleibt (`lanes.count == 1`, `kind == .midi`) — nicht bloß, dass das
    Dokument überlebt, denn das tut es heute schon durch Wegwerfen der Spur.
- ✅ **`RecordSource.videoCapture` GEKLÄRT: NUR ABGELEITET, nie persistiert** — `recordSource` ist überall
  eine berechnete `var` (`TrackInstrument.swift:71`, `Timeline.swift:123-132`), steht in keinem `CodingKeys`,
  kein Stored Property dieses Typs existiert. Entfernen ist persistenz-sicher. **Kopplung:**
  `Timeline.swift:129` (`case .video: return .videoCapture`) → `ClipKind.video` und `.videoCapture` müssen
  im GLEICHEN Commit fallen, sonst kompiliert der Switch nicht.
- ✅ **KEIN `schemaVersion` einführen** (Steward-Empfehlung, gut begründet): das `SpatialScene`-„Vorbild" ist
  eine Warnung, kein Muster — es hat NULL Migrations-Branch, wird laut Grep in `Sources/` überhaupt nie
  persistiert (`SpatialSceneStore.swift:33` baut es zur Laufzeit neu), und sein Decoder ist der
  undefensivste im Repo (voll synthetisiert = Pflicht-Keys). Ein als Pflichtfeld hinzugefügtes
  `schemaVersion` wäre **selbst eine neue Falle** (jedes ältere Dokument hat den Key nicht → der
  Versions-Check wirft, bevor irgendeine Migration läuft). Feldweise Defensive ist ZUSTANDSLOS und scheitert
  sichtbar im Test; eine Versionsnummer ist Disziplin über Sessions hinweg — bei Ralph-Takt + Kontext-
  Kompaktierung ist eine nicht-gebumpte Version schlimmer als keine. Falls je gewünscht: nur als
  `decodeIfPresent ?? 0` für Diagnose, NIE den Decode daran hängen.

→ Slice 5 daher: **5a = rein defensiv** (die 3–4 Zeilen + Kommentar + Tests, KEIN Enum-Wegfall, reines
Foundation → läuft auf Linux-CI), **5b = Enum-Entfernung** (`ClipKind.video` + `RecordSource.videoCapture`
zusammen), danach die Modell-Retirement-Slices. Keep/Cut je Typ: siehe Abschnitt darunter.

## SLICE-5-PLAN (DAW-Model-Removal) — GEPLANT 2026-07-25 (planning-agent + Persistence-Steward + Council)

**Reihenfolge-Entscheidung: Slice 5 kommt NACH Task #131** (Re-Dooring). #131 ist Ship-Gate-Punkt 2
„Kontrolle" — ohne es hebt der Freeze nicht; Slice 5 ist Hygiene ohne sichtbaren Nutzen. Zusätzlich
gibt es eine **echte Abhängigkeit** in dieser Richtung (siehe „Offene Produktfrage" unten).

### Widerlegte Annahme (wichtig — nicht aus dem Gedächtnis weiterschleppen)
**Die Launch-Kette treibt NICHT den Loop-Modus.** Ich hatte `LaunchQuantizer`/`ClipLaunchEngine`/
`LaneLaunchLatch` als mögliche Keeper vermutet — **falsch.** `LaunchQuantizer` (`:18`) hat NULL Consumer
in `Sources/` (nur Tests); `LaneLaunchLatch.swift:13` nennt es selbst „legacy"; und die Nachfolge-Kette
ist ebenso tot: `launchRegion`/`stopLaunched`/`launchState` (`TimelineRegionPlayer.swift:202/218/226`)
haben genau EINEN Aufrufer — `ClipLaunchGlyph.swift:49/52/54` — und `ClipLaunchGlyph` hat null Mount-Sites.
**Der Loop-Modus ist die bio-generative Schleife** (`player.pattern`-Pfad, `WorkspaceView.swift:418`),
nicht Clip-Launching. → alle drei CUT.

### KEEP — instrument-seitig, per Call-Site belegt
| Typ | entscheidender Consumer |
|---|---|
| `MIDIFileExporter` | `EchoelStudioView.swift:4244` (`exportMIDI()`) — Export ist Keeper-Feature |
| `MIDIFileImporter` | `EchoelStudioView.swift:4331/4339` |
| `LoopCutter` | `EchoelStudioView.swift:4241/4242` |
| `AutomationPlayer` + `AutomationTarget` | `EchoelmusicApp.swift:731/798`, `PianoRollView.swift:649` |
| `AutomationLane` | `PianoRollView.swift:500/508` — gezeichnete Automation, die spielt |
| `TimelineTime` | 480-PPQ-Namespace, überall (`EchoelStudioView:4024/4090`, `WorkspaceView:436/442`, `RecordController`) |
| `SpatialSceneStore` | `ADMOSCSender.swift:78/115` — **die Ausgabe-Stufe** |
| `LaneVoiceRack` (+`Pool`/`SlotMap`/`Kind`/`RackPlan`) | `EchoelStudioView` 8 Stellen — FX-Inserts + Tuning |
| `MediaLibrary` | `BeatPlayer.swift:597` `resolveRef` (Drum-Samples) + SampleBrowser |
| `TimelineStore` · `ClipStore` · `TimelineDocument`/`Lane`/`Region` | `TransportBar.toggle()` = `WorkspaceView.swift:410` liest `timelineStore`/`clipStore`/`timelinePlayer`; `EchoelStudioView:3339/4045/4084/4094` |

### KEEP/DEFER — NICHT in Slice 5 anfassen
`TimelineRegionPlayer` (`:53`) ist ein **Hybrid**: Workstation-Hälfte (`play(document:clips:)` ←
`WorkspaceView:437`) UND Instrument-Hälfte (~15 Timbre-Sinks, `EchoelmusicApp.swift:582-717` —
`slotKindSink`/`rollPatchSink`/`rollTransposeSink`/`slotPanSink` → `laneVoiceRack`/`polyVoice`), getickt
via `PianoRollView.swift:647`; `FeatureFlags.swift:50` `multiRoll` ist **default-ON**. `MultiRollFanout`
+ `TimelineScheduling` sind seine Innereien. **Naiv geschnitten bricht Per-Spur-Timbre.** Braucht eine
EIGENE Slice, die zuerst das Timbre-Routing heraustrennt. Ebenso NICHT anfassen: das Trio
`TimelineStore`/`ClipStore`/`TimelineDocument`.

### CUT — null lebende Instrument-Consumer
`LaunchQuantizer` · `ClipLaunchEngine` · `LaneLaunchLatch` · `ClipLaunchGlyph` ·
`ArrangementStore` · `Arrangement` · `ArrangementPlayer` (getickt bei `PianoRollView:646`, aber No-Op
ohne `Arrangement` — nichts kann eine starten) · der Audio-Datei-Region-Cluster (`AudioClipRegion`,
`AudioClipPlayer`, `AudioLanePlayer`, `AudioClipFactory`, `AudioRegionPlayback`, `StretchPlan`,
`StretchMode`, `TempoMatch`; einziger lebender Eintritt `EchoelmusicApp.swift:717`) ·
`MIDINoteRecorder` · `BioAutomationRecorder` · `AutomationGestureRecorder` · `TakeRecorder` ·
`RecordController` · `RecordAnchor` · `SpatialAutomationMapping` (hat selbst null Consumer).

**Tote `.environment`-Injektionen nach dem Cut:** `EchoelmusicApp.swift:366` `arrangementStore`,
`:368` `arrangementPlayer`, `:370` `recordController` (+ `@State` :95/:100/:104 + `recordController.wire(...)`
:840-849 + die `midiPub.onRecordNoteOn/Off`-Tees). **Bleiben müssen** `:363` clipStore, `:367`
timelineStore, `:369` timelinePlayer (TransportBar).

### Grep-Fallen (nicht darauf reinfallen)
`AudioEngine.swift:781/788/795` „Clip player node" sind **Log-Strings**, `:765` ein Doc-Kommentar —
`AudioEngine` hängt NICHT an `Clip`/`AudioClipPlayer`. `BeatPlayer.swift:461/468/588/592` sind **alle
Doc-Kommentare**; echte Nutzung nur `MediaLibrary.resolveRef` `:597`. `PianoRollModel.loadArrangement` /
`arrangementForExport()` / `arrangementBars` sind **eigene Member des Modells** und hängen NICHT am
`Arrangement`-Typ — beide load-bearing (`EchoelStudioView:3901/4239`). `LaneVoicePlan` existiert nicht
(gemeint: `LaneVoiceRackPlan.swift:44` + `SlotCommand:31`, beide KEEP).
`Clip` ist ein **Teil-Cut**: `MIDIFileExporter.swift:199` hat eine `export(clip:)`-Overload, die
`EchoelStudioView` nicht nutzt (nur `exportCombined`) → diese eine Overload löschen entkoppelt den Keeper.

### Sub-Slices (je 1 Ralph-Commit, Gates grün + Reviewer, leaf-first)
- **5a — REIN DEFENSIV, kein Enum-Wegfall:** die 3(+1) Decode-Zeilen in `TimelineLane.init(from:)`
  (`:145`/`:154`/`:160`, optional `:161`) auf `(try? c.decode(...)) ?? default` + Kommentar `:138-142`
  korrigieren + Decode-Tests (Spur muss ERHALTEN bleiben, nicht nur das Dokument). Pure Foundation →
  Linux-CI. **Reviewer: code-reviewer als Persistence-Steward.** MUSS vor 5b liegen.
- **5b — Enum-Entfernung:** `ClipKind.video` + `RecordSource.videoCapture` im GLEICHEN Commit
  (`Timeline.swift:129`-Kopplung) + `Clip.swift:86/190`, `TakeRecorder.swift:76`,
  `TrackInstrument.swift:120/130`. Persistence-Steward.
- **5c** `LaunchQuantizer` (+Tests) — voll isoliert, null Risiko.
- **5d** `ClipLaunchEngine` + `LaneLaunchLatch` + `ClipLaunchGlyph` (+Tests) — eine geschlossene Kette.
- **5e** `SpatialAutomationMapping` → `AutomationGestureRecorder` → `BioAutomationRecorder`/
  `MIDINoteRecorder` → `TakeRecorder` → `RecordController` (leaf-first) + die `.environment`/`wire`-Reste.
- **5f** `ArrangementPlayer` → `Arrangement` → `ArrangementStore` + `.environment`-Reste.
- **5g** der Audio-Datei-Region-Cluster (8 Typen + `WarpedClipPlan`/`TimelineAudioSink`-Nutzung, ~8 Testdateien).
- **5h (eigene, später)** `TimelineRegionPlayer`-Split: Timbre-Sinks heraustrennen, DANN entscheiden.
- Schutz-Gate je Slice: `swift build` grün + Kern-Tests (EchoelDDSP/BioEventGraph/Sequencer/Genre/rPPG)
  + bio-generatives Spielen bleibt hörbar (Geräte-Verify beim Founder für 5e/5g/5h).

### ⚠ Offene Produktfrage, die #131 beantworten MUSS (deshalb #131 zuerst)
`syncPrimaryRollClip` (`EchoelStudioView.swift:4082`, gerufen aus dem Generate-Pfad `:3922`) schreibt die
komponierte Fassung in `ClipStore` + `TimelineStore`. Sein eigener Doc-Kommentar (`:4056-4060`) nennt den
Zweck: „so a tile shows on the Arrange timeline" — **diese Timeline ist seit Slice 4 weg.** Der Code läuft,
sein Zweck ist fort. Explizit NICHT klang-tragend („Purely ADDITIVE — the live-loop path … still drives
the sound"). **Ob dieser Spiegel stirbt, entscheidet #131b:** editiert die re-getürte `PianoRollView`
den GESPEICHERTEN Clip oder die LEBENDE Rolle? Bei „lebende Rolle" ist der Spiegel toter Ballast — und
damit fällt der Hauptgrund, dass das Instrument `ClipStore`/`TimelineStore` überhaupt anfasst.

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

- ✅ **Slice 3 (Video-Schnitt-Removal) — KOMPLETT GESHIPPT 2026-07-25 (3a-i…3e, alle Gates grün).** consumer-first, 6 Sub-Slices.
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
    - ✅ **3a-i — Video-Monitor-Tür zu GESHIPPT (2a235d0, Gates grün):** `WorkspaceView` `@AppStorage("video.monitor.visible")` +
      `FloatingVideoMonitor`-Präsentation raus. **KORREKTUR zur Planzeile:** die Kachel NICHT gelöscht — sie war ein Hybrid, dessen
      Kontextmenü die EINZIGE Tür zur Recorded-Clips-Library (`showVideoLibrary` → `VideoLibraryPanelContent`, Decision-A/#51-KEEP) war.
      Ground-truth (`.echoelChromeDoor "video"` → EchoelStudioView:532) zeigte das → **umgewidmet:** `EchoelVideoMonitorMini` →
      `EchoelClipsMonitorMini`, Tap öffnet jetzt die Clips-Library (vorher Long-Press), REC-Indicator bleibt. ui-state-reviewer CLEAN.
    - ✅ **3a-ii — `FloatingVideoMonitor.swift` GELÖSCHT (e9db7a2, Gates grün):** 386 Zeilen, alle 4 Typen (`FloatingVideoMonitor`,
      `MonitorVideoSink`, `MonitorPlayerView`, `VideoMonitorContent`) auf 0 Refs gegreppt. `MonitorVideoSink` (einziger Sink-Impl) nirgends
      instanziiert → compile-safe. code-reviewer CLEAN.
    - ✅ **3b — Video-Lane-PLAYBACK-Engine GELÖSCHT (2f86a6b, Compile-Gate grün, CI/CD lief noch):** `VideoLanePlayer.swift`
      (+`VideoRegionSink`/`VideoMonitorSelect`), `VideoRegionSync.swift`, `VideoResyncPolicy.swift` + 4 Tests (954 Zeilen). Alle 7 Symbole
      auf 0 Code-Refs (Rest = Doc-Kommentar in VideoClipView, stirbt in 3c). App-tot. `TimelineScheduling`-Doc-Kommentare entstaubt
      (`videoLaneEvents`/`videoLaneIDs` BLEIBEN → Slice 5). Data-Loss gewahrt (`ClipKind.video`/`RecordSource.videoCapture` intakt).
      code-reviewer CLEAN (kein Audio-Thread).
    - ✅ **3c — Video-Import-Tür zu GESHIPPT (6b271a5, Gates grün):** `ArrangeTimelineView` `case .video: VideoClipView(...)` → `EmptyView()`;
      „Video track"-Erzeugungs-Button raus; `VideoClipView.swift` gelöscht (411 Zeilen). ⚠ `ClipKind.video`-Case BLEIBT (Data-Loss). ui-state-reviewer CLEAN.
    - ✅ **3d — Video-Import/Export-Modell GELÖSCHT (78233c0, Gates grün):** `VideoClipFactory.swift`, `VideoRegionTrim.swift`, `VideoExportPlan.swift`,
      `VideoAudioPairing.swift`, `Video/VideoAudioExtractor.swift` + 3 Tests (707 Zeilen). `ClipNativeDurationTests.testNil_whenNotMeasured`
      chirurgisch auf `AudioClipFactory` umgestellt (Audio-Coverage behalten). persistence-steward CLEAN (`VideoRegionTrim` transient, kein Doc-Feld).
    - ✅ **3c-2 — Gestrandete Legacy-Video-Lane-Türen GELÖSCHT (7c20ef2, Gates grün):** Lane-Head „Import video…"-Button + Leer-Lane-Import-Gesture für
      `.video`-Lanes entfernt (waren tote Türen nach 3c). modalEditor `.lane`-Ternary auf `.audio` vereinfacht. code-reviewer CLEAN.
    - ✅ **3e — `Video/Shaders/ChromaKey.metal` GELÖSCHT (251433e):** 487 Zeilen loses File (nicht in project.yml/Package.swift; MetalBioView kompiliert eigene
      Shader inline via `makeLibrary(source:)`). `BioColorGradeParams` BLEIBT, nur der stale ChromaKey/BioGrade.metal-Kommentar entstaubt. code-reviewer CLEAN.
      **→ SLICE 3 KOMPLETT: Video-Schnitt entfernt; rPPG-Bio-Input + generatives Visual (inkl. VisualRecorder) behalten.**
  - Protection-Gate je Slice: rPPG-Bio-Input (CameraAnalyzer/CameraCapture/PulsePeriodEstimator/RPPGConditioning) +
    Visuals (MetalBioView/FloatingVisual/BioVisualParams) + Rausch-Triad + (rec A) VisualRecorder/VideoRecorder/VideoMuxer UNBERÜHRT.

- ✅ **Slice 4 (DAW-UI-Removal) — KOMPLETT GESHIPPT 2026-07-25, alle vier Sub-Slices, beide echten Gates grün je Commit:**
  4a `807dc0d` (ClipView, 219 Z) · 4b `eb58e7a` (ArrangeTimelineView + BodyVibeSurfaceView, 2567 Z) ·
  4c `1af527f` (AudioClipView, 471 Z) · 4d `36a8468` (AutomationView + ClipAutomationView, 711 Z).
  Summe ≈ 3968 gelöschte Zeilen, KEIN Rewire, KEINE Persistenz-Änderung, KEINE Test-Löschung.
  REINER DEAD-CODE-SWEEP, 4 Sub-Slices.
  **Ground-Truth-Verdikt: #124 IST fertig** — `WorkspaceView.body`:156 → `SurfaceHost`:129-133 mountet NUR `EchoelStudioView()`; die
  Arrange-Timeline + `SurfaceSwitcherBar` + alle DAW-Surfaces sind bereits UNMOUNTED. **Kein Navigations-/Rewire-Edit in Slice 4** —
  nur Löschung der jetzt-unerreichbaren Surface-Dateien. Kein `Codable`/Persistenz-Key berührt → **kein persistence-steward nötig** (das
  Modell ist Slice 5).
  - Boundary-Entscheidungen (evidenzbelegt):
    - **(A) Instrument behält KEINE Timeline/Clip/Arrangement-Fläche.** `AudioClipView` (Audio-Datei-Import) → **CUT** (erzeugt Timeline-
      Audio-Regions, die der Slice-5-`TimelineRegionPlayer` spielt — ohne Timeline kein Zuhause; DAW, nicht Instrument). **1-Zeilen-Founder-
      Confirm beim Freeze-Lift** (wie VisualRecorder). „Eigenen Sound importieren" überlebt via `SampleBrowserView` (per-Drum-Pad, BLEIBT).
      `PianoRollView` (Instrument-Noten-Editor) NICHT im Cut. `AutomationView`/`ClipAutomationView` (manuelle Automations-Editoren) → CUT;
      generative Bio-Operatoren/Variation-Maze BLEIBEN, `AutomationCanvasMath` (pure) BLEIBT. `BodyVibeSurfaceView` (per-Lane) → CUT der VIEW,
      die EchoelBodyVibe-Voice/Engine UNBERÜHRT.
    - **(B) Kein Rewire** — reiner Sweep. `SurfaceSwitcherBar` + `WorkspaceSurface`-Enum (unmounted Nav-Gerüst, `@AppStorage("workspace.surface")`) → **Slice 6**.
  - **KEEP (nicht in Slice 4 anfassen):** `ChannelRackView` (live Drum-Mix, `EchoelStudioView:1510`), `PianoRollView`, `TransportPositionView`
    (`WorkspaceView:472`, Always-on-Transport), `TimelineAutomationRow.swift` (dessen `TimelineAutomationRowMath` LIVE in `TimelineStore:718`;
    Orphan-View-Structs → Slice 6), `SampleBrowserView`, `PatchbayView` (Routing, kein DAW-Timeline). ArrangementView existiert nicht mehr (Plan-§C-Phantom).
  - **Sub-Slices (consumer-first: der Top-Consumer `ArrangeTimelineView` zuerst, dann sind die Leaf-Editoren Orphans):**
    - ✅ **4a — `ClipView.swift` GELÖSCHT (807dc0d, beide Gates grün):** 219 Z, ein Top-Level-Typ, 0 Live-Refs (alle Erwähnungen Kommentare;
      `AudioClipView` ist ein ANDERER, lebender Typ — unberührt). Zwei stale Kommentare entstaubt. ui-state-reviewer + code-reviewer CLEAN.
    - ✅ **4b — `ArrangeTimelineView.swift` (2432 Z) + `BodyVibeSurfaceView.swift` (126 Z) GELÖSCHT (eb58e7a):** EINE kohärente Löschung
      (BodyVibe konsumierte `LaneCompositionSection`, das IN ArrangeTimelineView lebte — einzeln gelöscht hätte es den Build gebrochen).
      Alle 10 externen ArrangeTimelineView-Refs = Kommentare; `LaneCompositionSection`/`BodyVibeSurfaceView` 0 externe Refs. BodyVibe-ENGINE
      (Sequencer/BreathArp, TrackInstrument, LaneVoiceKind, LaneVoiceRack) unberührt. ui-state-reviewer + code-reviewer CLEAN.
      **⚠ FOLGE — 8 Views verlieren ihre EINZIGE Tür** (Views selbst NICHT gelöscht; waren vor dem Commit schon unerreichbar, da ihr Presenter
      unmounted war → keine neue Regression, aber jetzt dauerhaft): `AudioClipView` (→4c) · `AutomationView` + `ClipAutomationView` (→4d) ·
      `ClipLaunchGlyph` + `FileWaveformView` + `TimelineAutomationRow` (→ Slice 6 Cleanup) · **`PianoRollView` + `PatchEditorView` = KEEPER
      OHNE TÜR → Task #131** (ihre eigenen EchoelStudioView-Sheets fielen v10.79.207; CLAUDE.md-Behauptung „reachable from EchoelStudioView"
      war stale, 2026-07-25 korrigiert). Ebenfalls türlos: `ImmersiveStageView` (Spatial-Stage; Header dokumentiert es jetzt).
    - ✅ **4c — `AudioClipView.swift` (471 Z, +`WaveformTrimEditor`) GELÖSCHT (1af527f):** Orphan seit 4b, 0 Refs (nicht mal Kommentare).
      Boundary-A ist seit 2026-07-25 nicht mehr founder-offen — `docs/dev/PRODUCT_DEFINITION.md` (Founder-Delegation, Grand Council) setzt
      **Editor ≠ Workstation**: Audio-Datei-Import/Trim = Workstation = CUT. code-reviewer CLEAN.
      **⚠ SLICE-6-SCOPE WÄCHST (Reviewer-Fund, Kaskade eine Ebene tiefer als kartiert):** `Studio/WaveformView.swift` (beide Typen —
      `WaveformView` + `FileWaveformView`) UND `Audio/WaveformCache.swift` (`WaveformCache` + `WaveformData`, einziger Consumer war
      `WaveformView.swift:80`) sind jetzt verwaist. Kein Keeper hängt dran (`SampleBrowserView` zeichnet KEINE Waveforms).
      **`DSP/WaveformReducer.swift` BLEIBT** — reiner, testgedeckter Core (`WaveformReducerTests`), wie die anderen gehaltenen puren Cores.
      Doc-Drift für den Epic-Doc-Sync: `docs/dev/VISION_REALITY_2026-07.md:50` nennt `WaveformView` noch als geshippte Timeline-Komponente.
    - **4d — `AutomationView.swift` (412 Z) + `ClipAutomationView.swift` (299 Z) löschen** (Orphans nach 4b; `AutomationCanvasMath` UNBERÜHRT). code-reviewer.
  - Delete-Rule je Slice: jeden deklarierten Top-Level-Typ greppen (0 Live-Consumer) VOR rm. Keine Test-Löschung (die toten Views haben keine eigenen Tests;
    `ClipTests`/`TimelineAutomationRowTests`/`TimelineStoreAutomationEditTests` müssen weiter kompilieren — testen KEEP-Modell/Math).
