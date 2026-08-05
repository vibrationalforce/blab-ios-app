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

### 1d. GERÄTE-BELEG (Founder-Log v10.79.369 / Build 2486, 2026-08-05) — und er verschiebt die Gewichte

Neun `generate[…]`-Zeilen über ~4 Minuten, Genre `selfObservation` (der Default, auf den eine
Neuinstallation öffnet). **Jede einzelne meldet `5 notes`.** Alles andere konstant: `key=C4
minor`, `tuning=edo12`, `a4=440.0`, `rollMixGain=1.00`, `userMix=1.00/1.00/1.00`. Der einzige
Wert, der sich bewegt, ist `vMax` — zwischen 0,699 und 0,835.

**Das ist KEIN Defekt im Seed, und genau deshalb ist es die wichtigste Zeile dieses Plans.**
`MusicStyle.selfObservation` liefert `HarmonicProfile(progression: [0, 5, 3], chordTones:
[0, 2, 4, 6], leadDensity: 0.0, sustained: true)` — vier gehaltene Akkordtöne plus einen
Bass-Grundton, kein Lead, keine Drums. Fünf Noten sind die **Bauart**, nicht ein Zufall: das
Profil ist am 2026-07-07 bewusst so gesetzt worden („reine meditative Flächen", „ein wahrer
Drone"), und es tut, was es soll.

Die Folge für #403 ist trotzdem hart: **für das Genre, auf das eine Neuinstallation öffnet,
hat der `structureSeed` fast keinen Hebel.** Notenzahl fest, Akkordtöne fest, Lage fest,
kein Lead. Was der Körper überhaupt bewegen kann, ist die Velocity und — über die Evolves —
welcher der drei Akkorde gerade gehalten wird. Ein Personen-Seed im Skelett-Strom (Slice 1)
verändert an einer gehaltenen Fläche also **kaum etwas Hörbares**.

**Konsequenz, ausdrücklich als Planänderung:** Slice 2 (Charakter-Offsets — Tempo-Neigung im
Genre-Fenster, Dichte, Register) ist damit **nicht die Politur nach Slice 1, sondern der
einzige Hebel, der die kontemplative Mitte der Marke überhaupt erreicht.** Slice 1 bleibt
zuerst, weil die Signatur existieren muss, bevor sie etwas neigen kann — aber die Erwartung
„nach Slice 1 klingt es individuell" wäre für die Default-Genres falsch, und diese Zeile steht
hier, damit sie nicht entsteht.

⚠️ Der Wächter `testASustainedPadStillMovesWithTheBody` (Slice 0) misst genau diesen Fall auf
`.drift` und fordert bewusst nur „größer null", keine Schwelle. Nach dieser Lesung ist klar,
warum das die richtige Entscheidung war: auf einer gehaltenen Fläche bleibt heute im
Wesentlichen der Velocity-Anteil übrig, und der wiegt 0,10.

⚠️ Ebenfalls aus diesem Log: die Sitzung lief mit `bio simulation starting`, also der
SIMULIERTEN Quelle, nicht mit einem gemessenen Puls. Sie sagt deshalb nichts darüber, ob der
Körper des Founders das Instrument erreicht — nur, was die Schablone zulässt.

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

### Slice 0 — die Zahl (blockiert alles andere) · **GEBAUT 2026-08-05**
`Sources/Echoelmusic/Sequencer/TakeDistance.swift` + `Tests/CISmoke/TakeDistanceTests.swift`.
Elf Eigenschaften des reinen Maßes plus fünf Wächter an echten `BioComposer`-Takes (16 gesamt —
Zahl per `grep -c "func test"` prüfen, nicht aus dem Kopf). Die beiden im Absatz unten
geforderten sind `testDifferentBodiesDoNotCollapseOntoOneTake` und
`testTheSamePersonIsCloserToItselfThanToAStranger`.
⚠️ Drei Einschränkungen, die beim Zitieren mitmüssen:
(1) Die Seed-Faltung im Test ist eine NACHBILDUNG der App-Faltung (`bioSeed` ist privat auf
einer @MainActor-View) — gepinnt ist die Unterscheidungskraft des Maßes, NICHT die
App-Verdrahtung; die bekommt ihren Wächter mit Slice 1.
(2) `minimumCrossBodyDistance = 0.05` ist ein BODEN gegen Kollaps, keine gemessene Grenze — die
echte Zahl liefert Slice 2.
(3) `testTheSamePersonIsCloserToItselfThanToAStranger` belegt die PRODUKT-Eigenschaft, nicht die
Naht: die Fremd-Paare unterscheiden sich auch in allen vier Bio-Werten, die Ordnung hielte also
selbst bei folgenlosem `structureSeed`. Die Naht isoliert
`testTheSkeletonSeedAloneChangesTheTake` — alles gleich außer dem Skelett-Seed. **Das ist der
Test, an dem Slice 1 hängt.**

Ein reiner Kern `TakeDistance`, der zwei `[Note]`-Takes vergleicht und einen Abstand in
[0,1] liefert, aufgeteilt in benannte Anteile: Tonhöhen-Kontur · Rhythmus-Onsets ·
Dichte · Register · Velocity-Profil. Plus Wächter im blockierenden Bundle:
„zwei Takes aus DEMSELBEN Preset mit VERSCHIEDENEN Körpern müssen mindestens X auseinander
liegen" und „zwei Takes derselben Person müssen NÄHER beieinander liegen als zwei
verschiedener Personen".
**Ohne diese Zahl ist jede folgende Scheibe Geschmackssache.** Rein, testbar, kein UI.

### Slice 1 — `PerformerSignature` (Kern + Verdrahtung, keine Fläche) · **GEBAUT 2026-08-05**
`Sources/Echoelmusic/Bio/PerformerSignature.swift` + `Tests/CISmoke/SignatureIsThePersonNotTheMomentTests.swift`
(24 Testfunktionen — Zahl per `grep -c "func test"` prüfen, nicht aus dem Kopf). Verdrahtet in
`EchoelStudioView.makeComposerInput`: Salt-Faltung in `structureSeed`, Lernen nur auf einem
echten Take.

**Drei Dinge, die beim Bauen anders entschieden wurden als der Plan sie beschrieb, jeweils mit
Grund — wer aus diesem Plan zitiert, muss sie kennen:**

1. ⛔ **„Sie fällt NICHT in den evolvingSeed" ist im heutigen Code NICHT herstellbar, und das war
   schon vor #403 so.** `evolvingSeed` wird aus `structureSeed` ABGELEITET
   (`structureSeed ^ (evolution &* K)`), also erreicht jedes dort gefaltete Salz auch das Detail
   — der Wetter-Salt tut das seit E3b, und der Quellkommentar daneben behauptete wörtlich das
   Gegenteil („the detail seed below stays body+evolution"). Beides ist mit diesem Commit
   richtiggestellt. Die Absicht der Regel bleibt erfüllt: die Evolutions-Nonce bewegt sich bei
   jedem Take, die Person verschiebt also WO im Raum ihre Takes liegen, sie kollabiert sie
   nicht auf einen Punkt. Eine echte Trennung wäre eine Umstellung von `evolvingSeed` auf den
   Seed VOR dem Salz — das änderte auch das Wetterverhalten und gehört nicht in diese Scheibe.
2. **Der Simulator darf nicht lehren.** `BioSimulator` stempelt `.fallback` und liefert
   plausible Werte; eine daraus gelernte Handschrift wäre ein synthetischer Mensch, der als der
   Nutzer ausgegeben wird — genau die Vision-Keeper-Sorge aus Abschnitt 2. Nicht theoretisch:
   die Founder-Sitzung vom 2026-08-05 lief mit `bio simulation starting`.
3. **Ein 30-s-Fenster begrenzt das Lernen.** Jeder Bedienschritt komponiert neu; ohne Fenster
   hätte EINE Sitzung die Handschrift besessen, die über Sitzungen hinweg gelten soll. Und die
   Ablehnung — ob Fenster oder Simulator — verbraucht das Fenster ausdrücklich NICHT, sonst
   friert eine unmessbare Quelle das Lernen dauerhaft ein.

⚠️ Was diese Scheibe NICHT belegt: dass es hörbar individuell klingt. Sie entscheidet, auf
welches Skelett ein Körper öffnet. Für `.selfObservation` bleibt der Hebel klein — siehe 1d.

**Ursprünglicher Plan-Text:**
Ein persistierter, langsam lernender Fingerabdruck aus dem, was ohnehin gemessen wird:
Ruhepuls-Lage, HRV-Streuung, typische Atemrate, typische Kohärenz. Aktualisiert per
laufendem Mittel über Sessions, nicht pro Frame. Faltet in `structureSeed`.
Leer/unbekannt ⇒ bit-identisch zu heute (Golden-Law).
⚠️ Kern UND Aufrufer im selben Commit — ein reiner Kern ohne Aufrufer ist derselbe Fehler
mit mehr Schritten.

### Slice 2 — Charakter-Offsets · **Tempo-Hälfte GEBAUT 2026-08-05**
Die Signatur neigt das Tempo INNERHALB des Genre-Fensters, die Notendichte und das
Register. Klein und begrenzt: sie darf die Genre-Identität nicht aufheben — #81 hat schon
einmal bewiesen, dass „erst individuell, dann alles gleich" die andere Richtung derselben
Falle ist. Grenzen werden mit Slice 0 gemessen, nicht geschätzt.

**Gebaut (Tempo):** `PerformerSignature.tempoTilt` (−1 … +1 über der Ruhepuls-Spanne
50…90) + `StudioCalculator.tilted(_:within:by:)`, verdrahtet an BEIDEN Körper-Tempo-Pfaden
in `makeComposerInput` (Erst-Aussaat und Pro-Tick-Konvergenz). Wächter:
`Tests/CISmoke/ThePaceIsTiltedInsideTheGenreTests.swift`.

Drei Dinge, die beim Bauen anders entschieden wurden als der Plan sie offen ließ:

1. **Warum das KEINE zweite Kopie der Live-Abbildung ist** — der naheliegendste Einwand,
   und er hat eine belegbare Antwort statt einer Meinung. `genreTempo` OKTAV-FALTET, und
   jeder Körper, dessen Oktave die Fenster-Decke überschießt, kommt als eine der beiden
   GRENZEN zurück. Über Contemplation (44…66) durchgerechnet: 68, 70, 72, 74, 76 → alle 66;
   78 bis 88 → alle 44. Rund die Hälfte gewöhnlicher Ruhepulse landet auf zwei Zahlen, und
   nicht einmal monoton. Die Neigung wirkt NACH der Faltung und stellt wieder her, was die
   Faltung zerstört hat.
   ⛔ **Die erste Fassung dieses Punktes schrieb „41 % einer Oktave fallen auf den Boden"
   und berief sich auf das Doc von `genreTempo`.** Dieser Satz beschreibt dort den Fehler,
   den #237 BEHOBEN hat — im Perfekt. Ihn im Präsens zu zitieren wäre genau die
   Falsch-Begründung-im-Kommentar, die diese Datei an anderer Stelle als schlimmer als gar
   keine Begründung bezeichnet. Er stand gleichzeitig in vier Dateien. Die richtige Zahl
   ist schlechter, nicht besser — und sie wurde nachgerechnet, nicht zitiert.
2. **Die Genre-Grenze hält durch die FORM, nicht durch einen Clamp** — die Bewegung ist ein
   Bruchteil (`maxTiltShare` 0.35) des VERBLEIBENDEN Kopfraums. Ein „Offset dann Clamp"
   sähe äquivalent aus und würde eine ganze Population von Performern auf eine Grenze
   sättigen; der Wächter wischt deshalb über tilt × bpm statt Stichproben zu nehmen.
3. **Der GESPERRTE Tempo-Zweig bleibt unberührt** — eine vom Nutzer getippte Zahl gehört
   ihm. Der Wächter prüft das als POSITIVEN Scan auf die unveränderte Zuweisung, weil ein
   negativer Scan Code nicht von Prosa unterscheiden kann (#367 rückwärts).

**Reviewer-Nachlese (zwei Reviewer, beide mit HIGH-Befunden auf der BEGRÜNDUNG, nicht auf
dem Code):**

- **Die Begründung maß das falsche Genre.** Sie lief über Contemplation (44…66) und nannte es
  „das Genre, auf dem eine Neuinstallation öffnet" — das ist `.selfObservation` (46…78,
  `StudioDefaultKeys`). Auf dem echten Default gehen 50…78 unverändert durch, also rund drei
  Viertel der Tilt-Spanne: dort *verstärkt* die Neigung, statt wiederherzustellen. Das ist
  legitim (habituell vs. momentan), war aber als Minderheitsfall dargestellt.
- **Die Begründung führte mit dem schwächsten Argument.** Das stärkste ist
  `BioComposer.tempo(for:)`: bei voller Kohärenz zieht es JEDEN Puls auf 72 — ein ganzer
  ruhiger Raum bekommt ein Tempo, ohne jede Faltung. Steht jetzt an erster Stelle, mit Test.
- **Die Anekdote „neun Takes, ein Tempo" war unbelegbar** — die Breadcrumb trägt gar kein
  Tempo, konstant waren die NOTEN (`5 notes`), und die Sitzung lief simuliert. Gestrichen.
- **Kein einziger Test unterschied die Kopfraum-Form von „Offset dann Clamp"** — obwohl drei
  Kommentare behaupteten, sie täten es. `testNearABoundTheTiltStaysInjective` tut es jetzt.
- **Der erste Messwert trug die volle Neigung** (`blend`-Gewicht 1/(n+1) = 1 bei n = 0). Jetzt
  Rampe über `confidentAfter` = 8 Beobachtungen.
- Dazu: `restingSpan` → `habitualSpan` (der Mittelwert misst den SPIELENDEN Körper),
  `headroom.isFinite`-Wächter, `clamped(to:)` statt verschachteltem `min(max(…))`, und der
  Oktav-Lock-Preis der Neigung erstmals irgendwo aufgeschrieben.

**Offen in Slice 2:** Register-Neigung und Dichte-Neigung.

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
