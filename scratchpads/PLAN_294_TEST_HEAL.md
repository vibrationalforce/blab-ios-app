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

## ✅ 294 SOURCES COMPILE (b9d6f0c reveal, 2026-07-21) — remaining = harness build/packaging

The b9d6f0c full-tests reveal has an EMPTY ERROR_FILES list (zero `.swift:N: error:`
in test sources) — the whole 20-cycle compile-heal is DONE. build-for-testing is still
`failure`, but for TWO reasons that are NOT test-source drift, both isolated to the
non-blocking reveal harness (main gates + shipping app untouched):

| Blocker | Root | Fix (commit 6306133) |
|---------|------|----------------------|
| Test-bundle LINK fails: undefined `Echoelmusic.<Type>` property/nominal-type descriptors + key paths (Scale, NoteHit, ClipKind, LogLevel, …) | hosted-xctest Swift symbol resolution — ld doesn't resolve these from the host binary at link even with TEST_HOST/BUNDLE_LOADER (smoke target links only because it references fewer/simpler symbols) | `OTHER_LDFLAGS: -Xlinker -undefined -Xlinker dynamic_lookup` on the REVEAL-ONLY `EchoelmusicFullTests` target — host provides the public symbols at runtime injection |
| App INSTALL fails: `EchoelmusicAUv3.appex` placeholder rejected, "bundleVersion must be set" | `CURRENT_PROJECT_VERSION = ${BUILD_NUMBER:=1}` but XcodeGen ignores the `:=` default → empty CFBundleVersion; ci.yml only stays green because its smoke install is mask-forced green | `BUILD_NUMBER: '1'` in `full-tests.yml` env (real TestFlight sets its own) |

> Both are verified via the next reveal (6306133). If green → do the section below.
> NOTE the appex-version finding CONFIRMS the ci.yml mask problem: the masked smoke
> install likely fails the same way today — dropping the masks (below) will expose it,
> so the BUILD_NUMBER fix must also land in ci.yml when the gate flips.

## ✅✅ 294 BUILD + INSTALL + RUN in CI (6306133 reveal, 2026-07-21) — real-test-heal phase

The 6306133 reveal (run 29808005493): **`build-for-testing: success`** (linker gone —
`dynamic_lookup` worked), the app **installed** and the suite **RAN** (appex bundleVersion
gone — `BUILD_NUMBER=1` worked; the run step took ~20 min = real execution, tests visibly
pass/fail). BUILD_ERRORS + ERROR_FILES both EMPTY. Main gates stayed GREEN on 6306133.

`test-without-building: failure` is now **real red tests** (~30 shown, grep head-limited).
The compile+harness phase is DONE; this is behavior triage: each red test is TEST-DRIFT
(stale expectation → Tests-only fix), REAL-BUG (Sources defect → fix + reviewer), or
SIM-ENV (bundled-resource/audio-engine/timeout under the app-hosted runner). A background
triage agent is categorizing all ~30 against Sources; heal the clearest Tests-only cluster
per cycle, flag real bugs for careful Sources fixes. Reveal cadence is now ~24 min (tests
actually run) — batch a few clusters per reveal rather than the old 6-9 min loop.

Known first red set: FXChainFilterStage · CommunityLibrary(2)+MoodPreset (bundled-resource,
likely SIM-ENV) · SessionNaming · BioEndToEnd · EchoelDDSPReverb(2) · SpectralMorphing(2) ·
Cellular.reset · PolySynthVoice(5) · TimelineRegionSplitMerge.abuts · SamplerVoice(74s,
timeout?) · DDSPInit frameSize-clamp(2) · SpectralColorCIE · LoopCutter.barLengths ·
CrossSynthBioCoherence · ModulationEngine(2) · ChannelInsertFX.drive · LogCategory.totalCount ·
SynthPatchApply · TimelineStoreAutomationEdit(2).

### Real-test-heal progress (triaged: 18 TEST-DRIFT · 5 REAL-BUG · 6 SIM-ENV)
**Cycle 1 (1467587 + b9c0518) — healed 12:**
- REAL-BUG #19/#20: EchoelDDSP init negative-size crash (self.frameSize + sibling
  harmonicCount/noiseBandCount hardening) — dsp-reviewer CONFIRMED. This was a hard
  trap aborting a runner clone → likely un-blocks collateral failures too.
- TEST-DRIFT ×10: LogCategory 30 · LoopBarLength [1,2,4,8,16,32] · ChannelInsertFX
  <=1.0 · abuts 0.5 (480 PPQ) · FXChain chorus-off · SessionNaming Drums4bar ·
  Reverb 0.25/2.0 · Cellular.reset singleCenter · Morph via setMorphPosition (×2).

