# Working Method — Echoel v10

**Single source of truth for how Claude (sandbox) and User (Mac) collaborate to ship the v10 TestFlight by 2026-05-17.**

This file is short on purpose. If it grows past two screens, something is wrong.

---

## Reality Check (Sandbox vs Mac)

| Capability | Sandbox (this Claude) | Mac (User / Mac Claude) |
|---|---|---|
| Edit files | ✅ | ✅ |
| `swift build` / `swift test` | ❌ no toolchain | ✅ Xcode 26.2 + Swift 6 |
| `xcodebuild` | ❌ | ✅ |
| `fastlane pilot upload` | ❌ | ✅ |
| iOS Simulator | ❌ | ✅ |
| Real device test | ❌ | ✅ |
| Git commit + push | ✅ | ✅ |
| GitHub Actions `workflow_dispatch` trigger | ❌ no `gh` CLI, no MCP tool | ✅ via `gh workflow run` or web UI |
| Read GitHub PRs / issues / commits | ✅ via `mcp__github__*` | ✅ |

**Implication:** Sandbox-Claude proposes & writes code, Mac-side runs the build. The CI workflow `testflight.yml` is the canonical build oracle — it runs on GitHub macOS runners and is the only way to reach TestFlight from this sandbox.

---

## The Loop (one cycle = one feature or fix)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   1. PICK              from PLAN_v10_TestFlight_Sprint.md (next item)   │
│         ↓                                                               │
│   2. WRITE             one feature OR one fix in ≤ 3 files              │
│         ↓                                                               │
│   3. COMMIT            conventional prefix, one logical change          │
│         ↓                                                               │
│   4. PUSH              to claude/unified-production-app-Qdm6b           │
│         ↓                                                               │
│   5. CI BUILD          User triggers testflight.yml (build_only: true)  │
│         ↓                                                               │
│   6. VERIFY            Mac CI green? → continue. Red? → fix forward.    │
│         ↓                                                               │
│   7. DEVICE TEST       once per feature, on real iPhone                 │
│         ↓                                                               │
│   8. LOG               update SESSION_LOG.md with commit + outcome      │
│         ↓                                                               │
│   9. REPEAT            back to PICK                                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Hard rules:**
- ONE feature/fix per cycle. No batching unrelated work.
- Build green is non-negotiable. Red CI = drop everything until green.
- Tests get written in the same commit as the feature, not later.
- No commit without `swift build` having run somewhere (Mac local OR CI).
- No "I think this will compile." Either it built, or it didn't ship.

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

## Triggering CI from Sandbox

Sandbox-Claude **cannot** trigger workflows. To verify a build:

1. Sandbox-Claude commits + pushes
2. User runs on Mac:
   ```bash
   gh workflow run testflight.yml \
     -f platform=ios \
     -f build_only=true \
     -f skip_compile_check=false
   ```
   …or clicks "Run workflow" in GitHub Actions UI.
3. Wait ~10 min for compile-check + build_only result.
4. User pastes failure log, OR confirms green.

For the actual TestFlight upload:
```bash
gh workflow run testflight.yml -f platform=ios -f build_only=false
```

**Slash command on Mac:** `/testflight-deploy` runs the full pre-flight + deploy.

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

Every Mac session starts with:

```bash
cd Echoelmusic
git fetch origin
git checkout claude/unified-production-app-Qdm6b
git pull
cat .ai/WORKING_METHOD.md      # this file
cat scratchpads/PLAN_v10_TestFlight_Sprint.md
tail -60 scratchpads/SESSION_LOG.md
swift build 2>&1 | tail -30    # baseline must be green
```

If `swift build` is red, that's the cycle. Nothing else happens until it's green.
