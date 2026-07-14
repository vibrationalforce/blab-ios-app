# ECHOEL_RENDER_LAYOUT — JSON-Spezifikation v1.0
## Ring-/Lautsprecher-Geometrie für EchoelRender

> Referenzdokument für Repo + Claude Code. Definiert das Layout-Dateiformat,
> das EchoelRender einliest, um eine `SpatialScene` auf physische Lautsprecher
> zu rendern. Gehört zu `ECHOEL_SESSION_PROTOCOL` (P3 im Spatial-Prompt v2).
>
> **Swift-Modell:** `Sources/Echoelmusic/Core/EchoelRenderLayout.swift` (pure,
> Codable, Foundation-only) parst + validiert dieses Format. Tests:
> `Tests/EchoelmusicTests/EchoelRenderLayoutTests.swift` (die drei Vorlagen unten
> als Round-Trip + Validierung). Das Modell aktiviert NICHTS am Audio-Graph — es
> ist reine Datenschicht, die der (flag-gated) Renderer später konsumiert.

---

## 0. Grundsatz: NICHT neu erfinden — IEM-Format als Basis

Es existiert bereits ein etabliertes, dokumentiertes Format: die
**IEM AllRADecoder `LoudspeakerLayout`-JSON** (die du über IEM Plugin Suite
und Grapes ohnehin nutzt). Diese Spec ist eine **echte Obermenge** davon:

- Die Basis-Struktur ist **byte-für-byte IEM-kompatibel** → jede
  EchoelRender-Layoutdatei lässt sich direkt in AllRADecoder / SimpleDecoder
  und Grapes importieren.
- Alles, was IEM nicht kennt (physische Kanal-Zuordnung, Sub-/Shaker-Gruppen,
  Einmesswerte, Distanzen in Metern, Havarie-Mapping), liegt in einem
  separaten Top-Level-Block `EchoelRender`, den IEM-Tools schlicht ignorieren.

Referenz IEM-Format: <https://plugins.iem.at/docs/configurationfiles/>

---

## 1. Koordinaten-Konvention (identisch zu IEM — nicht abweichen)

| Größe | Konvention |
|---|---|
| **Azimuth** | Grad, float. Front = `0`, **links = +90**, **rechts = −90** (Rechte-Hand-Regel), hinten = `180`/`−180`. |
| **Elevation** | Grad, float. Ohrhöhe = `0`, oben positiv (−90…+90). |
| **Radius** | nur relevant für `IsImaginary: true` (Basis-Format). Reale Distanz → im Echoel-Block in Metern. |
| **Channel** | Integer, 1-basiert. Logischer Ambisonics-/Decoder-Kanal (nicht zwingend = physischer Ausgang). |

> ⚠️ Häufiger Fehler: „rechts = +90" annehmen. IEM/Grapes nutzen **links = +90**.
> Wer das dreht, spiegelt die ganze Bühne. Immer diese Konvention verwenden.

---

## 2. Basis-Schema (IEM-kompatibel, Pflichtteil)

```json
{
  "Name": "Echoel Hexa Ring 6.1",
  "Description": "6er Ground-Stack Ring + 1 Sub, ear-level",
  "LoudspeakerLayout": {
    "Name": "hexa-ground",
    "Loudspeakers": [
      { "Azimuth":    0.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 1, "Gain": 1.0 },
      { "Azimuth":   60.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 2, "Gain": 1.0 },
      { "Azimuth":  120.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 3, "Gain": 1.0 },
      { "Azimuth":  180.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 4, "Gain": 1.0 },
      { "Azimuth": -120.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 5, "Gain": 1.0 },
      { "Azimuth":  -60.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 6, "Gain": 1.0 }
    ]
  }
}
```

Für reine 2D-Ringe (keine Höhenlautsprecher) sollte für den AllRAD-Weg ein
**imaginärer Lautsprecher unten** (`Azimuth 0, Elevation -90, IsImaginary true,
Gain 0`) ergänzt werden, damit die Triangulation eindeutig ist — Standard-IEM-
Praxis. EchoelRender im reinen VBAP-Modus braucht ihn nicht, im Ambisonics-Modus
schon.

---

## 3. Echoel-Erweiterung (`EchoelRender`, optionaler Top-Level-Block)

Alles, was der physische Betrieb braucht. Wird über `Channel` mit dem
Basis-Block verknüpft.