**Cycle 2 (2073b39 + f639f52 + b05a127 + 980d95e) — healed 4 clusters (11 tests):**
- REAL-BUG: EchoelDDSP init negative-SAMPLERATE crash — generateReverbIR used the raw
  `sampleRate` param → `Int(0.02*negative)` range trap. Surfaced AFTER cycle-1's #19 fix
  un-blocked its test-runner clone (reveal-quirk in action). Fixed to `self.sampleRate`
  (clamped `max(1,…)`). dsp-reviewer PASS: byte-identical valid path, NO remaining raw-param
  trap in init.
- TEST-DRIFT: DSPTests EchoelDDSP default/reverb params (frequency 110, harmonicity 0.88,
  noiseLevel 0.01, amplitude 0.5; reverbMix 0.25) against verified Sources defaults.
- TEST-DRIFT: PolySynthVoice allocation (7 tests) — noteOn/off/allOff only ENQUEUE to the
  SPSC queue now; poly mutates on the audio thread inside renderOnAudioThread. Extracted the
  render's note-drain into a byte-identical `drainNoteCommands()` shared by render + a
  `#if DEBUG pumpNoteCommandsForTesting()`; tests pump before asserting. audio-thread-reviewer
  PASS (render byte-identical, no audio-thread violation, DEBUG pump can't reach production).
- TEST-DRIFT: breath→noise → breath→filter-movement (2 tests, BioIntegration + DSPValidation).
  A8 audit moved breath depth off noiseLevel onto `lfoToFilterDepth = 0.05 + breathDepth*0.3`;
  noise now tracks coherence. Both tests pinned coherence 0.5 → noise delta always 0. Assert
  the real relationship (deeper breath → more filter movement).

**Cycle 3 (35fb16e) — BioDDSPMapping cluster + PolySynth unison (test-only):**
- HEALED (mapping intact, direction/range asserts replace dead exact formulas):
  coherence→harmonicity ×4 · heartRate→vibrato ×1 · PolySynthVoice applyPatch (RICHNESS
  unison default = 2 voices/note → assert >=1, no-crash intent).
- ⚠️ **#77 CANARY — 3 bio-mappings VANISHED from the shipped `applyBioReactive` path**
  (XCTSkip'd with loud markers, NOT rewritten-green, so the loss stays visible):
  1. **HRV→brightness** — gone; brightness now coherence/HR/LFO-driven, HRV → reverbMix only.
  2. **breath-phase→amplitude swell** — only in opt-in `.harmonicSeries`, absent in default `.natural`.
  3. **coherenceTrend→spectral-morph** — `coherenceTrend` param accepted but NEVER read.
  The function `applyBioReactive` (EchoelDDSP L1263-1348) is a palimpsest: its own header
  says "DESIGNED TO BE AUDIBLE… previous ranges too subtle" while the A8 block below says
  "modulate SUBTLY". These 3 lost mappings are a plausible ROOT CAUSE of **#77 (genres sound
  the same / unprofessional)** — the body stopped driving brightness, amplitude-swell and
  morph. **When #78 gate is green and REIHENFOLGE reaches #77: decide restore (Sources fix +
  un-skip the 7 tests, likely the #77 answer) vs retire (delete tests).** Not asked as a
  blocking question — #77 already tracks it; this is the head-start.

**Remaining for next cycles:**
- TEST-DRIFT: #6 BioEndToEnd + #23 CrossSynth (verify vs newest reveal; may share the
  vanished-mapping root — check before rewriting).
- SIM-ENV/founder-gated/protected (unchanged): Community/Mood bundled JSON · AppGroupStore
  pollution · SamplerVoice 74s · ModulationEngine guard value>0 (#24/#25) · BioSignalDeconvolver
  (protected triad, dsp-reviewer) · EchoelMeter · BioComposer ×2 · EchoelFXChain ×3 ·
  BioMusicDirector gate-off · SpectralColorCIE Kammerton (#21) · SynthPatchApply · TimelineStore ×2.
- SIM-ENV: #2/#3/#4 Community/Mood bundled JSON (`.process("Resources")` flattens subdirs →
  `urls(…subdirectory:"Community/fx")` nil; needs `.copy` of Resources/Community/** or a
  flattened-root loader — build-config, care) · #29/#30 TimelineStore AppGroupStore temp-dir
  fallback pollutes across tests (isolate/clear in setUp) · #18 SamplerVoice AVAudioSourceNode
  outputFormat on headless sim (74 s; skip-on-CI or relax).
- REAL-BUG (Sources + reviewer): #21 SpectralColorCIE — Kammerton grid tint is INERT near A4
  (toneLinearRGB saturates deep-red plateau ~620-631 nm; 8 Hz shift → Δ0.0 colour). Real gap
  vs a founder ask. #24/#25 ModulationEngine `guard value > 0` skips driving a destination to
  0 (stuck-parameter) — has an intentional-looking comment → reviewer/founder call before fix.

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
