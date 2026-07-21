# PLAN — heal the 294-suite compile drift (Task #78)

The 294 test files never compiled in any CI (project.yml had no test target). After
wiring `@testable import` (6051e08: ENABLE_TESTABILITY + explicit-modules-off), the
non-blocking `full-tests.yml` reveal peels one compile-error cluster per run. Each
cluster is healed test-first; the reveal shows the falling count. NOT touching ci.yml
until build-for-testing goes green.

## Cluster log (newest first)

| Commit | Cluster | Fix kind |
|--------|---------|----------|
| 6051e08 | `Unable to find module dependency 'Echoelmusic'` (all 294) | project.yml wiring |
| 097472e | stale `TuningReferenceTests` dup · dead `UndoRedoManager` tests · RollHitTest @MainActor | delete stale / isolate |
| 7c55759 | 13× rPPG trust statics (CameraRPPGTrustTests) | `nonisolated static` |
| f6bce70 | 17× OSC encode/address + RMSSD statics | `nonisolated static` |
| **(this)** | BioComposerTests seed-arg-order (9) · BioEngineTests:255 closure `_ in` | mechanical API-order |

## REMAINING — BioIntegrationTests.swift (NEXT cycle, needs care)

This one file carries a whole REMOVED subsystem — investigate + delete/repair per method:

- **Removed types (gone from Sources → DELETE the test methods):**
  - `testVisualPalette_coherenceInterpolation` (~548), `testVisualPalette_midCoherence_interpolated` (~561) — `VisualPalette` gone
  - `testBioVisualState_defaults` (~571) — `BioVisualState` gone
  - `testVisualMode_allCasesAvailable` (~606) — `VisualMode` + `.particles/.hilbertMap/.bioGraph/.flowField` gone
  - `testNormalizedCoherence_BoundaryValues` (~732) — `NormalizedCoherence` gone
  (The visual-mode system was superseded by MetalBioView / BioVisualParams; these test dead code.)
- **`EchoelBioEngine()` (~704, 712, 722):** init is now `private` (singleton). Repoint to
  `EchoelBioEngine.shared`, or delete the method if it only exercised removed API.
- **`renderStereo` (~331–445, "EchoelDDSP has no member"):** the method EXISTS
  (EchoelDDSP.swift:1948) — the "no member" is likely a cascade from an error-typed
  instance (e.g. a private-init construction nearby). Confirm the `poly`/`synth`
  construction; fix the constructor, not renderStereo.
- Then any residual `extra arguments` / `takes no arguments` in that file = signature
  drift → match the current Sources signature.

## After the 294 COMPILE (build-for-testing: success)

1. Read `test-without-building` real pass/fail count (until now it cascaded to
   "Missing bundle ID" from the failed build). Heal red tests test-first.
2. When 0 red: **the blocking gate slice (code-reviewer!):** ci.yml — replace the stale
   destination `platform=iOS Simulator,OS=18.2,name=iPhone 16 Pro` (does NOT exist on
   macos-26/Xcode 26.2) with `generic/platform=iOS Simulator` (build) + `name=iPhone 17`
   (test); DROP the `… | tee x.log | xcpretty || cat x.log` mask (trailing `|| cat`
   forces step success → false green); flip the main `Echoelmusic` scheme test target
   from `EchoelmusicTests` (smoke) to `EchoelmusicFullTests`; retire the smoke target.
   Also repoint ci.yml:433-451 `-only-testing:…/ComprehensiveTestSuite`.
3. Then the safety-net is REAL: a red test finally reddens a gate.
