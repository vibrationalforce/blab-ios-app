# Pivot Plan — Echoel Live Studio
**Date:** 2026-04-18  
**Status:** DRAFT — awaiting confirmation before any code changes

---

## The Vision (Michael's words, distilled)

> Impro-Session, 2:30 min → klingt professionell → direkt als Single veröffentlichbar.
> Gleichzeitig live gestreamt mit Video + Visuals.
> Alles in EINEM Screen auf dem iPhone. Kein Fensterwechsel.
> Landscape/macOS mit Touch/Maus.
> Multi-User, Worldwide, Echtzeit.

---

## Was das NICHT ist

- Kein DAW im klassischen Sinn (kein Arrange-View, keine Tracks im Vordergrund)
- Kein Ableton-Klon (zu viel Lernkurve, falsche Zielgruppe)
- Kein Soundscape-Generator (zu wenig für Produzenten)
- Kein Feature-Stapel (jedes Feature muss in 30 Sekunden findbar sein)

---

## Was das IST

**Ein Live Music Studio** — du spielst, es klingt professionell, du streamst, du veröffentlichst.

Drei Sätze für den App Store:
1. Spiel. Klinge sofort professionell.
2. Stream es live — Video, Visuals, dein Herzschlag.
3. Veröffentliche die Session als Single — direkt aus der App.

---

## Die entscheidende technische Innovation

**"Instant Pro Sound"** — das Schwierigste und Wertvollste.

Der Nutzer weiß nicht wie man mixt. Das App weiß es. Konkret:
- Auto-Gain-Staging beim Hinzufügen jedes Instruments
- Smart Compression (Instrumente ducken automatisch wenn Melodie spielt)
- Referenz-EQ-Kurven je nach Genre/Stimmung
- LUFS-Target Mastering (-14 LUFS Streaming, -9 LUFS Club) — ein Knopf
- Spatial Reverb der immer passt (Room → Hall → Space je nach Energie)
- Quantization die musikalisch klingt (Swing, Groove templates, nicht starr)

Das ist keine KI-Magie — das ist gute DSP-Voreinstellung + vDSP + Limiter + LUFS-Messung.
Alles bereits im Stack vorhanden, nur noch nicht als "Auto-Mix-Chain" verdrahtet.

---

## UI-Konzept: ONE SCREEN

### iPhone Portrait — Performance View

```
┌─────────────────────────────────────────┐
│  ● REC   00:02:17   ⚡ Live   👁 342    │  ← Status Bar
├──────────────┬──────────────────────────┤
│              │   ♥ 72bpm  HRV 45ms     │
│              │   ════════════ -12 LUF   │  ← Bio + Level
│  INSTRUMENT  │   ────────────────────   │
│  PLAY AREA   │   [TRACK 1] Pad    ●    │
│              │   [TRACK 2] Bass   ●    │  ← Live Mixer
│  (Touch)     │   [TRACK 3] Drums  ○    │  (minimal)
│              │   ────────────────────   │
│              │   [AUTO MIX]  [MASTER]  │
├──────────────┴──────────────────────────┤
│  [KEYS] [PADS] [LOOPS] [BIO] [STREAM]  │  ← Mode Strip
└─────────────────────────────────────────┘
```

Kein separates Mixer-Fenster. Kein separates FX-Fenster. Alles sichtbar.

### iPhone Landscape / macOS — Studio View

```
┌──────────┬───────────────────┬──────────┐
│          │                   │ STREAM   │
│ INSTRUM. │   ARRANGEMENT /   │ ● LIVE   │
│ LIBRARY  │   SESSION GRID    │          │
│          │   (Ableton-style  │ Camera   │
│ [Synth]  │    Clip Launch)   │ Visuals  │
│ [Pads]   │                   │ Bio HUD  │
│ [Bass]   ├───────────────────┤          │
│ [Drums]  │  MIXER + MASTER   │ EXPORT   │
│ [Live]   │  (channel strips) │ [Single] │
└──────────┴───────────────────┴──────────┘
```

Drei Zonen. Immer sichtbar. Keine Navigation.

---

## Was bereits existiert (NICHT neu bauen)

| Modul | Verwendung in neuem Produkt |
|-------|----------------------------|
| `AudioEngine` | Master Engine — unverändert |
| `EchoelDDSP` | Pad-Instrument + Auto-Harmony-Layer |
| `EchoelSynth` (5 Engines) | Melodie/Lead/Bass Instrumente |
| `EchoelCellular` | Ambient-Texture-Track (automatisch) |
| `EchoelModalBank` | Percussion/Bells/Atmospheres |
| `EchoelLFO` + `EchoelSVFilter` | Auto-Animation der Sounds |
| `BioSourceManager` | Bio-HUD + reaktive Modulation |
| `EchoelEntrainment` | Rhythmus-Sync mit Bio |
| `MIDIInput` | MIDI-Controller Support |
| `CameraCapture` | Stream-Video-Input |
| `OSC Networking` | Externe Controller, Multi-Device |
| `SPSCQueue` | Lock-free Audio-Pipeline |
| `CrashSafeStatePersistence` | Session-Autosave |
| AUv3 Infrastructure | Plugin-Hosting |

