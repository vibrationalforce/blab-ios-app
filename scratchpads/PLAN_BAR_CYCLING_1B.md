# PLAN — Bar-cycling loop reconfigure (1b)

Founder: composition must be reconfigured per loop size + loop through. 1a (visual
loop indicator) shipped in 79.35. 1b makes the composition ACTUALLY N distinct bars.

## Approach (Council: NOT a stepCount lift — reuse the proven seamless boundary swap)

Keep PatternEngine/PianoRollModel at 16 steps. Add a bar-cycler that pre-generates
N = loopBars distinct 16-step bars and swaps them at each loop boundary using the
mechanism the live re-seed already uses (pianoRoll.loadAtBoundary → pendingNotes,
consumed at step 0 in trigger()).

## Generate N cohesive-but-distinct bars
- N = loopBars.rawValue (LoopBarLength: 2/4/8/16/32). Cap at e.g. 8 bars live to
  bound memory/CPU (32-bar arrangements need not all be pre-generated melodies).
- For barIndex in 0..<N: BioComposer.compose(input) with the SAME structureSeed but
  detail seed = baseSeed &+ UInt64(barIndex). Same structure (progression/register)
  → bars cohere; different detail seed → each bar varies. Result: [BioComposition].

## Glitch-free staging discipline (PROVEN by construction)
Definitions: `notes`/drums = bar currently sounding; `pending` = bar to sound at the
NEXT step-0 wrap.

PatternEngine additions:
- `pendingSteps`/`pendingAccents: [[Bool]]?` + `loadAtBoundary(steps:accents:)`.
- In advance(), when `step == 0`, apply pending drums (consume) BEFORE onStep fires.
- New `onBar: (() -> Void)?` fired at END of advance() when `step == 0` (after onTick).

Play start (generate): index=0, notes=bar0 + pattern.load(bar0 drums) IMMEDIATELY,
pending EMPTY (both melody + drums). onBar handler:
```
nextBarIndex = (nextBarIndex + 1) % N     // starts at 0
stage(bars[nextBarIndex])                 // pianoRoll.loadAtBoundary + pattern.loadAtBoundary
```
Trace:
- 1st step-0 (bar0 downbeat): pending empty → bar0 plays (correct). onBar → stage bar1.
- 2nd step-0 (bar1 downbeat): pending=bar1 consumed → bar1 plays. onBar → stage bar2.
- N-th step-0: stage bar0 → loops. ✓ No off-by-one, no cut (held notes ring out).

## Fallback / safety
- N<=1 OR bars empty → behave exactly as today (single bar, no onBar/pending). No regression.
- Clamp N to [1, maxLiveBars]. Export still uses loopBars.rawValue (unchanged).

## Files
- Sequencer/PatternEngine.swift: pendingSteps/pendingAccents + loadAtBoundary(steps:accents:)
  + onBar callback (apply pending at step 0 top; fire onBar at step 0 end).
- Studio/EchoelStudioView.swift generate(): build [BioComposition], load bar0, wire onBar.
- (LoopCutter.tile NOT needed — we compose N real bars, not tile one.)

## Verification
- CI compile-check only (timing is device-only). Ship 79.36 with a CLEAR device-verify
  note: confirm bars change across the loop + seamless wrap + loop indicator matches audio.
- Risk: off-by-one at boundary is the failure mode; the discipline above avoids it, but
  ONLY device confirms. Graceful-degrade (a boundary discontinuity, not a crash).
