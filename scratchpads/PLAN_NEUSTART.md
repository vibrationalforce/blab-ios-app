# PLAN — NEUSTART (Prioritäten-Reframe, 2026-07-04)

## Trigger
Founder: "Wenn ich sag Neustart, wir haben uns verlaufen. Wüsstest du gleich was wir von
Anfang an anders machen?" → then "Neustart."

**NOT a code rewrite.** The engine (DSP, generative music, visuals, EngineBus, patch system)
is the good part. "Verlaufen" = wrong priorities: the app tried to be everything (DAW +
biofeedback + visuals + broadcast) while the CORE INPUT — camera rPPG on a fingertip — is the
least reliable part, so nearly every device session gets consumed fighting the pulse instead
of making music. This reframe keeps the engine and fixes the priorities.

## The four pillars (in order)

### P1 — The pulse must EARN trust; camera is the *approximate* fallback, not the anchor
Root of ~90% of our loops. rPPG at the fingertip is physically noisy (finger pressure, light,
motion). Confidence alone gets inflated by the peak-counter self-agreeing on a bad signal.
- **Step 1 (79.52, THIS cycle):** trust-gate — a reading may move the shown pulse / latch the
  tempo only when confident AND corroborated by real autocorrelation (acf ≥ 0.4). A bad
  reading now HOLDS ("acquiring") instead of showing/seeding a fantasy number.
  (Device log 2026-07-04: acf 0.14 / conf 0.90 "settled" at a wrong 79; true pulse ~54.)
- **Next:** make **BLE HR (chest strap / band, 0x180D — already built) the PREFERRED source**;
  camera clearly labeled "≈ approximate (camera)". Source priority: BLE > HealthKit > camera.

### P2 — The music must be ROBUST to a noisy pulse (drive on the TREND, never the raw number)
For music you don't need a medically-accurate BPM — you need a smooth body-energy signal that
never jumps. Tempo/mod already glide + settle + fold; keep pushing so a noisy pulse can never
ruin the take. (Largely in place after 79.42–79.51; audit for any remaining raw-number path.)

### P3 — ONE screen that does ONE thing perfectly, then expand
Body → one generative musical loop → one visual, flawless. DAW depth (clips/arrange/mix/patch)
stays reachable but never front-and-centre until the core loop is loved. (WorkspaceView is
already one adaptive view + floating visual — continue pruning by evidence, not by gu! Founder
signals: "eine reicht", "alles weg außer Visuals", the BPM-readout consolidation 79.50.)

### P4 — Honesty everywhere (already the house rule)
Claim only what ships; "≈" on approximate readings; "self-observation, not diagnosis". The
new bio guide (79.51) + honest source labels serve this.

## Sequencing (one Ralph cycle each, CI-green + device-verify per step)
1. **79.52 — P1 Step 1: rPPG trust-gate (acf floor).** ← THIS cycle.
2. P1 — BLE as preferred source + honest "≈ camera" label on the fallback.
3. P2 — audit every tempo/mod writer for a raw-number path; confirm trend-only.
4. P3 — verify the core loop (Start → body → music + visual) is the calm default; prune.

## Guardrails
- Ralph: one feature/fix per cycle, ≤3 files, CI-green, device-verify before next.
- Council for anything hard-to-reverse; never touch the protected Rausch triad.
- Reversible always (feature flags / kept-but-unmounted), no big-bang.
