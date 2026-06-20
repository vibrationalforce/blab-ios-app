# Plan: Authoritative Transport / Clock (shared time base for the DMW)
Date: 2026-06-20
Branch: claude/transport-clock (cut from current dev branch)

## Context
Today "time" lives inside `PatternEngine` (Sequencer/PatternEngine.swift): it owns the
DispatchSourceTimer, `currentStep`, `tempo`, `swing`, and the `onStep`/`onTick`/`onStop`
callbacks. Everything that needs to be in time piggy-backs on it: `ArrangementPlayer`
(`transportStep(step)`), `PianoRollModel` (`pattern.onTick`), `BeatPlayer` (`pattern.onStep`),
and tempo modulation (`beatPlayer.pattern.setTempo`). 16 steps == 1 bar is baked in.

To become the "bio-reactive object source for multidimensional media" we need ONE clock a
future video playhead, MIDI clock (in/out), and Ableton Link can all ride. Extract a
`Transport` that owns tempo + position + transport state + subscribers; make PatternEngine a
*follower* of it. **Step 1 changes zero audible behavior** (PatternEngine keeps its own timer,
just mirrors state into Transport). Later cycles move the timer into Transport and add
sync sources.

## Target Transport API (Core/Transport.swift — NEW)
`@MainActor @Observable public final class Transport` — the control plane (snapshots only;
identical concurrency posture to PatternEngine/EngineBus).

Properties (observed, `private(set)`):
- `tempo: Double` (clamped 30...300), `swing: Double` (0...0.5)
- `isPlaying: Bool`
- `position: TransportPosition` — value type `{ bar, beat, step, ppqTick, sampleTime }`
  (16 steps/bar, 4 steps/beat). `step` is the global step counter; `bar/beat/step` derived.
- `ppqResolution: Int = 24` (MIDI-clock standard: 24 ppq → 6 pulses per 16th).
- `sampleRate: Double` (set from AudioEngine; for sample-time stamping).

Methods (control plane, main actor):
- `play()`, `stop()`, `continue()` (resume without zeroing position), `seek(toStep:)`
- `setTempo(_:)`, `setSwing(_:)`
- `tick(step:)` — advance one 16th boundary; recomputes `position`, fans out to subscribers.
  (In step-1 this is *called by* PatternEngine; later Transport drives it.)

