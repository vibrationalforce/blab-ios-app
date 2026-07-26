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

Reiner Wertetyp, zwei Floats, keine Allokation, kein Lock — audio-thread-sicher per
Konstruktion. Die drei Eigenschaften, die getestet sind, weil sie die Fehlerquellen sind:

1. **Ratenbasiert.** Block-Rate (~188 Hz bei 256 Frames/48 kHz) und Sample-Rate landen
   nach derselben Wanduhr-Zeit am selben Punkt. Sonst hinge der Klang an der Puffergröße,
   die der Host gerade liefert.
2. **Er kommt EXAKT an.** Ein Einpol erreicht sein Ziel nie; ein Cutoff, der nie
   aufhört sich zu ändern, lässt `EchoelSVFilter.didSet` bis Sessionende jeden Block
   `tanf` neu rechnen. (Dieselbe Lehre wie `presenceEpsilon` in 54a2dd5.)
3. **Nicht-endliche Ziele werden gehalten, nicht durchgereicht.** Der Wert speist einen
   rekursiven Filter — ein NaN dort ist dauerhaft.

Bewusst BLOCK-Rate, nicht Sample-Rate: `EchoelSVFilter` rechnet bei jeder
Cutoff-Änderung ein `tanf`, und genau dieses Pro-Sample-Transzendente wurde aus der
Stufe absichtlich entfernt. 188 Hz sind bereits ~19× feiner als der 10-Hz-Träger, der
die Treppe verursacht.

## Slice 2 — NÄCHSTER ZYKLUS (Filter zuerst, größte Spanne)

1. `EchoelFXChain` bekommt `filterCutoff` / `filterResonance` als Ziel-Fassade
   (Steuerebene) plus zwei `ParamGlide` (Audio-Seite).
2. `processBuffer` / `processBufferMono` — die EINZIGEN echten Eintrittspunkte, beide
   Voices gehen darüber — steppen den Glide einmal pro Block und schreiben das Ergebnis
   in `filterL/filterR`.
3. Alle sechs externen Stellen auf die Fassade umziehen. Danach ist die Kette der
   einzige Schreiber der Stufe.
4. `setFilter(...)` und `reset()` **snappen** (Dokument laden, leerer Signalweg: es gibt
   nichts, wovon man gleiten könnte, und ein Hochgleiten von einem alten Wert wäre selbst
   das Artefakt). Der 30-Hz-Treiber und der UI-Fader **gleiten**.
5. Pflicht: `audio-thread-reviewer` + Gerätelauf. Ein Glide, den man nicht gehört hat,
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
