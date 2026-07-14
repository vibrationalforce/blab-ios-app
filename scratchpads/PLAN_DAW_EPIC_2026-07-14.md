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
3. **Audio-Import in eine Spur** — AudioClipFactory-Naht existiert+getestet; nur Importer→Kopie→
   addRegion fehlt. Danach: transport-synced AudioLanePlayer (Audio-Regions am startTick planen).
4. **Video-Spuren** — größter Brocken. Scaffolding (VideoRegionSync/Trim/ClipFactory/ExportPlan)
   pur+getestet, aber KEIN VideoLanePlayer, kein PHPicker-Import, kein Editor-Tür. Eigene Etappen:
   (a) PHPicker-Import→.video-Region + AVPlayer-Preview, (b) VideoLanePlayer transport-synced,
   (c) Trim-UI, (d) per-Spur-Video-FX (ChromaKey.metal verdrahten).

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