```json
"EchoelRender": {
  "specVersion": "1.0",
  "coordinateSystem": { "azimuthZero": "front", "azimuthPositive": "left", "rightHanded": true, "distanceUnit": "m" },

  "venue": { "name": "Club X", "date": "2026-08-01", "notes": "Ring r=3m, FOH hinten" },

  "output": {
    "device": "MOTU 16A",
    "sampleRate": 48000,
    "channelMap": { "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "sub": 7 }
  },

  "groups": {
    "ring":    { "channels": [1,2,3,4,5,6], "role": "spatial" },
    "subs":    { "channels": ["sub"], "coupling": "mono", "crossoverHz": 90, "cardioid": false },
    "shakers": { "channels": [], "lowpassHz": 80 }
  },

  "speakers": {
    "1": { "distanceM": 3.0, "delayMs": 0.0, "gainTrimDb": 0.0, "limiterPeakDb": -3.0, "model": "Echoel-Top-12CX" },
    "2": { "distanceM": 3.0, "delayMs": 0.0, "gainTrimDb": 0.0, "limiterPeakDb": -3.0, "model": "Echoel-Top-12CX" },
    "3": { "distanceM": 3.0, "delayMs": 0.0, "gainTrimDb": 0.0, "limiterPeakDb": -3.0, "model": "Echoel-Top-12CX" },
    "4": { "distanceM": 3.0, "delayMs": 0.0, "gainTrimDb": 0.0, "limiterPeakDb": -3.0, "model": "Echoel-Top-12CX" },
    "5": { "distanceM": 3.0, "delayMs": 0.0, "gainTrimDb": 0.0, "limiterPeakDb": -3.0, "model": "Echoel-Top-12CX" },
    "6": { "distanceM": 3.0, "delayMs": 0.0, "gainTrimDb": 0.0, "limiterPeakDb": -3.0, "model": "Echoel-Top-12CX" }
  },

  "render": {
    "panner": "vbap",
    "ambisonicsOrder": 3,
    "diffusionFloorHz": 120,
    "defaultFocus": 1.0,
    "distanceModel": { "gain": true, "airAbsorption": true, "delayBasedDistance": false }
  },

  "fallback": {
    "stereo": { "left": [1,2,6], "right": [3,4,5] }
  }
}
```

### Feldreferenz

| Feld | Zweck |
|---|---|
| `coordinateSystem` | Selbstdokumentation; MUSS zur IEM-Konvention passen. |
| `output.channelMap` | logischer `Channel` → physischer Interface-Ausgang. Trennt Decoder-Kanal von Verkabelung. |
| `groups.ring` | die ortenden Tops (VBAP/Ambisonics). |
| `groups.subs` | `coupling:"mono"`, `crossoverHz`, optional `cardioid`. Subs werden **nie** gepannt. |
| `groups.shakers` | optionale Körperschall-Ebene, eigener Lowpass. |
| `speakers.<ch>` | Einmesswerte pro Kanal: `distanceM`, `delayMs` (Alignment auf Ringmittelpunkt), `gainTrimDb`, `limiterPeakDb`/`limiterRmsDb`, `model`. |
| `render.panner` | `"vbap"` (Standard, exakt für beliebige Ringe) oder `"ambisonics"`. |
| `render.diffusionFloorHz` | unterhalb bleibt alles mono/geortet (Diffus-Regler greift nicht). Default 120. |
| `render.defaultFocus` | Start-Fokus neuer Objekte (1.0 = Punktquelle). |
| `fallback.stereo` | Havarie-Preset: welche Kanäle bilden L/R, wenn der Renderer/OSC ausfällt. |

Unbekannte Felder → ignorieren (Vorwärtskompatibilität). Fehlender
`EchoelRender`-Block → Datei ist trotzdem gültig (reines IEM-Layout, Defaults
greifen).

---

## 4. Vollständige Beispiele

### 4.1 Stereo (2 Tops + 1 Sub) — Startstufe
```json
{
  "Name": "Echoel Stereo 2.1",
  "Description": "Startstufe, L/R + Sub",
  "LoudspeakerLayout": {
    "Name": "stereo",
    "Loudspeakers": [
      { "Azimuth":  30.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 1, "Gain": 1.0 },
      { "Azimuth": -30.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 2, "Gain": 1.0 }
    ]
  },
  "EchoelRender": {
    "specVersion": "1.0",
    "coordinateSystem": { "azimuthZero": "front", "azimuthPositive": "left", "rightHanded": true, "distanceUnit": "m" },
    "output": { "device": "any", "sampleRate": 48000, "channelMap": { "1": 1, "2": 2, "sub": 3 } },
    "groups": {
      "ring": { "channels": [1,2], "role": "spatial" },
      "subs": { "channels": ["sub"], "coupling": "mono", "crossoverHz": 90, "cardioid": false }
    },
    "speakers": {
      "1": { "distanceM": 2.5, "delayMs": 0.0, "gainTrimDb": 0.0, "limiterPeakDb": -3.0 },
      "2": { "distanceM": 2.5, "delayMs": 0.0, "gainTrimDb": 0.0, "limiterPeakDb": -3.0 }
    },
    "render": { "panner": "vbap", "diffusionFloorHz": 120, "defaultFocus": 1.0 },
    "fallback": { "stereo": { "left": [1], "right": [2] } }
  }
}
```

