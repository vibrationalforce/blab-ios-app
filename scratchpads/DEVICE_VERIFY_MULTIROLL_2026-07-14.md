# DEVICE-VERIFY CHECKLIST — Multi-Roll (when TestFlight is re-enabled)

The pure foundation + the B07 rack scaffold are landed + CI-green behind
`FeatureFlags.multiRoll` (default OFF = today's single-voice path, bit-identical).
This is the crisp on-device sequence to bring multi-roll live. Do it in ORDER; each
step is a small commit + a device run. Keep the flag OFF in shipped builds until
step 4 passes.

## 0. Enable the flag (dev/staging only)
- `FeatureFlags.set(.multiRoll, true)` from a dev toggle (no shipped purchase/settings
  UI needed — set it in a debug affordance or a launch-time dev default). Confirm a
  clean launch first (LaunchGuard "healthy", no black screen).

## 1. Verify B07 rack attaches cleanly (already built — 174e931)
- On launch with the flag ON, the rack creates + attaches N=4 PolySynthVoice slots
  BEFORE `audioEngine.start()`. ACCEPTANCE:
  - [ ] App launches, audio engine starts OK (breadcrumb "audio engine started OK").
  - [ ] NO dropout/glitch at launch from the extra attaches.
  - [ ] CPU < 30%, memory < 200 MB at idle with 4 idle slot voices (idle-voice skip
        should keep them near-free). If mem/CPU too high, lower N or lazy-attach.

## 2. Build + verify B08 fan-out (the real playback wiring — build on device)
- TimelineRegionPlayer, when `FeatureFlags.multiRoll`: per transport step call
  `LaneVoiceScheduling.plan(document, from, to, &pool)` → `LaneVoiceRackPlan.commands(steps, capacity: rack.capacity)`
  → for each SlotCommand: `.load(slot, clipID)` load that clip's melody into the
  slot's roll/voice; `.clear(slot)` stop it; `.silence(slot)` overflow = muted.
  Route each lane's notes to `rack.voice(slot:)`'s SPSC queue (same as the single roll,
  ×N). Keep the single-`rollLaneID` path as the OFF fallback (do not delete).
- DESIGN CHOICE to settle on device: per-slot `PianoRollModel` (heavy, matches today's
  driver) vs. a lighter direct note-scheduler per slot. Prototype the lighter path
  first — a per-slot note cursor reading the lane's active region — and only fall back
  to N PianoRollModels if timing/automation needs the full driver.
- ACCEPTANCE:
  - [ ] Two MIDI lanes with different clips play SIMULTANEOUSLY, each on its own voice.
  - [ ] Loop seam is clean (no double-trigger / hung note at the wrap).
  - [ ] Removing/adding a lane mid-play re-binds slots without a glitch (LaneVoicePool
        stability + overflow-promotion — already unit-pinned in LaneVoicePoolChurnTests).

## 3. B09 per-lane mix + B10 instrument-kind (after B08 plays)
- B09: bind each lane's level/pan/mute/solo (effectiveGain) to its slot voice
  (mixGain + control-plane sourceNode.pan). ACCEPTANCE: mute/solo/pan per track are
  audibly independent.
- B10: use `TrackInstrument.voiceKind` (pure, shipped) to instantiate the right voice
  per slot (drums/sampler/subBass/bio) instead of always poly. ACCEPTANCE: a drum track
  sounds like drums, a bass track like bass.

## 4. Flip the default
- Only after 1–3 pass on device across a couple of sessions: consider defaulting
  `FeatureFlags.multiRoll` ON (or gate it to a "Pro/Studio" toggle). Ship.

## Ready-made pure pieces (all CI-green, no rebuild needed)
- `LaneVoicePool` / `LaneVoiceScheduling.plan` — slot alloc + per-lane events.
- `LaneVoiceRackPlan.commands` — steps → deterministic SlotCommands + overflow.
- `LaneVoiceKind` / `TrackInstrument.voiceKind` — instrument → voice class.
- `LaneVoiceRack` (B07) — pre-attached slot pool (attach-before-start, flag-gated).
- Adjacent record/warp/video cores: RecordAnchor, BioAutomationRecorder,
  MIDINoteRecorder, WarpedClipPlan, AudioClipFactory, VideoResyncPolicy, VideoExportPlan,
  RPPGConditioning — each de-risks its device item the same way.
