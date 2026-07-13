# MASTER-RESTRUKTURIERUNG — Echoel als tracks-zentrierte Produktions-DAW (2026-07-13)

Founder-Auftrag (verbatim-Kern): "Wir brauchen eine Restrukturierung des gesamten
Projekts… Ableton als Vorbild-DAW… Audiomaterial manipulieren mit Warp… Master-
Automationen + Editing-Modi… Clip-View sparen wir uns (Live aus der Hauptansicht)…
die ganze Video-Editing-Ebene kommt mit in die Spuren… Arbeite mit der richtigen
architektonischen Planung."

**Kernbotschaft dieses Plans:** Das Zielbild ist NICHT neu — es steht schon in ~15
deiner Pläne (grand-council-bestätigt 2026-07-10C). Diese Datei ERFINDET nichts, sie
**sequenziert** das Geplante gegen den ECHTEN Code-Stand (zwei Deep-Audits 2026-07-13)
zu sichtbaren Scheiben. Kein Big-Bang-Rewrite; ein Ralph-Zyklus pro Scheibe.

Quellen: `PLAN_ONE_VIEW_2026-07-11.md` (Live-Perform-Spec), `PLAN_ONE_VIEW_CONVERGENCE_2026-07-10.md`
(K1–K5), `PLAN_ARRANGEMENT_VIDEO_ONE_VIEW.md` (Video-in-Spuren), `PLAN_DMMW_SHELL_V3_2026-07-12.md`,
`PLAN_AUTOMATION_IN_TRACK_2026-07-13.md`, `PLAN_MULTIROLL_2026-07-13.md`, `PLAN_TRANSPORT_CLOCK.md`,
`docs/dev/DMMW_ARCHITECTURE.md`, `memory/vision.md`.

---

## 1. ZIELBILD (eine Ansicht, alles Spuren)

Eine Timeline-Ansicht = die App. Jede Spur ist ein universeller Kanalzug für IHREN
Typ — **MIDI · Audio · Video · Automation · (Bio als Modulations-Overlay)** — mit
Level/Mute/Solo + typ-spezifischer Semantik. Der Körper moduliert über den EngineBus
oben drauf (bio = beschränkter Offset auf den Automations-Basiswert, NIE last-writer).
Kein separater Clip-View: Clips sind die Region-Payload; Live-Performance läuft in der
einen Timeline (Tap = Launch/Loop, Long-Press = Editor). Ableton-Vorbild für Ordnung +
Warp + Automation; Video = Capture→Trim→Bio-Grade→Export IN den Spuren.

