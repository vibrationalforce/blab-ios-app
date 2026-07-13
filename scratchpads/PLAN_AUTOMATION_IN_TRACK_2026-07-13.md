# PLAN — Automation in der Spur (Founder-Item 1, 2026-07-13)

Founder-Verdikt v183: "AUTOMATION IN DER SPUR: im Clip UND clip-übergreifend auf dem
Raster, mit ALLEN Parametern (EchoelParameterRegistry als Ziel-Katalog). Erst PLAN +
Council, dann Zyklen."

Erstellt aus einem Planungs-Workflow (Map + Synthese) + Council. Ground-truth gegen den
echten Code verifiziert (4 von 5 Map-Agenten fielen aus [Explore+Schema], Synthese hat
die Dateien selbst gelesen; ich habe Registry/AutomationPlayer/AutomationLane direkt
nachgeprüft).

## Bestand (WIEDERVERWENDEN, nicht neu bauen)
- **`AutomationLane`** (Sequencer/) — pur, parameter-agnostisch, `parameter: String` = bereits
  ein keyPath-Slot, Keyframes in 480-PPQ-Ticks, normalized 0…1, curve + curvature,
  decodeIfPresent-migriert. **Verbatim für BEIDE Scopes.**
- **`AutomationCanvasMath`** (Sequencer/) — pure Zeichen-/Hit-/Snap-Geometrie, aktuell 1-Bar.
- **`AutomationPlayer`** (Core/) — @MainActor @Observable, `applyStep(step)` pro Transport-Step
  (≤16/Bar), AppGroupStore-persistiert, 3-Fall-Enum `AutomationTarget`
  (masterLevel→`audioEngine.masterVolume`, tempo→`pattern.setTempo`, filterCutoff→
  `voice.setCutoffScale`). Diese 3 sind DISJUNKT vom Registry-DDSP-Katalog.
- **`EchoelParameterRegistry` + `DDSPParameterCatalog`** (Core/) — 15 `ddsp.*`-Deskriptoren,
  keyPath = stabile ID, `denormalized()/normalized()`. **NICHT verdrahtet** (nur Inventar +
  validierter Schreib-Pfad-Scaffold; `apply:`-Closure ist ein Loch, das der Caller füllt).
- **`AutomationView`** + der bestehende `$showAutomation`-Sheet-Slot auf EchoelStudioView.
- **`ParameterToolCore.set()`** validate→clamp→apply-Kontrakt + `ParameterSetResult`.

## Die EINE fehlende Verdrahtung
Ein **keyPath→Live-Setter-Router** (`ParameterApplyRouter`) — der konkrete Körper der
`apply:`-Closure, die `ParameterToolCore.set()` schon immer verlangt. Sobald er existiert,
IST `AutomationLane.parameter` ein Registry-keyPath und alles komponiert.

## Architektur-Entscheide (Council-geprüft)
- **EIN Lane-Typ in ZWEI Heimen:** In-Clip = `Clip.automation: [AutomationLane]` (RELATIVE
  Ticks, wandert mit dem Clip). Clip-übergreifend = `TimelineDocument.automation:
  [AutomationLane]` (song-ABSOLUTE Ticks, ans Raster gepinnt). Beide `decodeIfPresent`→[]
  (Legacy byte-identisch).
- **EIN Schreib-Pfad:** beide Scopes terminieren an `ParameterApplyRouter.apply(keyPath,
  real)`. Kein Fork (Architect: sonst driftet der Code).
- **Audio-Thread:** Eval main-actor pro Step; der Set erreicht die Voices über deren
  bestehende `nonisolated(unsafe)`-Atomic-Float-Spiegel. Router lebt in Core/, NIE in DSP/
  (AUv3 kompiliert DSP/ isoliert), NIE aus einem Render-Block erreichbar.
- **UI:** EINE Zeichen-Canvas, gleiche Gesten (tap-add/drag/bend/double-tap-delete),
  präsentiert über den BESTEHENDEN `$showAutomation`-Sheet — KEIN neues `.sheet`
  (Metadata-Black-Screen-Gesetz). Ziel-Picker = Registry-Deskriptoren, **nur GEBUNDENE
  keyPaths** (kein toter Lane). Scope-Switch (In-Clip ↔ Arrangement) = sichtbarer
  Segmented-Control. EchoelValueField für Werte-Zeilen. Playhead-Overlay = eigenes Leaf.

## Zyklen (Ralph-Wiggum, test-first wo pur)
1. **`ParameterApplyRouter`** (Core/) — keyPath→Setter-Dispatch + Registry-Startup-Population.
   Pur, CI-testbar, kein App/Render-Touch. Rev: DSP Purist + Architect. **← DIESER ZYKLUS.**
