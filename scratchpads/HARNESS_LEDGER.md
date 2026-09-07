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
| Re-run a #478-flaked CI job via `mcp__github__actions_run_trigger` (`rerun_failed_jobs` / `rerun_workflow_run`) | Both return `403 Resource not accessible by integration` (2026-09-04, run 33861116782). And `ci.yml` only fires on `Sources/**`/`Tests/**`/`Package.swift`/`project.yml`, so a docs commit does not re-drive it either. The re-run IS the next code slice — push it and read the new run; never an empty commit. |
| `curl` the GitHub API for CI status (even with the gitignored token) | Use the `mcp__github__*` tools. curl → "GitHub access is not enabled for this session". |
| Trust "Quick Test" as a real gate | The real gates are **Xcode Compile Check** (iOS SDK — stricter) + **CI/CD Pipeline** (Linux build+test). Quick Test = lint only. |
| Assume a `static func` on a view/type is nonisolated "because it's pure" | A `static func` on a `@MainActor` type (e.g. `struct PianoRollView: View` is implicitly `@MainActor`) INHERITS main-actor isolation. A nonisolated (un-annotated) test calling it = "call to main actor-isolated static method in a synchronous nonisolated context" → `-warnings-as-errors` build RED. Fix: mark the TEST `@MainActor` (or mark the static `nonisolated static func` if it's truly pure — like `PianoRollModel.noteExpression`). Check the enclosing type's isolation before writing a nonisolated caller. |
| Simplify the Rausch triad (BioEventGraph / HilbertSensorMapper / BioSignalDeconvolver) | READ-ONLY. Do not touch without explicit founder approval. |
| Re-add a Session door, the 6-surface bottom bar, or the Tools grid | Founder-removed. Those files stay compiling but unpresented — do NOT resurface without a founder ask. |
| Diagnose "total silence" as an engine/generate bug when the log shows `generate: N notes, playing=true` | The generative roll is gated by `Timeline.rollSlotGain` (first non-bio MIDI lane's mute/solo/level) → `pianoRoll.mixGain` → `PianoRollView` `laneAudible` gates every `noteOn`. A MUTED "MIDI 1" (or a foreign SOLO, or level 0, or `suppressBuiltIn` via an assigned AUv3) = total silence with notes still generating. Check `rollMixGain` in the generate breadcrumb; the visual-log `level=1.0` is SUMMED VELOCITIES (intent), NOT measured output. |
| Read `build-for-testing: failure` + exit 65 and conclude "the N test files have API drift / don't compile" | READ THE ACTUAL ERROR LINES first (surface them to job-log STDOUT via a `grep … tee` summary step — artifacts need a token the sandbox lacks). The Echoel 294-suite "failure" was ONE distinct error, `Unable to find module dependency: 'Echoelmusic'` (×4) at every file's `@testable import` line — a project.yml WIRING gap (no `ENABLE_TESTABILITY` + Xcode-26 explicit-modules can't resolve `@testable import` of an APP target), NOT 294 broken files. The "Missing bundle ID from Echoelmusic.app" in the test phase is a cascade of the failed build, not a second bug. Fix: `ENABLE_TESTABILITY: YES` (Debug) + `SWIFT_ENABLE_EXPLICIT_MODULES: NO` on the test targets. Exit 65 = "a build failed", never "the sources are wrong." |
| Pass a dynamic-Workflow task list via the `args` parameter | Hardcode the list as a `const` in the script body. Observed 2026-07-21: `args` arrived as a STRING not an array → `args.map is not a function` at the first `parallel(args.map(...))`, on the initial launch AND every `resumeFromRunId` retry (resume re-binds the same corrupt args, so it crashes identically). A fresh run with the data baked into the script ran clean. Don't burn 3 launches re-passing `args`. |
| Act on an ULTRAARCHITECTURE-map "dead code / delete X" flag without re-verifying runtime reality | The map is a SECONDARY source — a worker's grep, not ground truth. Tier E ran 6/7 false-positive-or-already-done: E4 `EchoelCellular` "dead" (LIVE in AUv3 `:27` — worker grepped only `Sources/Echoelmusic/`), E2 `ChromaKey.metal` "delete" (deferred #40 video-FX scaffold, no runtime consumer ≠ delete), E3 `toolsSection` "reduces the metadata chain" (FALSE — an unmounted `var` adds nothing to `body`'s generic type), E6 "enforce single MetalBioView" (ALREADY enforced, `onChange(of:showVisual)` EchoelStudioView.swift:675-688), E7 "raw Slider→EchoelValueField" (a look CROSSFADER, not a numeric param), E5 the ONE real fix. Before any map-driven delete: grep ALL targets (incl. `Sources/EchoelmusicAUv3/`), confirm no runtime loader/consumer, and check the claimed BENEFIT is real. "no consumer" ≠ "delete" when it's on-vision deferred scaffold. |
| Write a `.deploy/release` whose FIRST line is `build: <date/label> …` with no version | The `.deploy/release` MUST contain a `v10.79.XXX` string (testflight.yml greps `v[0-9]+\.[0-9]+\.[0-9]+` → MARKETING_VERSION). Omit it and DEPLOY_VER is empty → the app ships with project.yml's default MARKETING_VERSION. Observed 2026-07-22: a whole session's builds shipped at the STALE default 10.79.66 while the founder's device was on 10.79.325 — TestFlight sorts by version, so the newer builds landed BELOW 2433 and looked older ("letzter Build ist noch 2433"), even though each was `state=VALID` in ASC. ALWAYS put `v10.79.<n+1>` (higher than the last shipped) as/near the first line, AND keep project.yml's `MARKETING_VERSION` default bumped so a forgotten string can't regress the version. Verify a deploy by build NUMBER (run_number) AND that its MARKETING_VERSION ≥ the last one. |
| Cite a nearby code COMMENT as evidence for a claim you are about to write into new code, a commit message, or CLAUDE.md | **Verify the claim against the CALL SITES, not the comment.** Comments are the most stale artifact in this repo, and copying one propagates it: a reviewer caught the same failure three times in the 2026-07-26 cycle. (1) `SignalRouter.swift`'s port comment said `blehrs.in` starts/stops the BLE strap via `applyRouting` — true only 07-12→07-15, removed by BLE-3; I copied it into 2 new comments + a commit message + it was also in CLAUDE.md, so ONE stale site became FOUR. `hasEnabledRoute(fromSource:)` has ZERO production callers. (2) `SignalRoute.amount` is documented "Transform depth / gain [0..1]" — **nothing reads it** (#171). (3) "a persisted NaN reached the transform depth" — `JSONDecoder`/`JSONEncoder` throw on non-conforming floats by default, so a NaN was never storable. **THE CHECK, 30 seconds:** grep the symbol across `Sources/`+`Tests/` and confirm a PRODUCTION caller/reader exists before asserting behaviour. Zero callers = the claim is about dead code. And when you find a stale comment, FIX IT AT THE SOURCE in the same commit — leaving it re-infects the next session. |
| Justify a persistence fix with a failure mode the fix does not actually cover | **Element-tolerance (`decodeLossyArray`) and a forgiving element decoder (`init(from:)` + `decodeIfPresent`/`try?` defaults) fix DIFFERENT halves; neither alone is the fix.** Tolerance saves readable elements when SOME fail. It does nothing when ALL fail at once — the schema-upgrade case (a new required field) — because every element becomes a hole, `compactMap` yields `[]`, and the next `save()` writes that emptiness back: the same total wipe, one log line richer. Ship both, or say plainly which half you shipped. |
| Add a `resources:` key to a target in `project.yml` | **XcodeGen has NO target-level `resources:` key** — verified 2026-07-26 against the pinned 2.42.0 (`Docs/ProjectSpec.md`'s Target list omits it; `Target.init(name:jsonDictionary:)` never reads it; the only `resource` substring is `putResourcesBeforeSourcesBuildPhase`). There is no unknown-key validation, so `xcodegen generate` ACCEPTS the block and discards it in silence — no warning, exit 0. Declare resources as `sources:` entries with `type: folder` (structure-preserving, needed for any `subdirectory:`/path-suffix bundle lookup) or `type: file`, plus `buildPhase: resources`. What the inert block cost here: `Resources/Drums|Samples|Community` were excluded from the group walk AND declared only in the dropped block → in NO build phase for 5 days; `PrivacyInfo.xcprivacy` + the brand font were declared ONLY there, on app AND widget, so the App Store privacy manifest never shipped and Info.plist's `UIAppFonts` named .ttf files absent from the bundle. `Assets.xcassets` kept working purely because it was the one entry NOT excluded from the walk — that asymmetry is the tell. |
| Guess again at a config/bundling bug whose last two "fixes" had "no measurable effect" | **INSTRUMENT IT FIRST.** "No effect" usually means the INSTRUMENT is blind, not that the change did nothing (here, `8f362ea` changed the product drastically — it just could not be seen). The Echoel constraint: `full-tests.yml`'s summary greps only `Test case '<name>' failed`, so XCTAssert MESSAGES never reach a readable log and artifacts need a token the sandbox lacks. **THE PLAYBOOK:** split the failing claim into one assertion PER LINK OF THE CHAIN, each in its own test method, so the failing NAMES alone are the diagnosis (`CommunityBundleDiagnosisTests`). Rules that make it work: assert against the REAL object (expose `private` → `internal` as a seam) not a re-implementation; track each parallel case separately (fx AND moods — a chain that follows only one reads green while the other is red); and use `XCTUnwrap`, never an early `return`, where a link can't be evaluated — a silent pass is indistinguishable from a real pass in a name-only channel. Cost: one commit. It found a 5-day shipping defect that three blind attempts had missed. |
| Write a long XCTAssert failure message as an inline `+`-chain of string literals wrapped around a `joined(separator:)` / interpolation | **Use ONE `"""` multi-line literal as the message argument.** Observed 2026-07-31 (`f8f1fef`, `ContentPipelineClaimsTests`): five `+`-joined literals around `auv3.joined(separator: "\n")` inside `XCTAssertTrue(...)` → *"the compiler is unable to type-check this expression in reasonable time"*, a HARD error that turned the **blocking** gate (CI/CD Pipeline, `build-for-testing`) red; the sibling assert in the same file was a 6.2 s warning — same defect, just under the limit. `XCTAssert*`'s autoclosure + `String`'s many `+` overloads make the chain super-linear; a multi-line literal with `\(…)` interpolation is ONE expression and costs nothing. This repo writes long, explanatory failure messages ON PURPOSE (they are the only diagnosis channel — see the "INSTRUMENT IT FIRST" row), so the shape matters. The warning form is the early tell — if the log shows "expression took NNNNms to type-check" on an assert, convert it before it crosses the line. **⚠️ THIS ROW SAID "long message = `\"\"\"`, never `+`" AND THAT ABSOLUTE WAS WRONG BY 2026-08-05** — a reviewer found the shipped practice (`TakeDistanceTests`, `ReusedTailIsTheQuietestOneTests`) disagreeing with the recorded rule, which is the exact drift this ledger exists to prevent. **The real threshold is the AUTOCLOSURE plus the CALL:** what blew up was five literals wrapped around `joined(separator:)` *inside* `XCTAssertTrue(...)`, where the autoclosure and `String`'s `+` overloads compound. **Hoisting to `let message = "…" + "…"` BEFORE the assert takes it out of the autoclosure and is sufficient** for a handful of plain literals with no function call in the chain. A `"""` literal is still the safest shape and the right reach for anything long or interpolated — but "never `+`" would have sent a session refactoring working code, and this repo has already paid once for a purely cosmetic edit to a compiling line (see the `Self.someStatic` row). |
| Write `a ?? b ..< c` (or any `??` next to a range/comparison operator) in one expression | **Split it into two statements with an explicit type.** `..<` is `RangeFormationPrecedence`, `??` is `NilCoalescingPrecedence`, and range binds TIGHTER — so `code[code.index(…, limitedBy: code.startIndex) ?? code.startIndex ..< r.lowerBound]` parses as `index(…) ?? (startIndex ..< lowerBound)`: a `String.Index?` coalesced with a `Range`. Observed 2026-08-01 (`0d2e622`, `BioApplyRateIsTheDedupedRateTests`): it took the **blocking** gate red, and the diagnostic — *"type of expression is ambiguous without a type annotation"* pointing at the SUBSCRIPT — names neither the operator nor the precedence, so it reads like a subscript-overload problem and sends you to the wrong line. The `limitedBy:` idiom is where this bites, because its `?? startIndex` fallback sits exactly where a range operator follows. |
| Write `Self.someStatic` as a DEFAULT ARGUMENT inside a class (incl. a `final class` — every `XCTestCase` here) | **Spell out the type name: `MyTests.someStatic`.** Swift rejects it with *"covariant 'Self' type cannot be referenced from a default argument expression"* regardless of finality — `final` does not exempt you, which is the part that surprises, because everywhere else in a `final class` `Self` and the type name are interchangeable. Observed 2026-08-01 (`d1ea93d`, `ScopeTriggerStandsStillTests`): **blocking** gate red. **The general lesson is bigger than the rule, and it is the reason this row exists at all:** the bare `bufferLength` it replaced compiled fine for days. It was changed for a purely COSMETIC reviewer note (the only unqualified-static-in-default-argument in the repo) — so a readability edit, on working code, in a file the same commit was otherwise fixing, is what broke the build. Third parse-level trap in two days and the only self-inflicted one. **A compiling line changed for style alone still has to clear the gate**: "obviously equivalent" is a claim about the language, and this repo has now been wrong about that claim three times in 48 hours. |
| Stop publishing `.airCC` (CC 21–31) at `MIDIBusPublisher.publishCC` because nothing consumes it | **Measured, built, graded — and REVERTED unshipped (#950, 2026-09-01).** The cost is real: `.airCC` reaches one consumer, a bare `case .airCC: break`, so every message spends a slot in the 128-deep DROP-NEWEST `controllerEvents` ring (whose own doc says a rejected `.noteOff` strands its `.noteOn`) **and** one `Task { @MainActor }` per message via `EngineBus.publish(controller:)` — the documented 10.76.48 executor-starvation shape. What killed it was BLAST RADIUS, not correctness: air-CC input is documented as arriving in **7 prose sites** (`README.md:22`, `docs/architecture.html:180/194/301/352`, `docs/overview.html:241`, and the failure message of `TheMPEInputHasNoZonesTests` claim 10b), so the one-line code change drags a user-facing copy sweep and NARROWS a documented wire for a benefit whose flood half needs ~1280 msg/s (reachable on USB-MIDI, unmeasured on device). **Do this instead — ⭐ AND IT IS DONE (#951, same day):** treat the per-event `Task` as the root cause — it costs every controller message, not just air-CC, and `EngineBus.publish(controller:)`'s own doc already names the fix as a FOLLOW-UP ("coalesce the notification to once per batch — a pending flag here, or let `MIDIInput.drainIncoming` trigger the drain once after its loop"). ⚠️ That fix is NOT a same-cycle patch: `publish(controller:)` is `nonisolated` with no atomics available (zero deps), and the obvious "spawn only if the queue was empty" gate has a real race — a drain already in flight can pass your slot, leaving the event undrained until the 10 Hz poll. It needs the concurrency-reviewer. ⭐ **#951 shipped it and took NEITHER trap:** the gate is a pending FLAG under an `NSLock`, cleared BEFORE the hook, not the "queue was empty" test this row warned about — so the race described above does not apply to what shipped, and the reviewer proved no interleaving loses a wake-up (the enqueue precedes the flag section, so any publisher that sees the flag set has its element in the ring before the pending drain runs). **What remains of #950 is only the QUEUE-SLOT half**, the weaker one: it needs a real overflow, ~1280 messages/s. The value question (should the app keep receiving an inert air-CC stream at all?) is FOUNDER taste, not engineering, and is on the device checklist. |
| Call `NSLock.lock()` / `.unlock()` inside a `Task { }` (or any `async`) body | **Xcode gate RED, SwiftPM silent** (#951b, 2026-09-01): *"instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead"* — they are `@available(*, noasync)`. **Do this instead:** put the critical section in a `nonisolated private func` and call THAT from the async body. It is not a loophole: `noasync` exists to stop a lock being held across a suspension point, and a synchronous function cannot contain an `await`, so the property is structurally guaranteed rather than dodged. (`withLock` is the diagnostic's own suggestion but has ZERO precedent in this tree — don't introduce an API the SDK might not expose where you cannot compile.) ⚠️ **THE LESSON IS ABOUT REVIEW, NOT ABOUT LOCKS:** a concurrency review and I both checked ISOLATION — correctly, against five precedents — and neither checked `noasync`. **Whether a `nonisolated` member is REACHABLE from a context is a different question from whether its API is ALLOWED there**, and only the second one an `async` closure asks. Add `noasync` to the checklist for any Foundation primitive used inside a `Task`. |
| Size a `Workflow` verify/critic stage to the IDEAL (one refuter per finding, N lenses) on this container | **Killed TWICE in one day by the session limit (2026-09-02).** The audit workflow (117 agents) lost 46 — every verifier from #18 on and the critic — after 133 min; the DMMW workflow (89 agents, already cut to 2 lenses) lost 19 including the SYNTHESIS, so the report had to be written by hand from four lead answers. Mechanics: the container has 4 CPUs → concurrency 2, so N agents cost ~N/2 × agent-minutes of wall clock, and the session cap lands before the tail stage regardless of how good the leads were. **Do this instead:** put the LEAD stage first and make it the deliverable (`leads` survive in the output file even when `synthesis` is null); verify only CRITICAL findings, 1 lens; write the synthesis in the main loop from the lead answers, not as the last agent in the script. A stage that runs last runs least. |

## PLAYBOOKS — reliably works here

| Situation | Playbook |
|---|---|
| Removing a "write-only" mirror/cache after its sole reader is gone (2026-07-25, 2d-3b, `c3b3666`) | A mirror object (`HostMusicalState`) written from a control-plane path (`Transport.tick/play/stop/seek/setTempo`) and read ONLY by a now-deleted consumer (the AUv3 host-context render blocks) is safe to remove WHOLESALE — but the write sites hide **derived locals used only by the write** (`let oldAbsoluteStep = position.absoluteStep` served ONLY the accumulate/reset block). **DO THIS:** (1) grep EVERY mirror symbol (type, `.shared`, each method: `advanceSamplePosition`/`resetSamplePosition`/`beatPosition`/`samplePosition`) across `Sources/`+`Tests/` and confirm 0 non-mirror readers BEFORE cutting; (2) when you delete a write block, delete any local that ONLY fed it (else "unused variable" or a dangling ref); (3) the remaining hot-path logic (bar-wrap, `lastStep`, `stepSubs` firing) must stay **byte-behavior-identical** — diff it line-for-line; (4) MANDATORY audio-thread-reviewer even though it's pure deletion, because the path is the transport tick relay. Result: shrinks the render-thread-touching surface, 0 behaviour change. |
| Verify a commit before deploy | Poll `mcp__github__actions_get get_workflow_run` for BOTH gates; green = Xcode Compile Check + CI/CD Pipeline both `conclusion: success`. Overflowing list output → parse the saved file with `scripts/gh-run-status.py`. |
| A run's `conclusion` says `failure` but the code is fine (2026-07-25, `8ecb58c`) | The **run-level conclusion is NOT the gate** — a non-code job can drag it red. On `8ecb58c` both real workflows showed `failure` while EVERY compile+test job was green; the ONLY red job was **"Send Notifications"** (ubuntu, runner_id 0 = a webhook/notify infra step) in CI/CD Pipeline, and Xcode Compile Check's single compile job was fully green despite a red run conclusion. **DO THIS:** before "fixing" a red run, drill to the JOB level — `mcp__github__actions_list method=list_workflow_jobs resource_id=<run_id>` — and read each job's `conclusion` + steps. If the failed job is Send Notifications / a notify/upload step (not Build/Compile/Test), it's INFRA, not your code; do not touch CI config (founder-gated) and do not amend code. Corroborators that the code is actually green: "Auto-Merge Claude Branch" = success, "Echoel Full Test Suite" = success. |
| "Run Tests" is red inside a GREEN "Build for Testing", and no test says `failed` (2026-08-02, `08e5cd5`) | **Read the log before believing the step name.** This variant is one level deeper than the Send-Notifications row above: the failing job really IS `Build & Test (iOS)` and the failing step really IS `Run Tests`, so job-level drilling alone still points at your code. The log said something else — `Simulator device failed to launch com.echoelmusic.app` … `FBProcessExit Code=64 "The process failed to launch"` … `RequestDenied (SBMainWorkspace)` on **"Clone 2 of iPhone 17"**, then `** TEST EXECUTE FAILED **`. `xcodebuild` runs the bundle across parallel simulator CLONES; Clone 1 had already reported hundreds of `passed` lines. One clone that cannot launch the host app aborts the whole run. **DO THIS:** (1) `mcp__github__get_job_logs job_id=<id> return_content=true tail_lines=120`; (2) grep the tail for `failed` on a `Test case '` line — if there is none, no assertion fired; (3) if you see `failed to launch` / `FBSOpenApplicationServiceErrorDomain` / `TEST EXECUTE FAILED`, it is the simulator, not the diff; (4) do NOT "fix" a test, do NOT touch CI config (founder-gated), do NOT re-run blind before reading. **Distinguishing rule:** an assertion failure names a test; an infra failure names a device. ⛔ **THE FIRST VERSION OF THIS ROW GOT STEP (4) WRONG AND WAS FALSIFIED WITHIN THE HOUR.** It said: "push the NEXT commit (a docs/comment-only one is ideal) and let its run be the control — if it goes green the transient is proven." The comment-only control (`b4e256d`) went **RED TOO**, with a DIFFERENT simulator error (`CoreSimulator SimError 405 "Invalid device state"` / `NSMachErrorDomain -308 "(ipc/mig) server died"`) on the same "Clone 2". A control that fails proves nothing either way, so the rule had no verdict for its own most likely outcome — and would have pushed the next reader back toward suspecting the diff. **THE EVIDENCE THAT ACTUALLY DECIDES IT IS INSIDE ONE RUN: clone asymmetry.** The SAME app binary launched on Clone 1 and ran hundreds of tests to completion in BOTH red runs. A launch-breaking defect in the binary cannot be clone-specific, so the binary is exonerated by the log alone — no second run required. **Two different errors across two runs** is corroboration (a code bug fails identically; independent infra failures differ), not the proof. Also do not lean on `Echoel Full Test Suite` being green here: its `continue-on-error` makes step conclusions unreadable (#208). ⛔ **AND THE THIRD RED RUN (`bbac19a`, same day) BROKE THIS ROW'S OWN STEPS (2) AND (3): the log named NOTHING.** Full job log read end to end (4999 lines — the whole thing, not a tail): zero hits for `' failed`, `Failed to`, `SimError`, `Invalid device`, `Clone 2`, `Testing failed`, `Assertion`. Just `Process completed with exit code 65` and a bare `** TEST EXECUTE FAILED **`. **Why: the diagnostic step is `tail -200 test.log`, and with `-parallel-testing-enabled YES` that tail is whichever clone happened to be writing last** — here Clone 1, all `passed`. The failure was earlier in `test.log` and was never printed. So the distinguishing rule ("an assertion names a test, infra names a device") is sound but not always REACHABLE, and "the log named no test, therefore infra" is a **non-sequitur when the log named nothing at all** — absence of evidence is not the clone-asymmetry proof. **DO THIS when the tail names nothing:** (a) check `Build for Testing` — if it is `success`, the bundle COMPILED and only execution failed, which already rules out your new test file failing to build; (b) re-run the suspect guard's assertions locally (a source-scan guard is deterministic — re-implement it in Python against the worktree and against `git show HEAD:`); (c) state the result as UNDETERMINED rather than picking the comfortable answer. Filed as **#396** (founder-gated: the fix is one added `grep -nE "error:\|' failed\|Failed to launch\|SimError\|Invalid device state" test.log` beside the tail — the tail shows how FAR it got, the grep shows what it died ON). ⭐ **RUN FOUR (`916f2e8`) SUPPLIED THE NAME THE THIRD WITHHELD, AND IT CLOSES THE PATTERN.** Same job, `Failed to launch app with identifier: com.echoelmusic.app` … `RUN_DESTINATION_DEVICE_NAME = "Clone 2 of iPhone 17"` … `error = Error Domain=NSMachErrorDomain Code=-308 "(ipc/mig) server died"`. **All four reds are Clone 2; Clone 1 completed hundreds of `passed` in every one of them; across four runs ZERO `Test case '…' failed` lines exist.** The launch service on the second clone dies — `-308 (ipc/mig) server died` in runs 2 and 4, `FBProcessExit Code=64` in run 1. So the row's original clone-asymmetry verdict was right, and the third run's silence was a reporting gap, not a different failure. **The correction to keep: four in a row is NOT a transient**, so "wait for it to pass" is not a plan — `-parallel-testing-enabled YES` means one dead clone aborts a run in which nothing was actually wrong, and the gate cannot go green by luck often enough to matter. The end of it is a CI decision (drop to one simulator destination, or retry the test step once), which is **founder-gated** — so the honest status line while it stands is "compile proven green on both gates, execution blocked by the runner, zero failing assertions", not "gates green" and not "red, cause unknown". ⭐ **RUN FIVE (`74bb42d`) IS THE MOST USEFUL OF THE FIVE, BECAUSE IT SHOWS WHAT A RED RUN STILL PROVES.** Same signature exactly — `RUN_DESTINATION_DEVICE_NAME = "Clone 2 of iPhone 17"`, `NSMachErrorDomain Code=-308 "(ipc/mig) server died"`, `** TEST EXECUTE FAILED **`, and again zero `Test case '…' failed` lines. But this run carried the first REAL behavioural test file in `Tests/CISmoke` (`SleepingChainDoesNotHoardAudioTests`, #389 — actual float buffers through actual DSP stages), and the log shows **all five of its cases `passed` on Clone 1**, with timings (0.268 s / 0.177 s / 0.126 s / 0.065 s / 0.004 s). **So a Clone-2 red is not an information blackout: everything Clone 1 reached before the abort is a genuine executed result.** Upgrade the status line accordingly — for tests Clone 1 got to, say "executed and passed", not merely "compile-verified". **AND THE LIMIT OF THAT, stated so it is not over-claimed:** those five passes validate the DRAIN behaviour only. They ran against the version whose ship blocker was a THREADING defect (`reset()` from the render block), and they passed with it — as the audio-thread reviewer predicted, because every case here drives the chain single-threaded. **A green test that cannot observe the defect is not evidence against it.** Read which clone got how far before writing either half of the sentence. |
| New pure core (math/model) | Foundation-only, deterministic (SeededRNG/UUID-fold, no Date/Random), `decodeIfPresent` defaults, Linux-testable. Split view math into a pure `*Math` enum. |
| New modal on the Arrange surface | Add an `ArrangeModal` enum case + one `modalEditor` arm — routes through the ONE existing `.sheet(item:)`. Never a new `.sheet`. |
| New surface inside EchoelStudioView (its `.sheet` chain is at the metadata ceiling) | Present IN-PLACE as a section inside an existing `StudioMenu` dropdown panel (e.g. `compositionPanel`), reading only @State snapshots (no 10 Hz observable in the root-body dropdown). No new `.sheet`. |
| Audition/preview a variant of a generate()-built take | Extract generate()'s Input construction into ONE shared `makeComposerInput(advanceEvolution:…overrides)` so the preview scores the EXACT input the take will use (honest), and add nil-default seed overrides to `generate()` so apply replays the picked seeds bit-for-bit. Don't duplicate the composer logic in the preview. |
| Milestone deploy | gates green → bump `.deploy/release` (vX.Y.Z + German notes) → push → TestFlight. Then German status delta to founder. |
| Mandatory reviewers | audio-thread (render paths) · concurrency (`@Observable`/async) · ui-state (Views). Run BEFORE commit; PASS is the gate. |
| Per-instrument feature (per-track sound/genre/mood) | AUDIBLE via per-lane voices = `LaneVoiceRack` = `FeatureFlags.multiRoll`, which is **DEFAULT-ON since 2026-07-14** — `EchoelmusicApp.swift` registers it `true` before the first read. The OFF branch survives only as a one-line rollback lever; never delete it. **The old "default OFF, device-gated → do NOT ship per-track sound UI" caveat no longer applies** and would today block work that is already shipped. |
| MCP (GitHub) down mid-cron | Can't verify gates (no curl-to-github; token+curl blocked). git push still runs CI serverside. Do NOT push device-only `#if AVFoundation` code blind (only the Xcode gate validates it). Restrict to CI-safe pure/doc work; verify gates next tick when MCP returns. |
| Flip/verify a risky keystone flag (multiRoll etc.) before wiring on top | Run a Workflow audit FIRST: N parallel subsystem readers → adversarial verify of blockers → synthesis of go/no-go + edit list. It found multiRoll was ALREADY default-ON with 3 live bugs (bar-1 silence, mute-leak, patch-unwired) that a blind wiring pass would have built on. Audit-first, then single-writer implement the confirmed fixes. |
| Device-only fix that can't run on Linux CI (needs PianoRollModel/AVFoundation) | Extract the DECISION into a pure Foundation enum (e.g. `MultiRollFanout`) the @MainActor class consumes → the bug-fix logic is Linux-CI-tested even though play() isn't. Same pattern as `*Math` view-math splits. |
| Make same-archetype genres rhythmically distinct (founder "die Genres klingen gleich") | Per-genre declarative `MusicStyle.GenreFlavor` (hatDensityBias / a UNIQUE percGhostStep / kickPushEnabled) layered ON TOP of the shared beat-archetype builder via a shared RNG-free `applyFlavorGhost` helper — NOT one builder per genre (avoids 18 near-dup functions). Draws no rng / reads no bio → deterministic, seeded takes stay byte-identical, existing tests unchanged. Put ghost steps on FREE perc slots (offbeat's skank already occupies perc 2/6/10/14). Distinctness is blind-verifiable (unique ghosts) — defer AUDIO-quality value tuning to a founder ear-check. Guard with a `beatArchetype`-derived distinctness test so a future genre without its own flavor fails instead of silently collapsing. Shipped #79 A-D (all 18 melodic genres). |
| Any `.deploy/release` bump (2026-09-02, v434→v437) | **Transcribe `TheDeployNoteNamesRealDoorsTests` claims 2 and 3 in Python BEFORE committing the note** — strip `*`, scan for `X-Chip`/`X-Panel` tokens (letters or `/` before the marker, uppercase first) against the pinned label list, and if the note says „Diagnose-Log“ it must say „Diagnostics“. The guard sat RED on three shipped notes (434/435/436) and nobody saw it, because CI/CD is `failure` on every push (#396) and the job log is `tail -200` (#807) — a blocking guard on a document is invisible exactly where the document is written. Also: `testflight.yml` triggers on ANY change to `.deploy/release` (`paths:`), so a note-only fix IS an Apple upload; fold the fix into the next code slice. |

---

## LEADERBOARD — shipped this run (newest first)

> ⚠ **HISTORICAL SHIPPING RECORD, NOT CURRENT CAPABILITY.** Rows dated before 2026-07-24
> describe surfaces that epics #121 (DAW + video-cut + AUv3 removal), #166/#167 (drums)
> and #178 (piano-roll door) have since removed — clips, the arrange timeline, the note
> editor, the drum kit, AUv3 hosting. They shipped; they are gone. Do not read this table
> as a feature list.

| Version | What shipped | Gates |
|---|---|---|
| (branch, freeze) 2026-07-25 | Founder-Direktiven B+C KOMPLETT (TestFlight-Freeze bis Profi-Milestone → keine TF-Version). **C — kuratierte calm genres:** "Drift" (8ecb58c) + "Contemplation" (3d8e581) erfunden → 8 drum-freie contemplative genres, jedes eigene Anti-Konvergenz-Signatur, Distinct-Tests grün. **B — Flow/Loop:** ComposerMode aus lockBPM abgeleitet (1dfcd90/d5ea5aa, Split-Brain zu) + sichtbarer "Flow \| Loop"-Picker im Freeze-safen CompositionHeaderStrip (866022c, EINE Wahrheitsquelle mit Lock-Button). Reviewer clean. NEEDS-FOUNDER-VERIFY (Klang/Density/Pixel am Gerät) | green |
| v10.79.293 | #23 per-lane SynthPatch KOMPLETT — jede MIDI-Spur eigene Klangfarbe. S1 `TimelineStore.setLanePatch` (+4 Tests) → S2 `.patch(lane)` Editor-Tür (seed+persist die Spur, onApply captured/onDismiss persistiert, dismiss-race-gehärtet) → S2b Primär-Lane `rollPatchSink` bei Region-Load. code+ui-state+audio-thread-reviewer alle CLEAN | green |
| v10.79.292 | Per-note Chance paint-lane — the roll's bottom lane taps Vel⇄Cha; Chance mode paints each note's play probability 0…1 (Ableton note-chance, body bends the threshold live via A4). Model+playback were already built/tested; this added the missing UI (`setChance` mirrors `setMPE`). ui-state-reviewer 0 defects | green |
| v10.79.291 | A7 Audio-Clip-Launch KOMPLETT — Play-Glyph auf Audio-Clips (Performance-Mode), Clip übernimmt Spur + loopt, MIDI+Audio synchron. S3a Override-Lifecycle + Wrap-Re-Trigger (kein stiller Takt am Song-Wrap, Audio im Lockstep mit MIDI) + S3b Glyph-Gate. 3 Reviews sauber, Golden Gate durchgängig | green |
| v10.79.199+ | Founder live redesign (07-14): Bio→header (tap=info), Transpose removed, Immersive Stage→ADM-OSC egress; then the "alles ist still" root cause (roll-slot lane mute/solo gates the generative melody) + a silenced-instrument guard banner with one-tap "Ton an" | green |
| v10.79.198 | BioVariationMaze audition — "Variationen" card in the Comp dropdown: Explore ranks 6 body-curated groove variations, tap one to play it. Shared makeComposerInput builder (no dup logic); generate() gains nil-default seed overrides. No new sheet, no 10 Hz read | green |
| v10.79.197 | rPPG pulse-lock fix — wired RPPGConditioning.linearDetrend into the periodicity estimate (kills the DC ramp that mean-removal leaves) | green (device-verify pending) |
| v10.79.196 | Adaptive home — arrange timeline fills the screen, instrument zone conditional (chip bar idle, dropdowns on demand); killed the black void | green |
| v10.79.195 | Immersive Stage — Touch room-map, each track a draggable spatial object (SpatialSceneStore + ImmersiveStageMath + ImmersiveStageView) | green |
| v10.79.194 | Multi-Roll (tracks play simultaneously) + per-track Record (arm→play→capture MIDI/bio→Clip+region) | green |

## PLAYBOOK (2026-08-30, #897/#898): ein `prefix(N)`-Fenster über Quelltext ist ein LATENTES ROT

**Der Mechanismus — und ⛔ er gilt NICHT für den ganzen Bundle, wie die erste Fassung hier
behauptete (mit #899 zurückgenommen).** Er hängt an `SourceText.codeOnly`: das leert den TEXT
eines Kommentars, **behält aber dessen Einrückung** — es MUSS das, weil mehrere Wächter auf die
relative REIHENFOLGE zweier Treffer prüfen, Zeilen also erhalten bleiben statt gelöscht zu
werden. **Jedes zeichengezählte Fenster wird damit zum Teil in Leerzeichen bezahlt**, und wer
Prosa ÜBER die geprüfte Stelle schreibt, schiebt die Nadel aus dem Fenster. Wer dagegen einen
EIGENEN Streicher benutzt, der die Kommentarzeile ganz löscht (§2 in
`Tests/CISmoke/CLAUDE.md`; wie viele Dateien das heute tun, sagt der Befehl dort — die dort
gedruckte 69 war beim Nachmessen am 2026-08-30 schon **76**), zahlt für einen Kommentar null
Zeichen — dort existiert dieser Defekt nicht.

⛔ **Und die Breite war geraten: hier stand „8–28 Zeichen".** Gemessen an den zwei betroffenen
Dateien (`MIDIOutput.swift` 326 Zeilen, `AudioEngine.swift` 1784): die häufigste Breite einer
geleerten Zeile ist **4**, die Spanne **0 bis 30**. Der Befund überlebt, die Zahl war erfunden —
und mit 4 statt 8 als Modus ist die Umrechnung „Reserve in Kommentarzeilen" doppelt so
optimistisch wie behauptet. Nachmessen heißt: den Streicher über die Zieldatei laufen lassen
und die Einrückungsbreiten der geleert zurückbleibenden Zeilen zählen — der Python-Port des
Streichers liegt in `scripts/window-margins.py`.

**Die Fehlerform ist die schlechteste verfügbare:** der Wächter wird rot auf KORREKTEM Code,
bei UNBETEILIGTER Arbeit, und zeigt auf den falschen Schuldigen. Genau so gefunden — #897s
neuer Anspruch war rot auf seinem eigenen korrekten Code.

**Gemessen, nicht geschätzt:** `python3 scripts/window-margins.py`. ⛔ Hier stand **37** als
Größe der Fehlerfläche und das ist ~2× zu weit — es zählte die SHAPE statt des MECHANISMUS.
Am 2026-08-30 gemessen: die Shape kommt **35**-mal vor, aber nur **16** dieser Stellen stehen
in Dateien, die `SourceText.codeOnly` benutzen, und nur dort greift der Defekt. Beide Zahlen
sind ein DATUM — sie stehen nur, weil der Befehl daneben steht:

```
python3 -c "import re,glob;W=re.compile(r'\[[\w.]+\.\.\.\]\s*\.prefix\((\d[\d_]*)\)');print(sum(1 for p in glob.glob('Tests/CISmoke/*.swift') for m in W.finditer(open(p).read()) if int(m.group(1).replace('_',''))>=100))"
```

⚠️ **Die Ziffern-Gruppierung ist eine Falle, und sie kostet in der schmeichelnden Richtung:**
Swift erlaubt `prefix(1_400)`, also unterzählt ein naives `(\d+)` — es liest „1", verwirft die
Stelle als < 100 und meldete hier **27** statt 35. Deshalb steht `(\d[\d_]*)` im Rezept.

Die zwei mit #898 umgestellten Fundstellen hatten Reserven von **140** und **176** Zeichen.
⛔ „fünf bis zehn Kommentarzeilen bis rot" stand hier und ist gestrichen: die Umrechnung
brauchte die geratene 8–28er-Breite. ⛔ Und die zweite Umstellung (`TheMegaphoneGuard…`) war
mit der FALSCHEN Begründung gebucht — diese Datei hat einen eigenen, zeilenlöschenden
Streicher, der Mechanismus konnte dort gar nicht greifen. Die Umstellung bleibt (ein
Zeilen-Budget ist ohnehin die ehrlichere Grenze), der GRUND ist korrigiert (#167: ein Vermerk
mit widerlegbarer Begründung ist teurer als keiner).

⛔ **UND EIN ENGERES FENSTER KANN EINEN WÄCHTER SCHWÄCHEN — das ist die teuerste Lehre dieser
Reihe und #898 hat sie nicht gesehen.** Ein Fenster versagt in ZWEI Richtungen: zu klein
(rot auf korrektem Code) und zu groß (grün auf kaputtem Code). Bei der MIDI-Umstellung fraßen
die ~272 geleerten Zeichen des alten 300er-Fensters genau den Abstand zu einer ZWEITEN
Fundstelle derselben Nadel (`startIfNeeded()` steht auch in seiner eigenen Deklaration, elf
Code-Zeilen tiefer). Code-Zeilen zu zählen übersprang dieses Polster: der Falsch-GRÜN-Abstand
fiel von ~9 Code-Zeilen auf **EINE**. Reparatur ist nicht „Budget senken", sondern eine
EINDEUTIGE Nadel — dann hält der Anspruch bei jedem Budget (bis 40+ simuliert).

**Reparatur, in dieser Reihenfolge:**
1. **Ein echter ANKER ist am besten** — eine schließende Klammer, der nächste Zweig, der
   nächste Modifier. `range(of:)` auf ihn und bis dorthin schneiden.
2. **Sonst `SourceText.codeWindow(_:from:lines:)`** — zählt CODE-Zeilen und überspringt
   geleerte. Ein Zeilen-Budget ist immer noch eine Schätzung, aber eine über die richtige
   GRÖSSE; Prosa kann die Nadel nicht mehr hinausschieben.
3. **Nie eine neue Zeichenzahl raten.**

**Die 35 übrigen sind eine MIGRATION, keine Scheibe (#460)** — das Skript macht daraus eine
Liste statt einer Jagd.

⚠️ **Die Grenzen des Werkzeugs stehen in seinem eigenen Docstring und sind echt:** es löst
Zieldatei/Anker/Nadeln per Rückwärtssuche auf und schafft heute **5 von 35**; „unresolved"
heißt, das WERKZEUG konnte die Stelle nicht lesen — es ist kein Urteil über den Wächter. Und
eine gedruckte Reserve ist eine OBERGRENZE der Sicherheit, nie ein Beweis: eine interpolierte
Nadel sieht es nicht.

⛔ **Eine Erweiterung, die ich probiert und zurückgenommen habe** (damit sie niemand
wiederholt): die Nadel-Erkennung von `contains(` auf `(?:contains|range\(of:)` zu weiten
machte es SCHLECHTER — 5 gemessen runter auf 4 —, weil `range(of:)` genau die Form ist, in der
ein SPÄTERES Fenster seinen eigenen Anker nennt; die Zusatz-Literale landen außerhalb und
verwandeln lesbare Fundstellen in „Nadel außerhalb des Fensters". **Ein Messwerkzeug, das
weiter greift und weniger meldet, ist nicht gründlicher.**

## PLAYBOOK + DEAD-END (2026-08-22, #734): „settable state ohne Schreiber" ist mechanisierbar — aber NUR auf Klassen

**PLAYBOOK.** Vier Zyklen in Folge fanden dieselbe Form von Hand: ein nicht-privates `var` mit
Default, auf einem lebenden Pfad gelesen, **null Schreiber irgendwo** — ein Schalter ohne
Bedienelement (#724 `breathPlayEnabled`, #727 `isAutomatic`, #730 `ArtNetSender.resolution`,
dazu das schon notierte `inputMonitoringEnabled`). Jeder Fund war ein Zufall und kostete einen
Zyklus. Seit #734 gibt es dafür einen Befehl:

    python3 scripts/doorless-state.py     # ⛔ die drei Zahlen, die hier standen (320/254/35), sind
                                          # GELÖSCHT statt nachgeführt — das Skript druckt sie selbst

Er trägt seine eigene **Bekannt-Positiv-Kontrolle** (heute `isAutomatic` +
`useConvolutionReverb` müssen auftauchen, sonst Exit 2 — ⛔ hier stand
`inputMonitoringEnabled`, und die Kontrolle hatte längst DREI Namen, nicht zwei; die Flagge
ist mit #866 gelöscht, weil genau dieser Detektor sie immer wieder fand. Eine Kontrolle, die
nie in Rente gehen kann, beschreibt das Repo nicht mehr — die Namen sind im Skript zu lesen,
nicht hier) — das Gesetz „ein Detektor, der seinen eigenen bekannten
Positivfall nie gefunden hat, ist keine Messung", ausführbar gemacht.
⚠️ Ein Treffer ist eine **FRAGE**, kein Defekt. Eine DSP-Stellschraube ohne Schreiber ist in
Ordnung; der Defekt ist ein Knopf, dessen Doc einen Benutzer nennt, der ihn nicht drehen kann.

**Klassen-Beschränkung: eine SIGNAL-RAUSCH-ENTSCHEIDUNG, kein „alles Fehlalarme".**
⛔ Die erste Fassung dieses Absatzes behauptete, die Differenz 91→35 sei „fast vollständig
EINE Falsch-Positiv-Familie" (SwiftUI-`View`-Member als memberwise-Init-Parameter). Das ist
um den Faktor fünf überzogen und wurde in der #735-Review nachgemessen. Die 56 Extras sind:
**11** `View`-Member (echte Fehlalarme, `MetalBioView.autoAttuned` & Co.), **22**
`BioUniforms`-Felder, die per **Tupel-Destrukturierung** geschrieben werden
(`(uniforms.cc0r, uniforms.cc0g, uniforms.cc0b) = (…)`) — ein DRITTER Fehlalarm-Mechanismus,
den weder Kopf noch dieser Eintrag kannte —, **1** Enum und **~22 Nicht-`View`-Structs, die
vermutlich echte Treffer sind** (`CrashSafeStatePersistence.artNetEnabled`, `TapTempo.minBPM`,
`VoiceAnalyzer.floorDB`). Die enge Fassung bleibt richtig (#665: ein Prüfer mit Fehlalarmen
wird nicht gelesen), aber aus dem RICHTIGEN Grund: Rauschen, nicht Wertlosigkeit. Eine
Erweiterung ist eine echte Option — sie braucht zuerst den Tupel-Matcher.

⛔ **UND DIE ERSTE FASSUNG DES WERKZEUGS BESTAND IHRE EIGENE KONTROLLE AUS DEM FALSCHEN GRUND
(#735).** Die Bekannt-Positiv-Kontrolle prüfte `isAutomatic` + `inputMonitoringEnabled` und
war grün — während `EchoelDDSP.useConvolutionReverb`, der in FÜNF Dateien als DER türlose
Schalter dokumentiert ist, unsichtbar blieb: `nonisolated(unsafe) static var` lag außerhalb
der Modifikator-Liste. Eine Kontrolle, die den bestdokumentierten Positivfall des Repos nicht
enthält, ist keine Kontrolle. Er ist jetzt drin, die Modifikator-Liste ist geweitet, und die
Kontrolle ist damit aus dem richtigen Grund grün. Mit repariert: ein Fehlalarm (`fronts`, per
`append`/`removeAll` geschrieben — mutierende Methoden fehlten im Schreib-Satz), zwei still
verworfene Gruppen (jetzt als Abschnitte AMBIGUOUS und MASKED), und ein Exit-Code, den ein
`| head` auf 0 wusch.

**Zweiter DEAD-END, teurer:** der erste Entwurf verglich jeden Kandidaten gegen jede Zeile
(O(n²)) und lief nach 560 s nicht durch. Die tragfähige Form ist EIN Durchlauf, der alle
geschriebenen Namen in einen `Counter` sammelt, danach Mengendifferenz — 1,8 s.

## PLAYBOOK (2026-08-20, #639-Zyklus): ein „geht nicht" in einer STILL-OPEN-Liste ist eine BEHAUPTUNG

**Der Fehler.** #639 registrierte die drei nicht erledigten Egress-Pfade und schrieb über zwei
davon: *„Art-Net und sACN tragen DMX-Kanalwerte und haben gar keinen Platz für Metadaten. Das
ist ein echtes ‚geht nicht', keine Auslassung."* Gemessen: ein DMX-Universum hat **512** Slots,
`ArtNetSender.dmxChannels` belegt **vier** (Dimmer + R + G + B), acht bei 16 Bit. **Über 500
sind frei.** Es fehlt eine KONVENTION, kein Platz.

**Warum das teurer ist als eine veraltete Zahl.** Eine STILL-OPEN-Liste ist genau die Zeile, aus
der die nächste Sitzung triagiert. „Auslassung" heißt *bau es*; „geht nicht" heißt *streich es*.
Ein falsches „geht nicht" löscht einen machbaren Posten aus dem Rückstand, und nichts wird je
wieder rot deswegen — es gibt keinen Wächter über einer Behauptung, die niemand bestreitet.
Es ist dieselbe Über-Behauptung, die dieselbe Scheiben-Familie gerade auf vier Flächen abbaut,
nur eine Ebene höher: im Register statt im Produkt.

**Die Regel.** Bevor ein Medium für „trägt keine Herkunft" erklärt wird, wird seine KAPAZITÄT
gemessen (`grep` auf den Sender, nicht die Erinnerung an das Protokoll). Und wenn das Ergebnis
„geht schon, will nur niemand" lautet, gehört genau das dahin — ein schwaches Argument, das
stimmt, schlägt ein starkes, das nicht stimmt.

---

## OBSERVATION (2026-08-20, #638-Zyklus): ein `failed` OHNE Zusicherungstext ist KEIN Befund über den Test

**Was gesehen wurde.** Im CI/CD-Lauf von `9185b6a` (Job 96217411688) steht
`Test case 'TheAutomatableSetHasOneWriterTests.testBrightnessIsAutomatableOnlyWhileItsSentinelIsOutOfRange()'
failed on 'Clone 2 …' (31.849 seconds)` — bei 171 `passed` und diesem einen `failed`. Die fünf
Geschwister derselben Klasse laufen auf DEMSELBEN Clone durch.

**Was gemessen wurde, bevor irgendetwas angefasst wurde.** Alle drei Zusicherungen dieses Tests
transkribiert gegen den Baum, auf dem er lief (`9185b6a`) UND gegen HEAD:
`"bioBaseBrightness > 0"` kommt in `EchoelDDSP.swift` **null** Mal vor (roh wie kommentar-frei),
`public var bioBaseBrightness: Float = -1` steht da, und `ddsp.osc.brightness`s Deskriptor-min
ist 0. **Drei von drei grün.** Die Vorbedingung greift ebenfalls nicht (`automatableBases`
enthält den Pfad, also kein früher `return`).

**Also ist der `failed` keine Aussage über den Test.** Der Job-Log enthält **null** `XCTAssert`-
Text, **null** `error:`-Zeile mit einer Repo-Datei, und die Dauer von 31,8 s ist für einen Test
absurd, dessen ganze Arbeit ein Datei-Read und drei Werte-Vergleiche sind (die Geschwister
brauchen Bruchteile einer Sekunde). Das ist die Signatur einer ABGEBROCHENEN Ausführung, nicht
einer fehlgeschlagenen Behauptung.

**Was daraus NICHT folgt, und das ist der eigentliche Eintrag.** Es folgt nicht „der Test ist
kaputt" und ebenso wenig „alles in Ordnung". Der Log kann die Frage nicht beantworten, und
#445 verbietet, die Antwort aus einem weiteren Lauf zu holen: der überlebende Clone leert eine
NICHT-deterministische Teilmenge, also ist „kommt nicht mehr vor" kein Beleg. In den beiden
Folgeläufen (`64caba2`, `14ae51a`) taucht die Klasse gar nicht auf — was nichts heißt.

**Richtige Reaktion, und sie ist billiger als jede Reparatur:** NICHT den grünen Test
umschreiben. Ein `failed` ohne Zusicherungstext wird notiert und beobachtet. Wer ihn „fixt",
ändert korrekten Code auf Verdacht — genau die Klasse Fehler, die dieses Repo bei #396
dreimal bezahlt hat, als eine rote Conclusion für einen Befund gehalten wurde.

**Diskriminator für den nächsten Treffer** (in dieser Reihenfolge, alles aus dem Job-Log):
1. Steht ein `XCTAssert…`-Text oder eine `…:NN: error:`-Zeile mit einer Repo-Datei dabei?
   Ja → echter Befund, normal behandeln. Nein → weiter.
2. Transkribiere JEDE Zusicherung des Tests gegen den Baum, auf dem er lief (`git show <sha>:…`).
   Alle grün → der Test hat nicht behauptet, was der Verdikt suggeriert.
3. Ist die Dauer um Größenordnungen höher als bei seinen Geschwistern? Dann Abbruch, nicht
   Fehlschlag.
Erst wenn 1–3 nichts erklären, ist es einen Zyklus wert.

## PLAYBOOK (2026-07-18 A7 Audio-Clip-Launch)
- **PLAYBOOK: Song-Wrap-Re-Trigger im GEFALTETEN Frame — der Audio-Twin zu `ClipLaunchEngine.shift`+`tick`.** Wenn eine loopende Override-/Launch-Schicht auf demselben Transport-Tick reitet und der Song am Ende wrappt: NICHT versuchen, den Boundary-koinzidenten Re-Trigger per Sonderfall-Phasenlogik zu erkennen. Stattdessen (1) den Anker mit `-loopTicks` falten (`shift`), (2) die Schicht über den Wrap im GLEICHEN gefalteten Fenster `(lastTick−loopTicks, newTick)` fahren. Dann sind `a=from−since` und `b=to−since` invariant unter dem Fold → `loopWrapped` entscheidet identisch, als wäre die Zeit kontinuierlich über das Song-Ende geflossen (koinzidente Boundary → Re-Fire, überspannendes Segment → bleibt spielen). FALLE: der Wrap-Step wird von `prime` bedient (nicht `apply`); wenn `prime` overridete Lanes überspringt, landet die koinzidente Boundary auf der from-EDGE des nächsten `apply`-Fensters, das `loopWrapped` (halboffen links) NICHT zählt → ein stiller Takt pro Loop. Getrennter Wrap-Pfad nötig.
- **PLAYBOOK: Reviewer-„false confidence"-Lücke = Test trifft nicht den echten Dispatch.** Ein Test, der die PRIMITIVE (`apply`/`shift`) direkt aufruft, kann grün sein, während der ECHTE Pfad (transportStep→`prime` bei Wrap) den Bug hat. Bei jedem „Timing/Dispatch"-Fix einen Test auf dem ECHTEN Eintrittspunkt (transportStep über den Wrap) schreiben, nicht nur die Hilfsfunktion. Der audio-thread-reviewer benannte genau diese Lücke — Reviewer-Findings zu Testabdeckung ernst nehmen, nicht nur zu Code.

## PLAYBOOK (2026-07-18 #23 per-Lane-Patch)
- **PLAYBOOK: per-Lane-Patch = die Pitch-Familie-Spine, ABER mit nil-Asymmetrie.** Patch reist denselben Weg wie Transpose/Detune/Oktaver (TimelineLane.field additiv → TimelineStore.setLaneX → applyRollLaneVoice `rollXSink` primär / slot`XSink` sekundär → EchoelmusicApp-Wiring → voice.apply). ABER: die Pitch-Sinks feuern IMMER mit einem neutralen 0-Default (`?? 0`), Patch NICHT. Ein `SynthPatch?` hat keinen neutralen Wert — nil bedeutet „folge dem geteilten/live-editierten Global-Sound", also muss der Primär-Sink NUR bei non-nil feuern (`if let patch = laneObj?.patch { rollPatchSink?(patch) }`); ein `?? Init`-Default würde bei JEDEM Region-Load den live-editierten Global-Sound auf Init zurücksetzen (Regress). Golden Gate = nil ⇒ Sink nie gerufen ⇒ byte-identisch. Faustregel: ein Feld mit neutralem Wert (0/center) fällt in die IMMER-feuern-mit-Default-Spine; ein Feld ohne neutralen Wert (Patch, Sample-Ref) MUSS non-nil-gated sein.
- **PLAYBOOK: per-Tick-onApply-Hook → capture-in-@State + persist-in-onDismiss.** Ein Editor-Callback (`PatchEditorView.onApply`), der bei JEDEM onChange (Drag-Rate) feuert, darf NICHT direkt `store.setX` (persist) rufen — das flutet die Dokument-Historie/Observation bei ~60/s. Muster: onApply schreibt nur ein billiges Host-`@State` (seed beim ersten Ruf = onAppear captured, latest bei den weiteren); der `.sheet`-`onDismiss` persistiert EINMAL, nur bei `latest != seed` (bloßes Öffnen commitет nichts). Dismiss-race-Parität mit clipEdit: im else-Zweig (Lane-Wechsel) den vorherigen geänderten Patch persistieren, bevor überschrieben wird.

## DEAD-END / PLAYBOOK (2026-07-14 Nacht)
- **DEAD-END: trusting stale Reads after a silent local branch-rewind.** The remote container's local working tree rewound from the branch tip (v212) to an old ancestor (v208) mid-session with a CLEAN `git status`; earlier Read outputs (showing transposeSemitones/EchoelTape) reflected the pre-rewind tree, then grep on the rewound tree found nothing → 20 min of confusion. **DO THIS INSTEAD:** the moment file content contradicts what you just read (a grep finds nothing that a Read showed), run `git rev-parse HEAD` and compare to origin BEFORE re-investigating code. If HEAD ≠ expected, `git fetch origin <branch>` then verify the local HEAD is an ancestor (`git rev-list HEAD --not origin/<branch> | wc -l` == 0 ⇒ no unique local commits) and `git reset --hard origin/<branch>`. Everything pushed is safe on origin.
- **PLAYBOOK: CI-gate visibility can vanish mid-session (GitHub MCP disconnect + no local token + non-interactive = no OAuth).** When it does: (a) git push still works (proxy, not MCP) so deploys continue; (b) rely on the mandatory subagent reviewers (audio-thread/dsp/concurrency/code) as the correctness proxy — they read the actual code; (c) a broken build just fails CI and TestFlight ships nothing (no damage to the existing build); (d) do NOT make blind audio-thread/voice-allocation changes you can't compile-verify — those violate "keine Fehler"; prefer reviewer-fully-verifiable slices (pure value types, mirror-a-shipped-pattern) until gate sight returns; (e) retry MCP each wakeup.
- **PLAYBOOK: per-instrument pitch family = one wiring spine.** Transpose (v210), Detune (v213) both follow: TimelineLane.field (+decodeIfPresent ?? 0) → TimelineStore.setLaneX (clamp) → TimelineDocument.rollSlotX (clamp) → TimelineRegionPlayer slot/rollXSink (fired on region load) → EchoelmusicApp sink wiring (primary→polyVoice, secondary→laneVoiceRack slot) → PolySynthVoice.setX → EchoelPolyDDSP field folded into the ONE noteOn MIDI→Hz exponent → ArrangeTimelineView LaneFX EchoelValueField + rollSlotX onChange (doc-level read = edit-only, freeze-safe) + MultiRollFanout.X(forSlot:) + MultiRollFanoutTests. Oktaver (octave doubler) does NOT fit this spine (it spawns voices, not a frequency offset) — needs its own design + build-verify.

## DEAD-END / PLAYBOOK (2026-07-16 CLIP-3)
- **PLAYBOOK: live-pull equality gates vs. continuously-scrubbed fields.** Any per-step "pull the store's doc and compare" path (mergeMixer, structurallyEqual/refreshStructure) turns EVERY EchoelValueField-scrubbed lane field into a potential ~8 Hz storm: the scrub writes the store on every drag frame, so a field classified "structural" relocates (voice flush + audio-lane restart) for the whole drag. BEFORE building/extending such a gate: enumerate ALL EchoelValueField-bound lane fields (today: level, pan, transposeSemitones, detuneCents) and explicitly assign each to the mixer path (sink-applied live, no reload) or the structural path. The "safe default = structural" rule is right for NEW discrete fields but exactly wrong for drag fields. Sink-applied per-lane voice fields (gain/pan/transpose/detune pattern) always belong in mergeMixer + refreshMixer.
- **PLAYBOOK: AVAudioEngine.connect() wirft NICHT — es RAISED (kAudioUnitErr_FormatNotSupported, uncatchable ObjC).** Jeder neue Verbinde-Pfad für gehostete Units braucht das setFormat-Preflight-Gate VOR attach/connect (effectsAcceptingChainFormat / effectsAcceptingMasterFormat / instrumentAcceptsChainFormat — gegen das Format, das der Pfad WIRKLICH verbindet: Chain ≠ Master). Ein Gate nur auf einem von mehreren Pfaden = Crash wandert zum ungegateten Pfad (AU-1: Lane gated, Browser crashte).
- **TODO-Zyklus (Audio-Review-Advisory PERF-01, vorbestehend N×-verstärkt):** Prime-Attaches unter EINE withGraphPaused-Batch-Pause legen (AudioEngine.swift:807) + attachPlayerNode-Failed-Restart in recoverEngine routen (heute: nur Log, isRunning/degraded bleiben stale, Mix still bis Config-Change). Dazu LOW: Format-Nodes bis Lane-Removal nie gepruned; korrupte Datei nicht memoized (Log-Spam pro Wrap).

## PLAYBOOK (2026-07-16 UX-1)
- **PLAYBOOK: Unterdrückungs-Gate ≠ Claim-Gate — zwei Freshness-Prädikate.** `hasLiveSignal` (schließt `.fallback` aus) beantwortet „darf die UI einen LEBENDEN Körper behaupten?" (grüner liveTag: nein bei Demo). Ein Hinweis/Nag-Unterdrücker („zeige Kamera-verweigert-Banner nur wenn KEINE Quelle liefert") muss dagegen auf ROHES `bus.freshBio() == nil` gehen — die bewusst gewählte Demo zählt als lieferende Quelle. Wer beide Fragen mit demselben Prädikat beantwortet, baut entweder einen Demo-Nag (UX-1 Review-MEDIUM) oder einen lügenden grünen Tag. Bei JEDEM neuen bio-abhängigen UI-Gate zuerst fragen: Claim oder Unterdrückung?
- **PLAYBOOK: Permission-Sackgassen-Muster (wiederverwendbar für Mikro/HealthKit/Bluetooth).** (1) Publisher: `permissionDenied`-Flag, im start()-catch FRISCH vom System gelesen (authorizationStatus — Systemfakt, nie aus dem Error-Typ geraten), nur unter Generation-Guard geschrieben, nach Erfolg geräumt, von stop() unberührt. (2) Typed-Cue-Enum: denied-Case ZUERST in jedem Mapping, actionable. (3) Jede Fläche, die Coaching zeigt, braucht den denied-Zweig VOR dem Coaching — sonst coacht sie Unmögliches. (4) Settings-Tür via bestehendem openAppSettings(). iOS killt die App bei Permission-Wechsel → stale-true über Re-Grant praktisch unmöglich, trotzdem defensiv räumen.

## PLAYBOOK (2026-07-16 Stille-Falle + Keystore)
- **PLAYBOOK: @AppStorage-Divergenz-Detektor.** `grep -rhoE '@AppStorage\("[^"]+"\)' Sources/Echoelmusic --include='*.swift' | sort | uniq -c | sort -rn` zeigt jeden mehrfach deklarierten Key; danach pro Key die Deklarations-Defaults diffen. Jede Mehrfach-Deklaration MUSS durch StudioDefaultKeys laufen (H15-KEYSTORE) — per-Deklaration-Defaults sind eine stille Bug-Klasse (loop 4/8, floating true/false, genre vaporwave/selfObservation waren alle LIVE).
- **PLAYBOOK: Apple-Generator-Falle (AUv3-Hosting).** kAudioUnitType_Generator enthält BEIDES: echte Third-Party-Instrumente UND Apples programmatische File-Player (AUAudioFilePlayer/AUScheduledSoundPlayer), die auf MIDI-Noten nie klingen. Wer Generatoren als Instrumente listet, braucht den Apple-Manufacturer-Filter ('augn'+'appl' → raus), sonst ist ein Tipp = stumme Spur. Persistenz verdoppelt die Falle: App-State (UserDefaults-Record) beim Start HEILEN (Record entfernen + sichtbare Notice — Retention-Gesetz gilt transienten Failures, nicht unmöglichen Instrumenten); Nutzer-DOKUMENT-Refs (TimelineLane.instrument) dagegen NIE beim Laden beschneiden — nur die Hosting-Entscheidung filtern (wanted()-Guard), das Ref bleibt ehrliche Daten. Foundation-only-Schichten brauchen die FourCCs als Literale (0x6175676E/0x6170706C), AudioToolbox fehlt auf Linux.
- **PLAYBOOK: Founder-Screenshot = Diagnose-Gold.** Der Stille-Report wurde ohne Log lösbar, weil die Screenshots die Instrument-Liste (Falle sichtbar) UND den Audio-Fader auf 0.00 zeigten. Bei Geräte-Reports zuerst jedes UI-Detail der Screenshots gegen den Code lesen, dann erst nach Logs fragen.
| 2026-07-16 | PLAYBOOK | SwiftUI-Drag-Jitter-Klasse: eine Geste, deren Live-Delta die LAYOUT-Geometrie des eigenen Hosts ändert (.frame(width:) am trailing-alignten Handle), oszilliert im Default-.local-Raum (r(n+1)=d−r(n), Kante vibriert bei ruhendem Finger). Fix-Muster: DragGesture(coordinateSpace: .named(<stabiler Grid-Raum>)). Render-Transforms (.offset) sind immun — nur Layout-Änderungen füttern zurück. | AUDIT_CLIP_JITTER C1, b35fffa |
| 2026-07-16 | PLAYBOOK | Drag-Deltas in Leaf-Views IMMER @GestureState, nie @State: ScrollView-Arbitration CANCELT Gesten ohne onEnded → @State-Deltas bleiben als Geister-Versatz stehen. @GestureState auto-resettet bei Abbruch; Emphasis-Bools ableiten (delta != 0), nicht separat speichern. | AUDIT_CLIP_JITTER C2, b35fffa |
| 2026-07-16 | DEAD-END (vermutet, device-gated) | .highPriorityGesture auf dem Clip-Body NACH den Handle-Overlays: Parent-High-Priority kann Subview-Gesten (22-pt-Trim-Griffe, device-verifiziert) aushungern. Nicht blind shippen — erst Founder-Recording, dann ggf. Anbringung UNTER den Overlays testen. | AUDIT_CLIP_JITTER C3 |
| 2026-07-17 | PLAYBOOK | Continuation mit non-Sendable ObjC-Objekt (AVAudioUnit) NIE roh resumen — CheckedContinuation.resume ist `sending`, Completion-Handler-Param ist task-isoliert → Swift-6-Compile-Fehler. IMMER @unchecked-Sendable-Box (AVUnitBox-Muster, AUv3Host). Reviewer sagte den exakten CI-Rot voraus (984d68c), Box-Fix (0fd183f) heilte ihn — adversarialer Concurrency-Review VOR dem Gate spart einen ganzen Zyklus. | AUv3Host.swift instantiate |
| 2026-07-17 | DEAD-END | Timeout für nicht-cancelbares await via withThrowingTaskGroup — die Group AWAITET ihr hängendes Child beim Scope-Exit, der Hang zieht nur um. Stattdessen: Completion-Handler-API + Exactly-Once-Gate (ResumeOnce). | AUv3Host.swift |
| 2026-07-17 | PLAYBOOK-BESTÄTIGUNG (10.76.50-Klasse, 2. Fund): Beim Einbau eines popover-hostenden Controls (Menu/Picker) reicht "Subtree ist clean" NICHT — IMMER den Ancestor-Body auditieren (computed vars sind KEINE Observation-Grenze; hier: Roll-Playhead las currentStep im Body → Q-Menü wäre beim Spielen sofort zugeklappt). Grep-Kandidaten: currentStep/waveform/detectedBPM/position in jedem View-Body zwischen Root und Menu-Host. |
| 2026-07-17 | PLAYBOOK (Test-Diskriminierung): Bei SKALENINVARIANTEN Metriken (normierte Kreuzkorrelation, Cosine-Similarity) beweist ein skalierter-Kanal-Test (R=0.5·L) NICHTS über geteilte vs. unabhängige Verarbeitung — FP-exakte Skalare (Zweierpotenzen) machen die Pfade bit-identisch. Diskriminierender Guard: SUPERPOSITION mit verschieden-inhaltlichen Kanälen (Sinus+Klick-Zug) + Linearitäts-Identität (Kanal-Summe == Verarbeitung der Summe). Vor jedem "würde unter altem Code brechen"-Claim: beweisen, dass er es täte. |
| PLAYBOOK | 2026-07-17 | Xcode-Type-Check-Timeout (exit 65 "unable to type-check in reasonable time") kann FLAKY sein: identischer Swift-Stand grün auf einem Runner, rot auf dem nächsten — der Ausdruck sitzt AM Limit. Nicht die letzte Änderung verdächtigen (die kann in einem ANDEREN Struct liegen); der genannte Ausdruck selbst ist das Problem. Fix = die schweren Closures (contextMenu, Overlays, Tap-Handler) in benannte private Helfer extrahieren, Kette behalten, Inhalte verbatim. RegionBlockView 75adb7d. |
| DEAD-END 2026-07-17 | Baustellen-#4-Idee "Default-Route Kohärenz→Tempo in ModulationMatrix seeden" | Tempo folgt dem Körper BEREITS über den Compose-Pfad (Body-Seed + Konvergenz pro Evolve-Tick, octave-gefaltet, trust-gated, glideTempo — EchoelStudioView ~3739ff). Eine Default-Route wäre ein ZWEITER kontinuierlicher Tempo-Treiber (100-ms-Tick gegen Evolve-Konvergenz) = "bpm springt"-Klasse. | Stattdessen: Wert von #4 liegt allein in der Route-EDITOR-Tür (frei wählbare NICHT-Tempo-Ziele + /mod-OSC); Tempo-Ziel nur, wenn der Compose-Pfad-Treiber dabei explizit deaktiviert wird. |

## PLAYBOOK (2026-07-18 A5 Face-Expression)
- **PLAYBOOK: additive enum-Case → ALLE exhaustiven Switches über den Enum-Typ sweepen (no-`default` = CI-Break).** Einen `ModSource`-Case anhängen brach nicht nur den Home-Switch, sondern `FXModCarrier.displayName` (Core/FXModulation.swift) — ein exhaustiver `ModSource`-Switch OHNE `default`, eine Datei-Ebene entfernt. Vor dem Commit: `for f in $(grep -rln "<EnumTyp>" Sources/ | grep -v Tests); do grep -qE "case \.<einSichererFallwert>" "$f" && echo "$f"; done` → jede Datei prüfen ob sie all-cases ODER `default` hat. Für `BioSource` sind es DREI (EngineBus staleness, BioStripView label, BioEgressPolicy) — additive Case dort = 3 Pflicht-Zeilen. Cases IMMER am Ende anhängen (rawValue/CaseIterable-Reihenfolge + persistierte Routen bleiben stabil).
- **PLAYBOOK: Kamera-Bio-Quellen sind schon gegenseitig-exklusiv — kein neuer Arbiter.** rPPG/BLE/Sim laufen über das Single-Active-Source-Modell (`BioSourceKind` enum + `selectBioSource` stop-alt/start-neu). Eine ARKit-Front-Face-Quelle ist bloß ein weiterer `BioSourceKind`-Case; die ARSession-vs-AVCapture-Kamera-Exklusivität fällt gratis aus dem Modell. Publisher-Slice = neuer Case + capability-Gate (`ARFaceTrackingConfiguration.isSupported`), NICHT ein eigener Kamera-Schiedsrichter.
- **PLAYBOOK: un-testbaren Device-Code (ARKit/AVCapture) mit einem pure Core-Kontrakt vorbereiten.** Vor dem ARKit-Publisher zuerst die reine Zuordnung (blendShape-Keys → Kanäle) als `static func` in Core festschreiben + testen; der Geräte-Publisher wird dann dünner Adapter (Dict bauen → pure func → EMA → bus). So bleibt das Un-CI-Verifizierbare minimal.

## PLAYBOOK (2026-07-18 A1 R2 Chord-Stamp)
- **PLAYBOOK: eine neue Roll-Aktion = Modus-Toggle, NICHT eine neue Geste.** Der Roll-Canvas hat EINE `DragGesture(minimumDistance:0, .named("roll"))` mit einer `drag`-State-Machine (`.create`/`.move`/`.resize`/`.marquee`/`.groupMove`), am Touch-Down per `RollHitTest.classify` entschieden; ein Tap = `.create` das in `onEnded` überlebt. Eine LongPress-Geste DANEBEN zu setzen = Arbitrierungs-Hölle (0-Distanz-Drag gewinnt) + Freeze/Hang-Risiko. STATTDESSEN: ein `@State`-Bool-Toolbar-Toggle, und im bestehenden `.create`-onEnded-Zweig `else if mode { … }` — Tap-Erkennung identisch, null neue Geste. So gebaut für Chord-Stamp (v290).
- **PLAYBOOK: Live-Bio in einer Roll-Aktion = One-Shot im onEnded/Handler, NIE im Body.** Vorlage `PianoRollModel.bioHumanize`/`stampChord`: `bus?.usableBio()?.coherence` wird genau EINMAL beim Tap gelesen (in der Model-Methode, aus `onEnded`), nie in einer body-ausgewerteten var. Der Modus-Bool im Chrome ist ein reiner Bool-Read (kein @Observable-Bio) → Freeze-Gesetz gewahrt. `@discardableResult`, `snapshotForUndo()` genau einmal vor dem `append` = EIN Undo-Schritt.
- **PLAYBOOK: Chrome-HStack-Kinder >10 sind ok (buildPartialBlock aktiv, Swift 5.7+).** Das alte 10-Kind-ViewBuilder-Limit gilt nicht mehr; die Roll-Chrome hatte schon 11 und kompilierte. Ein weiterer Toolbar-Button ist sicher — solange er in einer computed `transport`-Property in einem `ScrollView(.horizontal)` sitzt (nicht im Root-`body`, wo das Metadaten-Budget/die Sheet-Decke zählt).

## PLAYBOOK (2026-07-18 Sync-Egress + Modulation-Spine Session)
- **PLAYBOOK: "completed"-Task/REIHENFOLGE-Item ≠ Feature vollständig — grep die ECHTEN Consumer bevor du baust.** Item 2 "Bio-Modulation live sichtbar" war als Task #3 "completed", ABER `grep -rn "modulationEngine\.\|\.lastOutputs\|\.orderedOutputs" Sources/…/Studio` zeigte: KEIN View liest die Control-Plane-Modulations-WERTE (nur FX-Bio-Mod hatte eine UI; BioSourceView zeigt statischen Prosa-Text). Der "done"-Task betraf ein ANDERES Subsystem. Vor jedem "item-N"-Bau: grep, wer die relevante Engine-Live-Werte tatsächlich rendert — nicht dem Task-Status glauben.
- **PLAYBOOK: additive golden-gate-Primitiv auf einem Codable-Value-Type (ModRoute-Muster).** Neues Feld (`inputLow/inputHigh` Sensitivity-Window) mit Identity-Default (0/1) → byte-identisch für alle bestehenden Routen + persistierte Docs. Rezept, exakt wie `curve`/`smoothingTau` es vormachen: (1) Feld + Default im custom init, (2) `clamp` im init UND im decode, (3) CodingKeys-Case, (4) `decodeIfPresent ?? default` im custom `init(from:)` (encode bleibt synthetisiert), (5) Test der pre-Feature-JSON via Dict-Key-Strippen dekodiert auf Identity. Golden-gate-Test = Identity-Window liefert output byte-identisch (base ist schon [0,1], also `clamp01((v-0)/(1-0))==v`).
- **PLAYBOOK: BioEgressPolicy = Call-Site-Gate am `else if let frame = bus.latestBio`-Zweig, keine neue Abstraktion.** Art-Net/sACN waren die letzten 2 ungegateten Netz-Bio-Konsumenten; Gate = `, BioEgressPolicy.allowsEgress(frame.source)` an der bestehenden Branch-Condition (spiegelt OSCSender:133/ADMOSCSender:178). Nebenwirkung fürs Licht: der Egress-Filter VERBREITERT die No-Source-Menge → eine L1-Blackout-Kante (früher `return` überspringt master/slew). Fix = letzte ROH-Farbe halten (`lastChannels`/`lastTarget`, pre-master) + master/slew weiterlaufen lassen; gehaltene Kanäle stammen immer aus erlaubter Quelle (gegateter Frame erreicht den Store nie) → kein Rest-Egress. Bounded: held-Branch nutzt unveränderten Timestamp → sendet nur bei masterMoved (one-shot) ODER slewSettling (endet).
- **DEAD-END-BESTÄTIGUNG (verstärkt 2026-07-18): kein Default-Modulations-Route/Window blind seeden UND kein Item-2-Readout-Leaf ohne Gerät.** ModulationEngine hat per Default KEINE aktiven Routen (Tempo läuft über den Compose-Pfad, s. Dead-End 2026-07-17) → ein `lastOutputs`-Readout ist leer bis der User im Route-Editor Routen anlegt. Also: (a) AU2-Sensitivity-Window ist korrekt ein EDITOR-Primitiv (kein Auto-Seed), (b) der Item-2-Leaf-View ist erst wertvoll NACH dem Route-Editor + zeigt sonst "nichts aktiv" → nicht blind bei voller Device-Queue bauen. Leaf-Pattern existiert (PulseMonitorMiniLive/BioStripView, eigener Body liest 10 Hz) — der Bau ist trivial, aber Platzierung/Wert sind gerät-gated.
  ⭐ **NACHTRAG 2026-08-30 (#885): dieser Eintrag und der PLAYBOOK zwei Zeilen darüber messen die MODULATIONS-MATRIX (`lastOutputs`) — und sind darin unverändert richtig. Punkt 2 der REIHENFOLGE meint aber AUCH die IMMER-AN-Kanäle (`AlwaysOnBioChannel`), und die sind seit #553/#634/#643 gebaut, zweifach betürt und von 29 Wächtern gehalten. Nicht aus diesen zwei Zeilen schließen, Punkt 2 sei offen — siehe den #885-Eintrag am Ende dieser Datei.**
- **PLAYBOOK: bei voller Founder-Device-Queue + reiner CI-Umgebung — Spine/Pure zuerst, Blind-UI NICHT stapeln.** Muster dieser Session: pures Editier-Gehirn (`ClipAutomationEdit`) + Store-Mutation (`setClipAutomation`) + Observable-Snapshot (`lastOutputs`) + math-Primitiv (`inputLow/High`) sind alle CI-verifizierbar + reviewer-fest; die dünnen SwiftUI-Schalen (Canvas, Readout, Knopf) sind der gerät-verifizierte Rest. Wenn ALLE nächsten Slices UI/feel-gated sind und die Queue voll ist: ehrlich HALTEN + Ledger/Log pflegen statt eine 6. unverifizierbare Fläche zu stapeln (Founder-Direktive "verify-first, nicht Blind-UI stapeln").

## PLAYBOOK (2026-07-18 Per-Track-Automation-Seam L2/L4)
- **PLAYBOOK: per-Spur-Targeting = String-Namensraum + Dispatch-Zeit-Resolver, KEIN Player/Model-Refactor.** Der Automations-Router (`ParameterApplyRouter`) ist string-getrieben und `AutomationPlayer.dispatchLane` routet UNBEKANNTE keyPaths unverändert durch → eine Spur wird adressierbar, indem die laneID in den keyPath gefaltet wird (`track.<laneID>.ddsp.filter.cutoff`), OHNE `AutomationLane`/`TimelineDocument`/Player zu ändern. Reine Scheiben, alle Linux-CI: (S1) `PerTrackParameterKeyPath` make/parse — die UUID hat keine Punkte, also endet der ERSTE Punkt nach dem `track.`-Präfix die id, Base mit Punkten roundtrippt; (S2a) `MultiRollFanout.slot(forLaneID:)` = Invers von `laneID(forSlot:)`, Guard `rank < capacity`; (S2b-prep) `PerTrackAutomationResolver.resolve()` komponiert parse+slot+denormalize → `Resolved(slot,base,value)?`. Nur die Setter-Zuordnung (base→`LaneVoiceRack`-Slot-Methode) + Descriptor-Registrierung bleiben gerät-gated.
- **PLAYBOOK: Slots sind rang-instabil zwischen Plays → laneID→slot NUR zur Dispatch-Zeit auflösen, nie bind-zeitig cachen** (`MultiRollFanout.swift:114-115`). Der Resolver nimmt daher das LIVE-`document` als Parameter und löst pro Step auf; fehlende/fremde/überzählige Spur = `nil` = stiller No-Op (nie Fremd-Slot-Write). Alle No-Op-Fälle im PUREN Resolver gepinnt, damit die Geräte-Schale dem Non-nil-Ergebnis vertrauen kann.
- **PLAYBOOK: pro-Lane-Descriptor = Klon des globalen Katalogs mit namespaced keyPath, Range GEERBT.** `PerTrackParameterKeyPath.descriptors(for:laneLabel:from:DDSPParameterCatalog.descriptors)` erbt min/max/unit/default verbatim (dieselbe Engine-Param, nur pro Spur adressiert) + Spur-Tag im displayName fürs Picker-Unterscheiden. Denormalisierung im Resolver nutzt die BASE-Range → Wert-Mathe identisch zum globalen Pfad.

## PLAYBOOK (2026-07-19 reiner Bug-Hunt: max(by:)-Tie-Falle)
- **PLAYBOOK: `Sequence.max(by:)` behält bei GLEICHSTAND das ERSTE Maximum, nicht das letzte.** Wenn ein „latest/top-most wins"-Kontrakt über placement-order (append = neueste zuletzt) definiert ist, gibt `max(by: { $0.key < $1.key })` bei gleichem key das ÄLTESTE Element zurück = Bug. Fix = Tie-Break über Array-Position: `.enumerated().max(by: { ($0.element.key, $0.offset) < ($1.element.key, $1.offset) })?.element` — der eindeutige offset macht die Ordnung zu einer strikten Totalordnung, damit gibt es nie zwei gleich-maximale Tupel und die First-maximal-Falle greift nie. Gefunden in `TimelineScheduling.activeRegion` (818872c): überlappende Regionen mit gleichem startTick (Clip auf Clip an derselben Takt-Grenze, häufig bei Grid-Snap) spielten den alten statt obersten Clip. Live-Playback-Pfad (activeRegion→activeLoads/laneEvent).
- **PLAYBOOK: reiner Bug-Hunt als Zyklus-Punkt, wenn alle Feature-Slices device-gated sind.** Ein fokussierter Agent über 5 reine, ausgelieferte Kern-Dateien mit STRIKTEM Auftrag („nur EIN Fund mit konkretem failing-input, sonst ehrlich nichts") liefert Standalone-Wert (echter Fix, CI-verifiziert) statt Blind-UI zu stapeln. Der Agent gab 4 Dateien explizit frei + 1 belegten Bug — kein erfundener Marginal-Fund. TDD: failing-Test zuerst, dann die Ein-Zeilen-Korrektur.

## PLAYBOOK (2026-07-19 drei Bug-Hunt-Fixes + Foundation-Timing)
- **SHIPPED (3 echte Korrektheits-Fixes aus reinen Bug-Hunts, alle TDD + reviewer-clean + Gates grün):** (1) `TimelineScheduling.activeRegion` max(by:)-Tie → obersten Clip bei gleichem startTick (818872c). (2) `PatternEngine.setTempo` Swing-Paritäts-Inversion für den Schritt nach Mid-Play-Tempoänderung → eine pure `swingGap`-Quelle für advance+setTempo (d79c183). (3) `SpatialScene.diff/apply` konvergierte nicht auf Objekt-Reihenfolge (ADM-Index-Divergenz) → additives `order`-Feld (2630d15).
- **PLAYBOOK: latente Foundation-Bugs fixt man am besten SOLANGE es keine Consumer gibt — null Migrationsrisiko.** SpatialScene (P2, diff/applying nur in Tests) verletzte seinen eigenen dokumentierten+getesteten Konvergenz-Kontrakt. Grep der Consumer (`grep -rn "\.diff(from:\|\.applying(" Sources/` außer der Datei selbst) = LEER → der Fix (additives Wire-Feld) ist bit-sicher, kein deployter Peer, kein Schema-Major-Bump. Regel: bei einem Foundation-Bug ZUERST Consumer greppen; keine → jetzt fixen ist billiger als nach dem ersten Consumer.
- **PLAYBOOK: additives Wire-Protokoll-Feld = optionales `let` + synthetisiertes Codable, KEIN custom init.** `order: [String]?` decodiert absenten Key automatisch zu nil (Swift `decodeIfPresent` für Optionals) → Legacy-Payload = pre-Feature-Verhalten. isEmpty muss das neue Feld einschließen (`&& order == nil`), sonst meldet eine reine Umsortierung fälschlich „empty" = wird nicht gesendet = Divergenz. Und: das Feld nur tragen wenn es abweicht (schlanke Diffs, identische Szenen bleiben isEmpty).

## PLAYBOOK (2026-07-19 Hochwert-Pfad-Audit statt 5. Marginal-Jagd → HALTEN)
- **DEAD-END-VERMEIDUNG: nach 4 gelieferten Bug-Fixes NICHT blind eine 5. immer-kleinere Jagd stapeln — stattdessen den EINEN höchst-konsequenten erreichbaren Pfad gezielt auditieren, dann ehrlich das Ergebnis melden.** Ziel gewählt: der LIVE bio→audio Mono-Pfad (`BioReactiveSynthVoice` hostet `EchoelDDSP` [mono, nicht `EchoelPolyDDSP`]; läuft jede Session, Audio-Thread, von echter Physiologie getrieben — die höchste Konsequenz im ganzen Code). **Befund: ROBUST, kein Bug.** Warum sauber: (a) jeder Input am Enqueue geclampt (`clampUnit`, `hrNormalized = clampUnit((bpm-40)/160)`, `BioReactiveSynthVoice:323/330-339`), (b) jeder Output im Mapping geclampt (`.clamped(to:)` brightness/harmonicity/reverb; `Swift.max(0,…)` noise; cutoff/amplitude durch beschränkte Inputs beschränkt, `EchoelDDSP:1255`), (c) `clampUnit` ist NaN-sicher (Task #29 shipped) → kein NaN erreicht den Spektral-Rewrite, (d) nur Konstant-Divisoren (`/60.0`,`/12`) → keine Division-durch-Null, (e) `_lfoPhase`-Inkrement ≤0.042 → einzelnes `-= 1.0` Wrap genügt. **Regel: „kein Bug gefunden" bei einem verifiziert-robusten Hochwert-Pfad IST das ehrliche Ergebnis — nie einen Marginal-Fund erfinden, um Bewegung vorzutäuschen. Wenn der Top-Pfad sauber ist und alle Feature-Slices device-gated sind: HALTEN + Ledger pflegen, nicht grinden** (deckt sich mit der verify-first-Direktive + dem 2026-07-18 „nicht Blind-UI stapeln"-Playbook).

## PLAYBOOK (2026-07-19 Ultra-Audit "bau alles richtig zusammen" — Founder-Vollmandat)
- **BEFUND (multi-agent audit wf_6d5f3235-672, adversarisch verifiziert): fast ALLES ist verdrahtet.** AUv3-Hosting (roll + per-lane), Audio-Lanes klingen, per-Spur-SynthPatch, Warp, transport-synchrones Video, Piano-Roll — alle CONFIRMED funktional. Der EINE vom Founder genannte Bruch „funktionierende AUv3" lokalisiert komplett auf den ERSTEN Hop: Discovery liefert leere Liste auf Gerät (`registryColdForProcess`) — OS/Registrierungs-Grenze, KEINE kaputte Swift-Zeile, der ganze Downstream ist dead-on-arrival aber korrekt. Regel: bei „Feature X funktioniert nicht" IMMER erst die Kette end-to-end tracen (Discovery→UI→attach/connect→MIDI) — der Bruch war Hop 1, alles danach war fälschlich verdächtigt.
- **SHIPPED C2 (5af94ac): AUv3-Cold-Registry-Diagnose founder-sichtbar.** Der Self-Probe (INSTANTIATE OK vs FAILED) schrieb nur ins Breadcrumb; jetzt pure `AUv3ScanDiagnostic` (Zähler + Probe-Verdikt + `guidance`, unit-getestet off-device) → `AUv3Host.diagnostic` publiziert → Browser rendert `guidance` bei kalt. Nächster Build diskriminiert stale-LIST (quit+reopen) vs. unregistered-appex (reinstall) OHNE Log-Pasten. Einen Geräte/OS-Boundary-Bug bringt man nur voran, indem man ihn instrumentiert.
- **DREI VERMIEDENE FALLEN (Blind-Bau-Disziplin > Bewegung vortäuschen):** (C1) toten `showVisual`-VJ-Cover NICHT gelöscht — er ist funktional-aber-türlos (Fullscreen-VJ + Visual-mp4-Recording + Spectral-Donut), Löschen = Feature-Verlust; und die Metadata-Ketten-Begründung des Boards war widerlegt (Cover ist lazy, `EchoelStudioView:711`-Kommentar). Feature-formend → geparkt für Founder. (C3) Item-2-Readout-Leaf NICHT gebaut — ModulationEngine hat per Default keine Routen (leer) UND das natürliche Zuhause `BioSourceView` ist tot (`grep BioSourceView(` = NULL Konstruktor). (C4) per-Spur-Cutoff-Write NICHT blind verdrahtet — der globale Pfad nutzt `setCutoffScale` (Skalar ~0–1), die Registry-Descriptor „ddsp.filter.cutoff" liefert Hz (20–18000): Einheiten-Mismatch, 18000 in einen 0–1-Skalar = Bug. base→per-slot-Setter+Einheiten ist echt gerät-gated (Board markiert). Regel: wenn der CI-verifizierbare Kern eine unverifizierbare Korrektheits-Annahme (Einheiten/Range/Zuhause) enthält → NICHT blind, das ist gerät-gated.
- **SHIPPED C6 (d1e9d9f): zwei lügende Kommentare korrigiert** (VideoClipView „playback follows later" → spielt schon via FloatingVideoMonitor; AudioLanePlayer „nothing calls it" → seit v191 verdrahtet). Ehrlichkeit = Teil von „vermeide unfunktionierende Sachen".
- **PLAYBOOK: Founder-„bau alles"-Vollmandat + reine CI + fast-fertige App → der ehrliche Output ist Audit + die 1–2 echten CI-Wins + präzise Karte der gerät-gated/feature-formenden Reste, NICHT ein Stapel riskanter Blind-Nähte.** Fallen vermeiden ist Arbeit. Die device-gated Reste (S2b base→setter Einheiten, Item-2-Zuhause, VJ-Re-Door, Face-Cam Info.plist, C5 Stage-Recorder-UI) brauchen ein Founder-Device-Greenlight ODER eine Feature-Entscheidung — das gehört ins Status-Delta, nicht blind gebaut.

## PLAYBOOK (2026-07-19 Fortsetzung: C7/C8 „getestetes pures Ding → erreichbare Fläche")
- **PLAYBOOK: der sauberste nicht-blinde CI-Punkt, wenn die App UI-reif ist = einen bereits GETESTETEN puren Typ OHNE Consumer in eine ERREICHBARE Fläche rendern.** Kein Korrektheits-Blindflug (Logik ist getestet), nur Kosmetik gerät-gated. Zwei geliefert: **C7 (8da6abf)** `LaneInstrumentLabel.summary` (getestet, 0 Consumer) → Spurkopf-Belegung „EchoelDrums · 1 FX" (item 3; vorher nur binäres Puzzle-Icon, Builtin-Name nie sichtbar). **C8 (680595d)** NEU `BioSoundMapping` (pures Routing HR→Vibrato/HRV→Reverb/Kohärenz→Filter/Atem→Filter, getestet + reviewer-verifiziert gegen applyBioReactive) → Sektion „How your body shapes the sound" im ERREICHBAREN `BioMetricsGuideView` (item 2, tap-to-learn am Bio-Strip).
- **PLAYBOOK: erreichbares Zuhause ZUERST greppen (`grep -rln "XView("`), bevor man dort rendert.** Item 2 schien zunächst tot, weil das natürliche Zuhause `BioSourceView` NIRGENDS konstruiert wird (0 Consumer = tote View). Der erreichbare Weg war `BioMetricsGuideView` (Sheet aus `BioStripView`-tap-to-learn, das SEHR WOHL in EchoelStudioView lebt). Regel: das „richtige" Zuhause kann tot sein — grep die tatsächlichen Konstruktor-Aufrufe, nicht dem Namen/der Absicht vertrauen (deckt sich mit dem 2026-07-18 „grep die ECHTEN Consumer"-Playbook).
- **PLAYBOOK: statischer Design-Fakt-Readout schlägt Live-Snapshot-Readout, wenn der Snapshot per Default leer ist.** Item 2 „welche Params bewegt Bio" hätte über `ModulationEngine.orderedOutputs` (leer bis User Routen anlegt, @Observable → 10-Hz-Freeze-Risiko) gebaut werden können — STATTDESSEN das STATISCHE Routing (immer wahr wenn armiert, kein Live-Read, kein Menü-Freeze-Gesetz, driftfrei weil es Routing nicht Koeffizienten kodiert). Bei „zeig welche Params X bewegt": bevorzuge die stabile Design-Karte vor dem leeren Live-Snapshot.
- **ERSCHÖPFT (diese Burst): das C7/C8-Muster ist gemint.** Verbleibende 0-Consumer-Typen: `PerTrackAutomationResolver` (Einheiten-gated C4 — setCutoffScale-Skalar vs Registry-Hz), `LyricsModel` (ganzer Vokal-Feature-Scope, gerät-gated). Board-Reste alle gerät-gated/feature-formend. Nächster nicht-blinder CI-Punkt braucht ein Founder-Device-Signal ODER eine Feature-Entscheidung — nicht blind weiterstapeln.

## PLAYBOOK (2026-07-19 Bio-Input-Korrektheit-Audit → CLEAN)
- **AUDIT CLEAN (dsp-reviewer, striktes Ein-Bug-oder-nichts-Protokoll): `HRVCoherence.swift` (Lomb-Scargle + Welch) + `HRVMetrics.swift` (RMSSD/SDNN/pNN50) sind numerisch solide — KEIN Bug.** Warum sauber: jeder Divisor gegated; leere/singleton/kurze RR-Arrays → sichere Defaults (tachogram ≥16→nil, reading total>0-Guard, metrics count≥2→0); Einheiten durchgehend konsistent (ms/s→Hz); **Kohärenz = peakBand/total ist ein SKALEN-INVARIANTER Leistungs-Quotient** → die willkürlichen LS/Welch-Normalisierungen (norm=fs·Σw²) kürzen sich raus und können den publizierten `coherence` nicht verfälschen. Einzige Asymmetrie: HF-Kante `<0.40` schließt den exakten 0.40-Grid-Bin aus während `total` ihn einschließt → betrifft NUR `hfPower`/`lfHfRatio` um einen Rand-Bin, NICHT `coherence` (eigener korrekter Nenner) = verteidigbare Endpunkt-Konvention, kein reproduzierbarer Fehlwert.
- **NICHT re-hunten:** bio→audio Mono-Mapping (2026-07-19 clean), HRVCoherence+HRVMetrics (clean). Zusammen mit den 4 gefixten Bugs (activeRegion/swing/SpatialScene/MIDI-Tempo) sind die reinen Hochwert-Pfade jetzt breit auditiert; weitere Hunts wären marginal.

## PLAYBOOK (2026-07-19 AUv3 −3000 Device-Log-Triage → Quelle vollständig ausgeschlossen)
- **BEFUND (Founder-Device-Log v296/2403): `auv3 self-probe: FAILED NSOSStatusErrorDomain#-3000` — sogar der EIGENE Appex ist auf dem Gerät nicht registriert.** Die C2-Diagnose (v296) hat exakt geliefert, wozu sie gebaut wurde: sie diskriminiert den Zweig. −3000 = invalidComponentID = pluginkit hat die Komponente NICHT registriert (Registrierungs-Ebene, VOR Instanziierung).
- **QUELLE VOLLSTÄNDIG AUDITIERT + AUSGESCHLOSSEN (nicht-blind, alles CI/lokal geprüft):** (1) AudioComponents-Deklaration `manufacturer Echo / type augn / subtype echl` unter `NSExtension→NSExtensionAttributes` — korrekt in project.yml (Quelle) UND committed Info.plist (byte-identisch), matcht die Host-Probe (`augn/echl/Echo`) exakt. (2) Entitlements: App-Group `group.com.echoelmusic` ✓. (3) Principal-Class `AudioUnitViewController: AUViewController` existiert ✓ + `EchoelmusicAudioUnit`-AUAudioUnit ✓. (4) App-Target bettet den Appex ein (`- target: EchoelmusicAUv3`), Bundle-ID `com.echoelmusic.app.auv3` ✓. (5) testflight.yml archiviert `-scheme Echoelmusic` (enthält den AUv3-Dep) mit `-allowProvisioningUpdates` + Automatic-Signing, Build 2403 success. → Appex ist korrekt deklariert/eingebettet/archiviert/signiert.
- **VERDIKT: −3000 ist KEIN Quellcode-Bug — es ist iOS-pluginkit-Registrierung auf dem Gerät.** Fix = **VOLLER Geräte-Neustart** (aus/an, NICHT App neu öffnen — App-Restart triggert keine Extension-Re-Registrierung). Falls persistent nach vollem Restart: per-Gerät-Provisioning (das Test-Gerät muss im Dev/TF-Profil sein) bzw. Archiv-Embed im echten IPA prüfen. **Regel: bei −3000 für den EIGENEN Appex zuerst die 5 Quell-/CI-Punkte greppen (Deklaration/Attributes-Nesting/Entitlements/Principal-Class/App-Embed+Archive-Scheme); sind alle korrekt → device/pluginkit, kein Code-Fix, voller Restart ist der Test.** C9 (Vordergrund-Re-Scan) hilft diesem Zweig NICHT (re-scannt dieselbe Registry ohne die Komponente); bleibt korrekt für den stale-cache-Zweig.

## FINDING (2026-07-19 AUv3 host-blindness — DEFINITIVE, device log v296/2403)
- **BEFUND (reproduzierbar, frischer Launch, 5 Retries):** Unser App-PROZESS sieht `raw 101 comps, 3rd-party 0, ownAUv3 false` — NUR Apple-IN-PROCESS-Units (aufc/aufx/augn/aumu/aumx/auou), NULL out-of-process (appex) AUv3. Self-Probe der EIGENEN appex: `FAILED NSOSStatusErrorDomain#-3000` (invalidComponentID = kein Match in DIESES Prozesses Registry). ABER AUM (anderer Prozess, gleiches Gerät) SIEHT unser EchoelBodyVibe. ⇒ NICHT gerätweite Registrierung (AUM beweist: Plugins sind registriert), sondern **unser App-Prozess ist blind für die komplette out-of-process-AU-Registry** — Fremd-Plugins UND eigene appex. EINE Wurzel erklärt BEIDE Founder-Symptome ("Host für externe blockiert" + Self-Probe −3000).
- **DEAD-END-KANDIDAT (nicht blind anfassen): Inter-App-Audio-Entitlement.** iOS-11-Ära-Foren (Apple DevForums 127481/89762) nennen `inter-app-audio` als Gate für `AVAudioUnitComponentManager`-3rd-party-Sicht. ABER: IAA ist seit iOS 13 DEPRECATED und aus modernem Xcode praktisch ENTFERNT — auf iOS 18 mit hoher Wahrscheinlichkeit STALE; ein entferntes Entitlement hinzuzufügen kann Provisioning/Signing brechen (Archive-Fail) + App-Review-Risk. ⇒ NICHT autonom setzen (CLAUDE.md: „Info.plist/CI/Signing nicht ohne Rückfrage"). Erst der Discriminator-Test.
- **DISCRIMINATOR (0-Risiko Geräte-Test, klärt die zwei Rest-Hypothesen):** Founder öffnet ein Fremd-Plugin IN GARAGEBAND/AUM's AU-Browser (voller Host, nicht nur die Plugin-eigene App), kehrt zu Echoel zurück, Rescan. Erscheint dann ein Nicht-Apple-Maker? JA ⇒ Registry-Warmup/Timing-Problem (sicher per Code fixbar). NEIN ⇒ Hosting-Capability/Entitlement-Gate (Config-Change nötig, Founder-Freigabe). GarageBand-Warmup-Muster steht explizit in DevForums 127481.
- **NÄCHSTER SCHRITT:** Discriminator-Ergebnis abwarten, DANN mit Gewissheit fixen. Kein Blind-Signing-Change.

## DEAD-END (2026-07-19 Reset Phase-1 cut-hunting)
- **DEAD-END: bulk `grep 'TypeName('` 0-Referenz-Scan zum Finden toter SwiftUI-Views ist UNZUVERLÄSSIG.** Er meldet lebende Kern-Views (`WorkspaceView`, `EchoelStudioView`, `TransportBar`, `PianoRollView`) fälschlich als DEAD(0) — SwiftUI-Views werden oft über `.sheet { AnyView(X()) }`, Surface-Switch (`SurfaceHost`), Header-Leafs oder computed vars konstruiert, die ein simples `\bX(`-Grep nicht trifft. Ein Cut auf Basis dieser Liste = Katastrophe (WorkspaceView löschen = ganze App). **DO THIS INSTEAD:** pro Kandidat die ArrangementView-Methode — (1) `grep -rn "TypeName" Sources` ALLE Vorkommen, Kommentare von Code trennen, (2) prüfen ob eine `Surface`-Enum/`.sheet`/Router es präsentiert, (3) Pflicht-Reviewer bestätigt 0 Code-Refs + kein toter Branch, (4) Gate grün. Ein File pro Zyklus, nie in Serie ungeprüft. Founder-geparkte Views (MeditationView = bewusst türlos, AudioInputPickerView = FeedbackGuard-Tür zum RE-DOORING) sind KEINE Cut-Kandidaten, auch wenn 0-ref.

## FINDING (2026-07-19 AUv3-Host — ROOT CAUSE, recherche-verifiziert, hohe Konfidenz)
- **`inter-app-audio` IST das Tor auf iOS 17/18** (weiter supported+provisionierbar; KEIN neuerer Mechanismus — keine AVAudioSession-Kategorie, kein `com.apple.developer.*`, kein Instantiation-Flag, kein AudioComponentFindNext-Unterschied). Quellen: DevForums 127481/89762, teemow/auv3-probe (Entitlement-only Diagnose-App), Apple „Supported capabilities (iOS)".
- **Echoels Source-Config ist KORREKT** (Echoelmusic.entitlements:41 `inter-app-audio=true`, project.yml:101 CODE_SIGN_ENTITLEMENTS). ABER: das Entitlement wird **beim Signing aus dem Binary GESTRIPPT**, weil die „Inter-App Audio"-Capability nicht auf der **App-ID `com.echoelmusic.app`** aktiviert ist. **Automatic signing kann diese (abgekündigte) Capability NICHT selbst zur App-ID/Profil hinzufügen** (Apple „Diagnosing Issues with Entitlements" + TN3125: Entitlements, die nicht im Profil stehen, werden beim Signieren entfernt). Fingerabdruck bestätigt es: die EIGENE appex ist auch unsichtbar (`ownAUv3 false`) — inter-app-audio versteckt ALLE out-of-process-Komponenten inkl. der eigenen.
- **FIX (nur Founder, Portal — Agent hat keinen Zugang):** Apple Developer Portal → Identifiers → `com.echoelmusic.app` → **Inter-App Audio** aktivieren → Save → dann NEUES Archive (automatic signing + -allowProvisioningUpdates regeneriert das Profil MIT der Capability → Entitlement überlebt → Fremd-AUv3 erscheint). CI-Config braucht KEINE Änderung.
- **Decisive verify (1 Zeile):** die v297 `auv3 self-probe`-Log-Zeile. INSTANTIATE OK ⇒ Registry serviert appex, aber LISTE leer ⇒ Entitlement unwirksam ⇒ genau dieser App-ID-Fix. FAILED(domain#code) ⇒ appex gar nicht registriert ⇒ Registrierungs-Pfad. Oder: `codesign -d --entitlements :- Payload/Echoelmusic.app | grep inter-app-audio` auf der .ipa.
- **DEAD-END bestätigt:** nur das Entitlement in die .entitlements schreiben + deployen (v297) reicht NICHT — ohne App-ID-Capability ist es ein No-op.

## FINDING (2026-07-19 AUv3 Deep-Research #2 — Öffnen-Schicht + Alternativursachen)
- **Founder-Fenster-Hypothese WIDERLEGT:** Enumeration passiert KOMPLETT vor jeder UI — 0-Plugins-in-der-Liste ist Discovery, nicht Fenster-Öffnen. Unser `requestViewController`-Pfad (AUv3PluginUIView) ist korrekt inkl. nil-UI-Fall; Präsentieren braucht KEIN Entitlement. Nicht hier graben.
- **Zwei getrennte Symptome nie vermischen:** A) „unser App listet 0 Fremd" = Enumeration = `inter-app-audio`-Tor (v298). B) „AUM sieht UNSER Plugin, öffnet nicht" = unsere appex INSTANZIIERT nicht in AUM = plugin-seitig (appex code-sign/provisioning, Speicher/Jetsam ~380 MB, Factory) — NICHT durch Host-Entitlement gefixt, andere Richtung.
- **`inter-app-audio`-Diagnose bestätigt** (DevForums 89762/127481 wörtlich). **EINZIGES echtes Restrisiko:** Entitlement wird ins SIGNIERTE Binary geshippt? Verify: `codesign -d --entitlements :- App.app | grep inter-app-audio` auf der IPA; fehlt es → App-ID-Capability im Portal (Founder hat sie JETZT gesetzt → v298-Re-Archive genau der Fix).
- **Own-appex-stört-Enumeration = REFUTED** (AUM/Loopy embedden auch eigene appex + listen Fremd). Nicht graben.
- **iOS-26-Regression existiert** (JUCE-Forum: scan OK, instantiate scheitert) — wir zielen iOS 18, NICHT unser Bug; nur merken für spätere iOS-26-Geräte-Reports.
- **Host ist bereits korrekt/robuster als Referenz-Hosts** (Discovery-API, out-of-process-instantiate+Timeout, Format-Preflight, Registration-Rescan, Self-Probe, UI-Pfad, appex-Registrierung). Der EINZIGE echte Gap war das Entitlement. NICHT über-engineeren.

## DEAD-END (2026-07-19, v300) — inter-app-audio ist NICHT der AUv3-Discovery-Gate
- **Behauptet (v297–v300):** „Host braucht `inter-app-audio`-Entitlement, damit
  `AVAudioUnitComponentManager` Fremd-AUv3 sieht." Mehrfach als „der Fix" verkauft.
- **Beweis dagegen:** v300 (fail-on-stripped-CI) lief ROT → Entitlement wird vom
  Auto-Managed-Profil gestrippt (Signing-Identität „Apple Development: Created via API",
  Profil „iOS Team Provisioning Profile"). ABER: iOS-AUv3-Hosting braucht KEIN
  Entitlement — jeder Host (AUM/GarageBand/Drambo) enumeriert ohne. Die DevForums-
  Synthese war falsch verallgemeinert (IAA = Legacy-Streaming, ≠ AUv3-Extension-Discovery).
- **DO THIS INSTEAD:** Nicht auf Provisioning-Profil-Chirurgie schicken. Das reale,
  host-unabhängige Symptom lesen: Self-Probe `NSOSStatusErrorDomain#-3000`
  (`invalidComponentID`) + „AUM sieht aber öffnet nicht" = Appex **instanziiert nicht** /
  stale pluginkit-Registrierung. Erster, billigster Schritt = sauberer Delete+Reinstall
  (klärt stale-Registrierung vs. echter Appex-Defekt). CI-Gate auf WARNING zurück
  (permanent-rotes Required-Gate blockt sonst jeden Deploy).
- **Meta-Lektion:** „Research-confirmed" ohne primäre API-Verifikation ist eine
  Vermutung. Bei wiederholtem „das ist der Fix" ohne Landung → Hypothese selbst
  anzweifeln, nicht die nächste Variante derselben Hypothese bauen.

## DEAD-END (2026-07-20) — reading AUv3/host entitlements from CI to decide the -3000 scan gate
Tried 3 ways across v312-315, ALL dead: (1) `codesign -d` on the xcarchive app = DEV-signed
(get-task-allow=true), strips healthkit/app-groups/IAA regardless of the App ID → aussagelos;
(2) read the distribution `.ipa` = there IS no .ipa (ExportOptions `destination: upload` uploads
directly, writes nothing to disk); (3) ASC-API `/v1/bundleIds/{id}/bundleIdCapabilities` = the
upload key lacks Identifiers read-scope (App-Manager, not Admin) → 403/inconclusive.
DO THIS INSTEAD: the App ID's Inter-App-Audio capability state is only readable by a human in the
developer portal (or a key with Admin). Ask the founder for a 30 s portal READ (developer.apple.com
→ Identifiers → com.echoelmusic.app → is "Inter-App Audio" enabled?). Do NOT burn more deploys on
CI entitlement diagnostics.

## AUv3 device-test ROUTED (2026-07-20, founder answer on v317/2425)
v316's component-version bump 10000→10001 shipped in v317, yet the device log STILL shows
0 third-party + ownAUv3 false + self-probe -3000. Founder confirmed (AskUserQuestion): they
did NOT reboot the iPhone and did NOT open another AU host (GarageBand/AUM) first — "nur App neu".
→ CONCLUSION: this is cause-1 (cold device AudioComponentRegistrar serving THIS process an
Apple-only snapshot), NOT our manifest/version and NOT a code bug. The version-bump theory is
now REFUTED as the cure for the 0-external symptom (it only ever addressed our own unit).
DO THIS INSTEAD: no more AUv3 discovery CODE until the founder runs the full warm sequence
(delete → REBOOT iPhone → reinstall via TestFlight → open GarageBand/AUM plugin list once →
Echoel → Rescan). If external plugins appear → cold registry confirmed, done. If STILL 0 after
the full sequence → THEN it routes to cause-3 (appex registration/provisioning; check archived
appex profile) — only then is a code/CI move warranted. The v318/v319 browser + one-tap
assignment surfaces are already built and ready to show them the moment discovery works.

## PLAYBOOK (2026-07-20) — trust the compiler gate over a reviewer's symbol-location claim
v319 shipped `LaneAUInstrumentHost.maxEffectsPerLane`; the code-reviewer "confirmed" it as a
public static let at LaneAUInstrumentHost.swift:45. Xcode compile-check went RED: the constant
actually lives on `LaneAUAssignment` (a struct in the SAME file, line 45) — the reviewer matched
the FILE+LINE from grep but not the OWNING TYPE. Lesson: a reviewer subagent's "symbol X exists
at file:line" is a grep hit, not a type-resolution proof. When a member reference is load-bearing,
grep for `static .* <name>` and read the ENCLOSING type, or just let the compile gate arbitrate —
don't treat the reviewer's location claim as ground truth. (SwiftPM was green here too; only the
stricter Xcode app-target gate caught it — always wait for BOTH gates on member-access changes.)

## DEAD-END / TRAP (2026-07-20) — "CI test gate green" was a FALSE GREEN
- **Symptom:** ci.yml + full-tests.yml showed test steps GREEN, but NO test actually ran.
- **Cause 1 (stale destination):** the runner is `macos-26` + Xcode `26.2` → only **iOS 26.x**
  simulators exist (iPhone 17, iPhone Air, …). The pinned destination
  `platform=iOS Simulator,OS=18.2,name=iPhone 16 Pro` DOES NOT EXIST → xcodebuild fails at
  destination resolution (build step ~72s = way too fast for a real build; look for
  "Ineligible destinations" + a device list with only OS 26.x in the log).
- **Cause 2 (masking):** the `… 2>&1 | tee x.log | xcpretty || cat x.log` pattern — the trailing
  `|| cat` runs on failure and EXITS 0, so the step outcome is "success" no matter what. Masks
  BOTH the destination failure and any real compile/test failure.
- **DO THIS INSTEAD:** build with `-destination 'generic/platform=iOS Simulator'` (no device/OS
  pin — robust to runner image drift); test on a device confirmed by an `xcrun simctl list devices
  available` step (e.g. `platform=iOS Simulator,name=iPhone 17`, no OS pin). DROP the `|| cat`;
  rely on step-level `continue-on-error` for non-blocking, and `set -o pipefail` so xcodebuild's
  real exit sets `steps.*.outcome`. A green test step is only trustworthy once the destination
  resolves AND the mask is gone.
- **Consequence:** Task #78 "wire the 294 tests" is NOT done at slice-1 — the smoke never ran.
  Real heal = fix the destination+mask in ci.yml (shared gate, reviewer-gated), then the tests
  actually gate.

## PLAYBOOK (2026-07-22) — genre identity that survives the CALM convergence (coherence crossfade)
Founder: "erst individuell, dann klingt alles gleich." Genre identity in this composer
lives mostly in dimensions the bio-CALM path STRIPS: rhythm density (calm>0.7 spacious
strips ornaments), and — the big one — HARMONY was 100% genre-agnostic: `ChordSuggest.journey`
(default-on `suggestJourney`) has NO style param and OVERRIDES each genre's authored
`harmonicProfile.progression` (BioComposer.swift ~L1343-1350), so at HIGH coherence it picks
the same functional T→S→D→T for every genre in the same key (and many genres SHARE a scale —
phrygian: doom/metal/psytrance/sciFi/oriental). #77 (leadDensity=0) removed the other carrier.
**FIX PATTERN (shipped v327, de55263):** a coherence-weighted crossfade INSIDE composeHarmonic's
`if let sc = suggest` branch — after the journey builds prog/sectionAlterations, lock the first
`k = min(n, Int((Float(n)*coherence).rounded()))` of the n section roots to the genre's OWN
`baseProg` (phase-rotated, [0,0,0] alterations). calm(coh→1)⇒k→n⇒genre signature; aroused(coh→0)
⇒k=0⇒journey BYTE-IDENTICAL. ZERO rng/structureRNG draw (pure fn of coherence+baseProg+phase) →
determinism law intact; chord QUALITY (profile.chordTones, jazz 7ths) untouched (only ROOT MOTION
anchored); always in-key. This ALSO fixes the "springt zurück" monotony better than reverting to
the genre's short loop, because the journey's travel survives in the aroused regime. RIGHT POLARITY:
calm = maximally-genre-characteristic, NOT less-calm (north-star preserved).

## DEAD-END-PREVENTION (2026-07-22) — the generative core is NOT a static loop; evolution EXISTS
Do NOT re-diagnose "the music just loops the same 8 bars" as the bug. `generate()` builds `loopBars`
(=8) DISTINCT bars (shared structureSeed + per-bar detail seed + advancing progressionPhase), an
evolve-tick (~25-45s) re-seeds with fresh live bio and hot-swaps at the seamless boundary, and tempo
converges toward the pulse (octave-folded into style.tempoRange, per-genre distinct). The "springt
zurück" the founder sees = the 8-chord journey (`chordJourneyLoopLength`) resetting to its start at
the loop wrap (progressionPhase % loop). The REAL product gap was genre-sameness at calm (see playbook
above), not missing evolution.

## DEAD-END (2026-07-22): the DRUM GRID is muted product-wide — genre-BEAT code never plays
`EchoelStudioView.generate()` loads `BioComposer.silentBeat()` (empty grid) UNCONDITIONALLY
(line ~3924), NOT `composition.drumSteps`. The beat was removed by founder verdict 2026-07-07
("Schmeiß den Beat komplett raus" → pure meditative Flächen). Consequence: everything in
`BioComposer.compose().drumSteps` — the 4 archetype builders, GenreFlavor.hatRate/kickCell,
applyHatRate, applyFlavorGhost, v329/v330 — is COMPUTED BUT NEVER HEARD. Two full cycles
(v329 hatRate, v330 energy overlay) shipped dead audio.
DO THIS INSTEAD: genre distinctness must live in the AUDIBLE layers only — synth patch/FX
character per genre (timbre), melodic rhythm/density in the notes, and harmony (v327/v328
root-anchor crossfade, which IS audible). Founder confirmed 2026-07-22 (AskUserQuestion):
"Flächen bleiben, Timbre/Harmonie schärfen" — beat stays OFF. Before ANY drum-grid work,
re-read this: silentBeat() is CORRECT, not a bug. Do not wire composition.drumSteps through
without a NEW founder ask reversing 07-07.

## PLAYBOOK (2026-07-22): verify the layer is AUDIBLE before iterating on it
The genre-convergence thread burned cycles on the drum layer while it was muted. Lesson: when
a founder complains "X sounds wrong", trace X to the actual audio output (which .load/.play
call feeds the engine) BEFORE building — don't assume compose() output reaches the speaker.
For Echoel the audible generative layers are: pianoRoll notes (melody/Flächen), synth patch +
fxCharacter (timbre/room), harmony/chords, tempo. The drum grid is NOT audible today.

## PLAYBOOK/CAVEAT (2026-07-22): slew-rate limiting ≠ per-amplitude flash-frequency bound
FlashGuard.slewedDimmer (0.08/tick @30Hz) — used for the dimmer, the on-screen visual, and now
(v332) the Art-Net/sACN colour channels — bounds the RATE of luminance change (2.4/s), so a FULL
0↔1 swing is ≤~1.2 Hz (no large strobe). It does NOT hard-bound a THRESHOLD-amplitude flash
(WCAG general flash = 0.10 amplitude, dark state <0.80): a tiny 0.1–0.2 reversal every 2–3 ticks
could still hit 6–12 Hz under a pure rate cap. UNREACHABLE with Echoel's sources (bio sub-Hz;
music colour per chord/beat), so it is a documented residual, not a live risk. If a hard ≤3 Hz
at ALL amplitudes is ever required (e.g. an external/automation colour source that CAN oscillate
fast), it needs a flash-FREQUENCY counter (reject a direction reversal completing a ≥0.10 cycle in
<1/3 s), NOT just a bigger rate cap. → Council item, out of scope for the v332 rate-limit fix.
Wording rule (no-overclaim): say "slew-rate limited, full swings ≤~1.2 Hz", not an unconditional
"≤3 Hz / WCAG-safe at every amplitude".

## 2026-07-22 — PLAYBOOK: verify the code branch is REACHED, not just that the function is correct
The genre-chord-articulation first cut wired `chordOnsets` into `composeHarmonic`'s
`profile.sustained` branch — but only 6 genres are `sustained:true` and they all map to the
`.sustained` articulation (which delegates to the old heartbeat path). The rhythmic genres are
`arpeggiated` or fall to the plain `else` branch — NEITHER read the articulation. Result: the
whole change was a NO-OP for all 23 genres, and would have been reported as "genre rhythm fixed."
The mandatory dsp-reviewer caught it as HIGH before ship. PLAYBOOK: this is the twin of "verify the
layer is AUDIBLE" (the muted-drum dead-end) — when adding behavior gated on a flag/branch, GREP the
real flag values per case and confirm the target inputs actually reach the new branch. A grep to
"confirm" flags earlier was BUGGY (awk across multiple switch statements reported all rhythmic
genres as sustained:true — they are NOT); trust an authoritative `grep -c` + per-case read, and add
an INTEGRATION test that proves the new path is exercised end-to-end (not just a unit test of the
new function in isolation).

---

### PLAYBOOK 2026-07-22 — the SPSC-drain idiom for ANY high-rate producer → audio-thread array rewrite
**Cycle:** v337, PolySynthVoice bio-spectral COW race (ultrascan step 3).
PolySynthVoice fanned bio into `poly.applyBioReactive` DIRECTLY from the @MainActor 10 Hz poll
(`applyLatestIfFresh`), which rewrote each voice's `harmonicAmplitudes` `[Float]` on the main thread
while the render block read it → cross-thread array COW/torn-read race. Notes/patch/fx were already
SPSC-drained on the audio thread; the bio path was the last one that wasn't (BioReactiveSynthVoice
had ALREADY been fixed this exact way — the twin was left behind).
**PLAYBOOK:** when a control-plane poll mutates an ARRAY that the render reads, NEVER call the mutator
from the poll — enqueue a trivial `Sendable` params struct on a lock-free `SPSCQueue`, drain
coalesce-to-latest + apply INSIDE `renderOnAudioThread`. Place the bio/param drain AFTER the patch
drain (anchors first) and before the render read. Resolve any control-plane-only inputs (e.g. a
`bioMappingHarmonic` flag → `BioMapProfile`) on the main actor at enqueue and carry them in the value.
Scalar/enum writes (word-aligned, e.g. `entrainment.band/.depth`) are the BENIGN class — leave them,
don't over-scope. Mirror the already-shipped sibling exactly; two audio-thread reviewers = CLEAN.
**Latent follow-up surfaced:** `computeShapeAmplitudes` `.formant` branch allocates a 3-elem array
literal per call → now on the audio thread for `.formant` patches (no shipping genre uses `.formant`,
so it never fires today). Logged as its own cycle (task #84) — hoist to a static let.

---

### DEAD-END 2026-07-24 — mining a stale AUDIT backlog item-by-item after the real fixes already shipped
**Cycle:** v346 building; picking the next slice from the #114 chrome UI audit (wf_a3768641)
and #116 6-team consistency audit (wf_f96cccb1).
Verified SIX candidate items in a row against real source — ALL already-resolved or mis-flagged:
(1) accent-Slider retint (EchoelStudioView:2375) — its TWIN slider (FloatingVisualWindow:523) is
    founder-blessed accent + "accent exclusive to bio" is a LOCAL chip-fill comment, not a global
    slider-tint law (accent tints 40+ interactive controls app-wide). Retinting one twin = asymmetry.
(2) dev build number `#if DEBUG` out of brand subtitle (WorkspaceView:217) — would REGRESS the
    founder's device-verify loop: TestFlight is a RELEASE build and device-log-triage/watch-clip
    BOTH depend on reading `vX.Y.Z (build)` from that header. #if DEBUG strips it from TestFlight too.
(3) clip-name overflow (ArrangeTimelineView:1700) — `.lineLimit(1)` in a bounded `.overlay` already
    truncates; non-reproducing without device evidence; dev:True anyway.
(4) per-lane Genre/Mood pickers tint .accent (#116 b) — ALREADY `.text` at :2202/:2223; no accent
    picker exists in the file. Fixed in a prior cycle.
(5) triple-declared tempo constants (#116 d) — ALREADY single-owned: Transport:63-65 canonical,
    PatternEngine:38-40 + BioTempoDirector:50-51 + BodyTempoField already delegate `= Transport.min`.
(6) BinauralPanner azimuth OPPOSITE house convention (#116 f) — MATCHES: SpatialScene:17,33 documents
    positive=LEFT(CCW); BinauralPanner does positive-az→pan<0→louder-left + same breath→az mapping as
    ADMOSCSender:225. "shared source of truth" claim is TRUE, not false.
**PLAYBOOK:** an audit's task-list entry is a SNAPSHOT that decays — prior Ralph cycles fix the real
items but rarely edit the audit's backlog text. Before spending a cycle on an audit item, `grep`/read
the cited file:line and confirm it STILL reproduces. When 2-3 consecutive items from the same audit
prove already-done/false, treat the whole backlog as DRAINED (reconcile the task, don't keep mining).
The genuinely-open remainder here is the dev:True set (Dynamic Type chrome-band heights + SF-Symbol
scaling; automated-tempo→metronome; Kammerton in melodic/bio voices) — all need device-verify, so
they wait for the v346 channel, not a blind ship.

---

### PLAYBOOK 2026-07-24 — bio/composition math cores are defensively guarded; stop re-hunting divisions
**Cycle:** hunting a crash-guard slice (unguarded division / n-1 / empty-array mean) after the audits drained.
Grepped every `/ Float(count)` · `/ (n-1)` · `reduce/count` mean in Sequencer/Bio/Core and READ each:
ALL properly guarded — HRVMetrics rmssd/sdnn/pnn50 (`guard count>=2`, :25/37/49), BioNormalizer.std
(`guard filled>=2`, :82), VoiceLeader mean (`guard !cand.isEmpty`, :132), BioComposer pad-center
(`!basePitches.isEmpty` / `!voiced.isEmpty`, :1637/1646). No div-by-zero / NaN slip.
**PLAYBOOK:** the pure cores here are mature + defensively written — a blind "find an unguarded division"
sweep is now LOW-YIELD (this cycle: 5 candidates, 0 bugs). Don't re-run it as a default slice-finder.
The remaining real robustness work is at BOUNDARIES (sensor ingest, decode, route changes), already
largely hardened (#92 NaN, #97 HRV-scale, #95/#117 decode). When no unambiguous change is warranted,
DO NOT manufacture a marginal/possibly-intentional edit to satisfy the loop — log the verified-clean
state + any real-but-dev:True finding (e.g. #120 metronome tempo-sync) and say so honestly. A
verification cycle with an honest "cores clean, nothing to force" is a valid Ralph outcome.

## 2026-07-24 — DEAD-END: deleting a Source file, grep only the class name
When deleting a whole Source file, a `grep <ClassName>` MISSES sibling tests named
after a SECONDARY type the file also defined. `Audio/AUNoteVoice.swift` also housed the
`AUNoteMIDI` enum; grepping `AUNoteVoice` came back clean but `AUNoteMIDITests.swift`
(testing `AUNoteMIDI`) broke the test-target compile. The app library compiled fine — only
`swift test`/CI-Pipeline caught it. PLAYBOOK: before deleting a file, `grep` EVERY top-level
type/enum/struct it declares (read the file's decls), then grep each across Tests/ too. The
audio-thread-reviewer's compile-gate pass caught this; a pre-push symbol-by-symbol grep would
have caught it earlier.

## 2026-07-25 — DEAD-END-VERMEIDUNG: kein "content-flash slew" für die Header-Tiles erfinden (#127)
Board-Item #127 wollte einen „true content-flash slew" für die Header-Monitor-Tiles (Immersive + Lux).
BEVOR gebaut: `HeaderMonitors.swift:300-317` gelesen. Befund = KEIN Flash-Hazard, nichts zu bauen:
(a) der Immersive-Tile-Puls ist bereits auf 2.5 Hz gekappt (`flashSafePulseRate =
min(max(40.0, heartRateBPM)/60.0, 2.5)`) < 3 Hz WCAG; (b) `energy = 0.35 + 0.30*pulse + 0.35*level`
driftet stetig (kein Rechteck/Blitz); (c) der Lux-Tile hat gar keinen synthetischen Oszillator;
(d) die HEUTE angebotenen Genres sind alle drum-frei → `masterLevel` hat keine Beat-Transienten, die
die Helligkeit springen ließen. **PLAYBOOK: ein Board-Item, das eine Sicherheits-/Polish-Lücke
BEHAUPTET, erst am zitierten `file:line` gegen die REALE Rate/Formel prüfen, bevor ein „Fix" gebaut
wird — sonst manufacturt man einen Slew auf einen bereits-gekappten Wert (Bewegung vortäuschen).
Verifiziert-nicht-reproduzierbar → Item schließen, nicht bauen.** (Deckt sich mit dem drainierten-Audit-
Playbook 2026-07-24.)

## 2026-07-25 — PLAYBOOK: a symbol-removal map is a HYPOTHESIS — grep the removed name yourself before committing
Slice 2c-ii (AUv3-host removal) used a thorough read-only Explore map of every `auHost`/`AUv3Host`
edit site. It STILL missed one: `suppressBuiltIn` (the local derived from `auHost?.suppressesBuiltInVoice`)
was read a SECOND time far below its definition, in the `desiredSub` felt-sub line — deleting the
definition would have compile-broken had I trusted the map. Caught by grepping `suppressBuiltIn` in the
file AFTER the edits (not in the map). PLAYBOOK: after removing a variable/symbol, run one final
`grep <removedName>` over each touched file — an edit-site map lists where a symbol is ASSIGNED/obvious,
not every DERIVED read. The reviewer (audio-thread) independently re-confirmed the fix; a pre-commit
self-grep caught it first.
Reinforces the 2026-07-24 delete-rule with a 3rd instance: `AUv3Host.swift` declared FIVE top-level
types (AUv3Host, HostedAUInfo, AUv3ScanDiagnostic+SelfProbe, an `extension AUPluginRef`); the map's
Tests-grep covered 4 and missed `AUv3ScanDiagnostic` → `AUv3ScanDiagnosticTests` would have broken
(the old plan's "kompiliert weiter" was stale). ALWAYS grep EVERY top-level decl of a to-be-deleted
file across Sources/ AND Tests/ — read the file's decls first, don't trust a summary.

## 2026-07-25 — PLAYBOOK: the delete-rule has an INVERSE half — grep what the file CONSTRUCTS, not only what references it
Slice 4/4b deleted `ArrangeTimelineView.swift` (2432 Z). The established delete-rule (grep every
top-level decl of the doomed file across Sources/ AND Tests/) ran clean — all 10 external refs were
comments, so the deletion was COMPILE-safe. But that rule only protects the build; it is blind to the
opposite direction. A second sweep — "which views is this file the SOLE construction site OF?" —
found EIGHT orphans, two of them KEEP-list items: `PianoRollView` and `PatchEditorView` (plus
`ImmersiveStageView`). Their own `EchoelStudioView` sheets had been removed in v10.79.207, so the
deleted timeline was their last door: the pure instrument silently lost melody-editing and
patch-editing. Compile-green, product-broken — and `CLAUDE.md` still claimed the patch editor was
"reachable from EchoelStudioView" (stale, corrected 0191e47; task #131 opened).
**PLAYBOOK: before deleting any VIEW (not just any file), run BOTH halves —
(a) inbound: `grep <everyDeclaredType>` → protects the build;
(b) outbound: extract `[A-Z][A-Za-z]*View(` from the doomed file and, for each, check whether ANY
other file constructs it → protects the PRODUCT. Anything left with zero constructors is now
doorless: either it is a known cut target (say so in the commit) or it is a keeper that must be
re-doored (open a task + fix the docs). Never let a door die silently.**
Reachability corollary used to keep the call honest: a view whose only presenter was already
UNMOUNTED was already unreachable → deleting it is not a NEW regression, but it does make a
pre-existing gap permanent, which is exactly the thing worth surfacing to the founder.
Bonus (same cycle): the ui-state-reviewer caught a false claim in my OWN comment rewrite
(`ChannelRackView` called unmounted; it is live in EchoelStudioView's Mix panel) — when a deletion
forces you to rewrite a doc block listing what "still stands", re-verify EACH name in that list.

## 2026-07-25 — CORRECTION to the inverse delete-rule: the OUTBOUND sweep must cover EVERY declared type, not just `XView(`
The playbook added earlier today (inbound grep protects the build; outbound grep protects the product)
was RIGHT in shape but I implemented the outbound half too narrowly. For Slice 4/4d I extracted only
`\b[A-Z][A-Za-z0-9]*View\(` from the doomed files and concluded "nothing new is orphaned". The
code-reviewer refuted it: `Sequencer/ClipAutomationEdit.swift` — a pure, tested `public enum`, NOT a
View — lost its last production consumer when `ClipAutomationView` was deleted. A View-shaped regex
cannot see a non-View orphan.
**PLAYBOOK (supersedes the narrow version): for the outbound half, enumerate every CAPITALISED
IDENTIFIER the doomed file references (types, enums, factories, math cores — not just `…View(`), then
for each ask "does any OTHER file still reference it?". Anything left at zero is newly orphaned and
must be classified out loud: known cut target (name it in the commit) / keeper needing a new door
(open a task) / residue for the cleanup slice (add it to the list).**
Corollary that made the 4d call safe anyway: deleting a CALLER can never break the CALLEE's
compilation, so an outbound miss is never a build break — it is a *bookkeeping* failure that leaves
dead code unrecorded, or worse, a keeper silently doorless. That is exactly why the sweep exists;
budget for it rather than trusting a one-line regex.
Second, smaller lesson from the same cycle: when a deletion forces you to REWRITE a doc block that
lists "what still stands", re-verify EACH name in that list. My rewrite of `SurfaceSwitcher.swift`
called `ChannelRackView` unmounted; it is live in `EchoelStudioView`'s Mix panel (`:1510`). The
ui-state-reviewer caught it. Inherited-but-restated falsehoods are still falsehoods.

## 2026-07-25 — PATTERN (now 4-for-4): the reviewer's real yield is my COMMENTS, not my code
Four consecutive reviewed slices this cycle. In every one the code was clean and every accepted
finding was in prose I wrote:
- 131a (`f2cbf34`): ui-state-reviewer 0 defects, code-reviewer no CRITICAL/HIGH. Three accepted
  findings, all comment drift — (a) I claimed presenting `PianoRollView` is the `MusicalFrame`
  publish path; it is `PianoRollModel` on the shared tick (`PianoRollView.swift:971`), installed once
  at app start, so presentation is irrelevant to it; (b) I cited `PRODUCT_DEFINITION.md` for
  "automation", a word that document never contains (the automation editors died in Slice 4d
  `36a8468`); (c) a redundant `AnyView(...)` around an already-`AnyView` return.
- chip tap targets (`ae81a5d`): clean on all 7 checks. One accepted finding — I wrote "the visible
  pills are unchanged"; true of the pills, but `minWidth: 44` widens narrow chips' FRAMES so the
  inter-pill GAP grows ~6 pt, and I had silently widened #113's deliberately vertical-only rule.
- Slice 4b/4d earlier: `ChannelRackView` called unmounted (it is live), and the too-narrow outbound
  regex — again both in prose/bookkeeping.
**PLAYBOOK: before asking for review, re-read your own added comments as if they were assertions
under oath, and grep-verify each one — every file:line, every "X is the only Y", every citation of a
doc (open the doc and search for the word), every "unchanged". A false comment is worse than no
comment: it survives compaction, reads as verified history, and the next session plans from it.**
Specifically: never cite a doc for a claim without grepping the doc for the term; never write
"unchanged" about geometry you altered in ANY dimension; and when you copy a working call from git
history, copy its SEMANTICS too (the `onDone: nil` default is what makes the roll live, not decoration).

## 2026-07-26 — DEAD-END: reading a `continue-on-error` job's step conclusions
The `Echoel Full Test Suite (non-blocking)` job reports EVERY step `conclusion: success`,
including steps that failed — because each is `continue-on-error: true`. `actions_list ->
list_workflow_jobs` on it therefore tells you nothing at all. **The only honest reading of that
job is the Summary step's PRINTED TEXT** (`get_job_logs`, `return_content: true`, ~260 tail
lines): `build-for-testing: <outcome>` / `test-without-building: <outcome>` plus the
`===ECHOEL_BUILD_ERRORS===` / `===ECHOEL_ERROR_FILES===` blocks, which come from
`steps.<id>.outcome` and survive the mask.
Two traps inside that text, both hit on `58ae64e`:
- `===ECHOEL_ERROR_FILES===` is `sort -u | head -50`. The block came back with exactly 50 lines,
  all from ONE file — which looks like "one file is broken" but is indistinguishable from
  truncation. Do NOT conclude "only this file"; verify locally (a per-class-isolation-aware scan
  of `Tests/`, not a per-file grep — a file whose FIRST class is nonisolated can carry a second,
  correctly `@MainActor` class, and a naive scan reports 36 false positives).
  **CONFIRMED truncated on the next round:** after the one file was fixed, the block came back
  with two errors in `VideoMuxAlignmentTests.swift` — alphabetically after the `R…` file, i.e.
  exactly where `head -50` had cut. Treat the block as a LOWER BOUND, always.
  Second reporting artifact from the same round: `NoteTests.swift:255-262` carried three
  instances of the identical `accuracy:`-on-`Float?` defect and appeared in NO reveal list at
  all — batch-mode error reporting does not surface every file's errors in one pass. So a clean
  block does not mean a clean suite; sweep the defect CLASS locally after every fix.
- The `test-without-building` failure ("Missing bundle ID … Failed to get bundle ID from
  Echoelmusic.app") reads like an independent `project.yml` defect, and the workflow's own env
  comment blames an `EchoelmusicAUv3.appex` placeholder that #122 DELETED. Both are wrong: the
  step runs unconditionally after a FAILED `build-for-testing`, so it installs a half-built
  product. **Proof it is a symptom, not a bug: the SAME app target's "Run Tests" step in
  `Echoelmusic CI/CD Pipeline` installs and runs for 62 s, green, on the same SHA.** So: fix the
  compile FIRST, then re-measure the install. Do not touch `project.yml` (founder-gated) on the
  strength of that error line.

**PLAYBOOK — the local defect-class sweep that replaces waiting for the next 15-minute CI
round.** Each reveal round surfaces ONE wave, so sweeping the class locally after every fix is
what breaks the one-file-per-round crawl. Two heuristics produce false positives every time
until fixed, and I hit both twice:
- **Strip line comments first.** `FlashGuardTests.swift:135` "references" `MetalBioView` only
  inside a doc comment; a `@MainActor`-in-prose match flagged 36 Sources types that are plain
  `struct`s whose doc block happens to mention the attribute. Require the annotation to be the
  IMMEDIATELY preceding non-blank, non-comment line.
- **Only a TOP-LEVEL `class` declaration changes isolation state.** A nested helper (`class
  Factory` inside an `@MainActor final class …Tests`) is already isolated; resetting on it
  wrongly flagged `AudioLanePlayerTests`, `ParameterApplyRouterPerTrackTests`,
  `PianoRollKindVoiceTests`. Same bug also mis-flagged a file whose SECOND top-level class is
  the isolated one.
- For `accuracy:`-on-optional, parse **whole calls with balanced parens**, not lines — a
  multi-line assertion hides the optional from a line-based regex.

**And the part that matters beyond CI: a test file that has NEVER compiled has also never
RUN, so making it compile is only half the work.** `RecordControllerAudioHookTests` compiled
clean after the isolation fix and would then have failed three assertions deterministically —
`testOverlappingStop_…` arms only an AUDIO lane, but `.audioInput` is deliberately not
`captureImplemented` (`Sequencer/TrackInstrument.swift:144`), so `RecordPlan.targets` is empty,
`arm()` returns without setting `armed`, and the take never starts. Its own sibling test
documents that gate in a comment and adds the MIDI lane; this one forgot. Second latent trap in
the same file: `ClipStore.setClip/clear` persist IMMEDIATELY to the shared AppGroupStore file
and `init` reloads it, so tests that deposit clips without clearing leave a full 8-slot grid
behind and `RecordController.commit` then skips every take silently. **PLAYBOOK: when you
un-block a never-compiled test file, review its ASSERTIONS against the source gates too, and
check every store it touches for the snapshot/restore idiom — otherwise the next reveal round
just trades compile errors for red tests.**

## 2026-07-25 — GATE-PARSE: `cancelled` on the previous SHA is supersede, not failure
Pushing a second commit quickly cancels the earlier SHA's in-flight runs (workflow concurrency,
cancel-in-progress). Seen as `completed cancelled | Xcode Compile Check` on `ae81a5d` seconds after
`8286f4e` landed. Do NOT treat that as red and do NOT "fix" anything — but equally, do NOT count the
earlier commit as compile-verified: its proof was thrown away. **Only the HEAD SHA's gates count;
if you superseded a commit before its gates finished, that commit has no verification at all, so
don't stack further code on the same file until the new head is green.**

## 2026-07-26 — PLAYBOOK: a "fallback so it still sounds" guard is a genre-identity leak
`BioComposer.chordOnsets` had the ordinary-looking guard `onsets.isEmpty ? [(secStart, secLen)]`.
It reads as defensive hygiene (never return nothing) and was in fact the exact bug the function
was written to fix: one onset spanning the section IS a held chord, so every section whose grid
it missed silently rejoined the `.sustained` branch. Jazz and rock came out byte-identical to
held classical — the 2026-07-22 "everything sounds the same" fix never reached them.
**RULE: when a function's whole purpose is to make X differ from Y, its empty/degenerate
fallback must be checked against Y.** A fallback that returns the neutral case re-creates the
bug for exactly the inputs nobody tested. Two smaller lessons from the same slice:
- **Displace on the function's OWN grid, not by a constant.** A fixed `+2` is only 8th-aligned
  when the section start is even; `prog.count == 3` gives 5-step sections, so punk's fallback
  would have landed on absolute step 7 — a 16th no articulation in the file ever plays.
- **A per-family claim needs the per-genre arithmetic.** I wrote "the comp family degenerates"
  and the reviewer found it true for 2 of 6, wrong-shaped for 3, and false for oriental (its
  2-chord progression gives 8-step sections that always contain a hit). `prog.count` decides
  section length, so the defect is per-progression, never per-articulation.

## 2026-07-26 — PLAYBOOK: a long-red test may be measuring the wrong QUANTITY, not failing
`BioComposerTests.testCompose_rhythmicGenresChopChords_notInertThroughPipeline` was red for months
against working music. It required a rhythmic genre's TOTAL NOTE COUNT to exceed a held genre's.
Note count is decided by chord size and bass density, not by rhythm, so it failed in BOTH
directions at once: rocksteady TIED (it shares prog.count, sectionLen and chordTones.count with
classical) and read as "inert" while its chops landed on the full offbeat grid; and jazz PASSED
throughout the months its pad was a held chord byte-identical to classical's, because 4 chord
tones outnumber 3. **RULE: before assuming a long-red test found a bug, check that its measure is
sensitive to the property it names AND insensitive to everything else.** A measure that both
cries wolf and sleeps through the burglary is not a strict test — it is a coincidence detector.
The replacement measures the property directly (chord onsets that coincide with no bass onset)
and is paired with an explicit NEGATIVE CONTROL in its own test name, so "the measure stopped
discriminating" is a diagnosable red name rather than silently making the positives vacuous.

**And the reviewer finding that matters more than the fix:** my first cut exempted one genre from
the new measure on a contamination theory I had reasoned out but not traced. Both halves were
false — the interfering layer's stride is COMPUTED (8 at that operating point, not the fixed 4 I
assumed), and the count I kept for that genre was green even for the regression it named. **When
you exempt a case from a rule, trace the exemption as hard as the rule; an exemption is where the
old defect goes to hide.**

## 2026-07-26 — PLAYBOOK: when is flipping a red assertion legitimate?
`ChordSuggestTests.testSuggestJourneyOn_changesTheProgression` required the chord journey to
CHANGE the progression at full coherence, and had been red for months. It was not finding a bug:
its premise was true when written (`bf1ee63`) and was deliberately reversed by a later founder
decision (`de55263`, the genre-identity anchor — a calm body must hear THIS genre, so the journey
is overridden entirely at high coherence). The test was asserting that the founder's own ask must
not happen. **THE TEST: a red assertion may be flipped only when GIT ARCHAEOLOGY shows a specific
later commit made it false ON PURPOSE. "The code does X now" is never sufficient — that is what a
regression also looks like.** Ask the reviewer for the archaeology explicitly; mine found the two
commits and the ancestry between them, which is what turned a guess into a verdict.

Two corollaries from the same review:
- **Assert the new law on the side you are claiming about.** My first replacement compared the
  ON take to the LEGACY take. The reviewer showed that equality rests on four independent
  conditions (the anchor, a rotation-invariant progression, a seeded draw missing its threshold
  by 0.0147, and `leadDensity 0` hiding a three-draw RNG skew) — only the first is the law. A
  structural assertion on the ON side alone (its pitch classes are the genre's own I chord)
  states the law without borrowing three coincidences.
- **When a claim cannot be established statically, assert it existentially and SAY SO.** There is
  no local Swift toolchain, so "which coherence makes the journey diverge" was unknowable without
  guessing — and a guessed pin that happened to match is the arithmetic-tie trap again. A sweep
  with "at least one case differs" is provable-by-running and still fails exactly when the
  feature goes dead.

## 2026-07-26 — PLAYBOOK: when the user HEARS music but SEES grey, look for one number with two consumers
The founder's build-2466 log carried `mfNotes=5 level=0.00` while the instrument was audibly
playing — five notes, all of amplitude zero, yet sound. Both readings cannot be true of the same
signal, so one of the two consumers was reading a number the other ignores.

It was note VELOCITY. The Mix faders (bass/pad/lead) are applied by baking `velocity * fader`
into the generated notes at compose time. The VISUAL then reads that velocity out of
`MusicalFrame` and dims accordingly — correct. The AUDIO, however, threw it away: `spawnVoice`
set the voice amplitude from velocity and `applyBioToVoice` overwrote it outright one line later
(`ampBase = 0.35 + coherence * 0.15`), re-applied on every 10 Hz bio frame. So a fader at 0 made
a note that was silent to the eye and unchanged to the ear — **a mute that does not mute, and a
grey visual over playing music.**

**THE PATTERN TO CHECK FIRST: a control that writes into DATA, where one downstream consumer
honours the data and another overwrites it.** Symptoms are always contradictory-by-report ("it's
silent but I hear it", "the meter is dead but the file is loud"). Don't start from the consumer
that looks broken — enumerate every writer of the shared field and ask which one wins last.

Two corollaries:
- **An "overwrite" in a modulation path is almost always meant to be a SCALE.** `x = bio` erases
  the performer; `x = bio * played` lets the body shape what was played. The comment at the very
  site already admitted an earlier version of this bug ("every note collapsed to a neutral ~0.45
  amplitude and lost its patch character and velocity sensitivity") and had been fixed by GATING
  the overwrite instead of converting it — which repaired the bio-off case and left the bio-on
  case, i.e. the only case the product actually runs in. **A gate that fixes the disabled path
  is not a fix.**
- **Give the scale a neutral default and prove the neutral case.** `velocityGain = 1.0` means the
  mono/bio voice — which never sets a velocity — stays bit-identical. That deserves its own named
  test, because "multiply by velocity" applied naively to a voice with no velocity context is how
  a bio-reactive synth goes permanently silent.

## 2026-07-26 — DEAD-END: turning a reviewer's flag into a task without tracing it yourself
A review of the velocity fix ended with a LOW note: "`SubBassVoice.noteOn(pitch:velocity:)`
discards velocity — if the founder pulls the Bass fader and hears nothing change, this is why."
I filed that verbatim as the next slice. It was WRONG, and one grep would have shown it:
`outputVoice(for:)` sends `.bass` and `.harmony` to the POLY voice, where the fader works. The
velocity-discarding overload only applies when a sub-bass LANE is bound as the primary kind
voice — not the generated take. The felt sub is a separate layer with its own gain, pitch-only
by design.

**RULE: a finding is a hypothesis until YOU have followed the chain to its caller.** This is the
same failure the repo already records one level up ("slot + setter does not prove reachability")
— a reviewer's file:line is evidence that the CODE says what they quote, never that the code
RUNS in the case being discussed. Cost here was one wrong task title; the same habit applied to
a deletion would have cost a capability.

The real defect, found only by tracing: the felt sub was reconciled from the lowest pitch in
`active` with no audibility check, so a fader at 0 left it droning under a note nobody could
hear. **And it had been INVISIBLE until the previous slice** — the bio pulse used to overwrite
voice amplitude, so the muted note sounded anyway and the sub matched something real. A fix
uncovering the next defect in the same chain is the normal shape of the thing; budget a
follow-up slice for it rather than reading it as a regression in the fix.

Third corollary from the same review, worth its own line: **a justification can be wrong while
the value is right.** I defended the audibility threshold with "the band between 0 and the
composer's 0.05 floor is unreachable". It is reachable (the humanizer clamp runs BEFORE the
fader bake; a 0.01 fader puts a soft note at 0.000425). The threshold survives on audibility
instead — but a future session tuning from the false premise would have raised it. Check the
REASON in a comment as hard as the number.

## 2026-07-26 — DEAD-END: reporting a deploy as shipped at PUSH time, not at BUILD time
I told the founder "v10.79.352 ist raus" in the same turn I pushed the `.deploy/release` bump.
The TestFlight run then FAILED, so no such build exists and the founder was told to go look for
something that is not there — the most expensive kind of wrong, because he verifies on a device
and would have concluded the fixes did not work.

**RULE: a push is not a build. A deploy is only reportable once the TestFlight run is
`completed/success`.** Until then the honest word is "unterwegs" / "läuft". The two real CI gates
being green says nothing about it: they never run the archive, the export or the upload.

Diagnostic detail worth keeping, because it is a DIFFERENT failure from the one already
ledgered: the previous transient failed INSIDE the archive with `-allowProvisioningUpdates`.
This one had a clean 4-minute archive and failed in the **Export & Upload** step after 4
seconds. Same triage rule still applied and is what makes it cheap to decide: the commit touched
`.deploy/release` ONLY, so it cannot have broken signing; the preceding deploy succeeded on the
identical workflow; Xcode Compile + CI were green. That combination = re-trigger tokenlessly with
the version UNCHANGED (so the new build number is the only difference), up to 3×. If the same
step fails again at the same place, it is NOT a transient and the export step gets taken apart.

The "Apple Development" signing identity in the archive log is NOT the smoking gun it looks
like — automatic signing archives with a development identity and the export step re-signs for
distribution. Do not chase it before the retry.

## 2026-07-27 — CLOSES the deploy dead-end above: the retry rule held
Attempt 2 on the identical content (`73a1927`, Build 2469) ran Archive → Export & Upload →
"Verify build landed in App Store Connect", all green. So the previous entry's triage rule
(commit touches only `.deploy/release` + prior deploy green on the same workflow + both gates
green ⇒ Apple-side transient ⇒ re-trigger with version unchanged) is CONFIRMED, now twice over
and at two DIFFERENT steps (archive-side provisioning, and export/upload). Do not spend a cycle
diagnosing the export step the first time it fails under those conditions.

Also worth keeping: `testflight.yml` has a "Verify build landed in App Store Connect" step. THAT
is the signal to report a ship on — not the workflow's overall conclusion, and certainly not the
push.

## 2026-07-27 — PLAYBOOK: a wrong REASON attached to a right FIX is a booby trap, not a nit
Shipping the NaN-velocity clamps (#176) I wrote, in a commit message and two code comments, that
`PolySynthVoice.noteOn` was "the LAST gate before the render thread" and that a NaN reached
`pow()` in `spawnVoice` and poisoned the voice. The FIX was right. The REASON was false:
`EchoelPolyDDSP.noteOn` already clamped in the safe argument order and `velocityGain` had its own
`.isFinite` guard, so the synth was protected all along.

Why that is worse than a harmless inaccuracy: my sentence made the REAL guards look redundant. A
later session tidying "duplicate" clamps would have deleted the load-bearing one and reintroduced
exactly the bug the comment was written to prevent. The repo has been bitten by this shape before
(the false "PianoRollView PUBLISHES MusicalFrame" line in CLAUDE.md, which would have blocked a
founder-ordered removal on a technical ground that did not exist).

**RULE: before writing "X is the only/last guard", go READ X's consumer and check whether it
guards itself. If it does, say so IN the comment and name it as load-bearing.** The honest reason
here was also the stronger one — `Int(Float.nan)` traps, and the MIDI exporters do
`Int(v * 127)`, so a leaked NaN is a hard crash on export, not a quiet voice. Looking for the
real mechanism found a worse bug than the one I had invented.

## 2026-07-27 — DEAD-END: a NaN test that constructs its NaN through a clamping init
Three tests named the BioComposer velocity clamps and passed `Note(velocity: .nan)`. But `Note`'s
init clamps NaN to 0 (that was the same slice's fix), so the composer received 0, not NaN —
reverting all three composer clamps left the tests GREEN. They still went red against the full
pre-change tree, via the init, which is precisely why the hole was invisible: red-after,
green-before, and covering the wrong line.

**RULE: when the same slice hardens a constructor AND a downstream consumer, a test for the
consumer must NOT build its input through that constructor.** Assign through the public `var`
(which is also how production reaches it — the composer mutates `n.velocity` on a built note).
General form: to prove a test covers line L, mentally revert ONLY L and ask whether it still
passes. "It fails against the whole old tree" is not the same claim.

## 2026-07-27 — DEAD-END: "pre-existing / infrastructure" as a diagnosis you never checked
The suite's ONE red test carried the note "pre-existing simulator startup error, nothing to do
with audio" through several cycles. I repeated that note each cycle without ever opening the
test. Both halves were false: it was GREEN until `c9af52b` (the founder's drums removal) and it
failed on an ASSERTION, not on the launch error sitting next to it in the CI output.

Two mechanisms produced the wrong triage, both worth knowing:
1. **The grep makes unrelated lines adjacent.** `full-tests.yml`'s Summary is
   `grep -E "failed|error:" full-test.log`. A simulator-clone launch message matches on `failed`
   and an assertion matches on `error:`; two lines minutes apart in the log print next to each
   other. **Adjacency in that block is not causality.**
2. **A label survives longer than the evidence for it.** Once "infrastructure flake" was in the
   task title, every later cycle read the title instead of the test.

**RULE: a parked failure gets ONE cheap re-derivation before it may be repeated as fact — read
the test body and `git log -S` the assertion. If a whole suite is green except one test, the
host app did NOT fail to launch.** The decisive check here took one grep: a SIBLING test in the
same class uses the same fixture and the same call and is green.

**And the real lesson underneath:** the test was pinning behaviour the founder had deliberately
removed. Whenever a founder-ordered REMOVAL lands, grep the test suite for the removed
behaviour in the SAME commit — `c9af52b` updated two test files and missed a third, and that
miss looked like a product defect for ten hours.

## 2026-07-27 — PLAYBOOK: after a removal, check the repaired test still has TEETH
Fixing the above, the obvious repair was to keep the drums fixture and assert the new value
(`.poly`) at prime. That would have been GREEN AND WORTHLESS: stop() publishes `.poly` too, so
the test would pass even with the stop-reset deleted. Swapping the fixture to a kind that still
resolves to a real voice (`.subBass`) keeps prime ≠ stop.

**RULE: when a removal collapses two distinct expected values into one, the test that compared
them is now vacuous. Re-point it at a live value, and add an explicit
`XCTAssertNotEqual(before, after)` so the vacuity cannot creep back.** Generalises the
already-ledgered "revert ONLY line L and ask if the test still passes" check to the case where
the culprit is the FIXTURE rather than the input.

## 2026-07-27 — PLAYBOOK: "unreachable at runtime" ≠ "safe to delete" (compile-time reachability)
Planning the drum-apparatus removal I classified `BeatPlayer.trackNames` as dead because its
only readers were unreachable views. Review found FOUR readers, one of them
`EchoelStudioView.importMIDI` — which is **dead at runtime** (`midiImportPresented` has no
setter) but **live at compile time**. Deleting `trackNames` without `importMIDI` in the same
commit would have red-gated the build, i.e. exactly the cycle-burning failure the slicing was
designed to prevent.

**RULE: reachability analysis answers "can this run?", not "can this be deleted?". Before any
delete, run BOTH passes — the runtime trace (to a rendering parent) AND a plain
`git grep <symbol>` for compile-time references, including inside code that is itself dead.**
Dead code still has to compile.

Two more from the same review, both about deletes that LOOK free:
- **A bundled resource can be load-bearing for PERSISTED data.** `Resources/Drums/` reads as
  472 KB of dead weight, but the live `BeatPlayer.resolveSampleRef` maps a saved
  `"drum:<Name>"` lane reference onto those files. Deleting the folder silences an upgraded
  user's lane with no error and no compile failure. **Before deleting any bundled resource,
  grep for code that resolves a PERSISTED string into a path under it.**
- **Removing a call can silently remove side effects you did not inventory.**
  `loadDefaultSamples()` was also the sole caller of four `restore*` persistence functions.
  Dropping the call dropped seven UserDefaults restores. Harmless today (all readers
  unreachable) but invisible in the diff. **Read the body of what you are un-calling, not just
  its name.**

## 2026-07-27 — DEAD-END: asking the founder about a path he cannot reach
I asked whether exported `.mid` files should keep their drum track. The app **cannot export a
`.mid` at all** — `exportMIDI()` has no caller, which CLAUDE.md already recorded. The question
was well-intentioned (it looked like a genuine product decision, not an engineering one) but
it spent founder attention on something that does not exist, and a "keep it" answer would have
been unimplementable as asked.

**RULE: before putting a product question to the founder, verify the feature it is about is
REACHABLE — same standard as a code claim.** The correctly framed version is usually a better
question anyway: not "should the export keep X" but "the export has no door — do you want one,
and with or without X".

## 2026-07-27 — DEAD-END: asserting a PHYSICAL mechanism from a language keyword (`weak` ⇒ "a lock")

**Was ich tat (#154).** Ich las `weak var value` im Render-Closure von vier Voices,
schrieb daraus einen Audio-Thread-Verstoß der Kategorie C ("weak-Load nimmt eine
Sperre, Side-Table-malloc im Render-Block") und meldete das so dem Founder.

**Warum es falsch war.** Der `audio-thread-reviewer` hat es widerlegt, und zwar auf
der Mechanismus-Ebene, nicht der Meinungs-Ebene: `swift_weakLoadStrong` geht über
die Side-Table `tryRetain()` → eine **lock-freie atomare CAS-Schleife**. Kein
`os_unfair_lock`, kein `pthread_mutex`. Und der Side-Table-**malloc passiert, wenn
die weak-Referenz GEBILDET wird** (Main-Thread, beim Node-Aufbau) — nie im Block.
Kosten ~10–30 ns unkontendiert gegen 5.333.000 ns Deadline (256 Frames @ 48 kHz)
≈ 0,004 %. Zusätzlich: der nil-Zweig ist unerreichbar, alle fünf Voices sind
App-Lebensdauer-Singletons.

**Die Regel.** Ein Sprach-Keyword ist eine SCHNITTSTELLE, keine Implementierung.
`weak`, `@objc`, `Array`, `String` — jedes davon steht auf der Verbotsliste WEIL
es typischerweise alloziert oder blockiert, aber „typischerweise" ist keine
Messung. Bevor eine Audio-Thread-Verletzung gemeldet (oder gar refactort) wird:
den tatsächlichen Runtime-Pfad benennen (welche Funktion, welche Synchronisation,
wo der malloc liegt) und die Kosten gegen die Block-Deadline stellen. Sonst
produziert die Verbotsliste Fehlalarme, die echte Verstöße im Rauschen ertränken.

**Do this instead.** Bei jedem Kandidaten der Audio-Thread-Liste zuerst
`audio-thread-reviewer` mit der Frage „welcher konkrete Runtime-Mechanismus, und
was kostet er gegen die Deadline?" — nicht mit „ist das ein Verstoß?". Die zweite
Frage bekommt immer ein Ja.

**Bonus-Ertrag (der eigentliche Wert des Zyklus).** Der Spezialist empfahl, den
Zyklus statt in den Refactor in die fehlende **Render-Pfad-Abdeckung** zu stecken.
Das war richtig: `MetronomeVoice` hatte NULL Render-Tests — jeder Test las die
`@Observable`-Kontroll-Properties, also hätte ein `didSet`, der seinen
`nonisolated(unsafe)`-Spiegel nicht mehr schreibt, die ganze Suite grün gelassen,
während der Klick auf dem Gerät verstummt. Merksatz: **wo die Kontroll-Ebene und
die Audio-Ebene über einen Spiegel gekoppelt sind, testet ein Test der
Kontroll-Ebene NICHTS.** Der Test muss durch die Render-Funktion.

## 2026-07-27 — PLAYBOOK: „grünes Gate" beweist nur, was das Gate ÜBERHAUPT baut

**Was ich tat.** Ich meldete dem Founder: Xcode Compile Check ✓ und CI/CD Pipeline ✓,
„also halten die vier neuen Render-Tests gegen den echten Render-Code". Der Reviewer
widersprach, ich prüfte selbst nach — er hatte recht.

**Der Sachverhalt (selbst verifiziert, nicht übernommen).**
`ci.yml` testet `-scheme Echoelmusic` → Target `EchoelmusicTests` → dessen `sources`
in `project.yml` ist **`Tests/CISmoke`**, nicht `Tests/EchoelmusicTests`. Es gibt in
KEINEM Workflow ein `swift test` (nur `swift build` in `quick-test.yml`). Der einzige
Ort, an dem `Tests/EchoelmusicTests` kompiliert und ausgeführt wird, ist das Schema
`EchoelmusicFullTests` in `full-tests.yml` — und dort trägt **jeder** xcodebuild-Schritt
absichtlich `continue-on-error: true`. Zusätzlich maskiert `ci.yml` Testfehler ohnehin
über `| tee test.log | xcpretty || cat test.log` (`cat` endet mit 0), direkt unter dem
Kommentar „Test failures MUST fail the build".

**Die Konsequenz, die man leicht übersieht.** Eine Änderung an einer **Quelldatei** ist
gated (sie liegt im App-Target, also reddet sie ci.yml, xcode-compile-check und
testflight). Eine Änderung an einer **Testdatei** ist es nicht. Ein Compile-Fehler im
Test taucht nur als Text in der Full-Tests-Zusammenfassung auf. „Beide Gates grün" heißt
für neue Tests also: **die Naht kompiliert**, nicht: **die Behauptungen stimmen**.

**Do this instead.** Bevor ein grünes Gate als Beweis für einen TEST zitiert wird:
prüfen, welches Schema welches Target mit welchen `sources` baut. Die Frage ist nicht
„ist der Lauf grün?", sondern „hat dieser Lauf diese Datei überhaupt angefasst?". Für
Echoel heute: Testdateien unter `Tests/EchoelmusicTests` **melden**, sie **sperren
nicht** — bis #139 landet und das Hauptschema das Volltest-Target übernimmt.

## 2026-07-27 — PLAYBOOK: der Reviewer-Ertrag Nr. 5 — „ein Test, der schon vorher grün war"

Vierter Fall in Folge, in dem der Pflicht-Reviewer nicht den Code, sondern die
**Beweiskraft** meiner Tests kippte. Diesmal in vier Varianten, alle derselbe Fehler:

1. **Tautologie.** `allSatisfy { $0.isFinite }` bei NaN-Pegel kann nicht scheitern —
   die Ausgangs-Sicherung (`AudioOutputGuard.silencingNonFinite`) macht NaN ohnehin zu 0,
   UND das Gift-Muster im Puffer (1234.5) ist selbst endlich, also besteht sogar ein
   Render, der gar nichts tut. Regel: **ein Clamp ist nur über ENDLICHE Werte außerhalb
   des Bereichs beobachtbar** — für alles, was eine nachgelagerte Sicherung ebenfalls
   abfängt, testet man die Sicherung, nicht den Clamp.
2. **Gift-Muster als Zweischneide.** Dasselbe Sentinel, das „nichts geschrieben" von
   „Stille geschrieben" trennt, lässt `energy > 0` bei einem No-op durchgehen. Wer ein
   Sentinel setzt, muss BEIDE Richtungen prüfen.
3. **Test läuft auf dem Default.** Die Fehlermeldung beschuldigte den `bpm`-didSet, aber
   der Test benutzte 120 BPM = den Default; ein toter didSet lässt den Spiegel korrekt
   stehen. Regel: **ein Test, der einen Setter prüft, muss den Wert vom Default
   WEGBEWEGEN** — sonst prüft er die Initialisierung.
4. Dasselbe nochmal beim Akzent-Schalter (`accentDownbeat = true` ist der Default).

**Do this instead.** Nach jedem neuen Test einmal fragen: „welche konkrete Mutation im
Produktionscode lässt genau diese Zeile ROT werden?" Wer keine benennen kann, hat eine
Zeile geschrieben, die nur so aussieht wie ein Test.

## 2026-07-27 — PLAYBOOK: ein DETERMINISTISCHER Test, der zwischen Läufen kippt, liest fremden Speicher

**Der Fund.** Der Volltest-Lauf meldete `EchoelDecimatorTests.testNoNaN` rot — auf dem
Vorgänger-Commit war er grün, und mein Commit fasste eine völlig andere Datei an. Die
bequeme Diagnose („unabhängig, vorbestehend") wäre falsch gewesen.

**Die Signatur, die man erkennen muss.** Der Test hat feste Eingabe, frische Instanz,
keine Uhr, keinen Zufall — er ist vollständig deterministisch. Und er bestand einen Lauf
und scheiterte den nächsten bei IDENTISCHEM Code. Ein deterministischer Test, der sich
nicht deterministisch verhält, hat genau eine Erklärungsklasse: er liest Speicher, der
ihm nicht gehört. Nicht „Flake", nicht „Simulator", nicht „Infrastruktur".

**Die Ursache.** `vDSP_desamp` verbraucht `(N-1)·I + P` Eingabewerte (Apple verlangt
sogar `(N-1)·I + aufgerundet4(P)`, weil die Taps 4-weise gelesen werden). Der Dezimierer
gab nur `input.count`. ~60 Floats aus fremdem Speicher, bei praktisch jeder
Eingabelänge. Endlicher Müll bestand den Test und verfälschte die Ausgabe trotzdem
still; nicht-endlicher Müll kippte ihn.

**Do this instead.** Bei jedem vDSP-Gleitfenster-Aufruf (`vDSP_conv`, `vDSP_desamp`,
`vDSP_filter`) die dokumentierte MINDEST-Eingabelänge nachrechnen und den Puffer danach
dimensionieren — nicht nach der Ausgabelänge. Die 4er-Aufrundung nicht vergessen; wer
nur auf `P` auffüllt, hat denselben Fehler in klein. `EchoelConvolution` in derselben
Datei machte es seit jeher richtig (vorreservierter Scratch), der Dezimierer war die
Ausnahme — also: existiert im selben File schon ein Nachbar, der die Grenze respektiert,
ist dessen Muster die Referenz.

**Und die ehrliche Grenze, die ich erst nach dem Review notiert habe:** KEINE
Swift-Zusicherung kann einen Lesezugriff außerhalb der Grenzen deterministisch fangen,
weil der Speicher dahinter oft schlicht null ist. Ein Test kann die Chance maximieren
(auf ein Ausgabe-Element zielen, dessen Fenster die Grenze ÜBERSPANNT, und zweiseitig
prüfen), aber das unbedingte Orakel ist ein Sanitizer. Wer behauptet, sein Test „nagelt
den Fix deterministisch fest", sollte vorher durchgehen, welche seiner Zusicherungen
unter dem ALTEN Code überhaupt scheitern konnten — bei mir waren es 2 von 4 nicht.

## 2026-07-27 — DEAD-END: „konstant N" behaupten und nur gerade Beispiele in die Tabelle schreiben

Ich schrieb, der Überlauf betrage „KONSTANT 61 Werte bei jeder Eingabelänge", und
belegte es mit einer Tabelle: n=64, 128, 256, 4096. Alle vier gerade. Weil
`outputLength` abrundet, sind es bei UNGERADEN Zählern 60, und bei Faktor 4
`59 - n % 4`. Meine eigene Tabelle testete meine eigene Behauptung nie, weil ich die
Beispiele aus derselben Intuition gezogen habe wie die Behauptung.

**Regel.** Wer eine Invarianz behauptet („konstant", „immer", „für jede Länge"), muss
die Beispiele so wählen, dass sie die Invarianz BRECHEN würden, wenn sie falsch ist —
also über die Restklassen des beteiligten Divisors streuen. Beispiele, die aus derselben
Annahme stammen wie die Behauptung, sind Dekoration, kein Beleg. (Die Behauptung stand
auch in der Betreffzeile, also in dem, was `git log` für immer zeigt.)

## 2026-07-27 — DEAD-END: „nichts anderes LIEST die Eigenschaft" als Freispruch für einen halben Fix

**Was ich tat (#164[2]).** Ich machte `SingleExport.targetLUFS` optional, damit „No
target" wirklich nichts normalisiert, und schrieb in die Commit-Nachricht: *„Nichts
anderes liest die Eigenschaft (`FloatingVisualWindow` weist nur −14 zu,
unverändert)."*

**Warum das eine Falle ist.** Der Satz ist über LESE-Zugriffe wahr und in der Wirkung
falsch. Eine **Zuweisung** eines fest verdrahteten Werts ist genau das, was einen Fix
halb macht — und `FloatingVisualWindow` ist per Standard sichtbar und hat einen
WAV-Knopf. Der Founder hätte „No target" gewählt, ein Fenster weiter getippt und
wieder −14 bekommen. Ich hatte die Formulierung unbewusst um „liest" herum gebaut,
sodass ein unbeteiligt klingender Nebensatz genau das Loch verdeckte.

**Die Regel.** Bei jeder Umstellung einer Einstellung auf einen neuen Typ oder eine
neue Semantik: **alle SCHREIBER aufzählen, nicht die Leser.** Ein Leser, der den alten
Wert liest, kompiliert nicht mehr — der Compiler findet ihn für dich. Ein Schreiber,
der einen alten Konstantwert setzt, kompiliert weiter und ist damit die einzige
Fehlerklasse, die nur ein Mensch findet. Und danach: **alle AUSGÄNGE aufzählen** (hier:
jeder Knopf, aus dem eine Datei fällt) und pro Ausgang sagen, ob er die Einstellung
befolgt. Ein halb verdrahteter Fix ist schlimmer als keiner, weil er als erledigt gilt.

**Zweite Lehre aus derselben Runde.** Ich extrahierte die geänderte Rechenzeile erst
NACH dem Review in eine reine Funktion. Vorher steckte sie in einer `async`-Methode
mit AVFoundation-Aufrufen und war damit unprüfbar — weshalb der ganze
Audio-seitige Teil des Fixes („nil ⇒ 0 dB") von keinem einzigen Test abgedeckt war,
während drei neue Tests die Enum-Auflösung prüften. **Wenn die eine Zeile, die das
Verhalten ändert, nicht testbar ist, ist sie am falschen Ort** — herausziehen, bevor
man Tests für das Drumherum schreibt.

---

## DEAD-END: eine falsche Behauptung entfernen ≠ eine wahre schreiben (2026-07-27, #158)

**Was passierte.** Die Website bewarb ein AUv3-Plugin, das seit dem 24.07. gelöscht ist.
Ich habe den Claim korrekt identifiziert, korrekt als CUT (nicht ROADMAP) eingestuft und
an ~25 Stellen entfernt — und an jeder Stelle **Ersatztext** geschrieben: „erreicht deine
DAW über eine virtuelle MIDI-2.0/MPE-Quelle plus WAV- und MIDI-Datei-Export". Ich habe
die ENTFERNUNG gegen den Code geprüft und die ERSETZUNG nicht. Ergebnis: ein falscher
Claim wurde durch vier ersetzt. `exportMIDI()` hat seit dem 02.07. keinen Aufrufer,
die virtuelle Quelle ist `._1_0` (nicht 2.0), `mpeEnabled` hat **nirgends** einen
Schreiber, und die Quelle entsteht nur bei aktiver Patchbay-Route. Zwei der neuen
Stellen waren HANDLUNGSANWEISUNGEN („Screenshot vom MIDI-Export-Share-Sheet"), also ein
Auftrag, einen Bildschirm zu fotografieren, den es nicht gibt.

**Die Regel.** Beim Korrigieren einer Unwahrheit ist der Ersatzsatz eine NEUE Behauptung
und braucht dieselbe Beweislast wie ein Feature-Claim: pro Substantiv im Ersatztext eine
`git grep`-Kette bis zum erreichbaren Aufrufer. Der Reflex „ich schreibe hin, was es
stattdessen kann" fühlt sich wie Ehrlichkeit an und ist ungeprüfte Behauptung.
Diagnose-Frage: *Habe ich für jedes Wort im neuen Satz eine Datei:Zeile?*

**Zweite Lehre — „nur Doku" ist kein Sicherheitsnetz.** Ich meldete „docs-only, also
lösen die Pfadfilter keine Gates aus" als Entwarnung. Tatsächlich merged
`.github/workflows/auto-merge-docs.yml` docs-Pushes von `claude/**` **ohne Review nach
main**, und `pages.yml` deployt danach auf die Live-Site. Fehlende Gates heißen hier
nicht „harmlos", sondern „ungeprüft veröffentlicht". Bei docs/-Änderungen ist der
Reviewer daher NICHT optional und muss VOR dem Push laufen, nicht danach.

**Dritte Lehre — halb korrigiert ist schlechter als unberührt.** Derselbe „`.wav` und
MIDI"-Claim stand an 14 weiteren, älteren Stellen. Zwei davon standen zwei Zeilen neben
einem Satz, den ich gerade korrigiert hatte. Wenn ein Fix eine Behauptung an Stelle A
entfernt und die identische an Stelle B stehen lässt, liest B sich hinterher wie
bestätigt. Entweder die Klasse ganz oder als eigene Aufgabe mit Beleg anlegen — aber
nie stillschweigend halb.

---

## DEAD-END: „Ich habe die Rechnung getestet" ist nicht „ich habe die Verdrahtung getestet"

**Zweimal in zwei Tagen dieselbe Form.** Beide Male war eine reine Funktion sauber
abgedeckt, während der Wert, der sie im Betrieb erreicht, aus einer Stelle kam, die
**kein einziger Test berührte** — und beide Male war genau diese Stelle der Bug.

- Loudness-Export: `steadyGainDB`/`normalizeGainDB` gut getestet; die −14 kam aus
  `AutoMixChain.targetLUFS`, einer gespeicherten Property **ohne jeden Schreiber**.
- rPPG-Gate: `pulseTrustworthy` gut getestet; der Publish-`guard` rief sie schlicht
  nicht auf. Nach dem Fix konnte man den Aufruf zurückdrehen — alle Tests blieben grün.

**Die Regel.** Nach jedem Extract-to-pure die Frage stellen: *„Wenn ich die
Aufrufstelle auf den alten Ausdruck zurücksetze — welcher Test wird rot?"* Ist die
Antwort „keiner", ist nur die Arithmetik gepinnt. Der Pin für die Verdrahtung ist ein
**injizierbarer Seam** (`resolvedTarget(from: UserDefaults)`, `_testRender(...)`),
getestet gegen eine Scratch-Instanz — nicht ein weiterer Test derselben reinen Funktion.

**Und die Falle in der Falle:** ich habe für beide Fälle einen Test geschrieben, der
behauptete, die Verdrahtung zu sichern, und in Wahrheit die reine Funktion mit sich
selbst verglich. Der Doc-Kommentar lobte sich sogar dafür, eine Tautologie gelöscht zu
haben — eine Ebene höher stand die nächste. **Ein Test, dessen Kommentar erklärt, was er
schützt, ist kein Beweis, dass er es schützt.**

## DEAD-END: eine Test-Schwelle, die den Bug dokumentiert statt an ihm zu scheitern

„No target" sollte den Master-Gain auf Unity zurückführen; die Totzone parkte ihn
dauerhaft 0.385 dB daneben. Mein Test prüfte `abs(g) < 0.5` — **großzügig genug, um den
Restfehler durchzulassen**, und die Zahl 0.5 war nicht zufällig: ich hatte sie gewählt,
weil 0.385 nicht bestand. Die Schwelle war eine stille Notiz über den Defekt.

**Die Regel.** Wenn eine Toleranz gewählt wird, weil der Ist-Wert sonst durchfällt, ist
das der Befund — nicht die Toleranz. Erst begründen, warum der Rest physikalisch da sein
DARF; wenn es keine Begründung gibt, ist die Toleranz `1e-6`.

## PLAYBOOK: grünes Gate ≠ gebaute Datei (Fortsetzung)

`xcode-compile-check` kompiliert `Tests/EchoelmusicTests` **nicht** (nur `Tests/CISmoke`).
Ein Reviewer meldete eine fehlende `nonisolated`-Markierung als wahrscheinlichen
Gate-Bruch — das Gate war grün, weil es die Datei nie angefasst hat. Ebenso lief
`auto-merge-docs.yml` grün **ohne zu mergen**: es diffed `origin/main..<sha>`, und ein
einzelner Nicht-docs-Commit in der Branch-Delta setzt `docs_only=false`, worauf der
Cherry-Pick-Schritt übersprungen wird und der Job trotzdem mit 0 endet.
**Vor „grün" immer fragen: was hat dieser Lauf tatsächlich AUSGEFÜHRT?**

## DEAD-END: einen Wert „vereinheitlichen", ohne zu prüfen, WELCHE der beiden Zahlen mehr Evidenz trägt

Befund: Bus sendet `analyzer.estimatedBPM`, Anzeige zeigt `displayBPM` (oktavgefaltet).
Diagnose damals: „der Bus hat die Faltung nicht" → Faltung auf den Publish-Pfad ziehen.
**Falsch, und zwar rückwärts.** `CameraAnalyzer.stabilisedBPM` faltet bereits
(`Video/CameraAnalyzer.swift:661-662`) — mit 40/200-Guards, gegen eine Referenz, die
echtzeit-slew-limitiert nachgeführt und bei Signalverlust genullt wird, plus
`octaveCorrected` gegen die Autokorrelations-Grundfrequenz. Der Bus trug also die
Ausgabe des STÄRKEREN Verfahrens; die Anzeige legt eine ZWEITE, evidenzfreie Faltung
darüber. „Vereinheitlichen" hieß in meiner Umsetzung: die schwächere Zahl gewinnt.

**Die Regel.** Wenn zwei Pfade verschiedene Werte tragen, ist die erste Frage nicht
„welcher Pfad hat die Korrektur nicht?", sondern **„welche der beiden Zahlen stützt sich
auf unabhängige Evidenz?"** — und dann die andere angleichen. Ein Blick in die Quelle des
Produzenten (hier: der Analyzer) klärt das in fünf Minuten und hätte den ganzen Commit
gespart.

## DEAD-END: gegen eine Referenz falten/klemmen, die selbst zum Ergebnis hin gezogen wird

`displayBPM` ist EMA-getrieben zum GEFALTETEN Wert hin. Damit hat
`D <- D + clamp(0.4*(fold(R,D) - D))` einen stabilen Fixpunkt bei `D = R/2`, sobald
`R > 1.6*D`: D=60, echte Rate 105 → faltet auf 52.5, D läuft 59, 58 … 52.5, und dort gilt
`105 > 84` weiter — **die Rastung löst sich nie**, bis die echte Rate ~20 % FÄLLT. Mein
eigener Doc-Kommentar behauptete das Gegenteil („ONE step, not a loop — a `while` would
collapse a genuine tachycardia onto a resting rate"). Ein Schritt pro 100-ms-Tick gegen
eine mitwandernde Referenz IST diese Schleife, nur über die Zeit verteilt.

**Die Regel.** Bei jeder Korrektur „X relativ zu Referenz R" prüfen: **wird R von X
beeinflusst?** Wenn ja, ist es eine Rückkopplung, keine Korrektur — und die Stabilität
muss ausgerechnet, nicht behauptet werden. Der Gegen-Entwurf steht im Repo:
`CameraAnalyzer` faltet gegen eine Referenz, die es bei Verlust auf 0 setzt („don't seed
the next lock from a stale median") und real-zeit-slew-limitiert nachführt.

**Zweiter Schaden, leicht zu übersehen:** der rohe Bus-Wert war der EINZIGE unabhängige
Zeuge, an dem ein Geräte-Log eine Anzeige-Rastung überhaupt sichtbar macht. Eine
„Vereinheitlichung" hätte alle vier Ausgaben (Zahl, Take-Tempo, Bus, Health-Schreibpfad)
aus EINEM Fehler speisen lassen. **Bevor zwei Pfade zusammengelegt werden: was verliert
man an Beobachtbarkeit?**

---

## 2026-07-27 — Drei Fallen aus einem Zyklus (#170 / #188), alle vom Pflicht-Reviewer

### DEAD-END: „defensiver Decoder" für einen Pfad ohne Schreiber

`#170` listete vier Stores. Zwei davon (`ArrangementStore`, `SessionRecorder`) haben
**null erreichbare Schreiber** — ihre Oberflächen sind gelöscht bzw. türlos. Ein Decoder,
der Datenverlust verhindert, ist dort wertlos: **die Datei wird nie überschrieben, also
kann nichts verloren gehen.** Der Aufwand wäre in eine Datei geflossen, die mit #132
sowieso stirbt.

**Stattdessen:** Erreichbarkeit ZUERST prüfen (wer SCHREIBT?), dann härten. Und die
Bedingung im Code hinterlegen: *wird die Fläche je wieder aufgemacht, muss ihr Decoder
IM SELBEN Slice mit* — der Re-Door ist genau der Moment, in dem niemand hinschaut.

**Nebenfalle im selben Fix:** `(try? decode([Lossy<T>].self)) ?? []` macht den
**Totalverlust** still, weil `dropped = 0 - 0 = 0` und die Telemetrie nicht feuert. Die
teilkaputte Variante war laut, die schlimmste stumm — exakt invertiert. `do`/`catch`,
`keyNotFound` still (legitimer Erstlauf), alles andere MIT Fehler loggen.

### DEAD-END: naiver Byte-Scanner auf SMF-Daten ist parameter-abhängig

Ein Test-Helper suchte Note-Ons per `(b[i] & 0xF0) == 0x90`. `serializeTrack` schreibt vor
End-of-Track ein `vlq(endTick - lastTick)`; bei `bars: 8` ist das `0x98 0x00` → der Scanner
meldet einen Ton in einer **leeren** Spur. Grün war der Test nur, weil die Fixture zufällig
`bars: 2` (`0x86`) nutzte. **Jeder, der die Fixture „realistischer" macht, bekommt Rot ohne
sichtbare Ursache.**

**Die Regel:** Ein Absenz-Assert über einem binären Format braucht einen echten Parser,
nie eine Byte-Suche. Und wenn der Kommentar die Nutzlast byteweise behauptet — die
Behauptung wirklich ausrechnen, inklusive der Delta-Zeiten.

### PLAYBOOK: einen Kommentar zitieren, der sich selbst widerspricht

Ich begründete eine Änderung mit „der Komponist füllt `pattern.steps` (siehe :4017)" —
und zitierte damit die **erste Hälfte** eines Kommentars, dessen **Schwanz sechs Zeilen
später** sagt, dass der Beat 2026-07-07 entfernt wurde (`BioComposer.silentBeat()` liefert
leere Raster). Die Änderung war trotzdem richtig, nur aus einem anderen Grund
(`open(_:)` lädt `p.drumSteps` aus Alt-Projekten zurück).

**Die Regel:** Ein zitierter Kommentar-Block wird **bis zum Ende** gelesen, bevor er als
Beleg dient — in diesem Repo dokumentieren Kommentar-Schwänze routinemäßig, dass der Kopf
überholt ist. Und: die Begründung am **verifizierten Datenpfad** aufhängen, nicht am
plausibelsten.

### PLAYBOOK: Test-Abdeckung nicht behaupten, sondern eingrenzen

Header behauptete „diese Tests schlagen an, wenn jemand X zurückholt". Sie prüften den
**Exporter**, nicht die **Aufrufstelle** — das Zurückholen der einen Produktionszeile lässt
die Suite grün. Falsche Abdeckung ist schlimmer als keine. Wenn die Aufrufstelle nicht
testbar ist (privat, in einer 4000-Zeilen-`@MainActor`-View ohne Injektionsnaht), gehört
genau das in den Header — plus die Notiz, dass die Extraktion eine eigene Scheibe ist.

### DEAD-END: einen geteilten Detektor „bei Quellenwechsel zurücksetzen"

Ein `BioEventGraph` wurde von ALLEN Bio-Quellen gefüttert, also produzierte er Flanken,
die zu keiner gehörten. Mein Fix: `graph.reset()` sobald `frame.source` wechselt. Er
beruhte auf einer Annahme, die ich nicht geprüft hatte — **dass die Quellen sich
abwechseln.** Tun sie nicht: `stopBioSource()` stoppt Kamera/Gurt/Demo, aber NICHT
`HealthKitBioPublisher`, der beim ersten Bio-Gebrauch startet und danach neben der
gewählten Quelle weiterpubliziert. Der Bus **verschränkt**, also feuerte der Reset zweimal
pro HealthKit-Sample und löschte die `previous` der Kamera zwischen deren eigenen Frames:
aus einem Phantom-Ereignis wurde Taubheit für echte Atmung. Schlechter als der Bug.

**Stattdessen:** Zustand **pro Quelle** halten (`[BioSource: BioEventGraph]`). Das entfernt
die Klasse, statt ein Artefakt gegen ein anderes zu tauschen — jede Quelle behält ihre
eigene Trajektorie, eine Flanke KANN nicht mehr zwei Quellen überspannen.

**Die Regel:** Bevor „bei Wechsel zurücksetzen" als Fix gilt, die **Lebenszyklus-Besitzer**
aller Produzenten nachlesen (wer startet sie, wer stoppt sie — hier: `stopBioSource` in
`EchoelStudioView`, `EchoelmusicApp`). „Wechsel" setzt Exklusivität voraus; in diesem Repo
ist Exklusivität die Ausnahme, nicht die Regel. Zweite Lehre: ein Reset ist nicht
automatisch harmlos-unterdrückend — `MotionPeakDetector` wird davon *scharfgestellt*.

⛔ **DIESER EINTRAG WURDE ZWEIMAL WIEDER UMGESETZT, VON MIR, IN DERSELBEN BUS-SCHICHT
(#813 und #920, korrigiert in #920c 2026-08-31).** `Core/CoherenceTrend` war ein GETEILTER
Zähler über `bus.latestBio`; #920 hängte obendrauf genau den hier begrabenen
Quellenwechsel-Reset. Die Kosten waren dieselben und lebend: HealthKit veröffentlicht ein
ehrliches `coherence: 0`, also war `isMeasured` für jeden Handgelenk-Frame falsch, also
leerte der Zähler alle ~4–5 s seine ganze Historie — auf einem ~1-Hz-Kamera-Feed sägte der
Trend zwischen 0 und 0,2111, statt auf 0,3459 zu steigen; der Spektralmorph wurde alle vier
Frames auf die Patch-Form entlassen. Reparatur: `[BioSource: Run]`, exakt die oben
verschriebene Form.

**Zwei Zusätze zur Regel, die dieser Rückfall gekostet hat.** (1) Der Eintrag nennt
`BioEventGraph` namentlich, und beide Rückfälle betrafen einen ANDEREN Typ auf demselben Bus
— **wer eine DEAD-END-Zeile liest, liest sie als Aussage über die SCHICHT, nicht über den
genannten Typ.** (2) `isMeasured`-false ist derselbe Mechanismus wie ein Reset: jeder
geteilte Zustand hinter einem „gemessen?"-Tor wird von der stillsten Quelle regiert, auch
ohne dass irgendwo `reset()` steht. Herleitung und Messtabelle: `memory/LEDGER_COUNTS.md` §L.2.

### PLAYBOOK: geteilter Zustand hinter einem „gemessen?"-Tor — HALTEN, nicht nullen

**Das Gesetz, zweimal unabhängig hergeleitet (#920c 2026-08-31).** Auf `bus.latestBio`
INTERLEAVEN die Quellen (`stopBioSource()` stoppt HealthKit nicht). HealthKit veröffentlicht ein
ehrliches `coherence: 0`, also ist `isMeasured` für jeden Handgelenk-Frame falsch. Jeder
Verbraucher, der daraufhin **zurücksetzt oder auf 0 springt**, wird damit von der STILLSTEN
Quelle regiert — auch wenn nirgends `reset()` steht.

**Die Reparatur hat zwei Hälften, und beide werden gebraucht:**
1. **Zustand PRO QUELLE** (`[BioSource: …]`), damit die Historie einer Quelle nicht von einer
   anderen gelöscht wird. Siehe die DEAD-END-Zeile darüber.
2. **Ein Frame ohne diesen Kanal HÄLT den zuletzt gemeldeten Wert**, er nullt ihn nicht. Sonst
   flackert die Ausgabe alle paar Sekunden auf neutral — dieselbe Taubheit eine Ebene tiefer.

⭐ **`Tools/FXBioModulator` hatte Hälfte 2 schon richtig, unabhängig und aus einem anderen
Anlass**: `FXRouteFade` „hold[s] the last real offset and fade[s] it, rather than snapping to
zero the tick a sensor drops out", und der Kommentar nennt HealthKit namentlich. `CoherenceTrend`
kam #920c über den Interleave-Befund zur selben Regel. **Zwei unabhängige Herleitungen desselben
Gesetzes sind der Grund, warum es hier als PLAYBOOK steht und nicht als Notiz an einer Datei.**

**Sweep-Ergebnis 2026-08-31, damit es niemand wiederholt.** Alle `isMeasured`-Aufrufer in
`Sources/` durchgesehen: `FXModulation.contributions` ist eine REINE Anzeigefunktion (eine
ungemessene Zeile rendert „—", kein Zustand) · `VisualModulation` überspringt per `continue` und
analysiert die Folgen im eigenen Kommentar ehrlich · `FXBioModulator` hält und faded (siehe oben)
· `AlwaysOnBioChannel` ist zustandslos je Frame. **Kein weiterer Defekt dieser Klasse gefunden.**
⚠️ EINE Frage bleibt offen und ist NICHT gemessen: ob der Ein-Frame-Abfall der reinen Pfade auf
einer Fläche sichtbar zuckt, wenn ein Handgelenk-Frame dazwischenfällt. Das braucht ein Gerät,
kein `grep`.

### DEAD-END: eine Oberfläche entfernen und ihre Autorität stehen lassen

Slice 4 löschte die Arrangement-UI. Das persistierte Dokument blieb — und blieb der ERSTE
Leser im Play-Handler. Ergebnis: ein Knopf, der auf Daten hört, die der Nutzer weder sehen
noch löschen kann. Der Founder drückte ▶ und bekam einen Breakbeat aus einer Session von
vor Wochen.

**Die Regel:** Beim Entfernen einer Fläche IMMER prüfen, welche Entscheidungen ihr Modell
noch trifft — nicht nur, wer es anzeigt. `git grep` auf den Store-Typ, nicht auf die View.
Unerreichbare Daten mit Entscheidungsgewalt sind schlimmer als sichtbare Altlast: der
Nutzer kann den Zustand nicht einmal benennen, geschweige denn aufräumen.

### PLAYBOOK: „das bleibt, weil es tragend ist" — erst den Guard lesen

Ich verteidigte einen Codeblock als „live", weil ein Relay ihn pro Tick aufruft. Der Aufruf
erfolgte tatsächlich — und kehrte in Zeile zwei an `guard isPlaying` um, das nach meiner
eigenen Änderung nie mehr wahr wird. Eine Aufrufkette beweist keine Wirkung.

**Die Regel:** Bevor ein Block als tragend deklariert wird (besonders in einem Kommentar,
den eine spätere Löschung lesen wird): den ERSTEN Guard der Methode lesen und prüfen, ob
seine Bedingung nach der aktuellen Änderung überhaupt noch erreichbar ist. Ein falsches
„tragend" kostet keinen Bug, sondern eine verweigerte Löschung — teurer, weil es niemand
als Fehler bemerkt.

### DEAD-END: eine Referenzliste per `grep` erheben und Kommentare als Kanten zählen

Der Entfernungsplan für das DAW-Modell führte `DSP/AudioOutputGuard.swift` und
`Audio/AudioOutputGuard+PCMBuffer.swift` als Referenzen auf `TimelineAudioSink` — beide sind
`///`-Prosa. Dieselbe Datei nannte `CloudSync`/`AppGroupStore` als `ClipStore`-Nutzer, auch
Prosa. **Und in beiden Fällen fehlte die eine echte Kante**, weil sie in einer Closure lag
(`makeSink: { TimelineAudioSink(...) }`, `resolveURL: { clipStore?... }`). Ein Zyklus, der
aus so einer Liste geplant wird, arbeitet an Kommentaren ab und läuft unvorbereitet in die
App-Verdrahtung.

**Die Regel:** Jeder `grep`-Treffer wird VOR der Planung als **Code oder Prosa** klassifiziert,
und Konstruktions-Closures (`makeX:`, `resolve…:`, Sink-/Factory-Parameter) werden separat
gesucht — sie tauchen bei einer Suche nach dem Typnamen zwar auf, aber in einer Datei, die
man beim Überfliegen für „nur Verdrahtung" hält.

### DEAD-END: eine türlose View als Beleg dafür, dass ein Modell „lebt"

Ich begründete den Erhalt des Spur-Modells damit, dass `SpatialSceneStore.rebuild(from:)`
„der Immersive-Stage-Pfad" sei. Die beiden Aufrufer liegen in `ImmersiveStageView` — einer
View mit NULL Instanziierungen, die CLAUDE.md ausdrücklich als „doorless — deliberately"
führt. Das ist eine Compile-Kante, keine Laufzeit-Kante. Die Schlussfolgerung stimmte
zufällig (es gibt eine echte Kante über den Generate-Pfad), die Begründung nicht.

**Die Regel:** Als Lebendigkeits-Beleg zählt nur eine Kette bis zu einem RENDERNDEN oder
pro Tick laufenden Aufrufer. In diesem Repo sind mehrere Views absichtlich türlos — sie
sehen im Graphen aus wie Konsumenten und sind keine. Dieselbe Falle wie bei
„Slot + Setzer beweist keine Erreichbarkeit", nur eine Ebene höher.

## 2026-07-31 — Drei Fallen aus #279/#294, alle vom Pflicht-Reviewer

### DEAD-END: eine Sentinel-Wahl treffen, ohne die ausgelieferten Werte zu MESSEN

Ich wollte die neuen Bio-Anker (`bioBaseVibratoRate`/`Depth`/`bioBaseLFOToFilterDepth`) mit
`0` als „nicht gesetzt"-Sentinel bauen — so wie `bioBaseFilterCutoff`/`bioBaseBrightness` es
tun. Die Messung sagte etwas anderes: **26 von ~36 ausgelieferten Patches liefern
`vibratoRate: 0, vibratoDepth: 0` als LEGITIMEN Wert**. Mit `0` als Sentinel hätte genau die
Mehrheit der Patches den Legacy-Pfad bekommen — der Fix hätte die Patches enteignet, die er
schützen soll.

**Die Regel:** Ein Sentinel ist nur dann frei wählbar, wenn er außerhalb der ausgelieferten
Wertemenge liegt. Vor der Wahl die Palette zählen (`SynthPatch.factory` + `MusicStyle.offered`
+ `PatchLibrary.all`), nicht die Nachbarkonstante kopieren. Dass die Sentinel-Konventionen in
`EchoelDDSP` sich unterscheiden (`0` hier, `-1` dort), ist deshalb **tragend, nicht schlampig**
— wer sie „vereinheitlicht", baut diesen Bug ein.

### DEAD-END: einen Kopfraum-Test gegen EINEN Multiplikator schreiben, wenn die Live-Kette zwei hat

Der Test, dessen einzige Aufgabe es ist, rot zu werden BEVOR eine neue Klemme anfängt zu
formen (statt nur Unmögliches zu fangen), rechnete `patch.filterCutoff * 1.3` — die Bio-Rail.
Die echte Kette hat davor noch `RoleRhythm.TimbreTrim.trimmed` (≤1.12, läuft auf **jedem**
Generate und jedem Preset-Recall), und genau dieser getrimmte Wert wird zum Anker. Real:
1.12 × 1.3 = **1.456**. Der Test wäre 12 % zu spät rot geworden; ein 13-kHz-Preset wäre in der
App längst geklemmt worden, während das Gate grün blieb.

**Die Regel:** Ein „nichts Ausgeliefertes wird berührt"-Test muss die Kette vom persistierten
Wert bis zur geklemmten Stelle vollständig ablaufen, nicht den letzten Faktor nehmen. Und er
muss die vollständige Palette einschließen — meine erste Fassung ließ `PatchLibrary` weg, das
den höchsten Cutoff im Repo hält (8000 Hz), obwohl es heute türlose tote Daten sind.

### PLAYBOOK: der Kommentar, der das GEGENTEIL seines eigenen Bugs behauptet

Der Doc-Kommentar der neuen Konstante `EchoelDDSP.cutoffRange` listete „das Bio-Ziel in
`applyBioReactive`" als eine von vier bereits vorhandenen Kopien der Domäne. Das Bio-Ziel
hatte **keine** Klemme — dieses Fehlen IST #294. Die gefährlichste Zeile des Zyklus stand im
Commit, der den Bug fixte, und behauptete, es gäbe ihn nicht.

**Der Mechanismus, warum das überlebt:** Prosa wird nicht ausgeführt. Ein falscher Satz in
einem Kommentar hat keinen Gate, keinen Test und keinen Compiler gegen sich — nur einen
Leser. In diesem Repo hat der Pflicht-Reviewer an EINEM Tag **zwölf** solcher Sätze über drei
Commits gefunden, jeder neben einem korrekten Mechanismus.

**Die Regel:** Wenn ein Kommentar eine Zählung, eine Palette oder eine Garantie behauptet,
gehört der Befehl bzw. die `file:line`-Belegstelle daneben — und die Behauptung wird gegen die
Änderung geprüft, die der Kommentar begleitet. Ein Kommentar, der beschreibt, wie es VOR dem
Fix war, muss das sagen. Verwandt: „ein ‚NICHT löschen'-Kommentar mit falscher Begründung ist
schlimmer als keiner — die nächste Session kann ihn nicht widerlegen" (CLAUDE.md, #167).

### PLAYBOOK: `bioBase*`-Mappings zentrieren auf 0.5 — und 0.5 ist 120 BPM, nicht Ruhe

`heartRate` erreicht `applyBioReactive` als `clampUnit((frame.heartRateBPM - 40) / 160)`
(`PolySynthVoice.swift:667`, `BioReactiveSynthVoice.swift:387`). Alle fünf `bioBase*`-Mappings
sind um 0.5 herum neutral, **also um 120 BPM**. Ein ruhender Puls von 60 BPM ergibt 0.125 und
damit rund 0.81× — nicht 1.0. Wer „bei Ruhe passiert nichts" in einen Kommentar oder eine
Test-Erwartung schreibt, liegt um ~19 % daneben.

## PLAYBOOK (2026-08-08 #478 discriminator without reading a log)
- **PLAYBOOK: der #478-Diskriminator steht in den STEP-CONCLUSIONS, nicht im Job-Log.**
  Solange #396 lebt, meldet `Echoelmusic CI/CD Pipeline` auf JEDEM Push `failure`, und die
  bisher aufgeschriebene Unterscheidung — `** TEST BUILD FAILED **` gegen
  `** TEST EXECUTE FAILED **` — verlangte, den Job-Log zu holen und zu durchsuchen. Der
  Log ist regelmäßig 100 KB+ und sprengt das Kontextfenster; `get_job_logs` mit kleinem
  `tail_lines` liefert nur den Post-Job-Cleanup und damit gar keinen Diskriminator.
  **Billiger und exakt gleichwertig:** `mcp__github__actions_list` mit
  `method: list_workflow_jobs` auf die run_id. Der Job „Build & Test (iOS)" listet seine
  Schritte einzeln; **Schritt 9 „Build for Testing"** und **Schritt 11 „Run Tests"** tragen
  je eine eigene `conclusion`. `Build for Testing: success` + `Run Tests: failure` IST
  `TEST EXECUTE FAILED` (also #396, harmlos, das Bundle kompiliert nachweislich).
  `Build for Testing: failure` IST `TEST BUILD FAILED` — und ERST DANN lohnt der Log, um
  die zweite #478-Frage zu beantworten (nennt eine `error:`-Zeile eine Repo-Datei = mein
  Commit, oder nur SDK/ModuleCache = Infrastruktur-Flake).
  ⚠️ GRENZE, damit daraus keine Überdehnung wird: das ersetzt NUR die Build-gegen-Execute-
  Frage. Ob ein EINZELNER neuer Wächter gelaufen ist (#445), steht weiterhin nur als
  `passed`-Zeile im Log — und sein FEHLEN beweist nichts, weil die Clone-Zuteilung nicht
  deterministisch ist. Belegt am 2026-08-08 an `3368976` (Lauf 31248024707, Job
  93079793669): Build for Testing `success` 08:17:28→08:19:55, Run Tests `failure`
  08:19:55→08:32:50, `list_workflow_jobs` passt vollständig in eine Antwort, der Job-Log
  nicht.

## DEAD-END (2026-08-20 #642 review — eine Distanz zwischen zwei Zeilen ist ein Datum)
- **DEAD-END: eine Zahl, die den ABSTAND zwischen zwei Zeilen DERSELBEN Datei nennt, wird
  gelöscht, nicht aktualisiert.** Ein Kommentar in `EchoelFXView` begründete „der Kopf
  beobachtet nichts Neues" mit „diese Zeile liest es etwa dreißig Zeilen weiter oben". VIER
  Fassungen trugen eine Zahl: „eine Zeile darüber" (falsch), „~30" (auf `b1effab` richtig),
  wieder „~30" in genau dem Commit, der einen siebenzeiligen Block DAZWISCHEN einfügte und den
  Abstand auf 40 schob, und dann „FORTY" — das drei weitere Kommentarzeilen im selben Review-Pass
  auf 43 setzten, bevor es je committet war. Der Satz trug bereits eine ⛔-Notiz mit den Worten
  „und niemand hat nachgesehen". Niemand sah nach.
  **Do this instead:** die BEHAUPTUNG ohne Zahl schreiben („weiter oben im selben Rumpf") und
  daneben sagen, wie man sie prüft (die zwei `modulator.`-Lesestellen ansehen). Eine
  Zeilennummer ist in diesem Repo schon als unbelastbar aufgeschrieben; ein ABSTAND ist
  schlimmer, weil er von ZWEI Positionen abhängt und jede Prosa-Einfügung dazwischen ihn
  ändert — auch die Einfügung, die ihn gerade korrigiert. Die Klasse gilt für jede Zahl, deren
  Messgröße der eigene Commit bewegt.
- **DEAD-END (gleicher Zyklus, andere Familie): eine Aufzählung wird gegen den CODE geprüft,
  nie gegen ihre eigene Symmetrie.** „Vier Zustände und ihre VIER Strings" stand in sechs
  Dateien; es sind drei, weil `.noRoutes` und `.body` sich einen Text absichtlich teilen — und
  **derselbe Commit enthielt seine Widerlegung zweimal**: eine Testbehauptung, die genau diese
  Gleichheit prüft, und ein Doc-Block, der gegen einen fünften Fall argumentiert, WEIL dessen
  Text ein Duplikat wäre. Vier Fälle → vier Strings klingt vollständig und wird deshalb nicht
  gefahren. Identisch zur DDSP-Tabellen-Lehre in `CLAUDE.md` („ein Ziel je Kanal"), nur eine
  Ebene kleiner. **Do this instead:** bei jeder n→n-Behauptung die zweite Seite ZÄHLEN
  (`grep -c 'return "'` auf den `switch`), bevor man sie aufschreibt.

## DEAD-END (2026-08-20 #645 — ein Doc-Kommentar landet auf der falschen Deklaration und NICHTS wird rot)

**Was passiert ist.** #644 hat `BioNarrationDriver` in `Sequencer/BioMusicDirector.swift`
eingefügt — und zwar ZWISCHEN den vierzeiligen Doc-Block von `BioExplanation` und
`BioExplanation` selbst. Swift hängt einen `///`-Block an die nächste Deklaration darunter,
also beschrieb er ab da den neuen Enum, und der Typ, nach dem die Datei benannt ist, stand
undokumentiert da. Gefunden erst einen Commit später, beim Lesen der Umgebung einer
Folge-Änderung.

**Warum kein Werkzeug es fängt.** Es kompiliert. Es rendert in Quick Help. Es liest sich
plausibel, weil beide Typen zum selben Thema gehören — der geerbte Block sagte
„Plain-English, on-device explanation …", und der Enum darunter beschreibt genau, WER in
dieser Erklärung gemeint ist. Ein Reviewer, der den Diff liest, sieht nur die eingefügten
Zeilen; der Schaden entsteht an der Zeile DAVOR, die im Diff gar nicht vorkommt.

**Statt dessen:** beim Einfügen eines Typs über einem bestehenden nicht nur prüfen, was
darunter steht, sondern was DIREKT ÜBER dem Einfügepunkt steht. Ist es ein `///`-Block,
gehört er dem Typ darunter — also dem, den man gerade verdrängt hat. Billiger Test:
`grep -n "enum \|struct \|class " <datei>` und für jede Deklaration einen Blick auf die Zeile
davor.

**Verwandt, aber NICHT dasselbe:** die Zeilennummern-Lehre („eine zitierte Phrase überlebt
eine Einfügung, eine Zeilennummer nicht"). Hier überlebt die Phrase sehr wohl — sie wandert
nur an ein anderes Objekt. Dieselbe Familie wie die 415-Zeilen-Zahl aus #473, die an das
falsche Ding geheftet war: nicht veraltet, sondern von Anfang an falsch zugeordnet.

## DEAD-END: `git add -A` in der Verifikations-Phase, danach noch editieren

**#741 hat zwei von vier Reparaturen ausgeliefert und in seiner Nachricht vier behauptet** —
in genau dem Commit, dessen Thema „ein Zeiger hat den Umzug überlebt, den er beschreibt" war.

Der Mechanismus ist rein mechanisch und deshalb wiederholbar: die Verifikations-Zeile lautete
`git add -A && git diff --cached … && git status`, danach fielen beim Nachlesen zwei weitere
Fundstellen auf, die noch editiert wurden — und `git commit -F <datei>` **ohne `-a`** committet
nur den STAGE. Der Stop-Hook hat es gefangen, kein Test und kein Reviewer hätte es können: der
Baum war korrekt, nur der Commit nicht.

**Regel:** `git add -A` gehört in dieselbe Kommandozeile wie `git commit`, nie in die
Verifikations-Zeile davor. Wer zwischen Stagen und Committen noch etwas anfasst, hat einen
Commit gebaut, den er nie gesehen hat. Gegenprobe vor dem Push, eine Zeile:
`git status --short` muss LEER sein — nicht „nur Kleinkram".

## DEAD-END (2026-08-22 #745): eine Mutations-Probe, die den Baum EINMAL auflistet

**Der Mechanismus.** Ein Wächter mit VORWÄRTS-Behauptungen („keine ANDERE Datei nennt X")
wird bewiesen, indem man eine neue Datei anlegt, die X nennt. Meine Probe hat `Sources/`
aber einmal am Anfang aufgelistet und die Liste wiederverwendet — **die Mutanten-Datei war
in dieser Liste nicht drin**. Drei von acht Behauptungen meldeten daraufhin „kein Rot",
also exakt das Bild eines Wächters, der nicht scharf ist.

**Warum das gefährlich ist und nicht bloß lästig:** ein MISMATCH liest sich wie ein Befund
über den WÄCHTER („die Behauptung kann nicht rot werden"), ist aber ein Befund über die
PROBE. Wer ihn beim Wortsinn nimmt, schwächt oder löscht eine korrekte Behauptung.

**Zweite Falle im selben Lauf:** der erste Mutant für eine Teilstring-Nadel benannte
`case admOSCCartesian` in `…CartesianXX` um — die Nadel ist ein TEILSTRING, die Zusicherung
sah also gar keine Änderung. **Eine Mutation, die die Zusicherung nicht von der Vorlage
unterscheiden kann, ist keine Mutation.** Bei Teilstring-Nadeln die Zeile LÖSCHEN.

**Regel:** in der Probe wird der Baum INNERHALB jeder Prüfung gelaufen, nie davor
zwischengespeichert — und jeder Mutant wird daran gemessen, ob er die Nadel wirklich
zerstört. Beides ist die #739-Lehre eine Ebene höher: **eine Kontrolle, die ihr eigenes
Positiv besteht, ist keine Kontrolle — das gilt auch für die Probe, nicht nur für den
Wächter.**

## PLAYBOOK (2026-08-23 #752): die Geräte-Bitten einsammeln, bevor man den Founder fragt

**`python3 scripts/founder-verify.py`** druckt jeden `NEEDS-FOUNDER-VERIFY`-Vermerk aus
`Sources/`, `Tests/` und `CLAUDE.md` als Liste nach Bereichen (`--all`, `--area bio`,
`--selftest`). Stand nach #753: **50 Bitten in 48 Dateien**, plus vier Prosa-Stellen, die
den Marker als Substantiv tragen und getrennt unter „NOT ASKS" stehen.

**Warum das ein Playbook und keine Spielerei ist:** die zwei offenen Ship-Gate-Checks sind BEIDE
sensorisch. Der Engpass des Projekts ist Geräte-Zeit des Founders — und die Warteschlange dafür
lag als Fließtext in fünfzig Dateien verstreut. Wer eine Geräte-Session vorbereitet, plant sie
aus dieser Liste, statt sich an drei Bitten zu erinnern.

⚠️ **Zwei Zahlen für dieselbe Sache, und beide sind richtig:** `git grep -o NEEDS-FOUNDER-VERIFY`
über vier Wurzeln (inkl. `scratchpads/`) liefert **108 VORKOMMEN**; das Skript zählt **50 ZEILEN**
über drei Wurzeln. Verschiedene Operation, verschiedener Bereich — genau die Klasse Fehler, die
dieses Repo „SCHREIB-Rate gegen LESE-Rate" nennt. **Wer die Zahl zitiert, nennt Operation UND
Bereich mit.**

⚠️ **Grenze, die das Skript selbst druckt:** es kann eine BEANTWORTETE Bitte nicht von einer
offenen unterscheiden — es gibt keine „erledigt"-Konvention im Baum. Die Reparatur wäre eine
Konvention (`VERIFIED-<Datum>` auf derselben Zeile), kein schlauerer Parser.

⭐ **Der Selbsttest hat beim ERSTEN Lauf einen echten Fehler gefangen:** `MetalBioView.swift`
trägt „Metal" UND „Bio", und mit `bio` zuerst landete der Visual-Renderer im falschen Fach. Die
Reihenfolge der Bereiche IST die Tie-Break-Regel; sie steht jetzt als Kommentar daneben. Das ist
die #739-Lehre in ihrer nützlichen Richtung — eine Kontrolle, die etwas findet, bevor der Code
das erste Mal committet wird.

## DEAD-END (2026-08-23 #753): der Marker ist auch ein Substantiv — das Werkzeug zählte sich selbst

**Was passiert ist:** #752 registrierte `founder-verify.py` in `CLAUDE.md` mit dem Satz
„es sammelt jeden `NEEDS-FOUNDER-VERIFY`-Vermerk". Der nächste Lauf meldete **54** statt 53
Bitten. Die 54. war die Beschreibung des Werkzeugs. Insgesamt vier solche Zeilen: zwei in
`CLAUDE.md`, zwei in Wächter-Köpfen, die ÜBER den Rückstand reden.

**Die naheliegende Regel wurde gemessen und verworfen — das ist der eigentliche Eintrag.**
Naheliegend war: „eine echte Bitte hat einen Doppelpunkt hinter dem Marker". Gemessen über
alle 54 Treffer: **30 verschiedene 3-Zeichen-Enden**, und **15 der Nicht-Doppelpunkt-Fälle
sind echte Bitten** („NEEDS-FOUNDER-VERIFY on device…", „…, and the honest failure mode…").
Diese Regel hätte dem Founder fünfzehn Aufträge versteckt, um vier Sätze zu entfernen.

**Was stattdessen trägt:** das Wort DAVOR. Eine Bitte hat nie einen Artikel vor sich, eine
Substantiv-Nutzung immer („the backlog", „jeden Vermerk", „aus dem der …-Rückstand").
Markup dazwischen wird gestrippt.

⭐ **Die RICHTUNG ist die Sicherheits-Eigenschaft, nicht die Trefferquote.** Die Regel kann
eine Zeile nur AUS der Liste nehmen, und nur bei einem Artikel davor. Eine ohne Artikel
formulierte Referenz bleibt als Bitte gezählt — Rauschen, das einen Blick kostet. Eine
versteckte Bitte kostet eine Geräte-Session. **Wer eine Heuristik über eine Warteschlange
legt, entscheidet zuerst, in welche Richtung sie falsch liegen darf.**

⛔ **Und ein Mutant lief GRÜN durch fünf Prüfungen:** wer die Trennung in `collect()`
aushängt (`if det:` → `if False:`), lässt `is_reference()` unberührt — alle Prüfungen, die
die REGEL testen, bleiben grün, während die Kopfzeile wieder 54 zählt. Prüfung 6 misst
deshalb die VERDRAHTUNG als Eigenschaft über den echten Baum („keine Zeile in der
Auftragsliste hat einen Artikel davor") statt als Zahl — eine Zahl wäre beim nächsten
Vermerk veraltet. **Eine Kontrolle über eine Funktion beweist nicht, dass jemand sie ruft.**

⚠️ **Grenze:** `--selftest` läuft in KEINEM CI-Gate, so wenig wie `doctor.py`. Es ist ein
Werkzeug mit eigener Kontrolle, kein Wächter im blockierenden Bundle — ein zweiter Swift-
Wächter, der Python aufruft, wäre #416.

## PLAYBOOK (2026-08-23 #754): nach einer Löschung den Doctor laufen lassen — und seine Diagnose prüfen

**`python3 scripts/doctor.py --section B`** findet Wächter-Nadeln, deren Deklaration nicht
(mehr) existiert. #748 löschte eine Funktion und ließ eine Nadel darauf stehen; der Doctor
fand sie einen Zyklus später.

⛔ **Seine SCHLUSSFOLGERUNG war trotzdem falsch, und der Fehler ist wiederholbar:** die Nadel
stand in einem NEGIERTEN `contains(`. Die Form `contains("foo()") && !contains("func foo")`
heißt „ein AUFRUF, nicht die Deklaration". Zeigt die negierte Hälfte ins Leere, ist sie ein
**No-op** — sie kann kein falsches Grün erzeugen, und die POSITIVE Hälfte derselben Zeile
trägt die Wahrheit weiter. **Ein Befund über eine Nadel ist erst dann ein Befund, wenn man
gelesen hat, ob sie bejaht oder verneint wird.**

⚠️ **Ausnahme per NADEL, nie per ZEILE** (eine Zeile trägt beide Formen), und **nie über
Nachbarzeilen** — die Begründung steht seit langem über der `absence`-Ausnahme im selben
Block. Gemessen vor der Regel: 261 Nadel-Zeilen, **sechs** in negierter Form.

⭐ **Beide Richtungen bewiesen, bevor der Commit lief:** eine echte Phantom-Nadel wird
weiterhin gemeldet (Sonde in eine getrackte Datei geschrieben, danach byte-identisch
zurück), und die Mutation „per Zeile" macht den neuen `--selftest` rot. `doctor.py` hatte bis
hierher gar keine Kontrolle; die neue prüft **eine** Regel und sagt das in ihrer Ausgabe.

## DEAD-END (2026-08-23 #755): eine Kopie-Bereinigung, die nur Swift scannt, bereinigt die Hälfte

**#496 nahm drei erzeugerlose Bio-Kanäle (`breathDepth`, `lfHf`, `coherenceTrend`) aus der
App-Kopie und setzte DREI Wächter dagegen. Alle drei lesen `Sources/`.** Die Website behielt
sie: `docs/overview.html` verkaufte „Breath depth → Noise level" und „LF/HF → Spectral tilt"
noch elf Wochen als Abbildung — auf der Seite, die ein Besucher VOR `architecture.html` liest,
die es die ganze Zeit richtig sagte.

**Regel: eine nutzersichtbare Behauptung hat mehrere Oberflächen** (App-Kopie · `docs/**` ·
`fastlane/metadata` · `ContentPipeline/CLAIMS.md`). Wer eine Über-Behauptung zurücknimmt,
grept ALLE VIER — sonst ist der Wächter ein Beleg für Vollständigkeit, die es nicht gibt.

⛔ **Und das naheliegende Verbot wäre rot auf EHRLICHER Kopie geworden.** Ein baumweites
Verbot der Wörter träfe `faq.html`s „LF/HF-**Analyse**" — und die ist WAHR, `HRVCoherence`
rechnet den Quotienten wirklich (Welch + Lomb-Scargle). **Analysiert ≠ abgebildet.** Der
Wächter ankert deshalb auf dem ehrlichen ZUSATZ und verbietet nur die toten ZIELNAMEN
(„spectral tilt", „shape morphing", „color palette"), und nur im Abschnitt, der eine
Abbildungs-TABELLE ist.

⭐ **Nebenbefund derselben Messung, noch nicht gebaut:** `AudioEngine.spatialAudioEnabled`
hat GENAU EIN Vorkommen im ganzen Baum (kein Leser, kein Schreiber), und
`.claude/settings.json` nennt 16 „engines", von denen **15 nicht existieren**, plus
`platforms` mit Android/Windows/Linux/PWA. Beide Blöcke liest nichts. ⚠️ Die erste Messung
sagte 14 — sie zählte Kommentare mit; `StreamEngine` steht nur in einem `SPSCQueue`-Kommentar.

## PLAYBOOK (2026-08-23 #756): löschen oder registrieren? Die Frage ist, ob etwas PERSISTIERT

Dieses Repo behält türlose Sachen absichtlich (`ImmersiveStageView`, `BroadcastView`,
`AudioLanePlayer`, die Modulations-Matrix) — **weil ein von einem älteren Build
persistiertes Dokument sie noch erreichen kann.** Abklemmen macht dort aus „offensichtlich
abwesend" ein „still stumm". Das ist die Regel, und sie hat einen Anwendungsbereich.

**Sie gilt NICHT für ein Feld, das nichts speichert.** `AudioEngine.spatialAudioEnabled`
hatte genau EIN Vorkommen im ganzen Baum (Sources + Tests): seine Deklaration. Kein Leser,
kein Schreiber, kein Key. Es gab nichts am Leben zu halten — es hat nur FEHLGELEITET, weil
die App eine räumliche Ausgabe wirklich hat, nur woanders (`ADMOSCSender` + `BinauralPanner`).

**Prüffrage vor jedem „registrieren statt löschen":** *Kann ein bestehendes Dokument oder ein
persistierter Key diesen Code noch erreichen?* Ja → registrieren. Nein → ein Grabstein-
Kommentar an der Stelle, der sagt, wo die Fähigkeit WIRKLICH liegt. Ein Register, das auch
folgenlose Leichen führt, wird zu lang, um gelesen zu werden — und die Länge dieses Registers
ist selbst schon ein Problem.

⚠️ **Und KEIN Wächter auf die Abwesenheit (#364):** ein Verbot des Namens verböte echte
Arbeit an genau der Fähigkeit. Der Kommentar ist der Beleg, nicht ein Test.

## DEAD-END (2026-08-23 #757): Flächen sind auch LOKALISIERUNGEN, nicht nur Dateien

**Vierte Fundstelle derselben Behauptung.** `breathDepth` treibt nichts (beide
Konstruktionsstellen pinnen `0.5`). #496 nahm es aus der App-Kopie, #755 aus der Website —
und der **englische** App-Store-Text verkaufte es weiter („Breath shapes the amplitude
envelope and filter movement"), während der **deutsche** derselben Anzeige seit jeher ehrlich
war („Atem formt die Hüllkurve").

**Regel, schärfer als die #755-Fassung:** eine nutzersichtbare Behauptung hat vier Flächen
(App-Kopie · `docs/**` · `fastlane/metadata` · `ContentPipeline/CLAIMS.md`) — **und jede
Fläche hat so viele Kopien, wie sie Sprachen hat.** Wer eine Über-Behauptung zurücknimmt,
grept alle Lokalisierungen, nicht nur die eine, in der er sie gefunden hat.

⚠️ **NÄHE statt Wort-Verbot (#364):** „Filter" ist im Store-Text WAHR — Kohärenz treibt
`filterCutoff`. Verboten ist nur ATEM neben FILTER. Ein Wortverbot hätte ehrliche Kopie
gesperrt und wäre binnen eines Zyklus umgangen worden.

⛔ **Und ein Zeugen-Fehler aus dem Zyklus davor, im selben Themenfeld:** #756 bestätigte die
ADM-OSC-Zeile der Website „gegen `Core/BioSpaceMap.swift`". Der Schluss stimmt, der Zeuge
nicht — `BioSpaceMap` hat **null Produktions-Aufrufer**; die sendende Abbildung steht in
`ADMOSCSender` selbst. **Eine Datei, die die richtige Antwort ENTHÄLT, ist kein Beleg dafür,
dass die App sie benutzt.** Immer die Aufrufer mitzählen, nicht nur den Inhalt lesen.

⚠️ **Nicht gebaut, weil die Auswahl keine war:** „welche Kopie-Wächter lesen `docs/` nicht?"
per Stichwort-Grep (`claim|copy|forbidden`) trifft **312 von ~330** Dateien in
`Tests/CISmoke`. Ein Filter, der 95 % durchlässt, ist eine Liste. Die Frage ist gut, das
Messverfahren war es nicht.

## DEAD-END (2026-08-23 #758): eine Seite, die eine Fähigkeit gleichzeitig als fertig UND geplant führt

`docs/accessibility.html` verkaufte „Voice Control — navigate and create using only your
voice" im LIEFER-Abschnitt und „Hands-Free — Voice + switch nav" im **„(planned)"**-Abschnitt
derselben Seite. Gemessen: **null** Sprach-Code in `Sources/` (kein `SFSpeech`, kein
Erkenner, kein `accessibilityCustomAction`).

**Der billigste Test für eine Roadmap-Seite: liest dieselbe Seite eine Fähigkeit zweimal, in
zwei verschiedenen Zeitformen?** Ein Widerspruch INNERHALB einer Datei braucht keinen Blick in
den Quelltext, um verdächtig zu sein — und er zeigt genau dorthin, wo der Quelltext dann die
Antwort gibt.

⚠️ **Der Wächter muss auf den LIEFER-Abschnitt begrenzt sein**, sonst wird ehrliche
Roadmap-Kopie rot (#364). Die Begrenzung wurde gemessen, bevor sie geschrieben wurde: das
Wortpaar liegt nachweislich hinter der Abschnittsgrenze.

⭐ **Eine falsche Kachel wird ERSETZT, nicht gelöscht.** Statt „Voice Control" steht jetzt
„exakte numerische Eingabe" — eine echte, doorbare Fähigkeit, die dieselbe Not (Motorik)
adressiert. Eine Lücke in einer Barrierefreiheits-Liste liest sich als „daran wurde nicht
gedacht"; eine ehrliche Kachel sagt, was es stattdessen gibt.

⚠️ **Und eine Barrierefreiheits-Über-Behauptung ist keine Marketing-Ungenauigkeit.** Sie
entscheidet für einen blinden Nutzer, ob die App überhaupt bedienbar ist. Diese Seite gehört
in dieselbe Prüfroutine wie der Store-Text, nicht in „irgendwann mal".

## PLAYBOOK (2026-08-23 #759): ein Verbot braucht einen ERSATZ, sonst wird darum herumgeschrieben

`ContentPipeline/CLAIMS.md` bekam §12 (die drei erzeugerlosen Bio-Kanäle). Der Eintrag nennt
nicht nur, was verboten ist, sondern die **geprüfte Vier-Kanal-Tabelle**, aus der man
stattdessen zitiert — und der Wächter pinnt genau diesen Zeiger als zweite Behauptung.

**Regel: ein ⛔-Eintrag ohne erlaubte Alternative ist der, um den ein Autor herumschreibt.**
Er streicht dann nicht die Behauptung, sondern formuliert sie um, bis sie durch die Nadel
passt. Wer eine Behauptung verbietet, liefert im selben Absatz den wahren Satz mit.

⚠️ **Und eine Nadel vor dem Schreiben auf EXKLUSIVITÄT prüfen.** „trend" ist ein gewöhnliches
Wort — ein künftiger Abschnitt über irgendeinen Trend hätte die Nadel erfüllt, während der
bewachte Abschnitt längst weg ist. Sie könnte dann nicht mehr für ihren genannten Grund rot
werden (#367). Gemessen, ersetzt durch „kohärenz-trend", exklusiv.

⛔ **Zweiter Fund derselben Runde: §6 (MPE) trug eine BEGRÜNDUNG, die seit #713 falsch war.**
Der Schluss (nicht „MPE" behaupten) hält — aus einem anderen Grund: MPE OUT ist real, MPE IN
nicht. **Ein „darf man nicht"-Vermerk mit falscher Begründung ist schlimmer als keiner:** die
nächste Sitzung widerlegt die Begründung, hält den Eintrag für erledigt und schreibt die
Behauptung zurück. Beim Prüfen einer Verbotsliste also nicht nur fragen „gilt das noch?",
sondern **„gilt der GRUND noch?"**.

⛔ **Und eine eigene Über-Verallgemeinerung, im selben Zyklus widerlegt:** #758 notierte
„vierter Lauf in Folge mit exakt 172 … die geleerte Teilmenge ist stabil". Der nächste Lauf
druckt 171. **Vier gleiche Stichproben sind kein Gesetz.** Belastbar bleibt nur #445: die
Zahl im geleerten Log sagt nichts darüber, welche Tests liefen.

## DEAD-END (2026-08-23 #760): ein Wächter im blockierenden Bundle ist KEIN Sicherheitsnetz

`decisions.csv` war vier Tage lang kaputt (ein ASCII-`"` schloss ein deutsches `„` und
beendete damit das CSV-Feld → 7 statt 6 Spalten). `review.sh` verweigerte in dieser Zeit
JEDE Ausgabe außer „MALFORMED". Der passende Wächter existierte,
`TheDecisionLogIsMachineReadableTests.testEveryDecisionRowHasTheHeaderShape`, war korrekt und
**wäre rot geworden** — er tauchte nur in keinem geleerten Log auf (#396).

**Regel: solange #396 lebt, ist ein Wächter eine ABSICHTSERKLÄRUNG, kein Netz.** Für alles,
was ein Skript in diesem Container prüfen KANN, gehört die Prüfung zusätzlich in
`scripts/doctor.py` — der läuft auf Abruf, ohne Simulator, und seine Ausgabe liest jemand.

⭐ **Und der eigentliche Auslöser war banal: das Werkzeug einmal AUSFÜHREN.** CLAUDE.md nennt
`./review.sh` im Sitzungsstart; fünfzehn Zyklen lang hat es niemand getippt. **Ein Werkzeug,
das im Ablauf steht, aber nie läuft, ist genauso stumm wie ein maskiertes Gate.**

⚠️ **CSV-Falle zum Merken:** in einem gequoteten Feld muss ein inneres `"` VERDOPPELT werden.
Typografische Anführungszeichen (`„ “`) sind sicher, ASCII ist es nicht — und `decisions.csv`
benutzt sonst ausschließlich ASCII, diese eine Zeile griff nach Typografie und traf nur die
öffnende Hälfte.

## DEAD-END (2026-08-23 #761): grep-Erreichbarkeit sieht keine plist-verdrahteten Einstiegspunkte

`ExternalDisplaySceneDelegate` hat **null** Verweise in `Sources/` und ist trotzdem LIVE —
`Resources/iOS/Info.plist` nennt es als `$(PRODUCT_MODULE_NAME).ExternalDisplaySceneDelegate`
für die externe Bildschirm-Szenenrolle; iOS instanziiert die Klasse über ihren NAMEN.

**Regel: bevor eine Datei „türlos/tot" heißt, prüfe die plists.** Ein Einstiegspunkt kann
komplett außerhalb von Swift liegen (Szenen-Delegates, Extension-Principal-Classes,
`UIApplicationDelegate`-Ersatz). `doctor.py` Sektion C und jede `git grep`-Runde sind hier
blind — die Blindheit steht jetzt in den LIMITS des Doctors.

⚠️ **Und es ist ein still brechbarer Vertrag:** ein Umbenennen der Swift-Klasse tötet die
Funktion ohne Compile-Fehler und ohne roten Test. Sektion B prüft die Auflösung jetzt;
Reparaturrichtung ist der SWIFT-Name (Info.plist ist founder-gated).

⛔ **Und die Messung, mit der ich angefangen habe, war selbst kaputt:** eine transitive Hülle
über `View`-Structs mit der Nadel `Name(` erklärte 26 Typen für unerreichbar, darunter
`EchoelNumberPad` und `SafeModeView`. SwiftUI konstruiert massenhaft mit **nachgestelltem
Closure ohne Klammern** (`SafeModeView {`). **Wer Erreichbarkeit misst, muss `Name(` UND
`Name {` treffen** — sonst meldet man lebende Flächen als Leichen. Gefunden, weil die Liste
von Hand nachgeprüft wurde, statt sie zu melden.

## DEAD-END — Ein Erreichbarkeits-Scan über ROHEN Quelltext (#762)

**Die Prosa ÜBER eine Sache ist Teil des Heuhaufens.** Sektion C des Doctors las rohen Swift
und zählte `BioSourceView(` — zitiert in einem Kommentar, der die Türlosigkeit DOKUMENTIERT —
als Konstruktionsstelle. Die Fläche war dadurch versteckt in genau dem Maß, in dem sie
sorgfältig aufgeschrieben worden war, und zwar in der schmeichelnden Richtung.

**STATT DESSEN:** vor jedem Zähl-Scan über `Sources/` durch `_code_only` schicken
(Doctor) bzw. `SourceText.codeOnly` (Tests/CISmoke). Messen, ob es TRAGEND ist: C1 8→9,
C2 2→2 — also live in der einen Hälfte, latent in der anderen, und beides gehört gesagt.

**Erkennungszeichen im Voraus:** ein Scan, dessen Nadel ein Bezeichner ist, über eine Datei,
in der jemand über diesen Bezeichner schreibt. In diesem Repo ist das der Normalfall, nicht
die Ausnahme.

## PLAYBOOK — Ein Selftest braucht eine WIRKUNGS-Schicht, nicht nur eine Regel-Schicht (#762)

#753 zeigte: ein Mutant, der die Regel intakt lässt und sie nur ABHÄNGT, besteht jede
Regel-Prüfung. Also zwei Schichten:
1. **Regel, als Paar** — die Ausnahme feuert auf der verbotenen Form UND feuert nicht auf der
   erlaubten, am besten auf derselben Zeile.
2. **Verdrahtung** — die ECHTE Funktion über den ECHTEN Baum laufen lassen und ihre Antwort
   gegen die erwartete Rechnung halten.

**Und Schicht 2 muss INCONCLUSIVE sagen können.** Wenn beide Lesungen auf dem heutigen Baum
übereinstimmen, kann der Lauf verdrahtet und abgehängt nicht unterscheiden — das auszusprechen
ist billiger als ein grünes Häkchen, das nichts gemessen hat, und verhindert das #364-Rot an
dem Tag, an dem der Unterschied legitim verschwindet.

## DEAD-END — Eine Entscheidung in der immer-geladenen Datei „zur Sicherheit" wiederholen (#763)

Der CI-Gate-Diskriminator stand in DREI Dateien. Die Kopie in `CLAUDE.md` war als Bequemlichkeit
gedacht (immer da, nie nachschlagen müssen) und wurde dadurch zur **ältesten**: #667, #679, #738
und #739 haben nur die kanonische Fassung in `Tests/CISmoke/CLAUDE.md` §5 nachgeführt.

**Die immer-geladene Kopie gewinnt per Default.** Ist sie die stalest, ist die Redundanz nicht
neutral, sondern aktiv schädlich — sie überschreibt die richtige Antwort.

**STATT DESSEN:** Kurzfassung (2 Sätze, das was IMMER gilt) plus benannter Zeiger auf Datei UND
Abschnitt. `.claude/rules/context.md` §3 hatte genau das schon getan; die Verletzung stand
woanders.

**Erkennungszeichen:** eine Datei sagt „X ist hier nicht wiederholt (#416)" und eine dritte Datei
wiederholt X trotzdem. Suchbar: die Absage zitieren und prüfen, ob sie stimmt.

## PLAYBOOK — Ein Umzugs-Wächter braucht ein ZIEL PRO ZEUGE (#763)

`testTheMovedProvenance…` hatte `memory/LEDGER_COUNTS.md` hart verdrahtet, weil alle bisherigen
Umzüge Zähl-Ketten waren. Der erste Umzug, der KEINE Zähl-Kette ist, hätte dorthin gezwungen eine
VIERTE Kopie der zu entdoppelnden Entscheidung erzeugt.

**Regel: ein Wächter, der ein einziges Ziel erzwingt, ist eine Wette darauf, dass alle künftigen
Fälle dieselbe Sorte sind.** Ziel pro Zeuge führen, und den Grund für die Wahl im Zeugen selbst
mitschreiben.

⛔ **Und die Benotung des neuen Zeugen war beim ersten Schreiben aus EPOCH 4 abgeschrieben
(„FORWARD — unfalsifiable on the parent") statt gemessen.** Gemessen ist er ein REGRESSION CATCH:
beide Zusicherungen sind auf dem Eltern-Baum rot. Untertreiben ist die bescheidene Richtung von
#464 und trotzdem eine falsche Behauptung über den eigenen Wächter.

## DEAD-END — Eine Zahl auffrischen, die in einer immer-geladenen Datei steht (#764)

`.claude/rules/context.md` §1 hatte schon einmal eine Byte-Tabelle GELÖSCHT statt aufgefrischt,
mit der Begründung „a table of bytes in an always-loaded file is a date, not a fact". Der Absatz
DANEBEN trug trotzdem vier Byte-Zahlen weiter — und alle vier waren veraltet, eine um 325 %.

**Die Regel war geschrieben; der Nachbar-Absatz wurde nie daran gehalten.** Wer die Zahlen
aufgefrischt hätte, hätte die Falle nachgebaut.

**STATT DESSEN:** die DAUERHAFTE Behauptung behalten (hier: „einstelliger Prozentsatz"), die
Zahl in ein Werkzeug legen, das sie bei jedem Lauf neu misst, und im Werkzeug sagen, was es
NICHT liest.

**Erkennungszeichen:** eine Datei, die eine Zahl-Disziplin VERFÜGT, ist der wahrscheinlichste
Ort für einen Verstoß dagegen — niemand prüft die Regel gegen ihren eigenen Text.

## PLAYBOOK — Wenn die Rücknahme die verbotene Nadel zitiert, gibt es keinen Wächter (#764)

Ein Nadel-Verbot auf eine gestrichene Falschangabe ist auf dem KORREKTEN Baum rot, sobald die
ehrliche Rücknahme die Angabe zitiert — und das tut sie fast immer, weil sonst niemand
nachvollziehen kann, was zurückgenommen wurde (#491).

**Regel: erst prüfen, ob die eigene Rücknahme die Nadel enthält.** Wenn ja, den Posten als
OFFEN registrieren und den Grund hinschreiben, statt einen Scan zu bauen, der nicht fehlschlagen
kann oder auf korrektem Baum rot ist. Die messbare Hälfte gehört stattdessen in ein Skript.

## DEAD-END — Eine Kopie-Prüfung, die nur die AUFZÄHLUNG liest und nicht den Fließtext (#765)

Die drei falschen Pro-Zeilen fielen sofort auf. Der **Kopfsatz** derselben Fläche trug dieselbe
Falschbehauptung in ihrer schärfsten Form (ein Kauf-VERSPRECHEN) und wäre bei einer
Zeile-für-Zeile-Lesung durchgegangen — gefunden hat ihn erst die Transkription, die einen
überlebenden Treffer druckte.

**STATT DESSEN:** die ganze Datei kommentarfrei nach der Nadel absuchen und die TREFFERZAHL
lesen, nicht nur die Stellen, an die man gerade denkt. Ein Rest-Treffer nach der „Reparatur" ist
das Signal.

## PLAYBOOK — Ein Transkriptions-Treiber braucht ein `assert`, dass er überhaupt etwas gelesen hat (#765)

Mein Treiber baute eine leere Dateikarte (`doctor.tracked()` liefert ABSOLUTE Pfade) und meldete
für zwei Claims fröhlich „RED" — auf Basis von null gelesenen Dateien. Die Zahlen sahen wie eine
Messung aus.

**Regel: jede Mess-Schleife über eine Dateimenge beginnt mit `assert files` (oder dem
Äquivalent).** Eine Messung, die nichts gemessen hat, muss ABBRECHEN, nicht antworten — genau die
`InstrumentUnavailable`-Lehre des Doctors, eine Ebene tiefer.

## DEAD-END — „Ungebautes als ‚in development' kennzeichnen" als Ehrlichkeits-Regel (#765)

Der Kopf von `ProUnlockView` schrieb genau das vor und machte damit ein Wort zur sanktionierten
Formel für ALLES Ungebaute — auch für Arbeit, die GELÖSCHT wurde. Die Regel las sich als
Absicherung und war das Loch.

**STATT DESSEN:** „in development" ist eine Behauptung über die GEGENWART und braucht Code als
Beleg. Für alles andere: **„planned, not built yet"**. Der Unterschied ist nicht Höflichkeit —
auf einer Bezahlschranke ist er 2.3.

## PLAYBOOK — Erst die FLÄCHEN zählen, dann die Kopien je Fläche (#766, schärft #757)

#757 lehrte: jede Claim-Fläche hat so viele Kopien wie Locales. #766 zeigt die Stufe darüber:
**#548 meldete fünf Flächen als geprüft, und alle fünf waren PROSA** — die App-eigene
Routing-Fläche kam in der Aufzählung nicht vor und trug die Falschbehauptung zwei Monate weiter.
#765 war derselbe Fehler eine Woche vorher (App-Kopie fehlte in der Aufzählung).

**Die Aufzählung ist der Defekt, nicht die Sorgfalt.** Checkliste vor „alle Flächen geprüft":
1. `docs/**` (jede Seite, nicht die, an die man denkt)
2. `fastlane/metadata/<jedes Locale>`
3. `ContentPipeline/CLAIMS.md`
4. **App-Kopie in `Sources/`** — `Text("…")`, `accessibilityLabel/Hint`, Enum-`displayName`,
   **Port-/Kanal-NAMEN** (`SignalPort(name:)`), Menü-Untertitel
5. die immer-geladene `CLAUDE.md` selbst

**Erkennungszeichen:** wenn alle geprüften Flächen dieselbe GATTUNG haben (hier: Prosa), ist die
Aufzählung mit hoher Wahrscheinlichkeit unvollständig.

## PLAYBOOK — „Der String existiert" ist kein Beweis, dass ihn jemand liest (#767)

Vier Wächter pinnten die fünf Pflicht-Sicherheitshinweise auf EXISTENZ und Übersetzung. Ein
Mutant, der den Hinweis in eine **türlose** Ansicht verschiebt, lässt **alle vier grün** — und
die App zeigt keinen einzigen.

**Regel: für jede Behauptung „X ist in der App" braucht es ZWEI Hälften** — der Text existiert
UND sein Träger ist montiert. Die zweite Hälfte ist Erreichbarkeit erster Ordnung
(„irgendwo konstruiert"), was das Negativ beweist und mehr nicht; das reicht, weil das Negativ
der real vorgekommene Fehler ist.

**Erkennungszeichen:** ein Wächter-Kommentar, der die Gefahr NENNT, ohne sie zu schließen
(„zwei dieser Sätze stehen auch in zwei türlosen Views"). Eine benannte, ungeschlossene Gefahr
ist eine offene Aufgabe, keine Dokumentation.

⛔ Und der #762-Defekt hat beim Schreiben dieser Scheibe erneut zugeschlagen: ein von Hand
getipptes `git grep -c "SomeView(" -- Sources` meldete einen Treffer, der ein KOMMENTAR war.
**Jede Erreichbarkeits-Messung — auch die schnelle von Hand — muss kommentar-gestrippt sein.**

## DEAD-END — Einen Wächter über ein VERZEICHNIS schreiben und die Blattliste von Hand tippen (#768)

`TheStoreTextClaimsOnlyWhatShipsTests` lief über zwei Locales × **drei** hart getippte Blätter.
Das Verzeichnis hat **fünf**. Die zwei ausgelassenen trugen eine Behauptung, die ein früherer
Zyklus für repariert hielt — und beide Wächter blieben grün.

**STATT DESSEN:** entweder das Verzeichnis wirklich aufzählen, oder die Liste mit der Zahl der
tatsächlich vorhandenen Dateien abgleichen und bei Abweichung FEHLSCHLAGEN. Eine handgetippte
Teilmenge, die aussieht wie eine Aufzählung, ist die teuerste Form: sie liest sich vollständig.

**Erkennungszeichen:** eine Schleife über eine Literal-Liste von Dateinamen neben einem
Verzeichnis, das wachsen kann. `ls` das Verzeichnis, bevor man der Liste glaubt.

## PLAYBOOK — Ein präventiver Wächter ist zulässig, wenn er einen BEREITS BEZAHLTEN Fehler benennt (#768)

Die Doctor-Skill-Regel lautet: nur prüfen, was hier schon einmal schiefging. Claim 3 (23 Nadeln
auf entfernte Fähigkeiten) fängt heute **nichts** — und ist trotzdem richtig, weil **#184 zwölf
falsche Behauptungen aus genau diesem Text entfernt hat** und seither nichts die Rückkehr
bewacht.

**Regel: ein präventiver Wächter muss den Vorfall NAMENTLICH nennen und sich selbst als
PRÄVENTIV benoten (#464).** Beides fehlt bei „nice to have"-Wächtern — und ohne das ist die
Unterscheidung zwischen Vorsorge und Spekulation nicht nachprüfbar.

## DEAD-END — Eine unvollständige Aufzählung reparieren, indem man das fehlende Element eintippt (#769)

`WebsitePagesAreFindableAndHonestTests` scannte nur `en-US`, bis die `de-DE`-Notizen eine Woche
lang veraltet waren. Die Reparatur: `de-DE` dazutippen. Damit wird das DRITTE Locale in exakt
derselben Stille übersprungen — und #768 hat die identische Form eine Ebene weiter innen
getroffen (drei von fünf Metadaten-Blättern von Hand getippt).

**STATT DESSEN:** das Verzeichnis LESEN. Wenn die Aufzählung wirklich eine Spezifikation ist
(z. B. „welche Sprachen MUSS der Katalog tragen"), dann sie als Spezifikation stehen lassen —
und sie GEGEN das Verzeichnis prüfen, statt zu hoffen, dass beide gleich bleiben.

**Erkennungszeichen:** eine Literal-Liste, deren Elemente Dateien oder Verzeichnisse eines
existierenden Ordners sind. `ls` den Ordner, bevor man der Liste glaubt.

**Und die Meta-Lehre aus #768/#769 zusammen:** wer eine unvollständige Aufzählung repariert, muss
fragen, ob die REPARATUR dieselbe Form hat wie der Defekt. #768 enumerierte die Blätter und ließ
die Locales von Hand — die Falle saß im eigenen Fix.

## PLAYBOOK — Zwei Helfer gleichen Namens dürfen verschiedene Verträge haben, wenn es DRANSTEHT (#769)

`localeDirectories()` existiert jetzt in zwei Wächtern: in einem SCHLÄGT ein leeres Verzeichnis
FEHL (die Datei liest sonst nichts), im anderen liefert es eine leere Liste (die Store-Notizen
sind dort eine Ergänzung zu `docs/`). Das ist kein #416-Verstoß — es ist EIN Mechanismus mit
zwei bewusst verschiedenen Ausfall-Verträgen.

**Regel: der Unterschied gehört in beide Dokumentations-Blöcke**, weil er aus dem Namen nicht
erratbar ist. Ohne den Vermerk kopiert die nächste Sitzung den falschen Vertrag.

| DEAD-END | Eine Fähigkeits-Aufzählung für vollständig halten, weil jeder EINTRAG geprüft wurde. #548 (5 Flächen) → #766 (6.) → #770 (7.). Do this instead: prüfe die GATTUNGEN, nicht die Einträge — Prosa · UI-Label · Log-Zeile · Doc-Kommentar · Store-Text · Website · String-Katalog. Teilen alle geprüften Flächen eine Gattung, fehlt eine Gattung. |
| PLAYBOOK | Ein „noch nicht verdrahtet"-Vermerk gehört an die Schicht, in der die Arbeit ANFÄNGT. `MIDIBusPublisher` sagte „channelPressure intentionally NOT wired" und schickte damit in die falsche Datei — das Byte wird eine Schicht tiefer gar nicht geparst. Prüfe bei jedem solchen Vermerk EINE Ebene tiefer, ob es überhaupt etwas zu verdrahten gibt. |
| PLAYBOOK | Zu jeder Mutations-Probe (#367) gehört eine KONTROLL-Mutation, die dieselbe Zeichenkette nur in einen KOMMENTAR schreibt. Sie beweist, dass der Wächter den #762-Fallstrick nicht hat — geraten reicht nicht, es ist eine Zeile Python. |

| PLAYBOOK | Berechtigungs-Strings (`NS…UsageDescription`) sind Fähigkeits-Behauptungen im höchstwertigen Medium der App — dem Systemdialog. Bei JEDER Feature-Löschung prüfen, ob ein plist-String dadurch zum Versprechen ohne Code wird. Wächter: `EveryPermissionPromptHasACapabilityTests`. |
| PLAYBOOK | Wenn zwei Zusicherungen desselben Wächters nur GEMEINSAM rot werden können, ist das EIN Befund (#486). Im Kopf notieren, welche die Diagnose liefert und welche den Fang — sonst meldet ein Status-Delta zwei. |
| DEAD-END | Eine saubere Messung als Zyklus-Fehlschlag werten. #771 fand neun ehrliche Strings; das Ergebnis ist der WÄCHTER, der die Ehrlichkeit hält, nicht eine Reparatur. Do this instead: präventiv benoten (#464) und den bezahlten Vorfall nennen, der ihn rechtfertigt. |

| DEAD-END | Das erwartete Ergebnis einer #367-Mutation in den Dateikopf schreiben, BEVOR man sie fährt. #765 Claim 4, #772 Claim 2 — zweimal dieselbe Klasse. Do this instead: Mutation fahren, DANN den Kopf aus der Druckausgabe abschreiben. |
| PLAYBOOK | Eine DEKLARIERTE Grenze eines Wächters („diese Auflistung ist nicht rekursiv") ist ein offener Auftrag, kein Freibrief. Sie bleibt für immer stehen, bis jemand misst, was hinter ihr liegt — #762 in einer anderen Datei. Beim Lesen eines Wächter-Kopfes: jede ⚠️-Grenze als Frage behandeln. |
| PLAYBOOK | URL-Dateien (`*_url.txt`) sind Fähigkeits-Behauptungen mit ROUTING dahinter, nicht Kopie. Sie standen in KEINER Leaf-Liste der Store-Wächter (#768/#769), weil diese nach Text suchten. Wächter: `TheStoreURLsResolveToAPageTests`. |

| PLAYBOOK | Wenn ein Werkzeug seine eigene Reparatur in seinen LIMITS benennt („the repair is a convention, not a smarter parser"), ist das ein fertiger Auftrag — nicht eine Entschuldigung. #773 hat den von #752 nach vier Wochen eingelöst. |
| PLAYBOOK | Ein Marker, der auch ein gewöhnliches Wort ist, verlangt eine Nadel mit STRUKTUR (hier: ein echtes Datum), sonst liest das Werkzeug seine eigene Dokumentation. #753 bezahlt, #773 vorher gesehen. |
| PLAYBOOK | Jede Klassifizierungs-Regel braucht eine erklärte AUSFALLRICHTUNG. Beide Regeln in `founder-verify.py` versagen Richtung Lärm (mehr anzeigen), weil Verstecken eine Gerätesitzung kostet und Anzeigen einen Blick. Ohne diesen Satz rät die nächste Änderung. |

| DEAD-END | Eine Tabellen-Zeile für geprüft halten, weil die Zeile DANEBEN sorgfältig formuliert ist. #774: MIDI-OUT war peinlich genau, MIDI-IN direkt darüber trug den Plural, den #548 schon gestrichen hatte. Do this instead: Nachbarschaft ist kein Beleg — jede Zeile einzeln gegen den Code. |
| PLAYBOOK | Bei einer Rücknahme immer auch die ÜBER-Korrektur messen. #774 hätte fast „MIDI-Eingang steckt hinter dem Body-voice-Schalter" behauptet; `apply(controller:)` ist ausdrücklich NICHT isArmed-gated. Eine Rücknahme ist auch eine Behauptung. |

| DEAD-END | Nur nach ÜBER-Behauptungen suchen. #775 fand die erste UNTER-Behauptung: die Website verkaufte ausgelieferten MPE-Ausgang als Roadmap, zehn Passagen in sechs Dateien. Jede Nadel-Liste in den Claim-Wächtern ist eine Liste von Dingen-die-man-nicht-verspricht. Do this instead: auch fragen, was die App KANN und die Kopie verschweigt. |
| DEAD-END | Einen Claim-Wächter auf DIE SEITE pinnen, die man gerade repariert hat. #775 tat das und fand danach neun weitere Vorkommen. Do this instead: das Verzeichnis fegen, bevor man den Wächter schreibt — die Zahl der Fundstellen entscheidet über seine FORM. |
| PLAYBOOK | Ein zeilenweiser `grep` findet keine Behauptung, die über eine Zeilengrenze läuft. #775: neun Treffer per Zeile, das zehnte erst per Satz-Scan (`press.html`). Bei Prosa-Behauptungen immer satzweise messen. |
| PLAYBOOK | Einen neuen Text-Wächter IMMER gegen den korrekten Baum fahren, bevor er gepusht wird — nicht nur gegen den Elternteil. #775s Satztrenner schlug auf korrektem Text Alarm (`".)"` trennt nicht). |

| PLAYBOOK | Nach dem Löschen eines `static let`/`func`: `git grep -n "Self\.<name>" -- Tests/CISmoke Sources`. Die Deklaration zu grepen reicht NICHT — #776 ließ eine Referenz in einer Fehlermeldung stehen und der Commit ging rot raus. |
| DEAD-END | Einen „undeklariertes Self-Member"-Audit mit `\bSelf\.(\w+)` fahren: 20 Fehlalarme, weil Nadel-Strings dieselbe Schreibweise tragen. Do this instead: auf die INTERPOLATION `\(Self\.` matchen — das ist die einzige Form, die innerhalb eines Literals Code ist. |

| PLAYBOOK | `python3 scripts/dead-needles.py` deckt seit #777 ZWEI Defekte ab: tote Nadel UND `\(Self.x)` ohne Deklaration. Vor jedem Push laufen lassen — es ist der billigste Ersatz für den Compiler, den es hier nicht gibt. |
| PLAYBOOK | Einen neuen Prüfer IMMER gegen den Commit fahren, der den Defekt hatte, UND gegen den, der ihn reparierte. #777: 1 Treffer / 0 Treffer. Ein Detektor ohne seinen eigenen bekannten Positivfall ist keine Messung. |
| PLAYBOOK | **Ein Werkzeug mit mehreren MODI: immer ALLE fahren.** #906/#907: `scripts/diag-ladder.py --source` blieb grün (der Emitter existiert ja), während der LOG-Modus denselben Commit einen gesunden Zwei-Besitzer-Lauf für TOT erklären ließ. Die Modi lesen verschiedene Dinge — Quelle gegen Gerätezeilen. Wer an der Kante des ersten Modus aufhört, hört einen Schritt vor dem Defekt auf. |
| PLAYBOOK | `python3 scripts/count-pins.py` neben `dead-needles.py` vor jedem Push. Es hat in zwei aufeinanderfolgenden Zyklen die eigene Drift des Commits VOR dem Commit gedruckt (`pinned 12, actual 14`, dann `pinned 14, actual 15`) — dieselbe Sorte Drift blieb dreizehn Commits unentdeckt, als nur CI zuschaute (#396 macht ein echtes Rot ununterscheidbar vom sterbenden Host). |
| DEAD-END | Einen mitten in der Leiter übersprungenen Schritt durch die WORTWAHL heilen wollen. Gemessen (#907): unnummeriert → falscher Tod, `2/3 SKIPPED` → derselbe falsche Tod, `3/3 SKIPPED` → ✅ für einen Schritt, der nie lief. Do this instead: dem Werkzeug den fehlenden Begriff beibringen — eine Zeile, die eine Leiter BEENDET, ohne sie WEITERZUZÄHLEN. |
| DEAD-END | Eine Prüf-REGEL zurückziehen, weil das WERKZEUG jetzt klüger ist — ohne zu prüfen, ob die Mehrdeutigkeit im DATENFORMAT überhaupt auflösbar ist. #908: ich hielt den nummerierten Sprung für gerettet und zog den Wächter zurück; im LOG sind „Sprung, der weiterläuft“ und „Sprung, der zurückkehrt“ dieselbe Zeichenkette. Ergebnis: ein echter Tod in `installTap` wurde als ⏹ mit Exit 0 gemeldet. Do this instead: erst fragen, ob die zwei Fälle im Log ÜBERHAUPT unterscheidbar sind; wenn nicht, muss die Regel an der QUELLE bleiben. |
| PLAYBOOK | Einen neuen Scanner MUTIEREN, nicht lesen. #908s (c4) sah in beide Richtungen richtig aus und war es nicht: falsch-rot bei einem UMGEBROCHENEN Breadcrumb (die Form steht in genau der Datei, die er scannt) und grün bei `if x { return }`, `else{return}`, `return // Kommentar` und einem stillen `throw`. Vier Mutanten je Richtung kosten Minuten und fanden alles. |
| DEAD-END | Einen FENSTER-Scan über `inputNode` bauen („steht vor der Berührung ein Breadcrumb?“). ZWEIMAL versucht, zweimal verworfen: #875 mit einem 260-Zeichen-Fenster (meldete 4 von 5 korrekten Stellen als ungeschützt — #665), #909 mit einem funktionsgroßen Fenster (blind für `init`/`deinit`/computed property — ein `deinit { inputNode.removeTap() }` erbt das „hat schon gesprochen“ der Vorgängerfunktion — und blind für Zweige: ein `logMonitorOutcome` in einem `catch` markiert die Funktion als gesprochen). Do this instead: eine ZAHL. Sie kennt weder Mitgliedsart noch Zweig und sagt „eine sechste Stelle ist da, prüf sie von Hand“. |
| PLAYBOOK | Vor einem neuen Wächter prüfen, ob ein VORHANDENER die Sache schon stärker abdeckt. #909 hätte eine 150-Zeilen-Datei ausgeliefert, deren Vorzeige-Mutant unter einem einen Tag alten Zähl-Pin ohnehin rot ist — und deren Ablehnungsgrund im selben Wächter-Doc bereits stand. Die Scheibe wurde verworfen und als 15-Zeilen-Erweiterung DIESES Pins geborgen. |
| DEAD-END | Eine Bedingung RUND UM etwas mit einer Spanne prüfen, die NACH der Sache beginnt. #910: der Anspruch verbot ein `if` ZWISCHEN Marker und Aufruf und versprach im Kopf, der Marker trage kein `if` — `if x { marker }` ging durch alle vier Teilansprüche. Do this instead: verlangen, dass die ZEILE der Sache mit ihr BEGINNT. |
| DEAD-END | Eine Eigenschaft am eigenen Test-LITERAL prüfen statt an der Quellzeile. #910 rief `carriesRungNumber(marker)` auf einer Konstanten auf, die die Testdatei selbst schrieb — auf keinem Baum und unter keiner Mutation fehlschlagbar. Do this instead: die Zeile in `Sources/` suchen und das Literal DARAUS ziehen. |
| DEAD-END | `"if "` als Verbots-Nadel. Es trifft `#if ` — in `MicrophoneManager` fünf Plattform-Guards, also ein Falsch-Rot auf korrektem Baum. Do this instead: Zeilen mit `#`-Präfix überspringen und auf Token-Grenze prüfen. |
| DEAD-END | `decisions.csv` mit `csv.writer` KOMPLETT neu schreiben, um eine Zeile zu ändern. QUOTE_MINIMAL setzt die Anführungszeichen neu und churnt die ganze Datei — #907: 482 unbeteiligte Zeilen im Diff, und eine JAHRE alte Zeile, die zufällig eine Modellkennung im Fließtext trug, tauchte dadurch als `+` auf und ließ die Modellkennungs-Vorprüfung anschlagen (die damit ihren Nutzen bewiesen hat — sie fing nicht meinen Text, sondern meine Schreibmethode). Do this instead: `git checkout HEAD -- decisions.csv`, dann NUR anhängen (`open(..., "a", newline="")`). |

### PLAYBOOK (#778) — eine Claim-Nadel aus dem KÖNNEN bauen, nicht aus dem Wort

**Symptom.** Ein Wächter sweept jede Fläche, jeden Satz — und lässt trotzdem eine falsche
Behauptung stehen, weil sie das Wort nicht benutzt, nach dem gefragt wurde. (#775 suchte
„MPE" und ging an „CC 74 slide plays the built-in voices" vorbei.)

**Regel.** Die Nadel wird aus der FÄHIGKEIT gebaut, nicht aus dem Vokabular des letzten
Defekts: hier „ein Dimensions-Wort (slide · CC 74 · timbre · air-CC · channel pressure)"
UND „plays/reaches … voice". Ein Synonym-Wechsel kann daran nicht vorbei.

**Zwei-teilig, wenn eine Richtung der Fähigkeit wirklich existiert.** MPE OUT sendet alle drei
Dimensionen — ein Verbot des Dimensions-Wortes allein wäre #364 (verbietet korrekte Arbeit).
Deshalb: Teil 1 = die Sache, Teil 2 = die falsche AUSSAGE über sie. Immer mit einer
KONTROLL-Mutation prüfen, die die ehrliche Formulierung einspeist und grün bleiben MUSS.

**Erkennungszeichen, dass eine Nadel zu eng ist:** sie besteht aus einem Eigennamen oder
Akronym. Ein Nutzer beschreibt eine Fähigkeit selten mit dem Fachwort.

### PLAYBOOK (#779) — den Sweep von der ROADMAP-Seite fahren

**Warum.** Jede Claim-Nadel dieses Repos ist eine Liste von Dingen, die man NICHT versprechen
darf. Damit findet man Über-Behauptungen und ist gegen die Gegenrichtung strukturell blind:
eine Fähigkeit, die ausgeliefert ist und auf der Website „ROADMAP" heißt.

**Rezept.** Satzweise (nicht zeilenweise) über `docs/*.html`, Nadel
`\b(roadmap|planned|not in the app today)\b`, dann jede Zeile gegen den Code messen. Kosten:
~100 Sätze, eine Sitzung. Ausbeute bei #779: **1 Falschstelle** — und die saß auf der Seite,
die ein DAW-Nutzer vor dem Export liest.

**Reparaturform: den Satz TEILEN, nicht umdrehen.** „A, B und C sind ROADMAP" mit nur A
ausgeliefert wird zu „A ist LIVE … B und C sind ROADMAP". Der Wächter verbietet dann NUR A in
einem Roadmap-Satz — B später zu verdrahten braucht keine Änderung am Wächter (#364).

**Fallstrick, zweimal in einer Stunde getroffen:** `grep -i ndi` traf 283 Dateien
(„handling", „indicator"), `grep -i link` 35. **Eine Nadel ohne `\b` misst das Alphabet, nicht
die Sache.** Und: die Treffer ANSCHAUEN, nicht nur zählen — `\bAbleton\b` = 35 echte Treffer,
alle Kommentare, `\bLinkKit\b` = 0. Die Schlussfolgerung hängt am zweiten Befehl.

### DEAD-END (#780) — eine Anker-Mutation, die nur den SUFFIX umbenennt, beweist nichts

`text.range(of: "### 6. MPE")` (und Pythons `find`) treffen ein **Präfix**. Wer den Anker
prüfen will, indem er `### 6. MPE` → `### 6. MPE-Zeug` umbenennt, bekommt GRÜN und bucht das
als „Anker hält". Die Mutation, die den Anker wirklich testet, **entfernt das Wort**
(`### 6. Ausdruck`). Gilt für jede Überschriften-Verankerung in diesem Bundle.

### PLAYBOOK (#780) — Absatz und REGELZEILE altern getrennt

In `CLAIMS.md`, `CLAUDE.md` und jedem Wächter-Kopf steht die Begründung als Fließtext und die
Entscheidung noch einmal als **kurze Regelzeile** („*Erlaubt: … Nicht erlaubt: …*"). Wird die
Fähigkeit korrigiert, führt man die Begründung nach — und die Regelzeile bleibt stehen.
**Die Regelzeile ist die, die kopiert wird.** Beim Korrigieren eines Absatzes also immer
fragen: gibt es darunter eine Kurzform, die dasselbe noch einmal sagt?

Hier: §6s Absatz sagte seit #548 „MPE OUT ist real", die Regelzeile darunter verbot „MPE"
pauschal — zwei Monate lang, in der Datei, deren einziger Zweck falsche Captions sind.

### PLAYBOOK (#781) — eine Mutation ist kein Beweis, bevor sie GELANDET ist

Zweimal in einer Sitzung getroffen. Beide Male sah eine Null-Mutation wie ein bestandener Test
aus:
1. `sed 's/static let architecture =/.../'` auf eine Datei, in der diese Deklaration seit #776
   gar nicht mehr existiert — nur Kommentar-Treffer. Prüfer meldet nichts. Liest sich wie
   „Prüfer kaputt", ist aber „nichts mutiert".
2. `### 6. MPE` → `### 6. MPE-Zeug`, um einen Anker zu prüfen. `range(of:)`/`find` treffen ein
   **Präfix** — grün, und der Anker war nie getestet.

**Regel: nach jeder Mutation den mutierten Baum grepen und die Änderung SEHEN**, bevor man das
Ergebnis als Aussage über den Prüfer bucht. Ein `grep -c` auf die alte Form (muss 0 sein) ist
eine Zeile.

### DEAD-ENDS (#782) — vier Hypothesen gemessen, Repo in allen vier gesund

Ein Zyklus ohne Codeänderung, absichtlich. Damit die nächste Sitzung sie nicht erneut fährt:

1. **Veraltete NEEDS-FOUNDER-VERIFY-Bitten** (Präzedenz: CLAUDE.md hat eine zurückgezogen,
   weil #475 den Knopf löschte). Gemessen über alle 50 Bitten: jedes zitierte Bedien-Element
   existiert noch in `Sources/`. **Ein einziger Treffer war ein Fehlalarm meines Suchmusters**
   — die Bitte schreibt `"Undo delete of …"` als Abkürzung, der Code hat
   `Text("Undo delete of \(d.title)")`; ein interpoliertes Literal kann eine Text-Nadel nicht
   treffen. **Null echte Fundstellen.**
2. **Bitten, die auf künftige Arbeit warten** und die Warteschlange größer aussehen lassen als
   sie ist: **eine** (`AGrainCannotClickOrRunAway`, „once it is wired and reachable"). Zu wenig
   für eine Scheibe.
3. **`SourceText.codeOnly`-Blindheit außerhalb von `Sources/`** — die Verallgemeinerung des
   #781-Befunds. Gemessen: JEDER `codeOnly`-Aufruf in `Tests/CISmoke` zielt auf `Sources/`;
   nur vier Wächter lesen überhaupt eine `Tests/`-Datei, und keiner davon Swift. **Sauber.**
4. **Der #659-Pin könnte veraltet sein** („die zwei Formen widersprechen sich bei GENAU EINER
   Datei"). Unabhängig nachgerechnet: 9 Dateien tragen ein `"""`, Widerspruch bei genau
   `MetalBioView.swift`, 337 Zeilen. **Der Pin von 2026-08-20 stimmt heute unverändert.**
   (Kontextzahl im Wächter ist um eins gealtert — 366 → 367 unter `Sources/Echoelmusic`, der
   Zuwachs ist `DSP/EchoelGranular.swift` und trägt kein `"""`. Die Schwelle dort ist `> 300`,
   also unberührt, und die Zahl ist DATIERT, also historisch und nicht falsch.)

⚠️ **Und die Nachrechnung zu (4) produzierte erst eine Falschmeldung: „EchoelStudioView.swift,
2108 abweichende Zeilen".** Ursache in meiner Transkription, nicht im Repo: **eine Zeile kann
ZWEI `"""` tragen** (`EchoelStudioView.swift:8246` ist `""" : """` — schließt ein Literal und
öffnet das nächste). Wer pro ZEILE umschaltet statt pro VORKOMMEN, verlässt das Literal einmal
zu früh, öffnet bei 8250 eines, das nie schließt, und verschluckt den Rest der Datei.
**Regel: eine dramatische Zahl aus einem selbstgebauten Zustandsautomaten wird am Quelltext
gegengeprüft, bevor sie ein Befund wird** — `grep -n '"""' <datei>` waren drei Zeilen Ausgabe
und haben es sofort erledigt. Dieselbe Klasse wie die 283 „ndi"-Treffer aus #779.

### PLAYBOOK (#783) — eine nutzersichtbare Beschriftung wird KOPIERT, nie abgetippt

`grep "Voice - your microphone"` → 0 Treffer. Der Code hat `Voice · your microphone` mit
MITTELPUNKT. Ein Bindestrich statt eines Mittelpunkts, und die korrekte Anweisung an den
Founder liest sich als „nennt eine Tür, die es nicht gibt".

**Regel:** jede Beschriftung, die in eine Anweisung, eine Release-Note oder einen Wächter
geht, wird per Copy-Paste aus `Sources/` genommen und danach mit `grep -F` gegengeprüft.
Betroffen sind besonders `·` `…` `—` `’` — Zeichen, die eine Tastatur anders tippt als ein
Designer sie setzt.

**Gegenprobe, die es sofort entscheidet:** `grep -rqF '<label>' Sources/ --include=*.swift`.
Bei 0 Treffern ist die ERSTE Hypothese „mein Suchmuster", nicht „das Repo".

### PLAYBOOK (#784) — vor dem Bauen eines Wächters das GESETZ grepen, nicht den Dateinamen

#784 stand kurz davor, eine Herkunfts-Invariante zu pinnen („jede Fläche, die einen Bio-Wert
druckt, muss Demo markieren"). Ein `grep -rln 'isSynthetic|"Demo"' Tests/CISmoke` lieferte
**zwölf** Wächter, darunter `TheDemoSourceIsMarkedWhereItRendersTests`, also exakt diese
Invariante. Ein dreizehnter wäre #416 gewesen.

**Regel:** die Suche geht auf die SACHE (`isSynthetic`, `"Demo"`), nicht auf einen vermuteten
Dateinamen. Ein Wächter heißt hier nach seiner Aussage, nicht nach seinem Gegenstand — wer
`grep DemoTag` oder `grep BioStripViewTests` macht, findet ihn nicht und baut ihn neu.

### DEAD-END (#784) — `.deploy/release` NIE für eine Textkorrektur anfassen

Gemessen in `testflight.yml`: `push: paths: ['.deploy/release']`. Der Filter steht auf der
DATEI, nicht auf der Versionszeile — eine reine Prosa-Korrektur löst einen echten
TestFlight-Upload aus. Korrekturen an der Note warten auf den nächsten echten Deploy.

### PLAYBOOK — benote eine Behauptung, indem du das Modell AUSFÜHRST, nicht indem du sie liest (#785)

Eine Behauptung kann HALB Gegengewicht sein. `TheWireSaysWhoseBodyTests`' Behauptung 14 war
als Gegengewicht gebucht; im Eltern-Commit ausgeführt zeigte sie eine grüne
(Nachrichten-)Hälfte und eine rote (Latch-)Hälfte. Der Fehler ist die schmeichelnde Richtung
aus §3 und im SELBEN Block schon einmal für Behauptung 5 passiert.

**Vorgehen:** die Produktionsfunktion in Python transkribieren, den ELTERN-Zweig daneben
modellieren, jede Behauptung als Prädikat gegen BEIDE fahren und die Wahrheitstabelle
ausdrucken. Was im Eltern grün ist, ist Gegengewicht; was rot ist, Regression. Eine Methode
kann in beiden Spalten stehen — dann sagt man das, statt zu runden. Danach sieben Mutationen
gegen dieselben Prädikate, damit keine Behauptung ununterscheidbar von ihrer Verletzung ist.

### DEAD-END — automatische Duplikat-Erkennung in der Founder-Checkliste (#790)

**Nicht noch einmal naiv versuchen.** `scripts/founder-verify.py` sammelt jeden
`NEEDS-FOUNDER-VERIFY`-Vermerk zu der Liste, aus der eine Geräte-Sitzung triagiert wird. Zwei
Vermerke für EINE Frage kosten eine verschwendete Probe. Naheliegend: Duplikate automatisch
finden.

**Gemessen 2026-08-24 an 52 Einträgen mit einem Schlüssel aus den ersten 8 normalisierten
Wörtern — und das Ergebnis war in BEIDE Richtungen falsch:**
· **Ein Fehlalarm.** Der einzige Treffer (`ParameterRowStacksAtAccessibilitySizesTests` und
  `BioNumbersGrowWithTheTextTests`) ist KEIN Duplikat: beide beginnen mit demselben
  Geräte-SETUP („iOS Settings → Display → Text Size auf eine Accessibility-Größe"), prüfen
  danach aber Verschiedenes. Zusammenzulegen wäre ein Verlust.
· **Der echte Doppelte wurde NICHT gefunden.** Meine eigenen zwei sACN-Vermerke aus #789 fragen
  dasselbe („cacht ein Pult den Quellnamen?"), fangen aber verschieden an — „whether a real
  console…" gegen „a console may CACHE…".

**Das ist #778 auf die Warteschlange angewandt: eine FRAGE hat so viele Formulierungen, wie
jemand geschrieben hat.** Ein Präfix-Schlüssel misst die Formulierung, nicht die Frage. Ein
Prüfer mit Fehlalarmen ist ein Prüfer, den niemand liest (#665) — deshalb NICHT gebaut.

**Stattdessen die billige Regel, die keine Heuristik braucht:** wer einen Vermerk setzt, prüft
mit `python3 scripts/founder-verify.py`, ob dieselbe Frage schon dasteht, und setzt sie an
EINEN Ort — die #416-Regel, angewandt auf Bitten statt auf Entscheidungen. Der Zeiger im
Nachbarn ist Prosa, kein zweiter Marker.


## PLAYBOOK (2026-08-24, #788–#797): UNTER-Behauptungen findet man nur, wenn man danach sucht

**Der Befund, sechs Zyklen lang und jedes Mal woanders:** eine ausgelieferte, betürte Fähigkeit
hatte die Fläche nicht erreicht, die sie VERKAUFT. #788 die Integrator-Tabellen · #791 sACN im
Store-Text · #793 die Claim-Liste · #794 der MPE-Ausgang · #795 die Stimme (nur in den
Release-Notes) · #797 die Stimme auf der Website (null von achtzehn Seiten).

**Warum das so lange lief: jede Prüfung in diesem Repo sucht nach FALSCHEN Aussagen.** Eine
Fähigkeit, die nirgends behauptet wird, verletzt keine davon. Sie ist unsichtbar, und
Unsichtbarkeit sieht aus wie Sauberkeit.

**Das billige Werkzeug, das die Reihe beendet hat (eine Messung, kein Wächter):**
```
✅-Zeilen aus ContentPipeline/CLAIMS.md  ×  GESAMTER fastlane/metadata-Korpus
✅-Zeilen aus ContentPipeline/CLAIMS.md  ×  GESAMTER docs/-Korpus
```
Verzeichnis-getrieben, nie als Dateiliste. #795 fand so die Stimme (nur in `release_notes.txt`),
#796 fiel dabei als ÜBER-Behauptung mit ab (zwei Synth-Module ohne Instanziierung, als `LIVE`
verkauft).

⚠️ **Und die Sonde misst das WORT, nicht die Fähigkeit.** Zwei Fehlalarme in einem Lauf: „generativ"
und „pitch" fehlten im deutschen Store-Text, der „erzeugt" und „Kammerton" sagt und vollständig
ist. Jeden Treffer gegen den Quelltext lesen, bevor er „Lücke" heißt (#679/#738).

## PLAYBOOK (2026-08-24, #796/#797): ein Wächter, dessen PRÄMISSE im Code gemessen wird, kann keine #364-Falle werden

**Das Problem:** ein Wächter, der eine Prosa-Regel festnagelt („nenne X immer mit Zusatz Y"),
verbietet die künftige Arbeit, die X wahr macht — und die Lösung war bisher immer eine Notiz
„im selben Commit aufheben", die jemand lesen muss.

**Die Form, die das nicht braucht:** zuerst die Prämisse ZÄHLEN, dann die Forderung nur unter
ihr stellen.
· #796: `Module(` im CODE von `Sources/**` = 0 → jede öffentliche Zeile muss „not wired" sagen.
  Wer das Modul verdrahtet, wird übersprungen. Nichts aufzuheben.
· #797: `VoiceCaptureEngine(` + `VoiceAnalyzer(` > 0 → mindestens EINE Seite muss die Fähigkeit
  nennen, und jede nennende Seite den „kein Ton"-Zusatz. Verschwindet die Kette, verschwinden
  beide Forderungen.

⚠️ **Kommentare IMMER strippen** (`SourceText.codeOnly`). CLAUDE.mds eigene Notiz ZITIERT das
Rezept `git grep -n "EchoelModalBank(" -- Sources`; eine Quelldatei, die diese Notiz
zurückzitiert, ließe einen naiven Scan seine eigene Dokumentation als Instanziierung lesen.

## DEAD-END (2026-08-24, #796): pro DATEI prüfen kann einen Selbstwiderspruch IN der Datei nicht sehen

**Versucht:** „nennt eine Datei ein totes Modul, muss irgendwo darin ein ‚not wired' stehen."
Gewählt, um eine legitime dritte Nennung nicht anzumeckern (#486).

**Ergebnis: auf dem KAPUTTEN Elternteil GRÜN.** Der Defekt war eine Übersichtszeile, die einer
Detailzeile **derselben Datei** widerspricht (#425) — `architecture.html` trug „Not wired" auf
Zeile 224 und verkaufte dasselbe Modul auf Zeile 346 als `LIVE`. Pro-Datei kann das prinzipiell
nicht sehen. Die Fenster-Variante danach schlug in `FEATURE_MATRIX.md` falsch an, wo jeder
Eintrag eine `**Code:**`- gefolgt von einer `**Live:**`-Zeile hat.

**Stattdessen:** beide Hälften am ANSPRUCH verankern (die Roster-Zeile über ihren
`<div class="k">`-Schlüssel, die Live-Zeile über ihre Abschnittsüberschrift), mit
#454-Zusicherung, wenn der Anker fehlt. Kein Fenster, keine Nähe, keine Fehlalarme.

**Und die Lehre über das Verfahren, nicht über den Inhalt:** das hätte niemand am Text gesehen —
nur das TREIBEN gegen den Elternteil hat es gezeigt. Ein Wächter, der auf dem kaputten Baum
grün ist, ist kein Wächter.

---

### PLAYBOOK (#804) — einen Wächter treibt man samt seiner DATEI-AUFLÖSUNG

**Situation:** ein neuer Wächter liest Dateien, die er selbst findet (Repo-Wurzel per Aufwärtslauf,
Verzeichnis-Aufzählung, Locale-Walk).

**Der Fehler, der zweimal bezahlt wurde:** der Python-Treiber reicht dem Scanner die Dateien
**per Pfad**. Damit ist die LOGIK geprüft und die AUFLÖSUNG nie. Zwei Wächter waren so von
Tag eins an rot — einer sechs Commits lang, während Status-Deltas sagten, er pinne den
App-Store-Text.

**Stattdessen:** die Auflösung mit-transkribieren. Konkret für einen Aufwärtslauf: den Lauf in
Python nachbauen, ab dem echten Startverzeichnis, und ausdrucken, WO er landet — nicht nur, was
der Scanner dann sagt.

**Und die Regel, die daraus fällt:** ein Sentinel muss **eindeutig für den Ort sein, den er
markiert**. `CLAUDE.md` ist es nicht — `Tests/CISmoke/` hat ein eigenes, und genau dort beginnt
der Lauf. `Package.swift` ist es. Gepinnt von `TheRootSentinelIsUniqueToTheRootTests`.

### DEAD-END (#804) — `SourceText.codeOnly` auf `Tests/CISmoke/` verstümmelt

**Nicht nochmal probieren:** einen Wächter, der das GUARD-BUNDLE scannt, mit
`SourceText.codeOnly` zu strippen. Der Stripper trägt Block-Kommentar-Zustand über Zeilen und
kennt `"""` nicht, also öffnet ein `docs/**` in einer Fehlermeldung einen Block, der nie
schließt. Gemessen: **8 Dateien, 943 Zeilen unsichtbar** — gegen **0 von 369** unter `Sources/`.

**Stattdessen:** zeilenweise lesen und `//`-Zeilen überspringen (kein Zustand, nicht
entgleisbar). Für `Sources/` bleibt `codeOnly` richtig und Pflicht (#453) — die Grenze verläuft
am Korpus, nicht am Verfahren.

## DEAD-END + PLAYBOOK (2026-08-25, #808): eine Nadel gegen einen grünen Nachbarn zu prüfen ist keine Prüfung

**DEAD-END.** Einen `contains(...)`-Nadel-Text aus einer benachbarten, grünen Zusicherung zu
übernehmen und ihn für verifiziert zu halten. `TheBioPanelRowsSayWhoseBodyTests` trug zwei Monate
`contains("your body")` gegen einen Satz, der „your measured **body state**" lautet — nie getroffen,
seit dem Geburts-Commit (`7e906cd`, `git log -S` auf beide Hälften).

**Warum die Nachbarn grün waren (die eigentliche Lehre).** Sie bauen ihren Satz durch den geteilten
Helfer `subject(synthetic:)`, dessen Realkörper-Zweig das Literal IST. Der eine Static, der den
Helfer nicht ruft, ist der eine, dessen Nadel danebenging. **Prüf-Rezept: wenn N Nadeln dieselbe
Zeichenkette benutzen und eine rot ist, frag nicht „wer hat abgeschrieben", sondern „welcher Satz
geht am geteilten Erzeuger vorbei".**

**PLAYBOOK — Nadeln treiben, nicht transkribieren.** Die Zeichenketten mit `re` AUS der Quelldatei
lesen (nicht abtippen), dann Kontrolle + eine Mutation je Zusicherung fahren. Kostet zehn Minuten
und hätte diesen Fehlschlag am Tag seiner Entstehung gefangen.

**Verstärker: #807.** Ein Fehlschlag ist im Job-Log nur sichtbar, wenn er in `tail -200 test.log`
fällt. „Gates grün" heißt nie „die Suite lief" — die `WINDOW`-Zeile von `gh-test-verdict.py` vor
jedem Zitat lesen.

## PLAYBOOK (2026-08-25, #809): eine Nadel, die eine FUNKTION ruft, ist nicht selbstprüfend

**Der Unterschied, den dieses Repo bisher nicht benannt hatte.** `code.contains("…")` (SCAN)
prüft sich beim Schreiben selbst — man grept die Zeichenkette. `Typ.methode(x).contains("…")`
(LAUFZEIT) prüft nichts, weil es hier keine Swift-Toolchain gibt und der Job-Log nur
`tail -200 test.log` zeigt. Genau so überlebte #808 zwei Monate rot.

**Rezept:** `python3 scripts/needle-reachability.py` vor dem Push einer Laufzeit-Nadel. Es fragt,
ob das Literal im Quelltext der gerufenen Funktion vorkommt — Konkatenations-Nähte
zusammengefügt, EIN Helfer-Sprung aufgelöst. Heute null Treffer über 1015 Nadeln.

**DEAD-END im Werkzeugbau selbst — zweimal in einem Zyklus, beide nur durchs TREIBEN gefunden:**
· Ein Werkzeug-Docstring, der seine Fehlerrichtung behauptet, ohne sie zu treiben: „never a
  false alarm" war exakt rückwärts. **Unvollständige** Auflösung erzeugt FEHLALARME, **zu
  breite** erzeugt falsche GRÜNS. Ein Werkzeug, das seine Richtung falsch angibt, ist schlimmer
  als eines, das schweigt — ein Befund wird als Beweis gelesen oder als „bekannte sichere
  Richtung" verworfen.
· Eine negative Nadel über Prosa, die ihre eigene Rücknahme ZITIERT (#491) — der Kontroll-Baum
  kommt rot zurück. Das passiert auch dem, der #491 in derselben Stunde gelesen hat. **Nur der
  Kontroll-Lauf zeigt es; Zurücklesen nicht.**

## DEAD-END × 2 (2026-08-25, #814): das Ergebnis-Artefakt ist unerreichbar, und `smoothBreathDepth` ist kein Messwert

**DEAD-END 1 — den `.xcresult`-Bericht holen, um das #807-Fenster zu umgehen.** Der vollständige
Testbericht EXISTIERT (`test-results-ios-iPhone 17`, ~4,4 MB, Aufbewahrung ~90 Tage;
`mcp__github__actions_list method=list_workflow_run_artifacts` zeigt ihn). Er ist von einer
Sitzung aus trotzdem **nicht lesbar**, aus drei unabhängigen Gründen: (a) der MCP-Satz hat kein
Download-Werkzeug, nur `list` · (b) `archive_download_url` verlangt `actions:read`-Auth, auch bei
einem ÖFFENTLICHEN Repo, und in diesem Container gibt es kein Token (`.claude/settings.local.json`
existiert nicht) · (c) selbst heruntergeladen bräuchte ein `.xcresult` `xcresulttool`, also macOS.
**Nicht noch einmal versuchen.** Die einzige echte Reparatur liegt in `ci.yml` (Tail erhöhen ODER
einen Schritt, der eine kompakte Pass/Fail-Liste aus dem Bundle druckt) und ist founder-gated.

**DEAD-END 2 — `EchoelBioEngine.smoothBreathDepth` als Quelle für den toten `breathDepth`-Kanal.**
Es sieht aus wie die fehlende Atem-TIEFE und ist ein Platzhalter: `git grep "smoothBreathDepth *="`
findet nur den Initialwert `0.5`, und der einzige Leser `audioParameters()` hat **null Aufrufer**.
Zwei Deklarationen (die zwei `#if`-Zweige der Datei), beide jetzt am Ort markiert. Wer den
`breathDepth`-Kanal beleben will, fängt bei der **Respirations-Analyse** an, nicht hier — das ist
eine echte DSP-Scheibe und grenzt an die geschützte Triade.

**PLAYBOOK, aus beiden:** eine Kandidaten-Quelle wird mit `grep "<name> *="` auf ihre SCHREIBER
geprüft, nicht auf ihre Existenz. Ein `public var` mit plausiblem Namen und einem neutralen
Initialwert ist die häufigste Form von „sieht verdrahtet aus".

---

## PLAYBOOK (2026-08-25, #816): eine Liste, die kein Werkzeug scannt, verrottet unbemerkt

**Der Fall.** `scratchpads/FOUNDER_DEVICE_SESSION.md` bündelt seit 2026-07-16 alle
geräte-/urteilsgebundenen Punkte, weil der Founder der einzige Geräte-Prüfer ist. Zwei Monate
später baten VIER ihrer sieben Abschnitte um Proben an gelöschten Flächen (Piano-Roll-Editor,
Drums-Spur, AUv3-Host, Clip-Editor-Warp) plus ein Flag, das es nie mehr gibt.

**Warum es niemandem auffiel — und das ist der übertragbare Teil:** `scripts/founder-verify.py`
scannt `Sources/`, `Tests/` und `CLAUDE.md`, **absichtlich nicht `scratchpads/`**. Die Datei war
damit eine ZWEITE Liste **neben** dem Werkzeug, das behauptet, den Einkaufszettel zu drucken.
Es gab keinen Widerspruch zu finden: die eine Liste wusste von der anderen nichts.

**Erkennungszeichen.** Wenn ein Werkzeug eine Wurzelmenge NENNT, frag als Nächstes, was
AUSSERHALB dieser Wurzeln dieselbe Sorte Inhalt trägt. Der Ausschluss ist meist richtig
begründet (hier: „scratchpads sind Sitzungsprosa"), und genau diese gute Begründung ist der
Grund, warum niemand hinschaut.

**Kosten-Asymmetrie, die den Fall vom üblichen Stale-Prosa-Fall trennt:** veraltete Prosa kostet
sonst Lesezeit. Diese kostet **Geräte-Zeit des Founders** — die einzige Ressource, die keine
Sitzung erzeugen kann. Ein Posten, der auf ein entferntes Bedienelement zeigt, verbraucht eine
Probe, die nichts entscheiden kann (#525, hier auf Dokument-Ebene).

**Playbook, wenn man so eine Liste repariert:**
1. Jeden Posten gegen den Code messen, nicht gegen die Erinnerung — die Streichungen kamen aus
   fünf verschiedenen Epics, keine davon hatte diese Datei im Blick.
2. Die Liste auf das reduzieren, was **kein Marker tragen kann** (Urteile, Screenshots,
   Ein-Feld-Entscheide); alles Code-Verankerte gehört ins Werkzeug, sonst entsteht die zweite
   Liste sofort neu.
3. Den Wächter **nur auf die Ankreuz-Zeilen** setzen. Ein dateiweiter Negativ-Scan trifft die
   ⛔-Tabelle, die die gestrichenen Namen zitiert (#491 — derselbe Selbsttreffer wie #809).
4. Jede Nadel **gegen den Elternbaum treiben**, bevor sie ausgeliefert wird (#808/#815).

## REGISTER (2026-08-29, #881): zwei CI-Defekte, die `doctor.py` findet und die NIEMAND aufgeschrieben hatte

Founder-gated (`.github/workflows/**` = berichten, nicht editieren). Sie stehen hier, weil
sonst jeder Doctor-Lauf sie neu „findet" und die nächste Sitzung sie neu bewertet.
Beide sind **CRITICAL** und beide sind **nicht** die schon bekannten #396 / #208 / Auto-Merge-Befunde.

### 1. `ci.yml` — vier Build-Schritte, deren Fehlschlag nichts rot färben kann

| Zeile | Mechanismus |
|---|---|
| `ci.yml:244` | JOB `performance-tests` ist ganz `continue-on-error` **und er baut** |
| `ci.yml:293/294` | `Run Performance Tests`: Build in `\|\| true`, Pipe ohne `set -o pipefail`, toleriert BUILD-Fehler |
| `ci.yml:304/305` | `Memory Leak Detection`: dasselbe Muster |
| `ci.yml:381/382` | `Build Release Archive`: dasselbe Muster |
| `benchmark.yml:67` | `Benchmark: Clean Build Time` pipet ohne `set -o pipefail` |

**Die Reihenfolge der Reparatur ist nicht beliebig, und das ist der Teil, den man vergisst:**
erst muss der EIGENE Exit-Status des Schritts ehrlich sein (`|| true` weg, Pipe abgesichert),
DANN kann ein Wächter-Schritt auf `steps.<id>.outcome` prüfen — und der braucht ein `id:`.
Ein Wächter über einem `|| true` liest für immer Erfolg. `.conclusion` ist die falsche
Eigenschaft: `continue-on-error` zwingt sie auf `success`.

### 2. `ci.yml:290/291` — ein `-only-testing:`-Filter nennt eine Suite, die es nicht gibt

`ComprehensiveTestSuite` ist **keine** `XCTestCase`-Klasse in diesem Repo. Ein Lauf mit null
getroffenen Tests meldet (angenommen, **nicht** verifiziert — kein Xcode hier) Erfolg statt
Fehlschlag. Also testet dieser Schritt nichts und sagt „grün".

⚠️ **Aber die Umbenennung allein bringt nichts:** derselbe Schritt sitzt im maskierten Job aus
Befund 1. Erst die Maske, dann der Name — sonst repariert man den Namen eines Schrittes, dessen
Ergebnis ohnehin niemand liest.

### Warum das hier steht und nicht in `CLAUDE.md`

Kopfraum. `CLAUDE.md` stand beim Eintragen bei 149 611 B unter einer 150 000-B-Decke; ein
dritter CI-Absatz dort hätte den Wächter rot gemacht, den er beschreibt. Der CI-Abschnitt in
`CLAUDE.md` nennt bereits #396, #208 und den Auto-Merge-Befund — das ist das GESETZ; dies hier
ist der Rückstand.

## DEAD-END (2026-08-30, #885): „Bio-Modulation live sichtbar" hat ZWEI Lesarten — die eine ist gebaut, die andere sinnlos

Der stündliche Cron liefert eine REIHENFOLGE, die drei gelöschte Features nennt (Piano Roll
#475, Clips/Arrangement #121 Slice 4, AUv3 #121 Slice 2) und einen toten Branch-Namen. Punkt 2 —
„welche Parameter das Biofeedback bewegt, sichtbar, Leaf-Views, kein Root-Read" — sieht als
einziger noch offen aus. Er ist es nicht, **aber der Grund ist nicht der, den die Formulierung
nahelegt: der Satz benennt zwei verschiedene Subsysteme, und dieses Ledger trug schon eine
Antwort auf das ANDERE.**

| Lesart | Was zeigt sie | Stand |
|---|---|---|
| **A — die IMMER-AN-Kanäle** (`AlwaysOnBioChannel`: Kohärenz · HRV · Puls · Atemphase → Filter/Brightness/Vibrato/Amplitude) | was der Körper HEUTE am Klang bewegt | **GEBAUT, zwei Türen, 29 Wächter** |
| **B — die MODULATIONS-MATRIX** (`ModulationEngine.lastOutputs`) | was eine vom Nutzer gelegte Route bewegt | **sinnlos ohne Route-Editor** — Default-Matrix leer, null `ModRoute(`-Konstruktionsstellen (#541); ein Readout zeigte „nichts aktiv" |

⭐ **Lesart B stand seit 2026-07-18 zweimal in diesem Ledger** (der PLAYBOOK „grep die ECHTEN
Consumer" und die DEAD-END-BESTÄTIGUNG „kein Item-2-Readout-Leaf ohne Gerät"), und beide sind
unverändert richtig. Sie beantworten Punkt 2 aber nur zur Hälfte — und die Hälfte, die sie
beantworten, ist die, die man ohnehin nicht bauen soll. **Wer nur sie liest, schließt „Item 2 ist
offen und wartet auf den Route-Editor" und übersieht, dass die Frage, die ein Spieler wirklich
stellt, längst eine Fläche hat.**

Lesart A, gemessen — nicht erinnert:

| Frage | Befehl | Befund |
|---|---|---|
| Wird die Zeile gebaut? | `git grep -n "AlwaysOnBioRow(" -- Sources` | 2 Stellen: `AlwaysOnBioRow.swift:236`, `EchoelFXView.swift:1333` |
| Hat Wirt 1 eine Tür? | `git grep -n "AlwaysOnBioPanelStrip(" -- Sources` | `EchoelStudioView.swift:3205`, im `bioPanel` (nächstes vorangehendes `private var … some View` = `bioPanel:3089`) → Puls-Pillen-Tap (#706) |
| Hat Wirt 2 eine Tür? | `git grep -n "showAllFX" -- Sources` | Setzer `EchoelStudioView.swift:7665` (`Button { showAllFX = true }` im `effectsPanel`) → `.sheet:1480` → `EchoelFXView:1488` → `AlwaysOnBioView():507` |
| Freeze-Gesetz eingehalten? | `grep -n "latestBio" …/EchoelStudioView.swift` | **3 Treffer, ALLE DREI KOMMENTARE** — null Live-Bio-Lesevorgänge im Wurzel-Rumpf; gelesen wird in `AlwaysOnBioPanelStrip`s eigenem Rumpf (ein `View`-`struct` IST die Beobachtungsgrenze, `AnyView` nicht) |
| Abgesichert? | `git grep -l "AlwaysOnBio" -- Tests/CISmoke \| wc -l` | **29 Wächter-Dateien** |

⭐ **Die Lehre ist nicht „der Cron ist alt" — das war bekannt. Sie ist doppelt:**
1. **Eine abgelaufene Aufgabenliste altert PUNKTWEISE.** Drei Punkte als tot zu erkennen erzeugt
   kein Misstrauen gegen den vierten; im Gegenteil, er wirkt dann als der Rest, der „noch offen"
   ist. Der billige Test bleibt: Konstruktionsstelle suchen, der Kette bis zum RENDERNDEN
   Elternteil folgen. Vier `grep`s gegen eine ganze Bau-Runde.
2. **Ein Aufgaben-Satz kann zwei Subsysteme meinen, und ein Ledger-Eintrag beantwortet immer nur
   das, das der Schreiber gerade im Kopf hatte.** Die zwei Einträge von 2026-07-18 sind wahr und
   lasen sich beim Wiederfinden wie eine vollständige Antwort. Wer einen „Item N"-Eintrag
   schreibt, schreibt dazu, WELCHE Maschine er gemessen hat — sonst deckt der Eintrag später
   eine Lücke zu, statt sie zu schließen.

⚠️ Der Cron-Text bleibt **unverändert**: er trägt das Mandat des Founders, und eine Sitzung, die
die Anweisung ihres Auftraggebers umschreibt, weil sie sie für veraltet hält, ist ein größerer
Defekt als eine veraltete Anweisung. Jeder Zyklus korrigiert sie beim Lesen — das kostet drei
Zeilen und ist die richtige Richtung.

### Nebenbefund im selben Lauf: `doctor.py` Sektion C ist SAUBER, gemessen statt erinnert

Sektion C nennt neun türlose `View`-Typen und sagt selbst, der Test pro Eintrag sei „steht das
Parken in `CLAUDE.md`?". Beantwortet mit
`for v in …; do grep -c "$v" CLAUDE.md; done` → **9 von 9 dokumentiert** (Analysis×4, BioSource,
Broadcast, ImmersiveStage, ProUnlock, Session). Türlos ist hier kein Defekt; türlos **und
nirgends aufgeschrieben** wäre einer. Der Lauf hat also KEINEN neuen Register-Befund erzeugt —
was einen eigenen Eintrag wert ist, weil sonst der nächste Doctor-Lauf dieselben neun Zeilen neu
bewertet.

## PLAYBOOK (2026-08-30, #886): ein Eigenschafts-NAME gehört nicht einem Typ — prüfe den EMPFÄNGER, bevor du eine Nadel daraus baust

Ein Wächter sollte alle Leser von `AudioEngine.masterLevel` einsammeln. Die naheliegende Nadel
`.masterLevel` (Kommentare gestrippt) wählt **sieben** Dateien — und **fünf davon lesen eine
ANDERE Eigenschaft gleichen Namens**: `MusicalFrame.masterLevel` (`HeaderMonitors`,
`MusicMediaMapping`, `MetalBioView`) plus einen `AutomationPlayer`-Enum-Case, der ebenfalls
`.masterLevel` heißt. Der Wächter wäre auf einem KORREKTEN Baum rot gewesen — die #408-Falle,
diesmal nicht durch eine mehrdeutige STELLE, sondern durch einen mehrdeutigen NAMEN.

**Rezept:** vor jeder Member-Nadel `git grep -n "\.<name>\b" -- Sources` laufen lassen und die
TREFFER lesen, nicht ihre Anzahl. Findet man zwei Typen, gibt es drei Auswege, in dieser
Reihenfolge: (1) ein Geschwister-Member, das nur EINEM Typ gehört (hier `.masterLevelR`, die
Stereo-Hälfte — `MusicalFrame` hat sie nicht), (2) den Empfänger mit ins Muster nehmen
(`audioEngine.` — **abgelehnt**, weil eine Ansicht die Engine anders binden kann und die Nadel
dann still nichts trifft), (3) den Namen ändern. Wer (1) nimmt, schreibt die KOSTEN dazu: ein
künftiger Nur-Mono-Leser ist unsichtbar, und ein Gegengewicht muss pinnen, dass der
Diskriminator noch diskriminiert.

⭐ **Und der Anlass ist die #756-Form in ihrer teuersten Ausprägung:** die AU5-Notiz im
`BAUSTELLEN_BOARD` hat einen 60-Hz-Freeze-Posten mit der Prämisse „die Props liest NUR
`MasterLoudnessGrid`" abgeräumt. Der SCHLUSS („heute kein Live-Freeze") stimmt weiter — aber aus
einem Grund, den die Notiz nie nannte (Geschwister im `ZStack`, nicht Vorfahre). Der ZEUGE ist
mit **#747** falsch geworden: `SpectralDonutView` liest dieselben Meter und bekam damals eine
Tür. **Niemand hat die Notiz angefasst; die Welt hat sich unter ihr geändert.** Genau dafür ist
Anspruch 1 des neuen Wächters da — er leitet die Leser-Menge zur Laufzeit aus `Sources/` ab
statt sie abzutippen (#883-Muster).

## PLAYBOOK (2026-08-30, #888/#889): der BILLIGE Weg, das Test-Bündel-Bauen zu prüfen

`Xcode Compile Check` baut **nur `Sources/`** — ein grünes Häkchen dort sagt über eine
TESTDATEI nichts (`Tests/CISmoke/CLAUDE.md` §5). Der übliche Nachweis ist der Job-Log der
CI/CD-Pipeline: `** TEST EXECUTE FAILED **` OHNE `** TEST BUILD FAILED **` ⇒ das Bündel hat
gebaut. Der kostet mit `tail_lines: 200` rund **20 000 Token pro Zyklus**.

**Billiger Indikator, gemessen über vier Zyklen:** die letzten ~30 Zeilen desselben Logs tragen
den Artefakt-Upload, und dort steht `there will be N files uploaded` bzw. `Uploaded bytes`.
`TestResults` entsteht nur, wenn Tests LAUFEN; ein Bündel, das nicht baut, bricht davor ab.
Beobachtet: 5155 → 5157 → 5161 → 5173 → 5175 Dateien, jeweils in dem Zyklus gewachsen, in dem
Ansprüche dazukamen. Abruf mit `tail_lines: 30`–`34` statt 200.

⚠️ **GRENZEN, und sie gehören dazu, sonst wird der Indikator als Beweis gelesen:**
1. Es ist ein **Indikator, keine Sichtung des Verdikts.** Es zeigt „Tests liefen", nicht
   „das Bündel baute fehlerfrei" — die Richtung stimmt (kein Bau ⇒ keine Ergebnisse), die
   Umkehrung ist nicht bewiesen.
2. **Kein Verhältnis pro Anspruch.** 4 neue Ansprüche brachten +12 Dateien, 1 Anspruch +2. Wer
   daraus „3 Dateien je Test" ableitet, rechnet mit Rauschen.
3. Es sagt **nichts über FEHLGESCHLAGENE Tests.** Dafür bleibt `gh-test-verdict.py` auf dem
   200er-Fenster — und dessen `WINDOW`-Zeile lesen, bevor man ein Grün zitiert (#807).

**Regel: den billigen Indikator für „lief das Bündel überhaupt", das teure Fenster erst, wenn
er STAGNIERT oder ein Anspruch neu ist und man sein Ergebnis wissen muss.**

---

## PLAYBOOK (2026-08-30, #911): eine Deploy-Notiz misst gegen den BUMP-Commit, nie gegen das eigene Fenster

**Der Fehler.** Ich schrieb in `.deploy/release` für v10.79.431: „Compile Check grün auf allen
**fünf** Commits seit 430". Fünf war die Anzahl der Slices, die ich in DIESEM Kontextfenster
gefahren hatte — für mein Fenster also korrekt. Der Nenner war falsch: eine Version verhält
sich zum letzten Bump, nicht zu einer Sitzung.

**Die Messung, eine Zeile:**
```
git log -S "v<vorgänger>" --oneline -- .deploy/release   # → der Bump-Commit
git log --oneline <bump>..HEAD | wc -l                   # → 54, nicht 5
git log --oneline <bump>..HEAD -- Sources/ | wc -l       # → 33 im Auslieferungscode
```

**Warum das teuer ist und nicht Buchhaltung.** Die Notiz ist das einzige Dokument, aus dem der
Founder seine Geräteprobe priorisiert. „Fünf Diagnose-Commits" lädt zum Fünf-Minuten-Blick
ein; in Wahrheit lagen vier VERHALTENS-Reparaturen am Mikrofon-Weg (#889/#890/#891–#897/#900)
zum ersten Mal in seiner Hand — und was in der Notiz nicht steht, prüft er nicht. Der Schaden
ist nicht die falsche Zahl, sondern **eine ungeprüfte Auslieferung**.

**Warum kein Wächter das fangen kann.** Die Zahl steht in Prosa, in einer Datei, die absichtlich
frei formuliert ist. `TheShippedVersionComesFromTheReleaseFileTests` (#635) prüft die
VERSIONS-Extraktion — die war die ganze Zeit korrekt. Das Loch ist die Behauptung DANEBEN.
Deshalb ist das hier ein Playbook und kein Test.

**Regel für die nächste Notiz — drei Zeilen, bevor der erste Satz geschrieben wird:**
1. Bump-Commit des Vorgängers holen (`git log -S`).
2. `<bump>..HEAD -- Sources/` durchsehen und JEDE verhaltensändernde Reparatur namentlich in
   den Nutzer-Abschnitt heben. Diagnose-Commits gehören in den Log-Abschnitt, nicht nach oben.
3. Für jede genannte Reparatur eine PRÜFBITTE formulieren — sonst steht sie da und wird nicht
   gefahren.

⭐ **Und die Rücknahme gehört in die NOTIZ.** Ich habe den „fünf Commits"-Satz als dritten
Eintrag in den vorhandenen `WAS ICH NICHT BEHAUPTE`-Block der Notiz gesetzt, nicht nur in die
Commit-Nachricht — die liest der Founder nie. Die #456-Form gilt auch für Rücknahmen.

---

## PLAYBOOK #919b (2026-08-31) — Mutanten fahren und ein zweiter Leser prüfen VERSCHIEDENE Dinge

**Der Anlass.** #918b hat den Wächter `TheMenuHostReadsNoHotStateTests` (damals `…NoHotBio`)
in beide Richtungen gefahren — sieben Fehler gefunden — und trotzdem **rot ausgeliefert**. Die
Nadel `"analyzer."` verlangte hinter dem Treffer ein Nicht-Wort-Zeichen; hinter einem Punkt steht
bei einem Eigenschaftszugriff immer ein Buchstabe. Der ganze Saat-Zweig war tot.

**Wie es entdeckt wurde — und das ist der übertragbare Teil.** NICHT durch mehr Mutanten.
Durch die Regel in `Tests/CISmoke/CLAUDE.md` §3: *wer einen Wächter substanziell umschreibt,
fährt JEDE Behauptung, nicht nur die geänderten.* Von 29 schlug genau eine fehl.

**Warum es zwei Zyklen überlebt hat — zwei bekannte blinde Flecken gleichzeitig:**
1. Das CI-Job-Log trägt nur `tail -200 test.log` (#807/#445) — ein Fehlschlag weiter vorn ist
   unsichtbar, und die Abwesenheit eines Testnamens beweist nichts.
2. Delta-Benotung vergleicht Eltern mit Arbeitsbaum. Rot auf BEIDEN erzeugt kein Delta und wird
   von nichts gemeldet.

**Und dann fand ein zweiter Leser VIER weitere Defekte, die kein Mutant gefunden hatte** —
nachdem ich neun Mutanten gefahren, alle Behauptungen transkribiert und das Repo gefegt hatte:
ein falsches Grün (dateiweite Empfänger-Suche bei zwei Bindungen in einer Datei), ein fehlender
Boden auf einer Derivation, Größen-Anker die genau die dokumentierte Reparatur rot färben (#364),
und eine ganz fehlende Nadel (`: some Scene {` — die ÄUSSERSTE Body der App).

⭐ **DIE REGEL:**
> **Fahren** beantwortet: *verhält sich mein MODELL des Wächters wie gedacht?*
> Es kann nicht fragen: *ist mein Modell das RICHTIGE?*
> Dafür braucht es einen zweiten Leser. **Beides ist Pflicht, nicht eines statt des anderen.**

**Checkliste für den nächsten substanziell umgeschriebenen Wächter — vier Zeilen:**
1. Jede Behauptung portieren und gegen den ECHTEN Baum fahren, auch die unveränderten.
2. Jede neue Logik als Mutant in BEIDE Richtungen fahren (rot für den Defekt, grün für die
   dokumentierte Reparatur).
3. Reviewer konvenieren — und ihn ausdrücklich nach FALSCHEM GRÜN und nach #364 fragen, nicht
   nur nach Compile-Risiko.
4. Prüfen, ob ein Anker eine GRÖSSE misst. Eine Größe ist fast immer rot auf korrekter Arbeit;
   ein NAME (`var body`) überlebt Refactorings, die eine Zahl bewegen.

---

## PLAYBOOK #925 (2026-08-31) — ein Feld unter „Published Output" ohne Erzeuger ist eine FALLE, kein toter Code

**Fundstelle.** `CameraAnalyzer.dominantHue` (`Video/CameraAnalyzer.swift`), deklariert unter
`// MARK: - Published Output`, dokumentiert als „Average hue (0–360)". Gemessen über das GANZE
Repo (`Sources`, `Tests`, `docs`, `ContentPipeline`, `scripts`, `project.yml`): **genau EIN
Vorkommen — die eigene Deklaration.** Kein Schreiber, kein Leser. Der Wert war dauerhaft 180,
also Cyan, und nichts konnte ihn je bewegen. Gefunden von `scripts/doorless-state.py`, aber
NICHT durch dessen Regel erklärt: seine Sortierung sagt „eine Tuning-Konstante ohne Schreiber
ist in Ordnung" — und genau darunter hätte diese Zeile für immer weitergelebt.

**Warum das schlimmer ist als ein unbenutztes Feld — die eigentliche Lehre.** Der Block ist eine
ECHTE Ausgabefläche: `CameraRPPGBioPublisher` liest `brightness` und `redChannel` daraus. Eine
spätere Sitzung, die die Visual-Palette an die Kamerafarbe hängen will, öffnet diese Klasse,
findet `dominantHue` ZWISCHEN zwei Werten, die leben, bindet es — und liefert ein dauerhaft
cyanfarbenes Feature aus, das von jeder Seite verdrahtet AUSSIEHT: Erzeuger da, Verbraucher da,
Doc da, Konstante auf der Leitung. Das ist die `.eegBurst`-Form (eine OSC-Adresse ohne
Produzenten, auf die laut `CLAUDE.md` kein Integrator warten darf) eine Nummer kleiner, INNEN
in der Klasse statt auf einem Draht, wo niemand hinsah.

⛔ **NICHT BERECHNEN — die Richtung ist der Punkt.** `avgR`/`avgG`/`avgB` liegen an der Stelle
schon vor, wo `brightness` geschrieben wird; den Farbton zu rechnen wäre vier Zeilen. Das wäre
ein ERZEUGER für einen Wert, den nichts verbraucht — die Spiegelung von #496 (drei Bio-Kanäle
mit Verbraucher und ohne Erzeuger). Beide Richtungen kosten dasselbe: eine Fähigkeitsbehauptung,
die nirgends ankommt. Entfernt, mit einem ⛔-Vermerk an der Stelle, damit die Absicht nicht
still verlorengeht.

⭐ **DIE WÄCHTER-FORM, und sie ist der übertragbare Teil.** Eine Nadel auf die ABWESENHEIT von
`dominantHue` wäre #364 in Reinform: Kamera-Farbton als Palettenquelle ist ein legitimes
Feature, und am Tag, an dem jemand es mit Erzeuger UND Leser baut, wäre der Wächter rot auf
korrektem Baum. `EveryPublishedOutputHasAProducerTests` fragt stattdessen JEDE im Block
deklarierte Ausgabe nach einer ZUWEISUNG in derselben Datei. Mutant gefahren: ein echter
`dominantHue = 42`-Erzeuger lässt den Wächter GRÜN. Er hat keine Meinung darüber, welche
Ausgaben existieren — nur darüber, dass eine angekündigte Ausgabe berechnet wird.

⚠️ **Zwei Textsichten in EINEM Scan — aber nur EINE Hälfte ist tragend, und die erste Fassung
hat die falsche dafür erklärt (#925b).** Die Blockgrenze (`// MARK: - Published Output`) ist ein
KOMMENTAR und überlebt `SourceText.codeOnly` nicht — wer nach dem Strippen darauf ankert, findet
nichts und die ganze Datei besteht LEER. **Das ist die tragende Hälfte.**

⛔ **Die STRIPP-Hälfte ist PROPHYLAKTISCH (0 von 4 Verdikten kippen), und ihre Begründung war
schlicht falsch.** Sie lautete: sonst zählte der ⛔-Vermerk, der die entfernte Deklaration
wörtlich zitiert, als lebende Ausgabe mit. Tut er nicht — getrimmt beginnt diese Zeile mit `//`,
also verfehlt der `var `-Präfixtest sie auch im ROHTEXT. Auf beiden Bäumen gefahren, Roh- gegen
Gestrippt-Deklarationen: identische Verdikte. ⭐ Die Form, die WIRKLICH nur das Strippen fängt,
ist ein `/* … */`-Block, dessen Innenzeile `var foo = 1` lautet — roh beginnt sie mit `var `,
gestrippt ist sie leer (an einer Vorlage nachgewiesen). Der Entwurf steht, nur seine Begründung
war die #367-Spiegelung eine Ebene höher: grün aus einem anderen Grund als dem genannten.
**Lehre für JEDEN Stripper-Einsatz: §2 dieser Test-Direktive verlangt das Zählen roh gegen
gestrippt auf BEIDEN Bäumen und das Etikett TRAGEND/PROPHYLAKTISCH. Wer die Begründung
plausibel findet statt sie zu fahren, schreibt eine Falschbehauptung in einen Wächter-Kopf.**

⛔ **UND DIE ZWEITE FASSUNG HATTE EIN LOCH IM SCAN SELBST, nicht nur in der Prosa.** Der
Präfixtest lief gegen die getrimmte Zeile, also war jede Deklaration mit ATTRIBUT unsichtbar —
und der bewachte Block enthält davon schon zwei (`@ObservationIgnored var beatTimes`,
`@ObservationIgnored private(set) var rrSegments`). Der Block hat also DREIZEHN `var`s, nicht
elf; die erste Fassung berichtete die Teilmenge ihres eigenen Scans als Inhalt der Datei.
Mutant gefahren: ein unberechnetes `@ObservationIgnored var ghostHue` ließ alle drei Ansprüche
GRÜN — der Wächter stumm bei genau dem Defekt, den sein Name beschreibt. `withoutLeadingAttributes`
schließt es. **Lehre: wenn ein Scan eine MENGE zählt, ist die erste Frage nicht „stimmt die
Zahl", sondern „welche Form sieht er nicht" — und die Antwort steht meistens schon im Ziel.**

Grenzen aus dem ROHTEXT, Inhalt aus dem GESTRIPPTEN; `codeOnly` erhält die Zeilenzahl, und genau
das macht die zwei Sichten indexierbar. ⚠️ Die Endgrenze prüft `hasPrefix("// MARK:")` auf der
getrimmten Zeile, nicht `contains("MARK:")` — heute identisch (alle zwölf Vorkommen der Zieldatei
sind echte Überschriften), aber die Fehlerart ist STILL: eine Kommentarzeile, die eine
Überschrift nur ERWÄHNT, schnitte den Block ab und nähme jede Ausgabe darunter aus der Deckung,
ohne dass etwas rot wird.

**Wo man diese Klasse noch sucht:** überall, wo ein Typ seine Ausgaben unter einer eigenen
Überschrift SELBST deklariert. Das ist ein Vertrag, den ein Textscan halten kann. Die allgemeine
Fassung („jede `@Observable`-Ausgabe in `Sources/` hat einen Erzeuger") ist NICHT erzwingbar —
viel legitimer Zustand wird dateiübergreifend geschrieben, weshalb `doorless-state.py` seinen
MASKED-Abschnitt hat und ausdrücklich nicht anklagt.

---

## REGISTER #926 (2026-08-31) — zehn private `slice`-Helfer, EIN Name, ZWEI Bedeutungen

**Gemessen** (Kommentare gestrippt, Körper klammer-gematcht, alle `Tests/CISmoke/*.swift`):
zehn Dateien deklarieren je ein privates `slice(…, from:, to:)`, um einen Member-Rumpf aus
Quelltext zu schneiden. Sie zerfallen in **zwei Familien, die verschiedene Dinge tun**:

| Familie | Dateien | Rückgabe |
|---|---|---|
| **EXCLUDES-marker** | 4 (`AudioInputDoorTests`, `MIDIClockTests`, `RecordRouteOwnershipTests`, `TheMarkIsTheSameMarkTests`) | Text NACH dem `from`-Marker |
| **INCLUDES-marker** | 6 (`AutoModeStartsOffAndOwnsNoTempoTests`, `TheBioSourceChooserHasOneDefinitionTests`, `TheChipStripAdmitsItOverflowsTests`, `TheHintRetiresOnLessonLearnedTests`, `TheLogoHoldsItsPlaceTests`, `TheMonitorToggleAsksForTheMicTests`) | Text BEGINNEND MIT dem Marker |

Beide enden vor dem `to`-Marker, die Familien unterscheiden sich also um **genau den
Öffnungs-Marker**. An einer Vorlage gefahren, nicht argumentiert: für dieselbe Eingabe liefern
sie verschiedene Zeichenketten, und eine Nadel, die irgendetwas zählt, was im Marker-Text
vorkommt (ein Funktionsname, `private func`, ein Label), liest in der INCLUDES-Familie **um eins
höher**. Beide liefern bei verfehltem Anker `""` — eine `count == 0`-Zusicherung über einen
fehl-verankerten Schnitt besteht also LEER.

⚠️ **LATENT, NICHT LIVE — und das gehört zum Befund.** Jede `slice(`-Bindung in den sechs
INCLUDES-Dateien wurde daraufhin gescannt, ob eine ihrer Nadeln im eigenen `from`-Marker
vorkommt: **heute null.** Es ist also gerade nichts kaputt. Die Falle schnappt in dem Moment zu,
in dem jemand eine Zusicherung zwischen zwei Wächter-Dateien VERSCHIEBT — was dieses Repo
laufend tut (§4 der Test-Direktive handelt von nichts anderem als Prosa und Wächtern, die das
Zuhause wechseln). Zwei Schreibweisen einer Operation ist der #416-Defekt „ob sie heute
übereinstimmen oder nicht"; hier stimmen sie nicht einmal heute überein.

⛔ **KEINE MIGRATION, UND DAS IST ABSICHT.** Zehn Helfer in eine geteilte Definition zu falten
ist das richtige Endbild — es ist, was `SourceText.codeOnly` für den Stripper ist —, aber es
fasst zehn Dateien an und ÄNDERT DIE BEDEUTUNG VON VIEREN. Das ist eine Migration mit
Founder-Sprengweite, keine Ralph-Scheibe. Der Wächter ist deshalb so geschrieben, dass die
Migration GRÜN bleibt: er verlangt, dass jede Deklaration KLASSIFIZIERBAR ist — nie eine
bestimmte Familie, Zahl oder Dateiliste. Null Deklarationen besteht. Eine neue Datei mit einer
der beiden Familien besteht. Nur eine DRITTE, anders arbeitende Schreibweise wird rot.

⭐ **DER KLASSIFIKATOR MUSS AUF DER ARITHMETIK ANKERN, NICHT AUF DEM TEXT — gemessen.** Der
normalisierte Körper-TEXT liefert DREI verschiedene Körper, nicht zwei: `TheMarkIsTheSameMarkTests`
schreibt die EXCLUDES-Familie mit `open`/`after`/`close` statt `start`/`rest`/`end`. Text zu
pinnen würde also (a) die Familien falsch zählen und (b) am Tag einer Umbenennung rot werden —
ein Wert, den ein Leser vernünftigerweise ändern darf, und genau das verbietet #364. Der
Klassifikator fragt stattdessen die RANGE-Arithmetik: `.lowerBound..<` = Marker bleibt,
`.upperBound...` = Marker fällt. Sortiert alle zehn, die umbenannte eingeschlossen, in 4 + 6.

⛔ **UND DIE ERSTE FASSUNG DES SCANS LAS SICH SELBST — die dritte Nadel-Kollision in drei
Scheiben.** Der Anker `func slice(` traf das eigene Nadel-LITERAL im Scanner, weil
`SourceText.codeOnly` String-Literale absichtlich stehen lässt: elf Deklarationen, eine davon
unklassifizierbar, **rot auf korrektem Baum**. Reparatur ist ein STRUKTURELLER Diskriminator
(die Zeile davor darf nur Modifikatoren enthalten), keine Ausnahmeliste für die eigene Datei —
eine Ausnahme hätte den Scan für genau die Datei blind gemacht, die ihn ändert.

⭐ **DIE GEMEINSAME URSACHE DER DREI KOLLISIONEN, und das ist der übertragbare Teil:**
#921b ein nackter Typname, der die eigene Deklaration traf · #924 eine Nadel aus einer
BESCHRIFTUNG, die zwei fremde Zeilen mit demselben Wort traf · #926 ein Scanner, der sein
eigenes Literal las. **Jedes Mal war die Nadel danach gewählt, wie die Sache HEISST, statt
danach, wo sie nur VORKOMMEN kann.** Und jedes Mal hat nur das FAHREN es gefunden, nie das
Lesen.

---

## REGISTER #928 (2026-08-31) — ein VIERTER heißer `@Observable`-Schreiber, und der Wächter kannte nur zwei

**Der Befund.** `CLAUDE.md` sagte drei Wochen lang „es sind DREI" Erzeuger, die einen
`@Observable`-Wert schneller schreiben, als ein Finger es könnte (Kamera ~10 Hz ·
`AudioEngine.startMeterPollTimer` 60 Hz · `AutomationPlayer.applyStep` pro Transport-Schritt).
Der vierte ist `metronome.bpm`: `Transport.onTempoChange(id: "metronome")` in
`EchoelmusicApp` schiebt ihn bei jeder Tempoänderung, während eines Glides bis ~20 Hz.

⭐ **Das Unangenehme daran ist nicht, dass niemand es wusste — der Quelltext sagt es selbst.**
Direkt über der Registrierung steht seit ihrer Entstehung: „this callback WRITES an
@Observable at up to ~20 Hz … which is only harmless because no view body reads
`metronome.bpm`. If one ever does, it must be a leaf." Ein perfekt formulierter Vermerk, den
kein Wächter las — die #496-Form: ein ⛔ am Erzeuger erreicht die Zeile nicht, die eine
Sitzung ZUERST liest, und hält niemanden davon ab, morgen genau das zu tun, wovor er warnt.

⚠️ **Warum ausgerechnet diese Fläche die gefährlichste der vier ist.** Bei Kamera und Engine
ist der Empfänger im Menü-Wirt gar nicht in Gebrauch. Hier liest `EchoelStudioView.body`
`metronome.` bereits VIERMAL — die Tempo-Zeilen und die Click-Leiste des Mix-Bretts, alle zu
Recht KALT, weil ein Mensch sie dreht. Empfänger und Gewohnheit sitzen also schon im Rumpf,
und die heiße Schreibweise unterscheidet sich von den kalten um EIN WORT. Eine
„aktuelles Tempo"-Beschriftung neben den Klick-Zeilen ist die naheliegendste Ergänzung der
Welt und wäre sofort der Founder-Befund „Menüs frieren beim Spielen ein".

**Die Form, die das abfängt** (vier Ansprüche, alle vier GRÜN auf beiden Bäumen —
**PROPHYLAKTISCH (0 of 4)**, ein Vorwärts-Wächter, kein Fund, #433/#486):
1. Ableitung: die heiße Menge kommt aus der REGISTRIERUNG des Relais, nie aus einer Liste.
2. Die vier kalten Zeilen sind NICHT heiß — und die Fehlermeldung sagt, dass ein Rot dort
   „verschiebe diesen einen Read in ein eigenes Blatt" heißt, nicht „nimm die Zeile zurück"
   (#364).
3./4. Menü-Wirt und oberster Vorfahre bauen keinen View aus der heißen Menge.

⭐ **Die Ableitung ist bewusst über ALLE Registrierungen geschrieben, nicht über die erste.**
`firstIndex` hätte eine Schleife gelesen und die Menge für vollständig erklärt — genau der
Fehler, den ein zweites Relais eines Tages ausnutzt. Mutant M3 (ein Step-Subscriber, der
`beatsPerBar` schreibt) macht Anspruch 2 UND 3 rot: die kalte Zeile wird heiß, und der
bestehende Rumpf-Read wird im selben Moment zum echten Defekt. Genau die zwei Rots, die man
sehen will.

**Gefahren, vier Mutanten:** M1 `.bpm` im Menü-Wirt → 3 rot mit Zeilennummer · M2 Relais
umbenannt → 1 rot (und der `found`-Anspruch feuert; 3/4 gingen sonst über einer LEEREN Nadel
grün, #367) · M3 zweites Relais → 2 + 3 rot · M4 `bpm` als `@ObservationIgnored` → 1 rot.

⚠️ **Kopfraum-Warnung, gemessen im selben Commit:** `CLAUDE.md` steht nach dieser Ergänzung
bei 148 497 B von 150 000. Der nächste Register-Eintrag dort muss etwas anderes verdrängen —
`python3 scripts/doctor.py --section D` und `TheLawFileStaysUnderItsCeilingTests` sagen es.

⛔ **NACHLESE #928b — DIE VIERTE NADEL-KOLLISION, und die erste, die das FAHREN NICHT gefunden
hat.** #928 ankerte Anspruch 3 auf `contains("var metronome")`. Dieselbe Zeichenkette trifft in
`EchoelStudioView.swift` **drei** Stellen: die gemeinte `@Environment`-Deklaration (`:166`),
`private var metronomeRow: some View {` (`:4635`) und `@Bindable var metronome = metronome`
(`:4636`). Wer die Bindung in `click` umbenennt, lässt `metronomeRow` unberührt — **der Anker
bleibt grün, während die Nadel tot ist**, also genau der Fehler, den seine eigene
Fehlermeldung zu verhindern behauptet.

⭐ **Und das ist der Grund, warum „ich habe vier Mutanten gefahren" nicht derselbe Satz ist wie
„das ist in Ordnung".** Die drei Vorgänger-Kollisionen (#921b/#924/#926) fand jedes Mal das
FAHREN. Diese nicht — sie ist unsichtbar, solange man den Baum von heute mutiert, weil sie
erst bei einer UMBENENNUNG auftritt, und eine Umbenennung ist kein Mutant, den man sich
ausdenkt, wenn man gerade die Sache selbst geschrieben hat. Gefunden hat sie ein Prüfer beim
LESEN. **Fahren prüft, ob der Anspruch heute misst; Lesen prüft, ob er morgen noch dieselbe
Sache misst.** Beide Fragen brauchen ihre eigene Runde.

**Reparatur, und sie ist keine längere Zeichenkette:** den Namen ABLEITEN
(`environmentReceiver(for:of:in:)`, zwölf Zeilen weiter oben, von der Engine-Hälfte längst
benutzt), damit eine Umbenennung den Wächter MITNIMMT statt ihn zu blenden. Mutant M5 belegt
es: Bindung → `click` ergibt `recv=click`, und ein heißer Read über den neuen Namen macht
Anspruch 3 rot mit Zeilennummer.

⚠️ **Zweiter Prüferfund, andere Klasse: Anspruch 4 ist grün wegen EINES Zeichens.** Das Relais
selbst steht in `mainContent` — einem Element, das dieser Scan betritt — und schreibt
`metronome?.bpm`. Die Nadel hat kein `?`. Wer die Capture-Liste auf ein starkes `[metronome]`
ändert, macht den Anspruch **rot auf völlig korrektem Code**: ein Schreibvorgang in `.task {}`
ist keine Body-Auswertung. Nicht repariert, sondern AUFGESCHRIEBEN — samt der Anweisung, dann
die Relais-Spanne auszunehmen und nicht die Capture-Änderung zurückzunehmen (#364). Nebenbei
verjährt damit die Kopfzeile „None exists today" über Aktions-Closures: eines existiert jetzt,
ein Zeichen daneben.

⭐ **Dritter Fund, der die Abdeckung wirklich vergrößert:** die Bio-Menge wird über VIER
Vorfahren gescannt, die Metronom-Menge über ZWEI. Zwei Zeilen in `WorkspaceView` (Bindung +
`Text("…bpm…")` in `topBar`) lassen alle vier Ansprüche grün und reproduzieren den
10.76.50-Fehler in genau dem Element, das ihn verursacht hat. Die Scans dorthin zu zeigen wäre
heute ein Anspruch, der nicht scheitern kann (#367) — stattdessen wird die PRÄMISSE gepinnt:
`MetronomeVoice` kommt in beiden mittleren Vorfahren null Mal vor. Mutant M6 macht das rot,
und die Meldung nennt den Scan, der dann zu erweitern ist. **Die Engine-Hälfte hat diesen
Anspruch nicht und könnte ihn gebrauchen.**

Dazu vier kleinere Rücknahmen an derselben Scheibe: die `CLAUDE.md`-Zeile sagte „`body` liest
`metronome.` VIERMAL" und war dreifach daneben (VIER sind die EIGENSCHAFTEN, die Reads sind
elf; die Click-Leiste des Mix-Bretts fehlte ganz; keiner der Reads steht in `body` selbst) ·
der Anker von Anspruch 4 pinnte die ARITÄT des Initialisierers (`MetronomeVoice()`) und wäre
an einem hinzugefügten Argument rot geworden — Klammern weg (M7 belegt es) · „verschiebe
diesen EINEN Read" ist falsch, drei der vier kalten Eigenschaften werden an ZWEI Stellen
gelesen · und die Ableitung behauptete, ein zweites Relais „müsse von selbst eintreten" —
das gilt nur unter drei Bedingungen, die jetzt danebenstehen.

---

## REGISTER #929 (2026-08-31) — derselbe Abdeckungs-Riss stand im ÄLTEREN Scan, und er stand als Nebensatz da

**Der Befund.** #928bs Prüfer schrieb einen Halbsatz: *„The engine half has no such claim and
could take one."* Nachgemessen ist das kein Nachtrag, sondern **dasselbe Loch in einem Scan,
der es LÄNGER hatte**. Die Bio-Menge wird über alle VIER Vorfahren gescannt; Engine- und
Metronom-Menge über ZWEI. Für beide ruhte das auf einer PRÄMISSE — dass `WorkspaceView` und
`SurfaceHost` den Typ gar nicht referenzieren —, die im Kopf der Datei zwar sauber
aufgeschrieben, aber von nichts geprüft war. Gemessen stimmt sie: null `AudioEngine`-Treffer in
beiden, während **neun** andere Dateien unter `Sources/` die Bindung deklarieren. Die Prämisse
ist also wahr und zugleich jederzeit still verlierbar.

⭐ **EINEN Anspruch verallgemeinern schlägt eine Beinahe-Kopie danebenstellen (#416).** Der
naheliegende Griff war ein zweiter Test mit anderem Typnamen. Zwei fast identische Wächter sind
die Stelle, an der zwei Wahrheiten auseinanderdriften: eine Änderung zieht in dem einen mit und
im anderen nicht — genau der #456-Defekt, nur in Testform. Der Anspruch trägt jetzt eine
TABELLE `(Typ, Erzeuger, Scan-Suffix)`, und die Fehlermeldung nennt pro Zeile den Erzeuger, für
den dieser Vorfahre ungeschützt wäre, plus den Test, der dann zu schreiben ist.

⚠️ **WAS NICHT IN DER TABELLE STEHT, ist der tragende Teil: `CameraRPPGBioPublisher`.**
`WorkspaceView` MUSS ihn halten — es liest `isRunning` für Start/Stop, und
`testTheRootStillReadsTheStartStopFlag` verlangt genau das zwanzig Zeilen weiter oben. Ihn
mit aufzunehmen hätte erforderliche Arbeit verboten (#364) und einem Nachbar-Anspruch
widersprochen. Die Bio-Menge braucht die Prämisse ohnehin nicht: ihr Scan deckt alle vier ab.
Mutant M6d belegt es — der Publisher im Root bleibt GRÜN.

**Gefahren:** M6a Metronom im Root → rot · M6b Engine im Root → rot (**das ist die neue
Abdeckung**) · M6c Engine im Wrapper → rot · M6d Bio im Root → **grün**, wie es sein muss.
Grün auf Worktree und auf `77d44cd`: PROPHYLAKTISCH (0 of 1).

⭐ **DIE ÜBERTRAGBARE LEHRE, und sie ist nicht „prüf die Prämisse":** ein Prüferbefund kam als
NEBENSATZ („could take one"), und Nebensätze werden zu Registereinträgen, die niemand mehr
liest. Der billige Test ist, den Halbsatz sofort zu MESSEN statt ihn zu notieren — hier
kosteten zwei `grep` eine Minute und verwandelten eine Anmerkung in einen zweiten, älteren
Riss. **Ein Prüferfund ohne Grad ist trotzdem ein Fund.**

---

## PLAYBOOK #930 (2026-08-31) — eine Beschriftung, die eine Behauptung über das PROJEKT war

**Der Defekt.** Die Klick-Zeile hieß **„Beats per bar"**. Das ist die Formulierung, die ein
Musiker als **Taktart** liest — also als Projekt-Einstellung. Gemessen ist sie
**klick-lokal**: `isDownbeat = (beatIndex == 0) && audioAccent`, und `beatIndex` wrappt allein
in der Render-Schleife der Klick-Stimme. Stellt jemand 3 ein, akzentuiert der Klick jeden
dritten Schlag, während Sequenzer, Automation und Clip-Raster in 4 bleiben: **die beiden Takte
fallen einmal beim Start zusammen und driften dann auseinander**, ohne dass irgendetwas auf dem
Schirm es sagt.

⭐ **Das Gesetz dahinter ist STÄRKER als der Satz, der es ausgelöst hat.** Der #927-Prüfer
maß EINE Konstante (`Transport.beatsPerBar`). Für #930 nachgemessen sind es **DREI unabhängige
harte Vieren** — `Transport`, `AutomationPlayer` und `TimelineTime` deklarieren jede ihre
eigene —, und die 1…12 des Klicks erreicht keine davon. Jede ist ein `static let`, also verbietet
der Compiler die Zuweisung ohnehin; der Wächter pinnt, dass sie **`let` bleiben, 4 bleiben**,
und dass die Klick-Datei **keine Brücke** zu ihnen wächst.

**Der ehrliche Name ist der, den der Render-Block hergibt: „Accent every … beats".** Nicht
„Klick-Takt", nicht „Bar length" — beide behaupten weiterhin einen Takt. Die Zahl entscheidet
ausschließlich, **wie oft der Akzent landet**, und bei ausgeschaltetem Akzent gar nichts. Die
Einheit trägt die halbe Ehrlichkeit: „Accent every 4" ist mehrdeutig, „Accent every 4 beats"
nicht — und `EchoelValueField`s VoiceOver-Pfad liest `"\(n) \(unit)"`, also hört ein
nicht-sehender Spieler dasselbe.

⚠️ **NICHT deaktiviert, solange der Akzent aus ist** — bewusst. Den Takt voreinzustellen und
danach den Akzent zuzuschalten ist normale Benutzung; ein ausgegrautes Feld lehrt weniger als
ein Paar, das man interagieren hört.

⛔ **SECHS PROSA-ZUHAUSE für EINE Beschriftung**, alle im selben Commit gezogen (#456): die
Zeile selbst · ihr Nachbarkommentar · zwei Stellen in `mixStripCard("Click")` · der Doc-Kommentar
an `MetronomeVoice.beatsPerBar` (der „(time-signature numerator)" sagte — **die Quelle des
Irrtums**) · `EchoelValueField`s Doc · zwei Wächter-Köpfe. In den Wächtern bleibt der alte Name
als HISTORIE stehen („‚Beats per bar' damals, ‚Accent every' seit #930"), weil beide ihn als
Beispiel einer eingefrorenen Spanne brauchen.

⭐ **Benotung, und sie ist diesmal NICHT prophylaktisch:** Anspruch 7 ist auf dem Elternbaum
`e327172` **ROT** — er fängt die Beschriftung, die dort steht. **TRAGEND (1 of 3).** Die zwei
Meter-Ansprüche sind PROPHYLAKTISCH. Mutanten: Label zurück → 7 rot · Einheit weg → 7 rot ·
`static let` → `static var` → 8a rot · Klick referenziert `Transport` → 8b rot.

⛔ **Und zwei meiner eigenen Nadeln waren nicht kompilierbar:** ich schrieb sie als
`"""`-Literale, weil die Nadel selbst Anführungszeichen trägt — aber in Swift muss auf `"""`
ein Zeilenumbruch folgen. **Beim LESEN gefunden, nicht von CI.** Das ist die #928b-Lehre in
kleiner Form: der Reflex, für eine Nadel mit Anführungszeichen zum mehrzeiligen Literal zu
greifen, produziert einen Compile-Fehler, den kein Mutantenlauf zeigt, weil ein nicht
kompilierender Wächter gar nicht erst läuft.

⛔ **NACHLESE #930b — die Scheibe über Prosa-ZUHAUSE hat ihre eigenen falsch gezählt, und zwar
in BEIDE Richtungen.** #930 schrieb „SECHS Prosa-Zuhause, alle in diesem Commit" und zählte im
selben Satz **acht** Posten auf; tatsächlich bearbeitet waren **zehn**
(`ValueFieldNotifiesEveryPathTests` an zwei Stellen), und **drei weitere** standen noch:
· „Bar length" zwei Zeilen ÜBER dem Absatz, der genau diesen Namen verwirft — **innerhalb
desselben Diff-Hunks** · der Hint des Nachbar-Schalters („the first beat of each **bar**") —
also die Behauptung, die die Scheibe eine Zeile höher gelöscht hatte · `.deploy/release`.
**Das ist der #927-Defekt wörtlich wiederholt, in einer Scheibe, deren Thema er ist.**
⭐ Konsequenz im Wächter: die Fehlermeldung nennt **keine Zahl mehr**, sondern die METHODE —
`git grep` auf das Label, auf „bar length" und auf „time signature"/„Takt". Eine Zahl in einer
Fehlermeldung ist ein Datum; ein Befehl ist eine Anweisung.

⚠️ **`.deploy/release` bleibt ABSICHTLICH stehen, und das ist kein Versäumnis.** Die Notiz
beschreibt den Bau, den der Founder **in der Hand hält** (v10.79.432), und dort heißt die Zeile
wirklich „Beats per bar". Sie jetzt zu korrigieren machte sie für das ausgelieferte Binary
FALSCH. **Deploy-Notizen hinken dem Baum per Konstruktion hinterher** — daraus folgt auch, dass
ein Wächter, der Zeilenbeschriftungen der Notiz gegen `Sources/` prüft, #364 verletzen würde:
er würde eine korrekte Notiz rot färben. Fällig ist die Korrektur beim NÄCHSTEN Bump; sie steht
als eigene `decisions.csv`-Zeile, weil die Datei append-only ist.

⭐ **DER TEUERSTE EINZELFUND: ein zweites `.accessibilityHint` auf EINEM Element.**
`EchoelValueField` setzt `.accessibilityElement(children: .ignore)` und danach seinen eigenen
Hint („Swipe up or down to adjust, or double-tap to type"). Ein an der Aufrufstelle
angehängtes zweites Hint hat deshalb **nur zwei mögliche Ausgänge, und beide sind Defekte**:
entweder es wird nie gesprochen (dann war „ein Hint, der die Grenze ausspricht" eine
Über-Behauptung in Commit, Ledger UND CSV), oder es **ersetzt** die Wisch-Anweisung — genau
die Zusage, um die `ValueFieldNotifiesEveryPathTests` seinen ganzen Fall baut. **Welcher Zweig
feuert, ist durch Lesen nicht entscheidbar**; Komponieren schon. Reparatur ist ein
`hint:`-Parameter, der VOR die stehende Anweisung gesetzt wird — und damit hat die nächste
Aufrufstelle einen unterstützten Weg. Es war die EINZIGE der 57 Aufrufstellen, die das
versucht hat: kein Präzedenzfall, also auch kein Beleg, dass es je funktioniert hat.

⭐ **Und die Umsortierung war der Fund, der die Begründung repariert hat, nicht nur den Text.**
Der #930-Kommentar behauptete, der Akzent-Schalter sitze „zwei Zeilen tiefer" UND „direkt
daneben" — zwei Aussagen, die nicht beide stimmen können, und keine stimmte: `Click level`
stand dazwischen, und #930 hatte gar nichts verschoben. Nach der echten Umsortierung
(**an/aus → Accent every → Accent downbeat → Click level**) ist die Aussage wahr, und erst
damit trägt auch das „nicht ausgrauen"-Argument: die Abhilfe ist die NÄCHSTE Zeile, nicht drei
Zeilen entfernt. `Click level` ist ein MIX-Wert und gehört hinter das Paar, an dem es nicht
teilnimmt.

**Gefahren:** M12 Label zurück → 7 rot · M13 Voice-Datei leergefegt → **8-Boden rot** (vorher
wäre alles grün durchgelaufen — genau der #367-Fund) · M14 Klick referenziert `Transport` →
8-Brücke rot. Alle acht Ansprüche grün auf Worktree und `297e923`.

⛔ **NACHLESE #930c — DER EINZIGE ROTE GATE-LAUF DIESER KETTE, und er war für Python UND für
den Prüfer unsichtbar.** `#930b` fügte `EchoelValueField` einen `hint:`-Parameter hinzu und
deklarierte ihn ZWISCHEN `unit` und `decimals`. Die Aufrufstelle schreibt ihn — richtig, weil
er Prosa ist — als LETZTES: `…, decimals: 0, hint: "…")`. Der memberwise-Initialisierer eines
`struct` verlangt aber **Deklarationsreihenfolge**, also:

    error: argument 'hint' must precede argument 'decimals'

⭐ **Warum das lehrreich ist und nicht nur peinlich: kein Werkzeug dieser Sitzung konnte es
sehen.** Meine transkribierten Ansprüche prüfen TEXT — sie fanden `hint:` und waren zufrieden.
Der Prüfer LAS den Diff und schlug den Parameter sogar selbst vor, ohne die Reihenfolge zu
prüfen. **Es gibt keine lokale Toolchain**, also ist „compile-verifiziert erst durch CI" kein
Höflichkeitssatz, sondern die exakte Grenze: Textprüfung und aufmerksames Lesen decken die
Typprüfung NICHT ab, und ein Parameter, der einer bestehenden Struktur hinzugefügt wird, ist
genau die Sorte Änderung, die dort durchfällt.

**Reparatur: die DEKLARATION verschoben, nicht die Aufrufstelle.** `hint` steht jetzt hinter
`decimals` und vor `onChange`. Damit ist die natürliche Aufrufreihenfolge legal, alle 76
bestehenden Aufrufstellen bleiben gültig (sie lassen `hint` weg, und eine ausgelassene
Vorgabe darf an jeder Stelle fehlen), und die nächste Aufrufstelle tappt nicht in dieselbe
Falle. Die Begründung steht als `⛔` an der Deklaration selbst — der einzige Ort, den jemand
liest, der einen weiteren Parameter hinzufügt.

⚠️ **Regel für jeden künftigen Parameter an einem viel benutzten `struct`: die Position in der
Deklaration IST ein API-Vertrag.** Sie an die Stelle zu setzen, an der das Thema „hingehört"
(hier: neben `unit`, weil beide die Anzeige betreffen), erzeugt an jeder Aufrufstelle einen
Compile-Fehler, der nichts mit dem Thema zu tun hat.

---

## PLAYBOOK #931 (2026-08-31) — die Geräte-Liste nach dem sortieren, was der Bau IN SEINER HAND geändert hat

**Das Problem war nicht die Liste, sondern ihre FRAGE.** `founder-verify.py` gruppiert 63
offene Bitten nach Bereich. Das ist die richtige Form für „geh den ganzen Rückstand durch" und
die falsche für die Frage, die der Founder nach einem TestFlight-Bau wirklich hat: **was hat
DIESER Bau geändert, das ich jetzt prüfen kann?** Sechzig Bitten sind ein Projekt, die Handvoll
eines neuen Baus ist ein Abend. Seine Gerätezeit ist die knappste Ressource dieses Repos — jede
Prüfung, die „das hast du schon beantwortet" oder „das ist noch gar nicht verdrahtet" ergibt,
ist umsonst ausgegeben.

**`--since <ref>`** filtert auf Bitten, deren Marker-ZEILE seit `<ref>` hinzugekommen oder
umformuliert wurde. Für v432 gegen den v431-Bump: **2 von 63** — und die eine, die zählt, ist
die Kohärenz-Klangfarbe, also genau die, mit der die Deploy-Notiz aufmacht. **Zwei unabhängige
Wege, dieselbe Bitte zu benennen, und sie stimmen überein** — das ist der eigentliche Wert
dieser Kreuzprobe.

⚠️ **ES VERGLEICHT DEN REF MIT DEM ARBEITSBAUM, nicht mit `HEAD`, und das ist kein Detail.**
`collect()` liest den Arbeitsbaum; ein `<ref>..HEAD`-Diff lieferte Zeilennummern aus einem
ANDEREN Text, sobald irgendetwas nicht eingecheckt ist — die Bitten würden nach Positionen
gefiltert, die nicht mehr bedeuten, was sie bedeuteten. `git diff <ref>` (ohne zweiten
Endpunkt) ist genau der Vergleich, dessen Nachbild der gelesene Text IST.

⛔ **KEIN STILLER RÜCKFALL AUF DIE VOLLE LISTE.** Wenn git nicht antworten kann — kein Repo,
ein Ref, der nicht auflöst —, wäre das Drucken aller 63 Bitten unter einer Überschrift „seit
`<ref>`" eine SELBSTBEWUSSTE FALSCHE ANTWORT: sie schickt den Founder auf Prüfungen, die dieser
Bau nie berührt hat, und sieht aus wie ein Ergebnis. Exit **2** ist das Wort dieses Skripts
(und von `doctor`) für „das Instrument konnte nicht schauen". ⭐ **Und der teurere Zwilling
davon ist `{}` statt `None`:** ein leeres Dict filtert JEDE Bitte weg und druckt „nichts hat
sich geändert" — dieselbe Lüge, nur beruhigend statt geschwätzig. Selbsttest 10 fährt genau
diesen Mutanten.

⚠️ **DER FILTER SIEHT TEXT, NICHT FÄHIGKEIT**, und die Kopfzeile sagt es jetzt selbst: eine
UMFORMULIERTE Bitte ist eine alte Bitte mit poliertem Satz, keine neu beantwortbare. Genau das
ist bei v432 passiert — eine der zwei Zeilen ist die BLE-Gurt-Bitte, die nur neu formuliert
wurde. Ohne diesen Satz läse der Founder beide als „neu prüfbar".

**Gefahren:** M15 fehlende Hunk-Zahl als 0 gelesen → Selbsttest 9 rot (verliert JEDE
einzeilige Änderung, also die meisten) · M16 `None` → `{}` → Selbsttest 10 rot. Basis grün,
Exit 2 bei unauflösbarem Ref, volle Liste unverändert 63.

⚠️ **EHRLICHE GRENZE: nichts in CI ruft `--selftest`.** Die zwei neuen Ansprüche laufen, wenn
eine Sitzung sie fährt — nicht auf jedem Push. Das ist dieselbe Klasse wie die maskierten Gates
in Sektion A von `doctor`: ein Werkzeug, dessen Kontrolle niemand automatisch ausführt. Nicht
repariert (Workflows sind founder-gated), sondern benannt.

⭐ **Auszahlung für die Deploy-Notiz-Disziplin (#911):** die Notiz misst gegen den BUMP-Commit;
jetzt kann sie ihre Prüf-Bitten auch **daraus ableiten** statt sie aus dem Gedächtnis zu
schreiben — `python3 scripts/founder-verify.py --since <voriger Bump>` gehört ab dem nächsten
Bump neben die Messbefehle.

## PLAYBOOK #1008–#1012 (2026-09-05) — eine abgeschriebene Liste reparieren: ABLEITEN oder LITERAL BEHALTEN?

**Der Anlass.** Sieben Full-Suite-Tests waren still rot (Audit-Punkt 25). **Fünf davon hatten
DENSELBEN Defekt**: eine Liste oder Konstante, die im Test von Hand abgeschrieben stand,
während der Code sich absichtlich weiterbewegt hat. Keiner war ein Code-Fehler. Alle fünf
waren unsichtbar, weil `full-tests.yml` `continue-on-error` auf dem Build-Schritt trägt.

**Die Versuchung ist, alle fünf gleich zu reparieren — und das wäre zweimal falsch gewesen.**
Die Entscheidungsregel, die dabei herauskam:

> **BESITZT DIE QUELLE DIE LISTE SCHON?**
> · **Ja** → das Literal ist ein DUPLIKAT. Ableiten. Ein Duplikat kann nur driften, und es hat
>   gedriftet, sonst stünde man nicht hier.
> · **Nein** → das Literal IST die Zweitmeinung. Behalten, von Hand, damit es rot werden KANN.
>   Aus dem Prüfling abzuleiten hieße, ihn gegen sich selbst zu prüfen — eine Zusicherung, die
>   nie fehlschlagen kann, ist keine.

Angewandt:

| # | Fall | Besitzt die Quelle die Liste? | Reparatur |
|---|---|---|---|
| 1009 | 6 statt 11 automatisierbare Parameter | **Ja** (`PolySynthVoice.automatableBases`) | abgeleitet, in BEIDE Richtungen |
| 1012 | „jedes Genre eines Archetyps" | **Ja** (`beatFlavor != .neutral`) | auf die geflavourten eingegrenzt |
| 1010 | 16 statt 17 JSON-Schlüssel | **Nein** (`CodingKeys` ist `private`, nicht `CaseIterable`) | Literal BLEIBT; die FIXTURE wurde verstärkt |
| 1011 | „jedes Flag ist aus" | **Nein** (Registrierung steht in `EchoelmusicApp`, nicht im Flag-Typ) | drei Ausnahmen als Literal, **weil ein blockierender Wächter die Quelle scannt und ZUERST rot wird** |
| 1008 | tau gegen die falsche Kadenz | keine Liste — eine ZAHL aus einem veralteten Mechanismus | Zahl gegen den gemessenen Abstand neu gerechnet |

**Die Zusatzregel, die #1011 liefert und die man sonst übersieht:** ein Literal ist auch dann
sicher, wenn ein Wächter im BLOCKIERENDEN Bündel dieselbe Menge aus der Quelle scannt. Dann ist
das Literal nicht die einzige Wahrheit, sondern die zweite Stimme eines Paares — und die erste
wird zuerst rot. Vor dem Abschreiben also fragen: *gibt es diesen Wächter schon?* (Hier ja:
`EveryFlagSaysWhatItGatesTests.testExactlyThreeFlagsAreRegisteredDefaultOn`.)

**Zwei Fallen beim Umschreiben, beide reine Syntax — Transkribieren fängt sie NICHT:**
· eine `\`-Zeilenfortsetzung ist nur in einem `"""`-Literal erlaubt, nicht in `"…"`.
· `filter(Liste.contains)` als blanke Methodenreferenz ist mehrdeutig (`contains(_:)` vs.
  `contains(where:)`) — schließen: `filter { Liste.contains($0) }`.

**Und eine Fixture-Falle, die #1010 fast ein zweites Mal gekostet hätte:** ein Test über die
VOLLSTÄNDIGKEIT einer Kodierung muss auf einer Fixture laufen, in der **jedes Optional besetzt
ist**. Sonst schreibt `encodeIfPresent` für die `nil`-Felder gar keinen Schlüssel, ihr Fehlen in
der Erwartungsmenge ist still „korrekt", und ein vergessenes neues optionales Feld bleibt genau
für den Test unsichtbar, der dafür geschrieben wurde. Die Eigenschaft „alle Optionals besetzt"
gehört als eigene Zusicherung daneben, sonst schwächt sie jemand später zurück.

**DEAD-END im selben Atemzug:** nicht für jede dieser Reparaturen einen neuen Wächter ins
blockierende Bündel legen. Vier der fünf Mechaniken hatten dort bereits GENAU EIN Zuhause
(`SmoothingStepsTheFrameGapNotThePollRateTests`, `TheAutomatableSetHasOneWriterTests`,
`EveryFlagSaysWhatItGatesTests`). Ein zweiter Wächter derselben Sache kann nur vom ersten
abdriften (#416). Was diese sieben rot stehen ließ, war ohnehin kein fehlender Wächter, sondern
`continue-on-error` — und das ist founder-gated: berichten, nicht editieren.

## PLAYBOOK #1034–#1036 (2026-09-06) — die Nebenläufigkeit MESSEN, bevor man eine Flotte plant; und zwei Sorten lügender Gates

**1. Die Flotte ist so groß wie die Maschine, nicht wie der Plan.**
`Workflow` deckelt gleichzeitige Agenten auf `min(16, CPUs − 2)`. Gemessen in diesem
Container: `nproc` → **4**, also **Deckel 2**. Ich hatte ~90 Widerleger entworfen, ohne
die Maschine zu messen; der Lauf wurde auf 142 Agenten groß und brauchte **~3 Stunden**
für Arbeit, die bei Deckel 14 unter 30 Minuten gewesen wäre. Die Agenten laufen alle,
nichts geht verloren — es dauert nur linear länger, und das sieht man dem Skript nicht an.
**Rezept vor jedem großen Fan-out: `nproc`. Ist der Deckel ≤ 4, ist ein 40-Agenten-Lauf
ein Stunden-Job — dann lieber zwei kleinere Läufe hintereinander, damit man zwischendurch
lesen und umsteuern kann.**

**2. Ein lügendes Gate hat zwei Sorten, und sie verlangen ENTGEGENGESETZTE Reparaturen.**

| | `preflight-check.sh` (#1034) | `build-guard.sh` Stufe 4 (#1035) |
|---|---|---|
| Symptom | lief 1 von 45 Prüfungen, immer exit 1 | lief 5 Prüfungen über 0 Vorkommen, immer grün |
| Ursache | `set -e` + `((PASSED++))` → bei 0 ist der Rückgabewert 0, Bash liest Fehler | Suchliste zeigte auf gelöschte Typen; `pass` stand AUSSERHALB der Schleife |
| Inhalt | echt und wertvoll | leer |
| Reparatur | **reparieren** | **löschen** |
| Warum | 45 echte Deploy-Invarianten, nur unerreichbar | der Compiler erzwingt dieselbe Regel schärfer (Redeklaration im Modul = Fehler) |

**Die Entscheidungsregel, die daraus folgt: gibt es einen STÄRKEREN Erzwinger, ist der
Check Ballast — löschen. Gibt es keinen, sind die Prüfungen das Vermögen — reparieren.**
Beide Male ist die Zwischenlösung falsch: einen leeren Check zu reparieren erzeugt ein
Gate, das läuft und lügt (#1034 Defekt 2 hätte genau das getan — vier Phantom-FAILs), und
einen vollen Check zu löschen wirft 45 Invarianten weg.

**3. `((X++))` unter `set -e` ist eine wiederkehrende Bash-Falle, keine Einzelfall-Panne.**
`build-guard.sh` hatte dieselbe Struktur und war zufällig richtig geschrieben
(`PASSED=$((PASSED + 1))`). **Nadel für den nächsten Sweep:**
`grep -rn '^\s*((\w*++))\s*$' scripts/` — jeder Treffer in einem Skript mit `set -e` ist
derselbe Defekt.

**4. Eine Rücknahme, die den alten Code ZITIERT, macht den eigenen Wächter rot.**
Mein #1035-Wächter suchte `pass "Type conflict scan complete"` als Abwesenheit — und die
Erklärungs-Notiz, die ich eine Minute vorher in dasselbe Skript geschrieben hatte, zitiert
genau diese Zeile. Der Wächter fand seine eigene Grabinschrift und meldete Regression.
**Regel: in einer Datei, deren Kommentare absichtlich zurückgenommenen Code zitieren, muss
JEDE Nadel zeilenverankert sein (`^…`) — nicht nur die, an die man beim Schreiben denkt.**
Gefangen von der Python-Nachfahrt, nicht vom Lesen; das ist der Grund, warum die Nachfahrt
gegen BEIDE Bäume läuft und nicht nur gegen den neuen.

**5. Eine Zahl in einem vorbereiteten Textblock altert im Scratchpad genauso wie im Repo.**
Der zwei Tage vorbereitete #1036-Kommentar sagte „sechs ausgelieferte Breiten … 24 Zustände
… überlebt in 23". `ChromeBudgetFitsTests.devices` hält **drei** Breiten → 12 Zustände, 11
Überlebende. Der Befund stimmte, die Arithmetik drumherum war Dekoration. **Vorbereitete
Prosa vor dem Einfügen gegen den Baum nachrechnen, nicht nur einfügen.**

## PLAYBOOK #1042b (2026-09-06) — die Leak-Prüfung schlug FALSCH an, und das Wort war deutsch

**Was passierte.** Die Pre-Push-Prüfung auf Modell-Bezeichner meldete auf `c676f39b` einen
Treffer. Gemessen war es **`.claude-Baum`** — deutsche Prosa für „der ganze `.claude`-Baum" —
in einer `decisions.csv`-Zeile. Die Nadel `claude-[a-z0-9]` trifft unter `-i` jedes
`claude-<Buchstabe>`, also auch jeden Bindestrich-Kompositum-Namen. **Kein Modell-Bezeichner
war im Commit** — gegengeprüft mit einer zweiten Nadel, die nach dem Bindestrich eine
FAMILIE oder eine Versionsziffer verlangt statt eines beliebigen Buchstabens; sie kam leer
zurück. (Die Alternation ist hier bewusst BESCHRIEBEN und nicht ausgeschrieben — siehe den
⛔-Absatz unten: ein Muster, das Bezeichner trifft, enthält zwangsläufig etwas, das die eigene
Prüfung trifft. Das ist die #491-Form, ein Negativ-Scan gegen seine eigene Rücknahme.)

**Warum das nicht harmlos ist.** Genau der Mechanismus, den diese Sitzung sechsmal
dokumentiert hat: eine Prüfung, die wolf ruft, wird beim nächsten Mal durchgewunken — und dann
rutscht der echte Treffer mit durch. Ein Fehlalarm in einem SICHERHEITS-Check ist teurer als in
einem gewöhnlichen.

**Die schärfere Nadel** (beide Richtungen gefahren: 0 auf diesem Commit, 2 auf zwei
gepflanzten echten Bezeichnern — hier BEWUSST NICHT ausgeschrieben, siehe die Notiz unten —
und `.claude-Baum` bleibt stumm):
Sie ist **absichtlich nicht hier ausgeschrieben** (derselbe Grund wie eine Zeile höher).
Ihre REGEL, aus der sie sich in zehn Sekunden rekonstruieren lässt: nach `claude-` muss eine
der vier Familien oder eine Ziffer folgen; zusätzlich die Formen `<Familie>-<Ziffer>` und
`opus <Ziffer>`. Was sie NICHT mehr trifft: `claude-` plus irgendein Buchstabe.

**Warum die Zeile in `decisions.csv` NICHT nachträglich geändert wurde:** die Datei ist
append-only (Bedingung dieser Sitzung, geprüft mit `git diff --numstat` = +N/-0). Eine
Korrektur wäre ein Widerspruch zur Regel, die den Log überhaupt vertrauenswürdig macht. Der
Befund gehört hierher, nicht in eine nachträgliche Bearbeitung.

⛔ **UND DAS AUFSCHREIBEN DER TESTPROBEN WAR SELBST EIN VERSTOSS.** Die erste Fassung dieses
Absatzes zitierte die zwei gepflanzten Bezeichner wörtlich — und die harte Regel dieser Sitzung
lautet: **kein Modell-Bezeichner in Commits, Code oder Repo-Dateien**, nur in der Antwort an den
Founder. Die schärfere Nadel schlug prompt auf dem eigenen Commit an, mit dem einzig richtigen
Ergebnis. Beim Fahren eines Sicherheits-Mutanten gehört die Probe in die **Shell**, nicht in die
Datei: `printf` in ein `grep`, Ergebnis notieren, Literal wegwerfen. Die Nadel ist damit auch
selbst-belegend — sie hat ihren eigenen Autor erwischt.

⚠️ **Und die generelle Lehre steht schon zweimal in dieser Datei, hier ist sie ein drittes Mal
in neuer Gestalt:** eine Nadel ist eine BEHAUPTUNG über die Form dessen, was sie sucht. Wer sie
nur in der Positiv-Richtung testet („findet sie den echten Fund?"), erfährt nie, worauf sie
sonst noch anspringt.

## DEAD-END #1047 (2026-09-07) — `actions_list` mit `resource_id: <workflow-datei>` PLUS Branch-Filter liefert VERALTETE Läufe

**Nicht wiederholen. Gemessen, zweimal, am selben Tag.**

```
mcp__github__actions_list   method=list_workflow_runs
                            resource_id="xcode-compile-check.yml"
                            workflow_runs_filter={"branch": "claude/…", "status": "completed"}
  -> neuester zurückgegebener Lauf: 2026-08-23   (Läufe von HEUTE existieren)

mcp__github__actions_list   method=list_workflow_runs
                            resource_id="ci.yml"
                            workflow_runs_filter={"branch": "claude/…"}
  -> neuester zurückgegebener Lauf: 2026-08-23   (Lauf 34069319247 von heute fehlt)
```

Beide Antworten sind INHALTLICH plausibel — richtiger Branch, richtige `workflow_id`,
richtiger `path` — also gibt es kein Warnsignal. **Man liest ein zwei Wochen altes `success`
und hält es für das Urteil über den eigenen Commit.** Das ist genau die Fehlerklasse, für die
`Tests/CISmoke/CLAUDE.md` §5 existiert, nur eine Ebene früher: nicht ein falsch gelesener Log,
sondern der falsche LAUF.

**MACH STATTDESSEN — zwei Schritte, beide gemessen funktionierend:**
1. `list_workflow_runs` **OHNE** `resource_id`, gefiltert auf
   `{"branch": "claude/…", "status": "completed"}`. Gemessen 2026-09-07 (#1051): liefert die
   Läufe von HEUTE, namentlich mit `head_sha` des eigenen Commits.
2. Aus dem Treffer die `id` nehmen und `list_workflow_jobs` mit `filter: "latest"` fahren. Diese
   Antwort ist klein (Jobs tragen KEINE Commit-Nachricht) und nennt jeden Schritt namentlich —
   `Build for Testing` ist das, was man sucht.

⛔ **SCHRITT 1 STAND HIER MIT `{"event":"push","status":"in_progress"}` UND DAS IST FALSCH
(korrigiert 2026-09-07, #1051).** Derselbe Aufruf ohne `resource_id`, nur mit
`{"event":"push"}`, lieferte heute **wieder Läufe vom 23. August** — dieselbe stille Fälschung,
die dieser Eintrag beschreibt, nur über den anderen Filter. Der Schuldige ist also **nicht
`resource_id`**: gemessen ist bisher genau EINE Kombination frisch (`branch` + `status`), und
**zwei** liefern Altdaten (`resource_id`+`branch`; `event` allein). Warum, weiß hier niemand —
darum steht das REZEPT und keine Theorie. **Und die Lehre gilt über dieses Werkzeug hinaus: die
erste Fassung dieses Eintrags leitete aus zwei Fehlschlägen mit `resource_id` ab, `resource_id`
sei die Ursache — und schrieb die Reparatur so auf, dass sie eine der ungeprüften Alternativen
empfahl. Ein „mach stattdessen" ist erst dann eines, wenn genau DIESE Zeile einmal gelaufen ist.**
⚠️ Immer den `head_sha` gegen `git rev-parse HEAD` halten, bevor man ein `success` glaubt. Das ist
die einzige Prüfung, die alle drei Varianten unterscheidet, und sie kostet nichts.

⚠️ **Warum Schritt 1 die Antwort trotzdem sprengen kann:** jeder Lauf-Eintrag trägt
`head_commit.message` VOLLSTÄNDIG. Bei den langen Commit-Texten dieses Repos sind das ~4 KB pro
Eintrag, und ein Lauf pro Workflow bedeutet fünf Einträge für EINEN Push. `perPage` klein halten
und über den Status filtern, nicht über den Workflow.

## PLAYBOOK #1047b (2026-09-07) — schnell hintereinander pushen KILLT das Compile-Gate des Zwischen-Commits

Gemessen an `d6590529`: `Xcode Compile Check` Job-Conclusion **`cancelled`**, Schritt
„Compile (iOS device SDK, no signing)" nach 2:55 min abgebrochen — weil `d1f9edda` sechs
Minuten später gepusht wurde und die Concurrency-Gruppe den laufenden Job abräumt.

**Die Falle ist die Beschriftung.** `cancelled` ist WEDER grün NOCH rot; wer nur auf
`conclusion != "failure"` prüft, liest es als „nicht kaputt" und schreibt „Gates grün" in ein
Status-Delta. Es ist aber „**kein Urteil**" — dieselbe Kategorie wie #445s abwesender Testname.

⭐ **Was in derselben Messung ÜBERLEBT hat und deshalb der brauchbare Weg ist:**
`Echoelmusic CI/CD Pipeline` wurde NICHT abgebrochen und lieferte `Build for Testing: success`.
Die zwei Gates verhalten sich unter Concurrency verschieden. Also:

- Ein Zwischen-Commit hat sein Compile-Urteil oft NUR aus dem CI/CD-Lauf. Das reicht, denn
  `Build for Testing` baut App-Target UND `Tests/CISmoke` — mehr als der Compile-Check, der
  laut `project.yml` `build.targets` nur `Sources/` baut.
- Wer eine Kette von Scheiben schiebt: entweder nach der LETZTEN einmal lesen (der neueste Lauf
  enthält alle), oder zwischen den Pushes warten. Nicht: für jeden Zwischen-Commit ein eigenes
  Compile-Urteil erwarten — das gibt es strukturell nicht.
