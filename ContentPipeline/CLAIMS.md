# CLAIMS — was Echoel heute WIRKLICH kann

**Diese Datei ist die Quelle für jedes Skript, jede Caption, jedes Thumbnail.**
Sie steht bewusst VOR den Templates in dieser Pipeline, weil das Grundproblem von
Marketing-Content nicht das Format ist, sondern die Behauptung.

Zwei ganze Arbeitszyklen (#158, #192) wurden damit verbracht, EINE falsche Behauptung
wieder aus acht Dateien und ~25 Stellen der Website zu entfernen. Ein weiterer (#184)
entfernte zwölf falsche Behauptungen aus dem App-Store-Text — dort ist eine falsche
Behauptung ein 2.3-Ablehnungsgrund („Accurate Metadata"). Ein Skript, das eine
gestrichene Behauptung wieder einführt, macht diese Arbeit rückgängig.

Stand: 2026-07-30, v10.79.360. **Vor jeder neuen Kampagne gegen `CLAUDE.md`
„CURRENT STATE" und `docs/dev/FEATURE_MATRIX.md` gegenprüfen.**

---

## ✅ DARF behauptet werden — gebaut, verdrahtet, am Gerät gesehen

| Behauptung | Beleg |
|---|---|
| Der Puls wird **mit der iPhone-Kamera** gemessen (Finger auf die Linse, rPPG) | live; Log 2477: Lock in 14 s, danach Minuten bei Confidence 0,8–0,96 |
| Herzschlag, HRV und Kohärenz **modulieren Klang in Echtzeit** | `EchoelDDSP` Bio-Mappings, `FXBioModulator` |
| **Generative Komposition** in gewählter Tonart/Skala/Genre, tonartrein | `BioComposer`, 57 Skalen, 15 Stimmungssysteme |
| **Bio-reaktive Visuals** live auf dem Gerät (Metal) | `MetalBioView`, `FloatingVisualWindow` |
| **Licht: Art-Net + sACN** (DMX über Netzwerk), Grand Master + Blackout | EchoelLux, unicast live |
| **Immersiver Raum: ADM-OSC** Objekt-Ausgabe (`/adm/obj/{n}/*`) | `ADMOSCSender` |
| **OSC-Ausgabe** des Bio-Signals an jede Software im Netz | `OSCSender`, Adressliste in `CLAUDE.md` |
| **MIDI-Export** der erzeugten Musik als `.mid` | `MIDIFileExporter`, Tür im Export-Schacht |
| **MIDI-Eingang**: externer Controller spielt die Stimmen | CoreMIDI → `controllerEvents` |
| **Universeller BLE-Herzgurt** (0x180D), z. B. Polar H10 | gebaut + verdrahtet, Geräte-Verify offen — **so kennzeichnen** |
| **Apple Health** als Pulsquelle | `HealthKitBioPublisher` |
| **Offene Standards, kein SDK-Lock-in** | OSC · ADM-OSC · MIDI · Art-Net/sACN · BLE HRS |
| **Null externe Abhängigkeiten**, alles on-device | `Package.swift: dependencies: []` |
| **Barrierefrei spielbar**: Notennamen International/Deutsch/Solfège, VoiceOver auf der Spielfläche, Atkinson Hyperlegible | #232 C/E, `EchoelValueField` |

---

## ⛔ DARF NICHT behauptet werden — und warum genau

### 1. „AUv3-Plugin", „läuft in Logic/Ableton/GarageBand", „in Deiner DAW"
**Das AUv3-Target wurde am 2026-07-24 ENTFERNT** (#121 Slice 1+2, Founder-Verdikt
„reines Instrument"). Echoel ist eine eigenständige App und **kein Plugin**. Es kann
auch keine fremden Plugins laden — das Hosting ging im selben Schritt.
`project.yml:177` sagt es wörtlich. Ein AUv3-Claim ist doppelt falsch (Ziel + Host)
und war exakt der Claim, den #158 aus der Website entfernt hat.
*Wenn ein Bild eine DAW-Spur zeigt, ist es das falsche Bild.*

### 2. Wellness, Meditation, Schlaf, Fokus, Stressabbau, Longevity, „HealthTech"
`CLAUDE.md`: **„Biofeedback ist Kern, NICHT Wellness."** Echoel ist ausdrücklich kein
Wellness-, Soundscape- oder Therapieprodukt. Das ist keine Geschmacksfrage:
Heilungs-/Organ-/Frequenz-Claims sind Alt-Last aus einem Vorgängerprojekt und eine
permanente rote Linie, und in der App steht der Satz „für Selbstbeobachtung, nicht
für medizinische Diagnose". Ein Reel, das „nutze es für Meditation und
Schlafoptimierung" sagt, widerspricht dem Text in der eigenen App.
**Erlaubt** ist die Beschreibung des Mechanismus: *„ruhiger Puls → andere Musik."*
**Nicht erlaubt** ist die Wirkungsbehauptung: *„macht Dich ruhig / hilft beim Schlafen."*
Der Unterschied entscheidet auch über die App-Store-Kategorie.

### 3. Apple Watch misst und steuert
`Sources/EchoelmusicWatch/EchoelWatchApp.swift` ist eine **95-Zeilen-Anzeige**: sie
LIEST die Werte, die das iPhone in die App-Gruppe schreibt. Die Produzenten-Hälfte
(Puls am Handgelenk → App-Gruppe → Telefon) ist **nicht gebaut** und im Kopf der Datei
als offen markiert. Dazu die harte Grenze aus `CLAUDE.md`: Watch-HR hat 4–5 s Latenz,
**niemals** Beat-Sync. Ein Hook, der mit einer pulsierenden Watch aufmacht, verkauft
die Richtung falsch herum. **Der echte Hook ist der Finger auf der Kamera** — er ist
wahr, er braucht kein Zusatzgerät, und er sieht besser aus.

### 4. „Im App Store" / Store-Link
Es gibt heute **nur TestFlight**. Erst nach der ersten Freigabe umstellen.

### 5. Drums, Beats, Sampler, Sample-Import, Video-Schnitt, RTMP-Livestream, Mehrspur-Recorder
Alles entfernt oder nie gebaut (#166/#167 Drums, #121 Slice 3 Video-Schnitt;
`BroadcastPublisher` ist ein Compile-Gerüst ohne verlinktes Backend).

### 6. MPE
Aus dem I/O-Satz gestrichen — die Schalter haben seit dem Tools-Grid-Removal keinen
Schreiber.

---

## Sprache

- Marke: **Echoel**. Nie „BLAB", „Vibrational Force", nie Heilfrequenzen, Chakren, Solfeggio.
- **Wissenschaft zuerst:** lesbare Zahl vor Deko-Visual. HRV-Resonanz ist zitierbar
  (Lehrer/Vaschillo, Goessl 2017) — als *Forschungslage*, nie als Versprechen.
- Blitzrate in jedem Videomaterial **≤ 3 Hz** (W3C WCAG, Epilepsie). Das gilt auch für
  den Schnitt, nicht nur für die App.
- Diese Pipeline ist **PIPELINE-ONLY**: sie fasst `Sources/` niemals an.
