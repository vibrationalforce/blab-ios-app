# PLAN #54 — Warp im Audio-Clip-Editor (Founder: „neuste Technologie")

> ⛔ **SCOPE NOTE (audit 2026-09-02): this plan predates the product definition of 2026-07-25**
> (`docs/dev/PRODUCT_DEFINITION.md`, Editor ≠ Workstation). Where it names timeline / clips /
> arrangement / multitrack / lanes-as-tracks / AUv3 / broadcast / drums / piano-roll surfaces, those
> are CUT and that part is history — do not execute it. Nothing below was edited; check the
> definition before building from any line here.


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
- „neuste Technologie" — **Deep-Research 2026-07-16 (wf_bc68b344-d26, 13 Kandidaten
  verifiziert)** korrigiert den alten Plan-Satz: stock `AVAudioUnitTimePitch` läuft IMMER
  `AUNewTimePitch` (spectral phase-vocoder). Das `AVAudioTimePitchAlgorithm`-Enum
  (`.spectral`/`.timeDomain`/`.varispeed`) ist ein **AVPlayerItem/AVAssetExport-Knopf
  (offline)**, KEINE Property des Realtime-Graph-Node — am Node gibt es nichts zu „setzen"
  außer `rate`/`pitch`/`overlap`. Ranking: (1) `AVAudioUnitTimePitch` = FREI, nativ,
  realtime, zero-dep → **v1-Baseline (Slice A)**. (2) **Signalsmith Stretch** (MIT,
  header-only, Accelerate, transient-erhaltend, unabhängig über Rubber Band v2/v3 bewertet)
  → **Slice C**, der EINE offene Engine, die die Baseline schlägt, ohne Gebühr — aber das
  ERSTE C++ im Baum ⇒ Council + Founder-Dependency-Ja, contained im Bridging-Modul außerhalb
  des Render-Cores, NUR nach on-device A/B. (3) In-house WSOLA/SOLA (Ableton-„Beats"-Design,
  patentfrei) für Drums; (4) Varispeed „Tape"-Mode (`AVAudioUnitVarispeed`, gratis).
  REJECT alle bezahlten (jede zplane-élastique-Stufe / Ableton Complex/SOLOIST) + copyleft
  (Rubber Band GPL, SoundTouch LGPL-auf-iOS). KEINE Ableton-Warp-Marker (nur Native-BPM-Ratio).

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

### Slice C — „neuste Technologie" — DEPENDENCY FOUNDER-APPROVED 2026-07-16
- `AVAudioUnitTimePitch`-Executor gegen **Signalsmith Stretch** tauschen (höhere
  Qualität/Transienten). Founder-Ja liegt vor („C++ egal, gebührenfrei, Apple-first") →
  MIT-Dependency freigegeben. Disziplin bleibt: NUR nach A+B mit Stock-Unit hörbar +
  on-device A/B-Gewinn; contained C++-Bridge außerhalb des Render-Cores. = StretchMode
  `.studio` (siehe PLAN_STRETCH_ENGINE.md Slice 3).

## Erste Scheibe = Slice A (Preview-Render + minimaler Enable), audio-thread-reviewer.
## NICHT Math/Model neu bauen — Schritte 1–2 sind fertig + getestet (die Falle).

## ✅ Slice A GEBAUT (2026-07-16, on branch, beide Reviewer approve)
- Render: `AudioClipPlayer` besitzt jetzt einen `AVAudioUnitTimePitch`, always-in-chain
  `node → timePitch → masterMixer` (neue `AudioEngine.attachPlayerNode(_:through:format:)`
  + `detachPlayerNode(_:timePitch:)`). `play(region:projectBPM:)` setzt `timePitch.rate =
  region.effectiveStretchRate(projectBPM:)` (getestete Math), `pitch = 0` — Control-Plane,
  kein Render-Thread-Work. audio-thread-reviewer = CLEAN.
- UI: `AudioClipView.regionControls` hat Warp-Toggle + „Clip BPM"-`EchoelValueField`
  (20…400) + Live-Stretch-Anzeige; Play reicht `beatPlayer.pattern.tempo` durch.
- **Nur Editor-Preview** — Timeline (`TimelineAudioSink`) bleibt bit-transparent (Slice B).
- **Device-Gate (Founder-Session, Freeze-Lift):** (1) Warp-ON: Clip zieht hörbar auf
  Projekt-Tempo, Tonhöhe bleibt. (2) **Warp-OFF Preview klingt sauber?** — der Spectral-Node
  bleibt immer in der Kette (rate 1.0 ≠ bit-transparent, trägt Overlap-Add-Latenz). Falls
  hörbare Färbung/Latenz: Follow-up routet Warp-OFF durch den plain Single-Node-Pfad.
