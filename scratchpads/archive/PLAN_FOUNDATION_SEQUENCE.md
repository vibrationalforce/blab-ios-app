# Echoelmusic — Foundation Sequence (Phase 2 → Phase 3)

**Date:** 2026-05-18
**Branch:** `claude/echoelmusic-audit-testflight-x0MN0` (was `claude/audit-echoelmusic-foundation-Q9OYQ`)
**Predecessor:** `scratchpads/AUDIT_FOUNDATION_2026-05-18.md` (Phase 1)
**Authority:** Owner direction 2026-05-18 — "Alles für die Zukunft vorbereiten iOS 27. iPhone First. Ouraring bereits vorhanden zum Testen."

> One cycle per row. Each cycle = one atomic commit on this branch.
> Owner approves each cycle in Plan-Mode before code lands.
> No batching, no parallelism, no skipping rows.

---

## Direction signals from owner

| Signal | Reading |
|--------|---------|
| "iOS 27 vorbereiten" | iOS 27 SDK is not yet released (today: 2026-05-18). Floor today = iOS 18, Xcode 26. Code patterns adopted now must survive the iOS 27 jump (Swift 6 strict, `@Observable`, no deprecated APIs). |
| "iPhone First" | Drop macOS / watchOS / tvOS / visionOS from `Package.swift` platforms. iPhone is the only shippable target for v10. Other-platform code stays compilable behind `#if canImport(...)` for free, but is not a deliverable. |
| "Oura already testable" | Real Oura device available for validation. `OuraRingClient.swift` is already in `Sources/Echoelmusic/Bio/`. It gets wired into `EngineBus` once the bus exists. Oura becomes the first real-hardware bio source in the loop, not HealthKit. |
| (implicit) Product direction | Owner has not picked A/B/C from the audit. The plan below is **A→C transitional**: protects the v10 Beat-MVP path (existing BeatTab keeps working) while building the bio-first foundation (EngineBus, OSC, MPE) underneath. This is the lowest-regret order. |

---

## Cycle sequence

### Floor (foundation-only, no behavior change)

| # | Cycle | Files touched | Risk | Owner gate |
|---|-------|---------------|------|------------|
| F1 | **Deployment-target bump + iPhone-only platforms.** `Package.swift` → `platforms: [.iOS(.v18)]` only. `Project.swift` → `IPHONEOS_DEPLOYMENT_TARGET = 18.0`. No source changes. Verifies build still green under the new floor. | `Package.swift`, `Project.swift` | Low — mechanical | Approve before push |
| F2 | **Privacy + entitlements pass.** Reconcile App Group identifier (`group.com.echoelmusic.shared` ↔ `group.com.echoelmusic`), re-validate `PrivacyInfo.xcprivacy` Required-Reason API list under iOS 18, scrub Info.plist usage strings for any leftover soundscape/binaural-beat framing. No source changes. | `Echoelmusic.entitlements`, `Resources/PrivacyInfo.xcprivacy`, `Info.plist` | Low | Approve before push |

### Phase 2 — Skelett (per master prompt Anhang A)

