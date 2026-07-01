# Echoel — Produktstruktur (Head of Product · Interface · Architecture)

**Datum:** 2026-07-01 · **Branch:** claude/piano-roll-clip-view-wozlie
**Autor-Rollen:** Head of Product / Interface Design / Architecture (eine Synthese)

> Auslöser: „Ich will ganze Musikprodukte mit Visuals und Video machen — Bass, Leads,
> Drums, Breakbeats, Arrangement/Video-Edit. Ist das realistisch?" → Ja. Dieser Plan
> ordnet das WAS (Product), das WIE-Steuern (Interface) und das WIE-Gebaut (Architecture)
> zu einem sequenzierbaren Weg, an dem, was schon im Repo liegt.

---

## 0. Nordstern (Product)

**Echoel ist EIN Instrument mit drei Output-Säulen — der Körper ist der Controller.**

```
                    ┌──────────── BODY (heart · breath · motion) ────────────┐
                    │                    bio → EngineBus                       │
        ┌───────────┴───────────┬───────────────────────┬────────────────────┴───────┐
        ▼                       ▼                       ▼                              ▼
     SOUND                   VISUAL / LIGHT           VIDEO                        BROADCAST
  (Instrument + DAW)        (generativ, VJ, Art-Net)  (Capture→Edit→Export)       (RTMP/SRT live)
     ~80% da                 live, real                NEU (ein Subsystem)         1 Dependency weg
```

Nicht „ein paar Akkorde" — ein **ganzes Musikprodukt**: Bass, Leads, Drums, Breakbeats,
Arrangement, dazu bio-reaktive Visuals und (Ziel) Video + Live-Stream. Der Differenzierer
bleibt: **Physiologie steuert Klang, Bild, Licht, Stream in Echtzeit** — nicht „noch eine DAW".

**Guardrails (vision-gate, 2026-07-01):** kein TCA, kein externes MusicTheory-Paket,
`one-dependency`-Regel (HaishinKit als einzige externe, hinter `#if canImport`). Bio ist
Kern, nicht Wellness. Keine esoterische Sprache.

---

## 1. Realitäts-Audit (was WIRKLICH liegt — 2026-07-01)

| Baustein | Datei(en) | Status |
|---|---|---|
| **Bass** | `SubBassVoice.swift` | ✅ da |
| **Leads/Akkorde** | `PolySynthVoice.swift` (polyphon) | ✅ da |
| **Drums (Sample+Synth)** | `BeatPlayer` + `DrumSynthVoice` (Modal) | ✅ da |
| **Breakbeats/Slicing** | `LoopCutter` (1–32 Takte) + `SamplerVoice` + `AudioClipRegion` | ✅ Fundament |
| **Arrangement** | `Arrangement`/`ArrangementPlayer`/`ArrangementStore` + `AutomationLane` | ✅ + in `WorkspaceView` verdrahtet |
| **Clips/Session** | `Clip`/`ClipStore`/`ClipView(embedded:)` | ✅ verdrahtet |
| **Musiktheorie** | `MusicalKey`,`MusicStyle`,`MicrotonalTuning`,`GenrePatches`,`MoodPreset`,`BioComposer`,`BioMusicDirector` | ✅ in-house |
| **Export** | `MIDIFileExporter/Importer`, `SingleExport` (Audio-Master) | ✅ da |
| **Bio-Pipeline** | HealthKit + BLE HR + rPPG + `EngineBus` (SPSC + snapshot) | ✅ live |
| **Visuals** | `MetalBioView`, VJ-Overlay, Art-Net/sACN | ✅ live |
| **Patch-Editor** (Sound editierbar machen) | — | ⚠️ Params da, kein Editor/Presets |
| **Video-Edit** | `Video/` = nur rPPG+Shader | ❌ kein Recorder/Trim/Timeline |
| **Broadcast** | `BroadcastPublisher` (Gerüst hinter `#if canImport(HaishinKit)`) | ❌ HaishinKit nicht integriert |
| **Multitrack-Recording** | — | ❌ Roadmap |

