# PLAN — All-fronts team results (Workflow wf_0631b0db-2be, 2026-07-20)

Multi-team workflow (founder „mach alles richtig mit allen Teams"). 3/4 teams delivered;
AUv3 team failed the schema and was re-run as a free-text agent (separate).

## KEYSTONE FINDING (Leiste team) — the bar CANNOT dissolve until BodyVibe surface exists
NONE of the 5 remaining chips (mix/effects/sound/mood/synth) is safe to remove today — each
is a GLOBAL-generative control with no per-track home, or the visual window with only a
visibility toggle. My earlier PLAN_LEISTE_DISSOLVE table was too optimistic — corrections:
- **MIX is NOT redundant** with the lane head. `mixerPanel` uniquely owns the generative
  part-bus LEVELS (bass/pad/lead/drums), per-bus FILTER cutoff + DRIVE, and the drum
  CHANNEL RACK (`ChannelRackView` + B5 sample door). `laneMixStrip` only covers timeline-lane M/S/level.
- **SYNTH is the immersive VISUAL window**, not a synth. Header monitor toggles only VISIBILITY;
  the visual DESIGN customizer + play-surface touch-sound live only in `visualPanel`
  (fullscreen `visualVJOverlay` is dead-reachable via the dead `openTool('visual')`).
- **SOUND / EFFECTS / MOOD** = global generative timbre / FX-character / mood-dims; per-lane
  `.patch`/`.laneFX` doors are DIFFERENT targets (per-MIDI-lane), not the generative bed.

### Two prerequisite workstreams gate the whole dissolution
- **(A) Build the EchoelBodyVibe surface** = home for the generative timbre (sound), mood,
  global FX character (effects), and the generative bus-mix + drum rack (mix).
- **(B) Add a design door to `FloatingVisualWindow`** (or re-reach `visualVJOverlay`) for the
  synth/visual controls.

### Safe removal order (each = its own slice, `&& $0 != .X` on studioChips filter EchoelStudioView.swift:1184-1187)
video ✅(done v310) → [after A] MOOD → SOUND → EFFECTS → MIX → [after B] SYNTH →
then delete menuBar + studioChips + menuChip + menuDropdownHost + dead panels. Reversible each step.

## ECHOELBODYVIBE SURFACE (team design) — the keystone, build FIRST
**It is the bioVoice LANE's editor, NOT a 4th sibling surface.** `TrackInstrument.bioVoice.displayName`
is already "EchoelBodyVibe". Founder Plan B: "der Prototyp wird Bürger der Spuren-Welt".
- **Reach via the EXISTING single `.sheet(item: $activeModal)`** in ArrangeTimelineView (enum
  `ArrangeModal` L256). Add ONE case `bodyVibe(TimelineLane)` — NO new `.sheet` (sheet-chain law safe).
- **Composition** = existing leaves/panels re-hosted for one lane: generate/evolve flow
  (`generate()` ~L3760), soundPanel (~L2735), moodPanel (~L2611), effectsPanel fxCharacter
  (~L2940), visualPanel (~L2189), BioStripView leaf, + NEW camera-bio (A5 FaceExpressionBioPublisher,
  `FeatureFlags.cameraExpression` OFF).
- **Genre placement:** a SECOND Genre picker on the surface bound to the bioVoice LANE's OWN
  genre override (TimelineStore lane override, decodeIfPresent) via `composeLaneOverrides` — NOT
  the shared @AppStorage key (so it never clobbers the global recompose). The chrome
  `CompositionHeaderStrip` genre STAYS as the session default. Satisfies "Genre auch in BodyVibe".
- **Freeze-law:** host bodies read only low-freq `activeModal`; all ~10 Hz bio stays in leaves
  (BioStripView, a new face-channel meter leaf).
- **FIRST SLICE (next cycle):** NEW `Studio/BodyVibeSurfaceView.swift` (Genre-lane-override picker
  + BioStripView leaf + Generate button, EchoelValueField for params) + ArrangeTimelineView edits
  (add `.bodyVibe(lane)` enum case + id + modalEditor dispatch + bioVoice lane-head door). Later
  slices fold in mood/sound/effects/visual + Face source (founder-gated Info.plist camera string).

## ADAPTIVE TRACK HEADS (team design) — LANDED this cycle
Root cause: fixed `labelWidth=140` head, `.frame(width:140,height:56)` NO alignment → strip
footprint ~162 overflows → centred overflow shifts head LEFT → "MIDI 1" clips off left edge.
Landed edits (ArrangeTimelineView only, EchoelValueField untouched — floored at 162 not 152):
`labelWidth 140→162` (honest floor) · `@Environment(\.horizontalSizeClass)` + `headWidth`
(184 iPad / 162 iPhone) on ruler spacer + head · `alignment:.leading` (the un-clip) ·
door name `.minimumScaleFactor(0.85)` · strip `.dynamicTypeSize(...xLarge)` cap. Freeze-law OK
(hSize is not a 10 Hz publisher). See commit this cycle.

## AUv3 — separate free-text agent (schema team failed); see next status.

## BodyVibe surface — API investigation done (2026-07-20 cont.)
RESOLVED (all exist, public):
- `TimelineStore.setLaneGenreOverride(_ laneID, genre: MusicStyle?)` (TimelineStore.swift:545)
- `lane.genreOverride` (Timeline.swift:120/164, decodeIfPresent — Codable-safe), `mood`, `variationSeed`
- `LaneComposerInput.composeLaneOverrides` consumes them; `LaneCompositionSection` (private in
  ArrangeTimelineView:2093) already renders Genre+Mood+Variation per lane (shown for secondary MIDI lanes).
- `ArrangeModal` enum (267) + id (290) + `modalEditor` dispatch (448) — add `.bodyVibe(TimelineLane)` here.
- Genre picker pattern = grouped MusicStyle.Category (ArrangeTimelineView:2146).
- BioStripView = leaf reading EngineBus/CameraRPPG/Transport from env (inherited by sheets).

**BLOCKER (genuine ambiguity → founder ask):** NO bio lane is ever created — default doc =
MIDI 1 + Audio 1 (TimelineStore:58-72); `isBio: true` appears NOWHERE in Sources. So "BodyVibe =
the bioVoice lane's editor" has no host lane. WHERE the surface attaches (new seeded lane vs header
bio element vs standalone) is a user-visible architectural call + (for the lane option) a migration
question for existing saved projects. Asked founder. Once answered, first slice = BodyVibeSurfaceView
(Genre-override picker via public API + BioStripView leaf) reached from the chosen trigger; then fold
in mood/sound/generate/visual + Face source per the team design.
