# Echoelmusic — Foundation Build Index

**Purpose:** Sequenced execution plan for the full Echoelmusic vision, step-by-step, crash-safe, Ralph-Wiggum-loop.
**Last updated:** 2026-05-13
**Owner:** Echoel (Michael Terbuyken) + sandbox-Claude.

The destination is not "Beat-only TestFlight on May 17." The destination is **the original comprehensive Echoelmusic vision (DAW + Video + Stream) deployed end-to-end with all engines green on TestFlight**, without a date pressure that would force shipping broken code. Date drives quality, not the inverse.

---

## Execution sequence (one engine at a time, all device-verified)

| # | Phase | Plan file | Cycles | Status |
|---|-------|-----------|--------|--------|
| 0 | Crash bisect closure | (inline in this session) | done | ⏳ Awaiting device verify of `5e18a13` |
| 1 | BeatTab UI restore | (inline, this session) | 3 done | ⏳ Awaiting device verify |
| 2 | Beat-MVP polish | (inline in plan) | TBD on device | 🔒 Locked until device-green |
| 3 | W2_RECORDER | `PLAN_W2_RECORDER.md` | 6 cycles | 🔒 Locked until Beat-MVP green |
| 4 | W2_VIDEO | `PLAN_W2_VIDEO.md` | 7 cycles | 🔒 Locked until W2_RECORDER green |
| 5 | W3_STREAM | `PLAN_W3_STREAM.md` | 6 cycles | 🔒 Locked until W2_VIDEO green |
| 6 | v10.0 App Store submission | (future plan) | TBD | 🔒 Locked |
| 7 | AUv3 standalone plugin | (future plan) | ~6 cycles | 🔒 Parallel after v10.0 ships |

**Total cycles to v10.0 full-vision TestFlight:** ~22 atomic commits, each device-verified before the next starts.
**Realistic calendar estimate at 1-2 device cycles/day:** 4-6 weeks from Beat-MVP-green to v10.0 full-feature TestFlight.

---

## Why this sequence is safe

1. **One pillar at a time.** Each W-phase touches only its own files plus a single integration point. Bisect by phase.
2. **Dormant before live.** New `.swift` files land first as skeletons (compile but unreferenced), then get wired in a second commit. If the wire-up breaks something, revert the wire-up cycle, not the skeleton.
3. **Single dependency, late.** HaishinKit added only at W3-S1, after audio + video pipelines are proven. No "ship a HaishinKit-dependent app" risk if RTMP is bogus.
4. **Each phase has a fall-back.** If a phase reveals an unfixable issue, the prior phase's TestFlight is still shippable (just without that engine).

---

## Ralph Wiggum Lambda — operational rules

1. ONE behavioral change per commit. Conventional prefix (feat:/fix:/refactor:/test:/docs:/chore:/perf:).
2. Push → user triggers `testflight.yml` (build_only=true) → user reports green/red.
3. Green → next cycle. Red → bisect, fix root cause, re-push.
4. Per 4 green build_only cycles: one `build_only=false` TestFlight upload → device install → smoke test.
5. Per phase boundary: short status update to user (1-2 sentences). No long monologues mid-loop.
6. Never stack unverified commits on unverified base. (Exception: dormant-skeleton + wire-up may be the same session if the skeleton is mechanically trivial.)

---

## Known tech debt (out of TestFlight path, address after v10.0)

1. **CLAUDE.md fabricated bio-DSP citations.** Files `BioEventGraph.swift`, `HilbertSensorMapper.swift`, `BioSignalDeconvolver.swift` do not exist in `Sources/`. References in CLAUDE.md and `decisions.md` ARCHITECTURE table should be removed or marked as "v1.x roadmap."

2. **Broken test references.** `Tests/EchoelmusicTests/BioIntegrationTests.swift:579-601` calls `HilbertSensorMapper.map(...)` which has no source definition. Masked by `testflight.yml.skip_tests=true`. Fix: implement the mapper as a small recursive function (textbook Hilbert curve, ~30 LOC) OR delete the dead tests. Probably the latter, since the algorithm isn't actually used in product code.

3. **AUv3 Info.plist type bug.** `Resources/EchoelmusicAUv3/Info.plist:39` declares `aufx` (effect) but the kernel implements `augn` (generator). 5-min fix, but blocked by separate App Store Connect bundle ID registration.

4. **Deprecated code lingers compilable.** 715+ LOC of v8/v9 code (`SoundscapeEngine`, `ClipEngine`, `MomentCaptureView`, `BioSourceManager` chains, `OuraRingClient`, etc.) sits compilable but unwired. Removal can wait; documenting here for visibility.

5. **OnboardingView `shouldAutoPlay` binding** kept for parity but never set after the v10 onboarding rewrite. Can be removed in a later cleanup commit.

---

## Conventions across all plan files

- File paths absolute from `/home/user/Echoelmusic`
- Commits use German for personal notes, English for code/docs (per repo convention)
- All new Swift types: `@MainActor` unless the type explicitly serves the audio thread (then `@unchecked Sendable` + raw pointer storage, see `SamplerVoice` as reference)
- All new tests follow the `RetroCaptureTests` pattern (@MainActor isolation, behavioral assertions, not enum-checking)
- No external dependencies except HaishinKit; revisit only if Apple deprecates AVAudioEngine or AVAssetWriter

---

## When in doubt

Re-read CLAUDE.md sections "AUDIO THREAD — ABSOLUTE RULES", "CRITICAL BUILD ERROR PATTERNS", "DO NOT".

Or read this index again and resume the next unblocked phase.
