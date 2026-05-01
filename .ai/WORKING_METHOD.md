# Working Method — Echoel v10

**Single source of truth for how Claude (sandbox) and User (Mac) collaborate to ship the v10 TestFlight by 2026-05-17.**

This file is short on purpose. If it grows past two screens, something is wrong.

---

## Reality Check (iPhone + GitHub only — no Mac in the loop)

| Capability | Sandbox-Claude (this) | iPhone-User (you) | GitHub Actions (macOS runner) |
|---|---|---|---|
| Edit files | ✅ | ✅ via Working Copy / GitHub web | ✅ |
| `swift build` / `swift test` | ❌ no toolchain | ❌ iPhone has no Swift CLI | ✅ in CI |
| `xcodebuild archive` | ❌ | ❌ | ✅ in CI (`testflight.yml`) |
| `fastlane pilot upload` | ❌ | ❌ | ✅ in CI (`testflight.yml`) |
| Trigger workflow_dispatch | ❌ no `gh`, no MCP tool | ✅ via GitHub web UI on iPhone | n/a |
| Read GitHub PRs / issues / commits | ✅ via `mcp__github__*` | ✅ via web | ✅ |
| Real device test | ❌ | ✅ TestFlight on iPhone | ❌ |

**Implication:** The build oracle is **`testflight.yml` on GitHub Actions**. There is no local-build escape hatch. Every code change reaches truth via one path: push → trigger workflow on iPhone → CI verifies on macOS runner → TestFlight (or build error log).

This is stricter than a normal dev loop. It rewards small, focused commits and punishes speculative refactors.

---

## The Loop (one cycle = one feature or fix)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   1. PICK              from PLAN_v10_TestFlight_Sprint.md (next item)   │
│         ↓                                                               │
│   2. WRITE             one feature OR one fix in ≤ 3 files (sandbox)    │
│         ↓                                                               │
│   3. COMMIT            conventional prefix, one logical change          │
│         ↓                                                               │
│   4. PUSH              to claude/unified-production-app-Qdm6b           │
│         ↓                                                               │
│   5. TRIGGER CI        iPhone → github.com/.../actions →                │
│                          testflight.yml → "Run workflow":               │
│                            platform: ios                                │
│                            build_only: true       (verify-only first)   │
│                            skip_compile_check: false                    │
│         ↓                                                               │
│   6. WAIT ~10 MIN      CI runs preflight + simulator compile + archive  │
│         ↓                                                               │
│   7. READ RESULT       iPhone GitHub Actions tab shows green/red        │
│         ↓                                                               │
│   8. DEVICE TEST       once feature stable: re-trigger with             │
│                          build_only: false → Fastlane pilot uploads     │
│                          → TestFlight push notification on iPhone       │
│         ↓                                                               │
│   9. LOG               update SESSION_LOG.md with commit + outcome      │
│         ↓                                                               │
│  10. REPEAT            back to PICK                                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Hard rules:**
- ONE feature/fix per cycle. No batching unrelated work.
- Every push runs CI with `build_only: true` BEFORE TestFlight upload.
- Tests get written in the same commit as the feature, not later.
- No commit without sandbox-Claude having checked the code against the existing patterns in the repo (idioms, imports, access levels, concurrency annotations).
- Red CI = drop everything until green. No new feature work on a red branch.

---

## Source-of-Truth Map

| Concern | File | Owner |
|---|---|---|
| Project doctrine | `CLAUDE.md` | Authoritative — read FIRST every session |
| Active sprint plan | `scratchpads/PLAN_v10_TestFlight_Sprint.md` | Day-by-day tasks, exit criteria |
| Working method | `.ai/WORKING_METHOD.md` (this file) | How Sandbox + Mac collaborate |
| Decisions made | `memory/decisions.md` + `decisions.csv` | Architectural decisions with review dates |
| Session history | `scratchpads/SESSION_LOG.md` | What happened when, in chronological order |
| Audio thread rules | `.claude/rules/swift-audio.md` | Hard constraints for DSP/render code |
| User profile | `memory/user.md`, `people.md`, `preferences.md` | Who, what, how |
| Public README | `README.md` | What the app is, for outside readers |

**Anything not in this map is either obsolete or should be merged into one of these files.**

---

## Triggering CI from iPhone (no Mac, no gh CLI)

Sandbox-Claude cannot trigger workflows. The user does it from iPhone:

**Step 1 — Open the workflow:**
Safari → `https://github.com/vibrationalforce/Echoelmusic/actions/workflows/testflight.yml`

**Step 2 — Tap "Run workflow":**
Top-right "Run workflow" button → set inputs:

| Input | Verify-only | TestFlight upload |
|---|---|---|
| `platform` | `ios` | `ios` |
| `clean_build` | `false` | `false` (or `true` if cache poisoned) |
| `skip_tests` | `true` | `false` |
| `build_only` | **`true`** | **`false`** |
| `skip_compile_check` | `false` | `true` |

**Step 3 — Watch:**
Same Actions tab, refresh, or open the run page. ~10 min for `build_only`. ~30–45 min for full TestFlight upload.

**Step 4 — Read the result:**
Green: continue. Red: tap the failed job, expand the failed step, copy the last 30–60 lines of log, paste back to me here.

**Tip:** After every push, **always run `build_only: true` first**. Only after green, re-run with `build_only: false` to push the build to TestFlight.

---

## Commit Conventions

```
<type>(<scope>): <imperative summary, ≤ 70 chars>

<optional body — what & why, never what>

https://claude.ai/code/session_<id>
```

**Allowed types:** `feat` · `fix` · `refactor` · `test` · `docs` · `chore` · `perf`
**Allowed scopes:** `audio` · `sequencer` · `video` · `stream` · `studio` · `core` · `ci` · `docs`

One change per commit. If you're tempted to add a second concern, that's a second commit.

---

## What to Do When Stuck

| Symptom | Action |
|---|---|
| Build red, root cause unclear | STOP feature work. Open a `fix(build):` cycle. |
| Test red after green build | STOP feature work. Open a `fix(test):` cycle. |
| Plan ambiguous on next step | Ask user via `AskUserQuestion`, do not guess. |
| Tempted to "while I'm here, also fix X" | NO. Write X to a backlog note, ship current commit, then start X. |
| Spec contradicts existing code | The spec wins. Change code. Log decision in `memory/decisions.md`. |

---

## What to Never Do

- Touch `BioEventGraph`, `HilbertSensorMapper`, `BioSignalDeconvolver` (PROTECTED)
- Modify `Info.plist`, `*.entitlements`, `.github/workflows/*.yml`, `Package.swift` without naming it explicitly in the commit message
- Use `--no-verify`, `--no-gpg-sign`, `--amend` on a published commit
- Force-push to any branch
- Push directly to `main`
- Add a dependency without logging the decision in `memory/decisions.md`
- Create a new top-level directory under `Sources/Echoelmusic/` that isn't `Sequencer/`, `Stream/`, or `Studio/`
- Re-introduce bio-reactive auto-play in the main flow

---

## Definition of "Wie Gewaschen" (for TestFlight)

A TestFlight build that has been polished if and only if:

1. App launches in < 3 s on iPhone 14+
2. All four tabs (Beat / Record / Video / Share) are interactive — no placeholders
3. Beat tab plays a 16-step pattern at 120 BPM with no audible glitches
4. Record tab captures mic over the beat, sample-accurate sync (no drift > 1 frame)
5. Video tab records 30 s of 1080p30 + audio, file plays back externally
6. Share tab streams to a YouTube test stream for 60 s without dropout
7. Export produces a playable MP4 (video) and a WAV (audio mixdown)
8. No crashes during a 5-minute end-to-end session
9. `ProcessInfo.thermalState` ≤ `.serious` after 15 min of streaming
10. App icon present, launch screen present, Info.plist permissions strings written in correct German + English

Anything less is not "gewaschen" — it's a draft.

---

## Read This First (Session-Start Checklist)

Every sandbox-Claude session starts by reading these files in order:

```
1. CLAUDE.md                                  ← project doctrine
2. .ai/WORKING_METHOD.md                      ← this file (the loop)
3. scratchpads/PLAN_v10_TestFlight_Sprint.md  ← what to build next
4. tail -60 scratchpads/SESSION_LOG.md        ← what just happened
5. memory/decisions.md                        ← active architectural decisions
6. git log --oneline -10                      ← last 10 commits
```

The session-start state question that must be answered before any code change:
**"Is the latest CI run on `claude/unified-production-app-Qdm6b` green?"**
- If green: pick the next item from PLAN_v10 and write it.
- If red: that's the cycle. Read the failure, fix it, re-trigger CI.
- If unknown: ask the user to trigger `build_only: true` and report the result.
