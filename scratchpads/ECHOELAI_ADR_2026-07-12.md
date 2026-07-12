# ADR — EchoelAI: On-Device-SLM als Studio-Manager (Tier-Architektur)

Status: **ACCEPTED** (Founder-Night-Prompt 2026-07-12, verbindlich)
Referenz für alle EchoelAI-Arbeit ab jetzt. Ort: `scratchpads/` (Pipeline-Doku).

## Entscheidung

EchoelAI wird vom Chat-Feature zum autonomen "Studio-Manager", der die App
über eine abfragbare Parameter-Registry bedient. Drei Tiers, hart getrennt:

### Tier 1 (Default): Apple Foundation Models Framework (iOS 26+)
- Systemeigenes ~3B-On-Device-Modell; `Tool`-Protokoll für natives Function
  Calling; `@Generable`/`@Guide` für typsichere strukturierte Ausgaben.
- Kein eigener JSON-Parser, keine Modellgewichte im App-Prozess, offline, privat.
- Verfügbarkeit ausschließlich via `SystemLanguageModel.default.availability`.
- Kapselung: `#if canImport(FoundationModels)` + `#available(iOS 26.0, *)` —
  Deployment-Floor bleibt iOS 18, ALLE Targets (App, AUv3, Linux-CI) bauen weiter.

### Tier 2 (später, optional): MLX Swift + Qwen3-1.7B/4B 4-bit
- Downloadbares Fallback für Geräte ohne Apple Intelligence.
- NICHT in dieser Phase; keine MLX-Dependency wird angefasst (Zero-Deps-Gesetz
  bleibt bis zum expliziten Founder-Go für die Dependency).

### Tier 3 (Echtzeit): KEIN LLM
- Das SLM ist PLANER, nie Modulator. Es konfiguriert Mappings auf der
  Control-Plane; kontinuierliche Biosignal-Modulation läuft deterministisch
  über EngineBus + DSP (Snapshot-Poll + SPSC, wie auditiert).
- Ein Sprachmodell berührt den Audio-Render-Thread niemals — direkt noch
  indirekt (auch nicht über Timer/Task-Fluten; vgl. 10.76.48-Gesetz).

### Tool-Design
- KEINE Parameter-Dumps im System-Prompt (3B-Kontextfenster).
- Wenige generische Tools über eine abfragbare Registry:
  `listParameters`, `searchParameters`, `setParameter`, `applyParameterSet`,
  später `createBioMapping`.
- Parameter-Identität: stabiler `keyPath` (`modul.sektion.parameter`),
  NIE numerische AU-Adressen persistieren.

### AUv3-Hosting externer Plugins (später)
- `parameterTree` per KVO beobachten (Plugins ersetzen den Tree zur Laufzeit).
- `keyPath` statt `address` persistieren.
- Writes nur via `setValue(_:originator:)` von der Control-Plane oder — bei
  laufendem Graph und `flag_CanRamp` — via gecachtem `scheduleParameterBlock`.

### Persona-Doktrin (für spätere Instructions-Strings)
Proaktiver Co-Produzent: knapp, technisch präzise, trockener Humor erlaubt,
niemals geschwätzig, schlägt nächste Schritte vor statt zu fragen. Science-only-
Vokabular (Biosignal, Übertragungskurve, Zeitkonstante, Modulationstiefe).
VERBOTEN überall: Wellness-/Heil-/Therapie-/Frequenzmythologie-/Kinesiologie-
Framing (deckt sich mit dem bestehenden Brand-Gesetz in CLAUDE.md).

### Musikalisches Vokabular
Beschreibende Begriffe → Parameter-Tendenzen ("treibender" → kürzere synced
Delays, schnellere Comp-Release, mehr Transient-Attack, Hi-Hat-Dichte rauf;
"dunkler" → Cutoff runter, Air-Band runter, Reverb-Damping rauf; "breiter" →
Stereo-Spread rauf, kürzere ER, leichtes Detune; "ruhiger" → Modulationstiefe
runter, längere Attacks, Half-Time-Feel). Gepflegt als DATEN-Datei
(`Resources/echoelai-vocabulary.json`), nicht hartkodiert.

