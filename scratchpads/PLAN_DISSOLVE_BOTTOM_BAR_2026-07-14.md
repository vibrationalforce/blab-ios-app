# PLAN — Dissolve the bottom bar → header + per-instrument EchoelSynth

Founder 2026-07-14: "Generell funktionieren die ganzen EchoelTools noch nicht. Unten
die Leiste sollte längst aufgelöst sein und sich an anderer Stelle wieder finden."

Ground-truth map: Explore audit at HEAD 1cc4fd5 (see session transcript). This plan
sequences the redesign into atomic, render-safe Ralph steps.

## What actually exists today (verified)

- **"Leiste unten" = `EchoelStudioView.menuBar`** (`:1137`): a horizontal chip row —
  Comp · Session · Sound · Mix · FX · Mood · Synth · Video — each toggling an inline
  dropdown panel (`menuDropdownHost` `:1199`, NOT a sheet). It sits low because
  `SurfaceHost` stacks the timeline ABOVE EchoelStudioView.
- **"Tools don't work" = reachability collapse, not stubs.** ~9 tools survive via
  timeline lane-head doors (PianoRoll/Automation/PatchEditor/AUv3/AudioClip/laneFX/
  Patchbay/AudioInput/Immersive). **3 are dead-triggered** (Broadcast, Meditation,
  full-visual/SpectralDonut) — their only trigger was the unmounted `toolsSection`
  grid (`:880`) via `openTool` (`:846`).
- **Per-track model already exists**: `TimelineLane` carries `instrument`, `effects`,
  `builtinInstrument`, `pan`, `patch`, `genreOverride`, `mood`, `variationSeed`
  (`Timeline.swift:37-62`) — persisted, but `patch`/`genreOverride`/`mood`/
  `variationSeed` have **NO editing UI** yet; the lane `.patch` door edits the GLOBAL
  voice (honest limitation, ArrangeTimelineView `:206-207`).
- **Header** (`WorkspaceView.topBar`) has brand + monitors only. Key/Scale/tuning/
  tempo/Session all live in the bottom `compositionPanel`/`sessionPanel` dropdowns.

## Render-safety constraints (HARD — must respect every step)

1. **Metadata SIGSEGV cliff**: EchoelStudioView root body carries **21 presentation
   modifiers** (15 .sheet + 1 .fileImporter + 2 .fullScreenCover + 3 .alert,
   `:637-783`). NEVER add #22. Prefer removing dead ones / routing new destinations
   through ONE `.sheet(item:)` enum (ArrangeTimelineView already does this via
   `ArrangeModal`, `:141/:164`).
2. **10 Hz @Observable freeze rule**: no live bio/playhead read in the root/ancestor
   body. If Key/tempo move to the header, `BodyTempoField` (reads ~10 Hz pulse) MUST
   stay a self-contained leaf.
3. **Union-size contract**: SurfaceHost children pinned `.frame(...).clipped()`.
4. **Chrome↔studio decoupling** via `.echoelChromeDoor`/`.echoelToggleBio`
   NotificationCenter posts — preserve, don't reach across view state.

## Sequenced steps (one Ralph point per cycle)

- **Step 1 (THIS cycle) — clear dead weight, buy headroom.** Delete the unmounted
  `toolsSection` grid + `openTool` switch (pure dead code). Retire the cleanly-dead
  `showBroadcast` slot (state + .sheet); keep `BroadcastView.swift` compiling (RTMP is
  a non-functional scaffold — must not be surfaced, App-Store 2.1). Chain 21→20.
  Meditation/visual slots are entangled (keep-awake, video recorder) → later, careful.
  Reviewers: ui-state + code. LOW risk (removes toward the cliff, never toward it).
- **Step 2 — Header-up (#24).** Lift Key/Scale (`tonartRow`), tuning
  (`kammertonRow`+`tuningRow`), tempo (`tempoRow`/`BodyTempoField` as a LEAF), and
  Session name/place (`SessionNamePreviewLeaf`+`placeRow`) into a compact header row;
  remove the `Comp` + `Session` chips. Delete Transpose (founder-approved) + clean its
  `currentToneHz`/visual reads. Visible "die Leiste löst sich auf." Freeze-safe leaves.
- **Step 3 — Per-instrument EchoelSynth panel (#23).** Attach a per-lane panel to the
  lane door backed by the EXISTING `lane.patch`/`genreOverride`/`mood`/`variationSeed`
  fields (Sound&Texture · Mix · FX ; Composition: Genre · Variation · Mood ; Weather).
  Reuse existing panel builders (compositionPanel/soundPanel/mixerPanel/effectsPanel/
  moodPanel) rebound to the selected lane. Route via ArrangeModal enum (no new sheet).
- **Step 4 — Retire the remaining menuBar chips** as their function lands in header /
  per-instrument, until the bar is gone. Remove now-dead dropdown builders + slots.
- **Step 5 — Re-home or formally retire Meditation/full-visual** (detangle keep-awake
  + video recorder) per founder intent (Meditation is intentionally door-less).

## Open founder decisions (not blockers; resolvable from documented intent)
- Broadcast/Meditation stay retired-in-code (non-functional / intentionally door-less).
- Video recording of the visual (currently dead in the showVisual cover) = P3 roadmap;
  detangle in Step 5, don't delete the recorder blindly.
