# Optimization Backlog — 2026-06-01 (file-grounded audit)

Source: toolchain + AI-agent audit (general-purpose subagent), verified against repo.
Risk tiers: 🟢 safe/CI-verifiable · 🟡 touches the green ship pipeline (needs deliberate run) · 🗑️ cleanup.

## DONE this session
- ✅ 11 `.claude/agents/*.md` given `name`+`description` frontmatter → now loadable subagents (were inert markdown).
- ✅ `EchoelmusicAUv3` scheme added → AUv3 now CI-compile-verifiable by name (compile_check green on its addition).
- ✅ Export method `app-store` → `app-store-connect` (5 platform blocks) — latent Xcode-26 blocker for ALL uploads.
- ✅ Shipped TestFlight build 1454 (app + widget, CX live-data wired), ASC state=VALID.

## 🟢 Safe, CI-verifiable (next)
1. **SessionStart hook** in `.claude/settings.json` — `cat memory/*.md scratchpads/SESSION_LOG.md` so the "mandatory SESSION START context load" is enforced, not honor-system. (Affects future sessions; use `session-start-hook` skill for correct format.)
2. **`permissions.allow`** in `.claude/settings.json` — allow read-only/常用: `git status|log|diff`, `swift build|test`, `xcodebuild -list`, `grep|ls|cat`, the testflight dispatch curl. The existing bespoke `safety` block is NOT read by the CLI for prompting. Use `fewer-permission-prompts` skill.
3. **`project.yml` `settingGroups`** — hoist the truly-common settings. CAUTION: AUv3 currently lacks explicit `SDKROOT`/`SUPPORTED_PLATFORMS`; applying a full iOS group to it is a behavior change — only do so AFTER adding AUv3 to the compile_check build list so it's verified. Safe subset first: `signing-automatic` (CODE_SIGN_STYLE+DEVELOPMENT_TEAM, all 4 identical) and `explicit-infoplist` (GENERATE_INFOPLIST_FILE: NO, all 4).
4. **Add AUv3 to compile_check build list** (now that it has a scheme) — closes the "AUv3 only probe-verified" gap.

## 🟡 Touches the green ship pipeline (deliberate, expect red rounds)
5. **Collapse 5 platform jobs → `matrix`/composite action.** ~900 of 1,470 lines of `testflight.yml` are copy-paste; iOS vs others diverge only in archive path, `<destination>` and upload mechanism. Repo already has `.github/actions/setup-xcodegen` + `setup-asc-api-key` — extend the pattern. Highest CI leverage; rewrite of a just-green pipeline.
6. **Finish fastlane→xcodebuild migration + fix cert race.** iOS already uploads via `xcodebuild destination=upload`; macOS/Watch/TV/Vision still call `fastlane … upload` (two mechanisms). `Fastfile:setup_signing` **revokes ALL dev certs every run** while platform jobs run in parallel (`needs:[preflight]`, no serialization, `cancel-in-progress:false`) → real intermittent failure mode. Serialize signing OR move all uploads to the iOS inline path and retire the fastlane upload lanes.
7. **Cache the fastlane gem** (vs 5× `gem install fastlane:2.225.0`) → ~5–10 min/full run.

## 🟡 Feature-depth (per SPEC_ECOSYSTEM_TARGETS.md)
8. **C6b — watchOS companion embed (proper):** needs `WKCompanionAppBundleIdentifier` + Embed-Watch-Content phase (a bare `- target` dep produced a malformed archive: export "expected one {}"). Web-confirmed embedded-watch archives break export without the companion relationship.
9. visionOS / tvOS / Mac-Catalyst surfaces; RTMP (HaishinKit), EchoelLux.

## 🗑️ Cleanup
- `.github/workflows/decision-review.yml` is referenced by `.claude/routines/05-decision-review.md` but does NOT exist — create it or fix the reference.
- Stale workflows vs iPhone-only v10 scope: `android-build.yml`, `release-all-platforms.yml`, `desktop_build.yml`, `phase8000-ci.yml` — candidates for deletion (confirm first).
- `.claude/settings.json` `engines`/`platforms`/`wellness` block (:125-137) uses legacy "wellness"/"Photonics" naming that violates CLAUDE.md brand rules and is inert (CLI ignores these keys) — update or remove.

## Notes / corrections
- Audit "committed live PAT" = FALSE ALARM: `.claude/settings.local.json` is gitignored AND never tracked by git. (Rotate post-session anyway — pasted in chat.)
- 5 routines in `.claude/routines/` are manual "paste into claude.ai" prompts — none wired to a workflow/hook. Wiring them (or at least routine-01 PR-review + routine-04 CI-watchdog) to Actions would automate the documented multi-agent ops.

---

## 🔴 CRITICAL FINDING (2026-06-03): the test suite is NOT run by any green CI
- **`quick-test.yml`** (Linux `swift build`/`swift test`) — **fails at "Build (Linux)"** on every run (539–543): the iOS-framework-heavy package cannot build on Linux. `swift test` never executes.
- **`ci.yml`** (macOS `xcodebuild test -scheme Echoelmusic`) — **green, but runs ZERO tests**: `project.yml` defines **no unit-test target**, so the scheme's `test:` action has no testables. The 1000+ tests in `Tests/EchoelmusicTests/` are orphaned — compiled/run by nothing.
- **Impact:** "build stability" cannot actually be verified by CI today. Compile_check (app schemes) is the only working gate; correctness is unverified.
- **Fix (needs a macOS/Xcode session — host wiring is fiddly to do blind):**
  1. Add an `EchoelmusicCoreTests` `bundle.unit-test` target to `project.yml` with `TEST_HOST` = the app (or refactor the testable core into the SPM library so logic tests need no host), sources a **curated, currently-compiling** subset (legacy tests likely drifted vs deprecated code).
  2. Add it to the `Echoelmusic` scheme `test.targets` so `ci.yml` actually runs it.
  3. Start with `Tests/EchoelmusicCoreTests/MIDIFileExporterTests.swift` (added, isolated, current) — prove one test runs green, then migrate good legacy tests.
- **Added this session (compile-verified, byte-logic hand-verified, NOT yet test-run):**
  `Sources/Echoelmusic/Sequencer/MIDIFileExporter.swift` (SMF Type-0 export — EchoelSeq "beat → any DAW" roadmap) + its ready test. Wire the target to actually run it.