**Kernaussage:** Der Sound/DAW-Teil ist zu ~80 % fundiert — die Arbeit ist **Verdrahtung +
Tiefe + UI**, kein Neubau. Video-Edit ist der eine echte Neubau. Broadcast ist eine
Dependency + Capture-Wiring weg.

---

## 2. Architecture (Head of Architecture)

**Beibehalten — bewusst, gegen TCA-Vorschlag:**
- **Control plane:** `@MainActor @Observable` (MVVM), EngineBus-Snapshots (10 Hz Bio),
  lock-freie SPSC-Queue (MIDI/controllerEvents). Kein TCA — der 120-Hz-Bio-Loop und der
  <10 ms Audio-Render-Pfad dürfen nicht durch eine main-thread Reducer-Maschine.
- **Audio-Thread-Regeln:** kein malloc/lock/GCD/ObjC/os_log im Render-Block. N-Voices-Summe
  in EINEM `AVAudioSourceNode` + `tanh` Soft-Limit (SoundscapeEngine-Muster).
- **Protected Rausch-Triade** (`BioSignalDeconvolver`, `BioEventGraph`, `HilbertSensorMapper`)
  — read-only ohne Founder-Freigabe.
- **Persistenz:** neue große Strukturen (Patches, Clips, Arrangements) als Codable-JSON im
  **App-Group-Container** (`group.com.echoelmusic`) — überlebt Relaunch, AUv3-teilbar.
- **Dependency-Disziplin:** HaishinKit einzige externe, hinter `#if canImport`.

**Persistenz-Roadmap-Regel:** ein `AppGroupStore` (Codable JSON) als gemeinsamer Boden für
`PatchStore` + `ClipStore` + `ArrangementStore` (letzterer existiert schon).

---

## 3. Interface Design (Head of Interface) — „complete and easy to understand/control"

**Surface-Modell (ist):** `WorkspaceView` (Shell) hostet Surfaces via Opacity-Layer:
`compose · fx · mix · piano-roll · well · arrange · clips` + `Tools`-Menü.

**Design-Prinzipien (bindend):**
1. **Ein Control app-weit:** `EchoelValueField` für JEDEN numerischen Parameter (kein
   `Slider`/`Stepper`). Ein Keypad (`EchoelNumberPad`), −/+ Vorzeichen. Science-first: Zahl > Knopf.
2. **Uncodixfy-Ästhetik:** Linear/Raycast/Stripe — solide Fills, ≤12 px Radius, 1 px Borders,
   ≤8 px Shadow, keine Glassmorphism/Glow/Scale-Animationen. Bio = große lesbare Zahlen zuerst.
3. **Freeze-Regel (hart erkämpft):** Live-Bio (≈10 Hz: rPPG-Waveform, Playhead, Snapshots)
   NIE im `body` oder in einer vom `body` evaluierten computed var lesen — auch nicht in
   Ancestors (`WorkspaceView`-Header). Immer in ein Leaf-View (`PulseMonitorMiniLive`,
   `BioStripView`) einsperren, sonst reißt jeder Rebuild offene `.menu`-Picker ab.
4. **Presentation-Regel (Black-Screen-Regression):** die `.sheet`/`.fullScreenCover`-Kette
   NICHT weiter wachsen lassen — vor dem nächsten Modal in **eine** `.sheet(item:)`-Enum
   konsolidieren. Nie zwei Modals gleichzeitig true.

**Interaktions-Nordstern (Founder):** „One button, then deep tools." Ein Generate-Flow
(Compose) + Tools-Menü für die Editoren. Jede Surface: sofort verständlich, sofort steuerbar,
kein Placeholder, kein Stub.

**Navigations-Schuld (zu adressieren in P2):** Surfaces (7) + Tools (~7) sind gewachsen. Ein
klares, flaches Modell nötig — nicht noch ein Tab. Kandidat: Surfaces = „Räume" (Make · Arrange
· Perform), Tools = kontextuelle Editoren pro Raum.

---

## 4. Phasen-Roadmap (jede Phase = ein TestFlight-Ship)