### 4.2 Octa (8 Tops + Subs) — Vollausbau
```json
{
  "Name": "Echoel Octa Ring 8",
  "Description": "8er Ground-Stack, 45deg-Raster",
  "LoudspeakerLayout": {
    "Name": "octa-ground",
    "Loudspeakers": [
      { "Azimuth":    0.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 1, "Gain": 1.0 },
      { "Azimuth":   45.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 2, "Gain": 1.0 },
      { "Azimuth":   90.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 3, "Gain": 1.0 },
      { "Azimuth":  135.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 4, "Gain": 1.0 },
      { "Azimuth":  180.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 5, "Gain": 1.0 },
      { "Azimuth": -135.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 6, "Gain": 1.0 },
      { "Azimuth":  -90.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 7, "Gain": 1.0 },
      { "Azimuth":  -45.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 8, "Gain": 1.0 },
      { "Azimuth":    0.0, "Elevation": -90.0, "Radius": 1.0, "IsImaginary": true, "Channel": 9, "Gain": 0.0 }
    ]
  },
  "EchoelRender": {
    "specVersion": "1.0",
    "coordinateSystem": { "azimuthZero": "front", "azimuthPositive": "left", "rightHanded": true, "distanceUnit": "m" },
    "output": { "device": "Dante", "sampleRate": 48000,
      "channelMap": { "1":1,"2":2,"3":3,"4":4,"5":5,"6":6,"7":7,"8":8,"subA":9,"subB":10 } },
    "groups": {
      "ring": { "channels": [1,2,3,4,5,6,7,8], "role": "spatial" },
      "subs": { "channels": ["subA","subB"], "coupling": "mono", "crossoverHz": 90, "cardioid": true },
      "shakers": { "channels": [], "lowpassHz": 80 }
    },
    "render": { "panner": "vbap", "ambisonicsOrder": 3, "diffusionFloorHz": 120, "defaultFocus": 1.0,
      "distanceModel": { "gain": true, "airAbsorption": true, "delayBasedDistance": false } },
    "fallback": { "stereo": { "left": [1,2,3,8], "right": [4,5,6,7] } }
  }
}
```
(Hexa = Beispiel aus Abschnitt 2 + Echoel-Block analog.)

---

## 5. Wie EchoelRender die Datei nutzt

1. **Geometrie** aus `LoudspeakerLayout.Loudspeakers` → Panner-Aufbau
   (VBAP-Triangulation bzw. Ambisonics-Decoder).
2. **Routing** aus `EchoelRender.output.channelMap` → welcher logische Kanal
   auf welchen Interface-Ausgang.
3. **Einmessung** aus `EchoelRender.speakers.<ch>` → Delay/Gain/Limiter je Kanal.
4. **Objektpositionen** kommen zur Laufzeit per **OSC/ADM-OSC** herein (App →
   Renderer). Der ADM-OSC-Objektpunkt (Azimut/Elevation/Distanz bzw. x/y/z)
   wird per Panner auf diese Speaker-Geometrie abgebildet. Das Layout
   beschreibt die Boxen, ADM-OSC beschreibt die bewegten Objekte — beide teilen
   die Winkelkonvention aus Abschnitt 1.
5. **Subs**: `groups.subs` → mono gekoppelt, unterhalb `crossoverHz`; nie
   gepannt; `diffusionFloorHz` verhindert Diffusion im Bass.
6. **Havarie**: fällt der OSC-Strom/Renderer aus, greift
   `fallback.stereo` → Stereo-Summe läuft weiter.

---

## 6. Validierungsregeln

- Jeder `ring`-Kanal MUSS einen Eintrag in `LoudspeakerLayout.Loudspeakers`
  (per `Channel`) UND in `output.channelMap` haben.
- `subs`/`shakers`-Kanäle dürfen NICHT in `LoudspeakerLayout` stehen (sie
  werden nicht gepannt) — nur in `channelMap`.
- Azimut-Werte eindeutig; Ring idealerweise gleichmäßig verteilt.
- `fallback.stereo.left`/`right` dürfen nur `ring`-Kanäle referenzieren.
- Reiner 2D-Ring im Ambisonics-Modus → imaginärer Boden-Lautsprecher Pflicht.
- Datei ohne `EchoelRender`-Block ist gültig (IEM-Layout, Defaults).

---

## 7. Interoperabilität

- **IEM AllRADecoder / SimpleDecoder / Grapes**: Basis-Block importiert direkt;
  Echoel-Block wird ignoriert. Round-Trip verlustfrei für die Geometrie.
- **ADM-OSC**: gemeinsame Winkelkonvention → Objektsteuerung aus Fremdsystemen
  (Adamson FletcherMachine, L-ISA, d&b Soundscape) auf dasselbe Layout möglich.
- **Layout-Generatoren**: Web-Tools, die IEM-AllRAD-JSON exportieren (z. B.
  Dome-Layout-Generatoren), sind direkt als Ausgangspunkt nutzbar — danach nur
  den `EchoelRender`-Block ergänzen.
- **Session-Protokoll**: Diese Datei ist der `layout`-Teil von
  `ECHOEL_SESSION_PROTOCOL`; Versionierung über `specVersion`.

---

### Kurz
Basis = IEM (nichts neu erfunden, direkt in deinen Tools nutzbar). Der
`EchoelRender`-Block ergänzt nur Routing, Einmessung, Sub-/Shaker-Gruppen und
Havarie. Drei fertige Vorlagen (Stereo/Hexa/Octa) liegen bei.
