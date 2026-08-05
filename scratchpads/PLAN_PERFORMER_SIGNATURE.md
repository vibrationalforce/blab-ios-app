# PLAN — Individualität: „zwei User, gleiches Preset, verschiedene Songs"

**Founder-Ask (2026-08-05, wörtlich):** *„Mir wäre wichtig, das man nicht das Gefühl hat die
Kompositionen klingen gleich. Wenn verschiedene User das selbe preset auswählen und nichts
verändern sondern einfach rendern und damit einen Song produzieren soll er individuell nach
der Person klingen. Es wäre schlechtes Marketing, wenn die Songs alle ähnlich klingen."*

Status: PLAN. Noch keine Zeile Code. Nummer: **#403**.

---

## 1. WAS HEUTE WIRKLICH PASSIERT (per Quell-Lesung, nicht aus dem Gedächtnis)

Alle Belege aus `Sources/Echoelmusic/Studio/EchoelStudioView.swift` und
`Sources/Echoelmusic/Sequencer/BioComposer.swift`, gelesen am 2026-08-05.

### 1a. Zwei identische Renders sind AUSGESCHLOSSEN — das ist die gute Nachricht

Der Take hängt an zwei Seeds:

```
structureSeed = bioSeed(frame)                       // Skelett: Akkorde, Register, Dichte
evolvingSeed  = structureSeed ^ (evolution * φ)      // Detail: welche Töne, Feinvelocity
```

- **Mit Bio:** `bioSeed` faltet vier gemessene Werte fein quantisiert zusammen —
  Herzfrequenz ×100 (zwei Nachkommastellen), HRV/Kohärenz/Atemphase je ×100 000. Zwei
  Menschen müssten auf fünf Nachkommastellen denselben Körperzustand haben.
- **Ohne Bio:** `takeFallbackSeed = UInt64.random(in: 1...UInt64.max)`, neu gezogen bei
  jedem Start (`EchoelStudioView.swift`, `startBiofeedback`).

**Die Angst „alle bekommen dieselbe Datei" ist unbegründet.** Das ist belegt, nicht gehofft.

### 1b. Der echte Defekt ist ein anderer, und er ist schlimmer für das Marketing

Es gibt **zwei** Lücken, und sie sind nicht dieselbe:

