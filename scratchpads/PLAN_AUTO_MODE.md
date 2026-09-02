# PLAN — Optionaler Auto-Modus („der Vibe-Dirigent") — ENTWURF, Substrat-Aufklärung läuft

**Founder-Auftrag (2026-08-15, wörtlich):**
> „Wir brauchen einen optionalen automodus, der aufgrund des biofeedback's und Audio
> Visuellen Environments sich im interventionistischem Sinne auf die Stimmung einstellt
> und ggf. Sanft interveniert respektive den vibe catcht und harmonisiert, Kohärenz
> herstellen. Du hörst welches Genre, Tonsystem, mood, timbre, Rhythmus, Visuals etc.
> und Tonart gerade passt. Vermeide das es nicht passt. Sollten noch Komponenten fehlen
> füge sie hinzu. Ultraechoel"

**Interpretation (eine Zeile):** ein abschaltbarer Modus, der Körperzustand + aktuellen
musikalisch-visuellen Zustand liest, den Vibe schätzt und LANGSAM und SANFT die
genre-/tonart-/mood-/timbre-/rhythmus-/visual-Wahl nachführt, damit nichts gegeneinander
steht — Kohärenz im doppelten Sinn (HRV-Kohärenz des Körpers, Stimmigkeit des Outputs).

## Harte Leitplanken (stehen VOR jedem Entwurf fest)

1. **Optional heißt: eine erreichbare Tür, Default AUS.** Keine Maschine ohne Tür
   (ModulationEngine-/Audio-Lane-Lektion, CLAUDE.md Register-Einträge 5/6). Scheibe 1
   liefert Tür UND Kern zusammen.
2. **Tempo-Invariant T1/T2 unverletzt:** Tempo bewegt NUR der vorhandene Flow-Servo
   (kohärenz-gegated, geklammert, geglidet). Der Auto-Modus bekommt KEINEN neuen
   Tempo-Pfad; wenn er Tempo will, schaltet er höchstens in den Servo-Modus.
3. **Sanft = langsam + Hysterese + Nutzer gewinnt immer.** Interventionen in
   Takt-/Zehn-Sekunden-Raten, nie pro Frame; eine explizite Nutzer-Geste an einem
   Parameter pausiert die Auto-Steuerung dieses Parameters.
