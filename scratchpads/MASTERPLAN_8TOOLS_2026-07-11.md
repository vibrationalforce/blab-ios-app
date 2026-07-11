# MASTERPLAN — The 8 Tools in ONE bio-modulated interface (2026-07-11)

Founder ask: realize the whole vision (8 pro-tool domains + design) at the highest level,
seamless. Build **safely + constantly** (founder away for hours, cannot test) to close every
known gap. This is the single ordered build queue + the honest ground-truth matrix.

Ground truth verified against the code on 2026-07-11 (not memory). If the website or an old
note disagrees, **the code wins** (see `docs/dev/FEATURE_MATRIX.md`).

---

## PART 1 — THE HONEST MATRIX (what is REAL / OUTSTANDING / NOT-YET)

### ✅ REAL — ships today, verified in code
| Domain | Code | State |
|---|---|---|
| Bio-generative **instrument** (HOME) | EchoelDDSP/PolyDDSP · BioComposer · SynthPatch/PatchStore · analog warmth · tempo-adaptive Spielart | LIVE |
| **Beat maker** | PatternEngine · BeatPlayer · DrumSynthVoice · per-pad sample import · swing/accent | LIVE |
| **Bio** (heart) | HealthKit + universal BLE HRS + camera rPPG (locks on device) + HRVCoherence (Lomb-Scargle/Welch) | LIVE |
| **Mixer** (Module 1) | MixerStore — Bass·Pad·Lead·Drums faders, persisted | LIVE |
| **Per-track FX** (Module 2) | TrackFXStore + ChannelInsertFX — Bass·Melodic·Drums filter+drive, off by default | LIVE (needs founder ear) |
| **Lighting** | EchoelLux Art-Net + sACN unicast, flash-safe (≤3 Hz WCAG) | LIVE |
| **Visuals** | MetalBioView (HR→pulse, coherence→hue, breath→spread) + FloatingVisualWindow + VJ overlay | LIVE |
| **I/O** | OSCSender (`/echoelmusic/bio/*`) · ADMOSCSender (`/adm/obj/*`) · CoreMIDI MPE in/out | LIVE |
| **MIDI export** | exportMIDI() + ShareSheet | LIVE |
| Learn / theory | MusicTheoryPrimer · LearnLibrary · tap-to-learn BioMetricInfo | LIVE |

### 🟡 BUILT but UNWIRED / UNPRESENTED — exists, needs assembly (the real frontier)
| Thing | Code exists | Gap |
|---|---|---|
| **Per-track FX bio-mod routing** | TrackFXStore + ModulationMatrix | audio + UI DONE; bio→FX-param routing is the Q7 bind-a-knob UI (founder-eye) |
| **Clips / Arrangement / Timeline** | ClipView · ArrangementView · ArrangeTimelineView · AutomationView · ClipStore · ArrangementStore · AutomationLane · LaunchQuantizer | not reachable from the shell (surfaces exist, nav removed) |
| **Comprehensive interface** | SurfaceHost + WorkspaceSurface enum (arrange·clips·compose·mix) + SurfaceSwitcherBar | scaffolding present, bottom bar removed for render-safety — needs a render-SAFE re-assembly |
| **Modulation matrix** (bio→ANY param) | ModulationMatrix (ModSource→ModRoute) + consumers (FXBioModulator·FXModulation·VisualModulation·ModulationEngine) | no unified "assign bio to this knob" UI |
| **BioModulation** spine | Core/BioModulation.swift (BoundParameter + ClockSource) | **0 consumers** — wire or remove before it rots |
| **VocoderCore** | Studio/VocoderCore.swift (voice→sound+visual+light) | 1 consumer, not in the flow |
| **CloudSync** | Core/CloudSync.swift | **0 consumers** — wire or remove |
| **Channel rack / Patchbay** | ChannelRackView · PatchbayView | unpresented |

### 🔴 NOT-YET — genuinely needs deps / device / big work (do NOT claim)
| Domain | Why blocked | Path |
|---|---|---|
| **Video capture/trim/export** | VideoRecorder (AVAssetWriter) scaffold EXISTS but not wired to a live capture→encode→trim→export flow; needs device camera + founder testing | after audio spine proves out |
| **RTMP / live broadcast** | BroadcastPublisher is a `#if canImport(HaishinKit)` scaffold; HaishinKit NOT linked (dependency decision needed) | v1.2 (logged) |
| **Multitrack audio recording** | no wired recorder graph | roadmap |
| **Video mapping / projection** | no code | far roadmap |
| Anything needing the **founder's ear/eye** to confirm | sandbox cannot hear audio or see the UI render | queue → founder verifies |

---

## PART 2 — THE AUTONOMOUS BUILD QUEUE (safe, CI-verifiable, ordered)

**Rule:** each item is ONE Ralph cycle — build → tests → both CI gates green → commit → next.
Only items that are **verifiable without the founder's senses** ship as "done". Anything whose
final quality needs his ear/eye is built behind a SAFE default (off/passthrough/bit-identical),
gate-verified, and flagged `NEEDS-FOUNDER-VERIFY` — never claimed as finished-good.

- [x] **Q1. De-duplicate the modulation spine.** DONE 2026-07-11: `BioModSource` was a second,
      parallel bio-source enum → retired. `BoundParameter` re-based onto the canonical
      `ModSource` (nil = manual); `ClockSource` kept (the BPM-both master clock); added
      `ModSource.displayName` for the Q7 UI. Tests updated. 0 app consumers → 0 regression risk.
      NOTE for Q5: a THIRD clock concept `TransportClockSource` exists in Transport.swift — reconcile
      with `ClockSource` when building the bio-tempo lane. CloudSync (0 consumers) still pending.
