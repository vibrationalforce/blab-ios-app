# Vision ↔ Realität — Echoelmusic (Stand 2026-07-10, v10.79.144)

**Für den Founder: was ist JETZT real, was ist gebaut-aber-unsichtbar, was ist
zugesagt, was ist ehrlich fern.** Jede Zeile in genau EINER Stufe; ✅-Zeilen
tragen Datei-Belege. Quellen: Code (die Wahrheit), FEATURE_MATRIX, vision.md,
decisions, die beiden Audits vom 2026-07-10.

Legende: ✅ **REAL** (läuft in v10.79.144 auf dem Gerät) · 🔧 **GEBAUT, UNVERDRAHTET**
(Kern existiert + getestet, nichts präsentiert es) · 🗺 **ROADMAP** (beschlossen,
noch kein Code) · ⭐ **NORTH STAR** (Konzept, ehrlich fern — nie Produkt-Copy)

> Der eine Satz: *Das Instrument, bei dem EIN Körper Klang, Bild, Licht und Raum
> gleichzeitig spielt — iPhone-first, offene Standards, ohne Konto, ohne Server.*

---

## 1 · Body — der Differenzierer

| Stufe | Fähigkeit | Beleg |
|---|---|---|
| ✅ | Herz/HRV/Atem/Kohärenz live: HealthKit + **jeder** BLE-Gurt (0x180D) + Kamera-rPPG (lockt am Gerät) + Demo | `Bio/EchoelBioEngine`, `Bio/CameraRPPGBioPublisher` |
| ✅ | Echte frequenzbasierte HRV-Kohärenz (Lomb-Scargle + Welch) | `Bio/HRVCoherence.swift` |
| ✅ | Geschützte DSP-Triade (Event-Graph · Hilbert-Mapping · Deconvolver) | `Bio/BioEventGraph` u. a., SKILL-Verträge |
| ✅ | Tap-to-learn Bio-Metriken, Resonanz-Atem-Guide, rPPG-Watchdog + Sättigungs-Hold | `Studio/BioMetricInfo`, FEATURE_MATRIX #6 |
| 🗺 | EEG-Bandpower (LSL), Raw-PPG/EKG, Face-Tracking (ARKit) | FEATURE_MATRIX-Ideenraum — kein Code |

## 2 · Sound

| Stufe | Fähigkeit | Beleg |
|---|---|---|
| ✅ | Bio-generativer Komposer: 23 Genres, Tonart/Kammerton, seeded & reproduzierbar; Körper treibt Struktur | `MusicStyle.swift`, `BioComposer` |
| ✅ | PolySynth + SubBass + Hybrid-Drums (Sample+Synthese), Patch-Editor + Presets, Piano Roll, LoopCutter | `Tools/PolySynthVoice`, `Studio/PatchEditorView`, `Studio/PianoRollView` |
| ✅ | Sampler-ENGINE pro Pad: Start/End-Trim, Reverse, Pitch — lock-free | `Sequencer/SamplerVoice` (UI-Exposure = 🗺) |
| ✅ | EchoelFX-Kette inkl. Bio-Modulation (~30 Hz Körper→FX), Bitcrush, Widener | `Core/FXModulation`, `FXBioModulator` |
| ✅ | Export: WAV mit LUFS-Master (−1 dBFS True-Peak), MIDI-Export, Visual-MP4 | `SingleExport`, `exportMIDI()`, `VisualRecorder` |
| ✅ | Wetter färbt die Struktur (opt-in, 1 Fetch/Session, Attribution) · Ort im Session-Namen (opt-in, transient) | `Core/WeatherMood/-Provider`, `Core/LocationNamer` |
| ✅ | Keine Töne außer der Musik (Launch garantiert stumm; Push seit v144 stumm) | `AnnouncementCenter.swift` |
| 🔧 | **Audiovisual-Vocoder** (Flaggschiff: Stimme+Körper→Klang+Bild+Licht) — purer Kern getestet | `Studio/VocoderCore.swift` |
| 🔧 | BioModulation-Spine (`BoundParameter`), ResonanceFinder, CloudSync-Phase-0 | je eigene Dateien, 0 Konsumenten |
| 🗺 | Sampler-UI + Ordner/Waveform-Browser, EchoelBreak (Slicer/Jungle), One-Shot-Player, Instrument-Selector | `PLAN_ARRANGEMENT_VIDEO_ONE_VIEW.md` |
| 🗺 | Transient/Sustain-Split-FX (vDSP; bio-moduliert = Alleinstellung) — heute geparkt | inspiration.csv 2026-07-10 |
| 🗺 | **Stems auf einzelne USB-Kanäle** (BiG SiX/Xone:96 als Summing/Insert) | inspiration.csv 2026-07-10 |

