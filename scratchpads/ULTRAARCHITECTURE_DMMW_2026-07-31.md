# ULTRAARCHITEKTUR + DEEP RESEARCH — „Würden wir die DMMW diesmal hinbekommen?"

**Founder-Frage, 2026-07-31 (wörtlich):** *„Die Frage ist vor allem ob wir die Baustellen
hinbekommen würden an denen wir das letzte Mal gescheitert sind. Die gesamte DMMW mit allen
Spuren, Automationen, Instrumenten, Effekt, AUv3 scannen, Routing etc. Ist das letzte Mal
komplett gescheitert obwohl der Auftrag war es auf höchstem Niveau zu machen um
wettbewerbsfähig zu sein mit großen Softwares die bereits auf dem Markt sind."*

**Status:** Analyse + Plan. **Nichts gebaut, nichts gelöscht, keine Entscheidung getroffen.**
Die Entscheidung gehört dem Founder; dieses Dokument legt die Belege vor.

---

## 0. Die kurze Antwort

**Ja — technisch. Nein — unter den Bedingungen, unter denen es letztes Mal lief.**

Und die zwei Befunde, die das begründen, widersprechen beide der Prämisse der Frage:

1. **Es ist nicht an den Baustellen gescheitert.** Sie waren zum überwiegenden Teil FERTIG.
   Gescheitert ist die *Richtungskonstanz*: zwischen 2026-04-18 und 2026-07-28 hat die
   Produktrichtung **18-mal** zwischen „Breite/DAW" und „Fokus/Instrument" gewechselt — der
   längste ununterbrochene Lauf in eine Richtung war **vier Wochen**. Belege in §1.
2. **Die DMMW ist nicht gelöscht.** Gelöscht wurden die *Türen* (Views). Die **Engine- und
   Modell-Schicht lebt vollständig** — Timeline, Clips, Automation, Lane-FX, Multitrack,
   Arrangement-Player. Ein Wiederaufbau wäre kein Neubau, sondern ein **Wiederanhängen**.
   Inventar in §2.

Daraus folgt: die Frage „schaffen wir die Baustellen?" ist die falsche Frage. Die richtige
lautet **„halten wir 6 Monate lang dieselbe Richtung, und können wir mehr Fläche VERIFIZIEREN
als wir bauen?"** — und dort, nicht im Code, lag der Fehlschlag.

---

## 1. Was wirklich gescheitert ist — Beweis aus dem eigenen Entscheidungslog

`decisions.csv`, 333 Zeilen, jede vom Founder oder in seinem Auftrag eingetragen. Gefiltert
nach Richtungsentscheidungen ergibt sich:

| # | Datum | Entscheidung | Richtung |
|---|---|---|---|
| 1 | 2026-04-18 | Live Studio Pivot — DAW + Streaming + Mastering | **BREITE** |
| 2 | 2026-04-26 | v10 Pivot: DAW + Video + RTMP | **BREITE** |
| 3 | 2026-05-22 | „the first bio-reactive performance instrument" | FOKUS |
| 4 | 2026-06-03 | Deep-Audit: bio-reaktives INSTRUMENT, pillar-by-pillar | FOKUS |
| 5 | 2026-06-12 | FOCUS: Video/RTMP/Multitrack streichen | FOKUS |
| 6 | 2026-06-18 | „stay the focused bio+VOICE instrument; do NOT become a general DAW/NLE" | FOKUS |
| 7 | 2026-06-20 | **„Pivot to all-in-one professional production suite"** (DAW + AUv3-Host + NLE + Broadcast + Mapping + Spatial) | **BREITE** |
| 8 | 2026-06-21 | IA-Pivot: Arrangement/Clips-Timeline ist HOME (pro-workstation) | **BREITE** |
| 9 | 2026-07-01 | DAW-look reorg über WorkspaceView-Surfaces | **BREITE** |
| 10 | 2026-07-02 | Refocus auf calm shell, DAW hinter eine Studio-Tür | FOKUS |
| 11 | 2026-07-02 | *(gleicher Tag)* Eskalation: EINE adaptive Ansicht, Tab-Bar + Studio-Tür weg | FOKUS |
| 12 | 2026-07-06 | RE-FOCUS, supersedet den Shell-Flip vom selben Tag | FOKUS |
| 13 | 2026-07-10 | **FOUNDER-OVERRIDE: EINE Hauptansicht JETZT — Timeline über Instrument-Zone, Ableton-Arrangement-Layout** | **BREITE** |
| 14 | 2026-07-12 | DMMW-Shell v3 + **TESTFLIGHT-FREEZE bis DMMW Profi-Level** | **BREITE** |
| 15 | 2026-07-22 | App-HOME kippt auf das lebende Instrument | FOKUS |
| 16 | 2026-07-24 | **REINES INSTRUMENT — DAW + Video-Schnitt + AUv3 fliegen komplett** | FOKUS |
| 17 | 2026-07-25 | DMMW retired; ONE product; Grenze Editor ≠ Workstation | FOKUS |
| 18 | 2026-07-28 | All-in-one-Suite-Pivot (Nr. 7) als superseded markiert | FOKUS |
| **19** | **2026-07-31** | **diese Frage** | **BREITE?** |