Subscription model (NO Combine; matches repo's callback style):
- `public func addStepSubscriber(_ id: String, _ cb: @escaping (TransportPosition) -> Void)`
- `addStopSubscriber`, `addStartSubscriber`, `addTempoSubscriber`
- `removeSubscriber(_ id: String)` — keyed dictionary so views/players register/unregister
  cleanly (replaces today's single-slot `onStep`/`onTick`/`onStop`).
- Subscribers fire on the **main actor** — they do model/synth mutation (same as today's
  `onTick`). This is the SLOW control plane (~ up to ~33 Hz at 300 BPM), never the audio thread.

Audio-thread / lock-free posture:
- Transport mutates only on `@MainActor`; subscribers run on main. **No audio-thread reads of
  Transport.** Voices already pull params lock-free in their render blocks (SamplerVoice /
  PolySynthVoice `nonisolated(unsafe)` mirrors) — that path is untouched.
- For future sample-accurate scheduling: add `@ObservationIgnored nonisolated(unsafe) var
  sampleTimeMirror: Int64` written in `position`'s update, readable by a render block — same
  pattern as `SubBassVoice.audioSubGain`. Not needed for step 1.

## Backward-compatible adapter (Cycle 1 — ZERO behavior change)
Keep PatternEngine's timer EXACTLY as-is. Add a `weak var transport: Transport?` to
PatternEngine. In `advance()` (after computing `step`), call `transport?.tick(step:)`,
and call `transport?.play()/.stop()` from `play()/stop()`, `transport?.setTempo` from
`setTempo`. PatternEngine remains the source of pulses; Transport is a *mirror/relay*.
New subscribers can attach to Transport, but the existing `onStep`/`onTick`/`onStop`
closures stay wired and firing. Net audible change: none. CI stays green because no
call-site is forced to migrate yet.

## Files to add / change (per cycle, ≤3 files each)

### Cycle 1 — Add Transport + mirror (safe, no behavior change)
- ADD `Sources/Echoelmusic/Core/Transport.swift` (class + `TransportPosition`).
- ADD `Tests/.../TransportTests.swift` — position math (step→bar/beat), clamp, play/stop/seek,
  subscriber add/remove/fire ordering. (TDD: write RED first.)
- EDIT `Sequencer/PatternEngine.swift` — add `weak var transport`, relay `tick/play/stop/
  setTempo`. (3 files.)
- Test: `swift test --filter Transport` GREEN; existing Sequencer/PianoRoll tests unchanged.

### Cycle 2 — Migrate ArrangementPlayer to Transport subscriber
- EDIT `Sequencer/ArrangementPlayer.swift` — instead of host calling `transportStep`, register
  `transport.addStepSubscriber("arrangement")`; keep `transportStep(_:)` as a thin shim that
  Transport calls. Bar-wrap logic unchanged (still detects global step % 16 == 0).
- EDIT `EchoelmusicApp.swift` — pass `transport` into ArrangementPlayer.play(...).
- Test: existing ArrangementPlayer tests pass; add one asserting subscriber fires on wrap.

### Cycle 3 — Migrate PianoRollModel to Transport subscriber
- EDIT `Studio/PianoRollView.swift` — `PianoRollModel.start(...)` takes `transport`, registers
  `addStepSubscriber("pianoRoll")` + `addStopSubscriber`, drops `pattern.onTick/onStop`.
- EDIT `EchoelmusicApp.swift` — `pianoRoll.start(transport:voice:...)`.
- Test: melody trigger test drives `transport.tick(step:)` directly (no PatternEngine needed).

### Cycle 4 — Migrate BeatPlayer drum trigger to Transport
- EDIT `Sequencer/BeatPlayer.swift` — drums register `addStepSubscriber("drums")`, reading the
  grid at `position.step % 16`. Drop `pattern.onStep`. (PatternEngine still owns the timer.)
- EDIT `EchoelmusicApp.swift` — modulation tempo route calls `transport.setTempo` not
  `beatPlayer.pattern.setTempo`.
- Test: drum-trigger test via `transport.tick`.

### Cycle 5 — Move the clock INTO Transport (PatternEngine becomes pure model)
- EDIT `Core/Transport.swift` — move the swing-aware DispatchSourceTimer (verbatim from
  PatternEngine.scheduleTick/advance, incl. the iOS-18/Swift-6 main-queue-only trap comment)
  here; `tick()` becomes internal.
- EDIT `Sequencer/PatternEngine.swift` — delete timer/`advance`/`scheduleTick`; keep grid +
  `velocity()` + `load/clear`. `isPlaying/currentStep` become computed off Transport (or
  removed; callers read `transport.position.step % 16`).
- EDIT `EchoelmusicApp.swift` — own a single `Transport`, inject everywhere.
- Test: full sequencer suite GREEN; on-device beat audibly identical.

## MIDI clock (Cycle 6 — Swift/CoreMIDI, no dep)
- ADD `Sync/MIDIClockBridge.swift`.
  - **OUT (leader):** Transport subscriber that, on each step, sends 6 × 0xF8 clock bytes
    (24 ppq) spaced by `position` timing; 0xFA (start) on `play`, 0xFC (stop) on `stop`,
    0xFB (continue). Uses existing `MIDIOutput` (Audio/MIDIOutput.swift) virtual source.
  - **IN (follower):** parse 0xF8 in `MIDIInput` (Audio/MIDIInput.swift); average inter-pulse
    interval over 24 pulses → derived BPM → `transport.setTempo`; 0xFA/0xFC → play/stop. A
    `Transport.clockSource` enum (`.internal` / `.midi` / `.link`) gates who drives `tick`.
- Test: feed synthetic 0xF8 stream, assert derived tempo within tolerance + jitter smoothing.

## Ableton Link (later — free LinkKit)
- Link ships as `liblink` (C++ headers). Swift-only-with-one-dep rule: this is a **deferred,
  Council-gated** addition — bridge via a tiny `module.modulemap` shim, no SPM C++ target churn
  until approved. The integration point is already isolated: a `LinkBridge` becomes another
  `clockSource` that (follower) calls `transport.setTempo` + phase-aligns `tick`, or (leader)
  publishes Transport's tempo/beat to the Link session. No call-site outside Transport changes.

## Concurrency + audio-thread notes
- Transport is `@MainActor @Observable`; all subscribers run on main (slow control plane). The
  Swift-6 executor trap that bit builds 1769/1777 lives in the timer handler — when the timer
  moves (Cycle 5) it MUST stay `DispatchSource.makeTimerSource(queue: .main)` +
  `MainActor.assumeIsolated`; never a background queue (verbatim comment carried over).
- MIDI clock OUT/IN run on CoreMIDI's thread → hop to main via `DispatchQueue.main.async`
  before touching Transport (existing MIDIInput pattern). NO locks, NO malloc added anywhere
  on the audio render path; Transport is never read from a render block in any cycle here.
- Protected Rausch triad (BioEventGraph/HilbertSensorMapper/BioSignalDeconvolver) untouched.

## Risks
- Subscriber fan-out ordering matters: arrangement MUST load a section BEFORE piano-roll
  triggers that bar (today guaranteed by `onTick` calling `arrangement.transportStep` then
  `trigger`). → Mitigation: Transport fires step subscribers in a deterministic registration
  order and we register arrangement before pianoRoll (assert in a test).
- Double-fire during migration (both `onStep` and a new subscriber live). → Mitigation: each
  cycle removes the old closure in the SAME commit it adds the subscriber.
- Tempo-change re-arm lag already handled in PatternEngine; preserve exactly when moving timer.

## Test Strategy
- New: TransportTests (position math, subscribers, clock-source gating, MIDI-clock derive).
- Run each cycle: `swift test --filter Transport` + `--filter Sequencer` + `--filter PianoRoll`.
- Full `swift test` + `swift build` (warnings-as-errors) before each ship.
- On-device after Cycle 5: confirm beat + melody + arrangement audibly identical.

## Rollback
- Cycles 1–4 are additive/relay — revert the single commit; PatternEngine's own timer + closures
  still work standalone. Cycle 5 is the only irreversible-ish step; gate it behind a green
  device check and keep it isolated so `git revert` restores the in-engine timer cleanly.
