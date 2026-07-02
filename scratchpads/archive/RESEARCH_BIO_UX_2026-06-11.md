# Deep Research + Echoel-Umbauplan — Bio · UX · Architektur · Accessibility

**Datum:** 2026-06-11 · **Methode:** 5 parallele Deep-Research-Agenten (HRV-Physiologie · Sonification-Mapping · Unified-Architektur · Touch-Editing · Accessibility/Future-Apple) + 1 Codebase-Map-Agent. Jede Aussage zitiert; Wissenschaft vs. Spekulativ getrennt; Cross-Verifikation am Ende.
**Doktrin-Filter (für jede Empfehlung):** offene Standards, fast keine Dependencies; Audio-Thread = kein malloc/locks/GCD; iPhone-first; Biofeedback ist Kern, aber **keine Health-/Medical-Claims** (nur Selbstbeobachtung); UI minimal (Linear/Raycast), radius ≤16px, kein Glassmorphism auf Content, Flash ≤3 Hz.

---

# TEIL A — CITED RESEARCH REPORT

## A1 · Biofeedback — Bedeutung, Sensor-Reliabilität, Normalisierung

### Was jedes Signal bedeutet (SCIENCE-BASED)
- **HR (bpm):** Ruhe 60–100 (Athleten 37–60); momentane autonome Last; sekundenschnell, träge ggü. HRV. Robustester latenzärmster Roh-Wert → primäre Always-on-Modulationsquelle. Baseline erst nach 1–2 min Ruhe erfassen. (AHA; Mayo)
- **HRV Zeitbereich:** **RMSSD** = vagaler (parasympathischer) Tonus, robusteste Kurzzeit-Metrik, valide ab ~10–60 s (Munoz 2015 empfiehlt konservativ ≥2 min). **SDNN** = Gesamt-Variabilität, stark fensterabhängig (klinisch 5 min/24 h). **pNN50** korreliert mit RMSSD, mathematisch weniger robust. (Task Force ESC/NASPE 1996; Shaffer & Ginsberg, Front. Public Health 2017)
- **HRV Frequenzbereich:** **HF (0.15–0.40 Hz)** = valider vagaler Index. **LF (0.04–0.15 Hz)** = gemischt, NICHT rein sympathisch. Brauchen ~2–5 min sauberer Daten.
- **Coherence (HeartMath):** Ratio = Peak-Power (0.04–0.26 Hz, 0.030-Hz-Fenster) / (Total − Peak); Score 0–16. **Misst de facto Schmalbandigkeit/Sinusförmigkeit des HR-Rhythmus um ~0.1 Hz** = Detektor für langsame, regelmäßige (Resonanz-)Atmung.
- **Atmung:** Ruhe 12–20 bpm; Resonanz 4.5–6.5 bpm. **~0.1 Hz = 6 bpm** = Baroreflex-Resonanz, maximale RSA/HR-Amplitude. Phase & Tiefe sind eigenständige Größen. Resonanzfrequenz ist individuell, nicht zeitstabil.
- **Motion/Accelerometer:** Vector Magnitude √(x²+y²+z²) = rauscharmer Intensitäts-/Aktivitätsindikator; auch als **Confidence-Gate** für HRV (Bewegung korrumpiert PPG).
- **EEG-Bänder** (Echoel: deprecated): Delta 0.5–4 / Theta 4–8 / Alpha 8–13 / Beta 13–30 / Gamma 30–100+. Bandgrenzen quellenabhängig → konfigurierbar halten.

### Sensor-Reliabilität (KRITISCH: HR leicht, RR/HRV hart)
| Sensor | HR | HRV/RR | Verdikt |
|---|---|---|---|
| Chest-Strap ECG (Polar H10) | exzellent | Goldstandard-nah | **Einziger voll HRV-vertrauenswürdige Consumer-Sensor** |
| PPG-Wrist (Apple Watch) | gut (Ruhe) | unterschätzt ~8 ms, MAPE ~29%, Lücken | nur Trend-HR; ~4–5 s Latenz → **kein Beat-Sync** |
| Kamera-rPPG (Gesicht) | gut (HR r≈0.997) | nur ≥30 fps & >500 lux & still | HR ja, HRV mit Vorsicht |
| Finger-PPG (Kamera+Torch) | sehr gut | brauchbar bei ruhigem Finger | besser als Gesicht (höheres SNR) |

