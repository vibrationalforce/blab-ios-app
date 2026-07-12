# SPATIAL_EXPANSION_AUDIT.md — Phase 0 (2026-07-12, aktualisiert für Prompt v2.0)

Phase-0-Gate des Founder-Prompts "ECHOELMUSIC SPATIAL EXPANSION" —
**v2.0 (CONSOLIDATED) gilt; v1.0 superseded.** §§1–5 unten (v1-Kartierung der
Layer 1–5) bleiben gültig; §6 ergänzt die v2-Neuerungen: Prinzipien P1–P4,
Layer 6 (EchoelRender), Layer 7 (Motion & Show Control), P4-Inventar,
bestätigte Zyklus-Reihenfolge. Kein Code geändert — dieses Dokument IST das Gate.

**Verfassungs-Check:** `CLAUDE.md` gelesen (überstimmt den Prompt bei Konflikt),
`docs/dev/COLLAB_SYNC_TRIAGE.md` gelesen (existiert, founder-kuratiert
2026-07-02), der im Prompt genannte `APPLE_INTEGRATION_NOTES.md` heißt real
`docs/dev/APPLE_INTEGRATION_AUDIT_2026-06-19.md`. CI/TestFlight-Stand: alle
Gates grün bis `b6c5943`; v10.79.175-Deploy in Ausführung — **kein roter Build,
nichts zu fixen, Implementierung darf (phasenweise) starten, sobald v175
bestätigt ist** (Guardrail 1).

---

## 1. Was EXISTIERT schon (Layer-für-Layer-Kartierung)

### Layer 1 — Spatial Core: ~40 % vorhanden

| Prompt-Baustein | Repo-Realität |
|---|---|
| ADM-OSC-Objekt-Out (Renderer B, Dialekt 1) | **LIVE**: `Sync/ADMOSCSender.swift` sendet `/adm/obj/{n}/position/azimuth·elevation·…` (Grad-Konvention wie im Prompt); Bio→Position-Mapping (Atemphase→Azimut, HRV→Elevation) läuft bereits |
| Binaural-Kern (Renderer A, Kopfhörer) | **PURE CORE FERTIG, ungewired**: `DSP/BinauralPanner.swift` — ILD (equal-power) + ITD (Woodworth-Kopfmodell) + Distanz-Gain/Air-Highcut, deterministisch, unit-getestet, dieselbe Azimut/Elevation/Distanz-Konvention wie ADM-OSC. Bewusst NICHT im Render-Pfad (Kommentar im File: Wiring = eigener, audio-thread-reviewter + device-verifizierter Slice) |
| `AVAudioEnvironmentNode` / PHASE | **NICHT im Graph** (nur als Option im BinauralPanner-Kommentar genannt). ADR nötig (siehe §3) |
| Head-Tracking (`CMHeadphoneMotionManager`) | **Fehlt** (kein Treffer im Source) |
| `SpatialScene`/`SpatialObject`/`RoomModel` Wertetypen | **Fehlen** — aber die Konvention (az/el/dist) ist durch ADMOSCSender + BinauralPanner schon festgelegt; das Szenenmodell formalisiert nur, was es gibt |
| Parametrischer FDN-Hall (allokationsfrei) | **Teilbausteine da**: `DSP/EchoelDelayLine.swift` (Allpass-Interpolation, audio-thread-tauglich); ein vollständiges FDN-Netz fehlt. EchoelFX hat Hall-Stufen, aber nicht als parametrisches Raum-Modell |
| OSC-Encoder ohne Fremd-Dependency | **LIVE**: eigener OSC-Encoder (`OSCSender`), Package.swift `dependencies: []` — Prompt-Vorgabe "keine schweren Deps" ist Ist-Zustand |
| IEM-Dialekt-Adapter | **Fehlt** (nur ADM-OSC-Dialekt bisher) |

### Layer 2 — BioSpace: das MUSTER existiert, das Modul nicht

- `FXBioModulator` (~30 Hz, Körper→FX-Parameter-Routing) + `ModulationEngine`
  (bio→tempo, `/echoelmusic/mod/<key>`) + die P5-Wetter-Mixer
  (`WeatherMood.Param` mit per-Parameter-Intensity + `blend()`-Lerp) sind
  GENAU die "data-driven mapping matrix" des Prompts — dreimal bewiesen.
  `BioSpaceMap` = viertes Exemplar desselben Musters, auf Raum-Parameter.
- Bio-Zugriff: **Snapshot-Pfad** (`bus.freshBio()`, 10 Hz Poll) ist der
  auditierte korrekte Weg (CLAUDE.md-Architektur) — Subscribe-only, Protected
  Triad unangetastet. Slew-Limiting-Vorbilder: FXBioModulator glättet bereits.
