# Echoelmusic — Foundation Audit (Phase 1, no code-write)

**Date:** 2026-05-18
**Branch:** `claude/audit-echoelmusic-foundation-Q9OYQ`
**Reference vision:** New master prompt — biofeedback-first multimedia suite
  (EngineBus + EchoelTools / EchoelSync / EchoelWorks / EchoelWell).
**Reference state:** `CLAUDE.md` (v10 Beat-MVP) + Sources/ as of `86fbd8e`.

> Phase 1 is inventory and gap analysis only. No source files are touched.
> Output goes to scratchpads. Next step is Plan-Mode review with the owner.

---

## 1 · What exists today (high-level)

| Layer | Module | LOC | Status |
|------|--------|-----|--------|
| App entry | `EchoelmusicApp.swift` | 83 | Wires `AudioEngine` + `StudioRoot` + `BeatPlayer`; no `EngineBus`. |
| Tabs | `Studio/StudioRoot.swift`, `Studio/BeatTab.swift` | ~? | 4-tab `TabView`, only BeatTab is functional, others are placeholders. |
| Beat | `Sequencer/PatternEngine.swift`, `SamplerVoice.swift`, `BeatPlayer.swift` | — | Working 8×16 sampler, attached lazily before `audioEngine.start()`. |
| Audio | `Audio/AudioEngine.swift`, `AudioConfiguration.swift`, `MicrophoneManager.swift`, `MIDIInput.swift`, `RetroCapture.swift`, `AutoMixChain.swift`, `SingleExport.swift`, `MultiTrackRecorder.swift` | — | `MIDIInput` is a minimal CoreMIDI receiver (no MPE-zone parsing). `MultiTrackRecorder` is the dormant W2-C1 skeleton. |
| Bio | `Bio/EchoelBioEngine.swift` (516), `BioSourceManager.swift` (235), `MotionActivityProvider.swift` (164), `OuraRingClient.swift` (690) | 1,605 | HealthKit HR/HRV/breath pipeline lives in `EchoelBioEngine`. Oura + Motion + multi-source manager exist but are unwired in main flow. |
| DSP | `DSP/EchoelDDSP.swift` (1,237), `EchoelCellular.swift` (520), `EchoelModalBank.swift` (806), `EchoelVDSPKit.swift` (719), `EchoelSVFilter.swift`, `EchoelLFO.swift`, `EchoelEntrainment.swift` | 3,574 | Strong, audio-thread-safe building blocks. None of them are wired through a central bus today. |
| Video | `Video/CameraCapture.swift`, `CameraAnalyzer.swift`, `ShortContentRenderer.swift` | — | Capture + analyzer exist as foundations; no `Video/CameraSession`/`VideoRecorder`/`ClipTrimmer` per v10 spec yet. |
| Views (legacy) | `Views/*.swift` (Moment/Master/Soundscape/Onboarding/Settings/SessionGrid/SessionHistory/SoundDesign/CameraMeasurement) | — | Deprecated v8/v9 flows, compilable but not on main route. |
| AUv3 | `Sources/EchoelmusicAUv3/*` | — | Type recently corrected to `augn` (generator) at `f4bd091`. Standalone product, not in v10 main flow. |
| Tests | `Tests/EchoelmusicTests/*.swift` × 14 | — | Cover audio engine, sampler, sequencer, retro capture, single export, vDSP, DDSP, core, bio engine, bio integration. |

**Build & SDK reality**