2. **AutomationPlayer auf Registry-keyPaths retargeten** (Legacy-Alias masterLevel/tempo/
   filterCutoff → keyPaths, gespeicherte Automation überlebt). Rev: Architect + Skeptic.
3. **Canvas auf beliebige Span generalisieren** (`spanTicks`) + Registry-Deskriptor-Picker im
   bestehenden Sheet. Rev: User-Advocate + swiftui-render-safety. Device-gated.
4. **In-Clip:** `Clip.automation` (relative Ticks). Rev: Architect + Skeptic.
5. **Clip-übergreifend:** `TimelineDocument.automation` + absoluter Song-Tick aus
   `ArrangementPlayer.cursor`. Rev: Architect + DSP Purist + Shipper. Device-gated.
6. **Katalog Richtung ALLE Parameter weiten** (FX + Poly/Drum-Voice-Deskriptoren + Router-
   Einträge; jeder registrierte Deskriptor MUSS dispatchbar sein). Rev: DSP Purist + Vision.

## Offene Founder-Fragen + meine Defaults (autonom weitergebaut, umkehrbar)
1. "clip-übergreifend" = BEIDE (In-Clip-Lanes die mit dem Clip wandern + Arrangement-Lanes
   ans Raster gepinnt)? → **Vom Founder-Wortlaut schon beantwortet: BEIDE** (in-clip zuerst).
2. Präzedenz wenn In-Clip- UND Arrangement-Lane denselben keyPath treffen? → **Default:
   Arrangement gewinnt (last-writer), umkehrbar** (Cycle 5, noch nicht geshippt).
3. Welche Parameter zuerst? → **Default: die 15 DDSP-Params via Registry, aber Picker zeigt
   nur GEBUNDENE** (master/tempo/filter sind heute schon audio-verdrahtet; DDSP-Setter
   werden in Cycle 2/6 gebunden).
4. Clip länger als Automation / Loop → HOLD (heutiges Verhalten) oder LOOP? → **Default:
   HOLD**, Loop später.
5. Bio-Lane (`TimelineLane.isBio`) und Hand-Automation dieselbe Canvas oder getrennt? →
   **Default: getrennt** (Bio ist ein anderes Konzept), Zusammenführung später.
6. Nur zeichnen, oder auch RECORD/latch von Live-Param-Moves? → **Default: erst nur
   zeichnen** (Record = eigener größerer Build).

→ Founder kann jeden Default umlenken, bevor Cycle 3–6 shippen. Cycle 1 ist von allen
  Antworten unberührt.

## FOUNDER-VERDIKT 2026-07-13 (AskUserQuestion, nach C4-Ship) — Roadmap-Reorder
Vier Fragen beantwortet:
1. **Play/Stop-Knopf pro Clip: JA** (eigener sichtbarer Button; Tap-auf-Zelle bleibt als
   Schnellstart). → eigener kleiner Zyklus.
2. **Clip-Länge: „Flexibel wie bei Ableton. Auch Taktarten etc. ABER erstmal muss alles
   wirklich in den Spuren der Timeline richtig fertig sein."** → Clip-Länge + Taktarten
   werden ZURÜCKGESTELLT, bis die Timeline-Spuren (Regionen, Playback, Mix, **Automation
   song-absolut = C5**) wirklich fertig sind. C5 wird damit TOP-PRIORITÄT.
3. **Bio-Automation aufnehmen: JA** (live Bio-Modulation in eine Lane einfrieren →
   reproduzierbar/editierbar, auch ohne Sensor abspielbar). → eigener Zyklus nach C5.
4. **Normale Automation per Record/Latch: JA, zusätzlich zum Zeichnen.** → eigener Zyklus.

### Neue Zyklus-Reihenfolge (ab hier)
- **C5 (JETZT): Automation song-absolut in den Timeline-Spuren** — `TimelineDocument.automation`
  (song-absolute Ticks), gefüttert vom `TimelineRegionPlayer`-Cursor (`currentTick`), Präzedenz
  Timeline gewinnt (nach global+clip angewandt), sichtbar/editierbar im Arrange-View. Rev:
  Architect + DSP Purist + Shipper. Device-gated. „richtig fertig in den Spuren".
- **C6: Play/Stop-Knopf pro Clip** (Session-Grid; klein).
- **C7: Bio-Record** — live Bio-Modulation eines Parameters in eine Lane schreiben
  (Snapshot der resolved Werte, ~10–30 Hz → keyframe-reduziert). Bio-Safety-Reviewer.
- **C8: Param-Record/Latch** — live bewegte Regler in die Lane mitschreiben (Write/Latch-Mode),
  zusätzlich zur Canvas.
- **SPÄTER: Flexible Clip-Länge + Taktarten** (Ableton-Stil) — NACH C5, wenn die Timeline steht.
