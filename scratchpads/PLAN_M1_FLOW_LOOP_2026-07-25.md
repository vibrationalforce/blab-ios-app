# PLAN — M1 Flow/Loop-Modus-Schalter (Founder-Direktive B, 2026-07-25)

**Founder, wörtlich:** „What I like is to use flow mode for just meditation. But also loop
mode with proper timing for production."

Ein KLARER, sichtbarer „Flow | Loop"-Umschalter im Instrument-Home — **kein neues DSP**,
bündelt die schon vorhandenen Flags. Ground-Truth: Explore a0b7fcc (alle `file:line` verifiziert).

## Ground-Truth (verifiziert)

- **`ComposerMode`** (`BioComposer.swift:22-25`): `.flowFree` (Tempo folgt Herz, Meditation) vs
  `.studioLocked` (fixe BPM, DAW-Handoff). Konsumiert NUR in `BioComposer.tempo(for:)`
  (`:296-307`): studioLocked klemmt `lockedTempo` in `style.tempoRange`, flowFree folgt dem Puls.
- **Split-Brain / Dead-Path:** die LIVE-Kompositions­eingabe ist **hart `.flowFree`** verdrahtet
  (`EchoelStudioView.swift:3740`, `lockedTempo: 90`), und der Projekt-Save stempelt hart
  `ComposerMode.flowFree.rawValue` (`:4259`). D.h. der Composer läuft IMMER flowFree, egal was
  die UI/Genre-Policy sagt.
- **`MusicStyle.defaultMode`** (`MusicStyle.swift:808-812`, flowFree für die 4 drum-freien
  Ambient-Genres inkl. drift/contemplation, sonst studioLocked): **komplett toter Pfad** — kein
  einziger Caller in `Sources/` (nur die 3 MusicStyleTests-Assertions).
- **Tempo-Lock = SEPARATE Mechanik:** `lockBPM`/`lockedBPM` (`@AppStorage`,
  `EchoelStudioView.swift:159-160`, Keys `studio.lockBPM`=false / `studio.lockedBPM`=70). Gelesen
  im Generate-Pfad (`:3806-3808`): **wenn `lockBPM` an, gewinnt `lockedBPM`** und
  `composition.suggestedTempo` (der Composer-Tempo-Output) wird IGNORIERT. Toggle = Lock-Button im
  `BodyTempoField` (TransportBar, `BodyTempoField.swift:106-135`).
- **Schlüssel-Erkenntnis (Doppel-Lock-Frage geklärt, `EchoelStudioView.swift:3806-3833`):** weil
  `suggestedTempo` bei `lockBPM==true` ohnehin ignoriert wird, ist es **audio-neutral**, den
  Composer-`mode` aus `lockBPM` abzuleiten. Kein Doppel-Lock, kein Konflikt. Die einzige heutige
  „Falschheit": das Composer-Mode-LABEL + der gespeicherte Projekt-Mode sind permanent flowFree,
  auch wenn der User das Tempo lockt.
- **`loopBars`/`LoopCutter`** (`EchoelStudioView.swift:263`, Selector `:3223`, Export
  `LoopCutter.tile :4232`): schon **taktgenau** — treibt Mehrtakt-Generate + bar-akkuraten
  WAV-Export. „Loop mode with proper timing" ist hier bereits erfüllt.
- **UI-Fit (freeze-sicher):** `CompositionHeaderStrip` (`WorkspaceView.swift:563-680`) ist ein
  **dokumentierter Freeze-safe Leaf** (`:542-561`: liest NUR `@AppStorage`+`session.a4Hz`, kein
  ~10-Hz-Bio/Playhead) → ein `@AppStorage`-gebundenes Segmented-Control passt hier sicher rein.
- **Sheet-Decke:** EchoelStudioView-Root trägt ~11 Präsentations-Modifier (`:705-810`,
  Metadata-Limit) → **KEIN neues Modal**; der Schalter muss in-place (Chrome/Panel).
- **Tote Schwester-UI als Warnung:** `beatModeRow` **war** ein voll gebautes Segmented-Picker,
  das NIE gemountet wurde und dessen Wert nie konsumiert wurde (`silentBeat()`). „Control
  existiert im Source" ≠ „Control ist live" — der Schalter muss WIRKLICH die zwei Hardcode-Sites
  speisen. **Gelöscht mit #323 (2026-08-01)**; an seiner Stelle steht der Grabstein in
  `EchoelStudioView.swift`. (Die Zeilennummer `:1961`, die hier stand, war schon vor der
  Löschung falsch — die Lehre bleibt, der Zeiger war nie belastbar.)

## Council — proceed

- **Architect:** EINE Wahrheitsquelle = `lockBPM`; `mode` wird DARAUS abgeleitet. KEIN dritter
  Tempo-Flag (es gibt schon zwei). Composer-Tempo/Studio-Tempo-Interaktion geklärt (kein Doppel-Lock).
- **DSP-Purist:** reiner Control-Plane-Change, kein Audio-Thread, keine Render-Berührung. Safe.
- **Vision-Keeper:** „Flow | Loop" ist markengerecht (Meditation vs Produktion), vom Founder benannt.
  NICHT „Produktion"-Features überversprechen, die fehlen (Stems absent). Nur das Modus-Label.
- **Shipper:** S1 = reine Mapping-Funktion + Test + 2 Hardcode-Sites verdrahten. Winzig, reversibel,
  gate-verifizierbar. S2 = sichtbares Segmented-Control im Freeze-safe Leaf.
- **Skeptic:** Risiko = Composer/Studio-Tempo-Interaktion → GEKLÄRT (suggestedTempo ignoriert bei Lock).
  Verhaltensänderung: wer bisher BPM lockte, bekommt jetzt studioLocked-Komposition + korrekten
  gespeicherten Mode — das ist die GEWOLLTE Korrektur, kein Regress.