- `Package.swift`: `swift-tools-version: 5.10`, iOS 17, macOS 14, watchOS 10, tvOS 17, visionOS 1.
- `Project.swift`: `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `MACOSX_DEPLOYMENT_TARGET = 14.0`.
- New vision CLAUDE.md says deployment target ≥ iOS 18.0 + Xcode 26 / iOS 26 SDK. **Delta: iOS 17 → iOS 18 bump pending.**
- Project still depends on neither HaishinKit nor JUCE — `grep -r "JUCE\|juce::" Sources` → no matches. Clean.

**Entitlements & privacy**

- `Echoelmusic.entitlements`: HealthKit, iCloud (`iCloud.com.echoelmusic.app`), App Group `group.com.echoelmusic.shared`, keychain access.
- New vision says App Group `group.com.echoelmusic` — current is `.shared`. Either is fine, just needs a deliberate choice and consistent use across targets.
- `Resources/PrivacyInfo.xcprivacy` present, declares HealthData + AudioData collection, no tracking. Required-Reason API list still needs a once-over against the bumped iOS 18 requirement.
- `Info.plist` usage descriptions present for: Microphone, Health Share/Update, LocalNetwork, Motion, Bluetooth (Always + Peripheral), Camera, FaceID, HomeKit, Location, EyeTracking, Photo Library. **Strings need a science-only audit pass — at least one referenced legacy soundscape framing per past commit history.**

**CI / workflows**

- `.github/workflows/` carries 17 files including `testflight.yml` (primary), `ci.yml`, `build.yml`, `quick-test.yml`, `pr-check.yml`, `screenshots.yml`, plus android/desktop/release-all-platforms remnants.
- `android-build.yml` and `release-all-platforms.yml` are noise for an iPhone-first v10 — candidate for removal in a later cleanup cycle (not this one).
- `phase8000-ci.yml` is legacy and should be reviewed for archival.

---

## 2 · Vision-Reflect gap (what the new master prompt requires that we do not have)

| New vision component | Present? | Notes |
|----------------------|----------|-------|
| **`EngineBus`** central message bus | ❌ Missing | No file, no protocol. App wiring is via direct `@Environment` injection. |
| **`EchoelTools` module** (Bio→Sound/Visual/Pattern generators) | ❌ Missing as a named module | DSP building blocks exist (`EchoelDDSP`, `EchoelCellular`, `EchoelModalBank`); they need a `Tools/` shell that exposes them as bio-driven instruments. |
| **`EchoelSync` module** (OSC + MIDI/MPE bridge) | ⚠️ Partial | `MIDIInput.swift` exists but is generic. No OSC output. No MPE-zone detection. No Air-CC (21-31) receiver. |
| **`EchoelWorks` module** (sessions/recording/DAW handoff) | ⚠️ Partial | `MultiTrackRecorder`, `SingleExport`, `RetroCapture`, `AutoMixChain` exist, but no session model that crosses bus events to disk. |
| **`EchoelWell` module** (evidence-based breath/coherence) | ❌ Missing | Bio data exists, no UI module surfaces it as guided practice. |
| **OSC over UDP** (`/echoelmusic/bio/*`, `/echoelmusic/audio/*`) | ❌ Missing | No socket layer. `EchoelSync` namespace empty. |
| **MPE input layer** (Seaboard 2 via CoreMIDI, per-note channels, CC74 slide, channel pressure, pitch bend range config, zone auto-detect) | ❌ Missing | `MIDIInput` accepts MIDI 1.0/2.0 but does not split by MPE master/member channels. |
| **Air-CC receiver** (CC 21-31 via Network MIDI / BT MIDI) | ❌ Missing | No Network MIDI session listener. |
| **Modulation Matrix** (Bio × MPE × Air → app params, persistable) | ❌ Missing | No matrix engine, no persistence schema. |
| **Privacy / consent screen for cloud AI** (5.1.2(i)) | ⚠️ N/A today | No cloud AI in flight, but new vision allows optional opt-in — when wiring, must add explicit named consent. |

---

## 3 · Protected DSP components — critical inconsistency

Both the in-repo `CLAUDE.md` (v10) and the new master prompt declare three components as **protected, read-only, do-not-modify**:

- `BioEventGraph` — Event detection / k-means clustering (DELLY, Rausch 2012)
- `HilbertSensorMapper` — Hilbert curve 1D→2D phase mapping
- `BioSignalDeconvolver` — Adaptive biquad IIR signal separation (Tracy, Rausch 2017)

**Finding:** None of these exist as source files in `Sources/Echoelmusic/Bio/` or anywhere else under `Sources/`. The names appear in:

- `Tests/EchoelmusicTests/BioIntegrationTests.swift:579-601` — calls `HilbertSensorMapper.map(...)` and `mapToGrid(...)`. No type with that name is defined anywhere in the build target. These tests would not compile unless gated/skipped — confirmed: `testflight.yml.skip_tests=true` masks this.
- `Sources/Echoelmusic/Bio/EchoelBioEngine.swift:400` — a comment "Full implementation would use BioSignalDeconvolver (Rausch 2017)".

`scratchpads/PLAN_FOUNDATION_INDEX.md` already flags this under "Known tech debt" #1 and #2: the components are *fabricated citations*; the tests are dead.

**Decision required from owner:**

1. **Implement** the three components as real, documented modules and treat them as the canonical protected layer (matches the master prompt's intent), **or**
2. **Remove** the references from CLAUDE.md / decisions / dead tests so the project stops claiming an IP-protected layer that doesn't ship.

Both paths are legitimate. Option 1 is closer to the master prompt's vision. Option 2 is the honest minimum to get tests green and stop fabricated documentation.

> Per the master prompt, modifying the protected components requires explicit "APPROVED: modify [Component]". Implementing them from scratch is *creation*, not modification — but the owner should still confirm scope before any source file lands.

---

## 4 · Two visions in tension

The repo's own `CLAUDE.md` (`/home/user/Echoelmusic/CLAUDE.md`) describes a **Beat Maker + Recorder + Video + RTMP Stream** product. The active branch + the most recent commits (`docs(claude-md): sync Current State to v10 Beat-MVP polish phase`, `feat(studio): placeholder copy 'Coming in v1.1' for Record/Video/Share tabs`) are all converging on that vision and a 5-day TestFlight sprint.

The new master prompt provided in this session describes a **biofeedback-first multimedia suite** (EchoelTools / Sync / Works / Well, MPE+Air controllers, OSC bus, evidence-based wellness). It is a different product shape.

**Both can be reconciled** — the Beat MVP can sit inside `EchoelTools` as one of several bio-reactive generators, and the StudioRoot tabs can be reframed as the four-suite navigation — but this is a **product-direction decision the owner needs to make explicit** before any code lands. The Ralph Wiggum loop should not start picking fixes that pull the codebase in opposite directions at once.

Recommended owner deliverable (not done in this audit): pick one of:

- **(A) Continue v10 Beat-MVP** to TestFlight first, then layer the bio-first suite vision on top as v1.1+.
- **(B) Pivot now** to the bio-first suite vision; rescope TestFlight to a thinner slice that shows the bio-pipeline + one tool + OSC out + MPE in.
- **(C) Hybrid** — keep BeatTab functional, but begin building `EngineBus` + bio bus + OSC out underneath it so the v10 ship doubles as the suite's foundation.

The phrasing of the new master prompt strongly suggests **(B) or (C)**; the existing repo state has invested heavily in **(A)**. Worth a 5-minute conversation before the next commit.

---

## 5 · Compliance & TestFlight readiness snapshot (vs §8 of master prompt)

| Item | Status |
|------|--------|
| Built with Xcode 26 / iOS 26 SDK | ⚠️ `testflight.yml` pins Xcode 26.2, but `Project.swift` deployment target is iOS 17. New vision wants iOS 18. |
| Version bump discipline | OK — convention in place. |
| No deprecated APIs / warnings-as-errors | `Package.swift` enables `-warnings-as-errors`. Spot-checks needed once iOS 18 SDK delta lands. |
| HealthKit + App Group + Bluetooth + Network entitlements | ✅ Present. App Group name to be reconciled with master prompt. |
| Audio-thread safety (no malloc/lock/GCD in render) | Strong on paper; spot-audit needed on `SamplerVoice` render closure (recent fix dropped `@MainActor`). |
| Lock-free bio↔audio handoff | ⚠️ `SPSCQueue` exists in `Core/`; not yet used for bio→audio routing because there is no `EngineBus`. |
| `AVAudioSession` config | Lives inside `AudioEngine`; verify `.playback` + `.mixWithOthers` per master prompt. |
| Privacy manifest complete | ⚠️ Present, needs once-over against final iOS 18 Required-Reason list. |
| Cloud AI consent | N/A today; gate when adding. |
| Smoke test on real device | Pending current Phase 3 cycles (last device-verified commit unclear). |
| Science-only copy in store metadata + onboarding | ⚠️ Recent onboarding rewrite (`3a3e983`) and decisions log show ongoing scrub of legacy soundscape/binaural-beat copy. Needs a final read-through pass against `fastlane/metadata/`. |

---

## 6 · Risk register

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | Two product visions diverging in same branch | **High** | Owner picks A/B/C before next code commit. |
| R2 | Protected DSP layer claimed but absent | **High** | Decide implement vs. retract; align tests + docs. |
| R3 | `skip_tests=true` in TestFlight workflow masks bio-integration test breakage | Med | Re-enable tests once R2 is resolved. |
| R4 | iOS 17 deployment target vs iOS 18 master-prompt target | Med | Mechanical change; coordinate with SDK bump cycle. |
| R5 | Legacy modules (`SoundscapeEngine`, `ClipEngine`, OuraRingClient, Views/*) still compilable on main flow | Low | Tag for removal post-TestFlight, do not delete in this audit. |
| R6 | 17 GitHub workflows, several legacy (android, phase8000, release-all-platforms) | Low | Archive in a later cleanup commit. |
| R7 | App-Group identifier mismatch (`group.com.echoelmusic.shared` vs `group.com.echoelmusic`) | Low | Pick one consistently across entitlements + extensions. |
| R8 | Privacy / Info.plist strings may still contain legacy framings | Low | Single-commit copy audit, science-only. |

---

## 7 · Recommended next cycle (Plan-Mode item)

Per Ralph Wiggum Lambda: one fix per cycle. Highest-leverage first cycle, regardless of A/B/C choice above, is **R2** because it unblocks tests and corrects fabricated documentation:

- **Option 2a (cheap, ~1 commit):** Delete `testHilbertSensorMapper_*` tests from `Tests/EchoelmusicTests/BioIntegrationTests.swift`, remove "Protected DSP" claims from `CLAUDE.md` until the modules actually exist, log decision to `memory/decisions.md` + `decisions.csv`.
- **Option 2b (deliberate, ~3-5 commits):** Implement `HilbertSensorMapper` (recursive Hilbert curve, ~30 LOC, pure value-type, testable), then `BioEventGraph`, then `BioSignalDeconvolver`, each as a separate atomic commit with passing tests. Promotes them to the protected layer the master prompt describes.

Both are **non-disruptive to BeatTab** and progress the foundation toward the master-prompt vision without picking A/B/C yet.

This audit document does not pick. The owner picks. Then Plan-Mode opens, then one fix commits.

---

## 8 · Files touched by this audit

- **Written:** `scratchpads/AUDIT_FOUNDATION_2026-05-18.md` (this file).
- **Modified:** none.
- **Source files:** none.

---

*End of Phase 1 audit. Awaiting owner direction on:*
1. *Product vision A / B / C (§4).*
2. *Protected DSP path Option 2a / 2b (§3, §7).*
3. *iOS 18 deployment target bump scheduling (§5, R4).*
