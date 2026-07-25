# PLAN — Flow/Loop-Modi + Genre-Kuration (Founder 2026-07-24)

**Founder, wörtlich:**
> „What I like is to use flow mode for just meditation. But also loop mode with proper
> timing for production. Genre is better you decide and curate something that really fits
> the brand."
> „Die 6 ruhigen Genres. Aber erfinde noch passende dazu. Ambient-Meditation-drift-contemplation."

Zwei Arbeitsstränge auf dem reinen Instrument (#124-Home, keine Timeline):
- **A. Flow/Loop-Modus** — EIN klarer Modus-Umschalter: Flow (Meditation, frei) vs Loop
  (Produktion, getaktet).
- **B. Genre-Kuration** — auf eine markengerechte kontemplative Palette (an mich delegiert).

## Ground-Truth (Explore-Agent 2026-07-24, file:line verifiziert)

### Timing / Modi — die Flow/Loop-Trennung EXISTIERT bereits, ist aber zerstreut & versteckt
- `BioComposer.ComposerMode` (`BioComposer.swift:22-25`): `.flowFree` („tempo follows the
  heart, for meditation") vs `.studioLocked` („fixed BPM … for DAW handoff"). **Das IST die
  Flow/Loop-Achse auf Composer-Ebene.**
- Studio hardcodet `.flowFree` (`EchoelStudioView.swift:3740`) → `.studioLocked` + die
  Per-Genre-Policy `MusicStyle.defaultMode` (`MusicStyle.swift:729-734`) sind toter Pfad.
- Tempo-Lock = separater Flag `lockBPM`/`lockedBPM` (`EchoelStudioView.swift:157-160`),
  UI = Lock-Button im `BodyTempoField` (TransportBar).
- `BeatMode` (`BioComposer.swift:33-43`): `.off` (reine Flächen/ambient), `.pulse` (default),
  `.genre` (Bar-gelockter Genre-Groove). Orthogonal zur Timing-Achse.
- Bar-Quantisierung nur bei Capture/Export via `LoopCutter` + `loopBars`
  (`EchoelStudioView.swift:263`, `loopLengthSelector :3220`).
- **Fazit:** „Flow vs Loop" = die schon vorhandenen Flags (`ComposerMode` + `BeatMode` +
  `lockBPM` + `loopBars`) unter EINEN klaren Modus-Schalter bündeln — KEIN neues DSP.

### Meditation / Session — im Code, unmontiert
- `SessionEngine`/`SessionClock`/`EntrainmentEngine`/`SessionGuide` (`Bio/`) + `SessionView`
  (`Studio/`) existieren, kompilieren, werden aber NICHT präsentiert
  (`WorkspaceView.swift:45-47`). Breath-Pace/kontemplativ, KEINE Bar/Beat-Logik.
  `EchoelStudioView.presentSession` ist immer nil (`SurfaceHost` baut `EchoelStudioView()`
  ohne Argument). → wiederverwendbar für Flow-Modus.

### Genre — 23 Cases, 4-Kategorien-Picker
- `MusicStyle` (`MusicStyle.swift:63`), 23 Cases (`:123-145`). Kategorien
  meditative(4)/electronic(8)/rock(5)/acoustic(6) (`:97-105`).
- Live-Picker: `CompositionHeaderStrip` (`WorkspaceView.swift:566-575`), iteriert
  `Category.allCases → cat.genres`. (EchoelStudioView-`genrePicker` ist nur noch Kommentar,
  nach CompositionHeaderStrip verschoben; FloatingVisualWindow liest nur.)