**Grenze, die ich bestätigt brauche (Punkt 6):** Video-in-Spuren = *kein* voller NLE.
Deine bisherigen Pläne (07-10C, council'd) scopen es auf Aufnehmen-gegen-Transport ·
Region-Trimmen · Bio-Colour-Grade (Metal) · Export; Feinschnitt delegierst du an
InShot/Resolve, die Echoels Export konsumieren. Der Differenzierer ist bio-reaktives
Video (Puls-synchroner Schnitt, generative Metal-Visuals als Footage), nicht NLE-Kopie.

---

## 2. ECHTER CODE-STAND (Audit 2026-07-13) — was trägt, was fehlt

**Trägt schon (Fundament, load-bearing):** 480-PPQ Song-Tick-Modell (`Timeline.swift`,
Lanes/Regions, `ClipKind{midi,audio,video,visual}`) · reiner Snap/Scheduling-Fan-out
(`TimelineScheduling.laneEvents`) · additive Voice-Attach-Disziplin (`AudioEngine.attach*`) ·
`AudioClipPlayer` (Trim/Loop/Fade, getestet) · `TempoMatch`-Mathematik (Warp-Rate, getestet) ·
Automations-Spine (`AutomationLane`/`AutomationPlayer`/`EchoelParameterRegistry`/
`ParameterApplyRouter` + AUv3-KVO-Bridge) · Video-Export-Primitive (`VisualRecorder`/
`VideoRecorder`/`VideoMuxer`) · Timeline = Zuhause (v189).

**Die 6 echten Lücken (Audit-Ranking):**
1. **KEIN Per-Spur-Playback / kein Per-Spur-Signalweg** — alle MIDI-Spuren fallen auf
   `rollLaneID` (Spur 1) zusammen; Routing per `NoteRole`, nicht per Spur. Multi-Roll
   ist voll scaffolded aber TOT (`LaneVoiceSlotMap`, `midiLaneIDs`, `laneEvents`,
   `TimelineLane.instrument/effects` = nur persistiert). **DER Keystone.**
2. **Video-in-Spuren praktisch nicht vorhanden** — `.video`/`.visual` = nur Modell,
   `editor` gibt `EmptyView`; keine Kamera→Datei, kein Import (kein PHPicker), kein Trim,
   kein Video am Playhead. Nur Visual→MP4-Recorder + toter `ChromaKey.metal`.
3. **Timeline-Audio-Spuren spielen nicht** — `AudioClipPlayer` funktioniert isoliert,
   aber `TimelineRegionPlayer` fährt nur die MIDI-Roll-Spur; `audioLaneIDs` ungelesen.
4. **Kein Warp** — `TempoMatch` fertig, aber `AVAudioUnitTimePitch` NIRGENDS instanziiert;
   `AudioClipRegion` hat kein rate-Feld.
5. **Per-Spur-State persistiert, aber nicht geroutet** — level/pan/mute/solo/instrument/
   effects existieren, nur der eine Roll-Slot konsumiert gain/pan.
6. **Automation erreicht intern fast nichts** — nur Master-Level, Tempo, ein geteilter
   Cutoff; die 15 DDSP-Registry-Params registriert-aber-ungebunden; kein Per-Spur/Master-FX.

---

## 3. DER ABHÄNGIGKEITS-RÜCKGRAT (warum die Reihenfolge zwingend ist)

```
        ┌─ Per-Spur-Sound (Instrument je Spur)
        ├─ Audio-Spuren spielen + Warp
KEYSTONE┤
Multi-  ├─ Per-Spur Insert-FX + Per-Spur-Automation
Roll    ├─ Live-aus-Hauptansicht (Clip-Launch, lane-scoped)
        └─ (danach) Video-Spuren am selben Playhead
```
Alles hängt am Keystone. Deshalb ist Multi-Roll NICHT "Breite" — es ist genau der
Kern, der "alles über die Spuren" erst wahr macht. Es war pausiert; es ist jetzt #1.

---

## 4. SEQUENZ SICHTBARER SCHEIBEN (Ralph, je 1 Zyklus; ⚙️=geräteverifiziert nötig)

**P0 — jetzt, sicher, ohne Gerät (parallel, reine Cores + eine hörbare Scheibe):**
- P0a Meter/„die Eins": **A (Anker ohne Beat) + 8-Takt-Default, flexibel länger** —
  hörbare Kern-Verbesserung, geräte-hörbar (eigener Build). (`PLAN_CLEAR_METER`.)
- P0b Reiner Per-Spur-Routing-Vertrag: `LaneVoicePool`-Kontrakt + `laneEvents`-Fan-out
  als getestete Logik festzurren (kein Engine-Wiring). Fundament für P1.

**P1 — KEYSTONE: Per-Spur-Playback (Multi-Roll K2a) ⚙️** — N MIDI-Spuren → je eigener
Roll/Voice via `LaneVoicePool`+`LaneVoiceSlotMap`+`laneEvents`. CPU/Memory NUR am Gerät
messbar (Z3 wurde genau darum zurückgerollt). Sichtbar: zwei MIDI-Spuren klingen gleichzeitig
verschieden. (`PLAN_MULTIROLL`.)

**P2 — Audio-Spuren spielen + Warp ⚙️** — `TimelineRegionPlayer` fährt `audioLaneIDs` →
Per-Spur-`AudioClipPlayer`; `AVAudioUnitTimePitch`-Warp via `TempoMatch` (rate-Feld auf
`AudioClipRegion`, offline-render = 0 Audio-Thread-Kosten). Sichtbar: Audio-Clip reinziehen,
auf Projekt-Tempo gewarpt, spielt in der Spur. (`PLAN_ARRANGEMENT_VIDEO_ONE_VIEW` Warp.)

**P3 — Per-Spur Insert-FX + Automation (C5 song-absolut = Founder-Top) ⚙️** — DDSP-Registry
in den Router binden; `TimelineLane.effects` real routen; song-absolute Automation erreicht
die gewählte Spur; Master-FX-Automation. Editing-Modi: draw · record/latch · **bio-record**.
(`PLAN_AUTOMATION_IN_TRACK`.)

**P4 — Live aus der Hauptansicht ⚙️** — Clip-Launch lane-scoped (Tap=Launch/Loop,
Long-Press=Editor), `LaunchQuantizer` auf Lane-Ziele. Braucht P1. (`PLAN_ONE_VIEW` L1.)

**P5 — VIDEO-IN-SPUREN ⚙️ (eigener Sub-Plan + Council)** — Video-Lane spielt (`AVPlayer`
an Transport-Tick) → Kamera/Visual-Capture→Datei → Import (`PHPicker`, volle Mediathek) →
Trim/Scrubber/Thumbnails → Bio-Grade (`ChromaKey`/Metal-Pass) → Export. Groß, geräte-gepaced.
(`PLAN_ARRANGEMENT_VIDEO_ONE_VIEW`, `PLAN_DMMW_SHELL_V3` E3.)

**P6 — v1.1 Echoel Live (SharePlay) → v1.2 Broadcast (RTMP/HaishinKit).**

---

## 5. GESETZE / LEITPLANKEN (gelten für jede Scheibe)
- Timeline-als-Zuhause ist ENTSCHIEDEN (5× oszilliert lt. `memory/vision.md` — NICHT
  wieder aufmachen).
- Sheet-Kette nicht wachsen (SIGSEGV) · kein 10-Hz-Read in Root/Ancestor · Audio-Thread
  lock/alloc-frei · Flash ≤3 Hz · EchoelValueField · Rausch-Triad READ-ONLY · Conventional
  Commits + Trailer.
- **Geräte-Bottleneck ist der echte Taktgeber:** kein lokaler Swift-Build, ~1 TestFlight/Tag;
  jede Audio-Graph/Video-Scheibe (P1–P5) ist erst am Gerät bewiesen. Reine Cores (P0b) +
  hörbare Sound-Scheibe (P0a) laufen ohne Gerät voraus.

## 6. COUNCIL-Risiko-Check (kurz)
- Shipper: P1 nicht blind vergrößern — erst am Gerät CPU/Memory messen (2 Spuren, dann N).
- DSP-Purist: Warp offline rendern (kein Time-Stretch im Render-Block).
- Skeptiker: Video (P5) ist der größte Brocken + am stärksten geräte-gepaced — nicht vorziehen.
- User-Advocate: jede Scheibe muss am Gerät ERLEBBAR sein (kein unsichtbares Fundament ohne Nutzen).
- Vision-Keeper: Video = Capture/Trim/Grade/Export, kein NLE (Grenze in §1 bestätigen lassen).
- Architect: P0b-Vertrag zuerst → P1 sauber; nichts vor dem Keystone bauen, was ihn braucht.

## 7. WAS ICH VOM FOUNDER BRAUCHE (minimal)
1. Grünes Licht für die Reihenfolge P0→P6 (oder Korrektur der Priorität).
2. Bestätigung der Video-Grenze (§1): Capture/Trim/Bio-Grade/Export in den Spuren —
   Feinschnitt extern? Oder willst du mehr Schnitt-Tiefe drin?
3. P0a bestätigt: A (Anker ohne Beat) + 8-Takt-Default. (Kann ich sofort bauen.)

---

## STATUS 2026-07-13 (diese Session) — FUNDAMENT-SCHICHT KOMPLETT, alle CI-grün

"Alles parallel": 4 Tiefen-Agenten bauten die geräte-UNABHÄNGIGEN Kerne JEDER Phase
gleichzeitig; ich integriere in prüfbaren Batches (kein lokaler Compiler → CI ist die
einzige Verifikation). GELANDET + grün (Xcode Compile + CI/CD Pipeline):
- **P0a** Meter/„die Eins" (8-Takt-Default + Downbeat-Anker) — v10.79.190 auf TestFlight.
- **P1** `LaneVoicePool` + `LaneVoiceScheduling.plan` — Per-Spur-Voice-Zuweisung (Keystone-Kern).
- **P2** `AudioClipRegion` warp (warpEnabled/nativeBPM + effectiveStretchRate) — Warp-Kern.
- **P4** `LaneLaunchLatch`/`LaunchTiming`/`LaunchGestureResolver` — Live-Clip-Launch-Kern (neue
  Datei; alte tote `LaunchQuantizer`-Klasse bleibt bis ClipView-Reconciliation).
- **P5** `VideoRegionSync`/`VideoRegionTrim`/`VideoClipFactory`/`BioColorGradeParams` +
  `ClipKind.timelineEngineKinds`/`isMediaCarrier` + `videoLaneIDs`/`videoLaneEvents` — Video-Kern.
Alle rein, getestet, `decodeIfPresent`, Swift-6, audio-thread-frei.

**NÄCHSTE SCHICHT = geräte-verifiziertes Wiring (gestaffelt, je eigener Mess-Build,
ab hier der echte Taktgeber — nicht Planung):**
1. P1 `LaneVoiceRack` (2 Spuren → CPU/Memory messen → N) — der sichtbare Keystone.
2. P2 `AVAudioUnitTimePitch` offline-render in `AudioClipPlayer`.
3. P5 `VideoLanePlayer` (AVPlayer an Transport) + Import(PHPicker)/Trim/Grade/Export.
4. P4 MIDI-Launch-Driver (braucht P1) → dann Audio-Launch (braucht Timeline-Audio).
5. P3 Automation: DDSP-Registry in den Router binden (song-absolut, Founder-Top C5).
