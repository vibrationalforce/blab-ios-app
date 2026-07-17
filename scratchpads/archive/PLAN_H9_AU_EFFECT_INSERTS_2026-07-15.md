# PLAN H9 — AU-Effekt-Inserts pro Spur + musicalContext/transportState (2026-07-15)

Fortsetzung der Founder-Mandate "AUv3 von Third Party wie Eventide ermöglichen"
(U-Serie) + Healing Wave 2. Read-only-Audit abgeschlossen (Explore-Agent,
2026-07-15); Council-Verdikt: proceed, zwei Teilzyklen H9a/H9b.

## Audit-Befund (Voice→Master-Graph, Stand v10.79.252)

**Master-Spine:** alles summiert auf `masterMixer` → AutoMixChain →
`mainMixerNode` (outputVolume 0.89 = −1 dBFS Trim) → `outputNode`
(`AudioEngine.setupMasterEngine()` 298–339). Master-FX-Inserts splicen
zwischen mainMixer und output (`rewireMasterFX` 897–917).

**Per-Lane-Node-Grenzen HEUTE:**

| Pfad | Graph | Per-Lane-Grenze? |
|---|---|---|
| H5 AU-Instrument (AUNoteVoice) | AU → **laneMixer** → masterMixer (`attachLaneInstrument` AudioEngine 851–862) | ✅ JA — einzige echte Grenze |
| Audio-Spur (TimelineAudioSink) | AVAudioPlayerNode → masterMixer direkt (Sink 108) | ❌ aber Node ist bereits PER LANE → Grenze einfach einziehbar |
| PolySynth/SubBass/Sampler/DrumSynth (Rack) | sourceNode → masterMixer direkt; **gepoolte Slots**, dynamisch an Lanes gebunden (LaneVoiceRack/BeatPlayer 396–408) | ❌ per-Lane ≠ per-Voice; Re-Bind = Play-Start |
| Globaler AUv3Host | instrument → effectUnits → masterMixer (`connectChainNow` AUv3Host 339–348) | app-global, EIN Kanal — Insert-MECHANIK-Präzedenz |

**EchoelFXChain** = In-Render-DSP pro Voice (kein Graph-Node) — kein
Insert-Präzedenzfall, nicht anfassen.

**Datenmodell FERTIG:** `TimelineLane.effects: [AUPluginRef]` existiert
(Timeline.swift 38, decodeIfPresent 134, synthesized encode),
`TimelineStore.setLaneEffects` existiert (475–487), UI zeigt "FX: …"
(ArrangeTimelineView 617/657/681). **Kein Engine-Konsument** — exakt die
H5-Ausgangslage für `instrument`.

**musicalContextBlock/transportStateBlock: NULL Treffer im Repo.** Gehostete
AUs bekommen heute nur MIDI (`scheduleMIDIEventBlock`). Tempo-Quelle:
`Transport.tempo` (gespeist von PatternEngine, der autoritativen Clock);
Playhead: `TimelineRegionPlayer.currentTick` (480 PPQ absolut).

## Council-Verdikt (2026-07-15)

- Insert-Punkt: **laneMixer-Grenze** (H5-Muster), NICHT Rack-Voice-Rewiring.
  Gepoolte Rack-Slots re-binden bei Play-Start → Graph-Splice dort verletzt
  das Nie-mid-song-Gesetz → Rack-Voice-FX **ehrlich deferred** (Ausweg wäre
  per-Slot-Mixer ab Startup + FX-Wechsel nur zwischen Plays — eigener Zyklus,
  eigenes Council).
- DSP-Auflage: Context-Blocks laufen auf dem RENDER-Thread — lock-/alloc-frei,
  `nonisolated(unsafe)`-Spiegel (didSet-Muster wie SubBassVoice.audioSubGain),
  NIE @MainActor-Reads.

## H9a — Per-Lane-Effekt-Kette (ein Zyklus)

1. `LaneAUInstrumentHost` lernt Effekte: pro laneID zusätzlich
   `effectRefs: [AUPluginRef]` + gehostete `effectUnits: [AVAudioUnit]`.
   Sync-Quelle: `syncAssignments` liest `lane.effects` (persist()-Hook
   triggert bereits). Instanziierung NUR bei Zuweisung/Restore, in
   `withGraphPaused`; Fehler → Kette ohne die kranke Stufe (nie Stille);
   inFlight-Stale-Guard + failed-Parking wie H5.
2. `AudioEngine`: `attachLaneInstrument` erweitern (oder Schwester-API
   `spliceLaneEffects(unit:effects:laneMixer:)`): AU → fx0 → … → fxN →
   laneMixer, `auChainFormat`, alles in withGraphPaused.
3. Audio-Spuren: `TimelineAudioSink` bekommt eigenen laneMixer
   (player → [fx…] → laneMixer → masterMixer) — Grenze beim Attach einziehen,
   FX-Splice bei Assignment (zwischen Plays).
4. Cap beachten (heute 4 Instanzen) — Council-Frage im Bau: gemeinsames Budget
   Instrumente+Effekte oder getrennt (Vorschlag: gemeinsam 8, log-once).
5. UI-Tür: AUv3BrowserView-Effekt-Pfad auf `setLaneEffects` verdrahten
   (Tür existiert teils — prüfen, Slot-Reuse, Sheet-Kette NICHT wachsen).
6. Tests: Splice-Reihenfolge/Format pur wo möglich; Host-Logik via
   vorhandene LaneAUInstrumentHost-Testmuster.

## H9b — musicalContextBlock + transportStateBlock (Folgezyklus)

- Neuer lock-freier Spiegel (z. B. `HostMusicalState`, @unchecked Sendable):
  tempo, isPlaying, beatPosition (aus currentTick/480), sampleTime — Writer:
  Transport/TimelineRegionPlayer auf @MainActor (didSet/Step), Reader: die
  Blocks auf dem Render-Thread (atomare Breiten, keine Locks im Read-Pfad —
  Muster SamplerVoice-Params).
- Blocks setzen auf: globalem AUv3Host-Instrument + dessen effectUnits,
  AUNoteVoice-AUs, H9a-Effekten. Ein Setz-Ort: beim Attach.
- Gewinn: Eventide-Delays/Tempo-synced-LFOs laufen im Song-Tempo — Kern des
  "verhält sich wie professionelle Software"-Mandats.

Reviewer: audio-thread-reviewer (Blocks + Splice) + code-reviewer (Host-Logik).