- Presets des Prompts (Atem→Raumgröße, HRV→Diffusion, HR→Orbit) sind mit dem
  vorhandenen `BioSampleFrame` (bpm/hrv/breathPhase/breathRate/coherence)
  vollständig speisbar. Kein neuer Sensor-Code nötig (Prompt-Vorgabe erfüllt).

### Layer 3 — AVObjects: Ton↔Ort↔Farbe-Einheit ist Kernbestand

- **Render-Stack-Entscheidung ist schon gefallen und ist REPO-GESETZ:**
  genau EIN Metal-View (`MetalBioView`; GPU-Gesetz 2026-06-23: zwei MTKViews →
  schwarzes Immersive). **RealityKit als zweiter Stack ist damit RAUS** — der
  Prompt sieht das selbst vor ("do not introduce a second render stack").
- Ko-Lokation existiert konzeptuell: `SpectralColor.notePosition(forHz:)`
  (Ton→Ort im Feld, founder-abgenommen "Farben erscheinen WO der Ton klingt"),
  `TouchRippleChannel`/`TouchToneChannel` (Berührung = Licht am Klangort),
  physische Ton→Farbe (`SpectralColor`, CIE-Fit, im Shader gespiegelt).
- Fehlt: das gemeinsame `SpatialObject.visual`-Feld + Shader-Konsum der
  SZENEN-Positionen (heute konsumiert der Shader Noten/Bio, keine Szene).
- AirPlay/External-Display: `FloatingVisualWindow` + VisualRecorder existieren;
  ein dedizierter External-Screen-Pfad fehlt (Installations-Slice).

### Layer 4 — StageTracking: 0 % + solide Andockpunkte

- Kein `NearbyInteraction`, kein ARKit im Source. Tier 1 (manuell/MIDI-Fader)
  ist sofort machbar: Performer = ein `SpatialObject`, Position via
  EchoelValueField/MIDI-CC — alles Downstream käme aus Layer 1–3 gratis.
- Vocal-Kette: `MicrophoneManager` + `FeedbackGuard` (Live-Monitoring, WIRED)
  existieren; positionsabhängige FX-Sends fehlen. Latenz-Budget ≤10 ms deckt
  sich mit den bestehenden Performance-Hard-Limits (CLAUDE.md).
- `avaudio-route-resilience`-Skill ist Pflichtlektüre für jeden Slice, der
  Mic + Kamera(rPPG) gleichzeitig anfasst (bekannte 48k/44.1k-Falle).

### Layer 5 — CollabSync: Architektur-These bereits bewiesen

- **"State sync, not audio streaming" ist schon Beschluss UND Code:**
  `Sync/MultipeerSession.swift` + `Sync/ColabPayload.swift` (Codable
  Session-State + BioPeek — synct Puls/Projekt, NIE Audio) + LiveColabo-UI.
  Der Geschäftsmodell-Beschluss 2026-07-10B formuliert es wörtlich: "Wir
  streamen nicht Audio, wir streamen den Puls" (SharePlay-Pfad für v1.1).
- Ableton Link/LinkKit: von COLLAB_SYNC_TRIAGE §1.1 als Evaluations-Auftrag
  markiert, CLAUDE.md erlaubt es explizit als freie, gekapselte Ausnahme.
  Noch nicht integriert.
- CRDT: nicht vorhanden. `SpatialScene` als diff-bares Value-Type (Layer 1)
  ist die Voraussetzung — Ownership-Regel des Prompts (Objekt-Ersteller
  besitzt, Host besitzt Raum) ist mit ColabPayload-Erweiterung abbildbar.
  Globaler Kanal: ADR nötig (CloudKit vs. SharePlay-GroupSession vs. dünner
  Relay). SharePlay hat den strategischen Rückenwind des v1.1-Beschlusses.
- Self-hosted WebRTC bleibt rejected (Triage §3) — Prompt und Repo einig.

### Querschnitt

- **FeatureFlags: existieren NICHT** — neuer kleiner `Core/FeatureFlags.swift`
  (statische UserDefaults-Reader, Release-Default OFF) ist Slice 0 jeder
  Implementierung. Kein Singleton-Konflikt: reine Werte, kein Zustand.
- **EngineBus** ist der auditierte einzige Kopplungspunkt — Prompt-Guardrail 3
  = Ist-Architektur. Neue adressierbare Parameter (`space.room.*`) folgen dem
  `/echoelmusic/mod/<key>`-Muster des ModulationEngine.
