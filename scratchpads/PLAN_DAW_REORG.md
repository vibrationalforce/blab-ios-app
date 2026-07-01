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
1. ✅ **Mix surface** — Channel Rack as a first-class page (`.mix`). Shipped v10.77.5.
2. ✅ **Persistent transport bar** — Play/Stop · Tempo · bars.beats position across all
   surfaces (WorkspaceView chrome; position in a leaf → freeze-safe). NO fake loop button
   (deferred until a real loop region exists). Shipped v10.78.0.
3. ✅ **Dedupe** — Channel Rack Tools entry/sheet/@State removed now that Mix is a surface
   ("a name = one thing"; also shrinks the EchoelStudioView body generic type). v10.78.0.
4. ✅ **Biofeedback "a good place"** — a **Bio** SOURCE surface (`BioSourceView`): arm the
   body as an input, live metrics, route Body→sound / Body→visual, entrainment + safety.
   Shares the one `cameraRPPG` with Compose (idempotent → `isRunning` is truth). v10.78.0.
5. ✅ **Browser** surface (`BrowserView`) — Presets (recall a sound) + Samples (audition).
   Freeze-safe (segmented Picker, no high-freq read). v10.78.0.
6. ⏸ **Video page (DaVinci)** — DESIGNED + DEFERRED (needs on-device verification; see
   `scratchpads/PLAN_VIDEO_PAGE.md`). Not shipped blind during the autonomous window.

**Bottom bar now:** Arrange · Clips · Compose · Mix · Bio · Browse (6 tabs — pro-tool IA).

## Guardrails
- Surface adds follow the existing safe pattern (enum case + `surfaceLayer`, all mounted).
- No high-freq `@Observable` read in WorkspaceView/ancestor bodies (10 Hz freeze rule) —
  live bio/transport values read in leaf views only.
- Don't grow the `.sheet` chain in EchoelStudioView.
- Each cycle: reviewer pass (no local Swift build) → compile gate → ship.
