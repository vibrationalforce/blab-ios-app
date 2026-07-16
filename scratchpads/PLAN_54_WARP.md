# PLAN #54 — Warp im Audio-Clip-Editor (Founder: „neuste Technologie")

**Gap-Audit 2026-07-16 (Explore-Agent a103c199).** Kernbefund: **NICHT greenfield.**
Model + Math + Persistenz sind fertig und gehören zum best-getesteten Code im Repo —
aber **`warpEnabled` ist ein persistierter No-Op**: nichts time-stretcht Audio, und es
gibt **keine UI**, um Warp einzuschalten. Die Falle wäre, die getestete Math neu zu bauen.

## Ist-Zustand

- ✅ **Model + Persistenz (DONE, getestet):** `AudioClipRegion.warpEnabled/nativeBPM`
  (+ `TimelineRegion.warpEnabled`, `Clip.nativeBPM`), decodeIfPresent-back-compat,
  `effectiveStretchRate(projectBPM:)`, `warpedDurationSeconds`.
- ✅ **Pure Math (DONE, best-getestet):** `TempoMatch.stretchRate` (clamp 0.25…4.0),
  `WarpedClipPlan` (source/output-frames, onset), `AudioRegionPlayback` rate-aware
  `filePositionSeconds/startFrame/frameCount` (`stretchRate:` default 1.0). Cross-
  gecheckt in `AudioWarpMathTests`.
- ❌ **RENDER (MISSING — der Kern-Gap):** KEIN `AVAudioUnitTimePitch`/Varispeed
  irgendwo (nur Doc-Kommentare). `TimelineAudioSink.play()` scheduled roh aus der
  Datei; `AudioLanePlayer.start()` ruft `filePositionSeconds` OHNE `stretchRate:`;
  `AudioRegionSink.play(...)` hat gar keinen rate-Parameter. Editor-Preview
  `AudioClipPlayer.play(region:)` liest Frames + scheduleBuffer, ohne warpEnabled.
  ⇒ `effectiveStretchRate` wird nie mit ≠1.0 aufgerufen. Warp ist unhörbar.
- ❌ **UI (MISSING):** `AudioClipView.regionControls` hat EchoelValueField für
  Start/End/Gain/Fade + Loop — aber KEINEN Warp-Toggle, KEIN Clip-BPM-Feld. Der
  User kann Warp heute nicht einschalten. (`addToTimeline` setzt `nativeBPM`, aber
  NICHT `warpEnabled` → auch platzierte Clips sind warp-off.)
- „neuste Technologie": stock `AVAudioUnitTimePitch` = `.timeDomain` (Basis-Qualität).
  Repo hat schon **Signalsmith Stretch** (MIT, header-only, Accelerate) als
  `inspiration.csv:110` ADOPT-PRODUCT-PENDING-FOUNDER = transient-erhaltender v1-Kandidat.
  KEINE Ableton-Warp-Marker (nur ein Native-BPM-Ratio).

## Council (Warp jetzt bauen, welche Scheibe zuerst)

- **Shipper:** Math/Model fertig ⇒ die kleinste hörbare Scheibe ist reiner Render-
  Anschluss, kein Neubau. Editor-Preview = isoliert (ein Node, kein Transport/Render-
  Thread), niedrigstes Risiko.
- **DSP-Purist:** `AVAudioUnitTimePitch` ist ein Graph-Node, KEIN eigener Render-Block
  → keine Audio-Thread-Alloc/Lock-Verletzung. Aber: Graph-Änderung ⇒ audio-thread-
  reviewer Pflicht; Device-Audio-Verify unumgänglich (Freeze: erst CI+Review, Hörtest
  in Geräte-Session).
- **User-Advocate:** Ein Warp-Toggle OHNE hörbaren/sichtbaren Effekt wäre ein lügender
  Regler. Darum muss die erste USER-sichtbare Scheibe etwas Beobachtbares ändern —
  also Render (Preview) + minimaler Enable zusammen, nicht UI-Toggle allein.
- **Skeptic:** Editor-Preview-Render ist niedrig-Blast-Radius (nur Audition), im
  Gegensatz zur Timeline (betrifft Arrangement). Preview zuerst.
→ **Verdikt:** Preview-Render zuerst (Slice A), gepaart mit minimalem Warp-Enable im
  Editor, damit die Preview den Effekt DEMONSTRIERT. audio-thread-reviewer + code-
  reviewer. Kein Deploy (Device-Hörtest in Geräte-Session).

## Scheiben

### Slice A — Warp im Editor HÖRBAR (Preview-Render + minimaler Enable)
- `AudioClipPlayer.play(region:)`: `rate = region.effectiveStretchRate(projectBPM:)`;
  bei `rate != 1.0` den PlayerNode durch EINEN `AVAudioUnitTimePitch` (`.rate=rate`,
  pitch 0) routen statt roh zu schedulen. Attach-Pattern existiert schon im Engine.
- Minimaler Enable in `AudioClipView.regionControls`: Warp-Toggle + „Clip BPM"-
  `EchoelValueField` (bindet `region.warpEnabled`/`region.nativeBPM`), damit die
  Preview den Stretch demonstriert. (Nicht-lügender Regler.)
- Test-first wo pur möglich (die Rate-Wahl ist schon getestet; der Node-Pfad ist
  host-/audio-gebunden → audio-thread-reviewer statt Unit-Test).

### Slice B — Warp im Timeline-Arrangement hörbar (nach A)
- `rate`-Parameter in `AudioRegionSink.play(...)`; `AudioLanePlayer.start()` gibt die
  aus `warpEnabled`+`nativeBPM` abgeleitete Rate durch; `TimelineAudioSink` bekommt
  pro Node einen `AVAudioUnitTimePitch`. Die puren `filePositionSeconds/frameCount`
  akzeptieren `stretchRate:` bereits — nur durchreichen. (+ `addToTimeline`
  `warpEnabled` setzen, wenn nativeBPM erkannt.)

### Slice C — „neuste Technologie" (Founder-OK-gated)
- `AVAudioUnitTimePitch`-Executor gegen **Signalsmith Stretch** tauschen (höhere
  Qualität/Transienten). NUR nach A+B mit Stock-Unit hörbar; nicht die erste hörbare
  Scheibe an die Dependency-Entscheidung koppeln. (Dependency = Founder-Ask;
  inspiration.csv:110.)

## Erste Scheibe = Slice A (Preview-Render + minimaler Enable), audio-thread-reviewer.
## NICHT Math/Model neu bauen — Schritte 1–2 sind fertig + getestet (die Falle).