## 3 · Die EINE Hauptansicht (seit heute, v144)

| Stufe | Fähigkeit | Beleg |
|---|---|---|
| ✅ | **K1: EIN Bildschirm** — Arrangement-Timeline ÜBER dem Instrument (Ableton-Prinzip), quer + hochkant; keine Umschalt-Chips mehr | `SurfaceSwitcher.swift` (SurfaceHost), `WorkspaceView` |
| ✅ | Spur-Köpfe = Türen: MIDI→Piano Roll, Audio→Audio-Editor, Umbenennen, Löschen, „+" Spur | `ArrangeTimelineView.swift` |
| ✅ | Timeline-Fundament: 480-PPQ-Modell, Store + verlustfreie Migration, Beat-Grid, Pinch-Zoom, Playhead, Snap/magnetisch, Waveform-Kette | `Sequencer/Timeline.swift`, `Core/TimelineStore`, `WaveformView` |
| 🗺 | K2: Spur↔Engine-Bindung (Mute/Solo/Level in Spur-Köpfe — Mix löst sich auf) | `PLAN_ONE_VIEW_CONVERGENCE_2026-07-10.md` |
| 🗺 | K3: Regionen anfassen (verschieben/ziehen/erzeugen) + **Timeline treibt das Playback** | ebd. |
| 🗺 | K4: Compose-Bereich als Drawer der Timeline · K5: Video-/Bio-/MPE-Lanes | ebd. |
| — | **Ehrlich:** Die Timeline ZEIGT heute an; Abspielen läuft noch über den bar-genauen Legacy-Player. Audio-Waveforms erscheinen erst, wenn Aufnahme/Import eine Datei referenziert (kommt mit K3/Stage A). | Audit 2026-07-10 |

## 4 · Space · Licht · Vibration

| Stufe | Fähigkeit | Beleg |
|---|---|---|
| ✅ | ADM-OSC-Objekt-Out an jeden Renderer (L-ISA, d&b, …) + OSC-Bio-Adressen | `Sync/ADMOSCSender`, `Sync/OSCSender` |
| ✅ | Licht: Art-Net + sACN (unicast), Flash-Safety ≤3 Hz by construction | `Sync/EchoelLux` |
| ✅ | Sub-Bass-Voice (LFE/Körper) + Haptik-Infrastruktur | `Tools/SubBassVoice` |
| 🗺 | sACN-Multicast (Entitlement), Fixture-Library/Cues, Atmos/Spatial-Authoring, EchoelStage (Projektion/NDI) | FEATURE_MATRIX #9/#10 |

## 5 · Visual

