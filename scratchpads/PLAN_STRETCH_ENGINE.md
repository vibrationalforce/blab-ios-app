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

### Slice 1 — Tape-Executor (erster HÖRBARER Charakter, Founder-A/B)
`StretchExecutor`-Protokoll + Clean- & Tape-Executor. `AudioClipPlayer` hält beide Nodes,
routet per `region.stretchMode.effectiveMode` (Rewire unter Pause bei Modus-Wechsel). UI:
Modus-Picker (nur `selectable`) im Clip-Editor neben Warp. audio-thread/graph-review Pflicht.

### Slice 2 — Beats-Executor (In-house WSOLA)
Textbuch Verhelst-Roelands WSOLA (vDSP-Kreuzkorrelation, patentfrei). Pairt mit EchoelBreak/
BioEventGraph-Onsets. Pure WSOLA-Core test-first, dann Node-Wrapper.

### Slice 3 — Studio-Executor (Signalsmith, FOUNDER-GATED)
Nur nach Founder-Ja + Council + on-device A/B: MIT-C++-Bridge außerhalb des Render-Cores.

### Slice 4 — Überall
Video-Ton (PLAN_VIDEO_AUDIO), Sampler, Browser-Audition lesen dieselbe `StretchPlan`.
Ein Selektor, ein Verhalten app-weit.

## Erste Scheibe = Slice 0 (pure Spine, test-first). Kein Deploy (Freeze).
## Executoren einzeln — NICHT alle Algorithmen auf einmal (die Falle).
