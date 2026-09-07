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

**S1 — Standbild-Auslöser ins Fenster. ✅ AUSGELIEFERT als #1063 (`6316dcbf`)** — mit zwei
Korrekturen an diesem Absatz, beide gemessen:

⛔ **Die „Mitzuziehen"-Zeile war falsch zugeordnet.** `TheStillSaysWhetherItWasSavedTests:97`
verlangt nur, dass `EchoelStudioView` den Knopf ÜBERHAUPT montiert; die Drei-Türen-Liste
`:124-131` gehört zu einer ANDEREN Datei (`TheTakeSaysWhetherItWasWrittenTests`, Anspruch 5,
und sie zählt `TakeOutcomeLine`, nicht den Auslöser). Es war also nie ein VERSCHIEBEN nötig.
Ausgeliefert ist deshalb ein reines HINZUFÜGEN: beide Flächen montieren den Auslöser, solange
das Cover lebt — EIN Standbild mit zwei Bedienstellen an EINEM `VisualRecorder`, die Form der
REC-Taste seit #747. Die Cover-Kopie geht mit dem Cover (S3).

⛔ **„Portierbar: ja, eine Stelle" hat die BREITE nicht gemessen, und die entschied den
Entwurf.** `chromeFit` meldet im Vollbild-Balken auf einem 375-pt-Telefon **0 pt Schlupf**
(18 pt auf 393). Der Blattknopf trägt seinen Antwortsatz IM selben `HStack` — dort wäre er auf
nichts zusammengedrückt worden, also genau die Stille, gegen die #986 existiert. `StillShutterButton`
hat deshalb `AnswerPlacement` bekommen: `.beside` (Zeile ohne Budget) und `.below` (ein
`overlay`, das keine Layout-Breite beansprucht). EIN Blatt besitzt weiterhin Tipp UND Antwort.

**Abwurf-Rang:** nach dem Gitter-Schalter, VOR der leeren Video-Taste — beide sind
Aufnahme-TÜREN, und ein Standbild ist ein Einzelbild eines Bildes, das noch da ist, während
einer Video-Aufnahme die verpassten Sekunden fehlen. Gemessene Abwurf-Menge: die vier
`wavBusy`-Zustände auf 375 und 393 pt (der angepinnte WAV-Stopp reserviert 104 pt). Wächter:
`ChromeBudgetFitsTests.testTheStillShutterSurvivesWhereTheStillIsTaken`.

**S2 — Tipp-aufs-Bild. ⛔ GESTRICHEN, nachgemessen 2026-09-07 — die Geste hat im
verschmolzenen Fenster keinen Platz und trüge nichts mehr.** Zwei Messungen, beide gegen
den Quelltext:

1. **Im Fenster ist das Bild die SPIELFLÄCHE, in jeder Grösse.** `FloatingVisualWindow`
   legt `TouchInstrumentView` als `.overlay` über die Bild-Ebene (`:838`) — ein Tipp dort
   ist eine NOTE. Im Cover liegt statt dessen ein `Color.clear` mit `onTapGesture` über
   dem Visual (`EchoelStudioView.swift:1582`), also eine Fläche, die es im Fenster gar
   nicht gibt. Die Geste zu portieren hiesse, dem Instrument Anschläge wegzunehmen.
2. **Was sie schaltet, wird ohnehin gelöscht.** `showVisualControls` blendet genau EINE
   Sache ein und aus: `visualVJOverlay`. D2 sagt „EINE Definition" und löscht das
   VJ-Panel in S3 — der Schalter verlöre also sein Objekt, auch wenn die Geste ginge.

**Es geht nichts verloren, was D2 nicht schon entschieden hat.** Bleibt „sauberes Bild
für Projektion" gewünscht, ist das ein NEUES kleines Feature mit SICHTBARER Bedienstelle
(WCAG 2.2 — der Cover-Kommentar sagt das an derselben Stelle selbst) und eine
Founder-Geschmacksfrage, kein Port. Nicht einseitig gebaut.

