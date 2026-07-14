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
| Diagnose "total silence" as an engine/generate bug when the log shows `generate: N notes, playing=true` | The generative roll is gated by `Timeline.rollSlotGain` (first non-bio MIDI lane's mute/solo/level) → `pianoRoll.mixGain` → `PianoRollView` `laneAudible` gates every `noteOn`. A MUTED "MIDI 1" (or a foreign SOLO, or level 0, or `suppressBuiltIn` via an assigned AUv3) = total silence with notes still generating. Check `rollMixGain` in the generate breadcrumb; the visual-log `level=1.0` is SUMMED VELOCITIES (intent), NOT measured output. |

## PLAYBOOKS — reliably works here

| Situation | Playbook |
|---|---|
| Verify a commit before deploy | Poll `mcp__github__actions_get get_workflow_run` for BOTH gates; green = Xcode Compile Check + CI/CD Pipeline both `conclusion: success`. Overflowing list output → parse the saved file with `scripts/gh-run-status.py`. |
| New pure core (math/model) | Foundation-only, deterministic (SeededRNG/UUID-fold, no Date/Random), `decodeIfPresent` defaults, Linux-testable. Split view math into a pure `*Math` enum. |
| New modal on the Arrange surface | Add an `ArrangeModal` enum case + one `modalEditor` arm — routes through the ONE existing `.sheet(item:)`. Never a new `.sheet`. |
| New surface inside EchoelStudioView (its `.sheet` chain is at the metadata ceiling) | Present IN-PLACE as a section inside an existing `StudioMenu` dropdown panel (e.g. `compositionPanel`), reading only @State snapshots (no 10 Hz observable in the root-body dropdown). No new `.sheet`. |
| Audition/preview a variant of a generate()-built take | Extract generate()'s Input construction into ONE shared `makeComposerInput(advanceEvolution:…overrides)` so the preview scores the EXACT input the take will use (honest), and add nil-default seed overrides to `generate()` so apply replays the picked seeds bit-for-bit. Don't duplicate the composer logic in the preview. |
| Milestone deploy | gates green → bump `.deploy/release` (vX.Y.Z + German notes) → push → TestFlight. Then German status delta to founder. |
| Mandatory reviewers | audio-thread (render paths) · concurrency (`@Observable`/async) · ui-state (Views). Run BEFORE commit; PASS is the gate. |
| Per-instrument feature (per-track sound/genre/mood) | AUDIBLE only via per-lane voices = `LaneVoiceRack` = `FeatureFlags.multiRoll` ON (default OFF, device-gated). Store + wire the per-lane data BEHIND the flag (bit-identical OFF); do NOT ship user-facing per-track SOUND UI while multiRoll is OFF (inert control = worse than none). The keystone flip is a founder/device milestone. |
| MCP (GitHub) down mid-cron | Can't verify gates (no curl-to-github; token+curl blocked). git push still runs CI serverside. Do NOT push device-only `#if AVFoundation` code blind (only the Xcode gate validates it). Restrict to CI-safe pure/doc work; verify gates next tick when MCP returns. |
| Flip/verify a risky keystone flag (multiRoll etc.) before wiring on top | Run a Workflow audit FIRST: N parallel subsystem readers → adversarial verify of blockers → synthesis of go/no-go + edit list. It found multiRoll was ALREADY default-ON with 3 live bugs (bar-1 silence, mute-leak, patch-unwired) that a blind wiring pass would have built on. Audit-first, then single-writer implement the confirmed fixes. |
| Device-only fix that can't run on Linux CI (needs PianoRollModel/AVFoundation) | Extract the DECISION into a pure Foundation enum (e.g. `MultiRollFanout`) the @MainActor class consumes → the bug-fix logic is Linux-CI-tested even though play() isn't. Same pattern as `*Math` view-math splits. |

---

## LEADERBOARD — shipped this run (newest first)

| Version | What shipped | Gates |
|---|---|---|
| v10.79.199+ | Founder live redesign (07-14): Bio→header (tap=info), Transpose removed, Immersive Stage→ADM-OSC egress; then the "alles ist still" root cause (roll-slot lane mute/solo gates the generative melody) + a silenced-instrument guard banner with one-tap "Ton an" | green |
| v10.79.198 | BioVariationMaze audition — "Variationen" card in the Comp dropdown: Explore ranks 6 body-curated groove variations, tap one to play it. Shared makeComposerInput builder (no dup logic); generate() gains nil-default seed overrides. No new sheet, no 10 Hz read | green |
| v10.79.197 | rPPG pulse-lock fix — wired RPPGConditioning.linearDetrend into the periodicity estimate (kills the DC ramp that mean-removal leaves) | green (device-verify pending) |
| v10.79.196 | Adaptive home — arrange timeline fills the screen, instrument zone conditional (chip bar idle, dropdowns on demand); killed the black void | green |
| v10.79.195 | Immersive Stage — Touch room-map, each track a draggable spatial object (SpatialSceneStore + ImmersiveStageMath + ImmersiveStageView) | green |
| v10.79.194 | Multi-Roll (tracks play simultaneously) + per-track Record (arm→play→capture MIDI/bio→Clip+region) | green |
