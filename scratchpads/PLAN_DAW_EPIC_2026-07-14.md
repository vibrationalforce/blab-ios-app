# PLAN — DAW-Reifung (Founder 2026-07-14, "du entscheidest alles" + "arbeite 24h durch")

Founder-Wunsch (verbatim): "Automationen im Clip und auf der Timeline. Clips schneiden und
zusammenfügen. Audio und Midi endlich richtig ausarbeiten und integrieren. Videospuren
(Capture, importieren aus der Mediathek, Editieren, Effekte etc)." + MOTU Digital Performer
als Inspo (Profi-DAW: Automation auf jedem Parameter · Clip-Editing · Audio=MIDI gleichwertig
· Video-Spuren fürs Scoring). Leitprinzip übernommen: **jeder Parameter automatisierbar, jede
Spur gleichwertig** — aber Echoel bleibt bio-reaktives Instrument zuerst (kein DP-Klon).

Ground-truth via Explore (acc0ef7): siehe unten je Bereich. Ranking nach Wert×geringe Kosten.

---

## REIHENFOLGE (entschieden)

1. ✅ **Automation "alle Parameter"** (v214) — Fundament komplett audibel (Playback + UI + Clip/Timeline-
   Ebenen live & getestet). Es fehlt NUR die `router.bind`-Tabelle für die eingebauten DDSP-Params.
2. ✅ **Clips schneiden & fügen** (v215, Split/Join am Playhead) — Reine Tick-Mathematik + je
   eine TimelineStore-Methode + Toolbar-Knopf. Home-Fläche (ArrangeTimelineView) schon erreichbar.
3. **Audio-Import in eine Spur** — ✅ SLICE A (v216): Importer→App-Group-Kopie→addRegion.
   Audio-Lane-Tür (Lane-Kopf → „Open audio editor") zeigt jetzt „Add to timeline": lädt/trimmt
   Datei → `MediaLibrary.importAudio` (Kopie in App-Group `Media/Audio`) → `AudioClipFactory.clip/region`
   → freier ClipStore-Slot (`firstEmptySlotIndex`) + `TimelineDocument.nextStartTick` (hinter Lane-Inhalt)
   → `clips.setClip` + `timeline.addRegion`. Region zeigt Waveform + tap-audition (schon verdrahtet).
   Reviewer: security SECURE · concurrency PASS · code (Test-Hygiene + Doc-Kommentar gefixt).
   OFFEN (Folge-Slices): transport-synced **AudioLanePlayer** (Audio-Regions am geteilten Clock am
   startTick planen — heute klingt die Region NUR beim Antippen, nicht im Transport-Playback) ·
   Trim-OUT als harte Grenze (heute bar-gesnappt, contentOffset=In-Point) · Region-Editor lädt das
   referenzierte Medium (heute öffnet Long-press einer Audio-Region einen leeren Importer) · MIDI-Import
   erreichbar machen (MIDIFileImporter getestet, Trigger unerreichbar).
4. **Video-Spuren** — ✅ ETAPPE (a) (v217): Import→.video-Region + AVKit-Preview. Video-Lane-Kopf →
   „Import video…" öffnet `VideoClipView` (fileImporter .movie/.video → AVKit-VideoPlayer-Preview →
   Dauer via `AVURLAsset.load(.duration)` → „Add to timeline": `MediaLibrary.importVideo` (Kopie in
   App-Group `Media/Video`) → `VideoClipFactory.clip/region` → freier ClipStore-Slot + `nextStartTick`
   → `clips.setClip` + `timeline.addRegion`). Region = dim Block mit Name (keine Waveform/Audition —
   korrekt, „no engine → no door"). Reviewer: concurrency PASS · code (Doc-Divergenz + stale-async-Dauer
   + Fehler-Throw-Test gefixt). OFFEN: (b) **VideoLanePlayer** transport-synced (AVQueuePlayer an der
   Audio-Clock, VideoRegionSync/ResyncPolicy) — der Resolver MUSS beide mediaRef-Konventionen auflösen
   (Import=absoluter Pfad in Media/Video · Capture=Documents/Videos-Dateiname; im VideoClipFactory-Doc
   notiert) · (c) Trim-UI · (d) per-Spur-Video-FX (ChromaKey.metal verdrahten).

