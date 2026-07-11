# AUTONOMOUS BUILD CHARTER — the self-prompt (2026-07-11)

Feed this to yourself each cycle while the founder is away. It is tuned to build the whole
Echoel vision (8 tool domains in ONE bio-modulated interface) at the highest level, seamlessly,
without regressing the one thing that already works: the launching instrument.

---

## THE PROMPT (use verbatim each cycle)

> You are building Echoel toward its full vision — a single bio-modulated instrument that
> unifies DAW · sequencing · mixing · FX · visuals · lighting · (later) video · broadcast, where
> the body drives modulation and the user can also produce normally. The founder is away and
> cannot test. Your job: **close the next known gap safely and provably.**
>
> 1. Open `scratchpads/MASTERPLAN_8TOOLS_2026-07-11.md`. Take the FIRST unchecked queue item.
> 2. If it needs design deliberation or touches architecture / audio-thread / >1 file / render
>    safety, convene The Council (silently) and apply `swiftui-render-safety` + audio-thread rules.
> 3. Build the MINIMAL correct change (Ralph: one item, small blast radius). Write the failing
>    test FIRST for any new logic. Prefer pure, CI-verifiable work. For anything whose quality
>    needs the founder's ear/eye, ship it behind a SAFE default (off / passthrough / bit-identical)
>    and mark it `NEEDS-FOUNDER-VERIFY` — never claim a blind sensory change as finished-good.
> 4. Run the reviewers the change demands (audio-thread-reviewer for render paths,
>    ui-state-reviewer for SwiftUI, concurrency-reviewer for @Observable/async).
> 5. Commit (conventional prefix, the required trailers). Push to
>    `claude/piano-roll-clip-view-wozlie`. Verify BOTH gates green (Quick Test + Xcode Compile
>    Check) before treating it as done — CI is the only ground truth here.
> 6. Tick the item in the MASTERPLAN, keep `docs/dev/FEATURE_MATRIX.md` honest, log to
>    `scratchpads/SESSION_LOG.md`. Schedule the next cycle. Repeat until the queue's
>    autonomous items are done or the founder returns.
>
> Hard limits (never cross): don't grow EchoelStudioView's `.sheet` chain; no 10 Hz `@Observable`
> read in any ancestor of a menu host; no locks/malloc/GCD on the render path; Rausch triad
> read-only; no new deps/targets/dirs; EchoelValueField for every parameter; Uncodixfy + adaptive;
> brand purity. When a step genuinely needs the founder (taste, device, a dependency decision),
> STOP that step, queue it as `NEEDS-FOUNDER-VERIFY` / `DEFERRED`, and move to the next safe item —
> never fake progress and never stack unverified sensory changes.

---

## Why this converges (the seam)
- The 8 tools are ONE document (EngineBus + Transport + Clip/Arrangement/Automation stores +
  ModulationMatrix). Each "tool" is a VIEW onto it. We assemble views onto real infra — we do not
  build 8 engines. That is why it can be seamless and clean, not 8 mediocre clones.
- "Bio-modulated OR produced normally" = ONE mechanism: every parameter's value is set by a drawn
  automation curve OR a bio `ModRoute`. Same destination, two sources. Both halves already exist;
  the work is exposing the assignment everywhere through the one `EchoelValueField`.
- Safety is the path, not the brake: shipping behind safe defaults + CI gates lets the ambitious
  build proceed for hours without a single regression to the instrument that already launches.
