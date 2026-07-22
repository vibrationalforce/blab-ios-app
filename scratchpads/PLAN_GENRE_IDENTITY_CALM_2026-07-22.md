# PLAN — Genre-Identität überlebt die Calm-Konvergenz (2026-07-22)

**Founder (2026-07-22, Video Build 2440 + Text):** „Da springt wieder was zurück
aber es ist jetzt auch nicht so richtig gut geworden … bei den Genres kommt erst
eine individuelle Variation und dann klingt plötzlich alles gleich."

Zwei verbundene Symptome, EINE Wurzel: **die Konvergenz-zu-Ruhe konvergiert auch
zu Generizität.** Genre-Identität lebt heute fast nur in Dimensionen, die die
Bio-Beruhigung ABBAUT — sobald der Körper ruhig/kohärent wird, fällt alles auf
denselben sparsamen, tonal-funktionalen Zustand zusammen.

## Verifizierte Wurzel (file:line)

1. **Harmonie-Wash (Haupttreiber).** `suggestJourney = true` ist DEFAULT-ON
   (`EchoelStudioView.swift:3745`). Ist er an, ersetzt `compose()`
   (`BioComposer.swift:1343–1350`) `prog` (Akkord-Wurzeln) durch
   `ChordSuggest.journey(length:in:key:coherence:register:seed:)` — **ohne
   Genre-Parameter** (`ChordSuggest.swift:312`). Damit wird der Genre-Zweig
   (`BioComposer.swift:1357–1402`, `baseProg = profile.progression` +
   Seed-Rotation + Turnaround) ÜBERSPRUNGEN. Die coherence-getriebene Auswahl
   (`selectIndex`) wählt bei HOHER Kohärenz „erwartete" = rein funktionale
   T→S→D→T-Bewegung → über alle Genres GLEICH.
   - Akkord-QUALITÄT überlebt (`profile.chordTones`, z. B. Jazz-Septimen,
     `BioComposer.swift:1407`) — aber die WURZELBEWEGUNG nicht.
2. **Geteilte Scales.** `MusicStyle.scale` (`MusicStyle.swift:484`) gibt jedem
   Genre eine Scale, aber VIELE teilen sie: phrygian = doom/heavyMetal/psytrance/
   sciFi/oriental; mixolydian = disco/rocknroll; dorian = dubTechno/earlySynth/
   jazz. Geteilte-Scale-Gruppe + genre-agnostische Journey + Ruhe-Funktionszyklus
   = identische Harmonie im Ruhezustand.
3. **Rhythmus-Boden zu subtil.** Archetyp-Kern (`fourOnFloorBeat` etc.) + #79
   `GenreFlavor` überleben den Calm-Strip (RNG-frei); nur die seeded Ornamente
   (`pOpen/pPerc`) strippen bei `spacious = calm > 0.7`. Cross-Archetyp bleibt
   distinkt; INNERHALB eines Archetyps trägt bei Ruhe nur der subtile #79-Flavor
   → zu wenig Identität.
4. **#77 nahm die Lead-Stimme.** `leadDensity = 0` überall (2026-07-20) → die
   genre-tragende Melodie/Timbre fehlt genau dann, wenn der Rhythmus dünn wird.

**Nordstern (NICHT schwächen):** Musik beruhigt sich mit steigender Kohärenz
(Entspannung durch generative Veränderung). Ziel: Ruhe = „ruhige Version DIESES
Genres", nicht „generisch ruhig".

## Design-Prinzip

Genre-Identität muss von Dimensionen getragen werden, die die Calm-Konvergenz
ÜBERLEBEN. Die Konvergenz-zu-Ruhe soll je Genre zu SEINEM eigenen Ruhe-Signaturbild
führen. Der stärkste ungenutzte Hebel: **die Harmonie genre-färben** (Wurzelbewegung),
weil sie heute komplett genre-agnostisch ist und die Kohärenz sie bei Ruhe
zusätzlich vereinheitlicht — Doppel-Konvergenz.

