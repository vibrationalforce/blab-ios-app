# V1 — Vocal Chain ans Mikrofon (Founder-Wahl 2026-08-19)

**Ziel in einem Satz:** die 14 Stufen von `EchoelFXChain` — Harmonizer voran — sollen die
LIVE-STIMME erreichen, nicht nur die zwei Synthesestimmen.

**Alles unten ist gemessen** (`git grep`, 2026-08-19), nicht erinnert.

---

## 1 — Der Befund, der die ganze Scheibe erklärt

`EchoelFXChain` wird an genau ZWEI Stellen konstruiert: `BioReactiveSynthVoice.swift:154`
und `PolySynthVoice.swift:333`. In `AudioEngine.swift`: **null Treffer**.

Die Mikrofonkette ist heute
`input → notchEQ → [voiceTunePitch] → monitorMixer → masterMixer` — **roh.** Harmonizer,
Reverb, Delay, Chorus, Flanger, Phaser, Tremolo, Bitcrush, Saturation, Tape, Widener,
Kompressor, Limiter: alle gebaut, alle für die Stimme unerreichbar.

## 2 — Warum das nicht „einfach einhängen" ist

`EchoelFXChain` ist **kein `AVAudioUnit`**. Es ist eine reine Swift-Klasse mit
`processStereo(_ inL: Float, _ inR: Float) -> (Float, Float)` — **per Sample, pur,
allokations- und sperrfrei**, und sie läuft heute schon in `AVAudioSourceNode`-Render-Blöcken.
Das ist die gute Nachricht: die DSP-Hälfte ist fertig und audio-thread-tauglich.

Die schlechte: AVAudioEngine kann fremdes DSP nicht in eine bestehende Verbindung einfügen.
`installTap` **liest nur** und kann Audio nicht verändern. Es braucht eine Brücke:

```
input → notchEQ → [voiceTunePitch] → AVAudioSinkNode → SPSC-Ring → AVAudioSourceNode
                                                                    (EchoelFXChain hier)
                                                                        → monitorMixer
```

**Kein `AVAudioSinkNode` existiert heute im Repo** (`git grep AVAudioSinkNode -- Sources`
= 0). Der Ring dagegen schon: `Core/SPSCQueue` ist der lock-freie Träger des EngineBus.
Sechs `AVAudioSourceNode(`-Konstruktionsstellen belegen das Hausmuster.

## 3 — Der PREIS, ehrlich vorab

Sink und Source werden pro Render-Zyklus beide gerufen, aber ihre Reihenfolge ist nicht
garantiert ⇒ **ein Puffer Zusatzlatenz**, bei 256 Frames / 48 kHz ≈ **5,3 ms**, oben auf die
bestehende IO-Latenz. Das Performance-Budget in CLAUDE.md ist `<10 ms` Audio-Latenz, FAIL bei
`>15 ms`. **Diese Scheibe kann das Budget reißen**, und das ist der Grund, warum V1a unten
zuerst NUR die Brücke misst, bevor irgendein Effekt daran hängt.

Zweiter Preis: der Monitor-Weg bekommt einen zweiten Render-Block. Der Duck/Notch-Schutz
(`FeedbackGuard`, ~15 Hz) misst weiter am Ausgang — das bleibt richtig, siehe 4.

## 4 — Die Reihenfolge im Signalweg ist NICHT verhandelbar

**Notch und Duck bleiben VOR der FX-Kette.** Ein Reverb oder Delay vor dem
Rückkopplungsschutz macht den Schutz zum Jäger seines eigenen Schwanzes: er senkt ab, die
Hallfahne trägt den alten Pegel weiter, er senkt erneut. Der Guard misst am Ausgang und
regelt `monitorMixer.outputVolume` — das steht hinter der FX-Kette und bleibt damit korrekt,
solange die FX zwischen Notch und Monitor-Mixer sitzen und nicht dahinter.

## 5 — Getrennte Preset-Instanz, nicht die Musik-Kette

Die Stimme bekommt ihre EIGENE `EchoelFXChain`. Sie mit der Musik zu teilen hieße, dass ein
Genre-Preset die Stimme mit umstellt (die Genre-Presets schalten Reverb und Harmonizer ein)
— eine Kopplung, die niemand verlangt hat und die auf der Bühne unvorhersehbar ist.

## 6 — Scheiben (jede einzeln shippbar, Ralph-Takt)

- **V1a — die Brücke, PASS-THROUGH.** Sink → SPSC-Ring → Source, ohne jeden Effekt.
  Beweist: Audio überlebt, nichts knackst, und **misst die Zusatzlatenz** gegen das Budget.
  Wächter: Ring-Verhalten (Über-/Unterlauf, Kanalzahl, Rate-Wechsel) als reiner Werttyp-Test.
  ⚠️ **Abbruchkriterium:** reißt die gemessene Latenz die 15 ms, wird V1 neu entworfen
  (z. B. FX nur auf der AUFNAHME statt auf dem Monitor) statt durchgedrückt.
- **V1b — `EchoelFXChain` in den Source-Render-Block**, eigene Instanz, Bypass per Default.
- **V1c — die Tür.** Abschnitt „Voice FX" im vorhandenen Audio-input-Sheet (KEIN neuer
  Sheet — die Präsentationskette steht bei 14/16, Black-Screen-Gesetz). Vokabel und
  Bedienelemente aus `EchoelFXView` übernehmen, `EchoelValueField` für jeden Zahlenwert.
- **V1d — Bio-Route auf die Stimm-FX** (optional, danach): der Körper bewegt den Harmonizer.

## 7 — Council-Verdikt (2026-08-19)

- **Architect:** Brücke gehört nach `Audio/`, nicht `DSP/` — sie braucht `SPSCQueue` aus
  `Core/`, und DSP-Dateien dürfen keine Core-Typen sehen (AUv3 kompiliert `DSP/` isoliert).
  Sorge: ein zweiter Render-Block auf dem Monitorweg ist neue Kopplung im heikelsten Pfad.
- **DSP Purist:** `processStereo` ist per-Sample und allokationsfrei — tauglich. Sorge: der
  Ring MUSS lock-frei bleiben; ein `NSLock` dort wäre ein Audio-Thread-Verstoß.
- **Skeptic:** die Latenz ist das Risiko, nicht die DSP. Billigster Weg, falsch zu liegen:
  V1a bauen und MESSEN, bevor ein Effekt daran hängt. Genau deshalb ist V1a Pass-through.
- **Shipper:** vier kleine Scheiben statt einer großen; jede einzeln grün.
- **User-Advocate:** der Founder hat das ausdrücklich gewählt; die Stimme ist das, was auf
  der Bühne zählt. Aber eine Vocal Chain auf einem Monitor, der Ton killt, ist wertlos —
  **#625 muss zuerst am Gerät bestätigt sein.**

**Gate: proceed-with-mitigation.** Reihenfolge: erst die Geräteprobe von #625 (kommt der Ton
zurück?), dann V1a mit hartem Latenz-Abbruchkriterium.

## 8 — Was diese Scheibe NICHT ist

Granular und Voice Clone hängen an derselben Brücke, kommen aber später (Voice Clone braucht
zuerst einen Founder-Beschluss zu Einwilligung/Recht und zur „KEIN AUDIO wird je gespeichert"-
Zusage). Autotune und Pitch Shift existieren bereits und werden NICHT neu gebaut.
