# PLAN — Per-Track FX (Module 2 of the comprehensive interface)

> ⛔ **SCOPE NOTE (audit 2026-09-02): this plan predates the product definition of 2026-07-25**
> (`docs/dev/PRODUCT_DEFINITION.md`, Editor ≠ Workstation). Where it names timeline / clips /
> arrangement / multitrack / lanes-as-tracks / AUv3 / broadcast / drums / piano-roll surfaces, those
> are CUT and that part is history — do not execute it. Nothing below was edited; check the
> definition before building from any line here.


Founder 2026-07-11 ("Alles"): after the Mixer (Module 1), give each track its own FX,
bio-modulatable — the step toward the one bio-modulated timeline that unifies the 8 tools.

## The-Council verdict (applied inline)
- **Architect:** the roles don't yet live on separate buses. Physically separable TODAY:
  `bass` (SubBassVoice) · `melodic` (poly synth = lead+harmony together) · `drums`
  (BeatPlayer). The lead/pad split is its own audio-graph refactor — do NOT block per-bus
  FX on it.
- **DSP Purist:** `ChannelInsertFX` is already audio-thread-safe, zero-alloc, and `.off`
  is an EXACT passthrough. Install one insert per bus, `process` in the render loop, skip
  when passthrough. No new render-path allocation.
- **Shipper:** don't stack a THIRD unheard audio change on the still-unconfirmed warmth
  (v162). Ship the tested SPINE now (no audio change); gate the audible wiring behind a
  device pass, sequenced AFTER warmth is ear-confirmed.
- **Skeptic (premortem):** the failure mode is a blind render-path change I can't hear
  regressing the instrument. Mitigation: default every bus `.off` (bit-identical), wire
  behind `isPassthrough` skips, audio-thread-review each path, founder verifies on device.
- **Gate:** proceed with the spine (reversible, tested); HOLD audible wiring for the
  device pass + warmth confirmation.

## Cycles
1. **✅ SPINE (this cycle):** `TrackFX` (Codable settings) + `TrackFXStore`
   (@Observable, persisted, per-bus, default `.off`) + `insert(for:sampleRate:)` builder
   (nil when passthrough) + tests. NO audio-graph change, NO app wiring. Bit-identical.
2. **Audible wiring (next, device pass):** hold one `ChannelInsertFX` per bus in the
   render owner; install from `TrackFXStore.insert(for:)` on the control thread; `process`
   in each bus's render loop, skipping passthrough. Paths: `SubBassVoice` (bass),
   `PolySynthVoice`/`EchoelPolyDDSP` stereo out (melodic), `BeatPlayer`/drum mix (drums).
   audio-thread-review each. Founder verifies sound on device.
3. **Minimal UI:** a per-bus FX row (filter type · cutoff · resonance · drive) using
   `EchoelValueField` only, in the Mix panel next to the faders. Adaptive + Uncodixfy.
4. **Bio-modulation routing:** expose "assign a bio source to this insert's cutoff/drive"
   via the existing `ModulationMatrix` (`ModSource` → `ModRoute` → param) — the
   "FX durch Biofeedback beeinflusst" moment. Draw a curve OR route the pulse: same dest.
5. **Lead/pad bus split (later refactor):** separate the poly synth's lead vs harmony
   voices onto two buses so the shrill lead can be filtered independently. Unblocks true
   4-track FX (bass·pad·lead·drums) matching the 4 Mixer faders.

## Invariants
- `.off` bus = exact passthrough (guarded by `TrackFXStoreTests`).
- No parameter UI without `EchoelValueField` (CLAUDE.md law).
- Every render-path wiring gets an audio-thread-reviewer pass before commit.
- Nothing audible ships without a founder device confirmation (sandbox can't hear audio).