### Normalisierung für Echtzeit-Musik-Mapping (synthetisiert)
**Stack:** (1) **Rolling Z-Score**, Fenster 30–120 s, σ-Floor gegen Division-by-near-zero → relative Erregung; (2) **tanh/Percentile-Squash** auf [0,1], ausreißer-robust; (3) **One-Euro/EMA-Glättung** nach Normalisierung gegen Jitter; (4) **Motion-Confidence-Gate** vor jeder HRV-Nutzung; (5) **feste Min-Max** nur wo absolute Bedeutung zählt (HR 40–200 → Vibrato; vgl. OSC-Ranges).

### Science vs. Spekulativ — Bio
- **SCIENCE-BASED:** HR (alle Sensoren); RMSSD nur H10/ECG, 30–60 s; HF=vagal; Resonanzatmung 0.1 Hz erhöht HRV; Accelerometer-VM als Intensität.
- **MIT VORSICHT/„geschätzt":** HRV von Watch/rPPG; SDNN/Frequenz <2–5 min; Coherence als 0.1-Hz-Peak-Feature.
- **NICHT als Wissenschaft framen:** LF/HF = „sympathovagale Balance"; HeartMath „heart intelligence"/globale/energetische Kohärenz.

## A2 · Sonification — Mapping-Design, Kurven, Smoothing

### Grundlagen (ESTABLISHED)
- **Direct vs. metaphoric mapping** (Indexikalität); PMSon (Grond & Berger, Sonification Handbook Kap. 15) ideal für multivariate Daten.
- **Polarität ist datenabhängig, nicht universell** (Walker 2002: Pitch↑ für Temp↑, aber Pitch↓ für Size↑). Polarität existiert nur bei monotonem Mapping; Polaritäts-Konsens prognostiziert Wirksamkeit.
- **Perzeptuelle Skalen → nicht-linear mappen:** Pitch ≈ logarithmisch (Mel); Loudness = Stevens Power Law Exponent ≈0.3 (10 dB ≈ Verdopplung der Lautheit). **Linear-auf-Hz oder linear-auf-Amplitude ist perzeptuell falsch.** [Exponent 0.3 / Walker-Slope +1.4 = primär-quelle gegenprüfen]
- **Wahrnehmungslimit: ~3 simultane auditive Streams.** Darüber via Spatialization + Timbre separieren. Pitch & Loudness nicht orthogonal → für unabhängige Datenachsen perzeptuell getrennte Dimensionen (Pitch / Position / Dichte / Timbre).

### Smoothing/Dynamik (ESTABLISHED Engineering)
- **Slew-Rate-Limiter** begrenzt Änderungsrate; **Low-Pass** glättet, kostet aber Detail + Phasen-Lag (Kern-Trade-off); **Deadband** = Inaktionszone gegen Chattering; **Hysterese** = getrennte On/Off-Schwellen gegen Flattern.
- **Richtwerte (Bio-Zeitskala, als Startwerte tunen):** Brightness/Filter τ≈100–300 ms; Coherence/HRV τ≈0.5–2 s; Tempo via Slew-Limiter wenige BPM/s; Deadband+Hysterese an allen Schwellen-Events.

