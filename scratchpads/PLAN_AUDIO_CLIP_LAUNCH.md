> ⛔ **SUPERSEDED — do not execute (banner 2026-08-28).** This plan commands scope the Editor ≠ Workstation boundary (docs/dev/PRODUCT_DEFINITION.md, 2026-07-25) has CUT or that #121/#166/#167 dismantled. History only; ROADMAP.md + vision.md win over any PLAN file.

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

## S2 STATUS (2026-07-18 — gebaut, Reviewer laufen)
TimelineRegionPlayer Audio-Dispatch: `launchRegion` erlaubt jetzt `.audio`-Lanes; `applyLaunchTransitions`
routet Audio-Lane-Transitions an `audioLanes.setLaunchOverride/clearLaunchOverride` (Anker = `t.atTick`
= Bar-Grenze). Alle 4 Reset-Pfade (play/relocate/stop/handleTransportStopped) paaren jetzt
`clearAllLaunchOverrides()` mit `launch.removeAll()` (+ stopAll/prime) — Pflicht #1 erfüllt. Pflicht #2
(preload): gelauncht werden nur TIMELINE-Regionen, die bei play()/prime bereits ge-preloadet sind →
kein Mid-Song-Attach; Off-Timeline-Clips sind nicht launchbar (dokumentiert). 3 Integrationstests
(SpySink-Harness): Audio-Launch startet Override an der Grenze + Stop löst zurück; Transport-Stop löscht
Override; MIDI-Launch bleibt unberührt. **INERT bis S3** (kein Audio-Glyph → User kann Audio noch nicht
launchen; golden-gate-geschützt wie S1).
**HARTE S3-PFLICHT (in S2 bewusst NICHT gebaut, weil bis S3 unerreichbar):** wird eine GELAUNCHTE
Audio-Region mitten im Spiel STRUKTURELL GELÖSCHT, prunt `launch.prune` (refreshStructure) den Engine-
State OHNE Transition — die AudioLanePlayer-`overrides`-Karte (nur bei entfernter LANE, nicht Region,
selbst-bereinigt) bliebe verwaist und würde eine Phantom-Region loopen. S3 MUSS in refreshStructure die
Audio-Overrides gegen `launch.isOverriding` synchronisieren (clear wenn Engine nicht mehr overriding).
**+ WRAP-PFAD (audio-thread-review S2, bf38ff8):** derselbe Desync gilt für den Song-Loop-Wrap in
`transportStep` — die MIDI-Launch-Zeitbasis wird per `launch.shift(by: -loopTicks)` gefaltet, aber die
Audio-Seite ruft nur `prime` (ignoriert die overrides-Karte) und schiftet/löscht den Override NICHT.
Folge nach Wrap: (a) ein aktiver Audio-Override wird still vom Arrangement überschrieben während der
MIDI-Launch überlebt (Audio/MIDI-Inkonsistenz), (b) `startedAtTick` bleibt un-geshiftet → `loopWrapped`
bekommt einen veralteten Anker (elapsed < 0), Override strandet. S3-Pflicht: eine Audio-seitige `shift`
(analog `launch.shift`) ODER clear-and-reprime im Wrap-Zweig — NICHT nur in refreshStructure.

## S3a STATUS (2026-07-18 — gebaut + Wrap-Re-Trigger-Defekt gefixt, Final-Review läuft)
Die dokumentierten S3-Pflichten (refreshStructure- + Wrap-Pfad-Desync) geschlossen, INERT bis S3b:
- `AudioLanePlayer.prime` überspringt jetzt overridete Lanes (kein Arrangement-Clobber beim Re-Prime;
  play/relocate leeren die Karte vorher → dort no-op).
- `shiftLaunchOverrides(by:)` (Audio-Twin zu `ClipLaunchEngine.shift`) → im Wrap-Zweig gepaart mit
  `launch.shift`, faltet den Loop-Anker mit; `pruneLaunchOverrides(validLaneIDs:validRegionIDs:)` →
  in refreshStructure gepaart mit `launch.prune`, droppt+stoppt gelöschte Launch-Region/Lane.
- **`applyWrappedOverrides(in:fromTick:toTick:bpm:)` (91deeff, audio-thread-review-Defekt geschlossen):**
  der Wrap-Step läuft über `prime` (überspringt Overrides), also verlor ein bar-alignter Launch-Loop
  seinen Re-Trigger AM Wrap → 1 stiller Takt pro Song-Loop, Audio nicht im Lockstep mit MIDI. Fix
  fährt die Overrides über den Wrap im GEFALTETEN Frame `(lastTick − loopTicks, newTick)` — `loopWrapped`
  entscheidet selbst: Boundary-koinzident → Re-Fire vom Loop-Top; Segment das den Wrap überspannt →
  bleibt spielen (nur reconcile). Audio-Twin zu `ClipLaunchEngine.tick` nach `.shift`.
- 6 Unit-Tests (prime-skip, shift-fold, prune×3 + **`testAudioLaunch_reTriggersOnSongWrap_noSilentBar`**
  auf dem ECHTEN `transportStep`-Wrap-Pfad — schließt die False-Confidence-Lücke des Primitiv-Only-
  Shift-Tests). Golden Gate: alle no-op wenn `overrides.isEmpty`.
**Nächste = S3b:** `ClipLaunchGlyph` auf Audio-Regionen sichtbar machen (`launchGlyphOverlay` midi→
midi||audio; der Glyph ist bereits spur-agnostisch, liest nur `launchState`) → macht Audio-Launch
erreichbar+erlebbar → DEPLOY-reif.

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