- [x] **Q2. Modulation-matrix model completeness.** DONE 2026-07-11: the routing model was
      already complete + well-tested (`ModRoute` carries depth · curve · invert · trust-gate ·
      smoothing; `ModulationMatrix.evaluate` sums per destination; 37 tests). Added
      `BoundParameter: Codable` (+ round-trip tests) so the Q7 bind-a-knob bindings persist.
      **CloudSync reclassified:** NOT rot — it is a deliberate, unit-tested "Phase 0" CloudKit
      foundation (`scratchpads/PLAN_CLOUDKIT_SYNC.md`) awaiting the founder registering an iCloud
      container + entitlement (Phase 1). `DEFERRED to founder`, do NOT delete.
- [x] **Q3. Per-track FX audio wiring** (behind `TrackFX.isPassthrough` = bit-identical).
      DONE 2026-07-11 — all three buses: **bass** (`SubBassVoice` per-bus `ChannelInsertFX` fed
      by a lock-free `SPSCQueue<TrackFX>`/`setInsert`, per-sample only when active) · **melodic**
      (`PolySynthVoice` OWN stereo insert, two `ChannelInsertFX` with independent L/R state, AFTER
      the genre `fxChain`) · **drums** (turned out `BeatPlayer` ALREADY had per-CHANNEL insert FX —
      `ChannelFX` + `configureInsertFX` on each SamplerVoice/DrumSynthVoice, atomic-mirror handoff;
      no new audio code needed, just fan one insert across all 8 channels). off = bit-identical.
      audio-thread-reviewer: CLEAN on every bus. `NEEDS-FOUNDER-VERIFY` (sound).
- [x] **Q4. Per-track FX UI** — DONE 2026-07-11: `TrackFXStore` wired into the app
      (`.environment`); Mix panel now carries **Bass · Melodic · Drums** filter+drive
      `EchoelValueField` rows. Each binding persists (`trackFX.set`) AND pushes to audio live
      (bass→`subBass.setInsert`; melodic→`synth`+`leadSynth` so the shrill lead is covered;
      drums→fan `beatPlayer.setFX` across all 8 channels — a low-pass this way == a true bus
      filter since the biquad is LTI). Persisted settings re-applied on `.onAppear`; Reset clears
      all three. ui-state-reviewer: CLEAN (env intact, low-freq reads = render-safe, no `.sheet`
      growth). `.off` rests full-open so a field reads "no filtering". `NEEDS-FOUNDER-VERIFY`
      (sound + feel); buses stay `.off` until a control moves → cannot regress. **Module 2 COMPLETE.**
- [x] **Q5. Bio-tempo lane (model).** DONE 2026-07-11: `BioTempoDirector` (Core/) — pure,
      Codable, deterministic. `TempoMode.locked` (default, ignores the body) vs `.bioFollow`
      (transport tempo GLIDES toward the heartbeat, pulled toward the 72-BPM resonance band by
      coherence). One-pole glide so the beat never lurches; clamped to the musical band;
      NaN-safe. 9 tests. NOT wired to `Transport.tempo` yet → zero risk; the live wiring is a
      later DEVICE-PASS cycle. Clarified: `TransportClockSource` (internal/midi/link = sync
      topology) and `TempoMode` (locked/bioFollow = tempo value) are ORTHOGONAL, not duplicates.
- [ ] **Q6. Comprehensive interface — render-SAFE re-assembly.** Bring back arrange·clips·mix as
      reachable surfaces via SurfaceHost WITHOUT growing EchoelStudioView's `.sheet` chain and
      WITHOUT any 10 Hz `@Observable` read in an ancestor body (swiftui-render-safety skill).
      Compiles + render-safety-audited. `NEEDS-FOUNDER-VERIFY` (feel).
- [ ] **Q7. Modulation-matrix UI** — "assign a bio source (or draw a curve) to THIS parameter"
      via the one `EchoelValueField`. The multidimensional moment. `NEEDS-FOUNDER-VERIFY`.
- [ ] **Q8. Doc + test hygiene.** Keep FEATURE_MATRIX + this plan in sync each cycle; raise
      coverage on the new spines; delete dead scaffolding flagged for removal.

**Deferred to a founder/device session (NOT autonomous):** video capture flow (Q-video),
RTMP/HaishinKit dependency decision (Q-broadcast), any final sound/UI taste calls.

---

## PART 3 — GUARDRAILS (never violated, even under autonomy)
- **Never regress the launching instrument.** Render-safety laws: no growth of the
  EchoelStudioView `.sheet`/`.fullScreenCover` chain; no 10 Hz `@Observable` read in any
  ancestor of a menu host; live bio reads confined to leaf views (swiftui-render-safety).
- **Audio-thread rules** on every render-path change; audio-thread-reviewer before commit.
- **Protected Rausch triad** (BioEventGraph · HilbertSensorMapper · BioSignalDeconvolver) READ-ONLY.
- **CI is the ground truth** — Quick Test + Xcode Compile Check green before every deploy; no
  blind sensory change claimed as done.
- **Safe defaults** — new audio/UI paths ship off/passthrough/bit-identical until the founder verifies.
- **One change per cycle.** No batching unrelated work. Max blast radius per commit stays small.
- **EchoelValueField** for every parameter UI. Uncodixfy (no glassmorphism/neon, ≤12px radii, ≤3 Hz flash). Adaptive across iPhone/iPad/Mac/Vision.
- **Brand purity** — never wellness/esoteric/overclaim in user-facing copy.
- **No new deps, targets, or top-level dirs** without an explicit founder ask.
