# PLAN H5 — AU-Instrument-Routing pro Spur (2026-07-15)

Founder-Mandat (2026-07-15, ultracode): "Zusätzlich auv3 Plugins von third Party
wie Eventide und anderen Herstellern ermöglichen." Audit wf_9c6f33b7 CRITICAL:
`lane.instrument` ist persistierte Intent + UI-Label — KEIN Engine-Code liest es.

## Ist-Zustand (Explore-Map, verifiziert)

- **AU-Hosting REAL, aber global-single:** `Audio/AUv3Host.swift` — Scan
  (AVAudioUnitComponentManager, Retry-Leiter), `load()` → `AVAudioUnit.instantiate`
  → `engine.withGraphPaused { attachAU; connectChainNow }`, MIDI via
  `instrumentUnit.auAudioUnit.scheduleMIDIEventBlock` (:414-421). Gespeist NUR von
  der primären Roll (PianoRollView :554/:586 spiegelt jede Note an `auHost`;
  `replaceBuiltInVoice` ersetzt die interne Voice).
- **Lane-Daten:** `TimelineLane.instrument/effects: AUPluginRef` (Timeline.swift:37),
  gesetzt via ArrangeTimelineView:609 ("Assign '<loaded>' to this track" kopiert
  `auHost.loaded`), Reads heute NUR Display (assignmentSummary :677).
- **Fan-out-Naht:** `NoteVoice`-Protokoll (PianoRollView:18) · LaneVoiceRack
  (capacity 4, PolySynthVoice hart) · slotNoteSink (App:504) · MultiRollFanout
  (slot = Prioritäts-Rang) · slot{Patch,Transpose,Detune,Pan,Gain}Sink am Load.
- **Engine-APIs:** `attachInstrument(_ AVAudioUnit)` (AudioEngine:731,
  pause→attach→connect(masterMixer)→restart) · `withGraphPaused`/`attachAU`/
  `connectAUToMaster` · `auChainFormat`.
- **Tests:** TimelineLaneAUAssignmentTests = nur Datenmodell. AVFoundation-gated
  ⇒ Klang-Verify nur am Gerät.

## Council-Verdikt (proceed)

laneID-keyed AU-Instanzen (Slots sind Rang-instabil zwischen Plays) · Instantiate
NUR bei Assignment / App-Start-Restore / Play-Start (async + Graph-Pause — nie am
Region-Onset mid-song) · Fallback bei jedem Fehler = eingebaute Slot-Voice (nie
Stille) · Primary bleibt vorerst auf dem globalen Host-Pfad (funktioniert heute) ·
eigener Flag `laneAUInstruments` (Muster FeatureFlags.multiRoll), Absent=OFF,
register-default ON erst nach Geräte-Verify.

## Sub-Zyklen

### H5a — Infra (dieser Zyklus)
1. **`Audio/AUNoteVoice.swift` (NEU):** @MainActor final class, conform `NoteVoice`.
   Hält `avUnit: AVAudioUnit` + `laneMixer: AVAudioMixerNode` (AU → laneMixer →
   masterMixer; laneMixer trägt Gain [outputVolume] + Pan [AVAudioMixing]).
   `noteOn(pitch:velocity:)` → 3-Byte via `scheduleMIDIEventBlock`
   (AUEventSampleTimeImmediate; Muster AUv3Host.sendMIDI). `noteOff`, `allNotesOff`
   (CC 123 + aktive-Pitch-Offs wie AUv3Host). `setGain/setPan` control-plane.
   `transposeSemitones` als Property, in noteOn addiert (Detune per MIDI unmöglich —
   EHRLICH dokumentieren, kein Fake).
2. **`Audio/LaneAUInstrumentHost.swift` (NEU):** @MainActor @Observable.
   `voices: [UUID: AUNoteVoice]` (laneID-keyed) + `refs: [UUID: AUPluginRef]`.
   `syncAssignments(lanes:)` — diff: neue Refs async instantiate (Instanz-Cap 4,
   danach ehrlich loggen + skip), entfallene detach+release. Attach via
   `engine.withGraphPaused`-Muster (eigene Methode oder attachInstrument +
   laneMixer). Restore beim App-Start aus dem TimelineStore-Dokument. Fehler ⇒
   voices[laneID] bleibt nil ⇒ Fallback built-in.
3. **Pure Helfer + Tests (Linux-CI-fähig):** `MultiRollFanout.instrument(forSlot:)`
   (liest lane.instrument, Muster patch(forSlot:)) + Tests; MIDI-Byte-Mapping
   (pitch+transpose clamp 0-127, velocity 0-127) als pure Funktion + Tests.

### H5b — Routing (Folge-Zyklus)
- App slotNoteSink: erst `auVoices[laneID(forSlot:)]`, sonst Rack-Voice.
  slotGain/PanSink analog auf AUNoteVoice spiegeln. slotTransposeSink → Property.
- TimelineRegionPlayer: KEINE Änderung nötig (Sinks bleiben slot-basiert; die App
  löst slot→laneID via MultiRollFanout.laneID(forSlot:) mit dem Play-Dokument —
  dafür braucht der Sink Zugriff aufs aktuelle doc: liveDocument existiert schon).
  Alternativ (sauberer): slotInstrumentSink?(slot, laneID) am Load — entscheiden
  beim Bau, Reviewer fragen.
- Assignment-Hook: TimelineStore.setLaneInstrument → host.syncAssignments.
- allNotesOff-Pfade: stop()/handleTransportStopped()/flushPumps → AU-Voices auch.

### H5c — UI-Wahrheit (Folge-Zyklus)
- Lane-Menü zeigt echten Instanz-Zustand (lädt/aktiv/Fehler), nicht nur das Label.
- Geräte-Verify mit echtem Third-Party-AU (Founder), dann Flag register-default ON.

## Risiken / Ehrlichkeit
- CI kann Klang nicht beweisen (AVFoundation-gated) — Reviewer + Geräte-Log sind
  der Beweis. Flag OFF-Default schützt den Bestand bit-identisch.
- Third-Party-AU kann RAM/CPU ziehen: Cap 4 Instanzen, ResourceGovernor später.
- AU-Effekt-Inserts pro Lane + musicalContext/transportState = H9 (Welle 2), NICHT
  hier hineinziehen.
