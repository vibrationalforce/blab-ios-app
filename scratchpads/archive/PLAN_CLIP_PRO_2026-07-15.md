# PLAN: Clip-Professionalität + Third-Party-AUv3 (Founder-Mandat 2026-07-15, ultracode)

Founder: "Midi Clip und Audio Clip verhalten sich nicht wie von einer professionellen
Software erwartet wird. Problemlösung ultracode! Zusätzlich auv3 Plugins von third
Party wie Eventide und anderen Herstellern ermöglichen."

Quelle: Ultracode-Audit-Workflow wf_9c6f33b7-6ff (2026-07-15, 14 Agenten) — ALLE
11 CRITICAL/HIGH-Findings adversarial verifiziert REAL. Volle Evidenz (file:line):
`/tmp/.../tasks/wtdm5l634.output` (Sandbox) — Kernzitate unten pro Zyklus.

## Was ehrlich schon trägt (nicht kaputt-reparieren)
- Region-DATEN-Schicht + Gesten: split/merge/trim/front-trim/move/duplicate/combine/
  undo — pur, tick-präzise, getestet (Timeline.swift + TimelineStore).
- Region-Grenz-Erkennung (TimelineRegionPlayer load/clear an Kanten), Lane mute/solo/
  level, per-Lane patch/transpose/detune.
- Ein-Takt-MIDI-Clip auf Taktgrenze spielt korrekt; Audio-Daten tragen
  contentOffsetSeconds korrekt (nur die WIEDERGABE konsumiert sie nicht).
- AUv3-DISCOVERY ist solide (Instrumente + Effekte inkl. Eventide erscheinen;
  Cold-Registry-Retry). Es fehlt das ROUTING, nicht das Finden.

## Verifizierte Defekte → Heilungs-Zyklen (Ralph: einer pro Zyklus)

### Block M — MIDI-Clips klingen wie ihre Blöcke aussehen
- **M1a (pure core):** `RegionNoteWindow` — Noten eines Clips gefenstert auf
  [offsetTicks, offsetTicks+lengthTicks), rebasiert auf Region-relativ; Takt-Slice
  (barWithinRegion) für die bestehende `loadArrangement`-Mechanik. NUR neue Datei +
  Tests (Foundation-only).
- **M1b:** TimelineRegionPlayer lädt region-relativ + taktweise in PianoRollModel
  (`loadArrangement` statt flachem `load`); MIDI-Offset: contentOffsetSeconds→Ticks
  (bpm) beim Laden konsumieren. Fixt CRITICAL#1 (nur Takt 1) + HIGH#3 (Split/Trim
  fenstert nicht) für die Primär-Lane. Seamless-Split: allNotesOff überspringen, wenn
  gleiche clipID + medien-kontinuierlicher Offset (abuts()-Test existiert).
- **M1c:** LaneNotePump identisch (Sekundär-Lanes; Modulo-16-Faltung ersetzen).
- **M2:** Region-relative Phase — Clip abseits der Taktlinie spielt Noten an der
  CLIP-Position (CRITICAL#2). Mechanik aus M1 (Phase = tick - startTick), Trigger
  nicht mehr `startStep == absoluter Step`.
- **M3:** Clip-scoped Edit-Tür: `.region`-Modal lädt clip.melody in eine Editing-
  Session, Rückschreiben via ClipStore.updateMelody beim Dismiss (HIGH#4).
- **M4:** Combine-Datenverlust stoppen (HIGH#5): nur gleiche clipID kombinieren ODER
  Noten-Inhalte zeitversetzt mergen (pure, getestet). Bis dahin: Guard.
- **M5 (MEDIUM):** Mini-Noten-Preview im Clip-Block (Canvas, wie Audio-Waveform).
- **M6 (LOW):** Duplicate = tiefe Clip-Kopie oder UI-Hinweis auf geteilte Referenz.

### Block A — Audio-Spuren KLINGEN im Arrangement
- **A1:** AudioLanePlayer VERDRAHTEN (CRITICAL): AVAudioEngine-Sink (scheduleSegment
  ab contentOffsetSeconds, Länge = Region), Instanz in Transport-Play-Pfad neben
  TimelineRegionPlayer; stop/loop-Pfade. (Exakt das Video-Monitor-Muster v246: der
  getestete Koordinator bekommt seinen Device-Sink.)
- **A2:** Audition mit Offset (HIGH): auditionURL + region.contentOffsetSeconds +
  Länge an den Preview-Player.
- **A3:** Audio-Edit-Tür ehrlich (HIGH): `.region`-Modal öffnet den Editor MIT dem
  Region-Audio (mediaRef + offset + Länge) statt leerem Import.
- **A4 (MEDIUM):** Waveform im Block auf Region gefenstert (offset/length).
- **A5 (MEDIUM):** Editor-Gain/Fades beim "Add to timeline" übernehmen ODER ehrlich
  im Editor ausblenden; Klick-freie Split-Kanten (Mikro-Fade im Sink).
- **A6 (MEDIUM):** Tempo-Ehrlichkeit (Join-Refuse bei altem Tempo; Sekunden-Medien
  vs. Tick-Region) — Council nötig (Design-Entscheid: Region folgt Tempo oder Medium).

### Block U — Third-Party-AUv3 Ende-zu-Ende (Eventide)
- **U1:** Per-Track-AU-INSTRUMENT wirklich routen (CRITICAL): lane.instrument →
  AUv3Host-Instanz pro Lane → Engine-Graph; MIDI der Lane an die AU statt Built-in.
- **U2:** Per-Track-EFFEKT-Inserts (HIGH): Insert-Kette pro Lane (auch auf Built-in-
  Voices + Audio-Lanes); "Assign" auch für Effekte ohne Instrument (MEDIUM#5 mit).
- **U3:** musicalContextBlock + transportStateBlock setzen (HIGH): Tempo/Beat/
  Transport aus Transport/PatternEngine — Eventide-Delays syncen.
- **U4 (MEDIUM):** AU-Restore beim Relaunch (fullState pro Lane-Slot, nicht pro
  Plugin-Identität — MEDIUM#6 mit).
- **U5 (LOW):** Sample-genaues MIDI-Scheduling an gehostete AUs.

## Reihenfolge (Founder-Schmerz zuerst, Mechanik-Abhängigkeiten beachtet)
M1a → M1b → A1 → M1c → M2 → U1 → U2 → U3 → M3 → A2 → A3 → M4 → U4 → M5/A4/A5 → Rest.
Jeder Zyklus: Tests zuerst wo pur, Pflicht-Reviewer, Gates grün, Deploy-Bump,
deutsches Status-Delta.

## Rote Linien
- Audio-Thread-Regeln (kein malloc/lock im Render; Sink-Scheduling auf @MainActor,
  AVAudioEngine übernimmt den RT-Teil).
- Freeze-Regel: neue Player lesen Transport in eigenen Leaves/Koordinatoren.
- Store-first bleibt: jede neue Operation = Store/Core-Methode mit purer Mathematik
  (EchoelAI-andockbar).
