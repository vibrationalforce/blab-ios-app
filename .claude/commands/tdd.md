# /tdd — Test-Driven Development Cycle

Run a TDD cycle for the specified feature or fix.

## Usage
`/tdd [feature description]`

## Protocol

### Step 1: Understand
- Read the feature/fix description
- Identify the module and files involved
- Check existing tests for the module

### Step 2: RED — Write Failing Test
```bash
# Create or modify test file
# Test naming: test[Unit]_[Scenario]_[ExpectedBehavior]
```

For DSP/Audio tests:
- Use `XCTAssertEqual(_:_:accuracy:)` for floating-point
- Pre-allocate buffers (simulate audio thread constraints)
- Test with known input signals (sine waves, impulses)

For AUv3 tests:
- Test parameter tree addresses
- Test factory preset loading
- Test state save/restore round-trip
- Test render block with mock input

### Step 3: Verify RED — and be honest about what that costs here

There is no local Swift toolchain. RED and GREEN are observable only through CI, and one round
is ~7 minutes. Two consequences, neither of them optional:

- **Do not skip RED.** A test that never failed proves nothing, and this repo has written one:
  a first version of `assertUsable` used `energy > 0` and PASSED on a kernel measuring 2.97e-08
  — it would have certified the very bug it was written for. Review caught it before it shipped
  (`ConvolutionKernelBoundsTests.swift:43`, #182). If you cannot run the test, DERIVE the
  failing value and write the number into its comment, so the next reader can check the
  arithmetic instead of taking your word.
- **Batch the round.** Push the failing test and the implementation as separate commits only if
  you are willing to spend two CI rounds; otherwise state plainly in the commit body that RED
  was established by derivation rather than by a run.

```bash
python3 scripts/gh-run-status.py <saved-tool-result.json>
```

⛔ The blocking gates do NOT run `Tests/EchoelmusicTests` — the blocking bundle builds from
`Tests/CISmoke` (#208). Your new test executes only in `Echoel Full Test Suite (non-blocking)`, whose green
checkmark is meaningless because `continue-on-error` sits on its build step. Read its log:
`- build-for-testing:` and `- test-without-building:` must both say success. Until they do,
"the gates are green" says nothing about your test.

### Step 4: GREEN — Minimal Implementation
- Write ONLY enough code to pass the test
- No optimization, no extra features, no cleanup
- Follow CLAUDE.md constraints (no force unwraps, os_log only, etc.)

### Step 5: Verify GREEN
Same instrument as Step 3 — the Full Test Suite log, not the checkmark. Must PASS. If it fails,
fix the implementation, not the test.

### Step 6: REFACTOR
- Clean up while tests are green
- Extract only if 3+ repetitions
- The full suite runs on a push to `claude/**` **only when the push touches `Sources/`,
  `Tests/`, `Package.swift` or `project.yml`** — a refactor confined to docs or scripts
  produces no run at all, and no run is not a pass. Check its log for regressions.

### Step 7: Commit
```bash
git add [files]
git commit -m "test: add [description]"
git commit -m "feat: implement [description]"
```

## Rules
- ONE test at a time
- If test infrastructure doesn't exist, create it first
- Audio DSP values: always test with accuracy tolerance
- Bio values: test boundary conditions (coherence 0, 1, NaN)
- Never mock what you can test directly
