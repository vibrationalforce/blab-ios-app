# Routine #4 — CI Failure Watchdog

**Triggers:** `workflow_run.completed` where conclusion = `failure` on `vibrationalforce/Echoelmusic`
**Runs on:** Anthropic cloud (Linux, no iOS SDK)
**Status:** Active

When pasting into claude.ai: prepend `_golden-goal.md` verbatim, then this file.

---

## Your job

When CI fails, diagnose the failure, identify the root cause, and post a fix if it's clear.
If the root cause requires device testing, escalate to Michael.

### Step-by-step

1. **Get the failed run:**
   ```bash
   gh run view <run_id> --repo vibrationalforce/Echoelmusic --log-failed
   ```

2. **Get the commit that triggered it:**
   ```bash
   gh run view <run_id> --repo vibrationalforce/Echoelmusic --json headSha,headBranch,displayTitle
   ```

3. **Classify the failure:**

   | Pattern in log | Root Cause | Urgency |
   |----------------|------------|---------|
   | `error: cannot find type '...'` | Missing import or type renamed | 🔴 High |
   | `error: value of type '...' has no member '...'` | API changed or mistyped | 🔴 High |
   | `error: use of unresolved identifier 'log'` | Logger called as function | 🔴 High |
   | `Color.magenta` | Nonexistent SwiftUI color | 🔴 High |
   | `@MainActor` isolation violation | Concurrent access pattern wrong | 🔴 High |
   | `warning: ... treated as error` | Lint violation, `-warnings-as-errors` flag | 🟡 Medium |
   | `No such file or directory` | File renamed/moved, reference not updated | 🔴 High |
   | `ITMS-90725` | iOS 26 SDK not used | 🔴 HIGH — deadline April 28, 2026 |
   | Test failure: `XCTAssertEqual` | Logic regression | 🟡 Medium |
   | `xcodebuild: error: SDK "iphoneos" not found` | Xcode version on runner wrong | 🟡 Medium — check workflow yml |

4. **Common CI-specific fixes:**

   **Logger called as function:**
   ```swift
   // WRONG — causes "value of function type has no member" error
   log(.info, ...)
   // RIGHT
   log.log(.info, category: .audio, "message")
   ```

   **Color.magenta doesn't exist:**
   ```swift
   // WRONG
   .foregroundStyle(.magenta)
   // RIGHT
   .foregroundStyle(Color(red: 1, green: 0, blue: 1))
   ```

   **ITMS-90725 / iOS 26 SDK:**
   - Check `testflight.yml`: `xcode-version: '26.2'`
   - Check `Package.swift`: `platforms: [.iOS(.v17)]` (min, not build SDK)
   - Check Xcode CLI path in workflow: `xcodebuild -version`

   **`@MainActor` isolation:**
   ```swift
   // WRONG — Task captures non-Sendable self
   DispatchQueue.main.async { self.update() }
   // RIGHT
   Task { @MainActor [weak self] in self?.update() }
   ```

5. **If fix is clear (< 5 lines, < 3 files):**
   - Open a fix PR targeting the failing branch
   - Use title: `fix: ci: <description>`
   - Comment on the failed run via issue or PR

6. **If fix is ambiguous or large:**
   - Comment on the PR that triggered the run:
   ```bash
   gh pr comment <n> --repo vibrationalforce/Echoelmusic \
     --body "CI failed. Root cause: <diagnosis>. Needs investigation — see log line <X>."
   ```

7. **NEVER:**
   - Skip `--no-verify` to bypass hooks
   - Add `// swiftlint:disable` rules without understanding why lint fires
   - Patch a test to pass instead of fixing the underlying code
   - Lower the deployment target to fix an API availability error (add `@available` instead)

### Fix PR template

```markdown
## CI Fix — <workflow> run <id>

**Failure:** `<exact error line from log>`
**Root cause:** `<file:line>` — <why it fails>

**Fix:** <what changed>

**Verified:** Build would pass (static analysis only — runner cannot be simulated locally)

Triggered by: <SHA short> on <branch>
```
