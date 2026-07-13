# AUTONOMOUS NIGHT RUN — Standing Self-Directive (2026-07-13)

Founder mandate (verbatim core): "Mit all deinen neuen Fähigkeiten … Malmö Nacht
durcharbeiten. Ultracode Echoel. Grab all tasks in context Ralph Wiggum lambda mit
allen Fähigkeiten bis Echoelmusic bis ins kleinste Detail fertig ist. Status und
TestFlight NUR auf Nachfrage von mir. Ansonsten ohne Pause und ohne einschlafen
coden, testen, simulation, im Apple-Senior-Developer biggest agent team, super wise,
save. Laser Augen: Deep Audit, Deep Research, Feature Matrix in perfekt end-to-end
verbundenem Design + Architektur."

## HARD RULES for this run (do not violate)
1. **NO TestFlight deploy** unless the founder explicitly asks. => Do NOT touch
   `.deploy/release`. Work accumulates on branch `claude/piano-roll-clip-view-wozlie-5kxnrl`,
   CI-verified. He pulls to TestFlight when he asks.
2. **NO status messages** to the founder unless he asks. Work silently. (A device
   log or a question from him = a request; answer those.)
3. **CI is the only verification** (no local Swift compiler). Every landed change
   must pass "Xcode Compile Check" + "Echoelmusic CI/CD Pipeline". Pure cores get
   Linux XCTests. Device-gated wiring (audio/video/AVFoundation/CoreMIDI/HealthKit)
   is written + CI-compile-verified, and marked NEEDS-DEVICE-VERIFY — never claimed
   as working until a device run.
4. **Ralph Wiggum**: one coherent slice per cycle, minimal change, mandatory
   reviewer agents (concurrency / audio-thread / dsp / ui-state / code-review as
   fits), commit with conventional prefix + the required trailer. The agent TEAM
   parallelizes within a slice (find→build→adversarially verify), not sprawl.
5. **Protected DSP triad READ-ONLY** (BioEventGraph, HilbertSensorMapper,
   BioSignalDeconvolver). No audio-thread locks/alloc. No wellness/esoteric copy.
   EchoelValueField for params. Sheet-chain not grow. No 10 Hz @Observable in an
   ancestor body. decodeIfPresent for Codable. FeatureFlags default-OFF for new
   surfaces until wired.
6. Commit trailer:
   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
   Claude-Session: https://claude.ai/code/session_014nAZhmBhNNMa7NTn1FsmVB
   (Never put the model id in commits/code/artifacts.)

## LOOP PROTOCOL (each tick)
1. Read this file + `scratchpads/BACKLOG_2026-07-13.md` (the ranked, CI-safe backlog
   the Deep Audit produced). Pick the highest-priority item whose deps are met.
2. Implement it as a Ralph-Wiggum slice, TDD where a pure core exists. Use a
   Workflow (agent team) when the slice benefits from find→build→verify fan-out;
   solo for trivial mechanical edits.
3. Reviewer agent(s) → fix → commit → push. Wait for CI green (schedule wakeup).
   If red, fix immediately.
4. Update the backlog (mark done, add discovered follow-ups). Do NOT deploy or
   message the founder.
5. Repeat until the backlog is empty / "bis ins kleinste Detail fertig".

## TASKS IN CONTEXT (grabbed)
- #7 Multi-Roll — per-lane engine routing (the keystone many features depend on)
- #11 Architecture restructuring → Ableton-like tracks-centric DAW + video-in-tracks
- #13 Device-wiring: audio-loop import into lane + per-source record capture
- #14 rPPG never locks BPM (pk=0/conf=0) — the CORE bio value
- Founder feature list (07-13 screenshot): tracks = instruments (DONE v191),
  audio loops into lane, video lane drag-in, per-track record button by input,
  "all instruments/effects visible" (AUv3 Generator fix v192).

## END-TO-END TARGET (the connected design)
ONE view = the tracks/timeline. Every lane is an instrument OR a media carrier
(audio/video) with: its own voice/bus (multi-roll), record-arm→capture by input
(audio-in/MIDI-in/bio), warp for audio, video synced to the shared 480-PPQ
transport, master automation, bio-reactive core throughout. No Clip View. Live
performance from the main view. Everything routes through EngineBus; couplings
stay clean.