- **Audio-Graph heute:** AVAudioEngine-Master-Bus (`AudioEngine`), Voices
  als Source-Nodes (PolySynth/SubBass/BeatPlayer/TouchSynth), AUv3-Host-Kette
  (instrument→fx→master + Master-FX-Slots, `withGraphPaused`-Rewiring),
  Master-Trim −1 dBFS. Ein Spatializer-Node hätte als weiterer Master-Insert
  bzw. Voice-Send anzudocken — die `rewireMasterFX`-Mechanik ist das Vorbild.
- Performance-Budget (+≤15 % CPU flags-on) gegen die bestehenden Hard-Limits
  (CPU <30 %) prüfen: Ziel muss "flags-on ≤ Hard-Limit" heißen, nicht additiv.

---

## 2. Konflikte Prompt ↔ Repo-Verfassung (CLAUDE.md gewinnt)

1. **RealityKit (Layer 3 Option B): ABGELEHNT.** Ein-Metal-View-Gesetz.
   Visual-Konsum der Szene geht in den bestehenden `MetalBioView`-Shader.
2. **Neue Top-Level-Module (`EchoelSpace/` etc.): NICHT als neue Verzeichnisse.**
   CLAUDE.md verbietet neue Top-Level-Dirs ohne Approval. Platzierung:
   pure Kerne → `DSP/` (neben BinauralPanner), Szene/Mapping → `Core/`,
   OSC-Dialekte → `Sync/`, Graph-Nodes → `Audio/`. Modul-Namen bleiben
   als Datei-/Typ-Präfixe (`SpatialScene.swift`, `BioSpaceMap.swift`, …).
3. **"Own FDN, not convolution"**: deckt sich mit Zero-Dependency-Politik —
   kein Konflikt, aber der FDN ist ein echter neuer Audio-Thread-DSP-Block →
   audio-thread-reviewer + tdd-agent Pflicht, Gate vor Wiring.
4. Sonst: Guardrails 2–6 des Prompts sind bereits Repo-Gesetz (wörtlich).

---

## 3. Nötige ADRs (vor Implementierung des jeweiligen Slices)

- **ADR-001 Renderer A:** `AVAudioEnvironmentNode` vs. PHASE vs. eigener
  BinauralPanner-Node. Fakten: Environment-Node ist AVAudioEngine-nativ
  (passt in den bestehenden Graph, mono-Input-Beschränkung pro Quelle),
  PHASE ist ein zweiter Engine-Weltraum (Integrationsrisiko neben dem
  Master-Bus), der eigene Panner ist bereits getestet aber ohne echte HRTF.
  Benchmark auf Minimal-Gerät nötig — DEVICE-GATE (Founder).
- **ADR-002 Global-Transport (Layer 5):** SharePlay-GroupSession (v1.1-
  Beschluss, E2E, 32 Teilnehmer, kostenlos) vs. CloudKit vs. dünner Relay.
  Empfehlungstendenz: SharePlay zuerst (Beschlusslage), CloudKit für
  Persistenz. Audio-Streaming (Jamulus-Stil) = rejected-for-now, Gründe
  aus Triage §3 übernehmen.
- **ADR-003 LinkKit:** freie C++-Ausnahme laut CLAUDE.md, aber erste externe
  Dependency überhaupt → Council + Founder-Gate, eigener Zyklus.

---

## 4. Vorgeschlagene Zyklus-Reihenfolge (Ralph Wiggum: 1 Slice = 1 Zyklus)

Reihenfolge folgt "pure zuerst, Wiring device-gated, Risiko ans Ende":

1. **S0 — FeatureFlags** (`Core/FeatureFlags.swift`, alle OFF, Tests). Trivial, entsperrt alles.
2. **S1 — SpatialScene-Modell** (`Core/SpatialScene.swift`: Object/Room, Sendable, diff-bar, Tests). Pure.
3. **S2 — Szene→OSC-Brücke**: ADMOSCSender generalisieren (Szene speist Objekte statt nur Bio), + IEM-Dialekt-Adapter, Golden-File-Tests. Pure + Netz, kein Audio-Thread.
4. **S3 — BioSpaceMap** (Mapping-Matrix nach FXBioModulator-Muster, 3 Presets, Codable, Slew, Tests mit Bio-Fixtures). Pure.
5. **S4 — FDN-RoomModel-Kern** (DSP, allokationsfrei, Zero-Alloc-Assertion, audio-thread-review). Pure Kern, noch ungewired.
6. **S5 — ADR-001 + Renderer-A-Wiring** hinter Flag (Kopfhörer-Binaural). **DEVICE-GATE.**
7. **S6 — Szene→Shader** (MetalBioView konsumiert SpatialObject-Positionen; AVObjects-Gate). DEVICE-GATE (GPU).
8. **S7 — Performer Tier 1** (manuelles Performer-Objekt + positionsabhängige Vocal-Sends). DEVICE-GATE (Latenz/Feedback).
9. **S8 — Szene-Sync lokal** (ColabPayload + MultipeerSession um Szenen-Diffs erweitern). Zwei-Geräte-GATE.
10. **S9 — ADR-002 + globaler Kanal.** Danach UWB/ARKit-Tiers als eigene Zyklen.

