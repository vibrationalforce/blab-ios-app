# PLAN — Automation in der Spur (Founder-REIHENFOLGE Item 1), 2026-07-18

> Founder-Verdikt v10.79.183, Item 1: **„AUTOMATION IN DER SPUR (im Clip UND
> clip-übergreifend, alle Parameter via EchoelParameterRegistry) — ERST PLAN +
> Council, dann Zyklen."**
>
> Dieser Plan ersetzt den älteren `archive/PLAN_AUTOMATION_IN_TRACK_2026-07-13.md`
> und ergänzt `PLAN_TIMELINE_AUTOMATION_PERFORMANCE.md` (07-17, T1/P0/P1
> geliefert). Grundlage: Voll-Audit des IST-Stands (Explore-Agent 2026-07-18).

## IST-STAND (gebaut + verdrahtet — NICHT duplizieren)

Die **Spine ist fertig und live**:
- **Adressierung:** `EchoelParameterRegistry` — stabile String-keyPaths
  `"modul.sektion.parameter"` (z.B. `ddsp.filter.cutoff`), `ParameterDescriptor`
  (Codable, min/max/default/unit, normalized/denormalized-Clamp). 15 DDSP-Params
  + AUv3-Plugin-Params via `AUParameterBridge` (KVO). `automatableDescriptors()`
  = nur Params mit lebendem Setter (Placebo-Gesetz, keine toten Lanes).
- **Apply-Spine:** `ParameterApplyRouter.applyNormalized(keyPath, n)` →
  denormalisiert → gebundener Setter (DDSP: `PolySynthVoice:480`, AU:
  `AUParameterBridge:44`).
- **Kurven-Modell:** `AutomationLane` = `parameter` + sortierte `[AutomationPoint
  {tick, value[0…1], curve .hold/.linear, curvature[-1…1]}]` — Ableton-bendbar,
  Codable additiv, getestet.
- **Playback (3 Schichten, `AutomationPlayer.applyStep`):** (1) globale Loop-Lanes
  (per-Bar, `enabled`-Gate, Disk), (2) `clipLanes` (Clip-relativ, spielt wenn der
  Clip spielt, gewinnt über global), (3) `timelineLanes` (Song-absolut,
  autoritativ). `dispatchLane` routet freie keyPaths über den Router.
- **In-Clip-Daten (a):** `Clip.automation: [AutomationLane]` (Codable,
  Clip-relativ) — **reist mit dem Clip** (move/copy), spielt via
  `setClipAutomation` aus jedem Launch-Pfad (`TimelineRegionPlayer:529`,
  `ArrangementPlayer:137`, `LaunchQuantizer:77`, `ClipView:198`).
- **Cross-Clip-UI (b):** `TimelineAutomationRow` (T1, 07-17) — aufklappbare
  Zeile unter der Spur, Song-absolut, editiert `TimelineDocument.automation` via
  `TimelineStore.addAutomationPoint/move/remove`, gespielt via `timelineLanes`
  (`TimelineRegionPlayer:294/466/764`). **Zeichnen bewegt den Param beim Play.**
- **Präzisions-Editor:** `AutomationView` (Sheet) — Ziel-Picker (3 Enum-Targets +
  router-gebundene Registry-Params), Zeichen-Canvas (`AutomationCanvasMath`, pur)
  + getippte Keyframe-Liste. Editiert die **globalen Loop-Lanes**.

## DIE LÜCKEN (gegen Item-1-Vollbild)