---

## Was neu gebaut werden muss (Phase 1)

### 1. RetroCapture (Always-Recording Ring Buffer)
**Was:** 10-Minuten-Ringpuffer — alles wird aufgenommen, auch was vor dem Drücken von REC war.
**Warum:** "Ich hätte das aufnehmen sollen" ist nie wieder ein Problem.
**Technisch:** `[Float]`-Ringpuffer auf `AudioEngine`-Ebene, ~50MB bei 48kHz/Stereo/10min
**File:** `Audio/RetroCapture.swift` (neu)

### 2. AutoMixChain
**Was:** Gain-Staging, Kompression, LUFS-Messung, Limiter — automatisch auf Master-Bus.
**Warum:** Klingt sofort professionell ohne Mixer-Kenntnisse.
**Technisch:** AVAudioUnitEQ + AVAudioUnitDynamicsProcessor + LUFS via vDSP
**File:** `Audio/AutoMixChain.swift` (neu)

### 3. LiveStreamEngine
**Was:** RTMP-Output direkt aus AVCaptureSession → YouTube/Twitch/RTMP-Endpoint.
**Warum:** Kein OBS nötig. Ein Button.
**Technisch:** `AVAssetWriter` mit RTMP via `VideoToolbox` + `Network.framework`
**File:** `Core/LiveStreamEngine.swift` (neu)
**Alternative für MVP:** ReplayKit `RPScreenRecorder` → RTMP via HaishinKit (einzige sinnvolle externe Dep)

### 4. SessionGrid (Clip Launch)
**Was:** Ableton-style Clip-Matrix — vertikale Szenen, horizontale Tracks, Tap-to-Launch.
**Warum:** Der Kern der Live-Performance-Logik.
**Technisch:** SwiftUI Grid + `SoundscapeEngine` Clip-Scheduling, quantisiert auf Beat
**File:** `Views/SessionGridView.swift` (neu) + `Core/ClipEngine.swift` (neu)

### 5. MasterView (iPhone Portrait)
**Was:** Der eine Screen der alles zeigt — Status, Instrument, Mini-Mixer, Bio, Mode-Strip.
**Warum:** Kein Fensterwechsel. Das ist das Produkt.
**File:** `Views/MasterView.swift` (neu, ersetzt `SoundscapeView`)

### 6. SingleExport
**Was:** Mastering + Export als WAV/AAC/AIFF, direkt teilbar.
**Warum:** 2:30 Impro → veröffentlichungsfertig.
**Technisch:** `AVAudioFile` + LUFS-normalisiert + Metadata (ID3/MP4)
**File:** `Core/SingleExport.swift` (neu)

---

## Was Phase 2 ist (NICHT Phase 1)

- Multi-User Echtzeit-Session (WebRTC Audio — komplex)
- Spatial Audio Export (Dolby Atmos / ASAF)
- Spatial Video
- Visual Shader-System (Metal — CameraAnalyzer Basis existiert)
- macOS vollständige Desktop-UI
- Vision Pro

---

## Alte Fehler die wir diesmal vermeiden

| Fehler | Schutz |
|--------|--------|
| Feature ohne UI | Jedes neue Feature hat eine View die es zeigt |
| Engine ohne Init | Jedes Modul wird in `EchoelmusicApp.init` verdrahtet |
| Zu viele Baustellen | Max 1 offenes Feature gleichzeitig (Ralph Wiggum) |
| UI-Wechsel verstecken Features | One-Screen-Prinzip — alles sichtbar |
| Bio als Core statt Layer | Bio ist Overlay, nicht Pflicht für Audio |
| Rewrite statt Evolution | Bestehende Audio-DSP bleibt unverändert |

---

## Reihenfolge (strikt)

```
1. MasterView.swift       — der eine Screen (Shell zuerst)
2. RetroCapture           — always recording (Fundament)
3. AutoMixChain           — instant pro sound (Differenziator)
4. SessionGridView        — clip launch (Performance)
5. LiveStreamEngine       — RTMP out (USP)
6. SingleExport           — finalize & publish (Abschluss)
```

Jedes Feature: Baut auf dem vorigen auf. Keins überspringen.

---

## Produktname

**Echoel** — Live Music Studio  
Bundle: `com.echoelmusic.*` (unverändert)  
App Store ID: 6757957358 (unverändert)

Untertitel: "Record. Stream. Release."

---

## Freigabe-Frage

Bevor Code: Ist das die richtige Reihenfolge?  
Stimmt die One-Screen-UI-Idee?  
Soll Phase 2 Multi-User früher kommen?
