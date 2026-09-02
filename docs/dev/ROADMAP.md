# Echoel — Execution Roadmap (canonical for SEQUENCE — subordinate to the product definition)

> ⛔ **SUBORDINATE to `docs/dev/PRODUCT_DEFINITION.md` (2026-07-25).** That file decides WHAT Echoel is
> (a bio-reactive instrument; the workstation half is CUT; ship gate = the five checks of
> "Instrument-Complete v1" in `CLAUDE.md`). This file only orders HOW the kept scope gets built.
> Where a backlog item below names CUT scope (timeline, clips, multitrack, AUv3, broadcast), the
> definition wins and the item is history. The rule two paragraphs down ("this file + vision.md
> win") was written 2026-06-19, before the definition existed, and is bounded by it (audit 2026-09-02).

> **This is the single source of truth for *how we get there*.**
> The *vision* (north star, tiers, principles) lives in [`memory/vision.md`](../../memory/vision.md)
> and is not duplicated here. This doc indexes everything else, subordinates the
> scattered plans under one structure, and gives one pragmatic backlog.
>
> Rule: if a scattered `scratchpads/PLAN_*` or `STRATEGY_*` disagrees with this
> file or `vision.md`, **this file + vision.md win**. Plans are inputs, not truth.

_Last structured: 2026-06-19. Re-confirm at each session start alongside `memory/`._

---

## 0. Operating rhythm (the only gate)

- **Ralph Wiggum Lambda:** one change per cycle, no batching → build → test → ship → loop.
- **Definition of Done:** `swift build`/`swift test` **CI-green** → on the feature branch →
  TestFlight → **verified on device**. Green CI ≠ works on device (honesty rule).
- **One paradigm:** every surface is a pillar off the same bio bus + one `EchoelStudioView`.
  Add dimensions as controls on the one instrument — **never new tabs** (anti-pattern: breadth-first oscillation).
- **Guardrails:** open standards / near-zero deps · science-only copy · audio-thread sanctity ·
  accessibility-first · protected DSP triad read-only.

---

## 1. The five dimensions — reality status (anchor)

Body → Sound → Space → Light → Vibration, with **Data** (OSC · MIDI 1.0/2.0 · **MPE out**) as the spine. The direction word is not decoration: MPE **out** ships, MPE **in** does not (#548/#770).
Full LIVE/ROADMAP/NORTH-STAR detail in [`vision.md`](../../memory/vision.md) and
[`FEATURE_MATRIX.md`](FEATURE_MATRIX.md). One-line status:

| Dimension | Status | Where |
|---|---|---|
| **Body** (controller) | LIVE | HealthKit + BLE 0x180D + camera rPPG + Demo → 10 Hz bus |
| **Sound** | LIVE | DDSP, FX chain, presets+community, LUFS/MIDI export (⛔ "modal/cellular" stood in this Live row — both have zero production instantiators, #796/FEATURE_MATRIX) |
| **Light** | LIVE | native Art-Net + sACN (zero-dep UDP) |
| **Space** | LIVE | ADM-OSC object out `/adm/obj/{n}/*` |
| **Vibration** | LIVE | sub-bass/LFE voice + Core Haptics infra |
| **Data spine** | LIVE | OSC, MIDI 1.0/2.0 note **in**, **MPE out** (#713), RTP-MIDI, Widgets (AUv3 target deleted — #121 Slice 1). ⛔ **MPE _in_ is NOT live** and was claimed here as such — #548/#770: no zone disambiguation, no Channel Pressure case, and the three per-note dimensions reach a `break` in the voice. |

---

## 2. Status snapshot — shipped this cycle (2026-06-19, branch `claude/piano-roll-clip-view-wozlie`)

**Sound dimension hardened end-to-end** (all CI-green):
- FX: attack-knack fix · every parameter exposed (incl. Saturation/Harmonizer/Reverb).
- Presets: save/recall your own · 16 curated · search by name+tag · favorites + recents (on-device ranking).
- **Community loop:** in-app "Submit" → GitHub issue → `community-triage` Action validates JSON & opens a PR to `community/curated/`.
- **Sound/patch parity:** same community + favorites/recents on `SynthPatch`.
- Apple integration: [`APPLE_INTEGRATION_NOTES.md`](../../APPLE_INTEGRATION_NOTES.md) + [repo audit](../../scratchpads/APPLE_INTEGRATION_AUDIT_2026-06-19.md).

---

## 3. The backlog — Now / Next / Later (pragmatic, single list)

Each item: **[dimension]** description → *plan doc if any*. Pick from **Now** first.

### NOW (this + next few cycles — verifiable, low risk, on-vision)
1. **[Sound]** Push a **TestFlight build** so the founder hears the whole preset/FX/community package on device. *(DoD step; do before adding more.)*
2. ✅ **[Sound]** ~~In-app community loader~~ — DONE 2026-06-19: `CommunityLibrary` loads
   `Resources/Community/{fx,patches}/*.json` via `Bundle.module`, merged into the FX library
   (appended) + a "Community" section in the Sound editor. Best-effort (empty on failure → no
   regression). **CI-verified** via `CommunityLibraryTests` (a seeded `Aurora Drift` proves the
   bundling, so a resource-flatten fails in CI, not silently on device). Triage now writes here.
3. ✅ **[Sound]** ~~Wire the orphaned `SampleBrowserView`~~ — DONE 2026-06-19: reachable via
   Tools → **Drum Samples** (per-track). Device files now **preview-before-assign** (audition
   with ▶, then "Use"). *(Note: no manual drum-pad grid exists in the single view; samples are
   the drum-kit sounds used by generative playback. A pad grid is a separate, larger feature.)*
4. ✅ **[Body/Apple]** ~~HealthKit write~~ — DONE 2026-06-19 (v10.34.8): Tools → "Save to Apple
   Health" (off by default) writes the HR + respiratory rate Echoel measures (camera rPPG / BLE)
   as `HKQuantitySample`s. Non-circular (only self-measured sources), trustworthy units only (no
   fabricated HRV), throttled/range-guarded; pure unit-tested `HealthWritePolicy` + HealthKit-guarded
   `HealthKitWriter`. Uses the existing entitlement + `NSHealthUpdateUsageDescription` (string corrected).

> **NOW is cleared** (2026-06-19): all four NOW items shipped to TestFlight (v10.34.1–v10.34.8).
> Everything remaining below is **NEXT/LATER** and genuinely gated — each needs a new
> Info.plist key/entitlement, a larger DSP build (voice analyzer), and/or **device-in-the-loop**
> tuning, so they are deliberate cycles, not blind ships.

### NEXT (authorized direction, needs a deliberate cycle)
5. **[Body/Apple]** **AccessorySetupKit** pairing flow for BLE sensors (privacy + featuring), additive next to Core Bluetooth. → audit §6.
6. **[Body]** **Head-tracking** (`CMHeadphoneMotionManager`) as a new bio/modulation source on the one instrument — AirPods as sensor. → audit §5.
7. **[Sound/flagship]** **Audiovisual Vocoder** wiring (`VocoderCore`/`FeedbackGuard`/`BioModulation` cores exist). → *PLAN_CREATIVE_EXPANSION, vision Tier-2*.
   - **Note (2026-06-19 audit):** these 4 cores are *unifying refactors of already-working, sensitive
     paths* (synth bio→timbre; MetalBioView tone→light colour), not clean additions — so they need
     **device-in-the-loop** cycles, not blind wiring. `BioVisualParams` is now **partially wired**
     (heartbeat pulse / WCAG flash-safety via FlashGuard; v10.34.6). `VocoderCore` also needs a voice
     analyzer (mic pitch/energy/brightness) which was removed in the soundscape refactor.
8. **[Sound]** Replicate the preset/community pattern to **Mood** + **Sound & texture** surfaces.
   - ✅ **Mood** — DONE 2026-06-19 (v10.34.4): `MoodPreset`/`MoodPresetStore` mirror `PatchStore`
     (15 curated factory moods as of 2026-07-29 — `git grep -c 'MoodPreset(id: Self.uid'
     Sources/Echoelmusic/Sequencer/MoodPreset.swift`; it said 8 for six weeks after the set
     grew, so cite the command, not the number — favorites/recents, App-Group JSON, community loop with seeded
     `Aurora Calm` + triage). Mood panel has the full preset bar. CI-verified (`MoodPresetTests`).
   - ✅ **Sound & texture** — DONE, and this line was stale (for how long is not checkable in a
     shallow clone, so no duration is claimed): `soundPanel`'s `presetRow`
     already loads `patchStore.sortedPatches` (favorites first) plus `CommunityLibrary.patches`,
     and offers favourite / save / save-as / delete / submit. The "deep `PatchEditorView`" it was
     told to match is DELETED (#132 Slice 6, 2026-07-31) — it was a doorless duplicate, and the
     panel it was benchmarked against had already overtaken it. `SoundPanelPresetBarTests` now
     pins all six capabilities, so this cannot silently regress to the ⬜ state again.

### LATER (roadmap — gate before building; don't claim until shipping)
9. **[Space/Light]** Multi-device installation sync (multicast/AirPlay + a shared clock; today OSC is single-target, no PTP). → audit §11–12.
10. ~~**[Broadcast]** Live RTMP/SRT~~ — CUT, see the answered gate at the line "~~Live Broadcast~~" below (2026-07-25/07-31); the spec sits founder-gated in `BROADCAST_HAISHINKIT_FINISH.md`. (⛔ this row kept "resolve via vision-gate" alive past the verdict and pointed at `PLAN_W3_STREAM`, which lives only in `scratchpads/archive/`; audit 2026-09-02.)
11. **[Sound]** Higher-order ambisonics / in-app PHASE for headphone spatial preview (ADM-OSC stays the pro path). → audit §1,3.
12. **[Platforms]** visionOS / macOS surfaces; keep Metal shaders portable. → *PLAN_WWDC26_ADOPTION*.
13. **[Sound/AI]** CoreML / RAVE neural latent layer — gated on an on-device latency prototype.

---

## 4. Scattered-plan index (subordinated, not deleted)

Grouped by theme so nothing is lost. **Status legend:** 🟢 active input · 🟡 partial/needs gate · ⚪ superseded/parked.

- **Vision/Strategy:** `STRATEGY_STATE_OF_THE_ART_2026-06-06` 🟢 · `STRATEGY_USP_2026-06-12` 🟢 · `PLAN_MULTIDIMENSIONAL_2026-06-17` 🟢 · `STRATEGY_TOOLS_REDUCTION_2026-06-12` 🟢 · `STRATEGY_2026-05-18` ⚪
- **Sound/Synthesis:** `PLAN_SYNTHESIS_EXPANSION` 🟢 · `PLAN_CREATIVE_EXPANSION_2026-06-17` 🟢 · `PLAN_FLEXIBLE_NATURAL_ENGINE` 🟡 · `PLAN_BIO_GENERATIVE_2026-06-12` 🟢
- **Ecosystem/Community:** `PLAN_ECOSYSTEM_LOOP` 🟢 (now partly shipped: triage) · `PLAN_CLOUDKIT_SYNC` 🟡 · `PLAN_MULTIPLATFORM_LINKING` 🟡
- **DAW/Record/Video/Stream (superseded by one-instrument):** `PLAN_DAW_BUILDOUT` ⚪ · `PLAN_W2_RECORDER` ⚪ · `PLAN_W2_VIDEO` ⚪ · `PLAN_W3_STREAM` 🟡 (gate) · `PLAN_ARRANGEMENT_VIDEO_ONE_VIEW` 🟡
- **Foundation/Build/Signing:** `PLAN_FOUNDATION_INDEX` 🟢 · `PLAN_FOUNDATION_SEQUENCE` 🟢 · `PLAN_V11_CONSOLIDATION` 🟢 · `PLAN_MULTITARGET_SIGNING` 🟢 · `PLAN_v10_TestFlight_Sprint` ⚪
- **Apple adoption:** `PLAN_WWDC26_ADOPTION` 🟡 · `PLAN_COMPETITIVE_ROADMAP_2026-06-16` 🟢

> Cleanup convention: when a ⚪ plan's last idea is captured here or shipped, it may be
> deleted in a `chore:` cycle. Don't let the count grow past this index without re-rolling it up.

---

## 5. Honesty ledger (review every session — from `vision.md` §gaps + Apple audit)

- ~~Live Broadcast~~ — the gate ANSWERED (⛔ this line kept the oscillation alive past the verdict): CUT by Editor ≠ Workstation (2026-07-25) and struck from the identity line 2026-07-31. WATCH tier; re-entry needs a founder ask.
- ✅ ~~CLAUDE.md "v10 Target" diagram drift~~ — RECONCILED 2026-06-19: relabeled as superseded
  + honest banner, "Studio sections" table now reflects the as-built single `EchoelStudioView`.
- **Bus `bioFrames`/`bioEvents`** reserved but undrained (snapshot path is the live one).
- **No device-to-device clock sync**; OSC is single-target (item #9).
- **⚠️ CI verification gap (structural):** `ci.yml` uses `swift build` (SPM), which does NOT
  catch Xcode/Tuist-only build errors — `Bundle.module`, resource bundling, `Project.swift`
  issues only surface in the TestFlight (XcodeGen) build. This bit v10.34.0 (Bundle.module).
  **Rule:** SPM-only APIs MUST be `#if SWIFT_PACKAGE`-guarded (see BeatPlayer/CommunityLibrary).
  **MITIGATED 2026-06-19:** added `.github/workflows/xcode-compile-check.yml` (macos, xcodegen +
  `xcodebuild build`, no-sign) on every code push — it caught the AUv3 `FXCharacter` error in ~30s.
  **Standing rule:** keep `Sources/Echoelmusic/DSP/` self-contained — no `Core/`/`Sequencer/` types
  in `DSP/` files. (The original reason was that the AUv3 target compiled `DSP/` in isolation; that
  target is gone since #121, but the rule stays: it is what keeps the DSP layer portable.) And
  guard SPM-only APIs with `#if SWIFT_PACKAGE`.
- **Community loader on-device verification pending** — `CommunityLibraryTests` proves the SPM
  bundling in CI, but the Xcode/TestFlight bundle path should be confirmed once on device.

---

## 6. Review cadence

- **Session start:** read `memory/` + this file + `SESSION_LOG.md`.
- **Decisions:** log to `memory/decisions.md` + `decisions.csv`; default review +30 days (`./review.sh`).
- **This roadmap:** re-roll the backlog whenever Now empties or the brand promise and shipping
  reality drift more than one cycle apart.