| # | Lücke | Warum sie zählt | Dateien |
|---|-------|-----------------|---------|
| L1 | **Keine Zeichen-Fläche INS Clip.** `clip.automation` wird nur vom `BioAutomationRecorder` (Bio-Takes) befüllt; kein Draw-Editor schreibt es. | „im Clip" (Founder) = genau das. Speicher + Playback existieren schon → nur die Editier-Tür fehlt. | `ClipView`, `AutomationView`, `Clip`, `TimelineStore`/`ClipStore` |
| L2 | **Timeline-Automation ist DOKUMENT-global pro Parameter, nicht pro Spur.** Zwei Spuren mit „Filter Cutoff" editieren DIESELBE Kurve; Targets sind globale Engine-Params, nicht „Cutoff DIESER Spur". (Ehrlich dokumentiert `TimelineAutomationRow:11-16`.) | „in der Spur" verspricht Pro-Spur — heute eine latente UI-Lüge. | `Timeline`/`TimelineDocument`, `TimelineStore:735`, `AutomationPlayer`, `TimelineAutomationRow` |
| L3 | **`AutomationTarget`-Enum (master/tempo/filterCutoff) beschattet „alle Params".** Bespoke-Enum-Kurven + direkter `applyEnum`-Write; alles andere muss router-gebunden sein. | „alle Parameter" wird erst first-class, wenn das Enum-Sonderspiel in die Registry+Router-Bahn kollabiert. | `AutomationPlayer:20-110,202-275` |
| L4 | **Pro-Instrument-Params nicht als eigene keyPaths in der Registry.** DDSP wird EINMAL global registriert; mit Pro-Spur-Synth (#23, gebaut) bräuchte jede Spur `track.<id>.ddsp.…` + eigene Router-Bindung, damit „Cutoff dieser Spur" adressierbar ist. | Voraussetzung für L2 (echtes Pro-Spur-Targeting). | `EchoelParameterRegistry`, `PolySynthVoice:480`, Pro-Spur-Synth-Verdrahtung |
| L5 | **`AutomationGestureRecorder` unverdrahtet** (= Task #20, Immersive-Stage-Puck). Multi-Dim-Geste → Clip-Lanes hat keinen Producer/Consumer. | Eigener Track (Task #20), nicht Item-1-Kern. | Immersive-Stage + `clip.automation`-Write |

## COUNCIL — Slice-Sequenz für Item 1

**Frage:** Da die Spine steht, was ist die billigste Slice-Folge, die „Automation
in der Spur (im Clip + clip-übergreifend, alle Params)" EHRLICH liefert?

- **User-Advocate:** Der Founder nennt BEIDE Flächen. „clip-übergreifend" ist
  gebaut (TimelineAutomationRow). „im Clip" ist die sichtbare Leerstelle → **L1
  ist der direkte Treffer** und das, was er beim Antippen eines Clips erwartet.
- **Architect:** L1 dupliziert NICHTS — Speicher (`clip.automation`) + Playback
  (`setClipAutomation`) + Zeichen-Mathe (`AutomationCanvasMath`) existieren. Es
  fehlt nur: Canvas auf Clip-Länge skaliert + Write-Back-Mutation. **Kein neues
  Store-Modell, keine neue Sheet** (AutomationView wird clip-scoped erweitert →
  Sheet-Ketten-Gesetz gewahrt).
- **Skeptic:** L2 (Pro-Spur-Bindung) ist die eigentliche Ehrlichkeits-Schuld, aber
  sie hängt an L4 (Pro-Instrument-keyPaths) → eigener Design-Zyklus, NICHT in L1
  reinquetschen. Und: `AutomationView` editiert heute globale Loop-Lanes — die
  clip-scoped Variante darf den globalen Pfad NICHT brechen (Golden-Gate:
  ohne Clip-Bindung byte-identisch).
- **DSP-Purist:** Apply-Pfad ist schon MainActor/Router, kein Audio-Thread-Thema;
  `clip.automation` wird beim Launch gesetzt, nicht im Render. Sauber.
- **Shipper:** L1 in Scheiben: **S1** pure Store-Mutation `setClipAutomation`
  (persist + undo) + Tests (Linux-CI, 0 Geräterisiko). **S2** AutomationView
  clip-scoped (Binding + spanTicks=Clip-Länge, Golden-Gate global unverändert).
  **S3** Tür aus dem Clip-Long-Press-Menü (Slot-Reuse, keine neue Sheet). L2/L3/L4
  danach als eigene, founder-sichtbare Zyklen. L5 = Task #20 separat.

**Dissens (benannt):** Skeptic würde L2 höher gewichten (die Pro-Spur-Lüge), aber
alle stimmen: L2 ohne L4 ist ein halber Pfad; L1 liefert JETZT ehrlichen
sichtbaren Wert ohne Registry-Umbau. → **Gate: proceed mit L1 (S1→S2→S3), L2/L4
als benannter Folge-Design-Zyklus.**

## SLICES (Item 1 → L1 zuerst)

### S1 — `ClipStore`/`TimelineStore.setClipAutomation` (pur, test-first, 0 Gerät)
Mutation, die die `[AutomationLane]` eines Clips setzt/ersetzt, persistiert +
Undo-Snapshot (wie `setLanePatch`, #23-S1-Muster). Betrifft `Clip.automation`
(existiert). Tests: setzen, ersetzen, leeren, Roundtrip Codable, Undo.
**Verify:** Linux-CI grün. Reviewer: code-reviewer.

### S2 — `AutomationView` clip-scoped (Golden-Gate global unverändert)
Optionales `clipBinding` (Clip-ID + Länge). Ohne Binding: byte-identisch zu
heute (globale Loop-Lanes). Mit Binding: Canvas-spanTicks = Clip-Länge, Ziel-
Picker = `automatableDescriptors()`, Write-Back über S1. `AutomationCanvasMath`
wiederverwendet.
**Verify:** CI grün + Gerät (Kurve zeichnen, Clip spielt, Param bewegt sich).
Reviewer: ui-state-reviewer (Sheet-Ketten-Gesetz: KEINE neue Sheet, bestehende
erweitern; kein 10-Hz-Read im Body).

### S3 — Tür: Clip-Long-Press → „Automation" (Slot-Reuse)
Eintrag im bestehenden Clip-Kontextmenü (`ClipView`), öffnet S2 clip-scoped.
Keine neue `.sheet`.
**Verify:** Gerät (Menü → Automation → zeichnen → hörbar).

### Folge-Zyklen (benannt, NICHT jetzt)
- **L2+L4 Design-Zyklus:** Pro-Spur/Pro-Instrument-Targeting — `AutomationLane`
  bekommt Track-Bindung, Registry bekommt `track.<id>.…`-Namespace, Router bindet
  pro Spur. Eigener PLAN + Council (hängt an #23 Pro-Spur-Synth, gebaut).
- **L3:** `AutomationTarget`-Enum in Registry+Router kollabieren (Refactor,
  Golden-Gate, eigener Zyklus).
- **L5 = Task #20:** `AutomationGestureRecorder` an Immersive-Stage verdrahten.

## GESETZE (Checkliste je Slice)
- Sheet-Kette NICHT wachsen (S2 erweitert AutomationView, S3 reuse-Menü).
- Kein 10-Hz-Bio/Playhead-Read im Root/Ancestor-Body (Canvas ist Leaf).
- `AutomationLane`/`Clip.automation` Codable additiv (`decodeIfPresent`).
- EchoelValueField für die Keyframe-Zahlen (existiert in AutomationView).
- Audio-Thread unberührt (Apply ist MainActor/Router, Launch-zeitig).
- Conventional Commits + Fable-5-Trailer; Pflicht-Reviewer je Slice.