### Evaluierte Biofeedback-Mappings (ESTABLISHED)
- HR → Tempo/Puls/Notendauer/Timbre-Skalierung; multidimensionales/vokales Mapping einprägsamer als simples Frequenz-Mapping.
- Atmung → Amplitude/Hüllkurve (Ein=öffnen) + Phase→Spatial-Expansion (Ambisonics); Naturklang-Stimulus senkt Atemfrequenz am stärksten.
- Kohärenz/Personalisierung auf physiolog. Oszillationen erhöht Entspannung (Unwind, BIT 2018).
- Konsonanz-Modell (Plomp-Levelt Roughness max ~25% Critical-Band [gegenprüfen] + Harmonicity) → „geordnetes" Bio-Signal → konsonanter Klang (metaphorisch kongruent).
- Breath-Pacer auf **0.1 Hz/6 bpm** kalibrieren = wissenschaftlich fundiert.

### Visual/Light-Mapping (ESTABLISHED Affective Computing)
- **Arousal → Saturation + Brightness**; **Valenz → Hue** (Vorsicht: Rot=höchstes Arousal, nicht zwingend positiv). Etabliert: Valenz→Hue, Arousal→Saturation, Dominanz→Brightness.
- HR → visuelle Pulsrate/Partikeldichte (high-directness). **Flash hart ≤3 Hz** (WCAG).

## A3 · Kohärente UI-Architektur & IA

- **Das „ein-Werkzeug"-Gefühl kommt aus geteiltem Transport + geteilter Selektion — NICHT aus dem Navigations-Container.** Ableton: Session-Grid + Arrangement-Timeline fühlen sich als ein Tool an, weil sie dieselben Tracks/Devices/Transport teilen (Regel: „Session takes precedence").
- **Typisierter Scene-Graph** (Bitwig DAWproject als Referenz-Schema): `Project → Transport (eine Zeit-Autorität) → Structure (Tracks, contentType: audio|notes|video|light) → Arrangement (Lanes→Clips+Automation) → Scenes (Clip-Launcher)`. **Duale Zeitbasis** (beats für Audio/Bio, seconds/timecode für Video/Light).
- **Canvas + selektionsgetriebener Inspector** (Figma-Modell) hält N Editoren mit 1 Panel kohärent statt N Screens.
- **IA-Optionen:** Tabs = disjunkt (aktuell Echoel); NavigationSplitView = iPad-stark, iPhone-schwach, **nicht in TabView verschachteln** (State-Konflikte); ZUI/Semantic-Zoom = max. Kohäsion, aber Orientierungsverlust → mehrere diskrete Ebenen. **Apple-Hybrid: `TabView(.sidebarAdaptable)`.**
- **Show-Control für Light/Video:** QLab-Modell = mehrere unabhängige, OSC/Timecode-synchronisierbare Timelines/Cues statt starrer Single-Timeline — kompatibel mit Echoels OSC/ADM/Art-Net-Out.
- **Apple-Datenmodell:** zwei globale `@Observable`-Quellen — `transport` + `selection` — via `.environment()`; Dokument = `@Model` Scene-Graph; `@Query`-Views; unidirektionaler Fluss. Passt exakt zu Echoels `EngineBus`.
- **Gesten-Grammatik:** wiederverwendbare Verben (select/move/resize/zoom/scrub) als geteilte SwiftUI-Modifier in jedem Editor.

## A4 · Pro-Editing auf kleinem adaptivem Touchscreen

- **Zwei wirksamste Fat-Finger-Mitigations:** Auto-Zoom-on-hold (GarageBand-Loupe) + Snap/Quantize default-on — wichtiger als große Buttons.
- **Universelle Touch-Grammatik:** independent H/V-Pinch (H=Zeit, V=Pitch/Höhe); One-Finger-Edit / Two-Finger-Scroll-Trennung; Edge-Handles (links/mitte/rechts der Note = eindeutige Drag-Achse); Tool-Modi (Move X/Y/Length/Velocity, Cubasis).
- **Live-vs-Studio gelöst durch Edit/Perform-Mode-Split (MainStage) + Hardware/OSC-Offload** — MPE/CoreMIDI = Feineingabe (performer priority), Touch = Visualisierung, OSC = Macro-Surface. **Echoel ist dafür bereits gebaut.**
- **44 pt Hit-Area** via `.contentShape` (größer als visuell) + 8 pt Spacing.
- **SwiftUI-Stack:** `Canvas` + `TimelineView(.animation(minimumInterval:))` (cappt CPU); `MagnifyGesture`+`DragGesture` simultan (Drag zuerst, Pinch-Anchor-Offset selbst rechnen); `ViewThatFits` + Size-Classes (Portrait: Inspector inline/fullscreen; Landscape compact-height: Inspector seitlich); Transform-State (hZoom/vZoom/scroll) vom Daten-Model entkoppeln.

