# PLAN — Rhythmische Vielfalt, biofeedback-gesteuert (Task #79)

Founder 2026-07-21 (zweiter Teil derselben Nachricht wie #77): "Ansonsten ist
rhythmische Vielfalt bei allen Genres gefragt, die sich am Biofeedback
orientieren soll." Per Protokoll (wie schon bei "Automation in der Spur"):
ERST dieser Plan + Council-Gate, DANN Code-Zyklen. Kein Code in diesem Zyklus.

## 1. Ist-Zustand (verifiziert per Code-Read, nicht geraten)

`MusicStyle.beatArchetype` (MusicStyle.swift:222-233) ordnet jedes Genre EINEM
von 4 geteilten Skelett-Buildern in `BioComposer.swift` zu:

| Archetype    | Genres (Anzahl)                                              | Builder            |
|--------------|----------------------------------------------------------------|---------------------|
| `.fourOnFloor` | disco, eighties, earlySynth, futuristic, psytrance, synthwave (6) | `fourOnFloorBeat`  |
| `.backbeat`    | rock, punk, rocknroll, heavyMetal, jazz, oriental (6)         | `backbeatBeat`     |
| `.offbeat`     | ska, rocksteady, klezmer (3)                                  | `offbeatBeat`       |
| `.halfTime`    | doom, vaporwave, sciFi (3)                                    | `halfTimeBeat`      |
| `.signature`   | dubTechno, trap (2, je eigener Builder)                       | `dubBeat`/`trapBeat`|
| `.none`        | classical, esotericMeditation, selfObservation (3, drum-frei)  | –                   |

**18 von 23 Genres teilen sich eine von nur 4 Grundpattern-Skeletten.** Jeder
Builder nimmt bereits `energy` (aus Herzrate) und `calm`/`spacious` (aus
Kohärenz, `calm > 0.7`) — es gibt also SCHON Biofeedback-Einfluss, aber nur auf
**Dichte** (welche Zusatz-Hits/Fills dazukommen), nie auf die **Grundfigur**
selbst (Kick/Snare/Clap-Positionen sind für alle Genres im selben Archetype
IDENTISCH). Ergebnis: 6 sehr unterschiedliche Genres (Disco/80s/Früh-Synth/
Futuristic/Psytrance/Synthwave) klingen rhythmisch wie derselbe Loop mit
anderer Harmonie darüber — das ist exakt die Founder-Beobachtung.

`testEveryGenreHasADistinctMusicalIdentity` (MusicStyleTests.swift) prüft nur
das Quadrupel `scale|progression|chordTones|beatArchetype` — Genres MIT
gleichem `beatArchetype` bestehen den Test trotzdem, solange sich Skala/
Progression/Voicing unterscheiden. Der Test ist also kein Widerspruch zum
Befund, deckt aber die tatsächliche RHYTHMISCHE Wiederholung nicht ab.

## 2. Das Spannungsfeld

- Founder will **mehr Vielfalt pro Genre**, aber explizit **biofeedback-
  orientiert** — nicht 18 neue, hart-codierte, statische Patterns (das würde
  wieder in "klingen unprofessionell/generic" laufen, nur andersrum: zu viele
  Spezialfälle, schwer wartbar, schwer zu testen).
- Bestehendes Muster (die 4 Archetype-Builder) ist bewusst geteilte
  Infrastruktur — Duplizieren in 18 Kopien widerspricht "no premature
  abstraction" UMGEKEHRT: es würde 18 fast-identische Funktionen erzeugen.
- Die Rausch-Triad (BioEventGraph etc.) ist PROTECTED/read-only — jede neue
  Bio→Rhythmus-Kopplung muss auf den bestehenden Bio-Signalen aufsetzen
  (heartRateBPM/coherence/breathPhase/breathDepth/motion — bereits an
  `BioComposer.Input` vorhanden), keine neuen Sensor-Pfade nötig.

## 3. Vorschlag (zur Council-Prüfung, NICHT final)

**Slice A — Per-Genre "Flavor"-Overlay, nicht neue Skelette.** Jeder der 4
Archetype-Builder bekommt einen zusätzlichen, rein-funktionalen Parameter
`flavor: GenreFlavor` (ein kleiner Enum/Struct, z. B. `hatDensityBias`,
`percPlacementSeedOffset`, `kickPushEnabled`) — pro Genre EIN Flavor-Wert
(deklariert direkt neben `beatArchetype` in `MusicStyle.swift`, analog zu
`swing`/`leadPatchName`). Das hält die Skelett-Logik an EINER Stelle
(Architect-konform), macht aber jedes Genre hörbar unterscheidbar, ohne 18
Kopien zu schreiben.

**Slice B — Biofeedback bekommt mehr Einfluss als nur Ja/Nein-Dichte.** Heute
gated `energy`/`calm` nur binäre Zusatz-Hits. Vorschlag: `breathPhase` (schon
im Input, bisher nur für Melodie/Harmonie genutzt) verschiebt leicht die
Position EINES optionalen Zusatz-Hits pro Takt (z. B. der Open-Hat-Lift
wandert mit der Atemphase zwischen Step 12-15) — hörbar "lebendig", bleibt
deterministisch pro Seed+Bio-Snapshot, kein neuer Sensor.

**Slice C — Test + Council-Re-Check.** Neue Tests: (a) je zwei Genres im
selben Archetype dürfen NICHT mehr bit-identische `drumSteps` liefern (Flavor
macht sie hörbar verschieden), (b) Determinismus bleibt (gleicher Seed+Bio ⇒
gleicher Output), (c) bestehende `testFourOnFloorKicksEveryBeat`/
`testBackbeatSnareOnTwoAndFour` (BioComposerTests.swift) bleiben grün — die
KERN-Signatur pro Archetype darf sich nicht auflösen, nur die Details variieren.

## 4. Council (inline, fixed seats)

- **Architect:** Flavor-Parameter an den bestehenden 4 Buildern ist die
  richtige Form — vermeidet 18-Kopien-Duplikation, bleibt in `BioComposer.swift`
  gekoppelt. Sorge: `GenreFlavor` darf nicht zum Auffangbecken für beliebige
  Sonderfälle werden — hart auf 2-3 Felder begrenzen.
- **DSP Purist:** Kein Audio-Thread-Kontakt (`BioComposer.compose` läuft
  außerhalb des Render-Blocks, reine Werttypen) — unbedenklich. Rausch-Triad
  bleibt unberührt (nur Input-Werte gelesen, keine Änderung an deren Logik).
- **Shipper:** Zu groß für einen Zyklus — braucht mind. 3 Slices (A/B/C).
  Slice A allein (Flavor-Parameter + 1-2 Genres als Pilot, z. B. die
  6-fach-geteilte `.fourOnFloor`-Gruppe zuerst, da dort der Founder-O-Ton am
  konkretesten war: Psytrance war explizit genannt) ist der richtige erste
  Schnitt.
- **Skeptic:** Risiko: Flavor-Werte könnten zu subtil sein, um wirklich
  "Vielfalt" zu erzeugen, oder zu stark, um die Archetype-Identität (Res.
  bestehende Tests) zu sprengen. Mitigation: Slice C's Doppel-Test (verschieden
  UND signatur-treu) fängt beide Fehlrichtungen.