## Ground-Truth-Korrekturen zum Night-Briefing (Repo-Realität 2026-07-12)

Das Briefing zitiert einen Mai-Stand; CLAUDE.md ist oberste Instanz. Ehrliche
Abweichungen:

1. **Referenzdokumente:** `scratchpads/PLAN_FOUNDATION_SEQUENCE.md` und
   `scratchpads/DEEP_AUDIT_CONNECTION_MAP_2026-05-22.md` existieren nicht
   (mehr). Aktuelle Ground Truth: `scratchpads/ARCHITECTURE_AUDIT_2026-06-09.md`
   + `scratchpads/DEEP_AUDIT_2026-07-12.md` + `docs/dev/FEATURE_MATRIX.md`.
2. **Cycle N1 ("nichts subscribed auf bioFrames") ist ÜBERHOLT — der Link
   existiert:** `BioReactiveSynthVoice.start(subscribing:)` und
   `PolySynthVoice.start(subscribing:)` pollen `bus.latestBio` mit 10 Hz und
   rufen `applyBioReactive(...)` (BioReactiveSynthVoice.swift:200–212,
   PolySynthVoice.swift:429–460). Der Architektur-Audit 2026-06-09 hat den
   SNAPSHOT-Pfad bewusst zum Bio-Pfad erklärt (langsame Bio-Daten); die
   `bioFrames`-SPSC-Queue bleibt absichtlich undrainiert. Ein neuer
   Queue-Drainer würde die auditierte Architektur verletzen → N1 wird als
   DONE-BY-EXISTING geführt, kein redundanter Adapter gebaut.
3. **Test-Anforderung aus N1 ist erfüllt:** `BioIntegrationTests.swift`
   assertiert Frame→DDSP-Zielparameter über alle Mappings (Kohärenz→
   Harmonicity, HRV→Brightness, HR→Vibrato, Atem→Envelope/Noise, LF/HF→Tilt,
   Trend→Morph, Clamps).

## Was heute im Repo FEHLT (Voraussetzungen für das Zielbild)

- [ ] `FeatureFlags.echoelAI` — Flag existiert noch nicht (FeatureFlags.swift
      trägt bisher nur die 9 Spatial-Flags). → Cycle N2/N3.
- [ ] Eine Parameter-REGISTRY (abfragbar, keyPath-stabil) — es gibt heute
      keine; Parameter leben verteilt in Voices/FX/Patches. → Cycle N2.
- [ ] Ein Brain-Backend-Abstraktionslayer (`BrainBackend`-Protokoll +
      FoundationModels-Kapselung). → Cycle N3.
- [ ] Typisierte Parameter-Änderungs-Nachricht auf dem EngineBus
      (Control-Plane-Write-Pfad für Tools; heute schreiben nur UI/Stores
      direkt in die Voices). → N4/Folge-Zyklus.
- [ ] Vokabular-Datendatei. → N4.
- [ ] Später: KVO-Brücke AUParameterTree→Registry (Design-Kommentar in N2,
      Code erst mit AUv3-Hosting-Zyklus).
- [ ] Gerät mit Apple Intelligence für echte End-to-End-Verifikation
      (Simulator/CI kann nur `unavailable`-Pfade testen).

## Konsequenzen

- Alle EchoelAI-Commits bleiben hinter `FeatureFlags.echoelAI` (Default OFF,
  Release bit-identisch); UI ändert sich um null Pixel bis zum Founder-Go.
- Zero-Deps bleibt intakt (FoundationModels = System-Framework).
- Die Registry wird ZUERST über interne Engine-Parameter real (DDSP/FX),
  damit Tools gegen echte Bestände testbar sind, bevor je ein Modell läuft.