## A5 · Accessibility + Future-Apple-Design

- **„No-Glassmorphism vs. Liquid Glass" löst sich auf:** Apple mandatiert Glass NUR auf Navigations-/Control-Schicht über dem Content, nie auf Content (Listen, Media, Vollbild). → System-Bars/Buttons Glass lassen (Auto-Accessibility), eigenen Content (Grid/Timeline/Bio-Visual) flach/solide mit Tokens rendern = Apples gewünschtes Muster. HIG mandatiert *Verhalten* (Glass-not-on-content, a11y-Settings, GlassEffectContainer), nicht die Ästhetik. Radius frei (≤16px ok).
- **Custom Canvas/Metal-Views sind VoiceOver-unsichtbar** bis ausgezeichnet: `accessibilityElement(children:.contain)` + traits + value + `accessibilityAdjustableAction`. **Bio-Verläufe via `accessibilityChartDescriptor`/Audio Graph hörbar** (HR/HRV sonifiziert — thematisch ideal).
- **Core Haptics (Echoel: 0 Code) als eyes-free Kanal:** separate `playsHapticsOnly`-Engine (geringere Latenz, entkoppelt vom Render-Pfad → respektiert no-GCD-in-render); **`setAllowHapticsAndSystemSoundsDuringRecording(true)` zwingend** (sonst killt `.playAndRecord` Haptik); AudioSession vor Engine konfigurieren. Transient-Tap Beat-1 (hohe sharpness); continuous intensity = Coherence/Breath.
- **3-Hz-Flash hart in Render-Pipeline** (Luminanz-Delta + Rate clampen; „flash" = ≥10% Luminanz-Delta mit dunklerem Zustand <0.80); unter Reduce Motion ganz aus. Kontrast AA ≥4.5:1, bei Increase Contrast ≥7:1; Bio-Zahlen immer auf solidem Hintergrund.
- **Design-System:** semantische Color/Type/Spacing/Radius-Tokens (Asset-Catalog mit Dark + High-Contrast-Varianten), Dynamic Type via semantische Styles, zentrale a11y-Setting-Helfer für Graceful Degradation, multimodale Redundanz (Zahl + Haptik + Audio-Graph).

---

# TEIL B — ANGEWANDTER ECHOEL-UMBAUPLAN

## B0 · Ist-Zustand (Codebase-Map, file-grounded)
- **Root:** `Studio/StudioRoot.swift` — `BioStripView` (Header) + 5 Tabs: BeatTab(Tools)/ClipView(Clips)/WorksView(Works)/ModulationView(Sync)/WellView(Well).
- **Editoren:** `BeatTab`, `PianoRollView` (+`PianoRollModel`), `ClipView` (+`ClipStore`), `EchoelFXView`, `EchoelMixView`, `ModulationView`, `WellView`, `PatchEditorView`, `SampleBrowserView`, `BioVisualView`.
- **Control-Plane:** `Core/EngineBus.swift` (`@MainActor @Observable`, latestBio/latestControllerEvent/latestBioEvent + SPSCQueue). Transport: `Sequencer/PatternEngine.swift` (steps/accents/tempo/currentStep/isPlaying/swing; onStep+onTick) — drums+melody teilen diese Clock. `Core/ModulationEngine.swift` + `Core/ModulationMatrix.swift` (10 Hz bio-poll, Routes, UserDefaults-Persistenz, OSC-Tap).
- **Bio (PROTECTED, read-only):** `Bio/BioEventGraph.swift`, `Bio/HilbertSensorMapper.swift`, `Bio/BioSignalDeconvolver.swift`. Publishers: HealthKit/PolarH10/CameraRPPG/Oura/BioSimulator + `EchoelBioEngine`, `HRVMetrics`, `MotionActivityProvider`, `BioFeedbackPublisher` (App Group).
- **Sync:** `Sync/OSCSender`, `ADMOSCSender`, `ArtNetSender`, `SACNSender`, `MIDIBusPublisher`.
- **Design:** `Studio/EchoelTheme.swift` (black ground, bio-green accent, radius ≤8–12, size-class `Metrics`). **Keine Haptics-Datei.**
- **KERN-GAP:** **kein gemeinsames Dokument-/Timeline-Modell, keine globale Selektion.** Jeder Editor hält eigenen transienten State; Persistenz clip-scoped JSON. Geteilt: nur `EngineBus`, `PatternEngine` (Transport), `AudioEngine` (Metering). Intentional: Live-Instrument, kein DAW.

## B1 · Ziel-Architektur (IA als Prosa-Diagramm)
Zwei neue globale `@Observable`-Quellen neben `EngineBus`, via `.environment()`:

```
EchoelDocument  (@Observable, @Model-persistiert)   ← SINGLE SOURCE OF TRUTH (Inhalt)
  └ Transport (tempo, playhead-beats, playhead-seconds, isPlaying)   ← EINE Zeit-Autorität
  └ [Track]  (contentType: .audio | .notes | .light | .object)
       └ [Clip/Region]  (timeBase: .beats | .seconds)
            └ [Event] (note | step | cue | automationPoint)
Selection   (@Observable)   ← treibt den kontextuellen Inspector in JEDEM Editor
EngineBus   (bestehend)     ← Echtzeit-Bio/Controller-Plane (unverändert)
```

- **Container:** `TabView(.sidebarAdaptable)`. Tabs = grobe Modi (Compose / Perform / Stream). **Transport + Selection bleiben über Tab-Wechsel erhalten** → Kohäsion.
- **Editoren werden Sichten auf dasselbe Dokument:** PianoRoll = Notes-Track-Detail; BeatTab = Notes/Step-Track; ClipView = Scenes/Session; (neu) Arrangement = lineare Timeline; (neu) Light/Video = Cue-Lanes (QLab-Modell, seconds/timecode).
- **Inspector:** rechts (iPad/Landscape) / Bottom-Sheet (iPhone-Portrait), rein selektionsgetrieben.
- **Dual-View à la Ableton:** Arrangement (linear) + Session/Clip-Grid (Live) über denselben Tracks, „Session takes precedence".
- **Protected Triad bleibt unangetastet** — Dokument-Layer sitzt über der Bio-Plane, nicht darin.

## B2 · Bio→Parameter-Mapping-Matrix (implementierbar)
Pipeline pro Route: `raw → [Confidence-Gate] → Normalisierung → Kurve → Smoothing(τ) → Deadband/Hysterese → Ziel-Range`.
Update-Rate: 10 Hz (Control-Plane, kein Audio-Thread). Max ~3 gleichzeitig hörbare bio-Achsen → Rest via Pan/Timbre/Light separieren.

| Bio-Signal | Norm. | Ziel (Audio) | Kurve | τ / Slew | Deadband | Safe-Range | Status |
|---|---|---|---|---|---|---|---|
| HR (bpm) | fixed 40–200 | Vibrato-Rate; Puls/Tempo-Hint | linear (Rate); log (falls→Pitch) | 100–200 ms | — | Vibrato 0–8 Hz; Tempo Slew ≤4 BPM/s | SCIENCE |
| RMSSD (nur H10!) | rolling-z 60 s→tanh | Brightness / Spectral-Tilt | S-Kurve | 0.5–2 s | klein | gate: nur valid wenn ECG & low-motion | SCIENCE (sonst „geschätzt") |
| Coherence (0.1 Hz) | fixed 0–~6 | Harmonicity / Konsonanz | S-Kurve | 1–2 s | Hysterese an Schwellen | — | Feature OK; Zustand NICHT framen |
| Breath-Phase | 0–1 (Phase) | Amplitude/Envelope öffnen; Spatial-Expansion | sin/linear | 50–150 ms | — | — | SCIENCE |
| Breath-Depth | rolling-z→[0,1] | Noise/Granular-Dichte | linear | 200–400 ms | — | — | ESTABLISHED |
| LF/HF | rolling-z | „spectral tilt" (roh, KEIN Label) | linear | 1–2 s | — | — | roh erlaubt, kein physiolog. Label |
| Motion-Energy | rolling-z→[0,1] | FX-Send / Intensität; + HRV-Gate | linear | 100–300 ms | klein | — | SCIENCE |

| Bio-Signal | Ziel (Visual/Light/Space) | Kurve | Hinweis |
|---|---|---|---|
| Arousal (HR↑/HRV↓) | Saturation + Brightness ↑ | linear | Affective-Computing-belegt |
| Valenz (proxy: Coherence) | Hue (kühl↔warm) | linear | „Rot≠gut" beachten |
| HR | visuelle Pulsrate / Partikeldichte; DMX-Dimmer | linear | **Flash ≤3 Hz clamp** |
| Breath-Phase | ADM azimuth/distance Expansion; DMX-Fade | sin | bestehender ADMOSCSender |
| Coherence | DMX-Dimmer; ruhige kühle Hues | S-Kurve | bestehende EchoelLux-Map |

## B3 · Adaptives Layout (Portrait/Landscape, Size-Classes)
- **Portrait (compact W / regular H):** Editor fullscreen (Note-Modell), Inspector als Bottom-Sheet, Transport im `BioStripView`-Header.
- **Landscape compact H (iPhone):** vertikalen Platz sparen — Inspector seitlich (`ViewThatFits(in:.vertical)`), Track-Höhen reduziert.
- **Regular W (iPad/Max-Landscape):** Sidebar (Track-Liste) + Canvas + Inspector gleichzeitig.
- **Timeline-Render:** `Canvas` + `TimelineView(minimumInterval: 1/60)`; entkoppelte hZoom/vZoom/scroll; `MagnifyGesture.simultaneously(DragGesture)` (Drag zuerst); Snap default-on; Auto-Zoom-on-hold; 44 pt Hit-Zonen via `.contentShape`.

## B4 · Accessibility + Design-System-Spec
- **Tokens** in `EchoelTheme` erweitern: semantic colors (Asset-Catalog Any/Dark/High-Contrast), type-scale (nur semantische Styles), spacing (4/8/12/16/24/32), radius-token (cap 16).
- **Zentrale a11y-Helfer:** liest `accessibilityReduceMotion` / `accessibilityReduceTransparency` / `colorSchemeContrast` / `CHHapticEngine.capabilitiesForHardware().supportsHaptics`; jede Komponente fragt Helfer.
- **Custom-Views auszeichnen:** Pads/Steps/Notes mit Label+Value+Traits+AdjustableAction; Bio-Strip mit `accessibilityChartDescriptor` (Audio Graph).
- **Haptics-Layer (neu):** `HapticEngine` (separate `playsHapticsOnly`); AudioSession-Reihenfolge + `setAllowHapticsAndSystemSoundsDuringRecording(true)`.
- **Flash-Guard (neu/Hardening):** zentraler Clamp in Bio-Visual-Render (Rate ≤3 Hz, Luminanz-Delta-Limit); off bei Reduce Motion.
- **Liquid Glass:** mit Xcode 26 bauen, System-Controls Glass lassen, Content flach.

## B5 · Gestaffelte, atomare Roadmap (Ralph Wiggum Lambda — ein Zyklus/Schritt, ≤3 Files, build-green Gate, protected DSP unangetastet)

**Phase M — Mapping-Wissenschaft (höchster Wert, niedrigstes Risiko, kein UI-Umbau):**
1. `BioNormalizer` (neu, value type): rolling-z + tanh + EMA + σ-Floor + Motion-Gate. Unit-Tests.
2. `ModulationMatrix` erweitern: pro Route Kurve (lin/log/S) + τ + Deadband/Hysterese + Source-Confidence-Flag. RMSSD-Routes nur bei ECG „valid".
3. Mapping-Defaults aus B2 als Presets; Coherence/LF-HF-Labels säubern (kein physiolog. Claim).

**Phase H — Haptics + Accessibility (eyes-free, greenfield):**
4. `HapticEngine` (`playsHapticsOnly`, AudioSession-safe) + Transport/Beat-1-Tap.
5. Bio→Haptik continuous (Coherence/Breath); a11y-Auszeichnung Bio-Strip (Audio Graph).
6. Flash-Guard-Clamp in Bio-Visual; a11y-Setting-Helfer + Token-Härtung in `EchoelTheme`.

**Phase D — Dokument/Kohäsion (das eigentliche „connect the screens"):**
7. `EchoelDocument` + `Transport` + `Selection` als globale `@Observable`, `.environment()`-injiziert; `PatternEngine`-Transport hineinfalten (nicht ersetzen).
8. `StudioRoot` → `TabView(.sidebarAdaptable)`; Transport/Selection tab-persistent.
9. Selektionsgetriebener `InspectorView` (Bottom-Sheet/Side); je Editor Selektion publizieren.
10. Typisierter Scene-Graph (`@Model`), bestehende Clips/Patches/Sessions migrieren.

**Phase T — Adaptive Timeline + Arrangement:**
11. `TimelineCanvas` (Canvas+TimelineView, H/V-Zoom, Gesten, Snap, Loupe, 44pt).
12. Arrangement-View (lineare Timeline über Tracks) neben Session/Clip-Grid (Ableton-Dual).
13. Light/Video als Cue-Lanes (QLab-Modell, seconds/timecode) — füttert bestehende OSC/ADM/Art-Net.

**Phase F — Feature-Tiefe (nach Kohäsion, je Website-Parität):**
14. RTMP (HaishinKit — einzige sanktionierte Dep). 15. Video-Capture/Trim (HEVC). 16. Multitrack-Recorder. 17. Echte Realtime-Collaboration (Ableton Link + bidirektionales OSC; ggf. MultipeerConnectivity) — derzeit größte konzeptionelle Lücke vs. Vision.

## B6 · Offene Fragen (Geräte-Validierung nötig)
- On-Device-Latenz Haptik vs. Audio-Beat (Scheduled-Mode Sync messen).
- rPPG ≥30 fps/Lux-Realität auf Ziel-iPhones (HRV-Gültigkeit).
- CPU-Budget `Canvas`+`TimelineView` bei dichten Patterns (<30%).
- `EchoelDocument`/`@Model`-Migration ohne Bruch bestehender Clips.
- Realtime-Collaboration: Scope (nur Link/OSC vs. echte Multi-User-Session)?

## B7 · Cross-Verifikation & Vertrauen
- **Hoch (≥2 Agenten/Multi-Source):** Resonanz 0.1 Hz/6 bpm; Coherence=0.1-Hz-Feature; RMSSD nur ECG; Transport+Selection=Kohäsionsschlüssel; Glass-nur-auf-Control; 3-Hz-Flash; Auto-Zoom+Snap.
- **Einzel-Agent, Multi-Source:** LF/HF≠Balance (Billman); HeartMath-Kritik; 44pt; `playsHapticsOnly`+AudioSession-Konflikt.
- **GEGENPRÜFEN (WebFetch 403 beim Sonification-Agent):** Stevens-Exponent ≈0.3; Walker-Slope +1.4; Plomp-Levelt 25% Critical-Band. Richtungssicher (Standard-Psychoakustik), Zahlen vor Zitat primärquellen-prüfen.

*Vollständige Quell-URLs in den Agent-Transkripten / `SESSION_LOG.md`.*