- **User-Advocate:** Founder nannte KEIN konkretes Genre-Paar als Beispiel —
  Ambiguität liegt nur im Umfang (alle 23 vs. Pilot), nicht im Konzept selbst.
  Ein Pilot auf der `.fourOnFloor`-Gruppe (6 Genres, deckt den genannten
  Psytrance-Fall ab) ist eine sichere, kleine erste Iteration, keine
  AskUserQuestion nötig.

**Verdikt: proceed, gestaffelt.** Nächster Zyklus (nicht dieser): Slice A auf
`.fourOnFloor` (6 Genres) als Pilot — `GenreFlavor`-Typ + Werte in
`MusicStyle.swift`, Verdrahtung in `fourOnFloorBeat`, Tests nach Muster 3(a/b),
Pflicht-Reviewer (dsp-reviewer, da BioComposer-Kernpfad). Bei Erfolg: Slice A
auf die übrigen 3 Archetypes ausrollen, dann Slice B.

## 5. Referenzen

- `Sources/Echoelmusic/Sequencer/MusicStyle.swift:222-233` (Archetype-Zuordnung)
- `Sources/Echoelmusic/Sequencer/BioComposer.swift:701-823` (die 4 geteilten Builder)
- `Tests/EchoelmusicTests/BioComposerTests.swift` (`testFourOnFloorKicksEveryBeat`,
  `testBackbeatSnareOnTwoAndFour` — Signatur-Anker, dürfen nicht brechen)
- `decisions.csv`: `task-rhythmic-diversity-biofeedback-deferred` (2026-07-21)
