# PLAN — Unify the control surface (one accessible solution)

**Founder (2026-07-02):** "Die gesamte Bedieneinheit ist noch zu unübersichtlich.
Vermeide doppelte Wege — alles soll aus EINER accessible Lösung bestehen. Super
intelligent für noobs, die durch Echoelmusic zu professionellen Ergebnissen kommen."

## Mental model (the north star)
**One transport · one bio home · one place per function.** Every control lives in
exactly ONE home; the header is glanceable STATUS that routes to that home; the noob
sees one obvious primary action per surface, pros get depth without clutter.

- **Compose** = *make* music (bio-generative "Start" = create a take).
- **Transport bar** = *play* what exists (the ONE Play/Stop/Tempo/position, every page).
- **Bio** = the body as a source (arm · live metrics · routing · entrainment).
- **Mix / Browse / Arrange / Clips** = levels / sounds / song.

## Duplicate paths found (the clutter)
1. Play/Stop ×3 — transport bar · Arrange "Play song" · Compose "Start".
2. Bio ×3 — Compose BioStrip (+ "Read pulse") · Bio page · header pulse monitor→fullscreen.
3. Tempo ×2 — transport bar · Compose lockedBPM.
4. Visual ×2 — header immersive monitor (plain fullscreen) · Compose Tools "Visual" (rich: VJ + record).
5. Tools sheet (~13) partly overlapping Mix/Bio/Browse surfaces.

## Cycles (safest→riskiest; one commit each, reviewer + compile-gate)
- **U1 ✅ Pulse = one home.** Header pulse tap → switch to the Bio SURFACE (not a
  separate fullscreen). Remove the duplicate `ExpandedMonitor.pulse` fullscreen +
  `pulseScreen`. WorkspaceView/HeaderMonitors only — no EchoelStudioView risk. ← doing
- **U2 Visual = one home.** Keep the RICH visual (VJ controls + record); route the header
  immersive monitor to it; remove the plainer duplicate. (Needs cross-surface wiring —
  do carefully; keep record/VJ reachable.)
- **U3 Play on Arrange = the one transport.** Make the global transport Play context-aware
  on Arrange (drive ArrangementPlayer), retire Arrange's separate "Play song".
- **U4 Tempo = one model.** Fold Compose lockedBPM into the transport tempo (lock as a
  transport affordance), so there's one tempo control.
- **U5 Bio in Compose = slim.** Now that Bio page + header exist, reduce Compose's always-on
  BioStrip to a minimal status that routes to Bio (keep tap-to-learn reachable). RISKIEST
  (black-screen body) — its own carefully-reviewed cycle, shrinks the sheet chain.

## Guardrails
- EchoelStudioView: never grow the `.sheet` chain; removing sheets/sections is GOOD.
- 10 Hz @Observable freeze rule: live reads in leaves only.
- EchoelValueField for every parameter.
- No local build → reviewer + CI compile-gate verify each cycle; batch-deploy.
- Ralph-Wiggum: one safe dedup per commit; each shippable.
