# Live Monitoring + Vocal Chain — gemessener Bestand & Plan

**Founder-Ask 2026-08-19 (wörtlich):** „Live monitoring reparieren und für jede Art von
Situation optimieren egal ob in Device oder mit zusätzlicher Hardware. -zusätzlich
Harmonizer, Voice clone, granular, Autotune, pitch Shift, vocal chain."

**Alles unten ist GEMESSEN** (`git grep` am 2026-08-19), nicht erinnert. Jede Zeile nennt
ihren Beleg, damit die nächste Sitzung sie neu ableiten statt glauben kann.

---

## A — WAS ES HEUTE SCHON GIBT (und deshalb NICHT neu gebaut wird)

| Ding | Stand | Beleg |
|---|---|---|
| **Live-Monitoring** | gebaut, erreichbar | `AudioEngine.setInputMonitoring`, Tür = Master-Panel „Audio input" → `.sheet($showInput)` `EchoelStudioView.swift:1463` |
| **Autotune** („Tune to key") | **gebaut + erreichbar**, mit Stärke + Retune-Regler | `voiceTuneEnabled/Strength/Retune`, `VoicePitchCorrector`, YIN via `PitchTracker`; Tür `AudioInputPickerView.swift:229ff` |
| **Pitch Shift** (Monitor) | gebaut | `AVAudioUnitTimePitch` als `voiceTunePitch`, im Monitorpfad zwischen Notch und Monitor-Mixer |
| **Feedback-Schutz** | gebaut, zwei Hälften | `FeedbackGuard` Duck (Level) + `notchEQ` parametrische Kerbe (#595), ~15 Hz Tick |
| **Route-Wechsel-Re-Arm** | **GEBAUT (#612)** | `rearmInputMonitoring(reason:)`; Aufrufer = `start()` + der `.AVAudioEngineConfigurationChange`-Zweig, der `inputNode`-Rate gegen `monitorTapSampleRate` vergleicht |
| **Harmonizer** | gebaut — **aber nicht am Mikrofon** | `EchoelHarmonizer` lebt in `EchoelFXChain`; Intervalle als `HarmonyInterval`-Picker in `EchoelFXView` |
| **Zeit-/Tonhöhen-Kern** | gebaut | `EchoelWSOLA` (Stretch/Shift), heute von `AudioClipPlayer`/`AudioLanePlayer` benutzt |
| **Stimm-Analyse** | verdrahtet seit #592a | `VoiceAnalyzer` + `VoiceFrame` ← `VoiceCaptureEngine`, Tür Sound-Panel „Voice timbre" |

⛔ **Meine erste Hypothese war FALSCH und steht hier als Warnung:** ich hielt den
Route-Wechsel-Re-Arm für den offenen Defekt („reparieren"), weil ZWEI ⚠️-Kommentare an der
Tap-Install-Stelle ihn als ausstehend beschrieben („a route-change re-arm of monitoring is
the honest fix if this shows up on device"). #612 hat ihn längst gebaut. Die Kommentare sind
in diesem Zyklus mit ⛔-Rücknahme korrigiert — eine Prosa, die eine erledigte Reparatur als
offen führt, ist eine ANWEISUNG an die nächste Sitzung, sie ein zweites Mal zu bauen.

## B — WAS ES NICHT GIBT (0 Treffer in `Sources/`)

- **Granular** — `git grep -lE "granular|Granular" -- Sources` = **0**. Nichts, kein Kern.
- **Voice clone** — 0 Treffer. Kein Modell, kein Sampler-Pfad, keine Zustimmungs-Fläche.
  ⚠️ Trägt eine eigene Rechtsfrage (Einwilligung, Persönlichkeitsrecht) und die
  KEIN-AUDIO-wird-gespeichert-Zusage der Release-Notes — das ist ein Founder-Beschluss,
  keine Scheibe.
- **`VocoderMapping`** — existiert als reiner Kern, **0 Verbraucher** (die Ausgabe-Hälfte
  von VocoderCore, siehe CLAUDE.md).

## C — DER EIGENTLICHE STRUKTURBEFUND (die Antwort auf „vocal chain")

**`EchoelFXChain` läuft NUR in den zwei Synthesestimmen** — `BioReactiveSynthVoice.swift:154`
und `PolySynthVoice.swift:333`. `git grep -n "EchoelFXChain\|fxChain" -- AudioEngine.swift`
= **0 Treffer.**

Konsequenz, unmissverständlich: **die Mikrofon-Monitorkette hat überhaupt keine FX.** Sie ist
`input → notchEQ → [voiceTunePitch] → monitorMixer → masterMixer`. Harmonizer, Reverb, Delay,
Chorus, Bitcrush, Widener, Kompressor, Limiter — alle vorhanden, alle für die Stimme
unerreichbar. Das ist der Grund, warum „zusätzlich Harmonizer … vocal chain" sich wie ein
neues Feature anfühlt, obwohl 90 % des DSP schon im Repo liegt.

**Das ist die Fundament-Scheibe.** Granular, Voice-Clone und jeder weitere Stimmeffekt
brauchen sie zuerst; ohne sie baut man jedes Mal eine zweite Einzelverdrahtung wie
`voiceTunePitch` heute.

## D — RANGFOLGE (Vorschlag, Founder entscheidet die Spitze)

1. **V1 — Vocal Chain ans Mikrofon.** `EchoelFXChain` als Insert im Monitorpfad
   (`notchEQ → [tune] → fxChain → monitorMixer`), eigene Preset-Instanz getrennt von der
   Musik-Kette. Damit sind Harmonizer + 13 weitere Stufen sofort auf der Stimme.
   ⚠️ Braucht Council: eigener Render-Pfad, Audio-Thread, Latenzbudget (<10 ms),
   und der Notch/Duck-Schutz muss VOR den FX bleiben, sonst schaukelt sich Reverb auf.
2. **V2 — Latenz- und Situations-Härtung** („egal ob Device oder Hardware"): Buffer-Größe
   und Monitor-Weg je Route wählen (eingebautes Mikro vs. USB-Interface vs. Bluetooth —
   letzteres 150–250 ms, für Monitoring unbrauchbar und muss das ehrlich SAGEN statt
   still schlecht zu klingen). Heute gibt es dafür keine Fallunterscheidung.
3. **V3 — Granular** auf `EchoelWSOLA` aufsetzend (der Zeitbereichs-Kern existiert).
4. **V4 — Voice clone**: erst Founder-Beschluss (Recht + Einwilligung + Speicherzusage),
   dann Technik. Nicht vorher anfangen.

## E — WAS ICH NICHT WEISS (und was die Reihenfolge kippen kann)

„Reparieren" impliziert einen beobachteten Defekt am Gerät. Ich habe keinen Diag-Log und
keinen Clip dazu. Die vier plausiblen Beobachtungen führen zu VERSCHIEDENEN Scheiben:
- **kein Ton beim Monitoring** → Tür/Permission/Route, nicht FX;
- **Rückkopplung/Pfeifen** → Notch+Duck-Abstimmung;
- **hörbare Verzögerung** → V2 (Buffer/Route), nicht V1;
- **falsche Tonhöhe bei „Tune to key"** → der #612-Re-Arm greift nicht (Route-Wechsel ohne
  Configuration-Change-Notification) — das ist der einzige Fall, der eine ECHTE neue
  Reparatur im Monitor-Kern bedeutet.
