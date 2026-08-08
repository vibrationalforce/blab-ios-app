# PLAN #502 — „Usability und Kompaktheit im einheitlichen Design" (Founder-Screenshot 2494)

**Founder, 2026-08-08, zweiter roter Rahmen auf v10.79.377 (2494):**
> *„Den anderen rot umrandeten Bereich noch einmal auf Usability und kompactheit im
> einheitlichen Design intelligent anordnen und aufräumen"*

Der Rahmen umschließt ALLES zwischen Marken-Header und Panel-Inhalt. Ask 1 desselben
Screenshots ist #501 (geshippt, `3368976`).

---

## 1. WAS DA STEHT — gemessen, nicht geschätzt

Von oben nach unten, mit der Höhe, die jedes Band wirklich beansprucht:

| # | Band | Wo | Höhe | Grammatik |
|---|---|---|---|---|
| 1 | Marken-Header (`topBar`) | `WorkspaceView` | `minHeight: 50` | Marke · Loop-Anzeige · 3 Monitor-Kacheln |
| 2 | `CompositionHeaderStrip` — Genre · Key · Scale · Tonsystem · A4 | `WorkspaceView` | `minHeight: 40` | `labeled(caption) { Picker(.menu) }`, horizontal scrollend |
| 3 | `Divider()` | `WorkspaceView` | 1 | — |
| 4 | `startControlRow` Zeile 1 — ▶ · ⏸ · BPM+Schloss · Analyse-Pille | `EchoelStudioView` | 44 (`controlTapHeight`) | 64-breit prominent · 44 plain · 76+30 Feld+Schloss · gieriges Blatt |
| 5 | `quickActionRow` (Zeile 2) — Record · Keep last · MIDI · Save | dito | 32 (`controlHeight`) | 4× `EchoelIconTile(expands:)` |
| 6 | `quickDoorRow` (Zeile 3) — Open · Colabo · Learn + **Leerplatz** | dito | 32 | 3× `EchoelIconTile(expands:)` + `Spacer(minLength: 0)` |
| 7 | `menuBar` — 10 Chips, horizontal scrollend | dito | 44 | Pille in 44-pt-Tap-Rahmen |
| 8 | `menuPanelHost` → das gewählte Panel | dito | Rest | `EchoelPanel`-Karte |

**Arithmetik der Bänder 1–7** (also alles VOR dem Inhalt):
`startControlRow` = 44 + 8 + 32 + 8 + 32 = **124**, plus `.padding(.top, 4)` +
`.padding(.bottom, 10)` = **138**.
Summe: `50 + 40 + 1 + 138 + 44` = **273 pt**.

Auf einem iPhone 15 (852 pt, ~59 oben + ~34 unten sicher) bleiben ~759 pt nutzbar.
**273 von 759 = 36 % des Bildschirms sind Leisten, bevor Inhalt beginnt.** Das ist die
Zahl, auf die der Founder reagiert, und sie ist aus Konstanten gerechnet — keine Messung
eines gerenderten Layouts.

---

## 2. DER DEFEKT HAT EINEN NAMEN, UND ER IST NICHT „zu viel"

**VIER Bedien-Grammatiken in EINEM 273-pt-Band:**

