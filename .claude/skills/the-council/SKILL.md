---
name: the-council
version: 1.0.0
description: |
  Convene a fast internal council of fixed expert seats to pressure-test any
  significant decision BEFORE acting — architecture, scope, risky/multi-file
  changes, ambiguous founder asks, "should Echoel do X?", or anything that is
  hard to reverse. Each seat gives a one-line position + its sharpest concern,
  dissent is surfaced (not smoothed), then a single recommendation + the one
  cheapest next step is synthesized. Always-on in optimized form: skip trivial
  reversible actions, convene silently and only show the verdict for the rest.
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# The Council — deliberate before you act

**Principle: no significant move without a seat at the table.** The Council is a
single fast internal deliberation, not a meeting. It exists to catch the mistake
*before* the commit, surface real dissent, and converge on ONE next step — then
get out of the way. It composes with `vision-gate` (vision filter) and the Ralph
Wiggum loop (ship one thing); it does not replace them.

## When to convene (and when NOT to)

**Convene** when a decision is any of: architectural / cross-cutting; touches >1
file or the audio thread / protected Rausch triad; changes scope, roadmap, or
public copy; is ambiguous or could be read multiple ways; is hard to reverse
(deletes, deploys, force-pushes, external publishing); or the founder asks "should
we X?" / "what's best?".

**Skip** (optimized form — do NOT council these): typo/format fixes, single
obvious reversible edits, reading/searching, answering a direct factual question,
anything already decided and logged in `decisions.csv` (point to the row instead).
Convening on trivia is the failure mode — stay cheap.

## The seats (fixed; only relevant seats speak)

| Seat | Owns | Asks |
|------|------|------|
| **Architect** | system shape, coupling, EngineBus integrity | "Does this reuse what exists? What does it couple that shouldn't?" |
| **DSP Purist** | audio-thread sanctity, Rausch triad (read-only), no simplification | "Any malloc/lock/ObjC/GCD/file-I/O in render? Are we simplifying protected DSP?" |
| **Vision-Keeper** | brand/positioning, no esoteric/overclaim, open standards | "On-vision? Any false promise or banned term? (defer to `vision-gate`)" |
| **Shipper (Ralph)** | minimal change, one feature/cycle, green build, TestFlight | "Smallest change that ships? Does build/test stay green? One thing only?" |
| **Skeptic** | risk, scope creep, what breaks | "What's the failure mode? What are we NOT seeing? Cheapest way to be wrong?" |
| **User-Advocate** | founder's real intent, UX clarity, accessibility-first | "Is this what was actually asked? Is it legible and reversible for the user?" |
| **Aesthetic Maximalist** | expressive RANGE — does the artist have enough to play with? | "Is this expressive enough to be worth performing? What can the body/hand actually shape here that it can't today?" |

**Why the Aesthetic Maximalist exists** (added 2026-07-25, founder asked whether such a
voice was in the room — it was not). Every other seat pulls toward *less*: Shipper wants
the smallest change, Skeptic wants the risk gone, Architect wants no new coupling,
Vision-Keeper enforces "adding a medium = adding a subscriber, never a new surface". With
nobody arguing the other way, an instrument converges on safe and thin — and "thin" was
already a real founder complaint about the sound. This seat is the counterweight.
**Its constraint, non-negotiable:** it argues for expressive DEPTH on what exists — wiring
a dead modulation channel, widening a range, making a mapping legible — never for a new
screen, a new surface, or a new modal. It loses to Vision-Keeper on brand and to the
flash/accessibility laws every time. When it and Vision-Keeper disagree, name the
disagreement rather than averaging it.

## Procedure (fast)

1. **Frame** the decision in one sentence (the actual choice on the table).
2. **Seat the relevant voices** (often 2–4, not all six). Each gives ONE line:
   position + its sharpest concern. No padding.
3. **Surface dissent explicitly** — if seats disagree, name the disagreement; do
   not average it away. The strongest objection must be stated.
4. **Synthesize** ONE recommendation and the single cheapest next step that
   honors the loop (smallest reversible move, build stays green).
5. **Decide the gate:** proceed / proceed-with-mitigation / hold-for-founder.
   Use `AskUserQuestion` for **hold-for-founder** only — when dissent is
   material, the change is hard to reverse, or intent is genuinely ambiguous.
6. **Log** material decisions to `decisions.csv` (+ `memory/decisions.md`) so the
   Council never re-litigates the same point.

## Output (optimized form)

Default to a compact verdict, not a transcript:

```
Council — <decision in one line>
· Architect: <pos> — <concern>
· Skeptic: <pos> — <concern>
· Shipper: <pos> — <concern>
→ Recommendation: <one step>. Gate: proceed / mitigate / hold.
```

Show only the seats that have something real to say. For a clearly-pass decision,
one line is enough ("Council: unanimous proceed — <step>"). Reserve the full
table for genuinely contested or irreversible calls. Silence on trivia is correct.

## Guardrails

- The Council advises; it never overrides an explicit founder instruction or the
  hard rules in `CLAUDE.md` / `.claude/rules/` (audio-thread sanctity, protected
  triad, no esoteric terms, branch discipline, no PRs unless asked).
- Never let deliberation become procrastination: one pass, then act. If seats
  can't converge, that itself is the signal to **hold-for-founder**, not to loop.
- Do not fabricate consensus or invent a seat. Six seats, real concerns, or stay quiet.
