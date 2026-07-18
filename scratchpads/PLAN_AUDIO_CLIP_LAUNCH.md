# PLAN — Audio-Lane Clip-Launch (A7 next slice)

> Founder-Quelle: A7 „Play Button auf den Clips + Performance Mode" (07-17).
> MIDI-Launch ist KOMPLETT (ClipLaunchEngine + TimelineRegionPlayer + ClipLaunchGlyph,
> alle Zustände idle/queued/playing/queuedStop, flash-/freeze-sicher). Diese Slice
> erweitert den Launch auf AUDIO-Spuren. Protokoll: „ERST PLAN + Council, dann Zyklen"
> — weil es die Audio-Engine berührt, die eine Stille-Regressions-Historie hat (#22).

## Ist-Zustand (verifiziert, gelesen 2026-07-18)

- `ClipLaunchEngine` (pure, getestet): per-Spur State-Machine, `tick(now:)` liefert
  `LaunchTransition`s. **Spur-agnostisch** — kennt nur `laneID`/`regionID`, kein MIDI/Audio.
- `TimelineRegionPlayer.launchRegion(_:quantize:)`: **guard `lane.kind == .midi, !lane.isBio`**
  — Audio-Spuren werden heute still abgewiesen. `applyLaunchTransitions` dispatcht Roll
  vs. Sekundär-Rack-Slot; **kein Audio-Pfad**.
- `AudioLanePlayer` (@MainActor): `prime(in:atTick:bpm:)` + `apply(in:fromTick:toTick:bpm:)`
  entscheiden AUTONOM aus dem Dokument, welche Region je Audio-Spur spielt; `start(...)` privat.
  Spielt **One-Shot-Segmente** je Arrangement-Region (kein Loop).
- `ClipLaunchGlyph`: nur auf MIDI-Regions (`launchGlyphOverlay(isMidi:)` → `if …, isMidi, !laneIsBio`).
- **Pure Loop-Restart-Mathematik EXISTIERT** in `LaunchTiming` (LaneLaunchLatch.swift, getestet):
  `loopWrapped(from:to:sinceTick:loopLength:)` (Boundary-Crossing) + `loopContentTick(now:…)`.

## Die EINE harte Sache

MIDI-Launch re-windowt gratis (der Pump/Roll lädt die Region neu je Tick-Fenster). **Audio
kann das nicht**: ein Datei-Segment ist One-Shot. Ein *gelaunchtes* Audio-Clip muss **an
jeder Loop-Grenze neu getriggert** werden (Segment von vorn). Genau dafür ist
`LaunchTiming.loopWrapped` da — die Mathematik ist fertig, es fehlt nur die Verdrahtung.

## Design (kleinste sichere Verdrahtung, golden-gate-treu)

**S1 — Override-Karte in `AudioLanePlayer` (additiv, nil = heutiges Verhalten):**
- Neuer Zustand `private var overrides: [UUID: AudioLaunchOverride]` mit
  `struct AudioLaunchOverride { let region: TimelineRegion; let startedAtTick: Int }`.
- Neue Türen: `setOverride(_:for:atTick:bpm:)` (startet das Segment sofort, merkt Anker),
  `clearOverride(for:atTick:bpm:)` (zurück zum Arrangement über den bestehenden `apply`-Pfad),
  `hasOverride(_:) -> Bool`.
- In `apply(...)`: für Spuren MIT Override die Arrangement-Entscheidung ÜBERSPRINGEN und
  stattdessen bei `LaunchTiming.loopWrapped(from:to:sinceTick:startedAtTick, loopLength:region.lengthTicks)`
  == true das Segment neu starten (Content-Offset = `region.contentOffsetSeconds`, immer von vorn).
- **Golden Gate:** `overrides.isEmpty` ⇒ jeder Pfad byte-identisch zu heute.

**S2 — `TimelineRegionPlayer` Audio-Dispatch:**
- `launchRegion`: guard um `lane.kind == .audio` erweitern (MIDI-Pfad unverändert).
- `applyLaunchTransitions`: neuer Zweig „Spur ist Audio" → `audioLanes?.setOverride/clearOverride`
  statt Roll/Slot-Laden. `.switched` = setOverride(neue Region). `.stopped` = clearOverride.
- `transportStep`: Audio-Spuren mit Override NICHT über den normalen `audioLanes?.apply`
  doppelt fahren — der Override-Zweig in `apply` (S1) erledigt Loop-Restart; der normale
  Arrangement-Teil überspringt overridden lanes.
- Stop/relocate/wrap: `audioLanes?.clearAllLaunchOverrides()` in denselben Reset-Pfaden wie
  `launch.removeAll()` (Launch überlebt keinen Transport-Reset — P0-Gesetz).
  **HARTE S2-PFLICHT (audio-thread-review 41fac9c):** `clearAllLaunchOverrides()` leert NUR
  die Karte, stoppt KEIN Audio. In JEDEM stop/handleTransportStopped/relocate-Pfad MUSS das
  Paar zusammen gerufen werden: `stopAll()` (sonst tönt die overridete Spur weiter) UND
  `clearAllLaunchOverrides()` (sonst re-triggert das nächste `apply()` den Loop vom Top).
  S2-Test-Pflicht: ein Transport-Reset stoppt Audio UND `hasLaunchOverrides == false`.
- **HARTE S2-PFLICHT #2 (code-review 41fac9c, #22-Historie):** `setLaunchOverride` ruft direkt
  `start`→`sink.play`. Referenziert ein gelaunchtes Clip eine Datei, die auf DIESER Spur noch
  NICHT geprimed ist (z. B. ein Clip-Slot-Clip ohne Arrangement-Region), attacht der Geräte-Sink
  seinen Node mitten im Song = ganzer-Mix-Dropout (HIGH-2). S2 MUSS die Datei des gelaunchten
  Clips vor `setLaunchOverride` warmen (`preload`) ODER `setLaunchOverride` warmt selbst zuerst.

## S1 STATUS (2026-07-18, 41fac9c — gebaut, Gates laufen)
AudioLanePlayer Override-Türen + 7 SpySink-Tests. audio-thread-reviewer: CLEAN (golden gate
verifiziert, Anchoring korrekt, keine Audio-Thread-Regel berührt). Zwei Geräte-Verify-Punkte
(inhärent an Block-Re-Trigger, nicht hier beweisbar): (1) Loop-Restart ist auf das Transport-
Fenster gerundet, nicht sample-genau — bis zu 1 Fenster Phasenschlupf pro Wrap; (2) Klick/Gap
an der Naht hängt an der echten Sink-Implementierung (`AudioClipPlayer`, S2+). Beide erst mit
dem Geräte-Sink verifizierbar.

**S3 — Glyph auf Audio-Regions:** `launchGlyphOverlay(isMidi:)` → `isLaunchable` (midi ODER
audio, `!laneIsBio`). Der Glyph ist bereits spur-agnostisch (liest nur `launchState(laneID:)`).

## Reviewer-Pflicht
- `audio-thread-reviewer`: AudioLanePlayer ist @MainActor-Kontrollebene (kein Render-Thread),
  aber das Segment-Restart-Timing + Gapless prüfen.
- `concurrency-reviewer`: neue Override-Map, Sendable/Isolation.
- `ui-state-reviewer`: Glyph-Erweiterung, Freeze-Gesetz (Glyph liest nur `launchGeneration`).

## Test-Strategie (test-first)
- `AudioLanePlayer`-Tür-Tests via `AudioRegionSink`-Mock (existiert): setOverride startet EIN
  Segment; Loop-Wrap triggert Restart; clearOverride kehrt zum Arrangement zurück; leere
  Override-Map = identische `apply`-Aufrufe wie heute (golden gate).
- Wiederverwendung der `LaunchTiming`-Tests (Boundary-Crossing schon gepinnt).

## Risiko / Rollback
- Risiko: Audio-Doppelstart/Stille bei Override↔Arrangement-Übergang; Loop-Klick an der Grenze.
- Rollback: Override-Map-Feld + die drei Türen entfernen, `launchRegion`-guard zurück auf midi-only.
- Verify-Weg (Board): Founder tippt im Performance-Mode einen Audio-Clip-Play → Clip loopt
  hörbar an der Bar-Grenze, zweiter Tipp → zurück zum Arrangement.

## Reihenfolge der Bau-Zyklen
1. S1 AudioLanePlayer Override-Türen + Tests (kein TimelineRegionPlayer-Touch) — isoliert grün.
2. S2 TimelineRegionPlayer-Dispatch + Reset-Pfade — audio-thread-reviewer.
3. S3 Glyph-Erweiterung — ui-state-reviewer.
Jeder Zyklus einzeln deploy-fähig; S1 allein ist unsichtbar (kein Caller) = sicherster Start.
