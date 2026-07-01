# PLAN — DAW-look reorg (Ralph Wiggum loop)

**Founder direction (2026-07-01):** "Bau das alles um — Ralph Wiggum lambda — bis
Biofeedback einen guten Platz gefunden hat und der Fokus auf der multidimensionalen
Multimedia-Produktion mit DAW-Look ist."

**North star:** Echoel FEELS like a pro production tool (Ableton session/arrangement/
mixer/transport · DaVinci pages/timeline). **Biofeedback is ONE source/element**, not the
whole app. One cycle per change; build → review → ship → loop. NEVER a big-bang root
rewrite (WorkspaceView is the black-screen landmine) — grow via the EXISTING surface
switcher (`Surface` enum + `surfaceLayer`, all mounted).

## What already exists (don't rebuild)
- `WorkspaceView` surface switcher + bottom tab bar: **Arrange · Clips · Compose**.
- Built but buried (in Tools sheets): **Channel Rack** (mixer), Automation lanes, Audio
  clips, Piano roll, Patch editor, Step sequencer, MIDI export.
- Biofeedback: always-on BioStrip + rPPG + coherence (currently prominent → to be repositioned).

## Cycles (one per commit, each shippable)
1. **Mix surface** — Channel Rack as a first-class page (add `.mix` to Surface). ADDITIVE. ← doing
2. **Persistent transport bar** — Play/Stop · BPM · position · loop, across all surfaces
   (in WorkspaceView chrome; leaf-read live values → freeze-safe).
3. **Dedupe** — remove now-redundant Tools entries that became surfaces ("a name = one thing").
4. **Biofeedback "a good place"** — a **Bio** source/lane (not the always-on center): a Bio
   surface OR a track-lane that routes bio → audio/visual, so it's one modulation source
   among many. Repositions the BioStrip from "the app" to "a source".
5. **Browser** surface (Sounds/Samples/Presets) — Ableton's left column, from SampleBrowser.
6. **Video page (DaVinci)** — timeline + clips + the bio-visual as a source. BIG, greenfield
   (P3/P4); its own sub-plan + device verification.

## Guardrails
- Surface adds follow the existing safe pattern (enum case + `surfaceLayer`, all mounted).
- No high-freq `@Observable` read in WorkspaceView/ancestor bodies (10 Hz freeze rule) —
  live bio/transport values read in leaf views only.
- Don't grow the `.sheet` chain in EchoelStudioView.
- Each cycle: reviewer pass (no local Swift build) → compile gate → ship.