**Lücke A — ohne Bio ist der Unterschied ein Würfel, keine Person.**
Rendert jemand ohne Puls (kein Finger auf der Linse, kein Gurt), ist `frame == nil`. Dann
sagt der Körper NICHTS: Tempo, Energie und Dichte kommen aus neutralen Defaults, und die
einzige Individualität ist eine Zufallszahl. Zwei Nutzer bekommen verschiedene Songs — aber
aus demselben Grund, aus dem zwei Würfe verschieden sind. **Das ist genau die Behauptung,
die die Marke trägt („Dein Körper spielt es"), und sie wäre in diesem Pfad unwahr.** Eine
Rezension, die das bemerkt, ist teurer als ein fehlendes Feature.

**Lücke B — mit Bio ist der Unterschied ein MOMENT, keine PERSON.**
Der Seed kommt aus dem Körperzustand *jetzt*. Derselbe Mensch rendert morgens und abends und
bekommt zwei so verschiedene Songs wie zwei fremde Menschen. Es gibt heute **nichts
Persistiertes**, das „so klingt Michael" heißt. Die Founder-Formulierung ist aber
ausdrücklich *„individuell nach der Person"* — also wiedererkennbar, nicht bloß verschieden.

### 1c. …und was der Seed NICHT ändert (der Grund für das Gefühl „klingt gleich")

Der Seed wählt **innerhalb** einer Schablone. Konstant bleiben pro Preset/Genre:
Tonart+Skala, das Tempo-**Fenster** (`StudioCalculator.genreTempo(_, into: range)`),
die Rhythmus-Vorlagen für Bass/Pad, das Akkord-Vokabular, das Timbre (Patch), der
FX-Charakter, die Mischung. Andere Töne in derselben Schablone klingen wie **dasselbe Stück,
anders gespielt** — nicht wie ein anderes Stück. Genau das beschreibt „klingen gleich".

⚠️ **Was ich NICHT belegen kann:** dass es tatsächlich zu ähnlich klingt. Das ist ein
Ohr-Urteil, und es gehört dem Founder. Ich behandle es als Anforderung, nicht als Bugreport
— aber es gibt heute **keine Zahl** dafür (siehe Slice 0).

---

## 2. COUNCIL

- **Vision-Keeper:** on-vision, und zwar zwingend — „bio-reactive instrument" heißt, der
  Unterschied MUSS aus dem Körper kommen. Schärfste Sorge: eine Lösung, die Individualität
  aus mehr Zufall macht, ist ein Betrug an der eigenen Behauptung. Zufall ist kein Körper.
- **Skeptic:** die teuerste Falle ist, „Vielfalt" zu bauen, bevor irgendjemand Ähnlichkeit
  MESSEN kann. #314 sagt wörtlich „erst beweisen was kaputt ist, dann bauen". Ohne Zahl
  landen wir bei „ist es jetzt genug anders?" und drehen im Kreis.
- **Architect:** die Naht existiert schon und ist genau eine Zeile — `structureSeed`. Eine
  Personen-Identität dort einzufalten koppelt nichts Neues; sie darf nur NICHT zusätzlich in
  `evolvingSeed`, sonst wäre die Person auch die Detail-Variation und jeder Take derselbe.
- **User-Advocate:** die Signatur muss ohne Erklärung entstehen. Kein Fragebogen, kein
  „Kalibrierung starten". Sie fällt beim normalen Spielen ab oder gar nicht.
- **Shipper:** vier Scheiben, jede für sich lieferbar und rückwärts bit-identisch, solange
  die Signatur leer ist. Keine neue Fläche, keine neue Modal-Tür.
- **DSP Purist:** nichts davon berührt den Audio-Thread. Der Komponist läuft auf der
  Control-Plane. Rausch-Triad unberührt.

**Dissens, ausdrücklich stehengelassen:** Vision-Keeper und Shipper sind uneins, ob Lücke A
(ohne Bio) mit einer Signatur überhaupt geschlossen werden DARF. Ohne je gemessenen Körper
gibt es keine Signatur — dann bleibt der Würfel. Der Architect hält dagegen: sobald der
Nutzer EINMAL mit Puls gespielt hat, ist die Signatur da und färbt auch spätere
bio-lose Renders. Beide haben recht, für verschiedene Nutzer. **Konsequenz: der allererste
Render eines Nutzers, der nie Bio benutzt hat, bleibt ein Würfel — und das wird im Produkt
nicht anders behauptet.** Ehrlicher Text schlägt eine erfundene Signatur.

**Gate: proceed** — aber mit Slice 0 (messen) vor Slice 1 (bauen).

---

## 3. ENTSCHEIDUNG (souverän, Founder-Delegation)

**Die Signatur gehört der PERSON, die Variation gehört dem MOMENT.**
Derselbe Mensch soll wiedererkennbar klingen und trotzdem bei jedem Render ein neues Stück
bekommen — so wie ein Musiker eine Handschrift hat und nicht jedes Mal dasselbe spielt.

Technisch heißt das exakt:
- Die Signatur fällt in den **`structureSeed`** und in eine kleine Zahl von
  **Charakter-Offsets** (Tempo-Neigung im Genre-Fenster, Dichte-Neigung, Register-Neigung).
- Sie fällt **NICHT** in den `evolvingSeed`. Der bleibt Moment + Evolution.

Damit ist „gleiches Preset, zwei Personen" ein anderes Skelett, und „gleiches Preset,
dieselbe Person, zweimal" dasselbe Skelett mit neuer Melodie.

---

## 4. SCHEIBEN

### Slice 0 — die Zahl (blockiert alles andere)
Ein reiner Kern `TakeDistance`, der zwei `[Note]`-Takes vergleicht und einen Abstand in
[0,1] liefert, aufgeteilt in benannte Anteile: Tonhöhen-Kontur · Rhythmus-Onsets ·
Dichte · Register · Velocity-Profil. Plus Wächter im blockierenden Bundle:
„zwei Takes aus DEMSELBEN Preset mit VERSCHIEDENEN Körpern müssen mindestens X auseinander
liegen" und „zwei Takes derselben Person müssen NÄHER beieinander liegen als zwei
verschiedener Personen".
**Ohne diese Zahl ist jede folgende Scheibe Geschmackssache.** Rein, testbar, kein UI.

### Slice 1 — `PerformerSignature` (Kern + Verdrahtung, keine Fläche)
Ein persistierter, langsam lernender Fingerabdruck aus dem, was ohnehin gemessen wird:
Ruhepuls-Lage, HRV-Streuung, typische Atemrate, typische Kohärenz. Aktualisiert per
laufendem Mittel über Sessions, nicht pro Frame. Faltet in `structureSeed`.
Leer/unbekannt ⇒ bit-identisch zu heute (Golden-Law).
⚠️ Kern UND Aufrufer im selben Commit — ein reiner Kern ohne Aufrufer ist derselbe Fehler
mit mehr Schritten.

### Slice 2 — Charakter-Offsets
Die Signatur neigt das Tempo INNERHALB des Genre-Fensters, die Notendichte und das
Register. Klein und begrenzt: sie darf die Genre-Identität nicht aufheben — #81 hat schon
einmal bewiesen, dass „erst individuell, dann alles gleich" die andere Richtung derselben
Falle ist. Grenzen werden mit Slice 0 gemessen, nicht geschätzt.

### Slice 3 — Ehrlichkeit im Produkt
Wenn nie ein Körper gemessen wurde, sagt die App das (eine Zeile, kein Dialog) statt eine
Personalisierung zu behaupten, die es nicht gibt. Und der Store-Text darf erst dann von
„klingt nach Dir" sprechen, wenn Slice 0 belegt, dass es stimmt — `ContentPipeline/CLAIMS.md`
und `fastlane/metadata` ziehen mit.

---

## 5. AUSDRÜCKLICH NICHT IN DIESEM PLAN

- **Kein Fragebogen, keine Kalibrier-Fläche.** Die Signatur fällt beim Spielen ab.
- **Keine Cloud, kein Vergleich zwischen Nutzern.** Die Signatur bleibt auf dem Gerät;
  sie ist aus Gesundheitsdaten abgeleitet und verlässt es nicht.
- **Kein Heilungs-/Wellness-Claim.** Die Signatur ist eine musikalische Handschrift,
  keine Aussage über den Menschen.
- **Kein „mehr Zufall".** Würde das Symptom kurz lindern und die Marke beschädigen.
