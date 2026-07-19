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

**Cross-cutting teams** (activate per the work, not the domain):

| Team | Lead agentType | Owns | Activate when |
|------|----------------|------|---------------|
| **PLAN/ARCHITECTURE** | `planning-agent` | plan-first for big/ambiguous items — the "ERST PLAN + Council" front door; breaks work into atomic slices before any build cycle | before a large, multi-file, or ambiguous item |
| **RELEASE / CI / DEPLOY** | `build-error-resolver` | the whole ship pipeline as ONE charter — (a) both gates green (Xcode Compile Check + CI/CD Pipeline); (b) the tokenless deploy: bump `.deploy/release` + push → watch `testflight.yml` to a real TestFlight build, not just "CI green" (they differ — v304 needed a separate re-trigger after a green compile); (c) entitlements/provisioning hygiene (the AUv3 appex App-Group / inter-app-audio class of failures); (d) App Store Connect secrets + the 60-min pipeline health; (e) the deploy-note discipline on every real ship. Hands OFF to DEVICE-VERIFY post-deploy and convenes the App Store Release-Compliance Owner at submission. | every push / red gate / any `.deploy/release` bump / TestFlight build / entitlement or provisioning change |
| **RED-TEAM / SKEPTIC** | `general-purpose` (N refuters) | adversarially trying to BREAK a risky slice (N refuters, majority-kill), not just review it | only irreversible / high-risk changes (deletes, audio-thread, protected triad, deploys) |
| **DEVICE-VERIFY / RELIABILITY-QA** | `general-purpose` (+ `device-log-triage`/`watch-clip`/`video-watch` skills; pairs `tdd-agent`) | the post-deploy FEEDBACK stage: intake any founder device signal (`echoel_diag.log`, `.ips`, MetricKit, screen clip) → root-cause → ROUTE to the right domain team; owns the NEEDS-FOUNDER-VERIFY backlog + the flip-vs-rollback call per blind sensory flag at freeze-lift; adds a recurrence guard (test/lint on the known failure-class file) before the fix ships | a founder pastes a crash/diag log or clip; any on-device crash/freeze/anomaly; freeze-lift backlog burndown; a fix lands in a recurring failure-class file (sheet-chain, audio-route, LaunchGuard/SafeMode) |
| **DSP-CORRECTNESS** | `dsp-reviewer` | algorithm correctness (biquads, FFT/vDSP, Rausch triad READ-ONLY) — distinct from audio-thread safety | only DSP/ or Bio/ math changes |
| **ADAPTIVE DESIGN/UX** | `general-purpose` (armed with the Uncodixfy rules) | look & feel & accessibility — Uncodixfy compliance (radii ≤16, no glassmorphism, solid fills, `EchoelValueField`), adaptive/responsive layout (Dynamic Type, `ScaledMetric`, device sizes, dark/light), a11y (VoiceOver, reduce-motion, flash ≤3 Hz WCAG), and the "wow"/contemplative quality bar. DISTINCT from UI/STUDIO (which owns state-flow/freeze/sheet correctness) — they compose on a UI slice. | any user-facing UI/visual change, new screen/panel, or a "make it feel right" ask |
| **MEMORY/RECONCILE** | `general-purpose` | keeping the task list + `memory/` + `decisions.csv` honest — catch mislabeled-done, stale claims, drift | weekly / on task-list drift |

**Standing cross-cut reviewers** every code change passes before ship:
`concurrency-reviewer`, `code-reviewer`, `security-agent`.

## Leadership & steward roles (decision-ownership, NOT worker fan-out)

Teams supply vetted analysis + throughput; ROLES own standing DECISIONS. A role
convenes, decides, and gets out of the way — it does not fan out workers or touch
`Sources/`. The build half of the loop was well-covered; these fill the STEERING and
FEEDBACK halves the coverage audit found orphaned.

