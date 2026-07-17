# PLAN — Refocus to a calm shell (founder pivot 2026-07-02)

Founder: the app feels too complex / half-working / irritating. Decision (Council,
founder chose): **1A + 2A** — reduce the SURFACE, keep the ENGINE; wording stays
science-first (no "meditation"/wellness label; the *experience* may be calm).

Target product = 3 pillars:
1. Bio-session experience — body → beautiful generative music + visual.
2. Render tight audio loops.
3. Social-media short videos (the one genuinely NEW build; page designed, deferred).

## Principle
Additive / reversible only (never a root rewrite — CLAUDE.md). Surfaces stay
MOUNTED in the ZStack (audio lifecycle safe). We change WHAT IS SHOWN, delete
nothing yet. Hard pruning comes later, from evidence (what the founder never opens).

## Step 1 (this cycle) — reduce the bottom bar
`WorkspaceView.swift` only.
- `Surface.primary = [.bio, .compose]` (front-door calm flow), `.advanced =
  [.arrange, .clips, .mix, .browser]` (behind one "Studio" door).
- Bottom bar = the primary tabs + a **Studio** button that opens ONE `.sheet`
  listing the advanced surfaces (tap → set surface + dismiss). WorkspaceView has
  only 1 modal today (`expandedMonitor` cover); adding ONE sheet is safe (the
  sheet-chain limit is EchoelStudioView's problem, not WorkspaceView's).
- Default surface `.arrange` → `.compose` (the instrument is the home now).
- Studio highlights when the active surface is advanced; primary tabs are always
  present, so "back" is just tapping Bio/Compose.

## Later steps (not this cycle)
- Step 2: unify Compose's internal Picker (Compose/FX/Mix/Piano-Roll/Well) so the
  calm flow (generate + visual + play) is the default and editors are secondary.
- Step 3: loop render — confirm audio/loop export is reachable + tight (LoopCutter
  + export already exist; surface a clear "Render loop" action).
- Step 4: short-video export — finish the deferred Video page (needs device verify).
- Step 5: prune hard from evidence.

## Verify
- swift build clean (CI compile-check — no local toolchain).
- No new 10 Hz @Observable read in WorkspaceView.body (freeze rule): the Studio
  sheet + tab set read only low-freq state.
- Device: 3-tab bottom bar, Studio opens the 4 advanced surfaces, audio keeps
  running across switches.
