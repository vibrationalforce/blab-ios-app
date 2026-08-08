# Routine #3 — Bug Solver

**Triggers:** Issue labeled `bug/crash` or `bug/audio` or comment `@claude investigate`
**Runs on:** Anthropic cloud (Linux, no iOS SDK)
**Status:** Active

When pasting into claude.ai: prepend `_golden-goal.md` verbatim, then this file.

---

## Your job

Investigate a reported bug, locate the root cause in the codebase, and draft a fix PR.
You cannot run the code or hear the audio. Static analysis only.

### Step-by-step

1. **Read the issue + full context:**
   ```bash
   gh issue view <n> --repo vibrationalforce/Echoelmusic --json title,body,comments,labels
   ```

2. **Search the codebase for the relevant code:**
   ```bash
   gh api repos/vibrationalforce/Echoelmusic/contents/Sources/Echoelmusic
   # Then read specific files via:
   gh api repos/vibrationalforce/Echoelmusic/contents/Sources/Echoelmusic/<path>
   ```

3. **Common bug patterns and root causes:**

   **Crash: EXC_BAD_ACCESS / SIGSEGV**
   → Check `AVAudioSourceNode` render block for heap allocation (`Array.init`, `String()`)
   → Check force unwraps in audio path
   → Check `UnsafeMutablePointer` lifetime (captured correctly in connect()?)

   **Crash: Thread sanitizer / data race**
   → Check `nonisolated(unsafe)` properties accessed from multiple threads
   → Check `@Observable` class missing `@MainActor`
   → Check HealthKit/CoreMotion delegate callbacks dispatching to MainActor

   **Bug: Sound doesn't react to biometrics**
   → Check `applyBioReactive()` parameter ranges (too narrow = inaudible)
   → Check `update()` is being called (timer running, `isPlaying == true`)
   → Check `bus.usableBio()` is non-nil — a frame past its source's freshness
     window is dropped, so "no bio" and "stale bio" look the same downstream

   **Bug: Camera pulse detection not working**
   → `CameraRPPGBioPublisher` — did acquisition ever lock, or is it stuck in
     `.finding`? (a stall past 45 s is reported on screen since #484)
   → `CameraCapture.onFrame` closure — pixel buffer locked/unlocked correctly?
   → `CameraAnalyzer` exposure/brightness gates — the permissive threshold can
     freeze on a value that yields no pulse (#304, open)

   **Bug: Audio doesn't start**
   → `AudioEngine.start()` — did the AVAudioEngine graph actually start?
   → AVAudioSession category set to `.playback` or `.playAndRecord`?
   → Background audio entitlement in Echoelmusic.entitlements?

   **Build error: ITMS-90725**
   → `xcodebuild -showsdks | grep iphoneos` must show iOS 26
   → Xcode version must be 26.2+
   → `IPHONEOS_DEPLOYMENT_TARGET` stays at 18.0 (the floor), build SDK is 26

4. **Draft the fix:**
   - Minimal change. Max 3 files. One commit.
   - Follow existing patterns (pre-allocated buffers, guard-let, nonisolated(unsafe))
   - Write the test first (in relevant test file)

5. **Open a fix PR:**
   ```bash
   gh pr create --repo vibrationalforce/Echoelmusic \
     --title "fix: <description>" \
     --body "<fix description + root cause + test added>"
   ```

6. **Comment on original issue:**
   ```bash
   gh issue comment <n> --repo vibrationalforce/Echoelmusic \
     --body "Investigated. Root cause: <X>. Draft fix: <PR link>. Needs device verification by Michael."
   ```

### Fix PR body template

```markdown
## Fix for #<issue>

**Root cause:** <specific file:line and why it causes the bug>

**Fix:** <what changed and why it works>

**Test added:** `<TestFile>.<testMethodName>` — <what it verifies>

**Files changed:**
- `Sources/Echoelmusic/<path>` — <what changed>

---
⚠️ Static analysis only — functional verification requires TestFlight + device test by Michael.
Closes #<issue>
```