1. **Kachel-Format** (`EchoelIconTile`) — Zeilen 2 + 3, plus die drei Header-Monitore. Das
   ist das EINE Format, das der Founder selbst bestellt hat (#481/#482: *„die sollen immer
   gleichgroß sein. Orientiere dich an denen oben rechts."*).
2. **Transport-Zeile** — vier verschiedene Formen nebeneinander (64 prominent · 44 plain ·
   76+30 Feld+Schloss · gieriges Analyse-Blatt). Jede einzeln founder-entschieden
   (#307 Ableton-Transport, #305 *„etwas größere Anzeige für Analyse"*, #455 Tempo-Feld).
3. **Chip-Leiste** — Pillen mit eigener Füllung + `borderStrong`.
4. **`CompositionHeaderStrip`** — `Text(caption).font(11).dim` + nacktes
   `Picker(.menu).tint(EchoelTheme.text)`. **Die EINZIGE Fläche in diesem Band ohne
   Füllung, ohne Rand, ohne Radius, ohne 44-pt-Tap-Boden.**

⭐ **Grammatik 4 ist die, die aus der Reihe fällt, und das ist prüfbar statt Geschmack:**
`EchoelIconTile`, die Header-Kacheln, `menuChip` und die Transport-Steuerelemente lesen
seit #481/#483 alle `EchoelTheme.controlHeight` / `controlTapHeight` / `radius` /
`borderStrong`. `CompositionHeaderStrip.labeled` liest **keine davon**. Sie ist die
Fläche, die 2026-07-14 gebaut wurde und an #481/#482/#483 nicht teilgenommen hat.

---

## 3. COUNCIL

**Frage:** Was ist die billigste Scheibe, die „Usability · Kompaktheit · einheitliches
Design · intelligent anordnen" wirklich bewegt, ohne eine Founder-Entscheidung
umzudrehen, die nicht umgedreht wurde?

· **Architect** — wiederverwenden statt neu bauen: `EchoelTheme.controlHeight` /
  `controlTapHeight` / `radius` / `borderStrong` existieren, und drei der vier Grammatiken
  benutzen sie schon. *Sorge:* die Transport-Zeile ist NICHT uneinheitlich aus
  Nachlässigkeit — jede ihrer vier Formen ist eine eigene Founder-Entscheidung. Sie zu
  „vereinheitlichen" wäre das Gegenteil von Gehorsam.

· **Shipper (Ralph)** — die größte Höhen-Ersparnis wäre ein ganzes Band. *Sorge:*
  **jedes einzelne Band in diesem Rahmen ist innerhalb der letzten acht Tage vom Founder
  bestellt worden** (#307 · #482 · #492 · #290 · 2026-07-14). „Aufräumen" kann nicht
  heißen, das Bestellte zu löschen. Also: Format vor Löschung.

· **Skeptic** — die naheliegende Kompaktions-Scheibe (Genre/Key/Scale hinter den
  Tempo-Chip) reißt genau die Entscheidung vom 2026-07-14 ein: *musikalische Identität
  „lebt HIER in der Chrome, immer sichtbar, eine dünne Zeile"*. Das ist eine
  Founder-Frage, keine Aufräumarbeit. **HOLD.**

· **User-Advocate** — der eine dokumentierte, UNBEZAHLTE Usability-Verlust liegt genau in
  diesem Rahmen und steht wörtlich im Quelltext (`quickActionRow`-Doc, #482):
  *„`exportLabel` … is rendered as text NOWHERE any more. So a sighted user mid-take sees
  only a glyph swap … That cost is real, it is NOT paid … Whether the row deserves a state
  line under it is a founder-visible layout call."* **Der Founder hat jetzt eine
  founder-sichtbare Layout-Entscheidung über genau diese Fläche getroffen** — und
  „Usability" ist sein erstes Wort. Der Posten ist damit fällig.

· **Vision-Keeper** — Uncodixfy: *„one border per object, not a border per stacked band"*
  und *„Nested panel types"* verboten. Vier gestapelte Bänder mit je eigener Füllung sind
  genau die Grammatik, die die Regel verbietet. Eine Fläche OHNE jede Behandlung neben
  drei MIT ist der schlimmere Fall.

· **DSP Purist** — nicht betroffen, außer dem Freeze-Gesetz: `CompositionHeaderStrip`
  hostet `Picker`s. Was immer dort passiert, darf keinen Hochfrequenz-`@Observable` in
  ihren Rumpf holen — sie liest `transport` heute schon ausdrücklich NUR im Setter einer
  Bindung, und das muss so bleiben.

→ **Empfehlung: Slice 1 = Grammatik 4 in das EINE Format holen.** Gate: **proceed.**
→ Kompaktion durch Band-Entfernung: **hold-for-founder** (Abschnitt 5).

---

## 4. SCHEIBEN (Reihenfolge, je eine pro Zyklus)

**Slice 1 — `CompositionHeaderStrip` bekommt das eine Format.**
Die drei Picker (+ Tonsystem, + A4) lesen `EchoelTheme.controlHeight` /
`controlTapHeight` / `radius` / `borderStrong` wie jedes andere Bedienelement des Bandes.
Kein Control verschwindet, keine Reihenfolge ändert sich, keine Founder-Entscheidung wird
angefasst. Wächter: das Format-Gesetz aus #481/#483 auf diese Datei ausdehnen.
⚠️ Grenze: `minHeight: 40` der Leiste wird zu `controlTapHeight`-tauglich — das kann die
Leiste um bis zu 4 pt WACHSEN lassen. Ehrlich zu nennen: Slice 1 ist Einheitlichkeit,
NICHT Kompaktheit.

**Slice 2 — der unbezahlte #482-Posten.**
`exportLabel` erreicht wieder den Schirm, aber NUR während ein Take läuft (`exporter`
beschäftigt), damit im Ruhezustand null Höhe entsteht. ⚠️ Zu prüfen VOR dem Bauen:
`LockCueDoesNotShoveTheControlsTests` (#382) — eine bedingt erscheinende Zeile in genau
diesem Stapel ist die Klasse, für die jener Wächter existiert. Wenn sie schiebt, ist die
Antwort ein reservierter Platz, kein Verzicht auf die Information.

**Slice 3 — der Leerplatz in `quickDoorRow`.**
Heute ein `Spacer(minLength: 0)`, dessen einziger Zweck ist, drei Kacheln so breit wie
vier zu machen. Kandidat: `Grid`/`GridRow` mit vier Spalten, damit die leere Zelle
STRUKTUR ist statt eines Füll-Tricks. Render-neutral, reine Code-Ehrlichkeit — deshalb
zuletzt und nicht zuerst.

**Slice 4 — Höhen-Feinschliff, gemessen.**
`startControlRow`s `.padding(.bottom, 10)` und die zwei 8-pt-`VStack`-Lücken sind
zusammen 26 pt. Ob davon etwas weg kann, ist eine Geräte-Sichtprobe und keine Arithmetik.

---

## 5. HOLD-FOR-FOUNDER (nicht eigenmächtig entscheiden)

**Die einzige echte Kompaktion wäre, ein Band zu entfernen — und das beste Ziel ist
`CompositionHeaderStrip` (40 pt + 1 pt Divider = 41 pt, 15 % des Vorspanns).**
Genre · Key · Scale · Tonsystem · A4 sind EINSTELL-Werte, keine Performance-Regler: einmal
gewählt, dann bleiben sie. Sie konkurrieren dauerhaft mit dem Transport um Bildschirm.

⛔ **Ich setze das NICHT um, weil es eine aufgeschriebene Founder-Entscheidung umkehrt.**
2026-07-14, im Quelltext von `WorkspaceView` zitiert: *„Unten die Leiste sollte längst
aufgelöst sein und sich an anderer Stelle wieder finden"* — und die Antwort darauf war
ausdrücklich, dass die musikalische Identität *„HIER in der Chrome, immer sichtbar, eine
dünne Zeile"* lebt. Sie hinter den Tempo-Chip zu räumen macht die App 41 pt kompakter und
bricht genau diesen Satz. Das ist die #490/#501-Lage — und dort lag eine ausdrückliche
neue Anweisung vor, hier nicht.

**Frage an den Founder, wenn er wieder da ist (NICHT jetzt eskalieren):** soll
Genre/Key/Scale sichtbar bleiben, oder darf es hinter den Tempo-Chip, der ohnehin
„Tempo and variations" heißt?

---

## 6. GESETZE, DIE JEDE SCHEIBE EINHÄLT

· Sheet-Kette wächst nicht (14 auf der Kette / 16 dateiweit, #479).
· Kein Hochfrequenz-`@Observable`-Read in `WorkspaceView.body`,
  `EchoelStudioView.body` oder irgendeinem Vorfahren (10.76.41/50).
· `EchoelValueField` für jeden numerischen Parameter; benannte Werte bleiben `Picker`.
· 44 pt Tap-Boden (#113), `EchoelTheme.radius`-Token (#483), ein Rand pro Objekt.
· Vor JEDER Flächenänderung: `git grep` in `Tests/CISmoke`, nicht nur `Sources/` (#456).
· Ehrliche Benotung jedes Wächters gegen BEIDE Bäume (#433), Grenzen zuerst.

---

## 7. NACHTRAG 2026-08-08 — WIE ES AUSGEGANGEN IST

**Slice 1 — GEBAUT** (`92e0021`). `CompositionHeaderStrip` trägt das eine Format.
Band 40 → 44 (+4 pt Höhe, ≈ +124 pt Scroll-Breite), beides im `labeled`-Doc beziffert.
Wächter: `Tests/CISmoke/TheHeaderStripWearsTheOneFormatTests.swift`.

**Slice 2 — ZURÜCKGEZOGEN MIT BELEG, und stattdessen ein echter Defekt behoben**
(`09a6f6b`). Die Prämisse war ein Quellkommentar aus #482: *„the bar count is gone from
the screen entirely"*. Der war schon rund eine Stunde nach dem Schreiben falsch — #456 hat
`TransportPositionView` aus der Chrome-Leiste geholt, #490 hat es in die Mitte des
Marken-Headers gesetzt, wo es `loop N/8` UNBEDINGT rendert, aus demselben persistierten
Schlüssel. Die Taktzahl war also längst bezahlt.
Die verbliebene, echte Hälfte (mitten im Take gibt es keine WORTE) ist **ENTSCHIEDEN, nicht
vertagt**: eine dauerhafte vierte Zeile gibt genau die Höhe aus, um die die Ask geht, und
eine BEDINGTE ist die #382-Klasse in genau dem Stapel, für den #382 geschrieben wurde — sie
fügt sich beim Start eines Takes ein und entfernt sich bei einem ENDE, das der Nutzer nicht
ausgelöst hat.
Was die Prüfung der Prämisse zutage förderte: `WorkspaceView` war die letzte handgeschriebene
Kopie von `"studio.loopBars"` + `.eight` (#416) — unter einem Kommentar, der einen Menschen
anwies, sie gleich zu halten. Genau der Mechanismus, den H15-LOOPBARS einmal ausgeliefert hat.
Jetzt `StudioDefaultKeys`. Wächter: `Tests/CISmoke/TheBarCountHasACarrierTests.swift`.

**Slice 3 (`Grid`/`GridRow` statt `Spacer`) — ZURÜCKGEZOGEN. Gate: HOLD.**
· Der Nutzen ist NULL für den Nutzer: der Plan nennt sie selbst „render-neutral, reine
  Code-Ehrlichkeit".
· Der Preis ist ein Wechsel der LAYOUT-ENGINE auf genau dem Band, das der Founder gerade
  markiert hat, in einer Umgebung ohne Compiler und ohne Renderer. Damit vier Spalten über
  BEIDE Zeilen wirklich gleich breit sind, müssten `quickActionRow` und `quickDoorRow` in
  EIN `Grid` fallen — also zwei benannte Eigenschaften zu einer verschmelzen, deren Trennung
  („handelt am Take" / „verlässt den Take") in beiden Docs tragend ist. Und die leere vierte
  Zelle braucht ein Füll-View, das breiten- aber nicht höhen-gierig ist — genau die Sorte
  SwiftUI-Detail, die hier niemand prüfen kann.
· Der Ist-Zustand ist NICHT unbelegt: `expands` teilt die Breite unter den flexiblen Kindern
  EINES `HStack` gleich auf, der `Spacer(minLength: 0)` ist damit bereits die vierte Spalte,
  er ist im Doc als LAYOUT-KONSTANTE begründet und von `TheDoorsAreIndividualButtonsTests`
  (#492) festgenagelt.
**Eine verifizierte, dokumentierte, bewachte Konstruktion gegen eine unverifizierbare zu
tauschen, um denselben Pixel zu erzeugen, ist keine Aufräumarbeit.**

**Slice 4 (Höhen-Feinschliff) — ZURÜCKGESTELLT, mit einem Grund, der beim Nachmessen
auftauchte.** Die 14 pt aus `.padding(.top, 4)` + `.padding(.bottom, 10)` sind NICHT frei:
beide Konstanten liegen in `FloatingVisualLayout` und ihre Summe ist `startButtonBlockHeight`,
also der Bodenabstand der angedockten Visual-Karte. #481 hat genau deshalb die Finger davon
gelassen. Wer hier 10 auf 6 setzt, verschiebt das BILD um 4 pt in einem Höhen-Commit.
Die zwei 8-pt-`VStack`-Lücken sind eine Geräte-Sichtprobe, keine Arithmetik.

**Abschnitt 5 (das ganze Band entfernen) bleibt HOLD-FOR-FOUNDER** — unverändert.

**Bilanz der Ask 2:** die „einheitliches Design"-Hälfte ist gebaut und bewacht. Die
„Kompaktheit"-Hälfte ist um 4 pt in die falsche Richtung gegangen, und die einzige Scheibe,
die sie wirklich bewegt (41 pt), kehrt eine aufgeschriebene Founder-Entscheidung um. Das ist
die Frage aus Abschnitt 5, und sie wartet auf ihn.
