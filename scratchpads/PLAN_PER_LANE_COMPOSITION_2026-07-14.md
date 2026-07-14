# PLAN — Per-instrument composition (Genre · Mood · Variation per lane)

Founder architecture (2026-07-14, "alles pro Instrument"): each MIDI lane optionally
composes in its OWN genre / mood / variation, so several genres can sound at once —
the per-lane twin of the per-instrument Transpose (v210) and per-lane patch/pan.

Task #23. Continuation of the "dissolve bottom bar → per-instrument" arc (Step 3).

## Ground truth (Explore @ 8236a05)

- **The three fields exist + persist but are INERT** — `TimelineLane.genreOverride:
  MusicStyle?` / `mood: MoodProfile?` / `variationSeed: UInt64?` (`Timeline.swift:60-62`)
  are written/decoded but **read by NO live compose path** (like `patch` was pre-wiring).
- **A tested pure seam already exists with ZERO callers**: `LaneComposerInput.apply(_:to:)`
  (`Sequencer/LaneComposerInput.swift:32-38`) folds all three overrides onto a base
  `ComposerInput`; `hasOverride(_)` (`:42`) gates it. This is the missing piece's math,
  already done + unit-tested.
- **The compose path is GLOBAL, one take**: `EchoelStudioView.generate()`
  (`EchoelStudioView.swift:3617`) builds ONE `makeComposerInput()` (`:3493`, global
  `style`/`mood`/`structureSeed`), calls `BioComposer.compose(input)` ONCE (`:3627`),
  loads the single primary `pianoRoll`. No lane iteration.
- **Per-lane VOICES are live** (multi-roll: patch/transpose/pan per lane via
  `LaneVoiceRack`), but per-lane NOTES are not — a secondary lane plays whatever clip
  is placed on it (`TimelineRegionPlayer.swift:273/:317` load `clip.melody.notes`).
  There is no per-lane compose entry.
- Types: `MusicStyle` = `enum` 23 cases grouped by `Category` (→ Picker, NOT
  EchoelValueField). `MoodProfile` = struct of 8 Float 0…1 dims (→ each an
  EchoelValueField). `variationSeed` = UInt64 (→ dice/stepper, or reuse the maze).

## The seam (cheapest real slice, compose-only, bit-identical while no override set)

**Cycle A — compose fan-out (INVISIBLE, tested; the "make it actually work" core):**
In `generate()` AFTER the primary take composes, iterate the timeline's SECONDARY MIDI
lanes; for each `lane` with `LaneComposerInput.hasOverride(lane)`:
  1. `let laneInput = LaneComposerInput.apply(lane, to: input)` (reuse the base input's
     body-stable `structureSeed` for same-song cohesion).
  2. `BioComposer.compose(laneInput).notes` → same `finish(...)` mix/scale glue the
     primary uses.
  3. Write those notes into THAT lane's clip `melody.notes` via ClipStore/TimelineStore,
     so `TimelineRegionPlayer`/`LaneNotePump` (`:317`) picks them up on load.
Leave the primary lane on today's `pianoRoll` path (compose ONLY overridden secondary
lanes) → smallest slice, bit-identical while no lane has an override.
- Needs: a ClipStore/TimelineStore API to REPLACE a lane's clip melody notes (verify it
  exists or add a minimal setter). Determine how a secondary lane maps to its clip id.
- Tests: LaneComposerInput already tested; add a generate-fanout test if a pure seam can
  be extracted (e.g. a `composeLaneOverrides(base:lanes:) -> [laneID: [Note]]` pure func
  in Sequencer, called by generate()). PREFER extracting that pure func so the fan-out is
  Linux-testable and generate() just applies the dictionary.

**Cycle B — UI (per-lane, in the SAME LaneFX door as Transpose):**
Add to `LaneFXEditor` (already per-lane, already hosts Transpose): a Genre **Picker**
(reuse `genrePicker` sectioned pattern, bound to a new `setLaneGenre`), the 8 Mood
**EchoelValueField**s (bound to `setLaneMood`), and a Variation dice/seed. Each onCommit
routes through the compose fan-out (like `recomposeIfRunning()`), so an edit re-composes
that lane. MIDI-lane-gated. ui-state + code review.