**S3a — DER DONUT-SCHALTER BRAUCHT ZUERST EINE TÜR. ✅ AUSGELIEFERT als #1065 (`a2af8345`).**
⛔ Gemessen 2026-09-07; ohne diese Scheibe wäre S3 ein Rückschritt gewesen. `git grep -n "spectralDonuts.toggle()\|spectralDonuts ="
-- Sources` liefert die ganze Wahrheit: der EINZIGE Schreiber, der `true` erzeugen kann, ist
`EchoelStudioView.swift:1620` — der Knopf in der Kopfleiste DES COVERS. `lookScrub`s Setter
(`:6024`) schreibt nur `false`, und `FloatingVisualWindow:188` LIEST nur. Das Cover zu löschen
hiesse also: ein Merkmal, das nichts mehr einschalten kann — genau der #227-Defekt, den diese
Datei an vier Stellen beschreibt, und die Tombstone bei `:6034` sagt es selbst („#747 gab
`showVisual` einen Setter … damit ist der Donut-Umschalter des Covers erreichbar"). Der
Donut-Renderer, den #1043 gerade ins Fenster portiert hat, wäre wieder unerreichbar, und der
gelöschte `normaliseUnreachableDonutMode()` müsste zurückkommen.

**Scheibe:** ein zweiter `Toggle` neben dem Gitter-Schalter aus #1064, am Ende der
„Look"-Gruppe. Beide sind „was man sieht", beide sind Schalter, sie lesen sich als Paar.

**Weitere S3-Messungen, damit der Council Tatsachen hat statt einer Plan-Zusammenfassung:**
· `visualVJOverlay` besteht bis auf EINE Zeile aus geteilten Definitionen (`groupHeader`,
`visualLookStrip`, `visualPresetRow`, `visualAdjustFields` — alle auch im Field-Panel). Das
einzige EIGENE ist die AirPlay-Zeile („Project: mirror to a screen via AirPlay"), also der
einzige Wegweiser zur Projektion — **die muss mit umziehen, sonst ist sie weg.**
· `visualShare` (`:1633` setzen, `:1709` präsentieren) ist der SOFORT-Teilen-Weg nach einer
Aufnahme im Cover. Die Aufnahme bleibt teilbar (`videoPanel` → `VideoLibraryPanelContent`,
mp4-Share), aber nicht mehr unmittelbar — kleiner, benennbarer Verlust.
· `updateKeepAwake` liest `showVisual` (`:6240`). Nach S3 hält **kein** Vollbild-Visual den
Schirm mehr wach — das Vollbild-FENSTER steht dort absichtlich nicht drin, weil die App
hineinstartet. **Damit wird die offene Founder-Frage (Ship-Gate 4, kontemplativ) von „später"
zu „mit dieser Scheibe zu beantworten".**
· `floatingSizeRaw` ist in `WorkspaceView` deklariert, nicht in `EchoelStudioView`, und dort als
ROHER String `"visual.floating.size"` statt über `StudioDefaultKeys`. Der „Full screen"-Knopf
braucht also eine eigene `@AppStorage` — und die sollte den Konstanten-Weg nehmen.

**S3c — Cover löschen. ✅ AUSGELIEFERT als #1069 (`8577ff6b`).** Gelöscht: der Cover samt
~139 Zeilen · `showVisual` · `showVisualControls` · `visualShare` + sein genestetes
`.sheet(item:)` · `visualVJOverlay` (~53) · der `.onChange(of: showVisual)`-GPU-Handler (~32) ·
`floatingWasVisible`. **Gemessen statt geschätzt:** Präsentations-Modifier dateiweit 16 → 14,
Rumpf-Kette 14 → 13, beides mit dem Prädikat des Wächters selbst nachgerechnet.
Die AirPlay-Zeile ist ins Field-Panel („Look") umgezogen — im selben Commit, wie §1 verlangt.
Keep-awake nach §5 als KONJUNKTION. Nicht portiert und bewusst so benannt: `.statusBarHidden`
(Founder-Blick) und die Tipp-aufs-Bild-Geste (WCAG 2.2). Benannter Verlust: SOFORT-Teilen nach
der Aufnahme.

⭐ **§4 HAT SICH BEZAHLT GEMACHT, und zwar an einer Stelle, die dieser Plan NICHT vorhergesagt
hatte.** Die Liste „Wächter mitzuziehen" nannte sechs Dateien; das `git grep` über das GANZE
blockierende Bundle nach jeder entfernten Schreibweise fand eine SIEBTE —
`TheStillSaysWhetherItWasSavedTests` Anspruch 4 verlangte, dass `EchoelStudioView` den
`StillShutterButton` montiert, und genau diese Montagestelle lag IM Cover. Sie wäre auf einem
KORREKTEN Baum rot gewesen, im blockierenden Bundle, unsichtbar (CI/CD meldet auf jedem Push
`failure`). Dritte Aufzeichnung dieser Form in diesem Repo (#650, #960).
**Lehre für die nächste Löschung: eine im Plan aufgeschriebene Wächter-Liste ist eine
Erinnerung, kein Inventar — der `grep` ist das Inventar.**

⛔ **Die ursprüngliche S3-Zeile stand so:** `.fullScreenCover(isPresented: $showVisual)`, `showVisual`,
`showVisualControls`, `visualShare`, `visualVJOverlay` weg; „Full screen" schreibt die Grösse.
Mitzuziehen: `ResetSoundClearsWhatTheLaunchLineReportsTests` dateiweit `== 16` (die Ketten-Zahl
`<= 14` bleibt bei 13 grün), `VisualFineTuneReflowsTests` Ansprüche 5/6/7, plus die drei
Prosa-Stellen aus §0. **Das ist die einzige unumkehrbare Scheibe** — davor Council.

**S4 — Leiste im Vollbild WICKELN statt abwerfen (D7).** Der Look-Slider fällt heute auf jedem
Telefon; im Vollbild soll nichts fallen. `ChromeBudgetFitsTests` ist der Wächter und muss die
neue Regel mitbekommen. **Vorsicht: hier gibt es keinen Renderer** — die Abwurf-Leiter ist reine
Arithmetik und damit prüfbar, das WICKELN ist Layout und nur am Gerät zu sehen.

**S5 — Gitter-Schalter bekommt eine Tür im Field-Panel (D5c). ✅ AUSGELIEFERT als #1064**
(`c3f0fb27`), vorgerückt, weil S2 gestrichen ist und diese Scheibe weder vom Cover noch von
einem Council abhängt. `Toggle("Note grid on the field")` am Ende der „Look"-Gruppe, INNERHALB
der bestehenden `Group` (der Kind-Zähler des Panels bleibt gleich — der Typprüfer-Grund, den
das Panel selbst nennt). EIN gespeicherter Schalter, zwei Bedienstellen: beide Ansichten binden
`StudioDefaultKeys.touchShowGrid`. Keine Erklärzeile darunter — der Satz ist ein
`accessibilityHint` und kostet keine Fläche. Wächter:
`TheNoteGridHasADoorWhereTheAskWasTests` (zwei Ansprüche, sieben Behauptungen, Gegengewicht:
der Fenster-Knopf steht noch). Heute steckt das Ton-Gitter
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

---

## 4. COUNCIL — darf das Cover weg? (2026-09-07, vor S3)

**Die Frage:** `.fullScreenCover(isPresented: $showVisual)` samt `showVisual`,
`showVisualControls`, `visualShare`, `visualVJOverlay` löschen und „Full screen" auf die
Fenstergrösse umschreiben. **Einzige unumkehrbare Scheibe dieses Passes.**

· **Architect:** proceed — es sind zwei Chromes über EINEM Renderer; die Kette fällt 14 → 13,
  also in die sichere Richtung an der Metadaten-Decke. Sorge: `floatingSizeRaw` liegt hinter
  einem ROHEN String; ein weiterer Leser wäre der Drift-Defekt, vor dem der #1065-Wächter
  gerade gewarnt hat.
  ⛔ **„an zwei Stellen" war meine Zahl und sie war falsch — es sind SECHS** (`WorkspaceView`,
  `FloatingVisualWindow`, VIER in `EchoelStudioView`s Aufnahme-Pfad). Ich hatte nur die zwei
  `@AppStorage`-Deklarationen gezählt und die programmatischen `UserDefaults`-Zugriffe
  übersehen — zwei davon stehen direkt unter einem Kommentar, der das Gegenteil behauptet
  („via the namespace (H15-KEYSTORE)"). Korrigiert mit #1066; die Rücknahme steht auch im
  Quelltext an genau der Stelle.
· **Skeptiker:** proceed-with-mitigation — die Löschung ist gross und nicht rückholbar, und ihr
  gefährlichster Teil ist NICHT der Code, sondern die Reihenfolge: solange „Full screen" noch
  ins Cover zeigt, ist der neue Weg unbewiesen. Sorge: ein Commit, der Weg UND Ziel gleichzeitig
  ändert, hat keinen Zustand, in dem man messen kann, welche Hälfte kaputt ist.
· **User-Advocate:** hold auf EINEN Punkt — `updateKeepAwake` liest `showVisual`. Nach der
  Löschung hält **kein** Vollbild-Visual mehr den Schirm wach, und genau das ist der
  kontemplative Fall aus Ship-Gate 4. Das Vollbild-FENSTER unbedingt dazuzunehmen wäre falsch
  (es ist der Startzustand → Dauer-Wach = echter Akku-Rückschritt). Das ist eine
  Founder-Entscheidung, keine Messung.
· **Shipper:** proceed, aber in ZWEI Commits — erst den neuen Weg live schalten, dann den toten
  Code löschen. „Erst umlegen, dann abreissen" ist hier billiger als beides zusammen, weil es
  keinen Compiler gibt, der die Löschung gegenprüft.
· **Aesthetic Maximalist:** proceed — EINE Fläche ist genau das, was die Bitte verlangt; das
  VJ-Overlay verliert bis auf die AirPlay-Zeile nichts, was das Field-Panel nicht schon hat.

**→ Empfehlung: proceed, in drei Schritten statt einem.**
1. **S3b-0 — ✅ AUSGELIEFERT als #1066 (`f74beea3`).** `visual.floating.size` hat jetzt
   `StudioDefaultKeys.floatingVisualSizeKey`; **alle SECHS** rohen Literale sind darauf
   migriert. Reine Hygiene, KEINE Verhaltensänderung. Der DEFAULT bleibt bewusst an jeder
   Deklaration (an `WindowSize.small` gekoppelt) — `Core/` kann das Enum nicht sehen, ein
   nacktes `0` dort wäre die Entkopplung, gegen die `WorkspaceView`s eigenes Doc argumentiert.
   Wächter: `TheWindowSizeKeyHasOneHomeTests`.
2. **S3b** — „Full screen" schreibt Grösse + Sichtbarkeit statt `showVisual = true`. Ab hier ist
   das Cover **unerreichbar, aber noch da** — der Zustand, in dem man den neuen Weg prüft.
3. **S3c** — das nachweislich tote Cover löschen, mit AirPlay-Zeile umgezogen und den zwei
   Wächtern (`ResetSoundClearsWhatTheLaunchLineReportsTests` dateiweit `== 16`,
   `VisualFineTuneReflowsTests` 5/6/7) im selben Commit.

**Gate: proceed-with-mitigation.** Die Mitigation ist die Dreiteilung. **Offen und dem Founder
gehörend bleibt genau EINE Frage** (nicht einseitig entschieden, blockiert S3b-0/S3b nicht):
soll das Vollbild-Visual den Schirm wach halten, wenn NICHT gespielt wird? Heute tut das Cover
es, nach S3c niemand. Akku gegen Kontemplation.

---

## 5. S3c — DIE KEEP-AWAKE-FRAGE IST KEINE FOUNDER-FRAGE MEHR (gemessen 2026-09-07, nach #1068)

Der Council (§4) hielt EINEN Punkt zurück: nach dem Löschen des Covers liest
`updateKeepAwake` ein `showVisual`, das es nicht mehr gibt, und der User-Advocate sagte,
das Vollbild-FENSTER unbedingt dazuzunehmen wäre falsch — **„es ist der Startzustand →
Dauer-Wach = echter Akku-Rückschritt"**. Das war die Begründung, mit der der Punkt an den
Founder ging.

⛔ **DIE PRÄMISSE IST HALB FALSCH, und sie stammt nicht aus dem Council, sondern aus einem
QUELLKOMMENTAR, den er zitiert hat.** `EchoelStudioView.swift:6308-6311` schreibt wörtlich,
das Vollbild des schwebenden Fensters sei etwas, „which the app COLD-LAUNCHES into, so it is
the default state". Gemessen:

| Schlüssel | Default | Befund |
|---|---|---|
| `visual.floating.visible` | `true` | das Fenster ist beim Erststart SICHTBAR — stimmt |
| `visual.floating.size` | `WindowSize.small.rawValue` | **KLEIN, nicht Vollbild** |

Also: bei einer frischen Installation startet die App in eine kleine Karte. Der Kommentar
ist trotzdem nicht grundlos — `@AppStorage` ist KLEBRIG: wer einmal „Full screen" tippt,
startet ab dann jedes Mal im Vollbild. **Der RISIKO-Satz stimmt, der MECHANISMUS-Satz nicht**
(Default gegen Persistenz), und der Unterschied entscheidet die Frage.

**Die Auflösung, die keine Geschmacksentscheidung braucht:** die Bedingung wird
KONJUNKTIV statt allein.

```
running || showMeditation || breathPacer.isRunning || isProjectingExternally
  || (Fenster ist Vollbild && cameraRPPG.isRunning)
```

Drei Eigenschaften, alle prüfbar:
1. **Weniger wach als HEUTE, nicht mehr.** Heute hält `showVisual` ALLEIN den Schirm wach —
   ein offenes Cover ohne irgendetwas Laufendes hält das Telefon bis zum Akkuende an. Die
   neue Form tut das nicht. Die Klebrigkeit ist damit unschädlich: ein persistiertes Vollbild
   mit ausgeschaltetem Biofeedback hält gar nichts.
2. **Ship-Gate 4 (kontemplativ) ist gedeckt** — genau der Fall „Vollbild, der Körper treibt
   das Bild, Transport steht" ist die Konjunktion, und nur er.
3. **Kein heißer Read.** `floatingSizeRaw` ist `@AppStorage` (kalt, ändert sich auf Tipp);
   `cameraRPPG.isRunning` kippt laut `EchoelStudioView.swift:5072` zweimal pro Sitzung und ist
   damit dieselbe Klasse wie das schon in `body` beobachtete `isProjectingExternally` (#1044).
   Das 10-Hz-Gesetz (10.76.41/50) bleibt unberührt — beobachtet wird die EIGENSCHAFT, nicht
   das Objekt.

**Bleibt Founder-Sache, aber als VERIFY statt als Frage:** fühlt sich „Bild wach nur solange
der Puls läuft" richtig an? Das ist ein Geräte-Blick, kein Blocker — und die neue Form ist in
JEDER Richtung konservativer als die alte, also gibt es keinen Zustand, in dem sie schlechter
ist als das, was heute ausgeliefert wird.

⛔ **KORREKTUR, EINE STUNDE SPÄTER UND VOR DEM NÄCHSTEN COMMIT (#1070): DIESER ABSCHNITT HAT
EINEN RICHTIGEN QUELLKOMMENTAR FÜR FALSCH ERKLÄRT.** Gemessen wurde der `@AppStorage`-DEFAULT
(`WindowSize.small`) und daraus auf den START-ZUSTAND geschlossen. Der Default stimmt und ist
belanglos: **`WorkspaceView.swift:331-334` schreibt bei jedem Start `floatingVisualVisible = true`
und `floatingSizeRaw = .fullscreen`** — der Instrument-Home-Seed, hinter
`FeatureFlags.instrumentHome`, das `EchoelmusicApp.init()` als `true` REGISTRIERT. Die App
startet also sehr wohl im Vollbild, und der Kommentar sagte das korrekt.

⚠️ **Die Lehre ist nicht „mehr messen":** ein DEFAULT ist kein ZUSTAND. Der billige Test wäre ein
`grep` nach den SCHREIBERN des Schlüssels gewesen, nicht ein Blick auf seine Deklaration —
dieselbe Form wie #546 (dort: den LESERN folgen statt den Schreibern), nur spiegelverkehrt.
Gefunden beim Lesen von `FloatingVisualLayout:385`, das denselben Satz führt und das ich
beinahe ebenfalls „korrigiert" hätte.

⭐ **DIE SCHLUSSFOLGERUNG ÜBERLEBT UND WIRD STÄRKER, der Code bleibt unverändert.** Wenn Vollbild
der START-Zustand ist statt eines klebrigen Ein-Tipp-Zustands, hielte ein alleinstehender Term
den Schirm bei JEDEM Nutzer ab dem ersten Frame wach — schlimmer als das, was die falsche
Rücknahme beschrieb. Die KONJUNKTION ist damit nicht Vorsicht, sondern die Bedingung dafür, dass
der Port überhaupt sicher ist.
