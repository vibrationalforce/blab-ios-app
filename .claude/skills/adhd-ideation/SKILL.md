---
name: adhd-ideation
version: 1.0.0
description: |
  Multi-frame Tree-of-Thought ideation skill. Generates non-obvious, high-novelty
  architectural, testing, or UX approaches by isolating context windows and evaluating
  against a skeptical critic. Use when a problem has multiple valid senior-level
  approaches AND a standard/obvious answer would be costly to get wrong. Skip when the
  user asked for a quick/standard/simple solution, or the choice is trivial/reversible.
---

# ADHD / Tree-of-Thought Ideation Skill

## Pre-Check (Token Efficiency)
Before triggering full multi-frame exploration (unless explicitly invoked via
`/adhd-ideation` or a direct user prompt), evaluate the prompt against these 3
conditions:
1. **Open-Endedness:** Does this problem have multiple valid senior-level
   architectural/strategic approaches?
2. **High Stakes:** Would selecting a standard/obvious answer result in costly
   refactoring, hidden edge-case bugs, or product churn?
3. **User Intent:** Did the user explicitly request a "quick", "standard", or
   "simple" solution? (If yes, abort and answer directly.)

If conditions 1 and 2 are MET and condition 3 is NO, proceed with the execution loop.

---

## Execution Loop

### Phase 1: Filter Out Obvious Answers
- Explicitly reject the first **3 default responses** (the most common patterns in
  LLM training data and standard senior-agent defaults).
- Force ideation into uncharted, non-obvious territory.

### Phase 2: Isolated Frame Exploration (Tree of Thought)
Spin up isolated sub-context threads using at least 3 distinct analytical frames:
- **Frame A (Boundary / Edge Case):** Failure modes, race conditions, edge cases,
  unexpected user behaviors.
- **Frame B (Inverted / Minimalist):** Strip non-essential assumptions. Solve the
  core problem with zero-overhead or unconventional paradigms.
- **Frame C (Performance & Scale):** Bottleneck elimination, stress resilience,
  long-term maintainability.

*Rule:* Maintain strict context isolation between branches so ideas do not bleed
into or compromise each other. In this harness, isolation = **one `agent()` /
sub-agent per frame** (the `Workflow`/Task primitive), each blind to the others.

### Phase 3: Skeptical Senior Engineer Evaluation
Act as a skeptical, highly critical Senior Engineer. Score every generated branch on
three metrics (1–10 scale):
- **Novelty (N):** Uniqueness and non-obviousness of the approach.
- **Viability (V):** Feasibility of real-world implementation.
- **Fit (F):** Direct alignment with project goals and technical constraints.

---

## Output Format

### Shortlisted Directions
1. **[Direction Name]** — Score: `N: X | V: Y | F: Z`
   - **Concept:** Brief overview of the strategy.
   - **Implementation Sketch:** Core architectural/algorithmic outline.
   - **First Steps:** Concrete initial implementation actions.

### Trap List & Edge Cases
- **Identified Traps:** Potential pitfalls or subtle failure points per shortlisted
  direction.
- **Mitigation:** Recommended safeguards prior to implementation.

---

## Echoel composition & guardrails

- This is a **divergence** tool — it widens the option space. It composes with, and
  hands off to, the convergence tools: `the-council` (deliberate on the shortlist),
  `vision-gate` (filter any externally-inspired direction against the brand), and the
  Ralph-Wiggum loop (ship ONE slice). Ideate wide here → converge there → ship one.
- **It never overrides the hard rules** in `CLAUDE.md` / `.claude/rules/`: audio-thread
  sanctity, the protected Rausch triad (BioEventGraph · HilbertSensorMapper ·
  BioSignalDeconvolver stay READ-ONLY — a "novel" idea that simplifies them is
  auto-rejected), no esoteric/wellness terms, branch discipline, no PRs unless asked.
- **Novelty is scored, not shipped.** A high-N/low-V/low-F direction is a note in the
  trap list, not a build cycle. Only a shortlisted direction that also clears Viability
  and Fit — and passes the reviewers — enters the loop.
- Pipeline-only: this skill shapes *thinking*. It never edits `Sources/`; the PM main
  loop makes the vetted edit after convergence.