## Render-safety / law checks
- `generate()` is on the monolith EchoelStudioView but is an ACTION (not body) — no
  sheet-chain growth, no 10 Hz read added. UI additions go in the per-lane LaneFX SHEET
  (its own editor), NOT the root body → no freeze risk (same as Transpose).
- `BioComposer` unchanged (no DSP-triad touch); compose runs on @MainActor at generate
  time, never the audio thread. SeededRNG/UUID-fold discipline already in the composer.
- Additive: `hasOverride` gate ⇒ bit-identical while all overrides nil.

## Council (compact)
- Architect: reuse `LaneComposerInput` (tested) + a new pure `composeLaneOverrides` fan-out;
  no new coupling, generate() just applies results. ✓
- DSP-Purist: no audio-thread/triad touch; compose is main-actor. ✓
- Skeptic: cheapest-wrong = writing into the WRONG clip id / clobbering a user's placed
  clip. Mitigate: only overridden lanes, only their active region's clip, and confirm the
  ClipStore write path (Cycle A must verify clip ownership before shipping).
- Shipper: split A (invisible compose fan-out + pure test) / B (UI) — each reviewable,
  A is bit-identical while unset.
→ Gate: PROCEED to Cycle A once 8236a05 (v210) gates are green (Cycle A overlaps
  TimelineStore/Timeline with 8236a05 → don't stack on unverified). Extract the pure
  `composeLaneOverrides` seam first (test-first).

## Sequence
- [ ] Confirm 8236a05 green.
- [ ] Cycle A: pure `composeLaneOverrides(base:lanes:clips:)` seam + test (RED→GREEN),
      then call it in generate() + ClipStore write; verify clip-ownership. Reviewers:
      code + concurrency (+ dsp if BioComposer touched — it should NOT be).
- [ ] Cycle B: LaneFX per-lane Genre/Mood/Variation UI + setters; ui-state + code review.
- [ ] Deploy once B lands (working, visible) — like the Transpose two-commit/one-deploy.

## ⚠️ FINDING 2026-07-14 (Explore ad53aae) — PREMISE INVALIDATED, FOUNDER-GATED

Deep runtime trace invalidates Cycle A's core assumption:
- Secondary MIDI lanes DO read notes from ClipStore `clip(id: region.clipID).melody.notes`
  via LaneNotePump (TimelineRegionPlayer.swift:273/:317) — so the DATA TARGET is right.
- **BUT `EchoelStudioView.generate()` NEVER starts TimelineRegionPlayer, never creates
  regions, never writes ClipStore.** The generative take lives ONLY in PianoRollModel
  (+ beatPlayer.pattern). The timeline / "Play timeline" transport
  (ArrangeTimelineView.swift:300, `.disabled(regions.isEmpty)`) is a SEPARATE, opt-in
  path. During a normal generative take, secondary lanes are SILENT unless the user
  placed regions and pressed Play-timeline.
- Secondary lanes via LaneNotePump are single-bar (16-step) loops only (folds `% 16`);
  the primary roll cycles multi-bar arrangements. Multi-bar per-lane composition needs
  pump/loop-length work.

=> "Each instrument composes in its own genre during a GENERATIVE take" requires BRIDGING
   the generative flow into the timeline (create regions+clips per lane AND run the
   timeline transport, or drive the fan-out from Generate) — an ARCHITECTURALLY
   SIGNIFICANT unification of two transports, NOT a cheap decision-free slice. Filling
   `melody.notes` alone changes nothing audible in the generative flow = the banned
   "unfunktionierende Sache".

**GATE: HOLD-FOR-FOUNDER.** Real ambiguity (invalidated premise + two-transport
architecture question). Founder question to surface when active: "Sollen der generative
Instrument-Flow (pianoRoll) und die Timeline/Arrange-Spuren zu EINEM Transport
verschmelzen (Voraussetzung für Genre-pro-Spur im generativen Take), oder bleibt
Genre-pro-Spur auf die Timeline-Fläche beschränkt?" Meanwhile: proceed with the other
decision-free founder asks (Detune ✓ v213, Oktaver next).
