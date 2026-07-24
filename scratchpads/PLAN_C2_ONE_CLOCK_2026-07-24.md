# PLAN — C2: one clock (Transport owns the timer)

Status: **PLANNED, implementation HELD until the TestFlight freeze lifts** (Council
2026-07-24, gate=hold). Verified genuinely-open by the Tier-C/D audit 2026-07-24.

## Why (verified current state, file:line)

- `PatternEngine` owns the ONLY real timer: `DispatchSource.makeTimerSource(queue:.main)`
  (`Sequencer/PatternEngine.swift:421`), self-rescheduled by `advance()` (`:419-428`).
- `advance()` relays into Transport: `transport?.tick(step:)` (`:457`) — PatternEngine
  drives, Transport is merely NOTIFIED.
- `Transport` has ZERO timer code; its own comment admits it: *"Driven externally today
  (PatternEngine will relay here)"* (`Core/Transport.swift:162`). It already has the
  target machinery: a priority-ordered subscriber fan-out (`Transport.swift:183-204`),
  today carrying only `"haptics"` (prio 1000, `EchoelmusicApp.swift:515`) and `"record"`
  (prio 950, `RecordController.swift:69`). Musical note dispatch still rides
  `PatternEngine.onStep`/`onTick` (`PatternEngine.swift:460,463`).

Target: Transport owns the single clock; PatternEngine becomes a relay/subscriber.
C2 is the linchpin that unblocks C1 (retire the dual ArrangementPlayer/TimelineRegionPlayer
playback path) and the tempo write-authority split.

## Council verdict (2026-07-24) — HOLD during the freeze

The clock drives note dispatch = **audio timing**. A flag-OFF scaffold is Release-bit-
identical (safe), but the flag-ON flip is audible (jitter/drift) and MUST be device-
verified — impossible while TestFlight is frozen. Skeptic's decisive objection: an inert
parallel timer built now can silently diverge from PatternEngine's proven behavior, so the
eventual on-device flip builds on sand, and running two timers risks a transient double-
drive at the flip. Building timer code we can't exercise adds unverifiable complexity that
doesn't move the founder toward the "Profi-Milestone". → PLAN now, BUILD when the freeze lifts.

## Slice sequence (execute post-freeze, device-verify each flip)

1. **S1 (pure, testable, inert):** formalize the step-advance + priority-ordered dispatch
   as a pure core Transport will call (given currentStep, loopLength, subscriber list →
   next step + ordered dispatch). Tests only; no live timer installed. Reuses the existing
   `:183-204` fan-out. FREEZE-SAFE in isolation, but only worth shipping as the first brick
   of the whole sequence (no standalone value), so it waits with the rest.
2. **S2 (flag-gated timer):** Transport gains its own `DispatchSourceTimer` behind
   `FeatureFlags.transportOwnsClock` (default OFF). Flag OFF ⇒ PatternEngine stays the live
   driver, Release bit-identical. **Device-verify the flag-ON path for timing parity vs.
   PatternEngine (A/B the same pattern, compare onset timing/drift).**
3. **S3 (relay flip):** with the flag proven on-device, PatternEngine's timer becomes a
   thin relay to Transport's clock (or is retired); note dispatch moves onto Transport's
   subscriber list. Device-verify no double-drive during the transition.
4. **S4 (retire):** remove the dormant flag + PatternEngine timer once S3 is device-proven.

## Dependencies / ordering

- C2 unblocks **C1** (one song-timeline playback) and the **tempo write-authority** split.
- Do NOT start C1's playback retirement before C2/S3 (both feed the playhead today —
  `ArrangementPlayer` + `TimelineRegionPlayer`, `EchoelmusicApp.swift:100,103`).

## Corrected Tier-C/D roadmap (audit 2026-07-24, supersedes the map's flags)

- **C1** one song-timeline — GENUINELY-OPEN (dual store+player live; ArrangementStore now
  only seeds a one-time migration `bootstrapIfNeeded`, but ArrangementPlayer is still a live
  playback path). NOT freeze-safe.
- **C2** one clock — GENUINELY-OPEN, best next; HELD (this plan).
- **C3** one voice model — GENUINELY-OPEN (singleton voices + `LaneVoiceRack` coexist;
  `FeatureFlags.voiceKindRouting` machinery already exists). NOT freeze-safe (live audio).
- **C4** split EchoelStudioView (4485 lines) — GENUINELY-OPEN; NOT freeze-safe (per-panel
  SwiftUI metadata / device-verify, swiftui-render-safety law).
- **C5** one routing owner — ~75% DONE: `ParameterApplyRouter` is already the apply table
  for automation/AU/polyVoice/per-track; the holdout is `ModulationEngine`'s direct
  `glideTempo` closure (`EchoelmusicApp.swift:826-830`) bypassing the table. MED.
- **D1** deconvolver→live heartbeat — OPEN but COST UNDERSTATED: needs a raw-waveform bus
  first (only camera rPPG has a waveform; the bus carries HR scalars). `graph.process(
  cleanedHeart: 0 …)` is a hardcoded zero (`BioEventPublisher.swift:84`) so graph heartbeats
  never fire today. Substantial plumbing, not a wire.
- **D2** BioTempoDirector→Transport.tempo — OVER-FLAGGED: bio→tempo is ALREADY live via
  ModulationEngine's `glideTempo` (`EchoelmusicApp.swift:826-829`); `BioTempoDirector` is a
  redundant unwired duplicate (kept as a tested foundation — do NOT delete, per the Tier-E
  scaffold lesson). No valuable work here.
- **D4** BioVisualParams single owner — ~PARTIAL: `BioVisualParams.from(bio,…)` is the one
  computation point (`MetalBioView.swift:730`) but only `pulseHz` is consumed; the renderer
  re-derives hue/complexity itself (`:731-764`). NOT freeze-safe (visual change).

## Bottom line for the founder

Every genuinely-open Tier-C/D item is device-facing convergence → blocked by the freeze
for verification. The freeze-safe first-slices are all inert scaffolding whose value can't
be realized until a device flip. Recommendation surfaced in the status delta: either lift
the freeze for one verification build to unblock C2/C3, or keep this planned and I continue
device-independent hardening/pipeline work until the milestone.