4. **Nur lebende Bio-Kanäle behaupten:** Kohärenz, HRV, HR, Atemphase. breathDepth und
   LF-HF haben KEINE Produzenten (#496). ⛔ **#980: `coherenceTrend` stand hier mit und hat
   seit #813 einen** — genau den, den dieser Punkt verlangte ("ein Trend braucht einen ECHTEN
   neuen Produzenten aus der Kohärenz-Historie"): `Core/CoherenceTrend`. Er bleibt trotzdem aus
   der Auto-Mode-Kopie, weil der Mood-Steer ihn nicht liest — und aus jeder anderen Kopie,
   solange keine Fläche ihn LESEN kann.
5. **Freeze-Gesetz + Sheet-Decke:** keine 10-Hz-Reads in Root/Ancestor-Bodies; kein
   neuer Präsentations-Modifier auf der EchoelStudioView-Kette (14/16 gepinnt).
6. **Copy science-first:** kein Wellness-/Therapie-/Esoterik-Vokabular. „Kohärenz" ist
   Messgröße, kein Heilsversprechen. Red line bleibt hart.
7. **Ralph-Scheiben, kein lokaler Compiler:** jede Scheibe mit CISmoke-Wächter,
   transkribiert gegen Eltern + Worktree; CI ist der einzige Compiler.

## ENTSCHIEDEN (Ultracode-Urteil wf_ce747087-6ca, 2026-08-15; Council: proceed)

**Gewinner: „AutoAttune" (Reuse-maximal), mit Grafts aus den zwei anderen Entwürfen.**
Kein neuer Motor: ein purer Werttyp (`Sequencer/AutoAttune.swift`), konsultiert an dem
EINEN Engpass, den jeder Take passiert (`makeComposerInput`) — die Kadenz ist damit
STRUKTURELL der Evolve-Tick (~25–45 s ≈ 8 Takte), es existiert kein Timer, der falsch
raten könnte (der AutoConductor-Entwurf hätte die #541-Immer-an-Maschinen-Form
wiederholt). Körperschätzung = `BioComposer.musicalState` WÖRTLICH wiederverwendet
(#416, keine zweite Formel). Eingriff = `WeatherMood.blend` auf die lokalen
Mood-Werte (darkness · liveliness · tension), Intensität fix 0.3, Ziel-Delta ≤ 0.15
→ max. 0.045 Bewegung pro Tick. Hysterese: Enter/Exit-Bänder ≥ 0.15 auseinander +
Mindesthalt 1 Tick. Darkness kreuzt nie den Composer-Schalter (>0.6). Tempo: NULL
eigener Pfad (T1/T2 — Flow-Servo bleibt allein; Abstinenz per Scan beweisbar, weil
es keine Engine-Datei gibt, in der ein setTempo sich verstecken könnte).

**Grafts:** Nutzer-Geste pausiert den Parameter für die RESTLICHE SESSION (kein
Auto-Resume nach ~2 min — „sanft" heißt: nichts kommt ungebeten zurück) · Tür ist
bei fehlender Bio-Quelle DISABLED mit Caption („kein lügendes Bedienelement",
#135/#164/#227) · Caption nennt NUR lebende Kanäle (#496; „trend" verboten, bis ein
echter Produzent shipped) · Status-Leaf („Listening/Steering/Paused …") als eigene
spätere Scheibe · Valence-Rote-Linie: calm/arousal sind STEUERSIGNALE, nie eine
Emotions-/Stimmungsaussage über den Menschen (EngineBus-EU-AI-Act-Rahmung).

**Scheiben-Folge:**
1. ✅ **#608 Scheibe 1 (dieser Commit):** Tür (AutoModeRow in bioPanel, #603-Form,
   0 Präsentations-Modifier) + `StudioDefaultKeys.autoMode` (Default AUS) + purer
   Kern `AutoAttune` + Fold in `makeComposerInput` (mit dem Hoist der
   `var moodForInput` über das `#if` — die vom Richter verifizierte
   Nicht-WeatherKit-Falle — und EINER Definition der HR/HRV-Fallback-Ketten) +
   Wächter `AutoModeStartsOffAndOwnsNoTempoTests` (37 Verdikte).
2. ✅ **#609 Visual-Beitrag (2026-08-15) — mit begründeter ABWEICHUNG vom Richter-
   Entwurf:** nicht in `weatheredVisuals` (das Fenster hat KEINEN EngineBus-Zugriff,
   und ein ~1-Hz-Read in seinem Body verstieße gegen genau die Freeze-Regel, die
   sein eigener TouchInstrumentView-Kommentar feiert), sondern im PUREN
   `BioVisualParams.from` — der schon verdrahteten Bio→Visual-Ader, flash-safe by
   construction. `autoAttuned:`-Flag als init-Parameter durchgefädelt (Fenster/
   Vollbild/Beamer lesen `studio.autoMode` per @AppStorage, event-rate). Auto-Term
   = kontinuierlich auf der Kohärenz-Achse, Kappe = `AutoAttune.maxTargetDelta`
   (EINE Definition): settled → ruhigere Figur (complexity−) + minimal voller
   (intensity+); unmeasured (coherenceForSound-Fallback 0.5) → exakt 0. pulseHz/
   hue/spread unangetastet (Epilepsie-Decke, physikalische Farbe, Atem-Achse).
   Wächter-Erweiterung: 11 neue Verdikte (Kappen, Identitäten, Richtung, Threading).
3. **Settling-Achse:** echter Kohärenz-Trend-Produzent (`CoherenceTrendEstimator`,
   Ring aus (timestamp, coherence), Slope 30–60 s, dt aus Timestamps, lücken-tolerant).
   `BioParams.coherenceTrend` bleibt dabei tot, außer die eigene Scheibe zieht
   `TheAlwaysOnBioPathIsNamedTests` + beide AlwaysOnBioChannel-Sätze + CLAUDE.md mit.
4. ✅ **Geste-gewinnt (#614/#614b + #615, 2026-08-16) — in ZWEI Hälften entschieden,
   nicht eine gebaut:** (4a, GEBAUT) die drei gesteuerten Mood-Dials tragen
   `pausing:` — committeter Edit bei Auto AN pausiert GENAU diesen Regler für die
   Rest-Session; ent-pausieren NUR über Auto-Toggle-AUS; drei `.automation`-
   Breadcrumbs, der Evolve-Breadcrumb im advanceEvolution-Gate (Werkzeug für die
   2519-Hörbarkeitsprobe); Caption macht die Pause auffindbar (#615). (4b, PER
   COUNCIL AUFGELÖST STATT GEBAUT — decisions.csv 2026-08-16): der Visual-Term
   bestreitet keinen nutzer-eigenen Regler (er moduliert die Bio-Basis, die
   Look-Regler komponieren unangetastet obendrauf — anders als Mood, wo der Steer
   den eben gesetzten Dial-Wert versetzt); ein Session-Flag hätte drei
   @AppStorage-lesende Flächen gebraucht (persistenz-falsche Semantik oder neuer
   Singleton für ein Bool). WIEDERERÖFFNEN nur auf die registrierte Geräteprobe:
   settled Body kämpft hörbar/sichtbar gegen bewusst tiefe Visual-Intensity.
5. **Genre/Tonart-Vorschlag (FOUNDER-GATED):** erst Suggest-only-Chip; Auto-Apply
   nur hinter zweitem Sub-Toggle, beschränkt auf `MusicStyle.offered` — kollidiert
   sonst mit dem Kurations-Gesetz (#81/#125).

**Geräteprobe (offen, registriert mit #608b):** Ist der konstante Steuer-Offset
(≤0.045 auf einem Mood-Regler) HÖRBAR, wenn der Körper klar settled/driving ist?
Der Steer kumuliert bewusst NICHT (nichts schreibt in die gespeicherte Mood zurück);
falls unhörbar, ist Scheibe-2-Kandidat ein in `State` getragener Slew — nicht eine
größere Konstante. Und: liest die Caption-Bedingung („when your body is clearly
settled or clearly driving") verständlich?

**Rote Flaggen aus dem Urteil (bindend):** kein Auto-Resume zurückschmuggeln ·
Status-Leaf liest den ~1-Hz-Zustand NUR im eigenen Leaf-Body (Freeze-Gesetz) ·
PerformerSignature-relative Arousal bleibt count-gated (sonst liest die erste
Minute jeder Session als Abweichung von einer bedeutungslosen Baseline).

## Verhältnis zum GUI-Board

Der Founder-Auftrag preemptet GUI-Board-Scheibe 5 (First-Run-Erklärzeile). Das Board
bleibt bestehen und wird danach/verzahnt fortgesetzt; nichts daraus ist gestrichen.