### P0 — Stabilität (laufend, Gate für alles) ✅ größtenteils erledigt
Crashfree · kein Menu-Freeze · Pulse lockt bei gutem Kontakt · Audio ohne Aussetzer ·
Visuals konzentrisch. **Regel: keine Feature-Arbeit auf instabilem Boden.**

### P1 — SOUND COMPLETE ✅ BEREITS GEBAUT (Audit 2026-07-01)
Ziel war: aus vorhandenen Voices ein Produkt machen, bei dem der Sound **dir gehört**.
Der Audit zeigt: **schon fertig, verdrahtet und getestet** — der Plan war hier veraltet.
- **A. Patch-Editor + Presets** ✅ `SynthPatch`/`PatchStore`/`AppGroupStore`/`PatchEditorView`
  (aus `EchoelStudioView` erreichbar; Envelope/Tone/Filter/Space/Vibrato/Unison; Favorites/
  Community/Save-as/Delete; Live-Apply; `SynthPatchTests`+`PatchLibraryTests`).
- **B. Breakbeat-Loop-Cut** ✅ `LoopCutter`/`LoopBarLength` im Studio-UI (1–32 Takte).
  *(Rest-Idee, WATCH: echtes Slice/Chop/Reorder eines Samples — über Loop-Länge hinaus.)*
- **C. Arrangement/Clips** ✅ `ClipView`/`ArrangementView` als `WorkspaceView`-Surfaces +
  `ClipStore`/`ArrangementStore`/`AutomationLane`.
- **D. Export** ✅ MIDI-Export (`exportMIDI()` + `ShareSheet`) + Audio-Master (`SingleExport`).
- **Voices:** `PolySynthVoice` (poly) + `SubBassVoice` (bass) + `BeatPlayer`+`DrumSynthVoice` (drums).
- **Konsequenz:** kein Neubau in P1 — Fokus rückt auf P2 (Kohärenz) und P3 (Video).

### P2 — PERFORM (Kohärenz + Visuals als Output-Säule)
- Navigation konsolidieren (Räume-Modell), `.sheet`-Kette in eine Enum.
- VJ-Visuals als first-class Output (Presets, bio-Mapping, Art-Net-Szenen).
- „One button → deep tools"-Flow poliert.

### P3 — VIDEO-SUBSYSTEM (der eine echte Neubau — bewusst schmal)
Scope: **Capture → Trim → bio-reaktives Overlay → Export**. KEIN NLE-Klon.
- `Video/VideoRecorder` (AVAssetWriter H.264+AAC) · `ClipTrimmer` (In/Out) ·
  Overlay = bestehende `MetalBioView`/VJ als Composition-Layer · Export mp4.
- Neues Top-Level erlaubt: `Video/` existiert; nur additive Dateien.

### P4 — BROADCAST (RTMP/SRT live)
- HaishinKit als pinned Dependency integrieren (hinter `#if canImport`).
- Audio/Video-Capture an `BroadcastPublisher` anschließen. YouTube/Twitch/custom.

### Später / WATCH
- Multitrack-Recording (Mic über Beats).
- Deterministic bio-replay für Forschung (der EINE legitime Kern des TCA-Vorschlags — ohne TCA).
- Privacy/DSGVO-Audit (rohe Bio nie geloggt/außer Scope) — vorziehbar, klein, on-brand.

---

## 5. Entscheidungen (für decisions.csv)
- **Kein TCA** — widerspricht Echtzeit-Architektur (120 Hz Bio / <10 ms Audio), große Dependency,
  `@Observable` deckt UI-State einfacher ab.
- **Kein externes MusicTheory-Paket** — Musiktheorie ist in-house vollständig.
- **Sequenz: Sound complete (P1) zuerst** — holt das Meiste aus Vorhandenem, bevor der teure
  Video-Neubau (P3) startet.
- **Video bewusst schmal** — Capture/Trim/Overlay/Export, kein NLE.

---

## 6. Nächster konkreter Schritt
Founder-Freigabe der Sequenz. Default-Empfehlung: **P1-A (Patch-Editor + Presets)** als erster
Zyklus — größter Hebel, reine Verdrahtung/Tiefe auf vorhandenen Params, sofort auf Gerät hörbar.