## TRANSPORT-PLAYBACK (Audio-Regions klingen im Transport)
- ✅ SCHEDULING-NAHT (v220, test-first): `AudioRegionPlayback` (rein, Foundation-only) — die
  Medien-Zeit-Abbildung, die `TimelineScheduling` (Onset/Clear existiert schon) für Audio fehlt:
  `filePositionSeconds(region,atTick,bpm)` · `startFrame(…,sampleRate)` · `frameCount(…)`. Bilden 1:1
  auf `AVAudioPlayerNode.scheduleSegment(startingFrame:frameCount:)` ab. Reviewer code: Mathematik
  korrekt (start+count landet exakt auf Region-Ende; max. 1 Sample Unterlauf, nie Overread der Grenze).
- OFFEN — der **AVFoundation-Executor** (`AudioLanePlayer`, geräteverifiziert): pro Audio-Lane ein
  `AVAudioPlayerNode` an der geteilten Clock; auf `TimelineScheduling.laneEvent == .load(region)` →
  `scheduleSegment(startFrame, frameCount)`, auf `.clear` → stop. **MUSS gegen `AVAudioFile.length`
  klemmen** (startFrame≥length ⇒ skip; frameCount = min(frameCount, length−startFrame)) — sonst EOF-
  Overread (in AudioRegionPlayback-Doku als Executor-Contract festgehalten). Danach dasselbe für Video.

## GEMEINSAME NÄHTE (Audio + Video Import teilen sich)
- `MediaLibrary` (Core/): `importAudio`/`importVideo` → App-Group `Media/{Audio,Video}`, UUID-Zielname,
  Endung erhalten, ein unreiner Kopier-Schritt (`copyIn`). `ClipStore.firstEmptySlotIndex` +
  `TimelineDocument.nextStartTick(inLane:)` = reine, getestete Platzierungs-Naht. Audio-Region klingt
  bei tap-audition + zeigt Waveform; Video-Region zeigt nur Block+Name. Transport-Playback für BEIDE
  (Audio-Regions + Video-Regions) = je ein eigenes Player-Subsystem, geräteverifizierungs-pflichtig,
  DEFER in eigene Design-Zyklen (nicht blind bauen+deployen).

---

## BEREICH 1 — Automation (Detail)

- **Audibel HEUTE:** PatternEngine.onTick → AutomationPlayer.applyStep (PianoRollView.swift:295);
  3 Enum-Targets live (masterLevel/tempo/filterCutoff-scale). Clip-Ebene (setClipAutomation) +
  Timeline-Ebene (setTimelineAutomationTick) + Kurvenbiegung (AutomationLane.shapedFraction) alle live.
- **UI erreichbar:** AutomationView (zeichenbar: tap/drag/bend/delete) via Spurkopf-Menü „Automation".
  Picker schaltet segmented→menu automatisch bei >3 Targets — Katalog-Erweiterung braucht KEINE UI-Arbeit.
- **Lücke:** ParameterApplyRouter.bind wird NUR für gehostete AUv3-Knöpfe aufgerufen (AUParameterBridge:44).
  Die eingebauten DDSP-Registry-Descriptoren (15) sind UNGEBUNDEN → per Placebo-Gesetz unsichtbar.
- **⚠️ SUBTILITÄT (verifiziert):** die Bio-Modulations-Schleife (applyBioModulation, EchoelDDSP:1274-1316)
  ÜBERSCHREIBT harmonicity/noiseLevel/reverbMix/filterCutoff kontinuierlich → diese direkt zu
  automatisieren ist zwecklos solange Bio läuft (bioBase-Var wirkt nur WÄHREND Bio läuft, nicht idle).
  → **Slice 1 bindet NUR bio-unabhängige, render-wirksame Params** (dsp-reviewer klassifiziert a97bc28).
  Die bio-umkämpften 4 = Folge-Slice (Automation×Bio-Komposition = Design-Entscheid).
