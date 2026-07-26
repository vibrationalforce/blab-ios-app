# PLAN — FX-Parameter-Glide (#138): die Steuerraten-Treppe abstellen

Status: **Kern gebaut + getestet. Verdrahtung ist Slice 2 und steht noch aus.**
Angelegt 2026-07-26, nach dem Audio-Review zu `54a2dd5`.

## Das Problem, belegt

Keine einzige `EchoelFXChain`-Stufe glättet ihre eigenen Parameter. Alle dreizehn
`FXModTarget`-Werte werden roh pro Sample gelesen:

| Ziel | Lesestelle |
|---|---|
| cutoff / resonance | `EchoelSVFilter` (`didSet` rechnet Koeffizienten sofort neu) |
| delay mix / feedback | `EchoelDelay` |
| reverb mix / roomSize | `EchoelReverb` |
| chorus/flanger/phaser mix, tremolo depth | `EchoelModFX` |
| stereo width | `EchoelLoFiFX` |
| saturation drive | `EchoelFXChain` |

Der 30-Hz-Treiber schreibt sie, und sein Bio-Träger aktualisiert nur mit ~10 Hz. Also
ist ein körpergesteuerter Filter-Sweep eine Treppe mit zehn Stufen pro Sekunde — auf
einem resonanten Filter ist jede Stufe eine hörbare Kante statt eines Sweeps. Ein
LFO-Träger mit bis zu 8 Hz, abgetastet mit 30 Hz, sind ~3,75 Abtastungen pro Zyklus:
ein grob aliasender Stufenzug über fast die volle Spanne.

**Das Haus kennt das Muster schon.** `EchoelDelay` glättet `timeSeconds` mit einem
40-ms-Einpol IM Render-Loop, ausdrücklich „damit ein Preset-Wechsel den Lesekopf
schiebt statt ihn zu springen — ein Sprung ist ein Klick". `mix` und `feedback` zwei
Zeilen darüber bekommen nichts. Es fehlt nicht die Erkenntnis, es fehlt die Anwendung.

## Warum das NICHT in einem Zyklus naiv verdrahtet wird

`FXBioModulator.read` erfasst seine **Basis** aus genau dem Feld, das gleiten würde
(`c.filterL.cutoff`). Ein naiv eingebautes Gleiten ließe die Basis mitten im Glide
erfassen — der Treiber würde dann um einen zufälligen Zwischenwert modulieren. Dasselbe
gilt für `FXPreset` (speichert `chain.filterL.cutoff`) und `EchoelFXView` (setzt sein
VM daraus auf).

Es gibt sechs direkte Schreiber/Leser des Filterfelds außerhalb der Kette:
`FXBioModulator` (read + write), `EchoelFXView` (3×), `FXPreset` (2×), plus
`setFilter(...)` aus `GenreFX` und `FXCuratedLibrary`.

**Die Architektur, die das auflöst — und es ist dieselbe, die `EchoelDelay` schon hat:**
die Kette hält das ZIEL als maßgebliche Steuerebenen-Zahl, und der Glide ist ein
interner Audio-Spiegel, den nur `process` liest. Dann sehen Basis-Erfassung,
Preset-Speicherung und UI-Anzeige immer den Wert, den der Nutzer gesetzt hat, und nur
das Hörbare gleitet.

## Slice 1 — GEBAUT (dieser Zyklus)

`Sources/Echoelmusic/DSP/ParamGlide.swift` + `Tests/EchoelmusicTests/ParamGlideTests.swift`.

Reiner Wertetyp, ein einziger gespeicherter Float, keine Allokation, kein Lock — audio-thread-sicher per
Konstruktion. Die drei Eigenschaften, die getestet sind, weil sie die Fehlerquellen sind:

1. **Ratenbasiert.** Block-Rate (~188 Hz bei 256 Frames/48 kHz) und Sample-Rate landen
   nach derselben Wanduhr-Zeit am selben Punkt. Sonst hinge der Klang an der Puffergröße,
   die der Host gerade liefert.
2. **Er kommt EXAKT an — und zwar gegen das STEHENBLEIBEN, nicht gegen CPU.** Ein
   Float32-Einpol hört von selbst auf (der Zuwachs fällt unter ein halbes ULP und wird
   weggerundet), und ein konstanter Wert lässt auch das `didSet` nicht mehr feuern. Das
   Problem ist, WO er stehenbleibt: mit rein absoluter Schwelle parkt ein Cutoff auf dem
   Weg zu 18 000 Hz ein Stück davor für immer, weil absolute 1e-4 bei der Größenordnung
   unerreichbar sind (ein ULP dort ist ~0,002). Daher der relative Term.
3. **Nicht-endliche Ziele werden gehalten, nicht durchgereicht.** Der Wert speist einen
   rekursiven Filter — ein NaN dort ist dauerhaft.

