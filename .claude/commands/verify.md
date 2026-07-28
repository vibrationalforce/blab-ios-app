# /verify — Verification Loop

Run a comprehensive verification loop before any push or deploy.

## Usage
`/verify` or `/verify [specific-area]`

## Protocol

### 1. Build + Test Check — CI IS THE ONLY COMPILER AND THE ONLY TEST RUNNER

There is no local Swift toolchain in this environment. The previous version of this step said
`swift build` **MUST PASS** and gave the Linux case a comment instead of an instruction, and
`swift test` **MUST PASS** with no fallback at all — so the first two steps of the repo's own
verification loop could not be executed here and were skipped. That is the same class of defect
as a masked CI gate: a check that reports nothing and is read as approval.

Push the branch, then read the gates. The two that can turn a commit RED are `Xcode Compile
Check` and `Echoelmusic CI/CD Pipeline`. (They do not gate the merge: `auto-merge-claude.yml`
pushes `claude/**` to `main` with no `needs:` and no status-check wait. Red is a signal to you,
not a lock.) `⚡ Quick Test` runs neither a build nor a test — it is a hardcoded-secret grep.

```bash
# saved from mcp__github__actions_list (the raw response overflows context)
python3 scripts/gh-run-status.py <saved-tool-result.json>   # sha status conclusion run_id WORKFLOW-NAME title
```

⛔ **The gates are path-filtered** (`Sources/**`, `Tests/**`, `Package.swift`, `project.yml`,
and each workflow's own file). A commit that touches none of those produces **NO RUN** — and
`gh-run-status.py` will then print the previous commit's runs, all green. **Match the printed
`sha7` against `HEAD` before reading any conclusion. An absent run is not a pass.**

⛔ **A green conclusion is not proof a test ran.** `Echoel Full Test Suite (non-blocking)` carries
`continue-on-error` on its BUILD step, so it reports success even when nothing compiled. If this
verification concerns a test, read the job log lines, not the checkmark:

```
- build-for-testing:      <-- must say success
- test-without-building:  <-- must say success
```

Run `python3 scripts/doctor.py --section A` if you want that reasoning checked for you.

### 2. Audio Thread Safety (parallel agent)
Launch `audio-thread-reviewer` agent on all DSP/Audio files:
- `Sources/Echoelmusic/DSP/**/*.swift`
- `Sources/Echoelmusic/Audio/**/*.swift`
- `Sources/Echoelmusic/Tools/**/*.swift`   (PolySynthVoice, SubBassVoice — real render paths)

(The old list named two paths that no longer exist. `Sources/EchoelmusicAUv3/**` was deleted
with the AUv3 removal, #121 Slice 1 (`5ef8856`). `Sources/EchoelVoice/**` does not exist either,
but NOT for that reason — it has no source history in this checkout at all; it was a
Tuist-declared target that went with Tuist, separately and earlier, see
`docs/dev/APP_STORE_CONNECT.md`. Either way an agent scanning them reported "clean" for nothing.
Note this is a SHALLOW clone, so "was never here" can only ever mean "not in the history this
checkout has".)

### 3. Platform Guard Check
Every `.swift` file with UIKit/AppKit usage must have:
```swift
#if canImport(UIKit)
// ... iOS code
#endif
```
Scan: `grep -r "import UIKit" Sources/ --include="*.swift" -l`
Verify each has `#if canImport`

### 4. Code Quality Scan
- Force unwraps: `grep -rn ')\!' Sources/ --include="*.swift"` (exclude `!=`)
- print() usage: `grep -rn 'print(' Sources/ --include="*.swift"`
- TODO/FIXME: `grep -rn 'TODO\|FIXME' Sources/ --include="*.swift"`

### 5. Bio Safety Check
Launch `bio-safety-reviewer` agent:
- All mandatory warnings present
- No health claims without citations
- HealthKit data stays on device
- Flash rate ≤ 3 Hz

### 6. Report

Report the instrument reading, not a verdict you wish were true. `[X/Y passed]` is not
available here — nothing in this environment counts tests, and a template that asks for a
number invites an invented one.

```
## Verification Report
Date:   [timestamp]
Branch: [branch]
HEAD:   [sha7]   ← every gate line below must be a run on THIS sha, or say "no run"

Xcode Compile Check:       ✅/❌/no run
Echoelmusic CI/CD Pipeline:✅/❌/no run
Full Test Suite (log):     build-for-testing: … / test-without-building: …
Audio Safety:   ✅/❌   (agent, this session)
Platform Guards:✅/❌
Code Quality:   ✅/❌
Bio Safety:     ✅/❌   (agent, this session)

VERDICT: READY / NOT-READY
```

## Escalation
If 3+ verification loops fail on the same issue:
1. Log the pattern to `/learn`
2. Update CLAUDE.md error patterns
3. Consider architectural change