- **SLICE 1 (jetzt):** `PolySynthVoice.bindAutomatable(into:)` bindet die sicheren keyPaths →
  `poly.<var>`; im App-Wiring (EchoelmusicApp ~:610) aufrufen. AutomationView listet sie dann
  automatisch → gezeichnete Kurven bewegen echtes Audio über den schon-verdrahteten applyStep→router-Pfad.
  Reviewer: dsp (Klassifikation) + concurrency + code. KEINE neue UI/Engine.

## BEREICH 2 — Clips schneiden & fügen (Detail)

- Vorhanden: addRegion/removeRegion/moveRegion/resizeRegion (nur trailing-trim). KEIN split/merge.
- Modell bereit: TimelineRegion{startTick,lengthTicks,contentOffsetSeconds,endTick} + TimelineTime.seconds.
- Home erreichbar; Playhead da (display-only); Region-Auswahl heute nur via Long-press→Editor-Sheet.
- **SLICE:** TimelineStore.splitRegion(id:atTick:) (pure Helper, contentOffsetSeconds korrekt für Media)
  + Toolbar „Split at playhead" in ArrangeTimelineView (Playhead-Tick → Region darunter splitten).
  Merge (mergeAdjacent) = nächste Inkrement. Voll unit-testbar. Reviewer: code + concurrency.

## BEREICH 3 — Audio & MIDI (Detail)

- Audio-Spuren STUMM auf Timeline (TimelineRegionPlayer plant nur MIDI). AudioClipPlayer existiert+getestet
  (nur Preview-Nutzung in AudioClipView, nie in Timeline). Kein Import→Lane-Pfad (AudioClipFactory da+getestet).
- MIDI weiter: Import (MIDIFileImporter getestet, aber Trigger via totem Tools-Menü unerreichbar), Export ok,
  Recording (RecordController: externe MIDI+Bio in Clips+Regions pro armed Lane; KEIN Audio-Input-Capture).
- **SLICE:** Audio-Import in Lane: .fileImporter an Audio-Lane-Tür → in App-Group kopieren →
  AudioClipFactory.clip/region → clips.setClip + timeline.addRegion → Region zeigt Waveform + tap-audition.
  Danach: AudioLanePlayer (Audio-Regions am startFrame/startTick am geteilten Clock planen, AVAudioPlayerNode).

## BEREICH 4 — Video-Spuren (Detail)

- Pur+getestet: VideoRegionSync/VideoRegionTrim/VideoClipFactory/VideoResyncPolicy/VideoExportPlan; ClipKind.video/.visual;
  „Video track" addbar. VisualRecorder/VideoLibraryPanel = Aufnahme des Bio-Visuals (getrennt von Timeline).
- ABSENT: VideoLanePlayer (Typ existiert nicht), PHPicker/Library-Import, Editor-Tür (editor(forKind:.video)=EmptyView),
  Trim-UI, per-Lane-Video-FX (ChromaKey.metal unverdrahtet).
- **SLICE (a):** PHPicker-Import → Dauer messen → VideoClipFactory → setClip+addRegion → Clip auf Video-Lane
  + tap/long-press AVPlayer-Preview (VideoLibraryPanel-Muster). Kein Transport-Sync. Dann (b) VideoLanePlayer
  (AVQueuePlayer an Audio-Clock, VideoRegionSync/ResyncPolicy nutzen), (c) Trim, (d) FX.

---

## GESETZE (gelten für alle Slices)
- Sheet-Kette NICHT wachsen (Slot-Reuse / bestehende Türen). Kein 10-Hz-Read in Root/Ancestor.
- DSP/-Dateien ohne Core/Sequencer-Typen (AUv3 kompiliert DSP/ isoliert) — ParameterApplyRouter lebt in Core/.
- Audio-Thread lock/alloc-frei; Setter schreiben atomare Float-Mirror (nonisolated(unsafe)) die der Render lockfrei liest.
- SeededRNG/UUID-fold, decodeIfPresent für neue persistierte Felder. Flash ≤3 Hz. EchoelValueField für Params.
- Rausch-Triad READ-ONLY. Conventional Commits + Claude-Trailer. Deploy: .deploy/release bump+push. Gates grün.
