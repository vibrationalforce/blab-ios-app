# COLLAB_SYNC_TRIAGE.md — Triage: "Online-Kollaboration und Synchronisation System" (Braindump Feb 2025)

> **Für Claude Code.** Quelle: 193-seitiger Apple-Notes-Export aus der BLAB/SyngDAW-Ära (Feb 2025), Pseudocode in C++/JS/React. Dieses Dokument extrahiert, was für Echoelmusic relevant ist, und markiert explizit, was NICHT übernommen werden darf. Gilt zusammen mit `CLAUDE.md` und den dev-Notes. Bei Konflikt gewinnt `CLAUDE.md`.
>
> Founder-kuratiert (2026-07-02). In den Ledger/Repo aufgenommen als verbindliche Roadmap-Extraktion aus dem Legacy-Archiv.

---

## 0. Kontext & Grundregeln

- Der Braindump stammt aus einer Zeit vor der Swift-6/SwiftUI-Architektur. Fast alles ist konzeptioneller Pseudocode, kein lauffähiger Code. **Nichts 1:1 portieren — nur Konzepte übernehmen.**
- Harte Constraints aus CLAUDE.md bleiben unverändert gültig:
  - Swift 6, SwiftUI, AVAudioEngine, CoreMIDI (MIDI 2.0/MPE), Metal, OSC-Output (EchoelSync), **Zero JUCE**.
  - Audio-Thread-Regeln: keine Allocations, keine Locks, kein ObjC/Swift-Runtime-Dispatch im Render-Callback.
  - Protected DSP (read-only): `BioEventGraph`, `HilbertSensorMapper`, `BioSignalDeconvolver`. Mapping-Ideen aus dem Braindump sind **Inspiration für neue Module**, niemals Änderungen an den geschützten Komponenten.
  - **Science-only-Positionierung**: keine esoterischen Frequenz-/Farbheilungs-Claims, keine Therapie-Sprache, keine Gesundheitsversprechen (auch App-Store-relevant).

---

## 1. ÜBERNEHMEN (hohe Relevanz für Echoelmusic / EchoelSync)

### 1.1 Session-Synchronisation → EchoelSync-Roadmap
Der Kern des Dokuments: Multi-User-Sessions mit gemeinsamem Tempo/Key/Beat-Grid und Latenzkompensation.

- **Ableton Link** als Tempo-Sync: Es gibt offizielles **LinkKit für iOS** — passt perfekt zu EchoelSync und ist Industrie-Standard für Jam-Sessions. Konkrete Aufgabe: LinkKit-Integration als optionales Sync-Backend neben MIDI Clock und OSC evaluieren (Lizenz: kostenlos, Ableton Link SDK Agreement).
- **SyncState-Modell** (tempo, key, beatGrid, activeUsers, latencies): als Swift-`struct` für den EchoelSync-Sessionzustand adaptieren; Transport über OSC-Bundles mit Timetags.
- **Latenzkompensation pro Peer** (measure → offset → compensate): Konzept übernehmen. Für lokale Netze reicht NTP-artiges Ping/Offset über OSC; für Fernkollaboration realistisch bleiben (siehe Abschnitt 3).
- **Lokale Kollaboration zuerst**: `MultipeerConnectivity` / Network.framework (Bonjour) statt WebRTC-Server-Infrastruktur. Das ist Apple-nativ, offline-fähig und passt zur Installations-/Performance-Praxis (mehrere iPhones/Watches in einem Raum speisen eine Session).

### 1.2 Biofeedback→Harmonik-Mapping (als Inspiration, neues Modul)
Die Mapping-Ideen sind musikalisch brauchbar, wenn man sie von den Esoterik-Claims trennt:

- Herzfrequenz → Grundton/Fundamental (HR/60 als LFO- oder Pitch-Referenz).
- HRV → Spreizung/Detuning der Obertonreihe (`f·n·(1 + hrv/1000)`), d. h. HRV moduliert harmonische Dichte/Reinheit.
- Atemfrequenz → Amplituden-/Filtermodulation (langsamer Sinus-LFO, atemsynchron).
- Bewegung/ACC → Trigger-/Intensitätsebene.

**Umsetzung:** als neues Mapping-Preset-Set oberhalb der Protected-DSP-Schicht (Konsument der `BioEventGraph`-Events, kein Eingriff). Sprache im UI/Marketing: "harmonic mapping of physiological rhythms" — messbar, ohne Wirkversprechen.