S0–S4 sind ohne Gerät beweisbar (Linux-CI + Xcode-Gate) und brechen nichts —
sie können direkt nach der v175-TestFlight-Bestätigung beginnen. S5–S9 brauchen
Founder-Device-Verifikation pro Gate.

---

## 5. Ehrlichkeits-Notizen

- Nichts aus diesem Plan darf als "shipping" kommuniziert werden, bevor das
  jeweilige Gate device-verifiziert ist (FEATURE_MATRIX-Disziplin).
- Der Prompt-Satz "Biosignale verlassen nie das Gerät (L1–L4)" ist heute
  schon FALSCH-sicher formuliert: ADM-OSC/OSC senden abgeleitete Bio-Werte
  ins lokale Netz, wenn der Nutzer das Ziel konfiguriert — das ist gewollt
  (Rig-Bridge), muss aber in Purpose-Strings/Privacy-Text präzise bleiben:
  "sendet Steuerdaten an VOM NUTZER konfigurierte lokale Geräte".
- Layer-5-Bandbreite: ColabPayload synct heute BioPeek (bpm/hrv/…) zwischen
  Peers — der Prompt verbietet Roh-Biosignale in L5; BioPeek ist abgeleitet
  und bleibt damit konform, im ADR-002 explizit festhalten.

---

## 6. v2.0-ERGÄNZUNG (Prinzipien P1–P4 · Layer 6 · Layer 7 · Zyklus-Bestätigung)

### 6.1 P1 — Capability, not platform: Fundament existiert

`AdaptiveQuality` + `ResourceGovernor` (thermal/battery/measured-FPS → Tier)
sind exakt das geforderte Muster, heute nur fürs Visual. `DeviceCapability`
erweitert es um: Output-Kanalzahl (AVAudioSession `outputNumberOfChannels` /
Core-Audio-Route), Sensor-Verfügbarkeit, Headphone-Motion. Kein Plattform-Gate
im Bestand gefunden, das dem widerspricht (die `#if os()`-Guards sind
Compile-Guards, keine Feature-Gates).

### 6.2 P2 — Session-Rollen: Modell fehlt, Träger existiert

`ColabPayload` (kind/senderName/project/bio) + `MultipeerSession` sind der
Träger; ein Rollen-/Ownership-Modell (`author`/`performer`/`renderer`/
`mixControl`/`observer`, ownerPeer auf Objekten) fehlt und gehört als reines
Value-Type-Modell in den portablen Kern (S1-Nachbar).

### 6.3 P3 — Protocol-first: halbe Miete vorhanden

OSC-Adressraum ist dokumentiert (CLAUDE.md `/echoelmusic/*`; ADM-OSC
`/adm/obj/{n}/*` live). Fehlt: `docs/ECHOEL_SESSION_PROTOCOL.md` (versioniertes
JSON-Schema für Szene/Layout/Session) — wird mit S1 (Szenen-Modell) im selben
Zyklus geboren, nicht nachträglich.

### 6.4 P4 — Portable core: Inventar (heute, gemessen an Imports)

**Bereits P4-konform (Foundation/Observation only):** BinauralPanner,
EchoelDelayLine, SPSCQueue, EngineBus, ModulationEngine, WeatherMood,
AdaptiveQuality, SpectralColor, ColabPayload, SessionNaming, die Protected
Triad (BioEventGraph etc.), BioSampleFrame/MusicalFrame.
**Network zusätzlich (portabel-ok, Linux hat Network nicht → Adapter-Grenze
bei echter Portierung):** OSCSender, ADMOSCSender.
**P4-VERSTOSS (einziger im Kern-Kandidatenkreis):** `Sync/MultipeerSession.swift`
importiert **UIKit** — bei Layer-5-Arbeit hinter ein Transport-Protokoll ziehen
(Inventar-Auftrag erfüllt; kein Fix jetzt).
**Struktur-Realität:** ein einziges SwiftPM-Target, kein Paket-Split. Echte
`EchoelSpace`/`EchoelRenderKit`-Pakete = Restrukturierung (project.yml, CI,
Xcode-Gate). Phase-0-Empfehlung: **Stufe 1 = Verzeichnis-Disziplin + Import-Bann
als CI-Grep** (headless-Job prüft `import UIKit|SwiftUI|AppKit` in den
Kern-Pfaden), **Stufe 2 = echter Paket-Split als eigener, Council-gegateter
Zyklus** — nicht nebenbei.

