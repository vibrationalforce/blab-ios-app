# Ultracode Teams — small teams with leads, not a flat agent pool

**Principle: parallelize the THINKING, serialize the SHIP.** When the founder says
"ultracode", do NOT fan out one undifferentiated pool of 15–20 agents. Beyond ~8
parallel workers, quality degrades and junk slips through unnoticed (proven on
2026-07-19: a 21-agent flat audit had agent #20 return literal garbage —
`evidence:"test", files:["a.swift"]` — that a flat synthesis would have swallowed).
Instead run **small domain teams (≤4 workers each) each with a LEAD** who reconciles
and *adversarially verifies* its team's output before anything reaches the main loop.
The main loop (the PM) then synthesizes 6–8 vetted lead-reports, not 20 raw ones.

## The teams (lead = an existing reviewer agent where one fits)

| Team | Lead agentType | Owns | Max workers |
|------|----------------|------|-------------|
| **AUDIO/DSP** | `audio-thread-reviewer` | AudioEngine, `DSP/`, `Tools/` voices, render blocks | 3 |
| **BIO** | `bio-safety-reviewer` | `Bio/`, rPPG, HealthKit/BLE, ModulationEngine, EEG | 3 |
| **DAW/TIMELINE** | `general-purpose` (timeline lead) | `Sequencer/`, TimelineStore, clips, automation, MIDI | 3 |
| **UI/STUDIO** | `ui-state-reviewer` | `Studio/`, `Views/`, freeze-law, sheet-chain, EchoelValueField | 3 |
| **VIDEO/VISUAL** | `general-purpose` (visual lead) | `Video/`, Metal, shaders, FloatingVisual | 2 |
| **SYNC/LIGHT/CAST** | `general-purpose` (sync lead) | `Sync/` (OSC/ADM/Art-Net/sACN), `Stream/` | 2 |
| **AUv3/PLATFORM** | `e2e-test-agent` | AUv3 target, entitlements, CI/deploy | 2 |
| **MARKETING** (pipeline-only) | `echoel-marketing` | `docs/`, ASO, website — **never** `Sources/` | 2 |

**Standing cross-cut reviewers** every code change passes before ship:
`concurrency-reviewer`, `code-reviewer`, `security-agent`.

## The lead's job (the quality gate)

1. **Frame** its team's slice of the task in one sentence.
2. **Fan out** 2–4 focused workers (each a narrow, checkable question).
3. **Adversarially verify + reconcile** — catch the hallucinated API, the junk
   result, the "already built" false-positive, the stale-timestamp test trap. A
   lead that just concatenates workers is not a lead.
4. **Return ONE vetted result** to the PM.

## Rules

- **Max 4 per team, one lead. Never >8 in one undifferentiated pool.**
- **The PM ships, not the teams.** Teams audit/plan/review in parallel; the main
  loop makes the edits. There is **no local Swift compiler** — edits stay serial
  and each is gated by CI (`Echoelmusic CI/CD Pipeline` + `Xcode Compile Check`).
- **One Ralph-Wiggum change ships at a time.** Team parallelism buys breadth of
  *analysis*, not batched commits.
- **Harness limit (be honest):** the `Workflow` primitive nests only ONE level — a
  worker cannot spawn its own sub-team, and `workflow()` inside a child throws. So a
  "team" = one phase-group = {2–4 worker `agent()` calls} + {1 lead `agent()` call
  that synthesizes them}, all tagged with the same `phase:`. True 3-level hierarchy
  is emulated at the script level, not native.
- **Every finding is verified against real source** (cite `file:line`), because an
  agent claiming "already built" or a plausible-but-wrong API cannot be caught by a
  compiler here — only by the lead's adversarial read.

## Workflow shape (canonical)

```js
// Per team: workers fan out, the lead verifies, one vetted result comes back.
const teamResult = await (async () => {
  const workers = await parallel(TEAM.questions.map(q => () =>
    agent(q.prompt, { phase: TEAM.name, schema: WORKER_SCHEMA })))
  return agent(
    `You are the ${TEAM.name} LEAD. Reconcile + ADVERSARIALLY verify these worker
     findings against the real source (cite file:line). Reject any that don't hold.
     ${JSON.stringify(workers.filter(Boolean))}`,
    { phase: TEAM.name, agentType: TEAM.lead, schema: LEAD_SCHEMA, effort: 'high' })
})()
// PM (main loop) then synthesizes the 6–8 lead results and ships ONE slice.
```

## When to use / skip

- **Use** for an "ultracode" sweep, a broad audit, "close all gaps", a cross-cutting
  design, or any task touching >1 domain.
- **Skip** (Council anti-trivia rule) for a single small reversible slice — a
  one-line control-plane change does not need a 5-agent team; one verify agent is
  enough. Over-orchestrating trivia is the failure mode, same as under-structuring
  a big sweep.

Composes with `the-council` (deliberate before the move) and the Ralph-Wiggum loop
(ship one thing, green gates). Never overrides founder instructions or the hard
rules in `CLAUDE.md` / `.claude/rules/`.
