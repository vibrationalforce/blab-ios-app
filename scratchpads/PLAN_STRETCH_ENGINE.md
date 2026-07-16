# PLAN — EchoelStretchEngine (Founder 2026-07-16: „eigene Stretch Engine, verschiedene Algorithmen zur Auswahl, die besten von Qualität und Charakter überall")

**Was:** EINE Echoel-Stretch-Fassade mit wählbaren Algorithmen (Qualität + Charakter),
durch die JEDER Time-Stretch-Konsument geht — Audio-Clip (#54), Video-Ton
(PLAN_VIDEO_AUDIO), EchoelBreak/LoopCutter, Sampler, Browser-Audition. Ein Selektor,
ein Persistenz-Feld, ein Executor-Set. Genau die Verallgemeinerung der #54-Research.

**Council 2026-07-16:** proceed. Pure Spine zuerst; Executoren je eigene demobare Scheibe;
UI zeigt nur implementierte Modi (kein lügender Selektor); nicht-verdrahtete Modi fallen
ehrlich auf `.clean` zurück (nie still).

## Die Modi (nur FREIE, App-Store-saubere Executoren — bezahlt/copyleft raus per #54)

| Modus | Executor | Charakter | Pitch | Stand |
|---|---|---|---|---|
| **Clean** | `AVAudioUnitTimePitch` (Apple spectral) | transparent | erhalten | ✅ LIVE (#54 Slice A) |
| **Tape** | `AVAudioUnitVarispeed` (Apple) | Tape/Turntable | folgt Tempo | Executor = nächste Scheibe |
| **Beats** | In-house WSOLA/SOLA (patentfrei) | transienten-fest, Drums/Loops | erhalten | Scheibe (paart mit EchoelBreak) |
| **Studio** | Signalsmith Stretch (MIT C++) | höchste Transienten-Qualität | erhalten | **Founder-gated** (erstes C++) |

Charakter-Erweiterung später: **Vintage** (Akai-artig — 12-bit + Granular, inspiration.csv WATCH).

## Architektur (Fassade + Executor)

- **Pure Spine (diese Scheibe):** `StretchMode` (enum, Codable, Charakter-Laws + `effectiveMode`-
  Fallback + `selectable`) · `StretchPlan.resolve(mode:warpEnabled:nativeBPM:projectBPM:)` →
  `(rate, preservesPitch, mode)`, reine Werte über `TempoMatch`; nie divergent zu
  `AudioClipRegion.effectiveStretchRate`. + `AudioClipRegion.stretchMode` (decodeIfPresent, `.clean`).
- **Executor-Protokoll (nächste Scheibe):** `@MainActor protocol StretchExecutor { var node: AVAudioUnit; func apply(_ plan: StretchPlan) }`. Jeder Executor besitzt SEINEN Graph-Node
  (kein Render-Block → audio-thread-safe). Konsument steckt `executor.node` zwischen Quelle und
  Mixer; Modus-Wechsel = Graph-Rewire unter `withGraphPaused` (selten, Editor — NICHT pro Frame).
- **Konsumenten** lesen `StretchPlan.resolve(...)` und konfigurieren ihren Executor. `AudioClipPlayer`
  ist der erste (hält heute schon den `AVAudioUnitTimePitch` = Clean-Executor).

## Scheiben

### ✅ Slice 0 — Pure Spine (DIESE Scheibe, test-first)
`StretchMode` + `StretchPlan` + `AudioClipRegion.stretchMode`-Persistenz + `StretchEngineTests`.
Kein Verhalten geändert (Clean = heutiger Pfad). Der Boden, auf dem alles steht.

### Slice 1 — Tape-Charakter (✅ GEBAUT 2026-07-16, erster hörbarer A/B)
Risikoarmer Weg gewählt (kein Graph-Rewire, blind compile-sicher): Tape = Pitch-folgt-Tempo
auf dem VORHANDENEN `AVAudioUnitTimePitch` via `pitch = 1200·log₂(rate)` (`StretchPlan.
tapePitchCents`, pur+getestet). `.tape.isImplemented=true` → `selectable=[.clean,.tape]`.
`AudioClipPlayer.play` liest `StretchPlan`, setzt rate+pitch (Clean=0, Tape=cents). UI:
`.segmented`-Picker im Warp-Block + modus-bewusster Status ("pitch held" / "pitch rides tempo").
Reviews: audio-thread CLEAN, code MEDIUM+LOW gefixt. Nur hörbar bei Warp-ON (rate≠1) — by design.
**Device-Hörtest offen** (Freeze): warp-Clip, Clean vs Tape umschalten → Tonhöhe hält vs. reitet.

### Slice 1+ — authentisches Varispeed/Akai-Grit (Founder „vintage vibe")
`AVAudioUnitVarispeed`-Executor (echtes Resampling) als eigener Charakter neben dem
timePitch-Tape — DANN lohnt der Node-Swap-Aufwand (Rewire unter Pause). + Vintage/12-bit-Grit
(inspiration.csv Akai WATCH). Eigene Scheibe, audio-thread/graph-review.

### Slice 2 — Beats-Executor (In-house WSOLA)
Textbuch Verhelst-Roelands WSOLA (vDSP-Kreuzkorrelation, patentfrei). Pairt mit EchoelBreak/
BioEventGraph-Onsets. Pure WSOLA-Core test-first, dann Node-Wrapper.

### Slice 3 — Studio-Executor (Signalsmith) — DEPENDENCY FOUNDER-APPROVED 2026-07-16
Founder-Ja liegt vor („Python/C++ egal, wichtig gebührenfrei, Apple-first"): Signalsmith
Stretch (MIT, gratis) ist im Prinzip freigegeben. RESTLICHE Disziplin bleibt: on-device
A/B gegen `.clean`/Apple-spectral BEVOR committen; contained MIT-C++-Bridge AUSSERHALB des
Swift-Render-Cores (nie im Render-Callback); Council-Node-Review. Reihenfolge unverändert:
NACH Tape + Beats, nicht als erste hörbare Scheibe.

### Slice 1½ — Modell-Lücke geschlossen (✅ 2026-07-16): `TimelineRegion.stretchMode`
Der Editor-Warp+Tape-Entscheid ging beim „Add to timeline" VERLOREN — die platzierte
`TimelineRegion` hatte `warpEnabled`, aber KEIN `stretchMode`, und `AudioClipFactory.region`
trug nicht mal `warpEnabled` durch. Jetzt: `TimelineRegion.stretchMode: StretchMode`
(spiegelt `warpEnabled` — Init-Default `.clean`, CodingKey, `decodeIfPresent .clean`,
`abuts`-Guard verweigert Tape↔Clean-Join wie bei gain/warp; split/trim/merge/duplicate
erben via `var x = self`). `AudioClipFactory.region` bekam `warpEnabled`/`stretchMode`-
Parameter; `AudioClipView.addToTimeline` reicht `region.warpEnabled`/`region.stretchMode`
durch. Tests: Default/Legacy-Decode/Roundtrip/Split-carry/abuts-refuse + Factory-carry.
**EHRLICH GESTUFT:** Timeline-Audio WENDET den Modus noch NICHT an (`AudioRegionSink.play`
hat keinen rate/mode-Param → das ist Slice B unten). Diese Scheibe = die ehrliche
Persistenz, damit der Entscheid auf der Region ÜBERLEBT; Editor-Preview warpt hörbar,
Timeline-Warp = dokumentierte Slice-B-Lücke. `structurallyEqual` behandelt Modus-Wechsel
korrekt als strukturell (via `regions ==`, konsistent zu `warpEnabled`).

### Slice B (offen, device-verify-schwer) — Timeline-Audio wendet rate/mode an
`AudioRegionSink.play` um einen rate/mode-Param erweitern + `resolveNativeBPM` in
`AudioLanePlayer` injizieren + Sink-Impl setzt `timePitch.rate`/`.pitch` aus `StretchPlan`.
DANN klingt eine platzierte warp+Tape-Region auf der Timeline wie im Editor-Preview.

### Slice 4 — Überall
Video-Ton (PLAN_VIDEO_AUDIO), Sampler, Browser-Audition lesen dieselbe `StretchPlan`.
Ein Selektor, ein Verhalten app-weit.

## Erste Scheibe = Slice 0 (pure Spine, test-first). Kein Deploy (Freeze).
## Executoren einzeln — NICHT alle Algorithmen auf einmal (die Falle).
