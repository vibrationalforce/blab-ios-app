# PLAN — Multi-Roll device wiring behind a default-OFF flag (B07/B08/B09/B10)

Keystone: "tracks = instruments" REALLY playing — each MIDI lane its own voice.
Pure foundation COMPLETE + CI-green: LaneVoicePool (slot alloc/reconcile/overflow),
LaneVoiceRackPlan (steps→SlotCommand), TimelineScheduling.laneEvents/activeRegion.
Everything below is DEVICE wiring — compile-verified + audio-thread-reviewed here,
but NOT proven until a device run. Ships behind a flag so the shipping path is
untouched until the founder enables TestFlight and device-verifies.

## The safety envelope: FeatureFlags.multiRoll (default OFF)
- Absent key = OFF = today's exact single-shared-voice path. Release BIT-IDENTICAL.
- When OFF: the LaneVoiceRack is NOT instantiated/attached (no extra CPU/memory),
  TimelineRegionPlayer keeps the single rollLaneID path. Zero behavioral change.
- Flag flips ON only in a dev/TestFlight build for device verification; stays OFF
  in shipped builds until CPU<30% / mem<200MB / "two tracks sound" are device-proven.

## B07 — LaneVoiceRack (the pre-attached voice pool)
- NEW `Sequencer/LaneVoiceRack.swift`: `@MainActor final class LaneVoiceRack`.
  Holds N (=4 to start) `PolySynthVoice` instances — each ALREADY carries its own
  `lazy var sourceNode: AVAudioSourceNode` + `nonisolated(unsafe) SPSCQueue<NoteCommand>`
  (capacity 128) + its own render block. NO new audio-thread code; reuse the voice.
- `attachAll(to: audioEngine)`: calls `voice.attach(to:)` for each slot voice.
  INTEGRATION POINT: EchoelmusicApp startup "attaching voices" block (after
  subBass.attach, BEFORE `audioEngine.start()` — attach-before-start law), guarded
  `if FeatureFlags.multiRoll { rack.attachAll(to: audioEngine) }`. Inject via Environment.
- `start(subscribing: bus)` per slot voice (mirror the existing polyVoice.start), ON only.
- Each slot also owns a `PianoRollModel` (its lane's content container).

## B08 — TimelineRegionPlayer fan-out (drive all MIDI lanes)
- On each transport step, when `FeatureFlags.multiRoll`:
  `LaneVoiceScheduling.plan(document, from, to, pool)` → `LaneVoiceRackPlan.commands(steps, capacity)`
  → per `SlotCommand`: `.load(slot, clipID)` loads that clip's melody into slot's
  PianoRollModel+voice; `.clear(slot)` stops the slot; `.silence(slot)` = overflow lane muted.
  Route each slot's notes to ITS voice's SPSC queue (noteOn/off), exactly as the
  single roll does today — just N of them.
- The single `rollLaneID` path stays as the OFF fallback; do not delete it.

## B09/B10 — per-lane mix + builtin instrument (after B07/B08 device-verified)
- B09: bind TimelineLane.level/pan/mute/solo (effectiveGain) to each slot voice
  (mixGain + control-plane sourceNode.pan — the B2 path).
- B10: pure `LaneVoiceKind` map (builtinInstrument → poly/drums/sampler/subBass/bio);
  instantiate the resolved voice kind per slot instead of always PolySynthVoice.

## Audio-thread laws honored
- Each voice render reads its OWN SPSC queue (existing, lock/alloc-free). attach-before-start.
- No per-frame Task/@MainActor. Control plane (@MainActor) enqueues; render dequeues.
- Overflow deterministic (LaneVoiceRackPlan silences lowest-priority lanes).

## Build order (each: audio-thread-reviewer + CI-compile; DEVICE-verify when TestFlight on)
1. B07 rack + flag + attach (OFF = no-op) → CI green.
2. B08 fan-out behind flag → CI green.
3. Device-verify (flag ON dev build): 2 lanes sound, CPU/mem within limits.
4. B09 mix, B10 instrument-kind.
5. Only after device-verify: consider defaulting the flag ON.

## Why staged/flagged now (Council synthesis, inline)
Architect/Vision: multi-roll is THE keystone; flag-OFF landing is safe + real progress.
DSP Purist/Skeptic: audio-graph correctness needs device runtime; blind-building is
risky — so it ships OFF and is only claimed working after device verify. Shipper/User:
staged flagged means it's ready to flip the moment the founder enables TestFlight.
Verdict: BUILD behind the flag, incrementally, review each step; HOLD the "flag ON"
default for device verification. No shipping-path risk in the meantime.