| Stufe | Fähigkeit | Beleg |
|---|---|---|
| ✅ | Metal-GPU-Bio-Visual (Puls≤WCAG, Kohärenz→Farbton, Atem→Ausbreitung), Floating + Vollbild + VJ-Overlay, Adaptive Quality (Thermik/Akku/FPS) | `Views/MetalBioView`, `AdaptiveQuality` |
| 🗺 | E3c Wetter→Visual-Palette („Use weather palette") · Video-FX-Katalog | Plan E3c |

## 6 · Data / Interop / Apple-Ökosystem

| Stufe | Fähigkeit | Beleg |
|---|---|---|
| ✅ | MIDI/MPE **IN** (1.0/2.0/MPE + RTP-Netzwerk) · MIDI-**OUT** als virtuelle Quelle in jede DAW | `Audio/MIDIInput`, `Audio/MIDIOutput` |
| ✅ | Widgets (Live-Bio-Glance) — shipped. **Das AUv3-Plugin war geshippt und wurde am 2026-07-24 bewusst ENTFERNT** (Rein-Instrument-Epic #121 Slice 1 = Target, Slice 2 = Hosting). Kein Plugin, kein Host, nicht auf der Roadmap. | FEATURE_MATRIX Ecosystem |
| ✅ | Nearby-Colabo: Session teilen + **Puls nebeneinander** (jeder die eigene Zahl — nie ein Gruppen-Score) | `Sync/MultipeerSession`, `LiveColaboView` |
| ✅ | Push ohne Konto (CloudKit-Announcements, stumm) — **dein Dashboard-Setup + E2E-Test stehen aus** | `Sync/AnnouncementCenter`, `docs/dev/CLOUDKIT_ANNOUNCEMENTS.md` |
| ✅ | Kein Konto, keine Datensammlung („Data Not Collected"), Sign-in-with-Apple bewusst ungenutzt | Beschluss 2026-07-10 |
| 🗺 | Ableton Link (LinkKit freigegeben, Founder-Ok für Dep nötig) · Watch-Embed (braucht lokales Xcode) | inspiration.csv, FEATURE_MATRIX |
| 🗺 | Mac (Catalyst) · visionOS/tvOS · App Clip | FEATURE_MATRIX Ecosystem — nur Pfad-Entscheid |
| 🗺/⭐ | **Mehrere Interfaces parallel:** iPhone = OS-Grenze (kein Weg, belegt); „virtuelle Soundkarte umgeht die Clock-Latenz" = **widerlegt** (verschiebt nur das Resampling); Mac-Version kann das Aggregat **automatisch in-app** bauen (`AudioHardwareCreateAggregateDevice`) → Roadmap am Mac-Entscheid | `scratchpads/RESEARCH_MULTI_INTERFACE_2026-07-10.md` (25 verifizierte Claims, 20 Quellen) |

## 7 · Video & Broadcast

| Stufe | Fähigkeit | Beleg |
|---|---|---|
| ✅ | Kamera als BIO-Sensor (rPPG) — die einzige Video-Realität heute | `Video/CameraCapture` |
| 🔧 | ChromaKey-Shader existiert, nichts nutzt ihn | `Video/Shaders/ChromaKey.metal` |
| 🗺 | Video-AUFNAHME gegen die Transport-Uhr → Schnitt-Lane in der Timeline → MP4-A/V-Export | Plan Stage V/3–5 |
| 🗺 | RTMP-Broadcast (HaishinKit = die eine erlaubte Dependency; Scaffold kompiliert) | `Stream/BroadcastPublisher`, v1.2 |

## 8 · Gemeinsam & Einkommen

| Stufe | Fähigkeit | Beleg |
|---|---|---|
| ✅ | **v1.0 = das freie Instrument** — keine Kauf-UI, Launch-Kandidat liegt auf TestFlight | Beschluss 2026-07-10B |
| 🔧 | StoreKit-Gerüst (EchoelStore/ProGate/ProUnlockView) kompiliert unpräsentiert — wird v1.1 zum Jahresabo „Echoel Live" umgewidmet | `Core/EchoelStore.swift` u. a. |
| 🗺 | v1.1 „Echoel Live": SharePlay-Sessions weltweit — **wir syncen Puls + Partitur, nie Audio** (taktquantisiert; physik-ehrlich) · ~29,99 €/Jahr | STRATEGY_GLOBAL_LIVE |
| 🗺 | v1.2: Broadcast + Host-Fee (~9,99 €/Event) + Cause-Events (Partner-Modell, kein eigener Server) | ebd. |
| ⭐ | Weltweites Realtime-Jammen als AUDIO · Avatare/Marktplatz/Experten-Vermittlung (erst mit Community-Masse) | North Star — nie versprechen |

## 9 · Launch-Reststrecke (alles Schritte bei DIR — kein Code offen)

1. **v10.79.144 am Gerät testen** — eine Hauptansicht (quer/hochkant), Spur-Türen, Push stumm nach Toggle-Reset (aus→an), Crash weg?
2. **CloudKit-Dashboard**: `Announcement`-Schema anlegen + in **Production** deployen, Push-E2E-Test (`docs/dev/CLOUDKIT_ANNOUNCEMENTS.md`)
3. **Screenshots** (8-Motive-Drehbuch in `docs/dev/APP_STORE_LISTING_v1.md`)
4. **ASC-Listing** Copy-Paste + **Submit** — erst nach deinem Gerätetest

---

### Korrigierte Alt-Aussagen (damit keine Session sie wieder als wahr behandelt)

- FEATURE_MATRIX #4 „Session clips + Arrangement NOT built" ist **überholt**:
  `Sequencer/Clip.swift`, `ClipStore`, `ClipView`, der komplette Timeline-Stack und
  seit v144 die EINE Hauptansicht existieren (Audit + K1, 2026-07-10).
- „Der Plan war Studio-Home bis K3/K4" — **founder-überstimmt** am 2026-07-10:
  die Timeline IST die Hauptansicht, Konvergenz läuft in ihr weiter.