### Die drei Zahlen, auf die es ankommt

- **Zwei Tage.** Zwischen Nr. 6 („do NOT become a general DAW/NLE", 06-18) und Nr. 7
  („all-in-one professional production suite", 06-20) liegen **zwei Tage**.
- **Zwölf Tage.** Zwischen Nr. 14 („TestFlight-Freeze bis die DMMW Profi-Level hat", 07-12)
  und Nr. 16 („DAW + Video-Schnitt + AUv3 fliegen komplett", 07-24) liegen **zwölf Tage**.
  Die DMMW hatte also für den Auftrag „auf höchstem Niveau, wettbewerbsfähig" faktisch
  **zwölf Tage** ununterbrochenen Rückenwinds.
- **Fünf.** Der Deep-Audit vom **2026-06-03** hielt schon damals fest, wörtlich:
  *„History shows breadth-first caused **5 oscillations** + shipped no breadth."*
  Das war vor Nr. 7–14. Es sind seitdem noch einmal so viele geworden.

### Und der Wettbewerbs-Teil war bereits beantwortet — vom Founder selbst

`decisions.csv`, **2026-05-22**, Begründungsfeld wörtlich:

> *„Owner competitive analysis vs Loopy Pro/Bitwig/TouchDesigner showed **we cannot win on DAW
> maturity/plugins/visuals solo**; biofeedback-as-first-class-bus-modulation is the only
> defensible axis … concede other axes deliberately."*

Die Frage „sind wir wettbewerbsfähig mit den großen Softwares" wurde also vor **zehn Wochen**
mit einer eigenen Konkurrenzanalyse gestellt und mit **Nein — und das ist Absicht**
beantwortet. Nr. 7 (06-20) hat diese Antwort ohne neue Belege überschrieben. Das ist der
Moment, an dem die DMMW zum zweiten Mal begann.

**Das ist die ehrlichste Antwort auf „woran sind wir gescheitert":** nicht an Spuren,
Automationen oder AUv3. An der Tatsache, dass eine Entscheidung, die eine Konkurrenzanalyse
gekostet hat, 29 Tage später ohne Gegenbeleg gekippt wurde — und dann noch fünfmal.

---

## 2. Der Befund, der die Kostenrechnung umdreht: die DMMW ist NICHT weg

`#121` hat die **Oberflächen** entfernt, nicht die Maschine. Gemessen (`git grep -l … --
'Sources/**/*.swift'`, 2026-07-31):

| Baustein | Dateien, die ihn referenzieren | Zustand |
|---|---|---|
| `Timeline` (Modell) | **61** | lebt |
| `ClipStore` | 17 | lebt |
| `LaneVoiceRack` | 17 | lebt |
| `AutomationLane` | 13 | lebt |
| `TrackFX` | 11 | lebt |
| `TimelineStore` (inkl. Undo/Redo) | 9 | lebt |
| `MultiRollFanout` | 7 | lebt |
| `ArrangementStore` | 6 | lebt |
| `AudioLanePlayer` | 6 | lebt |
| `MultiTrackRecorder` | 6 | lebt, flag-gated AUS, türlos |

Dazu im `Sequencer/` (76 Dateien): `ArrangementPlayer`, `ClipLaunchEngine`, `AudioClipPlayer`,
`AudioClipRegion`, `AudioRegionPlayback`, `AutomationGestureRecorder`, `AutomationCanvasMath`,
`BioAutomationRecorder`, `ClipAutomationEdit`, `LaneLaunchLatch`, `KindVoiceAllocator`,
`LaneComposerInput`.

**Gelöscht sind:** `ClipView` (807dc0d), `ArrangeTimelineView` (eb58e7a), `ChannelRackView`,
`BrowserView`, `SampleBrowserView`, die Drum-Stimmen, der Video-Schnitt — und **das AUv3-Target
komplett** (`Sources/` hat heute nur noch `Echoelmusic`, `EchoelmusicWatch`,
`EchoelmusicWidgets`; kein `AVAudioUnitComponent`-Host-Code mehr).

### ⚠️ DIE DRINGENDSTE SACHE IN DIESEM DOKUMENT

**Task #132 Slice 5 „DAW-Model-Removal" steht offen — und würde genau diese Schicht löschen.**
Solange sie nicht ausgeführt ist, kostet eine DMMW-Rückkehr Wochen. Danach kostet sie Monate.

→ **Diese eine Entscheidung ist zeitkritisch und keine andere.** Entweder #132 Slice 5 wird
formal auf HOLD gesetzt, bis die DMMW-Frage entschieden ist — oder die Rückkehroption wird
bewusst weggeworfen. Beides ist vertretbar; unbewusst passieren darf es nicht.

---

## 3. Was ein Wiederaufbau WIRKLICH kostet (belegt, nicht geschätzt)

`Sources/` = **96.471 Zeilen Swift**, 333 Dateien. Die DMMW-Maschine steckt bereits darin.

| Baustelle | Realer Aufwand | Begründung |
|---|---|---|
| **Spuren / Timeline-UI** | mittel | Modell + Player + Undo/Redo + Automations-Canvas existieren. Es fehlt die View. Aber: sie muss **adaptiv** sein (#292) und darf die Modal-Kette nicht wachsen lassen. |
| **Automationen** | klein | `AutomationLane`, `AutomationCanvasMath`, `AutomationGestureRecorder`, `BioAutomationRecorder` sind gebaut und getestet. Reine Tür-Arbeit. |
| **Instrumente pro Spur** | klein–mittel | `LaneVoiceRack` + `MultiRollFanout` + `KindVoiceAllocator` leben. Offen ist die Patch-AUTORISIERUNG pro Spur (Task #23, Council-Frage schon gestellt). |
| **Effekte pro Spur** | klein | `TrackFX` lebt mit defensivem Decoder (#189 Slice 4). |
| **Multitrack-Recording** | klein | `MultiTrackRecorder` ist gebaut und wird konstruiert — nur `FeatureFlags.audioLaneRecording` wird nie registriert (#204). Ein Flag + eine Tür. |
| **Routing / Patchbay** | **fertig** | `PatchbayView` ist seit dem 2026-07-12-Batch wieder erreichbar. |
| **AUv3 als Target (Echoel IN Ableton)** | **groß** | Target gelöscht. Und der harte Teil ist nicht der Build: **die Bio-Quelle trägt der Appex-Sandbox schlecht.** Kamera-rPPG/HealthKit/BLE im Plug-in-Prozess = im besten Fall umständlich. Ein Echoel-AUv3 ohne Körper ist ein mittelmäßiger Synth in einem Markt voller sehr guter Synths. Der Ausweg ist die **App-Group-Brücke** (App misst → Plug-in klingt) — dieselbe Brücke, die die Watch seit Monaten als „C7" offen hat. |
| **AUv3 SCANNEN (fremde Plug-ins hosten)** | groß + entschieden | `#190` hat das am 2026-07-xx **abgelehnt**, mit der Begründung, die Bedingung des Founders sei nicht erfüllt. Technisch war es gebaut (#50, #75, #76: 3-Kategorien-Browser, One-Tap-Zuweisung, Eventide end-to-end) und wurde in #121 Slice 2 entfernt. |

**Ehrliche Gesamteinschätzung:** 60–70 % der DMMW ist Tür-Arbeit auf lebender Maschine.
30–40 % (AUv3-Target + Host-Scanning + Video-Schnitt) ist echter Neubau.

---

## 4. Deep Market Research — kann das gegen die Großen bestehen?

### 4.1 Die Ehrlichkeit zuerst

Auf der Achse, die der Founder nennt („wettbewerbsfähig mit den großen Softwares"), lautet die
Antwort **nein, und zwar aus Struktur, nicht aus Können**:

- **Ableton Live** — ~25 Jahre, dreistelliges Entwicklerteam, das Clip-Launching-Paradigma
  selbst erfunden.
- **Logic Pro** — Apple, kostenlos gebündelte Instrumentenbibliothek im Gigabyte-Bereich,
  59,99 € auf iPad.
- **FL Studio Mobile / BandLab / GarageBand** — Preis 0–15 €, Millionen Nutzer,
  Netzwerkeffekte über Sample-Packs und Communities.
- **Auf iOS speziell:** AUM, Loopy Pro, Drambo, Koala. Alle von 1–3 Personen, alle **radikal
  ein-paradigmatisch** (AUM = Mixer/Host. Loopy Pro = Looper. Drambo = modular. Koala =
  Sampler). Keine einzige erfolgreiche iOS-Musik-App ist ein Allrounder. **Das ist kein
  Zufall — es ist die einzige Form, in der ein kleines Team dort gewinnt.**

Ein Solo-Entwickler, der Spuren + Automation + Mixer + Video + Host + Broadcast gleichzeitig
auf Profi-Niveau halten will, konkurriert nicht mit einem Produkt, sondern mit **sechs
Produktteams gleichzeitig**. Das ist exakt, was `decisions.csv` am 2026-05-22 festgehalten hat.

### 4.2 Wo es tatsächlich unbesetzten Raum gibt

Die Marktlücke ist im Log ebenfalls schon benannt (2026-06-12, mit vier zitierten
Recherchesträngen): **Echtzeit-Physiologie → spielbarer Synth → offene Ausgabestandards
(OSC · ADM-OSC · Art-Net · sACN · MIDI 2.0)** hat *keinen kommerziellen Besetzer*.

- Biofeedback-Musik-Apps existieren, aber als **Wellness** (Endel, Brain.fm) — geschlossen,
  generativ-nur, keine Bühnen-Ausgabe, kein Performer-Anspruch.
- Immersive-Audio-Werkzeuge (L-ISA, d&b Soundscape, SpatGRIS) sind **Renderer** und warten auf
  **Objektquellen**. Echoel als bio-getriebene ADM-OSC-Objektquelle hat dort keinen Konkurrenten.
- Show-Control (Art-Net/sACN) ist reines UDP → passt zur Null-Abhängigkeits-Doktrin.

**Das ist verteidigbar, weil es niemand sonst tut — nicht weil es besser gemacht ist.** Ein
DAW-Feature ist immer vergleichbar und damit immer verlierbar. Eine Körper-getriebene
Objektquelle ist **unvergleichbar**.

### 4.3 Der Markt-Grund, der gegen die DMMW spricht — und der, der dafür spricht

**Dagegen:** Ein Käufer, der „DAW auf dem iPhone" will, kauft die App, findet 70 % von Ableton
und ist enttäuscht. Ein Käufer, der „mein Puls spielt Musik und steuert den Raum" will, findet
nichts Vergleichbares und ist begeistert. Dieselbe App, zwei Erwartungsrahmen — und der erste
erzeugt 1-Stern-Rezensionen für Features, die *funktionieren*, nur nicht auf Ableton-Niveau.

**Dafür (und das ist ein echtes Argument, nicht Höflichkeit):** Ohne Spuren gibt es keinen
*Übergabepunkt* an die Profis, die das Instrument nutzen sollen. Die Grenze
„Editor ≠ Workstation" aus `PRODUCT_DEFINITION.md` löst das aber bereits **ohne DMMW**: der
Übergabepunkt heißt **MIDI-Export, WAV/Stem-Export, MIDI-Clock/Link, OSC** — nicht
„eigene Arrangement-Ansicht". Man liefert an Ableton, statt Ableton nachzubauen.

---

## 5. Deep Research „Develop System" — warum es scheiterte und was es bräuchte

Das ist der Teil, den ich für den wichtigsten halte, weil er unabhängig von der
DMMW-Entscheidung gilt.

### 5.1 Der eigentliche Engpass ist Verifikations-Bandbreite, nicht Bau-Bandbreite

Fakten dieses Setups:

- **Kein lokaler Swift-Compiler.** Der einzige Compiler ist CI. Jeder Fehler kostet einen
  Zyklus statt einer Sekunde.
- **Kein automatisierter Gerätetest.** Kein Simulator-UI-Test im blockierenden Pfad.
- **Ein einziges Paar Ohren.** Klang, Gefühl und Gerätereaktion können ausschließlich vom
  Founder beurteilt werden. Das ist kein Mangel, das ist die Struktur.
- Das **blockierende** Testbündel ist `Tests/CISmoke` mit **78** Dateien. Die 313 Dateien in
  `Tests/EchoelmusicTests` laufen non-blocking (#208).

**Konsequenz, die alles erklärt:** Gebaute Fläche wächst schneller als geprüfte Fläche. Genau
das steht als Symptom über die ganze Task-Liste verteilt — und es ist keine Meinung, es ist
zählbar. Die wiederkehrenden Task-Titel dieses Repos lauten:
*„türlos"*, *„null Aufrufer"*, *„lügendes Control"*, *„erreicht das Audio nie"*,
*„tote Zweitkopie"*, *„persistiert, aber kein Leser"*.

Beispiele, alle belegt und alle aus der DMMW-Zeit: die Delay-Teilung von 29 Genres erreichte
das Audio nie (#257) · „All parameters" im FX-Panel erreichte nur die halbe Kette (#318) ·
`BioReactiveSynthVoice.arm()` hat null Aufrufer (#277) · `RecordController` ist komplett türlos
(#204) · `visualVJOverlay` ist eine vollständige tote Zweitkopie (#270) · `soundControls`
ebenso, sieben Panels (#321, heute gefunden) · aufgenommene WAVs landen ohne jeden Leser in
`Documents/Exports` (#274).

**Das ist das Muster des Scheiterns.** Nicht „konnten wir nicht bauen", sondern
**„haben mehr gebaut, als wir beweisen konnten, dass es angeschlossen ist."** Eine DAW ist die
denkbar schlechteste Produktform für dieses Muster, weil ihr Wert *ausschließlich* aus dem
Zusammenspiel vieler angeschlossener Teile entsteht.

### 5.2 Was ein DMMW-Versuch #3 an System bräuchte (nicht an Code)

Ohne diese fünf ist das Ergebnis vorhersagbar identisch:

1. **Richtungs-Sperrfrist.** Eine Produktrichtung wird für **mindestens 90 Tage** nicht
   revidiert — nur durch neue Belege, nie durch neue Begeisterung. Formal in `decisions.csv`
   mit `review_date` statt ad hoc. *(Direkte Antwort auf §1: die längste Konstanz waren 4 Wochen.)*
2. **Anschluss-Beweis als Merge-Bedingung.** Kein neues Feature ohne (a) gerenderte Tür,
   (b) CISmoke-Wächter, der die Tür pinnt, (c) einen benannten Produzenten UND Konsumenten.
   Das ist keine Bürokratie — es ist exakt die Liste der Defekte oben, in Regelform.
   *(Läuft seit ~10 Tagen und funktioniert: #281, #286, #292, #311, #320 haben je einen.)*
3. **Simulator-UI-Smoke im blockierenden Pfad.** Ein `mcp__ios-simulator`-Durchlauf, der die
   App startet, jeden Chip antippt und einen Screenshot je Panel ablegt, fängt Schwarzbild,
   Freeze und türlose Flächen ohne den Founder. **Das ist der größte einzelne Hebel des
   ganzen Dokuments** und unabhängig von der DMMW-Frage wertvoll.
4. **Ein zweites Paar Ohren** oder ein Referenz-Nulltest (LUFS/Spektrum-Vergleich gegen
   Referenztracks). Solange Klangqualität nur subjektiv prüfbar ist, ist „Profi-Niveau" kein
   Abnahmekriterium, sondern ein Gefühl. **Vorbedingung dafür: #316** — die LUFS-Anzeige misst
   heute VOR der Master-Kette, das Messgerät selbst ist also falsch.
5. **Fläche pro Zeit deckeln.** Eine neue Oberfläche darf erst entstehen, wenn die
   NEEDS-FOUNDER-VERIFY-Liste leer ist. Das ist das einzige Ventil, das
   Bau-Rate an Prüf-Rate koppelt.

---

## 6. Der Ultra-Architektur-Plan — WENN gebaut wird

Konstruiert so, dass er unter den realen Bedingungen (ein Entwickler, kein lokaler Compiler,
ein Ohrenpaar) tragfähig ist. Er baut die DMMW **nicht als Ansicht**, sondern als **Schicht
über dem Instrument**, damit das Instrument nie wieder Geisel des Ausbaus wird.

### Leitsatz

> **Das Instrument ist die App. Die DMMW ist ein optionaler AUFZEICHNUNGS- und
> ÜBERGABE-Layer darüber — nie die Startansicht, nie eine Vorbedingung für Klang.**

Damit ist Nr. 13/14 (Timeline über Instrument-Zone, Freeze bis DMMW-Profi-Level) strukturell
ausgeschlossen: der Ausbau kann nie wieder das Ausliefern blockieren.

### Die vier Schichten

```
┌─ L3  ÜBERGABE          MIDI-Export · Stem/WAV-Export · MIDI-Clock/Link · OSC
│                        „liefere an Ableton" statt „sei Ableton"
├─ L2  ARRANGEMENT       Timeline · Clips · Automation · Lane-FX · Multitrack
│      (optional,        ← MASCHINE EXISTIERT (§2). Kostet Türen, nicht Neubau.
│       eine Tür)          Adaptiv (#292), kein Wachsen der Modal-Kette.
├─ L1  AUSGABE-STUFE     Visual · Licht (Art-Net/sACN) · Raum (ADM-OSC) · Haptik
│      (existiert)       ← EIN Bus: BioFrame + MusicalFrame → N Subscriber
└─ L0  INSTRUMENT        Bio → Synthese → Komposition → Field
       (die App)         ← startet, klingt, exportiert AUCH OHNE L2
```

**Die harte Regel:** L0 darf zu keinem Zeitpunkt ein Symbol aus L2 importieren. Nur L2 kennt
L0. Ein CISmoke-Wächter kann das prüfen (Import-Richtung im Quelltext), und genau dieser
Wächter ist es, der den Rückfall verhindert — nicht Disziplin.

### Slice-Reihenfolge (jede Scheibe einzeln auslieferbar und einzeln zurücknehmbar)

| # | Scheibe | Vorbedingung | Beweis |
|---|---|---|---|
| **A0** | **#132 Slice 5 auf HOLD** — die Maschine nicht löschen, bis entschieden ist | — | Task-Status + `decisions.csv`-Zeile |
| **A1** | Simulator-UI-Smoke im blockierenden Pfad (§5.2 Nr. 3) | — | Start + jeder Chip + Screenshot je Panel |
| **A2** | Schicht-Wächter L0 ⊥ L2 (Import-Richtung) | — | CISmoke |
| **A3** | #316 LUFS hinter die Master-Kette (das Messgerät reparieren) | — | CISmoke + Hörprobe |
| **B1** | Multitrack-Tür: `FeatureFlags.audioLaneRecording` registrieren + Tür (#204) | A1–A2 | Wächter + Gerät |
| **B2** | Arrangement-Tür: EINE Timeline-Ansicht hinter EINEM Slot, adaptiv | B1 | Wächter + Gerät |
| **B3** | Automations-Tür (Kern existiert vollständig) | B2 | Wächter |
| **B4** | Patch/FX pro Spur autorisierbar (#23 — Council-Frage bereits gestellt) | B2 | Wächter + Gerät |
| **C1** | **App-Group-Brücke: App misst → zweiter Prozess klingt** (auch die Watch-Lücke „C7") | B-Reihe grün | Gerät |
| **C2** | AUv3-Target Echoel-als-Instrument, Bio über C1 | C1 | Host-Test in Logic/AUM |
| **D** | AUv3-Host/Scanning — **nur** wenn C2 im Feld trägt | C2 | — |

**C1 vor C2 ist die eigentliche Erkenntnis dieses Plans.** Ohne die Brücke ist ein Echoel-AUv3
ein Synth ohne Körper, also ohne Produkt. Und dieselbe Brücke schließt zugleich die seit
Monaten offene Wearable-Lücke — **ein Fundament, zwei Auszahlungen.**

---

## 7. Was ich empfehle (Du entscheidest)

**Nicht die DMMW als Ganzes. Aber auch nicht „nie".**

1. **Sofort und unabhängig von allem:** #132 Slice 5 auf HOLD (A0). Kostet nichts, hält die
   Option offen, verhindert eine irreversible Löschung durch eine spätere Aufräum-Session.
2. **Danach A1–A3.** Das sind die drei System-Reparaturen, die *unabhängig* von der
   DMMW-Entscheidung den Unterschied machen — und ohne die ein DMMW-Versuch #3 mit hoher
   Wahrscheinlichkeit genauso endet wie #1 und #2.
3. **v1.0 in den Store.** Ein Fremder muss das Instrument in der Hand gehabt haben, bevor die
   nächste Richtungsentscheidung fällt. Alles andere ist Planen ohne Rückkanal.
4. **Dann entscheiden — mit Daten statt Vermutung.** Wenn die ersten Nutzer nach Spuren fragen,
   liegt die Maschine bereit und die B-Reihe ist Türarbeit. Wenn sie nach Licht, Raum und
   Körper fragen, hast Du Dir sechs Monate DAW-Wettrüsten gespart.

**Und die eine Sache, die ich Dir nicht ersparen will:** Wenn diese Frage in zwei Wochen erneut
kippt, ist die Ursache nicht der Plan. Dann ist es Nr. 20. Die Sperrfrist aus §5.2 Nr. 1 ist
der einzige Punkt dieses Dokuments, den kein Code ersetzen kann.

---

## Belege / Reproduktion

```bash
# Die Oszillations-Tabelle (§1)
python3 -c "import csv,re; [print(r[0],'|',r[1][:110]) for r in csv.reader(open('decisions.csv')) if len(r)>1 and re.search(r'pivot|focus|instrument|daw|dmmw|breadth',r[1],re.I)]"

# Die überlebende Maschine (§2)
for f in Timeline TimelineStore ClipStore ArrangementStore AutomationLane TrackFX \
         LaneVoiceRack MultiTrackRecorder AudioLanePlayer MultiRollFanout; do
  echo "$f: $(git grep -l "$f" -- 'Sources/**/*.swift' | wc -l)"
done

# Codebasis (§3)
git ls-files 'Sources/**/*.swift' | xargs wc -l | tail -1     # 96471
ls Sources/                                                    # kein AUv3-Target mehr
git ls-files 'Tests/CISmoke/*.swift' | wc -l                   # 78 (blockierend)
git ls-files 'Tests/EchoelmusicTests/*.swift' | wc -l          # 313 (non-blocking, #208)
```

**Quellen im Repo:** `decisions.csv` · `docs/dev/PRODUCT_DEFINITION.md` ·
`docs/dev/DMMW_ARCHITECTURE.md` (superseded, history-only) ·
`docs/dev/VISION_REALITY_2026-07.md` · `scratchpads/STRATEGY_STATE_OF_THE_ART_2026-06-06.md` ·
`scratchpads/HARNESS_LEDGER.md`

**Grenzen dieses Dokuments, ehrlich:** Die Marktaussagen in §4 stammen aus Modellwissen plus
der im Repo protokollierten Konkurrenzanalyse des Founders, **nicht** aus einer heute
durchgeführten Live-Marktrecherche — Preise und Feature-Stände können sich verschoben haben.
Die Repo-Zahlen in §1–§3 und §5 sind dagegen alle heute gemessen und oben reproduzierbar.