- **User-Advocate:** der Founder will die zwei Modi SEHEN. Segmented „Flow | Loop" > kryptisches
  Lock-Icon. ABER: der Schalter und der bestehende Lock-Button MÜSSEN denselben State (`lockBPM`)
  binden, damit sie nie widersprechen.

**Gate: proceed.** Wahrheitsquelle = `lockBPM`, `mode` abgeleitet; S1 test-first pure Helper
(verhaltens-sicher), S2 der sichtbare Schalter im Freeze-safe Leaf.

## Slices (reversibel, eine/Zyklus, Reviewer + Gates, NEEDS-FOUNDER-VERIFY)

### M1-S1 — Split-Brain schließen: `ComposerMode` aus `lockBPM` ableiten (dieser Zyklus)
- **Pure Helper** (test-first) an `ComposerMode` (BioComposer.swift, Foundation-only):
  `public init(locked: Bool) { self = locked ? .studioLocked : .flowFree }`.
- **Wire `EchoelStudioView.swift:3740-3741`:** `mode: ComposerMode(locked: lockBPM),` und
  `lockedTempo: lockBPM ? lockedBPM : 90,` (bei Lock die ECHTE gelockte BPM übergeben, sonst
  bisheriger 90-Default; flowFree ignoriert lockedTempo ohnehin).
- **Wire `EchoelStudioView.swift:4259`:** `modeRaw: ComposerMode(locked: lockBPM).rawValue`
  (gespeicherter Projekt-Mode wird korrekt statt immer-flowFree — echter DAW-Handoff-Fix).
- **Test:** `ComposerMode(locked:)` Mapping (true→studioLocked, false→flowFree). Optional
  Project-Roundtrip, dass ein gelockter Save studioLocked schreibt.
- **NICHT rein audio-neutral (Reviewer-Korrektur 2026-07-25):** `input.mode` speist auch
  `tempo(for:)` INNERHALB `compose()` → `tempoDensityScale`. Bei Lock skaliert die Notendichte
  jetzt für `lockedBPM` statt für den Ruhe-Puls — das ist die GEWOLLTE Korrektur (ein 124-BPM-Loop
  soll für 124 skaliert werden, nicht für ~66; alter „auf 132 zu hektisch"-Mismatch), kein Regress.
  Der Transport-Tempo-Wert kommt weiter aus `lockedBPM`. **NEEDS-FOUNDER-VERIFY am Gerät.**
  Reviewer = code-reviewer (kein Body/Sheet/10-Hz-Read → Freeze-Gesetz n/a).

### M1-S2 — Sichtbarer „Flow | Loop"-Schalter (Folge-Zyklus)
- Segmented `Picker` (2 Segmente „Flow"/„Loop") in `CompositionHeaderStrip`
  (`WorkspaceView.swift`, Freeze-safe Leaf), an `@AppStorage(studio.lockBPM)` gebunden — EINE
  Wahrheitsquelle, identisch mit dem TransportBar-Lock-Button (nie widersprüchlich). Kein neues Sheet.
  onChange postet `.echoelCompositionEdited`/recompose wie die Geschwister-Picker.
- Label-Semantik: Flow = Meditation, Tempo folgt Körper · Loop = Produktion, fixe BPM (taktgenauer
  Loop/Export existiert via `loopBars`). EchoelValueField-Regel n/a (Modus-Toggle, kein Zahlenparam
  → Segmented Picker korrekt, wie `loopLengthSelector`).
- **Freeze-Check:** nur `@AppStorage`-Flag lesen, NIE Bio/Playhead im Strip-Body.

### M1-S3 — (optional, Polish) Loop-Seed
- Beim Wechsel Flow→Loop, falls `lockedBPM` noch nie sinnvoll gesetzt: aus dem aktuellen
  Body-Tempo seeden, damit Loop sofort eine sinnvolle fixe BPM hat.

## Status
- ✅ Ground-Truth (Explore a0b7fcc) + Council. PLAN steht.
- ✅ **M1-S1 GESHIPPT** `1dfcd90` (+ Ehrlichkeits-Fix `d5ea5aa`), beide echten Gates grün. pure
  `ComposerMode(locked:)` + 2 Hardcode-Sites verdrahtet. Reviewer-Korrektur: NICHT audio-neutral —
  bei Lock skaliert die Notendichte jetzt für `lockedBPM` (gewollte „auf 132 zu hektisch"-Korrektur),
  NEEDS-FOUNDER-VERIFY.
- ▶ **M1-S2 (dieser Zyklus):** sichtbarer „Flow | Loop"-`.menu`-Picker in `CompositionHeaderStrip`
  (Freeze-safe Leaf, horizontaler Scroll = kein Layout-Risiko wie die kompakte Transport-Leiste).
  An `studio.lockBPM` gebunden (EINE Wahrheitsquelle, deckungsgleich mit dem TransportBar-Lock-Button).
  Bei →Loop seedet `lockedBPM` aus `transport.tempo` (nur im set-Closure gelesen, nie im body →
  Freeze-sicher), postet den bestehenden `"tempoLock"`-Recompose-Hook → `generate()` wendet Tempo
  (glideTempo + metronome) + den abgeleiteten Mode (S1) an. `+40` Zeilen, 1 Datei. Reviewer =
  ui-state (Freeze/@Environment/Binding). Founder-benannte Modi jetzt sichtbar+wählbar.
- **M1-S3 (optional):** die Loop-Seed-Logik ist bereits in S2 gefaltet; ein separater S3 nur, falls
  das Metronom/Glide bei GESTOPPTEM Umschalten am Gerät nicht sauber greift (dann Parität zum
  Lock-Button herstellen). Sonst entfällt S3.