### 1.3 Oktavanaloge Noten→Farb-Tabelle
Die `NOTE_COLOR_MAP` (F#=rot … F=rotviolett) taucht im Dokument mehrfach konsistent auf und ist offenbar Michaels etablierte künstlerische Farbsprache seit den Installationen.

- Übernehmen als **künstlerische Design-Konstante** (`NoteColorPalette` in Swift, hex-basiert) für Metal-Visuals und Light-Output.
- **Nicht** als "Lichtwellenlänge entspricht Ton" verkaufen — die Wellenlängen-Spalte im Braindump ist physikalisch nicht haltbar (Oktavierung von Schall zu Licht ist eine Analogie, keine Physik). Framing: "octave-analogy color mapping (artistic convention)".

### 1.4 Frequenz→Note-Detection
Die JS-Funktion `12·log2(f/440)+49` ist Standard-Pitch-Quantisierung — in Swift trivial, nützlich für Visualizer (Audio-Input → Note → Farbe). Falls noch nicht vorhanden: kleines Utility im Visual-Layer.

### 1.5 Capability-basierte Engine-Initialisierung
`SyngEngine.Capabilities` (GPU? Spatial? maxChannels?) ist ein gutes Muster:

- iOS-Pendant: Geräteklassen-Detection → Metal-Feature-Set, `AVAudioSession`-Kanalzahl, Spatial-Audio-Fähigkeit (AirPods), ProMotion.
- Graceful Degradation: volle Partikel-/Fluid-Visuals auf neueren Chips, reduzierte Shader-Pfade auf älteren Geräten. Das gehört ohnehin zu App-Store-Qualität. (Teilweise vorhanden: `AdaptiveQuality`/`ResourceGovernor`.)

### 1.6 Performance-/Clip-Trigger-Konzept (light)
Der ClipLauncher (Banks, Trigger-Keys, Loops) ist als **Szenen-/Preset-Trigger** für Live-Performances sinnvoll: Bänke von Mapping-Presets + Visual-Szenen, triggerbar per MIDI-Note oder UI. Kein Video-Clip-Launcher bauen (das ist Resolume/VDMX-Territorium), sondern Szenenwechsel für Bio→Sound→Visual-Setups.

---

## 2. ADAPTIEREN / SPÄTER (mittlere Relevanz, Roadmap-Kandidaten)

- **Zusätzliche BLE-Geräte (Muse 2, OpenBCI):** Polar H10 + Apple Watch sind gesetzt. Muse 2 (EEG, BLE) wäre technisch machbar, aber: EEG-Consumer-Daten sind verrauscht, und EEG-Claims sind regulatorisch/kommunikativ heikel. Als "experimental input" auf der Long-List, nicht priorisieren. OpenBCI ist USB/WiFi-Bastlerhardware — für eine Consumer-iOS-App raus.
- **Spatial Audio statt "Dolby Atmos":** Der AtmosRenderer (128 Objects, ADM BWF, DAMF-Export) ist Studio-/Postpro-Welt und für eine iOS-App unrealistisch. Der richtige Apple-Pfad: **PHASE-Framework bzw. AVAudioEnvironmentNode** für objektbasiertes Spatial Rendering + Head-Tracking über AirPods. Als EchoelWorks/Performance-Feature evaluieren; ggf. offene Frage in den dev-Notes ergänzen ("PHASE für biofeedback-gesteuerte Objektpositionierung?"). Hinweis: der **ADM-OSC-Output** (`/adm/obj/{n}/*`) existiert bereits als offener Objekt-Sender in externe Renderer — das ist der on-vision Pfad, nicht der In-App-Atmos-Export.
- **Externe Displays/Projektoren:** Multi-Projektor-Warping/Edge-Blending ist Media-Server-Territorium (nicht nachbauen). Sinnvoller iOS-Scope: sauberer **External-Display-Support** (AirPlay/USB-C-HDMI, eigene `UIScene` für den Visual-Output, UI auf dem Gerät, Visuals auf dem Beamer). Für echtes Mapping: OSC/Syphon-artige Anbindung an Resolume/TouchDesigner via EchoelSync — das deckt den Installations-Use-Case besser ab als eigener Projektor-Code.
- **Audio-Routing/Xone:96:** Der Xone96Handler dokumentiert Michaels reales Setup. Für die App relevant: class-compliant USB-Audio-Interfaces auf iPad unterstützen (Multichannel via `AVAudioSession`), Kanalzuordnung konfigurierbar machen. Keine mixerspezifischen Handler-Klassen bauen; MIDI-Mapping generisch über CoreMIDI lösen.
- **Session-Recording & Review:** Aus dem "TherapySession"-Block ist die neutrale Idee brauchbar: Sessions aufzeichnen (Biosignal-Verlauf + Audio-Bounce + Parametertimeline) und danach als **Session-Review** visualisieren/exportieren. Framing: Performance-/Kreativ-Dokumentation, ggf. EchoelWell-Feature mit rein deskriptiver Auswertung (HRV-Verlauf anzeigen ≠ Gesundheitsclaim). HealthKit-Daten dann nur mit sauberem Consent und Privacy-Manifest.
- **Wasser-/Fluid-Visuals:** Die Canvas-Partikel-/Kaustik-/Interferenz-Ideen (audio-reaktive Wasseroberfläche, Interferenzmuster aus Frequenzbändern) passen perfekt zur Wasser-Licht-Klang-DNA — aber als **Metal-Compute-Shader** neu, nicht als Port des JS-Codes. Gute Kandidaten: GPU-Partikelsystem mit Note→Farbe-Palette (1.3), Kaustik-Layer, atemmodulierte Wellenamplitude.

---

## 3. NICHT ÜBERNEHMEN (Konflikte mit CLAUDE.md / Realität)

| Braindump-Inhalt | Grund für Ablehnung |
|---|---|
| **432 Hz "Harmonie", 528 Hz "DNA-Reparatur", Schumann 7,83 Hz, Chromotherapie-Effekttabellen inkl. erfundener Quellen** ("Journal of Sound Healing", "Frequency Medicine Review") | Verstößt direkt gegen die Science-only-Positionierung. Die zitierten Quellen existieren so nicht. Nichts davon in Code-Kommentare, UI-Texte oder Marketing. Frequenzen dürfen als frei wählbare musikalische Parameter existieren — ohne Wirkungs-Claims. |
| **"TherapySession", TherapyReport, "isTherapist()", therapeutische Empfehlungen** | Therapie-Sprache = Medizinprodukt-Risiko (MDR) + App-Store-Problem + Positionierungsbruch. Im Dokument steht selbst schon: "Aber nicht Therapie nennen." Neutral reframen (siehe 2, Session-Recording). |
| **JUCE-basierte SyngProcessor/VST3/AAX/CMake-Builds, Windows/Linux-Buildskripte** | Zero-JUCE-Regel; Echoelmusic ist iOS-first (Swift 6/AVAudioEngine). Der FFT-Visualizer-Ansatz ist in Accelerate/vDSP längst besser gelöst. |
| **WebRTC-Server-Infrastruktur + Avatar-System (3D-Avatare, Emotion-States aus Biofeedback)** | Massiver Scope-Creep Richtung Social-VR. Emotion-Inferenz aus Biosignalen ("calmness/energy") ist zusätzlich wissenschaftlich wackelig und claim-gefährlich. Falls je Fernkollaboration: erst lokale Sync (1.1) shippen, dann Server-Frage neu bewerten. |
| **Atmos-Master-Export (ADM BWF/DAMF/Pro-Tools-Session)** | Postpro-Toolchain, lizenz- und komplexitätsseitig weit außerhalb des App-Scopes. Spatial-Bedarf über PHASE (siehe 2). |
| **Web-Audio-Worklet/React-Visualizer-Code** | Falscher Stack. Konzepte (Frequenz→Note→Farbe) sind in Abschnitt 1 bereits nativ eingeplant. |
| **Eigenes Projektor-Warping/Edge-Blending/Keystone** | Media-Server-Funktionalität; über OSC-Integration mit bestehenden Tools lösen. |

---

## 4. Konkrete nächste Schritte (Vorschlag für Issues)

1. **EchoelSync:** Spike — Ableton LinkKit auf iOS neben bestehendem OSC-Clock evaluieren (Tempo-Sync mit Ableton Live/anderen Apps im LAN).
2. **EchoelSync:** `SessionState`-Struct (tempo, key, beatGrid, peers, latency) + MultipeerConnectivity-Discovery als lokaler Kollaborationsmodus (2+ Geräte, eine Session). *(Teilbasis vorhanden: `MultipeerSession`.)*
3. **Mapping-Layer:** Preset "Harmonic Series" — HR→Fundamental, HRV→Obertonspreizung, Atem→Amplitudenmodulation, als Konsument der BioEventGraph-Events (Protected DSP unangetastet).
4. **Visual-Layer:** `NoteColorPalette` (Oktavanalogie-Hexwerte) als zentrale Konstante + Frequenz→Note-Utility; Kennzeichnung "artistic convention" im Doc-Kommentar. *(Prüfen ggü. bestehendem Cousto-Ton→Farb-Mapping — evtl. schon abgedeckt.)*
5. **Visual-Layer:** Metal-Spike audio-/bioreaktive Wasseroberfläche (Partikel + Interferenz), Capability-basierte Qualitätsstufen (1.5).
6. **Doku:** Offene Frage ergänzen: PHASE/AVAudioEnvironmentNode für biofeedback-gesteuerte Spatial-Objekte; External-Display-Scene für Performances.
7. **Hygiene:** Sicherstellen, dass keine 432/528-Hz- oder Therapie-Formulierungen aus alten Notizen in Repo, Kommentare oder App-Store-Texte wandern (grep über Codebase: `432`, `528`, `Schumann`, `Therap`, `Heilung`, `healing`).

---

*Erstellt: 2026-07-02 · Quelle: `__Online-Kollaboration_und_Synchronisation_System.pdf` (193 S., Apple Notes, Feb 2025) · Founder-kuratiert, ins Repo übernommen.*
