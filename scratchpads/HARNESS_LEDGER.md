# HARNESS LEDGER — the Idea-Maze (read BEFORE you try something "new")

**Why this file exists.** In a long autonomous run the single biggest waste is
re-attempting an approach a *past* (now context-compacted) cycle already proved
is a dead-end — or re-discovering a deploy/CI trick from scratch. This is the
"effective harness for long-running agents" discipline (Anthropic, Nov 2025)
applied to Echoel: keep one durable, append-only map of **what was tried, what
won, and what is a known dead-end**, so the loop climbs instead of circling.

**How to use it (every cycle):**
1. **Before** trying a non-trivial approach, scan the DEAD-ENDS table. If it's
   listed, take the "do this instead" — do NOT re-run the failed path.
2. **After** a cycle, if you hit a real dead-end or found a reliable playbook,
   add ONE row. Keep rows one line, high-signal. Prune duplicates.
3. This complements `SESSION_LOG.md` (narrative history) and `decisions.csv`
   (strategic decisions). This file = tactical "don't retry / always do".

---

## DEAD-ENDS — proven not to work here (do the RIGHT column instead)

| Dead-end (do NOT retry) | Do this instead |
|---|---|
| Grow the `EchoelStudioView` `.sheet`/`.fullScreenCover` chain by appending another modal | Reuse/replace a slot, or one `.sheet(item:)` enum. Past the SwiftUI metadata-decoder limit = SIGSEGV at first render (black screen). `AnyView`-splitting the chain does NOT save it. |
| Read a ~10 Hz `@Observable` (rPPG waveform, bio snapshot, playhead) in a body/ancestor that hosts a `.menu`/Picker | Confine the live read to its own leaf `View`. `AnyView` is NOT an observation boundary. A 10 Hz read in ANY ancestor tears down open menus (the freeze). Audit the PARENT/ROOT, not just the obvious view. |
| `Task { @MainActor }` per frame from a 30 fps camera source | Push into a lock-protected `@unchecked Sendable` queue with zero actor hop; drain in an existing ~10 Hz main-actor poll. Per-frame main-actor tasks starve the SwiftUI executor. |
| `.map(String.init)` / bare `.init` func-refs in a pure Core | Use `.map { $0 }` / an explicit closure. Pure cores pass Linux CI but the iOS Xcode gate adds initializer overloads → "ambiguous" compile error. Scan new cores for this before pushing. |
| `.coordinateSpace(name:)` (and other iOS-16 SwiftUI overloads) | Use `.coordinateSpace(.named(_:))`. Deprecated-since-iOS-17 APIs can fail an `-warnings-as-errors` build. |
| `Double` expressions passed straight into `.frame`/`.position` | Keep view geometry in `CGFloat`; convert to `Double` only at a pure-math boundary. Double→CGFloat is not implicit for non-literals. |
| TestFlight deploy via workflow_dispatch / `gh` / curl GitHub API | Tokenless ONLY: bump+push `.deploy/release` (testflight.yml triggers on that path). Dispatch APIs return 403; the git relay allows only the designated feature branch. |
| `curl` the GitHub API for CI status (even with the gitignored token) | Use the `mcp__github__*` tools. curl → "GitHub access is not enabled for this session". |
| Trust "Quick Test" as a real gate | The real gates are **Xcode Compile Check** (iOS SDK — stricter) + **CI/CD Pipeline** (Linux build+test). Quick Test = lint only. |
| Simplify the Rausch triad (BioEventGraph / HilbertSensorMapper / BioSignalDeconvolver) | READ-ONLY. Do not touch without explicit founder approval. |
| Re-add a Session door, the 6-surface bottom bar, or the Tools grid | Founder-removed. Those files stay compiling but unpresented — do NOT resurface without a founder ask. |

## PLAYBOOKS — reliably works here

| Situation | Playbook |
|---|---|
| Verify a commit before deploy | Poll `mcp__github__actions_get get_workflow_run` for BOTH gates; green = Xcode Compile Check + CI/CD Pipeline both `conclusion: success`. Overflowing list output → parse the saved file with `scripts/gh-run-status.py`. |
| New pure core (math/model) | Foundation-only, deterministic (SeededRNG/UUID-fold, no Date/Random), `decodeIfPresent` defaults, Linux-testable. Split view math into a pure `*Math` enum. |
| New modal on the Arrange surface | Add an `ArrangeModal` enum case + one `modalEditor` arm — routes through the ONE existing `.sheet(item:)`. Never a new `.sheet`. |
| Milestone deploy | gates green → bump `.deploy/release` (vX.Y.Z + German notes) → push → TestFlight. Then German status delta to founder. |
| Mandatory reviewers | audio-thread (render paths) · concurrency (`@Observable`/async) · ui-state (Views). Run BEFORE commit; PASS is the gate. |

---

## LEADERBOARD — shipped this run (newest first)

| Version | What shipped | Gates |
|---|---|---|
| v10.79.195 | Immersive Stage — Touch room-map, each track a draggable spatial object (SpatialSceneStore + ImmersiveStageMath + ImmersiveStageView) | green |
| v10.79.194 | Multi-Roll (tracks play simultaneously) + per-track Record (arm→play→capture MIDI/bio→Clip+region) | green |