### 6.5 Layer 6 — EchoelRender: 0 % Code, 2 echte Struktur-Gates

Nichts Vorhandenes rendert Multichannel; `AudioEngine` ist Stereo-Master mit
−1-dBFS-Trim. VBAP/MDAP, Layout-Editor, Kalibrierung, OSC-in-Server: alles neu.
**Gate A (Struktur):** neues macOS-App-Target `EchoelRender` kollidiert mit
CLAUDE.md "keine neuen Targets ohne Approval" und "iPhone-only v10; Mac
v1.1+" — der v2-Prompt IST die Founder-Anweisung, aber die Ausführung braucht
project.yml-/CI-Umbau → eigener Zyklus mit Xcode-Gate, NACH den puren Slices.
**Gate B (Hardware):** 6-Ring/Interface/M-Series-Abnahme ist physisch
(Chris' Rig, FletcherMachine Virtual auf einem Mac) — reine Founder-Gates.
Vorher liefert der portable Kern (VBAP-Mathe, Layout-JSON, FDN) alles
CI-beweisbar: **VBAP-Gain-Vektoren + Layout-Roundtrip + OSC-Fuzzing sind
Linux-testbar, bevor irgendein Mac-Target existiert.**

### 6.6 Layer 7 — Motion & Show Control: Determinismus-Präzedenz existiert

Trajektorien-Engine/Extent-Clouds/Cue-System: nicht vorhanden. ABER die
tragende Anforderung — **deterministisch, seed-basiert, identisch auf jedem
Peer** — ist im Repo bewiesene Praxis: `BioComposer` fährt einen expliziten
Structure/Detail-RNG-Split (seed → identische Struktur), und der
Geschäftsmodell-Beschluss 2026-07-10B basiert auf genau dieser Eigenschaft
("Puls + Partitur syncen, beide Geräte rendern lokal dieselbe Musik").
MotionEngine verallgemeinert das aufs Räumliche: (seed, t) → Position, pure,
100-Hz-Control-Rate. LTC/MTC-Empfang: kein Bestand, Adapter-isoliert planen.
Cue-Snapshots: `MoodPresetStore`/`FXPresetStore`/`ProjectStore` sind die
vorhandenen Snapshot-Muster. Doppler: OFF-by-default bestätigt (Ring-Artefakte).

### 6.7 Zyklus-Reihenfolge v2 (0→1→2→6→7→3→4→5): BESTÄTIGT mit einer Präzisierung

Die pure Vorstufe bleibt wie in §4: **S0 FeatureFlags → S1 SpatialScene(+P2-
Rollen +P3-Protokolldoc) → S2 Dual-Dialekt-OSC (IEM+ADM) → S3 BioSpaceMap →
S4 FDN-Kern** — alles Linux-/CI-beweisbar, flags OFF, TestFlight-neutral.
Dann v2-Reihenfolge: **S5 = Layer-6-Kernmathe (VBAP/Layout-JSON, noch ohne
Target)** → **S6 = EchoelRender-Target (Struktur-Zyklus, Founder-Gate)** →
**S7 = Layer 7 MotionEngine (pure) → Show Control** → Layer 3 → 4 → 5.
Präzisierung gegenüber dem Prompt: die TARGET-Erzeugung (6) wird von der
KERNMATHE (6) getrennt, damit der Markt-Pfad (Rig mit Chris) nicht am
CI-/project.yml-Risiko hängt.

### 6.8 Neue/erweiterte ADRs

- ADR-004 **Cross-Platform-Strategie** (v2 §Roadmap; documentation-only) —
  liegt als `docs/adr/004-cross-platform-strategy.md` bei diesem Gate.
- ADR-005 **Paket-Split** (P4 Stufe 2): wann/wie SwiftPM-Mehrpaket-Struktur.
- ADR-006 **Automerge vs. eigener LWW-CRDT** (Layer 5; Zero-Dep-Politik
  spricht für minimalen eigenen LWW — im ADR entscheiden, nicht implizit).
- ADR-001/002/003 aus §3 unverändert gültig.