| # | Cycle | Files touched | Risk | Owner gate |
|---|-------|---------------|------|------------|
| S1 | **`EngineBus` skeleton.** New `Sources/Echoelmusic/Core/EngineBus.swift`. Defines the typed pub/sub bus, `BioEvent`, `BioSampleFrame`, `ControllerEvent` value types, and the `EngineBus` `actor` (or `@MainActor`-isolated class — to be decided in plan-mode). Lock-free `SPSCQueue` (already in repo) used for audio-thread paths. Not yet wired into `EchoelmusicApp`. Dormant + tested. | new file + new tests | Low — dormant | Approve before push |
| S2 | **Wire `EngineBus` into `EchoelmusicApp`.** Single environment injection. No subscribers yet. BeatTab continues to work unchanged. | `EchoelmusicApp.swift`, `StudioRoot.swift` | Low | Approve before push |
| S3 | **Oura → `EngineBus`.** `OuraRingClient` publishes `BioSampleFrame` (HR, HRV, breath) onto the bus. Validated against real Oura ring (owner's device). | `Sources/Echoelmusic/Bio/OuraRingClient.swift`, new `OuraBioPublisher` adapter, tests | Med — real hardware | Device-verify before next |
| P0 | **NEW: Polar H10 BLE direct.** `Sources/Echoelmusic/Bio/PolarH10BioPublisher.swift`. CoreBluetooth direct, no Kubios. Publishes `BioSampleFrame` with `source = .ble` at decimated rate. Polar H10 is HRV ground-truth (Sensors 2026 validation, Pearson r > 0.99 vs ECG) — pairs with S3 to cross-check Oura HRV. Per `STRATEGY_2026-05-18.md`. | new file + new tests | Med — BLE hardware | Device-verify before next |
| S4 | **HealthKit → `EngineBus`.** `HealthKitBioPublisher` polls `EchoelBioEngine.snapshot` and publishes `BioSampleFrame` with `source = .healthKit`. **DONE — `9d8e99b`.** | `EchoelBioEngine.swift`, new `HealthKitBioPublisher` | Low | Approve before push |
| S5 | **CoreMIDI MPE input layer.** Extend `MIDIInput.swift` to detect MPE zones (RPN 6,6), split per-note channels, and publish `ControllerEvent` (note + per-note CC74/pressure/pitchbend) onto `EngineBus`. Tested with canned MIDI byte streams. | `MIDIInput.swift`, new tests | Med | Approve before push |
| S6 | **First `EchoelTools` tool.** Minimal `Sources/Echoelmusic/Tools/HRVPadTool.swift` — subscribes to `BioSampleFrame.hrvNormalized` on the bus, modulates one parameter (filter cutoff) of an existing `EchoelDDSP` voice. Lives in a new `Studio/ToolsTab.swift` (the "Beat" tab name stays for now). | new dir `Tools/`, new tab | Med | Device-verify before next |

### Phase 3 — Vision-Reflect

| # | Cycle | Files touched | Risk |
|---|-------|---------------|------|
| V1 | **OSC output layer.** `Sources/Echoelmusic/Sync/OSCSender.swift` — UDP socket, `/echoelmusic/bio/*` and `/echoelmusic/audio/*` paths per master prompt §2. Subscribes to bus, sends. Configurable host:port. Verified end-to-end against TouchDesigner/Resolume. | new `Sync/` dir | Med |
| V2 | **Air-CC receiver.** Network MIDI session listener; CC 21–31 → `ControllerEvent.air(dimension:value:)` on bus. Off by default, opt-in via Settings. | `Sync/`, `MIDIInput.swift` | Med |
| V3 | **Modulation Matrix v0.** Persistable mapping table (Codable JSON): {source bus topic} × {scale, curve, smooth} → {destination parameter}. Minimal UI. | new `Modulation/` dir | High |
| V4 | ~~**Two more EchoelTools.** One uses breath-phase (Hilbert phase output), one uses motion-energy.~~ **SUPERSEDED by EchoelLoop module** (Loopy-Pro-style canvas + bio-modulated widgets, scheduled Q2 2027 per `STRATEGY_2026-05-18.md`). | post-V3 future cycle | High |

### Protected DSP triad — interleaved with Vision-Reflect

Owner direction 2026-05-18: **Option 2b confirmed (implement).** Interleaving rather than block-at-end, so each P-cycle unlocks the V-cycle that needs it:

| # | Cycle | Sits between | Files touched | Risk |
|---|-------|--------------|---------------|------|
| P1 | **`HilbertSensorMapper.swift`.** Pure value type, vDSP-based Hilbert transform, audio-thread-safe. Satisfies `SKILL.md` contract. Unlocks the dead test in `BioIntegrationTests.swift:579-601`. | After S6, before V1 — so V1's OSC out can publish instantaneous phase, not just BPM. | new `Bio/HilbertSensorMapper.swift` | High |
| P2 | **`BioSignalDeconvolver.swift`.** Detrend + notch + separate + validity flag per SKILL.md. Wired between sensors and `HilbertSensorMapper`. Cleans Oura HR/PPG before phase analysis. | After V1, before V2 — so by the time Air-CC arrives, the bio side already delivers clean phased signals. | new `Bio/BioSignalDeconvolver.swift` | High |
| P3 | **`BioEventGraph.swift`.** Event detectors consume cleaned + phase-marked samples; emit `BioEvent` on bus. | After V2, before V3 — Modulation Matrix gains discrete triggers (heartbeat, breath onset, coherence-shift) alongside continuous values. | new `Bio/BioEventGraph.swift` | High |

> P-cycles each require an explicit "APPROVED: modify [Component]" before the file ships, per the SKILL.md status block. After landing, those files become read-only.

### Ship rail (revised — P-cycles interleaved)

| # | Cycle | Goal |
|---|-------|------|
| Z1 | TestFlight build with F1..S6 landed | Bio-aware tab on device, Oura-verified, no protected DSP yet |
| Z2 | TestFlight build with P1 + V1 landed | OSC out carrying live Hilbert phase, dead test rehabilitated |
| Z3 | TestFlight build with P2 + V2 landed | Clean Oura signal, Air-CC in, validity-flag honored downstream |
| Z4 | TestFlight build with P3 + V3 + V4 landed | Discrete `BioEvent`s on bus, Modulation Matrix UI, two further tools |

Each Z is preceded by `swift build` + `swift test` green, real-device smoke test against the §8 checklist in master prompt, and copy review against the science-only line in master prompt §0.

---

## Owner decisions on record (2026-05-18)

1. **Protected DSP path:** Option 2b — implement. Interleaved with V-cycles per the table above.
2. **App-Group identifier:** `group.com.echoelmusic` (Master-Prompt form). F2 enforces.
3. **F1 authority:** Delegated to Claude ("Du entscheidest. Zukunftsträchtiges Management"). F1 executes immediately after this plan update commits.

## Decisions still owed (deferred to their own cycle)

- **`EngineBus` isolation model.** Actor vs `@MainActor` class vs hybrid (control plane on main, data plane on dedicated audio thread). Decided in S1 plan-mode.

---

## Files touched by this plan

- Written: `scratchpads/PLAN_FOUNDATION_SEQUENCE.md` (this file).
- Modified: none.
- Source files: none.

---

*This plan is a sequencing contract. It does not commit any code change.
Each row above requires its own plan-mode approval before its commit lands.
Cycle F1 is the next ask once owner confirms the sequence is acceptable.*
