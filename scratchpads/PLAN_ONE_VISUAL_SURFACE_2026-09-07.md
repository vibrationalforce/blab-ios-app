# PLAN — EINE Visual-Fläche (D1), gemessen am 2026-09-07

**Founder-Bitte, wörtlich:** *„aktuell gibt es fullscreen Mode das soll aber alles zu einem Ding
zusammen gefasst werden"* — plus *„kompakter und übersichtlicher"*.

**Die Entscheidungen stehen schon** in `scratchpads/AUDIT_VISUAL_2026-09-06.md` unter DECIDED
D1 · D2 · D7 · D9. Dieser Plan verhandelt sie NICHT neu. Er tut zwei Dinge: er **misst nach**,
was seit dem Audit passiert ist, und er schneidet den Rest in Ralph-Scheiben.

---

## 0. WAS SICH SEIT DEM AUDIT GEÄNDERT HAT — nachgemessen, nicht erinnert

⭐ **Der grösste Posten von Scheibe 1 ist bereits erledigt, und das Audit weiß es nicht.**
`git grep -n "SpectralDonutView(" -- Sources` liefert **ZWEI** Produktionsstellen:
`EchoelStudioView.swift:1566` (das Cover) und `FloatingVisualWindow.swift:789` (das Fenster,
seit #1043). Das Audit schreibt „the single `SpectralDonutView(` site in Sources" — das war am
2026-09-06 wahr und ist es nicht mehr. **Der Donut-Zweig ist portiert.**

⭐ **Die HIGH-Fundstelle zur Leiste ist zur Hälfte erledigt.** Das Audit sagt, im Vollbild werde
„the only LABELLED way out" abgeworfen. #1036 hat den `studioChip` im Abwurf-Rang ganz nach
hinten geschoben; sein eigener gemessener Vermerk sagt: der Chip fiel vorher in 10 von 12
Zuständen, heute in 1 (375 pt mit gleichzeitig laufender WAV- UND Video-Aufnahme). **Offen
bleibt die andere Hälfte: der Look-Slider fällt weiterhin auf JEDEM Telefon** — er steht an
erster Stelle der Abwurfliste.

⚠️ **Und eine Sache, die ich fast „repariert" hätte und die KORREKT ist.** `updateKeepAwake`
enthält das Vollbild-Fenster absichtlich nicht, mit der Begründung „die App startet kalt
hinein, das hieße immer wach". Ich habe geprüft, ob das stimmt, weil die
`@AppStorage`-Deklaration auf `.small` steht — und es stimmt: `WorkspaceView` sät bei JEDEM
Start `floatingVisualVisible = true` und `floatingSizeRaw = .fullscreen`, sobald
`FeatureFlags.instrumentHome` an ist, und dieser Schlüssel wird in `EchoelmusicApp.init()`
auf `true` registriert. **Der Kommentar hatte recht; die Deklarations-Default ist nur nicht
die ganze Geschichte.** (Genau deshalb widersprechen sich zwei Zeilen in
`ChromeBudgetFitsTests` scheinbar — Zeile 40 meint den EFFEKTIVEN Startzustand, Zeile 526 die
DEKLARATION. Beide sind in ihrem Kontext richtig.)

⛔ **Drei Prosa-Stellen sind durch #1043 und #747 abgelaufen** und gehören in die nächste
Scheibe, die sie berührt (#456): `VisualEnergy.swift:33` („on a doorless path" — der Donut hat
seit #747 eine Tür und seit #1043 eine zweite Fläche), `EchoelStudioView.swift:6558` („the
full-screen cover renders `SpectralDonutView`" — jetzt tun es zwei Flächen), und die
Audit-Zeile selbst, die hier oben korrigiert ist.

---

## 1. WAS DAS COVER HEUTE NOCH ALLEIN HAT — gemessen

| Sache | Stellen | Portierbar? |
|---|---|---|
| `StillShutterButton` | `EchoelStudioView.swift:1663`, EINE Stelle | ja — im Fenster hinter `windowSize.isFullscreen` |
| Tipp-aufs-Bild-blendet-Chrome-aus | `showVisualControls`, 4 Stellen (967 · 1584 · 1585 · 1598) | ja — als fenster-lokaler `@State` |
| `.statusBarHidden(true)` | Cover | Geräte-Blick, Founder-Frage offen |
| Keep-awake über `showVisual` | `updateKeepAwake` | siehe ⚠️ oben — **nicht** blind übernehmen |
| VJ-Overlay-Panel | `visualVJOverlay` | wird gelöscht, nicht portiert (D2: EINE Definition) |
| Donut-Renderer | ~~cover-only~~ | **schon portiert (#1043)** |

`showVisual` hat genau EINEN echten Schreiber (`EchoelStudioView.swift:5180`, die
„Full screen"-Taste) und einen Zurücksetzer (`:1666`). Nach D1 wird der Schreiber ein
`visual.floating.size = .fullscreen`, und der Steckplatz fällt weg — Kette **14 → 13**, also
die SICHERE Richtung an der Metadaten-Decke.

---

## 2. SCHEIBEN — je eine Ralph-Runde, Wächter im SELBEN Commit (#456)

**S1 — Standbild-Auslöser ins Fenster.** `StillShutterButton` in die Fensterleiste, gegated
`if windowSize.isFullscreen` (wie Studio-Chip und Slider), damit der Klein-Karten-Boden
unberührt bleibt. Mitzuziehen: `TheStillSaysWhetherItWasSavedTests:97` und die Drei-Türen-Liste
`:124-131` sind PER DATEI auf `EchoelStudioView` gepinnt. Compile-prüfbar; wie es aussieht,
ist Gerät.

**S2 — Tipp-aufs-Bild.** `showVisualControls` als fenster-lokaler `@State`; im Fenster gilt
dieselbe Geste. Klein, keine Wächter bekannt.

**S3 — Cover löschen.** `.fullScreenCover(isPresented: $showVisual)`, `showVisual`,
`showVisualControls`, `visualShare`, `visualVJOverlay` weg; „Full screen" schreibt die Grösse.
Mitzuziehen: `ResetSoundClearsWhatTheLaunchLineReportsTests` dateiweit `== 16` (die Ketten-Zahl
`<= 14` bleibt bei 13 grün), `VisualFineTuneReflowsTests` Ansprüche 5/6/7, plus die drei
Prosa-Stellen aus §0. **Das ist die einzige unumkehrbare Scheibe** — davor Council.

**S4 — Leiste im Vollbild WICKELN statt abwerfen (D7).** Der Look-Slider fällt heute auf jedem
Telefon; im Vollbild soll nichts fallen. `ChromeBudgetFitsTests` ist der Wächter und muss die
neue Regel mitbekommen. **Vorsicht: hier gibt es keinen Renderer** — die Abwurf-Leiter ist reine
Arithmetik und damit prüfbar, das WICKELN ist Layout und nur am Gerät zu sehen.

**S5 — Gitter-Schalter bekommt eine Tür im Field-Panel (D5c).** Heute steckt das Ton-Gitter
hinter einem Abwurf-Rang-4-Glyph in der Fensterleiste, und die Fläche, um die die Bitte ging,
hat gar keinen Schalter dafür.

---

## 3. WAS NICHT IN DIESEN PASS GEHÖRT

D10 gilt: keine neuen Looks, keine Räumlichkeit, kein zweites `TouchInstrumentView`, **kein
neues Sheet**. Und die Founder-Fragen aus dem Audit (Erststart-Farbe, Statusleiste im Vollbild,
welche der 15 Erklärzeilen weg dürfen, Beamer wettergemischt oder roh) bleiben **offen** — sie
sind Geschmack oder Geräte-Blick, nicht Messung. Nicht einseitig entscheiden.

⚠️ **Eine neue Founder-Frage aus §0:** das Vollbild-Visual ist der ERSTE Bildschirm, und der
Bildschirm schläft dort ein, wenn nicht gespielt wird — genau im kontemplativen Fall, den
Ship-Gate 4 nennt. Immer-wach wäre ein echter Akku-Rückschritt (es ist der Startzustand). Das
ist eine Produktentscheidung, keine Messung.
