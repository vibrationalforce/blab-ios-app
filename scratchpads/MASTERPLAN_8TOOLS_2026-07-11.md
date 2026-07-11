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
| **Lighting** | EchoelLux Art-Net + sACN unicast, flash-safe (≤3 Hz WCAG) | LIVE |
| **Visuals** | MetalBioView (HR→pulse, coherence→hue, breath→spread) + FloatingVisualWindow + VJ overlay | LIVE |
| **I/O** | OSCSender (`/echoelmusic/bio/*`) · ADMOSCSender (`/adm/obj/*`) · CoreMIDI MPE in/out | LIVE |
| **MIDI export** | exportMIDI() + ShareSheet | LIVE |
| Learn / theory | MusicTheoryPrimer · LearnLibrary · tap-to-learn BioMetricInfo | LIVE |

### 🟡 BUILT but UNWIRED / UNPRESENTED — exists, needs assembly (the real frontier)
| Thing | Code exists | Gap |
|---|---|---|
| **Per-track FX** (Module 2) | TrackFXStore + ChannelInsertFX (this session) | audio wiring + UI + bio-mod routing |
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

- [ ] **Q1. Wire or delete the rotting cores.** BioModulation (0 consumers) → wire its
      `BoundParameter`/`ClockSource` as the spine under the modulation matrix, with tests; or
      remove if truly superseded. Same decision for CloudSync (0 consumers). Verifiable: unit
      tests + compile.
- [ ] **Q2. Modulation-matrix model completeness.** Ensure every `ModSource` (incl. bio) can
      route to a typed destination with a pure `output(for:frame:)`; add depth/curve; tests.
      No UI yet. Pure + CI.
- [ ] **Q3. Per-track FX audio wiring** (behind `TrackFX.isPassthrough` = bit-identical).
      Install one `ChannelInsertFX` per bus (bass/melodic/drums) from `TrackFXStore`, process
      in each render loop, skip passthrough. audio-thread-review each. `NEEDS-FOUNDER-VERIFY`
      (sound), but off-by-default so it cannot regress.
- [ ] **Q4. Per-track FX UI** — a per-bus row (filter·cutoff·reso·drive) in the Mix panel using
      `EchoelValueField` only. Adaptive + Uncodixfy. Compiles + design-safe. `NEEDS-FOUNDER-VERIFY`.
- [ ] **Q5. Bio-tempo lane (model).** A pure tempo-map: musical-time master + optional bio-tempo
      source, tests. (The BPM-both decision, already logged.) Pure + CI.
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