**Zeitkonstante `bioTau = 0,05 s`, gemessen statt geschätzt.** Bio-Träger liefern etwa
alle 100 ms einen neuen Wert. Bei τ = 0,02 liegt die Einpol-Ecke bei 8 Hz, also direkt
auf dem 10-Hz-Stufenzug: das entfernt die Unstetigkeit (den Klick), lässt die Treppe aber
stehen, Welligkeit nur ~4 dB runter. Bei τ = 0,05 liegt die Ecke bei 3,2 Hz, ~10 dB
runter, und — entscheidend — der Glide ist bei 100 ms erst zu 86 % angekommen, also noch
in Bewegung, wenn der nächste Wert eintrifft. Die Stufen überlappen zu EINER Kontur statt
zu zehn getrennten Rampen pro Sekunde. Kosten: 50 ms Latenz auf eine Körpergeste,
unhörbar und drei Größenordnungen unter der 4–5-s-Watch-Latenz, mit der die Plattform
ohnehin lebt.

Bewusst BLOCK-Rate, nicht Sample-Rate — aber NICHT, weil Pro-Sample verboten wäre:
`EchoelDDSP` gleitet den Cutoff heute pro Sample im Render-Loop, und die Gleichheits-
Sperre in `EchoelSVFilter.didSet` existiert genau dafür. Der Grund ist Aufwand: `tanf`
läuft auf jedem Sample, auf dem sich der Glide bewegt — ~3000 pro Glide bei 48 kHz gegen
~10 auf Blockrate, ohne hörbaren Unterschied, weil die Integratoren Cutoff-Bewegung
innerhalb eines Blocks gar nicht auflösen.

## Slice 2 — NÄCHSTER ZYKLUS (Filter zuerst, größte Spanne)

1. `EchoelFXChain` bekommt `filterCutoff` / `filterResonance` als Ziel-Fassade
   (Steuerebene) plus zwei `ParamGlide` (Audio-Seite).
2. `processBuffer` / `processBufferMono` — die einzigen Eintrittspunkte, über die beide
   Voices gehen (und sie halten je eine EIGENE `EchoelFXChain`, also kein Doppel-Steppen)
   — steppen den Glide einmal pro Block und schreiben das Ergebnis in `filterL/filterR`.
   **Die Schrittrate aus dem ECHTEN Block ableiten (`sampleRate / frameCount`), nie aus
   angenommenen 256 Frames**: `frameCount` ist variabel (bis `maxBlockFrames` = 4096),
   ein gegen eine Annahme gecachter Koeffizient ließe die Glide-Dauer mit der Puffergröße
   des Hosts skalieren — genau die Ratenabhängigkeit, die die Formel entfernt, an der
   Aufrufstelle wieder eingebaut. Koeffizient gegen den zuletzt gesehenen `frameCount`
   cachen, damit `expf` nur bei Puffergrößen-Wechsel läuft.
   **Und `processStereo` ist `public` und pro Sample** — wird der Glide nur in den
   Block-Eintrittspunkten gesteppt, bekäme ein künftiger Direktaufrufer einen dauerhaft
   eingefrorenen Cutoff. Entweder `processStereo` internal machen oder ein eigenes
   `advanceBlock(frameCount:)` einführen, das Aufrufer verpflichtend rufen.
3. Alle sechs externen Stellen auf die Fassade umziehen. Danach ist die Kette der
   einzige Schreiber der Stufe.
4. **Snappen**, nicht gleiten, an DREI steigenden Flanken: `setFilter(...)`, `reset()`
   und — leicht zu übersehen — `filterEnabled`s steigende Flanke. Die dritte ist real:
   `FXBioModulator.enableStage` setzt genau dieses Flag, wenn eine Route zum ersten Mal
   beiträgt, und ohne Snap wäre das erste Hörbare nach dem Einrasten einer Bio-Route ein
   Hochsweepen von einem alten Wert — genau das Artefakt, gegen das `snap` existiert.
   Der 30-Hz-Treiber und der UI-Fader **gleiten**.
5. Für den Reviewer schon notiert, damit er es nicht neu entdecken muss: sobald der Glide
   `filterL.cutoff` von der Audio-Seite schreibt, läuft `updateCoefficients()` auf dem
   Audio-Thread (zulässig — `tanf` steht auf der erlaubten Liste), und Steuer-Thread
   (`resonance`) und Audio-Thread (`cutoff`) können gleichzeitig darin `g` schreiben. Nach
   der Tear-Toleranz-Begründung in `EchoelSVFilter` bleibt jedes zerrissene `(g, k)`-Paar
   ein konsistenter Filter — die Eigenschaft ist load-bearing und darf nicht wegoptimiert
   werden.
6. Pflicht: `audio-thread-reviewer` + Gerätelauf. Ein Glide, den man nicht gehört hat,
   ist nicht fertig.

## Slice 3+ — die übrigen Ziele

Reihenfolge nach hörbarer Spanne: delay feedback (Selbstoszillation nahe 0,95) →
reverb mix/size → die Mixe → stereo width → saturation drive. Jeweils dieselbe
Ziel/Glide-Trennung.

## Ausdrücklich NICHT in diesem Plan

Das Aliasing des LFO-Trägers (8 Hz, abgetastet mit 30 Hz) verschwindet durch Glätten
NICHT — es wird nur weicher. Der richtige Fix dort ist, den LFO auf Audio- oder
Block-Rate in der Kette laufen zu lassen statt im 30-Hz-Treiber. Eigener Punkt, eigener
Plan; hier nur festgehalten, damit ein späterer Zyklus nicht glaubt, das Glätten hätte
es erledigt.
