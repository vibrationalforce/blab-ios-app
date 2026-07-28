# Ship — Full Automated Ship Workflow

One-command release: merge base, run tests, review diff, audit safety, commit, push, create PR. Combines GStack's comprehensive shipping with Echoelmusic's iOS-specific pre-release checks.

User says `/ship` → DO IT. Non-interactive except for blockers.

**Only stop for:**
- On base branch (abort)
- Merge conflicts that can't be auto-resolved
- Test failures
- Pre-landing review ASK items needing judgment
- iOS 26 SDK validation failure (BLOCKER)
- Audio thread safety violations (CRITICAL)

**Never stop for:**
- Uncommitted changes (always include)
- CHANGELOG content (auto-generate)
- Commit message approval (auto-commit)

---

## Step 0: Detect Base Branch

```bash
_BASE=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null || gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo "main")
echo "BASE: $_BASE"
```

---

## Step 1: Pre-Flight

### 1a: Branch Check
If on base branch: "You're on the base branch. Ship from a feature branch." → ABORT.

### 1b: iOS 26 SDK Validation (ITMS-90725)
```bash
grep -rE "deploymentTarget|IPHONEOS_DEPLOYMENT_TARGET|SDK" project.yml Project.swift 2>/dev/null | head -5
```
**BLOCKER** if not targeting iOS 26 SDK (deadline: April 28, 2026).

### 1c: Status & Scope
```bash
git status
git diff $_BASE...HEAD --stat
git log $_BASE..HEAD --oneline
```

---

## Step 2: Merge Base Branch (before tests)

```bash
git fetch origin $_BASE && git merge origin/$_BASE --no-edit
```

If merge conflicts: try auto-resolve simple ones (VERSION, CHANGELOG ordering). Complex conflicts → STOP.

---

## Step 3: Run Tests (platform-aware)

**On macOS with Xcode:**
```bash
swift build 2>&1
swift test 2>&1
```

**On Linux/web sessions — which is every session here:**
Same instrument as `/verify` and `/tdd`, so all three files read the gates the same way:
```bash
# saved from mcp__github__actions_list (the raw response overflows context)
python3 scripts/gh-run-status.py <saved-tool-result.json>   # sha status conclusion run_id WORKFLOW-NAME title
```

The old line here was `gh run list --workflow ci.yml` — one workflow out of four, and it cannot
show the two Full-Test-Suite log lines Step 7 asks you to quote.

Must pass with zero errors. **If any test fails → STOP.**

---

## Step 3.5: Pre-Landing Review

Run the full `/review` command inline (all steps from review.md). Key additions for /ship context:

### Audio Thread Safety Audit
Launch `audio-thread-reviewer` agent to scan ALL render callbacks:
- No malloc, no locks, no ObjC, no file I/O, no GCD on audio thread

### Bio-Safety Compliance
Launch `bio-safety-reviewer` agent to verify:
- All safety disclaimers present
- No unauthorized health claims
- Flash rate ≤ 3 Hz (W3C WCAG)
- Privacy compliance for health data

### Crash Path Scan
Search for:
- Force unwraps (`!` not preceded by guard/if-let)
- Unguarded divisions
- Unguarded array access
- Missing `@MainActor` on `@Observable`
- Missing `.environmentObject()` injection

### Fix-First Flow
- AUTO-FIX obvious issues directly
- ASK for judgment calls in ONE batched AskUserQuestion
- If ANY code fixes applied: commit fixed files, then re-run tests (Step 3)
- If no fixes: continue to Step 4

---

## Step 4: Performance Baseline

Verify targets are met (or document current baseline):

| Metric | Target | FAIL |
|--------|--------|------|
| Audio Latency | <10ms | >15ms |
| CPU | <30% | >50% |
| Memory | <200MB | >300MB |
| Visual FPS | 120fps | <60fps |
| Bio Loop | 120Hz | <60Hz |

On Linux/web: Note "Performance verification requires device testing" and continue.

---

## Step 5: Commit (bisectable chunks)

### 5a: Analyze and group changes into logical commits

**Commit ordering** (earlier first):
1. Infrastructure: config changes, new files
2. Core: DSP, engines, services (with their tests)
3. UI: Views, view models (with their tests)
4. Final: VERSION + CHANGELOG + docs

### 5b: Rules
- Model + test → same commit
- Service + test → same commit
- Each commit independently valid (no broken imports)
- Conventional prefixes: `feat:`, `fix:`, `test:`, `refactor:`, `docs:`, `chore:`, `perf:`

---

## Step 5.5: Verification Gate

**IRON LAW: NO PUSH WITHOUT FRESH VERIFICATION.**

If ANY code changed after Step 3's test run:
1. Re-run tests. Paste fresh output.
2. "Should work now" → RUN IT.
3. "Already tested earlier" → Code changed. Test again.

**If tests fail here → STOP. Do not push.**

---

## Step 6: Push

```bash
git push -u origin $(git branch --show-current)
```

---

## Step 7: Create PR

⛔ **Everything between the `<<'EOF'` and the closing `EOF` is PUBLISHED as the PR body.** Do not
put instructions to yourself in there — the first version of this template did, and every PR
Echoel opened would have carried a paragraph addressed to the agent. Notes for the agent go
here, above the fence; only the filled-in template goes inside.

Filling it in:
- Every box starts UNCHECKED. Tick a box only for a check you actually ran in this session.
  A pre-ticked `PASS` is a claim without a measurement — which is the exact defect this
  template exists to prevent.
- Never write `swift build: PASS`. Nothing in this environment can run it.
- For the Full Test Suite quote the LOG LINES, never the checkmark: `continue-on-error` sits on
  its build step, so the conclusion is green even when nothing compiled.

```bash
gh pr create --base $_BASE --title "<type>: <summary>" --body "$(cat <<'EOF'
## Summary
<bullet points describing what shipped>

## Echoelmusic Checks
- [ ] iOS 26 SDK validated (ITMS-90725)
- [ ] Audio thread safety audit: <result>
- [ ] Bio-safety compliance: <result>
- [ ] Crash path scan: <result>
- [ ] Performance baseline: <documented / not measured>

## Pre-Landing Review
<findings from Step 3.5, or "No issues found.">

## Test Results
- [ ] Xcode Compile Check: <conclusion> (sha: <sha7>)
- [ ] Echoelmusic CI/CD Pipeline: <conclusion> (sha: <sha7>)
- [ ] Echoel Full Test Suite (non-blocking): `build-for-testing: <outcome>` /
      `test-without-building: <outcome>`

## Test plan
<what to verify on device>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Output the PR URL.

---

## Step 8: Update Session Log

Update `scratchpads/SESSION_LOG.md` with:
- What was shipped
- PR URL
- Any concerns or follow-ups

---

## Important Rules

- **Never skip tests.** If tests fail, stop.
- **Never skip audio thread safety audit.** Audio crashes = user trust destroyed.
- **Never skip bio-safety check.** Health claim violations = legal risk.
- **Never force push.** Regular `git push` only.
- **Never skip iOS 26 SDK validation.** ITMS-90725 = App Store rejection.
- **Platform-aware:** Use GitHub API for build/test verification on Linux/web.
- **The goal:** User says `/ship`, next thing they see is the review + PR URL.

STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