- Default = `.selfObservation` (`StudioDefaultKeys.swift:47`) — bereits eine ruhige.
- **TEST-SPERRE:** `MusicStyleTests.testEveryGenreIsOfferedInExactlyOneCategory` (`:11`)
  verlangt `Set(Category.allCases.flatMap{genres}) == Set(allCases)` — JEDE Genre muss
  kategorisiert sein. → `Category.genres` NICHT leeren (bricht den Test, der die alte
  „alles rein"-Politik einbetoniert).

## Design-Entscheidung (Council: proceed)
- **Genre:** „Angebotene Palette" von „voller Taxonomie" ENTKOPPELN. `Category.genres` +
  Enum bleiben KOMPLETT (Taxonomie-Test grün, Switches exhaustiv, gespeicherte Werte
  decodieren, reversibel). NEU: `MusicStyle.offered: [MusicStyle]` = kuratierte kontemplative
  Palette; der Picker iteriert `offered`, gruppiert nach Kategorie, überspringt leere
  Sections. Reversibel = `offered`-Liste ändern, keine Enum-Löschung.
- **Naming-Rotlinie:** `esotericMeditation`-rawValue NICHT umbenennen (Codable-Migration);
  Display „Deep Ambient" ist markengerecht. KEINE Genre wörtlich „Meditation" nennen
  (Wellness-nah) — die kontemplative Absicht über Ambient/Drift/Contemplation ausdrücken.

## Slices (reversibel, eine/Zyklus, Gate-grün + Reviewer, NEEDS-FOUNDER-VERIFY)

### Genre
- ▶ **G1 (dieser Zyklus) — Kuration auf die ruhige Basis.** `MusicStyle.offered` = die 6
  kontemplativen Bestands-Genres [selfObservation, esotericMeditation("Deep Ambient"),
  vaporwave, sciFi, classical, dubTechno]; Picker iteriert `offered` (leere Sections
  überspringen); neuer Test `offered ⊆ allCases`, nicht-leer, Snapshot. Default schon
  offered. → Founder sieht „nur die ruhigen".
- **G2 — Neue Ambient-Familie erfinden** („erfinde noch passende dazu"): je neue `MusicStyle`-
  Case (Ambient/Drift/Contemplation/…) mit VOLLER Signatur (displayName, lineage, tempoRange,
  defaultTempo, beatArchetype=.none, harmonicProfile, scale, category=.meditative, alle
  Switches + Distinktheits-Test) — je Genre eine Slice, damit jede gut & distinct klingt
  (Anti-Konvergenz). In `offered` aufnehmen.

### Flow/Loop-Modus
- **M1 — PLAN + Council** für den EINEN Modus-Schalter (Flow/Loop) als eigenen Zyklus:
  Flow = `.flowFree` + `lockBPM=false` + BeatMode `.off/.pulse` (frei, ambient, kontemplativ);
  Loop = `.studioLocked`/`lockBPM` + BeatMode `.genre` + `loopBars`-Quantisierung (getaktet,
  produzierbar). UI-Schalter im Instrument-Home (render-sensibel — sheet-Kette/Freeze
  beachten). Wiederverwendet die vorhandenen Flags, kein neues DSP.

## Status
- ✅ **G1 GESHIPPT** — Commit `cdc0fff`, beide echten Gates grün (Xcode Compile + CI/CD,
  inkl. der zwei neuen Tests). Picker zeigt nur noch die 6 kontemplativen: Self-Observation ·
  Deep Ambient · Vaporwave · Sci-Fi · Classical · Dub Techno. Vollständige Taxonomie + Enum
  unangetastet (reversibel via `offered`-Liste). ui-state-reviewer PASS auf alle 6 Checks.
  **NEEDS-FOUNDER-VERIFY** (Picker am Gerät; TestFlight-Freeze). Rand-Fall: wer vorher eine
  jetzt-nicht-angebotene Genre gespeichert hatte, sieht erst keine Picker-Markierung (nicht
  kritisch; Komposition läuft weiter) — Union-mit-Alt-Wert nur falls Founder es will.
- ▶ **G2 Slice 1 — „Drift" erfunden (dieser Zyklus, Reviewer läuft):** erste neue Ambient-
  Familien-Genre als voller `MusicStyle`-Case. Signatur bewusst DISTINKT von den zwei
  bestehenden drum-freien Flächen (Anti-Konvergenz): **dorian** (nicht das dunkle Moll von
  Self-Observation, nicht das helle Lydian von Deep Ambient) · Progression `[0,4]` i→v ·
  **padOctave 4** (eine Oktave ÜBER den beiden = luftiger/schwebender) · tempoRange 48…74,
  default 60 · beatArchetype `.none` · sustained · leadDensity 0 · category `.meditative` ·
  defaultMode `.flowFree` (Ambient folgt dem Herz = Flow). Eigenes Timbre („Drift Pad", DD):
  weiterer Unison-Shimmer (3/12), sehr langsamer tiefer Filter-Drift, größter Raum. Eigener
  FX-Preset: weiter dotted-quarter Digital-Shimmer, hellster/undämpfter Big-Hall. In `offered`
  aufgenommen (jetzt 7 kontemplative). 3 Sources + 1 Test-Datei (neuer Distinktheits-Test +
  drum-frei-Set von 3→4 geweitet). BioComposer unverändert — Drift läuft durch den `default:`-
  Flächen-Pfad wie die Geschwister. **Alle exhaustiven MusicStyle-Switches erweitert**
  (MusicStyle/GenrePatches/GenreFX), BioComposer nutzt `default:`.
- **G2 Slice 2/3 — „Ambient" + „Contemplation"** (Folge-Zyklen): je eigene distinkte Signatur.
  Danach **M1 — Flow/Loop-Modus-Schalter** (eigener PLAN + Council).
