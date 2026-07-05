---
name: grand-council
version: 1.0.0
description: |
  Convene a panel of great minds + mental models to pressure-test a BIG,
  hard-to-reverse founder decision before committing — a pivot, a rewrite, a
  pricing/positioning change, a "should Echoel do X?" fork, or any strategic
  bet where being wrong is expensive. Each relevant thinker speaks in ONE line
  through their signature lens, three mental-model checks run (inversion,
  premortem, blind-spot), dissent is surfaced not smoothed, then a single
  recommendation + the cheapest reversible first step is synthesized. This is
  the SLOW council for founder-level strategy; `the-council` stays the FAST gate
  for build decisions. PIPELINE only — never ships in-app, never touches Sources/.
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# Grand Council — think it through with the great minds

**Principle: before an expensive, hard-to-reverse decision, borrow the best
thinking humans ever produced.** The Grand Council is one fast internal
deliberation that runs a founder-level decision past a panel of great minds and
a short mental-model checklist, then converges on ONE recommendation and the
cheapest reversible first step. It is the *strategy* companion to `the-council`
(the build-decision gate) and composes with `vision-gate` (the vision filter).

It advises. It never overrides an explicit founder instruction or the hard rules
in `CLAUDE.md`. Its job is to make the founder's decision *better-informed*, then
get out of the way.

## When to convene (and when NOT to)

**Convene** for decisions that are strategic AND hard to reverse:
- a pivot, rewrite, or "start from scratch" (kill vs. keep working assets)
- pricing / business model / positioning changes
- "should Echoel do X?" where X reshapes the product or the roadmap
- betting scarce solo-founder time on one direction over others
- anything that, if wrong, costs months or the brand

**Skip** (do NOT convene): reversible build choices (that's `the-council`),
typo/UX tweaks, anything already decided and logged in `decisions.csv`, or a
direct factual question. Convening a 18-mind panel on trivia is the failure mode.

## The panel (select the 4–7 most relevant; never run all eighteen)

Each mind is a *lens*, not a quote generator. Pick the ones whose lens actually
cuts the decision on the table. Full roster + how to apply each: `references/roster.md`.

**Decide & judge (business, capital, risk)**
- **Charlie Munger** — *inversion + latticework*: "What guarantees failure here? Solve for that."
- **Warren Buffett** — *circle of competence + moat*: "Is this inside what we truly know, and does it compound a durable edge?"
- **Clay Christensen** — *jobs-to-be-done*: "What job does the user hire this to do? Are we building the job or the feature?"
- **Nassim Taleb** — *antifragility + via negativa*: "What's the downside tail? What should we REMOVE, not add?"
- **Daniel Kahneman** — *bias + base rates*: "What's the outside view? Which cognitive bias is flattering us right now?"

**Build & invent (craft, science, first principles)**
- **Richard Feynman** — *first principles + "don't fool yourself"*: "Strip it to physics. What are we pretending to understand?"
- **Steve Jobs** — *taste + subtraction*: "What do we say no to? Is this insanely great or merely good?"
- **Jony Ive** — *design & care*: "Does the whole thing feel inevitable, resolved, cared-for?"
- **Leonardo da Vinci** — *cross-domain analogy*: "What does nature / another field already solve this way?"
- **Charles Darwin** — *disconfirfirmation*: "Actively hunt the evidence that we're WRONG; record it first."

**Live & endure (wisdom, meaning, the long game)**
- **Marcus Aurelius / the Stoics** — *dichotomy of control*: "What here is actually in our control? Spend only there."
- **Socrates** — *elenchus*: "Question the premise. Is the thing we're arguing even the real question?"
- **Seneca** — *premeditatio + time*: "Is this the best use of the one scarce resource, time?"
- **Naval Ravikant** — *leverage + specific knowledge*: "Does this use the founder's unique, unfakeable edge — or anyone's?"
- **Lao Tzu** — *wu wei / subtraction*: "Is the strongest move to do less, and let the working parts work?"

(Reserve slots — swap in a domain expert the decision demands: a scientist for a
bio-signal claim, a lawyer for a compliance fork, etc.)

## The three mental-model checks (ALWAYS run, they are cheap and catch the worst errors)

1. **Inversion (Munger):** Don't ask "how do we succeed?" Ask "what would
   guarantee this fails?" — then make sure we're not doing those things.
2. **Premortem (Klein/Kahneman):** Fast-forward 6 months; the decision failed
   badly. Write the most likely obituary. That paragraph is the risk to mitigate now.
3. **Blind-spot / second-order (the reel's "blinder Fleck"):** What are we NOT
   seeing? What does this cause *after* the first effect — the effect of the effect?

## Procedure (one pass, then act)

1. **Frame** the decision in one sentence — the actual fork, with the options.
2. **Ground it** in repo reality first: `memory/`, `docs/dev/FEATURE_MATRIX.md`,
   `CLAUDE.md` "CURRENT STATE" / "Absent", `decisions.csv`. No invented facts.
3. **Seat 4–7 relevant minds.** Each gives ONE line: position + sharpest concern,
   spoken through their lens. No padding, no fortune-cookie quotes.
4. **Run the three mental-model checks** (inversion · premortem · blind-spot).
5. **Surface dissent explicitly.** If the minds split, NAME the split — don't
   average it into mush. The strongest objection must be stated out loud.
6. **Synthesize** ONE recommendation + the single cheapest *reversible* first
   step that tests the bet without betting everything.
7. **Gate:** proceed / proceed-with-mitigation / **hold-for-founder**. Use
   `AskUserQuestion` for hold-for-founder only — when the call is genuinely the
   founder's (irreversible + values-laden) and the evidence doesn't force it.
8. **Log** the decision + rationale to `decisions.csv` and `memory/decisions.md`
   so the Grand Council never re-litigates a settled question.

## Output (compact verdict, not a transcript)

```
Grand Council — <decision in one line>
Panel:
· Munger (inversion): <one line> — <sharpest concern>
· Christensen (JTBD): <one line> — <concern>
· Taleb (via negativa): <one line> — <concern>
· Feynman (first principles): <one line> — <concern>
Checks:
· Inversion → <what would guarantee failure>
· Premortem → <the 6-month obituary in one sentence>
· Blind spot → <what we're not seeing / second-order effect>
Dissent: <the real disagreement, named>
→ Recommendation: <one step>. Cheapest reversible test: <the move>.
  Gate: proceed / mitigate / hold-for-founder.
```

Show only the minds with something real to say. For a clearly-pass decision, a
few lines is enough. Reserve the full panel for genuinely contested,
irreversible calls.

## Guardrails

- **Advises, never overrides** an explicit founder instruction or `CLAUDE.md` /
  `.claude/rules/` hard rules. The founder decides; the Council informs.
- **Never procrastinate.** One pass, then act or hold. If the panel can't
  converge, that itself is the "hold-for-founder" signal — don't loop.
- **No hero worship, no invented quotes.** Use each mind's *method*, applied to
  the real facts of the decision. A lens that doesn't cut this decision stays silent.
- **Composes, doesn't duplicate.** Build-level / reversible → `the-council`.
  External-inspiration adoption → `vision-gate`. Marketing publication →
  `echoel-marketing` + `the-council`. Grand Council is for the big founder forks.
- **PIPELINE only.** It is a thinking tool. It never ships in-app and never
  touches `Sources/`.