| Role | Owns the decision | Relationship / when |
|------|-------------------|---------------------|
| **Head of Product** | the WHAT/WHY: keeps ONE canonical REIHENFOLGE, reconciling the ~70 `PLAN_*.md` + BACKLOG + MASTERPLAN into a single ranked roadmap; every cut/keep + monetization-scope call (EchoelStore, RTMP/Broadcast, Video deferral); ambiguous-ask → intent→spec | sits ABOVE the PM main loop (PM executes one verified slice/cycle against the order HoP sets). DISTINCT from `the-council`/`grand-council` (they advise then leave — HoP owns the standing decision), from `vision-gate` (filters INBOUND inspiration — HoP owns the OUTBOUND roadmap), and from PLAN/ARCHITECTURE (decomposes the HOW of an already-chosen task). Runs continuously while the founder is away. |
| **Head of Quality** (Definition-of-Done) | the "is it actually good" bar gates don't cover: organic/professional SOUND, contemplative "wow" VISUAL; whether a NEEDS-FOUNDER-VERIFY item is truly closeable | peer to Head of Product (HoP owns WHAT ships next; HoQ owns whether what shipped meets the bar). Delegates device root-cause to DEVICE-VERIFY; keeps the sensory judgment. On any safe-default slice, a "make it sound/feel professional" ask, or a release-readiness check. |
| **EchoelAI Safety Owner** | sign-off before ANY `EchoelAI/` slice ships: binding a model apply-closure to `Core/ParameterApplyRouter.swift` (the concrete keyPath→live-voice-setter hole), any new FoundationModels `@Generable`/Tool wrapper, any `FeatureFlags.echoelAI` flip. Enforces the ADR write-path law ("the model NEVER writes DSP state directly") + no-audio-thread + Release-bit-identical gating | lead `security-agent` (LLM guardrail/injection lens) with `audio-thread-reviewer` standing cross-cut. Any cycle touching `Sources/Echoelmusic/EchoelAI/**` or wiring a model closure to the router/EngineBus. |
| **Persistence & Schema-Migration Steward** | approval of any persisted `Codable` field rename/removal, any `*Store` add/rename, container/format change. Mandates `schemaVersion` + `decodeIfPresent` + non-destructive fallback — ends the silent `try?`-decode that vaporizes user docs on a field rename (only `SpatialScene` is versioned today) | lead `code-reviewer`. Lightweight standing role (the ~12 stores are too multi-domain to fold into DAW/TIMELINE). Any change to a persisted `Codable` type or a `*Store`. |
| **App Store Release-Compliance Owner** | the submission-time go/no-go: 2.1/2.3/5.1.3 reject-risk sign-off, privacy-nutrition-label + age-rating answers, the `fastlane/metadata` skip-metadata safety call | folded into RELEASE/CI as its release-gate seat — convenes the existing reviewers (`security-agent` privacy + `bio-safety-reviewer` health-claim + `echoel-marketing` copy), no new team. Before any App Store submission or change to `fastlane/metadata`/`PrivacyInfo.xcprivacy`/entitlements. |

### Fold-ins (deliberately NOT new teams)

- **Core/ control-plane** (EngineBus topics, SignalRouter, `ParameterApplyRouter`, store schemas, `FeatureFlags`/`ProGate`) → PLAN/ARCHITECTURE's explicit Owns, with `concurrency-reviewer` standing.
- **Runtime performance budget** (CPU<30%, mem<200MB, 120fps, audio<10ms, bio 120Hz; `benchmark.yml`) → RELEASE/CI, composing AUDIO/DSP (latency) + VIDEO/VISUAL (fps) on the relevant slice.
- **Governance/knowledge** (CLAUDE.md drift, `HARNESS_LEDGER`, `review.sh` backlog, active scratchpad PLANs, decisions.csv taxonomy) → widen MEMORY/RECONCILE's charter.
- **All user-facing brand-red-line copy** (not just bio copy) → widen BIO's copy scope + UI/STUDIO.
- **Commerce/StoreKit** (`EchoelStore`/`ProGate`, dormant) → AUv3/PLATFORM, convened only on activation.

### Continuous processing — ONE PM loop, teams plug in per-task

The safe way to "work through all open tasks in a loop" is NOT to keep every team
running continuously — that multiplies token cost, floods the PM with raw output,
and (with no local compiler + serial commits) manufactures merge conflicts. The loop
lives at the PM level; teams are activated inside each iteration:

```
LOOP (the hourly cron heartbeat / Ralph cadence):
  1. RECONCILE  — MEMORY/RECONCILE keeps the task list honest (periodically, not every tick)
  2. PICK       — the next task by REIHENFOLGE (founder priority order)
  3. PLAN       — PLAN/ARCHITECTURE if the task is big/ambiguous ("ERST PLAN")
  4. ACTIVATE   — only the 1–3 teams that task touches (domain + relevant cross-cutting)
  5. SHIP ONE   — one verified Ralph-Wiggum slice; lead-verify + cross-cut reviewers gate it
  6. GREEN      — RELEASE/CI confirms both gates; deploy note on a real ship
  7. repeat
```

This is exactly the loop already running (the 24h cron + this skill). A task is only
"done" when its slice is shipped AND green AND (for device-facing behavior) founder-
verified. The loop guarantees *safe* progress because every iteration ends in a gated,
reversible, single-slice state — never a half-built pile.

### Anti-proliferation (as important as the teams themselves)

More teams are NOT automatically safer — the same ">8 parallel degrades focus"
law applies to the roster itself. So:
- **Per task, activate only the 1–3 relevant teams**, never all 13. The domain
  teams are picked by which directory the change touches; the cross-cutting teams
  by the "Activate when" column.
- Every team stays **≤4 workers + 1 lead**; the PM synthesizes vetted LEAD reports,
  never raw worker output.
- If activating a team wouldn't change the decision, don't — coordination overhead
  is the failure mode in the other direction.

**Deliberately rejected** (coverage audit 2026-07-19 — do NOT re-add without new evidence):
a standalone Eng/Architecture lead or separate CORE team (duplicates the-council Architect
+ PLAN/ARCHITECTURE); a standalone Performance team (folds into RELEASE/CI); Head of Growth
+ a Localization team (growth folds into Head of Product; localization is a deliberate v1.0
iPhone-first single-market deferral — zero `.strings` today); standalone EchoelAI/Commerce/
Community worker teams (all decision-ownership or dormant, covered by roles/fold-ins above).

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