## Slices (Reihenfolge — Ralph Wiggum, 1 Ding/Zyklus, Determinismus-Vertrag)

Determinismus-Vertrag für JEDEN Slice: neutrale Genre-Farbe ⇒ byte-identisch;
keine Verschiebung bestehender RNG-Draw-Reihenfolge; alles bleibt in-key;
compose() bleibt pure/main-actor (kein Audio-Thread).

- **Slice 1 (Kandidat, wartet auf Design-Panel-Synthese wf_29bf774b-288):**
  Genre-gefärbte Journey — die coherence-getriebene Reise BEHÄLT ihre Bewegung
  (fixt die Monotonie/„springt zurück"), aber ihre Vokabular-/Ranking-Präferenz
  wird je Genre gebogen (z. B. Doom bevorzugt bVI/bVII/i-modal, Disco IV/V/vi
  hell, Jazz ii–V), sodass ein RUHIGES Doom ≠ ruhiges Disco ≠ ruhiges Jazz.
  Optionaler `genreColor`-Parameter an `ChordSuggest.journey`, Default = no-op
  (neutrale Farbe lässt die getesteten `ChordSuggestTests`-Gesetze byte-identisch).
  ALT./billiger: Crossfade in `compose()` — hohe Kohärenz lehnt zur genre-eigenen
  `baseProg` (stabil/charakteristisch), niedrige Kohärenz zur Journey (Exploration)
  — berührt ChordSuggest NICHT, nur die `prog`-Quellenwahl in BioComposer.
- **Slice 2:** Rhythmus-Identitätsboden — #79-`GenreFlavor` so stärken, dass eine
  genre-definierende Hat/Kick-Signatur den Calm-Strip überlebt (RNG-frei, additiv).
- **Slice 3:** Timbre-Boden — je Genre eine ruhige Pad/Bass-Farbe, die den Verlust
  der Lead-Stimme (#77) kompensiert.

## Beweistest (Kern-Invariante)

`BioComposerTests`: zwei Genres, die Scale UND Archetyp teilen (oder mind. Scale),
bei HOHER Kohärenz (calm ≈ 1) müssen weiterhin **unterscheidbare Harmonie-
Wurzelbewegung** (und/oder Drums) produzieren. Heute: identisch → Test ROT. Nach
Slice 1: distinkt → Test GRÜN. Plus Determinismus-Test: neutrale Farbe = byte-
identisch zum aktuellen Take (gleicher Seed).

## Council (inline)

- **Architect:** Harmonie ist der einzige heute komplett genre-agnostische Träger;
  Genre-Daten (progression/chordTones/scale) existieren schon → minimale neue
  Kopplung. Kein Fork der Journey; Farbe oben drauflegen.
- **DSP Purist:** compose() pure/main-actor. #79 hat bewiesen: genre-statische,
  RNG-freie Färbung ohne Determinismusbruch möglich. Änderung additiv/neutral-
  byte-identisch. `ChordSuggestTests`-Gesetze (Kadenz D→T top-1, Borrowed nie
  top-1) müssen halten ODER die Farbe darf sie nur innerhalb einer Funktionsklasse
  brechen.
- **Vision-Keeper:** Calm-Konvergenz NICHT schwächen — Ruhe = dieses Genre. On-vision.
- **Skeptic:** Risiko: Über-Färbung klingt „falsch" (Jazz-Septime auf Doom-Wurzel).
  Mitigation: konservative, je-Genre validierte Farbe; Beweistest gegen Regression
  der frischen #79-Distinctness.
- **Shipper:** Ein Slice, ≤3 Dateien, Reviewer Pflicht (dsp + code).

**Gate:** proceed-with-mitigation — Slice 1 nach Panel-Synthese festzurren, dann
implementieren + dsp-reviewer + code-reviewer + Determinismus-/Distinctness-Test.
