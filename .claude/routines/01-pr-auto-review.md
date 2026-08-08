# Routine #1 — PR Auto-Review

**Triggers:** `pull_request.opened`, `pull_request.synchronize` on `vibrationalforce/Echoelmusic`
**Runs on:** Anthropic cloud (Linux, no iOS SDK)
**Status:** Active

When pasting into claude.ai: prepend `_golden-goal.md` verbatim, then this file.

---

## Your job

First-responder reviewer for every PR on Echoelmusic. Execute a full static review.
Stop before any decision that requires device testing or human judgment on sound quality.

### Step-by-step

1. **Read CLAUDE.md first.** Anchor every decision to the non-negotiable principles there.

2. **Fetch the PR:**
   ```bash
   gh pr view <n> --repo vibrationalforce/Echoelmusic --json title,author,body,files,commits,statusCheckRollup
   gh pr diff <n> --repo vibrationalforce/Echoelmusic
   ```

3. **Classify the PR type:**
   - **Audio/DSP change** → mandatory audio thread safety audit
   - **Bio/HealthKit change** → data accuracy + privacy audit
   - **UI/SwiftUI change** → design constraints audit (banned patterns from CLAUDE.md)
   - **CI/Build change** → reproducibility + iOS 26 SDK compliance check
   - **Docs/Memory change** → factual accuracy only

4. **Audio thread safety audit (ALL audio/DSP PRs — mandatory):**

   Check every `AVAudioSourceNode` render block and DSP kernel for:

   | Violation | Severity |
   |-----------|----------|
   | `Array.init`, `[T](repeating:)` inside render block | 🔴 P0 — BLOCKS MERGE |
   | `malloc`, `free`, `new`, `delete` | 🔴 P0 |
   | `String()`, string interpolation | 🔴 P0 |
   | `DispatchQueue`, `Task`, `async/await` | 🔴 P0 |
   | `NSLock`, `pthread_mutex`, semaphore | 🔴 P0 |
   | `os_log` in render hot path | 🟡 P1 |
   | Missing `nonisolated(unsafe)` on audio thread properties | 🟡 P1 |
   | New scratch buffer not pre-allocated in `init`/`connect()` | 🟡 P1 |

   **Safe on audio thread:** pre-allocated `[Float]` index access, `vDSP_*`, `memcpy`, arithmetic, `nonisolated(unsafe)` reads.

5. **Swift 6 concurrency audit:**
   - All new `@Observable` classes must have `@MainActor`
   - Callbacks from HealthKit/CoreMotion/AVFoundation must be `nonisolated` + dispatch to `@MainActor` via `Task { @MainActor in }`
   - No `@unchecked Sendable` without comment explaining thread-safety proof
   - No `print()` — use `log.log(.info, category: .X, "message")`

6. **Bio/Science audit (Bio PRs):**
   - Every new bio claim needs a peer-reviewed citation
   - No pseudoscience terms: chakra, aura, energy healing, quantum, vibration (in non-physics context)
   - Coherence calculation must use LF/HF ratio, not audio-level proxy
   - Safety warnings must remain intact (3Hz flash limit, not-for-medical-diagnosis)

7. **UI/Design audit (View PRs):**

   **BANNED — reject as P1:**
   - Border radius > 16px
   - `.ultraThinMaterial`, `.blur()`, glassmorphism
   - Glow effects, neon colors, shadows > 8px blur
   - Scale/transform animations (opacity/color only)
   - `Color.magenta` (doesn't exist — use `Color(red:1,green:0,blue:1)`)
   - `ObservableObject`, `@Published` (must use `@Observable`)
   - `UIScreen.main` (deprecated)

8. **Test coverage check:**
   - New DSP algorithm → test in `DSPTests.swift` or `EchoelDDSPTests.swift`
   - New bio calculation → test in `BioEngineTests.swift` or `BioIntegrationTests.swift`
   - New core system → test in `CoreSystemTests.swift`
   - No new test file needed for trivial parameter changes

9. **Post the review:**
   ```bash
   gh pr review <n> --repo vibrationalforce/Echoelmusic --comment --body "..."
   ```
   **Never** `--approve`. **Never** `--request-changes` unless P0 found.

### Review body template

```markdown
## Review (automated — needs device verification by Michael)

Thanks @<author> for <specific thing that works>. <One sentence, specific.>

### Findings

| Priority | Area | Summary |
|---|---|---|
| P0 | Audio Thread | Array allocation in render block line 163 |
| P1 | Concurrency | Missing @MainActor on new @Observable class |
| P2 | Style | Redundant guard clause |

### P0: <title>

`Sources/Echoelmusic/Audio/AudioEngine.swift:163`

<concrete description + suggested fix with code>

### What I checked (static only)

- [ ] Audio thread safety in render blocks
- [ ] Swift 6 @MainActor / @Observable patterns
- [ ] Bio science claims + citations
- [ ] UI design constraints (CLAUDE.md)
- [ ] Test coverage

**⚠️ Functional correctness not verified — needs TestFlight build + device test by Michael.**
```
