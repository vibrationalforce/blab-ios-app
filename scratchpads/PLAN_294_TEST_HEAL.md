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
| 982600d | BioComposerTests seed-arg-order (9) · BioEngineTests:255 closure `_ in` | mechanical API-order |
| 9540b4f | sACN packet statics (SACNSenderTests) | `nonisolated static` |
| 001aeaa | BioIntegrationTests DDSP/removed-type drift | type-swap + delete-removed |
| fbcfe93 | LaneNotePump tuple-array asserts | element-wise helper |
| fc50df5 | SignalRouter statics + 3 test drifts (throws/Float/extent) | `nonisolated static` + test |
| 65530a7 | VDSPTests nested-enum qualify (10) · VideoInTracksTests:73 `Double?` | qualify + XCTUnwrap |
| 60e8ec4 | MicrotonalTuningTests:124 `Array.first` Double? | throws + XCTUnwrap |
| 361775a | @MainActor sender tests (ADMOSC/ArtNet init() from nonisolated) | class-level `@MainActor` |
| 3542105 | Timeline suite: migrate() @MainActor · misplaced gain tests (lane/clip/region scope) · 3× Double? accuracy | @MainActor method · add helpers to class 2 · XCTUnwrap |
| 9825e44 | EchoelRenderLayout azimuth Double? · FaceExpression bag [String:Double]→[String:Float] | XCTUnwrap · type annotation |
| 65dd32b | AudioEngineTests: 7 dead-API classes (Metronome*/CountInMode/TunerReading/MusicalNote-ext/TuningReference-ext removed/redesigned) | delete obsolete classes |
| 57329c0 | AUv3HostTests split/categorize (@MainActor class) · AUParameterMapping registry method · AudioRegionPlayback filePos Double? | class/method @MainActor · XCTUnwrap |
| a5b18de | CoreSystemTests: AudioConstantsTests (→AudioConfiguration) + MusicalNoteTests (redesigned) dead | delete classes |
| 840ba8f | DSPTests: AnalogEmulationProcessTests + DSPCrossfadeCurve/RegionTests + 4 Crossfade methods dead · render(into:)→render(buffer:) · hrv:→hrvVariability: | delete classes + drift |
| 5ebbff5 | DSPValidationTests: testBreathPhaseExcitation (private continuousExcitationLevel) · CARule.contains([UInt8] vs struct) · EchoelRealFFT.forward() now returns (magnitudes,phases) tuple · powerSpectrum(_:) is a method · AnalogEmulationValidationTests dead | delete/adapt |
| **b9d6f0c** | Next layer: EchoelDDSPTests 9× NoiseColor/SpectralShape codableRoundTrip (enums NOT Codable, only String/CaseIterable/Sendable) → delete; DSPValidationTests ConvolutionKernel: lowpassKernel/highpassKernel now STATIC (cutoffHz:sampleRate:taps:), init is (kernel:_) → repair to static API; XCTAssertEqual(cell.rule, rule1) needs CARule:Equatable → compare .number | delete codable + repair static + .number |

> LESSON reinforced: the reveal peels ONE diagnostic layer per run (serialized-
> diagnostics quirk). a5b18de reveal named only DSPTests+DSPValidationTests; healing
> those surfaced a NEW file (EchoelDDSPTests) + residual DSPValidationTests lines in
> the 5ebbff5 reveal. Proactively grep ALL Tests for each fixed drift pattern
> (EchoelConvolution(tapCount:), NoiseColor/SpectralShape codable, XCTAssertEqual …rule)
> to heal siblings in one cycle — here all three were confined to the two files.

> Both DSPTests + DSPValidationTests (the removed analog-emulation + crossfade
> cluster) healed 2026-07-21. These were the LAST two files in the a5b18de reveal's
> ERROR_FILES list. Next reveal (head 5ebbff5) should show build-for-testing SUCCESS
> or the next residual cluster.

## HISTORICAL — DSPTests + DSPValidationTests (removed analog-emulation subsystem) [DONE 840ba8f/5ebbff5]
CONFIRMED GONE from Sources: SSLBusCompressor/LA2ACompressor/AnalogConsole/CrossfadeRegion/
CrossfadeCurve/UREI1176Limiter/PultecEQP1A/ManleyVariMu/FairchildLimiter/APIBusCompressor.
- DSPTests.swift: DELETE `AnalogEmulationProcessTests` (380-489), `DSPCrossfadeCurveTests`
  (142-209), `DSPCrossfadeRegionTests` (490-506). Then FIX drift in KEPT classes:
  EchoelDDSP.SpectralShape exists but NOT Codable (encode/decode tests → remove/adapt),
  EchoelRealFFT.magnitudes (3×), `sampleRate` extra-arg (4×), CARule Equatable/Collection,
  continuousExcitationLevel private (2×), type-check-timeout (2× → split expression).
- DSPValidationTests.swift: DELETE `AnalogEmulationValidationTests` (612+); check others for
  the same drift.

> CORRECTION (65dd32b): reveal #14's AudioEngineTests:111-135 lines were NOT noise —
> they were REAL dead-API errors (CountInMode/MetronomeConfiguration are REMOVED types).
> The reveal's dedup BUILD_ERRORS ('init()'+'descriptor(for:)', count 1 each) did NOT
> map cleanly to the ~50 ERROR_FILES sites — a serialized-diagnostics/log quirk. LESSON:
> when BUILD_ERRORS messages don't match the ERROR_FILES list, TRUST ERROR_FILES +
> grep Sources for each referenced type; removed type → delete the test class.

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
   **Exact ci.yml sites (read 2026-07-21):**
   - L86-88 matrix `destination:` (iPhone 16 Pro / iPhone SE 3rd) → the iOS test job's
     build-for-testing (L150-156) + test-without-building (L161-168).
   - L432-449 SECOND job: `-scheme Echoelmusic -destination …iPhone 16 Pro`
     `-only-testing:EchoelmusicTests/ComprehensiveTestSuite/…` → repoint to FullTests + iPhone 17.
   - L156/168/438/449 carry the `… | tee …log | xcpretty || cat log` / `|| true` mask → drop.
   - macOS/watch/tv/vision jobs (L255-389) are separate schemes — leave untouched this slice.
3. Then the safety-net is REAL: a red test finally reddens a gate.
